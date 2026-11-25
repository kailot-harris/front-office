# ==============================================================================
# tools/log_momentum_forward.R
#
# Forward log of the Momentum Board. Each pipeline run appends, for the run date
# only, what the board said about every team BEFORE that team's next games were
# played: the combined score, its four components (form, trend, residual, Elo
# change) for each window (5, 10, 18), the team's pregame Elo and games played.
# tools/score_forward_log.R later compares these logged values with the games
# that followed.
#
# Why: the momentum study (docs/research/momentum_measures_study.md) found no
# reliable momentum signal on past seasons. A forward log asks the same question
# on games that had not happened when the value was written, so the answer cannot
# be fitted after the fact.
#
# Rules
#   * Values are read from web/public/data/momentum_board.json exactly as the
#     board build published them; nothing is recomputed, filled or imputed. A
#     null in the board is an empty cell here.
#   * Forward only: rows are written for the run date (as_of == today) and no
#     other. A past or future as_of is refused with an error. No backfill, no
#     reconstruction, no seeding from study output.
#   * The board must be fresh: generated today (local date) and through a date
#     before the run date (so the run date's games are not in it). Otherwise the
#     logger warns and writes nothing.
#   * Idempotent: the key is (as_of_date, team). A row whose key is already in
#     the log is never replaced and never appended again.
#   * Append-only: the file is never rewritten. If its header differs from the
#     columns below, the logger warns and writes nothing.
#
# Output: data/history/momentum_forward_log.csv (MOMENTUM_FORWARD_LOG in
# config.R), tracked in git and staged by tools/publish_web.R.
#
# Usage: Rscript tools/log_momentum_forward.R   (or the run_full_pipeline.R stage)
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

FORWARD_LOG_WINDOWS <- c(5L, 10L, 18L)
FORWARD_LOG_WINDOW_FIELDS <- c("combined", "combined_rank", "form_z", "trend_z", "residual_z", "elo_z",
                               "form", "trend", "residual", "elo_change", "games_in_window")
FORWARD_LOG_COLUMNS <- c(
  "as_of_date", "logged_at_utc", "board_generated_at", "through_date", "season",
  "team", "games_played", "elo_pregame",
  unlist(lapply(FORWARD_LOG_WINDOWS, function(w) sprintf("w%d_%s", w, FORWARD_LOG_WINDOW_FIELDS)))
)

.fl_warn <- function(fmt, ...) {
  msg <- sprintf(fmt, ...)
  message(sprintf(">>> [WARN] log_momentum_forward.R: %s", msg))
  invisible(msg)
}

# NULL / missing -> NA; never a substitute value.
.fl_num <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else as.numeric(x[[1]])
.fl_chr <- function(x) if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1]])
.fl_get <- function(x, path) {
  for (k in path) { if (is.null(x) || !is.list(x)) return(NULL); x <- x[[k]] }
  x
}

#' Local calendar date of the board's generated_at (ISO 8601 UTC).
.fl_generated_local_date <- function(generated_at, tz = "") {
  t <- as.POSIXct(generated_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(t)) return(as.Date(NA))
  as.Date(format(t, tz = tz, usetz = FALSE))
}

#' One row per team from the board, values as published.
fl_board_rows <- function(board, as_of, logged_at_utc) {
  boards <- board$boards
  teams <- character(0)
  for (w in FORWARD_LOG_WINDOWS) {
    rows <- .fl_get(boards, c(as.character(w), "rows"))
    teams <- union(teams, vapply(rows, function(r) .fl_chr(r$team), character(1)))
  }
  teams <- sort(teams[!is.na(teams)])
  if (!length(teams)) return(NULL)

  find_row <- function(w, tm) {
    rows <- .fl_get(boards, c(as.character(w), "rows"))
    for (r in rows) if (identical(.fl_chr(r$team), tm)) return(r)
    NULL
  }

  out <- lapply(teams, function(tm) {
    rec <- list(as_of_date = format(as_of), logged_at_utc = logged_at_utc,
                board_generated_at = .fl_chr(board$generated_at),
                through_date = .fl_chr(board$through_date), season = .fl_chr(board$season),
                team = tm, games_played = NA_real_, elo_pregame = NA_real_)
    for (w in FORWARD_LOG_WINDOWS) {
      r <- find_row(w, tm)
      if (!is.null(r)) {
        # games_played and the current Elo are window-independent; take the
        # first window that carries them.
        if (is.na(rec$games_played)) rec$games_played <- .fl_num(r$games_played)
        if (is.na(rec$elo_pregame)) rec$elo_pregame <- .fl_num(.fl_get(r, c("elo", "current")))
      }
      cs <- if (is.null(r)) NULL else r$combined_score
      comp <- if (is.null(cs)) NULL else cs$components
      vals <- list(
        combined        = .fl_num(cs$value),
        combined_rank   = .fl_num(cs$rank),
        form_z          = .fl_num(comp$form_z),
        trend_z         = .fl_num(comp$trend_z),
        residual_z      = .fl_num(comp$residual_z),
        elo_z           = .fl_num(comp$elo_z),
        form            = .fl_num(.fl_get(r, c("opponent_adjusted_form", "value"))),
        trend           = .fl_num(.fl_get(r, c("sort_keys", "net_rating_change"))),
        residual        = .fl_num(.fl_get(r, c("model_residual", "value"))),
        elo_change      = .fl_num(.fl_get(r, c("elo", "change_in_window"))),
        games_in_window = .fl_num(if (is.null(r)) NULL else r$games_in_window))
      for (f in FORWARD_LOG_WINDOW_FIELDS) rec[[sprintf("w%d_%s", w, f)]] <- vals[[f]]
    }
    as.data.frame(rec[FORWARD_LOG_COLUMNS], stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

#' Append today's rows to the forward log.
#'
#' @param as_of  run date; must equal `today`.
#' @param today  the current local date (a parameter only so tests can pin it).
#' @return invisible list(written = <rows appended>, reason = <why not, or NULL>, rows = <data.frame>)
log_momentum_forward <- function(board_path, log_path, as_of = Sys.Date(), today = Sys.Date(),
                                 now = Sys.time()) {
  as_of <- as.Date(as_of); today <- as.Date(today)
  # Guard 1: forward only. Past dates are history and are never written.
  if (is.na(as_of) || as_of < today)
    stop(sprintf("log_momentum_forward refuses as_of %s: it is before today (%s); the forward log never writes past dates.",
                 format(as_of), format(today)), call. = FALSE)
  if (as_of > today)
    stop(sprintf("log_momentum_forward refuses as_of %s: it is after today (%s).", format(as_of), format(today)),
         call. = FALSE)
  none <- function(reason) invisible(list(written = 0L, reason = reason, rows = NULL))

  # Guard 2: the board must exist and describe today's run.
  if (!file.exists(board_path)) return(none(.fl_warn("momentum board %s is missing; nothing logged for %s.", basename(board_path), format(as_of))))
  board <- tryCatch(jsonlite::fromJSON(board_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(board)) return(none(.fl_warn("momentum board %s could not be read; nothing logged for %s.", basename(board_path), format(as_of))))
  gen_date <- .fl_generated_local_date(.fl_chr(board$generated_at))
  if (is.na(gen_date) || gen_date != as_of)
    return(none(.fl_warn("momentum board is stale (generated_at %s, local date %s; run date %s); nothing logged.",
                         .fl_chr(board$generated_at), format(gen_date), format(as_of))))
  through <- as.Date(.fl_chr(board$through_date))
  if (is.na(through) || through >= as_of)
    return(none(.fl_warn("momentum board through_date %s is not before the run date %s, so it may already include games of %s; nothing logged.",
                         format(through), format(as_of), format(as_of))))

  rows <- fl_board_rows(board, as_of, format(as.POSIXct(now), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (is.null(rows) || !nrow(rows)) return(none(.fl_warn("momentum board has no team rows; nothing logged for %s.", format(as_of))))

  # Guard 3: idempotent, append-only. Keys already logged are left alone.
  exists_already <- file.exists(log_path) && file.info(log_path)$size > 0
  if (exists_already) {
    old <- utils::read.csv(log_path, colClasses = "character", na.strings = "", check.names = FALSE)
    if (!identical(names(old), FORWARD_LOG_COLUMNS))
      return(none(.fl_warn("%s has a different header than this logger writes; nothing appended (the file is never rewritten).", basename(log_path))))
    have <- paste(old$as_of_date, old$team)
    rows <- rows[!paste(rows$as_of_date, rows$team) %in% have, , drop = FALSE]
  }
  if (!nrow(rows)) {
    message(sprintf(">>> log_momentum_forward: %s already logged for every team; nothing appended.", format(as_of)))
    return(invisible(list(written = 0L, reason = "already logged", rows = rows)))
  }
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(rows, log_path, sep = ",", na = "", row.names = FALSE,
                     col.names = !exists_already, append = exists_already, qmethod = "double")
  message(sprintf(">>> log_momentum_forward: appended %d row(s) for %s (board through %s) to %s",
                  nrow(rows), format(as_of), format(through), basename(log_path)))
  invisible(list(written = nrow(rows), reason = NULL, rows = rows))
}

#' Pipeline entry (run_full_pipeline.R call_fn). Never stops the pipeline for a
#' missing or stale board: those are [WARN] lines and nothing is written.
run_log_momentum_forward <- function() {
  if (!exists("WEB_JSON_MOMENTUM_BOARD") || !exists("MOMENTUM_FORWARD_LOG")) source("config.R")
  log_momentum_forward(WEB_JSON_MOMENTUM_BOARD, MOMENTUM_FORWARD_LOG)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("log_momentum_forward\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN", ""))) return(invisible(NULL))
  setwd(normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE))
  source("config.R")
  run_log_momentum_forward()
})
