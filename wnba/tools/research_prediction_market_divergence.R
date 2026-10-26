# ==============================================================================
# tools/research_prediction_market_divergence.R
#
# Research Next Step #2 from docs/prediction_market_alpha_research_plan.md: measure
# whether real Kalshi KXWNBAGAME pre-game prices diverge from this repo's own
# RETROSPECTIVE (known-inputs-only, no-lookahead) win probability, on real settled
# games. This is the single measurement the plan says determines whether hypothesis
# #1/#2 (buy-and-hold / same-day scalp on mispriced game contracts) have any edge at
# all -- do not add staking/P&L logic on top of this without a real divergence shown
# first (see plan's Next Steps #3).
#
# Side-project research script. NOT part of run_full_pipeline.R's DAG, NOT wired
# into any production file. Public, unauthenticated Kalshi market-data reads only.
#
# Method (mirrors tools/backtest_margin_hyperparams.R's TRACK A, the repo's existing
# leakage-free convention -- reused here rather than re-derived):
#   - "Model" probability = pnorm((home_roll_margin - away_roll_margin + WNBA_HCA) /
#     WNBA_MARGIN_SIGMA), where roll_margin is each team's TRAILING (strictly prior
#     games only, reset per season) rolling point differential over
#     ROLLING_WINDOW_SIZE games -- exactly Track A's leakage-free proxy. NOT
#     predict_live_matchup()/project_all_wnba_teams(): those read the CURRENT
#     active_rosters/rapm_ratings/injury caches, which are today's snapshot, not a
#     point-in-time-correct snapshot for a historical game -- using them here would
#     silently leak future information into a "retrospective" comparison.
#   - apply_rating_limits_param(limit=5.0, dampening=0.1): mirrors
#     market_odds_engine.R::apply_rating_limits()'s Phase-2-confirmed live constants
#     (see that file's own comment for the walk-forward evidence) -- not re-derived
#     here, just reused for consistency with the live model's actual behavior.
#   - "Market" probability = the real Kalshi YES price (mid of last hourly candle's
#     yes_bid/yes_ask close) for the HOME team's side market, at the last candlestick
#     strictly BEFORE that game's scheduled tip-off (box_scores_cache's
#     game_date_time, assumed America/New_York per this repo's existing box-score
#     convention -- confirmed against a real spot-checked game below).
#
# Usage: Rscript.exe tools/research_prediction_market_divergence.R
# ==============================================================================

# GitHub issue #90: PROJECT_ROOT was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("research_prediction_market_divergence.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_ROOT)
source("config.R")

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(purrr)
  library(tibble)
  library(slider)
  library(stringr)
  library(lubridate)
})

KALSHI_BASE <- "https://api.elections.kalshi.com/trade-api/v2"

# Same known Kalshi<->WNBA_TEAMS code divergences as tools/research_prediction_markets.R
# (CONN found from the ticker, PDX found empirically by that script's own overlap
# check). Kept here too since this script does its own independent team-code work
# (city-name matching, not ticker-side-code matching) -- not currently exercised by
# this path, but retained for anyone extending this script to parse ticker codes.
KALSHI_TEAM_CODE_MAP <- c(CONN = "CON", PDX = "POR")

kalshi_get <- function(path, query = list()) {
  resp <- tryCatch(
    request(paste0(KALSHI_BASE, path)) |>
      req_url_query(!!!query) |>
      req_timeout(20) |>
      req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || resp_status(resp) != 200) {
    stop(sprintf("Kalshi API call to %s failed (status: %s).",
                 path, if (is.null(resp)) "no response" else resp_status(resp)))
  }
  resp_body_json(resp, simplifyVector = FALSE)
}

# ------------------------------------------------------------------------------
# 1. Pull ALL settled KXWNBAGAME markets (paginated).
# ------------------------------------------------------------------------------
cat("[1/5] Pulling all settled KXWNBAGAME markets from Kalshi (paginated)...\n")
all_markets <- list()
cursor <- NULL
page <- 0
repeat {
  page <- page + 1
  q <- list(series_ticker = "KXWNBAGAME", status = "settled", limit = 200)
  if (!is.null(cursor) && nchar(cursor) > 0) q$cursor <- cursor
  resp <- kalshi_get("/markets", q)
  all_markets <- c(all_markets, resp$markets)
  cursor <- resp$cursor
  cat(sprintf("      page %d: %d markets (running total %d)\n", page, length(resp$markets), length(all_markets)))
  if (is.null(cursor) || nchar(cursor) == 0 || length(resp$markets) == 0 || page >= 20) break
}
cat(sprintf("      TOTAL: %d settled markets pulled.\n\n", length(all_markets)))

markets_df <- map_dfr(all_markets, function(m) {
  tibble(
    ticker = m$ticker %||% NA_character_,
    event_ticker = m$event_ticker %||% NA_character_,
    yes_sub_title = m$yes_sub_title %||% NA_character_,
    result = m$result %||% NA_character_,
    status = m$status %||% NA_character_,
    open_time = m$open_time %||% NA_character_,
    close_time = m$close_time %||% NA_character_
  )
})
markets_df <- markets_df |> filter(status == "finalized", result %in% c("yes", "no"))
cat(sprintf("      %d finalized markets with a real result.\n\n", nrow(markets_df)))

# ------------------------------------------------------------------------------
# 2. Build the city -> WNBA_TEAMS abbreviation map EMPIRICALLY from box_scores_cache
#    (team_location is city-only, same naming convention as Kalshi's yes_sub_title --
#    confirmed by inspection, not assumed) instead of a separate ad hoc mapping.
# ------------------------------------------------------------------------------
cat("[2/5] Loading real box scores and building city->abbreviation map...\n")
stopifnot(file.exists(CACHE_TEAM_BOX))
box_scores <- readRDS(CACHE_TEAM_BOX)

city_to_abbr <- box_scores |> distinct(team_location, team_abbreviation) |> deframe()
cat(sprintf("      %d distinct (city -> abbr) pairs from box_scores_cache.\n\n", length(city_to_abbr)))

# ------------------------------------------------------------------------------
# 3. Group settled markets into games (2 sides per event_ticker), map each side's
#    city to a WNBA_TEAMS abbreviation, and join to the real completed game in
#    box_scores_cache by (unordered team pair, nearest game_date to the market's
#    close_time). Kalshi's close_time is generally in the early hours UTC of the day
#    AFTER the local game date (game finishes before local midnight, UTC has already
#    rolled over) -- so try close_date and close_date-1 explicitly rather than a
#    fuzzy window, and require a UNIQUE match before accepting it.
# ------------------------------------------------------------------------------
cat("[3/5] Joining Kalshi settled game-events to real box_scores_cache games...\n")

events <- markets_df |>
  mutate(close_date_utc = as.Date(close_time)) |>
  group_by(event_ticker) |>
  filter(n() == 2) |>
  summarise(
    city_a = yes_sub_title[1], ticker_a = ticker[1], result_a = result[1],
    city_b = yes_sub_title[2], ticker_b = ticker[2], result_b = result[2],
    close_date_utc = close_date_utc[1],
    .groups = "drop"
  ) |>
  mutate(
    abbr_a = unname(city_to_abbr[city_a]),
    abbr_b = unname(city_to_abbr[city_b])
  )

unmatched_cities <- events |> filter(is.na(abbr_a) | is.na(abbr_b))
if (nrow(unmatched_cities) > 0) {
  cat(sprintf("      %d events had a city not found in box_scores_cache (likely off-season/preseason exhibitions or a city not yet in a completed game) -- dropped:\n", nrow(unmatched_cities)))
  print(unmatched_cities |> select(event_ticker, city_a, city_b) |> head(10))
}
events <- events |> filter(!is.na(abbr_a), !is.na(abbr_b))

box_games <- box_scores |>
  filter(team_home_away == "home") |>
  transmute(
    game_id, season, game_date, game_date_time,
    home_abbr = team_abbreviation, away_abbr = opponent_team_abbreviation,
    home_score = team_score, away_score = opponent_team_score,
    home_win = team_winner
  )

match_one_event <- function(abbr_a, abbr_b, close_date_utc) {
  cand <- box_games |> filter(
    (home_abbr == abbr_a & away_abbr == abbr_b) | (home_abbr == abbr_b & away_abbr == abbr_a),
    game_date %in% c(close_date_utc, close_date_utc - 1)
  )
  if (nrow(cand) != 1) return(NA_character_)
  cand$game_id[1]
}

events <- events |> rowwise() |> mutate(
  game_id = match_one_event(abbr_a, abbr_b, close_date_utc)
) |> ungroup()

n_before <- nrow(events)
events <- events |> filter(!is.na(game_id))
cat(sprintf("      %d/%d Kalshi game-events matched UNIQUELY to a real box_scores_cache game.\n\n", nrow(events), n_before))

events <- events |> left_join(box_games |> select(game_id, home_abbr, away_abbr, game_date, game_date_time, home_score, away_score, home_win), by = "game_id")

# Figure out which Kalshi side ticker is the HOME side (matches box_games' home_abbr).
events <- events |> mutate(
  home_ticker = if_else(abbr_a == home_abbr, ticker_a, ticker_b),
  away_ticker = if_else(abbr_a == home_abbr, ticker_b, ticker_a)
)

if (nrow(events) == 0) stop("No Kalshi<->real-game matches found -- nothing to measure. Check Kalshi market coverage window vs box_scores_cache's date range.")

# ------------------------------------------------------------------------------
# 4. For each matched game, pull the HOME side's hourly candlesticks and pick the
#    last candle strictly before scheduled tip-off (game_date_time, assumed
#    America/New_York -- this repo's existing box-score convention).
# ------------------------------------------------------------------------------
cat("[4/5] Pulling candlesticks per matched game and extracting pre-tip-off market price...\n")

get_pregame_price <- function(home_ticker, tipoff_et) {
  tipoff_utc <- with_tz(force_tz(as_datetime(tipoff_et), "America/New_York"), "UTC")
  start_ts <- as.integer(tipoff_utc) - 5 * 86400
  end_ts   <- as.integer(tipoff_utc) + 3600
  resp <- tryCatch(
    kalshi_get(sprintf("/series/KXWNBAGAME/markets/%s/candlesticks", home_ticker),
               list(start_ts = start_ts, end_ts = end_ts, period_interval = 60)),
    error = function(e) NULL
  )
  if (is.null(resp) || length(resp$candlesticks) == 0) return(NA_real_)
  candles <- map_dfr(resp$candlesticks, function(c) {
    tibble(
      end_ts = c$end_period_ts,
      yes_bid = as.numeric(c$yes_bid$close_dollars %||% NA),
      yes_ask = as.numeric(c$yes_ask$close_dollars %||% NA)
    )
  })
  tipoff_epoch <- as.integer(tipoff_utc)
  pre <- candles |> filter(end_ts <= tipoff_epoch) |> arrange(desc(end_ts)) |> slice(1)
  if (nrow(pre) == 0) return(NA_real_)
  mean(c(pre$yes_bid, pre$yes_ask), na.rm = TRUE)
}

events$market_home_prob <- NA_real_
for (i in seq_len(nrow(events))) {
  events$market_home_prob[i] <- get_pregame_price(events$home_ticker[i], events$game_date_time[i])
  if (i %% 10 == 0) cat(sprintf("      ...%d/%d\n", i, nrow(events)))
}
n_priced <- sum(!is.na(events$market_home_prob))
cat(sprintf("      %d/%d games got a usable pre-tip-off market price.\n\n", n_priced, nrow(events)))
events <- events |> filter(!is.na(market_home_prob))

# ------------------------------------------------------------------------------
# 5. Compute the retrospective, no-lookahead MODEL win probability (Track A's
#    leakage-free trailing-rolling-margin method) and measure divergence.
# ------------------------------------------------------------------------------
cat("[5/5] Computing retrospective (no-lookahead) model probabilities and divergence...\n")

apply_rating_limits_param <- function(rating, limit, dampening) {
  if (is.na(rating)) return(NA_real_)
  if (rating > limit) return(limit + dampening * (rating - limit))
  if (rating < -limit) return(-limit + dampening * (rating + limit))
  return(rating)
}
LIMIT <- 5.0; DAMPENING <- 0.1  # mirrors market_odds_engine.R::apply_rating_limits()

rolled <- box_scores |>
  arrange(team_id, season, game_date) |>
  group_by(season, team_id) |>
  mutate(
    margin = team_score - opponent_team_score,
    roll_margin = slide_dbl(margin, mean, .before = ROLLING_WINDOW_SIZE, .after = -1)
  ) |>
  ungroup()

home_roll <- rolled |> filter(team_home_away == "home") |> select(game_id, home_roll_margin = roll_margin)
away_roll <- rolled |> filter(team_home_away == "away") |> select(game_id, away_roll_margin = roll_margin)

events <- events |>
  left_join(home_roll, by = "game_id") |>
  left_join(away_roll, by = "game_id")

n_before_window <- nrow(events)
events <- events |> filter(!is.na(home_roll_margin), !is.na(away_roll_margin))
cat(sprintf("      %d/%d priced games have a full trailing %d-game rolling window for both teams (no lookahead).\n\n",
            nrow(events), n_before_window, ROLLING_WINDOW_SIZE))

if (nrow(events) == 0) stop("No games left with both a market price and a full leakage-free rolling window.")

events <- events |> mutate(
  h_lim = vapply(home_roll_margin, apply_rating_limits_param, numeric(1), limit = LIMIT, dampening = DAMPENING),
  a_lim = vapply(away_roll_margin, apply_rating_limits_param, numeric(1), limit = LIMIT, dampening = DAMPENING),
  model_margin = (h_lim - a_lim) + WNBA_HCA,
  model_home_prob = pnorm(model_margin / WNBA_MARGIN_SIGMA),
  divergence = model_home_prob - market_home_prob,
  home_actually_won = as.logical(home_win),
  model_brier = (model_home_prob - as.numeric(home_actually_won))^2,
  market_brier = (market_home_prob - as.numeric(home_actually_won))^2
)

out_path <- file.path("tools", "research_output", "prediction_market_divergence.csv")
write.csv(events |> select(game_id, game_date, home_abbr, away_abbr, model_home_prob, market_home_prob,
                            divergence, home_actually_won, model_brier, market_brier),
          out_path, row.names = FALSE)

cat("\n================================================================\n")
cat(" RESULTS: MODEL vs. KALSHI MARKET DIVERGENCE ON REAL SETTLED GAMES \n")
cat("================================================================\n\n")
cat(sprintf("N games = %d, date range %s to %s\n\n", nrow(events),
            min(events$game_date), max(events$game_date)))

cat(sprintf("Mean divergence (model - market, home-team prob):      %+.4f\n", mean(events$divergence)))
cat(sprintf("Median divergence:                                      %+.4f\n", median(events$divergence)))
cat(sprintf("Mean |divergence|:                                      %.4f\n", mean(abs(events$divergence))))
cat(sprintf("SD of divergence:                                       %.4f\n\n", sd(events$divergence)))

t_test <- t.test(events$divergence)
cat(sprintf("t-test (H0: mean divergence = 0): t=%.3f, p=%.4f, 95%% CI [%.4f, %.4f]\n",
            t_test$statistic, t_test$p.value, t_test$conf.int[1], t_test$conf.int[2]))
cat("(A non-zero, significant mean divergence would mean the model is SYSTEMATICALLY more/less\n")
cat(" bullish on home teams than the market -- a directional bias, not by itself tradeable edge.\n")
cat(" What matters for hypothesis #1/#2 is whether LARGE per-game divergences predict which side\n")
cat(" was actually right more often than the market -- see the threshold analysis below.)\n\n")

cat(sprintf("Model Brier score:  %.4f\n", mean(events$model_brier)))
cat(sprintf("Market Brier score: %.4f\n", mean(events$market_brier)))
cat("(Lower is better-calibrated. Kalshi markets are usually very well-calibrated by construction\n")
cat(" -- if the model's Brier score is not close to or better than the market's, that alone is\n")
cat(" evidence AGAINST tradeable edge, independent of the divergence-threshold analysis below.)\n\n")

for (thresh in c(0.03, 0.05, 0.08, 0.10)) {
  sub <- events |> filter(abs(divergence) >= thresh)
  if (nrow(sub) == 0) {
    cat(sprintf("|divergence| >= %.2f: N=0 games\n", thresh))
    next
  }
  model_side_won <- mean((sub$divergence > 0) == sub$home_actually_won)
  market_implied_side_won <- mean((sub$market_home_prob > 0.5) == sub$home_actually_won)
  cat(sprintf("|divergence| >= %.2f: N=%d games | model's more-favored side won %.1f%% of the time | market's more-favored side won %.1f%% of the time\n",
              thresh, nrow(sub), 100 * model_side_won, 100 * market_implied_side_won))
}

cat(sprintf("\n[done] Full per-game table saved to %s\n", out_path))
cat("\nThis is a divergence MEASUREMENT only, per the plan's explicit instruction not to build\n")
cat("staking/P&L backtest logic before a real divergence is shown here (Next Steps #3). See\n")
cat("docs/prediction_market_alpha_research_plan.md for what should happen next given these numbers.\n")
