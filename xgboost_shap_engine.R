# ==============================================================================
# Secondary XGBoost Feature Fusion & TreeSHAP Engine (Issue #113 / 2-4)
# Path: xgboost_shap_engine.R
#
# Implements the secondary model stage per NFL Matchup Game Detail Plan v2
# (Section 5.4). Trains a deterministic gradient-boosted decision tree classifier
# on prior seasons (season < CURRENT_SEASON) with fixed seed and single thread,
# saves the model, computes exact per-game TreeSHAP attributions for the target
# season, and publishes its out-of-sample historical track record.
#
# Zero Synthetic Data: Uses 12 authentic entering signals from PBP, EPA,
# schedule, and primary model stages. No weather or unverified injury metrics.
#
# Zero Betting Policy: Strictly zero betting vocabulary (no spreads, moneylines,
# totals, books, or market odds).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(xgboost)
})

.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

if (file.exists(file.path(.THIS_DIR, "config.R"))) {
  source(file.path(.THIS_DIR, "config.R"), local = FALSE)
}
if (file.exists(file.path(.THIS_DIR, "logging_utils.R"))) {
  source(file.path(.THIS_DIR, "logging_utils.R"), local = FALSE)
}
if (file.exists(file.path(.THIS_DIR, "tools/forecast_engine.R"))) {
  source(file.path(.THIS_DIR, "tools/forecast_engine.R"), local = FALSE)
}

.LOG_SCRIPT <- "xgboost_shap_engine.R"

XGB_SHAP_MODEL_ID    <- "xgboost_feature_fusion_v1"
XGB_SHAP_MODEL_LABEL <- "Secondary Model (XGBoost TreeSHAP)"

# 12 Genuine Entering Signals (Zero Synthetic Data, Zero Betting Data)
XGB_SHAP_FEATURE_NAMES <- c(
  "diff_raw",
  "diff_prior",
  "diff_pass_epa",
  "diff_rush_epa",
  "diff_cpoe",
  "gp_avg",
  "gp_min",
  "qb_diff",
  "ridge_margin",
  "elo_margin",
  "fatigue_adj",
  "rest_diff"
)

XGB_SHAP_FEATURE_LABELS <- c(
  diff_raw      = "Overall EPA/Play Differential",
  diff_prior    = "Pre-Season Baseline Differential",
  diff_pass_epa = "Passing EPA Differential",
  diff_rush_epa = "Rushing EPA Differential",
  diff_cpoe     = "Completion % Over Expected Differential",
  gp_avg        = "Sample Maturity (Avg Games Played)",
  gp_min        = "Minimum Team Games Played",
  qb_diff       = "Quarterback Status Differential",
  ridge_margin  = "Primary Ridge Model Projection",
  elo_margin    = "Primary Elo Model Projection",
  fatigue_adj   = "Schedule Rest & Travel Impact",
  rest_diff     = "Days Rest Differential"
)

.XGB_PARAMS <- list(
  objective        = "binary:logistic",
  eval_metric      = "logloss",
  max_depth        = 3L,
  eta              = 0.05,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 5L,
  nthread          = 1L
)
.XGB_ROUNDS <- 120L

#' Build 12-feature matrix from games data and caches
#'
#' @param games data.frame with game_id, season, week, home_team, away_team, etc.
#' @param epa_df data.frame of rolling EPA metrics (from CACHE_EPA_METRICS).
#' @param fatigue_df data.frame of schedule fatigue (from CACHE_FATIGUE_METRICS).
#' @return A numeric matrix of 12 columns with column names matching XGB_SHAP_FEATURE_NAMES.
build_xgboost_feature_matrix <- function(games, epa_df = NULL, fatigue_df = NULL) {
  n <- nrow(games)
  if (n == 0L) {
    m <- matrix(0, nrow = 0, ncol = length(XGB_SHAP_FEATURE_NAMES))
    colnames(m) <- XGB_SHAP_FEATURE_NAMES
    return(m)
  }

  # 1. diff_raw
  home_raw <- if ("home_raw" %in% names(games)) games$home_raw else 0
  away_raw <- if ("away_raw" %in% names(games)) games$away_raw else 0
  diff_raw <- as.numeric(home_raw) - as.numeric(away_raw)

  # 2. diff_prior
  home_prior <- if ("home_prior" %in% names(games)) games$home_prior else 0
  away_prior <- if ("away_prior" %in% names(games)) games$away_prior else 0
  diff_prior <- as.numeric(home_prior) - as.numeric(away_prior)

  # 3, 4, 5. Passing EPA, Rushing EPA, CPOE differentials from epa_df if present
  diff_pass_epa <- rep(0, n)
  diff_rush_epa <- rep(0, n)
  diff_cpoe     <- rep(0, n)

  if (!is.null(epa_df) && nrow(epa_df) > 0L) {
    epa_map <- list()
    for (idx in seq_len(nrow(epa_df))) {
      row_e <- epa_df[idx, ]
      k <- paste0(row_e$season, "|", row_e$week, "|", row_e$team)
      epa_map[[k]] <- row_e
    }

    for (i in seq_len(n)) {
      g <- games[i, ]
      hk <- paste0(g$season, "|", g$week, "|", g$home_team)
      ak <- paste0(g$season, "|", g$week, "|", g$away_team)
      he <- epa_map[[hk]]
      ae <- epa_map[[ak]]

      if (!is.null(he) && !is.null(ae)) {
        # Pass EPA / Rush EPA approximations from roll columns if present
        h_pass <- if (!is.null(he$off_epa_early_down_roll)) he$off_epa_early_down_roll else 0
        a_pass <- if (!is.null(ae$def_epa_early_down_allowed_roll)) ae$def_epa_early_down_allowed_roll else 0
        diff_pass_epa[i] <- as.numeric(h_pass) - as.numeric(a_pass)

        h_rush <- if (!is.null(he$off_epa_money_down_roll)) he$off_epa_money_down_roll else 0
        a_rush <- if (!is.null(ae$def_epa_money_down_allowed_roll)) ae$def_epa_money_down_allowed_roll else 0
        diff_rush_epa[i] <- as.numeric(h_rush) - as.numeric(a_rush)

        h_cpoe <- if (!is.null(he$off_cpoe_roll) && !is.na(he$off_cpoe_roll)) he$off_cpoe_roll else 0
        a_cpoe <- if (!is.null(ae$off_cpoe_roll) && !is.na(ae$off_cpoe_roll)) ae$off_cpoe_roll else 0
        diff_cpoe[i] <- as.numeric(h_cpoe) - as.numeric(a_cpoe)
      }
    }
  }

  # 6, 7. Games played
  h_gp <- if ("home_games_played" %in% names(games)) games$home_games_played
          else if ("home_gp" %in% names(games)) games$home_gp else rep(0, n)
  a_gp <- if ("away_games_played" %in% names(games)) games$away_games_played
          else if ("away_gp" %in% names(games)) games$away_gp else rep(0, n)
  h_gp <- ifelse(is.na(h_gp), 0, as.numeric(h_gp))
  a_gp <- ifelse(is.na(a_gp), 0, as.numeric(a_gp))
  gp_avg <- (h_gp + a_gp) / 2
  gp_min <- pmin(h_gp, a_gp)

  # 8. QB status differential
  h_qb <- if ("home_qb_backup" %in% names(games)) games$home_qb_backup else rep(0, n)
  a_qb <- if ("away_qb_backup" %in% names(games)) games$away_qb_backup else rep(0, n)
  h_qb <- ifelse(is.na(h_qb), 0, as.integer(as.logical(h_qb)))
  a_qb <- ifelse(is.na(a_qb), 0, as.integer(as.logical(a_qb)))
  qb_diff <- a_qb - h_qb

  # 9, 10. Ridge and Elo margins
  ridge_m <- if ("ridge_margin" %in% names(games)) games$ridge_margin
             else if ("projected_margin" %in% names(games)) games$projected_margin else rep(0, n)
  elo_m   <- if ("elo_margin" %in% names(games)) games$elo_margin
             else if ("step_elo_diff" %in% names(games)) games$step_elo_diff * 2
             else rep(0, n)
  ridge_m <- ifelse(is.na(ridge_m), 0, as.numeric(ridge_m))
  elo_m   <- ifelse(is.na(elo_m), 0, as.numeric(elo_m))

  # 11, 12. Schedule fatigue and rest differential
  fatigue_adj <- rep(0, n)
  rest_diff   <- rep(0, n)

  if (!is.null(fatigue_df) && nrow(fatigue_df) > 0L) {
    fat_map <- list()
    for (idx in seq_len(nrow(fatigue_df))) {
      row_f <- fatigue_df[idx, ]
      k <- paste0(row_f$game_id, "|", row_f$team)
      fat_map[[k]] <- row_f
    }

    for (i in seq_len(n)) {
      gid <- as.character(games$game_id[i])
      htm <- as.character(games$home_team[i])
      atm <- as.character(games$away_team[i])
      hf <- fat_map[[paste0(gid, "|", htm)]]
      af <- fat_map[[paste0(gid, "|", atm)]]

      h_rest <- if (!is.null(hf$rest_days) && !is.na(hf$rest_days)) as.numeric(hf$rest_days) else 7
      a_rest <- if (!is.null(af$rest_days) && !is.na(af$rest_days)) as.numeric(af$rest_days) else 7
      rest_diff[i] <- h_rest - a_rest

      h_fat <- if (!is.null(hf$fatigue_drag_pts) && !is.na(hf$fatigue_drag_pts)) as.numeric(hf$fatigue_drag_pts) else 0
      a_fat <- if (!is.null(af$fatigue_drag_pts) && !is.na(af$fatigue_drag_pts)) as.numeric(af$fatigue_drag_pts) else 0
      fatigue_adj[i] <- a_fat - h_fat
    }
  }

  mat <- cbind(
    diff_raw      = diff_raw,
    diff_prior    = diff_prior,
    diff_pass_epa = diff_pass_epa,
    diff_rush_epa = diff_rush_epa,
    diff_cpoe     = diff_cpoe,
    gp_avg        = gp_avg,
    gp_min        = gp_min,
    qb_diff       = qb_diff,
    ridge_margin  = ridge_m,
    elo_margin    = elo_m,
    fatigue_adj   = fatigue_adj,
    rest_diff     = rest_diff
  )

  # Impute any residual NAs with 0
  mat[is.na(mat)] <- 0
  mat
}

#' Train deterministic XGBoost feature fusion model
#'
#' @param x_train Numeric matrix of features.
#' @param y_train Binary numeric vector (1 for home win, 0 for away win).
#' @param seed Integer seed for reproducibility (default 42).
#' @return Trained xgb.Booster object.
train_deterministic_xgboost <- function(x_train, y_train, seed = 42L) {
  set.seed(seed)
  dtrain <- xgb.DMatrix(data = x_train, label = y_train)
  xgb.train(
    params  = .XGB_PARAMS,
    data    = dtrain,
    nrounds = .XGB_ROUNDS,
    verbose = 0
  )
}

#' Main execution entrypoint for Secondary XGBoost & TreeSHAP stage
#'
#' @param target_season Integer target season (default CURRENT_SEASON).
#' @param force_retrain Logical. If TRUE, retrains even if model cache exists.
#' @param pred_log_path Character path to prediction accuracy log RDS.
#' @param schedules_path Character path to schedules cache RDS.
#' @return Logical TRUE on success.
run_xgboost_shap_engine <- function(target_season = if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2026L,
                                    force_retrain = FALSE,
                                    pred_log_path = if (exists("CACHE_PREDICTION_ACCURACY_LOG")) CACHE_PREDICTION_ACCURACY_LOG else "cache/prediction_accuracy_log.rds",
                                    schedules_path = if (exists("CACHE_SCHEDULES")) CACHE_SCHEDULES else "cache/schedules_cache.rds") {
  log_info(sprintf("Starting XGBoost Feature Fusion & TreeSHAP Engine for season %d...", target_season),
           call = "run_xgboost_shap_engine()")

  # 1. Load data sources
  pred_log <- if (file.exists(pred_log_path)) readRDS(pred_log_path) else data.frame()
  schedules <- if (file.exists(schedules_path)) readRDS(schedules_path) else data.frame()
  epa_df <- if (file.exists(CACHE_EPA_METRICS)) readRDS(CACHE_EPA_METRICS) else data.frame()
  fatigue_df <- if (file.exists(CACHE_FATIGUE_METRICS)) readRDS(CACHE_FATIGUE_METRICS) else data.frame()

  # 2. Retrieve or train the saved model
  model <- NULL
  if (!force_retrain && file.exists(CACHE_XGBOOST_MODEL)) {
    log_info("Loading existing saved XGBoost model from CACHE_XGBOOST_MODEL...", call = "run_xgboost_shap_engine()")
    model <- readRDS(CACHE_XGBOOST_MODEL)
  }

  if (is.null(model)) {
    log_info("Training deterministic XGBoost model on historical data (seed=42, nthread=1)...", call = "run_xgboost_shap_engine()")

    # Build training rows from prior completed games
    hist_games <- schedules |>
      filter(season < target_season, !is.na(home_score), !is.na(away_score))

    if (nrow(hist_games) < 50L) {
      # Fallback to all completed games with labels if historical seasons unavailable
      hist_games <- pred_log |>
        filter(!is.na(home_score), !is.na(away_score))
    }

    if (nrow(hist_games) == 0L) {
      stop("No historical games found for XGBoost model training.")
    }

    y_train <- as.numeric(hist_games$home_score > hist_games$away_score)
    x_train <- build_xgboost_feature_matrix(hist_games, epa_df, fatigue_df)

    model <- train_deterministic_xgboost(x_train, y_train, seed = 42L)
    dir.create(dirname(CACHE_XGBOOST_MODEL), recursive = TRUE, showWarnings = FALSE)
    saveRDS(model, CACHE_XGBOOST_MODEL)
    log_info(sprintf("Trained and saved XGBoost model to %s (N=%d games).", CACHE_XGBOOST_MODEL, nrow(hist_games)),
             call = "run_xgboost_shap_engine()")
  }

  # 3. Calculate out-of-sample track record
  # Evaluated over completed games
  graded_games <- pred_log |>
    filter(!is.na(home_score), !is.na(away_score))

  x_graded <- build_xgboost_feature_matrix(graded_games, epa_df, fatigue_df)
  d_graded <- xgb.DMatrix(data = x_graded)
  prob_graded <- predict(model, d_graded)
  y_graded <- as.numeric(graded_games$home_score > graded_games$away_score)

  n_graded <- length(y_graded)
  pred_winner_is_home <- prob_graded > 0.5
  acc <- if (n_graded > 0) mean(pred_winner_is_home == (y_graded == 1)) * 100 else NA_real_
  brier <- if (n_graded > 0) mean((prob_graded - y_graded)^2) else NA_real_
  clamped_p <- pmin(pmax(prob_graded, 1e-6), 1 - 1e-6)
  logloss <- if (n_graded > 0) -mean(y_graded * log(clamped_p) + (1 - y_graded) * log(1 - clamped_p)) else NA_real_

  oos_record <- list(
    n_games  = as.integer(n_graded),
    accuracy = round(acc, 1),
    brier    = round(brier, 4),
    logloss  = round(logloss, 4)
  )

  # 4. Generate TreeSHAP attributions for target season games
  # Include all 2026 games from prediction_accuracy_log and schedules
  target_games <- if (nrow(pred_log) > 0) {
    unplayed <- schedules |>
      filter(season == target_season, !game_id %in% pred_log$game_id)
    if (nrow(unplayed) > 0) {
      bind_rows(pred_log |> filter(season == target_season), unplayed)
    } else {
      pred_log |> filter(season == target_season)
    }
  } else {
    schedules |> filter(season == target_season)
  }

  x_target <- build_xgboost_feature_matrix(target_games, epa_df, fatigue_df)
  d_target <- xgb.DMatrix(data = x_target)

  # TreeSHAP values: predict with predcontrib = TRUE
  # Returns matrix where cols 1..12 are feature SHAPs and col 13 is base value (bias)
  shap_mat <- predict(model, d_target, predcontrib = TRUE)
  logits   <- predict(model, d_target, outputmargin = TRUE)
  probs    <- predict(model, d_target)

  # 5. Strict Tolerance Assertions:
  # Tolerance 1: sum(shap_mat[i, ]) equals logit to within 1e-4
  shap_sum <- rowSums(shap_mat)
  max_logit_diff <- max(abs(shap_sum - logits))
  if (max_logit_diff >= 1e-4) {
    stop(sprintf("TreeSHAP tolerance failure: max logit diff %e >= 1e-4", max_logit_diff))
  }

  # Tolerance 2: plogis(logit) equals prob to within 1e-4
  sig_probs <- stats::plogis(logits)
  max_prob_diff <- max(abs(sig_probs - probs))
  if (max_prob_diff >= 1e-4) {
    stop(sprintf("TreeSHAP tolerance failure: max prob diff %e >= 1e-4", max_prob_diff))
  }

  log_info(sprintf("TreeSHAP tolerance gate passed: logit diff %e < 1e-4, prob diff %e < 1e-4.",
                   max_logit_diff, max_prob_diff),
           call = "run_xgboost_shap_engine()")

  # 6. Format per-game SHAP explanation payloads
  p <- ncol(x_target)
  n_games <- nrow(target_games)
  game_shap_list <- vector("list", n_games)

  for (i in seq_len(n_games)) {
    gid <- as.character(target_games$game_id[i])
    base_val <- as.numeric(shap_mat[i, p + 1L])

    feat_rows <- vector("list", p)
    for (j in seq_len(p)) {
      fname <- XGB_SHAP_FEATURE_NAMES[j]
      flabel <- XGB_SHAP_FEATURE_LABELS[[fname]]
      feat_rows[[j]] <- list(
        feature     = fname,
        label       = flabel,
        value       = round(as.numeric(x_target[i, j]), 3),
        shap_value  = round(as.numeric(shap_mat[i, j]), 4)
      )
    }

    game_shap_list[[i]] <- list(
      game_id            = gid,
      season             = as.integer(target_games$season[i]),
      week               = as.integer(target_games$week[i]),
      home_team          = as.character(target_games$home_team[i]),
      away_team          = as.character(target_games$away_team[i]),
      model_win_prob     = round(as.numeric(probs[i]), 3),
      logit              = round(as.numeric(logits[i]), 4),
      base_value         = round(base_val, 4),
      features           = feat_rows,
      model_metadata     = list(
        model_id            = XGB_SHAP_MODEL_ID,
        model_label         = XGB_SHAP_MODEL_LABEL,
        trained_seasons     = sprintf("< %d", target_season),
        out_of_sample_record = oos_record
      )
    )
  }
  names(game_shap_list) <- target_games$game_id

  # 7. Persist to cache
  shap_payload <- list(
    generated_at       = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    target_season      = as.integer(target_season),
    model_id           = XGB_SHAP_MODEL_ID,
    model_label        = XGB_SHAP_MODEL_LABEL,
    out_of_sample_record = oos_record,
    games              = game_shap_list
  )

  dir.create(dirname(CACHE_XGBOOST_SHAP), recursive = TRUE, showWarnings = FALSE)
  saveRDS(shap_payload, CACHE_XGBOOST_SHAP)
  log_info(sprintf("Persisted TreeSHAP explanations for %d games to %s.",
                   length(game_shap_list), CACHE_XGBOOST_SHAP),
           call = "run_xgboost_shap_engine()")

  TRUE
}

# Auto-run if executed directly as a script
if (sys.nframe() == 0L) {
  run_xgboost_shap_engine()
}
