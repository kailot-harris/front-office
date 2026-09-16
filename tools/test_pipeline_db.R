# ==============================================================================
# Test Suite: Pipeline Integration DB Test
# Path: tools/test_pipeline_db.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(duckdb)
})

source("config.R")

cat("\n>>> [TEST] Executing Full Pipeline Integration Test...\n")

# 1. Run the full pipeline
# We capture stdout to ensure it completes
system("Rscript run_full_pipeline.R")

# 2. Verify Logs DB updated
log_con <- dbConnect(duckdb(), "logs/logs.duckdb")
log_count <- dbGetQuery(log_con, "SELECT count(*) as n FROM logs")$n
dbDisconnect(log_con, immediate = TRUE)

# 3. Verify Embeddings DB updated
emb_con <- dbConnect(duckdb(), "logs/analytics.duckdb")
emb_count <- dbGetQuery(emb_con, "SELECT count(*) as n FROM team_embeddings")$n
dbDisconnect(emb_con, immediate = TRUE)

cat(sprintf("\nPipeline results:\n- Log events in DB: %d\n- Embeddings in DB: %d\n",
            log_count, emb_count))

if (log_count > 0 && emb_count > 0) {
  cat("\n[SUCCESS] Pipeline successfully integrated with DuckDB stores.\n")
} else {
  stop("Pipeline ran but failed to populate one or more DB stores.")
}
