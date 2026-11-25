# ==============================================================================
# tests/test_forward_log.R - QB-change forward logger and its scorer (issue #220 follow-up)
# Offline, base R. Uses a small hand-built fixture in temp directories; never
# touches the real data/history/ log or cache/.
#   1. the logger appends one row per playing team per as-of date (bye: no row)
#   2. a second run on the same date appends nothing
#   3. a past as-of date is refused
#   4. the scorer skips incomplete windows and says "not enough games yet"
#   5. config / pipeline / publish wiring
# Run: Rscript tests/test_forward_log.R
# ==============================================================================
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
root_dir <- if (file.exists("config.R")) getwd() else normalizePath("..", winslash = "/")
setwd(root_dir)
suppressPackageStartupMessages(library(dplyr))
source("config.R")
source(file.path("tools", "elo_model.R"))
source(file.path("tools", "log_qb_change_forward.R"))
source(file.path("tools", "score_forward_log.R"))

tmp <- tempfile("fwdlog_"); dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
today <- Sys.Date()
S <- as.integer(CURRENT_SEASON)

# ---- fixture: 5 teams; a 120-game prior season (Elo warm-up), then this season ----
teams <- c("AAA", "BBB", "CCC", "DDD", "EEE")
pairs <- t(combn(teams, 2))
mk_game <- function(season, week, day, home, away, hs, as) {
  data.frame(game_id = sprintf("%d_%02d_%s_%s", season, week, away, home), season = season, game_type = "REG",
             week = week, gameday = format(day), home_team = home, away_team = away,
             home_score = hs, away_score = as, location = "Home", stringsAsFactors = FALSE)
}
prev <- list(); d0 <- as.Date(sprintf("%d-09-01", S - 1L))
for (w in 1:12) for (p in seq_len(nrow(pairs))) {
  i <- (w - 1L) * nrow(pairs) + p
  prev[[length(prev) + 1L]] <- mk_game(S - 1L, w, d0 + 7L * (w - 1L), pairs[p, 1], pairs[p, 2],
                                       17L + (i %% 7L), 14L + (i %% 5L))
}
cur <- list(
  mk_game(S, 1, today - 14L, "AAA", "BBB", 24L, 17L), mk_game(S, 1, today - 14L, "CCC", "DDD", 10L, 20L),
  mk_game(S, 1, today - 14L, "EEE", "AAA", NA, NA)[0, ],
  mk_game(S, 2, today - 7L, "BBB", "AAA", 21L, 13L), mk_game(S, 2, today - 7L, "DDD", "CCC", 27L, 3L),
  mk_game(S, 2, today - 6L, "EEE", "CCC", 14L, 14L),
  mk_game(S, 3, today + 2L, "AAA", "CCC", NA, NA), mk_game(S, 3, today + 2L, "BBB", "DDD", NA, NA),
  mk_game(S, 4, today + 9L, "EEE", "AAA", NA, NA), mk_game(S, 5, today + 16L, "AAA", "DDD", NA, NA))
sch <- do.call(rbind, c(prev, cur))
sched_path <- file.path(tmp, "schedules.rds"); saveRDS(sch, sched_path)

# play-by-play: AAA's starter changes from game 1 to game 2; BBB keeps its starter.
qb <- list(AAA = c("QA1", "QA2"), BBB = c("QB1", "QB1"), CCC = c("QC1", "QC1"), DDD = c("QD1", "QD1"))
pbp <- list()
for (g in which(sch$season == S & !is.na(sch$home_score))) {
  for (tm in c(sch$home_team[g], sch$away_team[g])) {
    k <- if (sch$week[g] == 1) 1L else 2L
    starter <- if (tm %in% names(qb)) qb[[tm]][k] else "QE1"
    pbp[[length(pbp) + 1L]] <- data.frame(
      game_id = sch$game_id[g], season = S, season_type = "REG", posteam = tm, qb_dropback = 1,
      passer_player_id = c(rep(starter, 30), rep("BACKUP", 3), NA),
      rusher_player_id = c(rep(NA, 33), starter), stringsAsFactors = FALSE)
  }
}
pbp <- do.call(rbind, pbp)
pbp_path <- file.path(tmp, "pbp.rds"); saveRDS(pbp, pbp_path)
log_path <- file.path(tmp, "history", "qb_change_forward_log.csv")

# ---- 1. one row per playing team for today ----
r1 <- log_qb_change_forward(today, sched_path, pbp_path, log_path, S)
lg <- read.csv(log_path, stringsAsFactors = FALSE, colClasses = "character")
ok("FL-1 log written with the expected header", identical(names(lg), QCF_COLUMNS))
ok("FL-2 one row per team playing this week (4 teams), as-of date today",
   nrow(lg) == 4L && setequal(lg$team, c("AAA", "BBB", "CCC", "DDD")) && all(lg$as_of_date == format(today)))
ok("FL-3 team on a bye this week (EEE) has no row", !"EEE" %in% lg$team)
ok("FL-4 only unplayed games dated today or later are logged",
   all(lg$week == "3") && all(as.Date(lg$next_game_date) >= today))
ok("FL-5 qb_change_last: AAA TRUE (starter changed), BBB FALSE",
   lg$qb_change_last[lg$team == "AAA"] == "TRUE" && lg$qb_change_last[lg$team == "BBB"] == "FALSE")
a <- lg[lg$team == "AAA", ]
ok("FL-6 expected margin = (Elo - opp Elo + HCA x home sign) / pts per margin",
   abs(as.numeric(a$elo_expected_margin) -
         (as.numeric(a$elo_pre) - as.numeric(a$opp_elo_pre) + ELO_HCA_POINTS) / ELO_POINTS_PER_MARGIN_PT) < 1e-3)

# ---- 2. idempotent on the same date ----
before <- readLines(log_path)
r2 <- log_qb_change_forward(today, sched_path, pbp_path, log_path, S)
ok("FL-7 second run on the same date appends nothing and changes nothing",
   nrow(r2) == 0L && identical(readLines(log_path), before))

# ---- 3. past dates refused ----
err <- tryCatch({ log_qb_change_forward(today - 1L, sched_path, pbp_path, log_path, S); NULL },
                error = function(e) conditionMessage(e))
ok("FL-8 a past as-of date is refused (error, no backfill)", !is.null(err) && grepl("refusing", err))
ok("FL-9 the refused run left the log untouched", identical(readLines(log_path), before))

# NA stays NA: a team whose latest game has no play-by-play gets qb_change_last NA.
pbp2_path <- file.path(tmp, "pbp2.rds"); saveRDS(pbp[pbp$posteam != "CCC", ], pbp2_path)
r3 <- log_qb_change_forward(today, sched_path, pbp2_path, file.path(tmp, "other.csv"), S, dry_run = TRUE)
ok("FL-10 missing play-by-play leaves qb_change_last missing (no imputation)",
   is.na(r3$qb_change_last[r3$team == "CCC"]) && !file.exists(file.path(tmp, "other.csv")))

# ---- 4. scorer: incomplete windows skipped, tiny sample -> "not enough games yet" ----
done <- sch[!is.na(sch$home_score), ]; done$gameday <- as.Date(done$gameday)
elo_games <- run_elo_walkforward(done, data.frame(game_id = character(0), team = character(0),
                                                  fatigue_drag_pts = numeric(0)), ELO_K_FACTOR)
fx <- rbind(
  # prior season week 1: next game and next 3 all played
  data.frame(season = as.character(S - 1L), week = "1", as_of_date = format(d0 - 1L), team = "AAA",
             opponent = "BBB", next_game_id = sprintf("%d_01_BBB_AAA", S - 1L), next_game_date = format(d0),
             home = "TRUE", elo_pre = "1500", opp_elo_pre = "1500", elo_expected_margin = "1.92",
             last_game_id = NA, qb_id_last = NA, qb_id_prev = NA, qb_change_last = "TRUE", logged_at = "x"),
  # this season: the logged row from today (games not yet played -> skipped)
  lg)
fx$last_game_id <- as.character(fx$last_game_id)
sc <- sfl_score_rows(fx, sch, elo_games)
ok("FL-11 scorer skips rows whose games are not played yet",
   sum(sc$rows$complete1) == 1L && sum(sc$rows$complete3) == 1L && sc$units == 5L)
ok("FL-12 next-game margin beyond Elo = margin - logged expected margin",
   abs(sc$rows$beyond1[sc$rows$complete1] - ((sch$home_score[1] - sch$away_score[1]) - 1.92)) < 1e-9)
fx_path <- file.path(tmp, "fx.csv"); write.csv(fx, fx_path, row.names = FALSE)
out_md <- file.path(tmp, "forward_log_scoring.md")
res <- suppressWarnings(capture.output(score_forward_log(fx_path, sched_path, out_md, n_boot = 50L)))
md <- readLines(out_md)
ok("FL-13 tiny fixture: report says 'not enough games yet' for both horizons",
   sum(grepl("not enough games yet", md)) == 2L)
ok("FL-14 report gives rows logged and rows scored, and no difference number",
   any(grepl("Rows logged: 5", md)) && any(grepl("Rows scored: 1", md)) && !any(grepl("Difference", md)))

# above the minimum, the comparison reports a CI
big <- data.frame(season = rep(as.character(2000 + 1:40), each = 6), team = rep(sprintf("T%02d", 1:40), each = 6),
                  next_game_id = sprintf("g%d", 1:240), flag = rep(c(TRUE, rep(FALSE, 5)), 40),
                  beyond1 = rep(c(2, 0, 1, -1, 0.5, -0.5), 40), beyond3 = 0, complete1 = TRUE, complete3 = TRUE)
cm <- sfl_compare(big, "beyond1", "complete1", n_boot = 200L)
ok("FL-15 at 40 flagged / 240 rows the comparison reports a difference and a 95% CI",
   isTRUE(cm$enough) && abs(cm$diff - 2) < 1e-9 && cm$ci_lo <= cm$diff && cm$ci_hi >= cm$diff)

# ---- 5. wiring ----
ok("FL-16 config: FORWARD_LOG_QB_CHANGE under data/history and in PIPELINE_OUTPUT_FILES",
   gsub("\\\\", "/", FORWARD_LOG_QB_CHANGE) == "data/history/qb_change_forward_log.csv" &&
     FORWARD_LOG_QB_CHANGE %in% PIPELINE_OUTPUT_FILES)
pl <- readLines("run_full_pipeline.R")
i_log <- grep("log_qb_change_forward.R", pl, fixed = TRUE)[1]
ok("FL-17 pipeline: logger stage after the ingest, Elo and play-by-play stages",
   !is.na(i_log) && i_log > grep("\"team_ratings_engine.R\"", pl, fixed = TRUE)[1] &&
     i_log > grep("run_stage(\"build_passing_dataset.R\"", pl, fixed = TRUE)[1])
pw <- readLines(file.path("tools", "publish_web.R"))
ok("FL-18 publish step stages the forward log by exact path", any(grepl("FORWARD_LOG_QB_CHANGE", pw, fixed = TRUE)))
ign <- Sys.which("git")
if (nzchar(ign)) {
  st <- suppressWarnings(system2(ign, c("check-ignore", "-q", "data/history/qb_change_forward_log.csv"),
                                 stdout = FALSE, stderr = FALSE))
  ok("FL-19 the forward log path is not gitignored", identical(as.integer(st), 1L))
} else cat("[SKIP] FL-19 git unavailable\n")

cat(sprintf("\n%d failure(s)\n", failures))
if (failures > 0L) quit(status = 1L)
