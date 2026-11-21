# tests/test_render_weekly_gifs.R
# Offline tests for render_weekly_gifs.R: the 6-day due check, per-script isolation
# (one failing script never stops the others or raises), the off-season skip and the
# FO_FORCE_GIF_RENDER=1 override. Uses throwaway fake scripts; no real GIF is rendered.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("config.R")
source("render_weekly_gifs.R")

now <- as.POSIXct("2026-11-21 12:00:00", tz = "UTC")
ok("GIF_RERENDER_DAYS is 6", identical(GIF_RERENDER_DAYS, 6))
ok("5 days old -> not due", identical(gif_scripts_due(now - 5 * 86400, now), FALSE))
ok("6 days old -> due", identical(gif_scripts_due(now - 6 * 86400, now), TRUE))
ok("no GIFs -> due", identical(gif_scripts_due(as.POSIXct(NA), now), TRUE) &&
   identical(gif_scripts_due(as.POSIXct(character(0)), now), TRUE))

tmp <- tempfile("rwg_"); dir.create(tmp)
out_file <- file.path(tmp, "written.txt")
good <- file.path(tmp, "gif_good.R")
writeLines(sprintf('writeLines("ok", "%s")', gsub("\\\\", "/", out_file)), good)
bad <- file.path(tmp, "gif_bad.R")
writeLines("quit(status = 1)", bad)
media <- file.path(tmp, "animations"); dir.create(media)   # empty -> due
status <- file.path(tmp, "status.json")

Sys.unsetenv("FO_FORCE_GIF_RENDER")
res <- tryCatch(run_render_weekly_gifs(media, scripts = c(good, bad), in_season = TRUE, now = now,
                                       status_path = status),
                error = function(e) e)
ok("one failing script raises no error", is.list(res) && !inherits(res, "error"))
ok("good script rendered, bad script failed",
   identical(res$rendered, basename(good)) && identical(res$failed, basename(bad)) && is.null(res$skipped_reason))
ok("good script actually ran", file.exists(out_file))
ok("status file written", file.exists(status))

unlink(out_file)
off <- run_render_weekly_gifs(media, scripts = good, in_season = FALSE, now = now, status_path = status)
ok("offseason -> skipped, nothing rendered",
   identical(off$skipped_reason, "offseason") && length(off$rendered) == 0L && !file.exists(out_file))

# Due is driven by the status file's last_success_at, not by GIF/commit dates.
st1 <- jsonlite::fromJSON(status)
ok("status records last_success_at = the successful run's time",
   identical(st1$last_success_at, "2026-11-21T12:00:00Z"))
ok("offseason skip keeps last_success_at", identical(jsonlite::fromJSON(status)$last_success_at, "2026-11-21T12:00:00Z"))
nd <- run_render_weekly_gifs(media, scripts = good, in_season = TRUE, now = now + 5 * 86400, status_path = status)
ok("last success 5 days ago -> not due (even with no GIFs in media_dir)",
   identical(nd$skipped_reason, "not_due") && !file.exists(out_file))
g <- file.path(media, "x.gif"); writeBin(as.raw(1:3), g)
Sys.setFileTime(g, now + 6 * 86400)   # e.g. a publish/copy touching the GIF today
due6 <- run_render_weekly_gifs(media, scripts = good, in_season = TRUE, now = now + 6 * 86400, status_path = status)
ok("last success 6 days ago -> due, even though a GIF looks brand new",
   is.null(due6$skipped_reason) && identical(due6$rendered, basename(good)))
unlink(out_file)
unlink(status)
nd2 <- run_render_weekly_gifs(media, scripts = good, in_season = TRUE, now = now + 7 * 86400, status_path = status)
ok("status file missing -> falls back to newest GIF mtime (1 day old -> not due)",
   identical(nd2$skipped_reason, "not_due") && !file.exists(out_file))

Sys.setenv(FO_FORCE_GIF_RENDER = "1")
forced <- run_render_weekly_gifs(media, scripts = good, in_season = FALSE, now = now, status_path = status)
Sys.unsetenv("FO_FORCE_GIF_RENDER")
ok("FO_FORCE_GIF_RENDER=1 overrides offseason and not-due",
   is.null(forced$skipped_reason) && identical(forced$rendered, basename(good)) && file.exists(out_file))

# Every script failing -> status file not rewritten (strict_output reports the stage as failed).
unlink(status)
allbad <- run_render_weekly_gifs(file.path(tmp, "none"), scripts = bad, in_season = TRUE, now = now,
                                 status_path = status)
ok("all scripts failing -> no error, no status file",
   identical(allbad$failed, basename(bad)) && !file.exists(status))

# A hanging script (with a hanging child R process) is killed with its whole tree on timeout.
marker <- paste0("rwg_hang_", as.integer(runif(1, 1e8, 1e9)))
hang <- file.path(tmp, paste0("gif_", marker, ".R"))
child <- file.path(R.home("bin"), "Rscript")
started <- file.path(tmp, "hang_started.txt")
writeLines(c(sprintf('writeLines("x", "%s")', gsub("\\\\", "/", started)),
             sprintf('system2("%s", c("-e", shQuote("Sys.sleep(120) # %s")))', gsub("\\\\", "/", child), marker),
             "Sys.sleep(120)"), hang)
procs_with <- function(m) {
  if (.Platform$OS.type == "windows") {
    out <- suppressWarnings(system2("powershell", c("-NoProfile", "-Command",
      shQuote(sprintf("Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*%s*' -and $_.Name -notin @('powershell.exe','bash.exe','cmd.exe') } | ForEach-Object { $_.ProcessId }", m))),
      stdout = TRUE, stderr = FALSE))
  } else {
    out <- suppressWarnings(system2("pgrep", c("-f", shQuote(paste0("[", substr(m, 1, 1), "]", substring(m, 2)))), stdout = TRUE, stderr = FALSE))
  }
  out[nzchar(trimws(out))]
}
unlink(status)
Sys.setenv(FO_FORCE_GIF_RENDER = "1")
t0 <- Sys.time()
hr <- run_render_weekly_gifs(media, scripts = c(hang, good), in_season = TRUE, now = now, status_path = status,
                             timeout_sec = 5)
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
Sys.unsetenv("FO_FORCE_GIF_RENDER")
Sys.sleep(1)
ok("hanging script times out as failed; next script still renders",
   identical(hr$failed, basename(hang)) && identical(hr$rendered, basename(good)) && el < 60)
ok("no process with the hanging script's command line survives (script did start)",
   file.exists(started) && length(procs_with(marker)) == 0L)

# sync_gif_to_media(): a script that only wrote cache/ still gets published.
cdir <- file.path(tmp, "cache"); dir.create(cdir); mdir <- file.path(tmp, "media"); dir.create(mdir)
writeBin(as.raw(1:5), file.path(cdir, "gif_sync.gif")); writeBin(as.raw(9:12), file.path(cdir, "gif_sync.png"))
sync_gif_to_media("tools/gif_sync.R", mdir, cdir, Sys.time() - 60)
ok("cache-only script's GIF and PNG are copied to media",
   identical(readBin(file.path(mdir, "gif_sync.gif"), "raw", 10), as.raw(1:5)) && file.exists(file.path(mdir, "gif_sync.png")))
writeBin(as.raw(7:8), file.path(cdir, "gif_sync.gif"))
sync_gif_to_media("tools/gif_sync.R", mdir, cdir, Sys.time() - 60)
ok("re-rendered cache GIF overwrites the stale media copy", identical(readBin(file.path(mdir, "gif_sync.gif"), "raw", 10), as.raw(7:8)))
sync_gif_to_media("tools/gif_none.R", mdir, cdir, Sys.time() - 60)
ok("script with no cache output syncs nothing, no error", !file.exists(file.path(mdir, "gif_none.gif")))

# stale source (mtime older than the script's start) must not overwrite media
writeBin(as.raw(1:3), file.path(mdir, "gif_stale.gif")); writeBin(as.raw(50:60), file.path(cdir, "gif_stale.gif"))
Sys.setFileTime(file.path(cdir, "gif_stale.gif"), Sys.time() - 3600)
sync_gif_to_media("tools/gif_stale.R", mdir, cdir, Sys.time() - 60)
ok("stale cache source does not overwrite media", identical(readBin(file.path(mdir, "gif_stale.gif"), "raw", 20), as.raw(1:3)))

# season signal = landing_digest.json season_state
warned <- character(0)
quiet <- function(expr) withCallingHandlers(expr, message = function(m) { warned <<- c(warned, conditionMessage(m)); invokeRestart("muffleMessage") })
res <- quiet(mlb_gif_in_season(Sys.time(), file.path(tmp, "no_such_digest.json")))
ok("missing landing_digest.json -> FALSE", identical(res, FALSE))
ok("missing landing_digest.json logs season-state-unknown warning", any(grepl("season state unknown", warned)))
dg <- file.path(tmp, "digest.json")
for (case in list(list("regular", TRUE), list("postseason", TRUE), list("preseason", FALSE), list("offseason", FALSE))) {
  writeLines(jsonlite::toJSON(list(season_state = case[[1]]), auto_unbox = TRUE), dg)
  ok(sprintf("season_state %s -> %s", case[[1]], case[[2]]), identical(mlb_gif_in_season(Sys.time(), dg), case[[2]]))
}
writeLines("{not json", dg); warned <- character(0)
ok("unreadable digest -> FALSE with warning", identical(quiet(mlb_gif_in_season(Sys.time(), dg)), FALSE) && any(grepl("season state unknown", warned)))
writeLines('{"slate_date": "2026-11-20"}', dg); warned <- character(0)
ok("digest without season_state -> FALSE with warning", identical(quiet(mlb_gif_in_season(Sys.time(), dg)), FALSE) && any(grepl("season state unknown", warned)))

# Scripts are pinned to season 2026: a later MLB_CURRENT_SEASON skips (never re-stamps 2026 data).
unlink(status)
pin <- run_render_weekly_gifs(media, scripts = good, in_season = TRUE, now = now, status_path = status, current_season = 2027L)
ok("MLB_CURRENT_SEASON past the scripts' pinned season -> skipped",
   identical(pin$skipped_reason, "scripts_pinned_to_other_season") && length(pin$rendered) == 0L)
Sys.setenv(FO_FORCE_GIF_RENDER = "1")
pinf <- run_render_weekly_gifs(media, scripts = good, in_season = TRUE, now = now, status_path = status, current_season = 2027L)
Sys.unsetenv("FO_FORCE_GIF_RENDER")
ok("FO_FORCE_GIF_RENDER=1 overrides the season pin", identical(pinf$rendered, basename(good)))

sched <- list_gif_scripts()
ok("schedule lists tools/gif_*.R scripts", length(sched) > 0L && all(grepl("^tools/gif_.*\\.R$", sched)))
ok("excluded scripts are not scheduled", !any(basename(sched) %in% names(GIF_RENDER_EXCLUDED)))
ok("every exclusion names a reason", all(nzchar(GIF_RENDER_EXCLUDED)))
ok("payroll bubble (hand-typed payrolls, imputed WAR) is excluded", "gif_payroll_efficiency_bubble.R" %in% names(GIF_RENDER_EXCLUDED))
ok("trophy lift (random confetti) is excluded", "gif_trophy_lift_champions.R" %in% names(GIF_RENDER_EXCLUDED))
ok("all 21 gif scripts are either scheduled or excluded with a reason",
   length(list.files("tools", pattern = "^gif_.*[.]R$")) == length(sched) + length(GIF_RENDER_EXCLUDED))

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All render_weekly_gifs tests passed\n")
