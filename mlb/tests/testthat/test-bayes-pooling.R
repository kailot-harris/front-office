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
  expect_true(test_shrinkage_monotonicity())
})
