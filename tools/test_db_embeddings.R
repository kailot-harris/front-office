# ==============================================================================
# Test Suite: Embeddings DB Verification
# Path: tools/test_db_embeddings.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(duckdb)
})

source("config.R")

cat("\n>>> [TEST] Verifying Embeddings DB Functionality...\n")

# 1. Execute the embedding script
system("python team_embeddings.py")

# 2. Verify the DB file exists
db_path <- "logs/analytics.duckdb"
if (!file.exists(db_path)) {
  stop("Analytics DB file not found! team_embeddings.py failed to create it.")
}

# 3. Verify tables and content
con <- dbConnect(duckdb(), db_path)

# Check embeddings table
emb_data <- dbGetQuery(con, "SELECT * FROM team_embeddings LIMIT 5")
# Check similarity table
sim_data <- dbGetQuery(con, "SELECT * FROM team_similarity LIMIT 5")

dbDisconnect(con, immediate = TRUE)

cat("\nSample Embeddings from DB:\n")
print(emb_data)
cat("\nSample Similarity from DB:\n")
print(sim_data)

# Validation
if (nrow(emb_data) > 0 && nrow(sim_data) > 0) {
  cat("\n[SUCCESS] Embeddings and Similarity stored and retrieved correctly from DB.\n")
} else {
  stop("Embeddings or Similarity tables are empty!")
}
