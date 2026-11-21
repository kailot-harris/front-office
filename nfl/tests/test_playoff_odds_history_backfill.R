# tests/test_playoff_odds_history_backfill.R
# Offline tests for tools/playoff_odds_history_backfill.R's season guard and incremental
# behavior (#194). The Monte Carlo simulator is replaced by a stub that records which weeks it
# was asked for; every file is written to a temp dir, never to cache/.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("tools/playoff_odds_history_backfill.R")
# Keep test runs out of the real log sinks.
log_info <- function(...) invisible(NULL)
log_warn <- function(...) invisible(NULL)
log_error <- function(...) invisible(NULL)

tmp <- tempfile("pohb_"); dir.create(tmp)
hist_path <- file.path(tmp, "history.rds")
meta_path <- file.path(tmp, "meta.json")

# Schedule shape only (weeks with/without results); the stub never reads teams or scores.
sched_through <- function(season, done_weeks, all_weeks = 1:6) {
  d <- expand.grid(game = 1:2, week = all_weeks)
  done <- d$week %in% done_weeks
  data.frame(season = season, game_type = "REG", week = d$week,
             home_team = "AAA", away_team = "BBB",
             home_score = ifelse(done, 1, NA), away_score = ifelse(done, 0, NA),
             stringsAsFactors = FALSE)
}
called <- integer(0)
stub <- function(w, team_ratings, sch, season) {
  called <<- c(called, w)
  data.frame(week = w, team = c("AAA", "BBB"), division_win_prob = 0.5,
             playoff_prob = 0.5, bye_prob = 0, stringsAsFactors = FALSE)
}
cached_rows <- function(weeks) {
  data.frame(week = rep(weeks, each = 2), team = c("AAA", "BBB"), division_win_prob = 0.25,
             playoff_prob = 0.25, bye_prob = 0.25, stringsAsFactors = FALSE)
}
run <- function(season, done_weeks, sim = stub) {
  called <<- integer(0)
  run_playoff_odds_history_backfill(history_path = hist_path, meta_path = meta_path, season = season,
                                    sch = sched_through(season, done_weeks), team_ratings = data.frame(),
                                    simulate_week = sim)
}

# 1. Season change: last season's sidecar -> every completed week is simulated again.
saveRDS(cached_rows(1:5), hist_path)
jsonlite::write_json(list(season = 2025L, max_week = 5L), meta_path, auto_unbox = TRUE)
r1 <- run(2026L, 1:3)
h1 <- readRDS(hist_path)
ok("season change: full rebuild (weeks 1-3 simulated)", isTRUE(r1) && identical(called, 1:3))
ok("season change: no row of last season survives", all(h1$division_win_prob == 0.5) && identical(sort(unique(h1$week)), 1:3))
ok("season change: sidecar now names the current season",
   identical(as.integer(jsonlite::fromJSON(meta_path)$season), 2026L))

# 2. Missing sidecar -> full rebuild too.
saveRDS(cached_rows(1:2), hist_path); unlink(meta_path)
r2 <- run(2026L, 1:3)
ok("missing sidecar: full rebuild", isTRUE(r2) && identical(called, 1:3) && file.exists(meta_path))

# 3. Same season, weeks 1-2 cached, 1-4 complete -> only 3 and 4 are simulated.
saveRDS(cached_rows(1:2), hist_path)
jsonlite::write_json(list(season = 2026L, max_week = 2L), meta_path, auto_unbox = TRUE)
r3 <- run(2026L, 1:4)
h3 <- readRDS(hist_path)
ok("same season: only missing weeks simulated", isTRUE(r3) && identical(called, 3:4))
ok("same season: cached weeks kept as they were",
   all(h3$division_win_prob[h3$week <= 2] == 0.25) && identical(sort(unique(h3$week)), 1:4))
ok("published schema unchanged",
   identical(names(h3), c("week", "team", "division_win_prob", "playoff_prob", "bye_prob")))
ok("sidecar records max week", identical(as.integer(jsonlite::fromJSON(meta_path)$max_week), 4L))

# 4. Nothing new -> no simulation, TRUE.
r4 <- run(2026L, 1:4)
ok("up to date: nothing simulated", isTRUE(r4) && length(called) == 0L)

# 5. A failing simulation returns FALSE and leaves the cache untouched.
before <- readRDS(hist_path)
r5 <- run(2026L, 1:5, sim = function(...) NULL)
ok("simulator failure: FALSE and cache unchanged", identical(r5, FALSE) && identical(readRDS(hist_path), before))

unlink(tmp, recursive = TRUE)
if (failures > 0L) quit(status = 1L)
cat("All playoff odds history backfill tests passed.\n")
