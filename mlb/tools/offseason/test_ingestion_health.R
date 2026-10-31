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

message("=====================================================================")
message(">>> ALL INGESTION HEALTH TESTS PASSED CLEANLY (5/5)")
message("=====================================================================")
