# ==============================================================================
# Weekly Turnover-Margin History Cache
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/turnover_margin_history.R
#
# Phase 9 / issue #19 (Wave 1, P9-C). Aggregates CACHE_PBP's play-level
# interception/fumble_lost columns to one row per (week, team) and writes the
# result to CACHE_TURNOVER_HISTORY, feeding the planned turnover-margin race
# chart (P9-I / issue #33). Not part of run_full_pipeline.R's DAG - ad-hoc/
# on-demand, same category as tools/weekly_accuracy_report.R.
#
# Run with (absolute path required - a relative path to a user-level skill
# script segfaults Rscript.exe on this machine; this is a repo-local tools/
# script so a relative path from the repo root also works, but absolute is
# always safe):
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "c:/Users/kailo/kayceeslices/NFL Analytics/tools/turnover_margin_history.R"
#
# ------------------------------------------------------------------------------------------
# LIVE-VERIFIED COLUMN SEMANTICS (2026-10-13, nflreadr::load_pbp(seasons = 2024), 49,492 rows)
# ------------------------------------------------------------------------------------------
# Per this repo's CLAUDE.md data-quirks discipline (cpoe/pass_oe NA-handling precedent), both
# interception and fumble_lost were checked live against real re-ingested data before being
# trusted here - NOT assumed from their names.
#
#   str(pbp$interception)
#    num [1:49492] NA 0 0 0 0 0 0 0 0 0 ...
#   table(interception, useNA = "always")
#       0     1  <NA>
#   47570   405  1517
#   -> clean 0/1 indicator (NA only on non-play rows: kickoffs/timeouts/etc., same NA pattern
#      class as cpoe's non-target NAs). 1 = pass intercepted by the defense. No count-valued
#      rows observed.
#
#   str(pbp$fumble_lost)
#    num [1:49492] NA 0 0 0 0 0 0 0 0 0 ...
#   table(fumble_lost, useNA = "always")
#       0     1  <NA>
#   47690   285  1517
#   -> clean 0/1 indicator, same NA pattern as interception.
#
#   table(fumble = pbp$fumble, fumble_lost = pbp$fumble_lost, useNA = "always")
#                 fumble_lost
#         fumble     0     1  <NA>
#                0   47312     0     0
#                1     378   285     0
#               <NA>     0     0  1517
#   -> CONFIRMED fumble_lost is NOT merely "a fumble occurred": of 663 total fumble==1 plays,
#      378 (57%) have fumble_lost == 0 (the fumbling offense recovered its own fumble) and only
#      285 (43%) have fumble_lost == 1 (possession actually changed). Using `fumble` instead of
#      `fumble_lost` here would have overstated every team's giveaways by ~2.3x - exactly the
#      kind of silent-corruption quirk CLAUDE.md warns about.
#
#   Spot-check against fumble_recovery_1_team (who recovered the FIRST fumble on the play) vs.
#   posteam (who had the ball at snap): among fumble==1 rows with a non-NA recovery team,
#     fumble_lost==1 & recovered_by_other_team==TRUE  : 258/310 (~83%)
#     fumble_lost==0 & recovered_by_other_team==FALSE : 298/325 (~92%)
#   The ~10-15% disagreement is attributable to multi-fumble plays (a second bobble/recovery
#   tracked by fumble_recovery_2_team, not re-checked here) rather than fumble_lost being wrong
#   - fumble_lost is nflverse's own derived "did possession change" field and is authoritative
#     for this aggregation; we use it directly rather than re-deriving turnover status from the
#     recovery-team columns ourselves.
#
# CONCLUSION: interception and fumble_lost are both used as-is. A team's weekly:
#   - takeaways  = (opponent's interception==1 plays where this team was defteam)
#                + (opponent's fumble_lost==1 plays where this team was defteam)
#   - giveaways  = (this team's interception==1 plays where this team was posteam)
#                + (this team's fumble_lost==1 plays where this team was posteam)
#   - turnover_margin = takeaways - giveaways
# ------------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
})

setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "turnover_margin_history.R"

# ------------------------------------------------------------------------------------------
# build_turnover_margin_history(): the sole callable. Reads CACHE_PBP, aggregates turnovers to
# one row per (week, team), writes CACHE_TURNOVER_HISTORY via saveRDS(), and returns the
# resulting data frame. Exposed as a function (not a sys.nframe()==0 top-level guard) per
# CLAUDE.md's "Process / conventions" frame-depth-guard caution, even though this script is not
# currently part of run_full_pipeline.R's DAG - keeps it consistent with every other stage
# script and safe to wire into the DAG later without rework.
# ------------------------------------------------------------------------------------------
build_turnover_margin_history <- function(season = CURRENT_SEASON) {
  if (!file.exists(CACHE_PBP)) {
    stop("CACHE_PBP not found at ", CACHE_PBP, " - run daily_ingest.R's run_daily_ingest() first.")
  }

  pbp <- readRDS(CACHE_PBP)

  required_cols <- c("week", "season", "posteam", "defteam", "interception", "fumble_lost")
  missing_cols <- setdiff(required_cols, names(pbp))
  if (length(missing_cols) > 0) {
    stop("CACHE_PBP is missing required column(s): ", paste(missing_cols, collapse = ", "),
         " - re-run daily_ingest.R's run_daily_ingest(force_refresh = TRUE) after widening ",
         ".PBP_CACHE_COLUMNS to include them.")
  }

  # Scoped to a single season (default CURRENT_SEASON), matching the sibling
  # CACHE_PLAYOFF_ODDS_HISTORY contract (also `week, team` with no season column - see
  # docs/task_assignments_phase8.md's Interface Contracts table) - these weekly-race caches are
  # single-season by design (the race chart animates one season's weeks), and the published
  # schema genuinely has no `season` column, so cross-season week collisions must be prevented
  # by filtering here rather than by smuggling a season column into the output.
  pbp <- pbp |> filter(season == !!season)
  if (nrow(pbp) == 0) {
    stop("No CACHE_PBP rows found for season ", season, ".")
  }

  # Real plays only: posteam/defteam are blank on non-play rows (timeouts, end-of-quarter, etc.)
  # which also carry NA interception/fumble_lost - drop them rather than let them silently
  # coerce into FALSE/0 downstream.
  plays <- pbp |>
    filter(!is.na(posteam), !is.na(defteam), posteam != "", defteam != "")

  # Giveaways: turnovers committed while on offense (posteam).
  giveaways <- plays |>
    group_by(week, team = posteam) |>
    summarise(
      giveaways = sum(coalesce(interception, 0), na.rm = TRUE) +
                  sum(coalesce(fumble_lost, 0), na.rm = TRUE),
      .groups = "drop"
    )

  # Takeaways: turnovers forced while on defense (defteam).
  takeaways <- plays |>
    group_by(week, team = defteam) |>
    summarise(
      takeaways = sum(coalesce(interception, 0), na.rm = TRUE) +
                  sum(coalesce(fumble_lost, 0), na.rm = TRUE),
      .groups = "drop"
    )

  history <- full_join(takeaways, giveaways, by = c("week", "team")) |>
    mutate(
      takeaways = coalesce(takeaways, 0),
      giveaways = coalesce(giveaways, 0),
      turnover_margin = takeaways - giveaways
    ) |>
    arrange(team, week) |>
    group_by(team) |>
    mutate(cumulative_margin = cumsum(turnover_margin)) |>
    ungroup() |>
    arrange(week, team) |>
    select(week, team, takeaways, giveaways, turnover_margin, cumulative_margin)

  saveRDS(history, CACHE_TURNOVER_HISTORY)
  log_info(sprintf("Wrote %d (season, week, team) turnover-margin rows to %s",
                    nrow(history), CACHE_TURNOVER_HISTORY),
           call = "build_turnover_margin_history()")

  history
}

if (sys.nframe() == 0 && !interactive()) {
  # Allow direct `Rscript.exe turnover_margin_history.R` invocation for ad-hoc refreshes, same
  # as tools/weekly_accuracy_report.R's pattern - this script is NOT sourced by
  # run_full_pipeline.R, so the frame-depth caution in CLAUDE.md doesn't apply here.
  invisible(build_turnover_margin_history())
}
