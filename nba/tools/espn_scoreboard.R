# ==============================================================================
# tools/espn_scoreboard.R - the one ESPN scoreboard client in this repo
#
# Extracted (2026-10-27) from tools/verify_results_vs_espn.R, verbatim and with
# no behaviour change, when tools/refresh_live_results.R became a second
# consumer. A second hand-rolled copy of the fetch - and especially a second
# copy of the abbreviation alias table - is exactly the drift this repo's
# CLAUDE.md warns about: the two callers would disagree about which team "WSH"
# is, and only one of them would be wrong.
#
# Assumes the caller has already setwd() to the project root and sourced
# config.R (both consumers do, via their own bootstrap). Loads jsonlite and
# nothing else, so it stays usable from the jsonlite-only scheduled workflow.
#
# ESPN is the right arbiter for this repo and not an arbitrary third party:
# hoopR's load_nba_* release assets are themselves built from ESPN, and the
# matchups payload carries ESPN game_ids, so the join is exact and a
# disagreement is a real defect rather than two sources differing. The flip
# side is that this is NOT a fully independent source - it cannot catch an
# error ESPN itself made upstream.
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Team abbreviation dialect. ESPN's scoreboard feed and the hoopR-derived payload
# disagree on a handful of codes; these are spelling differences, not mismatches,
# and treating them as mismatches would make every caller cry wolf on every run.
# ------------------------------------------------------------------------------
ESPN_ALIAS <- c(UTAH = "UTA", NY = "NYK", WSH = "WAS", GS = "GSW",
                SA = "SAS", NO = "NOP", PHO = "PHX", NOLA = "NOP")

.espn_norm <- function(x) {
  x <- toupper(trimws(as.character(x)))
  hit <- x %in% names(ESPN_ALIAS)
  x[hit] <- ESPN_ALIAS[x[hit]]
  x
}

ESPN_SCOREBOARD <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=%s"

# ESPN rejects a default R user agent with 403, so a browser UA is required rather than
# cosmetic. One request per date; the feed is keyed by a single YYYYMMDD.
#
# A fetch failure warns and returns NULL rather than stopping: a caller sweeping
# a date range must be able to lose one day to a transient 5xx without losing
# the whole run. Callers are responsible for noticing an all-NULL sweep.
.espn_fetch_date <- function(d) {
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
      ab <- .espn_norm(t$team$abbreviation)
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

#' Fetch a range of dates in one call
#'
#' @param dates Vector coercible to Date.
#' @return One data.frame of all games found, or NULL when every date failed or
#'   was empty.
espn_fetch_dates <- function(dates) {
  out <- do.call(rbind, lapply(dates, .espn_fetch_date))
  if (is.null(out) || !nrow(out)) return(NULL)
  out
}
