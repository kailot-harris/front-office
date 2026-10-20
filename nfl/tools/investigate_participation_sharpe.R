# ==============================================================================
# Investigation: is ridge_participation_phase1_combined's +0.0017 Sharpe (n=262) real?
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/investigate_participation_sharpe.R
#
# tools/model_backtest_harness.R reported the FIRST non-negative Sharpe value in this entire
# remediation arc's 18-candidate comparison: ridge_participation_phase1_combined,
# Sharpe = +0.0017 at n=262 bets (tau_best=9, matching the current production gate exactly).
# Every other candidate this session has been solidly negative (-0.02 to -0.22). Before treating
# +0.0017 as anything other than noise, this script asks three concrete questions the single
# summary number can't answer on its own:
#   1. Does the positive Sharpe hold across a WIDER tau grid, or is tau=9 an isolated point in
#      an otherwise-negative surface (same "thin, non-robust bump" pattern already found and
#      flagged for LONGSHOT_DECIMAL_ODDS_CAP's cap=4.0 result)?
#   2. What's the bootstrap confidence interval on this Sharpe estimate? A point estimate with
#      no uncertainty band is not evidence by itself, especially at n=262.
#   3. Does the positive result concentrate in seasons with REAL participation coverage (2016+),
#      or is it driven by the 2003-2015 zero-imputed years (in which case the participation
#      feature is contributing nothing and the result is pure ridge/QB/market-blend noise)?
#
# Precedent: tools/investigate_ev_clustering.R (same "don't just report the summary number,
# look at the actual bet-level distribution" discipline).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/investigate_participation_sharpe.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/investigate_participation_sharpe.R"

source("team_ratings_engine.R")
source("market_odds_engine.R")
source("tools/backtest_common.R")
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R")
source("tools/ridge_participation_model.R")

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

CALIBRATION_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("Investigating ridge_participation_phase1_combined's positive-Sharpe result -", format(Sys.time()), "\n")
cat("==============================================================\n\n")

games <- build_walkforward_games(epa, completed, CALIBRATION_SEASONS, avg_plays_per_game) |>
  filter(!is.na(home_ml), !is.na(away_ml))
cat(sprintf("Built %d walk-forward games with real historical moneylines.\n", nrow(games)))

starter_tbl <- get_qb_starter_table((MODERN_ERA_START_SEASON):(CURRENT_SEASON - 1L))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- ifelse(is.na(games$home_ml) | is.na(games$away_ml), NA_real_, imp_h / (imp_h + imp_a))

part_features <- readRDS(CACHE_PARTICIPATION_FEATURES) |> mutate(game_date = as.Date(game_date))
games <- attach_participation_asof(games, part_features)
cat(sprintf("Games with real participation history for BOTH teams: %d/%d.\n\n",
            sum(!is.na(games$home_off_personnel_11_rate_roll) & !is.na(games$away_off_personnel_11_rate_roll)),
            nrow(games)))

# ------------------------------------------------------------------------------------------
# Reconstruct ridge_participation_phase1_combined's probability vector exactly as
# model_backtest_harness.R's candidate does.
# ------------------------------------------------------------------------------------------
home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
part_margin <- predict_ridge_participation_walkforward(games) - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
part_prob <- MARKET_BLEND_WEIGHT * games$market_prob + (1 - MARKET_BLEND_WEIGHT) * pnorm(part_margin / NFL_MARGIN_SIGMA)
part_prob <- ifelse(is.na(games$market_prob), pnorm(part_margin / NFL_MARGIN_SIGMA), part_prob)

# Baseline for comparison: the currently-deployed ensemble_ridge_elo.
ridge_margin_raw <- predict_ridge_massey_walkforward(games)
source("tools/elo_model.R")
fatigue <- readRDS(CACHE_FATIGUE_METRICS)
elo_full_history <- sch |> filter(!is.na(home_score), !is.na(away_score), season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |> select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")
ridge_margin <- ridge_margin_raw - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
elo_margin   <- games$elo_margin_pts + games$fatigue_adj - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
blend_one <- function(model_prob) ifelse(is.na(games$market_prob), model_prob, MARKET_BLEND_WEIGHT * games$market_prob + (1 - MARKET_BLEND_WEIGHT) * model_prob)
ensemble_prob <- 0.5 * blend_one(pnorm(ridge_margin / NFL_MARGIN_SIGMA)) + 0.5 * blend_one(pnorm(elo_margin / NFL_MARGIN_SIGMA))

# ------------------------------------------------------------------------------------------
# build_staking(): the same staking-simulation shape as model_backtest_harness.R's
# compute_backtest_metrics(), returning the per-game bet-level table (not just a summary).
# ------------------------------------------------------------------------------------------
build_staking <- function(prob) {
  p <- pmin(pmax(prob, 1e-6), 1 - 1e-6)
  games |> mutate(
    prob = p, model_away_prob = 1 - p,
    home_dec = american_to_decimal(home_ml), away_dec = american_to_decimal(away_ml),
    home_ev = p * home_dec - 1, away_ev = model_away_prob * away_dec - 1,
    pick_home = home_ev > away_ev,
    best_prob = if_else(pick_home, p, model_away_prob),
    best_dec  = if_else(pick_home, home_dec, away_dec),
    won       = if_else(pick_home, home_win == 1L, home_win == 0L),
    min_gp    = pmin(home_gp, away_gp),
    kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
    bet_return_pct = if_else(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)
  )
}

staking_part <- build_staking(part_prob)
staking_base <- build_staking(ensemble_prob)

sharpe_for_tau <- function(staking, tau, cap = LONGSHOT_DECIMAL_ODDS_CAP) {
  bets <- staking |> filter(min_gp >= tau, kelly_pct > 0, best_dec <= cap)
  if (nrow(bets) < 2) return(list(sharpe = NA_real_, n = nrow(bets), ret = NA_real_))
  list(sharpe = mean(bets$bet_return_pct) / sd(bets$bet_return_pct), n = nrow(bets), ret = sum(bets$bet_return_pct))
}

# ------------------------------------------------------------------------------------------
# Q1: full tau grid, side by side with the deployed baseline.
# ------------------------------------------------------------------------------------------
cat("=== Q1: Sharpe across the FULL tau grid (participation candidate vs. deployed baseline) ===\n")
cat(sprintf("%5s %8s %10s %10s | %8s %10s %10s\n", "tau", "n_part", "sharpe_p", "ret_p", "n_base", "sharpe_b", "ret_b"))
for (tau in 0:15) {
  rp <- sharpe_for_tau(staking_part, tau)
  rb <- sharpe_for_tau(staking_base, tau)
  cat(sprintf("%5d %8d %10s %10s | %8d %10s %10s\n",
              tau, rp$n, ifelse(is.na(rp$sharpe), "NA", sprintf("%.4f", rp$sharpe)), ifelse(is.na(rp$ret), "NA", sprintf("%.2f", rp$ret)),
              rb$n, ifelse(is.na(rb$sharpe), "NA", sprintf("%.4f", rb$sharpe)), ifelse(is.na(rb$ret), "NA", sprintf("%.2f", rb$ret))))
}

# ------------------------------------------------------------------------------------------
# Q2: bootstrap CI on the tau=9 result (the one the harness reported).
# ------------------------------------------------------------------------------------------
cat("\n=== Q2: Bootstrap 95% CI on Sharpe at tau=9 (10,000 resamples, sampling WITH replacement) ===\n")
set.seed(20260917)
bets_at_9 <- staking_part |> filter(min_gp >= MIN_SAMPLE_GAMES_FOR_STAKE, kelly_pct > 0, best_dec <= LONGSHOT_DECIMAL_ODDS_CAP)
n_boot <- 10000
boot_sharpes <- vapply(seq_len(n_boot), function(i) {
  s <- sample(bets_at_9$bet_return_pct, size = nrow(bets_at_9), replace = TRUE)
  if (sd(s) == 0) return(NA_real_)
  mean(s) / sd(s)
}, numeric(1))
boot_sharpes <- boot_sharpes[!is.na(boot_sharpes)]
ci <- quantile(boot_sharpes, c(0.025, 0.5, 0.975))
cat(sprintf("n bets = %d\n", nrow(bets_at_9)))
cat(sprintf("Observed Sharpe = %.4f\n", mean(bets_at_9$bet_return_pct) / sd(bets_at_9$bet_return_pct)))
cat(sprintf("Bootstrap 95%% CI: [%.4f, %.4f], median %.4f\n", ci[1], ci[3], ci[2]))
cat(sprintf("Fraction of bootstrap resamples with Sharpe > 0: %.1f%%\n", mean(boot_sharpes > 0) * 100))
cat("(A CI that comfortably straddles zero, with roughly half the resamples on each side, means\n")
cat(" this point estimate is NOT distinguishable from a zero-edge/pure-noise strategy.)\n")

# ------------------------------------------------------------------------------------------
# Q3: does the result concentrate in real-participation-coverage seasons (2016+)?
# ------------------------------------------------------------------------------------------
cat("\n=== Q3: bet season distribution - does this rely on real participation data at all? ===\n")
cat("Season counts among the tau=9 bets:\n")
print(table(bets_at_9$season))
n_real_coverage <- sum(bets_at_9$season >= PARTICIPATION_MIN_SEASON)
cat(sprintf("\n%d/%d (%.1f%%) of these bets are in seasons with REAL participation coverage (>= %d).\n",
            n_real_coverage, nrow(bets_at_9), 100 * n_real_coverage / nrow(bets_at_9), PARTICIPATION_MIN_SEASON))

same_pick_as_baseline <- bets_at_9$game_id %in% (staking_base |> filter(min_gp >= MIN_SAMPLE_GAMES_FOR_STAKE, kelly_pct > 0, best_dec <= LONGSHOT_DECIMAL_ODDS_CAP))$game_id
cat(sprintf("%d/%d of the participation candidate's tau=9 bets are on the SAME game_id the deployed baseline also bets on.\n",
            sum(same_pick_as_baseline), length(same_pick_as_baseline)))

cat("\n==============================================================\n")
cat("Done. See docs/HANDOFF.md for the interpretation of these results.\n")
cat("==============================================================\n")

saveRDS(list(
  run_at = Sys.time(),
  tau_grid_part = lapply(0:15, function(t) sharpe_for_tau(staking_part, t)),
  tau_grid_base = lapply(0:15, function(t) sharpe_for_tau(staking_base, t)),
  bootstrap_ci = ci, boot_sharpes = boot_sharpes,
  bets_at_9 = bets_at_9 |> select(game_id, season, week, home_team, away_team, best_dec, kelly_pct, won, bet_return_pct)
), file.path(CACHE_DIR, "participation_sharpe_investigation.rds"))
cat("Saved full investigation output to cache/participation_sharpe_investigation.rds\n")
