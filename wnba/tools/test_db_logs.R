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

con <- dbConnect(duckdb(), db_path)
logs <- dbGetQuery(con, "SELECT * FROM logs ORDER BY timestamp DESC LIMIT 3")
dbDisconnect(con, immediate = TRUE)

cat("\nRecent Log Entries from DB:\n")
print(logs)

# 3. Validation
if (nrow(logs) >= 3) {
  cat("\n[SUCCESS] Log DB is capturing events correctly.\n")
} else {
  stop(sprintf("Log DB only captured %d events. Expected >= 3.", nrow(logs)))
}
