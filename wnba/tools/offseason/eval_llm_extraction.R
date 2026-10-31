# ==============================================================================
# eval_llm_extraction.R
# WNBA Offseason Dynamics Monitor — Offline LLM Evaluation Harness (Layer B / Phase 3)
#
# Evaluates candidate deltas using Key Tuple Identity:
#   (entity_id == exp_id) & (field == exp_field) & (tier == exp_tier)
#
# Decoupled from blocking publish gates; serves as advisory scoring benchmark
# during prompt tuning and model validation.
#
# Usage:
#   Rscript tools/offseason/eval_llm_extraction.R [--fixtures=<path>]
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
  library(jsonlite)
})

source(file.path("tools", "offseason", "extract_llm.R"))

#' Score extracted deltas against expected benchmark tuples
#' Key Tuple Identity: (entity_id == exp_id) & (field == exp_field) & (tier == exp_tier)
score_extraction_tuples <- function(extracted_deltas, expected_deltas) {
  if (length(expected_deltas) == 0 && length(extracted_deltas) == 0) {
    return(list(tp = 0, fp = 0, fn = 0, precision = 1.0, recall = 1.0, f1 = 1.0))
  }
  
  matched_expected <- rep(FALSE, length(expected_deltas))
  matched_extracted <- rep(FALSE, length(extracted_deltas))
  
  for (i in seq_along(extracted_deltas)) {
    act <- extracted_deltas[[i]]
    for (j in seq_along(expected_deltas)) {
      if (matched_expected[j]) next
      exp <- expected_deltas[[j]]
      
      id_match <- identical(as.character(act$entity_id), as.character(exp$entity_id))
      field_match <- identical(as.character(act$field), as.character(exp$field))
      tier_match <- identical(as.character(act$tier), as.character(exp$tier))
      
      if (id_match && field_match && tier_match) {
        matched_expected[j] <- TRUE
        matched_extracted[i] <- TRUE
        break
      }
    }
  }
  
  tp <- sum(matched_extracted)
  fp <- length(extracted_deltas) - tp
  fn <- sum(!matched_expected)
  
  precision <- if (length(extracted_deltas) > 0) tp / length(extracted_deltas) else 1.0
  recall <- if (length(expected_deltas) > 0) tp / length(expected_deltas) else 1.0
  f1 <- if ((precision + recall) > 0) (2 * precision * recall) / (precision + recall) else 0.0
  
  list(
    tp = tp,
    fp = fp,
    fn = fn,
    precision = precision,
    recall = recall,
    f1 = f1
  )
}

#' Run offline evaluation harness across benchmark fixtures
evaluate_offline_benchmark <- function(benchmark_samples = NULL) {
  if (is.null(benchmark_samples)) {
    # 1. Load official wire samples
    wire_path <- file.path("data", "fixtures", "official_wire_raw_samples.json")
    benchmark_samples <- if (file.exists(wire_path)) jsonlite::fromJSON(wire_path, simplifyVector = FALSE) else list()
    
    # 2. Add Tier 2 & Tier 3 synthetic benchmark items
    benchmark_samples[[length(benchmark_samples) + 1]] <- list(
      id = "beat_sample_001",
      date = "2027-01-08",
      raw_text = "Sources: Phoenix Mercury seeking veteran point guard in upcoming free agency.",
      expected_deltas = list(
        list(
          entity_id = "PHX",
          field = "reportedTarget",
          tier = "REPORTED"
        )
      )
    )
    
    benchmark_samples[[length(benchmark_samples) + 1]] <- list(
      id = "spec_sample_001",
      date = "2027-01-12",
      raw_text = "League chatter connects Chicago Sky to several potential frontcourt trade speculation talks.",
      expected_deltas = list(
        list(
          entity_id = "CHI",
          field = "tradeSpeculation",
          tier = "SPECULATIVE"
        )
      )
    )
  }
  
  total_tp <- 0
  total_fp <- 0
  total_fn <- 0
  
  baseline_path <- file.path("cache", "league_state_baseline.json")
  baseline_state <- if (file.exists(baseline_path)) jsonlite::fromJSON(baseline_path, simplifyVector = FALSE) else NULL
  
  cat("========================================================================\n")
  cat("Running Layer B Offline LLM Evaluation Harness\n")
  cat("Evaluation Metric: Semantic Key Tuple Identity (entity_id, field, tier)\n")
  cat("========================================================================\n\n")
  
  for (sample in benchmark_samples) {
    extracted <- extract_deltas_llm(
      raw_text = sample$raw_text,
      date = sample$date,
      source_url = sample$source_url,
      baseline_state = baseline_state,
      mock = TRUE
    )
    
    res <- score_extraction_tuples(extracted, sample$expected_deltas)
    total_tp <- total_tp + res$tp
    total_fp <- total_fp + res$fp
    total_fn <- total_fn + res$fn
    
    cat(sprintf("[%s] Evaluated %d candidate deltas -> P: %.2f | R: %.2f | F1: %.2f\n",
                sample$id, length(extracted), res$precision, res$recall, res$f1))
  }
  
  macro_precision <- if ((total_tp + total_fp) > 0) total_tp / (total_tp + total_fp) else 1.0
  macro_recall <- if ((total_tp + total_fn) > 0) total_tp / (total_tp + total_fn) else 1.0
  macro_f1 <- if ((macro_precision + macro_recall) > 0) (2 * macro_precision * macro_recall) / (macro_precision + macro_recall) else 0.0
  
  cat("\n------------------------------------------------------------------------\n")
  cat(sprintf("Macro Benchmark Results: TP: %d | FP: %d | FN: %d\n", total_tp, total_fp, total_fn))
  cat(sprintf("Macro Precision: %.4f | Macro Recall: %.4f | Macro F1: %.4f\n",
              macro_precision, macro_recall, macro_f1))
  cat("------------------------------------------------------------------------\n")
  
  invisible(list(
    precision = macro_precision,
    recall = macro_recall,
    f1 = macro_f1
  ))
}

if (!interactive()) {
  evaluate_offline_benchmark()
}
