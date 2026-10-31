# ==============================================================================
# test_offseason_ingestion.R
# Unit Tests for Offseason Ingestion Subsystem & Health Gate (Phase 2 / Issue #119)
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# Source ingestion code
source(file.path("tools", "offseason", "ingest_sources.R"))

test_dir <- tempfile("test_ingest_archive_")
dir.create(test_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

test_that("ingest_sources.R exports expected public interface functions", {
  expect_true(exists("poll_league_wire"))
  expect_true(exists("poll_team_releases"))
  expect_true(exists("poll_beat_feeds"))
  expect_true(exists("compute_composite_health"))
  expect_true(exists("can_assert_quiet_week"))
  expect_true(exists("check_publication_gate"))
  expect_true(exists("run_ingestion"))
  expect_true(exists("snapshot_raw_response"))
})

test_that("snapshot_raw_response saves text and raw content to archive", {
  txt_file <- snapshot_raw_response("sample payload", "league_wire", "test1", "txt", archive_dir = test_dir)
  expect_true(file.exists(txt_file))
  expect_equal(readLines(txt_file), "sample payload")
  
  raw_payload <- charToRaw("binary payload")
  bin_file <- snapshot_raw_response(raw_payload, "team_releases", "test2", "bin", archive_dir = test_dir)
  expect_true(file.exists(bin_file))
  expect_equal(readBin(bin_file, "raw", n = 100), raw_payload)
})

test_that("dry-run produces healthy adapters across all three feeds", {
  manifest_tmp <- file.path(test_dir, "test_manifest.json")
  manifest <- run_ingestion(
    dry_run = TRUE,
    allow_degraded = FALSE,
    output_manifest = manifest_tmp,
    archive_dir = test_dir
  )
  
  expect_equal(manifest$composite_health, "HEALTHY")
  expect_equal(manifest$adapters$league_wire$status, "HEALTHY")
  expect_equal(manifest$adapters$league_wire$http_code, 200)
  expect_equal(manifest$adapters$team_releases$status, "HEALTHY")
  expect_equal(manifest$adapters$team_releases$feeds_polled, 15)
  expect_equal(manifest$adapters$team_releases$feeds_succeeded, 15)
  expect_equal(manifest$adapters$beat_feeds$status, "HEALTHY")
  expect_equal(manifest$adapters$beat_feeds$sources_polled, 6)
  expect_equal(manifest$adapters$beat_feeds$sources_succeeded, 6)
  
  expect_true(file.exists(manifest_tmp))
  parsed <- jsonlite::fromJSON(manifest_tmp)
  expect_equal(parsed$composite_health, "HEALTHY")
  expect_equal(parsed$adapters$league_wire$status, "HEALTHY")
})

test_that("composite health computation follows strict hierarchy", {
  healthy <- list(status = "HEALTHY")
  degraded <- list(status = "DEGRADED")
  failed <- list(status = "FAILED")
  
  # All healthy -> HEALTHY
  expect_equal(compute_composite_health(healthy, healthy, healthy), "HEALTHY")
  
  # Wire healthy, secondary degraded -> DEGRADED
  expect_equal(compute_composite_health(healthy, degraded, healthy), "DEGRADED")
  expect_equal(compute_composite_health(healthy, healthy, degraded), "DEGRADED")
  
  # Wire failed -> FAILED
  expect_equal(compute_composite_health(failed, healthy, healthy), "FAILED")
  
  # Both secondary failed -> FAILED
  expect_equal(compute_composite_health(healthy, failed, failed), "FAILED")
})

test_that("quiet-week precondition enforces composite_health == HEALTHY", {
  expect_true(can_assert_quiet_week(list(composite_health = "HEALTHY")))
  expect_false(can_assert_quiet_week(list(composite_health = "DEGRADED")))
  expect_false(can_assert_quiet_week(list(composite_health = "FAILED")))
})

test_that("publication gate blocks when league wire is FAILED unless --allow-degraded is set", {
  manifest_wire_failed <- list(
    composite_health = "FAILED",
    adapters = list(
      league_wire = list(status = "FAILED", http_code = 500),
      team_releases = list(status = "HEALTHY"),
      beat_feeds = list(status = "HEALTHY")
    )
  )
  
  # Without --allow-degraded -> blocked
  gate_blocked <- check_publication_gate(manifest_wire_failed, allow_degraded = FALSE)
  expect_false(gate_blocked$allowed)
  expect_true(grepl("Publication blocked", gate_blocked$reason))
  
  # With --allow-degraded -> allowed, advisory, promotion_frozen = TRUE
  gate_override <- check_publication_gate(manifest_wire_failed, allow_degraded = TRUE)
  expect_true(gate_override$allowed)
  expect_true(gate_override$advisory)
  expect_true(gate_override$promotion_frozen)
  expect_true(grepl("baseline promotion PROHIBITED", gate_override$reason))
})

test_that("secondary degradation does not block publication but sets advisory flag", {
  manifest_secondary_degraded <- list(
    composite_health = "DEGRADED",
    adapters = list(
      league_wire = list(status = "HEALTHY", http_code = 200),
      team_releases = list(status = "DEGRADED"),
      beat_feeds = list(status = "HEALTHY")
    )
  )
  
  gate_eval <- check_publication_gate(manifest_secondary_degraded, allow_degraded = FALSE)
  expect_true(gate_eval$allowed)
  expect_true(gate_eval$advisory)
  expect_false(gate_eval$promotion_frozen)
})

message("All unit tests passed successfully!")
