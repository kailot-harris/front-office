# ==============================================================================
# Ridge Model + Participation/Personnel Features (Known Issue #7 pickup)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/ridge_participation_model.R
#
# Extends tools/ridge_massey_model.R's ridge feature set with the six per-team-per-game
# participation/personnel features tools/participation_features.R computes (personnel-grouping
# tendency, box counts, pressure rates - see that file's header). BACKTEST-ONLY by hard
# data-availability necessity (participation.R's header explains why CACHE_PARTICIPATION_FEATURES
# can never be populated for CURRENT_SEASON) - this candidate exists purely to answer "does this
# data add real predictive signal at all," for tools/model_backtest_harness.R, never to be
# wired into team_ratings_engine.R's live prediction path.
#
# Deliberately a separate file from ridge_massey_model.R and ridge_situational_model.R (same
# rationale as the latter's own header: an unvalidated candidate must not touch the live
# production fallback path).
#
# NO-LOOKAHEAD ATTACH: attach_participation_asof() finds, for each (team, cutoff_date) pair,
# that team's most recent CACHE_PARTICIPATION_FEATURES row strictly before cutoff_date - same
# discipline as tools/backtest_common.R's build_week_snapshot(), implemented standalone here
# (not by editing that shared, production-critical function) since this feature set's hard
# 2016+-only / never-current-season availability doesn't belong baked into a function
# team_ratings_engine.R's live ridge_fit training also calls.
#
# Assumes the CALLER has already done: source("config.R"); library(dplyr); library(glmnet);
# source("tools/ridge_massey_model.R") (for fallback_margin()).
# No top-level side effects beyond function definitions - safe to source() from any script.
# ==============================================================================

PARTICIPATION_ROLL_COLS <- c(
  "off_personnel_11_rate_roll", "off_defenders_in_box_faced_roll", "off_pressure_rate_allowed_roll",
  "def_pass_rushers_avg_roll", "def_pressure_rate_generated_roll", "def_defenders_in_box_deployed_roll"
)

# ------------------------------------------------------------------------------------------
# attach_participation_asof(): `games` needs season/week/gameday/home_team/away_team (the
# shape tools/backtest_common.R's build_walkforward_games() already produces). Adds
# home_<col>/away_<col> for every PARTICIPATION_ROLL_COLS column, NA where that team has no
# participation history strictly before the game (e.g. every team's first participation-era
# game, or any team-game entirely before PARTICIPATION_MIN_SEASON).
# ------------------------------------------------------------------------------------------
attach_participation_asof <- function(games, part_features) {
  part_features <- part_features |> dplyr::arrange(team, game_date)
  by_team <- split(part_features, part_features$team)

  asof_lookup <- function(team, cutoff_date) {
    df <- by_team[[team]]
    if (is.null(df)) return(NULL)
    n_before <- sum(df$game_date < cutoff_date)
    if (n_before == 0) return(NULL)
    df[n_before, ]
  }

  home_cols <- lapply(PARTICIPATION_ROLL_COLS, function(cn) rep(NA_real_, nrow(games)))
  away_cols <- lapply(PARTICIPATION_ROLL_COLS, function(cn) rep(NA_real_, nrow(games)))
  names(home_cols) <- paste0("home_", PARTICIPATION_ROLL_COLS)
  names(away_cols) <- paste0("away_", PARTICIPATION_ROLL_COLS)

  for (i in seq_len(nrow(games))) {
    h_row <- asof_lookup(games$home_team[i], games$gameday[i])
    a_row <- asof_lookup(games$away_team[i], games$gameday[i])
    for (cn in PARTICIPATION_ROLL_COLS) {
      if (!is.null(h_row)) home_cols[[paste0("home_", cn)]][i] <- h_row[[cn]]
      if (!is.null(a_row)) away_cols[[paste0("away_", cn)]][i] <- a_row[[cn]]
    }
  }

  dplyr::bind_cols(games, as.data.frame(home_cols), as.data.frame(away_cols))
}

build_ridge_participation_features <- function(games) {
  diff_raw   <- games$home_raw   - games$away_raw
  diff_prior <- games$home_prior - games$away_prior
  avg_gp     <- (games$home_gp + games$away_gp) / 2

  base <- cbind(
    diff_raw      = diff_raw,
    diff_prior    = diff_prior,
    diff_raw_gp   = diff_raw * avg_gp,
    diff_prior_gp = diff_prior * avg_gp
  )

  participation <- vapply(PARTICIPATION_ROLL_COLS, function(cn) {
    d <- games[[paste0("home_", cn)]] - games[[paste0("away_", cn)]]
    ifelse(is.na(d), 0, d)
  }, numeric(nrow(games)))
  colnames(participation) <- paste0("diff_", PARTICIPATION_ROLL_COLS)

  cbind(base, participation)
}

# Same determinism-fix seed as ridge_massey_model.R/ridge_situational_model.R - arbitrary,
# reused verbatim (a determinism fix, not a tuned hyperparameter).
fit_ridge_participation <- function(train_games) {
  x <- build_ridge_participation_features(train_games)
  y <- train_games$home_margin
  set.seed(20260917)
  glmnet::cv.glmnet(x, y, alpha = 0, nfolds = 5)
}

predict_ridge_participation_walkforward <- function(games) {
  seasons <- sort(unique(games$season))
  pred_margin <- rep(NA_real_, nrow(games))

  for (s in seasons) {
    train_idx <- which(games$season < s)
    test_idx  <- which(games$season == s)

    if (length(train_idx) < 100) {
      pred_margin[test_idx] <- fallback_margin(games[test_idx, ])
      next
    }

    fit <- fit_ridge_participation(games[train_idx, ])
    x_test <- build_ridge_participation_features(games[test_idx, ])
    pred_margin[test_idx] <- as.numeric(predict(fit, newx = x_test, s = "lambda.min"))
  }

  pred_margin
}
