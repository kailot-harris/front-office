# ==============================================================================
# tools/research_prediction_market_futures_divergence.R
#
# Research Next Step #4 (season-futures half) from
# docs/prediction_market_alpha_research_plan.md, hypothesis #4: does this repo have
# any edge against Kalshi's real season win-total markets (KXWNBAWINS) --
# roster_bottom_up_engine.R's season projections, in spirit.
#
# v2 (2026-09-17, same day as v1): v1 found a promising-looking but fragile signal
# (N=26, single open-time snapshot per market, plug-in binomial probability). Per
# explicit follow-up request, this version addresses both weaknesses:
#
#   1. SAMPLE SIZE: v1 used exactly ONE observation per market (the price at
#      open_time). Real settled KXWNBAWINS markets are rare (53 total, ~15-20
#      distinct team-thresholds) -- there is no way to get more distinct MARKETS.
#      Instead this version pulls each market's FULL daily candlestick history in a
#      single API call (open_time -> close_time) and treats each day as a separate,
#      still-leakage-free snapshot: the model probability is recomputed AS OF that
#      exact date (using only games strictly before it), paired with that day's real
#      market price. This turns 26 single-snapshot observations into several hundred
#      paired observations. These are NOT independent within a market (today's price
#      and tomorrow's price are obviously correlated, and every snapshot from the
#      same market shares the same eventual outcome) -- this script reports BOTH the
#      naive pooled statistics (labeled explicitly as anti-conservative/descriptive)
#      AND market-clustered statistics (one number per real market, N=53ish), and the
#      clustered numbers are what should actually be trusted for any significance
#      claim.
#
#   2. CALIBRATION: v1's plug-in binomial treated the estimated win-rate as the TRUE
#      probability, with only sampling variance over remaining games -- several
#      resulting probabilities were effectively 0 or 1, a known overconfidence
#      failure mode. Replaced with a BETA-BINOMIAL: a Beta(alpha0, beta0) prior on
#      each team's true win probability, seeded from that team's real PRIOR-season
#      win rate at a tunable pseudo-sample-size (PRIOR_STRENGTH, swept below rather
#      than asserted), updated with real observed wins/losses as of the snapshot
#      date, and the total-wins distribution over remaining games is the analytically
#      exact Beta-Binomial (integrates out parameter uncertainty, unlike the plug-in
#      binomial) -- computed directly via lchoose/lbeta (no extraDistr dependency
#      available on this machine, confirmed before writing this).
#
# NOT a backtest/P&L script -- divergence measurement only, per the plan's Next
# Steps discipline.
#
# Usage: Rscript.exe tools/research_prediction_market_futures_divergence.R
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
      stop(sprintf("research_prediction_market_futures_divergence.R: cannot locate the repo root (no config.R at or above '%s')", start))
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
  library(stringr)
  library(lubridate)
})

KALSHI_BASE <- "https://api.elections.kalshi.com/trade-api/v2"
KALSHI_TEAM_CODE_MAP <- c(CONN = "CON", PDX = "POR")  # mirrors tools/research_prediction_markets.R
SNAPSHOT_STEP_DAYS <- 5     # take one snapshot every N days of a market's real life, not every day
                            # (every day would be extreme within-market autocorrelation for little
                            # extra information -- 5 days is a compromise, not a tuned value)
MAX_SNAPSHOTS_PER_MARKET <- 20  # bound worst case (a market open for months) so runtime stays sane
PRIOR_STRENGTH_GRID <- c(11, 22, 44, 88, 176)  # pseudo-games of confidence placed on the prior-season
                                                # win rate -- swept, not asserted, same "stability check"
                                                # discipline as tools/backtest_margin_hyperparams.R

normalize_kalshi_team_code <- function(code) {
  unname(ifelse(code %in% names(KALSHI_TEAM_CODE_MAP), KALSHI_TEAM_CODE_MAP[code], code))
}

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

# ------------------------------------------------------------------------------
# 1. Pull all settled KXWNBAWINS markets (paginated).
# ------------------------------------------------------------------------------
cat("[1/5] Pulling all settled KXWNBAWINS markets from Kalshi...\n")
all_markets <- list(); cursor <- NULL; page <- 0
repeat {
  page <- page + 1
  q <- list(series_ticker = "KXWNBAWINS", status = "settled", limit = 200)
  if (!is.null(cursor) && nchar(cursor) > 0) q$cursor <- cursor
  resp <- kalshi_get("/markets", q)
  all_markets <- c(all_markets, resp$markets)
  cursor <- resp$cursor
  if (is.null(cursor) || nchar(cursor) == 0 || length(resp$markets) == 0 || page >= 20) break
}
cat(sprintf("      TOTAL: %d settled KXWNBAWINS markets pulled.\n\n", length(all_markets)))

markets_df <- map_dfr(all_markets, function(m) {
  tibble(
    ticker = m$ticker %||% NA_character_,
    event_ticker = m$event_ticker %||% NA_character_,
    floor_strike = as.numeric(m$floor_strike %||% NA),
    result = m$result %||% NA_character_,
    status = m$status %||% NA_character_,
    open_time = m$open_time %||% NA_character_,
    close_time = m$close_time %||% NA_character_
  )
}) |> filter(status == "finalized", result %in% c("yes", "no"), !is.na(floor_strike))
cat(sprintf("      %d finalized win-total markets with a real strike/result.\n\n", nrow(markets_df)))

# ------------------------------------------------------------------------------
# 2. Parse team code + season year from event_ticker.
# ------------------------------------------------------------------------------
cat("[2/5] Parsing team + season from event_ticker...\n")
markets_df <- markets_df |>
  mutate(
    year_token = str_match(event_ticker, "^KXWNBAWINS-(\\d{2})([A-Z]+)$")[, 2],
    code_token = str_match(event_ticker, "^KXWNBAWINS-(\\d{2})([A-Z]+)$")[, 3],
    season = 2000 + as.integer(year_token),
    abbr = normalize_kalshi_team_code(code_token)
  )
unmatched_abbr <- markets_df |> filter(!abbr %in% names(WNBA_TEAMS))
if (nrow(unmatched_abbr) > 0) {
  cat(sprintf("      %d markets had a team code not in WNBA_TEAMS -- dropped:\n", nrow(unmatched_abbr)))
  print(unmatched_abbr |> distinct(code_token))
}
markets_df <- markets_df |> filter(abbr %in% names(WNBA_TEAMS))
cat(sprintf("      %d markets with a real WNBA_TEAMS-matched team + season.\n\n", nrow(markets_df)))

stopifnot(file.exists(CACHE_TEAM_BOX))
box_scores <- readRDS(CACHE_TEAM_BOX)

# ------------------------------------------------------------------------------
# 3. Beta-Binomial retrospective model. Prior = Beta seeded from the team's real
#    PRIOR-season win rate at PRIOR_STRENGTH pseudo-games (still strictly
#    leakage-free -- known before the market ever opens); posterior updates with
#    real current-season wins/losses observed strictly before the snapshot date;
#    P(final wins >= floor_strike) integrates out win-rate uncertainty exactly via
#    the Beta-Binomial survival function over the real games remaining.
# ------------------------------------------------------------------------------
beta_binom_log_pmf <- function(k, n, alpha, beta) {
  lchoose(n, k) + lbeta(k + alpha, n - k + beta) - lbeta(alpha, beta)
}
beta_binom_sf_ge <- function(k_min, n, alpha, beta) {
  if (k_min <= 0) return(1.0)
  if (k_min > n) return(0.0)
  ks <- k_min:n
  sum(exp(beta_binom_log_pmf(ks, n, alpha, beta)))
}

compute_model_prob_bb <- function(abbr, season_yr, snapshot_date, floor_strike, prior_strength) {
  prior_games <- box_scores |> filter(team_abbreviation == abbr, season == season_yr, game_date < snapshot_date)
  games_played <- nrow(prior_games)
  wins_so_far <- sum(prior_games$team_winner)

  prev_season <- box_scores |> filter(team_abbreviation == abbr, season == season_yr - 1)
  prev_win_rate <- if (nrow(prev_season) > 0) mean(prev_season$team_winner) else 0.5  # true expansion-team case

  alpha0 <- prev_win_rate * prior_strength
  beta0  <- (1 - prev_win_rate) * prior_strength
  alpha_post <- alpha0 + wins_so_far
  beta_post  <- beta0 + (games_played - wins_so_far)

  remaining <- WNBA_SEASON_GAMES - games_played
  if (remaining <= 0) return(list(prob = NA_real_, games_played = games_played, remaining = remaining))

  k_min <- floor_strike - wins_so_far  # need >= this many wins among the remaining games
  prob <- beta_binom_sf_ge(k_min, remaining, alpha_post, beta_post)
  list(prob = prob, games_played = games_played, remaining = remaining)
}

# ------------------------------------------------------------------------------
# 4. Pull each market's FULL daily candlestick history in ONE call, resample every
#    SNAPSHOT_STEP_DAYS, and pair each kept day with a leakage-free model prob
#    computed as of that exact date.
# ------------------------------------------------------------------------------
cat("[3/5] Pulling full daily candlestick history per market (one call each)...\n")

get_daily_series <- function(ticker, open_time, close_time) {
  open_epoch  <- as.integer(as_datetime(open_time, tz = "UTC"))
  close_epoch <- as.integer(as_datetime(close_time, tz = "UTC"))
  resp <- tryCatch(
    kalshi_get(sprintf("/series/KXWNBAWINS/markets/%s/candlesticks", ticker),
               list(start_ts = open_epoch, end_ts = close_epoch, period_interval = 1440)),
    error = function(e) NULL
  )
  if (is.null(resp) || length(resp$candlesticks) == 0) return(tibble())
  map_dfr(resp$candlesticks, function(c) {
    tibble(end_ts = c$end_period_ts,
           yes_bid = as.numeric(c$yes_bid$close_dollars %||% NA),
           yes_ask = as.numeric(c$yes_ask$close_dollars %||% NA))
  }) |> arrange(end_ts) |> mutate(snapshot_date = as.Date(as_datetime(end_ts, tz = "UTC")),
                                   market_prob = (yes_bid + yes_ask) / 2) |>
    filter(!is.na(market_prob))
}

snapshot_rows <- list()
for (i in seq_len(nrow(markets_df))) {
  m <- markets_df[i, ]
  daily <- get_daily_series(m$ticker, m$open_time, m$close_time)
  if (nrow(daily) == 0) next
  keep_idx <- seq(1, nrow(daily), by = SNAPSHOT_STEP_DAYS)
  if (length(keep_idx) > MAX_SNAPSHOTS_PER_MARKET) keep_idx <- keep_idx[seq_len(MAX_SNAPSHOTS_PER_MARKET)]
  daily <- daily[keep_idx, ]
  daily$ticker <- m$ticker
  daily$abbr <- m$abbr
  daily$season <- m$season
  daily$floor_strike <- m$floor_strike
  daily$real_result_yes <- m$result == "yes"
  daily$days_before_close <- as.numeric(as.Date(m$close_time) - daily$snapshot_date)
  snapshot_rows[[i]] <- daily
  if (i %% 10 == 0) cat(sprintf("      ...%d/%d markets\n", i, nrow(markets_df)))
}
snapshots <- bind_rows(snapshot_rows)
cat(sprintf("      %d markets yielded %d total (market, day) snapshots (~%.1f/market).\n\n",
            length(unique(snapshots$ticker)), nrow(snapshots), nrow(snapshots) / length(unique(snapshots$ticker))))

# ------------------------------------------------------------------------------
# 5. Sweep PRIOR_STRENGTH, compute model prob per snapshot for each candidate,
#    score pooled AND market-clustered Brier, and report the full sweep (not just
#    a single "winning" value) per this repo's stability-check convention.
# ------------------------------------------------------------------------------
cat("[4/5] Computing Beta-Binomial model probabilities across the PRIOR_STRENGTH sweep...\n")

score_prior_strength <- function(ps) {
  probs <- pmap_dbl(list(snapshots$abbr, snapshots$season, snapshots$snapshot_date, snapshots$floor_strike),
                     function(a, s, d, f) compute_model_prob_bb(a, s, d, f, ps)$prob)
  df <- snapshots |> mutate(model_prob = probs) |> filter(!is.na(model_prob))
  df <- df |> mutate(model_brier = (model_prob - as.numeric(real_result_yes))^2,
                      market_brier = (market_prob - as.numeric(real_result_yes))^2)
  pooled_model_brier  <- mean(df$model_brier)
  pooled_market_brier <- mean(df$market_brier)
  clustered <- df |> group_by(ticker) |> summarise(model_brier = mean(model_brier), market_brier = mean(market_brier), .groups = "drop")
  list(prior_strength = ps, n_snapshots = nrow(df), n_markets = nrow(clustered),
       pooled_model_brier = pooled_model_brier, pooled_market_brier = pooled_market_brier,
       clustered_model_brier = mean(clustered$model_brier), clustered_market_brier = mean(clustered$market_brier),
       df = df, clustered_df = clustered)
}

sweep_results <- map(PRIOR_STRENGTH_GRID, score_prior_strength)
sweep_table <- map_dfr(sweep_results, function(r) tibble(
  prior_strength = r$prior_strength, n_snapshots = r$n_snapshots, n_markets = r$n_markets,
  pooled_model_brier = r$pooled_model_brier, pooled_market_brier = r$pooled_market_brier,
  clustered_model_brier = r$clustered_model_brier, clustered_market_brier = r$clustered_market_brier
))
cat("\nPRIOR_STRENGTH sweep (pseudo-games of confidence on prior-season win rate):\n")
print(knitr::kable(sweep_table, format = "simple", digits = 4))

best_idx <- which.min(sweep_table$clustered_model_brier)
best <- sweep_results[[best_idx]]
cat(sprintf("\nLowest clustered-Brier prior_strength = %d (clustered model Brier = %.4f vs market = %.4f).\n",
            best$prior_strength, best$clustered_model_brier, best$clustered_market_brier))
cat("NOTE: with only ~53 real markets (clustered N), this selection is DIRECTIONAL, not a rigorously\n")
cat("cross-validated hyperparameter choice -- report the full sweep, not just this row, to anyone acting on it.\n\n")

out_path <- file.path("tools", "research_output", "prediction_market_futures_divergence.csv")
write.csv(best$df |> select(ticker, abbr, season, floor_strike, snapshot_date, model_prob, market_prob,
                             real_result_yes, model_brier, market_brier),
          out_path, row.names = FALSE)
sweep_path <- file.path("tools", "research_output", "prediction_market_futures_divergence_prior_sweep.csv")
write.csv(sweep_table, sweep_path, row.names = FALSE)

# ------------------------------------------------------------------------------
# Final report at the selected prior_strength: pooled (labeled anti-conservative)
# AND market-clustered (the trustworthy one) statistics side by side.
# ------------------------------------------------------------------------------
cat("[5/5] Final report at the selected PRIOR_STRENGTH...\n")
df <- best$df |> mutate(divergence = model_prob - market_prob)  # best$df already carries every snapshots column, including days_before_close
clustered <- df |> group_by(ticker, abbr, real_result_yes) |> summarise(
  mean_model_prob = mean(model_prob), mean_market_prob = mean(market_prob),
  mean_divergence = mean(divergence), model_brier = mean(model_brier), market_brier = mean(market_brier),
  .groups = "drop"
)

# EARLY vs LATE regime split: KXWNBAWINS threshold markets close EARLY the moment the
# outcome is mathematically locked (see this script's own header) -- snapshots taken
# close to a market's real close_time are close to a trivially-certain outcome for
# BOTH the model and the market (both converge toward 0/1 as the answer becomes
# obvious), which would inflate accuracy for both sides and make "who called it
# right" look artificially perfect without testing real forecasting skill. Split
# explicitly rather than let one blended number hide this.
cat("\n--- EARLY vs. LATE regime split (days before each market's real close_time) ---\n")
cat("(LATE snapshots are close to the market's own early-closure point, where the outcome is\n")
cat(" close to mathematically obvious for both sides -- treat LATE accuracy as a sanity check that\n")
cat(" both series converge correctly, NOT as evidence of forecasting skill. EARLY is the real test.)\n\n")
for (regime in list(list(label = "EARLY (>=30 days before close)", filt = \(d) d$days_before_close >= 30),
                     list(label = "LATE (<30 days before close)",  filt = \(d) d$days_before_close < 30))) {
  sub_df <- df[regime$filt(df), ]
  sub_clustered <- sub_df |> group_by(ticker, real_result_yes) |> summarise(
    mean_divergence = mean(model_prob - market_prob), mean_market_prob = mean(market_prob),
    model_brier = mean(model_brier), market_brier = mean(market_brier), .groups = "drop"
  )
  cat(sprintf("%s: %d snapshots across %d markets\n", regime$label, nrow(sub_df), nrow(sub_clustered)))
  if (nrow(sub_clustered) >= 3) {
    cat(sprintf("  Clustered Model Brier = %.4f | Market Brier = %.4f\n",
                mean(sub_clustered$model_brier), mean(sub_clustered$market_brier)))
    model_right <- mean((sub_clustered$mean_divergence > 0) == sub_clustered$real_result_yes)
    market_right <- mean((sub_clustered$mean_market_prob > 0.5) == sub_clustered$real_result_yes)
    cat(sprintf("  Model favored-side right %.1f%% | Market favored-side right %.1f%%\n", 100*model_right, 100*market_right))
  } else {
    cat("  (too few markets to report)\n")
  }
  cat("\n")
}

cat("\n================================================================\n")
cat(" RESULTS: MODEL (Beta-Binomial) vs. KALSHI WIN-TOTAL DIVERGENCE \n")
cat("================================================================\n\n")
cat(sprintf("Selected prior_strength = %d pseudo-games. %d real markets, %d total snapshots (~%.1f/market, every %d days).\n\n",
            best$prior_strength, nrow(clustered), nrow(df), nrow(df) / nrow(clustered), SNAPSHOT_STEP_DAYS))

cat("--- POOLED (all snapshots as independent rows -- ANTI-CONSERVATIVE, descriptive only) ---\n")
cat(sprintf("N = %d | Model Brier = %.4f | Market Brier = %.4f\n", nrow(df), mean(df$model_brier), mean(df$market_brier)))
t_pooled <- t.test(df$divergence)
cat(sprintf("Mean divergence = %+.4f, pooled-t p=%.4f (DO NOT treat this p-value as valid -- rows are correlated within market)\n\n",
            mean(df$divergence), t_pooled$p.value))

cat("--- MARKET-CLUSTERED (one number per real market -- the trustworthy inference) ---\n")
cat(sprintf("N = %d real markets | Model Brier = %.4f | Market Brier = %.4f\n", nrow(clustered), mean(clustered$model_brier), mean(clustered$market_brier)))
t_clustered <- t.test(clustered$mean_divergence)
cat(sprintf("Mean divergence = %+.4f, clustered-t p=%.4f, 95%% CI [%.4f, %.4f]\n\n",
            mean(clustered$mean_divergence), t_clustered$p.value, t_clustered$conf.int[1], t_clustered$conf.int[2]))

for (thresh in c(0.05, 0.10, 0.15)) {
  sub <- clustered |> filter(abs(mean_divergence) >= thresh)
  if (nrow(sub) < 3) { cat(sprintf("|clustered divergence| >= %.2f: N=%d markets (too few to report)\n", thresh, nrow(sub))); next }
  model_side_right <- mean((sub$mean_divergence > 0) == sub$real_result_yes)
  market_side_right <- mean((sub$mean_market_prob > 0.5) == sub$real_result_yes)
  cat(sprintf("|clustered divergence| >= %.2f: N=%d markets | model's favored side right %.1f%% | market's favored side right %.1f%%\n",
              thresh, nrow(sub), 100 * model_side_right, 100 * market_side_right))
}

cat(sprintf("\n[done] Full snapshot table saved to %s\n", out_path))
cat(sprintf("[done] PRIOR_STRENGTH sweep saved to %s\n", sweep_path))
cat("\nDivergence MEASUREMENT only. Market-clustered N is still ~53 real markets (one season) --\n")
cat("this is a better-calibrated, larger-sample re-test of v1's lead, not a validated strategy.\n")
cat("See docs/prediction_market_alpha_research_plan.md before building any staking/P&L logic.\n")
