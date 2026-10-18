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
source("mlb_elo_engine.R")

test_that("Elo parameter resolution and Tangotiger game score calculation behave correctly", {
  params <- get_elo_params()
  expect_true(is.numeric(params$hfa))
  expect_true(params$hfa > 0)
  expect_true(is.numeric(params$pitcher_blend_coef))
  expect_true(params$pitcher_blend_coef > 0)

  # Average start: 6 IP (18 outs), 5 H, 2 R, 2 BB, 5 K, 1 HR
  # GS = 47.4 + 5 + 1.5*18 - 2*2 - 2*5 - 3*2 - 4*1
  #    = 47.4 + 5 + 27 - 4 - 10 - 6 - 4 = 55.4
  gs_avg <- calc_pitcher_game_score(
    k = 5, outs = 18, bb = 2, h = 5, r = 2, hr = 1,
    weights = params$gs_weights, park_factor = 100
  )
  expect_equal(gs_avg, 55.4, tolerance = 1e-4)

  # Dominant start (shutout, 10 K): 9 IP (27 outs), 2 H, 0 R, 0 BB, 10 K, 0 HR
  # GS = 47.4 + 10 + 1.5*27 - 0 - 4 - 0 - 0 = 93.9
  gs_dom <- calc_pitcher_game_score(
    k = 10, outs = 27, bb = 0, h = 2, r = 0, hr = 0,
    weights = params$gs_weights, park_factor = 100
  )
  expect_true(gs_dom > 90)
  expect_true(gs_dom > gs_avg)

  # Hitter park adjustment (e.g. Coors Field PF = 115) rewards pitcher
  gs_coors <- calc_pitcher_game_score(
    k = 5, outs = 18, bb = 2, h = 5, r = 2, hr = 1,
    weights = params$gs_weights, park_factor = 115
  )
  expect_true(gs_coors > gs_avg)
})

test_that("Elo win probability formula behaves symmetrically and monotonically", {
  # Even matchup
  diff_0 <- 0
  prob_even <- 1 / (1 + 10^(-diff_0 / 400))
  expect_equal(prob_even, 0.50, tolerance = 1e-4)

  # 100 point favorite
  diff_100 <- 100
  prob_fav <- 1 / (1 + 10^(-diff_100 / 400))
  prob_dog <- 1 / (1 + 10^(-(-100) / 400))
  expect_equal(prob_fav + prob_dog, 1.0, tolerance = 1e-4)
  expect_true(prob_fav > 0.60 && prob_fav < 0.70)
})
