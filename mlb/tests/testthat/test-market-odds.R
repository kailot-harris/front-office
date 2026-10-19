if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    "c:/Users/kailo/kayceeslices/MLB Analytics"
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
})

source("logging_utils.R")
source("config.R")
source("mlb_market_odds_engine.R")

test_that("American and decimal odds conversions are exact and reversible", {
  # +100 is 2.00 decimal and 0.50 prob
  expect_equal(american_to_decimal(100), 2.00)
  expect_equal(american_to_prob(100), 0.50)
  expect_equal(prob_to_american(0.50), -100)

  # +150 is 2.50 decimal and 0.40 prob
  expect_equal(american_to_decimal(150), 2.50)
  expect_equal(american_to_prob(150), 0.40)
  expect_equal(prob_to_american(0.40), 150)

  # -200 is 1.50 decimal and 0.6667 prob
  expect_equal(american_to_decimal(-200), 1.50)
  expect_equal(american_to_prob(-200), 2/3, tolerance = 1e-4)
  expect_equal(prob_to_american(2/3), -200)
})

test_that("Fractional Kelly staking respects edge direction and caps", {
  # Positive EV: model prob 0.60 on +100 odds (decimal 2.0)
  # Full Kelly: (1 * 0.60 - 0.40) / 1 = 0.20 (20%)
  # Quarter Kelly: 0.20 * 0.25 = 0.05 (5.0%) -> capped at max_cap_pct (3.0%)
  stake_cap <- calculate_kelly(prob = 0.60, decimal_odds = 2.0, fraction = 0.25, max_cap_pct = 3.0)
  expect_equal(stake_cap, 3.0)

  # Small edge: model prob 0.52 on +100 odds (decimal 2.0)
  # Full Kelly: (1 * 0.52 - 0.48) / 1 = 0.04 (4.0%)
  # Quarter Kelly: 0.04 * 0.25 = 0.01 (1.0%)
  stake_small <- calculate_kelly(prob = 0.52, decimal_odds = 2.0, fraction = 0.25, max_cap_pct = 3.0)
  expect_equal(stake_small, 1.0)

  # Zero / Negative EV: model prob 0.45 on +100 odds -> stake must be 0%
  stake_zero <- calculate_kelly(prob = 0.45, decimal_odds = 2.0, fraction = 0.25, max_cap_pct = 3.0)
  expect_equal(stake_zero, 0.0)
})

test_that("MLB team resolution handles abbreviations, nicknames, and full names", {
  expect_equal(resolve_team_name("NYY"), "New York Yankees")
  expect_equal(resolve_team_name("yankees"), "New York Yankees")
  expect_equal(resolve_team_name("Dodgers"), "Los Angeles Dodgers")
  expect_equal(resolve_team_name("LAD"), "Los Angeles Dodgers")
  expect_equal(resolve_team_name("Athletics"), "Athletics")
})
