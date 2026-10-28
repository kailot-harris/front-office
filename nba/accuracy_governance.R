# ==============================================================================
# accuracy_governance.R — Forecast Governance & Calibration Engine (NBA)
#
# GitHub issue #17 (Part of epic #31).
# Evaluates model forecast quality without betting or financial grading:
#   - Straight-Up (SU) Accuracy: Season-to-date and rolling 30-game accuracy.
#   - Brier Skill Score (BSS): Benchmarked against naive baselines:
#       1) 50/50 toss-up baseline (Brier = 0.2500)
#       2) Home-team-always-wins empirical baseline
#   - Binary/Multi-class Log-Loss: Penalizes overconfident mispredictions.
#   - Expected Calibration Error (ECE) & 10-decile reliability bin table.
#
# Reads cache/prediction_accuracy_log.rds and writes:
#   - cache/accuracy_governance.rds
#   - web/public/data/projections_diagnostics.json
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
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
  source(file.path(.THIS_DIR, "config.R"), local = TRUE)
}

if (!exists(".LOG_SCRIPT", inherits = FALSE)) {
  .LOG_SCRIPT <- "accuracy_governance.R"
}

if (!exists("CACHE_DIR", inherits = FALSE)) {
  CACHE_DIR <- if (exists("PROJECT_DIR", inherits = FALSE)) file.path(PROJECT_DIR, "cache") else "cache"
}

#' Compute Forecast Governance Metrics
compute_forecast_governance <- function(p_pred, y_obs, n_bins = 10L, rolling_window = 30L) {
  valid <- !is.na(p_pred) & !is.na(y_obs)
  p <- pmin(pmax(as.numeric(p_pred[valid]), 1e-6), 1 - 1e-6)
  y <- as.numeric(y_obs[valid])
  n <- length(y)

  if (n == 0L) {
    return(list(
      status                   = "NO_DATA",
      total_games              = 0L,
      su_accuracy              = NA_real_,
      rolling_su_accuracy      = NA_real_,
      brier_score              = NA_real_,
      brier_skill_score_tossup = NA_real_,
      brier_skill_score_home   = NA_real_,
      log_loss                 = NA_real_,
      ece                      = NA_real_,
      home_win_rate            = NA_real_,
      calibration_bins         = list()
    ))
  }

  # Straight-Up Accuracy
  pred_winner <- p >= 0.5
  su_correct <- pred_winner == (y == 1)
  su_accuracy <- mean(su_correct)
  rolling_n <- min(n, rolling_window)
  rolling_su_accuracy <- mean(tail(su_correct, rolling_n))

  # Brier Score & BSS benchmarks
  brier <- mean((p - y)^2)
  brier_baseline_tossup <- 0.2500
  home_win_rate <- mean(y)
  brier_baseline_home <- mean((home_win_rate - y)^2)

  bss_tossup <- 1 - (brier / brier_baseline_tossup)
  bss_home <- if (brier_baseline_home > 0) 1 - (brier / brier_baseline_home) else 0.0

  # Log-loss
  log_loss <- -mean(y * log(p) + (1 - y) * log(1 - p))

  # Decile Reliability Table & ECE
  cuts <- seq(0, 1, length.out = n_bins + 1L)
  calib_bins <- list()
  weighted_calib_error <- 0.0

  for (b in 1:n_bins) {
    low <- cuts[b]
    high <- cuts[b + 1L]
    mask <- if (b == n_bins) (p >= low & p <= high) else (p >= low & p < high)
    cnt <- sum(mask)
    mean_p <- if (cnt > 0L) mean(p[mask]) else (low + high) / 2
    obs_rate <- if (cnt > 0L) mean(y[mask]) else 0.0
    err <- abs(mean_p - obs_rate)

    if (cnt > 0L) {
      weighted_calib_error <- weighted_calib_error + (cnt / n) * err
    }

    calib_bins[[b]] <- list(
      bin               = sprintf("%d-%d%%", as.integer(round(low * 100)), as.integer(round(high * 100))),
      midpoint          = round((low + high) / 2, 2),
      count             = as.integer(cnt),
      meanPredictedProb = round(mean_p, 4),
      empiricalWinRate  = round(obs_rate, 4),
      calibrationError  = round(mean_p - obs_rate, 4)
    )
  }

  list(
    status                   = "OPTIMAL",
    total_games              = as.integer(n),
    su_accuracy              = round(su_accuracy, 4),
    rolling_su_accuracy      = round(rolling_su_accuracy, 4),
    rolling_window           = as.integer(rolling_n),
    brier_score              = round(brier, 4),
    brier_skill_score_tossup = round(bss_tossup, 4),
    brier_skill_score_home   = round(bss_home, 4),
    log_loss                 = round(log_loss, 4),
    ece                      = round(weighted_calib_error, 4),
    home_win_rate            = round(home_win_rate, 4),
    calibration_bins         = calib_bins,
    evaluated_at             = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

run_nba_accuracy_governance <- function() {
  cat("\n==================================================================\n")
  cat("     FORECAST ACCURACY GOVERNANCE & CALIBRATION ENGINE (NBA)       \n")
  cat("==================================================================\n\n")

  log_path <- if (exists("CACHE_PREDICTION_LOG")) CACHE_PREDICTION_LOG else file.path(CACHE_DIR, "prediction_accuracy_log.rds")
  if (!file.exists(log_path)) {
    cat(sprintf("[ACCURACY GOVERNANCE] Prediction log not found: %s\n", log_path))
    return(invisible(FALSE))
  }

  df <- readRDS(log_path)
  resolved <- df |> filter(status == "RESOLVED" & !is.na(predicted_home_win_prob) & !is.na(actual_winner))

  if (nrow(resolved) == 0) {
    cat("[ACCURACY GOVERNANCE] No resolved predictions available in log.\n")
    return(invisible(FALSE))
  }

  home_won <- as.integer(resolved$actual_winner == resolved$home_team)
  p_win <- resolved$predicted_home_win_prob

  gov <- compute_forecast_governance(p_win, home_won)

  # Cache output
  out_rds <- file.path(CACHE_DIR, "accuracy_governance.rds")
  saveRDS(gov, out_rds)
  cat(sprintf("[ACCURACY GOVERNANCE] Saved metrics to %s\n", out_rds))
  cat(sprintf("  -> Total Evaluated: %d | SU Acc: %.1f%% | Rolling 30 SU: %.1f%%\n",
              gov$total_games, gov$su_accuracy * 100, gov$rolling_su_accuracy * 100))
  cat(sprintf("  -> Brier Score: %.4f | BSS(50/50): +%.2f%% | Log-Loss: %.4f | ECE: %.4f\n",
              gov$brier_score, gov$brier_skill_score_tossup * 100, gov$log_loss, gov$ece))

  # Sync web diagnostic export: web/public/data/projections_diagnostics.json
  web_data_dir <- if (exists("WEB_DATA_DIR")) WEB_DATA_DIR else file.path(.THIS_DIR, "web", "public", "data")
  if (dir.exists(web_data_dir)) {
    # Match web Diagnostics schema
    calib_formatted <- lapply(gov$calibration_bins, function(b) {
      list(
        bin               = b$bin,
        midpoint          = b$midpoint,
        count             = b$count,
        meanPredictedProb = b$meanPredictedProb,
        empiricalWinRate  = b$empiricalWinRate
      )
    })

    # Accuracy drift by season if season column exists
    drift_list <- list()
    if ("season" %in% names(resolved)) {
      seasons <- sort(unique(resolved$season))
      for (s in seasons) {
        s_df <- resolved |> filter(season == s)
        s_y <- as.integer(s_df$actual_winner == s_df$home_team)
        s_p <- s_df$predicted_home_win_prob
        drift_list[[length(drift_list) + 1]] <- list(
          season     = as.character(s),
          games      = as.integer(nrow(s_df)),
          accuracy   = round(mean((s_p >= 0.5) == (s_y == 1)), 4),
          brierScore = round(mean((s_p - s_y)^2), 4)
        )
      }
    }

    # Residual distribution
    residuals <- p_win - home_won
    residual_dist <- list(
      list(bucket = "< -0.4",       count = sum(residuals < -0.4),                      label = "Large Under-forecast"),
      list(bucket = "-0.4 to -0.2", count = sum(residuals >= -0.4 & residuals < -0.2), label = "Moderate Under-forecast"),
      list(bucket = "-0.2 to 0.0",  count = sum(residuals >= -0.2 & residuals < 0.0),  label = "Slight Under-forecast"),
      list(bucket = "0.0 to 0.2",   count = sum(residuals >= 0.0 & residuals <= 0.2),  label = "Slight Over-forecast"),
      list(bucket = "0.2 to 0.4",   count = sum(residuals > 0.2 & residuals <= 0.4),   label = "Moderate Over-forecast"),
      list(bucket = "> 0.4",        count = sum(residuals > 0.4),                       label = "Large Over-forecast")
    )

    diag_payload <- list(
      generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      totalResolvedGames   = gov$total_games,
      overallAccuracy      = gov$su_accuracy,
      brierScore           = gov$brier_score,
      brierSkillScore      = gov$brier_skill_score_tossup,
      logLoss              = gov$log_loss,
      homeWinRate          = gov$home_win_rate,
      weightedCalibError   = gov$ece,
      calibrationStatus    = gov$status,
      calibration          = calib_formatted,
      accuracyDrift        = drift_list,
      residualDistribution = residual_dist
    )

    out_json <- file.path(web_data_dir, "projections_diagnostics.json")
    write_json(diag_payload, out_json, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("[ACCURACY GOVERNANCE] Synced %s\n", out_json))
  }

  invisible(gov)
}

if (!interactive()) {
  run_nba_accuracy_governance()
}
