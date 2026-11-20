# tests/test_refresh_landing_digest.R  (NFL_analytics#183)
# Slots B/C: tools/refresh_live_results.R patches landing_digest.json's
# yesterday, record and calibration from newly finished scores. Temp dirs and an
# injected CSV reader only; no network.
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
res <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                            csv_reader = csv, digest_path = dp)
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
ok("RLD-7 slot A fields untouched (slate_date, today, movers, season_state)",
   identical(after$slate_date, before$slate_date) && identical(after$today, before$today) &&
     identical(after$movers, before$movers) && identical(after$season_state, before$season_state))
ok("RLD-8 generated_at advanced on a real change", !identical(after$generated_at, before$generated_at))
res2 <- refresh_live_results(2026L, matchups_path = mp, diagnostics_path = file.path(d, "none.json"),
                             csv_reader = csv, digest_path = dp)
ok("RLD-9 re-run is a no-op for the digest", !(dp %in% res2$files))

if (failures > 0L) quit(status = 1L)
