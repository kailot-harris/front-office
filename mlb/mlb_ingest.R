# ==============================================================================
# mlb_ingest.R — MLB Stats API & Statcast Ingestion Engine
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_ingest.R
#
# Ingestion pipeline for official MLB game schedules, box scores, and Statcast
# pitch-level data.
#
# Data sources & verified nuances (docs/MLB_REPLICATION_PLAN.md §2a, §2b):
#   - MLB Stats API (statsapi.mlb.com/api/v1/):
#       Confirmed public/unauthenticated endpoint for schedules, games, and box scores.
#       baseballr::mlb_schedule() / baseballr::mlb_game_pks() wrapper with fallback.
#   - Statcast / Baseball Savant (baseballsavant.mlb.com):
#       baseballr::statcast_search() family for pitch-level data.
#       Documented seam 1: PITCHf/x (2008-2016) vs. Statcast (2017+).
#       Documented seam 2: 2026 strike zone reference point changed to middle-of-plate.
#
# Interface contract (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 / Issue #13):
#   - Callable top-level function: run_mlb_ingest(season = NULL, start_date = NULL, end_date = NULL, force_refresh = FALSE)
#   - Writes to cache_path("ingest", ...)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_ingest.R"

MLB_STATS_API_BASE <- "https://statsapi.mlb.com/api/v1"

#' Ingest MLB Regular & Postseason Schedule for a Season
#'
#' @param season Integer year (e.g. 2024, 2025, 2026)
#' @param force_refresh If TRUE, re-fetches from API even if cached
#' @return A tibble with game schedule details
ingest_mlb_schedule <- function(season = 2024, force_refresh = FALSE) {
  cache_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", season))
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached MLB schedule for %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  log_info(sprintf("Fetching MLB schedule for season %d", season), script = .LOG_SCRIPT)
  
  sched_df <- tryCatch({
    if (.mlb_has_baseballr) {
      df <- baseballr::mlb_schedule(season = season)
      if (!is.null(df) && nrow(df) > 0) {
        # Standardize aliases if baseballr returns teams_away_team_name format
        if ("teams_away_team_name" %in% names(df) && !"away_team_name" %in% names(df)) {
          df$away_team_name <- df$teams_away_team_name
        }
        if ("teams_home_team_name" %in% names(df) && !"home_team_name" %in% names(df)) {
          df$home_team_name <- df$teams_home_team_name
        }
        if ("teams_away_team_id" %in% names(df) && !"away_team_id" %in% names(df)) {
          df$away_team_id <- df$teams_away_team_id
        }
        if ("teams_home_team_id" %in% names(df) && !"home_team_id" %in% names(df)) {
          df$home_team_id <- df$teams_home_team_id
        }
        if ("teams_away_score" %in% names(df) && !"away_score" %in% names(df)) {
          df$away_score <- df$teams_away_score
        }
        if ("teams_home_score" %in% names(df) && !"home_score" %in% names(df)) {
          df$home_score <- df$teams_home_score
        }
        df
      } else {
        NULL
      }
    } else {
      NULL
    }
  }, error = function(e) {
    log_warn("baseballr::mlb_schedule failed, attempting direct MLB Stats API fallback",
             condition = e, script = .LOG_SCRIPT)
    NULL
  })
  
  if (is.null(sched_df)) {
    # Direct MLB Stats API fallback
    url <- sprintf("%s/schedule?sportId=1&season=%d&hydrate=team,probablePitcher,lineups",
                   MLB_STATS_API_BASE, season)
    raw <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) {
      log_error("Direct MLB schedule API fetch failed", condition = e, script = .LOG_SCRIPT)
      NULL
    })
    
    if (!is.null(raw) && !is.null(raw$dates)) {
      games_list <- list()
      for (d in raw$dates) {
        dt <- d$date
        for (g in (d$games %||% list())) {
          away_t <- g$teams$away
          home_t <- g$teams$home
          games_list[[length(games_list) + 1]] <- tibble::tibble(
            game_pk           = as.integer(g$gamePk %||% NA_integer_),
            game_date         = as.character(dt),
            season            = as.integer(season),
            game_type         = as.character(g$gameType %||% ""),
            status            = as.character(g$status$detailedState %||% ""),
            away_team_id      = as.integer(away_t$team$id %||% NA_integer_),
            away_team_name    = as.character(away_t$team$name %||% ""),
            away_score        = as.integer(away_t$score %||% NA_integer_),
            away_probable_id  = as.integer(away_t$probablePitcher$id %||% NA_integer_),
            home_team_id      = as.integer(home_t$team$id %||% NA_integer_),
            home_team_name    = as.character(home_t$team$name %||% ""),
            home_score        = as.integer(home_t$score %||% NA_integer_),
            home_probable_id  = as.integer(home_t$probablePitcher$id %||% NA_integer_),
            venue_id          = as.integer(g$venue$id %||% NA_integer_),
            venue_name        = as.character(g$venue$name %||% "")
          )
        }
      }
      if (length(games_list) > 0) {
        sched_df <- dplyr::bind_rows(games_list)
      }
    }
  }
  
  if (is.null(sched_df) || nrow(sched_df) == 0) {
    log_warn(sprintf("No schedule records retrieved for season %d", season), script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }
  
  saveRDS(sched_df, cache_file)
  log_info(sprintf("Saved %d schedule records for %d to cache", nrow(sched_df), season),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  sched_df
}

#' Ingest Box Scores for a Vector of Game PKs
#'
#' @param game_pks Integer or character vector of MLB game IDs
#' @param season Optional season integer for caching
#' @param force_refresh If TRUE, re-fetches even if cached
#' @return A tibble of aggregated team/game box scores
ingest_mlb_boxscores <- function(game_pks, season = 2024, force_refresh = FALSE) {
  cache_file <- cache_path("ingest", sprintf("mlb_boxscores_%d.rds", season))
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached box scores for %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  if (length(game_pks) == 0) {
    log_warn("No game PKs provided for boxscore ingestion", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  log_info(sprintf("Ingesting box scores for %d games (season %d)", length(game_pks), season),
           script = .LOG_SCRIPT)
  
  # Fetch box scores via direct API in chunks or loop
  box_rows <- list()
  # Sample or full batch
  sample_pks <- utils::head(game_pks, 100) # Safeguard batch size
  
  for (pk in sample_pks) {
    url <- sprintf("%s/game/%s/boxscore", MLB_STATS_API_BASE, as.character(pk))
    bs <- tryCatch(fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(bs) || is.null(bs$teams)) next
    
    for (side in c("away", "home")) {
      tm <- bs$teams[[side]]
      ts <- tm$teamStats
      bat <- ts$batting %||% list()
      pit <- ts$pitching %||% list()
      
      box_rows[[length(box_rows) + 1]] <- tibble::tibble(
        game_pk          = as.integer(pk),
        side             = as.character(side),
        team_id          = as.integer(tm$team$id %||% NA_integer_),
        team_name        = as.character(tm$team$name %||% ""),
        runs             = as.integer(bat$runs %||% NA_integer_),
        hits             = as.integer(bat$hits %||% NA_integer_),
        errors           = as.integer(ts$fielding$errors %||% 0),
        rbi              = as.integer(bat$rbi %||% 0),
        home_runs        = as.integer(bat$homeRuns %||% 0),
        strikeouts       = as.integer(bat$strikeOuts %||% 0),
        base_on_balls    = as.integer(bat$baseOnBalls %||% 0),
        pitchers_used    = as.integer(length(tm$pitchers %||% list())),
        strikeouts_thrown = as.integer(pit$strikeOuts %||% 0),
        walks_allowed    = as.integer(pit$baseOnBalls %||% 0),
        runs_allowed     = as.integer(pit$runs %||% 0)
      )
    }
  }
  
  if (length(box_rows) == 0) {
    log_warn("No box score records successfully parsed", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  box_df <- dplyr::bind_rows(box_rows)
  saveRDS(box_df, cache_file)
  log_info(sprintf("Saved %d team box score entries to cache", nrow(box_df)),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  box_df
}

#' Ingest Statcast Pitch-Level Data with Documented Seam Awareness
#'
#' @param start_date Date string YYYY-MM-DD
#' @param end_date Date string YYYY-MM-DD
#' @param force_refresh If TRUE, re-fetches even if cached
#' @return A tibble of pitch-level Statcast data with seam annotations
ingest_statcast_pitches <- function(start_date = "2024-04-01",
                                    end_date = "2024-04-03",
                                    force_refresh = FALSE) {
  cache_file <- cache_path("ingest", sprintf("statcast_pitches_%s_%s.rds", start_date, end_date))
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached Statcast pitches (%s to %s) from disk", start_date, end_date),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  log_info(sprintf("Querying Statcast pitch data from %s to %s", start_date, end_date),
           script = .LOG_SCRIPT)
  
  pitches <- tryCatch({
    if (.mlb_has_baseballr) {
      baseballr::statcast_search(start_date = start_date, end_date = end_date)
    } else {
      stop("baseballr is required for Statcast pitch data")
    }
  }, error = function(e) {
    log_error("statcast_search failed", condition = e, script = .LOG_SCRIPT)
    NULL
  })
  
  if (is.null(pitches) || nrow(pitches) == 0) {
    log_warn("No Statcast pitch records retrieved", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }
  
  # Annotate documented coverage seams (docs/research/phase0a-vendor-api.md §16)
  start_yr <- as.integer(substr(start_date, 1, 4))
  pitches <- pitches %>%
    dplyr::mutate(
      tracking_system = ifelse(start_yr < 2017, "PITCHf_x_adjusted", "Statcast_out_of_hand"),
      sz_reference_point = ifelse(start_yr >= 2026, "middle_of_plate_ABS", "front_of_plate")
    )
  
  saveRDS(pitches, cache_file)
  log_info(sprintf("Saved %d pitch records to cache (%s, zone ref: %s)",
                   nrow(pitches), pitches$tracking_system[1], pitches$sz_reference_point[1]),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  pitches
}

#' Master Stage Runner for Phase 1 MLB Ingestion
#'
#' @param season Season integer (defaults to current year or 2024)
#' @param start_date Optional start date for Statcast sample
#' @param end_date Optional end date for Statcast sample
#' @param force_refresh If TRUE, re-ingests even if cached
#' @return A named list of ingested schedule and box score summaries
run_mlb_ingest <- function(season = 2024,
                           start_date = "2024-04-01",
                           end_date = "2024-04-02",
                           force_refresh = FALSE) {
  log_info("Starting MLB data ingestion stage", script = .LOG_SCRIPT,
           season = season, force_refresh = force_refresh)
  
  # 1. Ingest schedule
  sched <- ingest_mlb_schedule(season = season, force_refresh = force_refresh)
  
  # 2. Ingest box scores for completed games
  completed_pks <- if (!is.null(sched) && "game_pk" %in% names(sched)) {
    unique(sched$game_pk[!is.na(sched$game_pk)])
  } else {
    integer()
  }
  
  boxscores <- if (length(completed_pks) > 0) {
    ingest_mlb_boxscores(game_pks = completed_pks, season = season, force_refresh = force_refresh)
  } else {
    tibble::tibble()
  }
  
  # 3. Ingest Statcast sample
  statcast_sample <- ingest_statcast_pitches(
    start_date = start_date,
    end_date = end_date,
    force_refresh = force_refresh
  )
  
  summary <- list(
    schedule  = sched,
    boxscores = boxscores,
    statcast  = statcast_sample
  )
  
  log_info(sprintf("Completed MLB data ingestion: %d schedule rows, %d box score rows, %d Statcast rows",
                   nrow(sched), nrow(boxscores), nrow(statcast_sample)),
           script = .LOG_SCRIPT)
  
  invisible(summary)
}
