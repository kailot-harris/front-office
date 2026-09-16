# ==============================================================================
# NFL Roster Synchronizer
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/sync_rosters.R
#
# Ported from WNBA Analytics's sync_rosters.R (see that repo's file for the original
# ESPN-site-API-driven pattern), with the ESPN/wehoop-style per-team live HTTP loop
# REPLACED by a single nflreadr::load_rosters() bulk call - nflreadr already returns
# every team's roster in one data pull (no per-team endpoint, no polite Sys.sleep()
# throttling loop needed the way the WNBA ESPN-scrape version required).
#
# NFL-specific structural differences discovered via live empirical check against
# nflreadr::load_rosters(CURRENT_SEASON) on 2026-09-16 (see docs/task_assignments_phase0.md
# Interface Contracts for this script's fixed run_sync_rosters() signature):
#   - Team abbreviations: load_rosters()'s `team` column matched all 32 of config.R's
#     NFL_TEAMS keys exactly (ARI, ATL, ..., WAS) with zero unrecognized abbreviations -
#     confirmed empirically, not assumed, per the task brief. The defensive filter below
#     is kept anyway (same discipline as WNBA's WNBA_TEAMS filter) in case a future season's
#     relocation/rename briefly desyncs config.R from nflverse before NFL_TEAMS is updated.
#   - load_rosters() is NOT limited to the 53-man active/gameday roster. Its `status` column
#     returned ACT (1,691 rows), CUT (423), DEV (559 - developmental/practice-squad players;
#     559/32 teams ~= 17.5/team, consistent with NFL_PRACTICE_SQUAD_SIZE=16 plus rotation
#     churn), EXE (4 - reserve/exempt list), RES (268 - reserve/IR), and RET (23 - retired
#     this season) in a single live pull. So YES, practice-squad players ARE present (status
#     == "DEV"), alongside cut/retired/IR players who were on a team's books at some point
#     this season - this is one wide season-to-date roster ledger, not a live 53-man snapshot.
#     Downstream consumers that want only the current active/dressable roster must filter on
#     status == "ACT" themselves; this sync script caches the full ledger un-filtered by
#     status (only filtering on the team-abbreviation validity check below), since collapsing
#     to ACT-only here would silently discard practice-squad/IR data other stages may want
#     (e.g. an injury-report join needs RES/IR rows, not just ACT).
#   - One row per player per pull (2,967 of 2,968 rows had a unique gsis_id; the single NA
#     gsis_id belongs to one player nflverse hasn't yet assigned a GSIS ID to) - no
#     team-loop/pagination logic is needed the way WNBA's per-team ESPN scrape required.
#   - load_rosters()/load_rosters_weekly() both default `seasons` to
#     nflreadr::most_recent_season(roster = TRUE) when called with no args; this script still
#     passes CURRENT_SEASON explicitly (config.R's constant) rather than relying on that
#     default, per this repo's constants convention (CLAUDE.md).
# ==============================================================================

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "sync_rosters.R"

suppressPackageStartupMessages({
  library(nflreadr)
})

run_sync_rosters <- function() {
  cat("\n==================================================================\n")
  cat("             SYNCING NFL ROSTERS (nflreadr::load_rosters)         \n")
  cat("==================================================================\n\n")

  log_info(sprintf("Fetching NFL rosters for season %s via nflreadr::load_rosters().", CURRENT_SEASON),
           call = "run_sync_rosters()", season = CURRENT_SEASON)

  rosters <- tryCatch({
    as.data.frame(nflreadr::load_rosters(seasons = CURRENT_SEASON))
  }, error = function(e) {
    log_error("nflreadr::load_rosters() failed.", condition = e,
              call = "run_sync_rosters()", season = CURRENT_SEASON)
    NULL
  })

  if (is.null(rosters) || nrow(rosters) == 0) {
    log_error("No roster rows returned; aborting sync without touching the cache.",
              call = "run_sync_rosters()", season = CURRENT_SEASON)
    cat("[ROSTER SYNC] FAILED: no data returned from nflreadr::load_rosters().\n")
    return(FALSE)
  }

  if (!"team" %in% names(rosters)) {
    log_error("load_rosters() response has no 'team' column; cannot validate against NFL_TEAMS.",
              call = "run_sync_rosters()", columns = paste(names(rosters), collapse = ", "))
    cat("[ROSTER SYNC] FAILED: unexpected schema from load_rosters().\n")
    return(FALSE)
  }

  # Validate every row's team abbreviation against config.R's NFL_TEAMS (single source of
  # truth for the 32-team map, itself pulled from nflreadr::load_teams() - see config.R's
  # header). Drop and loudly log any row whose abbreviation isn't a recognized NFL_TEAMS key,
  # the same discipline WNBA's sync_rosters.R applies against WNBA_TEAMS, rather than letting
  # an unrecognized abbreviation silently corrupt a downstream join.
  known_mask      <- rosters$team %in% names(NFL_TEAMS)
  unknown_abbrevs <- sort(unique(rosters$team[!known_mask]))

  if (length(unknown_abbrevs) > 0) {
    log_warn(sprintf(
      "Dropping %d roster row(s) with team abbreviation(s) not in config.R's NFL_TEAMS: %s. Update NFL_TEAMS if this is a real franchise (relocation/rename/expansion), not a data glitch.",
      sum(!known_mask), paste(unknown_abbrevs, collapse = ", ")
    ), call = "run_sync_rosters()", unknown_teams = paste(unknown_abbrevs, collapse = ", "),
       dropped_rows = sum(!known_mask))
    cat(sprintf("[ROSTER SYNC] WARNING: dropping %d row(s) with unrecognized team abbreviation(s): %s\n",
                sum(!known_mask), paste(unknown_abbrevs, collapse = ", ")))
  }

  rosters <- rosters[known_mask, , drop = FALSE]

  if (nrow(rosters) == 0) {
    log_error("All roster rows were dropped by the NFL_TEAMS validity filter; aborting without writing the cache.",
              call = "run_sync_rosters()")
    cat("[ROSTER SYNC] FAILED: zero valid rows survived team-abbreviation validation.\n")
    return(FALSE)
  }

  n_teams <- length(unique(rosters$team))
  if (n_teams != NFL_TEAM_COUNT) {
    log_warn(sprintf("Roster pull covers %d team(s), expected %d (NFL_TEAM_COUNT).", n_teams, NFL_TEAM_COUNT),
             call = "run_sync_rosters()", teams_found = n_teams, teams_expected = NFL_TEAM_COUNT)
  }

  # Sanity range check: with practice squad + cuts/IR/retirees all included in one season-to-date
  # ledger (see header comment), a healthy per-team row count comfortably exceeds
  # NFL_ROSTER_MAX + NFL_PRACTICE_SQUAD_SIZE (69) but should not be wildly out of range.
  avg_per_team <- nrow(rosters) / n_teams
  cat(sprintf("[ROSTER SYNC] %d rows across %d teams (avg %.1f rows/team; NFL_ROSTER_MAX=%d, NFL_PRACTICE_SQUAD_SIZE=%d).\n",
              nrow(rosters), n_teams, avg_per_team, NFL_ROSTER_MAX, NFL_PRACTICE_SQUAD_SIZE))

  saveRDS(rosters, CACHE_ROSTERS)

  cat(sprintf("[CACHE] Saved %d roster rows to: %s\n", nrow(rosters), CACHE_ROSTERS))
  log_info(sprintf("Synchronized %d NFL roster rows across %d teams.", nrow(rosters), n_teams),
           call = "run_sync_rosters()", rows = nrow(rosters), teams = n_teams, out_path = CACHE_ROSTERS)

  TRUE
}
