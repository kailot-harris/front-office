# ==============================================================================
# Elo History Builder (Phase 9 infra, issue #17)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/elo_history_data.R
#
# Extracted verbatim (no logic changes) from docs/week5_elo_analysis.qmd's
# `compute-elo` chunk, plus the `fig-trajectory` chunk's `trajectory` object -
# both folded into a single reusable get_elo_history(max_week = NULL) so the
# seven Elo-dependent Phase 9 visualizations (tools/gif_elo_*.R,
# tools/gif_upset_timeline.R, tools/gif_pf_pa_scatter_elo.R,
# tools/gif_sos_adjusted_winrace.R) don't each re-derive this ~60-line
# computation and risk drifting out of sync - the exact failure class
# CLAUDE.md's constants/logic single-source-of-truth section warns about
# (WNBA sibling repo Finding C-1: a hardcoded-a-second-time HCA constant
# silently drifted from config.R).
#
# max_week = NULL reproduces the qmd's existing behavior exactly - through the
# latest completed week of CURRENT_SEASON. A non-NULL integer max_week caps
# CURRENT_SEASON games to week <= max_week before the Elo walk-forward runs,
# so every downstream object (current_ratings, long_games, team_performance,
# trajectory) reflects state as of that week only - prior seasons are left
# untouched (they are already complete, so "through week W" has no meaning for
# them; only CURRENT_SEASON has an in-progress week dimension). This is what
# lets P9-H's SOS-adjusted win race call get_elo_history(max_week = w) once per
# week to build its animation frames.
#
# Run standalone with (sources config.R/logging_utils.R/elo_model.R itself -
# no caller setup required):
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" "c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/elo_history_data.R"
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

source("config.R")
source("logging_utils.R")
source("tools/elo_model.R")

# get_elo_history(max_week = NULL)
#
# Returns a list with exactly 4 named elements (Interface Contract,
# docs/task_assignments_phase8.md):
#   - long_games       : game-level, team-perspective, pre-game Elo for team + opponent
#   - trajectory       : team/week/elo - pre-game rating per week played, plus a final
#                         current-rating point
#   - current_ratings  : one row per team - final_elo, last_season, current_elo,
#                         division, conference
#   - team_performance : one row per team - games_played, wins, win_pct,
#                         expected_win_pct, avg_opponent_elo, surprise_index,
#                         current_elo, division, conference
get_elo_history <- function(max_week = NULL) {
  sch <- readRDS(CACHE_SCHEDULES)
  fatigue <- if (file.exists(CACHE_FATIGUE_METRICS)) {
    readRDS(CACHE_FATIGUE_METRICS)
  } else {
    data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0))
  }

  elo_hist <- sch |>
    filter(!is.na(home_score), !is.na(away_score),
           season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON) |>
    mutate(gameday = as.Date(gameday))

  # max_week filtering: only CURRENT_SEASON has an in-progress week dimension -
  # prior seasons are already complete, so they are left unfiltered.
  if (!is.null(max_week)) {
    elo_hist <- elo_hist |>
      filter(season < CURRENT_SEASON | week <= max_week)
  }

  elo_run <- run_elo_walkforward(elo_hist, fatigue, ELO_K_FACTOR, return_final_state = TRUE)
  elo_games <- elo_run$games

  # Current rating per team: each team's final walkforward rating, carryover-projected to
  # CURRENT_SEASON (same logic team_ratings_engine.R's live ensemble uses via project_elo_rating()).
  current_ratings <- tibble(
    team = names(elo_run$final_elo),
    final_elo = unname(elo_run$final_elo),
    last_season = unname(elo_run$final_season)
  ) |>
    rowwise() |>
    mutate(current_elo = project_elo_rating(final_elo, last_season, CURRENT_SEASON)) |>
    ungroup() |>
    mutate(division = NFL_DIVISIONS[team],
           conference = substr(division, 1, 3)) |>
    filter(!is.na(division))

  # Regular-season games played so far this season, both team perspectives, with PRE-GAME
  # (no-hindsight) Elo for both the team and its opponent.
  reg_current <- elo_games |>
    filter(season == CURRENT_SEASON) |>
    inner_join(sch |> select(game_id, game_type), by = "game_id") |>
    filter(game_type == "REG")

  long_games <- bind_rows(
    reg_current |> transmute(game_id, week, team = home_team, opp = away_team,
                              team_elo_pre = home_elo_pre, opp_elo_pre = away_elo_pre,
                              team_win = home_win, team_win_prob = elo_prob_pure),
    reg_current |> transmute(game_id, week, team = away_team, opp = home_team,
                              team_elo_pre = away_elo_pre, opp_elo_pre = home_elo_pre,
                              team_win = 1L - home_win, team_win_prob = 1 - elo_prob_pure)
  )

  team_performance <- long_games |>
    group_by(team) |>
    summarise(games_played = n(),
              wins = sum(team_win),
              win_pct = mean(team_win),
              expected_win_pct = mean(team_win_prob),
              avg_opponent_elo = mean(opp_elo_pre),
              surprise_index = win_pct - expected_win_pct,
              .groups = "drop") |>
    left_join(current_ratings |> select(team, current_elo), by = "team") |>
    mutate(division = NFL_DIVISIONS[team], conference = substr(division, 1, 3))

  # Pulled in from the qmd's fig-trajectory chunk (same inputs/logic, unchanged) so every
  # Elo-dependent caller gets this object too, not just the original 4 compute-elo objects.
  trajectory <- bind_rows(
    long_games |> transmute(team, week, elo = team_elo_pre),
    current_ratings |> transmute(team, week = max(long_games$week) + 1L, elo = current_elo)
  ) |>
    distinct(team, week, .keep_all = TRUE) |>
    mutate(division = NFL_DIVISIONS[team]) |>
    filter(!is.na(division))

  list(
    long_games = long_games,
    trajectory = trajectory,
    current_ratings = current_ratings,
    team_performance = team_performance
  )
}
