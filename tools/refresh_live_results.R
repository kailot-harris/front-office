# ==============================================================================
# tools/refresh_live_results.R — fill finished scores into the committed web JSON
#
# WHY THIS EXISTS, AND WHY IT IS NOT export_web_data.R
#
# export_matchup_slates() rebuilds every slate from the pipeline caches
# (mlb_schedule_*.rds, mlb_elo_history.rds, mlb_team_ratings.rds). Those are
# gitignored, so it can only ever run on a machine that has run the pipeline.
# This script does the one narrow job that has to happen every day during the
# postseason — "games finished, write their scores in" — using only the JSON
# already committed in web/public/data plus the public MLB Stats API. No
# caches, no API key, no renv restore. That is what makes it runnable from a
# scheduled GitHub Action (.github/workflows/refresh-results.yml).
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It never invents or regrades a prediction. home_win_prob,
#     projection_source and prediction_correct are copied through untouched.
#     Grading needs the walk-forward Elo probability, which lives in a cache
#     this script cannot see, and recomputing it from current Elo would be
#     hindsight grading (see HANDOFF.md section 4).
#   * It never adds or removes games. A schedule change — a postponement
#     creating a new game_pk, say — needs a real pipeline re-export.
#
# Run a full export_web_data.R pass whenever the pipeline is refreshed; this
# is a between-times top-up, not a replacement.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

source(file.path("tools", "world_series_summary.R"))

MLB_SCHEDULE_API <- "https://statsapi.mlb.com/api/v1/schedule"

# Statuses that mean "this game is over and the score is final". Mirrors the
# is_completed rule in build_matchup_slates(); keep the two in step.
COMPLETED_STATUSES <- c("Final", "Completed Early", "Game Over")

# Local null-coalesce. This script never sources logging_utils.R, which owns
# the canonical %||% (see its comment: that is the one definition in the repo),
# so this stays private rather than becoming a second public copy.
`%||%` <- function(a, b) if (is.null(a)) b else a

.as_int_or_na <- function(x) if (is.null(x)) NA_integer_ else as.integer(x)

#' Fetch finished-game results for a season from the public MLB Stats API
#'
#' @param season Season year
#' @param url_reader Injectable reader, for tests. Takes a URL, returns parsed JSON.
#' @return data.frame of game_pk, status_detail, home_score, away_score
fetch_season_results <- function(season = 2026,
                                 url_reader = function(u) jsonlite::fromJSON(u, simplifyVector = FALSE)) {
  url <- sprintf("%s?sportId=1&season=%d&gameTypes=R,F,D,L,W", MLB_SCHEDULE_API, season)
  raw <- url_reader(url)

  rows <- list()
  for (d in (raw$dates %||% list())) {
    for (g in (d$games %||% list())) {
      rows[[length(rows) + 1L]] <- data.frame(
        game_pk       = as.integer(g$gamePk),
        status_detail = as.character(g$status$detailedState %||% NA_character_),
        home_score    = .as_int_or_na(g$teams$home$score),
        away_score    = .as_int_or_na(g$teams$away$score),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    return(data.frame(game_pk = integer(0), status_detail = character(0),
                      home_score = integer(0), away_score = integer(0),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Patch finished results into committed matchup rows
#'
#' Only rows that are currently incomplete AND come back final with both
#' scores are touched, so a re-run is a no-op and a partial API response can
#' never blank out a score that is already recorded.
#'
#' @param rows data.frame of matchup rows read from a week-NN.json
#' @param results data.frame from fetch_season_results()
#' @return List of rows (patched) and n_changed
apply_results <- function(rows, results) {
  if (nrow(rows) == 0 || nrow(results) == 0) {
    return(list(rows = rows, n_changed = 0L))
  }

  idx <- match(rows$game_pk, results$game_pk)
  n_changed <- 0L

  for (i in seq_len(nrow(rows))) {
    j <- idx[i]
    if (is.na(j)) next
    if (isTRUE(rows$is_completed[i])) next

    status <- results$status_detail[j]
    hs <- results$home_score[j]
    ascore <- results$away_score[j]
    if (!status %in% COMPLETED_STATUSES || is.na(hs) || is.na(ascore)) next

    rows$status_detail[i] <- status
    rows$is_completed[i]  <- TRUE
    rows$home_score[i]    <- hs
    rows$away_score[i]    <- ascore
    n_changed <- n_changed + 1L
  }

  list(rows = rows, n_changed = n_changed)
}

#' Recompute the index fields that depend on results, leaving the rest alone
#'
#' Week labels, dates and graded counts are not recomputed: nothing this
#' script does can change them (it never grades), and the anchor-Monday maths
#' that produced them lives in build_matchup_slates().
recompute_index <- function(index, all_rows, today = Sys.Date(), generated_at = NULL) {
  index$completed_games <- sum(vapply(all_rows, function(r) sum(r$is_completed), numeric(1)))
  index$generated_at <- generated_at %||%
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  # Active week = the week whose date range holds today, when today is in
  # season. Same rule as build_matchup_slates(), derived from the index's own
  # start/end dates rather than re-deriving an anchor Monday.
  wk <- index$available_weeks
  starts <- as.Date(vapply(wk, function(w) w$start_date, character(1)))
  ends   <- as.Date(vapply(wk, function(w) w$end_date, character(1)))
  hit <- which(today >= starts & today <= ends)
  if (length(hit) == 1) {
    index$active_week <- wk[[hit]]$week
    for (k in seq_along(wk)) {
      wk[[k]]$status <- if (wk[[k]]$week < index$active_week) {
        "past"
      } else if (wk[[k]]$week == index$active_week) {
        "active"
      } else {
        "future"
      }
    }
    index$available_weeks <- wk
  }
  index
}

#' Write only when the bytes would actually change
#'
#' The scheduled job runs daily whether or not anything happened. Without
#' this, every run rewrites generated_at and produces a commit that says
#' nothing — which trains you to ignore the commits that do matter.
#'
#' @return TRUE if the file was written
write_json_if_changed <- function(x, path, pretty) {
  new_text <- as.character(jsonlite::toJSON(x, pretty = pretty, auto_unbox = TRUE, na = "null"))
  if (file.exists(path)) {
    old_text <- paste(readLines(path, warn = FALSE), collapse = "
")
    if (trimws(old_text) == trimws(new_text)) return(FALSE)
  }
  writeLines(new_text, path)
  TRUE
}

#' Refresh the committed web JSON with any newly finished results
#'
#' @param season Season year
#' @param data_dir Directory holding matchups_index.json and matchups/
#' @param url_reader Injectable JSON reader, for tests
#' @param today Date treated as "now", for tests
#' @return List: n_changed, files (paths rewritten), world_series (summary or NULL)
refresh_live_results <- function(season = 2026,
                                 data_dir = file.path("web", "public", "data"),
                                 url_reader = NULL,
                                 today = Sys.Date()) {
  index_file <- file.path(data_dir, "matchups_index.json")
  weeks_dir <- file.path(data_dir, "matchups")
  if (!file.exists(index_file)) {
    stop(sprintf("refresh_live_results(): no index at %s — run export_web_data.R first.",
                 index_file))
  }

  results <- if (is.null(url_reader)) {
    fetch_season_results(season)
  } else {
    fetch_season_results(season, url_reader)
  }

  index <- jsonlite::read_json(index_file, simplifyVector = FALSE)
  week_numbers <- vapply(index$available_weeks, function(w) as.integer(w$week), integer(1))

  all_rows <- list()
  changed_files <- character(0)
  n_changed <- 0L

  for (wk in week_numbers) {
    f <- file.path(weeks_dir, sprintf("week-%02d.json", wk))
    if (!file.exists(f)) next
    rows <- jsonlite::fromJSON(f, simplifyDataFrame = TRUE)
    patched <- apply_results(rows, results)
    all_rows[[as.character(wk)]] <- patched$rows

    if (patched$n_changed > 0) {
      jsonlite::write_json(patched$rows, f, pretty = FALSE, auto_unbox = TRUE, na = "null")
      changed_files <- c(changed_files, f)
      n_changed <- n_changed + patched$n_changed
    }
  }

  combined <- do.call(rbind, unname(all_rows))
  ws <- build_world_series_summary(combined, season = season)
  f_ws <- file.path(data_dir, "world_series.json")
  if (!is.null(ws) && write_json_if_changed(ws, f_ws, pretty = TRUE)) {
    changed_files <- c(changed_files, f_ws)
  }

  # Carry the old generated_at into the candidate first, so an unchanged day
  # compares equal and writes nothing; only stamp a new time if something else
  # in the index really moved.
  candidate <- recompute_index(index, all_rows, today = today,
                               generated_at = index$generated_at)
  if (write_json_if_changed(candidate, index_file, pretty = TRUE)) {
    # Something real moved, so the stamp is now meaningful. Write once more
    # with the current time.
    candidate$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    jsonlite::write_json(candidate, index_file, pretty = TRUE, auto_unbox = TRUE, na = "null")
    changed_files <- c(changed_files, index_file)
  }

  list(n_changed = n_changed, files = changed_files, world_series = ws)
}

# Entry point for the scheduled workflow: Rscript tools/refresh_live_results.R [season]
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else 2026
  res <- refresh_live_results(season = season)

  cat(sprintf("Newly completed games written: %d\n", res$n_changed))
  if (!is.null(res$world_series)) {
    ws <- res$world_series
    cat(sprintf("World Series: %s %d-%d after %d of %d games%s\n",
                ws$status, ws$home_field$wins, ws$challenger$wins,
                ws$games_played, ws$games_scheduled,
                if (!is.na(ws$champion)) sprintf(" - champion: %s", ws$champion) else ""))
  }
}
