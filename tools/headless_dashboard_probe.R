# Headless browser verification for app.R, using shinytest2 (chromote-backed, drives real Chrome).
#
# WHY THIS EXISTS: every prior round of work in this repo disclosed "no display available to verify
# the dashboard" as an open residual risk (see docs/SPEC_COMPLIANCE_REPORT.md, docs/USER_TASKS.md).
# That's no longer true - Chrome is installed on this machine, and `shinytest2`/`chromote` (CRAN)
# can drive it headlessly to click into any tab and capture real browser console/DOM state, not just
# code-level inspection. This script is the reusable form of the ad hoc probe that traced a real bug
# in the Injury & Load Monitor tab (2026-09-12): a vector-unsafe use of this file's own scalar `%||%`
# operator (app.R line 50) inside a `mutate()` on a 42-row column, which R 4.3+ hard-errors on and
# Shiny/DT surfaces to the browser as an unreadable "Error [object Object]" instead of a real message.
#
# USAGE: Rscript.exe tools/headless_dashboard_probe.R [tab_value ...]
#   e.g. Rscript.exe tools/headless_dashboard_probe.R tab_injuries tab_embeddings tab_calibration
#   With no arguments, probes every tab in TAB_VALUES below.
#
# Requires: install.packages("shinytest2") once (pulls in chromote); Chrome or Edge installed.
# NOTE: set NOT_CRAN=true in the environment before running - shinytest2/testthat's AppDriver
# otherwise aborts with "Reason: On CRAN" even in normal interactive use.

Sys.setenv(CHROMOTE_CHROME = Sys.getenv(
  "CHROMOTE_CHROME",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"
))
if (Sys.getenv("NOT_CRAN") == "") Sys.setenv(NOT_CRAN = "true")

script_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
project_dir <- if (!is.na(script_dir)) normalizePath(file.path(script_dir, "..")) else getwd()
setwd(project_dir)

suppressMessages(library(shinytest2))

TAB_VALUES <- c(
  "tab_daily_edges", "tab_steam_radar", "tab_injuries", "tab_bet_tracker",
  "tab_embeddings", "tab_calibration", "tab_standings_calc", "tab_player_props"
)

args <- commandArgs(trailingOnly = TRUE)
tabs_to_check <- if (length(args) > 0) args else TAB_VALUES

app <- AppDriver$new(
  app_dir = project_dir, name = "wnba-dashboard-probe",
  height = 900, width = 1600, load_timeout = 60000, timeout = 30000,
  shiny_args = list(port = 7656)
)
Sys.sleep(2)

results <- list()
for (tab in tabs_to_check) {
  clicked <- app$run_js(sprintf(
    'var el = document.querySelector(\'a[data-value="%s"]\'); if (el) { el.click(); true; } else { false; }',
    tab
  ))
  if (isFALSE(clicked)) {
    cat(sprintf("[%s] SKIP - no such tab in the sidebar\n", tab))
    next
  }
  Sys.sleep(3)
  errs <- app$get_js('
    JSON.stringify(Array.from(document.querySelectorAll(".shiny-output-error")).map(function(e) {
      return {id: e.id, text: e.innerText};
    }));
  ')
  n_errs <- length(jsonlite::fromJSON(errs))
  status <- if (n_errs == 0) "OK" else "ERROR"
  cat(sprintf("[%s] %s%s\n", tab, status, if (n_errs > 0) paste0(" -> ", errs) else ""))
  results[[tab]] <- list(status = status, errors = errs)
}

app$stop()

n_ok <- sum(vapply(results, function(x) x$status == "OK", logical(1)))
cat(sprintf("\n%d/%d tabs clean.\n", n_ok, length(results)))
