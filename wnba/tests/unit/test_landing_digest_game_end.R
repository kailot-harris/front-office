# ==============================================================================
# test_landing_digest_game_end.R  (front-office#240)
# Landing digest after each game ends: the slot B/C refresh re-derives today[]
# with results, rolls the digest forward past midnight US Eastern, sets
# today_pending only on a roll-over without rows, never rewrites an unchanged
# digest, and never touches a digest frozen as season_final in the lifecycle
# registry. Slot A writes the same today row shape and never today_pending.
# Base R + jsonlite only (runs under .github/scripts/run-tests.R). Temp-dir
# fixtures with invented dates; never reads cache/ or web/public/data.
# Run: Rscript tests/unit/test_landing_digest_game_end.R
# ==============================================================================

local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  root <- if (length(f) == 1 && file.exists(f)) dirname(dirname(dirname(normalizePath(f, winslash = "/")))) else getwd()
  while (!file.exists(file.path(root, "config.R")) && dirname(root) != root) root <- dirname(root)
  setwd(root)
})
dir.create("logs", showWarnings = FALSE)
suppressPackageStartupMessages(library(jsonlite))
Sys.setenv(WNBA_SKIP_DIGEST_AUTORUN = "1", WNBA_SKIP_MANIFEST_AUTORUN = "1")
ROOT <- getwd()
source(file.path("tools", "refresh_live_results.R"))   # also sources config.R + build_landing_digest.R
setwd(ROOT)

.fail <- 0L
check <- function(label, cond, info = NULL) {
  if (isTRUE(cond)) {
    cat("[PASS]", label, "\n")
  } else {
    cat("[FAIL]", label, if (!is.null(info)) paste0("\n       ", paste(format(info), collapse = "\n       ")), "\n")
    .fail <<- .fail + 1L
  }
  invisible(isTRUE(cond))
}

# One matchup row in matchups_slates.json shape.
mrow <- function(id, date, home, away, p = NA, start = NA_character_, week = 1L) {
  data.frame(game_id = id, game_date = date, week = week, season_type = "regular",
             start_time_utc = start,
             home_team = home, away_team = away, home_team_name = paste(home, "Name"),
             away_team_name = paste(away, "Name"), is_completed = FALSE,
             home_score = NA_integer_, away_score = NA_integer_, actual_margin = NA, actual_winner = NA,
             has_prediction = TRUE, has_logged_prediction = !is.na(p),
             projection_basis = if (is.na(p)) "team_rating_differential" else "logged_model",
             projected_margin = NA, home_win_prob = if (is.na(p)) 0.6 else p,
             predicted_winner = NA, is_graded = FALSE, prediction_correct = NA,
             status = "STATUS_SCHEDULED", stringsAsFactors = FALSE)
}
write_payload <- function(rows, path) {
  payload <- list(season = 2026L, generated_at = "2026-07-10T00:00:00Z", active_week = 1L,
                  available_weeks = 1L, summary = list(completed_games = 0L),
                  weeks = data.frame(week = 1L, completed_games = 0L, pending_games = nrow(rows),
                                     graded_games = 0L, correct_games = NA, accuracy_pct = NA),
                  matchups = rows)
  writeLines(toJSON(payload, auto_unbox = TRUE, na = "null", pretty = TRUE), path)
}
bytes <- function(p) readBin(p, "raw", file.info(p)$size)
row_of <- function(rows, id) Filter(function(g) identical(g$game_id, id), rows)[[1]]
et <- function(s) as.POSIXct(s, tz = "America/New_York")   # wall-clock US Eastern
RESULT_KEYS <- c("final", "home_score", "away_score", "predicted_winner", "hit")
NOREG <- NULL   # skip the lifecycle check for the in-season cases

d <- tempfile("ldge_"); dir.create(d)
mp <- file.path(d, "matchups_slates.json"); dp <- file.path(d, "landing_digest.json")
hist_none <- file.path(d, "no_history.csv")
rows <- rbind(
  mrow("201", "2026-07-10", "A", "B", 0.70, start = "2026-07-10T23:00:00Z"),
  mrow("202", "2026-07-10", "C", "D", 0.40, start = "2026-07-11T02:00:00Z"),
  mrow("204", "2026-07-10", "E", "F", NA,   start = "2026-07-11T02:30:00Z"),
  mrow("203", "2026-07-11", "A", "D", 0.55, start = "2026-07-11T23:30:00Z"))
write_payload(rows, mp)

cat("\n-- (e) slot A: today rows carry the result fields, never today_pending --\n")
sa <- build_landing_digest(now = et("2026-07-10 09:00:00"), matchups_path = mp, monitor_path = NULL,
                           standings_path = file.path(d, "none.rds"), history_path = hist_none,
                           update_history = FALSE)
writeLines(ld_json_text(sa), dp)
sj <- fromJSON(dp, simplifyVector = FALSE)
check("slot A today has the three 2026-07-10 games", identical(vapply(sj$today, `[[`, "", "game_id"), c("201", "202", "204")))
check("slot A today rows carry final/home_score/away_score/predicted_winner/hit",
      all(vapply(sj$today, function(g) all(RESULT_KEYS %in% names(g)), logical(1))))
g201 <- row_of(sj$today, "201")
check("slot A scheduled row: final false, scores and hit null, predicted_winner set",
      identical(g201$final, FALSE) && is.null(g201$home_score) && is.null(g201$away_score) &&
        is.null(g201$hit) && identical(g201$predicted_winner, "A"))
check("slot A never writes today_pending", !("today_pending" %in% names(sj)))
sa_empty <- build_landing_digest(now = et("2026-07-12 09:00:00"), matchups_path = mp, monitor_path = NULL,
                                 standings_path = file.path(d, "none.rds"), history_path = hist_none,
                                 update_history = FALSE)
check("slot A with no games on the slate date: today empty and still no today_pending",
      length(sa_empty$today) == 0 && !("today_pending" %in% names(sa_empty)))

# The payload loses 201's start time: the refresh must carry it from the digest.
pm <- fromJSON(mp, simplifyVector = TRUE); pm$matchups$start_time_utc[pm$matchups$game_id == "201"] <- NA
writeLines(toJSON(pm, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)

cat("\n-- (a) same-day refresh marks a finished today game final --\n")
fin201 <- function(dates) data.frame(game_id = "201", is_final = TRUE, home_score = 85L, away_score = 80L)
r1 <- refresh_live_results(dates = "2026-07-10", payload_path = mp, fetcher = fin201,
                           today = as.Date("2026-07-10"), digest_path = dp,
                           now = et("2026-07-10 22:30:00"), lifecycle_registry = NOREG)
o1 <- fromJSON(dp, simplifyVector = FALSE)
t201 <- row_of(o1$today, "201"); t202 <- row_of(o1$today, "202")
check("refresh rewrote the digest", identical(r1$digest_file, dp))
check("same-day: slate_date unchanged", identical(o1$slate_date, "2026-07-10"))
check("same-day: finished game is final with scores and a graded hit",
      identical(t201$status, "final") && isTRUE(t201$final) && identical(t201$home_score, 85L) &&
        identical(t201$away_score, 80L) && identical(t201$hit, TRUE) && identical(t201$predicted_winner, "A"),
      t201)
check("same-day: start_time_utc carried from the previous today row",
      identical(t201$start_time_utc, "2026-07-10T23:00:00Z"))
check("same-day: unfinished game stays scheduled with null scores and hit",
      identical(t202$status, "scheduled") && identical(t202$final, FALSE) && is.null(t202$home_score) &&
        is.null(t202$hit) && all(RESULT_KEYS %in% names(t202)))
check("same-day: no today_pending", !("today_pending" %in% names(o1)))
check("same-day: generated_at moved on the change", !identical(o1$generated_at, sj$generated_at))

cat("\n-- (d) a refresh with no result changes leaves the file byte-identical --\n")
b1 <- bytes(dp)
r1b <- refresh_live_results(dates = "2026-07-10", payload_path = mp, fetcher = fin201,
                            today = as.Date("2026-07-10"), digest_path = dp,
                            now = et("2026-07-10 23:30:00"), lifecycle_registry = NOREG)
check("no-op same-day refresh: digest_file NULL and bytes identical",
      is.null(r1b$digest_file) && identical(bytes(dp), b1))

cat("\n-- (b) roll-over with rows for the new Eastern date --\n")
fin202 <- function(dates) data.frame(game_id = c("201", "202"), is_final = TRUE,
                                     home_score = c(85L, 70L), away_score = c(80L, 75L))
r2 <- refresh_live_results(dates = "2026-07-10", payload_path = mp, fetcher = fin202,
                           today = as.Date("2026-07-11"), digest_path = dp,
                           now = et("2026-07-11 01:00:00"), lifecycle_registry = NOREG)
o2 <- fromJSON(dp, simplifyVector = FALSE)
y <- o2$yesterday
check("roll-over: slate_date moved to the new Eastern date", identical(o2$slate_date, "2026-07-11"), o2$slate_date)
check("roll-over: yesterday holds the 2026-07-10 games", identical(vapply(y, `[[`, "", "game_id"), c("201", "202", "204")))
y201 <- row_of(y, "201"); y202 <- row_of(y, "202"); y204 <- row_of(y, "204")
check("roll-over: finished games are final with scores and hits",
      isTRUE(y201$final) && identical(y201$home_score, 85L) && identical(y201$hit, TRUE) &&
        isTRUE(y202$final) && identical(y202$away_score, 75L) && identical(y202$hit, TRUE))
check("roll-over: start time carried into yesterday from the old today row",
      identical(y201$start_time_utc, "2026-07-10T23:00:00Z"))
check("roll-over: a not-yet-final game keeps its carried status, null scores and hit",
      identical(y204$status, "scheduled") && identical(y204$final, FALSE) && is.null(y204$home_score) && is.null(y204$hit),
      y204)
check("roll-over: record and calibration through the new date minus 1",
      identical(o2$record$season$hits, 2L) && identical(o2$record$season$games, 2L) &&
        identical(sum(vapply(o2$calibration, function(b) b$games, 0L)), 2L))
check("roll-over: today = rows for the new date", identical(vapply(o2$today, `[[`, "", "game_id"), "203") &&
        identical(o2$today[[1]]$status, "scheduled") && identical(o2$today[[1]]$final, FALSE))
check("roll-over with rows: no today_pending", !("today_pending" %in% names(o2)))
check("roll-over: season_state, next_milestone and movers carried unchanged",
      identical(o2$season_state, sj$season_state) && identical(o2$next_milestone, sj$next_milestone) &&
        identical(o2$movers, sj$movers))
b2 <- bytes(dp)
r2b <- refresh_live_results(dates = "2026-07-10", payload_path = mp, fetcher = fin202,
                            today = as.Date("2026-07-11"), digest_path = dp,
                            now = et("2026-07-11 02:00:00"), lifecycle_registry = NOREG)
check("(d) no-op after the roll-over: bytes identical", is.null(r2b$digest_file) && identical(bytes(dp), b2))

cat("\n-- (c) roll-over without rows sets today_pending; a later refresh with rows removes it --\n")
r3 <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = fin202,
                           today = as.Date("2026-07-12"), digest_path = dp,
                           now = et("2026-07-12 01:30:00"), lifecycle_registry = NOREG)
o3 <- fromJSON(dp, simplifyVector = FALSE)
check("roll-over without rows: slate_date moved, today empty, today_pending true",
      identical(o3$slate_date, "2026-07-12") && length(o3$today) == 0 && identical(o3$today_pending, TRUE), o3[c("slate_date", "today_pending")])
check("roll-over without rows: yesterday holds the 2026-07-11 game, start time from the old today row",
      identical(vapply(o3$yesterday, `[[`, "", "game_id"), "203") &&
        identical(o3$yesterday[[1]]$start_time_utc, "2026-07-11T23:30:00Z"))
txt3 <- paste(readLines(dp, warn = FALSE), collapse = "\n")
check("today_pending is written as JSON true", grepl('"today_pending": true', txt3, fixed = TRUE))
pm <- fromJSON(mp, simplifyVector = TRUE)
pm$matchups <- rbind(pm$matchups, transform(pm$matchups[pm$matchups$game_id == "203", ], game_id = "205",
                                            game_date = "2026-07-12", start_time_utc = "2026-07-12T23:00:00Z"))
writeLines(toJSON(pm, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
r4 <- refresh_live_results(dates = character(0), payload_path = mp, fetcher = fin202,
                           today = as.Date("2026-07-12"), digest_path = dp,
                           now = et("2026-07-12 10:30:00"), lifecycle_registry = NOREG)
o4 <- fromJSON(dp, simplifyVector = FALSE)
check("later refresh with rows: today filled and today_pending removed",
      identical(vapply(o4$today, `[[`, "", "game_id"), "205") && !("today_pending" %in% names(o4)))

cat("\n-- (f) season_final digest is never touched --\n")
reg <- file.path(d, "season_lifecycle.json")
writeLines(toJSON(list(schema_version = 1L, sport = "wnba", files = list(
  landing_digest.json = list(lifecycle = "season_final", season = 2026L, final_through_date = "2026-07-12",
                             frozen_sha256 = wnba_lifecycle_sha256(dp), frozen_at = "2026-07-13T00:00:00Z"))),
  auto_unbox = TRUE, pretty = TRUE), reg)
bf <- bytes(dp)
check("lifecycle helper reports the digest season_final", isTRUE(ld_digest_frozen(dp, reg)))
r5 <- refresh_live_results(dates = "2026-07-10", payload_path = mp,
                           fetcher = function(dates) data.frame(game_id = "204", is_final = TRUE, home_score = 60L, away_score = 66L),
                           today = as.Date("2026-07-20"), digest_path = dp,
                           now = et("2026-07-20 01:00:00"), lifecycle_registry = reg)
check("frozen: Eastern date past slate_date, new result in the payload, digest byte-identical",
      r5$n_changed == 1L && is.null(r5$digest_file) && identical(bytes(dp), bf))
check("frozen: content hash still equals frozen_sha256 (assertion L input)",
      identical(wnba_lifecycle_sha256(dp), fromJSON(reg)$files$landing_digest.json$frozen_sha256))
writeLines("{ not json", reg)
check("unreadable registry counts as frozen (digest untouched)",
      suppressMessages(isTRUE(ld_digest_frozen(dp, reg))) &&
        !isTRUE(suppressMessages(ld_patch_digest(fromJSON(mp)$matchups, dp, now = et("2026-07-20 02:00:00"), registry_path = reg))) &&
        identical(bytes(dp), bf))
writeLines(toJSON(list(schema_version = 1L, sport = "wnba", files = list(
  landing_digest.json = list(lifecycle = "live"))), auto_unbox = TRUE), reg)
check("a live lifecycle entry does not block the patch", !isTRUE(ld_digest_frozen(dp, reg)) &&
        isTRUE(ld_patch_digest(fromJSON(mp)$matchups, dp, now = et("2026-07-20 02:00:00"), registry_path = reg)))

cat(sprintf("\n%d failure(s)\n", .fail))
if (.fail > 0L) quit(status = 1L)
