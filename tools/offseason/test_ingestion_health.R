# ==============================================================================
# tools/offseason/test_ingestion_health.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Ingestion Health & Governance Tests
# Path: tools/offseason/test_ingestion_health.R
#
# Verifies:
#   1. Simulated league_wire failure transitions composite_health to "FAILED".
#   2. Simulated failure blocks quiet-week assertion (can_assert_quiet_week == FALSE).
#   3. allow_degraded allows execution past wire failure.
#   4. Degraded secondary feeds (team_releases or beat_feeds) transition to "DEGRADED"
#      while preserving non-quiet week execution.
#   5. All raw_items receive valid rosterTier discrimination ('MAJOR_40_MAN' | 'MINOR_LEAGUE').
#   6. Stale-snapshot laundering fallback is removed: an unreachable endpoint
#      with the Oct 31 snapshot present returns FAILED with true http_code (0L / non-200),
#      never HEALTHY and never a fabricated 200.
#   7. Persisted artifact (cache/offseason_wire_items.json) passes contract
#      validator (validate_wire_items), with unique transaction IDs and honest volume.
#   8. Explicit replay-snapshot opt-in reports status "DEGRADED" and http_code 0L.
#   9. Baseline-derived start_date dynamically resolves from baseline asOf.
# ==============================================================================

# GitHub issue #90: Project root resolution prelude.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("test_ingestion_health.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

# Ensure renv / user library path includes installed packages
if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

# Source the ingestion engine
source(file.path(PROJECT_DIR, "tools", "offseason", "ingest_sources.R"))

message("=====================================================================")
message(">>> Running Ingestion Health Gate & Governance Test Suite")
message("=====================================================================")

# Test 1: Simulated league_wire failure transitions composite_health to FAILED
message("Test 1: Simulated league_wire failure...")
fail_res <- ingest_all(mock_wire_fail = TRUE)
stopifnot(fail_res$manifest$adapters$league_wire$status == "FAILED")
stopifnot(fail_res$composite_health == "FAILED")
message("  [PASS] Composite health transitioned to 'FAILED' on wire outage.")

# Test 2: Block quiet-week assertion when wire is FAILED
message("Test 2: Quiet-week precondition enforcement...")
stopifnot(fail_res$can_assert_quiet_week == FALSE)
message("  [PASS] Quiet-week assertion is strictly blocked when composite_health != 'HEALTHY'.")

# Test 3: Allow-degraded governance check
message("Test 3: Degraded policy enforcement...")
fail_allow_res <- ingest_all(mock_wire_fail = TRUE, allow_degraded = TRUE)
stopifnot(fail_allow_res$composite_health == "FAILED")
message("  [PASS] --allow-degraded acknowledged on wire outage.")

# Test 4: Degraded secondary adapters (team_releases degraded)
message("Test 4: Secondary adapter degradation...")
deg_teams_res <- ingest_all(mock_teams_fail = TRUE)
stopifnot(deg_teams_res$composite_health == "DEGRADED")
stopifnot(deg_teams_res$manifest$adapters$team_releases$status == "DEGRADED")
stopifnot(deg_teams_res$can_assert_quiet_week == FALSE)
message("  [PASS] Degraded secondary adapter gracefully handled.")

# Test 5: Live / Full healthy ingestion state
message("Test 5: Healthy end-to-end ingestion state...")
healthy_res <- ingest_all()
stopifnot(healthy_res$composite_health == "HEALTHY")
stopifnot(healthy_res$manifest$adapters$league_wire$status == "HEALTHY")
stopifnot(healthy_res$can_assert_quiet_week == TRUE)
stopifnot(all(healthy_res$raw_items$rosterTier %in% c("MAJOR_40_MAN", "MINOR_LEAGUE")))
message("  [PASS] Healthy ingestion run validated with 100% rosterTier coverage.")

# Test 6: Removed laundering fallback — simulated network failure with snapshot present
message("Test 6: Laundering fallback removal with snapshot present on disk...")
snap_file <- file.path(PROJECT_DIR, "cache", "raw_ingest_archive", "20261031", "mlb_transactions_catchup.json")
stopifnot(file.exists(snap_file))

# 6a. mock_fail returns FAILED with 500, never 200, never HEALTHY
fail_wire <- fetch_league_wire(mock_fail = TRUE)
stopifnot(identical(fail_wire$status, "FAILED"))
stopifnot(identical(fail_wire$http_code, 500L))
stopifnot(identical(fail_wire$items_found, 0L))

# 6b. unreachable endpoint returns FAILED with http_code 0L, never 200, never HEALTHY
unreach_wire <- fetch_league_wire(timeout_secs = 0.0001)
stopifnot(identical(unreach_wire$status, "FAILED"))
stopifnot(identical(unreach_wire$http_code, 0L))
stopifnot(identical(unreach_wire$items_found, 0L))
message("  [PASS] Network failure yields FAILED with true http_code (0L / 500L); snapshot is not consulted.")

# Test 7: Persisted wire items artifact validation & contract conformance
message("Test 7: Wire items artifact validation (contract conformance)...")
artifact_path <- file.path(PROJECT_DIR, "cache", "offseason_wire_items.json")
stopifnot(file.exists(artifact_path))

items <- jsonlite::fromJSON(artifact_path, simplifyVector = FALSE, encoding = "UTF-8")
stopifnot(is.list(items) && length(items) > 0)

val_res <- validate_wire_items(items, require_unique_transaction_ids = TRUE, allow_unknown_fields = FALSE)
stopifnot(val_res$pass == TRUE)
stopifnot(val_res$n_errors == 0L)
message(sprintf("  [PASS] Artifact passes contract validation (%s).", val_res$summary))

# Verify honest volume: manifest items_found equals artifact record count
manifest_path <- file.path(PROJECT_DIR, "cache", "ingestion_manifest.json")
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
stopifnot(identical(as.integer(manifest$adapters$league_wire$items_found), length(items)))
message(sprintf("  [PASS] Honest volume verified: manifest items_found (%d) == artifact length (%d).",
                manifest$adapters$league_wire$items_found, length(items)))

# Verify trade dedup: transaction_id must be strictly unique
tids <- vapply(items, function(x) x$transaction_id, integer(1))
stopifnot(length(tids) == length(unique(tids)))
message("  [PASS] Unique transaction_id enforcement verified (mirrored trades collapsed).")

# Test 8: Replay snapshot opt-in governance
message("Test 8: Explicit snapshot replay opt-in governance...")
replay_wire <- fetch_league_wire(replay_snapshot = snap_file)
stopifnot(identical(replay_wire$status, "DEGRADED"))
stopifnot(identical(replay_wire$http_code, 0L))
stopifnot(replay_wire$items_found == 276L)
message("  [PASS] Replay snapshot reports status 'DEGRADED' and http_code 0L, never fabricated 200.")

# Test 9: Dynamic baseline-derived start_date
message("Test 9: Baseline-derived start_date resolution...")
derived_start <- derive_default_start_date()
baseline <- jsonlite::fromJSON(file.path(PROJECT_DIR, "cache", "league_state_baseline.json"), simplifyVector = FALSE)
expected_date <- substr(baseline$asOf, 1, 10)
stopifnot(identical(derived_start, expected_date))
message(sprintf("  [PASS] Default start_date correctly resolved to %s from baseline asOf (%s).",
                derived_start, baseline$asOf))

message("=====================================================================")
message(">>> ALL INGESTION HEALTH TESTS PASSED CLEANLY (9/9)")
message("=====================================================================")
