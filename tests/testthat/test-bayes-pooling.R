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
source("tools/evaluate_bayes_shrinkage.R")

test_that("Empirical Bayes shrinkage strictly adheres to theoretical monotonicity", {
  # test_shrinkage_monotonicity() runs five checks in one call; the first two
  # are closed-form and need nothing, but tests 3-5 read the pooled caches and
  # the function regenerates them from the FanGraphs caches when they are
  # absent — which is what fails in CI. Splitting the theoretical half out
  # would mean refactoring tools/evaluate_bayes_shrinkage.R, so the whole block
  # skips together. See helper-common.R.
  skip_if_no_cache("specialty", "bayes_pooled_batters.rds",
                   "bayes_pooled_pitchers.rds", "bayes_team_talent.rds")

  expect_true(test_shrinkage_monotonicity())
})
