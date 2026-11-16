# ==============================================================================
# tests/test_plot_today_predictions.R
#
# Tests for tools/plot_today_predictions.R (issue #130):
#   1. A date with games draws the game-day image for THAT date.
#   2. A date with no games draws the "No Games Scheduled" card for that date
#      (never another date's slate), names the next logged slate, writes all
#      four outputs, and returns normally.
#   3. A date between two seasons' logged games is labelled "Offseason".
#   4. A missing, unreadable, or column-deficient prediction log is an error,
#      and the script exits non-zero when run from the command line.
#
# The prediction log used here is a small hand-made fixture built in tempdir();
# it never touches cache/ or web/public/, and nothing here is published.
#
# Usage: Rscript --vanilla tests/test_plot_today_predictions.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}
section <- function(title) cat(sprintf("\n== %s ==\n", title))
error_message <- function(expr) {
  tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
}

# ------------------------------------------------------------------------------
section("Setup: source the script with autorun disabled; build a fixture log")
# ------------------------------------------------------------------------------

old_wd <- getwd()
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
plot_env <- new.env(parent = globalenv())
sys.source(file.path(REPO_ROOT, "tools", "plot_today_predictions.R"), envir = plot_env,
           keep.source = FALSE)
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
setwd(old_wd)

ok("plot_today_predictions() is defined", is.function(plot_env$plot_today_predictions))
ok("no latest_value_bets reference remains in the script",
   !any(grepl("latest_value_bets", readLines(file.path(REPO_ROOT, "tools", "plot_today_predictions.R")))))

scratch <- file.path(tempdir(), sprintf("plot_today_predictions_%d", Sys.getpid()))
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
cache_dir <- file.path(scratch, "cache")
media_dir <- file.path(scratch, "media")
dir.create(cache_dir, showWarnings = FALSE)

# Season A ends 2026-04-12; season B starts 2026-10-21 with a gap on 10-23.
fixture <- data.frame(
  game_id   = c("a1", "b1", "b2", "b3", "b4", "b5"),
  game_date = as.Date(c("2026-04-12", "2026-10-21", "2026-10-21", "2026-10-22",
                        "2026-10-24", "2026-10-24")),
  season    = c(2026L, 2027L, 2027L, 2027L, 2027L, 2027L),
  home_team = c("Home1", "Home2", "Home3", "Home4", "Home5", "Home6"),
  away_team = c("Away1", "Away2", "Away3", "Away4", "Away5", "Away6"),
  predicted_home_win_prob = c(0.60, 0.55, 0.40, 0.70, 0.52, 0.35),
  predicted_winner = c("Home1", "Home2", "Away3", "Home4", "Home5", "Away6"),
  status    = c("RESOLVED", "RESOLVED", "RESOLVED", "PENDING", "PENDING", "PENDING"),
  stringsAsFactors = FALSE
)
log_path <- file.path(scratch, "prediction_accuracy_log.rds")
saveRDS(fixture, log_path)

run_plot <- function(date, path = log_path) {
  suppressWarnings(suppressMessages(plot_env$plot_today_predictions(
    target_date = as.Date(date), pred_log_file = path,
    cache_dir = cache_dir, web_media_dir = media_dir)))
}
expected_outputs <- function(date) {
  c(file.path(cache_dir, sprintf("nba_predictions_%s.png", date)),
    file.path(cache_dir, sprintf("nba_predictions_%s.gif", date)),
    file.path(cache_dir, "nba_predictions_today.png"),
    file.path(cache_dir, "nba_predictions_today.gif"),
    file.path(media_dir, sprintf("nba_predictions_%s.png", date)),
    file.path(media_dir, sprintf("nba_predictions_%s.gif", date)),
    file.path(media_dir, "nba_predictions_today.png"),
    file.path(media_dir, "nba_predictions_today.gif"))
}

# ------------------------------------------------------------------------------
section("1. Game day draws that date's slate")
# ------------------------------------------------------------------------------

res <- run_plot("2026-10-22")
ok("kind is game_day", identical(res$kind, "game_day"))
ok("target date is unchanged", identical(res$target_date, as.Date("2026-10-22")))
ok("one game drawn", identical(res$n_games, 1L))
ok("all eight outputs written", all(file.exists(expected_outputs("2026-10-22"))))
built <- plot_env$build_game_day_plot(fixture[fixture$game_date == as.Date("2026-10-22"), ],
                                      as.Date("2026-10-22"))
ok("game-day title names the target date",
   identical(built$plot$labels$title, "NBA — Model Projections for Oct 22, 2026"))

# ------------------------------------------------------------------------------
section("2. No-games date draws the fallback card for that date")
# ------------------------------------------------------------------------------

msgs <- character(0)
res <- withCallingHandlers(
  suppressWarnings(plot_env$plot_today_predictions(
    target_date = as.Date("2026-10-23"), pred_log_file = log_path,
    cache_dir = cache_dir, web_media_dir = media_dir)),
  message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
ok("kind is no_games", identical(res$kind, "no_games"))
ok("target date is NOT substituted with the next slate",
   identical(res$target_date, as.Date("2026-10-23")))
ok("next slate is 2026-10-24 with 2 games",
   identical(res$next_slate$date, as.Date("2026-10-24")) && identical(res$next_slate$n_games, 2L))
ok("dated and _today outputs written in cache and media",
   all(file.exists(expected_outputs("2026-10-23"))))
ok("no image was written for the next slate's date",
   !file.exists(file.path(cache_dir, "nba_predictions_2026-10-24.png")))
ok("logs the no-games line",
   any(grepl("No NBA games on 2026-10-23; wrote no-games fallback image (next slate 2026-10-24)",
             msgs, fixed = TRUE)))
card <- plot_env$build_no_games_plot(as.Date("2026-10-23"), res$next_slate, FALSE)
ok("card title is 'No Games Scheduled for Oct 23, 2026'",
   identical(card$plot$labels$title, "NBA — No Games Scheduled for Oct 23, 2026"))
ok("card subtitle names the season",
   grepl("^Season [0-9]{4} · Generated ", card$plot$labels$subtitle))
ok("card carries the 'Next slate: Sat, Oct 24 (2 games)' line",
   any(vapply(card$plot$layers, function(l) {
     lab <- l$aes_params$label
     !is.null(lab) && identical(lab, "Next slate: Sat, Oct 24 (2 games)")
   }, logical(1))))

res <- run_plot("2026-10-30")
ok("date after the last logged game: no_games, no next slate",
   identical(res$kind, "no_games") && is.null(res$next_slate))

# ------------------------------------------------------------------------------
section("3. Between seasons is labelled Offseason")
# ------------------------------------------------------------------------------

res <- run_plot("2026-07-04")
ok("kind is offseason", identical(res$kind, "offseason"))
ok("offseason still points at the next slate",
   identical(res$next_slate$date, as.Date("2026-10-21")))
card <- plot_env$build_no_games_plot(as.Date("2026-07-04"), res$next_slate, TRUE)
ok("offseason title", identical(card$plot$labels$title, "NBA — Offseason for Jul 04, 2026"))

# ------------------------------------------------------------------------------
section("4. Missing or unreadable prediction log is an error")
# ------------------------------------------------------------------------------

msg <- error_message(run_plot("2026-10-22", file.path(scratch, "does_not_exist.rds")))
ok("missing log stops with 'Prediction log not found'",
   !is.na(msg) && grepl("Prediction log not found", msg, fixed = TRUE))

bad_path <- file.path(scratch, "corrupt.rds")
writeLines("not an rds file", bad_path)
msg <- error_message(run_plot("2026-10-22", bad_path))
ok("corrupt log stops with 'Prediction log is unreadable'",
   !is.na(msg) && grepl("Prediction log is unreadable", msg, fixed = TRUE))

thin_path <- file.path(scratch, "thin.rds")
saveRDS(fixture[, c("game_date", "home_team")], thin_path)
msg <- error_message(run_plot("2026-10-22", thin_path))
ok("log missing columns stops naming them",
   !is.na(msg) && grepl("missing required column", msg, fixed = TRUE))

# Command-line exit status: run the real script from a scratch project root
# (a copy of config.R plus the script) whose cache/ has no prediction log.
cli_root <- file.path(scratch, "cli_root")
dir.create(file.path(cli_root, "tools"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(REPO_ROOT, "config.R"), file.path(cli_root, "config.R"), overwrite = TRUE))
invisible(file.copy(file.path(REPO_ROOT, "tools", "plot_today_predictions.R"),
          file.path(cli_root, "tools", "plot_today_predictions.R"), overwrite = TRUE))
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
cli_out <- suppressWarnings(system2(rscript,
  c("--vanilla", shQuote(file.path(cli_root, "tools", "plot_today_predictions.R")), "--date=2026-10-22"),
  stdout = TRUE, stderr = TRUE))
cli_status <- attr(cli_out, "status")
ok("CLI with no prediction log exits non-zero",
   !is.null(cli_status) && cli_status != 0)
ok("CLI error names the missing prediction log",
   any(grepl("Prediction log not found", cli_out, fixed = TRUE)))
ok("CLI wrote no image when the log is missing",
   length(list.files(file.path(cli_root, "cache"), pattern = "^nba_predictions_")) == 0)

unlink(scratch, recursive = TRUE)

cat(sprintf("\n%d checks, %d failures\n", checks, failures))
if (failures > 0L) quit(status = 1L)
