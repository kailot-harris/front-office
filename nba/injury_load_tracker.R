# ==============================================================================
# Injury, Load Management & Schedule Fatigue Tracker
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/injury_load_tracker.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")

get_schedule_features <- function(box_scores) {
  sched_features <- box_scores |>
    select(game_id, season, game_date, team_id, team_home_away) |>
    distinct(game_id, team_id, .keep_all = TRUE) |>
    mutate(
      game_date = as.Date(game_date),
      team_id = as.integer(team_id)
    ) |>
    arrange(team_id, game_date) |>
    group_by(team_id) |>
    mutate(
      days_since_prior = as.numeric(game_date - lag(game_date)),
      is_back_to_back  = if_else(coalesce(days_since_prior, 3) == 1, 1L, 0L),
      
      # Density: 3 games in 4 nights / 4 in 5 nights
      is_3_in_4 = if_else(as.numeric(game_date - lag(game_date, 2)) <= 3, 1L, 0L),
      is_4_in_5 = if_else(as.numeric(game_date - lag(game_date, 3)) <= 4, 1L, 0L),
      
      # Travel burden: home <-> away transition
      prev_home_away = lag(team_home_away),
      travel_flag    = if_else(!is.na(prev_home_away) & (team_home_away != prev_home_away), 1L, 0L),
      
      # Composite Schedule Fatigue Index (0 to 4 scale)
      schedule_fatigue_index = is_back_to_back * 1.5 + is_3_in_4 * 1.0 + is_4_in_5 * 1.0 + travel_flag * 0.5
    ) |>
    ungroup() |>
    replace_na(list(
      is_back_to_back = 0L, is_3_in_4 = 0L, is_4_in_5 = 0L,
      travel_flag = 0L, schedule_fatigue_index = 0.0
    )) |>
    select(game_id, team_id, is_back_to_back, is_3_in_4, is_4_in_5, travel_flag, schedule_fatigue_index)
  
  return(sched_features)
}

load_injury_data <- function() {
  if (file.exists(CACHE_INJURY_DATA)) {
    readRDS(CACHE_INJURY_DATA)
  } else {
    tibble(
      game_date   = Sys.Date(),
      team_name   = character(),
      player_name = character(),
      player_id   = integer(),
      status      = character(),
      injury_desc = character()
    )
  }
}

team_availability_score <- function(injury_df, team_roster_bpm) {
  if (nrow(injury_df) == 0) return(1.0)
  
  penalty_map <- c("Out" = 1.0, "Doubtful" = 0.75, "Questionable" = 0.50, "Probable" = 0.10)
  
  joined <- injury_df |>
    left_join(team_roster_bpm, by = c("player_id", "team_id")) |>
    mutate(
      prob_out = penalty_map[status],
      prob_out = replace_na(prob_out, 0.0),
      impact_loss = prob_out * pmax(0, player_bpm)
    )
  
  net_loss <- sum(joined$impact_loss, na.rm = TRUE)
  availability <- pmax(0.70, 1.0 - (net_loss / 30.0))
  return(availability)
}