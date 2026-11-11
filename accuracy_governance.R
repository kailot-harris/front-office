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

  # `log_source` distinguishes a genuine pre-game forecast ("LOGGED_PREGAME",
  # written by .build_slate_rows() / tools/project_week_predictions.R BEFORE
  # the game happened) from a row seed_prediction_log() backfilled from box
  # scores AFTER the fact using a rating model that already knew the outcome
  # ("SEEDED_HINDSIGHT"). See prediction_accuracy_logger.R's
  # .classify_log_source()/.ensure_log_source_column(). A log written before
  # that column existed is migrated here too, on the same heuristic, so this
  # file never silently falls back to averaging the two populations together.
  if (!"log_source" %in% names(df)) {
    pt <- as.Date(df$prediction_timestamp)
    gd <- as.Date(df$game_date)
    df$log_source <- ifelse(!is.na(pt) & !is.na(gd) & pt < gd,
                             "LOGGED_PREGAME", "SEEDED_HINDSIGHT")
    cat("[ACCURACY GOVERNANCE] Migrated stored log: added log_source column.\n")
  }

  resolved <- df |> filter(status == "RESOLVED" & !is.na(predicted_home_win_prob) & !is.na(actual_winner))

  if (nrow(resolved) == 0) {
    cat("[ACCURACY GOVERNANCE] No resolved predictions available in log.\n")
    return(invisible(FALSE))
  }

  # The two populations, evaluated SEPARATELY. `genuine` is what the headline
  # figures and the Diagnostics page calibration chart are built from;
  # `hindsight` is reported only as a clearly-labeled historical-backtest
  # context block. Before this change, `resolved` (both populations pooled)
  # drove every published figure, so ~2,656 of ~2,791 "predictions" behind the
  # Diagnostics page were actually hindsight, not forecasts.
  genuine   <- resolved |> filter(log_source == "LOGGED_PREGAME")
  hindsight <- resolved |> filter(log_source == "SEEDED_HINDSIGHT")

  cat(sprintf(paste0(
    "[ACCURACY GOVERNANCE] Resolved rows: %d total -> %d genuine pre-game ",
    "forecasts (LOGGED_PREGAME), %d hindsight-seeded backtest rows ",
    "(SEEDED_HINDSIGHT).\n"), nrow(resolved), nrow(genuine), nrow(hindsight)))

  # Genuine forecasts are the headline metric this engine exists to govern. If
  # there are none yet (e.g. a brand-new log before the first weekly
  # projection has resolved), fall back to the pooled set so the pipeline
  # still produces a number, but say so loudly rather than silently reporting
  # hindsight as if it were live forecast accuracy.
  if (nrow(genuine) > 0) {
    gov <- compute_forecast_governance(genuine$predicted_home_win_prob,
                                        as.integer(genuine$actual_winner == genuine$home_team))
  } else {
    cat(paste0("[ACCURACY GOVERNANCE] WARNING: zero genuine (LOGGED_PREGAME) ",
               "resolved rows. Headline figures fall back to the pooled/",
               "hindsight set until the first weekly projection resolves.\n"))
    gov <- compute_forecast_governance(resolved$predicted_home_win_prob,
                                        as.integer(resolved$actual_winner == resolved$home_team))
  }

  gov_backtest <- if (nrow(hindsight) > 0) {
    compute_forecast_governance(hindsight$predicted_home_win_prob,
                                 as.integer(hindsight$actual_winner == hindsight$home_team))
  } else {
    NULL
  }
  gov$historical_backtest <- gov_backtest

  # Cache output
  out_rds <- file.path(CACHE_DIR, "accuracy_governance.rds")
  saveRDS(gov, out_rds)
  cat(sprintf("[ACCURACY GOVERNANCE] Saved metrics to %s\n", out_rds))
  cat(sprintf("  -> Genuine forecasts evaluated: %d | SU Acc: %.1f%% | Rolling 30 SU: %.1f%%\n",
              gov$total_games, gov$su_accuracy * 100, gov$rolling_su_accuracy * 100))
  cat(sprintf("  -> Brier Score: %.4f | BSS(50/50): +%.2f%% | Log-Loss: %.4f | ECE: %.4f\n",
              gov$brier_score, gov$brier_skill_score_tossup * 100, gov$log_loss, gov$ece))
  if (!is.null(gov_backtest)) {
    cat(sprintf("  -> [Historical backtest, hindsight-seeded] %d games | SU Acc: %.1f%% | Brier: %.4f\n",
                gov_backtest$total_games, gov_backtest$su_accuracy * 100, gov_backtest$brier_score))
  }

  # Sync web diagnostic export: web/public/data/projections_diagnostics.json
  web_data_dir <- if (exists("WEB_DATA_DIR")) WEB_DATA_DIR else file.path(.THIS_DIR, "web", "public", "data")
  if (dir.exists(web_data_dir)) {

    # Build the { calibration, accuracyDrift, residualDistribution } block for
    # ONE population (either the genuine forecasts or the hindsight backtest)
    # so the two never get averaged together downstream. `d` is already
    # filtered to one log_source and to RESOLVED rows with a known outcome.
    .diag_block <- function(d, g) {
      calib_formatted <- lapply(g$calibration_bins, function(b) {
        list(
          bin               = b$bin,
          midpoint          = b$midpoint,
          count             = b$count,
          meanPredictedProb = b$meanPredictedProb,
          empiricalWinRate  = b$empiricalWinRate
        )
      })

      drift_list <- list()
      if ("season" %in% names(d) && nrow(d) > 0) {
        seasons <- sort(unique(d$season))
        for (s in seasons) {
          s_df <- d |> filter(season == s)
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

      residuals <- if (nrow(d) > 0) {
        d$predicted_home_win_prob - as.integer(d$actual_winner == d$home_team)
      } else {
        numeric(0)
      }
      residual_dist <- list(
        list(bucket = "< -0.4",       count = sum(residuals < -0.4),                      label = "Large Under-forecast"),
        list(bucket = "-0.4 to -0.2", count = sum(residuals >= -0.4 & residuals < -0.2), label = "Moderate Under-forecast"),
        list(bucket = "-0.2 to 0.0",  count = sum(residuals >= -0.2 & residuals < 0.0),  label = "Slight Under-forecast"),
        list(bucket = "0.0 to 0.2",   count = sum(residuals >= 0.0 & residuals <= 0.2),  label = "Slight Over-forecast"),
        list(bucket = "0.2 to 0.4",   count = sum(residuals > 0.2 & residuals <= 0.4),   label = "Moderate Over-forecast"),
        list(bucket = "> 0.4",        count = sum(residuals > 0.4),                       label = "Large Over-forecast")
      )

      list(
        totalGames           = g$total_games,
        overallAccuracy      = g$su_accuracy,
        brierScore           = g$brier_score,
        brierSkillScore      = g$brier_skill_score_tossup,
        logLoss              = g$log_loss,
        homeWinRate          = g$home_win_rate,
        weightedCalibError   = g$ece,
        calibrationStatus    = g$status,
        calibration          = calib_formatted,
        accuracyDrift        = drift_list,
        residualDistribution = residual_dist
      )
    }

    # The population that actually drove `gov` above (genuine, or the pooled
    # fallback when there are zero genuine rows yet).
    headline_pop <- if (nrow(genuine) > 0) genuine else resolved
    headline_blk <- .diag_block(headline_pop, gov)

    diag_payload <- list(
      generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),

      # --- Headline figures: GENUINE pre-game forecasts only (log_source ==
      # "LOGGED_PREGAME"). This is what the Diagnostics page's headline cards
      # and calibration chart are driven by. Flat field names are unchanged
      # from before this fix so DiagnosticsClient.tsx keeps working, but the
      # population behind them changed from "all RESOLVED rows" (~2,791,
      # ~95% hindsight) to genuine forecasts only (~135 resolved today).
      totalResolvedGames   = headline_blk$totalGames,
      overallAccuracy      = headline_blk$overallAccuracy,
      brierScore           = headline_blk$brierScore,
      brierSkillScore      = headline_blk$brierSkillScore,
      logLoss              = headline_blk$logLoss,
      homeWinRate          = headline_blk$homeWinRate,
      weightedCalibError   = headline_blk$weightedCalibError,
      calibrationStatus    = headline_blk$calibrationStatus,
      calibration          = headline_blk$calibration,
      accuracyDrift        = headline_blk$accuracyDrift,
      residualDistribution = headline_blk$residualDistribution,

      # Explicit duplicate of the headline block, named for what it is -
      # for any consumer that wants to be unambiguous rather than relying on
      # the flat fields' meaning.
      genuineForecast      = headline_blk,

      # Historical backtest: SEEDED_HINDSIGHT rows only - box-score-derived
      # "predictions" computed after the outcome was already known. Reported
      # for transparency about model fit over history, never pooled into the
      # figures above.
      historicalBacktest   = if (!is.null(gov_backtest)) {
        .diag_block(hindsight, gov_backtest)
      } else {
        NULL
      },

      rowCounts = list(
        resolvedTotal      = as.integer(nrow(resolved)),
        genuinePregame     = as.integer(nrow(genuine)),
        seededHindsight     = as.integer(nrow(hindsight))
      )
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
