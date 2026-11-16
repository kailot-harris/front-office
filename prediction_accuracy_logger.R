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

#' Run Prediction Accuracy Logger
#'
#' Primary pipeline entry point. Reads projected matchups and schedules, appends
#' newly projected unplayed games with log_source = "LOGGED_PREGAME", freezes
#' pre-game forecast columns, and updates realized scores for completed games.
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
    elo_live                = NULL,
    force_refit             = FALSE) {

  log_info("Starting prediction accuracy logger pipeline stage.", script = .LOG_SCRIPT)

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

  existing_ids <- if (!is.null(existing_log) && nrow(existing_log) > 0) {
    existing_log$game_id
  } else {
    character(0)
  }

  # 2. Load schedules
  sch <- if (file.exists(schedules_path)) {
    tryCatch(readRDS(schedules_path), error = function(e) NULL)
  } else {
    NULL
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

  # 8. Identify new unplayed games from projected matchups that do not yet exist in log
  new_rows_list <- list()
  if (!is.null(pm) && nrow(pm) > 0) {
    unlogged_pm <- pm |> filter(!game_id %in% existing_ids)

    if (nrow(unlogged_pm) > 0) {
      log_info(sprintf("Logging %d new unplayed pregame forecasts with log_source = 'LOGGED_PREGAME'.",
                       nrow(unlogged_pm)), script = .LOG_SCRIPT)

      now_ts <- Sys.time()

      for (i in seq_len(nrow(unlogged_pm))) {
        g <- unlogged_pm[i, ]
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

        # Compute 5 points waterfall steps + rounding term
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

        new_rows_list[[i]] <- data.frame(
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
          log_timestamp      = now_ts,
          home_power_rating  = as.numeric(g$home_power_rating),
          away_power_rating  = as.numeric(g$away_power_rating),
          home_games_played  = as.integer(h_gp),
          away_games_played  = as.integer(a_gp),
          projected_margin   = as.numeric(g$projected_margin),
          home_win_prob      = as.numeric(g$home_win_prob),
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

  # 9. Update realization result fields for completed games in existing log
  # IMMUTABILITY GATE: None of the pregame forecast columns are ever touched!
  updated_existing <- existing_log
  n_results_updated <- 0L

  if (!is.null(updated_existing) && nrow(updated_existing) > 0 && !is.null(sch)) {
    sch_lookup <- sch |> filter(!is.na(home_score), !is.na(away_score))
    if (nrow(sch_lookup) > 0) {
      completed_map <- setNames(seq_len(nrow(sch_lookup)), sch_lookup$game_id)

      for (r in seq_len(nrow(updated_existing))) {
        gid <- updated_existing$game_id[r]
        if (gid %in% names(completed_map)) {
          # Update realization fields if not already populated
          if (is.na(updated_existing$home_score[r]) || is.na(updated_existing$away_score[r])) {
            sch_idx <- completed_map[[gid]]
            h_sc <- as.integer(sch_lookup$home_score[sch_idx])
            a_sc <- as.integer(sch_lookup$away_score[sch_idx])
            act_m <- as.numeric(h_sc - a_sc)
            act_w <- if (act_m > 0) updated_existing$home_team[r] else if (act_m < 0) updated_existing$away_team[r] else "TIE"
            h_won <- if (act_m > 0) 1.0 else if (act_m < 0) 0.0 else 0.5
            pred_w <- updated_existing$predicted_winner[r]
            is_corr <- if (act_w == "TIE") FALSE else (pred_w == act_w)
            brier <- (h_won - updated_existing$home_win_prob[r])^2

            updated_existing$home_score[r]         <- h_sc
            updated_existing$away_score[r]         <- a_sc
            updated_existing$actual_margin[r]      <- act_m
            updated_existing$actual_winner[r]      <- act_w
            updated_existing$prediction_correct[r] <- is_corr
            updated_existing$brier_score[r]        <- brier
            n_results_updated <- n_results_updated + 1L
          }
        }
      }
    }
  }

  # 10. Combine preserved existing rows with newly appended rows
  final_log <- if (is.null(updated_existing) || nrow(updated_existing) == 0) {
    if (!is.null(new_rows_df)) new_rows_df else data.frame()
  } else if (is.null(new_rows_df) || nrow(new_rows_df) == 0) {
    updated_existing
  } else {
    bind_rows(updated_existing, new_rows_df)
  }

  # Persist log to cache
  if (nrow(final_log) > 0) {
    saveRDS(final_log, log_path)
    log_info(sprintf("Persisted %d rows to %s (%d new unplayed logged, %d completed results updated).",
                     nrow(final_log), log_path,
                     if (!is.null(new_rows_df)) nrow(new_rows_df) else 0L,
                     n_results_updated),
             script = .LOG_SCRIPT)
  } else {
    log_info("Prediction accuracy log is empty — no rows to persist.", script = .LOG_SCRIPT)
  }

  invisible(final_log)
}
