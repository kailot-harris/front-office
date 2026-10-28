# ==============================================================================
# tools/refresh_live_results.R - fill finished scores into the committed web JSON
#
# WHY THIS EXISTS, AND WHY IT IS NOT export_web_datasets.R
#
# export_web_datasets.R rebuilds all ten payloads from the pipeline caches
# (cache/schedules.rds, cache/team_ratings.rds, cache/accuracy_history.rds and
# the rest). This script does the one narrow job that has to happen several
# times a day during the season - "games finished, write their scores in" -
# using only the JSON already committed under web/public/data plus the public
# nflverse schedule file. No pipeline caches, no API key, no renv restore. That
# is what makes it runnable from a scheduled GitHub Action
# (.github/workflows/refresh-results.yml), which is the whole point: the full
# DAG runs once a day on one Windows box, and the site should not carry
# yesterday's scores for the other 23 hours.
#
# WHY nflverse games.csv AND NOT ESPN
#
# https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv
# carries `game_id` in the EXACT format the payload already uses
# ("2026_08_PIT_NO"), so the join is an exact key match with no team-abbreviation
# crosswalk. ESPN's scoreboard would need one (WSH/WAS, LAR/LA), and every alias
# table is a second thing to drift. The file is plain CSV read by base R
# `read.csv` - not even jsonlite is needed to fetch it. nflverse is the same
# upstream the repo already ingests via nflreadr, just the cheap path to it.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   * It never invents or alters a prediction. `home_win_prob`,
#     `projected_margin`, `projected_spread`, `projected_total` and the rest of
#     the projection block are copied through untouched. It only GRADES them,
#     and grading here is a pure function of fields already committed in the
#     file (see .rlr_grade below) - not a recomputation from current ratings,
#     which would be hindsight grading.
#   * It never adds or removes games, and never touches `active_week`,
#     `available_weeks` or `total_games`. A schedule change needs a real
#     pipeline re-export, and `active_week` is asserted independently by
#     publish_web.R's assertion B against CACHE_SCHEDULES - a value this script
#     cannot see and must not contradict.
#   * It never marks a game complete in a week AFTER `active_week`. The web
#     contract suite asserts exactly that ("no game after the active week is
#     marked completed", tests/contracts/invariants.test.ts), so patching a
#     Thursday-night game of week N+1 before the pipeline has advanced
#     `active_week` would make publish_web.R's assertion G fail and block the
#     publish. Those finals are counted and reported as deferred; the next full
#     run picks them up.
#
# THE model_diagnostics.json COUPLING - READ THIS BEFORE EDITING
#
# matchups_current_week.json cannot be patched alone. The contract suite asserts
# that the number of completed matchups equals the LAST element of
# model_diagnostics.json's `n_games_graded` series ("graded games reconcile with
# the diagnostics game count"). Marking 14 new finals complete without touching
# the diagnostics breaks that assertion, and therefore the publish gate.
#
# That reconciliation is honourable to do here because the three season metrics
# are a pure function of the committed payload: every graded row carries
# `home_win_prob` and the final score, which is all accuracy, Brier and log loss
# need. Verified on the 2026-10-27 payload - 107 games, recomputed 62.6% /
# 0.2341 / 0.6633 against the committed 62.6 / 0.2341 / 0.6634 (log loss differs
# in the 4th decimal only, from accuracy_tracker.R's own clamping).
#
# The row is UPDATED IN PLACE, not appended: the series is one row per pipeline
# evaluation, and a cheap top-up is not an evaluation. The authoritative row is
# rebuilt from cache/accuracy_history.rds by export_web_datasets.R section 7 on
# the next full run, so anything written here is replaced rather than
# accumulated - this script writes no .rds and owns no history.
#
# Run a full export_web_datasets.R pass whenever the pipeline is refreshed; this
# is a between-times top-up, not a replacement.
#
# Usage:
#   Rscript tools/refresh_live_results.R              # current season
#   Rscript tools/refresh_live_results.R 2026         # explicit season
# ==============================================================================

# ------------------------------------------------------------------------------
# Bootstrap: setwd() to this script's project root, then source siblings by bare
# filename (repo convention - the repo is deliberately flat). Same helper shape
# as tools/publish_web.R; kept local rather than shared because this script must
# stay runnable with jsonlite alone.
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

# config.R only - NOT logging_utils.R. config.R loads no packages and its only
# side effect is dir.create() on the cache/web dirs, so it is safe under the
# jsonlite-only install the scheduled workflow sets up. logging_utils.R writes
# into logs/, which a CI runner has no reason to carry.
source("config.R")

NFLVERSE_GAMES_CSV <-
  "https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv"

# Local null-coalesce. This script never sources logging_utils.R, which owns the
# canonical %||%, so this stays private rather than becoming a second public copy.
`%||%` <- function(a, b) if (is.null(a)) b else a

# Vectorised isTRUE. `is_completed` round-trips as logical with NA possible on a
# payload that predates the field, and `rows[rows$is_completed, ]` would then
# silently produce NA-filled rows rather than dropping them.
.rlr_is_true <- function(x) !is.na(x) & x

# ------------------------------------------------------------------------------
# Fetch
# ------------------------------------------------------------------------------

#' Fetch finished-game results for a season from the nflverse schedule file
#'
#' @param season Season year.
#' @param csv_reader Injectable reader, for tests. Takes a URL, returns a data.frame.
#' @return data.frame of game_id, home_score, away_score - finals only.
fetch_season_results <- function(season = CURRENT_SEASON,
                                 csv_reader = function(u) {
                                   utils::read.csv(u, stringsAsFactors = FALSE)
                                 }) {
  raw <- csv_reader(NFLVERSE_GAMES_CSV)

  need <- c("game_id", "season", "home_score", "away_score")
  missing <- setdiff(need, names(raw))
  if (length(missing)) {
    stop(sprintf("fetch_season_results(): games.csv is missing column(s): %s",
                 paste(missing, collapse = ", ")))
  }

  raw <- raw[as.integer(raw$season) == as.integer(season), , drop = FALSE]
  hs <- suppressWarnings(as.integer(raw$home_score))
  as_ <- suppressWarnings(as.integer(raw$away_score))

  # A scored row IS a final here: nflverse leaves both score columns empty until
  # a game is over and never carries a partial score. There is no status column
  # to consult, so "both scores present" is the only completeness signal - which
  # is why apply_results() additionally refuses to touch a row that is already
  # complete, rather than trusting this to be monotonic.
  keep <- !is.na(hs) & !is.na(as_)

  data.frame(
    game_id    = as.character(raw$game_id[keep]),
    home_score = hs[keep],
    away_score = as_[keep],
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
# Patch
# ------------------------------------------------------------------------------

#' Grade one finished game from fields the payload already carries
#'
#' Mirrors the invariants the contract suite enforces, so the two read the same:
#'   * actual_winner is the FULL FRANCHISE NAME ("Seattle Seahawks"), never the
#'     2-3 letter code - mixing those two ID spaces in one row is the join
#'     hazard CLAUDE.md warns about.
#'   * a tie is credited to NEITHER team (NA), not silently to the away side.
#'   * prediction_correct is (projected_margin > 0) == (the home team won), the
#'     same expression tests/contracts/invariants.test.ts uses, and is NA for a
#'     tie because the projection took a side and neither side won.
.rlr_grade <- function(row, home_score, away_score) {
  if (home_score == away_score) {
    row$actual_winner <- NA_character_
    row$prediction_correct <- NA
    return(row)
  }
  home_won <- home_score > away_score
  row$actual_winner <- if (home_won) row$home_team_name else row$away_team_name
  row$prediction_correct <- ((row$projected_margin > 0) == home_won)
  row
}

#' Patch finished results into committed matchup rows
#'
#' Only rows that are currently incomplete AND come back scored are touched, so
#' a re-run is a no-op and a partial upstream file can never blank out a score
#' that is already recorded.
#'
#' @param rows data.frame of matchup rows read from matchups_current_week.json
#' @param results data.frame from fetch_season_results()
#' @param active_week The payload's own active_week; finals beyond it are deferred.
#' @return list(rows, n_changed, n_deferred)
apply_results <- function(rows, results, active_week) {
  if (nrow(rows) == 0 || nrow(results) == 0) {
    return(list(rows = rows, n_changed = 0L, n_deferred = 0L))
  }

  idx <- match(rows$game_id, results$game_id)
  n_changed <- 0L
  n_deferred <- 0L

  for (i in seq_len(nrow(rows))) {
    j <- idx[i]
    if (is.na(j)) next
    if (isTRUE(rows$is_completed[i])) next

    hs <- results$home_score[j]
    ascore <- results$away_score[j]
    if (is.na(hs) || is.na(ascore)) next

    # See the header: completing a game past active_week would fail the contract
    # suite and block the publish. Defer rather than half-publish.
    if (as.integer(rows$week[i]) > as.integer(active_week)) {
      n_deferred <- n_deferred + 1L
      next
    }

    rows$is_completed[i] <- TRUE
    rows$home_score[i]   <- hs
    rows$away_score[i]   <- ascore
    rows[i, ] <- .rlr_grade(rows[i, ], hs, ascore)
    n_changed <- n_changed + 1L
  }

  list(rows = rows, n_changed = n_changed, n_deferred = n_deferred)
}

# ------------------------------------------------------------------------------
# Diagnostics reconciliation
# ------------------------------------------------------------------------------

#' Recompute the three season metrics from the graded payload rows
#'
#' Pure function of committed fields, and a deliberate transcription of
#' grade_walkforward_games() in tools/backtest_common.R (~line 379) - the
#' function the pipeline itself grades with. The three details that matter, all
#' taken from there rather than from first principles:
#'
#'   * EVERY completed game counts, ties included. `home_win` is
#'     `home_score > away_score`, so a tie scores as a home loss and a
#'     prediction of the home side is simply wrong. Excluding ties instead
#'     changes the denominator and reports a different number: on the
#'     2026-10-27 payload that is 67/106 = 63.2% against the pipeline's
#'     67/107 = 62.6%.
#'   * the log-loss probability clamp is 1e-6 (`pmin(pmax(p, 1e-6), 1 - 1e-6)`),
#'     not an arbitrary epsilon.
#'   * the probability is the payload's own `home_win_prob`, which is the
#'     exporter's record of `home_win_prob_prod`. Nothing is re-derived from
#'     current ratings - that would be hindsight grading.
#'
#' Verified against the committed 2026-10-27 diagnostics: 107 games, accuracy
#' 62.6% and Brier 0.2341 reproduced exactly; log loss comes back 0.6633 against
#' a committed 0.6634. That last 1e-4 is not a bug to chase - the payload rounds
#' `home_win_prob` to 3 decimals (0.605), while the pipeline computed its log
#' loss from the unrounded `home_win_prob_prod`. Grading from committed data
#' cannot recover the lost digits, and no test or display depends on the 4th
#' decimal. The authoritative value returns on the next full run.
#'
#' @param rows All matchup rows, post-patch.
#' @param clamp Log-loss probability clamp, matching backtest_common.R.
#' @return list(n_games_graded, overall_accuracy, overall_brier, overall_logloss)
#'   or NULL when nothing is completed yet.
recompute_diagnostics <- function(rows, clamp = 1e-6) {
  done <- rows[.rlr_is_true(rows$is_completed), , drop = FALSE]
  done <- done[!is.na(done$home_score) & !is.na(done$away_score), , drop = FALSE]
  if (nrow(done) == 0) return(NULL)

  home_win <- as.integer(done$home_score > done$away_score)
  p <- as.numeric(done$home_win_prob)
  correct <- as.integer((p > 0.5) == (home_win == 1L))

  p_clamped <- pmin(pmax(p, clamp), 1 - clamp)
  p_actual <- ifelse(home_win == 1L, p_clamped, 1 - p_clamped)

  list(
    n_games_graded   = nrow(done),
    overall_accuracy = round(mean(correct) * 100, 1),
    overall_brier    = round(mean((p - home_win)^2), 4),
    overall_logloss  = round(-mean(log(p_actual)), 4)
  )
}

#' Update the last diagnostics row in place to match the patched payload
#'
#' The series is one row per pipeline evaluation; a cheap top-up is not an
#' evaluation, so this overwrites the tail rather than appending. Fields that are
#' model parameters rather than game counts - margin_sigma, home_field_adv,
#' ensemble_weights, calibration_curve - are left exactly as the pipeline wrote
#' them. brier_baseline is a constant (0.25) and brier_improvement is derived
#' from it rather than assumed.
#'
#' @return list(diag, changed)
reconcile_diagnostics <- function(diag, metrics) {
  if (is.null(metrics)) return(list(diag = diag, changed = FALSE))

  n <- length(diag$n_games_graded)
  if (n == 0) return(list(diag = diag, changed = FALSE))

  if (identical(as.integer(diag$n_games_graded[n]),
                as.integer(metrics$n_games_graded))) {
    return(list(diag = diag, changed = FALSE))
  }

  diag$n_games_graded[n]   <- metrics$n_games_graded
  diag$overall_accuracy[n] <- metrics$overall_accuracy
  diag$overall_brier[n]    <- metrics$overall_brier
  diag$overall_logloss[n]  <- metrics$overall_logloss

  baseline <- diag$brier_baseline
  baseline_n <- if (length(baseline) >= n) baseline[n] else baseline[1]
  if (length(diag$brier_improvement) >= n && !is.na(baseline_n) && baseline_n > 0) {
    diag$brier_improvement[n] <-
      round((baseline_n - metrics$overall_brier) / baseline_n * 100, 2)
  }
  # last_evaluated is a per-row timestamp, not a stamp of "when this file was
  # written" - the row now describes more games, so it gets the current time.
  if (length(diag$last_evaluated) >= n) {
    diag$last_evaluated[n] <- format(Sys.time(), "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
  }

  list(diag = diag, changed = TRUE)
}

# ------------------------------------------------------------------------------
# Write
# ------------------------------------------------------------------------------

#' Serialise the way export_web_datasets.R's write_json_clean() does
#'
#' `na = "null"`, NOT `null = "null"`. Verified empirically on the 2026-10-27
#' payload: a fromJSON/toJSON round trip with `na = "null"` is BYTE-IDENTICAL,
#' while `null = "null"` (what the exporter passes, building its data
#' differently) DROPS the five null fields from every pending game - 1,320 diff
#' lines, and a broken JSON contract for the Next.js app and its vitest suite.
#' If you change this call, re-check the no-op round trip first.
.rlr_json_text <- function(x) {
  as.character(jsonlite::toJSON(x, pretty = TRUE, auto_unbox = TRUE,
                                na = "null", digits = 4))
}

#' Write only when the bytes would actually change
#'
#' The scheduled job runs three times a day whether or not anything happened.
#' Without this, every run rewrites the file and produces a commit that says
#' nothing - which trains you to ignore the commits that do matter.
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
#' @param season Season year.
#' @param matchups_path Path to matchups_current_week.json.
#' @param diagnostics_path Path to model_diagnostics.json.
#' @param csv_reader Injectable reader, for tests.
#' @return list(n_changed, n_deferred, files, metrics)
refresh_live_results <- function(season = CURRENT_SEASON,
                                 matchups_path = WEB_JSON_MATCHUPS_CURRENT_WEEK,
                                 diagnostics_path = WEB_JSON_MODEL_DIAGNOSTICS,
                                 csv_reader = NULL) {
  if (!file.exists(matchups_path)) {
    stop(sprintf("refresh_live_results(): no payload at %s - run export_web_datasets.R first.",
                 matchups_path))
  }

  results <- if (is.null(csv_reader)) {
    fetch_season_results(season)
  } else {
    fetch_season_results(season, csv_reader)
  }

  payload <- jsonlite::fromJSON(matchups_path, simplifyVector = TRUE)
  patched <- apply_results(payload$matchups, results, payload$active_week)
  payload$matchups <- patched$rows

  changed_files <- character(0)
  metrics <- NULL

  if (patched$n_changed > 0) {
    if (write_json_if_changed(payload, matchups_path)) {
      changed_files <- c(changed_files, matchups_path)
    }

    metrics <- recompute_diagnostics(payload$matchups)
    if (file.exists(diagnostics_path)) {
      diag <- jsonlite::fromJSON(diagnostics_path, simplifyVector = TRUE)
      rec <- reconcile_diagnostics(diag, metrics)
      if (rec$changed && write_json_if_changed(rec$diag, diagnostics_path)) {
        changed_files <- c(changed_files, diagnostics_path)
      }
    } else {
      warning(sprintf("no diagnostics at %s - the contract suite's graded-count reconciliation will fail.",
                      diagnostics_path), call. = FALSE)
    }
  }

  list(n_changed = patched$n_changed, n_deferred = patched$n_deferred,
       files = changed_files, metrics = metrics)
}

# Entry point for the scheduled workflow: Rscript tools/refresh_live_results.R [season]
local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("refresh_live_results\\.R$", files))) return(invisible(NULL))

  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else CURRENT_SEASON
  res <- refresh_live_results(season = season)

  cat(sprintf("Newly completed games written: %d\n", res$n_changed))
  if (res$n_deferred > 0) {
    cat(sprintf("Finals deferred (week > active_week, see header): %d\n", res$n_deferred))
  }
  if (!is.null(res$metrics)) {
    m <- res$metrics
    cat(sprintf("Diagnostics reconciled: %d graded, accuracy %.1f%%, Brier %.4f, log loss %.4f\n",
                m$n_games_graded, m$overall_accuracy, m$overall_brier, m$overall_logloss))
  }
  if (length(res$files) == 0) {
    cat("No files changed.\n")
  } else {
    cat(sprintf("Files rewritten: %s\n", paste(basename(res$files), collapse = ", ")))
  }
})
