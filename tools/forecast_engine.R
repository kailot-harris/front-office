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
