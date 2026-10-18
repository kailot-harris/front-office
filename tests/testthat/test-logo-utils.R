# ==============================================================================
# tests/testthat/test-logo-utils.R — Unit Tests for MLB Team Logo Utilities
# ==============================================================================

if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    "c:/Users/kailo/kayceeslices/MLB Analytics"
  }
  setwd(proj_dir)
}

suppPackageStartupMessages <- function(...) suppressPackageStartupMessages(...)

logo_script <- if (file.exists("tools/mlb_logo_utils.R")) {
  "tools/mlb_logo_utils.R"
} else {
  file.path(getwd(), "tools", "mlb_logo_utils.R")
}
source(logo_script)

testthat::test_that("ensure_logo_dir creates or identifies cache/logos directory", {
  dir_path <- ensure_logo_dir()
  testthat::expect_true(dir.exists(dir_path))
})

testthat::test_that("get_team_logo_path returns valid path for existing MLB team", {
  # 158 is Milwaukee Brewers, 147 is NY Yankees
  path_mil <- get_team_logo_path(158)
  testthat::expect_true(!is.null(path_mil))
  testthat::expect_true(file.exists(path_mil))
  testthat::expect_true(file.info(path_mil)$size > 500)
})

testthat::test_that("get_team_logo_path gracefully handles invalid team_id", {
  testthat::expect_null(get_team_logo_path(NA))
  testthat::expect_null(get_team_logo_path(character(0)))
})

testthat::test_that("get_team_logo_grob creates a valid grid rasterGrob", {
  grob <- get_team_logo_grob(158)
  testthat::expect_true(inherits(grob, "rastergrob") || inherits(grob, "grob"))
})

testthat::test_that("gif_elo_trajectories exists and generated artifact is valid", {
  source("tools/gif_elo_trajectories.R")
  testthat::expect_true(is.function(generate_gif_elo_trajectories))
  
  gif_file <- cache_path("viz", "elo_trajectories_2026.gif")
  if (file.exists(gif_file)) {
    testthat::expect_gt(file.info(gif_file)$size, 50000) # greater than 50 KB
  }
})

