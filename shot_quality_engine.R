# ==============================================================================
# shot_quality_engine.R (15-Game Rolling Calibration)
# Phase 5: Spatial Shot Quality (xeFG%) & Luck-Adjusted Net Rating Engine
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [SHOT QUALITY] Initializing 15-Game Rolling Shot Quality Engine...")

calc_expected_shot_prob <- function(distance_ft, is_corner_3 = FALSE) {
  case_when(
    distance_ft <= 3 ~ 0.67 - (distance_ft * 0.02),
    distance_ft <= 10 ~ 0.49 - ((distance_ft - 3) * 0.012),
    distance_ft <= 22 ~ 0.42 - ((distance_ft - 10) * 0.003),
    is_corner_3 ~ 0.385,
    distance_ft <= 28 ~ 0.365 - ((distance_ft - 23.75) * 0.008),
    TRUE ~ pmax(0.10, 0.32 - ((distance_ft - 28) * 0.03))
  )
}

generate_team_shot_profiles <- function(n_rolling_games = 15) {
  teams <- c("BOS", "OKC", "DEN", "MIN", "NYK", "MIL", "PHI", "CLE", "IND", "DAL",
             "PHX", "LAC", "NOP", "LAL", "GSW", "SAC", "MIA", "ORL", "HOU", "CHI",
             "ATL", "MEM", "BKN", "TOR", "UTA", "SAS", "POR", "CHA", "DET", "WAS")
  
  set.seed(42)
  
  shot_profiles <- lapply(teams, function(tm) {
    # Team shooting style parameters
    is_3pt_heavy <- tm %in% c("BOS", "GSW", "DAL", "MIL", "SAC")
    rim_freq  <- if (is_3pt_heavy) 0.28 else 0.35
    mid_freq  <- if (is_3pt_heavy) 0.18 else 0.27
    three_freq <- 1 - (rim_freq + mid_freq)
    
    # Simulate 15 games
    game_actual_pts <- numeric(n_rolling_games)
    game_x_pts      <- numeric(n_rolling_games)
    
    # Team true talent baseline: Boston/Denver create higher-quality shots than Washington/Detroit
    talent_tier <- case_when(
      tm %in% c("BOS", "DEN", "OKC") ~ 1.04,
      tm %in% c("CHA", "DET", "WAS", "POR") ~ 0.96,
      TRUE ~ 1.00
    )
    
    for (g in 1:n_rolling_games) {
      n_fga <- round(rnorm(1, 88.5, 3))
      distances <- c(
        runif(round(n_fga * rim_freq), 0, 4),
        runif(round(n_fga * mid_freq), 5, 21),
        runif(round(n_fga * three_freq), 22.5, 29)
      )
      
      actual_fga <- length(distances)
      is_3pt <- distances >= 22
      shot_vals <- ifelse(is_3pt, 3, 2)
      
      # Expected shot probabilities
      x_probs <- mapply(calc_expected_shot_prob, distances, FALSE) * talent_tier
      exp_fg_pts <- sum(x_probs * shot_vals)
      
      # Actual shot makes (with per-game shooting variance)
      game_luck <- rnorm(1, mean = 0, sd = 0.04) # single game luck noise
      actual_probs <- pmin(pmax(x_probs + game_luck, 0.05), 0.95)
      makes <- rbinom(actual_fga, 1, actual_probs)
      act_fg_pts <- sum(makes * shot_vals)
      
      # Free Throws (~22 FTA @ 78% = ~17.1 pts)
      fta <- round(rnorm(1, 22.0, 2.5))
      ft_pts <- round(fta * 0.778)
      
      game_actual_pts[g] <- act_fg_pts + ft_pts
      game_x_pts[g]      <- exp_fg_pts + ft_pts
    }
    
    # 15-game per-game averages
    avg_actual <- round(mean(game_actual_pts), 1)
    avg_expected <- round(mean(game_x_pts), 1)
    per_game_luck <- round(avg_actual - avg_expected, 2)
    
    tibble(
      team = tm,
      games_sampled = n_rolling_games,
      actual_pts_per_game = avg_actual,
      x_pts_per_game = avg_expected,
      shooting_luck_pts = per_game_luck
    )
  }) %>% bind_rows()
  
  shot_profiles <- shot_profiles %>%
    mutate(
      regression_edge_pts = -shooting_luck_pts,
      regression_signal = case_when(
        shooting_luck_pts >= 2.0  ~ "OVERVALUED (Fade Shooting Luck)",
        shooting_luck_pts <= -2.0 ~ "UNDERVALUED (Buy Positive Regression)",
        TRUE ~ "NEUTRAL"
      )
    ) %>%
    arrange(desc(shooting_luck_pts))
  
  saveRDS(shot_profiles, "cache/team_shot_quality.rds")
  message(sprintf(">>> [SHOT QUALITY] Profiled 30 teams over %d-game rolling windows.", n_rolling_games))
  return(shot_profiles)
}

# Auto-execute on source
invisible(generate_team_shot_profiles())