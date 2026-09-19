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
# USAGE: Rscript.exe tools/headless_dashboard_probe.R [tab_value ...] [--screenshot]
#   e.g. Rscript.exe tools/headless_dashboard_probe.R tab_injuries tab_embeddings tab_calibration
#   With no arguments (other than --screenshot), probes every tab in TAB_VALUES below.
#   --screenshot: also saves tools/probe_screenshots/<tab_value>.png for every probed tab, and
#     (folded in from a one-off "probe_clutch_tab.R" script, 2026-09-17) prints the first data
#     table's row count/header/first-row text on the page, if one exists (id ending in a `-table`
#     wrapper or any `table` element) - useful for confirming a new tab's DT actually populated
#     with real rows, not just "no shiny-output-error". Omit --screenshot for a fast plain
#     error-only sweep across every tab (the original, most common use case).
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
  "tab_embeddings", "tab_calibration", "tab_standings_calc", "tab_player_props",
  "tab_clutch_shot_profile",
  # Added 2026-09-19: pre-existing tab, never added to this sweep list despite being
  # touched by two prior sessions' app.R fixes (2026-09-18 chart/provenance fix,
  # 2026-09-19 text-overflow fix) -- a real coverage gap, not a new tab.
  "tab_model_diagnostics"
)

args <- commandArgs(trailingOnly = TRUE)
want_screenshot <- "--screenshot" %in% args
args <- setdiff(args, "--screenshot")
tabs_to_check <- if (length(args) > 0) args else TAB_VALUES

if (want_screenshot) {
  shot_dir <- file.path(project_dir, "tools", "probe_screenshots")
  if (!dir.exists(shot_dir)) dir.create(shot_dir, recursive = TRUE)
}

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

  if (want_screenshot) {
    # A DT render can lag a couple seconds behind the tab-click itself (client JS builds
    # the table after Shiny pushes the data) - the 3s sleep above is enough to clear
    # shiny-output-error but caught empirically NOT enough for row count to be non-zero.
    app$wait_for_idle(duration = 500, timeout = 15000)
    Sys.sleep(6)
    # Shiny/bslib keep every tabPanel DOM mounted simultaneously (just hidden), so an
    # unscoped "table.dataTable" selector silently matches whichever tab happens to appear
    # first in the DOM instead of the one just clicked - and this app's hidden tab-panes
    # do not reliably carry a plain ".active" class to scope against either (tried that
    # first; still returned the wrong table). Filter on actual visibility instead
    # (offsetParent is null for any display:none ancestor) - this is what "active tab"
    # concretely means in the rendered DOM regardless of which CSS class scheme is used.
    find_visible_table_js <- function(body) sprintf('
      var tbls = Array.from(document.querySelectorAll("table.dataTable"))
        .filter(function(t) { return t.offsetParent !== null; });
      var tbl = tbls[0];
      %s
    ', body)
    # NOTE: row count read this way was empirically unreliable (returned 0 on a tab whose
    # saved screenshot clearly showed 184 populated rows) - some DT instances in this app
    # keep their <tbody> rows attached to a node this simple selector doesn't reach (e.g. a
    # virtual-scroll/paging body swap). Treat the header line as the authoritative "did we
    # find the right table" signal and the screenshot as ground truth for row content; the
    # row count here is a best-effort hint only, not a pass/fail signal.
    n_rows <- app$get_js(find_visible_table_js('tbl ? tbl.querySelectorAll("tbody tr").length : -1;'))
    header_text <- app$get_js(find_visible_table_js(
      'tbl ? Array.from(tbl.querySelectorAll("thead th")).map(function(th){return th.innerText;}).join(" | ") : "NO TABLE";'
    ))
    cat(sprintf("  -> table header: %s (row-count hint: %s, see screenshot for ground truth)\n", header_text, n_rows))
    console_logs <- tryCatch(app$get_logs(), error = function(e) NULL)
    if (!is.null(console_logs)) {
      browser_errs <- console_logs[console_logs$level %in% c("SEVERE", "error"), , drop = FALSE]
      cat(sprintf("  -> browser console SEVERE/error lines: %d\n", nrow(browser_errs)))
    }
    shot_path <- file.path(shot_dir, sprintf("%s.png", tab))
    if (file.exists(shot_path)) unlink(shot_path)
    app$get_screenshot(file = shot_path)
  }
}

app$stop()

n_ok <- sum(vapply(results, function(x) x$status == "OK", logical(1)))
cat(sprintf("\n%d/%d tabs clean.\n", n_ok, length(results)))
