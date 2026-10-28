# ==============================================================================
# tools/refresh_live_results.R - fill finished scores into the committed web JSON
#
# WHY THIS EXISTS, AND WHY IT IS NOT build_matchups_dataset.R
#
# build_matchups_dataset.R rebuilds the whole slate payload from the pipeline
# caches (the hoopR schedule cache, team ratings, the prediction log). Those are
# gitignored, so it can only run on a machine that has run the pipeline. This
# script does the one narrow job that has to happen several times a day during
# the season - "games finished, write their scores in" - using only the JSON
# already committed under web/public/data plus ESPN's public scoreboard. No
# caches, no API key, no renv restore. That is what makes it runnable from a
# scheduled GitHub Action (.github/workflows/refresh-results.yml), which is the
# point: the full DAG runs once a day on one Windows box, and the site should
# not carry last night's games as "pending" for the other 23 hours.
#
# WHY ESPN AND NOT hoopR
#
# The payload's `game_id` IS an ESPN event id ("401909088"), so the join is an
# exact key match with no crosswalk. hoopR's own release assets are built from
# ESPN, so this is the same upstream the pipeline ingests - just the cheap path
# to it, and one that does not wait for the ~12:20 UTC rebuild. The client
# itself lives in tools/espn_scoreboard.R, shared with
# tools/verify_results_vs_espn.R so the alias table has exactly one definition.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It never invents or alters a prediction. `predicted_margin`,
#     `predicted_home_win_prob`, `predicted_away_win_prob`, `predicted_winner`,
#     `has_projection` and `projection_basis` are copied through untouched. It
#     only GRADES them, and grading here is a pure function of fields already
#     committed in the file: `predicted_winner` versus who actually won. Nothing
#     is re-derived from current ratings, which would be hindsight grading.
#   * It never adds or removes games, and never touches `total_games`,
#     `available_slates`, `slates[].games_total` or `active_slate`. A schedule
#     change needs a real pipeline re-export, and `active_slate` is asserted
#     independently by publish_web.R's assertion B against the schedule cache -
#     a value this script cannot see and must not contradict.
#   * It never touches the prediction-log join fields
#     (`logged_predictions_matched`, `join_match_rate_pct`, `grading_state`,
#     `games_logged_basis` and the rest). Those describe how the projections
#     were sourced, not how the games turned out.
#
# WHAT IT DOES RECONCILE, AND WHY IT HAS TO
#
# Marking games complete without updating the counts that summarise them leaves
# the payload internally contradictory - and the web contract suite, which
# publish_web.R runs as assertion G, checks exactly these relations. So the
# script also recomputes, from the patched rows and nothing else:
#   * `completed_games` / `pending_games`
#   * each affected slate's `graded_total`, `correct_total`, `accuracy_pct`
# All four relations were verified against the committed 2026-10-27 payload
# before this script was written (slate 1: 52 games, 52 graded, 27 correct,
# 51.9% - reproduced exactly). `accuracy_pct` is null, not 0, for a slate with
# nothing graded yet, which is how the exporter writes it.
#
# Run a full pipeline pass whenever the caches refresh; this is a between-times
# top-up, not a replacement.
#
# Usage:
#   Rscript tools/refresh_live_results.R           # default 3-day lookback
#   Rscript tools/refresh_live_results.R 5         # widen the lookback
#   Rscript tools/refresh_live_results.R 2026-10-20 2026-10-26   # explicit range
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap: setwd() to this script's project root, then source siblings by bare
# filename (repo convention). Same helper shape as tools/publish_web.R.
# ------------------------------------------------------------------------------
.rlr_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1 && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) return(cand)
  }
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "config.R"))) return(d)
    p <- dirname(d)
    if (identical(p, d)) break
    d <- p
  }
  stop("refresh_live_results.R: cannot locate the project root (no config.R found).")
}

local({
  root <- .rlr_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})

suppressPackageStartupMessages(library(jsonlite))

# config.R loads no packages and its only side effect is dir.create() on the
# cache/web dirs, so it is safe under the jsonlite-only install the scheduled
# workflow sets up.
source("config.R")
source("tools/espn_scoreboard.R")

# Default lookback for the date sweep. ESPN's scoreboard is keyed by a single
# date, so an unbounded sweep over every pending date in a 1,200-game season is
# ~170 HTTP requests for the sake of one night's results. Three days covers the
# widest gap between scheduled slots (22:00 UTC to 13:00 UTC the next day) with
# room for a missed run, and is still three requests.
RLR_DEFAULT_LOOKBACK_DAYS <- 3L

# Vectorised isTRUE. `is_completed` round-trips as logical with NA possible, and
# `rows[rows$is_completed, ]` would then silently produce NA-filled rows.
.rlr_is_true <- function(x) !is.na(x) & x

# ------------------------------------------------------------------------------
# Patch
# ------------------------------------------------------------------------------

#' Which dates to ask ESPN about
#'
#' Only dates the payload actually schedules games on, only dates that are not
#' in the future, and only dates that still have something pending - asking
#' about a date whose games are all recorded cannot change anything.
#'
#' @param rows Matchup rows.
#' @param lookback_days How far back to sweep.
#' @param today Date treated as "now", for tests.
#' @return Character vector of YYYY-MM-DD, possibly empty.
pending_dates <- function(rows, lookback_days = RLR_DEFAULT_LOOKBACK_DAYS,
                          today = Sys.Date()) {
  d <- as.Date(substr(as.character(rows$game_date), 1, 10))
  open <- !.rlr_is_true(rows$is_completed) & !is.na(d) &
    d <= today & d >= (today - as.integer(lookback_days))
  sort(unique(as.character(d[open])))
}

#' Patch finished results into committed matchup rows
#'
#' Only rows that are currently incomplete AND come back final with both scores
#' are touched, so a re-run is a no-op and a partial ESPN response can never
#' blank out a score that is already recorded.
#'
#' `actual_winner` and `predicted_winner` are both team ABBREVIATIONS in this
#' payload (unlike the NFL repo's full franchise names), and the abbreviation is
#' taken from the payload's own row rather than from ESPN's reply - ESPN's
#' dialect is normalised by .espn_norm, but the payload's spelling is the one
#' every other field in the row already uses.
#'
#' @return list(rows, n_changed)
apply_results <- function(rows, results) {
  if (nrow(rows) == 0 || is.null(results) || nrow(results) == 0) {
    return(list(rows = rows, n_changed = 0L))
  }

  idx <- match(as.character(rows$game_id), as.character(results$game_id))
  n_changed <- 0L

  for (i in seq_len(nrow(rows))) {
    j <- idx[i]
    if (is.na(j)) next
    if (isTRUE(rows$is_completed[i])) next
    if (!isTRUE(results$is_final[j])) next

    hs <- results$home_score[j]
    as_ <- results$away_score[j]
    if (is.na(hs) || is.na(as_)) next

    # A tie is impossible in this sport - NBA games go to overtime until someone
    # wins - so unlike the NFL equivalent there is no tie branch. Guard anyway
    # rather than silently crediting the away side if ESPN ever reports one.
    if (hs == as_) {
      warning(sprintf("game %s came back %d-%d; refusing to grade a tie.",
                      rows$game_id[i], hs, as_), call. = FALSE)
      next
    }

    rows$is_completed[i]  <- TRUE
    rows$home_score[i]    <- hs
    rows$away_score[i]    <- as_
    rows$actual_margin[i] <- hs - as_
    winner <- if (hs > as_) rows$home_team[i] else rows$away_team[i]
    rows$actual_winner[i] <- winner
    rows$prediction_correct[i] <- identical(as.character(rows$predicted_winner[i]),
                                            as.character(winner))
    n_changed <- n_changed + 1L
  }

  list(rows = rows, n_changed = n_changed)
}

# ------------------------------------------------------------------------------
# Reconcile the counts that summarise the rows
# ------------------------------------------------------------------------------

#' Recompute the result-dependent summary fields from the patched rows
#'
#' Everything here is derived from `rows` alone. Fields describing the schedule
#' or the projection source are left exactly as the pipeline wrote them - see
#' the header for the full list and why.
recompute_summary <- function(payload) {
  rows <- payload$matchups
  done <- .rlr_is_true(rows$is_completed)

  payload$completed_games <- sum(done)
  payload$pending_games   <- sum(!done)

  slates <- payload$slates
  for (k in seq_len(nrow(slates))) {
    in_slate <- rows$slate == slates$slate[k]
    graded <- in_slate & done
    n_graded <- sum(graded)
    n_correct <- sum(.rlr_is_true(rows$prediction_correct) & graded)

    slates$graded_total[k]  <- n_graded
    slates$correct_total[k] <- n_correct
    # null, not 0, for a slate with nothing graded - that is how the exporter
    # writes it, and 0.0% would read as "we got every game wrong".
    slates$accuracy_pct[k] <- if (n_graded > 0) {
      round(n_correct / n_graded * 100, 1)
    } else {
      NA_real_
    }
  }
  payload$slates <- slates

  payload
}

# ------------------------------------------------------------------------------
# Write
# ------------------------------------------------------------------------------

#' Serialise the way the exporter does
#'
#' `na = "null"`. Verified empirically on the 2026-10-27 payload: a
#' fromJSON/toJSON round trip with this call is BYTE-IDENTICAL. `null = "null"`
#' instead DROPS null fields out of rows that have them, which breaks the JSON
#' contract the Next.js app and its vitest suite consume. If you change this
#' call, re-check the no-op round trip first.
.rlr_json_text <- function(x) {
  as.character(jsonlite::toJSON(x, pretty = TRUE, auto_unbox = TRUE,
                                na = "null", digits = 4))
}

#' Write only when the bytes would actually change
#'
#' The scheduled job runs three times a day whether or not anything happened.
#' Without this, every run rewrites `generated_at` and produces a commit that
#' says nothing - which trains you to ignore the commits that do matter.
#'
#' @return TRUE if the file was written
write_json_if_changed <- function(x, path) {
  new_text <- .rlr_json_text(x)
  if (file.exists(path)) {
    old_text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (trimws(old_text) == trimws(new_text)) return(FALSE)
  }
  writeLines(new_text, path, useBytes = TRUE)
  TRUE
}

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------

#' Refresh the committed web JSON with any newly finished results
#'
#' @param dates Explicit dates to sweep; NULL derives them from the payload.
#' @param lookback_days Used only when `dates` is NULL.
#' @param payload_path Path to matchups_slates.json.
#' @param fetcher Injectable ESPN reader, for tests. Takes dates, returns a
#'   data.frame shaped like espn_fetch_dates().
#' @param today Date treated as "now", for tests.
#' @return list(n_changed, dates, file)
refresh_live_results <- function(dates = NULL,
                                 lookback_days = RLR_DEFAULT_LOOKBACK_DAYS,
                                 payload_path = WEB_JSON_MATCHUPS_SLATES,
                                 fetcher = espn_fetch_dates,
                                 today = Sys.Date()) {
  if (!file.exists(payload_path)) {
    stop(sprintf("refresh_live_results(): no payload at %s - run the pipeline first.",
                 payload_path))
  }

  payload <- jsonlite::fromJSON(payload_path, simplifyVector = TRUE)
  payload$matchups$game_id <- as.character(payload$matchups$game_id)

  if (is.null(dates)) {
    dates <- pending_dates(payload$matchups, lookback_days, today)
  }
  if (length(dates) == 0) {
    return(list(n_changed = 0L, dates = character(0), file = NULL))
  }

  results <- fetcher(dates)
  patched <- apply_results(payload$matchups, results)

  if (patched$n_changed == 0) {
    return(list(n_changed = 0L, dates = dates, file = NULL))
  }

  payload$matchups <- patched$rows
  payload <- recompute_summary(payload)
  payload$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

  written <- write_json_if_changed(payload, payload_path)
  list(n_changed = patched$n_changed, dates = dates,
       file = if (written) payload_path else NULL)
}

# Entry point for the scheduled workflow.
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("refresh_live_results\\.R$", files))) return(invisible(NULL))

  args <- commandArgs(trailingOnly = TRUE)
  dates <- NULL
  lookback <- RLR_DEFAULT_LOOKBACK_DAYS

  if (length(args) >= 2) {
    dates <- as.character(seq(as.Date(args[1]), as.Date(args[2]), by = "day"))
  } else if (length(args) == 1 && grepl("^[0-9]+$", args[1])) {
    lookback <- as.integer(args[1])
  } else if (length(args) == 1) {
    dates <- as.character(as.Date(args[1]))
  }

  res <- refresh_live_results(dates = dates, lookback_days = lookback)

  cat(sprintf("Dates swept: %d%s\n", length(res$dates),
              if (length(res$dates)) sprintf(" (%s .. %s)", min(res$dates), max(res$dates)) else ""))
  cat(sprintf("Newly completed games written: %d\n", res$n_changed))
  if (is.null(res$file)) {
    cat("No files changed.\n")
  } else {
    cat(sprintf("Files rewritten: %s\n", basename(res$file)))
  }
})
