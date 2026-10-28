# schedule_provider.R (NBA)
# Native open-data schedule provider powered by hoopR::load_nba_schedule()
# Replaces The Odds API for NBA game schedules, ESPN game IDs, game dates,
# and venues without requiring any API key.

suppressPackageStartupMessages({
  library(dplyr)
  library(hoopR)
})

source("config.R")
.LOG_SCRIPT <- "schedule_provider.R"

#' Fetch NBA Schedule from Native Open League Data (hoopR)
#'
#' @param season Integer hoopR season (end year, e.g. 2027 for 2026-27), default MATCHUPS_HOOPR_SEASON
#' @param force_refresh Logical, whether to bypass disk cache
#' @return A tibble with schedule details
get_nba_schedule <- function(season = MATCHUPS_HOOPR_SEASON, force_refresh = FALSE) {
  cache_file <- CACHE_MATCHUPS_SCHEDULE(season)
  if (!force_refresh && file.exists(cache_file)) {
    sch <- tryCatch(readRDS(cache_file), error = function(e) NULL)
    if (!is.null(sch) && nrow(sch) > 0) return(sch)
  }

  cat(sprintf("[SCHEDULE] Fetching NBA schedule for season %d via hoopR::load_nba_schedule()...\n", season))
  sch <- tryCatch({
    hoopR::load_nba_schedule(seasons = season)
  }, error = function(e) {
    cat(sprintf("[SCHEDULE WARN] hoopR fetch failed: %s\n", conditionMessage(e)))
    if (file.exists(cache_file)) readRDS(cache_file) else tibble()
  })

  if (nrow(sch) > 0) {
    if (!dir.exists(dirname(cache_file))) dir.create(dirname(cache_file), recursive = TRUE)
    saveRDS(sch, cache_file)
  }

  sch
}

#' Fetch Upcoming (Unplayed) NBA Slate
#'
#' @param season Integer hoopR season, default MATCHUPS_HOOPR_SEASON
#' @return A tibble with upcoming games, game_ids, teams, and game dates
get_upcoming_nba_slate <- function(season = MATCHUPS_HOOPR_SEASON) {
  sch <- get_nba_schedule(season = season)
  if (nrow(sch) == 0) return(tibble())

  # Filter for games not yet completed
  upcoming <- sch
  if ("status_type_completed" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(!as.logical(status_type_completed))
  } else if ("home_score" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(is.na(home_score))
  }

  upcoming
}
