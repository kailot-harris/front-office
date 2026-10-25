# ==============================================================================
# tools/research_prediction_market_props_divergence.R
#
# Research Next Step #4 (player-props half) from
# docs/prediction_market_alpha_research_plan.md, hypothesis #3: does this repo have
# any edge against Kalshi's real player-prop markets (KXWNBAPTS/KXWNBAREB/KXWNBAAST --
# KXWNBAH2HPTS/KXWNBAH2HPRA have zero settled markets as of 2026-09-17, so they are
# NOT included here; re-check that series later). Same divergence-measurement
# discipline as tools/research_prediction_market_divergence.R (the game-market
# script): retrospective/no-lookahead model probability vs. a real pre-tip-off
# market price, scored against the real settled outcome. NOT a backtest/P&L script.
#
# IMPORTANT SIMPLIFICATION, disclosed up front (not hidden in a footnote): the
# "model" here is NOT copula_props_engine.R's live Wilson/ZINB copula output --
# that cache (cache/copula_wilson_pra.rds) is a single current-day snapshot with no
# historical reconstruction capability, so using it here for a 2026-07/08 game would
# silently use TODAY's fitted parameters on a past game (lookahead). Instead this
# script computes a per-player trailing rolling mean/sd (leakage-free, same
# convention as the team-margin script), normal-approximated -- a simpler, honest
# proxy for "what would a no-lookahead version of this model's mu/sigma have said,"
# not a reproduction of the live copula engine's exact math. If this shows a real
# divergence worth pursuing, the next step would be teaching copula_props_engine.R
# to run point-in-time (see Limitations in the findings doc this script produces).
#
# Usage: Rscript.exe tools/research_prediction_market_props_divergence.R
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
      stop(sprintf("research_prediction_market_props_divergence.R: cannot locate the repo root (no config.R at or above '%s')", start))
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
PROP_SERIES <- c(PTS = "KXWNBAPTS", REB = "KXWNBAREB", AST = "KXWNBAAST")
MIN_TRAILING_GAMES <- 5  # below this a per-player rolling mean/sd is too noisy to trust; drop, don't guess

# Real run against this endpoint hit one transient "no response" mid-pagination
# (thousands of settled prop markets exist -- far more real coverage than the
# feasibility check anticipated). Retry with backoff rather than treating a single
# transient failure as fatal; still fail loudly after genuinely repeated failures.
kalshi_get <- function(path, query = list(), max_tries = 4) {
  for (attempt in seq_len(max_tries)) {
    resp <- tryCatch(
      request(paste0(KALSHI_BASE, path)) |> req_url_query(!!!query) |> req_timeout(20) |> req_perform(),
      error = function(e) NULL
    )
    if (!is.null(resp) && resp_status(resp) == 200) return(resp_body_json(resp, simplifyVector = FALSE))
    if (attempt < max_tries) Sys.sleep(2 * attempt)
  }
  stop(sprintf("Kalshi API call to %s failed after %d attempts.", path, max_tries))
}

pull_all_settled <- function(series_ticker) {
  out <- list(); cursor <- NULL; page <- 0
  repeat {
    page <- page + 1
    q <- list(series_ticker = series_ticker, status = "settled", limit = 200)
    if (!is.null(cursor) && nchar(cursor) > 0) q$cursor <- cursor
    resp <- kalshi_get("/markets", q)
    out <- c(out, resp$markets)
    cursor <- resp$cursor
    if (is.null(cursor) || nchar(cursor) == 0 || length(resp$markets) == 0 || page >= 20) break
  }
  out
}

# ------------------------------------------------------------------------------
# 1. Pull all settled markets across the three per-game prop series.
# ------------------------------------------------------------------------------
cat("[1/5] Pulling all settled player-prop markets from Kalshi (PTS/REB/AST)...\n")
all_markets <- list()
for (stat in names(PROP_SERIES)) {
  m <- pull_all_settled(PROP_SERIES[stat])
  cat(sprintf("      %s (%s): %d settled markets\n", stat, PROP_SERIES[stat], length(m)))
  all_markets[[stat]] <- m
}

markets_df <- imap_dfr(all_markets, function(mkts, stat) {
  map_dfr(mkts, function(m) {
    tibble(
      stat = stat,
      ticker = m$ticker %||% NA_character_,
      event_ticker = m$event_ticker %||% NA_character_,
      yes_sub_title = m$yes_sub_title %||% NA_character_,
      floor_strike = as.numeric(m$floor_strike %||% NA),
      result = m$result %||% NA_character_,
      status = m$status %||% NA_character_,
      open_time = m$open_time %||% NA_character_
    )
  })
}) |> filter(status == "finalized", result %in% c("yes", "no"), !is.na(floor_strike))
cat(sprintf("      TOTAL: %d finalized single-player prop markets with a real strike/result.\n\n", nrow(markets_df)))

# ------------------------------------------------------------------------------
# 2. Parse player name (from yes_sub_title, e.g. "Diamond Miller: 15+") and the real
#    scheduled game date directly from event_ticker's embedded date (e.g.
#    "KXWNBAPTS-26AUG30CONNDAL" -> 2026-08-30) -- this avoids the UTC-crossover
#    ambiguity the game-market script had to work around via close_time, since the
#    ticker date IS the local scheduled date per Kalshi's own rules text
#    ("originally scheduled for Aug 30, 2026").
# ------------------------------------------------------------------------------
cat("[2/5] Parsing player name + game date from ticker fields...\n")
markets_df <- markets_df |>
  mutate(
    player_name = str_trim(str_remove(yes_sub_title, ":\\s*\\d+\\+?$")),
    date_token = str_match(event_ticker, "^KXWNBA[A-Z]+-(\\d{2}[A-Z]{3}\\d{2})")[, 2],
    game_date = as.Date(date_token, format = "%y%b%d")
  )
n_bad_date <- sum(is.na(markets_df$game_date))
if (n_bad_date > 0) cat(sprintf("      WARNING: %d markets had an unparseable date token, dropped.\n", n_bad_date))
markets_df <- markets_df |> filter(!is.na(game_date), !is.na(player_name))
cat(sprintf("      %d markets with a parsed player name + game date.\n\n", nrow(markets_df)))

# ------------------------------------------------------------------------------
# 3. Join to the real per-player, per-game stat line in player_box_scores_cache.rds
#    by (athlete_display_name, game_date) -- verified empirically to be a name
#    format match (both are "First Last"), require a UNIQUE match.
# ------------------------------------------------------------------------------
cat("[3/5] Joining to real player_box_scores_cache.rds rows...\n")
stopifnot(file.exists(CACHE_PLAYER_BOX))
player_box <- readRDS(CACHE_PLAYER_BOX)

stat_col <- c(PTS = "points", REB = "rebounds", AST = "assists")

box_lookup <- player_box |>
  select(athlete_display_name, game_date, season, game_date_time, points, rebounds, assists) |>
  distinct(athlete_display_name, game_date, .keep_all = TRUE)  # one row per player/date expected

dupe_check <- player_box |> count(athlete_display_name, game_date) |> filter(n > 1)
if (nrow(dupe_check) > 0) {
  cat(sprintf("      NOTE: %d (player, date) pairs have >1 box-score row (doubleheader/data dupe) -- first row kept, not averaged.\n", nrow(dupe_check)))
}

markets_df <- markets_df |> left_join(box_lookup, by = c("player_name" = "athlete_display_name", "game_date"))
n_before_match <- nrow(markets_df)
markets_df <- markets_df |> filter(!is.na(season))
cat(sprintf("      %d/%d prop markets matched to a real box-score row (player name + date).\n\n", nrow(markets_df), n_before_match))

markets_df <- markets_df |> mutate(actual_stat = case_when(
  stat == "PTS" ~ points, stat == "REB" ~ rebounds, stat == "AST" ~ assists
))

# Sanity check: does the Kalshi result agree with the real box-score outcome?
markets_df <- markets_df |> mutate(kalshi_result_yes = result == "yes", real_result_yes = actual_stat > floor_strike)
mismatch <- markets_df |> filter(kalshi_result_yes != real_result_yes)
cat(sprintf("      Sanity check: %d/%d matched markets where Kalshi's settlement disagrees with our matched box-score row (should be ~0; any nonzero here means a bad player/date match slipped through).\n\n",
            nrow(mismatch), nrow(markets_df)))
markets_df <- markets_df |> filter(kalshi_result_yes == real_result_yes)  # drop any mismatched joins rather than trust a bad match

# ------------------------------------------------------------------------------
# 4. Compute the retrospective (no-lookahead) trailing mean/sd per player/stat, and
#    pull each market's pre-tip-off price from its candlesticks.
# ------------------------------------------------------------------------------
cat("[4/5] Computing leakage-free trailing player stat distributions...\n")

rolled_player <- player_box |>
  arrange(athlete_display_name, season, game_date) |>
  group_by(season, athlete_display_name) |>
  mutate(
    roll_pts_mean = slide_dbl(points,    mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_reb_mean = slide_dbl(rebounds,  mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_ast_mean = slide_dbl(assists,   mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_pts_sd   = slide_dbl(points,    sd,   .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_reb_sd   = slide_dbl(rebounds,  sd,   .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_ast_sd   = slide_dbl(assists,   sd,   .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_n        = slide_dbl(points,    length, .before = ROLLING_WINDOW_SIZE, .after = -1)
  ) |>
  ungroup() |>
  select(athlete_display_name, game_date, season, roll_pts_mean, roll_reb_mean, roll_ast_mean,
         roll_pts_sd, roll_reb_sd, roll_ast_sd, roll_n)

markets_df <- markets_df |> left_join(rolled_player, by = c("player_name" = "athlete_display_name", "game_date", "season"))

markets_df <- markets_df |> mutate(
  trailing_mean = case_when(stat == "PTS" ~ roll_pts_mean, stat == "REB" ~ roll_reb_mean, stat == "AST" ~ roll_ast_mean),
  trailing_sd   = case_when(stat == "PTS" ~ roll_pts_sd,   stat == "REB" ~ roll_reb_sd,   stat == "AST" ~ roll_ast_sd)
)

n_before_window <- nrow(markets_df)
markets_df <- markets_df |> filter(!is.na(roll_n), roll_n >= MIN_TRAILING_GAMES, !is.na(trailing_sd), trailing_sd > 0)
cat(sprintf("      %d/%d matched markets have >= %d prior leakage-free games with nonzero variance.\n\n",
            nrow(markets_df), n_before_window, MIN_TRAILING_GAMES))

if (nrow(markets_df) == 0) stop("No markets left with a usable trailing distribution -- nothing to measure.")

markets_df <- markets_df |> mutate(
  model_prob = 1 - pnorm((floor_strike - trailing_mean) / trailing_sd)
)

MAX_CANDLESTICK_PULLS <- 200  # thousands of settled prop markets exist; one candlestick call per
# market is too slow/rate-limit-risky to run against all of them for a first divergence
# measurement -- take a reproducible random sample instead. Re-run with a higher cap (or full
# population) once this first pass shows whether the signal is worth the extra API cost.
if (nrow(markets_df) > MAX_CANDLESTICK_PULLS) {
  set.seed(20260917)
  cat(sprintf("      %d markets matched -- sampling %d for candlestick pricing (seed fixed for reproducibility).\n\n",
              nrow(markets_df), MAX_CANDLESTICK_PULLS))
  markets_df <- markets_df |> slice_sample(n = MAX_CANDLESTICK_PULLS)
}

cat("[5/5] Pulling pre-tip-off candlestick prices...\n")
get_pregame_price <- function(ticker, stat, tipoff_et) {
  tipoff_utc <- with_tz(force_tz(as_datetime(tipoff_et), "America/New_York"), "UTC")
  start_ts <- as.integer(tipoff_utc) - 5 * 86400
  end_ts   <- as.integer(tipoff_utc) + 3600
  resp <- tryCatch(
    kalshi_get(sprintf("/series/%s/markets/%s/candlesticks", unname(PROP_SERIES[stat]), ticker),
               list(start_ts = start_ts, end_ts = end_ts, period_interval = 60)),
    error = function(e) NULL
  )
  if (is.null(resp) || length(resp$candlesticks) == 0) return(NA_real_)
  candles <- map_dfr(resp$candlesticks, function(c) {
    tibble(end_ts = c$end_period_ts,
           yes_bid = as.numeric(c$yes_bid$close_dollars %||% NA),
           yes_ask = as.numeric(c$yes_ask$close_dollars %||% NA))
  })
  tipoff_epoch <- as.integer(tipoff_utc)
  pre <- candles |> filter(end_ts <= tipoff_epoch) |> arrange(desc(end_ts)) |> slice(1)
  if (nrow(pre) == 0) return(NA_real_)
  mean(c(pre$yes_bid, pre$yes_ask), na.rm = TRUE)
}

markets_df$market_prob <- NA_real_
for (i in seq_len(nrow(markets_df))) {
  markets_df$market_prob[i] <- get_pregame_price(markets_df$ticker[i], markets_df$stat[i], markets_df$game_date_time[i])
  if (i %% 20 == 0) cat(sprintf("      ...%d/%d\n", i, nrow(markets_df)))
}
n_priced <- sum(!is.na(markets_df$market_prob))
cat(sprintf("      %d/%d matched markets got a usable pre-tip-off market price.\n\n", n_priced, nrow(markets_df)))
markets_df <- markets_df |> filter(!is.na(market_prob))

if (nrow(markets_df) == 0) stop("No games left with both a model probability and a market price.")

markets_df <- markets_df |> mutate(
  divergence = model_prob - market_prob,
  model_brier = (model_prob - as.numeric(real_result_yes))^2,
  market_brier = (market_prob - as.numeric(real_result_yes))^2
)

out_path <- file.path("tools", "research_output", "prediction_market_props_divergence.csv")
write.csv(markets_df |> select(ticker, stat, player_name, game_date, floor_strike, trailing_mean, trailing_sd,
                                model_prob, market_prob, divergence, real_result_yes, model_brier, market_brier),
          out_path, row.names = FALSE)

cat("\n================================================================\n")
cat(" RESULTS: MODEL vs. KALSHI PLAYER-PROP DIVERGENCE ON REAL SETTLED MARKETS \n")
cat("================================================================\n\n")
cat(sprintf("N props = %d, date range %s to %s\n", nrow(markets_df), min(markets_df$game_date), max(markets_df$game_date)))
print(markets_df |> count(stat))
cat("\n")

cat(sprintf("Mean divergence (model - market):   %+.4f\n", mean(markets_df$divergence)))
cat(sprintf("Mean |divergence|:                   %.4f\n", mean(abs(markets_df$divergence))))
t_test <- t.test(markets_df$divergence)
cat(sprintf("t-test (H0: mean divergence = 0): t=%.3f, p=%.4f, 95%% CI [%.4f, %.4f]\n\n",
            t_test$statistic, t_test$p.value, t_test$conf.int[1], t_test$conf.int[2]))

cat(sprintf("Model Brier score:  %.4f\n", mean(markets_df$model_brier)))
cat(sprintf("Market Brier score: %.4f\n\n", mean(markets_df$market_brier)))

for (thresh in c(0.05, 0.08, 0.10, 0.15)) {
  sub <- markets_df |> filter(abs(divergence) >= thresh)
  if (nrow(sub) < 3) { cat(sprintf("|divergence| >= %.2f: N=%d (too few to report)\n", thresh, nrow(sub))); next }
  model_side_right <- mean((sub$divergence > 0) == sub$real_result_yes)
  market_side_right <- mean((sub$market_prob > 0.5) == sub$real_result_yes)
  cat(sprintf("|divergence| >= %.2f: N=%d | model's more-favored side right %.1f%% | market's more-favored side right %.1f%%\n",
              thresh, nrow(sub), 100 * model_side_right, 100 * market_side_right))
}

cat(sprintf("\n[done] Full per-market table saved to %s\n", out_path))
cat("\nDivergence MEASUREMENT only -- see docs/prediction_market_alpha_research_plan.md before\n")
cat("building any staking/P&L logic on top of this.\n")
