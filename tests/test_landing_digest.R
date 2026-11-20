# tests/test_landing_digest.R  (NFL_analytics#182-#185, front-office#200)
# Offline tests for tools/build_landing_digest.R: the shared hit rule, record and
# calibration, season state, movers with compared_to fallback, and the tracked
# ratings history. Synthetic fixtures only; no network, no cache/.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
suppressPackageStartupMessages(library(jsonlite))
source("tools/build_landing_digest.R")

# --- hit rule (#182/#184) ------------------------------------------------------
ok("LD-1 hit: >50% side won is TRUE", isTRUE(ld_hit(0.62, 24, 17)))
ok("LD-2 hit: >50% side lost is FALSE", identical(ld_hit(0.62, 17, 24), FALSE))
ok("LD-3 hit: away favourite (home 0.30) wins is TRUE", isTRUE(ld_hit(0.30, 10, 20)))
ok("LD-4 hit: exactly 50% is excluded (NA)", is.na(ld_hit(0.5, 24, 17)))
ok("LD-5 hit: a tie is excluded (NA)", is.na(ld_hit(0.7, 20, 20)))
ok("LD-6 hit: a postponed game is excluded (NA)", is.na(ld_hit(0.7, NA, NA, "postponed")))
ok("LD-7 hit: no prediction is NA", is.na(ld_hit(NA, 24, 17)))

# --- fixture season ------------------------------------------------------------
mk <- function(id, day, p, hs, as_, done = TRUE, status = NA) data.frame(
  game_id = id, season = 2026L, week = 1L, gameday = day, gametime = "13:00",
  home_team = "HOM", away_team = "AWY", has_projection = !is.na(p),
  home_win_prob = p, away_win_prob = if (is.na(p)) NA else round(1 - p, 3),
  is_completed = done, home_score = hs, away_score = as_, status = status, stringsAsFactors = FALSE)
m <- rbind(
  mk("g1", "2026-11-01", 0.65, 24, 17),            # hit, bucket 60-70
  mk("g2", "2026-11-01", 0.30, 27, 10),            # away pick 0.70 lost -> miss, bucket 70-80
  mk("g3", "2026-11-15", 0.50, 21, 14),            # exact 50% -> excluded
  mk("g4", "2026-11-18", 0.80, 20, 20),            # tie -> excluded
  mk("g5", "2026-11-19", 0.55, 31, 3),             # yesterday, hit
  mk("g6", "2026-11-19", 0.60, NA, NA, FALSE, "postponed"),  # yesterday, postponed
  mk("g7", "2026-11-20", 0.58, NA, NA, FALSE),     # today
  mk("g8", "2026-11-20", NA, NA, NA, FALSE))       # today, model not yet run
now <- as.POSIXct("2026-11-20 17:00:00", tz = "UTC")   # 12:00 Eastern
g <- ld_games_table(m)
rec <- ld_record(g, as.Date("2026-11-20"))
ok("LD-8 season record: 2 hits / 3 graded / 3 excluded (50%, tie, postponed)",
   identical(unlist(rec$season), c(hits = 2L, games = 3L, excluded = 3L)))
ok("LD-9 last_7 record covers 2026-11-13..19 only",
   identical(unlist(rec$last_7), c(hits = 1L, games = 1L, excluded = 3L)))
cal <- ld_calibration(g, as.Date("2026-11-20"))
ok("LD-10 calibration: five 10-point buckets from 50 to 100",
   length(cal) == 5 && identical(vapply(cal, `[[`, 0, "lo"), c(0.5, 0.6, 0.7, 0.8, 0.9)))
ok("LD-11 calibration: picked-side probability buckets with rate and count",
   cal[[1]]$games == 1 && cal[[2]]$games == 1 && cal[[3]]$games == 1 &&
     cal[[2]]$actual_rate == 1 && cal[[3]]$actual_rate == 0 && cal[[3]]$predicted_mean == 0.7 &&
     is.null(cal[[5]]$predicted_mean) && cal[[5]]$games == 0)

d <- build_landing_digest(m, NULL, NULL, now, 2026L)
ok("LD-12 digest top-level fields", all(c("schema_version", "sport", "generated_at", "slate_date",
   "season_state", "next_milestone", "today", "yesterday", "record", "calibration", "movers") %in% names(d)))
ok("LD-13 slate_date is the US Eastern date", identical(d$slate_date, "2026-11-20"))
ok("LD-14 today lists both games; unrun model gives null probs + not_yet_run",
   length(d$today) == 2 && identical(d$today[[2]]$prediction_status, "not_yet_run") &&
     is.null(d$today[[2]]$home_win_prob))
ok("LD-15 start_time_utc converts Eastern kickoff to UTC", identical(d$today[[1]]$start_time_utc, "2026-11-20T18:00:00Z"))
y <- setNames(d$yesterday, vapply(d$yesterday, `[[`, "", "game_id"))
ok("LD-16 yesterday: final graded hit; postponed has hit null and final false",
   isTRUE(y$g5$hit) && identical(y$g5$predicted_winner, "HOM") && is.null(y$g6$hit) && identical(y$g6$final, FALSE))
txt <- ld_json_text(d)
ok("LD-17 serialised digest keeps empty movers items as [] and has no betting terms",
   grepl('"items": []', txt, fixed = TRUE) && !grepl("odds|spread|moneyline|over/under", tolower(txt)))

# --- season state --------------------------------------------------------------
sch <- data.frame(season = 2026L, gameday = c("2026-09-10", "2027-01-10"), game_type = "REG")
ok("LD-18 regular season with no playoff rows yet -> final regular-season milestone",
   identical(ld_season_state(sch, as.Date("2026-11-20"), 2026L)$next_milestone$date, "2027-01-10"))
ok("LD-19 before kickoff -> preseason with kickoff milestone",
   identical(ld_season_state(sch, as.Date("2026-08-01"), 2026L)$season_state, "preseason"))
ok("LD-20 long after the season with no next schedule -> offseason, null milestone",
   { s <- ld_season_state(sch, as.Date("2027-06-01"), 2026L); identical(s$season_state, "offseason") && is.null(s$next_milestone) })
ok("LD-21 no schedule -> nulls, no guess", is.null(ld_season_state(NULL, as.Date("2026-11-20"), 2026L)$season_state))

# --- ratings history and movers (#185) ------------------------------------------
r <- function(v) data.frame(team = c("A", "B", "C"), power_rating = v)
h <- ld_read_history("")
h <- ld_update_history(h, r(c(1, 2, 3)), as.Date("2025-01-01"))   # will be pruned
h <- ld_update_history(h, r(c(1, 2, 3)), as.Date("2026-10-28"))
h <- ld_update_history(h, r(c(2, 2, 0)), as.Date("2026-11-12"))
h <- ld_update_history(h, r(c(5, 1, 0)), as.Date("2026-11-19"))
h <- ld_update_history(h, r(c(9, 1, 0)), as.Date("2026-11-20"))
h <- ld_update_history(h, r(c(6, 1, 0)), as.Date("2026-11-20"))   # same-day upsert
ok("LD-22 history: one row per team per day, pruned to ~400 days",
   nrow(h) == 12 && !any(h$date == "2025-01-01") && sum(h$date == "2026-11-20") == 3)
mv <- ld_movers(h, as.Date("2026-11-20"))
ok("LD-23 movers 1-day: exact date, top by |delta|",
   identical(mv$windows[["1"]]$compared_to, "2026-11-19") && identical(mv$windows[["1"]]$items[[1]]$team, "A") &&
     mv$windows[["1"]]$items[[1]]$delta == 1)
ok("LD-24 movers 7-day: no 2026-11-13 row -> falls back to nearest earlier 2026-11-12",
   identical(mv$windows[["7"]]$compared_to, "2026-11-12") && mv$windows[["7"]]$items[[1]]$delta == 4)
ok("LD-25 movers 21-day: falls back to 2026-10-28",
   identical(mv$windows[["21"]]$compared_to, "2026-10-28") && length(mv$windows[["21"]]$items) == 3)
mv2 <- ld_movers(h[h$date == "2026-11-20", ], as.Date("2026-11-20"))
ok("LD-26 movers with one day of history: compared_to null, items empty",
   is.null(mv2$windows[["7"]]$compared_to) && length(mv2$windows[["7"]]$items) == 0)
tf <- tempfile(fileext = ".csv"); ld_write_history(h, tf)
ok("LD-27 history CSV round-trips with date,team,metric,value",
   identical(names(ld_read_history(tf)), c("date", "team", "metric", "value")) && nrow(ld_read_history(tf)) == 12)

git <- Sys.which("git")
if (nzchar(git) && file.exists(LANDING_RATINGS_HISTORY)) {
  st <- suppressWarnings(system2(git, c("check-ignore", "-q", LANDING_RATINGS_HISTORY), stdout = FALSE, stderr = FALSE))
  ok("LD-28 git check-ignore: data/history/ratings_history.csv is NOT ignored (exit 1)", identical(as.integer(st), 1L))
} else {
  cat("[SKIP] LD-28 git or data/history/ratings_history.csv unavailable\n")
}

if (failures > 0L) quit(status = 1L)
