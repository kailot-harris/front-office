# ==============================================================================
# Ridge-Regularized Massey/EPA Rating Model + Situational EPA Features (Phase 4, model-quality
# remediation, situational-feature engineering)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/ridge_situational_model.R
#
# Extends tools/ridge_massey_model.R's ridge feature set with the per-team-per-game situational
# splits epa_metrics_engine.R now computes (config.R's SITUATIONAL_EPA_ROLL_COLS - early-down vs.
# money-down EPA/success, red-zone success rate, explosive-play rate, PROE) - see that file's
# header and config.R's "Situational EPA Feature Thresholds" section for the underlying
# definitions. Deliberately a SEPARATE file/candidate from ridge_massey_model.R, not an edit to
# it - this is a genuinely different, not-yet-validated question ("do situational splits add
# real signal beyond the aggregate EPA/play ridge already uses?"), and ridge_massey_model.R is
# the live production formula's fallback path (team_ratings_engine.R sources it directly) - it
# must not be touched by an unvalidated candidate. Only promote these features into
# ridge_massey_model.R / team_ratings_engine.R if tools/model_backtest_harness.R shows a real
# Brier/log-loss/Sharpe improvement over ensemble_ridge_elo, per this repo's own convention (see
# gbm_stack's negative-result precedent, tools/gbm_model.R).
#
# FEATURES: ridge_massey_model.R's four base features (diff_raw, diff_prior, diff_raw_gp,
# diff_prior_gp) PLUS one diff_<col> = home_<col> - away_<col> per config.R's
# SITUATIONAL_EPA_ROLL_COLS (14 more features, 18 total). NA diffs (either team's situational
# value NA - see epa_metrics_engine.R's PROE-coverage-gap comment for why this happens in
# 2002-2005 seasons) are imputed to 0 (neutral signal) rather than dropping the game entirely -
# a standard ridge-input convention, but not the only option (a missingness indicator column is
# an alternative worth trying in a later pass if this candidate looks promising).
#
# Assumes the CALLER has already done: source("config.R"); library(dplyr); library(glmnet);
# source("tools/ridge_massey_model.R") (for fallback_margin() - reused verbatim below, never a
# second copy of the production K-blend formula).
# No top-level side effects beyond function definitions - safe to source() from any script.
# ==============================================================================

build_ridge_situational_features <- function(games) {
  diff_raw   <- games$home_raw   - games$away_raw
  diff_prior <- games$home_prior - games$away_prior
  avg_gp     <- (games$home_gp + games$away_gp) / 2

  base <- cbind(
    diff_raw      = diff_raw,
    diff_prior    = diff_prior,
    diff_raw_gp   = diff_raw * avg_gp,
    diff_prior_gp = diff_prior * avg_gp
  )

  situational <- vapply(SITUATIONAL_EPA_ROLL_COLS, function(cn) {
    d <- games[[paste0("home_", cn)]] - games[[paste0("away_", cn)]]
    ifelse(is.na(d), 0, d)
  }, numeric(nrow(games)))
  colnames(situational) <- paste0("diff_", SITUATIONAL_EPA_ROLL_COLS)

  cbind(base, situational)
}

# Same determinism fix as ridge_massey_model.R's fit_ridge_massey() (glmnet::cv.glmnet()'s CV
# fold assignment uses the global RNG with no seed otherwise) - the seed value itself is
# arbitrary (a determinism fix, not a tuned hyperparameter), reused verbatim rather than a second
# independently-chosen literal.
fit_ridge_situational <- function(train_games) {
  x <- build_ridge_situational_features(train_games)
  y <- train_games$home_margin
  set.seed(20260917)
  glmnet::cv.glmnet(x, y, alpha = 0, nfolds = 5)
}

predict_ridge_situational_walkforward <- function(games) {
  seasons <- sort(unique(games$season))
  pred_margin <- rep(NA_real_, nrow(games))

  for (s in seasons) {
    train_idx <- which(games$season < s)
    test_idx  <- which(games$season == s)

    if (length(train_idx) < 100) {
      # Same fallback as ridge_massey_model.R's predict_ridge_massey_walkforward(): not enough
      # training history yet, use the production K-blend formula rather than fit on a tiny sample.
      pred_margin[test_idx] <- fallback_margin(games[test_idx, ])
      next
    }

    fit <- fit_ridge_situational(games[train_idx, ])
    x_test <- build_ridge_situational_features(games[test_idx, ])
    pred_margin[test_idx] <- as.numeric(predict(fit, newx = x_test, s = "lambda.min"))
  }

  pred_margin
}
