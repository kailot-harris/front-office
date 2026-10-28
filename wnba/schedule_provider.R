# schedule_provider.R (WNBA)
# Native open-data schedule provider powered by wehoop::load_wnba_schedule()
# Replaces The Odds API for WNBA game schedules, ESPN game IDs, game dates,
# and venues without requiring any API key.

suppressPackageStartupMessages({
  library(dplyr)
  library(wehoop)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "schedule_provider.R"

#' Fetch WNBA Schedule from Native Open League Data (wehoop)
#'
#' @param season Integer season year, default CURRENT_SEASON
#' @param force_refresh Logical, whether to bypass disk cache
#' @return A tibble with schedule details
get_wnba_schedule <- function(season = CURRENT_SEASON, force_refresh = FALSE) {
  if (!force_refresh && file.exists(CACHE_WNBA_SCHEDULE)) {
    sch <- tryCatch(readRDS(CACHE_WNBA_SCHEDULE), error = function(e) NULL)
    if (!is.null(sch) && nrow(sch) > 0) return(sch)
  }

  log_info(sprintf("Fetching WNBA schedule for season %d via wehoop::load_wnba_schedule()...", season), call = "get_wnba_schedule()")
  sch <- tryCatch({
    wehoop::load_wnba_schedule(seasons = season)
  }, error = function(e) {
    log_warn(sprintf("wehoop fetch failed: %s", conditionMessage(e)), call = "get_wnba_schedule()")
    if (file.exists(CACHE_WNBA_SCHEDULE)) readRDS(CACHE_WNBA_SCHEDULE) else tibble()
  })

  sch
}

#' Fetch Upcoming (Unplayed) WNBA Slate
#'
#' @param season Integer season year, default CURRENT_SEASON
#' @return A tibble with upcoming games, game_ids, teams, and dates
get_upcoming_wnba_slate <- function(season = CURRENT_SEASON) {
  sch <- get_wnba_schedule(season = season)
  if (nrow(sch) == 0) return(tibble())

  upcoming <- sch
  if ("is_completed" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(!is_completed)
  } else if ("status_type_completed" %in% names(upcoming)) {
    upcoming <- upcoming |> filter(!as.logical(status_type_completed))
  }

  upcoming
}
