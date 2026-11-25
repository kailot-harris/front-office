# ==============================================================================
# tests/test_forward_log.R
#
# Momentum Board forward log (tools/log_momentum_forward.R) and its scorer
# (tools/score_forward_log.R), on small hand-built fixtures in tempdir():
#   1. the logger appends one row per team for today's as-of date
#   2. a second run on the same date appends nothing
#   3. a past (or future) as-of date is refused
#   4. a stale or missing board writes nothing
#   5. nulls in the board stay empty (no imputation)
#   6. the scorer skips rows whose outcome window is incomplete and prints
#      "not enough games yet" below the minimum sample
# The real data/history/ file is never touched.
#
# Usage: Rscript tests/test_forward_log.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  else normalizePath(base, winslash = "/", mustWork = FALSE)
})

failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("  PASS  %s\n", label))
  else { failures <<- failures + 1L; cat(sprintf("  FAIL  %s\n", label)) }
}

old_wd <- getwd()
setwd(REPO_ROOT)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
env <- new.env(parent = globalenv())
sys.source(file.path(REPO_ROOT, "tools", "log_momentum_forward.R"), envir = env)
sys.source(file.path(REPO_ROOT, "tools", "score_forward_log.R"), envir = env)
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
setwd(old_wd)

tmp <- file.path(tempdir(), sprintf("forward_log_test_%d", Sys.getpid()))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
real_log <- file.path(REPO_ROOT, "data", "history", "momentum_forward_log.csv")
real_before <- if (file.exists(real_log)) unname(tools::md5sum(real_log)) else NA_character_

today <- Sys.Date()
now <- Sys.time()
team_row <- function(team, w, combined, form = 2.5, elo = 1550, residual = 1.1) list(
  team = team, team_name = team, games_played = 12L, window = w, games_in_window = min(w, 12L),
  combined_score = list(value = combined, rank = 1L,
                        components = list(form_z = 0.5, trend_z = -0.2, residual_z = if (is.null(residual)) NULL else 0.1, elo_z = 0.3),
                        null_reason = NULL),
  model_residual = list(value = residual), opponent_adjusted_form = list(value = form),
  elo = list(current = elo, change_in_window = 12.5), sort_keys = list(net_rating_change = 3.2))
write_board <- function(path, generated_at = now, through = today - 1L) {
  rows <- function(w) list(team_row("AAA", w, 1.2), team_row("BBB", w, -0.4, residual = NULL),
                           team_row("CCC", w, NULL))
  b <- list(schema_version = 1L, generated_at = format(as.POSIXct(generated_at), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
            season = "2026-27", through_date = format(through), windows = list(5L, 10L, 18L),
            boards = list(`5` = list(rows = rows(5L)), `10` = list(rows = rows(10L)), `18` = list(rows = rows(18L))))
  jsonlite::write_json(b, path, auto_unbox = TRUE, null = "null", digits = NA)
}

cat("1-2. append one row per team; second run on the same date adds nothing\n")
board <- file.path(tmp, "momentum_board.json"); logp <- file.path(tmp, "history", "momentum_forward_log.csv")
write_board(board)
r1 <- suppressMessages(env$log_momentum_forward(board, logp, as_of = today, today = today, now = now))
lg <- read.csv(logp, colClasses = "character", na.strings = "")
ok("first run writes 3 rows (one per team)", r1$written == 3L && nrow(lg) == 3L)
ok("one row per (as_of_date, team)", !anyDuplicated(paste(lg$as_of_date, lg$team)) && all(lg$as_of_date == format(today)))
ok("header is the documented column set", identical(names(lg), env$FORWARD_LOG_COLUMNS))
ok("values copied from the board (w10 combined, elo_pregame, w5 form)",
   lg$w10_combined[lg$team == "AAA"] == "1.2" && lg$elo_pregame[lg$team == "AAA"] == "1550" && lg$w5_form[lg$team == "AAA"] == "2.5")
bytes1 <- unname(tools::md5sum(logp))
r2 <- suppressMessages(env$log_momentum_forward(board, logp, as_of = today, today = today, now = now + 60))
ok("second run on the same date appends nothing", r2$written == 0L && nrow(read.csv(logp)) == 3L)
ok("second run leaves the file byte-identical", identical(unname(tools::md5sum(logp)), bytes1))

cat("3. past and future dates are refused\n")
past <- tryCatch({ env$log_momentum_forward(board, logp, as_of = today - 1L, today = today); "no error" },
                 error = function(e) conditionMessage(e))
ok("past as_of raises an error", grepl("refuses", past) && grepl("before today", past))
fut <- tryCatch({ env$log_momentum_forward(board, logp, as_of = today + 1L, today = today); "no error" },
                error = function(e) conditionMessage(e))
ok("future as_of raises an error", grepl("refuses", fut))
ok("refused runs wrote nothing", identical(unname(tools::md5sum(logp)), bytes1))

cat("4. missing or stale board writes nothing\n")
logp2 <- file.path(tmp, "h2", "log.csv")
m <- suppressMessages(env$log_momentum_forward(file.path(tmp, "nope.json"), logp2, as_of = today, today = today))
ok("missing board: 0 rows, no file", m$written == 0L && !file.exists(logp2))
stale <- file.path(tmp, "stale.json"); write_board(stale, generated_at = now - 3 * 86400)
s <- suppressMessages(env$log_momentum_forward(stale, logp2, as_of = today, today = today))
ok("stale board (generated 3 days ago): 0 rows, no file", s$written == 0L && !file.exists(logp2) && grepl("stale", s$reason))
same <- file.path(tmp, "same.json"); write_board(same, through = today)
s2 <- suppressMessages(env$log_momentum_forward(same, logp2, as_of = today, today = today))
ok("board through today (may include today's games): 0 rows", s2$written == 0L && !file.exists(logp2))

cat("5. nulls stay empty\n")
ok("null combined score is empty, not 0", is.na(lg$w10_combined[lg$team == "CCC"]))
ok("null residual is empty, not 0", is.na(lg$w10_residual[lg$team == "BBB"]) && is.na(lg$w10_residual_z[lg$team == "BBB"]))

cat("6. scorer: incomplete windows skipped; tiny sample says not enough games yet\n")
# Fixture log: two teams logged on 2026-11-01 (through 2026-10-31). AAA then
# plays 10 games, BBB only 4 (window incomplete for both horizons).
flog <- file.path(tmp, "score_log.csv")
cols <- env$FORWARD_LOG_COLUMNS
mk <- function(team, w5, w10) { r <- setNames(as.list(rep(NA, length(cols))), cols)
  r$as_of_date <- "2026-11-01"; r$through_date <- "2026-10-31"; r$season <- "2026-27"; r$team <- team
  r$elo_pregame <- 1500; r$w5_combined <- w5; r$w10_combined <- w10; as.data.frame(r, stringsAsFactors = FALSE) }
write.table(rbind(mk("AAA", 0.5, 0.7), mk("BBB", -0.3, -0.1)), flog, sep = ",", na = "", row.names = FALSE)
gd <- as.Date("2026-11-01") + 0:9
panel <- rbind(
  data.frame(team = "AAA", game_id = sprintf("a%02d", 0:9), game_date = gd, margin = 5, opp_elo_pre = 1500,
             home = rep(c(TRUE, FALSE), 5), neutral = FALSE),
  data.frame(team = "BBB", game_id = sprintf("b%02d", 0:3), game_date = gd[1:4], margin = -2, opp_elo_pre = 1500,
             home = TRUE, neutral = FALSE),
  # a game before the as-of date must not count
  data.frame(team = "AAA", game_id = "a_old", game_date = as.Date("2026-10-30"), margin = 40, opp_elo_pre = 1500,
             home = TRUE, neutral = FALSE))
loader <- function(season) if (season == 2027L) panel else NULL
oc10 <- env$fl_outcomes(read.csv(flog, colClasses = "character", na.strings = ""), 10L, loader)
ok("AAA next-10 target = 5 - 0 (home/away alternate, equal Elo)", isTRUE(abs(oc10$target[1] - 5) < 1e-9))
ok("BBB skipped: window incomplete", oc10$status[2] == "window incomplete" && is.na(oc10$target[2]))
oc5 <- env$fl_outcomes(read.csv(flog, colClasses = "character", na.strings = ""), 5L, loader)
ok("AAA next-5 target = 5 - (3 home - 2 away) x 100/28 / 5", isTRUE(abs(oc5$target[1] - (5 - (100 / 28) / 5)) < 1e-9))
md <- file.path(tmp, "forward_log_scoring.md")
out <- capture.output(res <- env$score_forward_log(flog, loader, out_md = md))
ok("scorer prints 'not enough games yet'", any(grepl("not enough games yet", out)))
ok("report gives counts (rows logged 2, rows scored 1 for window 10)",
   res[[1]]$rows_logged == 2L && res[[1]]$rows_scored == 1L && res[[1]]$dates_scored == 1L)
txt <- readLines(md)
ok("report has no correlation number below the minimum", !any(grepl("Correlation:", txt)) && any(grepl("not enough games yet", txt)))
ok("report lists the incomplete-window skip", any(grepl("window incomplete 1", txt)))

cat("7. real data/history file untouched\n")
real_after <- if (file.exists(real_log)) unname(tools::md5sum(real_log)) else NA_character_
ok("data/history/momentum_forward_log.csv unchanged", identical(real_before, real_after))

unlink(tmp, recursive = TRUE)
cat(sprintf("\n%s: %d failure(s)\n", if (failures == 0L) "ALL PASS" else "FAILURES", failures))
if (failures > 0L) quit(status = 1L)
