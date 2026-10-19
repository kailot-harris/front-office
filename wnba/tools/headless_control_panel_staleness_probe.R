# STALE SINCE ISSUE #54: control_panel_app.R now requires a real login (mod_login_ui/
# mod_login_server, issue #53) before any of the stage-picker/run_btn/etc. elements this
# script drives exist in the DOM at all -- this script predates that and does not log in
# first, so it will fail before reaching its own checks until updated to create a test
# account and log in (see tools/headless_login_module_probe.R's set_module_input() pattern)
# before interacting with anything below. Not updated here because shinytest2::AppDriver was
# failing system-wide in this environment at the time of #54's verification (confirmed
# unrelated to this change), so an update to this script could not itself be live-tested.

# Headless browser QA for control_panel_app.R's staleness-check feature (GitHub issue #47,
# Slice 3 of #43), using shinytest2 (chromote-backed, drives real Chrome) -- same pattern as
# tools/headless_control_panel_probe.R (issue #46) and tools/headless_dashboard_probe.R
# (NOT_CRAN env var, CHROMOTE_CHROME, AppDriver against the real Chrome install, wrapper
# app.R since shinytest2 always looks for a literal ./app.R in app_dir). Throwaway QA script
# for this ticket -- not part of run_full_pipeline.R's DAG, does not need to be
# production-grade.
#
# Verifies, in order, the four success criteria from the issue #47 brief:
#   1. Selecting a stage with a missing declared input disables the run button and shows a
#      message naming which input is missing.
#   2. The per-stage "I know, run it anyway" override allows the run to proceed and actually
#      executes the stage (checked via the stage's own captured FAIL output, since the
#      underlying script still fails without its real input).
#   3. A stage with fully fresh/present inputs is never blocked, checked across 3 stages
#      spanning different DAG depths: sync_rosters (no inputs at all), player_metrics (one
#      real upstream input), and roster_bottom_up_engine (many real cross-stage inputs).
#   4. Switching the stage selection after a block (without running) correctly re-evaluates
#      staleness for the newly-selected stage -- no stale "blocked" state leaking onto an
#      unrelated, actually-fresh stage.
#
# USAGE: Rscript.exe tools/headless_control_panel_staleness_probe.R

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

# roster_bottom_up_engine's declared inputs include active_rosters_cache.rds (a real file we
# can safely rename away for the duration of one probe run and restore afterward).
roster_cache <- file.path(CACHE_DIR, "active_rosters_cache.rds")
roster_cache_backup <- file.path(CACHE_DIR, "active_rosters_cache.rds.staleness_probe_backup")

wrapper_dir <- file.path(tempdir(), "control_panel_staleness_probe_app")
dir.create(wrapper_dir, showWarnings = FALSE)
writeLines(
  sprintf('setwd(%s)\nsource("control_panel_app.R")$value', shQuote(project_dir, type = "cmd")),
  file.path(wrapper_dir, "app.R")
)

app <- AppDriver$new(
  app_dir = wrapper_dir, name = "wnba-control-panel-staleness-probe",
  height = 900, width = 1400, load_timeout = 60000, timeout = 60000,
  shiny_args = list(port = 7658)
)
app$wait_for_idle(duration = 500, timeout = 60000)

restore_cache <- function() {
  if (file.exists(roster_cache_backup) && !file.exists(roster_cache)) {
    file.rename(roster_cache_backup, roster_cache)
    cat("Restored active_rosters_cache.rds.\n")
  }
}
on.exit({ restore_cache(); app$stop() }, add = TRUE)

run_btn_disabled <- function() isTRUE(app$get_js('document.getElementById("run_btn").disabled;'))
staleness_text   <- function() app$get_text("#staleness_ui")

# ------------------------------------------------------------------------------------------
# Criterion 3 (checked FIRST, with every real input untouched): 3 stages spanning different
# DAG depths are never blocked.
# ------------------------------------------------------------------------------------------
fresh_stages <- c("sync_rosters", "player_metrics", "roster_bottom_up_engine")
for (sid in fresh_stages) {
  app$set_inputs(stage_id = sid)
  app$wait_for_idle(duration = 500, timeout = 60000)
  disabled <- run_btn_disabled()
  st_text  <- staleness_text()
  cat(sprintf("Stage '%s' (fresh inputs) -- run_btn disabled: %s, staleness panel: %s\n",
              sid, disabled, st_text))
  if (!disabled && grepl("Inputs OK", st_text)) {
    pass(sprintf("Criterion 3: stage '%s' with fresh/present inputs is not blocked.", sid))
  } else {
    fail(sprintf("Criterion 3: stage '%s' unexpectedly blocked (disabled=%s, panel='%s').",
                 sid, disabled, st_text))
  }
}

# ------------------------------------------------------------------------------------------
# Criterion 1: rename active_rosters_cache.rds (declared input of roster_bottom_up_engine),
# select that stage, confirm the run control is blocked and the message names the missing
# file.
# ------------------------------------------------------------------------------------------
stopifnot(file.exists(roster_cache))
file.rename(roster_cache, roster_cache_backup)
cat(sprintf("Temporarily moved %s -> %s.\n", roster_cache, roster_cache_backup))

# Force a re-select (via an unrelated stage first) so the staleness panel is guaranteed to
# recompute against the now-missing file, not a cached render from before the rename.
app$set_inputs(stage_id = "sync_rosters")
app$wait_for_idle(duration = 300, timeout = 60000)
app$set_inputs(stage_id = "roster_bottom_up_engine")
app$wait_for_idle(duration = 500, timeout = 60000)

disabled_missing <- run_btn_disabled()
panel_missing <- staleness_text()
cat(sprintf("Stage 'roster_bottom_up_engine' (active_rosters_cache.rds missing) -- run_btn disabled: %s\n",
            disabled_missing))
cat(sprintf("Staleness panel text: %s\n", panel_missing))

if (isTRUE(disabled_missing) && grepl("BLOCKED", panel_missing) &&
    grepl("active_rosters_cache.rds", panel_missing) && grepl("MISSING", panel_missing)) {
  pass("Criterion 1: missing input disables run_btn and names the missing file as MISSING.")
} else {
  fail(sprintf("Criterion 1: expected blocked+named-missing-file, got disabled=%s panel='%s'.",
               disabled_missing, panel_missing))
}

# ------------------------------------------------------------------------------------------
# Criterion 4: switch away to a different, fresh-input stage WITHOUT running -- confirm the
# blocked state does not leak onto the new (unrelated, still-fresh) stage.
# ------------------------------------------------------------------------------------------
app$set_inputs(stage_id = "player_metrics")
app$wait_for_idle(duration = 500, timeout = 60000)
disabled_after_switch <- run_btn_disabled()
panel_after_switch <- staleness_text()
cat(sprintf("After switching to 'player_metrics' (fresh, unrelated to active_rosters_cache.rds) -- run_btn disabled: %s\n",
            disabled_after_switch))
cat(sprintf("Staleness panel text: %s\n", panel_after_switch))

if (!disabled_after_switch && grepl("Inputs OK", panel_after_switch)) {
  pass("Criterion 4: switching to a fresh-input stage after a block re-evaluates staleness and un-blocks correctly.")
} else {
  fail(sprintf("Criterion 4: blocked state leaked onto 'player_metrics' (disabled=%s, panel='%s').",
               disabled_after_switch, panel_after_switch))
}

# ------------------------------------------------------------------------------------------
# Criterion 2: switch back to the blocked stage, tick the per-stage override, confirm the
# run control becomes clickable, trigger the run, and confirm the stage attempt actually
# happened (captured FAIL output), not a silent no-op.
# ------------------------------------------------------------------------------------------
app$set_inputs(stage_id = "roster_bottom_up_engine")
app$wait_for_idle(duration = 500, timeout = 60000)

disabled_before_override <- run_btn_disabled()
cat(sprintf("Re-selected 'roster_bottom_up_engine' (still missing input) -- run_btn disabled: %s\n",
            disabled_before_override))

app$set_inputs(override_ack = TRUE)
app$wait_for_idle(duration = 300, timeout = 60000)
disabled_after_override <- run_btn_disabled()
cat(sprintf("After checking the override -- run_btn disabled: %s\n", disabled_after_override))

if (isTRUE(disabled_before_override) && isFALSE(disabled_after_override)) {
  pass("Criterion 2 (part A): checking the per-stage override re-enables the run control.")
} else {
  fail(sprintf("Criterion 2 (part A): expected disabled->enabled transition on override, got %s->%s.",
               disabled_before_override, disabled_after_override))
}

app$click("run_btn", wait_ = TRUE)
app$wait_for_idle(duration = 1000, timeout = 60000)

status_text <- app$get_text("#status_ui")
output_text <- app$get_text("#output_log")
cat(sprintf("Status after override-run of roster_bottom_up_engine (input still missing): %s\n", status_text))
cat(sprintf("Captured output (first 300 chars): %s\n", substr(output_text, 1, 300)))

ran_via_override <- grepl("override", status_text, ignore.case = TRUE)
attempted_and_failed <- grepl("FAIL", status_text) &&
  nchar(trimws(output_text)) > 0 && !identical(trimws(output_text), "(no output captured)")

if (ran_via_override && attempted_and_failed) {
  pass("Criterion 2 (part B): the override actually executed the stage attempt (captured FAIL output), not a no-op.")
} else {
  fail(sprintf("Criterion 2 (part B): expected override-run + FAIL + non-empty output, got status='%s' output_len=%d.",
               status_text, nchar(output_text)))
}

restore_cache()

cat(sprintf("\n%d failure(s) out of this probe run.\n", length(failures)))
if (length(failures) > 0) {
  cat("Failures:\n")
  for (f in failures) cat(sprintf(" - %s\n", f))
  quit(status = 1)
} else {
  cat("ALL CRITERIA PASSED.\n")
  quit(status = 0)
}
