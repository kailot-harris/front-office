# ==============================================================================
# tools/investigate_ev_clustering.R
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/investigate_ev_clustering.R
#
# Investigates docs/HANDOFF.md Known Issue #5: "essentially all Kelly-positive bets
# across every candidate tested are long-shot underdogs (~20-30% model win
# probability, ~18-19% actual win rate), clustering heavily in week 17
# (rest-players/meaningless-late-season-game noise). This looks like a structural
# quirk of the current EV computation finding 'value' in exactly the highest-
# variance, least-reliable part of the slate."
#
# Reuses tools/backtest_common.R's walk-forward game table and the PRODUCTION
# candidate (ensemble_ridge_elo, the formula actually deployed per docs/HANDOFF.md)
# exactly as tools/model_backtest_harness.R builds it - no second, independently-
# typed copy of the candidate formula (Finding C-1 discipline). This script does
# NOT touch config.R or any pipeline stage; it is read-only analysis over the
# existing walk-forward table, run once to characterize/confirm the clustering
# pattern and identify its root cause.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/investigate_ev_clustering.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/investigate_ev_clustering.R"

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

CALIBRATION_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("Building walk-forward game table (same as model_backtest_harness.R)...\n")
games <- build_walkforward_games(epa, completed, CALIBRATION_SEASONS, avg_plays_per_game)

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

home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
ridge_margin <- predict_ridge_massey_walkforward(games) - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
elo_margin   <- games$elo_margin_pts + games$fatigue_adj - QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
games$prob <- 0.5 * ridge_prob + 0.5 * elo_prob

# ------------------------------------------------------------------------------------------
# Reproduce the EXACT staking simulation from compute_backtest_metrics() (tools/
# model_backtest_harness.R), keeping every intermediate column so the clustering claim can be
# broken down by week/probability bucket rather than just re-confirmed in aggregate.
# ------------------------------------------------------------------------------------------
staking <- games |>
  filter(!is.na(home_ml), !is.na(away_ml)) |>
  mutate(
    model_away_prob = 1 - prob,
    home_dec = american_to_decimal(home_ml), away_dec = american_to_decimal(away_ml),
    home_ev = prob * home_dec - 1, away_ev = model_away_prob * away_dec - 1,
    pick_home = home_ev > away_ev,
    best_prob = if_else(pick_home, prob, model_away_prob),
    best_dec  = if_else(pick_home, home_dec, away_dec),
    best_ml   = if_else(pick_home, home_ml, away_ml),
    won       = if_else(pick_home, home_win == 1L, home_win == 0L),
    min_gp    = pmin(home_gp, away_gp),
    kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
    bet_return_pct = if_else(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)
  ) |>
  filter(min_gp >= MIN_SAMPLE_GAMES_FOR_STAKE, kelly_pct > 0)

cat(sprintf("\nTotal Kelly-positive bets at the production staking gate (tau=%d): %d\n",
            MIN_SAMPLE_GAMES_FOR_STAKE, nrow(staking)))
cat(sprintf("Overall win rate: %.1f%% | Mean model prob on the bet side: %.1f%% | Sharpe: %.4f\n",
            100 * mean(staking$won), 100 * mean(staking$best_prob),
            mean(staking$bet_return_pct) / sd(staking$bet_return_pct)))

cat("\n--- Underdog vs. favorite split (best_prob < 0.5 = underdog side picked) ---\n")
staking |>
  mutate(side = if_else(best_prob < 0.5, "underdog", "favorite")) |>
  group_by(side) |>
  summarise(n = n(), win_rate = mean(won), mean_prob = mean(best_prob),
            mean_kelly_pct = mean(kelly_pct), sharpe = mean(bet_return_pct) / sd(bet_return_pct),
            cum_return_pct = sum(bet_return_pct) * 100, .groups = "drop") |>
  print(n = Inf)

cat("\n--- By probability decile of the bet side (best_prob) ---\n")
staking |>
  mutate(prob_bin = cut(best_prob, breaks = seq(0, 1, 0.1), include.lowest = TRUE)) |>
  group_by(prob_bin) |>
  summarise(n = n(), win_rate = mean(won), mean_kelly_pct = mean(kelly_pct),
            cum_return_pct = sum(bet_return_pct) * 100, .groups = "drop") |>
  print(n = Inf)

cat("\n--- By week ---\n")
by_week <- staking |>
  group_by(week) |>
  summarise(n = n(), win_rate = mean(won), mean_prob = mean(best_prob),
            mean_kelly_pct = mean(kelly_pct), cum_return_pct = sum(bet_return_pct) * 100, .groups = "drop") |>
  arrange(desc(n))
print(by_week, n = Inf)

cat(sprintf("\nShare of all Kelly-positive bets in week 17: %.1f%% (%d of %d)\n",
            100 * sum(staking$week == 17) / nrow(staking), sum(staking$week == 17), nrow(staking)))
cat(sprintf("Week-17 subset: win rate %.1f%%, mean model prob %.1f%%, cum return %.1f%%\n",
            100 * mean(staking$won[staking$week == 17]),
            100 * mean(staking$best_prob[staking$week == 17]),
            sum(staking$bet_return_pct[staking$week == 17]) * 100))

# ------------------------------------------------------------------------------------------
# Root-cause probe: is the market-side "no-vig" probability itself biased for long-shot
# underdogs (the textbook "favorite-longshot bias" - bookmakers overround underdog lines more
# than favorite lines, so a naive 2-way devig under-corrects for longshots and leaves them
# looking cheaper than they truly are)? Compare best_prob (model, already market-blended at
# MARKET_BLEND_WEIGHT=0.97) against the RAW market implied probability on the same side,
# and check whether the market_blend's 2-way devig (american_to_prob() normalized by the
# 2-way overround only) is what's producing the apparent "edge" on longshots specifically.
# ------------------------------------------------------------------------------------------
cat("\n--- Root-cause probe: EV magnitude vs. best_prob (is EV inflated specifically at low prob?) ---\n")
staking |>
  mutate(ev_pct = if_else(pick_home, home_ev, away_ev) * 100,
         prob_bin = cut(best_prob, breaks = seq(0, 1, 0.1), include.lowest = TRUE)) |>
  group_by(prob_bin) |>
  summarise(n = n(), mean_ev_pct = mean(ev_pct), mean_kelly_pct = mean(kelly_pct), .groups = "drop") |>
  print(n = Inf)

cat("\nDone.\n")
