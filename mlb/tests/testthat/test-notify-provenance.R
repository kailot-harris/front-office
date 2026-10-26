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
  library(dplyr)
})

source("logging_utils.R")
source("config.R")
source("mlb_notify_bets.R")

# ------------------------------------------------------------------------------
# Provenance gate -- filter_live_provenance() and run_notify_bets()
#
# Regression guard for 2026-10-25, when mlb_market_odds_engine.R's synthetic
# fallback put six invented bets into the value-bets cache -- invented game_ids
# and prices, on teams already eliminated -- and the dispatcher broadcast three
# of them to Discord. The rows were labelled SYNTHETIC_FALLBACK; nothing read the
# label.
#
# The gate itself is asserted directly on the pure function. The two end-to-end
# tests additionally blank every webhook path, so even a total gate failure can
# only reach the console-preview branch -- a bug here must not be able to post
# anywhere. Fixtures are built in-test; nothing reads cache/, so this runs in CI.
# ------------------------------------------------------------------------------

# source = NULL builds a row with the column absent entirely, which is a
# different (and also untrusted) case from the column being present but NA.
make_bet <- function(source, team = "Tampa Bay Rays", ev = 13.6) {
  drop_col <- is.null(source)
  if (drop_col) source <- NA_character_
  df <- data.frame(
    game_id = "TEST_GAME_1", home_team = "Milwaukee Brewers", away_team = team,
    market = "h2h", bet_on = team, bookmaker = "TestBook", odds = 150,
    model_prob = 0.45, ev = ev, kelly_stake = 2,
    market_data_source = source, game_date = "2026-10-23",
    Matchup = paste(team, "@ Milwaukee Brewers"),
    Recommended_Bet = paste(team, "Moneyline"), Team = team, Book = "TestBook",
    Line = 150, Model_Win_Prob = 0.45, EV_Percent = ev, Exp_CLV = -0.2,
    Bankroll_Rec = 2, Status = NA_character_,
    stringsAsFactors = FALSE
  )
  if (drop_col) df$market_data_source <- NULL
  df
}

# --- the gate, asserted directly -------------------------------------------

test_that("live bets pass the gate untouched", {
  g <- filter_live_provenance(make_bet("LIVE_ODDS_API"))
  expect_equal(nrow(g$kept), 1L)
  expect_equal(g$n_dropped, 0L)
})

test_that("synthetic bets are dropped and reported", {
  g <- filter_live_provenance(rbind(
    make_bet("LIVE_ODDS_API"),
    make_bet("SYNTHETIC_FALLBACK", "Chicago Cubs")
  ))
  expect_equal(nrow(g$kept), 1L)
  expect_equal(g$kept$market_data_source, "LIVE_ODDS_API")
  expect_equal(g$n_dropped, 1L)
  expect_equal(g$dropped_sources, "SYNTHETIC_FALLBACK")
})

test_that("an all-synthetic slate leaves nothing to send", {
  g <- filter_live_provenance(rbind(
    make_bet("SYNTHETIC_FALLBACK"),
    make_bet("SYNTHETIC_FALLBACK", "Chicago Cubs")
  ))
  expect_equal(nrow(g$kept), 0L)
  expect_equal(g$n_dropped, 2L)
})

test_that("a missing market_data_source column fails closed", {
  g <- filter_live_provenance(make_bet(NULL))
  expect_equal(nrow(g$kept), 0L)
  expect_equal(g$dropped_sources, "<missing>")
})

test_that("an NA provenance value fails closed", {
  g <- filter_live_provenance(make_bet(NA_character_))
  expect_equal(nrow(g$kept), 0L)
  expect_equal(g$dropped_sources, "<missing>")
})

test_that("an unrecognised provenance value fails closed", {
  g <- filter_live_provenance(make_bet("MODEL_ONLY"))
  expect_equal(nrow(g$kept), 0L)
  expect_equal(g$dropped_sources, "MODEL_ONLY")
})

test_that("an empty slate is handled without error", {
  g <- filter_live_provenance(make_bet("LIVE_ODDS_API")[0, , drop = FALSE])
  expect_equal(g$n_before, 0L)
  expect_equal(g$n_dropped, 0L)
})

# --- end to end, with every webhook path blanked ----------------------------

with_blanked_webhook <- function(df, expr) {
  f <- tempfile(fileext = ".rds")
  saveRDS(df, f)
  old_webhook <- Sys.getenv("MLB_DISCORD_WEBHOOK", unset = NA)
  had_global <- exists("MLB_DISCORD_WEBHOOK", envir = globalenv())
  old_global <- if (had_global) get("MLB_DISCORD_WEBHOOK", envir = globalenv()) else NULL

  Sys.setenv(MLB_DISCORD_WEBHOOK = "", DISCORD_WEBHOOK_URL = "")
  assign("MLB_DISCORD_WEBHOOK", "", envir = globalenv())
  assign("CACHE_LATEST_VALUE_BETS", f, envir = globalenv())
  Sys.unsetenv("MLB_NOTIFY_ALLOW_SYNTHETIC")

  on.exit({
    if (!is.na(old_webhook)) Sys.setenv(MLB_DISCORD_WEBHOOK = old_webhook) else Sys.unsetenv("MLB_DISCORD_WEBHOOK")
    if (had_global) assign("MLB_DISCORD_WEBHOOK", old_global, envir = globalenv())
    if (exists("CACHE_LATEST_VALUE_BETS", envir = globalenv())) rm("CACHE_LATEST_VALUE_BETS", envir = globalenv())
    unlink(f)
  }, add = TRUE)

  force(expr)
}

test_that("run_notify_bets() declines an all-synthetic slate and still reports success", {
  # TRUE, not FALSE: refusing to send fabricated advice is the stage working.
  # Returning FALSE would fail the pipeline and train everyone to ignore it.
  res <- suppressMessages(capture.output(
    r <- with_blanked_webhook(make_bet("SYNTHETIC_FALLBACK"), run_notify_bets())
  ))
  expect_true(r)
})

test_that("run_notify_bets() still proceeds when a live bet is present", {
  res <- suppressMessages(capture.output(
    r <- with_blanked_webhook(make_bet("LIVE_ODDS_API"), run_notify_bets())
  ))
  expect_true(r)
})
