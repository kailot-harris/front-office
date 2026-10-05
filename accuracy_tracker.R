# ==============================================================================
# accuracy_tracker.R
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/accuracy_tracker.R
#
# GitHub issue #5 (Accuracy Tracker 3) — detects newly-completed/graded CURRENT_SEASON games
# since the last recorded run and appends one row to cache/accuracy_history.rds (config.R's
# CACHE_ACCURACY_HISTORY) via tools/backtest_common.R's append_accuracy_history(). A run that
# finds nothing new graded since the last recorded row is a clean no-op — see
# docs/SPEC_accuracy_trajectory_monitoring.md decisions #3-#5 and CACHE_ACCURACY_HISTORY's own
# schema comment in config.R for the full design intent.
#
# OUT OF SCOPE for this script (separate follow-up issues — do not add here):
#   - Discord dispatch of any kind (issue #6).
#   - run_full_pipeline.R DAG wiring (issue #7).
#
# Exposes a single callable run_accuracy_tracker() — no sys.nframe()/!interactive() top-level
# auto-run guard, per this repo's established call_fn convention (see notify_bets.R's header
# comment and run_notify_bets() for the exact pattern this file replicates). source()ing this
# file from an orchestrator must never silently no-op by virtue of frame depth.
#
# GAME IDENTITY FOR NEW-VS-SEEN COMPARISON: grade_walkforward_games()'s returned `per_game`
# table (tools/backtest_common.R) does NOT carry nflverse `game_id` — it's already select()ed
# down to week/away_full/home_full/home_win_prob_prod/predicted_winner/actual_winner/correct/
# home_margin before being returned, and this script may not modify backtest_common.R (out of
# scope per this issue's brief). Within a single CURRENT_SEASON grading pass there is at most one
# game per (week, away_full, home_full) triple (NFL never schedules the same two teams against
# each other twice in the same week), so `paste(season, week, away_full, home_full)` is a safe,
# sufficient reconstructed unique key for this comparison — recorded in each history row's
# newly_graded_games$game_key column (in addition to the documented matchup/predicted_winner/
# actual_winner/correct/predicted_win_prob columns) purely for this script's own idempotency
# check, not a schema change to CACHE_ACCURACY_HISTORY's documented columns.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "c:/Users/kailo/kayceeslices/NFL Analytics/accuracy_tracker.R"
# (no auto-run at the bottom of this file — that invocation only loads function definitions
# unless a caller also calls run_accuracy_tracker()).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")

source("team_ratings_engine.R")      # -> compute_power_rating_points()
source("market_odds_engine.R")       # -> american_to_prob()
source("tools/backtest_common.R")    # -> grade_walkforward_games(), accuracy-history cache helpers
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R") # -> predict_ridge_massey_walkforward()
source("tools/elo_model.R")          # -> run_elo_walkforward()

# Set AFTER all of the above source() calls, not before: several of those sibling scripts
# (e.g. market_odds_engine.R) set their own top-level `.LOG_SCRIPT` global as a side effect of
# being sourced, which would otherwise silently clobber this file's own value and mislabel every
# log_info() call below as coming from the wrong script.
.LOG_SCRIPT <- "accuracy_tracker.R"

# Builds the reconstructed per-game identity key described in this file's header comment.
.accuracy_tracker_game_key <- function(season, per_game) {
  paste(season, per_game$week, per_game$away_full, per_game$home_full, sep = "|")
}

run_accuracy_tracker <- function() {
  log_info(sprintf("Starting accuracy tracker for season %d.", CURRENT_SEASON), script = .LOG_SCRIPT)

  epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
  sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
  fatigue <- readRDS(CACHE_FATIGUE_METRICS)

  graded <- grade_walkforward_games(epa, sch, fatigue, CURRENT_SEASON)

  if (nrow(graded$per_game) == 0) {
    log_info(sprintf("No completed %d games found in CACHE_SCHEDULES yet — nothing to grade.", CURRENT_SEASON),
             script = .LOG_SCRIPT)
    return(invisible(FALSE))
  }

  current_keys <- .accuracy_tracker_game_key(CURRENT_SEASON, graded$per_game)

  history <- load_accuracy_history()

  # Union of every game_key recorded in any prior run's newly_graded_games list-column, across
  # all history rows for this season — the full set of games this tracker has already recorded
  # as "newly graded" in some earlier run.
  seen_keys <- character(0)
  if (nrow(history) > 0) {
    season_rows <- history[history$season == CURRENT_SEASON, , drop = FALSE]
    if (nrow(season_rows) > 0) {
      seen_keys <- unlist(lapply(season_rows$newly_graded_games, function(df) {
        if (is.null(df) || !("game_key" %in% names(df))) return(character(0))
        df$game_key
      }), use.names = FALSE)
    }
  }

  new_mask <- !(current_keys %in% seen_keys)

  if (!any(new_mask)) {
    log_info(sprintf("No new completed games since the last recorded run (season %d, %d game(s) graded total, all already recorded).",
                      CURRENT_SEASON, nrow(graded$per_game)),
             script = .LOG_SCRIPT)
    return(invisible(FALSE))
  }

  newly_graded <- graded$per_game[new_mask, , drop = FALSE]
  newly_graded_games <- data.frame(
    game_key            = current_keys[new_mask],
    matchup              = paste(newly_graded$away_full, "@", newly_graded$home_full),
    predicted_winner     = newly_graded$predicted_winner,
    actual_winner        = newly_graded$actual_winner,
    correct              = as.logical(newly_graded$correct),
    predicted_win_prob   = newly_graded$home_win_prob_prod,
    stringsAsFactors = FALSE
  )

  updated <- append_accuracy_history(
    season = CURRENT_SEASON,
    newly_graded_games = newly_graded_games,
    overall_accuracy = graded$overall_accuracy,
    overall_brier = graded$overall_brier,
    overall_logloss = graded$overall_logloss,
    n_games_graded = nrow(graded$per_game)
  )

  log_info(sprintf("Appended accuracy-history row: %d newly-graded game(s) this run, %d total graded this season, accuracy=%.3f brier=%.4f logloss=%.4f.",
                    nrow(newly_graded_games), nrow(graded$per_game),
                    graded$overall_accuracy, graded$overall_brier, graded$overall_logloss),
           script = .LOG_SCRIPT)

  invisible(TRUE)
}
