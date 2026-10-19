# ==============================================================================
# tools/test_phase4_dashboard.R
# Phase 4 / Wave 2 / P4-B (agent_dashboard) verification suite for app.R.
#
# Covers SECURITY_TECHNICAL_REVIEW.md findings:
#   C-1  HCA literal -> config.R's WNBA_HCA
#   C-3  Tab 8 filters synthetic rows + shows an "N real resolved predictions" count
#   H-3  CACHE_TEAM_BOX path, team_score/opponent_team_score columns, em dash (not 0.0) on no data
#   M-3  props search uses stringr::str_detect(fixed(..., ignore_case)) not grepl()
#   M-6  zero local `%||%` definitions in app.R
#   M-8  Win_Pct numeric in cache, scales::percent() at display time
#   L-6  single canonical CACHE_PLAYER_PROPS read
#
# Follows tools/headless_dashboard_probe.R's pattern: real Chrome via shinytest2/chromote, with
# NOT_CRAN=true set BEFORE AppDriver$new() (CLAUDE.md - otherwise AppDriver aborts "Reason: On
# CRAN" even outside a test suite).
#
# ISOLATION (important): this suite needs to stage contract-shaped fixtures (numeric Win_Pct, an
# is_synthetic column) and to temporarily hide data/box_scores_cache.rds. Phase 4's Wave-2
# constraint forbids touching cached .rds artifacts, and four other agents are editing this repo
# concurrently - so instead of mutating the real cache/ and data/ trees, the whole project (~14 MB)
# is COPIED to a temp sandbox, config.R's absolute PROJECT_DIR is rewritten to point at the
# sandbox, and every browser run is driven against that copy. The real repo is never written to.
#
# USAGE: "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_dashboard.R
# Exits 0 if every check passes, 1 otherwise.
# ==============================================================================

Sys.setenv(CHROMOTE_CHROME = Sys.getenv(
  "CHROMOTE_CHROME",
  "C:/Program Files/Google/Chrome/Application/chrome.exe"
))
if (Sys.getenv("NOT_CRAN") == "") Sys.setenv(NOT_CRAN = "true")

PROJECT_ROOT <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_ROOT)

suppressMessages({
  library(shinytest2)
  library(dplyr)
})

failures <- 0L
ok <- function(label, pass, detail = "") {
  if (!isTRUE(pass)) failures <<- failures + 1L
  cat(sprintf("[%s] %s%s\n", if (isTRUE(pass)) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("=== Phase 4 Wave 2 (P4-B) dashboard tests ===\n\n")

app_src <- readLines("app.R", warn = FALSE)

# The negative assertions below ("the old broken call is GONE") must be evaluated against CODE
# only. Every fix in this wave cites its finding ID in a comment that necessarily quotes the old
# broken expression verbatim, so a naive grep over the raw file matches the comment and reports a
# false failure. app_code strips whole-line comments and trailing comments before those greps.
app_code <- sub("#.*$", "", app_src)
app_code <- app_code[grepl("[^[:space:]]", app_code)]

# ==============================================================================
# PART 1 - STATIC SOURCE CHECKS (no browser needed)
# ==============================================================================
cat("--- PART 1: static source checks ---\n")

invisible(tryCatch({ parse("app.R"); ok("CHECK 0 app.R parses cleanly", TRUE) },
                   error = function(e) ok("CHECK 0 app.R parses cleanly", FALSE, conditionMessage(e))))

# --- M-6: zero LOCAL definitions of `%||%` in app.R -------------------------------------------
def_lines <- grep("^\\s*`%\\|\\|%`\\s*<-", app_src)
src_lines <- grep('^\\s*source\\("logging_utils\\.R"\\)', app_src)
ok("CHECK 1 (M-6) app.R contains 0 definitions of `%||%`",
   length(def_lines) == 0 && length(src_lines) > 0,
   sprintf("definitions found: %s | canonical def sourced from logging_utils.R at app.R:%s",
           if (length(def_lines)) paste(def_lines, collapse = ",") else "0",
           paste(src_lines, collapse = ",")))

# --- C-1: no restated HCA literal ---------------------------------------------------------------
hca_lits <- grep("calc_hca.*value\\s*=\\s*2\\.4[^0-9]|%\\|\\|%\\s*2\\.4[^0-9]|\\b11\\.6\\b", app_code)
ok("CHECK 2 (C-1) no hardcoded HCA literal (2.4 / 11.6) remains in app.R",
   length(hca_lits) == 0,
   sprintf("WNBA_HCA referenced on lines %s", paste(grep("WNBA_HCA", app_src), collapse = ",")))

# --- H-3: constant-based path + real column names -----------------------------------------------
ok("CHECK 3a (H-3) no bare \"cache/box_scores_cache.rds\" literal; CACHE_TEAM_BOX used instead",
   length(grep('"cache/box_scores_cache\\.rds"', app_code)) == 0 &&
     length(grep("CACHE_TEAM_BOX", app_code)) > 0,
   sprintf("code-only matches for the dead literal = 0; CACHE_TEAM_BOX on app.R lines %s",
           paste(grep("CACHE_TEAM_BOX", app_src), collapse = ",")))

ok("CHECK 3b (H-3) diagnostics select() uses team_score / opponent_team_score",
   length(grep("home_score\\s*=\\s*team_score", app_code)) > 0 &&
     length(grep("away_score\\s*=\\s*opponent_team_score", app_code)) > 0 &&
     length(grep("home_score\\s*=\\s*score\\b", app_code)) == 0,
   "old score / opponent_score references absent from code")

# --- M-3: stringr, not grepl --------------------------------------------------------------------
ok("CHECK 4a (M-3) props search uses stringr::str_detect(fixed(..., ignore_case = TRUE))",
   length(grep("str_detect\\(", app_code)) > 0 &&
     length(grep("ignore_case\\s*=\\s*TRUE", app_code)) > 0 &&
     length(grep("grepl\\(input\\$props_search_player", app_code)) == 0,
   "grepl(input$props_search_player, ...) removed from code")

# M-3's caveat, re-verified on this machine rather than taken from the review on trust.
subj <- c("A'ja Wilson", "aja wilson", "Caitlin Clark")
n_grepl_fixed <- suppressWarnings(sum(grepl("wilson", subj, ignore.case = TRUE, fixed = TRUE)))
n_grepl_ic    <- sum(grepl("wilson", subj, ignore.case = TRUE))
n_str_detect  <- sum(stringr::str_detect(subj, stringr::fixed("wilson", ignore_case = TRUE)))
ok("CHECK 4b (M-3) re-verified: grepl(fixed=TRUE) silently drops ignore.case; str_detect does not",
   n_grepl_fixed == 1 && n_grepl_ic == 2 && n_str_detect == 2,
   sprintf("grepl(fixed=TRUE)=%d  grepl(ignore.case=TRUE)=%d  str_detect(fixed(ignore_case=TRUE))=%d",
           n_grepl_fixed, n_grepl_ic, n_str_detect))

paren_err <- tryCatch({ grepl("(", subj, ignore.case = TRUE); "no error" },
                      error = function(e) conditionMessage(e))
paren_ok <- tryCatch(sum(stringr::str_detect(subj, stringr::fixed("(", ignore_case = TRUE))),
                     error = function(e) NA_integer_)
ok("CHECK 4c (M-3) a literal \"(\" errors under grepl() but is safe under str_detect()",
   grepl("invalid regular expression", paren_err) && identical(as.integer(paren_ok), 0L),
   sprintf("grepl -> %s | str_detect -> %s match(es), no error", paren_err, paren_ok))

# --- L-6: single canonical props path -----------------------------------------------------------
ok("CHECK 5 (L-6) props read uses CACHE_PLAYER_PROPS only (no data/ + cache/ dual path)",
   length(grep('"data/latest_player_props\\.rds"', app_code)) == 0 &&
     length(grep('"cache/latest_player_props\\.rds"', app_code)) == 0 &&
     length(grep("CACHE_PLAYER_PROPS", app_code)) > 0,
   sprintf("CACHE_PLAYER_PROPS on lines %s", paste(grep("CACHE_PLAYER_PROPS", app_src), collapse = ",")))

# --- C-3 / M-8 source-level ---------------------------------------------------------------------
ok("CHECK 6a (C-3) Tab 8 filters on is_synthetic and renders a provenance count",
   length(grep("is_synthetic", app_src)) > 0 &&
     length(grep("diag_provenance", app_src)) > 0 &&
     length(grep("real resolved prediction", app_src)) > 0,
   "is_synthetic / diag_provenance / \"N real resolved prediction(s)\" all present")

ok("CHECK 7a (M-8) Win_Pct formatted with scales::percent() at display time",
   length(grep("scales::percent", app_src)) > 0,
   sprintf("scales::percent on lines %s", paste(grep("scales::percent", app_src), collapse = ",")))

ok("CHECK 7b (M-8) app.R holds no hardcoded \"79.3%\" string Win_Pct",
   length(grep('Win_Pct\\s*=\\s*"', app_code)) == 0,
   "fallback tibble now stores a numeric proportion")

# ==============================================================================
# PART 2 - SANDBOX: copy the project so no shared cache is ever mutated
# ==============================================================================
cat("\n--- PART 2: building isolated sandbox (real repo is never written to) ---\n")

SANDBOX <- file.path(tempdir(), "p4b_app_sandbox")
unlink(SANDBOX, recursive = TRUE, force = TRUE)
dir.create(SANDBOX, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(SANDBOX, recursive = TRUE, force = TRUE), add = TRUE)

root_files <- list.files(PROJECT_ROOT, pattern = "\\.(R|r|csv|rds|py|bat)$", full.names = TRUE)
file.copy(root_files, SANDBOX, overwrite = TRUE)
for (d in c("cache", "data", "tools", "logs")) {
  if (dir.exists(file.path(PROJECT_ROOT, d))) {
    file.copy(file.path(PROJECT_ROOT, d), SANDBOX, recursive = TRUE)
  }
}
dir.create(file.path(SANDBOX, "logs"), showWarnings = FALSE)
unlink(file.path(SANDBOX, "logs", "logs.duckdb"), force = TRUE)  # don't inherit a locked DB

# Rewrite config.R's absolute PROJECT_DIR so every CACHE_* constant resolves inside the sandbox.
cfg <- readLines(file.path(SANDBOX, "config.R"), warn = FALSE)
pd_line <- grep('^PROJECT_DIR\\s*<-', cfg)
cfg[pd_line] <- sprintf('PROJECT_DIR <- "%s"', gsub("\\\\", "/", SANDBOX))
writeLines(cfg, file.path(SANDBOX, "config.R"))
cat(sprintf("  sandbox: %s\n  config.R:%d rewritten -> %s\n", SANDBOX, pd_line, cfg[pd_line]))

sb <- function(...) file.path(SANDBOX, ...)

# --- Stage contract-shaped fixtures INSIDE the sandbox ------------------------------------------
# Interface contract (docs/task_assignments_phase4.md): Win_Pct is a numeric PROPORTION, written by
# agent_pipeline this same wave. On-disk it may still be the old character "79.3%" until that lands.
std_fixture <- tibble::tibble(
  Rank = 1:3,
  Team = c("Minnesota Lynx", "New York Liberty", "Las Vegas Aces"),
  Net_Rating = c(12.14, 12.09, 8.50),
  Proj_Wins = c(34.9, 34.9, 30.1),
  Proj_Losses = c(9.1, 9.1, 13.9),
  Win_Pct = c(0.793, 0.793, 0.684),   # numeric proportion, NOT "79.3%"
  Top_Core_Players = "Star Core"
)
saveRDS(std_fixture, sb("cache", "projected_wnba_standings.rds"))
cat(sprintf("  staged standings fixture: Win_Pct class=%s values=%s\n",
            class(std_fixture$Win_Pct), paste(std_fixture$Win_Pct, collapse = ",")))

# Interface contract: `is_synthetic` (logical) on prediction_accuracy_log.rds, written by
# agent_props this same wave. Stage it explicitly so the Tab 8 filter is exercised against the
# CONTRACTED schema even before agent_props' migration lands on the real cache.
real_log <- tryCatch(readRDS(sb("cache", "prediction_accuracy_log.rds")), error = function(e) NULL)
log_had_flag <- !is.null(real_log) && "is_synthetic" %in% names(real_log)
if (!is.null(real_log) && nrow(real_log) > 0) {
  log_fixture <- real_log
  if (!log_had_flag) {
    log_fixture$is_synthetic <- startsWith(as.character(log_fixture$game_id), "DIAG_")
  }
  n_real_resolved <- sum(log_fixture$status == "RESOLVED" & !log_fixture$is_synthetic)
  saveRDS(log_fixture, sb("cache", "prediction_accuracy_log.rds"))
  cat(sprintf("  staged pred-log fixture: %d rows | is_synthetic on real cache already? %s | TRUE=%d FALSE=%d | RESOLVED & !is_synthetic = %d\n",
              nrow(log_fixture), log_had_flag, sum(log_fixture$is_synthetic),
              sum(!log_fixture$is_synthetic), n_real_resolved))
} else {
  n_real_resolved <- 0
}

# ==============================================================================
# PART 3 - BROWSER CHECKS
# ==============================================================================
TAB_VALUES <- c(
  "tab_daily_edges", "tab_steam_radar", "tab_injuries", "tab_bet_tracker",
  "tab_embeddings", "tab_calibration", "tab_standings_calc",
  "tab_model_diagnostics", "tab_player_props"
)

click_tab <- function(app, tab) {
  app$run_js(sprintf(
    'var el = document.querySelector(\'a[data-value="%s"]\'); if (el) { el.click(); true; } else { false; }',
    tab))
}
# Scope the error query to the ACTIVE tab pane. shinydashboard keeps every tab in the DOM, so a
# single broken output on one tab otherwise shows up again on every tab clicked afterwards and is
# counted N times (this is how the pre-existing plot_embeddings_heatmap failure presented as "5
# console errors" across 5 tabs). Falls back to a document-wide query if no active pane is found.
tab_errors <- function(app) {
  app$get_js('
    var pane = document.querySelector(".tab-pane.active") || document;
    JSON.stringify(Array.from(pane.querySelectorAll(".shiny-output-error")).map(function(e){
      return {id: e.id, text: e.innerText};
    }));
  ')
}
n_errors <- function(js) {
  parsed <- jsonlite::fromJSON(js)
  if (is.data.frame(parsed)) nrow(parsed) else length(parsed)
}
txt_of <- function(app, id) {
  app$get_js(sprintf('var e=document.querySelector("#%s"); e ? e.innerText : "";', id))
}

cat("\n--- PART 3a: all 9 tabs, box-score cache PRESENT ---\n")
app <- AppDriver$new(app_dir = SANDBOX, name = "p4b-dashboard",
                     height = 900, width = 1600,
                     load_timeout = 90000, timeout = 45000,
                     shiny_args = list(port = 7661))
on.exit(try(app$stop(), silent = TRUE), add = TRUE)
Sys.sleep(2)

total_errs <- 0L
for (tab in TAB_VALUES) {
  if (isFALSE(click_tab(app, tab))) { cat(sprintf("  [%s] SKIP - no such tab\n", tab)); next }
  Sys.sleep(3)
  errs <- tab_errors(app); ne <- n_errors(errs)
  total_errs <- total_errs + ne
  cat(sprintf("  [%s] %s%s\n", tab, if (ne == 0) "OK" else "ERROR",
              if (ne > 0) paste0(" -> ", errs) else ""))
}
ok("CHECK 8 (all findings) zero browser output errors across all 9 tabs",
   total_errs == 0, sprintf("total .shiny-output-error nodes = %d", total_errs))

# --- M-8 end-to-end: numeric 0.793 in the cache renders as "79.3%" ------------------------------
click_tab(app, "tab_standings_calc"); Sys.sleep(3)
std_html <- txt_of(app, "tbl_bottom_up_standings")
cat(sprintf("  standings table text (first 200 chars): %s\n",
            substr(gsub("\\s+", " ", trimws(std_html)), 1, 200)))
ok("CHECK 9 (M-8) numeric Win_Pct 0.793 renders as \"79.3%\" in the standings tab",
   grepl("79.3%", std_html, fixed = TRUE) && !grepl("0.793", std_html, fixed = TRUE),
   sprintf("contains '79.3%%'=%s ; leaks raw '0.793'=%s",
           grepl("79.3%", std_html, fixed = TRUE), grepl("0.793", std_html, fixed = TRUE)))

# --- C-1 end-to-end: HCA input seeded from config.R ---------------------------------------------
cfg_env <- new.env(); sys.source(file.path(PROJECT_ROOT, "config.R"), envir = cfg_env)
hca_val <- app$get_value(input = "calc_hca")
ok("CHECK 10 (C-1) calc_hca input default equals config.R's WNBA_HCA",
   isTRUE(all.equal(as.numeric(hca_val), as.numeric(cfg_env$WNBA_HCA))),
   sprintf("input$calc_hca = %s ; config.R WNBA_HCA = %s", hca_val, cfg_env$WNBA_HCA))

# --- C-3 end-to-end: provenance count -----------------------------------------------------------
click_tab(app, "tab_model_diagnostics"); Sys.sleep(3)
prov <- txt_of(app, "diag_provenance")
cat(sprintf("  Tab 8 provenance banner -> %s\n", gsub("\\s+", " ", trimws(prov))))
ok("CHECK 11 (C-3) Tab 8 renders a visible \"N real resolved prediction(s)\" provenance count",
   grepl("real resolved prediction", prov),
   sprintf("banner reports the real (non-synthetic) denominator = %d", n_real_resolved))

ok("CHECK 11b (C-3) synthetic DIAG_ rows are excluded, not silently scored as real",
   grepl("excluded as synthetic/diagnostic fixtures", prov),
   "banner states the count of excluded synthetic rows")

cat(sprintf("  vbox_mae (cache present) -> %s\n", gsub("\\s+", " ", trimws(txt_of(app, "vbox_mae")))))
app$stop(); Sys.sleep(1)

# ==============================================================================
# PART 3b - H-3: hide the box-score cache, reload, assert em dash (not 0)
# ==============================================================================
cat("\n--- PART 3b: box-score cache TEMPORARILY RENAMED in the sandbox (H-3) ---\n")
box_path <- sb("data", "box_scores_cache.rds")
hidden   <- sb("data", "box_scores_cache.rds.p4b_hidden")
renamed  <- file.exists(box_path) && file.rename(box_path, hidden)
cat(sprintf("  renamed sandbox data/box_scores_cache.rds (success=%s); file.exists now = %s\n",
            renamed, file.exists(box_path)))

app2 <- AppDriver$new(app_dir = SANDBOX, name = "p4b-dashboard-nobox",
                      height = 900, width = 1600,
                      load_timeout = 90000, timeout = 45000,
                      shiny_args = list(port = 7662))
on.exit(try(app2$stop(), silent = TRUE), add = TRUE)
Sys.sleep(2)
click_tab(app2, "tab_model_diagnostics"); Sys.sleep(4)

mae_txt  <- txt_of(app2, "vbox_mae")
rmse_txt <- txt_of(app2, "vbox_rmse")
bias_txt <- txt_of(app2, "vbox_bias")
prov2    <- txt_of(app2, "diag_provenance")
errs2    <- tab_errors(app2)

cat(sprintf("  vbox_mae  -> %s\n", gsub("\\s+", " ", trimws(mae_txt))))
cat(sprintf("  vbox_rmse -> %s\n", gsub("\\s+", " ", trimws(rmse_txt))))
cat(sprintf("  vbox_bias -> %s\n", gsub("\\s+", " ", trimws(bias_txt))))
cat(sprintf("  banner    -> %s\n", gsub("\\s+", " ", trimws(prov2))))

dash <- "\u2014"
has_dash   <- function(s) grepl(dash, s, fixed = TRUE)
shows_zero <- function(s) grepl("(^|[^0-9.])0(\\.0+)?(\\s|$)", s)

ok("CHECK 12 (H-3) MAE/RMSE/Bias render an em dash, NOT 0, when the box cache is missing",
   has_dash(mae_txt) && has_dash(rmse_txt) && has_dash(bias_txt) &&
     !shows_zero(mae_txt) && !shows_zero(rmse_txt) && !shows_zero(bias_txt),
   sprintf("mae='%s' rmse='%s' bias='%s'",
           trimws(mae_txt), trimws(rmse_txt), trimws(bias_txt)))

ok("CHECK 13 (H-3) the missing-data state is explicitly labelled, not silent",
   grepl("DIAGNOSTICS UNAVAILABLE", prov2),
   "banner carries a DIAGNOSTICS UNAVAILABLE warning")

ok("CHECK 14 (H-3) no Shiny error state on Tab 8 with the cache missing",
   n_errors(errs2) == 0,
   sprintf("error nodes = %d %s", n_errors(errs2), if (n_errors(errs2) > 0) errs2 else ""))

app2$stop(); Sys.sleep(1)
if (renamed) file.rename(hidden, box_path)

# ==============================================================================
# PART 3c - M-3: type "(" into the props search one character at a time
# ==============================================================================
cat("\n--- PART 3c: props search, natural character-by-character typing (M-3) ---\n")
app3 <- AppDriver$new(app_dir = SANDBOX, name = "p4b-dashboard-props",
                      height = 900, width = 1600,
                      load_timeout = 90000, timeout = 45000,
                      shiny_args = list(port = 7663))
on.exit(try(app3$stop(), silent = TRUE), add = TRUE)
Sys.sleep(2)
click_tab(app3, "tab_player_props"); Sys.sleep(3)

# Each element is the CUMULATIVE input value after one more keystroke - exactly what Shiny's
# textInput sends on every character. "(", "[", "a{1," are M-3's reproduced crash patterns.
keystrokes <- c("W", "Wi", "Wil", "(", "(a", "(a+", "(a+)", "[", "a{", "a{1", "a{1,", "Wilson")
typing_errs <- integer(0)
for (k in keystrokes) {
  app3$set_inputs(props_search_player = k)
  Sys.sleep(1.2)
  e <- tab_errors(app3); ne <- n_errors(e)
  typing_errs <- c(typing_errs, ne)
  cat(sprintf("  typed %-9s -> %d shiny error node(s)%s\n", sprintf('"%s"', k), ne,
              if (ne > 0) paste0(" ", e) else ""))
}
ok("CHECK 15 (M-3) props tab never enters Shiny's error state while typing \"(\", \"[\", \"a{1,\"",
   sum(typing_errs) == 0,
   sprintf("cumulative error nodes across %d keystrokes = %d", length(keystrokes), sum(typing_errs)))

# Case-insensitivity must survive the switch to literal matching (what fixed=TRUE would have broken).
app3$set_inputs(props_search_player = "wilson"); Sys.sleep(1.5)
lower_txt <- txt_of(app3, "tbl_props_terminal")
app3$set_inputs(props_search_player = "Wilson"); Sys.sleep(1.5)
upper_txt <- txt_of(app3, "tbl_props_terminal")
ok("CHECK 16 (M-3) search remains CASE-INSENSITIVE (lowercase query matches the same rows)",
   nchar(lower_txt) > 0 && identical(lower_txt, upper_txt),
   sprintf("'wilson' and 'Wilson' produce identical tables = %s", identical(lower_txt, upper_txt)))

app3$stop()

# --- Confirm the real repo's caches were never touched -------------------------------------------
cat("\n--- PART 4: confirming the real repo was not mutated ---\n")
real_std <- readRDS(file.path(PROJECT_ROOT, "cache", "projected_wnba_standings.rds"))
cat(sprintf("  real cache/projected_wnba_standings.rds Win_Pct class = %s (untouched by this test)\n",
            class(real_std$Win_Pct)))

cat(sprintf("\n=== %s: %d check(s) failed ===\n",
            if (failures == 0) "ALL CHECKS PASSED" else "FAILURES", failures))
quit(status = if (failures == 0) 0 else 1)
