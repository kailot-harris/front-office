# ==============================================================================
# prediction_accuracy_logger.R
# Pre-Game Forecast & Accuracy Tracking Stage (Issue #111 / Phase 2, Issue 2-2)
#
# Persists unplayed game forecasts into CACHE_PREDICTION_ACCURACY_LOG
# ("cache/prediction_accuracy_log.rds") with log_source = "LOGGED_PREGAME",
# the 5 points waterfall step values, ridge regression coefficients snapshot,
# margin sigma, and entering power ratings before kickoff.
#
# CRITICAL IMMUTABILITY GUARANTEE:
# Once a game is recorded with log_source = "LOGGED_PREGAME", all pre-game
# forecasts, step values, ridge coefficients, and power ratings are frozen
# permanently and NEVER overwritten on subsequent pipeline runs.
# When a game completes, only the realization result fields (home_score,
# away_score, actual_margin, actual_winner, prediction_correct, brier_score)
# are updated, leaving all pre-game forecast columns completely untouched.
#
# Strictly zero-betting compliant (no betting vocabulary or market data).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
}

if (file.exists("logging_utils.R")) {
  source("logging_utils.R")
} else if (file.exists("../logging_utils.R")) {
  source("../logging_utils.R")
}

source("tools/forecast_engine.R")
source("tools/elo_model.R")
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R")
if (file.exists("tools/backtest_common.R")) {
  source("tools/backtest_common.R")
} else if (file.exists("../tools/backtest_common.R")) {
  source("../tools/backtest_common.R")
}
if (file.exists("team_ratings_engine.R")) {
  source("team_ratings_engine.R")
} else if (file.exists("../team_ratings_engine.R")) {
  source("../team_ratings_engine.R")
}

.LOG_SCRIPT <- "prediction_accuracy_logger.R"

# Session-level cache for fitted ridge regression to avoid refitting repeatedly
if (!exists(".PREDICTION_LOGGER_RIDGE_CACHE", envir = .GlobalEnv)) {
  assign(".PREDICTION_LOGGER_RIDGE_CACHE", NULL, envir = .GlobalEnv)
}

#' Helper to resolve kickoff POSIXct and fallback flag from gameday and gametime
#'
#' If gametime is missing or malformed, freezes at the start of the game date in
#' Eastern time (00:00:00 America/New_York) and sets kickoff_fallback = TRUE.
#'
#' @param gday Character vector "YYYY-MM-DD"
#' @param gtime Character vector "HH:MM" (or NA/malformed)
#' @return A list with kickoff_time (POSIXct vector in America/New_York) and kickoff_fallback (logical vector)
.resolve_kickoff_time <- function(gday, gtime) {
  gday <- as.character(gday)
  gtime <- as.character(gtime)
  n <- max(length(gday), length(gtime))
  if (n == 0L || (length(gday) == 1L && (is.na(gday) || !nzchar(gday)))) {
    return(list(
      kickoff_time     = as.POSIXct(rep(NA, max(1L, n)), tz = "America/New_York"),
      kickoff_fallback = rep(TRUE, max(1L, n))
    ))
  }
  if (length(gday) < n) gday <- rep(gday, length.out = n)
  if (length(gtime) < n) gtime <- rep(gtime, length.out = n)

  has_valid_day <- !is.na(gday) & nzchar(gday)
  has_valid_time <- !is.na(gtime) & grepl("^\\d{1,2}:\\d{2}$", gtime)

  time_clean <- ifelse(has_valid_time,
                       ifelse(nchar(gtime) == 4L, paste0("0", gtime), gtime),
                       "00:00")
  time_part <- ifelse(has_valid_time, paste0(time_clean, ":00"), "00:00:00")
  dt_str <- ifelse(has_valid_day, paste(gday, time_part), NA_character_)

  ko_dt <- as.POSIXct(dt_str, format = "%Y-%m-%d %H:%M:%S", tz = "America/New_York")
  fallback <- !has_valid_time | !has_valid_day

  list(
    kickoff_time     = ko_dt,
    kickoff_fallback = fallback
  )
}

#' Helper to extract ridge coefficients from a model fit, matrix, or list
#'
#' @param fit Model fit object, matrix, or named list/vector of coefficients.
#' @return A named list with b_intercept, b_raw, b_prior, b_raw_gp, b_prior_gp.
get_ridge_coefficient_list <- function(fit) {
  if (is.null(fit)) {
    # Default fallback coefficients
    hca <- if (exists("NFL_HCA", mode = "numeric")) NFL_HCA else 1.84
    return(list(
      ridge_b_intercept = hca,
      ridge_b_raw       = 1.0,
      ridge_b_prior     = 0.0,
      ridge_b_raw_gp    = 0.0,
      ridge_b_prior_gp  = 0.0
    ))
  }

  get_val <- function(names_vec, default = 0.0) {
    if (inherits(fit, "cv.glmnet") || inherits(fit, "glmnet")) {
      mat <- as.matrix(stats::coef(fit, s = "lambda.min"))
      for (nm in names_vec) {
        if (nm %in% rownames(mat)) return(unname(mat[nm, 1]))
      }
    } else if (is.matrix(fit)) {
      for (nm in names_vec) {
        if (nm %in% rownames(fit)) return(unname(fit[nm, 1]))
        if (nm %in% colnames(fit)) return(unname(fit[1, nm]))
      }
    } else if (is.list(fit) || is.vector(fit)) {
      nms <- names(fit)
      for (nm in names_vec) {
        if (!is.null(nms) && nm %in% nms) return(unname(as.numeric(fit[[nm]])))
      }
    }
    default
  }

  list(
    ridge_b_intercept = get_val(c("(Intercept)", "b_intercept", "intercept", "ridge_b_intercept"), 0.0),
    ridge_b_raw       = get_val(c("diff_raw", "b_raw", "ridge_b_raw"), 0.0),
    ridge_b_prior     = get_val(c("diff_prior", "b_prior", "ridge_b_prior"), 0.0),
    ridge_b_raw_gp    = get_val(c("diff_raw_gp", "b_raw_gp", "ridge_b_raw_gp"), 0.0),
    ridge_b_prior_gp  = get_val(c("diff_prior_gp", "b_prior_gp", "ridge_b_prior_gp"), 0.0)
  )
}

#' Resolve Ridge Massey model fit for pregame logging
#'
#' Retrieves the fitted ridge model from session cache, cache file, or fits it
#' out-of-sample on historical seasons prior to CURRENT_SEASON.
#'
#' @param sch Schedules data frame.
#' @param epa EPA metrics data frame.
#' @param force_refit Logical, if TRUE forces refitting.
#' @return glmnet model fit object or NULL.
resolve_ridge_fit <- function(sch, epa, force_refit = FALSE) {
  if (!isTRUE(force_refit)) {
    cached <- get(".PREDICTION_LOGGER_RIDGE_CACHE", envir = .GlobalEnv)
    if (!is.null(cached)) return(cached)
  }

  if (missing(sch) || missing(epa) || is.null(sch) || is.null(epa) ||
      nrow(sch) == 0 || nrow(epa) == 0) {
    return(NULL)
  }

  # Require backtest_common and team_ratings_engine helpers if available
  if (file.exists("tools/backtest_common.R")) source("tools/backtest_common.R")
  if (file.exists("team_ratings_engine.R")) source("team_ratings_engine.R")

  fit <- tryCatch({
    cur_season <- if (exists("CURRENT_SEASON", mode = "numeric")) CURRENT_SEASON else 2026L
    mod_start <- if (exists("MODERN_ERA_START_SEASON", mode = "numeric")) MODERN_ERA_START_SEASON else 2002L
    hist_seasons <- (mod_start + 1L):(cur_season - 1L)

    hist_completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
    avg_plays <- if ("n_off_plays" %in% names(epa)) mean(epa$n_off_plays, na.rm = TRUE) else 62.5

    if (exists("build_walkforward_games", mode = "function") &&
        exists("fit_ridge_massey", mode = "function")) {
      hist_games <- build_walkforward_games(
        epa |> mutate(game_date = as.Date(game_date)),
        hist_completed |> mutate(gameday = as.Date(gameday)),
        hist_seasons,
        avg_plays
      )
      if (nrow(hist_games) >= 100) {
        fit_ridge_massey(hist_games)
      } else {
        NULL
      }
    } else {
      NULL
    }
  }, error = function(e) {
    log_warn(sprintf("resolve_ridge_fit failed: %s", conditionMessage(e)), script = .LOG_SCRIPT)
    NULL
  })

  if (!is.null(fit)) {
    assign(".PREDICTION_LOGGER_RIDGE_CACHE", fit, envir = .GlobalEnv)
  }
  fit
}

#' Resolve live Elo state for pregame logging
#'
#' @param sch Schedules data frame.
#' @param fatigue_path Path to fatigue metrics RDS.
#' @return Elo walkforward state or NULL.
resolve_elo_live <- function(sch, fatigue_path = if (exists("CACHE_FATIGUE_METRICS")) CACHE_FATIGUE_METRICS else "cache/fatigue_metrics.rds") {
  if (missing(sch) || is.null(sch) || nrow(sch) == 0) return(NULL)

  tryCatch({
    cur_season <- if (exists("CURRENT_SEASON", mode = "numeric")) CURRENT_SEASON else 2026L
    mod_start <- if (exists("MODERN_ERA_START_SEASON", mode = "numeric")) MODERN_ERA_START_SEASON else 2002L
    k_fact <- if (exists("ELO_K_FACTOR", mode = "numeric")) ELO_K_FACTOR else 20.0

    elo_hist <- sch |>
      filter(!is.na(home_score), !is.na(away_score),
             season >= mod_start, season <= cur_season) |>
      mutate(gameday = as.Date(gameday))

    fatigue_for_elo <- if (file.exists(fatigue_path)) {
      readRDS(fatigue_path)
    } else {
      data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0))
    }

    if (nrow(elo_hist) < 100) return(NULL)
    run_elo_walkforward(elo_hist, fatigue_for_elo, k_fact, return_final_state = TRUE)
  }, error = function(e) {
    NULL
  })
}

#' Recover missing completed games via honest walk-forward backfill
#'
#' Single unified recovery path for finished games with no pre-game forecast.
#' Routes missing completed games through tools/backfill_prediction_log.R,
#' evaluating ratings strictly prior to each game's week and assigning
#' log_source = "BACKTEST_PREWEEK".
#'
#' @param updated_log Existing prediction log data frame.
#' @param sch Schedules data frame.
#' @param epa_path Path to EPA cache (or data frame).
#' @param fatigue_path Path to fatigue cache (or data frame).
#' @param season Target season.
#' @param ridge_coefs Optional pre-computed ridge coefficients or model object.
#' @return Updated prediction log data frame.
#' @export
recover_missing_backtest_rows <- function(updated_log, sch, epa_path, fatigue_path, season = 2026L, ridge_coefs = NULL, qb_starter_table = NULL) {
  if (is.null(sch) || nrow(sch) == 0) return(updated_log)
  sch_completed <- sch |>
    filter(season == !!season, !is.na(home_score), !is.na(away_score))

  logged_gids <- if (!is.null(updated_log) && nrow(updated_log) > 0) updated_log$game_id else character(0)
  missing_completed <- sch_completed |> filter(!game_id %in% logged_gids)

  if (nrow(missing_completed) == 0) return(updated_log)

  log_info(sprintf("Found %d completed game(s) with no logged forecast. Generating backtest row(s) via walk-forward backfill.",
                   nrow(missing_completed)), script = .LOG_SCRIPT)

  if (!exists("compute_walkforward_backfill", mode = "function")) {
    bf_script <- if (file.exists("tools/backfill_prediction_log.R")) {
      "tools/backfill_prediction_log.R"
    } else if (file.exists("../tools/backfill_prediction_log.R")) {
      "../tools/backfill_prediction_log.R"
    } else {
      NULL
    }
    if (!is.null(bf_script)) source(bf_script)
  }

  epa_data <- if (is.data.frame(epa_path)) {
    epa_path
  } else if (!is.null(epa_path) && file.exists(epa_path)) {
    readRDS(epa_path)
  } else {
    NULL
  }

  fatigue_data <- if (is.data.frame(fatigue_path)) {
    fatigue_path
  } else if (!is.null(fatigue_path) && file.exists(fatigue_path)) {
    readRDS(fatigue_path)
  } else {
    NULL
  }

  if (exists("compute_walkforward_backfill", mode = "function") && !is.null(epa_data)) {
    backfill_df <- compute_walkforward_backfill(
      sch         = sch,
      epa         = epa_data,
      fatigue     = fatigue_data,
      season      = season,
      ridge_coefs = ridge_coefs,
      qb_starter_table = qb_starter_table
    )
    if (!is.null(backfill_df) && nrow(backfill_df) > 0) {
      missing_rows <- backfill_df |> filter(game_id %in% missing_completed$game_id)
      if (nrow(missing_rows) > 0) {
        updated_log <- if (is.null(updated_log) || nrow(updated_log) == 0) {
          missing_rows
        } else {
          bind_rows(updated_log, missing_rows)
        }
        log_info(sprintf("Successfully added %d backtested forecast row(s) for completed games.", nrow(missing_rows)),
                 script = .LOG_SCRIPT)
      }
    }
  } else {
    log_warn("compute_walkforward_backfill or epa_data unavailable; cannot backfill missing completed games.",
             script = .LOG_SCRIPT)
  }

  updated_log
}

#' Run Prediction Accuracy Logger
#'
#' Primary pipeline entry point. Reads projected matchups and schedules, appends
#' newly projected unplayed games with log_source = "LOGGED_PREGAME", refreshes
#' unplayed games until their kickoff time, freezes pre-game forecast columns at
#' kickoff, and updates realized scores for completed games.
#'
#' Kickoff Freeze Architecture (Owner Decision / Issue #149):
#' - Dual timestamps: `logged_at` (when first logged) and `refreshed_at` (last updated).
#' - Unplayed forecasts refresh on every run prior to kickoff.
#' - Kickoff freeze: once current time (or run start time) reaches kickoff, forecasts
#'   are permanently frozen.
#' - Mid-run kickoff safety: a run that starts before kickoff but finishes after it
#'   does NOT refresh that game.
#' - Missing kickoff fallback: if gametime is missing/malformed, freezes at start of
#'   the game's date in Eastern time (00:00:00 America/New_York) with kickoff_fallback = TRUE.
#' - Post-kickoff creation guard: unlogged games past kickoff are never created as
#'   LOGGED_PREGAME.
#' - Rescheduled games: follows updated kickoff time from schedule.
#'
#' @param log_path Path to persist the prediction accuracy log RDS.
#' @param schedules_path Path to schedules cache RDS.
#' @param projected_matchups_path Path to projected matchups cache RDS.
#' @param team_ratings_path Path to team ratings cache RDS.
#' @param epa_path Path to EPA metrics cache RDS.
#' @param fatigue_path Path to fatigue metrics cache RDS.
#' @param ridge_coefs Optional pre-computed ridge coefficients or model object.
#' @param qb_lookup Optional named logical vector of backup QB status by team.
#' @param elo_live Optional live Elo state.
#' @param force_refit Logical, if TRUE forces refit of Ridge model.
#' @param as_of Timestamp for run start (defaults to Sys.time()).
#' @param eval_time Optional timestamp for mid-run evaluation timing check.
#' @return Invisible data.frame of the full prediction accuracy log.
#' @export
run_prediction_accuracy_logger <- function(
    log_path                = if (exists("CACHE_PREDICTION_ACCURACY_LOG")) CACHE_PREDICTION_ACCURACY_LOG else file.path("cache", "prediction_accuracy_log.rds"),
    schedules_path          = if (exists("CACHE_SCHEDULES")) CACHE_SCHEDULES else file.path("cache", "schedules_cache.rds"),
    projected_matchups_path = if (exists("CACHE_PROJECTED_MATCHUPS")) CACHE_PROJECTED_MATCHUPS else file.path("cache", "projected_matchups.rds"),
    team_ratings_path       = if (exists("CACHE_TEAM_RATINGS")) CACHE_TEAM_RATINGS else file.path("cache", "team_ratings.rds"),
    epa_path                = if (exists("CACHE_EPA_METRICS")) CACHE_EPA_METRICS else file.path("cache", "team_epa_metrics.rds"),
    fatigue_path            = if (exists("CACHE_FATIGUE_METRICS")) CACHE_FATIGUE_METRICS else file.path("cache", "fatigue_metrics.rds"),
    ridge_coefs             = NULL,
    qb_lookup               = NULL,
    qb_starter_table        = NULL,
    elo_live                = NULL,
    force_refit             = FALSE,
    as_of                   = Sys.time(),
    eval_time               = NULL) {

  log_info("Starting prediction accuracy logger pipeline stage.", script = .LOG_SCRIPT)

  run_start_time <- as.POSIXct(as_of, tz = "America/New_York")
  eval_time_val <- if (is.null(eval_time)) {
    if (missing(as_of)) as.POSIXct(Sys.time(), tz = "America/New_York") else run_start_time
  } else {
    as.POSIXct(eval_time, tz = "America/New_York")
  }

  # Ensure target directory exists
  log_dir <- dirname(log_path)
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # 1. Load existing log (if any)
  existing_log <- if (file.exists(log_path)) {
    tryCatch({
      readRDS(log_path)
    }, error = function(e) {
      log_warn(sprintf("Could not read existing log from %s: %s. Starting fresh.", log_path, conditionMessage(e)), script = .LOG_SCRIPT)
      NULL
    })
  } else {
    NULL
  }

  # Standardize timestamp and kickoff columns in existing log
  if (!is.null(existing_log) && nrow(existing_log) > 0) {
    if (!"logged_at" %in% names(existing_log)) {
      existing_log$logged_at <- if ("log_timestamp" %in% names(existing_log)) existing_log$log_timestamp else run_start_time
    } else {
      na_logged <- is.na(existing_log$logged_at)
      if (any(na_logged) && "log_timestamp" %in% names(existing_log)) {
        existing_log$logged_at[na_logged] <- existing_log$log_timestamp[na_logged]
      }
    }

    if (!"refreshed_at" %in% names(existing_log)) {
      existing_log$refreshed_at <- existing_log$logged_at
    } else {
      na_refreshed <- is.na(existing_log$refreshed_at)
      if (any(na_refreshed)) {
        existing_log$refreshed_at[na_refreshed] <- existing_log$logged_at[na_refreshed]
      }
    }

    if (!"log_timestamp" %in% names(existing_log)) {
      existing_log$log_timestamp <- existing_log$logged_at
    }

    if (!"kickoff_time" %in% names(existing_log)) {
      existing_log$kickoff_time <- as.POSIXct(NA, tz = "America/New_York")
    }
    if (!"kickoff_fallback" %in% names(existing_log)) {
      existing_log$kickoff_fallback <- FALSE
    }
    if (!"away_win_prob" %in% names(existing_log) && "home_win_prob" %in% names(existing_log)) {
      existing_log$away_win_prob <- 1.0 - existing_log$home_win_prob
    }
  }

  # 2. Load schedules
  sch <- if (file.exists(schedules_path)) {
    tryCatch(readRDS(schedules_path), error = function(e) NULL)
  } else {
    NULL
  }

  # Backfill missing kickoff_time from schedule on existing rows if schedule is available
  if (!is.null(existing_log) && nrow(existing_log) > 0 && !is.null(sch) && nrow(sch) > 0) {
    need_ko <- is.na(existing_log$kickoff_time)
    if (any(need_ko)) {
      sch_match_idx <- match(existing_log$game_id[need_ko], sch$game_id)
      valid_match <- !is.na(sch_match_idx)
      if (any(valid_match)) {
        matched_sch <- sch[sch_match_idx[valid_match], ]
        ko_res <- .resolve_kickoff_time(matched_sch$gameday, matched_sch$gametime)
        row_indices <- which(need_ko)[valid_match]
        existing_log$kickoff_time[row_indices]     <- ko_res$kickoff_time
        existing_log$kickoff_fallback[row_indices] <- ko_res$kickoff_fallback
      }
    }
  }

  # 3. Load projected matchups (upcoming unplayed forecasts from Stage 5)
  pm <- if (file.exists(projected_matchups_path)) {
    tryCatch(readRDS(projected_matchups_path), error = function(e) NULL)
  } else {
    NULL
  }

  # 4. Load team ratings (raw & prior ratings lookups)
  tr <- if (file.exists(team_ratings_path)) {
    tryCatch(readRDS(team_ratings_path), error = function(e) NULL)
  } else {
    NULL
  }

  raw_lookup <- if (!is.null(tr) && "current_raw_rating" %in% names(tr)) {
    setNames(tr$current_raw_rating, tr$team)
  } else {
    list()
  }

  prior_lookup <- if (!is.null(tr) && "prior_season_rating" %in% names(tr)) {
    setNames(tr$prior_season_rating, tr$team)
  } else {
    list()
  }

  # 5. QB backup lookup
  if (is.null(qb_lookup)) {
    qb_lookup <- tryCatch({
      if (exists("get_live_qb_backup_flags", mode = "function")) {
        get_live_qb_backup_flags()
      } else {
        list()
      }
    }, error = function(e) list())
  }

  # 6. Live Elo state lookup
  if (is.null(elo_live) && !is.null(sch)) {
    elo_live <- resolve_elo_live(sch, fatigue_path)
  }

  get_team_elo <- function(team, season) {
    if (is.null(elo_live)) return(NA_real_)
    r <- elo_live$final_elo[team]
    s <- elo_live$final_season[team]
    if (is.na(r) || is.na(s)) return(NA_real_)
    project_elo_rating(unname(r), unname(s), season)
  }

  # 7. Ridge coefficients resolution
  resolved_coefs <- if (!is.null(ridge_coefs)) {
    get_ridge_coefficient_list(ridge_coefs)
  } else {
    epa <- if (file.exists(epa_path)) tryCatch(readRDS(epa_path), error = function(e) NULL) else NULL
    ridge_fit <- resolve_ridge_fit(sch, epa, force_refit = force_refit)
    get_ridge_coefficient_list(ridge_fit)
  }

  sigma_val <- if (exists("NFL_MARGIN_SIGMA", mode = "numeric")) NFL_MARGIN_SIGMA else 14.60

  # 8. Process projected matchups: refresh unplayed pre-kickoff forecasts and create new rows
  new_rows_list <- list()
  n_unplayed_refreshed <- 0L
  n_postkickoff_skipped <- 0L

  if (!is.null(pm) && nrow(pm) > 0) {
    for (i in seq_len(nrow(pm))) {
      g <- pm[i, ]
      home <- g$home_team
      away <- g$away_team
      gid  <- g$game_id

      # Metadata from schedule if available
      sch_match <- if (!is.null(sch)) sch |> filter(game_id == gid) else NULL
      gday  <- if (!is.null(sch_match) && nrow(sch_match) > 0 && "gameday" %in% names(sch_match)) as.character(sch_match$gameday[1]) else NA_character_
      wday  <- if (!is.null(sch_match) && nrow(sch_match) > 0 && "weekday" %in% names(sch_match)) as.character(sch_match$weekday[1]) else NA_character_
      gtime <- if (!is.null(sch_match) && nrow(sch_match) > 0 && "gametime" %in% names(sch_match)) as.character(sch_match$gametime[1]) else NA_character_
      loc   <- if (!is.null(sch_match) && nrow(sch_match) > 0 && "location" %in% names(sch_match)) as.character(sch_match$location[1]) else "Home"
      neu   <- if ("neutral" %in% names(g)) isTRUE(as.logical(g$neutral)) else FALSE

      # Resolve kickoff time and fallback flag
      ko_res <- .resolve_kickoff_time(gday, gtime)
      ko_dt  <- ko_res$kickoff_time
      ko_fb  <- ko_res$kickoff_fallback

      # Mid-run and start-time kickoff freeze evaluation:
      # If run started at/after kickoff OR reached evaluation at/after kickoff, it is past kickoff.
      is_past_kickoff <- is.na(ko_dt) || (run_start_time >= ko_dt) || (eval_time_val >= ko_dt)

      # Check if game already exists in log
      existing_idx <- if (!is.null(existing_log) && nrow(existing_log) > 0) {
        which(existing_log$game_id == gid)
      } else {
        integer(0)
      }

      if (length(existing_idx) > 0) {
        idx <- existing_idx[1]
        # Check if game is already completed
        is_completed <- (!is.na(existing_log$home_score[idx]) && !is.na(existing_log$away_score[idx])) ||
                        (!is.null(sch_match) && nrow(sch_match) > 0 && !is.na(sch_match$home_score[1]) && !is.na(sch_match$away_score[1]))

        if (is_completed) {
          # Already completed: pregame forecast is immutable
          next
        }

        if (is_past_kickoff) {
          # Game has kicked off: freeze forecast permanently!
          if (is.na(existing_log$kickoff_time[idx])) {
            existing_log$kickoff_time[idx]     <- ko_dt
            existing_log$kickoff_fallback[idx] <- ko_fb
          }
          next
        }

        # Game is unplayed and has NOT yet kicked off: REFRESH pre-game forecast
        h_raw   <- if (home %in% names(raw_lookup)) raw_lookup[[home]] else 0.0
        a_raw   <- if (away %in% names(raw_lookup)) raw_lookup[[away]] else 0.0
        h_prior <- if (home %in% names(prior_lookup)) prior_lookup[[home]] else 0.0
        a_prior <- if (away %in% names(prior_lookup)) prior_lookup[[away]] else 0.0

        h_gp <- if ("home_games_played" %in% names(g) && !is.na(g$home_games_played)) g$home_games_played else 0L
        a_gp <- if ("away_games_played" %in% names(g) && !is.na(g$away_games_played)) g$away_games_played else 0L

        h_elo <- get_team_elo(home, g$season)
        a_elo <- get_team_elo(away, g$season)
        elo_avail <- !is.na(h_elo) && !is.na(a_elo)

        h_bk <- if (!is.null(qb_lookup) && home %in% names(qb_lookup)) isTRUE(qb_lookup[[home]]) else FALSE
        a_bk <- if (!is.null(qb_lookup) && away %in% names(qb_lookup)) isTRUE(qb_lookup[[away]]) else FALSE

        waterfall <- compute_waterfall_steps(
          home_raw           = h_raw,
          away_raw           = a_raw,
          home_prior         = h_prior,
          away_prior         = a_prior,
          home_gp            = h_gp,
          away_gp            = a_gp,
          home_elo           = h_elo,
          away_elo           = a_elo,
          elo_available      = elo_avail,
          neutral            = neu,
          home_qb_backup     = h_bk,
          away_qb_backup     = a_bk,
          b_intercept        = resolved_coefs$ridge_b_intercept,
          b_raw              = resolved_coefs$ridge_b_raw,
          b_prior            = resolved_coefs$ridge_b_prior,
          b_raw_gp           = resolved_coefs$ridge_b_raw_gp,
          b_prior_gp         = resolved_coefs$ridge_b_prior_gp,
          projected_margin   = g$projected_margin
        )

        pred_winner <- if (g$projected_margin >= 0) home else away

        existing_log$home_power_rating[idx]  <- as.numeric(g$home_power_rating)
        existing_log$away_power_rating[idx]  <- as.numeric(g$away_power_rating)
        existing_log$home_games_played[idx]  <- as.integer(h_gp)
        existing_log$away_games_played[idx]  <- as.integer(a_gp)
        existing_log$projected_margin[idx]   <- as.numeric(g$projected_margin)
        existing_log$home_win_prob[idx]      <- as.numeric(g$home_win_prob)
        existing_log$away_win_prob[idx]      <- 1.0 - as.numeric(g$home_win_prob)
        existing_log$predicted_winner[idx]   <- pred_winner
        existing_log$margin_sigma[idx]       <- as.numeric(sigma_val)
        existing_log$step_current_epa[idx]   <- as.numeric(waterfall$step_current_epa)
        existing_log$step_prior_epa[idx]     <- as.numeric(waterfall$step_prior_epa)
        existing_log$step_elo_diff[idx]      <- as.numeric(waterfall$step_elo_diff)
        existing_log$step_home_field[idx]    <- as.numeric(waterfall$step_home_field)
        existing_log$step_qb_adjustment[idx] <- as.numeric(waterfall$step_qb_adjustment)
        existing_log$step_rounding[idx]      <- as.numeric(waterfall$step_rounding)
        existing_log$ridge_b_intercept[idx]  <- as.numeric(resolved_coefs$ridge_b_intercept)
        existing_log$ridge_b_raw[idx]        <- as.numeric(resolved_coefs$ridge_b_raw)
        existing_log$ridge_b_prior[idx]      <- as.numeric(resolved_coefs$ridge_b_prior)
        existing_log$ridge_b_raw_gp[idx]     <- as.numeric(resolved_coefs$ridge_b_raw_gp)
        existing_log$ridge_b_prior_gp[idx]   <- as.numeric(resolved_coefs$ridge_b_prior_gp)
        existing_log$home_raw[idx]           <- as.numeric(h_raw)
        existing_log$away_raw[idx]           <- as.numeric(a_raw)
        existing_log$home_prior[idx]         <- as.numeric(h_prior)
        existing_log$away_prior[idx]         <- as.numeric(a_prior)
        existing_log$home_elo[idx]           <- as.numeric(h_elo)
        existing_log$away_elo[idx]           <- as.numeric(a_elo)
        existing_log$home_qb_backup[idx]     <- as.logical(h_bk)
        existing_log$away_qb_backup[idx]     <- as.logical(a_bk)
        existing_log$elo_available[idx]      <- as.logical(elo_avail)
        existing_log$gameday[idx]            <- gday
        existing_log$weekday[idx]            <- wday
        existing_log$gametime[idx]           <- gtime
        existing_log$location[idx]           <- loc
        existing_log$neutral[idx]            <- neu
        existing_log$kickoff_time[idx]       <- ko_dt
        existing_log$kickoff_fallback[idx]   <- ko_fb
        existing_log$refreshed_at[idx]       <- run_start_time
        # logged_at and log_source are preserved untouched!
        n_unplayed_refreshed <- n_unplayed_refreshed + 1L

      } else {
        # Game does NOT exist in log
        is_comp <- (!is.null(sch_match) && nrow(sch_match) > 0 && !is.na(sch_match$home_score[1]) && !is.na(sch_match$away_score[1])) ||
                   ("home_score" %in% names(g) && !is.na(g$home_score) && "away_score" %in% names(g) && !is.na(g$away_score))

        if (is_past_kickoff && !is_comp) {
          # Post-kickoff creation guard: never create a pre-game row after kickoff!
          log_warn(sprintf("Game %s has already kicked off (kickoff: %s, run start: %s). Refusing to create LOGGED_PREGAME row.",
                           gid, as.character(ko_dt), as.character(run_start_time)), script = .LOG_SCRIPT)
          n_postkickoff_skipped <- n_postkickoff_skipped + 1L
          next
        }

        if (is_comp) {
          # Completed game without prior forecast: recovered via walk-forward backfill below
          next
        }

        # Game is pre-kickoff: create genuine LOGGED_PREGAME row
        h_raw   <- if (home %in% names(raw_lookup)) raw_lookup[[home]] else 0.0
        a_raw   <- if (away %in% names(raw_lookup)) raw_lookup[[away]] else 0.0
        h_prior <- if (home %in% names(prior_lookup)) prior_lookup[[home]] else 0.0
        a_prior <- if (away %in% names(prior_lookup)) prior_lookup[[away]] else 0.0

        h_gp <- if ("home_games_played" %in% names(g) && !is.na(g$home_games_played)) g$home_games_played else 0L
        a_gp <- if ("away_games_played" %in% names(g) && !is.na(g$away_games_played)) g$away_games_played else 0L

        h_elo <- get_team_elo(home, g$season)
        a_elo <- get_team_elo(away, g$season)
        elo_avail <- !is.na(h_elo) && !is.na(a_elo)

        h_bk <- if (!is.null(qb_lookup) && home %in% names(qb_lookup)) isTRUE(qb_lookup[[home]]) else FALSE
        a_bk <- if (!is.null(qb_lookup) && away %in% names(qb_lookup)) isTRUE(qb_lookup[[away]]) else FALSE

        waterfall <- compute_waterfall_steps(
          home_raw           = h_raw,
          away_raw           = a_raw,
          home_prior         = h_prior,
          away_prior         = a_prior,
          home_gp            = h_gp,
          away_gp            = a_gp,
          home_elo           = h_elo,
          away_elo           = a_elo,
          elo_available      = elo_avail,
          neutral            = neu,
          home_qb_backup     = h_bk,
          away_qb_backup     = a_bk,
          b_intercept        = resolved_coefs$ridge_b_intercept,
          b_raw              = resolved_coefs$ridge_b_raw,
          b_prior            = resolved_coefs$ridge_b_prior,
          b_raw_gp           = resolved_coefs$ridge_b_raw_gp,
          b_prior_gp         = resolved_coefs$ridge_b_prior_gp,
          projected_margin   = g$projected_margin
        )
        eff_proj_margin <- as.numeric(g$projected_margin)
        eff_win_prob <- as.numeric(g$home_win_prob)
        pred_winner <- if (eff_proj_margin >= 0) home else away

        new_rows_list[[length(new_rows_list) + 1L]] <- data.frame(
          game_id            = gid,
          season             = as.integer(g$season),
          week               = as.integer(g$week),
          gameday            = gday,
          weekday            = wday,
          gametime           = gtime,
          home_team          = home,
          away_team          = away,
          location           = loc,
          neutral            = neu,
          log_source         = "LOGGED_PREGAME",
          log_timestamp      = run_start_time,
          logged_at          = run_start_time,
          refreshed_at       = run_start_time,
          kickoff_time       = ko_dt,
          kickoff_fallback   = ko_fb,
          home_power_rating  = as.numeric(g$home_power_rating),
          away_power_rating  = as.numeric(g$away_power_rating),
          home_games_played  = as.integer(h_gp),
          away_games_played  = as.integer(a_gp),
          projected_margin   = eff_proj_margin,
          home_win_prob      = eff_win_prob,
          away_win_prob      = 1.0 - eff_win_prob,
          predicted_winner   = pred_winner,
          margin_sigma       = as.numeric(sigma_val),
          step_current_epa   = as.numeric(waterfall$step_current_epa),
          step_prior_epa     = as.numeric(waterfall$step_prior_epa),
          step_elo_diff      = as.numeric(waterfall$step_elo_diff),
          step_home_field    = as.numeric(waterfall$step_home_field),
          step_qb_adjustment = as.numeric(waterfall$step_qb_adjustment),
          step_rounding      = as.numeric(waterfall$step_rounding),
          ridge_b_intercept  = as.numeric(resolved_coefs$ridge_b_intercept),
          ridge_b_raw        = as.numeric(resolved_coefs$ridge_b_raw),
          ridge_b_prior      = as.numeric(resolved_coefs$ridge_b_prior),
          ridge_b_raw_gp     = as.numeric(resolved_coefs$ridge_b_raw_gp),
          ridge_b_prior_gp   = as.numeric(resolved_coefs$ridge_b_prior_gp),
          home_raw           = as.numeric(h_raw),
          away_raw           = as.numeric(a_raw),
          home_prior         = as.numeric(h_prior),
          away_prior         = as.numeric(a_prior),
          home_elo           = as.numeric(h_elo),
          away_elo           = as.numeric(a_elo),
          home_qb_backup     = as.logical(h_bk),
          away_qb_backup     = as.logical(a_bk),
          elo_available      = as.logical(elo_avail),
          home_score         = NA_integer_,
          away_score         = NA_integer_,
          actual_margin      = NA_real_,
          actual_winner      = NA_character_,
          prediction_correct = NA,
          brier_score        = NA_real_,
          stringsAsFactors   = FALSE
        )
      }
    }
  }

  new_rows_df <- if (length(new_rows_list) > 0) bind_rows(new_rows_list) else NULL

  # 9. Combine preserved existing rows with newly appended rows
  combined_log <- if (is.null(existing_log) || nrow(existing_log) == 0) {
    if (!is.null(new_rows_df)) new_rows_df else data.frame()
  } else if (is.null(new_rows_df) || nrow(new_rows_df) == 0) {
    existing_log
  } else {
    bind_rows(existing_log, new_rows_df)
  }

  # 10. Update realization result fields for completed games in log
  # IMMUTABILITY GATE: None of the pregame forecast columns are ever touched!
  updated_log <- combined_log
  n_results_updated <- 0L

  if (!is.null(updated_log) && nrow(updated_log) > 0 && !is.null(sch)) {
    sch_lookup <- sch |> filter(!is.na(home_score), !is.na(away_score))
    if (nrow(sch_lookup) > 0) {
      completed_map <- setNames(seq_len(nrow(sch_lookup)), sch_lookup$game_id)

      for (r in seq_len(nrow(updated_log))) {
        gid <- updated_log$game_id[r]
        if (gid %in% names(completed_map)) {
          # Update realization fields if not already populated
          if (is.na(updated_log$home_score[r]) || is.na(updated_log$away_score[r])) {
            sch_idx <- completed_map[[gid]]
            h_sc <- as.integer(sch_lookup$home_score[sch_idx])
            a_sc <- as.integer(sch_lookup$away_score[sch_idx])
            act_m <- as.numeric(h_sc - a_sc)
            act_w <- if (act_m > 0) updated_log$home_team[r] else if (act_m < 0) updated_log$away_team[r] else "TIE"
            h_won <- if (act_m > 0) 1.0 else if (act_m < 0) 0.0 else 0.5
            pred_w <- updated_log$predicted_winner[r]
            is_corr <- if (act_w == "TIE") FALSE else (pred_w == act_w)
            brier <- (h_won - updated_log$home_win_prob[r])^2

            updated_log$home_score[r]         <- h_sc
            updated_log$away_score[r]         <- a_sc
            updated_log$actual_margin[r]      <- act_m
            updated_log$actual_winner[r]      <- act_w
            updated_log$prediction_correct[r] <- is_corr
            updated_log$brier_score[r]        <- brier
            n_results_updated <- n_results_updated + 1L
          }
        }
      }
    }
  }

  # 10.5 Generate backtest rows for completed games with no logged forecast
  target_season <- if (exists("CURRENT_SEASON", mode = "numeric")) CURRENT_SEASON else 2026L
  prior_n <- if (!is.null(updated_log)) nrow(updated_log) else 0L
  updated_log <- recover_missing_backtest_rows(
    updated_log  = updated_log,
    sch          = sch,
    epa_path     = epa_path,
    fatigue_path = fatigue_path,
    season       = target_season,
    ridge_coefs  = resolved_coefs,
    qb_starter_table = qb_starter_table
  )
  n_backtest_added <- (if (!is.null(updated_log)) nrow(updated_log) else 0L) - prior_n

  final_log <- updated_log

  # Persist log to cache
  if (nrow(final_log) > 0) {
    saveRDS(final_log, log_path)
    log_info(sprintf("Persisted %d rows to %s (%d new unplayed logged, %d unplayed refreshed, %d completed results updated, %d backtest created for finished games, %d post-kickoff creation skipped).",
                     nrow(final_log), log_path,
                     if (!is.null(new_rows_df)) nrow(new_rows_df) else 0L,
                     n_unplayed_refreshed,
                     n_results_updated,
                     n_backtest_added,
                     n_postkickoff_skipped),
             script = .LOG_SCRIPT)
  } else {
    log_info("Prediction accuracy log is empty — no rows to persist.", script = .LOG_SCRIPT)
  }

  invisible(final_log)
}
