# ==============================================================================
# tools/espn_scoreboard.R - ESPN WNBA scoreboard client
#
# Fetches game results directly from ESPN's public WNBA scoreboard endpoint:
# https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/scoreboard?dates=%s
#
# Modelled on the NBA Analytics sibling (NBA Analytics/tools/espn_scoreboard.R).
#
# Assumes the caller has already setwd() to the project root and sourced
# config.R. Loads jsonlite and nothing else, so it stays usable from the
# jsonlite-only scheduled workflow (.github/workflows/refresh-results.yml).
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Team abbreviation dialect. Map any ESPN variants cleanly onto the canonical
# abbreviations defined in WNBA_TEAMS (ATL, CHI, CON, DAL, GS, IND, LA, LV,
# MIN, NY, PHX, POR, SEA, TOR, WSH).
# ------------------------------------------------------------------------------
ESPN_ALIAS <- c(
  NYL = "NY",
  WSH = "WSH",
  WAS = "WSH",
  LAS = "LA",
  LA  = "LA",
  LVA = "LV",
  LV  = "LV",
  PHO = "PHX",
  PHX = "PHX",
  GSW = "GS",
  GS  = "GS"
)

.espn_norm <- function(x) {
  x <- toupper(trimws(as.character(x)))
  hit <- x %in% names(ESPN_ALIAS)
  x[hit] <- ESPN_ALIAS[x[hit]]
  x
}

ESPN_SCOREBOARD <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/scoreboard?dates=%s"

# ESPN rejects a default R user agent with 403, so a browser UA is required.
# One request per date; the feed is keyed by a single YYYYMMDD.
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
