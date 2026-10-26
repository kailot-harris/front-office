# ==============================================================================
# live_calibration.R (WNBA port)
# Live In-Play Simulation, Market Odds Conversion & Calibration
# Path: live_calibration.R
#
# Not an explicit T4 deliverable per agent5.md, but required: bet_tracker.r
# `source()`s this file for its odds-conversion helpers (american_to_prob,
# remove_vig) exactly as the NBA original does. Per task_assignments.md's T2
# Handoff Notes ("T4 should port live_calibration.R itself... it's sport-agnostic
# math with no NBA-specific constants, so it should port with no logic changes
# beyond a header comment"), this is ported byte-for-byte below — no logic
# changes, only this header comment. `load_market_odds()`'s 10-game stub remains
# clearly synthetic/placeholder, same as the NBA original.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

# 1. Odds Conversion Utilities
american_to_prob <- function(odds) {
  if_else(odds > 0, 100 / (odds + 100), abs(odds) / (abs(odds) + 100))
}

remove_vig <- function(p_home, p_away) {
  overround <- p_home + p_away
  list(fair_home = p_home / overround, fair_away = p_away / overround)
}

# 2. Calibration Analysis Framework
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

# 3. Market Odds Comparison Stub — clearly synthetic, unchanged from NBA original.
load_market_odds <- function() {
  tibble(
    game_id = paste0("401", 1001:1010),
    game_date = Sys.Date() - 1:10,
    home_team = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
    away_team = c(11, 12, 13, 14, 15, 16, 17, 18, 19, 20),
    home_moneyline = c(-150, +130, -210, -110, +175, -140, +105, -180, +220, -125),
    away_moneyline = c(+130, -150, +175, -110, -210, +120, -125, +155, -270, +105)
  )
}

# 4. Model vs. Market Edge & Backtesting
compare_model_vs_market <- function(model_preds, market_odds) {
  joined <- model_preds |>
    inner_join(market_odds, by = "game_id") |>
    mutate(
      market_implied_raw = american_to_prob(home_moneyline),
      market_prob_fair = market_implied_raw / (market_implied_raw + american_to_prob(away_moneyline)),
      edge = .pred_Win - market_prob_fair,
      model_pick = if_else(.pred_Win > 0.50, "Home", "Away"),
      market_favorite = if_else(market_prob_fair > 0.50, "Home", "Away"),
      disagreement = model_pick != market_favorite
    )

  list(
    correlation = cor(joined$.pred_Win, joined$market_prob_fair),
    mean_abs_diff = mean(abs(joined$edge)),
    disagreement_count = sum(joined$disagreement),
    comparison_df = joined
  )
}

# 5. Live In-Play Simulation Engine (Quarter Updates) — sport-agnostic; note this
# NBA-derived version still uses a 4-quarter game-clock loop, which is structurally
# fine for WNBA (also 4 quarters, just 10 vs 12 minutes each) since this function
# operates on QUARTER INDEX, not minutes, so no change needed.
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
