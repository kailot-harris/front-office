# schedule_provider.R (NFL)
# Native open-data schedule provider powered by nflreadr::load_schedules()
# Replaces The Odds API for upcoming schedule slates, game IDs, kickoff times,
# and venues without requiring any API key.

suppressPackageStartupMessages({
  library(dplyr)
  library(nflreadr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "schedule_provider.R"

#' Fetch NFL Schedule from Native Open League Data (nflreadr)
#'
#' @param season Integer season year, default CURRENT_SEASON
#' @param force_refresh Logical, whether to bypass disk cache
#' @return A tibble with normalized schedule columns
get_nfl_schedule <- function(season = CURRENT_SEASON, force_refresh = FALSE) {
  if (!force_refresh && file.exists(CACHE_SCHEDULES)) {
    sch <- tryCatch(readRDS(CACHE_SCHEDULES), error = function(e) NULL)
    if (!is.null(sch) && nrow(sch) > 0) {
      if ("season" %in% names(sch)) {
        sch_season <- sch |> filter(season == !!season)
        if (nrow(sch_season) > 0) return(sch_season)
      }
      return(sch)
    }
  }

  log_info(sprintf("Fetching NFL schedule for season %d via nflreadr...", season), call = "get_nfl_schedule()")
  sch <- tryCatch({
    nflreadr::load_schedules(seasons = season)
  }, error = function(e) {
    log_warn(sprintf("nflreadr::load_schedules failed for season %d: %s", season, conditionMessage(e)), call = "get_nfl_schedule()")
    if (file.exists(CACHE_SCHEDULES)) readRDS(CACHE_SCHEDULES) else tibble()
  })

  sch
}

#' Fetch Upcoming (Unplayed) NFL Games
#'
#' @param season Integer season year, default CURRENT_SEASON
#' @return A tibble with upcoming games, timestamps, teams, and neutral site flag
get_upcoming_nfl_slate <- function(season = CURRENT_SEASON) {
  sch <- get_nfl_schedule(season = season)
  if (nrow(sch) == 0) return(tibble())

  upcoming <- sch |>
    filter(season == !!season, is.na(result) | is.na(home_score) | is.na(away_score)) |>
    mutate(
      is_neutral = (location == "Neutral"),
      game_id = as.character(game_id),
      home_team = as.character(home_team),
      away_team = as.character(away_team)
    )

  upcoming
}
