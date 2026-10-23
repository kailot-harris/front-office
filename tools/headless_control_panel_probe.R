# STALE SINCE ISSUE #54: control_panel_app.R now requires a real login (mod_login_ui/
# mod_login_server, issue #53) before any of the stage-picker/run_btn/etc. elements this
# script drives exist in the DOM at all -- this script predates that and does not log in
# first, so it will fail before reaching its own checks until updated to create a test
# account and log in (see tools/headless_login_module_probe.R's set_module_input() pattern)
# before interacting with anything below. Not updated here because shinytest2::AppDriver was
# failing system-wide in this environment at the time of #54's verification (confirmed
# unrelated to this change), so an update to this script could not itself be live-tested.

# Headless browser QA for control_panel_app.R (GitHub issue #46), using shinytest2
# (chromote-backed, drives real Chrome) -- following the exact same pattern as
# tools/headless_dashboard_probe.R (NOT_CRAN env var, CHROMOTE_CHROME, AppDriver against the
# real Chrome install). Throwaway QA script for this ticket -- not part of run_full_pipeline.R's
# DAG, does not need to be production-grade.
#
# Verifies, in order, the four success criteria from the issue #46 brief:
#   1. The app starts and the stage dropdown is populated with length(PIPELINE_STAGES) entries.
#   2. Running the cheap/side-effect-free "data_health_probe" stage shows a PASS result with
#      non-empty captured output.
#   3. Renaming active_rosters_cache.rds (an input of the "roster_bottom_up_engine" stage) for
#      the duration of one run causes that stage to FAIL in the UI without crashing the app
#      process, then the cache is restored.
#   4. The run control is disabled immediately after the click and re-enabled once the result
#      renders (checked across both the pass run and the fail run).
#
# USAGE: Rscript.exe tools/headless_control_panel_probe.R

Sys.setenv(CHROMOTE_CHROME = Sys.getenv(
  "CHROMOTE_CHROME",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"
))
if (Sys.getenv("NOT_CRAN") == "") Sys.setenv(NOT_CRAN = "true")

script_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
project_dir <- if (!is.na(script_dir)) normalizePath(file.path(script_dir, "..")) else getwd()
setwd(project_dir)

suppressMessages(library(shinytest2))

source("config.R")
source("pipeline_stages.R")

pass <- function(msg) cat(sprintf("[PASS] %s\n", msg))
fail <- function(msg) { cat(sprintf("[FAIL] %s\n", msg)); failures <<- c(failures, msg) }
failures <- character(0)

expected_stage_count <- length(PIPELINE_STAGES)
roster_cache <- file.path(CACHE_DIR, "active_rosters_cache.rds")
roster_cache_backup <- file.path(CACHE_DIR, "active_rosters_cache.rds.probe_backup")

# shinytest2's AppDriver always looks for a literal ./app.R inside app_dir -- pointing it at
# project_dir launches the EXISTING app.R (the shinydashboard viewer), not control_panel_app.R,
# silently (no error, just the wrong app with no #stage_id element at all, which is what
# produced the "0 options" / "no input binding" failures below). Point it at a throwaway
# wrapper dir instead, matching the pattern used for the other app probes in this directory.
wrapper_dir <- file.path(tempdir(), "control_panel_probe_app")
dir.create(wrapper_dir, showWarnings = FALSE)
writeLines(
  sprintf('setwd(%s)\nsource("control_panel_app.R")$value', shQuote(project_dir, type = "cmd")),
  file.path(wrapper_dir, "app.R")
)

app <- AppDriver$new(
  app_dir = wrapper_dir, name = "wnba-control-panel-probe",
  height = 900, width = 1400, load_timeout = 60000, timeout = 60000,
  shiny_args = list(port = 7657)
)
# AppDriver$new() returning only guarantees the Shiny session object exists, not that the
# client-side DOM (e.g. the stage dropdown's <option> tags) has finished rendering -- a flat
# Sys.sleep(2) was not reliably enough margin on this machine. wait_for_idle() blocks until the
# browser's reactive flush queue is actually empty.
app$wait_for_idle(duration = 500, timeout = 60000)

# ------------------------------------------------------------------------------------------
# Criterion 1: stage dropdown populated with the expected count.
# ------------------------------------------------------------------------------------------
# selectInput() wraps the <select> in selectize.js by default, which virtualizes the dropdown
# -- the underlying <select> only ever keeps the currently-SELECTED <option> as a real DOM
# node, so counting `#stage_id option` undercounts (always 1) regardless of how many choices
# were actually registered. Query selectize's own in-memory options map instead.
n_options <- app$get_js('Object.keys($("#stage_id")[0].selectize.options).length;')
cat(sprintf("Stage dropdown option count: %s (expected %s)\n", n_options, expected_stage_count))
if (identical(as.numeric(n_options), as.numeric(expected_stage_count))) {
  pass(sprintf("Criterion 1: dropdown has %s options matching length(PIPELINE_STAGES).", n_options))
} else {
  fail(sprintf("Criterion 1: dropdown has %s options, expected %s.", n_options, expected_stage_count))
}

# ------------------------------------------------------------------------------------------
# Criterion 2 + 4 (pass-run half): run data_health_probe (cheap, side-effect-free) and check
# the button is disabled immediately, then re-enabled with a PASS + non-empty output.
# ------------------------------------------------------------------------------------------
app$set_inputs(stage_id = "data_health_probe")
# click()'s default wait_ = TRUE blocks until the server round-trip (the whole stage run) is
# done -- by the time control returns, a fast stage like data_health_probe has already finished
# and the server's own shinyjs::enable() has already re-enabled the button, so checking
# "disabled" after a waiting click can never observe the disabled state at all. wait_ = FALSE
# returns right after the click event fires, before the server has processed it.
app$click("run_btn", wait_ = FALSE)

disabled_immediately <- app$get_js('document.getElementById("run_btn").disabled;')
cat(sprintf("run_btn.disabled immediately after click (data_health_probe): %s\n", disabled_immediately))
if (isTRUE(disabled_immediately)) {
  pass("Criterion 4 (disable-on-click): run_btn was disabled immediately after the click.")
} else {
  fail("Criterion 4 (disable-on-click): run_btn was NOT disabled immediately after the click.")
}

app$wait_for_idle(duration = 1000, timeout = 60000)

status_text <- app$get_text("#status_ui")
output_text <- app$get_text("#output_log")
cat(sprintf("Status after data_health_probe run: %s\n", status_text))
cat(sprintf("Captured output length: %d chars\n", nchar(output_text)))

if (grepl("PASS", status_text) && nchar(trimws(output_text)) > 0 &&
    !identical(trimws(output_text), "(no output captured)")) {
  pass("Criterion 2: data_health_probe showed a PASS result with non-empty captured output.")
} else {
  fail(sprintf("Criterion 2: expected PASS + non-empty output, got status='%s' output_len=%d.",
               status_text, nchar(output_text)))
}

enabled_after <- app$get_js('document.getElementById("run_btn").disabled;')
cat(sprintf("run_btn.disabled after result appeared (data_health_probe): %s\n", enabled_after))
if (isFALSE(enabled_after)) {
  pass("Criterion 4 (re-enable-after-run): run_btn was re-enabled once the result appeared.")
} else {
  fail("Criterion 4 (re-enable-after-run): run_btn is still disabled after the result appeared.")
}

# ------------------------------------------------------------------------------------------
# Criterion 3 + 4 (fail-run half): rename active_rosters_cache.rds (a declared input of
# roster_bottom_up_engine per pipeline_stages.R) for the duration of one run, confirm the UI
# shows a failure (not a crash), confirm the app process is still alive/responsive afterward,
# then restore the cache file.
# ------------------------------------------------------------------------------------------
stopifnot(file.exists(roster_cache))
file.rename(roster_cache, roster_cache_backup)
cat(sprintf("Temporarily moved %s -> %s for the failure-injection run.\n", roster_cache, roster_cache_backup))

restore_cache <- function() {
  if (file.exists(roster_cache_backup) && !file.exists(roster_cache)) {
    file.rename(roster_cache_backup, roster_cache)
    cat("Restored active_rosters_cache.rds.\n")
  }
}
# Make sure the cache is restored even if an assertion below throws.
on.exit(restore_cache(), add = TRUE)

app$set_inputs(stage_id = "roster_bottom_up_engine")
app$click("run_btn", wait_ = FALSE)

disabled_immediately_2 <- app$get_js('document.getElementById("run_btn").disabled;')
cat(sprintf("run_btn.disabled immediately after click (roster_bottom_up_engine): %s\n", disabled_immediately_2))
if (isTRUE(disabled_immediately_2)) {
  pass("Criterion 4 (disable-on-click, fail run): run_btn was disabled immediately after the click.")
} else {
  fail("Criterion 4 (disable-on-click, fail run): run_btn was NOT disabled immediately after the click.")
}

app$wait_for_idle(duration = 1000, timeout = 60000)

status_text_2 <- app$get_text("#status_ui")
cat(sprintf("Status after roster_bottom_up_engine run (cache missing): %s\n", status_text_2))

if (grepl("FAIL", status_text_2)) {
  pass("Criterion 3: missing-input run surfaced a FAIL result in the UI, not a crash.")
} else {
  fail(sprintf("Criterion 3: expected a FAIL status, got '%s'.", status_text_2))
}

# App-alive check: issue another request (switch stage selection + re-render) and confirm the
# process is still responsive, not crashed/hung.
alive_check <- tryCatch({
  app$set_inputs(stage_id = "data_health_probe")
  app$get_js('1 + 1;')
}, error = function(e) NA)
cat(sprintf("Post-failure liveness check (1+1 via app$get_js): %s\n", alive_check))
if (identical(as.numeric(alive_check), 2)) {
  pass("Criterion 3 (process alive): app process remained responsive after the failing run.")
} else {
  fail("Criterion 3 (process alive): app process did not respond after the failing run.")
}

enabled_after_2 <- app$get_js('document.getElementById("run_btn").disabled;')
cat(sprintf("run_btn.disabled after result appeared (roster_bottom_up_engine): %s\n", enabled_after_2))
if (isFALSE(enabled_after_2)) {
  pass("Criterion 4 (re-enable-after-run, fail run): run_btn was re-enabled once the result appeared.")
} else {
  fail("Criterion 4 (re-enable-after-run, fail run): run_btn is still disabled after the result appeared.")
}

restore_cache()

app$stop()

cat(sprintf("\n%d failure(s) out of this probe run.\n", length(failures)))
if (length(failures) > 0) {
  cat("Failures:\n")
  for (f in failures) cat(sprintf(" - %s\n", f))
  quit(status = 1)
} else {
  cat("ALL CRITERIA PASSED.\n")
  quit(status = 0)
}
