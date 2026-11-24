# ==============================================================================
# tests/test_slot_c_media_gate.R
#
# Tests for Part 2 of NBA_analytics#130:
#   1. tools/refresh_slot_c.R regenerates nba_predictions_today.png cleanly for
#      today's slate and renders a deterministic no-games fallback PNG when zero
#      games are scheduled.
#   2. tools/publish_web.R Gate C (.assert_nonempty_diff) permits media-only
#      changes under web/public/media (e.g. nba_predictions_today.png) when
#      web/public/data JSON payloads are unchanged, and still fails when both
#      data and media are clean.
#
# Fully offline: uses tempdir() fixtures and a temporary git repo.
# Usage: Rscript --vanilla tests/test_slot_c_media_gate.R
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

# ------------------------------------------------------------------------------
section("1. tools/refresh_slot_c.R: game-day and quiet-night (0 games) refresh")
# ------------------------------------------------------------------------------

old_wd <- getwd()
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
slotc_env <- new.env(parent = globalenv())
sys.source(file.path(REPO_ROOT, "tools", "refresh_slot_c.R"), envir = slotc_env, keep.source = FALSE)
Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
setwd(old_wd)

ok("run_slot_c_refresh() is defined", is.function(slotc_env$run_slot_c_refresh))

scratch <- file.path(tempdir(), sprintf("slotc_media_gate_%d", Sys.getpid()))
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

cache_dir <- file.path(scratch, "cache")
media_dir <- file.path(scratch, "media")
dir.create(cache_dir, showWarnings = FALSE)

fixture <- data.frame(
  game_id   = c("g1", "g2"),
  game_date = as.Date(c("2026-11-23", "2026-11-25")),
  season    = c(2027L, 2027L),
  home_team = c("NYK", "BOS"),
  away_team = c("MIA", "PHI"),
  predicted_home_win_prob = c(0.62, 0.58),
  predicted_winner = c("NYK", "BOS"),
  status    = c("PENDING", "PENDING"),
  stringsAsFactors = FALSE
)
log_path <- file.path(scratch, "prediction_accuracy_log.rds")
saveRDS(fixture, log_path)

res_game <- suppressWarnings(suppressMessages(slotc_env$run_slot_c_refresh(
  target_date = as.Date("2026-11-23"),
  pred_log_file = log_path,
  cache_dir = cache_dir,
  web_media_dir = media_dir,
  run_gate = FALSE,
  project_root = REPO_ROOT
)))

today_png <- file.path(media_dir, "nba_predictions_today.png")
ok("game-day refresh returns kind=game_day", identical(res_game$plot_result$kind, "game_day"))
ok("game-day refresh writes nba_predictions_today.png", file.exists(today_png) && file.info(today_png)$size > 0)

res_quiet1 <- suppressWarnings(suppressMessages(slotc_env$run_slot_c_refresh(
  target_date = as.Date("2026-11-24"),
  pred_log_file = log_path,
  cache_dir = cache_dir,
  web_media_dir = media_dir,
  run_gate = FALSE,
  project_root = REPO_ROOT
)))
quiet_bytes_1 <- readBin(today_png, "raw", n = file.info(today_png)$size)

res_quiet2 <- suppressWarnings(suppressMessages(slotc_env$run_slot_c_refresh(
  target_date = as.Date("2026-11-24"),
  pred_log_file = log_path,
  cache_dir = cache_dir,
  web_media_dir = media_dir,
  run_gate = FALSE,
  project_root = REPO_ROOT
)))
quiet_bytes_2 <- readBin(today_png, "raw", n = file.info(today_png)$size)

ok("quiet-night refresh returns kind=no_games and n_games=0L",
   identical(res_quiet1$plot_result$kind, "no_games") && identical(res_quiet1$plot_result$n_games, 0L))
ok("quiet-night refresh writes non-empty nba_predictions_today.png",
   file.exists(today_png) && length(quiet_bytes_1) > 0)
ok("quiet-night fallback PNG bytes are deterministic across repeated runs",
   identical(quiet_bytes_1, quiet_bytes_2))

# ------------------------------------------------------------------------------
section("2. tools/publish_web.R Gate C permits media-only diffs")
# ------------------------------------------------------------------------------

pw_env <- new.env(parent = globalenv())
old_wd2 <- getwd()
sys.source(file.path(REPO_ROOT, "tools", "publish_web.R"), envir = pw_env, keep.source = FALSE)
setwd(old_wd2)

tmp_repo <- file.path(scratch, "git_repo")
repo_data  <- file.path(tmp_repo, "web", "public", "data")
repo_media <- file.path(tmp_repo, "web", "public", "media")
dir.create(repo_data, recursive = TRUE, showWarnings = FALSE)
dir.create(repo_media, recursive = TRUE, showWarnings = FALSE)

run_git <- function(repo, args) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(ok = is.null(st) || identical(as.integer(st), 0L),
       out = if (is.null(out)) character(0) else as.character(out))
}

init_res <- run_git(tmp_repo, c("init", "-b", "main"))
if (!init_res$ok) run_git(tmp_repo, c("init"))
run_git(tmp_repo, c("config", "user.name", shQuote("Test Bot")))
run_git(tmp_repo, c("config", "user.email", "test-bot@example.invalid"))

writeLines('{"ok":true}', file.path(repo_data, "matchups_slates.json"))
writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x01)), file.path(repo_media, "nba_predictions_today.png"))
run_git(tmp_repo, c("add", "-A"))
run_git(tmp_repo, c("commit", "-m", shQuote("initial fixture")))

pw_env$WEB_DATA_DIR  <- repo_data
pw_env$WEB_MEDIA_DIR <- repo_media

canon <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)

clean_res <- pw_env$.assert_nonempty_diff(canon(tmp_repo))
ok("Gate C fails when both web/public/data and web/public/media are clean",
   !isTRUE(clean_res$pass))

# Modify ONLY web/public/media/nba_predictions_today.png (JSON unchanged)
writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x02)), file.path(repo_media, "nba_predictions_today.png"))
media_only_res <- pw_env$.assert_nonempty_diff(canon(tmp_repo))
ok("Gate C passes on media-only diff when JSON payloads are unchanged",
   isTRUE(media_only_res$pass))
ok("Gate C changed list includes nba_predictions_today.png",
   any(grepl("web/public/media/nba_predictions_today\\.png", media_only_res$changed)))
ok("Gate C preserves paths='web/public/data' for downstream callers",
   identical(media_only_res$paths, "web/public/data"))

cat(sprintf("\n%d checks, %d failures\n", checks, failures))
if (failures > 0L) quit(status = 1L)
