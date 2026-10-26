if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    stop("Cannot locate the project root: no config.R at ./ or ../../. Run tests from the repo root or from tests/testthat/.", call. = FALSE)
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
})

source("logging_utils.R")
source("config.R")
source("tools/evaluate_season_calibration.R")

test_that("Season calibration check runs, calculates valid scores, and flags status", {
  # Quality gate on the real season's Elo history; skips where caches don't
  # exist (CI, fresh clone, worktree). See helper-common.R.
  skip_if_no_cache("ratings", "mlb_elo_history.rds")

  res <- run_season_calibration_check(verbose = FALSE)

  expect_true(is.list(res))
  expect_equal(res$status, "OPTIMAL")
  expect_true(res$total_games > 2000)

  # Brier score must outperform coin-flip baseline (< 0.2500)
  expect_true(res$brier_score < 0.2500)
  expect_true(res$brier_skill_score > 0)

  # Log loss for MLB win probability typically between 0.67 and 0.70
  expect_true(res$log_loss > 0.65 && res$log_loss < 0.72)

  # Weighted calibration error should be under 5% (0.05)
  expect_true(res$weighted_calib_error < 0.05)

  # Zero extreme probability blowups (>85% or <15%)
  expect_false(res$has_extreme_outliers)

  # Bin calibration monotonicity: observed win rate should generally increase across bins
  bins <- res$bin_calibration
  expect_true(nrow(bins) >= 5)
  # Low bin vs High bin
  expect_true(bins$obs_win_pct[1] < bins$obs_win_pct[nrow(bins)])
})
