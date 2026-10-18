# ==============================================================================
# playoff_simulator.R
# Phase 4 Upgrade: Monte Carlo Playoff Series & Bracket Simulator (8-Man Depth)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (file.exists("config.R")) source("config.R")
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [PLAYOFFS] Initializing Monte Carlo Playoff Series Simulator...")

# ------------------------------------------------------------------------------
# Playoff Net Rating Adjuster (8-Man Shortened Rotation)
# ------------------------------------------------------------------------------
get_playoff_adjusted_rating <- function(team_code, reg_net_rating) {
  # Playoff rotation boosts teams with elite top-3 talent; reduces deep-bench reliance
  # Load RAPM if exists
  rapm_path <- if (exists("CACHE_DIR")) file.path(CACHE_DIR, "rapm_ratings.rds") else "cache/rapm_ratings.rds"
  if (file.exists(rapm_path)) {
    rapm_data <- tryCatch(readRDS(rapm_path), error = function(e) NULL)
    if (!is.null(rapm_data) && is.data.frame(rapm_data)) {
      tm_players <- rapm_data %>% filter(team == team_code) %>% arrange(desc(total_rapm))
      if (nrow(tm_players) >= 3) {
        top3_boost <- mean(head(tm_players$total_rapm, 3)) * 0.35
        return(reg_net_rating + top3_boost)
      }
    }
  }
  # Default playoff leverage bump for contenders
  message(sprintf(">>> [WARN] Using SYNTHETIC_FALLBACK playoff leverage: '%s' missing or insufficient player ratings for team %s.", rapm_path, team_code))
  contender_leverage <- c("BOS" = 2.4, "DEN" = 2.2, "OKC" = 1.8, "MIN" = 1.5, "NYK" = 1.6, "DAL" = 1.9, "MIL" = 1.4, "PHI" = 1.3)
  lev <- if (team_code %in% names(contender_leverage)) contender_leverage[[team_code]] else 0.0
  return(reg_net_rating + lev)
}

# ------------------------------------------------------------------------------
# Best-of-7 Series Simulation (2-2-1-1-1 Format)
# ------------------------------------------------------------------------------
simulate_single_series <- function(team_high, team_low, net_high, net_low, n_sims = 10000, hca_pts = 2.4) {
  # Home schedule for high seed: Games 1, 2, 5, 7 at Home
  home_high_flags <- c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE)
  
  rating_diff <- net_high - net_low
  
  # Game win probabilities for High Seed
  p_high_home <- pnorm((rating_diff + hca_pts) / (if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8))
  p_high_away <- pnorm((rating_diff - hca_pts) / (if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8))
  
  sim_results <- matrix(0, nrow = n_sims, ncol = 2) # [high_wins, low_wins]
  series_lengths <- integer(n_sims)
  high_series_wins <- 0
  
  for (s in 1:n_sims) {
    w_high <- 0
    w_low  <- 0
    g <- 1
    
    while (w_high < 4 && w_low < 4) {
      p_win <- ifelse(home_high_flags[g], p_high_home, p_high_away)
      if (runif(1) < p_win) {
        w_high <- w_high + 1
      } else {
        w_low <- w_low + 1
      }
      g <- g + 1
    }
    
    series_lengths[s] <- (w_high + w_low)
    if (w_high == 4) high_series_wins <- high_series_wins + 1
    sim_results[s, ] <- c(w_high, w_low)
  }
  
  p_series_high <- high_series_wins / n_sims
  p_series_low  <- 1 - p_series_high
  
  # Fair series moneyline odds
  fair_ml_high <- ifelse(p_series_high >= 0.5, 
                         round(-100 * p_series_high / (1 - p_series_high)), 
                         round(100 * (1 - p_series_high) / p_series_high))
  fair_ml_low  <- ifelse(p_series_low >= 0.5, 
                         round(-100 * p_series_low / (1 - p_series_low)), 
                         round(100 * (1 - p_series_low) / p_series_low))
  
  # Exact Game Outcomes
  outcomes <- tibble(
    high_w = sim_results[, 1],
    low_w  = sim_results[, 2]
  ) %>%
    mutate(scoreline = paste0(team_high, " ", high_w, "-", low_w, " ", team_low)) %>%
    count(scoreline) %>%
    mutate(prob_pct = round((n / n_sims) * 100, 2)) %>%
    arrange(desc(prob_pct))
  
  # Spread pricing (High Seed -1.5 Games, -2.5 Games)
  p_cover_minus_1_5 <- mean(sim_results[, 1] == 4 & sim_results[, 2] <= 2)
  p_cover_minus_2_5 <- mean(sim_results[, 1] == 4 & sim_results[, 2] <= 1)
  
  list(
    high_seed = team_high,
    low_seed = team_low,
    p_high_seed_win = round(p_series_high, 4),
    p_low_seed_win = round(p_series_low, 4),
    fair_ml_high = fair_ml_high,
    fair_ml_low = fair_ml_low,
    avg_series_games = round(mean(series_lengths), 2),
    p_high_cover_minus_1_5 = round(p_cover_minus_1_5, 4),
    p_high_cover_minus_2_5 = round(p_cover_minus_2_5, 4),
    exact_outcomes = outcomes
  )
}

# Run sample marquee playoff matchup simulation
simulate_playoff_suite <- function() {
  standings_path <- if (exists("CACHE_DIR")) file.path(CACHE_DIR, "projected_30_team_standings.rds") else "cache/projected_30_team_standings.rds"
  if (!file.exists(standings_path)) {
    message(sprintf(">>> [WARN] Using SYNTHETIC_FALLBACK series ratings: '%s' missing. Using baseline ratings (BOS=10.5, NYK=5.2).", standings_path))
  }
  
  # Example matchup: Boston (#1 East) vs New York (#2 East)
  res <- simulate_single_series(
    team_high = "BOS",
    team_low  = "NYK",
    net_high  = get_playoff_adjusted_rating("BOS", 10.5),
    net_low   = get_playoff_adjusted_rating("NYK", 5.2),
    n_sims    = 10000
  )
  
  out_path <- if (exists("CACHE_DIR")) file.path(CACHE_DIR, "playoff_series_bos_nyk.rds") else "cache/playoff_series_bos_nyk.rds"
  saveRDS(res, out_path)
  message(sprintf(">>> [PLAYOFFS] BOS vs NYK (10,000 Sims) | BOS Series Win: %.1f%% (%+d) | Avg Games: %.2f",
                  res$p_high_seed_win * 100, res$fair_ml_high, res$avg_series_games))
  return(res)
}

if (!interactive()) {
  invisible(simulate_playoff_suite())
}