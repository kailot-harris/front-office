# ==============================================================================
# test_ingest_freshness.R
# Unit Tests for Ingestion Freshness, Volume Gate, and Earned-Zero (Issue #163)
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

# Ensure user library is accessible even when running inside an isolated renv sandbox
user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")), "R", "win-library", "4.5")
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) {
    .libPaths(c(.libPaths(), default_user_lib))
  }
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# Source module under test
source(file.path("tools", "offseason", "ingest_freshness.R"))

test_dir <- tempfile("test_freshness_")
dir.create(test_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

# Reference timestamp for deterministic tests: 2026-11-07T12:00:00Z
FIXED_NOW <- parse_iso_timestamp("2026-11-07T12:00:00Z")

# Helper to construct a base mock manifest
make_manifest <- function(timestamp = "2026-11-07T10:00:00Z",
                          composite_health = "HEALTHY",
                          wire_status = "HEALTHY",
                          wire_items = 5L,
                          releases_status = "HEALTHY",
                          releases_items = 4L,
                          beat_status = "HEALTHY",
                          beat_claims = 6L) {
  list(
    ingest_timestamp = timestamp,
    composite_health = composite_health,
    adapters = list(
      league_wire = list(
        status = wire_status,
        http_code = 200L,
        items_found = wire_items,
        bytes_captured = 1024L
      ),
      team_releases = list(
        status = releases_status,
        feeds_polled = 15L,
        feeds_succeeded = 15L,
        items_found = releases_items
      ),
      beat_feeds = list(
        status = beat_status,
        sources_polled = 6L,
        sources_succeeded = 6L,
        claims_found = beat_claims
      )
    )
  )
}

# ------------------------------------------------------------------------------
# Criterion 1: Export Interface Verification
# ------------------------------------------------------------------------------
test_that("ingest_freshness.R exports all four required public functions", {
  expect_true(exists("check_ingest_freshness", mode = "function"))
  expect_true(exists("check_ingest_volume", mode = "function"))
  expect_true(exists("can_assert_quiet_week", mode = "function"))
  expect_true(exists("evaluate_ingestion_gate", mode = "function"))
})

# ------------------------------------------------------------------------------
# Criterion 2: Freshness Evaluation
# ------------------------------------------------------------------------------
test_that("freshness check blocks on missing or empty ingest_timestamp", {
  # Absent field
  m_absent <- list(composite_health = "HEALTHY", adapters = list())
  res_absent <- check_ingest_freshness(m_absent, now = FIXED_NOW)
  expect_false(res_absent$fresh)
  expect_false(res_absent$allowed)
  expect_true(grepl("absent", res_absent$reason, ignore.case = TRUE))

  # NULL timestamp
  m_null <- list(ingest_timestamp = NULL, composite_health = "HEALTHY")
  res_null <- check_ingest_freshness(m_null, now = FIXED_NOW)
  expect_false(res_null$fresh)
  expect_false(res_null$allowed)

  # Empty string timestamp
  m_empty <- list(ingest_timestamp = "   ", composite_health = "HEALTHY")
  res_empty <- check_ingest_freshness(m_empty, now = FIXED_NOW)
  expect_false(res_empty$fresh)
  expect_false(res_empty$allowed)

  # NA timestamp
  m_na <- list(ingest_timestamp = NA_character_, composite_health = "HEALTHY")
  res_na <- check_ingest_freshness(m_na, now = FIXED_NOW)
  expect_false(res_na$fresh)
  expect_false(res_na$allowed)
})

test_that("freshness check blocks on unparseable ingest_timestamp", {
  unparseable_values <- c(
    "not-a-timestamp",
    "2026-99-99T99:99:99Z",
    "yesterday afternoon",
    "undefined",
    "12345-invalid"
  )

  for (bad_ts in unparseable_values) {
    m_bad <- make_manifest(timestamp = bad_ts)
    res_bad <- check_ingest_freshness(m_bad, now = FIXED_NOW)
    expect_false(res_bad$fresh, info = paste("Should fail on:", bad_ts))
    expect_false(res_bad$allowed, info = paste("Should not be allowed on:", bad_ts))
    expect_true(grepl("unparseable", res_bad$reason, ignore.case = TRUE))
  }
})

test_that("freshness check blocks on stale timestamps past max_age_hours", {
  # Default is 168 hours (7 days)
  # Exactly 169 hours old -> stale
  ts_stale_169h <- strftime(FIXED_NOW - (169 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  m_stale <- make_manifest(timestamp = ts_stale_169h)
  res_stale <- check_ingest_freshness(m_stale, max_age_hours = 168, now = FIXED_NOW)
  expect_false(res_stale$fresh)
  expect_false(res_stale$allowed)
  expect_true(res_stale$age_hours > 168)
  expect_true(grepl("stale", res_stale$reason, ignore.case = TRUE))

  # 30 days old (720 hours) -> stale
  ts_30d <- strftime(FIXED_NOW - (30 * 24 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res_30d <- check_ingest_freshness(make_manifest(timestamp = ts_30d), now = FIXED_NOW)
  expect_false(res_30d$fresh)
  expect_true(res_30d$age_hours > 700)

  # Custom max_age_hours (e.g. 24 hours): 25h old should fail
  ts_25h <- strftime(FIXED_NOW - (25 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res_25h <- check_ingest_freshness(make_manifest(timestamp = ts_25h), max_age_hours = 24, now = FIXED_NOW)
  expect_false(res_25h$fresh)
})

test_that("freshness check succeeds on fresh timestamps", {
  # 2 hours old
  ts_2h <- strftime(FIXED_NOW - (2 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res_2h <- check_ingest_freshness(make_manifest(timestamp = ts_2h), now = FIXED_NOW)
  expect_true(res_2h$fresh)
  expect_true(res_2h$allowed)
  expect_equal(round(res_2h$age_hours, 1), 2.0)

  # 167 hours old (< 168h default)
  ts_167h <- strftime(FIXED_NOW - (167 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res_167h <- check_ingest_freshness(make_manifest(timestamp = ts_167h), now = FIXED_NOW)
  expect_true(res_167h$fresh)
  expect_true(res_167h$allowed)

  # Fractional seconds ISO: 2026-11-07T11:00:00.500Z (1 hour old)
  res_frac <- check_ingest_freshness(make_manifest(timestamp = "2026-11-07T11:00:00.500Z"), now = FIXED_NOW)
  expect_true(res_frac$fresh)

  # ISO with offset: 2026-11-07T07:00:00-05:00 (equivalent to 12:00:00 UTC, 0h age)
  res_offset <- check_ingest_freshness(make_manifest(timestamp = "2026-11-07T07:00:00-05:00"), now = FIXED_NOW)
  expect_true(res_offset$fresh)
  expect_true(abs(res_offset$age_hours) < 0.05)
})

test_that("freshness check blocks on timestamps significantly in the future", {
  # 5 hours in future -> clock drift anomaly
  ts_future <- strftime(FIXED_NOW + (5 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res_future <- check_ingest_freshness(make_manifest(timestamp = ts_future), now = FIXED_NOW)
  expect_false(res_future$fresh)
  expect_false(res_future$allowed)
  expect_true(grepl("future", res_future$reason, ignore.case = TRUE))
})

# ------------------------------------------------------------------------------
# Criterion 3: Volume Check & Status Verification
# ------------------------------------------------------------------------------
test_that("volume check blocks when composite health is HEALTHY but total items count is zero", {
  # HEALTHY with 0 items across adapters
  m_zero_healthy <- make_manifest(
    composite_health = "HEALTHY",
    wire_items = 0L,
    releases_items = 0L,
    beat_claims = 0L
  )
  vol_res <- check_ingest_volume(m_zero_healthy)
  expect_false(vol_res$valid)
  expect_false(vol_res$allowed)
  expect_equal(vol_res$total_items, 0L)
  expect_true(grepl("Zero-volume gate blocked", vol_res$reason))
})

test_that("volume check blocks when composite health is DEGRADED but total items count is zero", {
  # DEGRADED with 0 items
  m_zero_degraded <- make_manifest(
    composite_health = "DEGRADED",
    wire_items = 0L,
    releases_items = 0L,
    beat_claims = 0L
  )
  vol_res <- check_ingest_volume(m_zero_degraded)
  expect_false(vol_res$valid)
  expect_false(vol_res$allowed)
  expect_equal(vol_res$total_items, 0L)
  expect_true(grepl("Zero-volume gate blocked", vol_res$reason))
})

test_that("volume check succeeds when total items count is non-zero", {
  # HEALTHY with items
  m_healthy <- make_manifest(
    composite_health = "HEALTHY",
    wire_items = 2L,
    releases_items = 3L,
    beat_claims = 5L
  )
  vol_healthy <- check_ingest_volume(m_healthy)
  expect_true(vol_healthy$valid)
  expect_true(vol_healthy$allowed)
  expect_equal(vol_healthy$total_items, 10L)

  # DEGRADED with items (e.g., releases failed with 0 items, but wire has 4 and beat has 2)
  m_degraded <- make_manifest(
    composite_health = "DEGRADED",
    wire_items = 4L,
    releases_items = 0L,
    beat_claims = 2L
  )
  vol_degraded <- check_ingest_volume(m_degraded)
  expect_true(vol_degraded$valid)
  expect_true(vol_degraded$allowed)
  expect_equal(vol_degraded$total_items, 6L)
})

test_that("volume check extracts items from explicit top-level fields", {
  m_top_items <- list(
    ingest_timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    total_items = 12L
  )
  vol_res <- check_ingest_volume(m_top_items)
  expect_true(vol_res$valid)
  expect_equal(vol_res$total_items, 12L)

  m_items_df <- list(
    ingest_timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    items = data.frame(id = 1:7)
  )
  vol_df <- check_ingest_volume(m_items_df)
  expect_true(vol_df$valid)
  expect_equal(vol_df$total_items, 7L)
})

test_that("volume check strictly verifies status enum and never defaults to HEALTHY", {
  invalid_statuses <- c("OK", "UNKNOWN", "healthy", "PASS", "WARN", "", NA)
  for (bad_st in invalid_statuses) {
    m_bad_st <- list(
      ingest_timestamp = "2026-11-07T10:00:00Z",
      composite_health = bad_st,
      total_items = 10L
    )
    vol_res <- check_ingest_volume(m_bad_st)
    expect_false(vol_res$valid, info = paste("Should reject status:", bad_st))
    expect_false(vol_res$allowed)
    expect_true(grepl("Status verification failed", vol_res$reason))
  }
})

# ------------------------------------------------------------------------------
# Criterion 4: Earned-Zero Predicate (can_assert_quiet_week)
# ------------------------------------------------------------------------------
test_that("can_assert_quiet_week returns TRUE when ingest is fresh, healthy, volume non-zero, and zero changes", {
  m_valid_healthy <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 5L,
    releases_items = 3L,
    beat_claims = 4L
  )

  # Scalar 0
  expect_true(can_assert_quiet_week(m_valid_healthy, confirmed_changes = 0, now = FIXED_NOW))
  # 0L integer
  expect_true(can_assert_quiet_week(m_valid_healthy, confirmed_changes = 0L, now = FIXED_NOW))
  # Empty list()
  expect_true(can_assert_quiet_week(m_valid_healthy, confirmed_changes = list(), now = FIXED_NOW))
  # Empty data.frame()
  expect_true(can_assert_quiet_week(m_valid_healthy, confirmed_changes = data.frame(), now = FIXED_NOW))
  # NULL defaults to 0
  expect_true(can_assert_quiet_week(m_valid_healthy, confirmed_changes = NULL, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns TRUE when composite_health is DEGRADED with non-zero volume and zero changes", {
  m_valid_degraded <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "DEGRADED",
    wire_items = 6L,
    releases_items = 0L,
    beat_claims = 2L
  )

  expect_true(can_assert_quiet_week(m_valid_degraded, confirmed_changes = 0, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE when confirmed_changes > 0", {
  m_healthy <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 5L
  )

  # 1 confirmed change (integer)
  expect_false(can_assert_quiet_week(m_healthy, confirmed_changes = 1, now = FIXED_NOW))
  expect_false(can_assert_quiet_week(m_healthy, confirmed_changes = 5L, now = FIXED_NOW))

  # List with 1 item
  changes_list <- list(list(entity = "Sabrina Ionescu", change = "contract_extension"))
  expect_false(can_assert_quiet_week(m_healthy, confirmed_changes = changes_list, now = FIXED_NOW))

  # Dataframe with 1 row
  changes_df <- data.frame(entity = "Sabrina Ionescu", change = "contract_extension")
  expect_false(can_assert_quiet_week(m_healthy, confirmed_changes = changes_df, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE when ingest volume is zero (unearned zero)", {
  m_zero_vol <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 0L,
    releases_items = 0L,
    beat_claims = 0L
  )

  # Even though changes count is 0, zero volume means quiet week cannot be asserted
  expect_false(can_assert_quiet_week(m_zero_vol, confirmed_changes = 0, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE when timestamp is stale", {
  ts_stale <- strftime(FIXED_NOW - (200 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  m_stale <- make_manifest(
    timestamp = ts_stale,
    composite_health = "HEALTHY",
    wire_items = 10L
  )

  expect_false(can_assert_quiet_week(m_stale, confirmed_changes = 0, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE when timestamp is missing or unparseable", {
  m_no_ts <- make_manifest(
    timestamp = NULL,
    composite_health = "HEALTHY",
    wire_items = 10L
  )
  expect_false(can_assert_quiet_week(m_no_ts, confirmed_changes = 0, now = FIXED_NOW))

  m_bad_ts <- make_manifest(
    timestamp = "gibberish",
    composite_health = "HEALTHY",
    wire_items = 10L
  )
  expect_false(can_assert_quiet_week(m_bad_ts, confirmed_changes = 0, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE when composite_health is FAILED", {
  m_failed <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "FAILED",
    wire_items = 10L
  )

  expect_false(can_assert_quiet_week(m_failed, confirmed_changes = 0, now = FIXED_NOW))
})

test_that("can_assert_quiet_week returns FALSE on invalid status enum", {
  m_bad_status <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "CORRUPT_STATUS",
    wire_items = 10L
  )

  expect_false(can_assert_quiet_week(m_bad_status, confirmed_changes = 0, now = FIXED_NOW))
})

# ------------------------------------------------------------------------------
# Criterion 1 & Gate Orchestrator: evaluate_ingestion_gate
# ------------------------------------------------------------------------------
test_that("evaluate_ingestion_gate allows publication for fresh, healthy manifest with non-zero volume", {
  m_good <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 5L,
    releases_items = 3L,
    beat_claims = 4L
  )

  gate_res <- evaluate_ingestion_gate(m_good, allow_degraded = FALSE, now = FIXED_NOW)
  expect_true(gate_res$allowed)
  expect_false(gate_res$advisory)
  expect_false(gate_res$promotion_frozen)
  expect_true(grepl("Publication allowed", gate_res$reason))
})

test_that("evaluate_ingestion_gate allows DEGRADED manifest with advisory flag when volume and freshness pass", {
  m_deg <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "DEGRADED",
    wire_items = 5L,
    releases_items = 0L,
    beat_claims = 2L
  )

  gate_res <- evaluate_ingestion_gate(m_deg, allow_degraded = FALSE, now = FIXED_NOW)
  expect_true(gate_res$allowed)
  expect_true(gate_res$advisory)
  expect_false(gate_res$promotion_frozen)
  expect_true(grepl("advisory", gate_res$reason, ignore.case = TRUE))
})

test_that("evaluate_ingestion_gate blocks when timestamp is stale", {
  ts_stale <- strftime(FIXED_NOW - (175 * 3600), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  m_stale <- make_manifest(
    timestamp = ts_stale,
    composite_health = "HEALTHY",
    wire_items = 5L
  )

  # Even with allow_degraded = TRUE, stale manifest must be blocked
  gate_res <- evaluate_ingestion_gate(m_stale, allow_degraded = TRUE, now = FIXED_NOW)
  expect_false(gate_res$allowed)
  expect_true(gate_res$promotion_frozen)
  expect_true(grepl("stale", gate_res$reason, ignore.case = TRUE))
})

test_that("evaluate_ingestion_gate blocks when ingest_timestamp is missing or unparseable", {
  m_missing_ts <- make_manifest(
    timestamp = NULL,
    composite_health = "HEALTHY",
    wire_items = 5L
  )
  gate_res <- evaluate_ingestion_gate(m_missing_ts, now = FIXED_NOW)
  expect_false(gate_res$allowed)
  expect_true(grepl("absent", gate_res$reason, ignore.case = TRUE))

  m_bad_ts <- make_manifest(
    timestamp = "not_valid",
    composite_health = "HEALTHY",
    wire_items = 5L
  )
  gate_res2 <- evaluate_ingestion_gate(m_bad_ts, now = FIXED_NOW)
  expect_false(gate_res2$allowed)
  expect_true(grepl("unparseable", gate_res2$reason, ignore.case = TRUE))
})

test_that("evaluate_ingestion_gate blocks on zero volume even if allow_degraded is TRUE", {
  m_zero <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 0L,
    releases_items = 0L,
    beat_claims = 0L
  )

  gate_res <- evaluate_ingestion_gate(m_zero, allow_degraded = TRUE, now = FIXED_NOW)
  expect_false(gate_res$allowed)
  expect_true(gate_res$promotion_frozen)
  expect_true(grepl("Zero-volume gate blocked", gate_res$reason))
})

test_that("evaluate_ingestion_gate blocks on FAILED health unless allow_degraded = TRUE", {
  m_failed <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "FAILED",
    wire_status = "FAILED",
    wire_items = 0L,
    releases_status = "HEALTHY",
    releases_items = 5L,
    beat_status = "HEALTHY",
    beat_claims = 4L
  )

  # Without --allow-degraded -> blocked
  gate_blocked <- evaluate_ingestion_gate(m_failed, allow_degraded = FALSE, now = FIXED_NOW)
  expect_false(gate_blocked$allowed)
  expect_true(gate_blocked$promotion_frozen)
  expect_true(grepl("Operator override required", gate_blocked$reason))

  # With --allow-degraded -> allowed, advisory, promotion_frozen = TRUE
  gate_override <- evaluate_ingestion_gate(m_failed, allow_degraded = TRUE, now = FIXED_NOW)
  expect_true(gate_override$allowed)
  expect_true(gate_override$advisory)
  expect_true(gate_override$promotion_frozen)
  expect_true(grepl("baseline promotion PROHIBITED", gate_override$reason))
})

test_that("evaluate_ingestion_gate strictly rejects invalid composite_health enums", {
  m_invalid <- list(
    ingest_timestamp = "2026-11-07T10:00:00Z",
    composite_health = "BOGUS_STATUS",
    total_items = 10L
  )

  gate_res <- evaluate_ingestion_gate(m_invalid, now = FIXED_NOW)
  expect_false(gate_res$allowed)
  expect_true(grepl("Invalid or missing composite_health", gate_res$reason))
})

test_that("evaluate_ingestion_gate operates seamlessly from JSON file on disk", {
  manifest_obj <- make_manifest(
    timestamp = "2026-11-07T10:00:00Z",
    composite_health = "HEALTHY",
    wire_items = 7L,
    releases_items = 2L,
    beat_claims = 3L
  )

  manifest_path <- file.path(test_dir, "test_file_manifest.json")
  jsonlite::write_json(manifest_obj, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  expect_true(file.exists(manifest_path))

  # Test check_ingest_freshness from file path
  fresh_file <- check_ingest_freshness(manifest_path, now = FIXED_NOW)
  expect_true(fresh_file$fresh)

  # Test check_ingest_volume from file path
  vol_file <- check_ingest_volume(manifest_path)
  expect_true(vol_file$valid)
  expect_equal(vol_file$total_items, 12L)

  # Test can_assert_quiet_week from file path
  expect_true(can_assert_quiet_week(manifest_path, confirmed_changes = 0, now = FIXED_NOW))
  expect_false(can_assert_quiet_week(manifest_path, confirmed_changes = 2, now = FIXED_NOW))

  # Test evaluate_ingestion_gate from file path
  gate_file <- evaluate_ingestion_gate(manifest_path, now = FIXED_NOW)
  expect_true(gate_file$allowed)
  expect_false(gate_file$advisory)
  expect_false(gate_file$promotion_frozen)
})

message("All ingest_freshness unit tests completed successfully!")
