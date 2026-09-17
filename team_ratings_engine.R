# ==============================================================================
# Team Ratings & Matchup Projection Engine (NFL)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/team_ratings_engine.R
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
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "team_ratings_engine.R"

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
    completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

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

    projected_rows <- vector("list", nrow(upcoming))
    n_skipped <- 0L

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

      projected_margin <- (home_rating - away_rating) + NFL_HCA
      home_win_prob    <- pnorm(projected_margin / NFL_MARGIN_SIGMA)

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
