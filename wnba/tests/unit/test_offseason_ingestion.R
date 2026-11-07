# ==============================================================================
# test_offseason_ingestion.R
# Unit Tests for Offseason Ingestion Subsystem & Health Gate (Phase 2 / Issue #161)
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
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# Source schema and ingestion code
source(file.path("tools", "offseason", "wire_items_schema.R"))
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
  expect_true(exists("parse_league_wire_payload"))
})

test_that("snapshot_raw_response saves text and raw content to archive", {
  txt_file <- snapshot_raw_response("sample payload", "league_wire", "test1", "txt", archive_dir = test_dir)
  expect_true(file.exists(txt_file))
  expect_equal(readLines(txt_file), "sample payload")
  
  raw_payload <- charToRaw("binary payload")
  bin_file <- snapshot_raw_response(raw_payload, "league_wire", "test2", "bin", archive_dir = test_dir)
  expect_true(file.exists(bin_file))
  expect_equal(readBin(bin_file, "raw", n = 100), raw_payload)
})

# ------------------------------------------------------------------------------
# Criterion 1: run_ingestion() returns manifest and validated wire items
# ------------------------------------------------------------------------------
test_that("run_ingestion() returns both manifest and validated wire items", {
  manifest_tmp <- file.path(test_dir, "test_manifest_c1.json")
  res <- run_ingestion(
    dry_run = TRUE,
    allow_degraded = FALSE,
    output_manifest = manifest_tmp,
    archive_dir = test_dir
  )
  
  expect_true(is.list(res))
  expect_true("manifest" %in% names(res))
  expect_true("items" %in% names(res))
  
  # Validate manifest structure
  manifest <- res$manifest
  expect_equal(manifest$composite_health, "HEALTHY")
  expect_equal(manifest$adapters$league_wire$status, "HEALTHY")
  expect_equal(manifest$adapters$team_releases$status, "RETIRED")
  expect_equal(manifest$adapters$beat_feeds$status, "HEALTHY")
  
  # Validate wire items conforming to tools/offseason/wire_items_schema.R
  expect_true(is.list(res$items))
  expect_true(length(res$items) > 0)
  
  val <- validate_wire_items(res$items, detailed = TRUE)
  expect_true(val$valid)
  expect_equal(length(val$errors), 0)
  
  # Check written normalized wire items file in archive_dir
  norm_path <- file.path(test_dir, "wire_items_normalized.json")
  expect_true(file.exists(norm_path))
  norm_items <- read_wire_items(norm_path, validate = TRUE)
  expect_equal(length(norm_items), length(res$items))
})

# ------------------------------------------------------------------------------
# Criterion 2: league_wire record counting (25 rows, parse failure handling)
# ------------------------------------------------------------------------------
test_that("league_wire record counting reflects transaction row count and reports parse failure", {
  # 1. Test parsing official 2026-11-06 payload
  fixture_path <- file.path("cache", "raw_ingest_archive", "20261106", "league_wire_espn_114245.json")
  expect_true(file.exists(fixture_path))
  
  payload_raw <- readBin(fixture_path, "raw", file.info(fixture_path)$size)
  parsed_res <- parse_league_wire_payload(payload_raw, observed_at = "2026-11-06T11:42:45Z")
  
  expect_true(parsed_res$valid)
  # Transactions row count must be 25 (not data frame column count length = 3)
  expect_equal(parsed_res$items_found, 25L)
  expect_equal(parsed_res$page_count, 5L)
  expect_equal(length(parsed_res$items), 25L)
  expect_true(validate_wire_items(parsed_res$items))
  
  # Check first transaction attributes
  first_item <- parsed_res$items[[1]]
  expect_equal(first_item$source_family, "league_wire")
  expect_equal(first_item$source_id, "espn")
  expect_equal(first_item$team_abbr, "IND")
  expect_equal(first_item$event_date, "2026-10-23T07:00Z")
  expect_match(first_item$raw_text, "Kelly Krauskopf")
  
  # 2. Test parse error reporting: invalid JSON must fail closed (never items + 1)
  bad_parsed <- parse_league_wire_payload("NOT_JSON_<<<CORRUPT>>>")
  expect_false(bad_parsed$valid)
  expect_equal(bad_parsed$items_found, 0L)
  expect_equal(length(bad_parsed$items), 0L)
  expect_false(is.null(bad_parsed$error))
  
  # 3. Test poll_league_wire with mock fetcher returning corrupt JSON
  mock_fetch_corrupt <- function(url) {
    list(status_code = 200, content = charToRaw("{\"corrupt_json: true"))
  }
  wire_err <- poll_league_wire(
    dry_run = FALSE,
    archive_dir = test_dir,
    fetch_fn = mock_fetch_corrupt
  )
  expect_equal(wire_err$status, "FAILED")
  expect_equal(wire_err$items_found, 0L)
  expect_equal(length(wire_err$items), 0L)
})

# ------------------------------------------------------------------------------
# Criterion 3: Pagination loop across all pages up to pageCount
# ------------------------------------------------------------------------------
test_that("poll_league_wire paginates across all pages up to pageCount", {
  requested_urls <- character(0)
  
  # Mock fetcher supporting 3 pages
  mock_paginated_fetch <- function(url) {
    requested_urls <<- c(requested_urls, url)
    page_num <- 1L
    if (grepl("page=2", url)) page_num <- 2L
    if (grepl("page=3", url)) page_num <- 3L
    
    page_payload <- list(
      status = "success",
      count = 6L,
      pageIndex = page_num,
      pageSize = 2L,
      pageCount = 3L,
      transactions = list(
        list(
          date = sprintf("2026-10-%02d", 20L + page_num * 2L),
          description = sprintf("Transaction %d on page %d", page_num * 2L - 1L, page_num),
          team = list(abbreviation = "MIN", links = list(href = "https://example.com/min"))
        ),
        list(
          date = sprintf("2026-10-%02d", 20L + page_num * 2L + 1L),
          description = sprintf("Transaction %d on page %d", page_num * 2L, page_num),
          team = list(abbreviation = "SEA", links = list(href = "https://example.com/sea"))
        )
      )
    )
    
    list(
      status_code = 200,
      content = charToRaw(jsonlite::toJSON(page_payload, auto_unbox = TRUE))
    )
  }
  
  wire_res <- poll_league_wire(
    dry_run = FALSE,
    archive_dir = test_dir,
    fetch_fn = mock_paginated_fetch,
    base_url = "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/transactions"
  )
  
  expect_equal(wire_res$status, "HEALTHY")
  # 3 pages * 2 transactions = 6 items
  expect_equal(wire_res$items_found, 6L)
  expect_equal(length(wire_res$items), 6L)
  expect_true(validate_wire_items(wire_res$items))
  
  # Confirm all 3 pages were requested
  expect_equal(length(requested_urls), 3L)
  expect_true(any(grepl("transactions$", requested_urls) | grepl("page=1", requested_urls)))
  expect_true(any(grepl("page=2", requested_urls)))
  expect_true(any(grepl("page=3", requested_urls)))
})

# ------------------------------------------------------------------------------
# Criterion 4: Dry-run quarantine and purge of team_releases_*.txt
# ------------------------------------------------------------------------------
test_that("dry-run snapshots are quarantined from production archive and team_releases_*.txt are purged", {
  # 1. Confirm contaminated team_releases_*.txt are purged from cache/raw_ingest_archive/
  archive_sim_files <- list.files(
    file.path("cache", "raw_ingest_archive"),
    pattern = "^team_releases_.*\\.txt$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_equal(length(archive_sim_files), 0L)
  
  # 2. Confirm dry-run without explicit archive_dir writes to cache/dry_run_archive/ NOT raw_ingest_archive
  temp_manifest <- tempfile("dry_run_manifest_", fileext = ".json")
  today_str <- format(Sys.time(), "%Y%m%d")
  
  # Clean potential previous test dry_run dir for clean measurement
  dry_run_today_dir <- file.path("cache", "dry_run_archive", today_str)
  if (dir.exists(dry_run_today_dir)) {
    unlink(dry_run_today_dir, recursive = TRUE)
  }
  
  res <- run_ingestion(
    dry_run = TRUE,
    output_manifest = temp_manifest
    # archive_dir deliberately left NULL to test default quarantine
  )
  on.exit({
    if (file.exists(temp_manifest)) unlink(temp_manifest)
    if (dir.exists(dry_run_today_dir)) unlink(dry_run_today_dir, recursive = TRUE)
  }, add = TRUE)
  
  # Confirm files were written to dry_run_archive
  expect_true(dir.exists(dry_run_today_dir))
  dry_files <- list.files(dry_run_today_dir)
  expect_true(length(dry_files) > 0)
  
  # Confirm NO new team_releases_*.txt were written to raw_ingest_archive
  archive_sim_files_after <- list.files(
    file.path("cache", "raw_ingest_archive"),
    pattern = "^team_releases_.*\\.txt$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_equal(length(archive_sim_files_after), 0L)
})

# ------------------------------------------------------------------------------
# Criterion 5: team_releases retirement & DEFAULT_BEAT_SOURCES update
# ------------------------------------------------------------------------------
test_that("team_releases adapter is retired and DEFAULT_BEAT_SOURCES updated per #160 spike", {
  # 1. Adapter call returns RETIRED with 0 polled feeds
  releases_res <- poll_team_releases(dry_run = FALSE)
  expect_equal(releases_res$status, "RETIRED")
  expect_equal(releases_res$feeds_polled, 0L)
  expect_equal(releases_res$feeds_succeeded, 0L)
  expect_equal(releases_res$items_found, 0L)
  expect_true(isTRUE(releases_res$retired))
  
  # 2. Composite health is HEALTHY even when team_releases is retired / failed
  healthy <- list(status = "HEALTHY")
  retired <- list(status = "RETIRED")
  failed <- list(status = "FAILED")
  degraded <- list(status = "DEGRADED")
  
  # 3-arg call with retired / failed releases adapter does not block composite health
  expect_equal(compute_composite_health(healthy, retired, healthy), "HEALTHY")
  expect_equal(compute_composite_health(healthy, failed, healthy), "HEALTHY")
  
  # 2-arg call (wire, beat) works directly
  expect_equal(compute_composite_health(healthy, healthy), "HEALTHY")
  expect_equal(compute_composite_health(healthy, degraded), "DEGRADED")
  expect_equal(compute_composite_health(failed, healthy), "FAILED")
  
  # 3. Beat sources includes just_womens_sports and excludes athletic_wnba
  beat_ids <- sapply(DEFAULT_BEAT_SOURCES, function(x) x$id)
  expect_true("just_womens_sports" %in% beat_ids)
  expect_false("athletic_wnba" %in% beat_ids)
  
  jws_entry <- DEFAULT_BEAT_SOURCES[[which(beat_ids == "just_womens_sports")]]
  expect_equal(jws_entry$url, "https://justwomenssports.com/feed/")
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
      team_releases = list(status = "RETIRED"),
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
      team_releases = list(status = "RETIRED"),
      beat_feeds = list(status = "DEGRADED")
    )
  )
  
  gate_eval <- check_publication_gate(manifest_secondary_degraded, allow_degraded = FALSE)
  expect_true(gate_eval$allowed)
  expect_true(gate_eval$advisory)
  expect_false(gate_eval$promotion_frozen)
})

message("All offseason ingestion unit tests passed successfully!")
