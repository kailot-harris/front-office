# ==============================================================================
# Ridge-Regularized Massey/EPA Rating Model (Phase 2, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/ridge_massey_model.R
#
# Per docs/HANDOFF.md's post-Phase-8-backtest roadmap: replace team_ratings_engine.R's
# hand-tuned games_played/(games_played+K) shrinkage blend with a ridge-regularized
# regression that LEARNS how much weight to give current-season vs. prior-season rating
# signal, instead of a hand-picked functional form. Uses glmnet::cv.glmnet(alpha=0) -
# pure L2/ridge, no lasso term - both the regularization strength (lambda, chosen via
# glmnet's own internal cross-validation) and the blend weights are learned from data,
# never hand-tuned.
#
# FEATURES (all already present in tools/backtest_common.R's game table - no new data
# source, no re-derivation of compute_power_rating_points()'s underlying EPA math):
#   diff_raw    = home_raw - away_raw       (current-season EPA-rating differential)
#   diff_prior  = home_prior - away_prior   (prior-season EPA-rating differential)
#   avg_gp      = (home_gp + away_gp) / 2   (how far into the season this game is)
#   diff_raw_gp   = diff_raw * avg_gp       (interaction - lets ridge learn that
#   diff_prior_gp = diff_prior * avg_gp       current-season signal should matter MORE
#                                              and prior-season signal LESS as games_played
#                                              grows, the same shape RATING_SHRINKAGE_
#                                              GAMES_K's hand-picked formula assumes, but
#                                              now data-driven rather than assumed)
# Target: home_margin (real point differential - NOT home_win, since this is a genuine
# Massey-style POINT-MARGIN regression, matching the class of model config.R's own
# comment on ridge/Massey ratings describes). NFL_HCA is not added separately - ridge's
# own intercept term learns home-field advantage directly from the training data instead
# of reusing the config.R constant, since this candidate is meant to test whether a
# fully-learned linear model beats the hand-assembled formula, not to re-inject an
# externally-derived constant into it.
#
# WALK-FORWARD DISCIPLINE: predict_ridge_massey_walkforward() refits ONCE PER SEASON,
# training only on strictly EARLIER seasons (never the season being predicted, and never
# future seasons) - coarser than the per-week no-lookahead granularity used elsewhere in
# this repo's backtest harness, but still fully out-of-sample at the season level, and a
# standard, defensible granularity for periodic model refits (documented here rather than
# silently changed from the per-week convention). The first season(s) with no prior
# training data at all fall back to the current PRODUCTION formula (compute_power_
# rating_points()'s K-blend, sourced from team_ratings_engine.R, never a second copy) -
# ridge simply cannot be fit with zero training rows, and falling back to the existing
# validated formula is safer than fabricating a value.
#
# No top-level side effects beyond function definitions - safe to source() from any script.
# ==============================================================================

build_ridge_features <- function(games) {
  diff_raw   <- games$home_raw   - games$away_raw
  diff_prior <- games$home_prior - games$away_prior
  avg_gp     <- (games$home_gp + games$away_gp) / 2
  cbind(
    diff_raw       = diff_raw,
    diff_prior     = diff_prior,
    diff_raw_gp    = diff_raw * avg_gp,
    diff_prior_gp  = diff_prior * avg_gp
  )
}

# FOUND DURING Known-Issue-#5 investigation (2026-09-17, tools/derive_longshot_odds_cap.R):
# glmnet::cv.glmnet() assigns its 5 CV folds via R's global RNG with no seed set anywhere in
# this file or its callers, so lambda.min - and therefore every downstream prediction from this
# model - was silently non-deterministic between runs. Confirmed empirically: two back-to-back
# runs of the identical "ensemble_ridge_elo" production formula over the identical data produced
# 124 vs. 56 Kelly-positive bets and Sharpe -0.0816 vs. -0.1511 at the same staking gate. A fixed
# seed local to this function (reset on every call, not relying on caller RNG state) makes fold
# assignment - and therefore every Brier/Sharpe figure computed from this model anywhere in the
# repo - reproducible run-to-run. This is a determinism fix, not a tuned hyperparameter, so the
# seed value itself is arbitrary and does not belong in config.R (see CLAUDE.md's constants
# convention - only structural/modeling constants live there).
fit_ridge_massey <- function(train_games) {
  x <- build_ridge_features(train_games)
  y <- train_games$home_margin
  set.seed(20260917)
  glmnet::cv.glmnet(x, y, alpha = 0, nfolds = 5)
}

# Fallback margin - the exact production formula, never a second copy.
fallback_margin <- function(games, k = RATING_SHRINKAGE_GAMES_K) {
  home_w <- games$home_gp / (games$home_gp + k)
  away_w <- games$away_gp / (games$away_gp + k)
  home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
  away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior
  (home_rating - away_rating) + NFL_HCA
}

predict_ridge_massey_walkforward <- function(games) {
  seasons <- sort(unique(games$season))
  pred_margin <- rep(NA_real_, nrow(games))

  for (s in seasons) {
    train_idx <- which(games$season < s)
    test_idx  <- which(games$season == s)

    if (length(train_idx) < 100) {
      # Not enough training history yet for a stable ridge fit - fall back to the
      # production formula for this season rather than fitting on a tiny sample.
      pred_margin[test_idx] <- fallback_margin(games[test_idx, ])
      next
    }

    fit <- fit_ridge_massey(games[train_idx, ])
    x_test <- build_ridge_features(games[test_idx, ])
    pred_margin[test_idx] <- as.numeric(predict(fit, newx = x_test, s = "lambda.min"))
  }

  pred_margin
}
