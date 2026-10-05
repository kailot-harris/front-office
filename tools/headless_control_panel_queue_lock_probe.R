# Headless browser QA for control_panel_app.R's multi-select queueing + cross-session run
# lock (GitHub issue #48, Slice 4 of #43), using shinytest2 (chromote-backed, drives real
# Chrome) -- same pattern as tools/headless_control_panel_probe.R (#46) and
# tools/headless_control_panel_staleness_probe.R (#47): CHROMOTE_CHROME + NOT_CRAN env vars,
# a throwaway wrapper app.R (shinytest2 always looks for a literal ./app.R in app_dir),
# AppDriver against the real Chrome install. Throwaway QA script for this ticket -- not part
# of run_full_pipeline.R's DAG, does not need to be production-grade.
#
# TWO-SESSION / CROSS-TAB MECHANICS: criterion 2 and 3 both need a SECOND (and third/fourth)
# independent Shiny session connected to the SAME running app process as the first, per the
# issue's own brief ("reuse two independent AppDriver instances against the same running app
# (same port)"). shinytest2's AppDriver always launches its OWN backing R/Shiny process on
# construction, so a second AppDriver$new() pointed at the same app_dir/port would try to
# spawn a SECOND competing process on an already-bound port, not attach a second browser tab
# to the first process. Instead, exactly ONE AppDriver (`app_a`) is used as the process
# owner for the whole probe (never stopped until the very end), and every additional
# "session"/"tab" is a raw chromote::ChromoteSession navigated directly at app_a$get_url()
# -- a second, fully independent websocket connection into the SAME already-running Shiny
# process, exactly matching the "second browser tab" scenario the issue describes. Those raw
# tabs are driven via Shiny's own client-side JS API (Shiny.setInputValue(), a DOM .click())
# rather than shinytest2's app_dir-relaunching helpers.
#
# Verifies, in order, the four success criteria from the issue #48 brief:
#   1 & 4. Queuing sync_rosters -> roster_bottom_up_engine -> data_health_probe (a real
#          dependency: roster_bottom_up_engine declares active_rosters_cache.rds, which
#          sync_rosters produces, as an input) runs them in that order, and
#          roster_bottom_up_engine is NOT falsely staleness-blocked even though
#          active_rosters_cache.rds is deliberately missing at queue-submission time (it is
#          temporarily renamed away before the run) -- because sync_rosters, queued ahead of
#          it, regenerates that exact file for real (a live ESPN API call) before
#          roster_bottom_up_engine's own staleness check runs.
#   2. While that queue (on app_a) is in flight, a second independent session's run control
#      is observed disabled; once the queue finishes, that second session's run control
#      becomes enabled again.
#   3. A fresh session starts its own single-stage "queue", is observed to hold the lock
#      (a third session sees run_btn disabled), then that session is killed outright
#      (chromote tab closed, simulating a closed browser tab) while its stage is still
#      running -- a fourth, brand-new session's run control is confirmed to become usable
#      again within a bounded wait, rather than staying stuck disabled forever.
#
# USAGE: Rscript.exe tools/headless_control_panel_queue_lock_probe.R
# NOTE: this probe makes REAL network calls (ESPN rosters) and REAL writes to
# cache/active_rosters_cache.rds and cache/projected_wnba_standings.rds as part of exercising
# a genuine cross-stage dependency -- both are backed up before the probe runs and restored
# afterward (on.exit), same discipline as headless_control_panel_staleness_probe.R's cache
# rename-and-restore.

Sys.setenv(CHROMOTE_CHROME = Sys.getenv(
  "CHROMOTE_CHROME",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"
))
if (Sys.getenv("NOT_CRAN") == "") Sys.setenv(NOT_CRAN = "true")

script_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
project_dir <- if (!is.na(script_dir)) normalizePath(file.path(script_dir, "..")) else getwd()
setwd(project_dir)

suppressMessages({
  library(shinytest2)
  library(chromote)
})

source("config.R")
source("pipeline_stages.R")

pass <- function(msg) cat(sprintf("[PASS] %s\n", msg))
fail <- function(msg) { cat(sprintf("[FAIL] %s\n", msg)); failures <<- c(failures, msg) }
failures <- character(0)

# ------------------------------------------------------------------------------------------
# Raw chromote-tab helpers (see header comment for why these exist instead of a second
# AppDriver).
# ------------------------------------------------------------------------------------------
new_tab <- function(url) {
  cs <- ChromoteSession$new()
  cs$Page$navigate(url)
  cs
}

js_eval <- function(cs, expr) {
  res <- cs$Runtime$evaluate(expr, returnByValue = TRUE, awaitPromise = FALSE)
  res$result$value
}

wait_for_shiny_ready <- function(cs, timeout = 30) {
  deadline <- Sys.time() + timeout
  repeat {
    ready <- tryCatch(
      isTRUE(js_eval(cs, "typeof Shiny !== 'undefined' && !!document.getElementById('run_btn');")),
      error = function(e) FALSE
    )
    if (ready) return(invisible(TRUE))
    if (Sys.time() > deadline) stop("Shiny app did not become ready in a new tab within timeout.")
    Sys.sleep(0.3)
  }
}

run_btn_disabled <- function(cs) isTRUE(js_eval(cs, "document.getElementById('run_btn').disabled;"))

set_stage_queue_js <- function(cs, ids) {
  arr_js <- paste0("[", paste(sprintf("'%s'", ids), collapse = ","), "]")
  js_eval(cs, sprintf("Shiny.setInputValue('stage_id', %s, {priority: 'event'});", arr_js))
}

click_run_js <- function(cs) js_eval(cs, "document.getElementById('run_btn').click(); true;")

status_text_js   <- function(cs) js_eval(cs, "document.getElementById('status_ui').innerText;")
output_text_js   <- function(cs) js_eval(cs, "document.getElementById('output_log').innerText;")

wait_until <- function(cond_fn, timeout, interval = 0.5, label = "condition") {
  deadline <- Sys.time() + timeout
  repeat {
    if (isTRUE(cond_fn())) return(TRUE)
    if (Sys.time() > deadline) return(FALSE)
    Sys.sleep(interval)
  }
}

# ------------------------------------------------------------------------------------------
# Cache backup/restore (sync_rosters + roster_bottom_up_engine both really run and really
# write).
# ------------------------------------------------------------------------------------------
roster_cache        <- file.path(CACHE_DIR, "active_rosters_cache.rds")
roster_cache_backup <- file.path(CACHE_DIR, "active_rosters_cache.rds.queue_probe_backup")
standings_cache        <- "cache/projected_wnba_standings.rds"
standings_cache_backup <- "cache/projected_wnba_standings.rds.queue_probe_backup"

restore_caches <- function() {
  if (file.exists(roster_cache_backup)) {
    if (file.exists(roster_cache)) unlink(roster_cache)
    file.rename(roster_cache_backup, roster_cache)
    cat("Restored original active_rosters_cache.rds.\n")
  }
  if (file.exists(standings_cache_backup)) {
    if (file.exists(standings_cache)) unlink(standings_cache)
    file.rename(standings_cache_backup, standings_cache)
    cat("Restored original projected_wnba_standings.rds.\n")
  }
}

stopifnot(file.exists(roster_cache))
file.copy(roster_cache, roster_cache_backup, overwrite = TRUE)
if (file.exists(standings_cache)) file.copy(standings_cache, standings_cache_backup, overwrite = TRUE)

# ------------------------------------------------------------------------------------------
# Launch the one backing Shiny process (app_a is both the process owner AND session 1).
# ------------------------------------------------------------------------------------------
wrapper_dir <- file.path(tempdir(), "control_panel_queue_lock_probe_app")
dir.create(wrapper_dir, showWarnings = FALSE)
writeLines(
  sprintf('setwd(%s)\nsource("control_panel_app.R")$value', shQuote(project_dir, type = "cmd")),
  file.path(wrapper_dir, "app.R")
)

app_a <- AppDriver$new(
  app_dir = wrapper_dir, name = "wnba-control-panel-queue-lock-probe",
  height = 900, width = 1400, load_timeout = 60000, timeout = 60000,
  shiny_args = list(port = 7660)
)
app_a$wait_for_idle(duration = 500, timeout = 60000)
base_url <- app_a$get_url()
cat(sprintf("Backing Shiny process URL: %s\n", base_url))

on.exit({
  restore_caches()
  tryCatch(app_a$stop(), error = function(e) NULL)
}, add = TRUE)

# ------------------------------------------------------------------------------------------
# Criterion 1 & 4: real cross-stage dependency, queued in order, no false block.
# ------------------------------------------------------------------------------------------
# Remove active_rosters_cache.rds so it is genuinely MISSING at queue-submission time --
# sync_rosters (queued first) will recreate it for real before roster_bottom_up_engine's
# turn comes.
unlink(roster_cache)
cat("Removed active_rosters_cache.rds (will be regenerated mid-queue by sync_rosters).\n")

queue_ids <- c("sync_rosters", "roster_bottom_up_engine", "data_health_probe")
app_a$set_inputs(stage_id = queue_ids)
app_a$wait_for_idle(duration = 500, timeout = 30000)

preview_text <- app_a$get_text("#staleness_ui")
cat(sprintf("Queue preview (active_rosters_cache.rds missing): %s\n", preview_text))
if (grepl("roster_bottom_up_engine", preview_text) && grepl("BLOCKED", preview_text)) {
  pass("Sanity check: queue preview correctly shows roster_bottom_up_engine blocked BEFORE the run starts (input genuinely missing at submission time).")
} else {
  fail(sprintf("Sanity check failed: expected a pre-run BLOCKED preview for roster_bottom_up_engine, got: %s", preview_text))
}

# ------------------------------------------------------------------------------------------
# Criterion 2 (first half): open a second, independent session BEFORE triggering the queue,
# while the backing process is still idle, and confirm IT observes the run control going
# disabled once app_a's queue starts.
#
# Opening tab_b used to happen AFTER the click below, which deadlocked: once sync_rosters
# (the first queued stage) starts its own real, synchronous, non-yielding ESPN API call, the
# single backing R process cannot service ANY new session's initial page load/websocket
# handshake until the next later::later(..., delay = 0) yield point between queued stages --
# which may be minutes away for a brand-new, never-before-connected tab trying to complete
# Shiny's own startup handshake from scratch. A session that is ALREADY connected and idle,
# by contrast, just needs its existing reactive bindings to receive a push once the server
# frees up -- a much smaller ask that this architecture can actually satisfy. So tab_b must
# establish its session FIRST, before the queue starts, exactly like a real second browser
# tab a user had already open before clicking Run Queue in the first tab.
# ------------------------------------------------------------------------------------------
tab_b <- new_tab(base_url)
wait_for_shiny_ready(tab_b)

disabled_before_queue <- isTRUE(run_btn_disabled(tab_b))
cat(sprintf("Session 2 (independent tab, opened before the queue starts) run_btn disabled before queue: %s\n", disabled_before_queue))

app_a$click("run_btn", wait_ = FALSE)
cat("Clicked Run Queue on app_a (session 1) -- sync_rosters / roster_bottom_up_engine / data_health_probe.\n")

disabled_mid_queue <- wait_until(function() run_btn_disabled(tab_b), timeout = 20)
cat(sprintf("Session 2 (independent tab) observed run_btn disabled mid-queue: %s\n", disabled_mid_queue))
if (isTRUE(disabled_mid_queue)) {
  pass("Criterion 2 (part A): a second independent session sees the run control disabled while app_a's queue is in progress.")
} else {
  fail("Criterion 2 (part A): a second independent session did NOT see the run control disabled while app_a's queue was in progress.")
}

# ------------------------------------------------------------------------------------------
# Wait for the queue to actually finish (generous timeout -- real network + real engine
# runs), then verify criterion 1 & 4 and criterion 2's second half.
# ------------------------------------------------------------------------------------------
# status_ui is per-SESSION state (the `result`/`rv` reactiveVals it reads live inside this
# session's own server() closure) -- tab_b never ran anything itself, so its OWN status_ui
# will read "Idle." for the entire test regardless of what app_a's queue is doing. The queue
# progress/completion must be read from app_a (the session that actually clicked Run Queue),
# not tab_b. tab_b is only ever used to observe the shared cross-session LOCK (run_btn's
# disabled state), never the per-session status text.
.last_diag <- ""
queue_done <- wait_until(function() {
  cur <- tryCatch(app_a$get_text("#status_ui"), error = function(e) "")
  if (!identical(cur, .last_diag)) {
    cat(sprintf("[diag %s] app_a status_ui: %s\n", format(Sys.time(), "%H:%M:%S"), cur))
    .last_diag <<- cur
  }
  grepl("Queue complete", cur)
}, timeout = 90, interval = 1)

if (!isTRUE(queue_done)) {
  fail("Queue (sync_rosters / roster_bottom_up_engine / data_health_probe) did not report 'Queue complete' within the 240s timeout.")
} else {
  final_status <- app_a$get_text("#status_ui")
  final_output <- app_a$get_text("#output_log")
  cat(sprintf("Final status_ui text:\n%s\n", final_status))

  order_pos_sync    <- regexpr("sync_rosters", final_output)
  order_pos_roster  <- regexpr("roster_bottom_up_engine", final_output)
  order_pos_health  <- regexpr("data_health_probe", final_output)
  ran_in_order <- order_pos_sync > 0 && order_pos_roster > order_pos_sync &&
    order_pos_health > order_pos_roster

  roster_skipped_blocked <- grepl("roster_bottom_up_engine -- SKIPPED \\(blocked", final_status)

  if (ran_in_order) {
    pass("Criterion 1: the three queued stages executed in the chosen order (sync_rosters -> roster_bottom_up_engine -> data_health_probe).")
  } else {
    fail(sprintf("Criterion 1: queued stages did not execute in the expected order. Captured output:\n%s", final_output))
  }

  if (!roster_skipped_blocked) {
    pass("Criterion 4: roster_bottom_up_engine was NOT falsely staleness-blocked -- sync_rosters (queued ahead of it) regenerated active_rosters_cache.rds before roster_bottom_up_engine's own start-time staleness check ran.")
  } else {
    fail(sprintf("Criterion 4: roster_bottom_up_engine was skipped as blocked despite sync_rosters running ahead of it. Status: %s", final_status))
  }

  sync_ok <- grepl("sync_rosters -- PASS", final_status)
  if (sync_ok) {
    pass("Sanity check: sync_rosters itself reported PASS (really regenerated active_rosters_cache.rds via the live ESPN API).")
  } else {
    fail(sprintf("Sanity check: sync_rosters did not report PASS -- roster_bottom_up_engine's non-blocked status may not be meaningful. Status: %s", final_status))
  }

  cat(sprintf("Lock held after queue completion (should be FALSE): %s\n", pipeline_lock_is_held_probe <- {
    # Not calling the app's internal pipeline_lock_is_held() directly (it lives in the
    # server process's env, not this probe's) -- instead infer via the run control itself.
    run_btn_disabled(tab_b)
  }))

  # Criterion 2 (second half): the second session's run control re-enables once the queue
  # (started by app_a) finishes.
  reenabled <- wait_until(function() !run_btn_disabled(tab_b), timeout = 10)
  if (isTRUE(reenabled)) {
    pass("Criterion 2 (part B): the second independent session's run control re-enabled once app_a's queue finished.")
  } else {
    fail("Criterion 2 (part B): the second independent session's run control did NOT re-enable after app_a's queue finished.")
  }
}

# ------------------------------------------------------------------------------------------
# Criterion 3: a fresh session (tab_c) starts its own run, a different fresh session
# (tab_d, opened now) confirms the lock is held, tab_c is then KILLED mid-run (closed tab,
# simulating a closed browser), and tab_d's run control is confirmed to become usable again
# within a bounded wait rather than staying stuck disabled forever.
#
# sync_rosters (several sequential live HTTP calls) is used again here deliberately: it is a
# synchronous, foreign (non-R-event-loop-yielding) blocking call for its own full duration,
# so killing tab_c WHILE it is running is a genuine test of "the lock releases once this
# session's current stage finishes and Shiny notices the disconnect" -- not an easier
# between-stages case. The documented limitation (see control_panel_app.R's own comment
# above .PIPELINE_RUN_LOCK) is that release cannot happen any sooner than that current
# stage's own completion; the wait bound below is set generously past one sync_rosters run
# to accommodate that honestly, rather than asserting an unrealistic instant release.
# ------------------------------------------------------------------------------------------
tab_c <- new_tab(base_url)
wait_for_shiny_ready(tab_c)
tab_d <- new_tab(base_url)
wait_for_shiny_ready(tab_d)

lock_free_before_c <- wait_until(function() !run_btn_disabled(tab_d), timeout = 15)
if (!isTRUE(lock_free_before_c)) {
  fail("Criterion 3 setup: lock was not free before starting the kill-test run -- cannot proceed meaningfully.")
}

set_stage_queue_js(tab_c, c("sync_rosters"))
Sys.sleep(0.3)
click_run_js(tab_c)
cat("Clicked Run Queue on tab_c (session 3, to be killed) -- single-stage queue: sync_rosters.\n")

held_by_c <- wait_until(function() run_btn_disabled(tab_d), timeout = 15)
cat(sprintf("Session 4 (tab_d) observes run control disabled after session 3 (tab_c) started its run: %s\n", held_by_c))
if (isTRUE(held_by_c)) {
  pass("Criterion 3 (setup): a third session's run acquires the lock, observed as disabled by a fourth, independent session.")
} else {
  fail("Criterion 3 (setup): the lock was not observed held after tab_c started its run -- cannot test the kill/release path.")
}

cat("Killing tab_c (closing the chromote tab) while its stage is still running, simulating a closed browser tab...\n")
tryCatch(tab_c$close(), error = function(e) cat(sprintf("tab_c$close() raised (expected if already torn down): %s\n", conditionMessage(e))))

released <- wait_until(function() !run_btn_disabled(tab_d), timeout = 90, interval = 1)
cat(sprintf("Session 4 (tab_d) observes run control re-enabled after killing session 3: %s\n", released))
if (isTRUE(released)) {
  pass("Criterion 3: killing a session mid-queue released the cross-session lock -- a fresh/different session's run control became usable again (within a 90s bound covering one full sync_rosters run), not stuck disabled forever.")
} else {
  fail("Criterion 3: the lock remained held (run control still disabled) in a fresh session well after killing the session that held it.")
}

# Final sanity: a fresh session really can run again post-recovery.
if (isTRUE(released)) {
  set_stage_queue_js(tab_d, c("data_health_probe"))
  Sys.sleep(0.3)
  click_run_js(tab_d)
  final_recovery_ok <- wait_until(function() grepl("Queue complete", status_text_js(tab_d)), timeout = 30)
  if (isTRUE(final_recovery_ok) && grepl("data_health_probe -- PASS", status_text_js(tab_d))) {
    pass("Criterion 3 (confirmation): the recovered session successfully ran a brand-new queue end to end.")
  } else {
    fail("Criterion 3 (confirmation): the recovered session's own run did not complete as expected.")
  }
}

tryCatch(tab_b$close(), error = function(e) NULL)
tryCatch(tab_c$close(), error = function(e) NULL)
tryCatch(tab_d$close(), error = function(e) NULL)

cat(sprintf("\n%d failure(s) out of this probe run.\n", length(failures)))
if (length(failures) > 0) {
  cat("Failures:\n")
  for (f in failures) cat(sprintf(" - %s\n", f))
  quit(status = 1)
} else {
  cat("ALL CRITERIA PASSED.\n")
  quit(status = 0)
}
