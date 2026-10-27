# Independent truth check for the game results inside web/public/data/matchups_slates.json.
#
# Answers one question: are the finished games in the payload ACTUALLY what happened?
#
# Every other check in this repo is internal. publish_web.R's assertions ask when a file was
# written (A), whether its slate label matches the schedule cache (B), whether its bytes
# changed (C), what the log said (D), whose branch it is on (E), whether its embedded stamp is
# fresh (F) and whether its numbers agree with each other (G). None of them asks whether the
# numbers are TRUE — a payload can be fresh, self-consistent, contract-clean and confidently
# wrong, because every engine here falls back to a labelled synthetic value rather than failing.
# This file closes that gap by going outside the estate: it re-fetches final scores from ESPN's
# public scoreboard and compares them game by game.
#
# ESPN is the right arbiter here and not an arbitrary third party: hoopR's load_nba_* release
# assets are themselves built from ESPN, and this payload carries ESPN game_ids, so a
# disagreement is a real ingestion or grading defect rather than two sources differing.
# The flip side is that this is NOT a fully independent source — it cannot catch an error ESPN
# itself made upstream. It catches the failure that actually happens: stale, missing or
# mis-graded results on our side.
#
# READ-ONLY. It writes nothing and touches no cache. Exit status 0 when every finished game in
# the payload matches and nothing finished is missing, 1 otherwise, so a scheduled caller or a
# pre-publish step can branch on it.
#
# Usage:
#   Rscript tools/verify_results_vs_espn.R                  # auto: season start -> today
#   Rscript tools/verify_results_vs_espn.R 2026-10-25        # one date
#   Rscript tools/verify_results_vs_espn.R 2026-10-20 2026-10-26   # inclusive range

suppressPackageStartupMessages({
  library(jsonlite)
})

# Bootstrap: this repo's convention is a flat root sourced by bare filename.
.vr_project_root <- function() {
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
  stop("verify_results_vs_espn.R: cannot locate the project root (no config.R found).")
}
local({
  root <- .vr_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})
source("config.R")

# ------------------------------------------------------------------------------
# Team abbreviation dialect. ESPN's scoreboard feed and the hoopR-derived payload
# disagree on a handful of codes; these are spelling differences, not mismatches,
# and treating them as mismatches would make the check cry wolf on every run.
# ------------------------------------------------------------------------------
ESPN_ALIAS <- c(UTAH = "UTA", NY = "NYK", WSH = "WAS", GS = "GSW",
                SA = "SAS", NO = "NOP", PHO = "PHX", NOLA = "NOP")
.vr_norm <- function(x) {
  x <- toupper(trimws(as.character(x)))
  hit <- x %in% names(ESPN_ALIAS)
  x[hit] <- ESPN_ALIAS[x[hit]]
  x
}

ESPN_SCOREBOARD <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=%s"

# ESPN rejects a default R user agent with 403, so a browser UA is required rather than
# cosmetic. One request per date; the feed is keyed by a single YYYYMMDD.
.vr_fetch_date <- function(d) {
  url <- sprintf(ESPN_SCOREBOARD, format(as.Date(d), "%Y%m%d"))
  txt <- tryCatch({
    con <- url(url, open = "rb", headers = c("User-Agent" = "Mozilla/5.0"))
    on.exit(close(con), add = TRUE)
    paste(readLines(con, warn = FALSE), collapse = "")
  }, error = function(e) {
    warning(sprintf("ESPN fetch failed for %s: %s", d, conditionMessage(e)), call. = FALSE)
    NULL
  })
  if (is.null(txt) || !nzchar(txt)) return(NULL)
  j <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(j) || !length(j$events)) return(NULL)

  rows <- lapply(j$events, function(e) {
    comp <- e$competitions[[1]]
    home <- away <- NA_character_
    hs <- as_ <- NA_integer_
    for (t in comp$competitors) {
      ab <- .vr_norm(t$team$abbreviation)
      sc <- suppressWarnings(as.integer(t$score))
      if (identical(t$homeAway, "home")) { home <- ab; hs <- sc } else { away <- ab; as_ <- sc }
    }
    data.frame(
      game_id    = as.character(e$id),
      game_date  = as.character(as.Date(d)),
      away_team  = away, away_score = as_,
      home_team  = home, home_score = hs,
      is_final   = isTRUE(comp$status$type$completed),
      state      = as.character(comp$status$type$name %||% NA_character_),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Comparison. Three distinct defects are reported separately because they have
# different causes and different fixes:
#   MISSING_RESULT - ESPN has a final, the payload still shows the game pending.
#                    This is the staleness signature: the pull ran before the
#                    upstream hoopR build carried that night's games.
#   SCORE / WINNER / MARGIN - the payload has a result and it is wrong. An
#                    ingestion or grading defect, and far more serious.
#   PREMATURE      - the payload calls a game complete that ESPN does not.
# ------------------------------------------------------------------------------
main <- function() {
  argv <- commandArgs(trailingOnly = TRUE)
  path <- WEB_JSON_MATCHUPS_SLATES
  if (!file.exists(path)) stop(sprintf("payload absent: %s", path))
  pay <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  m <- pay$matchups
  m$game_id <- as.character(m$game_id)
  m$game_date <- substr(as.character(m$game_date), 1, 10)

  if (length(argv) >= 2) {
    dates <- seq(as.Date(argv[1]), as.Date(argv[2]), by = "day")
  } else if (length(argv) == 1) {
    dates <- as.Date(argv[1])
  } else {
    start <- as.Date(pay$season_start_date)
    dates <- seq(start, min(Sys.Date(), as.Date(pay$season_end_date)), by = "day")
  }
  # Only ask ESPN about dates the payload actually schedules games on.
  dates <- dates[as.character(dates) %in% unique(m$game_date)]

  cat("================================================================\n")
  cat(sprintf("NBA results truth check  -  payload vs ESPN scoreboard\n"))
  cat("================================================================\n")
  cat(sprintf("  payload          : %s\n", path))
  cat(sprintf("  generated_at     : %s\n", pay$generated_at %||% "<none>"))
  cat(sprintf("  payload says     : active_slate=%s completed=%s pending=%s\n",
              pay$active_slate, pay$completed_games, pay$pending_games))
  cat(sprintf("  dates checked    : %d (%s .. %s)\n", length(dates),
              min(dates), max(dates)))
  cat(sprintf("  arbiter          : ESPN scoreboard (hoopR's own upstream)\n\n"))

  truth <- do.call(rbind, lapply(dates, .vr_fetch_date))
  if (is.null(truth) || !nrow(truth)) {
    cat("  [FAIL] ESPN returned no games for any requested date - cannot verify.\n")
    return(1L)
  }

  cmp <- merge(m, truth, by = "game_id", suffixes = c("_pay", "_espn"))
  verified <- character(0); problems <- character(0)
  missing_final <- 0L; wrong <- 0L; premature <- 0L
  # Counted separately from `verified`, which also holds rows that are correctly still
  # pending. Only a game both sides call final and agree on is a verified RESULT.
  verified_finals <- 0L; agreed_pending <- 0L

  for (i in seq_len(nrow(cmp))) {
    r <- cmp[i, ]
    tags <- character(0)
    if (!identical(.vr_norm(r$away_team_pay), r$away_team_espn) ||
        !identical(.vr_norm(r$home_team_pay), r$home_team_espn)) tags <- c(tags, "TEAMS")

    pay_done <- isTRUE(r$is_completed)
    if (r$is_final && !pay_done) { tags <- c(tags, "MISSING_RESULT"); missing_final <- missing_final + 1L }
    if (!r$is_final && pay_done) { tags <- c(tags, "PREMATURE"); premature <- premature + 1L }

    if (r$is_final && pay_done) {
      bad <- character(0)
      if (!identical(as.integer(r$home_score_pay), r$home_score_espn) ||
          !identical(as.integer(r$away_score_pay), r$away_score_espn)) bad <- c(bad, "SCORE")
      exp_win <- if (r$home_score_espn > r$away_score_espn) r$home_team_espn else r$away_team_espn
      if (!identical(.vr_norm(r$actual_winner), exp_win)) bad <- c(bad, "WINNER")
      exp_margin <- r$home_score_espn - r$away_score_espn
      if (!identical(as.integer(r$actual_margin), as.integer(exp_margin))) bad <- c(bad, "MARGIN")
      if (length(bad)) { tags <- c(tags, bad); wrong <- wrong + 1L }
    }

    line <- sprintf("  %s %-10s %3s @ %-3s  payload %3s-%-3s  espn %3s-%-3s  %s",
                    r$game_date_pay, r$game_id,
                    r$away_team_pay, r$home_team_pay,
                    ifelse(is.na(r$away_score_pay), "--", r$away_score_pay),
                    ifelse(is.na(r$home_score_pay), "--", r$home_score_pay),
                    r$away_score_espn, r$home_score_espn, r$state)
    if (length(tags)) {
      problems <- c(problems, paste0(line, "  <<< ", paste(tags, collapse = ",")))
    } else {
      verified <- c(verified, line)
      if (r$is_final && pay_done) verified_finals <- verified_finals + 1L else
        agreed_pending <- agreed_pending + 1L
    }
  }

  cat(sprintf("-- Verified exact: %d game(s) ------------------------------------\n", length(verified)))
  if (length(verified)) cat(paste(verified, collapse = "\n"), "\n")
  cat(sprintf("\n-- Discrepancies: %d ---------------------------------------------\n", length(problems)))
  if (length(problems)) cat(paste(problems, collapse = "\n"), "\n") else cat("  none\n")

  espn_finals <- sum(truth$is_final)
  unmatched <- setdiff(truth$game_id[truth$is_final], cmp$game_id)

  cat("\n-- Verdict -----------------------------------------------------\n")
  cat(sprintf("  ESPN finals in window       : %d\n", espn_finals))
  cat(sprintf("  payload results VERIFIED    : %d of %d payload-complete game(s)\n",
              verified_finals, sum(cmp$is_completed, na.rm = TRUE)))
  cat(sprintf("  agreed still pending        : %d\n", agreed_pending))
  cat(sprintf("  WRONG results in payload    : %d%s\n", wrong,
              if (wrong) "   <-- ingestion/grading defect" else ""))
  cat(sprintf("  finals missing from payload  : %d%s\n", missing_final,
              if (missing_final) "   <-- payload is behind the games" else ""))
  cat(sprintf("  prematurely completed       : %d\n", premature))
  if (length(unmatched)) {
    cat(sprintf("  ESPN finals with no payload row: %d (%s)\n",
                length(unmatched), paste(head(unmatched, 8), collapse = ", ")))
  }

  bad_total <- wrong + premature + missing_final + length(unmatched)
  if (bad_total == 0) {
    cat("\n  TRUE - every finished game in the payload matches ESPN, and no\n")
    cat("  final is missing. The data is both correct and current.\n")
  } else if (wrong == 0 && premature == 0) {
    cat("\n  CORRECT BUT BEHIND - nothing in the payload is wrong, but results\n")
    cat("  exist that it does not carry. Re-run the pipeline after the upstream\n")
    cat("  hoopR build lands (~12:20 UTC) before publishing.\n")
  } else {
    cat("\n  DEFECTIVE - the payload disagrees with what actually happened.\n")
    cat("  Do NOT publish. Investigate the matchups build and the grading join.\n")
  }
  cat("================================================================\n")
  if (bad_total == 0) 0L else 1L
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("verify_results_vs_espn\\.R$", files))) return(invisible(NULL))
  quit(status = main())
})
