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
# grade_walkforward_games(): full walk-forward grading of a season's completed games against
# the PRODUCTION ensemble formula (ridge Massey + Elo, QB-injury-adjusted, market-blended).
#
# Extracted verbatim (2026-10) from tools/weekly_accuracy_report.R's former inline body
# (~lines 64-148 as of that extraction) so a second consumer (the planned accuracy_tracker.R,
# issue #5) can call the exact same no-lookahead grading logic instead of a second,
# independently-typed copy of it (the class of drift this repo's CLAUDE.md warns about).
# weekly_accuracy_report.R itself is NOT yet wired to call this function (see issue #3 / 1b,
# a separate follow-up) — this extraction is a pure relocation, zero behavior change.
#
# FORMULA PARITY WITH PRODUCTION (must be kept in sync with team_ratings_engine.R's run_team_
# ratings() inner loop, ~lines 519-576, if that formula ever changes): ridge margin (Phase 2,
# tools/ridge_massey_model.R's fit_ridge_massey()/predict_ridge_massey_walkforward(), refit once
# per season) + Elo margin (Phase 3, tools/elo_model.R's run_elo_walkforward(), includes real
# fatigue_adj), each shifted by the QB-injury penalty (config.R's QB_INJURY_RATING_PENALTY_PTS)
# then pnorm()'d against NFL_MARGIN_SIGMA, each blended with historical market-implied probability
# at MARKET_BLEND_WEIGHT, then averaged 50/50 — this is exactly tools/model_backtest_harness.R's
# validated "ensemble_ridge_elo" candidate.
#
# Assumes the CALLER has already done everything build_walkforward_games() above assumes, PLUS:
# source("market_odds_engine.R") (american_to_prob()), source("tools/qb_injury_features.R")
# (get_qb_starter_table()/compute_qb_backup_flags()), source("tools/ridge_massey_model.R")
# (predict_ridge_massey_walkforward()), source("tools/elo_model.R") (run_elo_walkforward()).
#
# Args: `epa` = CACHE_EPA_METRICS (readRDS + as.Date(game_date)); `sch` = CACHE_SCHEDULES
# (readRDS + as.Date(gameday)), NOT pre-filtered to completed games (this function does that
# filtering itself, exactly as the original inline code did); `fatigue` = CACHE_FATIGUE_METRICS
# (readRDS, no transform); `season` = single integer season to grade (e.g. CURRENT_SEASON).
#
# Returns list(per_game, by_week, overall_accuracy, overall_brier, overall_logloss) — the
# proposed shape from GitHub issue #2, used by the planned accuracy_tracker.R (issue #5).
# ------------------------------------------------------------------------------------------
grade_walkforward_games <- function(epa, sch, fatigue, season) {
  completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
  avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

  games <- build_walkforward_games(epa, completed, calibration_seasons = season, avg_plays_per_game)

  if (nrow(games) == 0) {
    return(list(
      per_game = games, by_week = data.frame(), overall_accuracy = NA_real_,
      overall_brier = NA_real_, overall_logloss = NA_real_
    ))
  }

  # QB-backup flags (as-of, no lookahead — get_qb_starter_table()/compute_qb_backup_flags() only
  # use each team's OWN starts strictly before the week in question, per tools/qb_injury_
  # features.R's own header).
  starter_tbl <- get_qb_starter_table(MODERN_ERA_START_SEASON:season)
  qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
  games <- games |>
    left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
    left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

  imp_h <- american_to_prob(games$home_ml)
  imp_a <- american_to_prob(games$away_ml)
  games$market_prob <- ifelse(is.na(games$home_ml) | is.na(games$away_ml), NA_real_, imp_h / (imp_h + imp_a))

  # Elo run sequentially across full history THROUGH `season` (unlike model_backtest_harness.R's
  # historical-calibration run, which stops at season - 1 on purpose) so its sequential state is
  # properly warmed up including this season's own completed weeks.
  # NOTE: `.env$season` disambiguates the function argument from sch's own `season` column inside
  # this data-masked filter() — without it, `season <= season` would silently compare the column
  # to itself instead of to the function argument.
  elo_full_history <- sch |>
    filter(!is.na(home_score), !is.na(away_score),
           season >= MODERN_ERA_START_SEASON, season <= .env$season)
  elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
    select(game_id, elo_margin_pts, fatigue_adj)
  games <- games |> left_join(elo_results, by = "game_id")

  blend_with_market <- function(model_prob, market_prob, weight) {
    ifelse(is.na(market_prob), model_prob, weight * market_prob + (1 - weight) * model_prob)
  }

  home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
  away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))

  ridge_margin <- predict_ridge_massey_walkforward(games) -
    QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj
  elo_margin <- games$elo_margin_pts + games$fatigue_adj -
    QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj

  ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
  elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, MARKET_BLEND_WEIGHT)
  games$home_win_prob_prod <- 0.5 * ridge_prob + 0.5 * elo_prob

  games <- games |>
    mutate(
      predicted_home_win = home_win_prob_prod > 0.5,
      correct = as.integer(predicted_home_win == (home_win == 1L)),
      home_full = NFL_TEAMS[home_team],
      away_full = NFL_TEAMS[away_team],
      actual_winner = ifelse(home_win == 1, home_full, away_full),
      predicted_winner = ifelse(predicted_home_win, home_full, away_full)
    )

  per_game <- games |>
    arrange(week, desc(home_win_prob_prod)) |>
    select(week, away_full, home_full, home_win_prob_prod, predicted_winner, actual_winner, correct, home_margin)

  by_week <- games |>
    group_by(week) |>
    summarise(
      n = dplyr::n(),
      accuracy = mean(correct),
      brier = mean((home_win_prob_prod - home_win)^2),
      .groups = "drop"
    )

  overall_accuracy <- mean(games$correct)
  overall_brier <- mean((games$home_win_prob_prod - games$home_win)^2)
  overall_logloss <- {
    p <- pmin(pmax(games$home_win_prob_prod, 1e-6), 1 - 1e-6)
    -mean(games$home_win * log(p) + (1 - games$home_win) * log(1 - p))
  }

  list(
    per_game = per_game, by_week = by_week, overall_accuracy = overall_accuracy,
    overall_brier = overall_brier, overall_logloss = overall_logloss
  )
}
