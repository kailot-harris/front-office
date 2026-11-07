# Diagnostic utility: cross-check WNBA Finals Game 7 (ESPN game_id 401918311,
# GS @ ATL, 2026-10-31) completion status against every data source this repo
# can reach, independent of the wehoop cache that's currently reporting it as
# unplayed. Read-only -- writes nothing to cache/.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\diagnose_game7_sources.R

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
})

GAME_ID <- "401918311"
cat("==================================================================\n")
cat("Game 7 multi-source diagnostic -- ESPN game_id", GAME_ID, "\n")
cat("==================================================================\n\n")

report <- function(label, fn) {
  cat("--", label, "--\n")
  tryCatch({
    fn()
  }, error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
  })
  cat("\n")
}

# 1. wehoop::load_wnba_schedule() -- the cached source currently used by
#    daily_ingest.R. Re-fetch live (no cache) to rule out a stale local cache.
report("1. wehoop::load_wnba_schedule(2026) [live, uncached]", function() {
  sch <- wehoop::load_wnba_schedule(seasons = 2026)
  g <- sch[sch$game_id == GAME_ID, ]
  if (nrow(g) == 0) {
    cat("  Game not found in wehoop schedule at all.\n")
  } else {
    cols <- intersect(c("game_id", "game_date", "status_type_completed",
                         "status_type_name", "home_score", "away_score"),
                       names(g))
    print(g[1, cols])
  }
})

# 2. ESPN site API scoreboard for the specific date.
report("2. ESPN site.api scoreboard for 2026-10-31", function() {
  url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/scoreboard"
  res <- GET(url, query = list(dates = "20261031"))
  cat("  HTTP status:", status_code(res), "\n")
  if (status_code(res) == 200) {
    j <- fromJSON(content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
    events <- j$events
    cat("  Events returned for this date:", length(events), "\n")
    for (ev in events) {
      cat(sprintf("   id=%s  status=%s  %s\n",
                   ev$id, ev$status$type$name, ev$name %||% ""))
    }
  }
})

# 3. ESPN site API summary endpoint for the exact game_id (box score / play-by-play host).
report("3. ESPN site.api summary for game_id directly", function() {
  url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/summary"
  res <- GET(url, query = list(event = GAME_ID))
  cat("  HTTP status:", status_code(res), "\n")
  if (status_code(res) == 200) {
    j <- fromJSON(content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
    comp <- j$header$competitions[[1]]
    cat("  status$type$name:", comp$status$type$name, "\n")
    cat("  status$type$completed:", comp$status$type$completed, "\n")
    if (!is.null(j$boxscore) && length(j$boxscore$teams) > 0) {
      for (t in j$boxscore$teams) {
        cat(sprintf("   team=%s  score=%s\n",
                     t$team$displayName %||% "?", t$statistics[[1]]$displayValue %||% "?"))
      }
    }
  }
})

# 4. ESPN core API (sports.core.api) for the same event -- a separate ESPN
#    backend from site.api, sometimes updates on a different cadence.
report("4. ESPN core API event lookup", function() {
  url <- paste0("https://sports.core.api.espn.com/v2/sports/basketball/leagues/wnba/events/", GAME_ID)
  res <- GET(url)
  cat("  HTTP status:", status_code(res), "\n")
  if (status_code(res) == 200) {
    j <- fromJSON(content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
    comp <- j$competitions[[1]]
    cat("  competitions[1]$status$`$ref`:", comp$status$`$ref` %||% "none", "\n")
    status_ref <- comp$status$`$ref`
    if (!is.null(status_ref)) {
      sres <- GET(status_ref)
      if (status_code(sres) == 200) {
        sj <- fromJSON(content(sres, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)
        cat("  status type name:", sj$type$name, "| completed:", sj$type$completed, "\n")
      }
    }
  }
})

# 5. Google News RSS as a sanity check -- did Game 7 even happen per any news source?
report("5. Google News RSS sanity check ('WNBA Finals Game 7')", function() {
  url <- "https://news.google.com/rss/search"
  res <- GET(url, query = list(q = "WNBA Finals Game 7 2026", hl = "en-US"))
  cat("  HTTP status:", status_code(res), "\n")
  if (status_code(res) == 200) {
    txt <- content(res, as = "text", encoding = "UTF-8")
    titles <- regmatches(txt, gregexpr("<title>(.*?)</title>", txt))[[1]]
    titles <- head(titles, 8)
    for (t in titles) cat("  ", t, "\n")
  }
})

cat("==================================================================\n")
cat("Done. Compare status/completed flags across sources 1-4 above.\n")
cat("If ALL sources agree Game 7 is incomplete/not-yet-played, the data\n")
cat("is correct and nothing has landed yet -- not a repo bug.\n")
cat("If source 2/3/4 show it complete but source 1 (wehoop) doesn't, that\n")
cat("confirms a wehoop-package lag, not a data-entry error.\n")
cat("==================================================================\n")
