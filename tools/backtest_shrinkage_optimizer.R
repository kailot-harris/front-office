# ==============================================================================
# Walk-Forward Backtest / Optimizer for Phase 8's Two Unvalidated Constants
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/backtest_shrinkage_optimizer.R
#
# config.R's own comments on RATING_SHRINKAGE_GAMES_K and MIN_SAMPLE_GAMES_FOR_STAKE
# both say, verbatim, "NOT YET EMPIRICALLY BACKTESTED" and call for exactly this: a
# walk-forward, out-of-sample validation against real historical results before either
# constant is trusted for real staking decisions (see docs/HANDOFF.md's "Suggested next
# steps" #2). This script does that, using an OPTIMIZER (stats::optimize(), golden-
# section search) rather than a hand-rolled grid search, per instruction.
#
# Two constants, two DISTINCT objectives (per config.R's own warning not to conflate
# them - RATING_SHRINKAGE_GAMES_K shapes the rating BLEND, MIN_SAMPLE_GAMES_FOR_STAKE
# gates STAKING only):
#   1. RATING_SHRINKAGE_GAMES_K -> minimizes out-of-sample Brier score of
#      home_win_prob vs. actual game outcomes, walk-forward across seasons 2003-2025
#      (2002 excluded: it's the first modern-era season in CACHE_EPA_METRICS, so it has
#      no prior-season rating to blend against).
#   2. MIN_SAMPLE_GAMES_FOR_STAKE -> maximizes the Sharpe ratio (mean / sd of per-bet
#      pct return) of a real quarter-Kelly staking simulation run against REAL historical
#      Vegas moneylines already present in CACHE_SCHEDULES (home_moneyline/away_moneyline
#      columns - reliable coverage confirmed 2010-2025; sparse/absent 2002-2009, so that
#      window is excluded from the staking backtest specifically, not the calibration one).
#
# Both objectives reuse the EXACT SAME formulas as the live pipeline (compute_power_
# rating_points() sourced from team_ratings_engine.R, calculate_kelly()/american_to_
# decimal()/american_to_prob() sourced from market_odds_engine.R) - never a second,
# independently-typed copy of that math (the class of drift bug this repo's CLAUDE.md
# warns about).
#
# LOOKAHEAD-BIAS NOTE: for every (season, week) snapshot, each team's rating is built
# ONLY from EPA rows dated strictly before that week's earliest game - a team's own
# same-week game (e.g. a Thursday-night game feeding into that week's later Sunday
# slate) is never allowed to leak into its own pre-game rating. avg_plays_per_game (a
# minor EPA/play -> point-margin scaling constant) is computed once globally rather
# than as-of each snapshot, matching the live pipeline's own approach - this is a
# deliberately accepted, documented simplification (the constant is empirically stable
# across the whole modern era per derive_nfl_constants.R's sigma comparison table), not
# an oversight.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/backtest_shrinkage_optimizer.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/backtest_shrinkage_optimizer.R"

# Reuse the pipeline's own formulas rather than retyping them (see header). Both scripts
# are source()-safe (no top-level side effects beyond function/constant definitions, per
# their own file-header contracts).
source("team_ratings_engine.R")   # -> compute_power_rating_points()
source("market_odds_engine.R")    # -> american_to_decimal(), american_to_prob(), calculate_kelly()

if (!file.exists(CACHE_EPA_METRICS) || !file.exists(CACHE_SCHEDULES)) {
  stop("CACHE_EPA_METRICS / CACHE_SCHEDULES missing - run run_daily_ingest() and run_epa_metrics() first.")
}

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))

completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

# CALIBRATION_SEASONS: every modern-era season with a real prior season to blend against
# (2002 is CACHE_EPA_METRICS's first season - no prior-season rating exists for it).
# CURRENT_SEASON (2026) is excluded - it's in-progress/partial (see config.R).
CALIBRATION_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)

# STAKING_SEASONS: subset with reliable real historical moneylines (empirically checked -
# home_moneyline is 0% populated 2002-2005, spotty 2006-2009, ~100% populated 2010+).
STAKING_SEASONS <- 2010L:(CURRENT_SEASON - 1L)

avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("NFL Phase 8 constant backtest/optimizer - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")
cat(sprintf("Calibration window (Brier score): seasons %d-%d\n",
            min(CALIBRATION_SEASONS), max(CALIBRATION_SEASONS)))
cat(sprintf("Staking window (real Vegas moneylines): seasons %d-%d\n\n",
            min(STAKING_SEASONS), max(STAKING_SEASONS)))

# ------------------------------------------------------------------------------------------
# Precompute, once per season, the prior-season-final rating for every team (identical
# formula/inputs to team_ratings_engine.R's own prior_epa_ratings block) - this doesn't
# depend on K or on in-season week, so it's cached per season rather than recomputed per game.
# ------------------------------------------------------------------------------------------
build_prior_season_ratings <- function(season) {
  prior_epa <- epa |>
    filter(season == !!(season - 1L)) |>
    arrange(team, game_date, week) |>
    group_by(team) |>
    slice_tail(n = 1) |>
    ungroup() |>
    select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll)

  if (nrow(prior_epa) == 0) return(data.frame(team = character(0), prior_season_rating = numeric(0)))

  league_avg_off_prior <- mean(prior_epa$off_epa_per_play_roll, na.rm = TRUE)
  league_avg_def_prior <- mean(prior_epa$def_epa_per_play_allowed_roll, na.rm = TRUE)

  prior_epa |>
    mutate(
      prior_season_rating = compute_power_rating_points(
        off_epa_per_play_roll, def_epa_per_play_allowed_roll,
        league_avg_off_prior, league_avg_def_prior, avg_plays_per_game
      )
    ) |>
    select(team, prior_season_rating)
}

# ------------------------------------------------------------------------------------------
# Precompute, once per (season, week) snapshot, every team's as-of "current_raw_rating" and
# real current-season games_played, using ONLY EPA rows strictly before that week's earliest
# game_date (no lookahead - see header note).
# ------------------------------------------------------------------------------------------
build_week_snapshot <- function(season, week, cutoff_date) {
  asof <- epa |> filter(game_date < cutoff_date)

  latest_asof <- asof |>
    arrange(team, game_date, week) |>
    group_by(team) |>
    slice_tail(n = 1) |>
    ungroup() |>
    select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll)

  if (nrow(latest_asof) == 0) return(NULL)

  league_avg_off <- mean(latest_asof$off_epa_per_play_roll, na.rm = TRUE)
  league_avg_def <- mean(latest_asof$def_epa_per_play_allowed_roll, na.rm = TRUE)

  latest_asof <- latest_asof |>
    mutate(
      current_raw_rating = compute_power_rating_points(
        off_epa_per_play_roll, def_epa_per_play_allowed_roll,
        league_avg_off, league_avg_def, avg_plays_per_game
      )
    )

  games_played <- asof |>
    filter(season == !!season) |>
    count(team, name = "games_played")

  latest_asof |>
    left_join(games_played, by = "team") |>
    mutate(games_played = ifelse(is.na(games_played), 0L, games_played)) |>
    select(team, current_raw_rating, games_played)
}

# ------------------------------------------------------------------------------------------
# Build the full walk-forward game table ONCE (K-independent inputs: current_raw_rating,
# prior_season_rating, games_played, actual outcome, moneylines). K is applied afterward as
# a pure blend, so the optimizer never re-touches CACHE_EPA_METRICS/CACHE_SCHEDULES per
# candidate K - only the cheap blend + pnorm() + Brier/EV math re-runs per candidate.
# ------------------------------------------------------------------------------------------
cat("Building walk-forward per-game snapshot table (one-time cost, not repeated per candidate K)...\n")

game_rows <- list()
row_i <- 0L

for (s in CALIBRATION_SEASONS) {
  prior_ratings <- build_prior_season_ratings(s)
  season_games  <- completed |> filter(season == s)
  weeks_this_season <- sort(unique(season_games$week))

  for (w in weeks_this_season) {
    week_games <- season_games |> filter(week == w)
    cutoff <- min(week_games$gameday, na.rm = TRUE)
    snap <- build_week_snapshot(s, w, cutoff)
    if (is.null(snap)) next

    snap <- snap |> left_join(prior_ratings, by = "team") |>
      mutate(prior_season_rating = ifelse(is.na(prior_season_rating), 0, prior_season_rating))

    rating_lu       <- setNames(snap$current_raw_rating, snap$team)
    prior_lu        <- setNames(snap$prior_season_rating, snap$team)
    games_played_lu <- setNames(snap$games_played, snap$team)

    for (i in seq_len(nrow(week_games))) {
      g <- week_games[i, ]
      h <- g$home_team; a <- g$away_team
      if (is.na(rating_lu[h]) || is.na(rating_lu[a])) next

      row_i <- row_i + 1L
      game_rows[[row_i]] <- data.frame(
        season = s, week = w, game_id = g$game_id,
        home_team = h, away_team = a,
        home_raw = unname(rating_lu[h]),   away_raw = unname(rating_lu[a]),
        home_prior = unname(prior_lu[h]),  away_prior = unname(prior_lu[a]),
        home_gp = unname(games_played_lu[h]), away_gp = unname(games_played_lu[a]),
        home_win = as.integer(g$home_score > g$away_score),
        home_ml = g$home_moneyline, away_ml = g$away_moneyline,
        stringsAsFactors = FALSE
      )
    }
  }
}

games <- bind_rows(game_rows)
cat(sprintf("Built %d walk-forward games across %d seasons.\n\n", nrow(games), length(CALIBRATION_SEASONS)))

# ------------------------------------------------------------------------------------------
# Objective 1: RATING_SHRINKAGE_GAMES_K -> minimize Brier score
# ------------------------------------------------------------------------------------------
brier_for_k <- function(k) {
  home_w <- games$home_gp / (games$home_gp + k)
  away_w <- games$away_gp / (games$away_gp + k)
  home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
  away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior

  margin <- (home_rating - away_rating) + NFL_HCA
  prob   <- pnorm(margin / NFL_MARGIN_SIGMA)

  mean((prob - games$home_win)^2)
}

cat("Optimizing RATING_SHRINKAGE_GAMES_K via stats::optimize() (golden-section search, bounded [0.1, 30])...\n")
opt_k <- optimize(brier_for_k, interval = c(0.1, 30), tol = 1e-4)

k_current <- brier_for_k(RATING_SHRINKAGE_GAMES_K)
cat(sprintf("  Current config.R value  K = %g  -> Brier = %.6f\n", RATING_SHRINKAGE_GAMES_K, k_current))
cat(sprintf("  Optimizer result        K = %.3f -> Brier = %.6f\n", opt_k$minimum, opt_k$objective))
cat(sprintf("  Naive baseline (K -> Inf, i.e. pure prior-season rating always): Brier = %.6f\n",
            brier_for_k(1e6)))
cat(sprintf("  Naive baseline (K -> 0, i.e. pure current-season rating always): Brier = %.6f\n\n",
            brier_for_k(1e-6)))

# ------------------------------------------------------------------------------------------
# Objective 2: MIN_SAMPLE_GAMES_FOR_STAKE -> maximize Sharpe ratio of a real quarter-Kelly
# staking simulation against real historical moneylines, using the OPTIMAL K found above
# (that's what the deployed pipeline would actually be predicting with).
# ------------------------------------------------------------------------------------------
staking_games <- games |>
  filter(season %in% STAKING_SEASONS, !is.na(home_ml), !is.na(away_ml))

cat(sprintf("Staking backtest: %d games with real historical moneylines (seasons %d-%d).\n",
            nrow(staking_games), min(STAKING_SEASONS), max(STAKING_SEASONS)))

apply_k <- function(df, k) {
  home_w <- df$home_gp / (df$home_gp + k)
  away_w <- df$away_gp / (df$away_gp + k)
  home_rating <- home_w * df$home_raw + (1 - home_w) * df$home_prior
  away_rating <- away_w * df$away_raw + (1 - away_w) * df$away_prior
  margin <- (home_rating - away_rating) + NFL_HCA
  df$model_home_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
  df
}

staking_games <- apply_k(staking_games, opt_k$minimum)

staking_games <- staking_games |>
  mutate(
    model_away_prob = 1 - model_home_prob,
    home_dec = american_to_decimal(home_ml),
    away_dec = american_to_decimal(away_ml),
    home_ev  = model_home_prob * home_dec - 1,
    away_ev  = model_away_prob * away_dec - 1,
    pick_home = home_ev > away_ev,
    best_prob = if_else(pick_home, model_home_prob, model_away_prob),
    best_dec  = if_else(pick_home, home_dec, away_dec),
    won       = if_else(pick_home, home_win == 1L, home_win == 0L),
    min_gp    = pmin(home_gp, away_gp),
    kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
    bet_return_pct = if_else(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)
  )

# Sharpe of per-bet pct return, gated at threshold tau (min_gp >= tau). Penalize thresholds
# that leave too few real bets to trust (n < 200) rather than letting the optimizer wander
# into a tiny, artificially-high-Sharpe corner of the sample.
MIN_BETS_FOR_TRUST <- 200L

sharpe_for_tau <- function(tau) {
  tau_r <- round(tau)
  bets <- staking_games |> filter(min_gp >= tau_r, kelly_pct > 0)
  n <- nrow(bets)
  if (n < 2) return(-Inf)
  sharpe <- mean(bets$bet_return_pct) / sd(bets$bet_return_pct)
  if (n < MIN_BETS_FOR_TRUST) {
    sharpe <- sharpe - (MIN_BETS_FOR_TRUST - n) / MIN_BETS_FOR_TRUST  # linear penalty toward 0 bets
  }
  sharpe
}

cat("\nOptimizing MIN_SAMPLE_GAMES_FOR_STAKE via stats::optimize() (bounded [0, 12], rounded to nearest game)...\n")
opt_tau <- optimize(function(tau) -sharpe_for_tau(tau), interval = c(0, 12), tol = 0.05)
opt_tau_rounded <- round(opt_tau$minimum)

report_tau <- function(tau) {
  tau_r <- round(tau)
  bets <- staking_games |> filter(min_gp >= tau_r, kelly_pct > 0)
  n <- nrow(bets)
  if (n == 0) return(sprintf("  tau=%d: 0 bets placed", tau_r))
  sprintf("  tau=%2d: n_bets=%5d  mean_return=%+.3f%%  sd_return=%.3f%%  sharpe=%.4f  total_return=%+.1f%% (unit-stake-sum of pct)",
          tau_r, n, mean(bets$bet_return_pct) * 100, sd(bets$bet_return_pct) * 100,
          sharpe_for_tau(tau_r), sum(bets$bet_return_pct) * 100)
}

cat(report_tau(MIN_SAMPLE_GAMES_FOR_STAKE), "  <- current config.R value\n")
cat(report_tau(opt_tau_rounded), "  <- optimizer result\n")
cat(report_tau(0), "  <- baseline: no gate at all\n\n")

# ------------------------------------------------------------------------------------------
# Summary / recommendation
# ------------------------------------------------------------------------------------------
cat("==============================================================\n")
cat("RECOMMENDATION\n")
cat("==============================================================\n")
cat(sprintf("RATING_SHRINKAGE_GAMES_K:      current = %g,  backtest-optimal = %.2f (Brier %.6f vs %.6f)\n",
            RATING_SHRINKAGE_GAMES_K, opt_k$minimum, opt_k$objective, k_current))
cat(sprintf("MIN_SAMPLE_GAMES_FOR_STAKE:    current = %g,  backtest-optimal = %d (Sharpe %.4f vs %.4f)\n",
            MIN_SAMPLE_GAMES_FOR_STAKE, opt_tau_rounded,
            sharpe_for_tau(opt_tau_rounded), sharpe_for_tau(MIN_SAMPLE_GAMES_FOR_STAKE)))
cat("\nBoth objectives are walk-forward / out-of-sample by construction (each game's rating is\n")
cat("built only from data strictly before that game's week). The staking objective additionally\n")
cat("uses REAL historical Vegas moneylines (CACHE_SCHEDULES home_moneyline/away_moneyline,\n")
cat("seasons 2010+ only - see header). Re-run this script whenever CACHE_EPA_METRICS/\n")
cat("CACHE_SCHEDULES are refreshed with a new completed season, and update config.R's two\n")
cat("constants (with their comments) if the recommendation changes materially.\n")

out <- list(
  run_at = Sys.time(),
  calibration_seasons = CALIBRATION_SEASONS,
  staking_seasons = STAKING_SEASONS,
  n_calibration_games = nrow(games),
  n_staking_games = nrow(staking_games),
  k_current = RATING_SHRINKAGE_GAMES_K,
  k_current_brier = k_current,
  k_optimal = opt_k$minimum,
  k_optimal_brier = opt_k$objective,
  tau_current = MIN_SAMPLE_GAMES_FOR_STAKE,
  tau_current_sharpe = sharpe_for_tau(MIN_SAMPLE_GAMES_FOR_STAKE),
  tau_optimal = opt_tau_rounded,
  tau_optimal_sharpe = sharpe_for_tau(opt_tau_rounded)
)
saveRDS(out, file.path(CACHE_DIR, "phase8_constant_backtest.rds"))
cat("\nSaved full backtest output to cache/phase8_constant_backtest.rds\n")
