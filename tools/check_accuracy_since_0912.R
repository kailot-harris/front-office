# Independent accuracy check for all games from 2026-09-12 onward (per explicit user request).
#
# Follows the same distrust-the-log's-own-columns pattern as tools/check_accuracy_0916_0917.R
# (see that script's header for the two known defects this repeats defense-in-depth screens for):
#   1. WNBA_GAME_1..6 (9/14-9/16) are the hardcoded SYNTHETIC_FALLBACK fixture slate, logged
#      pre-provenance, permanently mislabeled market_data_source = "UNKNOWN" and (for 4 of the 6)
#      is_synthetic = FALSE by migrate_prediction_log()'s incomplete classifier.
#   2. Real rows logged 2026-09-17/09-18 (before LIVE_ODDS_API provenance existed that day) have
#      predicted_margin/contrib_* permanently NA - win/loss and Brier/log-loss are still scoreable
#      for these, margin MAE/RMSE/bias is not.
# This script scores every row from 2026-09-12 through the latest date with real box-score
# outcomes on file, splitting results by whether predicted_margin is available.
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
      stop(sprintf("check_accuracy_since_0912.R: cannot locate the repo root (no config.R at or above '%s')", start))
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

WINDOW_START <- as.Date("2026-09-12")

log <- readRDS("cache/prediction_accuracy_log.rds")
box <- readRDS(CACHE_TEAM_BOX)

window_log <- log |> filter(as.Date(game_date) >= WINDOW_START)

cat(sprintf("\n=== Prediction log rows from %s onward: %d ===\n", WINDOW_START, nrow(window_log)))

is_fixture_id <- grepl("^WNBA_GAME_[0-9]+$", window_log$game_id)

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

excluded <- window_log |> filter(is_fixture_id | is.na(home_score))
cat(sprintf("\n--- EXCLUDED (%d row(s)): fixture game_id and/or no matching real box-score outcome yet (PENDING/future/unresolved) ---\n",
            nrow(excluded)))
print(as.data.frame(excluded |> select(game_id, game_date, home_team, away_team, status,
                                        is_synthetic, market_data_source, is_fixture_id)))

scoreable <- window_log |> filter(!is_fixture_id & !is.na(home_score))

cat(sprintf("\n--- SCOREABLE (%d row(s)): real game_id, real matched box-score outcome ---\n", nrow(scoreable)))

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
                                         brier_indep, actual_margin_indep, predicted_margin,
                                         market_data_source)))

score_block <- function(df, label) {
  n <- nrow(df)
  if (n == 0) {
    cat(sprintf("\n=== %s: 0 rows, skipping ===\n", label))
    return(invisible(NULL))
  }
  win_acc <- mean(df$correct_indep)
  brier <- mean(df$brier_indep)
  log_loss <- mean(df$log_loss_indep)
  cat(sprintf("\n=== %s (N = %d) ===\n", label, n))
  cat(sprintf("Win/loss accuracy:  %.1f%% (%d/%d correct)\n", 100 * win_acc, sum(df$correct_indep), n))
  cat(sprintf("Brier score:        %.4f (0 = perfect, 0.25 = coin flip)\n", brier))
  cat(sprintf("Log loss:           %.4f\n", log_loss))
  n_margin <- sum(!is.na(df$predicted_margin))
  if (n_margin == 0) {
    cat("Margin-based metrics (MAE/RMSE/bias): UNAVAILABLE - predicted_margin is NA on every row in this block.\n")
  } else {
    m <- df |> filter(!is.na(predicted_margin)) |> mutate(residual = actual_margin_indep - predicted_margin)
    cat(sprintf("Margin-based metrics computed on %d/%d row(s) with a real predicted_margin:\n", n_margin, n))
    cat(sprintf("  MAE:  %.2f pts\n", mean(abs(m$residual))))
    cat(sprintf("  RMSE: %.2f pts\n", sqrt(mean(m$residual^2))))
    cat(sprintf("  Bias: %.2f pts (positive = model underpredicts home margin)\n", mean(m$residual)))
  }
}

score_block(scoreable, "ALL SCOREABLE ROWS SINCE 2026-09-12")
score_block(scoreable |> filter(market_data_source == "LIVE_ODDS_API"),
            "LIVE_ODDS_API rows only (post-provenance-fix, full margin data)")
score_block(scoreable |> filter(market_data_source == "UNKNOWN"),
            "UNKNOWN-provenance rows only (pre-fix, win/loss+Brier only, margin NA)")

cat(sprintf("\nNOTE: %d row(s) excluded above are the SYNTHETIC_FALLBACK fixture slate and/or still-PENDING/unresolved games with no real outcome yet - not included in any accuracy number above.\n",
            nrow(excluded)))
