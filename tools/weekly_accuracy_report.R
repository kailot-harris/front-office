# ==============================================================================
# Weekly Accuracy Report — walk-forward grading of CURRENT_SEASON's completed weeks
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/weekly_accuracy_report.R
#
# Answers "how accurate were the model's predictions for the weeks that have been played
# this season?" — a question the live pipeline cannot answer on its own, because
# cache/projected_matchups.rds only ever holds UPCOMING games (each pipeline run overwrites it),
# and cache/betting_ledger.rds only records a pick once a game clears MIN_SAMPLE_GAMES_FOR_STAKE
# (empty all season so far, since 2026 hasn't reached that many current-season games for any
# team yet). Neither cache is a historical record of what the model said before a played game's
# kickoff. This script reconstructs that record after the fact, walk-forward (no lookahead):
# for each completed CURRENT_SEASON week, every team's rating/Elo/QB-starter state is built
# using ONLY data strictly before that week's earliest kickoff (tools/backtest_common.R's
# build_walkforward_games()/build_week_snapshot() - the same no-lookahead discipline
# tools/model_backtest_harness.R uses for historical-season calibration, applied here to the
# in-progress season instead).
#
# FORMULA PARITY WITH PRODUCTION (must be kept in sync with team_ratings_engine.R's run_team_
# ratings() inner loop, ~lines 519-576, if that formula ever changes): ridge margin (Phase 2,
# tools/ridge_massey_model.R's fit_ridge_massey()/predict_ridge_massey_walkforward(), refit once
# per season) + Elo margin (Phase 3, tools/elo_model.R's run_elo_walkforward(), includes real
# fatigue_adj), each shifted by the QB-injury penalty (config.R's QB_INJURY_RATING_PENALTY_PTS)
# then pnorm()'d against NFL_MARGIN_SIGMA, each blended with historical market-implied probability
# at MARKET_BLEND_WEIGHT, then averaged 50/50 — this is exactly tools/model_backtest_harness.R's
# validated "ensemble_ridge_elo" candidate, which is why this script reuses that candidate's
# formula verbatim rather than re-deriving a third copy (CLAUDE.md's constant/logic-drift
# discipline applies to formulas here just as much as to bare numeric constants).
#
# CAVEATS (state these to the reader every run, not just in this comment):
#   - Small-sample: a handful of weeks is not enough to distinguish real edge from noise.
#   - Uses CURRENT state of EPA/Elo/QB-starter data, not necessarily what a live run would have
#     produced in real time that week (e.g. a late-breaking injury correction made after the
#     fact still flows into "as-of" snapshots built from today's cache).
#   - Grades the model's OWN formula, not the market-blended `Model_Win_Prob` column end users
#     saw in a specific historical cache/latest_value_bets.rds snapshot (that file is overwritten
#     every run and was never itself archived per-week).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/weekly_accuracy_report.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/weekly_accuracy_report.R"

source("team_ratings_engine.R")   # -> compute_power_rating_points()
source("market_odds_engine.R")    # -> american_to_prob()
source("tools/backtest_common.R") # -> build_walkforward_games()
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R") # -> predict_ridge_massey_walkforward()
source("tools/elo_model.R")          # -> run_elo_walkforward()

cat("==============================================================\n")
cat(sprintf("Weekly accuracy report for season %d — run at %s\n", CURRENT_SEASON, format(Sys.time())))
cat("==============================================================\n\n")

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

games <- build_walkforward_games(epa, completed, calibration_seasons = CURRENT_SEASON, avg_plays_per_game)

if (nrow(games) == 0) {
  cat(sprintf("No completed %d games found in CACHE_SCHEDULES yet — nothing to grade.\n", CURRENT_SEASON))
  quit(save = "no", status = 0)
}

cat(sprintf("Built %d walk-forward games for season %d (weeks: %s).\n\n",
            nrow(games), CURRENT_SEASON, paste(sort(unique(games$week)), collapse = ", ")))

# QB-backup flags (as-of, no lookahead — get_qb_starter_table()/compute_qb_backup_flags() only
# use each team's OWN starts strictly before the week in question, per tools/qb_injury_
# features.R's own header).
starter_tbl <- get_qb_starter_table(MODERN_ERA_START_SEASON:CURRENT_SEASON)
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- ifelse(is.na(games$home_ml) | is.na(games$away_ml), NA_real_, imp_h / (imp_h + imp_a))

# Elo run sequentially across full history THROUGH CURRENT_SEASON (unlike model_backtest_
# harness.R's historical-calibration run, which stops at CURRENT_SEASON - 1 on purpose) so its
# sequential state is properly warmed up including this season's own completed weeks.
cat("Simulating Elo sequentially across full history (through the current season)...\n")
elo_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score),
         season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON)
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
  select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")

blend_with_market <- function(model_prob, market_prob, weight) {
  ifelse(is.na(market_prob), model_prob, weight * market_prob + (1 - weight) * model_prob)
}

home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))

ridge_margin <- predict_ridge_massey_walkforward(games) -
  QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
elo_margin <- games$elo_margin_pts + games$fatigue_adj -
  QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj

ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
games$home_win_prob_prod <- 0.5 * ridge_prob + 0.5 * elo_prob

games <- games |>
  mutate(
    predicted_home_win = home_win_prob_prod > 0.5,
    correct = as.integer(predicted_home_win == (home_win == 1L)),
    home_full = NFL_TEAMS[home_team],
    away_full = NFL_TEAMS[away_team],
    actual_winner = ifelse(home_win == 1, home_full, away_full),
    predicted_winner = ifelse(predicted_home_win, home_full, away_full)
  )

per_game <- games |>
  arrange(week, desc(home_win_prob_prod)) |>
  select(week, away_full, home_full, home_win_prob_prod, predicted_winner, actual_winner, correct, home_margin)

by_week <- games |>
  group_by(week) |>
  summarise(
    n = dplyr::n(),
    accuracy = mean(correct),
    brier = mean((home_win_prob_prod - home_win)^2),
    .groups = "drop"
  )

overall_accuracy <- mean(games$correct)
overall_brier <- mean((games$home_win_prob_prod - games$home_win)^2)
overall_logloss <- {
  p <- pmin(pmax(games$home_win_prob_prod, 1e-6), 1 - 1e-6)
  -mean(games$home_win * log(p) + (1 - games$home_win) * log(1 - p))
}

cat("=== Per-game results (production formula: ensemble ridge+elo, QB-injury-adjusted, market-blended) ===\n")
for (i in seq_len(nrow(per_game))) {
  r <- per_game[i, ]
  mark <- if (r$correct == 1) "correct" else "MISS"
  cat(sprintf("Wk%d %-28s @ %-28s HomeWinProb=%.3f Pred=%-24s Actual=%-24s [%s]\n",
              r$week, r$away_full, r$home_full, r$home_win_prob_prod,
              r$predicted_winner, r$actual_winner, mark))
}

cat("\n=== By week ===\n")
print(as.data.frame(by_week), row.names = FALSE)

cat(sprintf("\nOverall (n=%d games): accuracy=%.1f%%  Brier=%.4f  log-loss=%.4f\n",
            nrow(games), 100 * overall_accuracy, overall_brier, overall_logloss))
cat("(Brier 0.25 / log-loss 0.693 = coin-flip baseline; lower is better for both.)\n")
cat("\nCaveats: small sample (season-to-date only); uses TODAY's EPA/Elo/QB-starter state for\n")
cat("as-of snapshots, not necessarily what a live run produced in real time that week; grades\n")
cat("the model's own formula, not any specific historical cache/latest_value_bets.rds snapshot\n")
cat("(that file is overwritten every pipeline run and was never archived per-week).\n")

saveRDS(
  list(per_game = per_game, by_week = by_week, overall_accuracy = overall_accuracy,
       overall_brier = overall_brier, overall_logloss = overall_logloss, run_at = Sys.time(),
       season = CURRENT_SEASON),
  file.path(CACHE_DIR, "weekly_accuracy_report.rds")
)
cat("\nSaved full report to cache/weekly_accuracy_report.rds\n")
