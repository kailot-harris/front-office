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

# missing matchups_slates.json: FALSE (offseason) plus a warning
warned <- FALSE
res <- withCallingHandlers(wnba_gif_in_season(Sys.time(), file.path(tmp, "no_such_matchups.json")),
  message = function(m) { if (grepl("season state unknown", conditionMessage(m))) warned <<- TRUE; invokeRestart("muffleMessage") })
ok("missing matchups_slates.json -> FALSE", identical(res, FALSE))
ok("missing matchups_slates.json logs season-state-unknown warning", warned)

# season state from real digest logic: games Jun-Sep, slate inside -> in season; after -> offseason.
mp <- file.path(tmp, "matchups.json")
jsonlite::write_json(list(matchups = data.frame(
  game_id = c("1", "2"), game_date = c("2026-06-01", "2026-09-01"), season_type = c("regular", "regular"),
  home_team = c("A", "B"), away_team = c("B", "A"), is_completed = c(TRUE, TRUE), stringsAsFactors = FALSE)),
  mp, auto_unbox = TRUE)
ok("slate date inside the schedule -> in season",
   identical(wnba_gif_in_season(as.POSIXct("2026-07-15 16:00:00", tz = "UTC"), mp), TRUE))
ok("slate date after the last game -> offseason",
   identical(wnba_gif_in_season(as.POSIXct("2026-11-21 16:00:00", tz = "UTC"), mp), FALSE))

sched <- list_gif_scripts()
ok("schedule lists tools/gif_*.R scripts", length(sched) > 0L && all(grepl("^tools/gif_.*\\.R$", sched)))
ok("excluded scripts are not scheduled", !any(basename(sched) %in% names(GIF_RENDER_EXCLUDED)))
ok("every exclusion names a reason", all(nzchar(GIF_RENDER_EXCLUDED)))
ok("gif_rapm_leaders_2026 (literal 2026 season) is excluded", "gif_rapm_leaders_2026.R" %in% names(GIF_RENDER_EXCLUDED))
ok("gif_finals_closing_stretch (single 2026 game, not indexed) is excluded", "gif_finals_closing_stretch.R" %in% names(GIF_RENDER_EXCLUDED))

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All render_weekly_gifs tests passed\n")
