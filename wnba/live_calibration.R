# ==============================================================================
# live_calibration.R (WNBA port)
# Statistical Calibration Analysis & Live In-Play Simulation Engine (WNBA)
# Path: live_calibration.R
# Sanitized per Phase 0 (Issue #9): removed odds conversion & market comparison.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

# 1. Calibration Analysis Framework (Pure Statistical Evaluation)
calibration_analysis <- function(predictions_df) {
  # predictions_df must contain target_home_win ('Win'/'Loss') and .pred_Win
  cal_df <- predictions_df |>
    mutate(
      bin = cut(.pred_Win, breaks = seq(0, 1, by = 0.10), include.lowest = TRUE),
      win_actual = if_else(target_home_win == "Win", 1, 0)
    ) |>
    group_by(bin) |>
    summarise(
      n_games = n(),
      mean_predicted = mean(.pred_Win),
      observed_win_rate = mean(win_actual),
      .groups = "drop"
    )

  brier <- mean((if_else(predictions_df$target_home_win == "Win", 1, 0) - predictions_df$.pred_Win)^2)
  brier_baseline <- 0.25 # 50/50 baseline
  bss <- 1 - (brier / brier_baseline)
  log_loss <- -mean(
    if_else(predictions_df$target_home_win == "Win", 1, 0) * log(pmax(1e-6, predictions_df$.pred_Win)) +
      if_else(predictions_df$target_home_win == "Win", 0, 1) * log(pmax(1e-6, 1 - predictions_df$.pred_Win))
  )

  cal_plot <- ggplot(cal_df, aes(x = mean_predicted, y = observed_win_rate)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    geom_point(aes(size = n_games), color = "steelblue") +
    geom_line(color = "steelblue") +
    theme_minimal() +
    labs(
      title = "Probability Calibration: Predicted vs. Observed",
      subtitle = sprintf("Brier Score: %.4f | Brier Skill Score: %.3f | Log-Loss: %.4f", brier, bss, log_loss),
      x = "Predicted Win Probability",
      y = "Observed Win Rate"
    )

  list(table = cal_df, brier = brier, bss = bss, log_loss = log_loss, plot = cal_plot)
}

# 2. Live In-Play Simulation Engine (Quarter Updates)
simulate_live_game <- function(pre_game_home_win_prob, n_sims = 1000) {
  quarters <- paste0("Q", 1:4)
  cur_prob <- pre_game_home_win_prob
  prob_trajectory <- c(pre_game_home_win_prob)

  for (q in 1:4) {
    time_left_weight <- (4 - q) / 4.0
    diff_shock <- rnorm(1, mean = (pre_game_home_win_prob - 0.5) * 4, sd = 4.5)
    cur_logit <- qlogis(pmin(pmax(cur_prob, 0.01), 0.99))
    updated_logit <- cur_logit * 0.70 + (diff_shock / 3.0)
    cur_prob <- plogis(updated_logit)
    prob_trajectory <- c(prob_trajectory, cur_prob)
  }

  tibble(
    stage = c("Pre-game", "End Q1", "Halftime", "End Q3", "Final"),
    home_win_prob = round(prob_trajectory, 3)
  )
}
