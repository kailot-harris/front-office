# tools/generate_diagnostic_data.R
# Generates synthetic resolved data to test the Error Analysis framework.

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)
library(tidyverse)
source("config.R")

log_path <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
existing_log <- if (file.exists(log_path)) readRDS(log_path) else tibble()

set.seed(42)
n_games <- 100
teams <- names(WNBA_TEAMS)

# Create synthetic resolved games
synthetic_resolved <- tibble(
  schema_version = 1L,
  game_id = paste0("DIAG_", 1:n_games),
  game_date = as.Date("2026-01-01") + sample(0:200, n_games, replace = TRUE),
  season = 2026L,
  home_team = sample(teams, n_games, replace = TRUE),
  away_team = sample(teams, n_games, replace = TRUE),
  prediction_timestamp = Sys.time() - 86400,
  predicted_home_win_prob = runif(n_games, 0.2, 0.8),
  predicted_winner = "TBD", # Will fix below
  predicted_margin = rnorm(n_games, 0, 10),
  contrib_net_diff = rnorm(n_games, 0, 8),
  contrib_hca = 2.4,
  contrib_fatigue = rnorm(n_games, 0, 2),
  model_rolling_window_size = 12L,
  model_margin_sigma = 14.0,
  model_rotation_size = 8L,
  model_offseason_method = "reset",
  injury_data_source = "DIAGNOSTIC",
  shot_quality_data_source = "DIAGNOSTIC",
  status = "RESOLVED",
  actual_winner = "TBD",
  correct = NA,
  brier_component = NA_real_,
  log_loss_component = NA_real_,
  resolved_timestamp = Sys.time()
)

# Inject specific bias patterns for the diagnostic tool to find:
# 1. "The LV Aces Bias": Model consistently under-predicts LV Aces (Home)
#     lavez_idx <- which(synthetic_resolved$home_team == "LV")
#    synthetic_resolved$predicted_margin[lavez_idx] <- synthetic_resolved$predicted_margin[lavez_idx] - 5

# 2. "Fatigue Blindness": High fatigue_drag correlates with larger residuals
#    synthetic_resolved <- synthetic_resolved |>
#      mutate(actual_margin = predicted_margin + (contrib_fatigue * 1.5) + rnorm(n_games, 0, 5))

# Simplified synthetic outcome generation
synthetic_resolved <- synthetic_resolved |>
  mutate(
    # Base actual margin = predicted + noise
    actual_margin = predicted_margin + rnorm(n_games, 0, 7),
    # Inject LV Aces under-prediction bias
    actual_margin = if_else(home_team == "LV", actual_margin + 6, actual_margin),
    # Inject Fatigue Correlation (Residuals grow with fatigue_drag)
    actual_margin = actual_margin + (contrib_fatigue * 2.0),

    actual_winner = if_else(actual_margin >= 0, home_team, away_team),
    predicted_winner = if_else(predicted_margin >= 0, home_team, away_team),
    correct = (actual_winner == predicted_winner),
    # Dummy Brier/LogLoss for schema compliance
    brier_component = runif(n_games, 0, 0.25),
    log_loss_component = runif(n_games, 0.1, 1.0)
  )

updated_log <- bind_rows(existing_log, synthetic_resolved)
saveRDS(updated_log, log_path)
cat(sprintf("Successfully injected %d synthetic RESOLVED games into log for diagnostics.\n", n_games))
