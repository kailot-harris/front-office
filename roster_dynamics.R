# ==============================================================================
# Offseason Roster Dynamics, Age Curves & Continuity Regression (WNBA)
# Path: roster_dynamics.R
#
# Ported from NBA Analytics/roster_dynamics.R (T2 / wnba_rating_engine_agent). Ports as-is per
# WNBA_REPLICATION_PLAN.md §(b)/(d) - season-over-season minutes-continuity logic has no
# NBA-specific game-length/roster-size constant baked in (it's a ratio of minutes played by
# returning players over total prior-season minutes, which is scale-free). The one thing worth
# flagging for a future agent: WNBA's much shorter season (44 games vs 82) and 2020's real
# 22-game COVID-bubble season (config.R's HISTORICAL_SEASONS comment) mean a single season's
# `season_minutes` totals are smaller and noisier than NBA's - this doesn't change the
# continuity FORMULA, but it does mean roster_stability_score for 2020->2021 in particular
# should be interpreted with more caution than other transitions. Not a code change, just a
# reading-the-output caveat for whoever consumes get_roster_continuity() next.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("player_metrics.R")

get_roster_continuity <- function(seasons = ALL_SEASONS) {
  raw_box <- get_player_box_scores_chunked(seasons)

  player_season_minutes <- raw_box |>
    mutate(
      minutes = suppressWarnings(as.numeric(minutes)),
      minutes = replace_na(minutes, 0),
      athlete_id = as.integer(athlete_id),
      team_id = as.integer(team_id),
      season = as.integer(season)
    ) |>
    group_by(season, team_id, athlete_id) |>
    summarise(season_minutes = sum(minutes, na.rm = TRUE), .groups = "drop")

  continuity_records <- list()
  sorted_seasons <- sort(unique(player_season_minutes$season))

  for (i in seq_along(sorted_seasons)) {
    curr_season <- sorted_seasons[i]
    if (i == 1) {
      # Baseline default for first observed season
      teams <- unique(player_season_minutes$team_id[player_season_minutes$season == curr_season])
      continuity_records[[i]] <- tibble(
        season = curr_season,
        team_id = teams,
        returning_minutes_pct = 0.75,
        roster_stability_score = 0.75
      )
      next
    }

    prev_season <- sorted_seasons[i - 1]
    prev_data <- player_season_minutes |> filter(season == prev_season)
    curr_data <- player_season_minutes |> filter(season == curr_season)

    calc_df <- prev_data |>
      inner_join(curr_data, by = c("team_id", "athlete_id"), suffix = c("_prev", "_curr")) |>
      group_by(team_id) |>
      summarise(returning_prev_min = sum(season_minutes_prev), .groups = "drop")

    team_prev_totals <- prev_data |>
      group_by(team_id) |>
      summarise(total_prev_min = sum(season_minutes), .groups = "drop")

    season_result <- team_prev_totals |>
      left_join(calc_df, by = "team_id") |>
      mutate(
        returning_prev_min = replace_na(returning_prev_min, 0),
        season = curr_season,
        returning_minutes_pct = round(pmin(1.0, returning_prev_min / pmax(1, total_prev_min)), 4),
        # Roster stability score weights returning volume
        roster_stability_score = round(pmax(0.20, returning_minutes_pct), 4)
      ) |>
      select(season, team_id, returning_minutes_pct, roster_stability_score)

    continuity_records[[i]] <- season_result
  }

  bind_rows(continuity_records)
}

apply_continuity_adjustment <- function(feature_df, continuity_df) {
  # Regress teams with high turnover (low continuity) more aggressively to league mean
  adjusted <- feature_df |>
    left_join(continuity_df, by = c("season", "team_id")) |>
    mutate(
      roster_stability_score = replace_na(roster_stability_score, 0.75),
      # Dynamic decay weighting based on continuity
      roll_pts_scored = roster_stability_score * roll_pts_scored + (1 - roster_stability_score) * mean(roll_pts_scored, na.rm = TRUE),
      roll_efg = roster_stability_score * roll_efg + (1 - roster_stability_score) * mean(roll_efg, na.rm = TRUE)
    )
  return(adjusted)
}
