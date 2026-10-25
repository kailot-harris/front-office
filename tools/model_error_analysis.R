# ==============================================================================
# model_error_analysis.R
# Path: tools/model_error_analysis.R
#
# Rigorous error analysis for model projections.
# Calculates residuals (Actual - Predicted) and segments them to identify
# systemic failure patterns in the probabilistic margin model.
# ==============================================================================

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
      stop(sprintf("model_error_analysis.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "model_error_analysis.R"

# ------------------------------------------------------------------------------
# Core Analysis Function
# ------------------------------------------------------------------------------
run_error_analysis <- function() {
  cat("\n==================================================================\n")
  cat("           WNBA MODEL ERROR & RESIDUAL ANALYSIS TOOL           \n")
  cat("==================================================================\n\n")

  # 1. Load Data
  log_path <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
  box_path <- CACHE_TEAM_BOX

  if (!file.exists(log_path)) {
    log_error("Prediction accuracy log not found; cannot perform error analysis.", call = "run_error_analysis()")
    stop("Prediction log missing.")
  }
  if (!file.exists(box_path)) {
    log_error("Box scores cache not found; cannot perform error analysis.", call = "run_error_analysis()")
    stop("Box scores cache missing.")
  }

  pred_log <- readRDS(log_path)
  box_scores <- readRDS(box_path)

  # Only analyze resolved games that have margin data
  resolved <- pred_log |> filter(status == "RESOLVED")
  if (nrow(resolved) == 0) {
    cat("[INFO] No RESOLVED predictions found in log. Skipping analysis.\n")
    return(invisible(NULL))
  }

  # 2. Calculate Actual Margins and Residuals
  # We join on (home_team, game_date) as established in prediction_accuracy_logger.R
  # Note: box_scores_cache is team-centric; we need to find the game outcome.
  # box_scores_cache usually has home/away indicators.

  # Get actual game outcomes
  game_outcomes <- box_scores |>
    filter(team_home_away == "home") |>
    mutate(game_date = as.Date(game_date)) |>
    select(game_date, home_team_short = team_short_display_name,
           home_score = team_score, away_score = opponent_team_score) |>
    distinct()

  # Normalize log home_team (abbreviation) to short-nickname for join
  # (Reuse logic from prediction_accuracy_logger.R)
  resolved <- resolved |>
    mutate(.home_short = word(unname(WNBA_TEAMS[home_team]), -1))

  analysis_df <- resolved |>
    inner_join(game_outcomes, by = c("game_date" = "game_date", ".home_short" = "home_team_short")) |>
    mutate(
      actual_margin    = home_score - away_score,
      residual          = actual_margin - predicted_margin,
      abs_residual      = abs(residual)
    )

  if (nrow(analysis_df) == 0) {
    cat("[INFO] No games matched between prediction log and box scores. Skipping.\n")
    return(invisible(NULL))
  }

  # 3. Global Metrics
  mae <- mean(analysis_df$abs_residual, na.rm = TRUE)
  rmse <- sqrt(mean(analysis_df$residual^2, na.rm = TRUE))
  bias <- mean(analysis_df$residual, na.rm = TRUE)

  cat(sprintf("Global Performance (N = %d):\n", nrow(analysis_df)))
  cat(sprintf("  - Mean Absolute Error (MAE): %.2f points\n", mae))
  cat(sprintf("  - Root Mean Square Error (RMSE): %.2f points\n", rmse))
  cat(sprintf("  - Mean Bias: %.2f (Positive = Underpredicted Home, Negative = Overpredicted Home)\n\n", bias))

  # 4. Segmented Analysis: By Team
  cat("--- Failure Patterns: By Team ---\n")
  team_error <- analysis_df |>
    group_by(home_team) |>
    summarise(
      n = n(),
      mean_res = mean(residual, na.rm = TRUE),
      mae = mean(abs_residual, na.rm = TRUE),
      .groups = "drop"
    ) |>
    arrange(desc(abs(mean_res)))

  print(knitr::kable(team_error, format = "simple"))
  cat("\n")

  # 5. Segmented Analysis: By Component (Contribution Decomposition)
  cat("--- Contribution Analysis (Residual Correlation) ---\n")
  # Correlate residual with the components of the prediction
  # This tells us if specific factors (like fatigue) are driving the error.
  corrs <- c(
    net_diff = cor(analysis_df$residual, analysis_df$contrib_net_diff, use = "complete.obs"),
    hca      = cor(analysis_df$residual, analysis_df$contrib_hca, use = "complete.obs"),
    fatigue  = cor(analysis_df$residual, analysis_df$contrib_fatigue, use = "complete.obs")
  )

  for (name in names(corrs)) {
    cat(sprintf("  - Correlation(Residual, %s): %.3f\n", name, corrs[name]))
  }
  cat("\n")

  # 6. High-Error Deep Dive (Top 5 Failures)
  cat("--- Top 5 Model Failures (Highest Absolute Residuals) ---\n")
  top_fails <- analysis_df |>
    arrange(desc(abs_residual)) |>
    head(5) |>
    select(game_date, home_team, away_team, predicted_margin, actual_margin, residual)

  print(knitr::kable(top_fails, format = "simple"))
  cat("\n")

  invisible(analysis_df)
}

if (sys.nframe() == 0) {
  run_error_analysis()
}
