# ==============================================================================
# tests/test_forward_log_windows.R
#
# The forward log's windows come from ROLLING_WINDOW_SIZE through the helper the
# board uses (R/momentum_windows.R), on small hand-built fixtures in tempdir():
#   1. with the current setting the windows are 5, 10, 18 and match the board's
#      MOMENTUM_WINDOWS
#   2. the column list is unchanged: same names, same order as the spelled-out
#      list, the tracked log's header and (when git is available) the logger on
#      origin/main
#   3. a different window setting produces a different header, so against an
#      existing log the logger warns and writes nothing (file byte-identical)
#   4. a board whose published window sizes (windows, methods.windows.sizes)
#      differ from the setting is refused
# The real data/history/ file is never touched.
#
# Usage: Rscript tests/test_forward_log_windows.R
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

# Loads the logger into a fresh environment; `rolling` (when given) stands in
# for config.R's ROLLING_WINDOW_SIZE, otherwise config.R itself is read.
load_logger <- function(rolling = NULL) {
  old_wd <- getwd(); on.exit({ setwd(old_wd); Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") })
  setwd(REPO_ROOT)
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  e <- new.env(parent = globalenv())
  if (!is.null(rolling)) assign("ROLLING_WINDOW_SIZE", rolling, envir = e)
  suppressMessages(sys.source(file.path(REPO_ROOT, "tools", "log_momentum_forward.R"), envir = e))
  e
}

real_log <- file.path(REPO_ROOT, "data", "history", "momentum_forward_log.csv")
real_before <- if (file.exists(real_log)) unname(tools::md5sum(real_log)) else NA_character_

env <- load_logger()

cat("1. windows derived from the setting\n")
ok("ROLLING_WINDOW_SIZE in config.R is 18", identical(as.integer(env$ROLLING_WINDOW_SIZE), 18L))
ok("derived windows are c(5L, 10L, 18L)", identical(env$FORWARD_LOG_WINDOWS, c(5L, 10L, 18L)))
board_env <- local({
  old_wd <- getwd(); on.exit({ setwd(old_wd); Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") })
  setwd(REPO_ROOT); Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  e <- new.env(parent = globalenv())
  ok_src <- tryCatch({ suppressWarnings(suppressMessages(sys.source(file.path(REPO_ROOT, "build_momentum_dataset.R"), envir = e))); TRUE },
                     error = function(err) { cat(sprintf("  (build_momentum_dataset.R not loadable here: %s)\n", conditionMessage(err))); FALSE })
  if (ok_src) e else NULL
})
ok("logger windows equal the board's MOMENTUM_WINDOWS",
   !is.null(board_env) && identical(env$FORWARD_LOG_WINDOWS, board_env$MOMENTUM_WINDOWS))

cat("2. column list unchanged\n")
expected_cols <- c(
  "as_of_date", "logged_at_utc", "board_generated_at", "through_date", "season",
  "team", "games_played", "elo_pregame",
  unlist(lapply(c(5L, 10L, 18L), function(w) sprintf("w%d_%s", w,
    c("combined", "combined_rank", "form_z", "trend_z", "residual_z", "elo_z",
      "form", "trend", "residual", "elo_change", "games_in_window")))))
ok(sprintf("columns equal the spelled-out list (%d columns, same order)", length(expected_cols)),
   identical(env$FORWARD_LOG_COLUMNS, expected_cols))
if (file.exists(real_log)) {
  real_header <- names(utils::read.csv(real_log, nrows = 1L, colClasses = "character", check.names = FALSE))
  ok("columns equal the tracked data/history log's header", identical(env$FORWARD_LOG_COLUMNS, real_header))
} else cat("  SKIP  tracked log not present in this checkout\n")
main_src <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), "show", "origin/main:tools/log_momentum_forward.R"),
                                               stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
if (length(main_src) && is.null(attr(main_src, "status"))) {
  main_file <- tempfile(fileext = ".R"); writeLines(main_src, main_file)
  main_env <- local({
    old_wd <- getwd(); on.exit({ setwd(old_wd); Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") })
    setwd(REPO_ROOT); Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
    e <- new.env(parent = globalenv())
    suppressMessages(sys.source(main_file, envir = e)); e
  })
  cat(sprintf("  origin/main columns: %s\n", paste(main_env$FORWARD_LOG_COLUMNS, collapse = ",")))
  cat(sprintf("  this branch columns: %s\n", paste(env$FORWARD_LOG_COLUMNS, collapse = ",")))
  ok("columns identical to the logger on origin/main", identical(env$FORWARD_LOG_COLUMNS, main_env$FORWARD_LOG_COLUMNS))
  unlink(main_file)
} else cat("  SKIP  git show origin/main not available\n")

# --- fixtures ----------------------------------------------------------------
tmp <- file.path(tempdir(), sprintf("forward_log_windows_test_%d", Sys.getpid()))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
today <- Sys.Date(); now <- Sys.time()
team_row <- function(team, w) list(
  team = team, team_name = team, games_played = 25L, window = w, games_in_window = w,
  combined_score = list(value = 0.7, rank = 1L, components = list(form_z = 0.5, trend_z = -0.2, residual_z = 0.1, elo_z = 0.3)),
  model_residual = list(value = 1.1), opponent_adjusted_form = list(value = 2.5),
  elo = list(current = 1550, change_in_window = 12.5), sort_keys = list(net_rating_change = 3.2))
write_board <- function(path, sizes) {
  boards <- setNames(lapply(sizes, function(w) list(rows = list(team_row("AAA", w), team_row("BBB", w)))), as.character(sizes))
  b <- list(schema_version = 1L, generated_at = format(as.POSIXct(now), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
            season = "2026-27", through_date = format(today - 1L),
            windows = as.list(sizes), default_window = sizes[[length(sizes)]], boards = boards,
            methods = list(windows = list(sizes = as.list(sizes))))
  jsonlite::write_json(b, path, auto_unbox = TRUE, null = "null", digits = NA)
}
capture_warn <- function(expr) {
  msgs <- character(0)
  res <- withCallingHandlers(expr, message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  list(res = res, msgs = msgs)
}

cat("3. a different window setting -> header mismatch -> warn, write nothing\n")
board18 <- file.path(tmp, "board18.json"); write_board(board18, env$FORWARD_LOG_WINDOWS)
logp <- file.path(tmp, "history", "momentum_forward_log.csv")
r0 <- suppressMessages(env$log_momentum_forward(board18, logp, as_of = today, today = today, now = now))
ok("current setting writes rows with the existing header", r0$written == 2L &&
   identical(names(utils::read.csv(logp, check.names = FALSE)), expected_cols))
bytes0 <- unname(tools::md5sum(logp))

env20 <- load_logger(rolling = 20)
ok("setting 20 derives windows 5, 10, 20", identical(env20$FORWARD_LOG_WINDOWS, c(5L, 10L, 20L)))
ok("setting 20 derives a different header (w20_* instead of w18_*)",
   !identical(env20$FORWARD_LOG_COLUMNS, expected_cols) && any(grepl("^w20_", env20$FORWARD_LOG_COLUMNS)) &&
   !any(grepl("^w18_", env20$FORWARD_LOG_COLUMNS)))
board20 <- file.path(tmp, "board20.json"); write_board(board20, env20$FORWARD_LOG_WINDOWS)
r20 <- capture_warn(env20$log_momentum_forward(board20, logp, as_of = today + 0L, today = today, now = now + 60))
for (m in r20$msgs) cat(sprintf("    message: %s", m))
ok("setting 20 writes nothing", r20$res$written == 0L)
ok("setting 20 warns about the header", any(grepl("\\[WARN\\].*different header.*nothing appended", r20$msgs)))
ok("existing log left byte-identical", identical(unname(tools::md5sum(logp)), bytes0))

cat("4. board window sizes differing from the setting -> warn, write nothing\n")
r_mis <- capture_warn(env$log_momentum_forward(board20, logp, as_of = today, today = today, now = now + 120))
for (m in r_mis$msgs) cat(sprintf("    message: %s", m))
ok("mismatched board sizes write nothing", r_mis$res$written == 0L)
ok("mismatched board sizes warn", any(grepl("\\[WARN\\].*window sizes in windows \\(5, 10, 20\\) differ", r_mis$msgs)))
board_meth <- file.path(tmp, "board_methods.json"); write_board(board_meth, env$FORWARD_LOG_WINDOWS)
bm <- jsonlite::fromJSON(board_meth, simplifyVector = FALSE); bm$methods$windows$sizes <- list(5L, 10L, 20L)
jsonlite::write_json(bm, board_meth, auto_unbox = TRUE, null = "null", digits = NA)
r_meth <- capture_warn(env$log_momentum_forward(board_meth, logp, as_of = today, today = today, now = now + 180))
ok("mismatched methods.windows.sizes write nothing and warn", r_meth$res$written == 0L &&
   any(grepl("\\[WARN\\].*methods\\.windows\\.sizes \\(5, 10, 20\\) differ", r_meth$msgs)))
real_board <- file.path(REPO_ROOT, "web", "public", "data", "momentum_board.json")
if (file.exists(real_board)) {
  rb <- jsonlite::fromJSON(real_board, simplifyVector = FALSE)
  ok("the tracked momentum_board.json publishes windows equal to the derived ones",
     identical(as.integer(unlist(rb$windows)), env$FORWARD_LOG_WINDOWS) &&
     identical(as.integer(unlist(rb$methods$windows$sizes)), env$FORWARD_LOG_WINDOWS))
} else cat("  SKIP  tracked momentum_board.json not present in this checkout\n")
ok("existing log still byte-identical", identical(unname(tools::md5sum(logp)), bytes0))

cat("5. real data/history file untouched\n")
real_after <- if (file.exists(real_log)) unname(tools::md5sum(real_log)) else NA_character_
ok("data/history/momentum_forward_log.csv unchanged", identical(real_before, real_after))

unlink(tmp, recursive = TRUE)
cat(sprintf("\n%s: %d failure(s)\n", if (failures == 0L) "ALL PASS" else "FAILURES", failures))
if (failures > 0L) quit(status = 1L)
