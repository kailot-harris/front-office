# ==============================================================================
# build_offseason_dataset.R
# WNBA Offseason Moves & Expansion Hub (ARCHIVED — GitHub #129, #141)
# ==============================================================================
# This script has been archived. Hand-authored transactions, team grades, and
# draft orders have been retired from the DAG. Active off-season transaction
# reconciliation is provided by build_offseason_monitor.R.
# ==============================================================================

if (file.exists("logging_utils.R")) source("logging_utils.R")
message(">>> [OFFSEASON BUILDER] Stage archived pending live data integration (GitHub #129, #141). Skipping execution.")
if (exists("log_info")) {
  log_info("build_offseason_dataset: Stage archived pending live DAG integration. Skipping write.", script = "build_offseason_dataset.R")
}
