# ==============================================================================
# Lineup Synergy, Combinatorics & Staggering Metrics
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/lineup_synergy.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("player_metrics.R")

get_lineup_features <- function(seasons = ALL_SEASONS) {
  raw_box <- get_player_box_scores_chunked(seasons)
  
  cleaned <- raw_box |>
    mutate(
      minutes = suppressWarnings(as.numeric(minutes)),
      minutes = replace_na(minutes, 0),
      points  = suppressWarnings(as.numeric(points)),
      points  = replace_na(points, 0),
      athlete_id = as.integer(athlete_id),
      game_id = as.character(game_id),
      team_id = as.integer(team_id)
    )
  
  lineup_metrics <- cleaned |>
    group_by(game_id, team_id) |>
    arrange(desc(minutes)) |>
    summarise(
      top5_combined_pts = sum(head(points, 5), na.rm = TRUE),
      
      # Herfindahl-Hirschman Index of minute distribution
      minutes_hhi = {
        total_m <- sum(minutes)
        if (total_m > 0) sum((minutes / total_m)^2) else 0.20
      },
      
      # Star overlap: proportion of games where top-2 minute earners both played >= 30 mins
      star_overlap_pct = {
        m_vec <- head(minutes, 2)
        if (length(m_vec) >= 2 && min(m_vec) >= 30) 1.0 else 0.0
      },
      
      # Proxy for unit stability (continuity of minutes within the game)
      lineup_continuity_score = round(pmin(1.0, sum(head(minutes, 5)) / pmax(1, sum(minutes))), 3),
      .groups = "drop"
    )
  
  return(lineup_metrics)
}