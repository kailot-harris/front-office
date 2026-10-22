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
  library(dplyr)
})

source("logging_utils.R")
source("config.R")
source("mlb_postseason_simulator.R")

# export_web_data.R setwd()s to PROJECT_DIR when that global is already set, and
# the engines above seed it with a legacy absolute path. Pin it to this checkout
# so the exporter's relative source() calls resolve here. It has to go into the
# global environment, which is where source() evaluates the script.
assign("PROJECT_DIR", getwd(), envir = globalenv())
source("tools/export_web_data.R")

# ------------------------------------------------------------------------------
# Fixtures
#
# Three Monday-anchored weeks. The season's first game is Wed 2026-03-25, so week 1
# is the Mon 2026-03-23 week. Walk-forward probabilities are chosen so the grading
# outcome of every completed game is known by hand.
# ------------------------------------------------------------------------------

make_schedule_fixture <- function() {
  tibble::tribble(
    ~game_pk, ~official_date, ~game_type, ~status_detailed_state, ~series_description, ~venue_name, ~home_team_id, ~away_team_id, ~home_team_name,       ~away_team_name,       ~home_score, ~away_score,
    # --- Week 1 (Mon 2026-03-23 .. Sun 2026-03-29) -----------------------------
    1001L,    "2026-03-25",   "R",        "Final",                "Regular Season",    "Yankee Stadium", 147L,      111L,          "New York Yankees",    "Boston Red Sox",      5L,          2L,
    1002L,    "2026-03-29",   "R",        "Final",                "Regular Season",    "Camden Yards",   110L,      141L,          "Baltimore Orioles",   "Toronto Blue Jays",   1L,          4L,
    # --- Week 2 (Mon 2026-03-30 .. Sun 2026-04-05) -----------------------------
    1003L,    "2026-03-30",   "R",        "Final",                "Regular Season",    "Fenway Park",    111L,      147L,          "Boston Red Sox",      "New York Yankees",    3L,          7L,
    1004L,    "2026-04-05",   "R",        "Final",                "Regular Season",    "Rogers Centre",  141L,      110L,          "Toronto Blue Jays",   "Baltimore Orioles",   6L,          0L,
    # A postponed row sharing a game_pk with its makeup: the played row must win.
    1005L,    "2026-04-01",   "R",        "Postponed",            "Regular Season",    "Yankee Stadium", 147L,      110L,          "New York Yankees",    "Baltimore Orioles",   NA_integer_, NA_integer_,
    1005L,    "2026-04-02",   "R",        "Final",                "Regular Season",    "Yankee Stadium", 147L,      110L,          "New York Yankees",    "Baltimore Orioles",   2L,          1L,
    # --- Week 3 (Mon 2026-04-06 .. Sun 2026-04-12): not played yet -------------
    1006L,    "2026-04-08",   "R",        "Scheduled",            "Regular Season",    "Fenway Park",    111L,      141L,          "Boston Red Sox",      "Toronto Blue Jays",   NA_integer_, NA_integer_,
    # Excluded game types: spring training and the All-Star Game are not season games.
    9001L,    "2026-03-10",   "S",        "Final",                "Spring Training",   "Ed Smith",       110L,      147L,          "Baltimore Orioles",   "New York Yankees",    3L,          2L,
    9002L,    "2026-07-14",   "A",        "Final",                "MLB All-Star Game", "Truist Park",    144L,      147L,          "Atlanta Braves",      "New York Yankees",    4L,          3L
  )
}

make_elo_fixture <- function() {
  tibble::tribble(
    ~game_pk, ~game_date,              ~home_team_id, ~away_team_id, ~home_score, ~away_score, ~home_won, ~home_win_prob,
    # Favored home team won  -> correct
    1001L,    "2026-03-25T23:05:00Z",  147L,          111L,          5L,          2L,          1,         0.61,
    # Favored home team lost  -> incorrect
    1002L,    "2026-03-29T17:10:00Z",  110L,          141L,          1L,          4L,          0,         0.55,
    # Underdog home team lost -> correct (model favored the away side)
    1003L,    "2026-03-30T23:10:00Z",  111L,          147L,          3L,          7L,          0,         0.44,
    # Underdog home team won  -> incorrect
    1004L,    "2026-04-05T17:07:00Z",  141L,          110L,          6L,          0L,          1,         0.47,
    # Suspended-and-resumed game recorded twice; the earliest row is the real
    # pre-game prediction and must be the one used.
    1005L,    "2026-04-02T22:00:00Z",  147L,          110L,          2L,          1L,          1,         0.58,
    1005L,    "2026-04-03T18:00:00Z",  147L,          110L,          2L,          1L,          1,         0.33
  )
}

make_ratings_fixture <- function() {
  tibble::tribble(
    ~team_id, ~team_name,            ~elo_rating,
    147L,     "New York Yankees",    1550,
    111L,     "Boston Red Sox",      1500,
    110L,     "Baltimore Orioles",   1490,
    141L,     "Toronto Blue Jays",   1510
  )
}

build_fixture_dataset <- function() {
  build_matchup_slates(
    schedule     = make_schedule_fixture(),
    elo_history  = make_elo_fixture(),
    team_ratings = make_ratings_fixture(),
    season       = 2026
  )
}

# ------------------------------------------------------------------------------
# Week math
# ------------------------------------------------------------------------------

test_that("weeks are Monday-anchored", {
  # 2026-03-25 is a Wednesday; its week starts Monday 2026-03-23.
  expect_equal(monday_of_week(as.Date("2026-03-25")), as.Date("2026-03-23"))
  # A Monday is its own anchor; a Sunday belongs to the preceding Monday.
  expect_equal(monday_of_week(as.Date("2026-03-23")), as.Date("2026-03-23"))
  expect_equal(monday_of_week(as.Date("2026-03-29")), as.Date("2026-03-23"))

  anchor <- as.Date("2026-03-23")
  expect_equal(compute_season_week(as.Date("2026-03-23"), anchor), 1L)
  expect_equal(compute_season_week(as.Date("2026-03-29"), anchor), 1L)
  expect_equal(compute_season_week(as.Date("2026-03-30"), anchor), 2L)
  expect_equal(compute_season_week(as.Date("2026-04-05"), anchor), 2L)
  expect_equal(compute_season_week(as.Date("2026-04-06"), anchor), 3L)

  # Vectorized, and stable across a daylight-saving boundary (US DST: 2026-03-08).
  expect_equal(
    compute_season_week(as.Date(c("2026-03-25", "2026-04-02", "2026-04-08")), anchor),
    c(1L, 2L, 3L)
  )
})

test_that("slate labels describe the week's date range", {
  expect_equal(format_week_label(as.Date("2026-03-30")), "Mar 30 - Apr 5")
  expect_equal(format_week_label(as.Date("2026-03-23")), "Mar 23 - Mar 29")
})

# ------------------------------------------------------------------------------
# Grading
# ------------------------------------------------------------------------------

test_that("grade_matchup_prediction compares the favored side to the winner", {
  # Home favored (p > 0.5) and home won -> correct.
  expect_true(grade_matchup_prediction(0.61, 1))
  # Home favored and home lost -> incorrect.
  expect_false(grade_matchup_prediction(0.55, 0))
  # Away favored (p < 0.5) and home lost -> correct.
  expect_true(grade_matchup_prediction(0.44, 0))
  # Away favored and home won -> incorrect.
  expect_false(grade_matchup_prediction(0.47, 1))

  # Ungraded when either input is missing.
  expect_true(is.na(grade_matchup_prediction(NA_real_, 1)))
  expect_true(is.na(grade_matchup_prediction(0.6, NA_real_)))

  # Vectorized.
  expect_equal(
    grade_matchup_prediction(c(0.61, 0.55, 0.44, 0.47), c(1, 0, 0, 1)),
    c(TRUE, FALSE, TRUE, FALSE)
  )
})

test_that("completed games are graded from the walk-forward probability", {
  d <- build_fixture_dataset()
  graded <- dplyr::filter(d$matchups, !is.na(.data$prediction_correct))
  elo <- make_elo_fixture()
  elo <- elo[!duplicated(elo$game_pk), ]

  expect_equal(nrow(graded), 5L)

  joined <- merge(graded, elo, by = "game_pk", suffixes = c("", "_elo"))
  # The exported probability IS the walk-forward number, not a recomputation.
  expect_equal(joined$home_win_prob, joined$home_win_prob_elo, tolerance = 1e-9)
  # And the grade is exactly the documented invariant.
  expect_equal(
    joined$prediction_correct,
    (joined$home_win_prob_elo > 0.5) == (joined$home_won == 1)
  )

  by_pk <- function(pk, field) d$matchups[[field]][d$matchups$game_pk == pk]
  expect_true(by_pk(1001L, "prediction_correct"))
  expect_false(by_pk(1002L, "prediction_correct"))
  expect_true(by_pk(1003L, "prediction_correct"))
  expect_false(by_pk(1004L, "prediction_correct"))
  # Earliest Elo row (0.58) is used for the resumed game, not the later 0.33.
  expect_equal(by_pk(1005L, "home_win_prob"), 0.58)
  expect_true(by_pk(1005L, "prediction_correct"))

  expect_equal(d$graded_games, 5L)
  expect_equal(d$correct_picks, 3L)
  expect_equal(d$overall_accuracy, round(3 / 5, 4))
})

test_that("games without a walk-forward probability are projected, not graded", {
  d <- build_fixture_dataset()
  pending <- dplyr::filter(d$matchups, .data$game_pk == 1006L)

  expect_equal(nrow(pending), 1L)
  expect_false(pending$is_completed)
  expect_true(is.na(pending$prediction_correct))
  expect_equal(pending$projection_source, "current_elo")
  # A forward projection still exists, derived from current Elo.
  expect_false(is.na(pending$home_win_prob))
  expect_gt(pending$home_win_prob, 0)
  expect_lt(pending$home_win_prob, 1)
  # No score fields leak onto an unplayed game.
  expect_true(is.na(pending$home_score))
  expect_true(is.na(pending$away_score))

  # Completed games carry the walk-forward projection instead.
  completed <- dplyr::filter(d$matchups, .data$is_completed)
  expect_true(all(completed$projection_source == "walk_forward"))
})

# ------------------------------------------------------------------------------
# Slate grouping / coverage
# ------------------------------------------------------------------------------

test_that("every season game lands in exactly one slate", {
  d <- build_fixture_dataset()

  # Six distinct season games; the postponed duplicate collapses onto its makeup.
  expect_equal(nrow(d$matchups), 6L)
  expect_equal(d$total_games, 6L)
  expect_false(any(duplicated(d$matchups$game_pk)))
  expect_setequal(d$matchups$game_pk, c(1001L, 1002L, 1003L, 1004L, 1005L, 1006L))

  # Non-season game types are excluded.
  expect_false(any(c(9001L, 9002L) %in% d$matchups$game_pk))

  # No game is dropped or double-counted across slates.
  expect_equal(sum(d$available_weeks$game_count), nrow(d$matchups))
  expect_false(any(is.na(d$matchups$week)))

  # The makeup date (2026-04-02), not the postponed date, sets the slate.
  expect_equal(d$matchups$game_date[d$matchups$game_pk == 1005L], "2026-04-02")

  expect_equal(d$matchups$week[d$matchups$game_pk == 1001L], 1L)
  expect_equal(d$matchups$week[d$matchups$game_pk == 1002L], 1L)
  expect_equal(d$matchups$week[d$matchups$game_pk == 1003L], 2L)
  expect_equal(d$matchups$week[d$matchups$game_pk == 1005L], 2L)
  expect_equal(d$matchups$week[d$matchups$game_pk == 1006L], 3L)
})

test_that("slate statuses are past / active / future around the latest result", {
  d <- build_fixture_dataset()

  # Latest Elo result is 2026-04-05 (week 2), so week 2 is the active slate.
  expect_equal(d$active_week, 2L)
  expect_equal(d$available_weeks$week, c(1L, 2L, 3L))
  expect_equal(d$available_weeks$status, c("past", "active", "future"))
  expect_true(all(d$available_weeks$status %in% c("past", "active", "future")))

  expect_equal(d$available_weeks$label,
               c("Mar 23 - Mar 29", "Mar 30 - Apr 5", "Apr 6 - Apr 12"))

  # Per-slate accuracy counters back the "X / Y correct" readout.
  wk1 <- dplyr::filter(d$available_weeks, .data$week == 1L)
  expect_equal(wk1$game_count, 2L)
  expect_equal(wk1$graded_count, 2L)
  expect_equal(wk1$correct_count, 1L)

  wk3 <- dplyr::filter(d$available_weeks, .data$week == 3L)
  expect_equal(wk3$graded_count, 0L)
})

test_that("the dataset exposes the documented top-level shape", {
  d <- build_fixture_dataset()

  expect_true(all(c("active_week", "available_weeks", "matchups") %in% names(d)))
  expect_true(all(c("week", "label", "status") %in% names(d$available_weeks)))
  expect_true(all(
    c("game_pk", "game_date", "week", "home_team_id", "home_team_name",
      "away_team_id", "away_team_name", "is_completed", "home_win_prob",
      "home_score", "away_score", "prediction_correct") %in% names(d$matchups)
  ))
  expect_type(d$active_week, "integer")
  expect_type(d$matchups$is_completed, "logical")
  expect_type(d$matchups$prediction_correct, "logical")
})
