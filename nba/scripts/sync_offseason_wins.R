# ==============================================================================
# scripts/sync_offseason_wins.R
# Re-point offseason baseline_wins at the current season projections.
# ==============================================================================
#
# SOURCE-OF-TRUTH CONTRACT (issue #19)
# ------------------------------------------------------------------------------
# build_offseason_dataset.R preserves `baseline_wins` from the existing
# offseason_teams.json and never derives it from projections (see the header
# note there and the `existing` branch around line 277). That keeps a builder
# run from silently discarding a hand-set baseline -- but it also means a fresh
# season_simulator run leaves the offseason profiles holding the previous day's
# wins, which breaks the cross-dataset check in web/tests/contracts/
# referential.test.ts.
#
# This script is the other half of that contract: it is the only place that
# moves baseline_wins, and it must run AFTER season_simulator.R and BEFORE
# build_offseason_dataset.R. Promoted out of tmp/ so the daily pipeline can
# call it; it was previously an untracked scratch file.

suppressPackageStartupMessages(library(jsonlite))

sync_offseason_wins <- function(
  teams_file = "web/public/data/projections_season_teams.json",
  profile_file = "web/public/data/offseason_teams.json"
) {
  missing <- c(teams_file, profile_file)[!file.exists(c(teams_file, profile_file))]
  if (length(missing) > 0) {
    stop(sprintf("sync_offseason_wins: missing input(s): %s",
                 paste(missing, collapse = ", ")), call. = FALSE)
  }

  teams <- fromJSON(teams_file)
  proj <- setNames(as.numeric(teams$proj_wins), teams$team)
  profiles <- fromJSON(profile_file, simplifyVector = FALSE)

  round1 <- function(x) round(x, 1)
  changed <- 0L
  for (i in seq_along(profiles)) {
    abbr <- profiles[[i]]$team
    if (is.null(proj[[abbr]])) {
      stop(sprintf("sync_offseason_wins: no projection for %s", abbr), call. = FALSE)
    }
    old_base <- as.numeric(profiles[[i]]$baseline_wins)
    new_base <- round1(proj[[abbr]])
    if (!isTRUE(all.equal(old_base, new_base))) changed <- changed + 1L
    profiles[[i]]$baseline_wins <- new_base
    profiles[[i]]$projected_wins_with_moves <-
      round1(new_base + as.numeric(profiles[[i]]$net_wins_change))
  }

  # Same invariant build_offseason_dataset.R asserts on its own output.
  bad <- Filter(function(x) {
    abs(x$baseline_wins + x$net_wins_change - x$projected_wins_with_moves) > 0.051
  }, profiles)
  if (length(bad) > 0) {
    stop("sync_offseason_wins: baseline_wins + net_wins_change != projected_wins_with_moves.",
         call. = FALSE)
  }

  write_json(profiles, profile_file, pretty = TRUE, auto_unbox = TRUE, digits = NA)
  cat(sprintf(">>> [SUCCESS] Synced baseline_wins for %d teams (%d changed) in %s\n",
              length(profiles), changed, profile_file))
  invisible(length(profiles))
}

if (!interactive()) invisible(sync_offseason_wins())
