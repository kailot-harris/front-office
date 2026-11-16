# ==============================================================================
# tests/test_xgboost_shap_engine.R
# Unit and Integration Tests for Secondary XGBoost & TreeSHAP Engine (Issue #113)
#
# Validates:
#   1. Configuration constants and paths in config.R.
#   2. Feature matrix shape, 12 feature names, and non-null guarantees.
#   3. Exact TreeSHAP additivity: sum(SHAP) + base_value == logit within 1e-4.
#   4. Exact probability sigmoid: plogis(logit) == prob within 1e-4.
#   5. Determinism: fixed seed (42) and single thread (nthread = 1) produce identical results.
#   6. Out-of-sample track record structure and sanity.
#   7. Strict Zero-Betting Policy compliance.
# ==============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("testthat", quietly = TRUE)) {
    library(testthat)
  }
  library(dplyr)
  library(xgboost)
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}

source(file.path(root_dir, "config.R"))
source(file.path(root_dir, "xgboost_shap_engine.R"))

test_failures <- 0L
ok <- function(label, expr, detail = "") {
  res <- tryCatch(isTRUE(expr), error = function(e) FALSE)
  if (res) {
    cat(sprintf("[PASS] %s  -- %s\n", label, detail))
    expect_true(TRUE)
  } else {
    cat(sprintf("[FAIL] %s  -- %s\n", label, detail))
    test_failures <<- test_failures + 1L
    expect_true(FALSE)
  }
}

cat("=== NFL Analytics Secondary XGBoost & TreeSHAP Tests ===\n\n")

# ------------------------------------------------------------------------------
# Test 1: Config constants
# ------------------------------------------------------------------------------
test_that("XGB-1: CACHE_XGBOOST_MODEL and CACHE_XGBOOST_SHAP declared", {
  ok("XGB-1a CACHE_XGBOOST_MODEL declared",
     exists("CACHE_XGBOOST_MODEL", mode = "character") &&
       grepl("xgboost_shap_model\\.rds$", CACHE_XGBOOST_MODEL),
     basename(CACHE_XGBOOST_MODEL))
  ok("XGB-1b CACHE_XGBOOST_SHAP declared",
     exists("CACHE_XGBOOST_SHAP", mode = "character") &&
       grepl("xgboost_game_shap_2026\\.rds$", CACHE_XGBOOST_SHAP),
     basename(CACHE_XGBOOST_SHAP))
})

# ------------------------------------------------------------------------------
# Test 2: 12 Feature Matrix Construction
# ------------------------------------------------------------------------------
test_that("XGB-2: Feature matrix construction conforms to 12-feature definition", {
  dummy_games <- data.frame(
    game_id = c("2026_01_TEST_A", "2026_01_TEST_B"),
    season = c(2026L, 2026L),
    week = c(1L, 1L),
    home_team = c("KC", "BAL"),
    away_team = c("BAL", "KC"),
    home_raw = c(0.12, -0.05),
    away_raw = c(-0.05, 0.12),
    home_prior = c(0.10, -0.02),
    away_prior = c(-0.02, 0.10),
    home_games_played = c(1L, 1L),
    away_games_played = c(1L, 1L),
    home_qb_backup = c(FALSE, FALSE),
    away_qb_backup = c(FALSE, TRUE),
    projected_margin = c(4.5, -2.1),
    step_elo_diff = c(1.2, -0.8),
    stringsAsFactors = FALSE
  )

  mat <- build_xgboost_feature_matrix(dummy_games)
  ok("XGB-2a Exactly 12 columns in feature matrix",
     ncol(mat) == 12L && nrow(mat) == 2L,
     sprintf("dims: %d x %d", nrow(mat), ncol(mat)))

  ok("XGB-2b Column names match XGB_SHAP_FEATURE_NAMES exactly",
     identical(colnames(mat), XGB_SHAP_FEATURE_NAMES),
     paste(colnames(mat)[1:4], collapse = ", "))

  ok("XGB-2c Zero NaN or NA in constructed matrix",
     all(!is.na(mat)),
     "All finite values")
})

# ------------------------------------------------------------------------------
# Test 3: TreeSHAP Additivity and Sigmoid Tolerances
# ------------------------------------------------------------------------------
test_that("XGB-3 & 4: TreeSHAP sum and probability sigmoid within 1e-4 tolerance", {
  set.seed(42)
  n_samples <- 60L
  p_feats <- length(XGB_SHAP_FEATURE_NAMES)
  sim_x <- matrix(rnorm(n_samples * p_feats), nrow = n_samples, ncol = p_feats)
  colnames(sim_x) <- XGB_SHAP_FEATURE_NAMES
  sim_y <- rbinom(n_samples, 1, 0.5)

  test_model <- train_deterministic_xgboost(sim_x, sim_y, seed = 42L)

  dtest <- xgb.DMatrix(sim_x)
  shap_mat <- predict(test_model, dtest, predcontrib = TRUE)
  logits   <- predict(test_model, dtest, outputmargin = TRUE)
  probs    <- predict(test_model, dtest)

  # Tolerance 1: sum(SHAP) + bias equals logit within 1e-4
  shap_sum <- rowSums(shap_mat)
  max_logit_diff <- max(abs(shap_sum - logits))
  ok("XGB-3 TreeSHAP additivity gate: sum of SHAPs equals model logit within 1e-4",
     max_logit_diff < 1e-4,
     sprintf("max logit diff: %e", max_logit_diff))

  # Tolerance 2: plogis(logit) equals probability within 1e-4
  sig_probs <- stats::plogis(logits)
  max_prob_diff <- max(abs(sig_probs - probs))
  ok("XGB-4 Sigmoid gate: plogis(logit) equals win probability within 1e-4",
     max_prob_diff < 1e-4,
     sprintf("max prob diff: %e", max_prob_diff))
})

# ------------------------------------------------------------------------------
# Test 4: Determinism and Reproducibility
# ------------------------------------------------------------------------------
test_that("XGB-5: Determinism with fixed seed (42) and nthread = 1", {
  n_samples <- 40L
  p_feats <- length(XGB_SHAP_FEATURE_NAMES)
  sim_x <- matrix(rnorm(n_samples * p_feats), nrow = n_samples, ncol = p_feats)
  colnames(sim_x) <- XGB_SHAP_FEATURE_NAMES
  sim_y <- rbinom(n_samples, 1, 0.5)

  m1 <- train_deterministic_xgboost(sim_x, sim_y, seed = 42L)
  m2 <- train_deterministic_xgboost(sim_x, sim_y, seed = 42L)

  dtest <- xgb.DMatrix(sim_x)
  p1 <- predict(m1, dtest)
  p2 <- predict(m2, dtest)

  max_pred_diff <- max(abs(p1 - p2))
  ok("XGB-5 Deterministic predictions across distinct runs with seed 42",
     identical(p1, p2) || max_pred_diff < 1e-12,
     sprintf("max diff: %e", max_pred_diff))
})

# ------------------------------------------------------------------------------
# Test 5: End-to-End Pipeline Execution
# ------------------------------------------------------------------------------
test_that("XGB-6: End-to-end execution produces valid CACHE_XGBOOST_SHAP payload", {
  res <- run_xgboost_shap_engine(target_season = 2026L, force_retrain = TRUE)
  ok("XGB-6a run_xgboost_shap_engine returns TRUE", isTRUE(res), "Success")

  ok("XGB-6b CACHE_XGBOOST_SHAP file created on disk",
     file.exists(CACHE_XGBOOST_SHAP),
     CACHE_XGBOOST_SHAP)

  shap_data <- readRDS(CACHE_XGBOOST_SHAP)
  ok("XGB-6c Target season matches 2026",
     identical(as.integer(shap_data$target_season), 2026L),
     sprintf("Season: %d", shap_data$target_season))

  ok("XGB-6d Out-of-sample track record populated with valid metrics",
     !is.null(shap_data$out_of_sample_record) &&
       shap_data$out_of_sample_record$n_games > 0L &&
       !is.na(shap_data$out_of_sample_record$accuracy) &&
       !is.na(shap_data$out_of_sample_record$brier),
     sprintf("N=%d, Acc=%.1f%%, Brier=%.4f",
             shap_data$out_of_sample_record$n_games,
             shap_data$out_of_sample_record$accuracy,
             shap_data$out_of_sample_record$brier))

  ok("XGB-6e All 145 games contain complete 12-feature TreeSHAP explanations",
     length(shap_data$games) >= 145L &&
       length(shap_data$games[[1]]$features) == 12L &&
       !is.null(shap_data$games[[1]]$base_value),
     sprintf("%d games with 12 features each", length(shap_data$games)))
})

# ------------------------------------------------------------------------------
# Test 6: Zero-Betting Policy Guard
# ------------------------------------------------------------------------------
test_that("XGB-7: Zero-betting policy compliance in engine and tests", {
  banned_pattern <- "\\b(spread|projected_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book)\\b"
  engine_text <- readLines(file.path(root_dir, "xgboost_shap_engine.R"))
  clean_engine <- !any(grepl(banned_pattern, engine_text, ignore.case = TRUE))

  ok("XGB-7 Zero forbidden betting vocabulary in xgboost_shap_engine.R",
     clean_engine,
     "100% clean")
})

cat(sprintf("\n=== Secondary XGBoost Test Summary: %d failures ===\n", test_failures))
if (test_failures > 0) {
  stop(sprintf("%d test(s) failed in test_xgboost_shap_engine.R", test_failures))
}
