if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    getwd()
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

source("tools/refresh_live_results.R")

# ------------------------------------------------------------------------------
# Fixtures
#
# A two-week slate directory written to a tempdir, plus a stub MLB Stats API
# response. Nothing here touches the network or the pipeline caches — that is
# the whole point of this script, so the tests hold the same line.
# ------------------------------------------------------------------------------

make_row <- function(game_pk, date, week, type, home, away, home_score = NA,
                     away_score = NA, completed = FALSE, status = "Scheduled") {
  data.frame(
    game_pk            = as.integer(game_pk),
    game_date          = date,
    week               = as.integer(week),
    game_type          = type,
    series_description = if (type == "W") "World Series" else "Regular Season",
    status_detail      = status,
    venue_name         = if (home == "MIL") "American Family Field" else "Tropicana Field",
    home_team_id       = if (home == "MIL") 158L else 139L,
    home_team_name     = if (home == "MIL") "Milwaukee Brewers" else "Tampa Bay Rays",
    home_team          = home,
    away_team_id       = if (away == "MIL") 158L else 139L,
    away_team_name     = if (away == "MIL") "Milwaukee Brewers" else "Tampa Bay Rays",
    away_team          = away,
    is_completed       = completed,
    home_win_prob      = 0.5712,
    away_win_prob      = 0.4288,
    projection_source  = "current_elo",
    home_score         = as.integer(home_score),
    away_score         = as.integer(away_score),
    prediction_correct = NA,
    stringsAsFactors   = FALSE
  )
}

write_fixture_data_dir <- function() {
  dir <- file.path(tempdir(), paste0("refresh-test-", as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(dir, "matchups"), recursive = TRUE, showWarnings = FALSE)

  wk31 <- rbind(
    make_row(1L, "2026-10-23", 31, "W", "MIL", "TB", 3, 2, TRUE, "Final"),
    make_row(2L, "2026-10-24", 31, "W", "MIL", "TB")
  )
  wk32 <- rbind(
    make_row(3L, "2026-10-26", 32, "W", "TB", "MIL"),
    make_row(4L, "2026-10-27", 32, "W", "TB", "MIL")
  )
  write_json(wk31, file.path(dir, "matchups", "week-31.json"),
             pretty = FALSE, auto_unbox = TRUE, na = "null")
  write_json(wk32, file.path(dir, "matchups", "week-32.json"),
             pretty = FALSE, auto_unbox = TRUE, na = "null")

  index <- list(
    season = 2026L, generated_at = "2026-10-25T00:00:00Z", active_week = 31L,
    total_games = 4L, completed_games = 1L, graded_games = 0L, correct_picks = 0L,
    overall_accuracy = NULL,
    available_weeks = list(
      list(week = 31L, label = "Oct 19-25", status = "active",
           start_date = "2026-10-19", end_date = "2026-10-25",
           game_count = 2L, graded_count = 0L, correct_count = 0L),
      list(week = 32L, label = "Oct 26 - Nov 1", status = "future",
           start_date = "2026-10-26", end_date = "2026-11-01",
           game_count = 2L, graded_count = 0L, correct_count = 0L)
    )
  )
  write_json(index, file.path(dir, "matchups_index.json"),
             pretty = TRUE, auto_unbox = TRUE, na = "null")
  dir
}

# Stub API: game 2 finished 5-4, game 3 is live (not final), game 4 untouched.
stub_reader <- function(...) {
  function(url) {
    list(dates = list(
      list(games = list(
        list(gamePk = 1, status = list(detailedState = "Final"),
             teams = list(home = list(score = 3), away = list(score = 2))),
        list(gamePk = 2, status = list(detailedState = "Final"),
             teams = list(home = list(score = 5), away = list(score = 4))),
        list(gamePk = 3, status = list(detailedState = "In Progress"),
             teams = list(home = list(score = 1), away = list(score = 0))),
        list(gamePk = 4, status = list(detailedState = "Scheduled"),
             teams = list(home = list(score = NULL), away = list(score = NULL)))
      ))
    ))
  }
}

# ------------------------------------------------------------------------------

test_that("apply_results() fills in finished games and leaves the rest alone", {
  rows <- rbind(
    make_row(2L, "2026-10-24", 31, "W", "MIL", "TB"),
    make_row(3L, "2026-10-26", 32, "W", "TB", "MIL"),
    make_row(4L, "2026-10-27", 32, "W", "TB", "MIL")
  )
  results <- data.frame(
    game_pk = c(2L, 3L, 4L),
    status_detail = c("Final", "In Progress", "Scheduled"),
    home_score = c(5L, 1L, NA_integer_),
    away_score = c(4L, 0L, NA_integer_),
    stringsAsFactors = FALSE
  )

  out <- apply_results(rows, results)

  expect_equal(out$n_changed, 1L)
  expect_true(out$rows$is_completed[1])
  expect_equal(out$rows$home_score[1], 5L)
  expect_equal(out$rows$status_detail[1], "Final")

  # An in-progress game is NOT written in: a mid-game score is not a result.
  expect_false(out$rows$is_completed[2])
  expect_true(is.na(out$rows$home_score[2]))
  expect_equal(out$rows$status_detail[2], "Scheduled")
})

test_that("apply_results() never overwrites a score already recorded", {
  rows <- make_row(1L, "2026-10-23", 31, "W", "MIL", "TB", 3, 2, TRUE, "Final")
  # The API disagrees with the committed file. The committed file wins.
  results <- data.frame(game_pk = 1L, status_detail = "Final",
                        home_score = 99L, away_score = 0L, stringsAsFactors = FALSE)

  out <- apply_results(rows, results)

  expect_equal(out$n_changed, 0L)
  expect_equal(out$rows$home_score[1], 3L)
})

test_that("apply_results() ignores games the committed slates do not contain", {
  rows <- make_row(2L, "2026-10-24", 31, "W", "MIL", "TB")
  results <- data.frame(game_pk = 999L, status_detail = "Final",
                        home_score = 7L, away_score = 1L, stringsAsFactors = FALSE)

  out <- apply_results(rows, results)

  expect_equal(out$n_changed, 0L)
  expect_false(out$rows$is_completed[1])
})

test_that("refresh_live_results() writes scores and rebuilds the series summary", {
  dir <- write_fixture_data_dir()

  res <- refresh_live_results(season = 2026, data_dir = dir,
                              url_reader = stub_reader(),
                              today = as.Date("2026-10-25"))

  expect_equal(res$n_changed, 1L)

  wk31 <- fromJSON(file.path(dir, "matchups", "week-31.json"), simplifyDataFrame = TRUE)
  expect_true(all(wk31$is_completed))
  expect_equal(wk31$home_score[2], 5L)

  ws <- fromJSON(file.path(dir, "world_series.json"), simplifyVector = FALSE)
  expect_equal(ws$status, "in_progress")
  expect_equal(ws$games_played, 2L)
  expect_equal(ws$home_field$team, "MIL")
  expect_equal(ws$home_field$wins, 2L)
  expect_equal(ws$challenger$wins, 0L)

  idx <- fromJSON(file.path(dir, "matchups_index.json"), simplifyVector = FALSE)
  expect_equal(idx$completed_games, 2)
})

test_that("refresh_live_results() is a no-op on a second run", {
  dir <- write_fixture_data_dir()
  refresh_live_results(season = 2026, data_dir = dir, url_reader = stub_reader(),
                       today = as.Date("2026-10-25"))

  before <- vapply(list.files(dir, recursive = TRUE, full.names = TRUE),
                   function(f) paste(readLines(f, warn = FALSE), collapse = ""),
                   character(1))

  second <- refresh_live_results(season = 2026, data_dir = dir, url_reader = stub_reader(),
                                 today = as.Date("2026-10-25"))

  after <- vapply(list.files(dir, recursive = TRUE, full.names = TRUE),
                  function(f) paste(readLines(f, warn = FALSE), collapse = ""),
                  character(1))

  expect_equal(second$n_changed, 0L)
  expect_equal(length(second$files), 0L)
  # Byte-identical, including generated_at: a quiet day must not produce a commit.
  expect_identical(before, after)
})

test_that("refresh_live_results() moves the active week with the date", {
  dir <- write_fixture_data_dir()

  refresh_live_results(season = 2026, data_dir = dir, url_reader = stub_reader(),
                       today = as.Date("2026-10-28"))

  idx <- fromJSON(file.path(dir, "matchups_index.json"), simplifyVector = FALSE)
  expect_equal(idx$active_week, 32)
  expect_equal(idx$available_weeks[[1]]$status, "past")
  expect_equal(idx$available_weeks[[2]]$status, "active")
})

test_that("refresh_live_results() errors loudly when there is no index to patch", {
  empty <- file.path(tempdir(), paste0("refresh-empty-", as.integer(runif(1, 1, 1e6))))
  dir.create(empty, showWarnings = FALSE)

  expect_error(
    refresh_live_results(season = 2026, data_dir = empty, url_reader = stub_reader()),
    "no index at"
  )
})

test_that("fetch_season_results() flattens the API shape it is given", {
  out <- fetch_season_results(2026, stub_reader())

  expect_equal(nrow(out), 4L)
  expect_equal(out$game_pk, 1:4)
  expect_equal(out$status_detail[3], "In Progress")
  expect_true(is.na(out$home_score[4]))
})
