# ==============================================================================
# Player-Level Impact Metrics (BPM, Minutes Concentration & Depth) - WNBA
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/player_metrics.R
#
# Ported from NBA Analytics/player_metrics.R. Swaps hoopR::load_nba_player_box() for
# wehoop::load_wnba_player_box(), same chunked per-season retry/backoff pattern using
# MAX_RETRIES / RATE_LIMIT_SLEEP_SEC from config.R. calculate_bpm_components() and
# get_player_features() are ported unchanged (BPM box-score weights are not
# NBA-specific per WNBA_REPLICATION_PLAN.md §b Tier 2) except for the WNBA-specific
# exhibition-row filter applied right after each chunked wehoop pull.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(wehoop)
  library(slider)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "player_metrics.R"

# Same WNBA-specific gotcha as daily_ingest.R: raw wehoop player box includes
# non-franchise All-Star/Team USA exhibition rows. Filter before caching/aggregating.
#
# Also normalizes "CONN" -> "CON": ESPN used "CONN" as the Connecticut Sun's real
# abbreviation for 2019-2023 (switching to "CON" from 2024 on) - discovered during T1
# validation (2026-09-12). This is a real franchise code, not an exhibition row; a
# naive filter against WNBA_TEAMS would silently drop 5 seasons of real Sun player-game
# rows. See daily_ingest.R's normalize_team_abbreviation() for the team-box equivalent.
normalize_team_abbreviation <- function(df) {
  if ("team_abbreviation" %in% names(df)) {
    df <- df |> mutate(team_abbreviation = if_else(team_abbreviation == "CONN", "CON", team_abbreviation))
  }
  if ("opponent_team_abbreviation" %in% names(df)) {
    df <- df |> mutate(opponent_team_abbreviation = if_else(opponent_team_abbreviation == "CONN", "CON", opponent_team_abbreviation))
  }
  df
}

filter_real_franchises <- function(df) {
  if (!"team_abbreviation" %in% names(df)) return(df)
  df <- normalize_team_abbreviation(df)
  df |> filter(team_abbreviation %in% names(WNBA_TEAMS))
}

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
        wehoop::load_wnba_player_box(seasons = s)
      }, error = function(e) {
        warning(sprintf("     Attempt %d failed for season %d: %s", attempt, s, e$message))
        log_error(sprintf("wehoop::load_wnba_player_box() attempt %d/%d failed for season %d.",
                           attempt, MAX_RETRIES, s),
                  condition = e, call = "get_player_box_scores_chunked()", season = s, attempt = attempt)
        Sys.sleep(RATE_LIMIT_SLEEP_SEC * 2)
        NULL
      })
      if (!is.null(s_data)) break
    }

    if (is.null(s_data)) {
      log_error(sprintf("Failed to retrieve player box scores for season %d after %d retries.", s, MAX_RETRIES),
                call = "get_player_box_scores_chunked()", season = s, max_retries = MAX_RETRIES)
      stop(sprintf("Failed to retrieve player box scores for season %d after %d retries.", s, MAX_RETRIES))
    }

    s_data <- filter_real_franchises(s_data)
    log_info(sprintf("Ingested %d real-franchise player-game rows for season %d.", nrow(s_data), s),
             call = "get_player_box_scores_chunked()", season = s, rows = nrow(s_data))
    season_dfs[[as.character(s)]] <- s_data
    Sys.sleep(RATE_LIMIT_SLEEP_SEC) # Protect ESPN/wehoop endpoints
  }

  all_player_box <- bind_rows(season_dfs)
  saveRDS(all_player_box, CACHE_PLAYER_BOX)
  message(sprintf("[Player Metrics] Ingestion complete. Cached %d player-game rows.", nrow(all_player_box)))
  log_info(sprintf("Cached %d total player-game rows across %d seasons.", nrow(all_player_box), length(seasons)),
           call = "get_player_box_scores_chunked()", rows = nrow(all_player_box), out_path = CACHE_PLAYER_BOX)
  return(all_player_box)
}

calculate_bpm_components <- function(player_df) {
  # Robust column mapping across wehoop/ESPN historical schemas
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

  # Standard empirical BPM linear weights scaled per 36 minutes.
  # TODO(recalibrate): the -2.0 replacement-level anchor (and the per-stat weights
  # below) were hand-tuned against NBA per-36 distributions in the original repo.
  # WNBA games are 40 minutes (not 48) and per-player usage/pace distributions differ;
  # do NOT silently change this number without real WNBA data behind it - once
  # get_player_features() has run against several real WNBA seasons, re-derive this
  # anchor (and ideally the weights) from the actual WNBA per-36 stat distribution
  # rather than carrying the NBA-fit constant forward indefinitely.
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
