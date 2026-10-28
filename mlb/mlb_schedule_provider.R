# mlb_schedule_provider.R (MLB)
# Native open-data schedule provider powered by baseballr::mlb_schedule()
# and the MLB Stats API fallback in mlb_ingest.R.
# Replaces The Odds API for MLB game schedules, game_pk crosswalk, start times,
# and venues without requiring any API key.

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
source("mlb_ingest.R")
.LOG_SCRIPT <- "mlb_schedule_provider.R"

#' Fetch MLB Schedule from Native Open League Data
#'
#' @param season Integer season year, default MLB_CURRENT_SEASON
#' @param force_refresh Logical, whether to bypass disk cache
#' @return A tibble with schedule details
get_mlb_schedule <- function(season = MLB_CURRENT_SEASON, force_refresh = FALSE) {
  ingest_mlb_schedule(season = season, force_refresh = force_refresh)
}

#' Fetch Upcoming (Unplayed) MLB Games
#'
#' @param season Integer season year, default MLB_CURRENT_SEASON
#' @return A tibble with upcoming games, game_pks, timestamps, and teams
get_upcoming_mlb_slate <- function(season = MLB_CURRENT_SEASON) {
  sch <- get_mlb_schedule(season = season)
  if (is.null(sch) || nrow(sch) == 0) return(tibble::tibble())

  # Filter for upcoming games where status indicates scheduled/pre-game
  # or where scores/winner are not yet recorded
  upcoming <- sch
  if ("status_abstract_game_state" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(status_abstract_game_state != "Final")
  } else if ("teams_home_score" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(is.na(teams_home_score))
  }

  upcoming
}
