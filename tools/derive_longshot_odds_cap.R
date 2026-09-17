# ==============================================================================
# Long-Shot Staking Odds Cap - Empirical Derivation
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/derive_longshot_odds_cap.R
#
# Investigates and mitigates docs/HANDOFF.md Known Issue #5: tools/
# investigate_ev_clustering.R (run 2026-09-17, see that script's output) confirmed
# the pattern against the PRODUCTION candidate (ensemble_ridge_elo):
#   - 100% (124/124) of Kelly-positive bets at the production staking gate
#     (tau=MIN_SAMPLE_GAMES_FOR_STAKE=9) are on the underdog side (best_prob < 0.5).
#   - Mean EV% is strictly DECREASING as best_prob rises (2.26% in the [0,0.1] bin
#     down to 0.46% in the (0.4,0.5] bin) - the "edge" the model finds gets larger,
#     not smaller, the longer the odds.
#   - 29% of all Kelly-positive bets cluster in week 17 alone (36/124, next-highest
#     week is 15 with 15 bets) - consistent with real rest-players/meaningless-
#     late-season-game noise (teams resting starters ahead of the playoffs).
#
# ROOT CAUSE (identified via investigate_ev_clustering.R's root-cause probe):
# home_ev/away_ev is computed as `model_prob * decimal_odds - 1`. Since
# MARKET_BLEND_WEIGHT=0.97 anchors 97% of model_prob to the game's OWN devigged
# market probability (games$market_prob is derived from the SAME home_ml/away_ml
# used for decimal_odds here), the apparent edge is driven almost entirely by the
# model's remaining 3% weight's disagreement with the market. That disagreement is
# a roughly FIXED absolute probability delta, but decimal_odds scales inversely
# with market probability - so the SAME absolute model/market disagreement produces
# a small EV% at short (favorite) odds and an explosive EV% at long (underdog)
# odds, purely as an artifact of the p*dec-1 formula's odds-scaling, not because
# the model is more accurate on long shots. This is worst exactly where the
# model's own signal is noisiest (backup QBs, rested starters, week-17
# clinched-playoff-seed games) - the mechanism and the noisiest data line up.
#
# MITIGATION: rather than loosen/replace the deployed Kelly fraction (0.25) or its
# 3% cap (explicitly NOT to be done "to compensate", per market_odds_engine.R's own
# header and docs/task_assignments_phase5.md's Constraints), gate staking OUT of
# the underdog decimal-odds region where this artifact concentrates. Backtested the
# same way as MIN_SAMPLE_GAMES_FOR_STAKE (tools/backtest_shrinkage_optimizer.R
# precedent): stats::optimize() maximizing Sharpe of the real quarter-Kelly staking
# simulation against REAL historical closing moneylines, reusing
# tools/model_backtest_harness.R's exact "ensemble_ridge_elo" production formula
# (never re-typed - sourced from that file's own candidate list) and
# tools/backtest_common.R's game table (same no-lookahead discipline).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_longshot_odds_cap.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_longshot_odds_cap.R"

source("team_ratings_engine.R")
source("market_odds_engine.R")
source("tools/backtest_common.R")
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R")
source("tools/elo_model.R")

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

# Same window as MIN_SAMPLE_GAMES_FOR_STAKE/MARKET_BLEND_WEIGHT's own derivation - real
# historical closing moneylines only exist in CACHE_SCHEDULES from 2010 onward.
STAKING_SEASONS <- 2010L:(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("Long-shot staking odds cap derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

cat("Building walk-forward game table (seasons", min(STAKING_SEASONS), "-", max(STAKING_SEASONS), ")...\n")
games <- build_walkforward_games(epa, completed, STAKING_SEASONS, avg_plays_per_game)

starter_tbl <- get_qb_starter_table((MODERN_ERA_START_SEASON):(CURRENT_SEASON - 1L))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- ifelse(is.na(games$home_ml) | is.na(games$away_ml), NA_real_, imp_h / (imp_h + imp_a))

elo_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score), season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
  select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")

blend_with_market <- function(model_prob, market_prob, weight) {
  ifelse(is.na(market_prob), model_prob, weight * market_prob + (1 - weight) * model_prob)
}

# PRODUCTION formula (ensemble_ridge_elo), reproduced identically to
# tools/model_backtest_harness.R's candidate of the same name - never re-derive this
# independently (Finding C-1 discipline).
home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
ridge_margin <- predict_ridge_massey_walkforward(games) - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
elo_margin   <- games$elo_margin_pts + games$fatigue_adj - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
games$prob <- 0.5 * ridge_prob + 0.5 * elo_prob

staking_base <- games |>
  filter(!is.na(home_ml), !is.na(away_ml)) |>
  mutate(
    model_away_prob = 1 - prob,
    home_dec = american_to_decimal(home_ml), away_dec = american_to_decimal(away_ml),
    home_ev = prob * home_dec - 1, away_ev = model_away_prob * away_dec - 1,
    pick_home = home_ev > away_ev,
    best_prob = if_else(pick_home, prob, model_away_prob),
    best_dec  = if_else(pick_home, home_dec, away_dec),
    won       = if_else(pick_home, home_win == 1L, home_win == 0L),
    min_gp    = pmin(home_gp, away_gp),
    kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
    bet_return_pct = if_else(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)
  ) |>
  filter(min_gp >= MIN_SAMPLE_GAMES_FOR_STAKE, kelly_pct > 0)

sharpe_at_cap <- function(cap) {
  bets <- staking_base |> filter(best_dec <= cap)
  if (nrow(bets) < 2) return(list(sharpe = -Inf, n = nrow(bets), ret = NA_real_))
  list(sharpe = mean(bets$bet_return_pct) / sd(bets$bet_return_pct), n = nrow(bets),
       ret = sum(bets$bet_return_pct) * 100)
}

no_cap <- sharpe_at_cap(Inf)
cat(sprintf("No cap (current production behavior): n_bets=%d  Sharpe=%.4f  cumulative pct return=%.1f%%\n",
            no_cap$n, no_cap$sharpe, no_cap$ret))

cat("\nOptimizing a decimal-odds staking cap via stats::optimize() (bounded [1.5, 15], golden-section search)...\n")
opt <- optimize(function(cap) -sharpe_at_cap(cap)$sharpe, interval = c(1.5, 15), tol = 0.05)
opt_result <- sharpe_at_cap(opt$minimum)
cat(sprintf("Optimizer result: cap=%.2f (decimal odds) -> n_bets=%d  Sharpe=%.4f  cumulative pct return=%.1f%%\n",
            opt$minimum, opt_result$n, opt_result$sharpe, opt_result$ret))

cat("\nGrid for reference (decimal odds cap -> Sharpe/n/cum%):\n")
grid <- c(2, 2.5, 3, 3.5, 4, 5, 6, 8, 10, 12, 15)
for (g in grid) {
  r <- sharpe_at_cap(g)
  cat(sprintf("  cap=%5.1f  n=%4d  Sharpe=%8.4f  cum_return=%8.1f%%\n", g, r$n, r$sharpe, r$ret))
}

cat(sprintf("\nRECOMMENDATION for config.R: LONGSHOT_DECIMAL_ODDS_CAP <- %.1f\n", round(opt$minimum, 1)))
cat(sprintf("(derived from %d walk-forward games with real historical moneylines and >= %d games played,\n",
            nrow(staking_base), MIN_SAMPLE_GAMES_FOR_STAKE))
cat(sprintf(" seasons %d-%d, production ensemble_ridge_elo formula)\n", min(STAKING_SEASONS), max(STAKING_SEASONS)))

out <- list(
  run_at = Sys.time(),
  n_games_eligible = nrow(staking_base),
  seasons = STAKING_SEASONS,
  no_cap = no_cap,
  cap_optimal = opt$minimum,
  result_at_optimal = opt_result,
  grid = setNames(lapply(grid, sharpe_at_cap), grid)
)
saveRDS(out, file.path(CACHE_DIR, "longshot_odds_cap_derivation.rds"))
cat("\nSaved derivation output to cache/longshot_odds_cap_derivation.rds\n")
