# ==============================================================================
# mlb_ingest.R — MLB Stats API & Statcast Ingestion Engine
# Path: mlb_ingest.R
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
#   - Callable top-level function:
#       run_mlb_ingest(season = resolve_current_season(), start_date = NULL,
#                      end_date = NULL, force_refresh = FALSE, refresh_current = TRUE)
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

#' Resolve the Active MLB Season Year
#'
#' Checks `MLB_CURRENT_SEASON` (from config.R), then `CURRENT_SEASON`, and falls
#' back to the current calendar year when neither is defined.
#'
#' @return Integer season year
resolve_current_season <- function() {
  for (sym in c("MLB_CURRENT_SEASON", "CURRENT_SEASON")) {
    if (exists(sym, inherits = TRUE)) {
      val <- suppressWarnings(as.integer(get(sym, inherits = TRUE)))
      if (length(val) == 1L && !is.na(val) && val >= 1900L) {
        return(val)
      }
    }
  }
  as.integer(format(Sys.Date(), "%Y"))
}

.normalize_season_arg <- function(season) {
  if (is.null(season) || length(season) == 0L || is.na(season[1])) {
    return(resolve_current_season())
  }
  as.integer(season[1])
}

#' Build Canonical Season-Scoped Statcast Cache Path
#'
#' @param season Integer season year (defaults to current season)
#' @param create Logical; if TRUE, creates the ingest cache directory if needed
#' @return Normalized path to `cache/ingest/statcast_pitches_<season>.rds`
statcast_cache_path <- function(season = resolve_current_season(), create = TRUE) {
  season <- .normalize_season_arg(season)
  cache_path("ingest", sprintf("statcast_pitches_%d.rds", season), create = create)
}

#' Determine Whether an Ingest Cache File Should Be Refreshed
#'
#' Historical seasons (`season < current_season`) load cleanly from disk cache
#' when present unless `force_refresh = TRUE`. The current (or future) season is
#' refreshed when `refresh_current = TRUE` so newly completed games and Statcast
#' pitches are never masked by a build-once `file.exists()` short-circuit.
#'
#' @param season Integer season year
#' @param cache_file Path to the season cache file
#' @param force_refresh Logical; forces re-fetch regardless of season
#' @param refresh_current Logical; refreshes when `season >= current_season`
#' @param current_season Reference current season (defaults to `resolve_current_season()`)
#' @return Logical TRUE if the stage should fetch fresh data, FALSE to reuse cache
should_refresh_season_cache <- function(season,
                                        cache_file,
                                        force_refresh = FALSE,
                                        refresh_current = TRUE,
                                        current_season = resolve_current_season()) {
  if (!file.exists(cache_file)) return(TRUE)
  if (isTRUE(force_refresh)) return(TRUE)

  season_int <- suppressWarnings(as.integer(season))
  curr_int <- suppressWarnings(as.integer(current_season))
  if (isTRUE(refresh_current) &&
      length(season_int) == 1L && !is.na(season_int) &&
      length(curr_int) == 1L && !is.na(curr_int) &&
      season_int >= curr_int) {
    return(TRUE)
  }

  FALSE
}

#' Parse Game Dates From an Ingested MLB Schedule
#'
#' Coalesces `official_date`, `game_date`, and `date` (supporting ISO timestamps).
#'
#' @param sched Schedule data.frame/tibble
#' @return Date vector aligned with rows of `sched`
extract_schedule_dates <- function(sched) {
  if (is.null(sched) || !is.data.frame(sched) || nrow(sched) == 0L) {
    return(as.Date(character(0)))
  }
  out <- rep(as.Date(NA), nrow(sched))
  for (col in c("official_date", "game_date", "date")) {
    if (col %in% names(sched)) {
      vals <- as.character(sched[[col]])
      parsed <- suppressWarnings(as.Date(substr(trimws(vals), 1L, 10L), format = "%Y-%m-%d"))
      need <- is.na(out) & !is.na(parsed)
      out[need] <- parsed[need]
    }
  }
  out
}

#' Filter an Ingested Schedule Down to Completed Official Slate Games
#'
#' Excludes non-slate game types (Spring Training `"S"`, All-Star `"A"`,
#' Exhibitions `"E"`) when `game_type` is present, and excludes scheduled,
#' postponed, or in-progress games when status or score columns exist.
#'
#' @param sched Schedule data.frame/tibble
#' @return Filtered tibble/data.frame of completed games
extract_completed_games <- function(sched) {
  if (is.null(sched) || !is.data.frame(sched) || nrow(sched) == 0L) {
    return(tibble::tibble())
  }

  df <- sched
  slate_types <- if (exists("MATCHUP_GAME_TYPES", inherits = TRUE)) {
    get("MATCHUP_GAME_TYPES", inherits = TRUE)
  } else {
    c("R", "F", "D", "L", "W")
  }

  if ("game_type" %in% names(df)) {
    gt <- trimws(as.character(df$game_type))
    keep_gt <- is.na(gt) | !nzchar(gt) | gt %in% slate_types
    df <- df[keep_gt, , drop = FALSE]
    if (nrow(df) == 0L) return(df)
  }

  n <- nrow(df)
  status_chr <- rep(NA_character_, n)
  has_status_col <- FALSE
  for (col in c("status_detailed_state", "status", "status_abstract_game_state")) {
    if (col %in% names(df)) {
      has_status_col <- TRUE
      vals <- trimws(as.character(df[[col]]))
      vals[!nzchar(vals)] <- NA_character_
      need <- is.na(status_chr) & !is.na(vals)
      status_chr[need] <- vals[need]
    }
  }

  home_col <- intersect(c("home_score", "teams_home_score"), names(df))[1]
  away_col <- intersect(c("away_score", "teams_away_score"), names(df))[1]
  has_score_cols <- !is.na(home_col) && !is.na(away_col)
  both_scores <- if (has_score_cols) {
    !is.na(df[[home_col]]) & !is.na(df[[away_col]])
  } else {
    rep(FALSE, n)
  }

  if (has_status_col && any(!is.na(status_chr))) {
    has_row_status <- !is.na(status_chr)
    status_final <- has_row_status & grepl("^(Final|Completed Early|Game Over)\\b", status_chr, ignore.case = TRUE)
    is_completed <- status_final | (!has_row_status & has_score_cols & both_scores)
  } else if (has_score_cols) {
    is_completed <- both_scores
  } else {
    is_completed <- rep(TRUE, n)
  }

  df[is_completed, , drop = FALSE]
}

#' Derive Statcast Ingestion Date Window From Season Schedule
#'
#' Computes the inclusive `[start_date, end_date]` window spanning the earliest
#' and latest completed slate game dates in `sched`. Returns `NULL` when no
#' completed game dates are available.
#'
#' @param sched Schedule data.frame/tibble
#' @param season Optional season year (unused when dates are in `sched`; kept
#'   for interface symmetry)
#' @return Named list `list(start_date = "YYYY-MM-DD", end_date = "YYYY-MM-DD", n_games = <int>)`,
#'   or `NULL` when no completed game dates exist
derive_statcast_window <- function(sched, season = resolve_current_season()) {
  completed <- extract_completed_games(sched)
  if (nrow(completed) == 0L) return(NULL)

  dates <- extract_schedule_dates(completed)
  dates <- dates[!is.na(dates)]
  if (length(dates) == 0L) return(NULL)

  list(
    start_date = format(min(dates), "%Y-%m-%d"),
    end_date   = format(max(dates), "%Y-%m-%d"),
    n_games    = as.integer(nrow(completed))
  )
}

#' Split an Inclusive Date Window Into Contiguous Non-Overlapping Sub-Windows
#'
#' @param start_date Start date string YYYY-MM-DD (or Date)
#' @param end_date End date string YYYY-MM-DD (or Date)
#' @param chunk_days Maximum days per sub-window (default 5L for Baseball Savant limits)
#' @return List of `list(start_date, end_date)` elements
build_date_chunks <- function(start_date, end_date, chunk_days = 5L) {
  s <- suppressWarnings(as.Date(start_date))
  e <- suppressWarnings(as.Date(end_date))
  if (length(s) != 1L || length(e) != 1L || is.na(s) || is.na(e) || e < s) {
    return(list())
  }
  if (is.null(chunk_days) || is.na(chunk_days) || as.integer(chunk_days) <= 0L) {
    return(list(list(
      start_date = format(s, "%Y-%m-%d"),
      end_date   = format(e, "%Y-%m-%d")
    )))
  }
  step <- as.integer(chunk_days)
  starts <- seq(s, e, by = paste(step, "days"))
  lapply(starts, function(cs) {
    ce <- min(cs + (step - 1L), e)
    list(
      start_date = format(cs, "%Y-%m-%d"),
      end_date   = format(ce, "%Y-%m-%d")
    )
  })
}

#' Ingest MLB Regular & Postseason Schedule for a Season
#'
#' @param season Integer year (defaults to active season from config.R)
#' @param force_refresh If TRUE, re-fetches from API even if cached
#' @param refresh_current If TRUE, re-fetches when `season >= current_season`
#' @param url_reader Optional function(url) returning parsed JSON list (for tests)
#' @return A tibble with game schedule details
ingest_mlb_schedule <- function(season = resolve_current_season(),
                                force_refresh = FALSE,
                                refresh_current = TRUE,
                                url_reader = NULL) {
  season <- .normalize_season_arg(season)
  cache_file <- if (exists("CACHE_MLB_SCHEDULE", mode = "function")) {
    CACHE_MLB_SCHEDULE(season)
  } else {
    cache_path("ingest", sprintf("mlb_schedule_%d.rds", season))
  }

  if (!should_refresh_season_cache(season = season, cache_file = cache_file,
                                   force_refresh = force_refresh,
                                   refresh_current = refresh_current)) {
    log_info(sprintf("Loading cached MLB schedule for %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }

  log_info(sprintf("Fetching MLB schedule for season %d", season), script = .LOG_SCRIPT)

  sched_df <- tryCatch({
    if (is.null(url_reader) && .mlb_has_baseballr) {
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
    reader <- if (is.null(url_reader)) {
      function(u) jsonlite::fromJSON(u, simplifyVector = FALSE)
    } else {
      url_reader
    }
    # Direct MLB Stats API fallback
    url <- sprintf("%s/schedule?sportId=1&season=%d&hydrate=team,probablePitcher,lineups",
                   MLB_STATS_API_BASE, season)
    raw <- tryCatch(reader(url), error = function(e) {
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
          games_list[[length(games_list) + 1L]] <- list(
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
      if (length(games_list) > 0L) {
        sched_df <- dplyr::bind_rows(games_list)
      }
    }
  }

  if (is.null(sched_df) || nrow(sched_df) == 0L) {
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
#' @param game_pks Integer or character vector of MLB game IDs (uncapped)
#' @param season Season integer for caching (defaults to active season)
#' @param force_refresh If TRUE, re-fetches even if cached
#' @param refresh_current If TRUE, re-fetches when `season >= current_season`
#' @param url_reader Optional function(url) returning parsed JSON list (for tests)
#' @return A tibble of aggregated team/game box scores
ingest_mlb_boxscores <- function(game_pks,
                                 season = resolve_current_season(),
                                 force_refresh = FALSE,
                                 refresh_current = TRUE,
                                 url_reader = NULL) {
  season <- .normalize_season_arg(season)
  cache_file <- cache_path("ingest", sprintf("mlb_boxscores_%d.rds", season))

  if (!should_refresh_season_cache(season = season, cache_file = cache_file,
                                   force_refresh = force_refresh,
                                   refresh_current = refresh_current)) {
    log_info(sprintf("Loading cached box scores for %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }

  target_pks <- if (is.null(game_pks) || length(game_pks) == 0L) {
    integer(0)
  } else {
    unique(game_pks[!is.na(game_pks) & nzchar(trimws(as.character(game_pks)))])
  }

  if (length(target_pks) == 0L) {
    log_warn("No game PKs provided for boxscore ingestion", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }

  log_info(sprintf("Ingesting box scores for %d games (season %d)", length(target_pks), season),
           script = .LOG_SCRIPT)

  reader <- if (is.null(url_reader)) {
    function(u) jsonlite::fromJSON(u, simplifyVector = FALSE)
  } else {
    url_reader
  }

  box_rows <- vector("list", length(target_pks) * 2L)
  row_idx <- 0L

  for (pk in target_pks) {
    url <- sprintf("%s/game/%s/boxscore", MLB_STATS_API_BASE, as.character(pk))
    bs <- tryCatch(reader(url), error = function(e) NULL)
    if (is.null(bs) || is.null(bs$teams)) next

    for (side in c("away", "home")) {
      tm <- bs$teams[[side]]
      if (is.null(tm)) next
      ts <- tm$teamStats %||% list()
      bat <- ts$batting %||% list()
      pit <- ts$pitching %||% list()

      row_idx <- row_idx + 1L
      box_rows[[row_idx]] <- list(
        game_pk           = as.integer(pk),
        side              = as.character(side),
        team_id           = as.integer(tm$team$id %||% NA_integer_),
        team_name         = as.character(tm$team$name %||% ""),
        runs              = as.integer(bat$runs %||% NA_integer_),
        hits              = as.integer(bat$hits %||% NA_integer_),
        errors            = as.integer(ts$fielding$errors %||% 0L),
        rbi               = as.integer(bat$rbi %||% 0L),
        home_runs         = as.integer(bat$homeRuns %||% 0L),
        strikeouts        = as.integer(bat$strikeOuts %||% 0L),
        base_on_balls     = as.integer(bat$baseOnBalls %||% 0L),
        pitchers_used     = as.integer(length(tm$pitchers %||% list())),
        strikeouts_thrown = as.integer(pit$strikeOuts %||% 0L),
        walks_allowed     = as.integer(pit$baseOnBalls %||% 0L),
        runs_allowed      = as.integer(pit$runs %||% 0L)
      )
    }
  }

  if (row_idx == 0L) {
    log_warn("No box score records successfully parsed", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }

  box_df <- dplyr::bind_rows(box_rows[seq_len(row_idx)])
  saveRDS(box_df, cache_file)
  log_info(sprintf("Saved %d team box score entries to cache", nrow(box_df)),
           script = .LOG_SCRIPT, cache_file = cache_file)

  box_df
}

#' Ingest Statcast Pitch-Level Data with Documented Seam Awareness
#'
#' @param start_date Optional date string YYYY-MM-DD (derived from season schedule when omitted)
#' @param end_date Optional date string YYYY-MM-DD (derived from season schedule when omitted)
#' @param force_refresh If TRUE, re-fetches even if cached
#' @param season Optional integer season year (inferred from `start_date` or `resolve_current_season()`)
#' @param refresh_current If TRUE, re-fetches when `season >= current_season`
#' @param chunk_days Maximum days per Statcast query chunk (default 5L)
#' @param search_fn Optional function(start_date, end_date) returning pitch data.frame (for tests)
#' @return A tibble of pitch-level Statcast data with seam annotations
ingest_statcast_pitches <- function(start_date = NULL,
                                    end_date = NULL,
                                    force_refresh = FALSE,
                                    season = NULL,
                                    refresh_current = TRUE,
                                    chunk_days = 5L,
                                    search_fn = NULL) {
  if (is.null(season) || length(season) == 0L || is.na(season[1])) {
    inferred <- if (!is.null(start_date)) {
      suppressWarnings(as.integer(substr(as.character(start_date)[1], 1L, 4L)))
    } else {
      NA_integer_
    }
    season <- if (!is.na(inferred)) inferred else resolve_current_season()
  } else {
    season <- as.integer(season[1])
  }

  cache_file <- statcast_cache_path(season = season)

  if (!should_refresh_season_cache(season = season, cache_file = cache_file,
                                   force_refresh = force_refresh,
                                   refresh_current = refresh_current)) {
    log_info(sprintf("Loading cached Statcast pitches for season %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }

  if (is.null(start_date) || is.null(end_date)) {
    sched_file <- if (exists("CACHE_MLB_SCHEDULE", mode = "function")) {
      CACHE_MLB_SCHEDULE(season)
    } else {
      cache_path("ingest", sprintf("mlb_schedule_%d.rds", season), create = FALSE)
    }
    if (file.exists(sched_file)) {
      derived <- derive_statcast_window(readRDS(sched_file), season = season)
      if (!is.null(derived)) {
        if (is.null(start_date)) start_date <- derived$start_date
        if (is.null(end_date)) end_date <- derived$end_date
      }
    }
  }

  if (is.null(start_date) || is.null(end_date)) {
    log_warn(sprintf("No Statcast date window supplied or derivable for season %d", season),
             script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }

  chunks <- build_date_chunks(start_date, end_date, chunk_days = chunk_days)
  if (length(chunks) == 0L) {
    log_warn(sprintf("Invalid Statcast date window (%s to %s) for season %d",
                     as.character(start_date), as.character(end_date), season),
             script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }

  if (is.null(search_fn)) {
    if (!.mlb_has_baseballr) {
      log_error("statcast_search failed",
                condition = simpleError("baseballr is required for Statcast pitch data"),
                script = .LOG_SCRIPT)
      if (file.exists(cache_file)) return(readRDS(cache_file))
      return(tibble::tibble())
    }
    search_fn <- function(s_date, e_date) {
      baseballr::statcast_search(start_date = s_date, end_date = e_date)
    }
  }

  log_info(sprintf("Querying Statcast pitch data for season %d from %s to %s (%d chunk(s))",
                   season, start_date, end_date, length(chunks)),
           script = .LOG_SCRIPT)

  chunk_dfs <- list()
  for (ch in chunks) {
    df <- tryCatch(
      search_fn(ch$start_date, ch$end_date),
      error = function(e) {
        log_error("statcast_search failed", condition = e, script = .LOG_SCRIPT,
                  start_date = ch$start_date, end_date = ch$end_date)
        NULL
      }
    )
    if (!is.null(df) && is.data.frame(df) && nrow(df) > 0L) {
      chunk_dfs[[length(chunk_dfs) + 1L]] <- df
    }
  }

  pitches <- if (length(chunk_dfs) > 0L) dplyr::bind_rows(chunk_dfs) else tibble::tibble()

  if (nrow(pitches) == 0L) {
    log_warn("No Statcast pitch records retrieved", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) return(readRDS(cache_file))
    return(tibble::tibble())
  }

  # Annotate documented coverage seams (docs/research/phase0a-vendor-api.md §16)
  start_yr <- suppressWarnings(as.integer(substr(as.character(start_date)[1], 1L, 4L)))
  if (is.na(start_yr)) start_yr <- season
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
#' @param season Season integer (defaults to active season from config.R)
#' @param start_date Optional start date YYYY-MM-DD (defaults to derived schedule min date)
#' @param end_date Optional end date YYYY-MM-DD (defaults to derived schedule max date)
#' @param force_refresh If TRUE, re-ingests even if cached
#' @param refresh_current If TRUE, refreshes active/future seasons on disk
#' @param schedule_url_reader Optional reader for schedule API (tests)
#' @param boxscore_url_reader Optional reader for boxscore API (tests)
#' @param statcast_search_fn Optional reader for Statcast search (tests)
#' @return A named list of ingested schedule, boxscore, and Statcast tibbles
run_mlb_ingest <- function(season = resolve_current_season(),
                           start_date = NULL,
                           end_date = NULL,
                           force_refresh = FALSE,
                           refresh_current = TRUE,
                           schedule_url_reader = NULL,
                           boxscore_url_reader = NULL,
                           statcast_search_fn = NULL) {
  season <- .normalize_season_arg(season)

  log_info("Starting MLB data ingestion stage", script = .LOG_SCRIPT,
           season = season, force_refresh = force_refresh,
           refresh_current = refresh_current)

  # 1. Ingest schedule
  sched <- ingest_mlb_schedule(
    season = season,
    force_refresh = force_refresh,
    refresh_current = refresh_current,
    url_reader = schedule_url_reader
  )

  # 2. Ingest box scores for all completed games (uncapped)
  completed_games <- extract_completed_games(sched)
  completed_pks <- if (!is.null(completed_games) && "game_pk" %in% names(completed_games)) {
    unique(completed_games$game_pk[!is.na(completed_games$game_pk)])
  } else {
    integer()
  }

  boxscores <- if (length(completed_pks) > 0L) {
    ingest_mlb_boxscores(
      game_pks = completed_pks,
      season = season,
      force_refresh = force_refresh,
      refresh_current = refresh_current,
      url_reader = boxscore_url_reader
    )
  } else {
    tibble::tibble()
  }

  # 3. Derive Statcast date window from season schedule unless explicitly provided
  window <- if (!is.null(start_date) && !is.null(end_date)) {
    list(start_date = as.character(start_date), end_date = as.character(end_date))
  } else {
    derived <- derive_statcast_window(sched, season = season)
    if (is.null(derived)) {
      NULL
    } else {
      list(
        start_date = as.character(start_date %||% derived$start_date),
        end_date   = as.character(end_date %||% derived$end_date)
      )
    }
  }

  statcast_pitches <- if (!is.null(window)) {
    ingest_statcast_pitches(
      start_date = window$start_date,
      end_date = window$end_date,
      force_refresh = force_refresh,
      season = season,
      refresh_current = refresh_current,
      search_fn = statcast_search_fn
    )
  } else {
    log_warn(sprintf("No completed games in schedule for season %d; skipping Statcast fetch", season),
             script = .LOG_SCRIPT)
    sc_cache <- statcast_cache_path(season = season, create = FALSE)
    if (file.exists(sc_cache)) readRDS(sc_cache) else tibble::tibble()
  }

  summary <- list(
    schedule  = sched,
    boxscores = boxscores,
    statcast  = statcast_pitches
  )

  log_info(sprintf("Completed MLB data ingestion: %d schedule rows, %d box score rows, %d Statcast rows",
                   nrow(sched), nrow(boxscores), nrow(statcast_pitches)),
           script = .LOG_SCRIPT)

  invisible(summary)
}
