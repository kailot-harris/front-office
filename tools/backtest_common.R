# ==============================================================================
# Shared Walk-Forward Game-Table Builder (Phase A, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/backtest_common.R
#
# Extracted from tools/backtest_shrinkage_optimizer.R (2026-09-17) so a second
# consumer (tools/model_backtest_harness.R) can reuse the exact same no-lookahead
# walk-forward data assembly instead of a second, independently-typed copy of it
# (the class of drift this repo's CLAUDE.md warns about). backtest_shrinkage_
# optimizer.R itself was refactored in the same commit to call build_walkforward_
# games() below instead of its old inline loop - its own output (Brier/Sharpe
# figures) is unchanged by this refactor (verified by re-running it - see that
# script's own header/commit message).
#
# Assumes the CALLER has already done: source("config.R"); library(dplyr);
# source("team_ratings_engine.R") (for compute_power_rating_points()). This file
# defines no top-level side effects beyond function definitions - safe to source()
# from any script.
#
# LOOKAHEAD-BIAS NOTE (unchanged from the original script): for every
# (season, week) snapshot, each team's rating is built ONLY from EPA rows dated
# strictly before that week's earliest game - a team's own same-week game can
# never leak into its own pre-game rating.
# ==============================================================================

# ------------------------------------------------------------------------------------------
# Prior-season-final rating for every team, identical formula/inputs to team_ratings_engine.R's
# own prior_epa_ratings block. Cached per season by the caller if called in a loop (this function
# itself does no caching - callers should call it once per distinct season, not once per game).
# ------------------------------------------------------------------------------------------
build_prior_season_ratings <- function(epa, season, avg_plays_per_game) {
  prior_epa <- epa |>
    filter(season == !!(season - 1L)) |>
    arrange(team, game_date, week) |>
    group_by(team) |>
    slice_tail(n = 1) |>
    ungroup() |>
    select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll)

  if (nrow(prior_epa) == 0) return(data.frame(team = character(0), prior_season_rating = numeric(0)))

  league_avg_off_prior <- mean(prior_epa$off_epa_per_play_roll, na.rm = TRUE)
  league_avg_def_prior <- mean(prior_epa$def_epa_per_play_allowed_roll, na.rm = TRUE)

  prior_epa |>
    mutate(
      prior_season_rating = compute_power_rating_points(
        off_epa_per_play_roll, def_epa_per_play_allowed_roll,
        league_avg_off_prior, league_avg_def_prior, avg_plays_per_game
      )
    ) |>
    select(team, prior_season_rating)
}

# ------------------------------------------------------------------------------------------
# Every team's as-of "current_raw_rating" and real current-season games_played, using ONLY EPA
# rows strictly before cutoff_date (no lookahead).
#
# Also carries each team's latest as-of value of every column in config.R's
# SITUATIONAL_EPA_ROLL_COLS (Phase 4 model-quality remediation, situational-feature engineering)
# straight through, unchanged - these are NOT run through compute_power_rating_points() like
# off_epa_per_play_roll/def_epa_per_play_allowed_roll are (they aren't point-margin-scale
# ratings, just situational rates/EPA splits), just carried as their own as-of snapshot values
# for a candidate model's own feature engineering to use downstream.
# ------------------------------------------------------------------------------------------
build_week_snapshot <- function(epa, season, cutoff_date, avg_plays_per_game) {
  asof <- epa |> filter(game_date < cutoff_date)

  latest_asof <- asof |>
    arrange(team, game_date, week) |>
    group_by(team) |>
    slice_tail(n = 1) |>
    ungroup() |>
    select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll,
           dplyr::all_of(SITUATIONAL_EPA_ROLL_COLS))

  if (nrow(latest_asof) == 0) return(NULL)

  league_avg_off <- mean(latest_asof$off_epa_per_play_roll, na.rm = TRUE)
  league_avg_def <- mean(latest_asof$def_epa_per_play_allowed_roll, na.rm = TRUE)

  latest_asof <- latest_asof |>
    mutate(
      current_raw_rating = compute_power_rating_points(
        off_epa_per_play_roll, def_epa_per_play_allowed_roll,
        league_avg_off, league_avg_def, avg_plays_per_game
      )
    )

  games_played <- asof |>
    filter(season == !!season) |>
    count(team, name = "games_played")

  latest_asof |>
    left_join(games_played, by = "team") |>
    mutate(games_played = ifelse(is.na(games_played), 0L, games_played)) |>
    select(team, current_raw_rating, games_played, dplyr::all_of(SITUATIONAL_EPA_ROLL_COLS))
}

# ------------------------------------------------------------------------------------------
# build_walkforward_games(): the full walk-forward per-game table, K-independent (raw/prior
# ratings + games_played + actual outcome + moneylines), built ONCE and reused across every
# candidate a caller wants to compare - only the cheap blend/pnorm/metric math re-runs per
# candidate, not this data assembly.
#
# `epa` = CACHE_EPA_METRICS (readRDS + as.Date(game_date)); `completed` = CACHE_SCHEDULES filtered
# to non-NA home_score/away_score. `calibration_seasons` = integer vector of seasons to walk
# forward across (each must have a prior season present in `epa` for build_prior_season_ratings()
# to find real data, else that team falls back to prior_season_rating = 0 same as the live
# pipeline's own fallback).
#
# Adds `home_margin` (home_score - away_score) alongside the existing `home_win` (0/1) column -
# a strict superset of the original backtest_shrinkage_optimizer.R game table shape, needed by
# tools/derive_qb_injury_penalty.R's residual-based derivation (see that script). Existing
# consumers that only read home_win/home_ml/away_ml are unaffected.
# ------------------------------------------------------------------------------------------
build_walkforward_games <- function(epa, completed, calibration_seasons, avg_plays_per_game) {
  game_rows <- list()
  row_i <- 0L

  for (s in calibration_seasons) {
    prior_ratings <- build_prior_season_ratings(epa, s, avg_plays_per_game)
    season_games  <- completed |> filter(season == s)
    weeks_this_season <- sort(unique(season_games$week))

    for (w in weeks_this_season) {
      week_games <- season_games |> filter(week == w)
      cutoff <- min(week_games$gameday, na.rm = TRUE)
      snap <- build_week_snapshot(epa, s, cutoff, avg_plays_per_game)
      if (is.null(snap)) next

      snap <- snap |> left_join(prior_ratings, by = "team") |>
        mutate(prior_season_rating = ifelse(is.na(prior_season_rating), 0, prior_season_rating))

      rating_lu       <- setNames(snap$current_raw_rating, snap$team)
      prior_lu        <- setNames(snap$prior_season_rating, snap$team)
      games_played_lu <- setNames(snap$games_played, snap$team)
      # Phase 4 (situational-feature engineering): one named lookup vector per
      # SITUATIONAL_EPA_ROLL_COLS column, built once per (season, week) snapshot - avoids
      # rebuilding these inside the per-game loop below.
      situational_lu <- setNames(
        lapply(SITUATIONAL_EPA_ROLL_COLS, function(cn) setNames(snap[[cn]], snap$team)),
        SITUATIONAL_EPA_ROLL_COLS
      )

      for (i in seq_len(nrow(week_games))) {
        g <- week_games[i, ]
        h <- g$home_team; a <- g$away_team
        if (is.na(rating_lu[h]) || is.na(rating_lu[a])) next

        row_i <- row_i + 1L
        row <- data.frame(
          season = s, week = w, game_id = g$game_id, gameday = g$gameday,
          home_team = h, away_team = a,
          home_raw = unname(rating_lu[h]),   away_raw = unname(rating_lu[a]),
          home_prior = unname(prior_lu[h]),  away_prior = unname(prior_lu[a]),
          home_gp = unname(games_played_lu[h]), away_gp = unname(games_played_lu[a]),
          home_win = as.integer(g$home_score > g$away_score),
          home_margin = g$home_score - g$away_score,
          home_ml = g$home_moneyline, away_ml = g$away_moneyline,
          stringsAsFactors = FALSE
        )
        # Phase 4: attach home_<col>/away_<col> for every situational rolling column.
        for (cn in SITUATIONAL_EPA_ROLL_COLS) {
          row[[paste0("home_", cn)]] <- unname(situational_lu[[cn]][h])
          row[[paste0("away_", cn)]] <- unname(situational_lu[[cn]][a])
        }
        game_rows[[row_i]] <- row
      }
    }
  }

  bind_rows(game_rows)
}

# ------------------------------------------------------------------------------------------
# Accuracy-History Cache Helpers (prep infra for accuracy_tracker.R, GitHub issue #4 /
# docs/SPEC_accuracy_trajectory_monitoring.md decision #6)
#
# These helpers own CACHE_ACCURACY_HISTORY's on-disk schema (see config.R's constant comment
# for the authoritative row-schema documentation - do not restate/duplicate it here, only
# reference it, same "single source of truth" discipline CLAUDE.md requires for constants).
# Assumes the caller has already done source("config.R"); library(dplyr). No top-level side
# effects beyond function definitions - safe to source() from any script, same convention as
# the rest of this file.
# ------------------------------------------------------------------------------------------

# Empty, correctly-typed accuracy-history data.frame (zero rows) - the shape every init/append
# call below conforms to. Exists as its own function (rather than inlined) so init and append
# can both build from the identical column-type definition instead of risking two independently-
# typed copies drifting apart.
empty_accuracy_history <- function() {
  data.frame(
    run_timestamp  = as.POSIXct(character(0)),
    season         = integer(0),
    overall_accuracy = numeric(0),
    overall_brier    = numeric(0),
    overall_logloss  = numeric(0),
    n_games_graded   = integer(0),
    stringsAsFactors = FALSE
  ) |>
    dplyr::mutate(newly_graded_games = list())
}

# init_accuracy_history(): creates (and persists) an empty CACHE_ACCURACY_HISTORY cache file if
# one does not already exist. Idempotent - if a file already exists at that path this is a no-op
# that just returns it unchanged (does NOT overwrite/truncate real history). Returns the
# (possibly just-created) data.frame.
init_accuracy_history <- function() {
  if (file.exists(CACHE_ACCURACY_HISTORY)) {
    return(readRDS(CACHE_ACCURACY_HISTORY))
  }
  hist <- empty_accuracy_history()
  saveRDS(hist, CACHE_ACCURACY_HISTORY)
  hist
}

# load_accuracy_history(): reads the existing cache, or initializes+returns an empty one if this
# is the very first run (file doesn't exist yet) - the read-side counterpart callers should use
# instead of readRDS(CACHE_ACCURACY_HISTORY) directly, so "no history yet" never has to be
# special-cased by every caller.
load_accuracy_history <- function() {
  if (!file.exists(CACHE_ACCURACY_HISTORY)) return(init_accuracy_history())
  readRDS(CACHE_ACCURACY_HISTORY)
}

# append_accuracy_history(): appends one new row to CACHE_ACCURACY_HISTORY and persists the
# result, per decision #5/#6 - one row per run that detects newly-completed/graded games.
# Callers that detect nothing new graded since the last row should simply not call this (a
# true no-op run appends nothing, per decision #4's idempotency requirement) - this function
# itself always appends exactly one row when called.
#
# `newly_graded_games` = a data.frame for THIS run's newly-graded games only, with columns
# game_id/matchup/predicted_winner/actual_winner/correct/predicted_win_prob (see config.R's
# CACHE_ACCURACY_HISTORY comment for the full column-type spec) - typically 1 row, but may be
# >1 (e.g. a full Sunday slate graded in one pass).
# `overall_accuracy`/`overall_brier`/`overall_logloss`/`n_games_graded` = the CUMULATIVE
# season-to-date figures across all graded games for `season` as of this run, not just the
# incremental newly_graded_games rows - matches issue #2's grade_walkforward_games() output
# shape (overall_accuracy/overall_brier/overall_logloss scoped to all graded games so far).
#
# Returns the full updated history data.frame (existing rows + the new one), already persisted
# to CACHE_ACCURACY_HISTORY.
append_accuracy_history <- function(season,
                                     newly_graded_games,
                                     overall_accuracy,
                                     overall_brier,
                                     overall_logloss,
                                     n_games_graded,
                                     run_timestamp = Sys.time()) {
  existing <- load_accuracy_history()

  new_row <- data.frame(
    run_timestamp    = as.POSIXct(run_timestamp),
    season           = as.integer(season),
    overall_accuracy = as.numeric(overall_accuracy),
    overall_brier    = as.numeric(overall_brier),
    overall_logloss  = as.numeric(overall_logloss),
    n_games_graded   = as.integer(n_games_graded),
    stringsAsFactors = FALSE
  )
  new_row$newly_graded_games <- list(newly_graded_games)

  updated <- dplyr::bind_rows(existing, new_row)
  saveRDS(updated, CACHE_ACCURACY_HISTORY)
  updated
}
