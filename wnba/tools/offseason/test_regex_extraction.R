# ==============================================================================
# test_regex_extraction.R
# WNBA Offseason Dynamics Monitor — Deterministic CI Gate for Layer A (Phase 3)
#
# Asserts 100% precision and exact recall on official wire snapshots:
#   1. extracted_count == expected_count (exact recall)
#   2. 100% precision on tuples (entity_id, field, prior_val, new_val)
#
# Runs offline, 0 API calls, <100ms.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# Guarantees the script resolves repo root regardless of invocation working dir
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

# Source the regex extractor
source(file.path("tools", "offseason", "extract_regex.R"))

start_time <- Sys.time()

fixtures_path <- file.path("data", "fixtures", "official_wire_raw_samples.json")
if (!file.exists(fixtures_path)) {
  stop("Missing fixtures file: ", fixtures_path)
}

samples <- jsonlite::fromJSON(fixtures_path, simplifyVector = FALSE)
baseline_path <- file.path("cache", "league_state_baseline.json")
baseline_state <- if (file.exists(baseline_path)) jsonlite::fromJSON(baseline_path, simplifyVector = FALSE) else NULL

total_expected <- 0
total_extracted <- 0
exact_matches <- 0

test_that("Deterministic CI Gate (Layer A): Exact recall and 100% precision", {
  for (sample in samples) {
    raw_text <- sample$raw_text
    exp_deltas <- sample$expected_deltas
    
    extracted <- extract_deltas_regex(
      raw_text = raw_text,
      date = sample$date,
      source_url = sample$source_url,
      baseline_state = baseline_state
    )
    
    # 1. Exact Recall per sample
    expect_equal(length(extracted), length(exp_deltas),
                 info = sprintf("Recall mismatch for sample %s: expected %d, got %d",
                                sample$id, length(exp_deltas), length(extracted)))
    
    total_expected <<- total_expected + length(exp_deltas)
    total_extracted <<- total_extracted + length(extracted)
    
    # 2. Precision: verify each extracted matches an expected tuple exactly
    for (act in extracted) {
      matched <- FALSE
      for (exp in exp_deltas) {
        id_match <- identical(as.character(act$entity_id), as.character(exp$entity_id))
        field_match <- identical(as.character(act$field), as.character(exp$field))
        
        # Safe prior_val comparison (handling NULLs and numeric/char conversions)
        prior_match <- if (is.null(exp$prior_val)) {
          is.null(act$prior_val)
        } else {
          identical(as.character(act$prior_val), as.character(exp$prior_val))
        }
        
        # Safe new_val comparison
        new_match <- identical(as.character(act$new_val), as.character(exp$new_val))
        
        if (id_match && field_match && prior_match && new_match) {
          matched <- TRUE
          break
        }
      }
      expect_true(matched, info = sprintf("Precision error in %s: extracted (%s, %s, %s, %s) not expected",
                                          sample$id, act$entity_id, act$field, act$prior_val, act$new_val))
      if (matched) exact_matches <<- exact_matches + 1
    }
  }
  
  # Macro Assertions
  expect_equal(total_extracted, total_expected)
  expect_equal(exact_matches, total_expected)
  
  precision <- exact_matches / max(1, total_extracted)
  recall <- exact_matches / max(1, total_expected)
  
  expect_equal(precision, 1.0)
  expect_equal(recall, 1.0)
})

elapsed_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
cat(sprintf("\n[PASS] Layer A Regex CI Gate verified: 100%% precision, exact recall (%d/%d tuples matched in %.1f ms)\n",
            total_expected, total_expected, elapsed_ms))
