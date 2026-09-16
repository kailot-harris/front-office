# ==============================================================================
# optimize_hca.R
# Path: tools/optimize_hca.R
#
# Optimizes the Home Court Advantage (HCA) constant using observed residuals.
# Uses the L-BFGS-B optimization algorithm to find the HCA value that minimizes
# the Mean Absolute Error (MAE) of the probabilistic margin model.
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "optimize_hca.R"

run_hca_optimization <- function() {
  cat("\n==================================================================\n")
  cat("           WNBA HCA OPTIMIZATION ENGINE (L-BFGS-B)             \n")
  cat("==================================================================\n\n")

  # 1. Load Data
  log_path <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
  box_path <- CACHE_TEAM_BOX

  if (!file.exists(log_path) || !file.exists(box_path)) {
    stop("Missing required caches (prediction log or box scores).")
  }

  pred_log <- readRDS(log_path)
  box_scores <- readRDS(box_path)

  # 2. Prepare Resolved Dataset
  resolved <- pred_log |> filter(status == "RESOLVED")
  if (nrow(resolved) == 0) {
    stop("No RESOLVED predictions found to optimize against.")
  }

  # Join with actuals
  resolved <- resolved |>
    mutate(.home_short = word(unname(WNBA_TEAMS[home_team]), -1))

  game_outcomes <- box_scores |>
    filter(team_home_away == "home") |>
    mutate(game_date = as.Date(game_date)) |>
    select(game_date, home_team_short = team_short_display_name,
           home_score = team_score, away_score = opponent_team_score) |>
    distinct()

  analysis_df <- resolved |>
    inner_join(game_outcomes, by = c("game_date" = "game_date", ".home_short" = "home_team_short")) |>
    mutate(
      actual_margin    = home_score - away_score,
      # FINDING C-1: the logged `predicted_margin` already has the engine's HCA baked
      # in, so it is removed here to recover the HCA-free base margin. That HCA is
      # read from config.R::WNBA_HCA, not restated as a literal — restating it is the
      # exact drift mechanism that let the engine ship 11.6 while its comment said 2.40.
      #
      # STALENESS WARNING (Phase 4 / C-1 data invalidation, tracked as P4-G): rows in
      # cache/prediction_accuracy_log.rds written BEFORE the C-1 fix had 11.6 baked
      # into `predicted_margin`, not WNBA_HCA. For those rows this subtraction leaves a
      # ~9.2-point residual offset in `predicted_margin_base`, which will bias the
      # optimum upward. Do NOT treat this script's output as an empirical WNBA HCA
      # until the pre-fix rows are regenerated or excluded.
      predicted_margin_base = predicted_margin - WNBA_HCA
    )

  if (nrow(analysis_df) == 0) {
    stop("No matching resolved games found.")
  }

  cat(sprintf("Optimizing over N = %d resolved games...\n", nrow(analysis_df)))

  # 3. Define Objective Function (MAE)
  # We want to minimize the average absolute difference between actual and (base + hca)
  obj_fn <- function(hca) {
    preds <- analysis_df$predicted_margin_base + hca
    mae <- mean(abs(analysis_df$actual_margin - preds), na.rm = TRUE)
    return(mae)
  }

  # 4. Run Optimization
  # Bounds: [2.0, 50.0]
  opt_res <- optim(
    par = WNBA_HCA,   # FINDING C-1: start from the live config.R constant
    fn = obj_fn,
    lower = 2.0,
    upper = 50.0,
    method = "L-BFGS-B"
  )

  opt_hca <- opt_res$par
  opt_mae <- opt_res$value

  # Baseline MAE at the live config.R HCA (FINDING C-1 — read, never restated)
  baseline_mae <- obj_fn(WNBA_HCA)

  cat("\n--- Optimization Results ---\n")
  cat(sprintf("Current HCA (config.R::WNBA_HCA):  %.2f => MAE: %.3f\n", WNBA_HCA, baseline_mae))
  cat(sprintf("Optimal HCA:  %.3f => MAE: %.3f\n", opt_hca, opt_mae))
  cat(sprintf("Net Improvement: %.3f points reduction in MAE\n", baseline_mae - opt_mae))

  # Calculate Bias with optimal HCA
  final_residuals <- analysis_df$actual_margin - (analysis_df$predicted_margin_base + opt_hca)
  final_bias <- mean(final_residuals, na.rm = TRUE)
  cat(sprintf("Remaining Mean Bias: %.3f\n", final_bias))

  return(list(optimal_hca = opt_hca, mae = opt_mae))
}

if (sys.nframe() == 0) {
  run_hca_optimization()
}
