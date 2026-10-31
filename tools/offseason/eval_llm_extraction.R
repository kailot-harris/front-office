# ==============================================================================
# tools/offseason/eval_llm_extraction.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Layer B Semantic LLM Evaluation
# Path: tools/offseason/eval_llm_extraction.R
#
# Evaluates semantic key tuple scoring: (entity_id, field, tier)
# Weighted heavily toward complex trades, cash considerations, and PTBNL structures.
# Runs offline and reports evaluation summary metrics.
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
      stop(sprintf("eval_llm_extraction.R: cannot locate repo root (no config.R at or above '%s')", start))
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

source("tools/offseason/extract_llm.R")
source("tools/offseason/extract_regex.R")

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Running Layer B Semantic LLM Evaluation Harness\n")
  cat("=====================================================================\n")
  
  baseline_path <- "cache/league_state_baseline.json"
  if (!file.exists(baseline_path)) {
    stop("eval_llm_extraction.R: baseline not found at cache/league_state_baseline.json")
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  baseline$.player_index <- build_player_index(baseline$players)
  
  # Semantic benchmark test cases (complex trades, cash, PTBNL, beat rumors)
  # Weights:
  # - Standard move: weight 1.0
  # - Multi-player trade: weight 2.0
  # - Cash considerations: weight 2.5
  # - PTBNL structures: weight 3.0
  test_cases <- list(
    list(
      id = "semantic_trade_cash_ptbnl",
      text = "Boston Red Sox traded SS Tsung-Che Cheng to Detroit Tigers for cash considerations and a player to be named later.",
      category = "Complex Trade",
      expected_tuples = list(
        list(entity_id = "B_28344", field = "team", tier = "CONFIRMED", weight = 2.0),
        list(entity_id = "DET", field = "cbtPayrollCommitted", tier = "CONFIRMED", weight = 2.5),
        list(entity_id = "DET", field = "draftPicks2027", tier = "CONFIRMED", weight = 3.0)
      )
    ),
    list(
      id = "semantic_multi_player_swap",
      text = "Athletics traded RHP Jareth Rayo to Boston Red Sox for LF Nate Eaton.",
      category = "Player Swap",
      expected_tuples = list(
        list(entity_id = "B_25055", field = "team", tier = "CONFIRMED", weight = 2.0)
      )
    ),
    list(
      id = "semantic_beat_rumor",
      text = "Sources: San Diego Padres in active discussions to trade Lucas Giolito to Baltimore Orioles.",
      category = "Beat Rumor",
      expected_tuples = list(
        list(entity_id = "P_15474", field = "team", tier = "REPORTED", weight = 1.5)
      )
    )
  )
  
  total_weight <- 0
  achieved_weight <- 0
  total_tuples <- 0
  matched_tuples <- 0
  
  for (tc in test_cases) {
    cat(sprintf("Evaluating [%s] (%s):\n  \"%s\"\n", tc$id, tc$category, tc$text))
    
    extracted <- extract_llm_semantic(
      raw_text = tc$text,
      baseline = baseline,
      as_of_date = "2026-10-31",
      mock = TRUE
    )
    
    for (exp in tc$expected_tuples) {
      total_weight <- total_weight + exp$weight
      total_tuples <- total_tuples + 1
      
      # Search for matching (entity_id, field, tier)
      found <- FALSE
      for (act in extracted) {
        id_match <- identical(act$entity_id, exp$entity_id)
        field_match <- identical(act$field, exp$field)
        tier_match <- identical(act$tier, exp$tier)
        if (id_match && field_match && tier_match) {
          found <- TRUE
          break
        }
      }
      
      if (found) {
        achieved_weight <- achieved_weight + exp$weight
        matched_tuples <- matched_tuples + 1
        cat(sprintf("    [MATCH] Key tuple (%s, %s, %s) (weight: %.1f)\n",
                    exp$entity_id, exp$field, exp$tier, exp$weight))
      } else {
        cat(sprintf("    [MISS] Key tuple (%s, %s, %s) not matched!\n",
                    exp$entity_id, exp$field, exp$tier))
      }
    }
  }
  
  weighted_score <- (achieved_weight / total_weight) * 100
  accuracy <- (matched_tuples / total_tuples) * 100
  
  cat("\n---------------------------------------------------------------------\n")
  cat(sprintf("Total Evaluated Key Tuples: %d\n", total_tuples))
  cat(sprintf("Matched Key Tuples: %d (Accuracy: %.1f%%)\n", matched_tuples, accuracy))
  cat(sprintf("Total Tuple Weight: %.1f\n", total_weight))
  cat(sprintf("Achieved Tuple Weight: %.1f\n", achieved_weight))
  cat(sprintf("Weighted Semantic Score: %.1f%% (Benchmark Target: >=90.0%%)\n", weighted_score))
  cat("---------------------------------------------------------------------\n")
  
  if (weighted_score < 90.0) {
    stop("Layer B semantic evaluation failed benchmark target!")
  }
  
  cat(">>> ALL LAYER B SEMANTIC EVALUATION BENCHMARKS PASSED CLEANLY\n")
  cat("=====================================================================\n")
}

if (!interactive()) {
  main()
}
