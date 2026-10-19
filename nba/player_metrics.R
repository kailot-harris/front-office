# ==============================================================================
# Player-Level Impact Metrics (BPM, Minutes Concentration & Depth)
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/player_metrics.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(hoopR)
  library(slider)
})

source("config.R")

get_player_box_scores_chunked <- function(seasons = ALL_SEASONS) {
  if (file.exists(CACHE_PLAYER_BOX)) {
    message(sprintf("[Player Metrics] Loading player box scores from cache: %s", CACHE_PLAYER_BOX))
    return(readRDS(CACHE_PLAYER_BOX))
  }
  
  message("[Player Metrics] Cache not found. Initiating chunked download with rate-limiting...")
  season_dfs <- list()
  
  for (s in seasons) {
    message(sprintf("  -> Ingesting season %d...", s))
    s_data <- NULL
    for (attempt in 1:MAX_RETRIES) {
      s_data <- tryCatch({
        hoopR::load_nba_player_box(seasons = s)
      }, error = function(e) {
        warning(sprintf("     Attempt %d failed for season %d: %s", attempt, s, e$message))
        Sys.sleep(RATE_LIMIT_SLEEP_SEC * 2)
        NULL
      })
      if (!is.null(s_data)) break
    }
    
    if (is.null(s_data)) {
      stop(sprintf("Failed to retrieve player box scores for season %d after %d retries.", s, MAX_RETRIES))
    }
    
    season_dfs[[as.character(s)]] <- s_data
    Sys.sleep(RATE_LIMIT_SLEEP_SEC) # Protect ESPN/hoopR endpoints
  }
  
  all_player_box <- bind_rows(season_dfs)
  saveRDS(all_player_box, CACHE_PLAYER_BOX)
  message(sprintf("[Player Metrics] Ingestion complete. Cached %d player-game rows.", nrow(all_player_box)))
  return(all_player_box)
}

calculate_bpm_components <- function(player_df) {
  # Robust column mapping across hoopR historical schemas
  df <- player_df |>
    mutate(
      minutes = suppressWarnings(as.numeric(minutes)),
      minutes = replace_na(minutes, 0),
      points = suppressWarnings(as.numeric(points)),
      rebounds = suppressWarnings(as.numeric(rebounds)),
      assists = suppressWarnings(as.numeric(assists)),
      steals = suppressWarnings(as.numeric(steals)),
      blocks = suppressWarnings(as.numeric(blocks)),
      turnovers = suppressWarnings(as.numeric(turnovers)),
      field_goals_made = suppressWarnings(as.numeric(field_goals_made)),
      field_goals_attempted = suppressWarnings(as.numeric(field_goals_attempted)),
      three_point_field_goals_made = suppressWarnings(as.numeric(three_point_field_goals_made)),
      free_throws_made = suppressWarnings(as.numeric(free_throws_made)),
      free_throws_attempted = suppressWarnings(as.numeric(free_throws_attempted))
    ) |>
    replace_na(list(
      points = 0, rebounds = 0, assists = 0, steals = 0, blocks = 0,
      turnovers = 0, field_goals_made = 0, field_goals_attempted = 0,
      three_point_field_goals_made = 0, free_throws_made = 0, free_throws_attempted = 0
    ))
  
  # Standard empirical BPM linear weights scaled per 36 minutes
  df <- df |>
    mutate(
      min_factor = if_else(minutes > 0, 36 / minutes, 0),
      raw_bpm_rate = if_else(
        minutes >= 5,
        (0.60 * points + 0.70 * rebounds + 1.05 * assists + 1.40 * steals + 1.15 * blocks -
           1.20 * turnovers - 0.45 * (field_goals_attempted - field_goals_made) - 
           0.35 * (free_throws_attempted - free_throws_made) + 0.30 * three_point_field_goals_made) * (minutes / 36) - 2.0,
        -2.0
      )
    )
  return(df)
}

get_player_features <- function(seasons = ALL_SEASONS) {
  raw_player_box <- get_player_box_scores_chunked(seasons)
  bpm_df <- calculate_bpm_components(raw_player_box)
  
  # Aggregate features at team-game level
  team_game_features <- bpm_df |>
    filter(minutes > 0) |>
    group_by(game_id, team_id) |>
    summarise(
      total_team_minutes = sum(minutes, na.rm = TRUE),
      # Minutes-weighted BPM
      team_weighted_bpm = sum(raw_bpm_rate * minutes, na.rm = TRUE) / pmax(1, sum(minutes, na.rm = TRUE)),
      # Top-5 Unit BPM
      team_top5_bpm = mean(head(sort(raw_bpm_rate, decreasing = TRUE), 5), na.rm = TRUE),
      # Minutes Concentration (Herfindahl-Hirschman Index of team minutes)
      team_minutes_concentration = sum((minutes / pmax(1, sum(minutes, na.rm = TRUE)))^2, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      game_id = as.character(game_id),
      team_id = as.integer(team_id)
    )
  
  return(team_game_features)
}