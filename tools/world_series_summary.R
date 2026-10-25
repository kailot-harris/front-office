# ==============================================================================
# tools/world_series_summary.R — World Series series-state builder
#
# Split out of export_web_data.R so it can be sourced on its own. The nightly
# results refresh (tools/refresh_live_results.R) rebuilds world_series.json
# with these exact functions, and must not drag in config.R / duckdb / dplyr to
# do it — so everything here is base R with no side effects on source().
#
# Sourced by: tools/export_web_data.R, tools/refresh_live_results.R
# ==============================================================================

#' Summarize the World Series from the built matchup rows
#'
#' The postseason banner needs resolved game scores, not just a static blurb,
#' so fold the "W" game_type rows into a series state: per-game results, the
#' wins tally, and whether the series is scheduled, live, or decided.
#'
#' @param matchups Matchup rows from build_matchup_slates()
#' @param season Season year
#' @return List ready for JSON, or NULL when the season has no WS games yet
build_world_series_summary <- function(matchups, season = 2026) {
  ws <- matchups[matchups$game_type == "W", , drop = FALSE]
  if (nrow(ws) == 0) return(NULL)
  ws <- ws[order(ws$game_date, ws$game_pk), , drop = FALSE]

  # Game 1 fixes home-field advantage, so its home club anchors the pairing.
  hfa_abbr  <- ws$home_team[1]
  hfa_name  <- ws$home_team_name[1]
  road_abbr <- ws$away_team[1]
  road_name <- ws$away_team_name[1]

  winners <- ifelse(
    !ws$is_completed | is.na(ws$home_score) | is.na(ws$away_score),
    NA_character_,
    ifelse(ws$home_score > ws$away_score, ws$home_team, ws$away_team)
  )

  games <- lapply(seq_len(nrow(ws)), function(i) {
    list(
      game_number    = i,
      game_pk        = ws$game_pk[i],
      game_date      = ws$game_date[i],
      venue_name     = ws$venue_name[i],
      status_detail  = ws$status_detail[i],
      is_completed   = ws$is_completed[i],
      home_team      = ws$home_team[i],
      home_team_name = ws$home_team_name[i],
      home_score     = ws$home_score[i],
      away_team      = ws$away_team[i],
      away_team_name = ws$away_team_name[i],
      away_score     = ws$away_score[i],
      home_win_prob  = ws$home_win_prob[i],
      winner         = winners[i]
    )
  })

  hfa_wins   <- sum(winners == hfa_abbr, na.rm = TRUE)
  road_wins  <- sum(winners == road_abbr, na.rm = TRUE)
  played     <- sum(!is.na(winners))
  champion   <- if (hfa_wins == 4) hfa_abbr else if (road_wins == 4) road_abbr else NA_character_

  status <- if (!is.na(champion)) {
    "complete"
  } else if (played > 0) {
    "in_progress"
  } else {
    "scheduled"
  }

  list(
    season        = as.integer(season),
    title         = sprintf("%d World Series", season),
    format        = "Best-of-7",
    start_date    = ws$game_date[1],
    end_date      = ws$game_date[nrow(ws)],
    status        = status,
    games_played  = as.integer(played),
    games_scheduled = as.integer(nrow(ws)),
    champion      = champion,
    home_field    = list(team = hfa_abbr, team_name = hfa_name, wins = as.integer(hfa_wins)),
    challenger    = list(team = road_abbr, team_name = road_name, wins = as.integer(road_wins)),
    games         = games
  )
}

#' Write the World Series summary JSON consumed by the postseason banner
#'
#' @return Path written, or NULL when there is nothing to write
write_world_series_file <- function(summary, out_dir) {
  f_ws <- file.path(out_dir, "world_series.json")
  if (is.null(summary)) {
    if (file.exists(f_ws)) file.remove(f_ws)
    return(NULL)
  }
  jsonlite::write_json(summary, f_ws, pretty = TRUE, auto_unbox = TRUE, na = "null")
  f_ws
}
