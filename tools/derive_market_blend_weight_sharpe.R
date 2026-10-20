# ==============================================================================
# Market-Blend Weight - Sharpe-Objective Re-Derivation (Phase 5 continuation, model-quality
# remediation)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/derive_market_blend_weight_sharpe.R
#
# tools/derive_market_blend_weight.R derived MARKET_BLEND_WEIGHT=0.97 by minimizing walk-forward
# BRIER SCORE against the (now-superseded) baseline_k3.6 formula - never against Sharpe, and
# never against the formula actually deployed today (ensemble_ridge_elo). This is a DELIBERATELY
# SEPARATE script, not an edit to that one - "what weight best CALIBRATES the model" and "what
# weight is most PROFITABLE to stake with" are genuinely different questions (a repo-wide theme
# this session: situational-EPA and Kalman-state-space candidates both improved Brier while
# making Sharpe worse - see docs/HANDOFF.md's Phase 4/Phase 5 entries), and the original
# calibration-derived constant must not be silently overwritten by a differently-motivated one.
#
# Reuses the EXACT deployed formula (ridge + Elo 50/50 ensemble, QB-injury-adjusted, market-
# blended - team_ratings_engine.R's live wiring / model_backtest_harness.R's "ensemble_ridge_elo"
# candidate) and the EXACT deployed staking gate (MIN_SAMPLE_GAMES_FOR_STAKE +
# LONGSHOT_DECIMAL_ODDS_CAP, calculate_kelly() at fraction=0.25/max_cap_pct=3.0 - all reused
# verbatim from market_odds_engine.R, never re-typed) rather than a from-scratch objective, so
# the answer is directly relevant to what's actually staked, not a generic proxy.
#
# Same real-historical-moneylines restriction as the Brier-based derivation: STAKING_SEASONS =
# 2010:(CURRENT_SEASON-1).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_market_blend_weight_sharpe.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_market_blend_weight_sharpe.R"

source("team_ratings_engine.R")      # -> compute_power_rating_points()
source("market_odds_engine.R")       # -> american_to_decimal/prob, calculate_kelly()
source("tools/backtest_common.R")    # -> build_walkforward_games()
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R") # -> predict_ridge_massey_walkforward()
source("tools/elo_model.R")          # -> run_elo_walkforward()

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

STAKING_SEASONS <- 2010L:(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("Market-blend weight Sharpe re-derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

cat("Building walk-forward game table (seasons", min(STAKING_SEASONS), "-", max(STAKING_SEASONS), ")...\n")
games <- build_walkforward_games(epa, completed, STAKING_SEASONS, avg_plays_per_game) |>
  filter(!is.na(home_ml), !is.na(away_ml))
cat(sprintf("Built %d walk-forward games with real historical moneylines.\n", nrow(games)))

starter_tbl <- get_qb_starter_table(2002:(CURRENT_SEASON - 1L))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- imp_h / (imp_h + imp_a)

cat("Simulating Elo sequentially across full history (one-time cost)...\n")
elo_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score), season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
  select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")

cat("Fitting walk-forward ridge Massey model...\n")
ridge_margin_raw <- predict_ridge_massey_walkforward(games)

home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
ridge_margin <- ridge_margin_raw - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
elo_margin   <- games$elo_margin_pts + games$fatigue_adj - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj

ridge_model_prob <- pnorm(ridge_margin / NFL_MARGIN_SIGMA)
elo_model_prob   <- pnorm(elo_margin / NFL_MARGIN_SIGMA)

cat(sprintf("Games with real market odds + a computed ensemble prob: %d\n\n", nrow(games)))

# ------------------------------------------------------------------------------------------
# sharpe_for_weight(): builds ensemble_ridge_elo's home_win_prob at a given blend weight w, then
# runs the EXACT deployed staking gate (MIN_SAMPLE_GAMES_FOR_STAKE + LONGSHOT_DECIMAL_ODDS_CAP,
# quarter-Kelly via calculate_kelly()) - same staking simulation shape as
# tools/model_backtest_harness.R's compute_backtest_metrics(), reused inline here (that function
# isn't itself sourceable standalone - model_backtest_harness.R has top-level execution) rather
# than a from-scratch reimplementation of the Kelly math.
# ------------------------------------------------------------------------------------------
sharpe_for_weight <- function(w) {
  ridge_final <- w * games$market_prob + (1 - w) * ridge_model_prob
  elo_final   <- w * games$market_prob + (1 - w) * elo_model_prob
  prob <- 0.5 * ridge_final + 0.5 * elo_final

  model_away_prob <- 1 - prob
  home_dec <- american_to_decimal(games$home_ml)
  away_dec <- american_to_decimal(games$away_ml)
  home_ev <- prob * home_dec - 1
  away_ev <- model_away_prob * away_dec - 1
  pick_home <- home_ev > away_ev
  best_prob <- ifelse(pick_home, prob, model_away_prob)
  best_dec  <- ifelse(pick_home, home_dec, away_dec)
  won       <- ifelse(pick_home, games$home_win == 1L, games$home_win == 0L)
  kelly_pct <- calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0)
  bet_return_pct <- ifelse(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)

  min_gp <- pmin(games$home_gp, games$away_gp)
  eligible <- min_gp >= MIN_SAMPLE_GAMES_FOR_STAKE & kelly_pct > 0 & best_dec <= LONGSHOT_DECIMAL_ODDS_CAP
  bets <- bet_return_pct[eligible]

  if (length(bets) < 2) return(list(sharpe = -Inf, n = length(bets), cumret_pct = NA_real_))
  list(sharpe = mean(bets) / sd(bets), n = length(bets), cumret_pct = sum(bets) * 100)
}

cat("Grid diagnostic (w, n_bets, Sharpe, cumulative return %) - printed before optimizing, since\n")
cat("small-n Kelly-staking Sharpe surfaces are noisy (see LONGSHOT_DECIMAL_ODDS_CAP's own grid\n")
cat("finding a thin, non-robust local bump) - a single optimizer result alone would hide that:\n\n")
grid_w <- seq(0, 1, by = 0.05)
grid_results <- lapply(grid_w, sharpe_for_weight)
grid_table <- data.frame(
  w = grid_w,
  n = vapply(grid_results, `[[`, integer(1), "n"),
  sharpe = vapply(grid_results, function(r) ifelse(is.infinite(r$sharpe), NA_real_, r$sharpe), numeric(1)),
  cumret_pct = vapply(grid_results, `[[`, numeric(1), "cumret_pct")
)
for (i in seq_len(nrow(grid_table))) {
  with(grid_table[i, ], cat(sprintf("  w=%.2f  n=%4d  sharpe=%9.4f  cumret_pct=%9.2f\n", w, n, sharpe, cumret_pct)))
}

cat("\nOptimizing MARKET_BLEND_WEIGHT via stats::optimize() (bounded [0, 1], maximizing Sharpe)...\n")
opt <- optimize(function(w) -sharpe_for_weight(w)$sharpe, interval = c(0, 1), tol = 1e-3)
best <- sharpe_for_weight(opt$minimum)
current <- sharpe_for_weight(MARKET_BLEND_WEIGHT)

cat(sprintf("\nCurrent production MARKET_BLEND_WEIGHT=%.3f: n=%d, Sharpe=%.4f, cumret_pct=%.2f\n",
            MARKET_BLEND_WEIGHT, current$n, current$sharpe, current$cumret_pct))
cat(sprintf("Sharpe-optimal weight: w=%.3f: n=%d, Sharpe=%.4f, cumret_pct=%.2f\n",
            opt$minimum, best$n, best$sharpe, best$cumret_pct))

out <- list(
  run_at = Sys.time(), n_games = nrow(games),
  grid_w = grid_w, grid_table = grid_table,
  current_weight = MARKET_BLEND_WEIGHT, current_result = current,
  sharpe_optimal_weight = opt$minimum, sharpe_optimal_result = best
)
saveRDS(out, file.path(CACHE_DIR, "market_blend_weight_sharpe_derivation.rds"))
cat("\nSaved derivation output to cache/market_blend_weight_sharpe_derivation.rds\n")
