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

test_that("the export splits into an index plus one file per slate", {
  d <- build_fixture_dataset()
  out_dir <- file.path(tempdir(), "matchup-split-test")
  unlink(out_dir, recursive = TRUE)
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  # A combined file from an earlier export must not survive the split.
  legacy <- file.path(out_dir, "matchups_slates.json")
  writeLines("{}", legacy)

  written <- write_matchup_slate_files(d, out_dir)

  expect_false(file.exists(legacy))
  expect_equal(basename(written[1]), "matchups_index.json")
  expect_equal(length(written) - 1L, nrow(d$available_weeks))

  # The index carries the summaries and none of the rows: that is the whole
  # point, since everything in it is serialized into the page's static HTML.
  idx <- jsonlite::read_json(written[1])
  expect_false("matchups" %in% names(idx))
  expect_equal(idx$total_games, nrow(d$matchups))
  expect_equal(length(idx$available_weeks), nrow(d$available_weeks))

  # Zero-padded names, because MatchupsClient builds the URL the same way.
  week_files <- written[-1]
  expect_equal(
    basename(week_files),
    sprintf("week-%02d.json", d$available_weeks$week)
  )

  # Every game appears in exactly one slate file, and nowhere twice.
  rows <- unlist(lapply(week_files, jsonlite::read_json), recursive = FALSE)
  expect_equal(length(rows), nrow(d$matchups))
  pks <- vapply(rows, function(m) as.integer(m$game_pk), integer(1))
  expect_setequal(pks, d$matchups$game_pk)
  expect_false(any(duplicated(pks)))

  # Each file holds only its own week.
  wk1 <- jsonlite::read_json(file.path(out_dir, "matchups", "week-01.json"))
  expect_true(all(vapply(wk1, function(m) m$week, numeric(1)) == 1))
})

# ------------------------------------------------------------------------------
# World Series summary (postseason banner)
# ------------------------------------------------------------------------------

make_ws_matchups_fixture <- function(scores) {
  # Game 1 home club owns home-field advantage; scores is a list of
  # c(home, away) pairs or NA for games not yet played.
  dates <- c("2026-10-23", "2026-10-24", "2026-10-26", "2026-10-27",
             "2026-10-28", "2026-10-30", "2026-10-31")
  home <- c("MIL", "MIL", "TB", "TB", "TB", "MIL", "MIL")
  data.frame(
    game_pk        = 8001:8007,
    game_date      = dates,
    week           = c(31L, 31L, rep(32L, 5)),
    game_type      = rep("W", 7),
    series_description = rep("World Series", 7),
    status_detail  = vapply(scores, function(s) if (all(is.na(s))) "Scheduled" else "Final", character(1)),
    venue_name     = ifelse(home == "MIL", "American Family Field", "Tropicana Field"),
    home_team      = home,
    home_team_name = ifelse(home == "MIL", "Milwaukee Brewers", "Tampa Bay Rays"),
    away_team      = ifelse(home == "MIL", "TB", "MIL"),
    away_team_name = ifelse(home == "MIL", "Tampa Bay Rays", "Milwaukee Brewers"),
    home_score     = vapply(scores, function(s) as.integer(s[1]), integer(1)),
    away_score     = vapply(scores, function(s) as.integer(s[2]), integer(1)),
    is_completed   = vapply(scores, function(s) !all(is.na(s)), logical(1)),
    home_win_prob  = ifelse(home == "MIL", 0.5712, 0.4712),
    stringsAsFactors = FALSE
  )
}

test_that("build_world_series_summary() tallies resolved games", {
  # MIL wins both home games, the rest are unplayed.
  scores <- list(c(3L, 2L), c(5L, 4L), NA, NA, NA, NA, NA)
  ws <- build_world_series_summary(make_ws_matchups_fixture(scores), season = 2026)

  expect_equal(ws$status, "in_progress")
  expect_equal(ws$games_played, 2L)
  expect_equal(ws$games_scheduled, 7L)
  expect_true(is.na(ws$champion))
  expect_equal(ws$home_field$team, "MIL")
  expect_equal(ws$home_field$wins, 2L)
  expect_equal(ws$challenger$team, "TB")
  expect_equal(ws$challenger$wins, 0L)

  expect_equal(ws$games[[1]]$winner, "MIL")
  expect_equal(ws$games[[1]]$game_number, 1)
  expect_true(is.na(ws$games[[3]]$winner))
  expect_true(is.na(ws$games[[3]]$home_score))
})

test_that("build_world_series_summary() crowns a champion at four wins", {
  # TB sweeps games 1-2 on the road and 3-4 at home.
  scores <- list(c(2L, 3L), c(1L, 4L), c(6L, 1L), c(5L, 0L), NA, NA, NA)
  ws <- build_world_series_summary(make_ws_matchups_fixture(scores), season = 2026)

  expect_equal(ws$status, "complete")
  expect_equal(ws$champion, "TB")
  expect_equal(ws$challenger$wins, 4L)
  expect_equal(ws$home_field$wins, 0L)
})

test_that("build_world_series_summary() returns NULL without World Series games", {
  m <- make_ws_matchups_fixture(list(NA, NA, NA, NA, NA, NA, NA))
  m$game_type <- "R"
  expect_null(build_world_series_summary(m, season = 2026))
})

test_that("build_world_series_summary() reports an unplayed series as scheduled", {
  ws <- build_world_series_summary(
    make_ws_matchups_fixture(list(NA, NA, NA, NA, NA, NA, NA)),
    season = 2026
  )
  expect_equal(ws$status, "scheduled")
  expect_equal(ws$games_played, 0L)
})
