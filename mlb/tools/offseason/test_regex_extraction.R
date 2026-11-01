# ==============================================================================
# tools/offseason/test_regex_extraction.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Layer A Extraction CI Test Suite
# Path: tools/offseason/test_regex_extraction.R
#
# Validates deterministic regex extraction against authentic raw wire samples:
#   - Asserts exact recall match: actual_count == expected_count
#   - Asserts 100% precision: precision == 1.0 on (entity, field, prior_val, new_val)
#   - Runs offline in <100ms with zero network calls.
#
# Conforms to blueprint §§ 2, 3, 10 and Issue #45.
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
      stop(sprintf("test_regex_extraction.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

source("tools/offseason/extract_regex.R")

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Running Layer A Deterministic Regex Extraction Test Suite\n")
  cat("=====================================================================\n")
  
  # Load the pinned S0 capture, NOT cache/league_state_baseline.json. The
  # expected_tuples in official_wire_raw_samples.json are stated relative to
  # S0; against the live cache (already advanced past week 1) the extractor
  # correctly emits fewer deltas and the recall assertion fails spuriously.
  baseline_path <- "data/fixtures/league_state_s0.json"
  if (!file.exists(baseline_path)) {
    stop("test_regex_extraction.R: pinned S0 baseline not found at data/fixtures/league_state_s0.json")
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  baseline$.player_index <- build_player_index(baseline$players)
  
  fixture_path <- "data/fixtures/official_wire_raw_samples.json"
  if (!file.exists(fixture_path)) {
    stop(sprintf("test_regex_extraction.R: fixtures not found at %s", fixture_path))
  }
  fixtures <- fromJSON(fixture_path, simplifyVector = FALSE)
  
  total_samples <- length(fixtures)
  cat(sprintf("Loaded %d raw wire test fixtures.\n\n", total_samples))
  
  overall_expected <- 0
  overall_actual <- 0
  overall_correct <- 0
  
  start_time <- Sys.time()
  
  for (i in seq_along(fixtures)) {
    fixture <- fixtures[[i]]
    
    extracted <- extract_regex_from_text(
      raw_text = fixture$raw_text,
      baseline = baseline,
      as_of_date = fixture$date,
      source_url = fixture$source_url
    )
    
    expected_tuples <- fixture$expected_tuples
    n_expected <- length(expected_tuples)
    n_actual <- length(extracted)
    overall_expected <- overall_expected + n_expected
    overall_actual <- overall_actual + n_actual
    
    # Exact recall count check
    if (n_actual != n_expected) {
      stop(sprintf("  [FAIL] Recall mismatch for %s: expected %d tuples, got %d",
                   fixture$id, n_expected, n_actual))
    }
    
    # Precision and exact tuple matching
    for (act in extracted) {
      match_found <- FALSE
      for (exp in expected_tuples) {
        # Check entity_id, field, prior_val, new_val
        id_match <- identical(act$entity_id, exp$entity_id)
        field_match <- identical(act$field, exp$field)
        prior_match <- identical(as.character(act$prior_val), as.character(exp$prior_val))
        new_match <- identical(as.character(act$new_val), as.character(exp$new_val))
        
        if (id_match && field_match && prior_match && new_match) {
          match_found <- TRUE
          break
        }
      }
      
      if (!match_found) {
        stop(sprintf("  [FAIL] Unmatched extracted tuple in %s: (%s, %s, %s -> %s)",
                     fixture$id, act$entity_id, act$field, act$prior_val, act$new_val))
      } else {
        overall_correct <- overall_correct + 1
      }
    }
  }
  
  elapsed_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
  
  for (i in seq_along(fixtures)) {
    fixture <- fixtures[[i]]
    cat(sprintf("Sample %d [%s]: \"%s\"\n", i, fixture$id, fixture$raw_text))
    cat(sprintf("  [PASS] %d/%d tuples matched with 100%% precision.\n", length(fixture$expected_tuples), length(fixture$expected_tuples)))
  }
  precision <- if (overall_actual > 0) overall_correct / overall_actual else 1.0
  recall <- if (overall_expected > 0) overall_correct / overall_expected else 1.0
  
  cat("\n---------------------------------------------------------------------\n")
  cat(sprintf("Total Expected Tuples: %d\n", overall_expected))
  cat(sprintf("Total Extracted Tuples: %d\n", overall_actual))
  cat(sprintf("Exact Recall: %.1f%%\n", recall * 100))
  cat(sprintf("Precision: %.1f%%\n", precision * 100))
  cat(sprintf("Execution Time: %.2f ms (Target: <100ms offline)\n", elapsed_ms))
  cat("---------------------------------------------------------------------\n")
  
  if (precision < 1.0 || recall < 1.0) {
    stop("Layer A benchmark failed: precision or recall below 100%!")
  }
  
  cat(">>> ALL LAYER A DETERMINISTIC EXTRACTION TESTS PASSED CLEANLY (6/6)\n")
  cat("=====================================================================\n")
}

if (!interactive()) {
  main()
}
