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
  library(jsonlite)
})

source("logging_utils.R")
source("config.R")

# export_web_data.R setwd()s to PROJECT_DIR when that global is already set, so
# pin it to this checkout before sourcing -- same reason as test-matchup-slates.R.
assign("PROJECT_DIR", getwd(), envir = globalenv())
source("tools/export_web_data.R")

# ------------------------------------------------------------------------------
# build_value_bets_payload() -- the provenance gate on the web export path.
#
# Companion to test-notify-provenance.R. The notifier gate stops fabricated bets
# reaching Discord; this one stops them reaching web/public/data, which is the
# path with a route to the live site. The assertions run against the exported
# JSON (not just the R list) because serialization is where a single surviving
# row would actually become published advice.
#
# Fixtures are built in-test; nothing reads cache/, so this runs in CI.
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

# Round-trips the payload the way run_web_export() writes it, so the assertions
# see what the browser would fetch rather than the in-memory list.
exported <- function(bets_df) {
  payload <- build_value_bets_payload(bets_df)
  obj <- list(
    season = 2026L, n_sims = 10000L,
    value_bets = payload$value_bets,
    value_bets_provenance = payload$value_bets_provenance
  )
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  jsonlite::write_json(obj, f, pretty = TRUE, auto_unbox = TRUE)
  jsonlite::fromJSON(f, simplifyVector = FALSE)
}

test_that("live bets are published and counted", {
  j <- exported(make_bet("LIVE_ODDS_API"))
  expect_length(j$value_bets, 1)
  expect_equal(j$value_bets[[1]]$market_data_source, "LIVE_ODDS_API")
  expect_equal(j$value_bets_provenance$n_total, 1)
  expect_equal(j$value_bets_provenance$n_published, 1)
  expect_equal(j$value_bets_provenance$n_withheld, 0)
  expect_length(j$value_bets_provenance$withheld_sources, 0)
})

test_that("a mixed slate publishes only the live row and names what it withheld", {
  j <- exported(dplyr::bind_rows(
    make_bet("LIVE_ODDS_API"),
    make_bet("SYNTHETIC_FALLBACK", "Chicago Cubs")
  ))
  expect_length(j$value_bets, 1)
  expect_equal(j$value_bets[[1]]$away_team, "Tampa Bay Rays")
  expect_equal(j$value_bets_provenance$n_total, 2)
  expect_equal(j$value_bets_provenance$n_published, 1)
  expect_equal(j$value_bets_provenance$n_withheld, 1)
  expect_equal(unlist(j$value_bets_provenance$withheld_sources), "SYNTHETIC_FALLBACK")
})

test_that("the 2026-10-25 incident shape publishes nothing at all", {
  # Six SYNTHETIC_FALLBACK rows on eliminated teams -- the exact state the
  # scheduled pipeline wrote into the cache that day.
  teams <- c("Chicago Cubs", "St. Louis Cardinals", "Los Angeles Dodgers",
             "New York Yankees", "Atlanta Braves", "Baltimore Orioles")
  j <- exported(dplyr::bind_rows(lapply(teams, function(t) make_bet("SYNTHETIC_FALLBACK", t))))
  expect_length(j$value_bets, 0)
  expect_equal(j$value_bets_provenance$n_total, 6)
  expect_equal(j$value_bets_provenance$n_withheld, 6)
  expect_equal(unlist(j$value_bets_provenance$withheld_sources), "SYNTHETIC_FALLBACK")
})

test_that("a missing market_data_source column fails closed", {
  j <- exported(make_bet(NULL))
  expect_length(j$value_bets, 0)
  expect_equal(j$value_bets_provenance$n_withheld, 1)
  expect_equal(unlist(j$value_bets_provenance$withheld_sources), "<missing>")
})

test_that("an NA provenance fails closed", {
  j <- exported(make_bet(NA_character_))
  expect_length(j$value_bets, 0)
  expect_equal(j$value_bets_provenance$n_withheld, 1)
  expect_equal(unlist(j$value_bets_provenance$withheld_sources), "<missing>")
})

test_that("an unrecognised provenance fails closed rather than being assumed live", {
  j <- exported(make_bet("LIVE_ODDS_API_V2"))
  expect_length(j$value_bets, 0)
  expect_equal(j$value_bets_provenance$n_withheld, 1)
  expect_equal(unlist(j$value_bets_provenance$withheld_sources), "LIVE_ODDS_API_V2")
})

test_that("an empty or absent cache yields an empty array and a zeroed report", {
  for (empty in list(data.frame(), make_bet("LIVE_ODDS_API")[0, , drop = FALSE], NULL)) {
    j <- exported(empty)
    expect_length(j$value_bets, 0)
    expect_equal(j$value_bets_provenance$n_total, 0)
    expect_equal(j$value_bets_provenance$n_withheld, 0)
  }
})

test_that("the exporter and the notifier share one gate implementation", {
  # Two copies of this decision would drift silently. market_provenance.R is the
  # only definition; this asserts the exporter is really using it.
  expect_true(is.function(filter_live_provenance))
  expect_equal(LIVE_PROVENANCE, "LIVE_ODDS_API")
  expect_true(any(grepl('source("market_provenance.R")',
                        readLines("mlb_notify_bets.R", warn = FALSE), fixed = TRUE)))
  expect_true(any(grepl('source("market_provenance.R")',
                        readLines("tools/export_web_data.R", warn = FALSE), fixed = TRUE)))
})
