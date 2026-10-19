# ==============================================================================
# EPA / CPOE Metrics Engine (NFL)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/epa_metrics_engine.R
#
# Phase 2, Task P2-A (docs/task_assignments_phase2.md). First real consumer of
# ROLLING_WINDOW_SIZE. Aggregates nflreadr::load_pbp()'s play-level EPA/CPOE
# (already shipped by nflreadr's own pbp release - no separate nflfastR EPA
# model call is needed, per docs/NFL_REPLICATION_PLAN.md §5) into per-team-
# per-game offensive/defensive efficiency, then a rolling trailing average per
# team ordered by game date.
#
# Per this repo's CLAUDE.md ("Process / conventions") this script does NOT
# auto-run on source via a `sys.nframe() == 0` footer. The sole callable is
# run_epa_metrics(), invoked explicitly by run_full_pipeline.R's run_stage().
#
# Live-verified column names (readRDS(CACHE_PBP); names()/str() run 2026-09-16
# against the real cache written by daily_ingest.R, not assumed from memory):
# epa, posteam, defteam, success, cpoe, game_id, game_date, season, week,
# play_type, pass, season_type. `cpoe` is NA on every non-charted-pass-target
# play (confirmed live: cpoe non-NA count == 359,596, entirely a subset of
# pass == 1 rows, 0 non-NA cpoe rows where pass == 0) - handled below via
# na.rm-based averaging rather than treating missing CPOE as 0.
#
# SITUATIONAL FEATURES (added 2026-09-17, Phase 4 model-quality remediation): daily_ingest.R's
# .PBP_CACHE_COLUMNS was widened to also carry down, ydstogo, yardline_100, qtr,
# score_differential, yards_gained, pass_oe - previously cached (down/ydstogo/yardline_100/qtr)
# or newly added (score_differential/yards_gained/pass_oe) specifically for the situational
# splits below, per config.R's "Situational EPA Feature Thresholds" section (RED_ZONE_YARDLINE_
# MAX, EXPLOSIVE_PASS_YARDS, EXPLOSIVE_RUSH_YARDS, MONEY_DOWN_MIN, GARBAGE_TIME_ABS_SCORE_DIFF -
# never re-typed as literals here, sourced from config.R like every other modeling constant).
# These are ADDITIVE to the existing full-game off_epa_per_play/def_epa_per_play_allowed
# aggregates above (unchanged), not a replacement - team_ratings_engine.R's rating formula still
# consumes only the full-game columns; the situational columns are for a future candidate model
# (tools/model_backtest_harness.R) to evaluate, not yet wired into the live rating formula.
#
# DATA QUIRK, VERIFIED LIVE 2026-09-17 (add to CLAUDE.md if this file is revisited): nflverse's
# `pass_oe` (pass rate over expected, used for off_proe/def_proe_allowed below) is 100% NA for
# every play in seasons 2002-2005 - live-checked against the real CACHE_PBP: NA rate is exactly
# 1.0 for 2002-2005, then a stable ~26% (the normal non-dropback-play NA rate) from 2006 onward.
# This means off_proe_roll/def_proe_allowed_roll are structurally NA for any team-game whose
# entire trailing ROLLING_WINDOW_SIZE window falls in 2002-2005 (~16% of all rows in the full
# 2002-2026 history) - .safe_mean()/.roll_mean_trailing()'s na.rm handling already degrades this
# gracefully to NA rather than a wrong 0, but any consumer should expect real missingness in early
# seasons, not treat a NA PROE column as a bug.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "epa_metrics_engine.R"

# ------------------------------------------------------------------------------------------
# Internal helper: trailing rolling mean over a numeric vector already ordered chronologically
# for a single team, window size = ROLLING_WINDOW_SIZE (never hardcoded here - see config.R).
#
# Partial-window / short-history fallback (per task_assignments_phase2.md's Constraints:
# "CURRENT_SEASON's games are partial ... handle a team with fewer than ROLLING_WINDOW_SIZE
# completed games gracefully, e.g. fall back to a shorter available window or prior-season
# data, not error or silently drop the team"):
#   - Games are ordered continuously across season boundaries per team (the caller never resets
#     the sequence at a new season), so a team's early-CURRENT_SEASON games naturally pull in
#     trailing games from the END of the prior season to fill out the window rather than being
#     computed over an artificially tiny in-season-only sample.
#   - For a team's very first (ROLLING_WINDOW_SIZE - 1) games in its entire history (i.e. no
#     prior season exists to borrow from, or the pbp history literally starts there), the window
#     shrinks to whatever games are actually available (games 1..i for game i), rather than
#     producing NA or erroring. na.rm = TRUE additionally protects against any single-game NA
#     (e.g. off_cpoe when a team's game had zero charted-target pass attempts) polluting the mean.
# ------------------------------------------------------------------------------------------
.roll_mean_trailing <- function(x) {
  n <- length(x)
  vapply(seq_len(n), function(i) {
    lo <- max(1, i - ROLLING_WINDOW_SIZE + 1)
    mean(x[lo:i], na.rm = TRUE)
  }, numeric(1))
}

# ------------------------------------------------------------------------------------------
# .safe_mean(): mean(..., na.rm = TRUE) that returns NA_real_ instead of NaN when a
# per-team-per-game situational slice has zero qualifying plays (e.g. a team ran zero money-down
# plays in some unusual game) - same treatment off_cpoe already gets above, generalized so the
# situational features below don't each need their own all(is.na(...)) guard.
# ------------------------------------------------------------------------------------------
.safe_mean <- function(x) {
  if (length(x) == 0 || all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
}

# ------------------------------------------------------------------------------------------
# run_epa_metrics()
#
# Sole exposed entry point (per docs/task_assignments_phase2.md's Interface Contracts table).
# No required args. Reads CACHE_PBP (never writes it - owned by daily_ingest.R), computes
# per-team-per-game offensive EPA/play, defensive EPA/play-allowed, success rate, and CPOE
# (pass plays only, NA-safe), then a ROLLING_WINDOW_SIZE-game trailing average per team ordered
# by game date. Writes the full per-team-per-game table (raw + rolling columns) to
# CACHE_EPA_METRICS so downstream consumers (team_ratings_engine.R) can pick the latest row per
# team or inspect history. Returns TRUE on success, FALSE on failure (mirrors run_daily_ingest()'s
# non-stop()ping contract for run_full_pipeline.R's run_stage()).
# ------------------------------------------------------------------------------------------
run_epa_metrics <- function() {
  log_info("Starting EPA metrics engine...")

  result <- tryCatch({
    if (!file.exists(CACHE_PBP)) {
      log_error("CACHE_PBP does not exist - run_daily_ingest() must run before run_epa_metrics().",
                call = "run_epa_metrics()")
      return(FALSE)
    }

    pbp <- readRDS(CACHE_PBP)
    log_info(sprintf("Loaded CACHE_PBP with %d rows.", nrow(pbp)), call = "run_epa_metrics()")

    # Drop plays with no real possession/defense team assigned (timeouts, end-of-quarter/half
    # marker rows, etc.) and plays with no EPA value - these carry no meaningful team signal and
    # would otherwise silently corrupt the per-team-per-game means.
    pbp <- pbp |> filter(!is.na(posteam), !is.na(defteam), !is.na(epa))

    if (nrow(pbp) == 0) {
      log_error("CACHE_PBP had zero usable rows after filtering NA posteam/defteam/epa.",
                call = "run_epa_metrics()")
      return(FALSE)
    }

    # ---- Offensive per-team-per-game aggregates ----
    off_stats <- pbp |>
      group_by(season, game_id, game_date, week, team = posteam) |>
      summarise(
        off_epa_per_play = mean(epa, na.rm = TRUE),
        off_success_rate = mean(success, na.rm = TRUE),
        # CPOE only exists on charted-target pass attempts (confirmed live - see header comment).
        # mean(..., na.rm = TRUE) averages only over plays where CPOE is actually defined; if a
        # team had literally zero charted-target pass plays in a game, off_cpoe is left NA rather
        # than silently coerced to 0 (which would wrongly imply exactly average accuracy).
        off_cpoe    = if (all(is.na(cpoe))) NA_real_ else mean(cpoe, na.rm = TRUE),
        n_off_plays = dplyr::n(),
        .groups = "drop"
      )

    # ---- Defensive per-team-per-game aggregates (EPA/success ALLOWED) ----
    def_stats <- pbp |>
      group_by(season, game_id, game_date, week, team = defteam) |>
      summarise(
        def_epa_per_play_allowed = mean(epa, na.rm = TRUE),
        def_success_rate_allowed = mean(success, na.rm = TRUE),
        n_def_plays = dplyr::n(),
        .groups = "drop"
      )

    # ---- Situational splits (see header comment) ----
    # Precomputed once on the raw pbp table (not inside summarise()) so both the offensive and
    # defensive group_by() passes below reuse the identical boolean/numeric vectors - avoids
    # retyping the same down/yardline/garbage-time logic twice with a chance to drift out of sync.
    pbp <- pbp |>
      mutate(
        .early_down     = down %in% seq_len(MONEY_DOWN_MIN - 1),
        .money_down     = down >= MONEY_DOWN_MIN,
        .redzone        = yardline_100 <= RED_ZONE_YARDLINE_MAX,
        .is_garbage_time = !is.na(qtr) & !is.na(score_differential) &
                            qtr >= 4 & abs(score_differential) > GARBAGE_TIME_ABS_SCORE_DIFF,
        .is_explosive   = !is.na(pass) & !is.na(yards_gained) &
                           ((pass == 1 & yards_gained >= EXPLOSIVE_PASS_YARDS) |
                            (pass == 0 & yards_gained >= EXPLOSIVE_RUSH_YARDS)),
        .situation_neutral_early_down = .early_down & !.is_garbage_time
      )

    off_situational <- pbp |>
      group_by(season, game_id, game_date, week, team = posteam) |>
      summarise(
        off_epa_early_down        = .safe_mean(epa[.early_down]),
        off_success_early_down    = .safe_mean(success[.early_down]),
        off_epa_money_down        = .safe_mean(epa[.money_down]),
        off_success_money_down    = .safe_mean(success[.money_down]),
        off_redzone_success_rate  = .safe_mean(success[.redzone]),
        off_explosive_rate        = .safe_mean(as.numeric(.is_explosive)),
        off_proe                  = .safe_mean(pass_oe[.situation_neutral_early_down]),
        .groups = "drop"
      )

    def_situational <- pbp |>
      group_by(season, game_id, game_date, week, team = defteam) |>
      summarise(
        def_epa_early_down_allowed       = .safe_mean(epa[.early_down]),
        def_success_early_down_allowed   = .safe_mean(success[.early_down]),
        def_epa_money_down_allowed       = .safe_mean(epa[.money_down]),
        def_success_money_down_allowed   = .safe_mean(success[.money_down]),
        def_redzone_success_rate_allowed = .safe_mean(success[.redzone]),
        def_explosive_rate_allowed       = .safe_mean(as.numeric(.is_explosive)),
        def_proe_allowed                 = .safe_mean(pass_oe[.situation_neutral_early_down]),
        .groups = "drop"
      )

    team_game <- full_join(
      off_stats, def_stats,
      by = c("season", "game_id", "game_date", "week", "team")
    ) |>
      full_join(off_situational, by = c("season", "game_id", "game_date", "week", "team")) |>
      full_join(def_situational, by = c("season", "game_id", "game_date", "week", "team")) |>
      mutate(game_date = as.Date(game_date)) |>
      arrange(team, game_date, week)

    if (nrow(team_game) == 0) {
      log_error("No team-game rows produced from CACHE_PBP; aborting.", call = "run_epa_metrics()")
      return(FALSE)
    }

    n_teams <- length(unique(team_game$team))
    log_info(sprintf("Aggregated %d team-game rows across %d teams.", nrow(team_game), n_teams),
             call = "run_epa_metrics()", rows = nrow(team_game), teams = n_teams)

    # ---- Rolling trailing average, ROLLING_WINDOW_SIZE games, ordered chronologically per team.
    # Deliberately NOT reset at season boundaries (see .roll_mean_trailing()'s header comment for
    # the partial-window / short-CURRENT_SEASON-history fallback rationale).
    team_game <- team_game |>
      arrange(team, game_date, week) |>
      group_by(team) |>
      mutate(
        off_epa_per_play_roll         = .roll_mean_trailing(off_epa_per_play),
        def_epa_per_play_allowed_roll = .roll_mean_trailing(def_epa_per_play_allowed),
        off_success_rate_roll         = .roll_mean_trailing(off_success_rate),
        def_success_rate_allowed_roll = .roll_mean_trailing(def_success_rate_allowed),
        off_cpoe_roll                 = .roll_mean_trailing(off_cpoe),
        # Situational rolling columns (Phase 4 model-quality remediation) - same trailing-window
        # treatment as the full-game columns above, same partial-window/short-history fallback
        # behavior (.roll_mean_trailing()'s na.rm = TRUE also absorbs a team's occasional
        # single-game NA situational value, e.g. a game with zero money-down plays).
        off_epa_early_down_roll              = .roll_mean_trailing(off_epa_early_down),
        off_success_early_down_roll          = .roll_mean_trailing(off_success_early_down),
        off_epa_money_down_roll              = .roll_mean_trailing(off_epa_money_down),
        off_success_money_down_roll          = .roll_mean_trailing(off_success_money_down),
        off_redzone_success_rate_roll        = .roll_mean_trailing(off_redzone_success_rate),
        off_explosive_rate_roll              = .roll_mean_trailing(off_explosive_rate),
        off_proe_roll                        = .roll_mean_trailing(off_proe),
        def_epa_early_down_allowed_roll      = .roll_mean_trailing(def_epa_early_down_allowed),
        def_success_early_down_allowed_roll  = .roll_mean_trailing(def_success_early_down_allowed),
        def_epa_money_down_allowed_roll      = .roll_mean_trailing(def_epa_money_down_allowed),
        def_success_money_down_allowed_roll  = .roll_mean_trailing(def_success_money_down_allowed),
        def_redzone_success_rate_allowed_roll = .roll_mean_trailing(def_redzone_success_rate_allowed),
        def_explosive_rate_allowed_roll      = .roll_mean_trailing(def_explosive_rate_allowed),
        def_proe_allowed_roll                = .roll_mean_trailing(def_proe_allowed),
        games_in_window               = pmin(dplyr::row_number(), ROLLING_WINDOW_SIZE)
      ) |>
      ungroup()

    current_teams <- unique(pbp$posteam[pbp$season == CURRENT_SEASON])
    missing_current <- setdiff(names(NFL_TEAMS), current_teams)
    if (length(missing_current) > 0) {
      log_warn(sprintf("Teams with no %d-season plays yet in CACHE_PBP (will rely entirely on prior-season trailing games until they play): %s",
                        CURRENT_SEASON, paste(missing_current, collapse = ", ")),
               call = "run_epa_metrics()")
    }

    saveRDS(team_game, CACHE_EPA_METRICS)
    log_info(sprintf("Wrote %d team-game rows (%d teams) to CACHE_EPA_METRICS.", nrow(team_game), n_teams),
             call = "run_epa_metrics()", rows = nrow(team_game), teams = n_teams, out_path = CACHE_EPA_METRICS)

    TRUE
  }, error = function(e) {
    log_error("EPA metrics engine failed.", condition = e, call = "run_epa_metrics()")
    FALSE
  })

  invisible(isTRUE(result))
}
