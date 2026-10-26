# ==============================================================================
# tools/evaluate_season_calibration.R — Automated In-Season Model Calibration Monitor
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/evaluate_season_calibration.R
#
# Evaluates probability calibration, predictive accuracy, and edge integrity across
# walk-forward game predictions. Models evaluated:
#   1. Elo pre-game win probabilities (adj_home_elo vs. adj_away_elo)
#   2. Early-season sample progression (Games 1-300, 301-1000, 1001-2432)
#   3. Probability bin reliability (Brier Score, Log Loss, Expected vs Observed)
#   4. Dynamic warning flags for probability drift or overconfidence
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "evaluate_season_calibration.R"

#' Run Comprehensive Season Calibration Evaluation
#'
#' @param history_df Optional pre-loaded Elo history tibble. If NULL, loads cache/ratings/mlb_elo_history.rds.
#' @param verbose Logical; prints formatted calibration diagnostics if TRUE. Default TRUE.
#' @return A list containing Brier score, log loss, bin table, split metrics, and calibration status (OPTIMAL/WARNING).
run_season_calibration_check <- function(history_df = NULL, verbose = TRUE) {
  if (verbose) {
    cat("==================================================================\n")
    cat(">>> EVALUATING IN-SEASON MODEL CALIBRATION & PROBABILITY DRIFT\n")
    cat("==================================================================\n\n")
  }

  history_file <- cache_path("ratings", "mlb_elo_history.rds", create = FALSE)
  if (is.null(history_df)) {
    if (!file.exists(history_file)) {
      stop(sprintf("Elo history cache not found at %s. Run mlb_elo_engine.R first.", history_file))
    }
    history_df <- readRDS(history_file)
  }

  h <- as.data.frame(history_df)
  h <- h[!is.na(h$home_win_prob) & !is.na(h$home_won), ]
  n_games <- nrow(h)

  if (n_games < 50) {
    log_warn(sprintf("Insufficient games (%d) for statistically reliable calibration check.", n_games),
             script = .LOG_SCRIPT)
    return(list(status = "INSUFFICIENT_DATA", games = n_games))
  }

  # ----------------------------------------------------------------------------
  # 1. Overall Scoring Metrics (Brier Score, Log Loss)
  # ----------------------------------------------------------------------------
  p <- pmax(1e-6, pmin(1 - 1e-6, h$home_win_prob))
  y <- h$home_won

  brier_score <- mean((p - y)^2)
  # Uninformative coin-flip baseline Brier score = 0.2500
  brier_skill_score <- 1 - (brier_score / 0.2500)

  log_loss <- -mean(y * log(p) + (1 - y) * log(1 - p))

  # ----------------------------------------------------------------------------
  # 2. Probability Bin Calibration Table (Deciles / Groups)
  # ----------------------------------------------------------------------------
  bin_breaks <- c(0.0, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 1.0)
  bin_labels <- c("<40%", "40-45%", "45-50%", "50-55%", "55-60%", "60-65%", "65%+")

  h$prob_bin <- cut(p, breaks = bin_breaks, labels = bin_labels, include.lowest = TRUE)

  bin_summary <- h %>%
    dplyr::group_by(prob_bin) %>%
    dplyr::summarize(
      games         = dplyr::n(),
      pred_prob_avg = round(mean(home_win_prob), 4),
      obs_win_pct   = round(mean(home_won), 4),
      calib_error   = round(mean(home_win_prob) - mean(home_won), 4),
      .groups       = "drop"
    )

  # Weighted Average Calibration Error
  w_calib_error <- sum(abs(bin_summary$calib_error) * (bin_summary$games / n_games), na.rm = TRUE)

  # ----------------------------------------------------------------------------
  # 3. Early-Season vs. Mid/Late-Season Progression Split
  # ----------------------------------------------------------------------------
  split_tiers <- list(
    "Early (Games 1-300)"     = h[1:min(300, n_games), ],
    "Mid (Games 301-1200)"    = if (n_games > 300) h[301:min(1200, n_games), ] else NULL,
    "Late (Games 1201+)"      = if (n_games > 1200) h[1201:n_games, ] else NULL
  )

  split_summary <- list()
  for (tier_name in names(split_tiers)) {
    sub_df <- split_tiers[[tier_name]]
    if (!is.null(sub_df) && nrow(sub_df) > 0) {
      sub_p <- sub_df$home_win_prob
      sub_y <- sub_df$home_won
      sub_brier <- mean((sub_p - sub_y)^2)
      sub_sd    <- sd(sub_p)
      sub_min   <- min(sub_p)
      sub_max   <- max(sub_p)
      split_summary[[tier_name]] <- tibble::tibble(
        segment    = tier_name,
        games      = nrow(sub_df),
        mean_prob  = round(mean(sub_p), 4),
        sd_prob    = round(sub_sd, 4),
        min_prob   = round(sub_min, 4),
        max_prob   = round(sub_max, 4),
        brier      = round(sub_brier, 4)
      )
    }
  }
  split_df <- dplyr::bind_rows(split_summary)

  # ----------------------------------------------------------------------------
  # 4. Calibration Health Status Determination
  # ----------------------------------------------------------------------------
  # Criteria:
  # - Brier score < 0.250 (better than uninformative random coin flip)
  # - Weighted calibration error < 0.05 (predictions within 5% of actual frequency)
  # - Zero extreme outlier probabilities (> 0.85 or < 0.15) in regular season baseball
  has_extreme_outliers <- any(p > 0.85 | p < 0.15)
  calib_ok <- (brier_score < 0.250) && (w_calib_error < 0.05) && (!has_extreme_outliers)

  status <- if (calib_ok) "OPTIMAL" else "DRIFT_WARNING"

  if (verbose) {
    cat(sprintf("[METRICS] Total Games Evaluated: %d\n", n_games))
    cat(sprintf("  -> Overall Brier Score:       %.4f (Skill Score: +%.2f%% vs. 0.2500 coin-flip)\n",
                brier_score, brier_skill_score * 100))
    cat(sprintf("  -> Log Loss:                  %.4f\n", log_loss))
    cat(sprintf("  -> Weighted Calibration Error: %.4f (%.2f%%)\n",
                w_calib_error, w_calib_error * 100))
    cat(sprintf("  -> Extreme Outliers (>85%%/<15%%): %s\n\n",
                if (has_extreme_outliers) "DETECTED (Flagged)" else "None (Controlled)"))

    cat("[PROBABILITY BIN RELIABILITY]\n")
    print(as.data.frame(bin_summary))
    cat("\n")

    cat("[CHRONOLOGICAL SEASON PROGRESSION]\n")
    print(as.data.frame(split_df))
    cat("\n")

    if (calib_ok) {
      cat("==================================================================\n")
      cat(">>> CALIBRATION STATUS: OPTIMAL (Model probabilities well-calibrated)\n")
      cat("==================================================================\n\n")
    } else {
      cat("==================================================================\n")
      cat(">>> CALIBRATION STATUS: DRIFT_WARNING (Review rating parameters)\n")
      cat("==================================================================\n\n")
    }
  }

  log_info(sprintf("Season calibration evaluated: status=%s | brier=%.4f | w_error=%.4f | games=%d",
                   status, brier_score, w_calib_error, n_games),
           script = .LOG_SCRIPT)

  list(
    status                 = status,
    total_games            = n_games,
    brier_score            = round(brier_score, 4),
    brier_skill_score      = round(brier_skill_score, 4),
    log_loss               = round(log_loss, 4),
    weighted_calib_error   = round(w_calib_error, 4),
    bin_calibration        = bin_summary,
    progression_splits     = split_df,
    has_extreme_outliers   = has_extreme_outliers
  )
}

# Run only when invoked directly (Rscript tools/evaluate_season_calibration.R),
# not when sourced. The old `!interactive()` guard fired on every source() too,
# so test-calibration.R hit the missing-cache stop at load time — outside any
# test_that(), where skip_if_no_cache() cannot reach it. This is the same
# idiom the sibling tools use (see evaluate_bayes_shrinkage.R).
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--run" %in% args || length(args) == 0) {
    invisible(run_season_calibration_check())
  }
}
