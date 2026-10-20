# ==============================================================================
# Weekly Accuracy Report — walk-forward grading of CURRENT_SEASON's completed weeks
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/weekly_accuracy_report.R
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

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
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
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

# grade_walkforward_games() (tools/backtest_common.R) does its own internal build_walkforward_
# games() call (including the empty-games early return) and runs the full QB-backup / market-
# blend / Elo-simulation / ridge+Elo-ensemble grading in one shot. We derive the pre-existing
# "No completed games" guard and "Built N walk-forward games..." message from its per_game
# output (nrow/week column) rather than calling build_walkforward_games() a second time
# ourselves, so console output stays byte-for-byte identical to the old inlined version without
# redoing that work.
result <- grade_walkforward_games(epa, sch, fatigue, CURRENT_SEASON)

if (nrow(result$per_game) == 0) {
  cat(sprintf("No completed %d games found in CACHE_SCHEDULES yet — nothing to grade.\n", CURRENT_SEASON))
  quit(save = "no", status = 0)
}

per_game <- result$per_game
by_week <- result$by_week
overall_accuracy <- result$overall_accuracy
overall_brier <- result$overall_brier
overall_logloss <- result$overall_logloss

cat(sprintf("Built %d walk-forward games for season %d (weeks: %s).\n\n",
            nrow(per_game), CURRENT_SEASON, paste(sort(unique(per_game$week)), collapse = ", ")))

cat("Simulating Elo sequentially across full history (through the current season)...\n")

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
            nrow(per_game), 100 * overall_accuracy, overall_brier, overall_logloss))
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
