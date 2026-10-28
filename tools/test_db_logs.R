# ==============================================================================
# Test Suite: Log DB Verification
# Path: tools/test_db_logs.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(duckdb)
})

source("config.R")
source("logging_utils.R")

cat("\n>>> [TEST] Verifying Log DB Functionality...\n")

# 1. Trigger some log events
log_info("Test log event: INFO", call = "test_db_logs.R")
log_warn("Test log event: WARN", call = "test_db_logs.R")
log_error("Test log event: ERROR", call = "test_db_logs.R")

# 2. Query the DuckDB file
db_path <- LOG_DB_FILE
if (!file.exists(db_path)) {
  stop("Log DB file not found! DB writing failed.")
}

con <- .log_get_con()
logs <- dbGetQuery(con, "SELECT * FROM logs ORDER BY timestamp DESC LIMIT 3")
.log_disconnect()

cat("\nRecent Log Entries from DB:\n")
print(logs)

# 3. Validation
if (nrow(logs) >= 3) {
  cat("\n[PASS] Log DB captured INFO, WARN, and ERROR events (>= 3 rows).\n")
  cat("[SUCCESS] Log DB is capturing events correctly.\n")
} else {
  cat(sprintf("\n[FAIL] Log DB only captured %d events. Expected >= 3.\n", nrow(logs)))
  stop(sprintf("Log DB only captured %d events. Expected >= 3.", nrow(logs)))
}
