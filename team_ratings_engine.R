# ==============================================================================
# Team Ratings & Matchup Projection Engine (NFL)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/team_ratings_engine.R
#
# Phase 2, Task P2-B (docs/task_assignments_phase2.md). First real consumer of
# NFL_HCA and NFL_MARGIN_SIGMA (per that doc's Interface Contracts table). Reads
# epa_metrics_engine.R's output (CACHE_EPA_METRICS - a per-team-per-game table
# with a rolling trailing off_epa_per_play/def_epa_per_play_allowed already
# computed) plus CACHE_SCHEDULES, and produces:
#   1. cache/team_ratings.rds        - one row per team: a power rating derived
#      from rolling EPA, plus a Pythagorean-expectation win% as a COMPARISON
#      column only (see formula notes below).
#   2. cache/projected_matchups.rds  - one row per upcoming (unplayed) scheduled
#      game: projected point margin (home - away) and home win probability.
#
# Per this repo's CLAUDE.md ("Process / conventions") this script does NOT
# auto-run on source via a `sys.nframe() == 0` footer. The sole callable is
# run_team_ratings(), invoked explicitly by run_full_pipeline.R's run_stage().
#
# Live-verified column names (readRDS() run 2026-09-16 against the real caches):
#   CACHE_EPA_METRICS (13,030 team-game rows, 32 teams): season, game_id,
#   game_date, week, team, off_epa_per_play, off_success_rate, off_cpoe,
#   n_off_plays, def_epa_per_play_allowed, def_success_rate_allowed,
#   n_def_plays, off_epa_per_play_roll, def_epa_per_play_allowed_roll,
#   off_success_rate_roll, def_success_rate_allowed_roll, off_cpoe_roll,
#   games_in_window. Ordered by team, game_date, week (epa_metrics_engine.R's
#   own arrange()) - the LAST row per team is its most-recent rolling value.
#
#   CACHE_SCHEDULES (6,771 rows): game_id, season, game_type, week, gameday,
#   weekday, gametime, away_team, away_score, home_team, home_score, location,
#   result, total, overtime, ... An upcoming/unplayed game is one where
#   home_score and away_score are both NA (confirmed live: 2026 season's
#   later weeks carry NA score columns while game_id/teams/week are already
#   populated from the published schedule).
#
# ------------------------------------------------------------------------------------------
# RATING FORMULA (explain-in-header per task instructions):
#
# For each team, take its single most-recent rolling trailing value of
# off_epa_per_play_roll and def_epa_per_play_allowed_roll from CACHE_EPA_METRICS
# (epa_metrics_engine.R already handles partial-season / short-history rolling
# windows on its end - we just consume its latest already-smoothed value).
#
# net_epa_per_play = (off_epa_per_play_roll - league_avg_off_epa_per_play)
#                   - (def_epa_per_play_allowed_roll - league_avg_def_epa_allowed)
#
# i.e. how much better than average a team's offense is per play, minus how
# much worse than average its defense is at preventing opponent EPA per play
# (a team that ALLOWS more EPA/play than league average gets a negative
# contribution here, correctly penalizing bad defense).
#
# EPA/play is already denominated in expected-points units per play, so to turn
# a per-play differential into a projected POINT MARGIN for a full game we
# multiply by the league's empirical average offensive plays per team-game
# (computed live from CACHE_EPA_METRICS's n_off_plays column, NOT hardcoded -
# see avg_plays_per_game below). This is a standard EPA/play -> point-margin
# scaling approximation (summing per-play EPA over a game's plays approximates
# that team's scoring margin contribution); it has not been locally
# back-tested against actual final margins in this repo, so treat the
# resulting `power_rating` as a reasonable Phase 2 starting signal, not a
# validated point-spread model.
#
# rating_points = net_epa_per_play * avg_plays_per_game
#
# Projected margin for a scheduled game (home perspective):
#   projected_margin = (home_rating_points - away_rating_points) + NFL_HCA
# Home win probability, per config.R's own comment on NFL_MARGIN_SIGMA
# (empirically derived sd(home_score - away_score) - exactly the pnorm() use
# case that constant exists for):
#   home_win_prob = pnorm(projected_margin / NFL_MARGIN_SIGMA)
#
# ------------------------------------------------------------------------------------------
# RATING SHRINKAGE TOWARD A PRIOR-SEASON-INFORMED PRIOR (Phase 8, task P8-A):
#
# Early in a season, `current_raw_rating` above is computed from a team's single most-recent
# EPA row, which with only 1-2 real games played is extremely noisy (this is what produced
# 93%+ win probabilities and +224% EV figures against real Week 2 2026 market odds - see
# docs/task_assignments_phase7.md). To fix this, each team's FINAL power rating blends
# `current_raw_rating` with a `prior_season_rating` (that team's last EPA row from the most
# recent season strictly before CURRENT_SEASON, run through the EXACT SAME
# compute_power_rating_points() formula below - not a second, subtly-different formula),
# weighted by how many real CURRENT_SEASON games (completed, from CACHE_SCHEDULES) that team
# has actually played:
#
#   weight       <- games_played / (games_played + RATING_SHRINKAGE_GAMES_K)
#   power_rating <- weight * current_raw_rating + (1 - weight) * prior_season_rating
#
# games_played = 0 -> weight = 0 -> pure prior-season rating. As games_played grows, weight
# asymptotically approaches 1 (pure current-season signal). RATING_SHRINKAGE_GAMES_K lives in
# config.R (narrow documented exception, same pattern as CACHE_TEAM_RATINGS etc.) - see that
# constant's comment for why its value was chosen and that it is NOT yet backtested.
#
# If a team genuinely has no prior-season EPA history at all, prior_season_rating falls back to
# 0 (league average). Per CLAUDE.md, all 32 current NFL_TEAMS have real history back to at least
# 2002 in this repo's data, so this fallback is expected to essentially NEVER actually trigger -
# if a log_warn below ever fires for this, that is worth investigating as a real data gap, not
# something to silently accept.
# ------------------------------------------------------------------------------------------
# PYTHAGOREAN-EXPECTATION COMPARISON COLUMN (NOT the primary model):
# win_pct_pyth = PF^k / (PF^k + PA^k), PF/PA = each team's total points
# scored/allowed across its completed CACHE_SCHEDULES games this season.
# k = 2.37 is cited in public NFL sabermetrics research as a commonly-used
# exponent starting point (see e.g. Football Outsiders-style Pythagorean
# write-ups) - it has NOT been locally validated against this repo's own data.
# docs/NFL_REPLICATION_PLAN.md §5 cites a 2025 peer-reviewed comparison
# (Weirich et al., Frontiers in Sports and Active Living) showing ML/EPA-style
# approaches outperform a plain Pythagorean baseline; that paper's game-level
# result has not been re-run against this repo's own data, so win_pct_pyth is
# retained here strictly as a comparison/sanity column, never blended into
# power_rating or the projected-margin/win-probability outputs above.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(nflreadr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "team_ratings_engine.R"

# Model inputs & features:
# QB-injury adjustments (tools/qb_injury_features.R), historical walkforward
# games (tools/backtest_common.R), Ridge-Massey model (tools/ridge_massey_model.R),
# and Elo model (tools/elo_model.R).
# Note: Market odds blending has been decommissioned (Issue #8). Predictions are
# 100% endogenous and market-independent.
source("tools/qb_injury_features.R")
source("tools/backtest_common.R")     # -> build_walkforward_games() (Phase 2 training data)
source("tools/ridge_massey_model.R")  # -> fit_ridge_massey()/build_ridge_features() (Phase 2)
source("tools/elo_model.R")           # -> run_elo_walkforward()/project_elo_rating() (Phase 3)

# ------------------------------------------------------------------------------------------
# get_live_qb_backup_flags() - live analog of tools/qb_injury_features.R's walk-forward
# definition. NOTE A REAL DATA QUIRK, VERIFIED LIVE 2026-09-17 (not in CLAUDE.md yet - add it
# there if this file is revisited): nflreadr::load_depth_charts() returns TWO DIFFERENT
# SCHEMAS depending on season, and the cutoff is NOT simply "current season vs. history" -
# checked live season-by-season: 2002-2024 use the nflverse weekly-release shape (season/week/
# club_code/depth_team/game_type/position - what tools/qb_injury_features.R's
# get_qb_starter_table() expects and tools/derive_qb_injury_penalty.R's backtest actually used),
# while 2025 AND 2026 (i.e. CURRENT_SEASON - 1 too, not just CURRENT_SEASON) already use a live
# ESPN-scrape shape instead (columns: dt (a timestamp string, NOT season/week), team, gsis_id,
# pos_abb, pos_rank - no game_type/depth_team/position/season/week columns at all). This means
# get_qb_starter_table() (the historical/backtest function) cannot be reused for EITHER of the
# two seasons this live function needs - both calls below query the new schema directly.
#
#   1. "Established" starter: mode gsis_id at pos_abb=="QB" & pos_rank==1 across ALL of
#      CURRENT_SEASON - 1's snapshots (that team's most common 2025 starter).
#   2. "Current" starter: the single most recent `dt` snapshot's pos_rank==1 QB for
#      CURRENT_SEASON - that team's actual starter right now.
# A mismatch => qb_backup_started = TRUE. Returns a named logical vector (by NFL_TEAMS
# abbreviation), NA for any team with no usable depth-chart data in either call.
# ------------------------------------------------------------------------------------------
get_live_qb_backup_flags <- function() {
  fetch_qb_rows <- function(season) {
    tryCatch(as.data.frame(nflreadr::load_depth_charts(seasons = season)), error = function(e) {
      log_warn(sprintf("get_live_qb_backup_flags(): load_depth_charts(%d) failed.", season),
               call = "get_live_qb_backup_flags()", error_message = conditionMessage(e))
      NULL
    })
  }

  established_raw <- fetch_qb_rows(CURRENT_SEASON - 1L)
  current_raw      <- fetch_qb_rows(CURRENT_SEASON)

  if (is.null(established_raw) || nrow(established_raw) == 0 ||
      is.null(current_raw) || nrow(current_raw) == 0) {
    return(setNames(rep(NA, length(names(NFL_TEAMS))), names(NFL_TEAMS)))
  }

  established_mode <- established_raw |>
    dplyr::filter(pos_abb == "QB", pos_rank == 1) |>
    dplyr::count(team, gsis_id, sort = TRUE) |>
    dplyr::group_by(team) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup()
  established_lu <- setNames(established_mode$gsis_id, established_mode$team)

  current_starter <- current_raw |>
    dplyr::filter(pos_abb == "QB", pos_rank == 1) |>
    dplyr::arrange(team, dplyr::desc(dt)) |>
    dplyr::group_by(team) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup()
  current_lu <- setNames(current_starter$gsis_id, current_starter$team)

  lookup <- setNames(rep(NA, length(names(NFL_TEAMS))), names(NFL_TEAMS))
  for (tm in names(NFL_TEAMS)) {
    est <- established_lu[[tm]]
    cur <- current_lu[[tm]]
    if (!is.null(est) && !is.null(cur) && !is.na(est) && !is.na(cur)) {
      lookup[tm] <- (cur != est)
    }
  }
  lookup
}

# Pythagorean exponent - see header comment. Not a config.R modeling constant
# (it's local to this one baseline/comparison calculation, not shared by any
# other script), so it is kept as a local constant here rather than added to
# config.R.
.PYTHAGOREAN_EXPONENT <- 2.37

# ------------------------------------------------------------------------------------------
# compute_power_rating_points()
#
# The SINGLE formula for turning a team's rolling EPA/play values into a point-margin-scale
# power rating (see header comment's RATING FORMULA section). Extracted into a function so
# Phase 8's prior-season rating computation reuses the EXACT SAME math as the current-season
# rating - never a second, independently-typed copy of this formula (the class of drift bug
# this repo's CLAUDE.md warns about).
# ------------------------------------------------------------------------------------------
compute_power_rating_points <- function(off_epa_per_play_roll, def_epa_per_play_allowed_roll,
                                         league_avg_off, league_avg_def, avg_plays_per_game) {
  net_epa_per_play <- (off_epa_per_play_roll - league_avg_off) -
                       (def_epa_per_play_allowed_roll - league_avg_def)
  net_epa_per_play * avg_plays_per_game
}

# ------------------------------------------------------------------------------------------
# run_team_ratings()
#
# Sole exposed entry point (per docs/task_assignments_phase2.md's Interface Contracts table).
# No required args. Reads CACHE_EPA_METRICS + CACHE_SCHEDULES (never writes either - owned by
# epa_metrics_engine.R / Phase 1 ingestion respectively). Writes cache/team_ratings.rds and
# cache/projected_matchups.rds via the new CACHE_TEAM_RATINGS / CACHE_PROJECTED_MATCHUPS
# constants (added to config.R as a narrow documented exception - see that file's comment
# above them). Returns TRUE on success, FALSE on failure (mirrors run_epa_metrics()'s
# non-stop()ping contract for run_full_pipeline.R's run_stage()).
# ------------------------------------------------------------------------------------------
run_team_ratings <- function() {
  log_info("Starting team ratings engine...")

  result <- tryCatch({
    if (!file.exists(CACHE_EPA_METRICS)) {
      log_error("CACHE_EPA_METRICS does not exist - run_epa_metrics() must run before run_team_ratings().",
                call = "run_team_ratings()")
      return(FALSE)
    }
    if (!file.exists(CACHE_SCHEDULES)) {
      log_error("CACHE_SCHEDULES does not exist - ingestion must run before run_team_ratings().",
                call = "run_team_ratings()")
      return(FALSE)
    }

    epa <- readRDS(CACHE_EPA_METRICS)
    sch <- readRDS(CACHE_SCHEDULES)

    if (nrow(epa) == 0) {
      log_error("CACHE_EPA_METRICS has zero rows; aborting.", call = "run_team_ratings()")
      return(FALSE)
    }

    # ---- Latest rolling EPA row per team (data already ordered team/game_date/week) ----
    latest_epa <- epa |>
      arrange(team, game_date, week) |>
      group_by(team) |>
      slice_tail(n = 1) |>
      ungroup() |>
      select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll, games_in_window)

    n_teams_rated <- nrow(latest_epa)
    if (n_teams_rated < NFL_TEAM_COUNT) {
      missing_teams <- setdiff(names(NFL_TEAMS), latest_epa$team)
      log_warn(sprintf("Only %d of %d NFL_TEAMS have EPA metrics rows (missing: %s) - those teams will be skipped for any matchup involving them.",
                        n_teams_rated, NFL_TEAM_COUNT, paste(missing_teams, collapse = ", ")),
               call = "run_team_ratings()")
    }

    # League-average plays per team-game, empirically derived from this run's own data (not
    # hardcoded) - used only to scale an EPA/play differential into an approximate point margin.
    avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)
    if (!is.finite(avg_plays_per_game) || avg_plays_per_game <= 0) {
      log_warn("avg_plays_per_game was non-finite/non-positive; falling back to 65 plays/game (rough NFL norm).",
               call = "run_team_ratings()")
      avg_plays_per_game <- 65
    }

    league_avg_off  <- mean(latest_epa$off_epa_per_play_roll, na.rm = TRUE)
    league_avg_def  <- mean(latest_epa$def_epa_per_play_allowed_roll, na.rm = TRUE)

    latest_epa <- latest_epa |>
      mutate(
        current_raw_rating = compute_power_rating_points(
          off_epa_per_play_roll, def_epa_per_play_allowed_roll,
          league_avg_off, league_avg_def, avg_plays_per_game
        )
      )

    # ---- Phase 8 (P8-A): real current-season games_played, from CACHE_SCHEDULES ----
    # Completed = both score columns non-NA (see header comment's live-verified column notes).
    # Restricted to season == CURRENT_SEASON only - this is a deliberately different (and
    # deliberately correctly-scoped) count from the Pythagorean section's internal game count
    # below, which is renamed .pyth_games_played to avoid colliding with this column.
    completed_current <- sch |>
      filter(season == CURRENT_SEASON, !is.na(home_score), !is.na(away_score))

    games_played_current <- bind_rows(
      completed_current |> transmute(team = home_team),
      completed_current |> transmute(team = away_team)
    ) |>
      group_by(team) |>
      summarise(games_played = dplyr::n(), .groups = "drop")

    all_teams_df <- data.frame(team = names(NFL_TEAMS), stringsAsFactors = FALSE)
    games_played_current <- all_teams_df |>
      left_join(games_played_current, by = "team") |>
      mutate(games_played = ifelse(is.na(games_played), 0L, games_played))

    # ---- Phase 8 (P8-A): prior-season-final rating, same formula as current_raw_rating ----
    prior_seasons_available <- unique(epa$season[epa$season < CURRENT_SEASON])
    if (length(prior_seasons_available) == 0) {
      log_warn("No prior-season (< CURRENT_SEASON) rows exist in CACHE_EPA_METRICS at all - every team's prior_season_rating will fall back to 0 (league average). This should essentially never happen per CLAUDE.md (all 32 NFL_TEAMS have history back to at least 2002) - investigate if seen.",
               call = "run_team_ratings()")
      prior_epa_ratings <- data.frame(team = character(0), prior_season_rating = numeric(0))
    } else {
      most_recent_prior_season <- max(prior_seasons_available)

      prior_epa <- epa |>
        filter(season == most_recent_prior_season) |>
        arrange(team, game_date, week) |>
        group_by(team) |>
        slice_tail(n = 1) |>
        ungroup() |>
        select(team, off_epa_per_play_roll, def_epa_per_play_allowed_roll)

      league_avg_off_prior <- mean(prior_epa$off_epa_per_play_roll, na.rm = TRUE)
      league_avg_def_prior <- mean(prior_epa$def_epa_per_play_allowed_roll, na.rm = TRUE)

      prior_epa_ratings <- prior_epa |>
        mutate(
          prior_season_rating = compute_power_rating_points(
            off_epa_per_play_roll, def_epa_per_play_allowed_roll,
            league_avg_off_prior, league_avg_def_prior, avg_plays_per_game
          )
        ) |>
        select(team, prior_season_rating)
    }

    teams_missing_prior <- setdiff(names(NFL_TEAMS), prior_epa_ratings$team)
    if (length(teams_missing_prior) > 0) {
      log_warn(sprintf("%d team(s) have NO prior-season EPA history at all (falling back to prior_season_rating = 0 / league average): %s. Per CLAUDE.md this should essentially never trigger for a current NFL_TEAMS abbreviation - investigate if seen.",
                        length(teams_missing_prior), paste(teams_missing_prior, collapse = ", ")),
               call = "run_team_ratings()")
    }

    # ---- Blend: weight <- games_played / (games_played + RATING_SHRINKAGE_GAMES_K) ----
    latest_epa <- latest_epa |>
      left_join(games_played_current, by = "team") |>
      left_join(prior_epa_ratings, by = "team") |>
      mutate(
        games_played        = ifelse(is.na(games_played), 0L, games_played),
        prior_season_rating = ifelse(is.na(prior_season_rating), 0, prior_season_rating),
        shrinkage_weight     = games_played / (games_played + RATING_SHRINKAGE_GAMES_K),
        power_rating         = shrinkage_weight * current_raw_rating +
                                (1 - shrinkage_weight) * prior_season_rating
      )

    # ---- Pythagorean-expectation comparison column, from completed CACHE_SCHEDULES games ----
    # NOTE: intentionally unchanged from the pre-Phase-8 implementation (still all-time-schedule-
    # cache-scoped and comparison-only per the header comment) - its internal game-count column
    # is renamed .pyth_games_played below purely to avoid a name collision with the new,
    # correctly current-season-scoped `games_played` column above (which would otherwise silently
    # overwrite one or the other on the join and double-count/misreport one of them).
    completed <- sch |> filter(season == CURRENT_SEASON, !is.na(home_score), !is.na(away_score))

    pf_pa <- bind_rows(
      completed |> transmute(team = home_team, pf = home_score, pa = away_score),
      completed |> transmute(team = away_team, pf = away_score, pa = home_score)
    ) |>
      group_by(team) |>
      summarise(
        points_for        = sum(pf, na.rm = TRUE),
        points_against     = sum(pa, na.rm = TRUE),
        .pyth_games_played = dplyr::n(),
        .groups = "drop"
      ) |>
      mutate(
        win_pct_pyth = ifelse(
          points_for > 0 | points_against > 0,
          points_for^.PYTHAGOREAN_EXPONENT /
            (points_for^.PYTHAGOREAN_EXPONENT + points_against^.PYTHAGOREAN_EXPONENT),
          NA_real_
        )
      )

    team_ratings <- latest_epa |>
      full_join(pf_pa, by = "team") |>
      arrange(desc(power_rating))

    n_missing_pyth <- sum(is.na(team_ratings$win_pct_pyth))
    if (n_missing_pyth > 0) {
      log_warn(sprintf("%d team(s) have no completed CACHE_SCHEDULES games yet - win_pct_pyth left NA for them.",
                        n_missing_pyth), call = "run_team_ratings()")
    }

    saveRDS(team_ratings, CACHE_TEAM_RATINGS)
    log_info(sprintf("Wrote %d team power ratings to CACHE_TEAM_RATINGS.", nrow(team_ratings)),
             call = "run_team_ratings()", rows = nrow(team_ratings), out_path = CACHE_TEAM_RATINGS)

    # ---- Projected matchups: upcoming (unplayed) games only ----
    upcoming <- sch |> filter(is.na(home_score), is.na(away_score))
    log_info(sprintf("Found %d upcoming (unplayed) scheduled games in CACHE_SCHEDULES.", nrow(upcoming)),
             call = "run_team_ratings()")

    rating_lookup <- setNames(team_ratings$power_rating, team_ratings$team)
    # Phase 8 (P8-A): games_played lookup, propagated into projected_matchups so the P8-B
    # staking-gate agent can build its minimum-sample gate without re-deriving this count itself.
    games_played_lookup <- setNames(team_ratings$games_played, team_ratings$team)
    # Phase 2 (model-quality remediation): raw current-season rating (pre-shrinkage) and
    # prior-season rating lookups, needed as the ridge model's own input features - NOT the
    # already-blended power_rating column above (ridge learns its own blend, see below).
    raw_lookup   <- setNames(team_ratings$current_raw_rating, team_ratings$team)
    prior_lookup <- setNames(team_ratings$prior_season_rating, team_ratings$team)

    # ---- Phase 2 (model-quality remediation): ridge-regularized Massey rating ----
    # Replaces the hand-tuned games_played/(games_played+K) shrinkage blend (config.R's
    # RATING_SHRINKAGE_GAMES_K) with a ridge regression (tools/ridge_massey_model.R) that
    # LEARNS how to combine current-season vs. prior-season rating signal, fit fresh each
    # pipeline run on all available historical walk-forward games (never a second, drifting
    # copy of the training data - reuses build_walkforward_games() from tools/backtest_common.R,
    # the same builder tools/model_backtest_harness.R used to validate this candidate beat the
    # production baseline on Brier/log-loss/calibration - see docs/HANDOFF.md). Falls back to
    # the original K-blend formula (compute_power_rating_points()'s caller-level blend, inlined
    # below as ridge_fit <- NULL) if the historical table can't be built or the fit fails - never
    # silently skip prediction for a pipeline run.
    ridge_fit <- tryCatch({
      hist_seasons <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)
      hist_completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
      hist_games <- build_walkforward_games(epa |> mutate(game_date = as.Date(game_date)),
                                             hist_completed |> mutate(gameday = as.Date(gameday)),
                                             hist_seasons, avg_plays_per_game)
      if (nrow(hist_games) < 100) stop("insufficient historical walk-forward games for a ridge fit")
      fit_ridge_massey(hist_games)
    }, error = function(e) {
      log_warn("Ridge Massey fit failed - falling back to the RATING_SHRINKAGE_GAMES_K blend formula for this run.",
               call = "run_team_ratings()", error_message = conditionMessage(e))
      NULL
    })

    # ---- Phase 3 (model-quality remediation): live Elo state ----
    # A best-effort second, structurally-different rating to average with ridge into a 50/50
    # ensemble (docs/HANDOFF.md - Phase 3's exploratory ensemble_ridge_elo candidate beat pure
    # ridge on calibration and partially recovered the Sharpe regression pure Elo alone showed).
    # NOTE: unlike the backtest candidate, this live ensemble does NOT fold fatigue into Elo's
    # own margin - fatigue stays applied exactly once, downstream in market_odds_engine.R (see
    # below), to avoid double-counting it via two different code paths. fatigue_engine.R (stage
    # 6) runs AFTER this stage (5), so CACHE_FATIGUE_METRICS may be from a PRIOR pipeline run
    # here if it exists at all - a real, accepted staleness/ordering tradeoff (same class the
    # C-2 staleness check already tolerates elsewhere in this repo), not a correctness bug -
    # only used for warming up Elo's historical state, not for this run's live prediction.
    elo_live <- tryCatch({
      elo_hist <- sch |> filter(!is.na(home_score), !is.na(away_score),
                                 season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON) |>
        mutate(gameday = as.Date(gameday))
      fatigue_for_elo <- if (file.exists(CACHE_FATIGUE_METRICS)) {
        readRDS(CACHE_FATIGUE_METRICS)
      } else {
        data.frame(game_id = character(0), team = character(0), fatigue_drag_pts = numeric(0))
      }
      if (nrow(elo_hist) < 100) stop("insufficient historical games for a live Elo state")
      run_elo_walkforward(elo_hist, fatigue_for_elo, ELO_K_FACTOR, return_final_state = TRUE)
    }, error = function(e) {
      log_warn("Live Elo state computation failed - ensemble will use ridge only for this run.",
               call = "run_team_ratings()", error_message = conditionMessage(e))
      NULL
    })

    get_team_elo <- function(team, season) {
      if (is.null(elo_live)) return(NA_real_)
      r <- elo_live$final_elo[team]
      s <- elo_live$final_season[team]
      if (is.na(r) || is.na(s)) return(NA_real_)
      project_elo_rating(unname(r), unname(s), season)
    }

    # QB-injury adjustment lookup table for upcoming games
    qb_backup_lookup <- get_live_qb_backup_flags()

    projected_rows <- vector("list", nrow(upcoming))
    n_skipped <- 0L
    n_qb_adjusted <- 0L
    n_elo_ensembled <- 0L

    for (i in seq_len(nrow(upcoming))) {
      g <- upcoming[i, ]
      home <- g$home_team
      away <- g$away_team

      home_rating <- rating_lookup[[home]]
      away_rating <- rating_lookup[[away]]

      if (is.null(home_rating) || is.null(away_rating) ||
          length(home_rating) == 0 || length(away_rating) == 0 ||
          is.na(home_rating) || is.na(away_rating)) {
        log_warn(sprintf("Skipping matchup %s: missing power rating for home=%s or away=%s (e.g. bye week / no EPA history yet).",
                          g$game_id, home, away), call = "run_team_ratings()")
        n_skipped <- n_skipped + 1L
        next
      }

      home_games_played <- games_played_lookup[[home]]
      away_games_played <- games_played_lookup[[away]]
      if (is.null(home_games_played) || length(home_games_played) == 0) home_games_played <- NA_integer_
      if (is.null(away_games_played) || length(away_games_played) == 0) away_games_played <- NA_integer_

      if (!is.null(ridge_fit)) {
        feat <- build_ridge_features(data.frame(
          home_raw = raw_lookup[[home]], away_raw = raw_lookup[[away]],
          home_prior = prior_lookup[[home]], away_prior = prior_lookup[[away]],
          home_gp = ifelse(is.na(home_games_played), 0L, home_games_played),
          away_gp = ifelse(is.na(away_games_played), 0L, away_games_played)
        ))
        ridge_margin <- as.numeric(predict(ridge_fit, newx = feat, s = "lambda.min"))
      } else {
        ridge_margin <- (home_rating - away_rating) + NFL_HCA
      }

      # QB-injury adjustment (config.R's QB_INJURY_RATING_PENALTY_PTS, empirically derived via
      # tools/derive_qb_injury_penalty.R). NA flag (unknown) => zero adjustment, same convention
      # as that derivation script's own handling of games with no usable depth-chart data.
      home_backup <- isTRUE(qb_backup_lookup[[home]])
      away_backup <- isTRUE(qb_backup_lookup[[away]])
      if (home_backup || away_backup) n_qb_adjusted <- n_qb_adjusted + 1L
      qb_shift <- -QB_INJURY_RATING_PENALTY_PTS * home_backup + QB_INJURY_RATING_PENALTY_PTS * away_backup
      ridge_margin <- ridge_margin + qb_shift
      ridge_model_prob <- pnorm(ridge_margin / NFL_MARGIN_SIGMA)

      # Phase 3: Elo's own margin (HCA baked in via ELO_HCA_POINTS, converted to point-margin
      # scale via ELO_POINTS_PER_MARGIN_PT), same QB-injury shift applied. NA if either team's
      # live Elo state is unavailable (see elo_live/get_team_elo() above) - ridge-only that game.
      home_elo_r <- get_team_elo(home, g$season)
      away_elo_r <- get_team_elo(away, g$season)
      elo_available <- !is.na(home_elo_r) && !is.na(away_elo_r)
      if (elo_available) {
        elo_diff <- (home_elo_r + ELO_HCA_POINTS) - away_elo_r
        elo_margin <- (elo_diff / ELO_POINTS_PER_MARGIN_PT) + qb_shift
        elo_model_prob <- pnorm(elo_margin / NFL_MARGIN_SIGMA)
      }

      # Pure endogenous ensemble: 50% Ridge-Massey margin + 50% Elo margin (or 100% Ridge if Elo unavailable)
      # Win probability computed directly via normal CDF: pnorm(projected_margin / NFL_MARGIN_SIGMA)
      if (elo_available) {
        projected_margin <- 0.5 * ridge_margin + 0.5 * elo_margin
        home_win_prob <- pnorm(projected_margin / NFL_MARGIN_SIGMA)
        n_elo_ensembled <- n_elo_ensembled + 1L
      } else {
        projected_margin <- ridge_margin
        home_win_prob <- ridge_model_prob
      }

      projected_rows[[i]] <- data.frame(
        game_id            = g$game_id,
        season             = g$season,
        week               = g$week,
        home_team          = home,
        away_team          = away,
        home_power_rating  = home_rating,
        away_power_rating  = away_rating,
        home_games_played  = home_games_played,
        away_games_played  = away_games_played,
        projected_margin   = projected_margin,
        home_win_prob      = home_win_prob,
        stringsAsFactors = FALSE
      )
    }

    projected_matchups <- bind_rows(projected_rows)
    log_info(sprintf("Adjustments applied: %d games with a QB-backup adjustment, %d games ensembled with a live Elo rating.",
                      n_qb_adjusted, n_elo_ensembled), call = "run_team_ratings()")

    if (n_skipped > 0) {
      log_warn(sprintf("Skipped %d of %d upcoming games due to missing team ratings.",
                        n_skipped, nrow(upcoming)), call = "run_team_ratings()")
    }

    saveRDS(projected_matchups, CACHE_PROJECTED_MATCHUPS)
    log_info(sprintf("Wrote %d projected matchups to CACHE_PROJECTED_MATCHUPS.", nrow(projected_matchups)),
             call = "run_team_ratings()", rows = nrow(projected_matchups), out_path = CACHE_PROJECTED_MATCHUPS)

    TRUE
  }, error = function(e) {
    log_error("Team ratings engine failed.", condition = e, call = "run_team_ratings()")
    FALSE
  })

  invisible(isTRUE(result))
}
