# ==============================================================================
# Kalman-Filter State-Space Rating Model (Phase 5, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/kalman_state_space_model.R
#
# Per docs/HANDOFF.md's roadmap: "Phase 5 (Bayesian state-space) needs an Rtools/rstan install
# decision first, or a pure-R closed-form Kalman-filter alternative." rstan/cmdstanr/brms/rjags
# are NOT installed on this machine (CLAUDE.md's environment section) and installing an MCMC
# toolchain is a real, user-facing install decision, not something to do silently mid-session -
# this file is the documented fallback: a genuine Bayesian STATE-SPACE model (each team's
# latent point-margin-scale "strength" is a Gaussian random walk updated via exact conjugate-
# Gaussian (Kalman) math, not a hand-tuned Elo-style update rule), just without MCMC sampling.
#
# WHY THIS IS GENUINELY DIFFERENT FROM Phases 2/3 (not just a third re-parameterization of the
# same idea): ridge (Phase 2) and Elo (Phase 3) both report a single point estimate per team and
# rely on NFL_MARGIN_SIGMA (one FIXED variance for every game) to convert margin to a
# probability. This model tracks each team's own POSTERIOR VARIANCE explicitly (wide for a team
# with little recent history - rookie season, long injury layoff, a new season just started -
# narrow for a team with a long stable run of games) and uses the GAME-SPECIFIC combined
# variance (home_var + away_var + observation noise) for that game's win probability. This
# directly targets the Phase 8 finding that early-season ratings produced 93%+ win probabilities
# against real market odds (docs/task_assignments_phase7.md) - RATING_SHRINKAGE_GAMES_K's
# hand-picked games_played/(games_played+K) formula was a manual patch for exactly this; a
# Kalman filter's variance naturally starts wide and narrows with real evidence, no hand-picked
# K needed.
#
# STATE: per team, (mu, var) - mu is point-margin-scale strength (same units as home_margin,
# NOT Elo points), var is posterior uncertainty. Prior mean is 0 (league average) for every team
# with no history.
#
# PROCESS MODEL (state evolves BETWEEN games a team plays):
#   Within a season, before each game a team plays (except its first ever), inject
#   KALMAN_PROCESS_VARIANCE of fresh uncertainty (a team's true strength can drift game to
#   game - injuries, scheme changes, etc.) - mu is NOT changed, only var grows:
#     var <- var + KALMAN_PROCESS_VARIANCE
#   At a SEASON boundary (mirrors tools/elo_model.R's ELO_SEASON_CARRYOVER exactly, same
#   rationale, different math because this is a genuine Gaussian blend rather than an ad hoc
#   weighted average): the team's rating is treated as a linear combination of its own
#   end-of-prior-season posterior and a fresh N(0, KALMAN_INITIAL_VARIANCE) prior, weighted by
#   KALMAN_SEASON_CARRYOVER - both mu AND var update via the exact variance-of-a-linear-
#   combination-of-independent-Gaussians formula (not just an ad hoc reset):
#     mu  <- KALMAN_SEASON_CARRYOVER * mu
#     var <- KALMAN_SEASON_CARRYOVER^2 * var + (1 - KALMAN_SEASON_CARRYOVER)^2 * KALMAN_INITIAL_VARIANCE
#
# OBSERVATION MODEL (exact bivariate Kalman update - see derivation in this file's commit
# message / derive_kalman_params.R's header for the full algebra): treats each game as a noisy
# observation of (mu_home - mu_away), NOT a full 32x32 joint-covariance update across every team
# in the league - this is the same "assumed density filtering" independence approximation
# TrueSkill/Glicko make (cross-team covariance introduced by a shared game is dropped after each
# update, kept independent per-team going forward) - the standard, tractable simplification, not
# an oversight. NFL_HCA (this repo's single already-validated home-field-advantage constant, NOT
# a second independently-fit HCA) is reused directly as the observation-model intercept, since
# the state is already on the same point-margin scale NFL_HCA was derived in.
#   pred_margin = (mu_home - mu_away) + NFL_HCA
#   pred_var    = var_home + var_away + KALMAN_OBSERVATION_VARIANCE
#   residual    = home_margin - pred_margin
#   mu_home'  = mu_home + (var_home / pred_var) * residual
#   mu_away'  = mu_away - (var_away / pred_var) * residual
#   var_home' = var_home * (var_away + KALMAN_OBSERVATION_VARIANCE) / pred_var
#   var_away' = var_away * (var_home + KALMAN_OBSERVATION_VARIANCE) / pred_var
#
# All four KALMAN_* hyperparameters are empirically derived via tools/derive_kalman_params.R
# (stats::optim(), walk-forward Brier minimization - same discipline as every other derived
# constant in this repo) and live in config.R, never re-typed here.
#
# Interface deliberately mirrors tools/elo_model.R's run_elo_walkforward()/project_elo_rating()
# (return_final_state option, project_*_rating() for live inference) so team_ratings_engine.R
# could wire this in the same way Elo was wired in Phase 3, without a third, differently-shaped
# interface to learn.
#
# No top-level side effects beyond function definitions - safe to source() from any script.
# ==============================================================================

# ------------------------------------------------------------------------------------------
# run_kalman_walkforward(): sch_completed sorted chronologically. Returns one row per game with
# PRE-update state (no lookahead by construction - each team's state is only ever updated AFTER
# its own game is scored) plus that game's home_win_prob using the GAME-SPECIFIC combined
# variance (not NFL_MARGIN_SIGMA).
# ------------------------------------------------------------------------------------------
run_kalman_walkforward <- function(sch_completed, return_final_state = FALSE) {
  sch_completed <- sch_completed |> dplyr::arrange(gameday, game_id)

  mu_env  <- new.env(parent = emptyenv())  # team -> mu
  var_env <- new.env(parent = emptyenv())  # team -> var
  last_season_env <- new.env(parent = emptyenv())

  get_state <- function(team, season) {
    if (!exists(team, envir = mu_env, inherits = FALSE)) {
      assign(team, 0, envir = mu_env)
      assign(team, KALMAN_INITIAL_VARIANCE, envir = var_env)
      assign(team, season, envir = last_season_env)
      return(c(mu = 0, var = KALMAN_INITIAL_VARIANCE))
    }

    mu  <- get(team, envir = mu_env, inherits = FALSE)
    var <- get(team, envir = var_env, inherits = FALSE)
    prev_season <- get(team, envir = last_season_env, inherits = FALSE)

    if (season > prev_season) {
      mu_new  <- KALMAN_SEASON_CARRYOVER * mu
      var_new <- (KALMAN_SEASON_CARRYOVER^2) * var +
                 ((1 - KALMAN_SEASON_CARRYOVER)^2) * KALMAN_INITIAL_VARIANCE
      mu <- mu_new; var <- var_new
    } else {
      # Same-season, not this team's first game this season: process noise accrues game to game.
      var <- var + KALMAN_PROCESS_VARIANCE
    }

    assign(team, season, envir = last_season_env)
    c(mu = mu, var = var)
  }

  # Preallocated numeric/character vectors, not a list of 6,000+ one-row data.frames rebuilt via
  # bind_rows() - this function is called ONCE PER stats::optim() ITERATION during hyperparameter
  # derivation (tools/derive_kalman_params.R), so per-call allocation overhead matters on this
  # machine's limited memory (a prior list-of-data.frames version caused a real background-process
  # OOM kill during derivation - see that script's commit message). A single data.frame() call at
  # the end is both faster and lower-peak-memory than incrementally bind_rows()-ing 6,000+ frames.
  n <- nrow(sch_completed)
  home_win        <- integer(n)
  kalman_margin   <- numeric(n)
  kalman_pred_var <- numeric(n)
  home_win_prob   <- numeric(n)

  home_team_v <- sch_completed$home_team
  away_team_v <- sch_completed$away_team
  season_v    <- sch_completed$season
  home_score_v <- sch_completed$home_score
  away_score_v <- sch_completed$away_score

  for (i in seq_len(n)) {
    h <- home_team_v[i]; a <- away_team_v[i]; s <- season_v[i]

    st_h <- get_state(h, s)
    st_a <- get_state(a, s)
    mu_h <- st_h[["mu"]]; var_h <- st_h[["var"]]
    mu_a <- st_a[["mu"]]; var_a <- st_a[["var"]]

    pred_margin <- (mu_h - mu_a) + NFL_HCA
    pred_var    <- var_h + var_a + KALMAN_OBSERVATION_VARIANCE
    margin      <- home_score_v[i] - away_score_v[i]
    residual    <- margin - pred_margin

    mu_h_new  <- mu_h + (var_h / pred_var) * residual
    mu_a_new  <- mu_a - (var_a / pred_var) * residual
    var_h_new <- var_h * (var_a + KALMAN_OBSERVATION_VARIANCE) / pred_var
    var_a_new <- var_a * (var_h + KALMAN_OBSERVATION_VARIANCE) / pred_var

    assign(h, mu_h_new, envir = mu_env);  assign(h, var_h_new, envir = var_env)
    assign(a, mu_a_new, envir = mu_env);  assign(a, var_a_new, envir = var_env)

    home_win[i]        <- as.integer(home_score_v[i] > away_score_v[i])
    kalman_margin[i]   <- pred_margin
    kalman_pred_var[i] <- pred_var
    home_win_prob[i]   <- pnorm(pred_margin / sqrt(pred_var))
  }

  result <- data.frame(
    game_id = sch_completed$game_id, season = season_v, week = sch_completed$week,
    home_team = home_team_v, away_team = away_team_v,
    home_win = home_win, kalman_margin_pts = kalman_margin, kalman_pred_var = kalman_pred_var,
    home_win_prob = home_win_prob, stringsAsFactors = FALSE
  )
  if (!return_final_state) return(result)

  teams_seen <- ls(envir = mu_env)
  final_mu  <- setNames(vapply(teams_seen, function(t) get(t, envir = mu_env, inherits = FALSE), numeric(1)), teams_seen)
  final_var <- setNames(vapply(teams_seen, function(t) get(t, envir = var_env, inherits = FALSE), numeric(1)), teams_seen)
  final_season <- setNames(vapply(teams_seen, function(t) get(t, envir = last_season_env, inherits = FALSE), numeric(1)), teams_seen)
  list(games = result, final_mu = final_mu, final_var = final_var, final_season = final_season)
}

# ------------------------------------------------------------------------------------------
# project_kalman_state(): apply the season-carryover rule to a team's stored final (mu, var) if
# it hasn't yet played in `current_season` - mirrors project_elo_rating() (tools/elo_model.R).
# ------------------------------------------------------------------------------------------
project_kalman_state <- function(mu, var, last_played_season, current_season) {
  if (is.na(mu) || is.na(var) || is.na(last_played_season)) return(c(mu = NA_real_, var = NA_real_))
  if (current_season > last_played_season) {
    mu_new  <- KALMAN_SEASON_CARRYOVER * mu
    var_new <- (KALMAN_SEASON_CARRYOVER^2) * var +
               ((1 - KALMAN_SEASON_CARRYOVER)^2) * KALMAN_INITIAL_VARIANCE
    return(c(mu = mu_new, var = var_new))
  }
  c(mu = mu, var = var)
}
