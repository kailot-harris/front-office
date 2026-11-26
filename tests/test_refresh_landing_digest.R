# tests/test_refresh_landing_digest.R  (NFL_analytics#183)
# Slots B/C: tools/refresh_live_results.R patches landing_digest.json's
# today, yesterday, record and calibration from newly finished scores, and rolls
# the digest forward after midnight US Eastern (front-office#240). Temp dirs, an
# injected CSV reader and an injected clock only; no network.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
suppressPackageStartupMessages(library(jsonlite))
source("tools/refresh_live_results.R")   # also sources tools/build_landing_digest.R

d <- tempfile("rld_"); dir.create(d)
row <- function(id, day, p, done, hs = NA, as_ = NA) list(
  game_id = id, season = 2026L, week = 11L, gameday = day, weekday = "x", gametime = "20:15",
  home_team = "HOU", home_team_name = "Houston Texans", away_team = "IND",
  away_team_name = "Indianapolis Colts", has_projection = TRUE, projected_margin = if (p > 0.5) 3 else -3,
  home_win_prob = p, away_win_prob = round(1 - p, 3), is_completed = done,
  home_score = hs, away_score = as_, actual_winner = NA, prediction_correct = NA)
mp <- file.path(d, "matchups_current_week.json")
payload <- list(generated_at = "2026-11-20T05:00:00Z", active_week = 11L, available_weeks = 11L, total_games = 3L,
  matchups = list(row("2026_11_A", "2026-11-12", 0.6, TRUE, 20, 10),
                  row("2026_11_B", "2026-11-19", 0.7, FALSE),
                  row("2026_11_C", "2026-11-19", 0.5, FALSE)))
writeLines(toJSON(payload, auto_unbox = TRUE, na = "null", pretty = TRUE), mp)
m0 <- fromJSON(mp, simplifyVector = TRUE)$matchups
dg <- build_landing_digest(m0, NULL, NULL, as.POSIXct("2026-11-20 15:00:00", tz = "UTC"), 2026L)
dp <- file.path(d, "landing_digest.json")
ld_write_digest(dg, dp)
before <- fromJSON(dp, simplifyVector = FALSE)
ok("RLD-1 fixture digest starts with yesterday's games not final", !any(vapply(before$yesterday, function(g) isTRUE(g$final), TRUE)) &&
     before$record$season$games == 1)

csv <- function(u) data.frame(game_id = c("2026_11_B", "2026_11_C"), season = 2026L,
                              home_score = c(27L, 14L), away_score = c(13L, 10L))
same_day <- as.POSIXct("2026-11-20 20:00:00", tz = "UTC")
res <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                            csv_reader = csv, digest_path = dp, now = same_day)
after <- fromJSON(dp, simplifyVector = FALSE)
y <- setNames(after$yesterday, vapply(after$yesterday, `[[`, "", "game_id"))
ok("RLD-2 refresh rewrote landing_digest.json", dp %in% res$files)
ok("RLD-3 yesterday patched: B final, scored, hit TRUE", isTRUE(y$`2026_11_B`$final) && y$`2026_11_B`$home_score == 27 && isTRUE(y$`2026_11_B`$hit))
ok("RLD-4 yesterday patched: exact-50% game C final with hit null", isTRUE(y$`2026_11_C`$final) && is.null(y$`2026_11_C`$hit))
ok("RLD-5 record patched: season 2/2 with 1 excluded; last_7 1/1 with 1 excluded",
   after$record$season$hits == 2 && after$record$season$games == 2 && after$record$season$excluded == 1 &&
     after$record$last_7$games == 1 && after$record$last_7$excluded == 1)
ok("RLD-6 calibration patched: 60-70 and 70-80 buckets each hold one game",
   after$calibration[[2]]$games == 1 && after$calibration[[3]]$games == 1)
ok("RLD-7 slot A fields untouched on a same-day run (slate_date, movers, season_state)",
   identical(after$slate_date, before$slate_date) && length(after$today) == 0 &&
     identical(after$movers, before$movers) && identical(after$season_state, before$season_state))
ok("RLD-8 generated_at advanced on a real change", !identical(after$generated_at, before$generated_at))
res2 <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                             csv_reader = csv, digest_path = dp, now = same_day)
ok("RLD-9 re-run is a no-op for the digest", !(dp %in% res2$files))

# --- front-office#240: today carries results, roll-over, today_pending ---------
d2 <- tempfile("rld2_"); dir.create(d2)
mp2 <- file.path(d2, "matchups_current_week.json")
dp2 <- file.path(d2, "landing_digest.json")
nodiag <- file.path(d2, "none.json")
payload2 <- list(generated_at = "2026-11-20T05:00:00Z", active_week = 11L, available_weeks = 11L, total_games = 4L,
  matchups = list(row("2026_11_X", "2026-11-19", 0.6, TRUE, 20, 10),
                  row("2026_11_T1", "2026-11-20", 0.7, FALSE),
                  row("2026_11_T2", "2026-11-20", 0.4, FALSE),
                  row("2026_11_N1", "2026-11-21", 0.55, FALSE)))
writeLines(toJSON(payload2, auto_unbox = TRUE, na = "null", pretty = TRUE), mp2)
slot_a <- build_landing_digest(fromJSON(mp2, simplifyVector = TRUE)$matchups, NULL, NULL,
                               as.POSIXct("2026-11-20 15:00:00", tz = "UTC"), 2026L)
ld_write_digest(slot_a, dp2)
start <- fromJSON(dp2, simplifyVector = FALSE)
by_id <- function(rows) setNames(rows, vapply(rows, `[[`, "", "game_id"))
csv_t1 <- function(u) data.frame(game_id = "2026_11_T1", season = 2026L, home_score = 27L, away_score = 13L)
evening <- as.POSIXct("2026-11-21 03:00:00", tz = "UTC")      # 22:00 Eastern on 2026-11-20
r_a <- refresh_live_results(2026L, matchups_path = mp2, diagnostics_path = nodiag,
                            csv_reader = csv_t1, digest_path = dp2, now = evening)
da <- fromJSON(dp2, simplifyVector = FALSE)
ta <- by_id(da$today)
ok("RLD-10 same-day refresh marks a finished today game final with scores and hit",
   dp2 %in% r_a$files && identical(da$slate_date, "2026-11-20") && isTRUE(ta$`2026_11_T1`$final) &&
     identical(ta$`2026_11_T1`$status, "final") && ta$`2026_11_T1`$home_score == 27 &&
     ta$`2026_11_T1`$away_score == 13 && identical(ta$`2026_11_T1`$predicted_winner, "HOU") &&
     isTRUE(ta$`2026_11_T1`$hit))
ok("RLD-11 same-day refresh leaves an unfinished today game scheduled with null scores and hit",
   identical(ta$`2026_11_T2`$status, "scheduled") && identical(ta$`2026_11_T2`$final, FALSE) &&
     all(c("home_score", "away_score", "hit") %in% names(ta$`2026_11_T2`)) &&
     is.null(ta$`2026_11_T2`$home_score) && is.null(ta$`2026_11_T2`$hit) &&
     identical(ta$`2026_11_T2`$predicted_winner, "IND") && is.null(da$today_pending))
ok("RLD-12 same-day refresh keeps today's start times and the season record through yesterday",
   identical(ta$`2026_11_T1`$start_time_utc, by_id(start$today)$`2026_11_T1`$start_time_utc) &&
     da$record$season$games == 1)

bytes_before <- readBin(dp2, "raw", file.info(dp2)$size)
r_d <- refresh_live_results(2026L, matchups_path = mp2, diagnostics_path = nodiag,
                            csv_reader = csv_t1, digest_path = dp2, now = evening + 600)
ok("RLD-13 a refresh with no result changes leaves the digest byte-identical",
   !(dp2 %in% r_d$files) && identical(readBin(dp2, "raw", file.info(dp2)$size), bytes_before) &&
     identical(fromJSON(dp2, simplifyVector = FALSE)$generated_at, da$generated_at))

# Prove start times are carried from the old today rows at roll-over.
dz <- da; dz$today[[2]]$start_time_utc <- "2026-11-20T21:35:00Z"
carried_id <- dz$today[[2]]$game_id
ld_write_digest(dz, dp2)
csv_both <- function(u) data.frame(game_id = c("2026_11_T1", "2026_11_T2"), season = 2026L,
                                   home_score = c(27L, 10L), away_score = c(13L, 24L))
after_midnight <- as.POSIXct("2026-11-21 06:30:00", tz = "UTC")   # 01:30 Eastern on 2026-11-21
r_b <- refresh_live_results(2026L, matchups_path = mp2, diagnostics_path = nodiag,
                            csv_reader = csv_both, digest_path = dp2, now = after_midnight)
db <- fromJSON(dp2, simplifyVector = FALSE)
yb <- by_id(db$yesterday)
ok("RLD-14 roll-over moves slate_date to the new Eastern date",
   dp2 %in% r_b$files && identical(db$slate_date, "2026-11-21"))
ok("RLD-15 roll-over: yesterday holds the old slate's games final with scores and hits",
   setequal(names(yb), c("2026_11_T1", "2026_11_T2")) &&
     all(vapply(yb, function(r) isTRUE(r$final) && identical(r$status, "final"), TRUE)) &&
     yb$`2026_11_T2`$home_score == 10 && yb$`2026_11_T2`$away_score == 24 && isTRUE(yb$`2026_11_T2`$hit))
ok("RLD-16 roll-over carries start times from the old today rows",
   identical(yb[[carried_id]]$start_time_utc, "2026-11-20T21:35:00Z"))
ok("RLD-17 roll-over with rows: today is the new date's games and today_pending is absent",
   length(db$today) == 1 && identical(db$today[[1]]$game_id, "2026_11_N1") &&
     identical(db$today[[1]]$status, "scheduled") && !("today_pending" %in% names(db)))
ok("RLD-18 roll-over: record and calibration run through the new date minus 1",
   db$record$season$games == 3 && db$record$season$hits == 3 && db$record$last_7$games == 3 &&
     sum(vapply(db$calibration, `[[`, 0L, "games")) == 3)
ok("RLD-19 roll-over carries movers, season_state and next_milestone unchanged",
   identical(db$movers, start$movers) && identical(db$season_state, start$season_state) &&
     identical(db$next_milestone, start$next_milestone))

next_night <- as.POSIXct("2026-11-22 06:30:00", tz = "UTC")      # 01:30 Eastern on 2026-11-22
r_c <- refresh_live_results(2026L, matchups_path = mp2, diagnostics_path = nodiag,
                            csv_reader = csv_both, digest_path = dp2, now = next_night)
dc <- fromJSON(dp2, simplifyVector = FALSE)
txt_c <- paste(readLines(dp2), collapse = "\n")
ok("RLD-20 roll-over without rows for the new date: today [] and today_pending true",
   dp2 %in% r_c$files && identical(dc$slate_date, "2026-11-22") && length(dc$today) == 0 &&
     isTRUE(dc$today_pending) && grepl('"today": []', txt_c, fixed = TRUE) &&
     grepl('"today_pending": true', txt_c, fixed = TRUE))
ok("RLD-21 roll-over without rows: yesterday holds the unfinished game, not final",
   length(dc$yesterday) == 1 && identical(dc$yesterday[[1]]$game_id, "2026_11_N1") &&
     identical(dc$yesterday[[1]]$final, FALSE) && is.null(dc$yesterday[[1]]$hit))

pl <- fromJSON(mp2, simplifyVector = FALSE)
pl$matchups[[length(pl$matchups) + 1L]] <- row("2026_11_N2", "2026-11-22", 0.65, FALSE)
writeLines(toJSON(pl, auto_unbox = TRUE, na = "null", null = "null", pretty = TRUE), mp2)
r_e <- refresh_live_results(2026L, matchups_path = mp2, diagnostics_path = nodiag,
                            csv_reader = csv_both, digest_path = dp2, now = next_night + 3600)
de <- fromJSON(dp2, simplifyVector = FALSE)
ok("RLD-22 a later refresh with rows for the date removes today_pending",
   dp2 %in% r_e$files && identical(de$slate_date, "2026-11-22") && length(de$today) == 1 &&
     identical(de$today[[1]]$game_id, "2026_11_N2") && !("today_pending" %in% names(de)))

if (failures > 0L) quit(status = 1L)
