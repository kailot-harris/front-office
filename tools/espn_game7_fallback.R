# ==============================================================================
# tools/espn_game7_fallback.R
#
# One-off, idempotent patch for the 2026 WNBA Finals Game 7 (ESPN game_id
# 401918311, GS @ home vs ATL, 2026-10-31) staying unresolved in this repo's
# caches because wehoop::load_wnba_schedule()/load_wnba_team_box() had not
# picked up the final result six days after it was played (confirmed live via
# tools/diagnose_game7_sources.R: ESPN's site.api scoreboard, site.api summary,
# and core API all independently report STATUS_FINAL / completed = TRUE, while
# wehoop still reports STATUS_SCHEDULED with a 0-0 score). This is a wehoop
# package lag, not a data-entry error or a bug in this repo's own pipeline.
#
# WHAT THIS DOES:
#   1. Fetches ESPN's site.api summary endpoint directly for game_id 401918311.
#   2. Confirms it is actually STATUS_FINAL before writing anything (never
#      patches on a partial/live game).
#   3. Patches cache/wnba_schedule_cache.rds: sets is_completed = TRUE on both
#      of game_id 401918311's rows (GS, ATL), which is what
#      build_finals_game_predictions.R's load_finals_schedule_rest() keys on.
#   4. Appends two rows to data/box_scores_cache.rds (CACHE_TEAM_BOX) with the
#      real final score and box stats pulled from ESPN, in the exact column
#      shape wehoop::load_wnba_team_box() already uses -- this is what
#      build_playoff_bracket_2026.R's resolved-half logic reads team_score/
#      opponent_team_score from to decide the series winner.
#   5. Tags both new box rows with data_source = "ESPN_FALLBACK" (a new column,
#      NA on every pre-existing row) so this patched game is forever
#      distinguishable from a normal wehoop-sourced row in any future audit --
#      never silently indistinguishable synthetic data.
#
# IDEMPOTENT: re-running this script after wehoop catches up (or after a prior
# successful run) is a safe no-op -- it checks both caches first and does
# nothing if game 401918311 is already marked complete in each.
#
# NOT GENERAL-PURPOSE: this hardcodes game_id 401918311. It exists to unblock
# this one specific stuck closeout, not as a reusable "ESPN fallback for any
# game" utility -- see tools/diagnose_game7_sources.R if a different game ever
# needs the same cross-source check repeated.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\espn_game7_fallback.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(httr)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "espn_game7_fallback.R"

GAME_ID <- "401918311"

fetch_espn_final <- function(game_id) {
  url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/summary"
  res <- GET(url, query = list(event = game_id))
  if (status_code(res) != 200) {
    stop(sprintf("ESPN summary request failed with HTTP %s.", status_code(res)))
  }
  j <- fromJSON(content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
  comp <- j$header$competitions[[1]]
  if (!isTRUE(comp$status$type$completed)) {
    stop(sprintf(
      "ESPN reports game %s as '%s' (completed=%s), not final -- refusing to patch caches with an unresolved game.",
      game_id, comp$status$type$name, comp$status$type$completed))
  }

  competitors <- comp$competitors
  team_stats <- j$boxscore$teams

  stat_lookup <- function(team_abbr) {
    idx <- which(sapply(team_stats, function(t) t$team$abbreviation) == team_abbr)
    if (length(idx) == 0) return(NULL)
    stats <- team_stats[[idx[1]]]$statistics
    setNames(lapply(stats, function(s) s$displayValue), sapply(stats, function(s) s$name))
  }

  split_made_attempted <- function(val) {
    if (is.null(val)) return(c(NA_integer_, NA_integer_))
    parts <- strsplit(val, "-", fixed = TRUE)[[1]]
    if (length(parts) != 2) return(c(NA_integer_, NA_integer_))
    as.integer(parts)
  }

  rows <- lapply(competitors, function(c) {
    abbr <- c$team$abbreviation
    s <- stat_lookup(abbr)
    fg <- split_made_attempted(s[["fieldGoalsMade-fieldGoalsAttempted"]])
    tp <- split_made_attempted(s[["threePointFieldGoalsMade-threePointFieldGoalsAttempted"]])
    ft <- split_made_attempted(s[["freeThrowsMade-freeThrowsAttempted"]])
    list(
      team_abbreviation = abbr,
      team_home_away = c$homeAway,
      team_score = as.integer(c$score),
      team_winner = isTRUE(c$winner),
      field_goals_made = fg[1], field_goals_attempted = fg[2],
      field_goal_pct = as.numeric(s[["fieldGoalPct"]]),
      three_point_field_goals_made = tp[1], three_point_field_goals_attempted = tp[2],
      three_point_field_goal_pct = as.numeric(s[["threePointFieldGoalPct"]]),
      free_throws_made = ft[1], free_throws_attempted = ft[2],
      free_throw_pct = as.numeric(s[["freeThrowPct"]]),
      total_rebounds = as.integer(s[["totalRebounds"]]),
      offensive_rebounds = as.integer(s[["offensiveRebounds"]]),
      defensive_rebounds = as.integer(s[["defensiveRebounds"]]),
      assists = as.integer(s[["assists"]]),
      steals = as.integer(s[["steals"]]),
      blocks = as.integer(s[["blocks"]]),
      turnovers = as.integer(s[["turnovers"]]),
      team_turnovers = as.integer(s[["teamTurnovers"]]),
      total_turnovers = as.integer(s[["totalTurnovers"]]),
      technical_fouls = as.integer(s[["technicalFouls"]]),
      total_technical_fouls = as.integer(s[["totalTechnicalFouls"]]),
      flagrant_fouls = as.integer(s[["flagrantFouls"]]),
      turnover_points = as.integer(s[["turnoverPoints"]]),
      fast_break_points = as.integer(s[["fastBreakPoints"]]),
      points_in_paint = as.integer(s[["pointsInPaint"]]),
      fouls = as.integer(s[["fouls"]]),
      largest_lead = as.integer(s[["largestLead"]]),
      lead_changes = as.integer(s[["leadChanges"]]),
      lead_percentage = as.integer(s[["leadPercentage"]])
    )
  })
  names(rows) <- sapply(competitors, function(c) c$team$abbreviation)
  rows
}

# Carries forward the static per-team identity columns (team_id/uid/slug/
# location/name/colors/logo) from that team's most recent existing box row --
# these never change mid-season, and ESPN's summary payload doesn't expose
# all of them in the same shape wehoop does, so reuse rather than re-derive.
most_recent_identity_row <- function(box, abbr) {
  rows <- box[box$team_abbreviation == abbr, ]
  rows <- rows[order(rows$game_date, decreasing = TRUE), ]
  rows[1, ]
}

patch_schedule_cache <- function() {
  if (!file.exists(CACHE_WNBA_SCHEDULE)) {
    log_warn("Schedule cache not found; skipping schedule patch.", call = "espn_game7_fallback()")
    return(invisible(FALSE))
  }
  sched <- readRDS(CACHE_WNBA_SCHEDULE)
  target <- sched$game_id == GAME_ID
  if (!any(target)) {
    log_warn(sprintf("Game %s not present in schedule cache; nothing to patch.", GAME_ID),
             call = "espn_game7_fallback()")
    return(invisible(FALSE))
  }
  if (all(sched$is_completed[target])) {
    log_info(sprintf("Schedule cache already marks game %s as completed; no patch needed.", GAME_ID),
             call = "espn_game7_fallback()")
    return(invisible(FALSE))
  }
  sched$is_completed[target] <- TRUE
  saveRDS(sched, CACHE_WNBA_SCHEDULE)
  log_info(sprintf("Patched schedule cache: game %s marked is_completed = TRUE (%d row(s)).",
                    GAME_ID, sum(target)),
           call = "espn_game7_fallback()", out_path = CACHE_WNBA_SCHEDULE)
  invisible(TRUE)
}

patch_box_cache <- function(espn_rows) {
  box <- readRDS(CACHE_TEAM_BOX)
  if ("data_source" %in% names(box) && any(box$game_id == GAME_ID & box$data_source == "ESPN_FALLBACK")) {
    log_info(sprintf("Box cache already holds an ESPN_FALLBACK row for game %s; no patch needed.", GAME_ID),
             call = "espn_game7_fallback()")
    return(invisible(FALSE))
  }
  if (any(box$game_id == GAME_ID)) {
    log_warn(sprintf("Box cache already holds game %s row(s) from another source; leaving in place and not duplicating.", GAME_ID),
             call = "espn_game7_fallback()")
    return(invisible(FALSE))
  }
  if (!"data_source" %in% names(box)) box$data_source <- NA_character_

  abbrs <- names(espn_rows)
  new_rows <- lapply(abbrs, function(abbr) {
    opp_abbr <- setdiff(abbrs, abbr)
    identity <- most_recent_identity_row(box, abbr)
    opp_identity <- most_recent_identity_row(box, opp_abbr)
    e <- espn_rows[[abbr]]

    row <- identity
    row$game_id <- as.integer(GAME_ID)
    row$season <- CURRENT_SEASON
    row$season_type <- 3L
    row$game_date <- as.Date("2026-10-31")
    row$game_date_time <- as.POSIXct("2026-10-31 00:00:00", tz = "UTC")
    row$team_home_away <- e$team_home_away
    row$team_score <- e$team_score
    row$team_winner <- e$team_winner
    for (col in c("assists", "blocks", "defensive_rebounds", "field_goal_pct",
                  "field_goals_made", "field_goals_attempted", "flagrant_fouls",
                  "fouls", "free_throw_pct", "free_throws_made", "free_throws_attempted",
                  "largest_lead", "offensive_rebounds", "steals", "team_turnovers",
                  "technical_fouls", "three_point_field_goal_pct",
                  "three_point_field_goals_made", "three_point_field_goals_attempted",
                  "total_rebounds", "total_technical_fouls", "total_turnovers", "turnovers",
                  "fast_break_points", "points_in_paint", "turnover_points",
                  "lead_changes", "lead_percentage")) {
      row[[col]] <- e[[col]]
    }
    row$opponent_team_id <- opp_identity$team_id
    row$opponent_team_uid <- opp_identity$team_uid
    row$opponent_team_slug <- opp_identity$team_slug
    row$opponent_team_location <- opp_identity$team_location
    row$opponent_team_name <- opp_identity$team_name
    row$opponent_team_abbreviation <- opp_abbr
    row$opponent_team_display_name <- opp_identity$team_display_name
    row$opponent_team_short_display_name <- opp_identity$team_short_display_name
    row$opponent_team_color <- opp_identity$team_color
    row$opponent_team_alternate_color <- opp_identity$team_alternate_color
    row$opponent_team_logo <- opp_identity$team_logo
    row$opponent_team_score <- espn_rows[[opp_abbr]]$team_score
    row$data_source <- "ESPN_FALLBACK"
    row
  })

  new_df <- bind_rows(new_rows)
  # Coerce every column to match the existing cache's own class -- ESPN's JSON
  # types (e.g. a stat that happens to come through as character vs numeric)
  # don't always match wehoop's exported column types, and bind_rows() errors
  # on a mismatch rather than silently coercing.
  for (col in intersect(names(new_df), names(box))) {
    target_class <- class(box[[col]])[1]
    new_df[[col]] <- switch(target_class,
      integer = as.integer(new_df[[col]]),
      numeric = as.numeric(new_df[[col]]),
      double  = as.numeric(new_df[[col]]),
      character = as.character(new_df[[col]]),
      logical = as.logical(new_df[[col]]),
      Date = as.Date(new_df[[col]]),
      new_df[[col]]
    )
  }
  combined <- bind_rows(box, new_df) |> arrange(season, game_date, game_id)
  saveRDS(combined, CACHE_TEAM_BOX)
  log_info(sprintf(
    "Patched box cache: appended 2 ESPN_FALLBACK row(s) for game %s (final score %s %d - %s %d).",
    GAME_ID, abbrs[1], espn_rows[[abbrs[1]]]$team_score, abbrs[2], espn_rows[[abbrs[2]]]$team_score),
    call = "espn_game7_fallback()", out_path = CACHE_TEAM_BOX)
  invisible(TRUE)
}

run_espn_game7_fallback <- function() {
  log_info(sprintf("Starting ESPN fallback patch for game %s.", GAME_ID), call = "espn_game7_fallback()")
  espn_rows <- fetch_espn_final(GAME_ID)
  log_info(sprintf("ESPN confirms game %s is STATUS_FINAL.", GAME_ID), call = "espn_game7_fallback()")
  patch_schedule_cache()
  patch_box_cache(espn_rows)
  log_info("ESPN fallback patch complete.", call = "espn_game7_fallback()")
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  run_espn_game7_fallback()
}
