# ==============================================================================
# Automated Daily Box Score Ingestion Pipeline
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/daily_ingest.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(hoopR)
})

source("config.R")

log_message <- function(msg) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg))
}

daily_box_ingest <- function() {
  log_message("Starting daily box score ingestion...")
  
  # 1. Load existing cache
  if (file.exists(CACHE_TEAM_BOX)) {
    existing_box <- readRDS(CACHE_TEAM_BOX)
    log_message(sprintf("Loaded existing cache with %d records.", nrow(existing_box)))
  } else {
    log_message(sprintf("Cache not found. Initializing complete historical ingestion (%d:%d)...",
                        min(ALL_SEASONS), max(ALL_SEASONS)))
    existing_box <- hoopR::load_nba_team_box(seasons = ALL_SEASONS)
    saveRDS(existing_box, CACHE_TEAM_BOX)
    log_message(sprintf("Saved initial cache with %d records.", nrow(existing_box)))
    return(invisible(existing_box))
  }
  
  # 2. Fetch current season updates
  log_message(sprintf("Fetching updates for season %d from hoopR API...", CURRENT_SEASON))
  new_box <- tryCatch({
    hoopR::load_nba_team_box(seasons = CURRENT_SEASON)
  }, error = function(e) {
    log_message(sprintf("Error loading current season box scores: %s", e$message))
    return(NULL)
  })
  
  if (is.null(new_box) || nrow(new_box) == 0) {
    log_message("No records returned from API. Exiting.")
    return(invisible(existing_box))
  }
  
  # 3. Deduplicate by game_id and team_id
  combined <- bind_rows(existing_box, new_box) |>
    distinct(game_id, team_id, .keep_all = TRUE) |>
    arrange(season, game_date, game_id)
  
  n_new_records <- nrow(combined) - nrow(existing_box)
  log_message(sprintf("Ingestion complete. %d new records identified.", n_new_records))
  
  # 4. Save cache back to disk
  if (n_new_records > 0) {
    saveRDS(combined, CACHE_TEAM_BOX)
    log_message(sprintf("Updated %s with %d total records.", CACHE_TEAM_BOX, nrow(combined)))
  } else {
    log_message("Cache is already up to date. No write necessary.")
  }
  
  invisible(combined)
}

daily_box_ingest()