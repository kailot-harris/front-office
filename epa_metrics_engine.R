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

    team_game <- full_join(
      off_stats, def_stats,
      by = c("season", "game_id", "game_date", "week", "team")
    ) |>
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
