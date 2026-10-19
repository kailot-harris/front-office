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
source("mlb_id_crosswalk.R")

test_that("query_id_crosswalk rejects invalid schemes and retrieves cached players", {
  expect_error(query_id_crosswalk("invalid_scheme", "12345"), "Invalid id_scheme")

  cw_file <- cache_path("id_crosswalk", "mlb_id_crosswalk.rds", create = FALSE)
  if (file.exists(cw_file)) {
    cw <- readRDS(cw_file)
    expect_true(is.data.frame(cw))
    expect_true(all(c("mlb_id", "fangraphs_id", "bref_id", "retro_id", "espn_id") %in% names(cw)))
    expect_true(nrow(cw) > 1000)

    # Search for Aaron Judge MLBAM ID 592450
    judge <- query_id_crosswalk("mlb_id", "592450", crosswalk = cw)
    if (nrow(judge) > 0) {
      expect_equal(judge$last_name[1], "Judge")
      expect_true(!is.na(judge$fangraphs_id[1]))
    }
  }
})
