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
source("mlb_cbt_payroll_engine.R")

test_that("compute_cbt_tax() handles NULL/NA/NaN/Inf payroll without erroring (issue #125)", {
  expect_true(is.na(compute_cbt_tax(NA_real_, FALSE)))
  expect_true(is.na(compute_cbt_tax(NaN, FALSE)))
  expect_true(is.na(compute_cbt_tax(Inf, FALSE)))
  expect_true(is.na(compute_cbt_tax(-Inf, FALSE)))
  expect_true(is.na(compute_cbt_tax(NULL, FALSE)))
})

test_that("compute_cbt_tax() treats an NA repeater flag as FALSE with a warning (issue #125)", {
  expect_warning(
    result <- compute_cbt_tax(300, NA),
    "repeater"
  )
  expect_equal(result, compute_cbt_tax(300, FALSE))
})

test_that("compute_cbt_tax() is vectorised over payroll and is_repeater (issue #125)", {
  payrolls <- c(200, 250, 270, NA, Inf, 310)
  reps     <- c(FALSE, FALSE, TRUE, FALSE, TRUE, FALSE)

  result <- compute_cbt_tax(payrolls, reps)
  expect_length(result, length(payrolls))
  expect_equal(result[1], 0.0)          # under threshold
  expect_true(is.na(result[4]))         # NA payroll
  expect_true(is.na(result[5]))         # Inf payroll
  expect_false(is.na(result[6]))        # Tier 4 payroll still computes

  # Scalar input still works (not just vectors)
  expect_equal(compute_cbt_tax(200, FALSE), 0.0)
})

test_that("get_cbt_tier() returns 'Unknown' for NA/NaN/Inf payroll instead of erroring (issue #125)", {
  expect_equal(get_cbt_tier(NA_real_), "Unknown")
  expect_equal(get_cbt_tier(NaN), "Unknown")
  expect_equal(get_cbt_tier(Inf), "Unknown")
  expect_equal(get_cbt_tier(-Inf), "Unknown")
})

test_that("get_cbt_tier() is vectorised and matches expected tier bands (issue #125)", {
  payrolls <- c(200, 250, 270, 290, 310, NA)
  tiers <- get_cbt_tier(payrolls)

  expect_length(tiers, length(payrolls))
  expect_equal(tiers[1], "Under CBT Threshold")
  expect_equal(tiers[2], "Tier 1 Surcharge ($244M-$264M)")
  expect_equal(tiers[3], "Tier 2 Draft Penalty ($264M-$284M)")
  expect_equal(tiers[4], "Tier 3 Cohen Tax ($284M-$304M)")
  expect_equal(tiers[5], "Tier 4 Mega Tax (> $304M)")
  expect_equal(tiers[6], "Unknown")

  # Scalar input still works
  expect_equal(get_cbt_tier(200), "Under CBT Threshold")
})
