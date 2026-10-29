# ==============================================================================
# tools/refresh_live_results.R - fill finished scores into the committed web JSON
#
# WHY THIS EXISTS, AND WHY IT IS NOT build_matchups_dataset.R
#
# build_matchups_dataset.R rebuilds the whole slate payload from the pipeline
# caches (the wehoop schedule cache, box scores, standings, prediction log).
# Those are gitignored, so it can only run on a machine that has run the pipeline.
# This script does the one narrow job that has to happen several times a day
# during the season - "games finished, write their scores in" - using only the
# JSON already committed under web/public/data plus ESPN's public scoreboard.
# No caches, no API key, no renv restore. That is what makes it runnable from a
# scheduled GitHub Action (.github/workflows/refresh-results.yml).
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It never invents or alters a prediction. `projected_margin`, `home_win_prob`,
#     `predicted_winner`, `has_prediction`, `has_logged_prediction`, and
#     `projection_basis` are copied through untouched.
#   * NOTE ON GRADING: Per WNBA contracts, `team_rating_differential` must NEVER
#     be graded (`is_graded` remains FALSE, `prediction_correct` null). Only games
#     with a logged prediction (`has_logged_prediction == TRUE`, or basis
#     `logged_model` / `logged_model_prob_only`) are graded upon completion.
#   * It never adds or removes games, and never touches `total_games`,
#     `available_weeks`, `weeks[].total_games`, or `active_week`.
#
# WHAT IT DOES RECONCILE
#
# Marking games complete without updating summary counts leaves the payload
# internally contradictory. The script recomputes from patched rows:
#   * `summary$completed_games`, `summary$pending_games`, `summary$graded_games`,
#     `summary$correct_games`, `summary$accuracy_pct`, `summary$graded_games_available`,
#     `summary$grading_state`, `summary$played_without_logged_prediction`
#   * Each week's `completed_games`, `pending_games`, `graded_games`,
#     `correct_games`, `accuracy_pct`
#
# Usage:
#   Rscript tools/refresh_live_results.R           # default 3-day lookback
#   Rscript tools/refresh_live_results.R 5         # widen lookback to 5 days
#   Rscript tools/refresh_live_results.R 2026-09-10 2026-09-15  # explicit range
# ==============================================================================

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

source("config.R")
source("tools/espn_scoreboard.R")

RLR_DEFAULT_LOOKBACK_DAYS <- 3L

.rlr_is_true <- function(x) !is.na(x) & x

# ------------------------------------------------------------------------------
# Patch
# ------------------------------------------------------------------------------

#' Which dates to ask ESPN about
pending_dates <- function(rows, lookback_days = RLR_DEFAULT_LOOKBACK_DAYS,
                          today = Sys.Date()) {
  d <- as.Date(substr(as.character(rows$game_date), 1, 10))
  open <- !.rlr_is_true(rows$is_completed) & !is.na(d) &
    d <= today & d >= (today - as.integer(lookback_days))
  sort(unique(as.character(d[open])))
}

#' Patch finished results into committed matchup rows
#'
#' @param rows Matchup data.frame (or list).
#' @param results ESPN scoreboard data.frame.
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

    if (hs == as_) {
      warning(sprintf("game %s came back %d-%d; refusing to grade a tie.",
                      rows$game_id[i], hs, as_), call. = FALSE)
      next
    }

    rows$is_completed[i]  <- TRUE
    rows$home_score[i]    <- as.integer(hs)
    rows$away_score[i]    <- as.integer(as_)
    rows$actual_margin[i] <- as.integer(hs - as_)
    winner <- if (hs > as_) rows$home_team[i] else rows$away_team[i]
    rows$actual_winner[i] <- as.character(winner)

    # Prediction grading contract:
    # Per WNBA contracts, basis 'team_rating_differential' is NEVER graded.
    # Only games with logged prediction (has_logged_prediction == TRUE or
    # basis %in% c("logged_model", "logged_model_prob_only")) can be graded.
    can_grade <- isTRUE(rows$has_logged_prediction[i]) ||
      identical(as.character(rows$projection_basis[i]), "logged_model") ||
      identical(as.character(rows$projection_basis[i]), "logged_model_prob_only")

    if (can_grade && !identical(as.character(rows$projection_basis[i]), "team_rating_differential")) {
      rows$is_graded[i] <- TRUE
      rows$prediction_correct[i] <- identical(as.character(rows$predicted_winner[i]),
                                              as.character(winner))
    } else {
      rows$is_graded[i] <- FALSE
      rows$prediction_correct[i] <- NA
    }

    n_changed <- n_changed + 1L
  }

  list(rows = rows, n_changed = n_changed)
}

# ------------------------------------------------------------------------------
# Reconcile summary and week counts
# ------------------------------------------------------------------------------

#' Recompute the result-dependent summary fields and week rollups
recompute_summary <- function(payload) {
  rows <- payload$matchups
  done <- .rlr_is_true(rows$is_completed)
  n_total <- nrow(rows)
  n_done <- sum(done)
  n_pending <- sum(!done)

  graded <- .rlr_is_true(rows$is_graded)
  n_graded <- sum(graded)
  n_correct <- sum(graded & .rlr_is_true(rows$prediction_correct))

  # Summary update
  payload$summary$completed_games <- as.integer(n_done)
  payload$summary$pending_games   <- as.integer(n_pending)
  payload$summary$graded_games    <- as.integer(n_graded)
  payload$summary$correct_games   <- if (n_graded > 0) as.integer(n_correct) else NA_integer_
  payload$summary$accuracy_pct    <- if (n_graded > 0) round(100 * n_correct / n_graded, 1) else NA_real_
  payload$summary$graded_games_available <- (n_graded > 0)

  grading_state <- if (n_graded == 0) {
    "no_games_graded_yet"
  } else if (n_graded == n_done) {
    "complete"
  } else {
    "partial"
  }
  payload$summary$grading_state <- grading_state
  payload$summary$played_without_logged_prediction <- as.integer(
    sum(done & !.rlr_is_true(rows$has_logged_prediction))
  )

  # Active week update: last week containing a played game
  played_weeks <- sort(unique(rows$week[done]))
  if (length(played_weeks) > 0) {
    payload$active_week <- as.integer(max(played_weeks))
  }

  # Weeks rollup update
  weeks <- payload$weeks
  for (k in seq_len(nrow(weeks))) {
    w_id <- weeks$week[k]
    in_w <- rows$week == w_id
    w_done <- in_w & done
    w_n_done <- sum(w_done)
    w_n_pending <- sum(in_w & !done)

    w_graded <- in_w & graded
    w_n_graded <- sum(w_graded)
    w_n_correct <- sum(w_graded & .rlr_is_true(rows$prediction_correct))

    weeks$completed_games[k] <- as.integer(w_n_done)
    weeks$pending_games[k]   <- as.integer(w_n_pending)
    weeks$graded_games[k]    <- as.integer(w_n_graded)
    weeks$correct_games[k]   <- if (w_n_graded > 0) as.integer(w_n_correct) else NA_integer_
    weeks$accuracy_pct[k]    <- if (w_n_graded > 0) round(100 * w_n_correct / w_n_graded, 1) else NA_real_
  }
  payload$weeks <- weeks

  payload
}

# ------------------------------------------------------------------------------
# Write
# ------------------------------------------------------------------------------

.rlr_json_text <- function(x) {
  # Preserve season_types as JSON array even if length 1 by wrapping in I()
  if (is.data.frame(x$weeks) && "season_types" %in% names(x$weeks)) {
    x$weeks$season_types <- lapply(x$weeks$season_types, function(st) I(as.character(st)))
  }
  if (!is.null(x$available_weeks)) {
    x$available_weeks <- I(as.integer(x$available_weeks))
  }
  as.character(jsonlite::toJSON(x, pretty = TRUE, auto_unbox = TRUE,
                                na = "null", digits = 4))
}

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
#' @param fetcher Injectable ESPN reader, for tests.
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
