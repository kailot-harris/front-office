# tools/stacking_ensemble.R (NFL)
# Pure statistical stacking ensemble & empirical calibration layer
# Replaces 97% commercial market odds blend (Issue #11 / Epic #31)
#
# Combines:
# 1. Ridge-Massey EPA efficiency model
# 2. Dynamic margin-of-victory Elo model
# 3. Key player / QB availability adjustments (QB_INJURY_RATING_PENALTY_PTS)
# 4. Schedule fatigue drag adjustments
# 5. Empirical calibration mapping (isotonic / Platt scaling)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
source("tools/ridge_massey_model.R")
source("tools/elo_model.R")
source("tools/qb_injury_features.R")

.LOG_SCRIPT <- "stacking_ensemble.R"

#' Compute Endogenous Stacking Margin
#'
#' @param ridge_margin Numeric vector of projected Ridge margins
#' @param elo_margin Numeric vector of projected Elo margins (optional)
#' @param qb_adj Numeric vector of QB injury adjustments
#' @param fatigue_adj Numeric vector of fatigue drag adjustments
#' @param ridge_weight Numeric weight on Ridge model (default 0.50)
#' @return Numeric vector of combined projected margins
compute_stacking_margin <- function(ridge_margin,
                                    elo_margin = NULL,
                                    qb_adj = 0,
                                    fatigue_adj = 0,
                                    ridge_weight = 0.50) {
  if (is.null(elo_margin) || all(is.na(elo_margin))) {
    combined_base <- ridge_margin
  } else {
    combined_base <- ridge_weight * ridge_margin + (1 - ridge_weight) * elo_margin
  }
  
  combined_base + qb_adj + fatigue_adj
}

#' Calibrate Win Probability via Empirical Normal CDF
#'
#' @param projected_margin Numeric vector of final projected point margins
#' @param margin_sigma Numeric standard deviation of NFL margins (default NFL_MARGIN_SIGMA)
#' @return Numeric vector of calibrated win probabilities bounded in (0.001, 0.999)
calibrate_win_prob <- function(projected_margin, margin_sigma = NFL_MARGIN_SIGMA) {
  raw_prob <- pnorm(projected_margin / margin_sigma)
  pmin(pmax(raw_prob, 0.001), 0.999)
}

#' Fit Empirical Platt Scaling (Logistic Calibration) on Out-Of-Sample Predictions
#'
#' @param oos_predictions Data frame with columns `pred_margin` and `actual_win` (1/0)
#' @return Fitted glm model object for calibration
fit_empirical_calibration <- function(oos_predictions) {
  stopifnot("pred_margin" %in% names(oos_predictions), "actual_win" %in% names(oos_predictions))
  glm(actual_win ~ pred_margin, data = oos_predictions, family = binomial(link = "logit"))
}
