# ==============================================================================
# Gradient-Boosted Trees Model (Phase 4, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/gbm_model.R
#
# Per docs/HANDOFF.md's roadmap: gated on Phase 2 or 3 beating the Phase 1 baseline first
# (both did - ridge and the deployed ridge+Elo ensemble). xgboost is already installed in
# this environment (confirmed 2026-09-17) - no new dependency. lightgbm is NOT installed;
# xgboost is used instead, not both.
#
# FEATURES: reuses signals already computed elsewhere in this repo rather than re-deriving
# raw PBP features from scratch (out of scope for this pass - see docs/HANDOFF.md's Phase 4
# note on the ~350 dropped CACHE_PBP columns for what a future situational-feature pass could
# add). This is effectively a STACKING model: it takes Phase 2's ridge margin and Phase 3's
# Elo margin as INPUT FEATURES (along with the raw EPA-differential/games-played/QB-backup/
# market-probability signals each of those already consumes) and lets the tree ensemble learn
# a non-linear/interaction-aware combination, rather than the deployed formula's hand-picked
# 50/50 average. This is a genuinely different question from "is ridge or Elo individually
# better" - it's "can a learned, nonlinear meta-combination beat a naive linear average of the
# same two models' outputs."
#
# WALK-FORWARD DISCIPLINE WITH NESTED TUNING (per the plan's explicit requirement - hyper-
# parameter selection must happen INSIDE each fold, never on the full backtest): for each test
# season s, the training pool (all games$season < s) is itself split into a fit-pool (seasons
# < the most recent prior season) and a validation slice (the single most recent prior season),
# xgboost's own early-stopping picks the number of boosting rounds against that validation
# slice, then the FINAL model for predicting season s is refit on the ENTIRE training pool
# (fit-pool + validation season combined) using that chosen round count. The validation season
# is always strictly before the test season - no leakage. Tree hyperparameters beyond nrounds
# (max_depth, eta, subsample, colsample_bytree, min_child_weight) are fixed, deliberately
# conservative/regularized values, NOT exhaustively tuned - see header note on overfitting risk
# at this repo's data scale (~5,500 walk-forward games, a small regime for tree ensembles).
#
# No top-level side effects beyond function/constant definitions - safe to source() from any
# script.
# ==============================================================================

.GBM_PARAMS <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 3,
  eta = 0.05,
  subsample = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 5
)
.GBM_MAX_ROUNDS <- 500
.GBM_EARLY_STOP <- 20

build_gbm_features <- function(games, ridge_margin, elo_margin) {
  home_qb <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
  away_qb <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
  market_na <- is.na(games$market_prob)
  market_imputed <- ifelse(market_na, 0.5, games$market_prob)

  cbind(
    diff_raw     = games$home_raw - games$away_raw,
    diff_prior   = games$home_prior - games$away_prior,
    gp_min       = pmin(games$home_gp, games$away_gp),
    gp_avg       = (games$home_gp + games$away_gp) / 2,
    qb_diff      = away_qb - home_qb,
    ridge_margin = ridge_margin,
    elo_margin   = elo_margin,
    fatigue_adj  = ifelse(is.na(games$fatigue_adj), 0, games$fatigue_adj),
    market_prob  = market_imputed,
    market_na    = as.integer(market_na)
  )
}

predict_gbm_walkforward <- function(games, ridge_margin, elo_margin) {
  x_all <- build_gbm_features(games, ridge_margin, elo_margin)
  y_all <- games$home_win
  seasons <- sort(unique(games$season))
  pred <- rep(NA_real_, nrow(games))

  for (s in seasons) {
    train_seasons <- seasons[seasons < s]
    if (length(train_seasons) < 3) {
      # Not enough season-level history for a fit-pool/validation split - fall back to a
      # 50/50 average of ridge/Elo margins (the deployed production formula) for this season,
      # same "don't fit on too little data" discipline as tools/ridge_massey_model.R's fallback.
      idx <- which(games$season == s)
      fallback_margin <- (ridge_margin[idx] + elo_margin[idx]) / 2
      pred[idx] <- pnorm(fallback_margin / NFL_MARGIN_SIGMA)
      next
    }

    val_season <- max(train_seasons)
    fit_seasons <- train_seasons[train_seasons < val_season]
    fit_idx <- which(games$season %in% fit_seasons)
    val_idx <- which(games$season == val_season)
    full_train_idx <- which(games$season %in% train_seasons)
    test_idx <- which(games$season == s)

    if (length(fit_idx) < 100) {
      fallback_margin <- (ridge_margin[test_idx] + elo_margin[test_idx]) / 2
      pred[test_idx] <- pnorm(fallback_margin / NFL_MARGIN_SIGMA)
      next
    }

    dfit <- xgboost::xgb.DMatrix(data = x_all[fit_idx, , drop = FALSE], label = y_all[fit_idx])
    dval <- xgboost::xgb.DMatrix(data = x_all[val_idx, , drop = FALSE], label = y_all[val_idx])

    tuned <- xgboost::xgb.train(
      params = .GBM_PARAMS, data = dfit, nrounds = .GBM_MAX_ROUNDS,
      watchlist = list(val = dval), early_stopping_rounds = .GBM_EARLY_STOP,
      verbose = 0
    )
    best_nrounds <- tuned$best_iteration

    dtrain_full <- xgboost::xgb.DMatrix(data = x_all[full_train_idx, , drop = FALSE], label = y_all[full_train_idx])
    final_fit <- xgboost::xgb.train(params = .GBM_PARAMS, data = dtrain_full, nrounds = max(best_nrounds, 1), verbose = 0)

    dtest <- xgboost::xgb.DMatrix(data = x_all[test_idx, , drop = FALSE])
    pred[test_idx] <- predict(final_fit, dtest)
  }

  pred
}
