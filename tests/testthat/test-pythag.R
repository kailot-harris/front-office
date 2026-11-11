# Ensure working directory is project root
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
source("mlb_pythag_baseline.R")

test_that("Pythagorean win expectation conforms to bounds and monotonicity", {
  # 1. 0.500 when RS == RA
  p_even <- calc_pythagorean_win_pct(rs = 750, ra = 750, games = 162, method = "pythagenpat")
  expect_equal(p_even, 0.50, tolerance = 1e-4)

  # 2. Strict monotonicity with RS
  p_700 <- calc_pythagorean_win_pct(rs = 700, ra = 700, games = 162, method = "pythagenpat")
  p_800 <- calc_pythagorean_win_pct(rs = 800, ra = 700, games = 162, method = "pythagenpat")
  p_900 <- calc_pythagorean_win_pct(rs = 900, ra = 700, games = 162, method = "pythagenpat")
  expect_true(p_700 < p_800)
  expect_true(p_800 < p_900)

  # 3. Strict monotonicity with RA (inversely)
  p_ra_low  <- calc_pythagorean_win_pct(rs = 750, ra = 650, games = 162, method = "pythagenpat")
  p_ra_high <- calc_pythagorean_win_pct(rs = 750, ra = 850, games = 162, method = "pythagenpat")
  expect_true(p_ra_low > p_ra_high)

  # 4. Comparison across methods
  p_pat  <- calc_pythagorean_win_pct(rs = 800, ra = 650, games = 162, method = "pythagenpat")
  p_port <- calc_pythagorean_win_pct(rs = 800, ra = 650, games = 162, method = "pythagenport")
  p_183  <- calc_pythagorean_win_pct(rs = 800, ra = 650, games = 162, method = "fixed_1.83")
  p_sq   <- calc_pythagorean_win_pct(rs = 800, ra = 650, games = 162, method = "fixed_2")

  expect_true(p_pat > 0.5 && p_pat < 1.0)
  expect_true(p_port > 0.5 && p_port < 1.0)
  expect_true(p_183 > 0.5 && p_183 < 1.0)
  expect_true(p_sq > 0.5 && p_sq < 1.0)
  # Standard 800 RS / 650 RA is ~60% win expectation
  expect_true(abs(p_pat - 0.60) < 0.05)
})

test_that("pythagenport is robust to zero-run and low-run-environment edge cases (issue #126)", {
  # In production MLB_PYTHAG_EXPONENT (config.R) overrides the method switch
  # entirely, masking this bug. Temporarily clear it so the "pythagenport"
  # branch of calc_pythagorean_win_pct actually executes, as it would if the
  # empirical override were ever absent/NULL.
  old_exp <- MLB_PYTHAG_EXPONENT
  MLB_PYTHAG_EXPONENT <<- NULL
  on.exit(MLB_PYTHAG_EXPONENT <<- old_exp, add = TRUE)

  # 1. 0-0 / 0-game edge case must not be NaN -- falls back to 0.500
  p_zero <- calc_pythagorean_win_pct(rs = 0, ra = 0, games = 0, method = "pythagenport")
  expect_false(is.nan(p_zero))
  expect_equal(p_zero, 0.500, tolerance = 1e-9)

  # 2. Low-run environment (< ~0.5 combined runs/game) must not invert:
  # the team with more runs scored and fewer runs allowed must project
  # at or above .500, not under it.
  p_low <- calc_pythagorean_win_pct(rs = 3, ra = 1, games = 162, method = "pythagenport")
  expect_false(is.nan(p_low))
  expect_true(p_low >= 0.500)
})
