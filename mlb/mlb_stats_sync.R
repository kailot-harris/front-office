# ==============================================================================
# mlb_stats_sync.R — FanGraphs Leaderboard Sync & Advanced Metrics
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_stats_sync.R
#
# Syncs advanced batter and pitcher metrics from FanGraphs leaderboards via
# baseballr wrapper functions (docs/MLB_REPLICATION_PLAN.md §2a, §3):
#   - Batter stats: fg_batter_leaders() (wOBA, wRC+, BABIP, fWAR, etc.)
#   - Pitcher stats: fg_pitcher_leaders() (FIP, xFIP, BABIP, fWAR, etc.)
#   - Projections: fg_projections() (preseason/in-season projected baselines)
#   - Park factors: fg_park() (single-year / multi-year venue run & HR factors)
#
# Default WAR Source Decision (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1):
#   fWAR is chosen as the canonical WAR source because baseballr's FanGraphs
#   wrappers are actively maintained and functional, whereas Baseball-Reference
#   endpoints report HTTP 403 / 429 rate limit issues with no bWAR path.
#
# Interface contract (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 / Issue #13):
#   - Callable top-level function: run_stats_sync(seasons = NULL, force_refresh = FALSE)
#   - Writes outputs to cache_path("stats_sync", ...)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_stats_sync.R"

DEFAULT_SYNC_SEASONS <- c(2024, 2025, 2026)

#' Sync FanGraphs Batter Leaderboards
#'
#' @param seasons Numeric vector of seasons to sync
#' @param force_refresh If TRUE, re-fetches even if cached
#' @return A tibble of batter leaderboard data
sync_fg_batters <- function(seasons = DEFAULT_SYNC_SEASONS, force_refresh = FALSE) {
  cache_file <- cache_path("stats_sync", "fg_batters.rds")
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info("Loading cached FanGraphs batter data from disk", script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  if (!.mlb_has_baseballr) {
    log_error("baseballr package not available for FanGraphs sync", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  all_seasons_data <- list()
  
  for (yr in seasons) {
    log_info(sprintf("Fetching FanGraphs batter leaders for season %d", yr), script = .LOG_SCRIPT)
    
    bat_df <- tryCatch({
      # qual = 0 fetches all qualifying and non-qualifying batters with PA >= 10
      df <- baseballr::fg_batter_leaders(startseason = yr, endseason = yr, qual = 10)
      if (!is.null(df) && nrow(df) > 0) {
        df$season <- as.integer(yr)
        df
      } else {
        NULL
      }
    }, error = function(e) {
      log_warn(sprintf("fg_batter_leaders failed for season %d", yr),
               condition = e, script = .LOG_SCRIPT)
      NULL
    })
    
    if (!is.null(bat_df)) {
      all_seasons_data[[length(all_seasons_data) + 1]] <- bat_df
    }
  }
  
  if (length(all_seasons_data) == 0) {
    log_warn("No FanGraphs batter data retrieved across specified seasons", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }
  
  combined <- dplyr::bind_rows(all_seasons_data)
  
  # Ensure standard WAR column exists and is aliased to fWAR
  if ("WAR" %in% names(combined) && !"fWAR" %in% names(combined)) {
    combined$fWAR <- combined$WAR
  }
  
  saveRDS(combined, cache_file)
  log_info(sprintf("Saved %d batter records across %d season(s) to cache",
                   nrow(combined), length(unique(combined$season))),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  combined
}

#' Sync FanGraphs Pitcher Leaderboards
#'
#' @param seasons Numeric vector of seasons to sync
#' @param force_refresh If TRUE, re-fetches even if cached
#' @return A tibble of pitcher leaderboard data
sync_fg_pitchers <- function(seasons = DEFAULT_SYNC_SEASONS, force_refresh = FALSE) {
  cache_file <- cache_path("stats_sync", "fg_pitchers.rds")
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info("Loading cached FanGraphs pitcher data from disk", script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  if (!.mlb_has_baseballr) {
    log_error("baseballr package not available for FanGraphs sync", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  all_seasons_data <- list()
  
  for (yr in seasons) {
    log_info(sprintf("Fetching FanGraphs pitcher leaders for season %d", yr), script = .LOG_SCRIPT)
    
    pit_df <- tryCatch({
      df <- baseballr::fg_pitcher_leaders(startseason = yr, endseason = yr, qual = 10)
      if (!is.null(df) && nrow(df) > 0) {
        df$season <- as.integer(yr)
        df
      } else {
        NULL
      }
    }, error = function(e) {
      log_warn(sprintf("fg_pitcher_leaders failed for season %d", yr),
               condition = e, script = .LOG_SCRIPT)
      NULL
    })
    
    if (!is.null(pit_df)) {
      all_seasons_data[[length(all_seasons_data) + 1]] <- pit_df
    }
  }
  
  if (length(all_seasons_data) == 0) {
    log_warn("No FanGraphs pitcher data retrieved across specified seasons", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }
  
  combined <- dplyr::bind_rows(all_seasons_data)
  
  # Ensure standard WAR column exists and is aliased to fWAR
  if ("WAR" %in% names(combined) && !"fWAR" %in% names(combined)) {
    combined$fWAR <- combined$WAR
  }
  
  saveRDS(combined, cache_file)
  log_info(sprintf("Saved %d pitcher records across %d season(s) to cache",
                   nrow(combined), length(unique(combined$season))),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  combined
}

#' Sync FanGraphs Park Factors
#'
#' @param force_refresh If TRUE, re-fetches even if cached
#' @return A tibble of park factor data
sync_fg_park <- function(force_refresh = FALSE) {
  cache_file <- cache_path("stats_sync", "fg_park.rds")
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info("Loading cached FanGraphs park factors from disk", script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  if (!.mlb_has_baseballr) {
    log_error("baseballr package not available for FanGraphs park sync", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  log_info("Fetching FanGraphs park factors", script = .LOG_SCRIPT)
  
  park_df <- tryCatch({
    # Try fetching current or recent season park factors
    baseballr::fg_park(2024)
  }, error = function(e) {
    log_warn("fg_park(2024) failed, trying without season parameter",
             condition = e, script = .LOG_SCRIPT)
    tryCatch(baseballr::fg_park(), error = function(e2) NULL)
  })
  
  if (is.null(park_df) || nrow(park_df) == 0) {
    log_warn("No park factor data retrieved from FanGraphs", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }
  
  saveRDS(park_df, cache_file)
  log_info(sprintf("Saved %d park factor records to cache", nrow(park_df)),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  park_df
}

#' Master runner function for Phase 1 stats sync stage
#'
#' @param seasons Seasons vector to sync. Defaults to c(2024, 2025, 2026).
#' @param force_refresh If TRUE, bypasses disk cache. Default FALSE.
#' @return A named list containing:
#'   - batters: tibble of FanGraphs batter leaders
#'   - pitchers: tibble of FanGraphs pitcher leaders
#'   - park: tibble of FanGraphs park factors
run_stats_sync <- function(seasons = DEFAULT_SYNC_SEASONS, force_refresh = FALSE) {
  log_info("Starting FanGraphs stats sync stage", script = .LOG_SCRIPT,
           seasons = paste(seasons, collapse = ","), force_refresh = force_refresh)
  
  batters  <- sync_fg_batters(seasons = seasons, force_refresh = force_refresh)
  pitchers <- sync_fg_pitchers(seasons = seasons, force_refresh = force_refresh)
  park     <- sync_fg_park(force_refresh = force_refresh)
  
  summary <- list(
    batters  = batters,
    pitchers = pitchers,
    park     = park
  )
  
  log_info(sprintf("Completed FanGraphs stats sync: %d batters, %d pitchers, %d parks",
                   nrow(batters), nrow(pitchers), nrow(park)),
           script = .LOG_SCRIPT)
  
  invisible(summary)
}
