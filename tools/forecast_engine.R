# ==============================================================================
# tools/forecast_engine.R
# Unified Game Forecast Engine for NFL Analytics (Issue #110, Owner Decision D2).
#
# Provides the single shared forecast calculation across both live upcoming
# matchups (team_ratings_engine.R) and historical walk-forward grading
# (tools/backtest_common.R).
#
# Implements Variant 1 (Margin Averaging, Zero Fatigue):
#   - Point margin: 50% Ridge-Massey margin + 50% Elo margin
#   - Fallback: 100% Ridge-Massey margin when Elo is unavailable
#   - Fatigue: Completely removed from the forecast formula (zero fatigue term)
#   - Win probability: pnorm(projected_margin / margin_sigma)
#
# Strictly zero-betting compliant (no betting vocabulary or market data).
# ==============================================================================

if (!exists("NFL_MARGIN_SIGMA", mode = "numeric")) {
  if (file.exists("config.R")) {
    source("config.R")
  } else if (file.exists("../config.R")) {
    source("../config.R")
  }
}

#' Compute unified game forecast from Ridge and Elo projected margins
#'
#' Evaluates Variant 1: 50% Ridge margin + 50% Elo margin (or 100% Ridge when
#' Elo is unavailable), and converts projected point margin to home win probability
#' via the normal CDF: pnorm(projected_margin / margin_sigma).
#'
#' @param ridge_margin Numeric vector or scalar of Ridge projected margins
#'   (including quarterback adjustment if applicable).
#' @param elo_margin Numeric vector or scalar of Elo projected margins
#'   (including quarterback adjustment, strictly without fatigue), or NULL.
#' @param elo_available Logical vector or scalar indicating whether Elo is
#'   available for each game. Defaults to TRUE.
#' @param margin_sigma Numeric scalar, standard deviation of points margin
#'   (defaults to NFL_MARGIN_SIGMA or 14.60).
#' @return A list with components:
#'   - `projected_margin`: numeric vector of blended point margins (home - away)
#'   - `home_win_prob`: numeric vector of home win probabilities in [0, 1]
#' @export
compute_game_forecast <- function(ridge_margin,
                                  elo_margin = NULL,
                                  elo_available = TRUE,
                                  margin_sigma = if (exists("NFL_MARGIN_SIGMA", mode = "numeric")) NFL_MARGIN_SIGMA else 14.60) {
  if (length(ridge_margin) == 0L) {
    return(list(
      projected_margin = numeric(0),
      home_win_prob    = numeric(0)
    ))
  }

  n <- length(ridge_margin)

  if (is.null(elo_margin)) {
    use_elo <- rep(FALSE, n)
    elo_m <- rep(NA_real_, n)
  } else {
    elo_m <- as.numeric(elo_margin)
    if (length(elo_m) == 1L && n > 1L) {
      elo_m <- rep(elo_m, n)
    }
    avail <- as.logical(elo_available)
    if (length(avail) == 1L && n > 1L) {
      avail <- rep(avail, n)
    }
    use_elo <- avail & !is.na(elo_m)
  }

  projected_margin <- as.numeric(ridge_margin)
  if (any(use_elo)) {
    projected_margin[use_elo] <- 0.5 * ridge_margin[use_elo] + 0.5 * elo_m[use_elo]
  }

  home_win_prob <- stats::pnorm(projected_margin / margin_sigma)

  list(
    projected_margin = projected_margin,
    home_win_prob    = home_win_prob
  )
}

#' Compute quarterback injury adjustment shift
#'
#' Computes the additive shift in projected point margin (home - away)
#' resulting from backup quarterback participation.
#'
#' @param home_qb_backup Logical vector or scalar (TRUE if home backup started).
#' @param away_qb_backup Logical vector or scalar (TRUE if away backup started).
#' @param penalty Numeric scalar points penalty per backup quarterback
#'   (defaults to QB_INJURY_RATING_PENALTY_PTS or 1.60).
#' @return Numeric vector or scalar point shift applied to home margin.
#' @export
compute_qb_injury_shift <- function(home_qb_backup,
                                    away_qb_backup,
                                    penalty = if (exists("QB_INJURY_RATING_PENALTY_PTS", mode = "numeric")) QB_INJURY_RATING_PENALTY_PTS else 1.60) {
  h_flag <- ifelse(is.na(home_qb_backup), 0L, as.integer(as.logical(home_qb_backup)))
  a_flag <- ifelse(is.na(away_qb_backup), 0L, as.integer(as.logical(away_qb_backup)))
  -penalty * h_flag + penalty * a_flag
}

#' Compute 5-step points waterfall and rounding term for game projections
#'
#' Evaluates the Section 5.2 points waterfall decomposing projected point margin:
#'   1. step_current_epa:   w_ridge * (b_raw + b_raw_gp * avg_gp) * (home_raw - away_raw)
#'   2. step_prior_epa:     w_ridge * (b_prior + b_prior_gp * avg_gp) * (home_prior - away_prior)
#'   3. step_elo_diff:      w_elo * (home_elo - away_elo) / 25
#'   4. step_home_field:    (1 - neutral) * (w_ridge * ridge_intercept + w_elo * 48 / 25)
#'   5. step_qb_adjustment: 1.60 * (away_qb_backup - home_qb_backup)
#'   6. step_rounding:      projected_margin - sum(five steps)  (verified <= 0.02)
#'
#' Where:
#'   - If Elo is available: w_ridge = 0.5, w_elo = 0.5
#'   - If Elo is absent or NA: w_ridge = 1.0, w_elo = 0.0, step_elo_diff = 0
#'   - neutral: 1 if neutral site, 0 if home game
#'   - avg_gp: average games played (home_gp + away_gp) / 2
#'
#' @param home_raw Numeric vector of home current-season raw rating points.
#' @param away_raw Numeric vector of away current-season raw rating points.
#' @param home_prior Numeric vector of home prior-season rating points.
#' @param away_prior Numeric vector of away prior-season rating points.
#' @param home_gp Numeric/integer vector of home games played.
#' @param away_gp Numeric/integer vector of away games played.
#' @param home_elo Numeric vector of home Elo ratings (or NA).
#' @param away_elo Numeric vector of away Elo ratings (or NA).
#' @param elo_available Logical vector indicating Elo availability. If NULL, inferred from home/away Elo.
#' @param neutral Logical, numeric, or character vector (e.g. TRUE/FALSE, 1/0, "Neutral"/"Home").
#' @param home_qb_backup Logical vector (TRUE if home backup QB starts).
#' @param away_qb_backup Logical vector (TRUE if away backup QB starts).
#' @param ridge_coefs Named vector, list, matrix, or cv.glmnet of Ridge model coefficients.
#' @param b_intercept Numeric scalar/vector Ridge intercept.
#' @param b_raw Numeric scalar/vector Ridge diff_raw coefficient.
#' @param b_prior Numeric scalar/vector Ridge diff_prior coefficient.
#' @param b_raw_gp Numeric scalar/vector Ridge diff_raw_gp coefficient.
#' @param b_prior_gp Numeric scalar/vector Ridge diff_prior_gp coefficient.
#' @param projected_margin Optional numeric vector of projected margins for rounding verification.
#' @param qb_penalty Numeric scalar penalty per backup QB (default QB_INJURY_RATING_PENALTY_PTS or 1.60).
#' @param elo_hca Numeric scalar Elo home field points (default ELO_HCA_POINTS or 48).
#' @param elo_pts_per_margin Numeric scalar points per margin in Elo (default ELO_POINTS_PER_MARGIN_PT or 25).
#' @return A data.frame with columns:
#'   - `step_current_epa`
#'   - `step_prior_epa`
#'   - `step_elo_diff`
#'   - `step_home_field`
#'   - `step_qb_adjustment`
#'   - `step_rounding`
#' @export
compute_waterfall_steps <- function(home_raw,
                                    away_raw,
                                    home_prior,
                                    away_prior,
                                    home_gp,
                                    away_gp,
                                    home_elo = NA_real_,
                                    away_elo = NA_real_,
                                    elo_available = NULL,
                                    neutral = FALSE,
                                    home_qb_backup = FALSE,
                                    away_qb_backup = FALSE,
                                    ridge_coefs = NULL,
                                    b_intercept = NULL,
                                    b_raw = NULL,
                                    b_prior = NULL,
                                    b_raw_gp = NULL,
                                    b_prior_gp = NULL,
                                    projected_margin = NULL,
                                    qb_penalty = if (exists("QB_INJURY_RATING_PENALTY_PTS", mode = "numeric")) QB_INJURY_RATING_PENALTY_PTS else 1.60,
                                    elo_hca = if (exists("ELO_HCA_POINTS", mode = "numeric")) ELO_HCA_POINTS else 48,
                                    elo_pts_per_margin = if (exists("ELO_POINTS_PER_MARGIN_PT", mode = "numeric")) ELO_POINTS_PER_MARGIN_PT else 25) {
  # Extract ridge coefficients with fallback defaults
  get_coef <- function(names_to_try, direct_val, default = 0.0) {
    if (!is.null(direct_val)) return(direct_val)
    if (is.null(ridge_coefs)) return(default)
    if (inherits(ridge_coefs, "cv.glmnet") || inherits(ridge_coefs, "glmnet")) {
      cf_mat <- as.matrix(stats::coef(ridge_coefs, s = "lambda.min"))
      for (nm in names_to_try) {
        if (nm %in% rownames(cf_mat)) return(cf_mat[nm, 1])
      }
    } else if (is.matrix(ridge_coefs)) {
      for (nm in names_to_try) {
        if (nm %in% rownames(ridge_coefs)) return(ridge_coefs[nm, 1])
        if (nm %in% colnames(ridge_coefs)) return(ridge_coefs[1, nm])
      }
    } else if (is.list(ridge_coefs) || is.vector(ridge_coefs)) {
      nm_list <- names(ridge_coefs)
      for (nm in names_to_try) {
        if (!is.null(nm_list) && nm %in% nm_list) return(as.numeric(ridge_coefs[[nm]]))
      }
    }
    default
  }

  c_int      <- get_coef(c("(Intercept)", "b_intercept", "intercept", "ridge_b_intercept"), b_intercept, 0.0)
  c_raw      <- get_coef(c("diff_raw", "b_raw", "ridge_b_raw"), b_raw, 0.0)
  c_prior    <- get_coef(c("diff_prior", "b_prior", "ridge_b_prior"), b_prior, 0.0)
  c_raw_gp   <- get_coef(c("diff_raw_gp", "b_raw_gp", "ridge_b_raw_gp"), b_raw_gp, 0.0)
  c_prior_gp <- get_coef(c("diff_prior_gp", "b_prior_gp", "ridge_b_prior_gp"), b_prior_gp, 0.0)

  n <- max(
    length(home_raw), length(away_raw),
    length(home_prior), length(away_prior),
    length(home_gp), length(away_gp)
  )

  if (n == 0L) {
    return(data.frame(
      step_current_epa   = numeric(0),
      step_prior_epa     = numeric(0),
      step_elo_diff      = numeric(0),
      step_home_field    = numeric(0),
      step_qb_adjustment = numeric(0),
      step_rounding      = numeric(0),
      stringsAsFactors   = FALSE
    ))
  }

  h_raw   <- rep_len(as.numeric(home_raw), n)
  a_raw   <- rep_len(as.numeric(away_raw), n)
  h_prior <- rep_len(as.numeric(home_prior), n)
  a_prior <- rep_len(as.numeric(away_prior), n)
  h_gp    <- rep_len(as.numeric(home_gp), n)
  a_gp    <- rep_len(as.numeric(away_gp), n)

  h_elo   <- if (is.null(home_elo)) rep(NA_real_, n) else rep_len(as.numeric(home_elo), n)
  a_elo   <- if (is.null(away_elo)) rep(NA_real_, n) else rep_len(as.numeric(away_elo), n)

  if (is.null(elo_available)) {
    has_elo <- !is.na(h_elo) & !is.na(a_elo)
  } else {
    has_elo <- rep_len(as.logical(elo_available), n) & !is.na(h_elo) & !is.na(a_elo)
  }

  if (is.character(neutral)) {
    is_neu <- toupper(rep_len(neutral, n)) == "NEUTRAL"
  } else {
    neu_log <- as.logical(neutral)
    is_neu <- ifelse(is.na(neu_log), FALSE, rep_len(neu_log, n))
  }
  neu_factor <- ifelse(is_neu, 0.0, 1.0)

  h_bk <- ifelse(is.na(home_qb_backup), 0.0, as.numeric(as.logical(home_qb_backup)))
  a_bk <- ifelse(is.na(away_qb_backup), 0.0, as.numeric(as.logical(away_qb_backup)))
  h_bk <- rep_len(h_bk, n)
  a_bk <- rep_len(a_bk, n)

  w_ridge <- ifelse(has_elo, 0.5, 1.0)
  w_elo   <- ifelse(has_elo, 0.5, 0.0)
  avg_gp  <- (h_gp + a_gp) / 2.0

  step_current_epa   <- w_ridge * (c_raw + c_raw_gp * avg_gp) * (h_raw - a_raw)
  step_prior_epa     <- w_ridge * (c_prior + c_prior_gp * avg_gp) * (h_prior - a_prior)
  step_elo_diff      <- ifelse(has_elo, w_elo * (h_elo - a_elo) / elo_pts_per_margin, 0.0)
  step_home_field    <- neu_factor * (w_ridge * c_int + w_elo * (elo_hca / elo_pts_per_margin))
  step_qb_adjustment <- qb_penalty * (a_bk - h_bk)

  five_steps_sum <- step_current_epa + step_prior_epa + step_elo_diff + step_home_field + step_qb_adjustment

  if (!is.null(projected_margin)) {
    proj_m <- rep_len(as.numeric(projected_margin), n)
    step_rounding <- proj_m - five_steps_sum
  } else {
    step_rounding <- rep(0.0, n)
  }

  if (any(abs(step_rounding) > 0.02 + 1e-6, na.rm = TRUE)) {
    warning("compute_waterfall_steps: abs(step_rounding) exceeds 0.02 threshold")
  }

  data.frame(
    step_current_epa   = as.numeric(step_current_epa),
    step_prior_epa     = as.numeric(step_prior_epa),
    step_elo_diff      = as.numeric(step_elo_diff),
    step_home_field    = as.numeric(step_home_field),
    step_qb_adjustment = as.numeric(step_qb_adjustment),
    step_rounding      = as.numeric(step_rounding),
    stringsAsFactors   = FALSE
  )
}
