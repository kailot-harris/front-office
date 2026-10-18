# ==============================================================================
# Bottom-Up Player-Composed NBA H2H Prediction & Standings Engine
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/roster_bottom_up_engine.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("live_calibration.R")

# Ensure cache paths exist
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_DIR, "cache")
if (!exists("CACHE_INJURY_DATA")) CACHE_INJURY_DATA <- file.path(CACHE_DIR, "injury_data_cache.rds")

# ------------------------------------------------------------------------------
# 1. Compute Historical Player Impact (Empirically Centered BPM)
# ------------------------------------------------------------------------------
# 1. Compute Ground-Truth Player Impact (Box Creation + Empirical Plus-Minus Fusion)
get_player_bpm_ratings <- function() {
  if (!file.exists(CACHE_PLAYER_BOX)) stop("Player box cache missing.")
  
  player_box <- readRDS(CACHE_PLAYER_BOX)
  
  # Clean numeric plus_minus from raw game logs
  player_clean <- player_box |>
    filter(minutes > 8) |>
    mutate(
      pm_numeric = suppressWarnings(as.numeric(plus_minus)),
      pm_numeric = coalesce(pm_numeric, 0.0),
      weight     = if_else(season >= 2025, 1.5, 1.0)
    )
  
  # Aggregate across all games
  raw_stats <- player_clean |>
    group_by(athlete_id) |>
    summarise(
      player_name  = last(athlete_display_name),
      games_played = n(),
      total_min    = sum(minutes, na.rm = TRUE),
      avg_min      = mean(minutes, na.rm = TRUE),
      
      # Per-36 Box Score Creation
      pts36 = sum(points * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      reb36 = sum(rebounds * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      ast36 = sum(assists * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      stl36 = sum(steals * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      blk36 = sum(blocks * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      tov36 = sum(turnovers * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      
      # Ground-Truth Empirical On-Court Net Differential per 36
      empirical_pm36 = sum(pm_numeric * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      .groups = "drop"
    ) |>
    filter(total_min >= 200) |>
    mutate(
      # Standard Box Creation component
      box_score = 0.55 * pts36 + 0.60 * reb36 + 1.10 * ast36 + 1.40 * stl36 + 1.20 * blk36 - 1.25 * tov36
    )
  
  # Center both metrics at league average (0.00)
  box_mu <- sum(raw_stats$box_score * raw_stats$total_min) / sum(raw_stats$total_min)
  pm_mu  <- sum(raw_stats$empirical_pm36 * raw_stats$total_min) / sum(raw_stats$total_min)
  
  ratings <- raw_stats |>
    mutate(
      centered_box = box_score - box_mu,
      raw_centered_pm = empirical_pm36 - pm_mu,
      
      # Empirical Bayes Sample-Size Shrinkage:
      # Players with fewer minutes regress toward 0.0, preventing small-sample blowout distortion
      shrinkage_weight = total_min / (total_min + 500),
      centered_pm = raw_centered_pm * shrinkage_weight,
      
      # 50/50 Objective Fusion
      bpm = round(pmax(-5.0, pmin(12.0, 0.50 * centered_box + 0.50 * centered_pm)), 2)
    ) |>
    select(athlete_id, player_name, games_played, total_min, avg_min, bpm)
  
  return(ratings)
}

# ------------------------------------------------------------------------------
# 2. Build Dynamic Team Net Rating from 240-Minute Rotation
# ------------------------------------------------------------------------------
compute_team_live_rating <- function(team, active_rosters, player_ratings, injury_df = tibble()) {
  team_players <- active_rosters |>
    filter(team_name == team)
  
  if (nrow(team_players) == 0) return(list(net_rating = 0.0, rotation = tibble()))
  
  # Primary Join on athlete_id, Secondary Fallback on player_name
  roster_rated <- team_players |>
    left_join(player_ratings |> select(athlete_id, bpm, hist_avg_min = avg_min), 
              by = c("player_id" = "athlete_id"))
  
  # Fallback fill for any players matching by name
  unmatched_idx <- which(is.na(roster_rated$bpm))
  if (length(unmatched_idx) > 0) {
    name_lookup <- player_ratings |> select(player_name, bpm_name = bpm, min_name = avg_min)
    roster_rated[unmatched_idx, ] <- roster_rated[unmatched_idx, ] |>
      left_join(name_lookup, by = "player_name") |>
      mutate(
        bpm = coalesce(bpm, bpm_name),
        hist_avg_min = coalesce(hist_avg_min, min_name)
      ) |>
      select(-bpm_name, -min_name)
  }
  
  # Replacement level prior (-2.0 BPM) for rookies/incoming players
  roster_rated <- roster_rated |>
    mutate(
      bpm = coalesce(bpm, -2.0),
      hist_avg_min = coalesce(hist_avg_min, 15.0)
    )
  
  # Adjust minutes for real-time injury status
  if (nrow(injury_df) > 0) {
    inj_team <- injury_df |> filter(team_name == team)
    if (nrow(inj_team) > 0) {
      roster_rated <- roster_rated |>
        left_join(inj_team |> select(player_name, status), by = "player_name") |>
        mutate(
          hist_avg_min = case_when(
            status == "Out"          ~ 0.0,
            status == "Doubtful"     ~ hist_avg_min * 0.25,
            status == "Questionable" ~ hist_avg_min * 0.50,
            TRUE                     ~ hist_avg_min
          )
        ) |>
        select(-status)
    }
  }
  
  # Select top 9 rotation players
  active_rotation <- roster_rated |>
    arrange(desc(hist_avg_min * (bpm + 5.5))) |>
    slice_head(n = 9)
  
  tot_proj_min <- sum(active_rotation$hist_avg_min)
  if (tot_proj_min <= 0) tot_proj_min <- 240
  
  # Proportionally allocate the 240 regulation minutes
  active_rotation <- active_rotation |>
    mutate(allocated_min = (hist_avg_min / tot_proj_min) * 240)
  
  # Team Net Rating (5 on floor * minutes-weighted BPM)
  # Bounded to historical NBA extremes (-10.5 to +11.5)
  raw_team_nrtg <- sum(active_rotation$bpm * (active_rotation$allocated_min / 240)) * 5.0
  team_nrtg <- round(pmax(-10.5, pmin(14.0, raw_team_nrtg)), 2)
  
  list(
    net_rating = round(team_nrtg, 2),
    rotation   = active_rotation |> select(player_name, position, bpm, allocated_min)
  )
}

# ------------------------------------------------------------------------------
# 3. Single Head-to-Head Matchup Evaluator
# ------------------------------------------------------------------------------
predict_live_matchup <- function(home_team, away_team, active_rosters, player_ratings, injury_df = tibble()) {
  h_res <- compute_team_live_rating(home_team, active_rosters, player_ratings, injury_df)
  a_res <- compute_team_live_rating(away_team, active_rosters, player_ratings, injury_df)
  
  hca <- 2.40 # Standard NBA Home Court Advantage
  expected_margin <- (h_res$net_rating - a_res$net_rating) + hca
  
  home_prob <- pnorm(expected_margin / 11.8)
  fair_spread <- -round(expected_margin, 1)
  
  fair_home_ml <- if_else(home_prob >= 0.50,
                          round(-100 * home_prob / (1 - home_prob)),
                          round(100 * (1 - home_prob) / home_prob))
  
  tibble(
    Matchup         = paste(away_team, "@", home_team),
    Home_Team       = home_team,
    Away_Team       = away_team,
    Home_Rating     = h_res$net_rating,
    Away_Rating     = a_res$net_rating,
    Proj_Margin     = round(expected_margin, 1),
    Fair_Spread     = fair_spread,
    Home_Win_Prob   = round(home_prob, 3),
    Fair_Home_ML    = fair_home_ml
  )
}

# ------------------------------------------------------------------------------
# 4. Full 30-Team Calibrated Schedule Simulation Matrix (Zero-Sum)
# ------------------------------------------------------------------------------
project_all_30_teams <- function() {
  cat("\n==================================================================\n")
  cat("     ALL-30 NBA TEAMS: ZERO-SUM 82-GAME SCHEDULE SIMULATION       \n")
  cat("==================================================================\n\n")
  
  roster_file <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  if (!file.exists(roster_file)) stop("Run sync_rosters.R first.")
  
  active_rosters <- readRDS(roster_file)
  player_ratings <- get_player_bpm_ratings()
  
  all_teams <- sort(unique(active_rosters$team_name))
  n_teams <- length(all_teams)
  
  raw_ratings <- numeric(n_teams)
  top_stars   <- character(n_teams)
  
  for (idx in seq_along(all_teams)) {
    t <- all_teams[idx]
    res <- compute_team_live_rating(t, active_rosters, player_ratings)
    raw_ratings[idx] <- res$net_rating
    
    stars <- res$rotation |>
      arrange(desc(bpm)) |>
      slice_head(n = 3) |>
      pull(player_name) |>
      paste(collapse = ", ")
    top_stars[idx] <- stars
  }
  
  # Center League Net Ratings at Exactly 0.00
  league_mu <- mean(raw_ratings)
  true_net_ratings <- round(raw_ratings - league_mu, 2)
  
  team_df <- tibble(
    Team        = all_teams,
    True_NRtg   = true_net_ratings,
    Top_Stars   = top_stars
  )
  
  # Round-Robin Schedule Simulation Matrix (41 Home, 41 Away)
  hca <- 2.40
  sigma <- 11.8
  games_per_opponent <- 82 / (n_teams - 1)
  
  expected_wins <- numeric(n_teams)
  
  for (i in seq_along(all_teams)) {
    team_i_wins <- 0
    for (j in seq_along(all_teams)) {
      if (i == j) next
      margin_home <- (true_net_ratings[i] - true_net_ratings[j]) + hca
      p_win_home  <- pnorm(margin_home / sigma)
      
      margin_away <- (true_net_ratings[i] - true_net_ratings[j]) - hca
      p_win_away  <- pnorm(margin_away / sigma)
      
      team_i_wins <- team_i_wins + (0.5 * p_win_home + 0.5 * p_win_away) * games_per_opponent
    }
    expected_wins[i] <- round(team_i_wins, 1)
  }
  
  team_df <- team_df |>
    mutate(
      Proj_Wins   = expected_wins,
      Proj_Losses = round(82 - Proj_Wins, 1),
      Win_Pct     = paste0(round((Proj_Wins / 82) * 100, 1), "%")
    ) |>
    arrange(desc(Proj_Wins)) |>
    mutate(Rank = row_number()) |>
    select(Rank, Team, Net_Rating = True_NRtg, Proj_Wins, Proj_Losses, Win_Pct, Top_Core_Players = Top_Stars)
  
  print(knitr::kable(team_df, format = "simple"))
  
  cat(sprintf("\n[AUDIT] Total League Wins: %.1f / 1230.0 (League Average: %.1f wins)\n",
              sum(team_df$Proj_Wins), mean(team_df$Proj_Wins)))
  
  saveRDS(team_df, file.path(CACHE_DIR, "projected_30_team_standings.rds"))
  cat(sprintf("[CACHE] Standings saved to: %s\n\n", file.path(CACHE_DIR, "projected_30_team_standings.rds")))
  
  return(team_df)
}

# ------------------------------------------------------------------------------
# 5. Universal Point Spread & Win Probability Query Tool
# ------------------------------------------------------------------------------
get_fair_spread <- function(home_team, away_team) {
  standings_file <- file.path(CACHE_DIR, "projected_30_team_standings.rds")
  if (!file.exists(standings_file)) project_all_30_teams()
  
  standings <- readRDS(standings_file)
  
  h_row <- standings |> filter(Team == home_team)
  a_row <- standings |> filter(Team == away_team)
  
  if (nrow(h_row) == 0 || nrow(a_row) == 0) {
    stop("Team not found. Please verify spelling against active rosters.")
  }
  
  hca <- 2.40
  margin <- (h_row$Net_Rating - a_row$Net_Rating) + hca
  spread <- -round(margin, 1)
  win_prob <- round(pnorm(margin / 11.8), 3)
  
  cat(sprintf("\n🏀 MATCHUP: %s (Away) @ %s (Home)\n", away_team, home_team))
  cat(sprintf("   ► %s Rating: %+0.2f | %s Rating: %+0.2f\n", home_team, h_row$Net_Rating, away_team, a_row$Net_Rating))
  cat(sprintf("   ► Projected Margin: %+0.1f points to %s\n", margin, home_team))
  cat(sprintf("   ► Fair Vegas Spread: %s %s%0.1f\n", home_team, ifelse(spread > 0, "+", ""), spread))
  cat(sprintf("   ► Fair Win Probability: %s %.1f%% | %s %.1f%%\n\n",
              home_team, win_prob * 100, away_team, (1 - win_prob) * 100))
}

# Auto-execute simulation
project_all_30_teams()