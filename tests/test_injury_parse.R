# ==============================================================================
# tests/test_injury_parse.R
#
# NBA_analytics#144: the injury scraper parsed 0 of ~100 live ESPN entries
# because it read athlete$id, which the feed does not carry; the id lives in
# athlete.links[].href. Both invented-data fallbacks (a hand-typed injury list
# and a 4-game sample schedule slate) are gone: no feed / no schedule now means
# an empty table plus a WARN line.
#
# No network. The fixture copies the live feed's field names and nesting
# (injuries[] -> team {id, displayName, injuries[] -> entry {status, athlete
# {displayName, links[] {rel, href}}, type, details}}); the two players and ids
# are copied from the live feed of 2026-11-16, the third entry is a deliberately
# broken shape used only to test the NA-id path. Nothing here is written to a
# real cache.
#
# Usage: Rscript tests/test_injury_parse.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

n_pass <- 0L
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) {
    n_pass <<- n_pass + 1L
    cat("  PASS:", label, "\n")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL:", label, "\n")
  }
}
capture_msgs <- function(expr) {
  msgs <- character()
  val <- withCallingHandlers(expr, message = function(m) {
    msgs <<- c(msgs, conditionMessage(m))
    invokeRestart("muffleMessage")
  })
  list(value = val, messages = msgs)
}

Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
inj_env <- new.env()
suppressWarnings(suppressMessages(source(file.path(REPO_ROOT, "injury_scraper.R"), local = inj_env)))

expected_types <- c(game_date = "Date", team_name = "character", player_name = "character",
                    player_id = "integer", status = "character", injury_desc = "character")
has_schema <- function(df) {
  is.data.frame(df) && identical(names(df), names(expected_types)) &&
    identical(vapply(df, function(x) class(x)[1], character(1)), expected_types)
}

link <- function(rel, href) list(language = "en-US", rel = as.list(rel), href = href, text = "Player Card")
fixture_json <- '{
  "timestamp": "2026-11-16T15:00Z",
  "status": "success",
  "injuries": [
    {"id": "1", "displayName": "Atlanta Hawks", "injuries": [
      {"id": "-60978", "status": "Day-To-Day", "date": "2026-11-16T14:47Z",
       "athlete": {"displayName": "Jock Landale", "links": [
          {"rel": ["playercard", "desktop", "athlete"], "href": "https://www.espn.com/nba/player/_/id/3146557/jock-landale"},
          {"rel": ["stats", "sportscenter", "app", "athlete"], "href": "sportscenter://x-callback-url/showClubhouse?uid=s:40~l:46~a:3146557&section=stats"}]},
       "type": {"id": "6", "name": "INJURY_STATUS_DAYTODAY", "description": "day-to-day", "abbreviation": "DD"},
       "details": {"type": "Hip", "location": "Torso", "detail": "Inflammation", "side": "Right", "returnDate": "2026-11-18"}}
    ]},
    {"id": "10", "displayName": "Houston Rockets", "injuries": [
      {"id": "-1", "status": "Suspension", "date": "2026-11-16T14:00Z",
       "athlete": {"displayName": "Marcus Smart", "links": [
          {"rel": ["stats", "desktop", "athlete"], "href": "https://www.espn.com/nba/player/stats/_/id/2990992/marcus-smart"}]},
       "type": {"id": "9", "name": "INJURY_STATUS_SUSPENSION", "description": "suspension", "abbreviation": "S"},
       "details": {"type": "Not Specified", "location": "Other", "returnDate": "2026-11-20"}}
    ]},
    {"id": "22", "displayName": "Portland Trail Blazers", "injuries": [
      {"id": "-2", "status": "Out", "date": "2026-11-16T13:00Z",
       "athlete": {"displayName": "Test Entry Without Id", "links": [
          {"rel": ["news", "desktop", "athlete"], "href": "https://www.espn.com/nba/team/_/name/por"}]},
       "type": {"id": "4", "name": "INJURY_STATUS_OUT", "description": "out", "abbreviation": "O"},
       "details": {"type": "Knee", "location": "Leg", "side": "Left", "returnDate": "2026-12-01"}}
    ]},
    {"id": "30", "displayName": "Washington Wizards", "injuries": []}
  ]
}'
feed_list <- jsonlite::fromJSON(fixture_json, simplifyVector = FALSE)
feed_df   <- jsonlite::fromJSON(fixture_json, simplifyVector = TRUE)

cat("== ids parsed from athlete.links[].href ==\n")
r <- capture_msgs(inj_env$parse_espn_injuries(feed_list, game_date = as.Date("2026-11-16")))
tab <- r$value
check(has_schema(tab), "six columns with the cache's types")
check(nrow(tab) == 3L, "one row per entry; the team with no entries adds none")
check(identical(tab$player_id[tab$player_name == "Jock Landale"], 3146557L),
      "playercard href /id/3146557/ -> player_id 3146557")
check(identical(tab$player_id[tab$player_name == "Marcus Smart"], 2990992L),
      "non-playercard href with /id/<digits>/ is used when no playercard link exists")
check(identical(tab$team_name, c("Hawks", "Rockets", "Trail Blazers")), "team names cleaned as before")
check(identical(tab$status, c("Questionable", "Out", "Out")),
      "Day-To-Day -> Questionable, Suspension -> Out, Out -> Out")
check(identical(tab$injury_desc[1], "Right Hip Inflammation"),
      "description built from details (side, type, detail), not type$description")
check(!any(tab$injury_desc %in% c("day-to-day", "out", "suspension")), "status words are not used as descriptions")

cat("== unparsable href -> NA id, counted, row kept ==\n")
na_row <- tab[tab$player_name == "Test Entry Without Id", ]
check(nrow(na_row) == 1L && is.na(na_row$player_id), "entry without an id href keeps its row with player_id = NA")
warns <- grep("^>>> \\[WARN\\]", r$messages, value = TRUE)
check(length(warns) == 1L && grepl("1 of 3", warns), "one WARN line counts the NA ids (1 of 3)")
check(!any(grepl("SYNTHETIC_FALLBACK", r$messages)), "no SYNTHETIC_FALLBACK wording")
check(identical(inj_env$extract_espn_athlete_id(NULL), NA_integer_), "no links -> NA_integer_")
check(identical(inj_env$extract_espn_athlete_id(list(link("playercard", "https://www.espn.com/nba/player/_/id/abc/x"))), NA_integer_),
      "non-numeric id segment -> NA_integer_, never an invented id")

cat("== simplifyVector = TRUE (data-frame) form gives the same table ==\n")
tab_df <- suppressMessages(inj_env$parse_espn_injuries(feed_df, game_date = as.Date("2026-11-16")))
check(identical(tab_df, tab), "data-frame input parses identically")

cat("== empty / NULL / unreachable feed -> empty table, no fallback rows ==\n")
for (nm in c("NULL", "no injuries key", "empty injuries")) {
  f <- switch(nm, "NULL" = NULL, "no injuries key" = list(status = "success"),
              "empty injuries" = list(injuries = list()))
  e <- inj_env$parse_espn_injuries(f)
  check(has_schema(e) && nrow(e) == 0L, sprintf("%s -> zero-row six-column table", nm))
}
tmp_cache <- tempfile(fileext = ".rds")
out <- capture_msgs(capture.output(
  res <- inj_env$fetch_live_nba_injuries(url = "unused", cache_path = tmp_cache, fetch_fn = function(url) NULL)))
saved <- readRDS(tmp_cache)
check(has_schema(saved) && nrow(saved) == 0L, "unreachable feed saves an empty six-column table")
check(any(grepl("^>>> \\[WARN\\].*no entries", out$messages)), "unreachable feed logs a >>> [WARN] line")
check(!any(grepl("SYNTHETIC_FALLBACK", out$messages)), "unreachable-feed WARN has no SYNTHETIC_FALLBACK wording")
check(!any(saved$player_name %in% c("Kristaps Porzingis", "Kawhi Leonard", "Joel Embiid")),
      "the old hand-typed list is not written")

cat("== malformed feed -> caught, WARN, empty table ==\n")
tmp_cache2 <- tempfile(fileext = ".rds")
bad <- capture_msgs(capture.output(
  res2 <- inj_env$fetch_live_nba_injuries(url = "unused", cache_path = tmp_cache2,
                                          fetch_fn = function(url) list(injuries = list("not-a-team")))))
check(has_schema(readRDS(tmp_cache2)) && nrow(readRDS(tmp_cache2)) == 0L, "parse error leaves an empty table instead of stopping")
check(any(grepl("^>>> \\[WARN\\].*could not be parsed", bad$messages)), "parse error is logged as WARN")

cat("== injury cache readers cope with an empty table and NA ids ==\n")
saveRDS(inj_env$empty_injury_table(), tmp_cache)
reader_env <- new.env()
reader_env$CACHE_INJURY_DATA <- tmp_cache
src <- readLines(file.path(REPO_ROOT, "injury_load_tracker.R"), warn = FALSE)
src <- src[!grepl("^source\\(\"config.R\"\\)", src)]
suppressMessages(eval(parse(text = src), envir = reader_env))
ld <- reader_env$load_injury_data()
check(is.data.frame(ld) && nrow(ld) == 0L, "load_injury_data() returns the empty table")
check(identical(reader_env$team_availability_score(ld, data.frame()), 1.0), "team_availability_score() on zero rows -> 1.0")
saveRDS(na_row, tmp_cache)
check(is.na(reader_env$load_injury_data()$player_id), "load_injury_data() returns an NA-id row unchanged")

cat("== schedule missing -> empty fatigue table, no invented games ==\n")
old_wd <- setwd(tempdir())
fat_env <- new.env()
fat_env$FATIGUE_ENGINE_LIBRARY_ONLY <- TRUE
suppressWarnings(suppressMessages(source(file.path(REPO_ROOT, "fatigue_travel_engine.R"), local = fat_env)))
fake_cache <- file.path(tempdir(), "fatigue_cache_test")
dir.create(fake_cache, showWarnings = FALSE)
fat_env$CACHE_DIR <- fake_cache
fr <- capture_msgs(fat_env$evaluate_slate_fatigue())
setwd(old_wd)
fat_saved <- readRDS(file.path(fake_cache, "travel_fatigue_metrics.rds"))
check(is.data.frame(fr$value) && nrow(fr$value) == 0L, "no schedule -> zero rows returned")
check(nrow(fat_saved) == 0L, "no schedule -> zero rows saved")
check(identical(names(fat_saved), c("away_team", "home_team", "last_played_at", "days_rest", "is_b2b",
                                    "travel_miles", "tz_shift", "point_spread_drag")),
      "empty fatigue table has the normal path's columns")
check(any(grepl("^>>> \\[WARN\\].*no games invented", fr$messages)), "no schedule logs a >>> [WARN] line")
check(!any(grepl("SYNTHETIC_FALLBACK", fr$messages)), "schedule WARN has no SYNTHETIC_FALLBACK wording")

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
if (n_fail > 0L) quit(status = 1L)
