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
# The real builder map is checked below; the fake-script tests run with no builders.
REAL_BUILDERS <- GIF_HISTORY_BUILDERS
GIF_HISTORY_BUILDERS <- list()

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

# --- history builders (prerequisites) ---
order_file <- file.path(tmp, "order.txt")
append_line <- function(tag) sprintf('cat("%s\n", file = "%s", append = TRUE)', tag, gsub("\\\\", "/", order_file))
b_ok <- file.path(tmp, "build_ok.R"); writeLines(append_line("builder"), b_ok)
b_bad <- file.path(tmp, "build_bad.R"); writeLines("stop('CACHE_PBP not found')", b_bad)
b_hang <- file.path(tmp, "build_hang.R"); writeLines("Sys.sleep(120)", b_hang)
dep <- file.path(tmp, "gif_dep.R"); writeLines(append_line("dep"), dep)
indep <- file.path(tmp, "gif_indep.R"); writeLines(append_line("indep"), indep)
bmap <- function(b) setNames(list(basename(dep)), b)
Sys.setenv(FO_FORCE_GIF_RENDER = "1")
unlink(order_file)
r1 <- run_render_weekly_gifs(media, scripts = c(dep, indep), in_season = TRUE, now = now,
                             status_path = file.path(tmp, "sb1.json"), builders = bmap(b_ok))
ok("builder runs before its dependent GIF",
   identical(readLines(order_file), c("builder", "dep", "indep")) &&
   identical(r1$rendered, basename(c(dep, indep))) && length(r1$failed) == 0L)
unlink(order_file)
oc <- file.path(tmp, "outcome_b.json")
r2 <- run_render_weekly_gifs(media, scripts = c(dep, indep), in_season = TRUE, now = now,
                             status_path = file.path(tmp, "sb2.json"), outcome_path = oc, builders = bmap(b_bad))
ok("failing builder: dependent marked failed and not run, other GIF renders",
   identical(r2$failed, basename(dep)) && identical(r2$rendered, basename(indep)) &&
   identical(readLines(order_file), "indep"))
ok("failing builder: dependent is in the outcome's failed list",
   basename(dep) %in% jsonlite::fromJSON(oc)$failed)
unlink(order_file)
t0 <- Sys.time()
r3 <- run_render_weekly_gifs(media, scripts = c(dep, indep), in_season = TRUE, now = now,
                             status_path = file.path(tmp, "sb3.json"), builders = bmap(b_hang), timeout_sec = 5)
el3 <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
ok("hung builder is killed with exit 124 (timeout)", identical(run_gif_script(b_hang, tempfile(), 3), 124L))
ok("hung builder: dependent failed, other GIF renders, run bounded",
   identical(r3$failed, basename(dep)) && identical(r3$rendered, basename(indep)) && el3 < 60)
Sys.unsetenv("FO_FORCE_GIF_RENDER")
unlink(order_file)
sk <- run_render_weekly_gifs(media, scripts = c(dep, indep), in_season = FALSE, now = now,
                             status_path = file.path(tmp, "sb4.json"), builders = bmap(b_ok))
ok("builders do not run when the stage skips (offseason)",
   identical(sk$skipped_reason, "offseason") && !file.exists(order_file))
writeLines('{"last_success_at":"2026-11-21T12:00:00Z"}', file.path(tmp, "sb5.json"))
nd5 <- run_render_weekly_gifs(media, scripts = c(dep, indep), in_season = TRUE, now = now + 86400,
                              status_path = file.path(tmp, "sb5.json"), builders = bmap(b_ok))
ok("builders do not run when the stage skips (not due)",
   identical(nd5$skipped_reason, "not_due") && !file.exists(order_file))
ok("turnover history builder is a prerequisite of the race GIF",
   "gif_turnover_margin_race.R" %in% REAL_BUILDERS[["tools/turnover_margin_history.R"]] &&
   file.exists("tools/turnover_margin_history.R"))
ok("race GIF is no longer excluded", !"gif_turnover_margin_race.R" %in% names(GIF_RENDER_EXCLUDED))
po_gifs <- c("gif_playoff_odds_heatmap.R", "gif_playoff_prob_bump.R")
ok("playoff-odds backfill is a prerequisite of both playoff GIFs",
   setequal(REAL_BUILDERS[["tools/playoff_odds_history_backfill.R"]], po_gifs) &&
   file.exists("tools/playoff_odds_history_backfill.R"))
ok("playoff GIFs are no longer excluded", !any(po_gifs %in% names(GIF_RENDER_EXCLUDED)))
ok("playoff-odds backfill uses its config.R timeout",
   identical(GIF_HISTORY_BUILDER_TIMEOUTS[["tools/playoff_odds_history_backfill.R"]], PLAYOFF_ODDS_HISTORY_TIMEOUT_SEC))
# A failed backfill marks BOTH dependents failed (outcome file) and runs neither.
dep2 <- file.path(tmp, "gif_dep2.R"); writeLines(append_line("dep2"), dep2)
Sys.setenv(FO_FORCE_GIF_RENDER = "1")
unlink(order_file)
oc6 <- file.path(tmp, "outcome_b6.json")
r6 <- run_render_weekly_gifs(media, scripts = c(dep, dep2, indep), in_season = TRUE, now = now,
                             status_path = file.path(tmp, "sb6.json"), outcome_path = oc6,
                             builders = setNames(list(basename(c(dep, dep2))), b_bad))
Sys.unsetenv("FO_FORCE_GIF_RENDER")
ok("failed builder with two dependents: both failed in the outcome, neither ran",
   setequal(jsonlite::fromJSON(oc6)$failed, basename(c(dep, dep2))) &&
   identical(r6$rendered, basename(indep)) && identical(readLines(order_file), "indep"))

sched <- list_gif_scripts()
ok("schedule lists tools/gif_*.R scripts", length(sched) > 0L && all(grepl("^tools/gif_.*\\.R$", sched)))
ok("excluded scripts are not scheduled", !any(basename(sched) %in% names(GIF_RENDER_EXCLUDED)))
ok("every exclusion names a reason", length(GIF_RENDER_EXCLUDED) == 0L || all(nzchar(GIF_RENDER_EXCLUDED)))

# --- exporter gap: a failed script's leftover cache GIF must not be re-dated by publishing ---
source("web_media_filter.R")
pub_cache <- file.path(tmp, "cache"); dir.create(pub_cache)
pub_dir <- file.path(tmp, "published"); dir.create(pub_dir)
outcome <- file.path(tmp, "outcome.json")
old_render <- Sys.time() - 20 * 86400
leftover <- file.path(pub_cache, "gif_bad.gif")          # left by an earlier run; gif_bad.R fails now
writeBin(as.raw(1:10), leftover); Sys.setFileTime(leftover, old_render)
fresh <- file.path(pub_cache, "gif_good.gif")
writeBin(as.raw(11:20), fresh)
empty_media <- file.path(tmp, "empty_media"); dir.create(empty_media)   # no GIFs, no status -> due
run_render_weekly_gifs(empty_media, scripts = c(good, bad), in_season = TRUE, now = Sys.time() - 1,
                       status_path = file.path(tmp, "st2.json"), outcome_path = outcome)
publish <- function(f) {   # same rule as export_web_datasets.R
  dec <- gif_cache_copy_ok(f, file.path(pub_cache, f), outcome)
  if (dec$copy) file.copy(file.path(pub_cache, f), file.path(pub_dir, f), overwrite = TRUE, copy.date = TRUE)
  dec$copy
}
ok("failed script's leftover cache GIF is not published", !publish("gif_bad.gif") && !file.exists(file.path(pub_dir, "gif_bad.gif")))
ok("fresh GIF from a script that exited 0 is published", publish("gif_good.gif"))
ok("published mtime is the cache render time, not the copy time",
   abs(as.numeric(file.mtime(file.path(pub_dir, "gif_good.gif"))) - as.numeric(file.mtime(fresh))) < 2)
# Stage skipped (offseason): leftover may be copied but keeps its old render time.
run_render_weekly_gifs(media, scripts = c(good, bad), in_season = FALSE, now = Sys.time(),
                       status_path = file.path(tmp, "st3.json"), outcome_path = outcome)
ok("skipped stage: copy keeps the old cache render time",
   publish("gif_bad.gif") && file.mtime(file.path(pub_dir, "gif_bad.gif")) <= old_render + 2)
# Exit-0 script that did not rewrite its output: stale cache file is refused.
stale_ok <- file.path(pub_cache, "gif_good.gif"); Sys.setFileTime(stale_ok, old_render)
run_render_weekly_gifs(empty_media, scripts = good, in_season = TRUE, now = Sys.time() + 5,
                       status_path = file.path(tmp, "st4.json"), outcome_path = outcome)
ok("exit-0 script that left an old cache file is not copied", !gif_cache_copy_ok("gif_good.gif", stale_ok, outcome)$copy)

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All render_weekly_gifs tests passed\n")
