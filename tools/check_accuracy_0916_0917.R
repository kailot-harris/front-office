# Independent, one-off accuracy check for 2026-09-16 / 2026-09-17.
#
# Deliberately does NOT trust cache/prediction_accuracy_log.rds's own is_synthetic /
# correct / actual_winner / actual_margin columns - those are re-derived here directly
# from the raw box score cache, as a second, independent check. Two real defects found
# in this repo already motivate that distrust:
#   1. predicted_margin/contrib_* are NA on every real resolved row logged so far
#      (app.R's Model Diagnostics tab, fixed 2026-09-18 to show an honest placeholder
#      instead of a blank chart - see docs/HANDOFF.md).
#   2. The 2026-09-16 rows (game_id WNBA_GAME_5/WNBA_GAME_6) are the literal
#      SYNTHETIC_FALLBACK fixture slate from market_odds_engine.R's fetch_market_odds()
#      (matchups match verbatim: Phoenix Mercury vs. Dallas Wings, Indiana Fever vs.
#      Connecticut Sun), logged 2026-09-12 - before market_data_source provenance
#      existed in that day's cache - so migrate_prediction_log()'s backfill defaulted
#      them to market_data_source = "UNKNOWN" / is_synthetic = FALSE. That migration's
#      classifier only checks a DIAG_ game_id prefix or injury_data_source ==
#      "DIAGNOSTIC"; it has no rule for the WNBA_GAME_N fixture pattern, so these two
#      fixture rows are permanently mislabeled as real in the log itself.
# This script screens for both known synthetic signatures independently and only
# scores predictions against a real, matched box-score outcome.
# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
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
      stop(sprintf("check_accuracy_0916_0917.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
suppressMessages({
  library(dplyr)
  library(stringr)
})
source("config.R")

WINDOW_DATES <- as.Date(c("2026-09-16", "2026-09-17"))

log <- readRDS("cache/prediction_accuracy_log.rds")
box <- readRDS(CACHE_TEAM_BOX)

window_log <- log |> filter(as.Date(game_date) %in% WINDOW_DATES)

cat(sprintf("\n=== Prediction log rows for %s to %s: %d ===\n",
            WINDOW_DATES[1], WINDOW_DATES[2], nrow(window_log)))

# Independent synthetic screen #1: known fixture game_id pattern (market_odds_engine.R's
# fetch_market_odds() fallback uses "WNBA_GAME_<1-6>" literally - not a config.R constant,
# just this script's own defense-in-depth check against the exact known signature).
is_fixture_id <- grepl("^WNBA_GAME_[0-9]+$", window_log$game_id)

# Independent synthetic screen #2: does a real completed game actually exist for this
# (game_date, home_team) pair in the raw box score cache? A row that claims RESOLVED/
# PENDING against a date with zero real games for that matchup cannot be a real,
# scoreable prediction regardless of what is_synthetic says.
home_games <- box |>
  filter(team_home_away == "home") |>
  mutate(game_date = as.Date(game_date)) |>
  select(game_date, home_abbr = team_abbreviation, away_abbr = opponent_team_abbreviation,
         home_score = team_score, away_score = opponent_team_score, home_win = team_winner) |>
  distinct()

window_log <- window_log |>
  mutate(
    game_date = as.Date(game_date),
    is_fixture_id = is_fixture_id
  ) |>
  left_join(home_games, by = c("game_date" = "game_date", "home_team" = "home_abbr"))

flagged <- window_log |> filter(is_fixture_id | is.na(home_score))
if (nrow(flagged) > 0) {
  cat(sprintf("\n--- EXCLUDED (%d row(s)): fixture game_id pattern and/or no matching real game in %s ---\n",
              nrow(flagged), CACHE_TEAM_BOX))
  print(as.data.frame(flagged |> select(game_id, game_date, home_team, away_team, status,
                                         is_synthetic, market_data_source, is_fixture_id)))
}

scoreable <- window_log |> filter(!is_fixture_id & !is.na(home_score))

cat(sprintf("\n--- SCOREABLE (%d row(s)): real game_id, real matched box score outcome ---\n", nrow(scoreable)))

if (nrow(scoreable) == 0) {
  cat("No real, independently-verifiable predictions in this window. Stopping.\n")
  quit(status = 0)
}

scoreable <- scoreable |>
  mutate(
    actual_winner_indep = if_else(home_win, home_team, away_team),
    correct_indep        = predicted_winner == actual_winner_indep,
    actual_home_win      = as.integer(home_win),
    p_clamped            = pmin(pmax(predicted_home_win_prob, 1e-6), 1 - 1e-6),
    brier_indep          = (predicted_home_win_prob - actual_home_win)^2,
    log_loss_indep       = -(actual_home_win * log(p_clamped) + (1 - actual_home_win) * log(1 - p_clamped)),
    actual_margin_indep  = home_score - away_score
  )

print(as.data.frame(scoreable |> select(game_id, game_date, home_team, away_team,
                                         predicted_home_win_prob, predicted_winner,
                                         actual_winner_indep, correct_indep,
                                         brier_indep, actual_margin_indep, predicted_margin)))

n <- nrow(scoreable)
win_acc <- mean(scoreable$correct_indep)
brier <- mean(scoreable$brier_indep)
log_loss <- mean(scoreable$log_loss_indep)
n_margin <- sum(!is.na(scoreable$predicted_margin))

cat("\n=== Independently-recomputed accuracy, real games only ===\n")
cat(sprintf("N (real, box-score-verified) predictions: %d\n", n))
cat(sprintf("Win/loss accuracy:  %.1f%% (%d/%d correct)\n", 100 * win_acc, sum(scoreable$correct_indep), n))
cat(sprintf("Brier score:        %.4f (0 = perfect, 0.25 = coin flip)\n", brier))
cat(sprintf("Log loss:           %.4f\n", log_loss))
if (n_margin == 0) {
  cat("Margin-based metrics (MAE/RMSE/bias): UNAVAILABLE - predicted_margin is NA on all rows in this window (see header comment, same bug behind the Model Diagnostics tab's empty charts).\n")
} else {
  m <- scoreable |> filter(!is.na(predicted_margin)) |> mutate(residual = actual_margin_indep - predicted_margin)
  cat(sprintf("Margin-based metrics computed on %d/%d row(s) with a real predicted_margin:\n", n_margin, n))
  cat(sprintf("  MAE:  %.2f pts\n", mean(abs(m$residual))))
  cat(sprintf("  RMSE: %.2f pts\n", sqrt(mean(m$residual^2))))
  cat(sprintf("  Bias: %.2f pts (positive = model underpredicts home margin)\n", mean(m$residual)))
}

if (nrow(flagged) > 0) {
  cat(sprintf("\nNOTE: %d row(s) excluded above were the SYNTHETIC_FALLBACK fixture slate mislabeled is_synthetic=FALSE in the log (pre-M-5-provenance rows) - do not include them in any accuracy claim for this window.\n",
              nrow(flagged)))
}
