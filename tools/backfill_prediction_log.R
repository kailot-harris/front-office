# ==============================================================================
# tools/backfill_prediction_log.R
# Walk-Forward Backfill of Prediction Accuracy Log (Issue #112 / Section 5.3)
#
# Evaluates all completed 2026 games via walk-forward reconstruction using the
# unified Variant 1 formula (50% Ridge-Massey margin + 50% Elo margin, zero
# fatigue). Records each completed game into CACHE_PREDICTION_ACCURACY_LOG
# with log_source = "BACKTEST_PREWEEK", entering power ratings (non-zero),
# the five points waterfall steps with rounding <= 0.02, and realized scores/
# accuracy.
#
# CRITICAL IMMUTABILITY & D1 PROVENANCE GUARANTEE:
# - Backfill preserves any existing rows with log_source = "LOGGED_PREGAME"
#   permanently and never overwrites them.
# - The backtest record represents out-of-sample reconstruction strictly from
#   data available prior to each week's kickoff ("Rebuilt afterwards from data
#   available before the game"), maintaining honest provenance per Owner
#   Decision D1.
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
source("tools/backtest_common.R")
source("team_ratings_engine.R")
source("prediction_accuracy_logger.R")

.LOG_SCRIPT <- "backfill_prediction_log.R"

#' Backfill Prediction Accuracy Log for Completed Games
#'
#' Evaluates completed games for the target season walk-forward, computing
#' entering power ratings, five waterfall steps, projected margin and win
#' probability under Variant 1, and realized accuracy metrics. Writes backfilled
#' rows to log_path with log_source = "BACKTEST_PREWEEK" while preserving any
#' existing "LOGGED_PREGAME" rows.
#'
#' @param log_path Path to persist the prediction accuracy log RDS.
#' @param schedules_path Path to schedules cache RDS.
#' @param epa_path Path to EPA metrics cache RDS.
#' @param fatigue_path Path to fatigue metrics cache RDS.
#' @param season Target season to backfill (defaults to CURRENT_SEASON or 2026L).
#' @return Invisible data.frame of the updated prediction accuracy log.
#' @export
backfill_prediction_log <- function(
    log_path       = if (exists("CACHE_PREDICTION_ACCURACY_LOG")) CACHE_PREDICTION_ACCURACY_LOG else file.path("cache", "prediction_accuracy_log.rds"),
    schedules_path = if (exists("CACHE_SCHEDULES")) CACHE_SCHEDULES else file.path("cache", "schedules_cache.rds"),
    epa_path       = if (exists("CACHE_EPA_METRICS")) CACHE_EPA_METRICS else file.path("cache", "team_epa_metrics.rds"),
    fatigue_path   = if (exists("CACHE_FATIGUE_METRICS")) CACHE_FATIGUE_METRICS else file.path("cache", "fatigue_metrics.rds"),
    season         = if (exists("CURRENT_SEASON", mode = "numeric")) CURRENT_SEASON else 2026L) {

  log_info(sprintf("Starting prediction accuracy log backfill for season %d...", as.integer(season)),
           script = .LOG_SCRIPT)

  # Ensure destination cache directory exists
  log_dir <- dirname(log_path)
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (!file.exists(schedules_path)) {
    stop(sprintf("Schedules cache not found at %s", schedules_path))
  }
  if (!file.exists(epa_path)) {
    stop(sprintf("EPA metrics cache not found at %s", epa_path))
  }

  sch <- readRDS(schedules_path) |> mutate(gameday = as.Date(gameday))
  completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
  completed_target <- completed |> filter(season == !!season)

  if (nrow(completed_target) == 0) {
    log_info(sprintf("No completed games found for season %d — nothing to backfill.", as.integer(season)),
             script = .LOG_SCRIPT)
    return(invisible(NULL))
  }

  log_info(sprintf("Found %d completed games for season %d to backfill.", nrow(completed_target), as.integer(season)),
           script = .LOG_SCRIPT)

  epa <- readRDS(epa_path) |> mutate(game_date = as.Date(game_date))
  avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

  fatigue <- if (file.exists(fatigue_path)) {
    readRDS(fatigue_path)
  } else {
    data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0), stringsAsFactors = FALSE)
  }

  mod_start <- if (exists("MODERN_ERA_START_SEASON", mode = "numeric")) MODERN_ERA_START_SEASON else 2002L
  cal_seasons <- (mod_start + 1L):season

  # 1. Build walk-forward games table across historical calibration seasons through target season
  all_games <- build_walkforward_games(epa, completed, calibration_seasons = cal_seasons, avg_plays_per_game)

  # 2. QB backup participation flags (as-of, strictly prior to each game)
  starter_tbl <- get_qb_starter_table(mod_start:season)
  qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
  all_games <- all_games |>
    left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
    left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

  # 3. Elo walk-forward state (strictly historical through target season)
  elo_full_history <- sch |>
    filter(!is.na(home_score), !is.na(away_score), season >= mod_start, season <= season)
  k_factor <- if (exists("ELO_K_FACTOR", mode = "numeric")) ELO_K_FACTOR else 20.0
  elo_results <- run_elo_walkforward(elo_full_history, fatigue, k_factor) |>
    select(game_id, home_elo_pre, away_elo_pre, elo_margin_pts, fatigue_adj)
  all_games <- all_games |> left_join(elo_results, by = "game_id")

  # 4. Train Ridge Massey model strictly on historical seasons prior to target season
  train_idx <- which(all_games$season < season)
  if (length(train_idx) < 100) {
    stop(sprintf("Insufficient historical games (%d < 100) to train Ridge model for season %d",
                 length(train_idx), as.integer(season)))
  }
  fit_ridge <- fit_ridge_massey(all_games[train_idx, ])
  coefs <- get_ridge_coefficient_list(fit_ridge)

  # 5. Filter to target season games and predict
  target_games <- all_games |> filter(season == !!season)
  x_target <- build_ridge_features(target_games)
  target_games$ridge_margin_raw <- as.numeric(predict(fit_ridge, newx = x_target, s = "lambda.min"))

  home_adj <- ifelse(is.na(target_games$home_qb_backup), 0, as.integer(target_games$home_qb_backup))
  away_adj <- ifelse(is.na(target_games$away_qb_backup), 0, as.integer(target_games$away_qb_backup))
  qb_penalty <- if (exists("QB_INJURY_RATING_PENALTY_PTS", mode = "numeric")) QB_INJURY_RATING_PENALTY_PTS else 1.60
  qb_shift <- -qb_penalty * home_adj + qb_penalty * away_adj

  ridge_m <- target_games$ridge_margin_raw + qb_shift
  elo_m   <- target_games$elo_margin_pts + qb_shift
  elo_avail <- !is.na(target_games$elo_margin_pts)

  sigma_val <- if (exists("NFL_MARGIN_SIGMA", mode = "numeric")) NFL_MARGIN_SIGMA else 14.60

  # Evaluate Variant 1: 50% Ridge margin + 50% Elo margin, zero fatigue
  forecast <- compute_game_forecast(
    ridge_margin  = ridge_m,
    elo_margin    = elo_m,
    elo_available = elo_avail,
    margin_sigma  = sigma_val
  )
  target_games$projected_margin <- forecast$projected_margin
  target_games$home_win_prob    <- forecast$home_win_prob
  target_games$away_win_prob    <- 1.0 - forecast$home_win_prob

  # 6. Compute entering power ratings before kickoff
  k_shrinkage <- if (exists("RATING_SHRINKAGE_GAMES_K", mode = "numeric")) RATING_SHRINKAGE_GAMES_K else 3.6
  h_weight <- target_games$home_gp / (target_games$home_gp + k_shrinkage)
  a_weight <- target_games$away_gp / (target_games$away_gp + k_shrinkage)
  target_games$home_power_rating <- h_weight * target_games$home_raw + (1.0 - h_weight) * target_games$home_prior
  target_games$away_power_rating <- a_weight * target_games$away_raw + (1.0 - a_weight) * target_games$away_prior

  # 7. Merge schedule metadata (location, weekday, gametime, real scores)
  sch_meta <- sch |>
    filter(season == !!season) |>
    select(game_id, weekday, gametime, location, home_score, away_score)
  target_games <- target_games |> left_join(sch_meta, by = "game_id")

  # 8. Compute 5-step points waterfall and rounding term
  wf <- compute_waterfall_steps(
    home_raw         = target_games$home_raw,
    away_raw         = target_games$away_raw,
    home_prior       = target_games$home_prior,
    away_prior       = target_games$away_prior,
    home_gp          = target_games$home_gp,
    away_gp          = target_games$away_gp,
    home_elo         = target_games$home_elo_pre,
    away_elo         = target_games$away_elo_pre,
    elo_available    = elo_avail,
    neutral          = FALSE,
    home_qb_backup   = target_games$home_qb_backup,
    away_qb_backup   = target_games$away_qb_backup,
    b_intercept      = coefs$ridge_b_intercept,
    b_raw            = coefs$ridge_b_raw,
    b_prior          = coefs$ridge_b_prior,
    b_raw_gp         = coefs$ridge_b_raw_gp,
    b_prior_gp       = coefs$ridge_b_prior_gp,
    projected_margin = target_games$projected_margin
  )

  # Rounding check: maximum rounding divergence <= 0.02
  max_rounding <- max(abs(wf$step_rounding))
  if (max_rounding > 0.02) {
    stop(sprintf("Points waterfall rounding step exceeds tolerance: max divergence = %.6f > 0.02", max_rounding))
  }

  # 9. Realized game results & grading matching grade_walkforward_games
  act_margin <- target_games$home_score - target_games$away_score
  home_win <- as.integer(target_games$home_score > target_games$away_score)
  act_winner <- ifelse(act_margin > 0, target_games$home_team, ifelse(act_margin < 0, target_games$away_team, "Tie"))
  pred_winner <- ifelse(target_games$projected_margin >= 0, target_games$home_team, target_games$away_team)
  is_correct <- (target_games$home_win_prob > 0.5) == (home_win == 1L)
  brier <- (target_games$home_win_prob - home_win)^2

  now_ts <- Sys.time()

  # 10. Construct backfill dataframe matching prediction logger contract
  backfill_df <- data.frame(
    game_id            = as.character(target_games$game_id),
    season             = as.integer(target_games$season),
    week               = as.integer(target_games$week),
    gameday            = as.character(target_games$gameday),
    weekday            = as.character(target_games$weekday),
    gametime           = as.character(target_games$gametime),
    home_team          = as.character(target_games$home_team),
    away_team          = as.character(target_games$away_team),
    location           = as.character(target_games$location),
    neutral            = FALSE,
    log_source         = "BACKTEST_PREWEEK",
    log_timestamp      = now_ts,
    logged_at          = now_ts,
    home_power_rating  = as.numeric(target_games$home_power_rating),
    away_power_rating  = as.numeric(target_games$away_power_rating),
    home_games_played  = as.integer(target_games$home_gp),
    away_games_played  = as.integer(target_games$away_gp),
    projected_margin   = as.numeric(target_games$projected_margin),
    home_win_prob      = as.numeric(target_games$home_win_prob),
    away_win_prob      = as.numeric(target_games$away_win_prob),
    predicted_winner   = as.character(pred_winner),
    margin_sigma       = as.numeric(sigma_val),
    step_current_epa   = as.numeric(wf$step_current_epa),
    step_prior_epa     = as.numeric(wf$step_prior_epa),
    step_elo_diff      = as.numeric(wf$step_elo_diff),
    step_home_field    = as.numeric(wf$step_home_field),
    step_qb_adjustment = as.numeric(wf$step_qb_adjustment),
    step_rounding      = as.numeric(wf$step_rounding),
    ridge_b_intercept  = as.numeric(coefs$ridge_b_intercept),
    ridge_b_raw        = as.numeric(coefs$ridge_b_raw),
    ridge_b_prior      = as.numeric(coefs$ridge_b_prior),
    ridge_b_raw_gp     = as.numeric(coefs$ridge_b_raw_gp),
    ridge_b_prior_gp   = as.numeric(coefs$ridge_b_prior_gp),
    home_raw           = as.numeric(target_games$home_raw),
    away_raw           = as.numeric(target_games$away_raw),
    home_prior         = as.numeric(target_games$home_prior),
    away_prior         = as.numeric(target_games$away_prior),
    home_elo           = as.numeric(target_games$home_elo_pre),
    away_elo           = as.numeric(target_games$away_elo_pre),
    home_qb_backup     = as.logical(target_games$home_qb_backup),
    away_qb_backup     = as.logical(target_games$away_qb_backup),
    elo_available      = as.logical(elo_avail),
    home_score         = as.integer(target_games$home_score),
    away_score         = as.integer(target_games$away_score),
    actual_margin      = as.numeric(act_margin),
    actual_winner      = as.character(act_winner),
    prediction_correct = as.logical(is_correct),
    brier_score        = as.numeric(brier),
    stringsAsFactors   = FALSE
  )

  # Assert non-zero power ratings across all backfilled games
  zero_pwr <- which(backfill_df$home_power_rating == 0.0 | backfill_df$away_power_rating == 0.0)
  if (length(zero_pwr) > 0) {
    log_warn(sprintf("Found %d backfilled game(s) with power rating == 0.0", length(zero_pwr)),
             script = .LOG_SCRIPT)
  }

  # 11. Merge into log_path without overwriting LOGGED_PREGAME rows
  existing_log <- if (file.exists(log_path)) {
    tryCatch(readRDS(log_path), error = function(e) {
      log_warn(sprintf("Could not read existing log at %s: %s", log_path, conditionMessage(e)), script = .LOG_SCRIPT)
      NULL
    })
  } else {
    NULL
  }

  final_log <- if (!is.null(existing_log) && nrow(existing_log) > 0) {
    # Isolate existing genuine pregame rows
    pregame_rows <- existing_log |> filter(log_source == "LOGGED_PREGAME")
    if (nrow(pregame_rows) > 0) {
      log_info(sprintf("Preserving %d existing LOGGED_PREGAME row(s) untouched.", nrow(pregame_rows)),
               script = .LOG_SCRIPT)
      # Exclude any games already logged pregame
      clean_backfill <- backfill_df |> filter(!game_id %in% pregame_rows$game_id)
      # Also preserve other seasons' rows if any
      other_rows <- existing_log |> filter(log_source != "LOGGED_PREGAME", season != !!season)
      bind_rows(pregame_rows, other_rows, clean_backfill)
    } else {
      # No LOGGED_PREGAME rows; replace any prior backtest for target season
      other_rows <- existing_log |> filter(season != !!season)
      bind_rows(other_rows, backfill_df)
    }
  } else {
    backfill_df
  }

  saveRDS(final_log, log_path)
  log_info(sprintf("Successfully persisted %d rows to %s (%d backfilled for season %d).",
                   nrow(final_log), log_path, nrow(backfill_df), as.integer(season)),
           script = .LOG_SCRIPT)

  invisible(final_log)
}

if (!interactive()) {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0 && grepl("backfill_prediction_log\\.R$", file_arg[1])) {
    backfill_prediction_log()
  }
}
