# ==============================================================================
# tools/test_phase4_pipeline.R
# Phase 4 (Security & Data-Integrity Remediation) — Wave 2, task P4-D (agent_pipeline).
#
# Verifies the orchestrator/stage-script findings:
#   C-2  four (in fact five) stage scripts auto-run guards that never fire under run_stage()
#   M-1  Python stage exit status discarded -> false [COMPLETED]
#   M-2  run_full_pipeline.R never sourced config.R
#   M-7  future_lapply() called without future.seed (pipeline half)
#   C-1  hardcoded 2.40 HCA literals in roster_bottom_up_engine.R / playoff_simulator.R
#   H-2  naive left_join(rapm_df, by = "player_id") in roster_bottom_up_engine.R
#   M-8  Win_Pct persisted as a formatted string
#
# Per CLAUDE.md, run as a file (never inline -e):
#   "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_pipeline.R
#
# NOTE: this script deliberately does NOT source logging_utils.R at top level. DuckDB allows one
# writing process per file, and CHECK 2 launches a full pipeline run as a child process; holding
# logs.duckdb here would force every one of that child's log rows into the M-7 spill path.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")

RSCRIPT <- "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
BASELINE_REF <- "5761489"   # Wave 1 commit = the pre-fix state of every file P4-D touches

failures <- character(0)
ok <- function(label, detail = "") {
  cat(sprintf("[PASS] %s%s\n", label, if (nzchar(detail)) paste0("  -- ", detail) else ""))
}
bad <- function(label, detail = "") {
  failures <<- c(failures, label)
  cat(sprintf("[FAIL] %s%s\n", label, if (nzchar(detail)) paste0("  -- ", detail) else ""))
}
check <- function(cond, label, detail = "") if (isTRUE(cond)) ok(label, detail) else bad(label, detail)

cat("=== Phase 4 Wave 2 / P4-D (agent_pipeline) tests ===\n\n")

# ==============================================================================
# The declared DAG. Mirrors run_full_pipeline.R's 17 run_stage() invocations, in order.
#   fn    = declared entry point (NA for scripts with no guard -- they run unconditionally on
#           source -- and for the .py stage)
#   mode  = "guard"  script self-runs behind an auto-run guard  (C-2 territory)
#           "always" no guard at all, body executes on source
#           "call"   deliberately does not self-run; run_stage() invokes it via call_fn
#           "py"     python stage
#   out   = declared output cache(s), or NA
# ==============================================================================
DAG <- tibble::tribble(
  ~script,                          ~fn,                           ~mode,    ~out,
  "tools/data_health_probe.R",      "check_cache_health",          "call",   NA,
  # L-4 (with agent_props): explicit ingest stage. "call" not "guard" — its sys.nframe() footer
  # stays dormant on purpose so call_fn is the single invoker (no double-ingest). No declared
  # output: daily_box_ingest() legitimately skips the write when there are no new games.
  "daily_ingest.R",                 "daily_box_ingest",            "call",   NA,
  "sync_rosters.R",                 "sync_active_rosters",         "guard",  file.path(CACHE_DIR, "active_rosters_cache.rds"),
  "injury_scraper.R",               "fetch_live_wnba_injuries",    "guard",  CACHE_INJURY_DATA,
  # Real output is logs/analytics.duckdb, NOT config.R's CACHE_EMBEDDINGS/CACHE_SIMILARITY CSVs —
  # see the corrected stage comment in run_full_pipeline.R.
  "team_embeddings.py",             NA,                            "py",     "logs/analytics.duckdb",
  "prediction_accuracy_logger.R",   "reconcile_predictions",       "call",   NA,
  "shot_quality_engine.R",          NA,                            "always", "cache/team_shot_quality.rds",
  "fatigue_travel_engine.R",        "evaluate_slate_fatigue",      "guard",  "cache/travel_fatigue_metrics.rds",
  "rapm_engine.R",                  "estimate_rapm_ratings",       "guard",  "cache/rapm_ratings.rds",
  "roster_bottom_up_engine.R",      "project_all_wnba_teams",      "guard",  "cache/projected_wnba_standings.rds",
  "market_odds_engine.R",           NA,                            "always", file.path(CACHE_DIR, "latest_value_bets.rds"),
  "prediction_accuracy_logger.R",   "log_todays_predictions",      "call",   NA,
  # Canonical single write after agent_props' L-6 fix (was also writing data/latest_player_props.rds).
  "player_props_engine.R",          "generate_active_props_table", "guard",  CACHE_PLAYER_PROPS,
  "copula_props_engine.R",          "run_copula_suite",            "guard",  "cache/copula_wilson_pra.rds",
  "playoff_simulator.R",            "simulate_playoff_suite",      "guard",  "cache/playoff_series_wnba_demo.rds",
  "risk_management_engine.R",       "compute_risk_state",          "guard",  "cache/risk_state.rds",
  "notify_bets.R",                  NA,                            "always", NA,
  # betting_ledger.rds is CONDITIONAL (only written when a pending bet actually grades), so the
  # unconditional metrics file is the one declared for the freshness assertion.
  "bet_tracker.r",                  NA,                            "always", file.path(CACHE_DIR, "rolling_bet_metrics.rds")
)

check(nrow(DAG) == 18, "CHECK 0a  DAG table describes all 18 run_stage() invocations",
      sprintf("%d stages (17 original + daily_ingest.R, added for L-4)", nrow(DAG)))

pipeline_src <- readLines("run_full_pipeline.R", warn = FALSE)
declared <- unique(na.omit(stringr::str_match(pipeline_src, '^\\s*run_stage\\("([^"]+)"')[, 2]))
parallel_declared <- unique(na.omit(stringr::str_match(pipeline_src, '^\\s*list\\(s = "([^"]+)"')[, 2]))
declared <- unique(c(declared, parallel_declared))
missing_from_table <- setdiff(declared, DAG$script)
check(length(missing_from_table) == 0,
      "CHECK 0b  every run_stage() call site in run_full_pipeline.R is covered by this test",
      sprintf("uncovered: %s", if (length(missing_from_table)) paste(missing_from_table, collapse = ", ") else "none"))

# ==============================================================================
# CHECK 1 (C-2) — sys.nframe() harness
#
# Replicates run_stage()'s EXACT sourcing shape: source(local = FALSE) called from inside a
# function, itself inside withCallingHandlers() inside tryCatch(). Each stage script's real
# auto-run guard condition is extracted from its source and evaluated at that frame depth, both
# for the pre-fix files (read out of git at the Wave 1 commit) and the current working tree.
# ==============================================================================
cat("\n--- CHECK 1 (C-2): auto-run guard evaluation at run_stage()'s frame depth ---\n")

# Pull the last top-level `if (...)` whose condition mentions interactive()/sys.nframe().
extract_guard <- function(path) {
  exprs <- tryCatch(parse(path), error = function(e) NULL)
  if (is.null(exprs)) return(NA_character_)
  hits <- character(0)
  for (e in exprs) {
    if (is.call(e) && identical(as.character(e[[1]])[1], "if")) {
      cond <- paste(deparse(e[[2]]), collapse = " ")
      if (grepl("interactive\\(\\)|sys\\.nframe", cond)) hits <- c(hits, cond)
    }
  }
  if (length(hits) == 0) NA_character_ else hits[length(hits)]
}

# source() from inside a function, exactly as run_stage() does.
probe_guard_at_stage_depth <- function(cond_text) {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    sprintf("GUARD_RESULT <<- isTRUE(%s)", cond_text),
    "GUARD_NFRAME <<- sys.nframe()"
  ), tmp)
  GUARD_RESULT <<- NA; GUARD_NFRAME <<- NA
  run_stage_shape <- function(script_name) {
    tryCatch({
      withCallingHandlers({
        source(script_name, local = FALSE)
      }, error = function(e) invisible(NULL))
    }, error = function(e) invisible(NULL))
  }
  run_stage_shape(tmp)
  unlink(tmp)
  list(fires = GUARD_RESULT, nframe = GUARD_NFRAME)
}

baseline_dir <- file.path(tempdir(), "phase4_baseline")
dir.create(baseline_dir, showWarnings = FALSE, recursive = TRUE)
baseline_copy <- function(script) {
  dest <- file.path(baseline_dir, gsub("[/\\\\]", "_", script))
  txt <- suppressWarnings(system2("git", c("show", sprintf("%s:%s", BASELINE_REF, script)),
                                  stdout = TRUE, stderr = FALSE))
  if (length(txt) == 0) return(NA_character_)
  writeLines(txt, dest)
  dest
}

guard_rows <- list()
for (i in seq_len(nrow(DAG))) {
  s <- DAG$script[i]; mode <- DAG$mode[i]
  if (mode == "py") next
  cur_guard <- extract_guard(s)
  base_path <- baseline_copy(s)
  old_guard <- if (is.na(base_path)) NA_character_ else extract_guard(base_path)
  before <- if (is.na(old_guard)) list(fires = NA, nframe = NA) else probe_guard_at_stage_depth(old_guard)
  after  <- if (is.na(cur_guard)) list(fires = NA, nframe = NA) else probe_guard_at_stage_depth(cur_guard)
  guard_rows[[length(guard_rows) + 1]] <- tibble::tibble(
    script = s, mode = mode,
    guard_before = ifelse(is.na(old_guard), "<none: runs on source>", old_guard),
    fires_before = ifelse(is.na(old_guard), TRUE, before$fires),
    guard_after  = ifelse(is.na(cur_guard), "<none: runs on source>", cur_guard),
    fires_after  = ifelse(is.na(cur_guard), TRUE, after$fires),
    nframe       = ifelse(is.na(cur_guard), NA, after$nframe)
  )
}
guards <- dplyr::bind_rows(guard_rows) |> dplyr::distinct(script, .keep_all = TRUE)
print(as.data.frame(guards[, c("script", "mode", "guard_before", "fires_before", "guard_after", "fires_after")]),
      right = FALSE)
cat(sprintf("\n  sys.nframe() inside a run_stage()-style source(): %s\n",
            paste(unique(na.omit(guards$nframe)), collapse = "/")))

# "main body executes" == the guard fires, OR the script has no guard, OR run_stage() invokes the
# entry point explicitly via call_fn.
executes <- guards$fires_after | guards$mode %in% c("always", "call")
broken_before <- guards$script[!(guards$fires_before | guards$mode %in% c("always", "call"))]
check(all(executes), "CHECK 1a (C-2) every DAG stage's main body now executes under run_stage()",
      sprintf("%d/%d execute; non-executing: %s", sum(executes), nrow(guards),
              if (all(executes)) "none" else paste(guards$script[!executes], collapse = ", ")))
check(length(broken_before) >= 4,
      "CHECK 1b (C-2) the harness reproduces the ORIGINAL no-op behaviour at the Wave 1 commit",
      sprintf("%d stage(s) were silent no-ops before the fix: %s",
              length(broken_before), paste(broken_before, collapse = ", ")))

# ==============================================================================
# CHECK 2 (M-7) — future.seed present on both future_lapply() calls
# ==============================================================================
cat("\n--- CHECK 2 (M-7 / M-2): static checks on run_full_pipeline.R ---\n")
# Strip whole-line AND trailing comments before counting: these fixes are heavily commented and
# every finding ID / rationale note mentions the very tokens being grepped for. Counting raw lines
# would pass on a file where the fix is only described, not applied.
strip_comments <- function(lines) {
  lines <- lines[!grepl("^\\s*#", lines)]
  trimws(sub("#.*$", "", lines))
}
pipeline_code <- strip_comments(pipeline_src)
n_seed <- sum(grepl("future\\.seed", pipeline_code))
check(n_seed == 2, "CHECK 2a (M-7) future.seed passed to both future_lapply() calls",
      sprintf('grep -c "future.seed" run_full_pipeline.R = %d', n_seed))
check(any(grepl('^source\\("config\\.R"\\)', pipeline_code)),
      "CHECK 2b (M-2) run_full_pipeline.R sources config.R explicitly")
check(any(grepl("system2\\(\"python\"", pipeline_code)) && any(grepl("exited with status", pipeline_code)),
      "CHECK 2c (M-1) python stage uses system2() and checks the exit status")

# ==============================================================================
# CHECK 3 (C-1) — no 2.40 HCA literals left in the two owned files
# ==============================================================================
hca_lits <- character(0)
for (f in c("roster_bottom_up_engine.R", "playoff_simulator.R")) {
  code <- strip_comments(readLines(f, warn = FALSE))
  if (any(grepl("2\\.40", code))) hca_lits <- c(hca_lits, f)
}
check(length(hca_lits) == 0, "CHECK 3 (C-1) no hardcoded 2.40 HCA literal in executable code",
      sprintf("offenders: %s", if (length(hca_lits)) paste(hca_lits, collapse = ", ") else "none"))

# ==============================================================================
# CHECK 4 (H-2) — naive player_id join gone from roster_bottom_up_engine.R
# ==============================================================================
rb_code <- strip_comments(readLines("roster_bottom_up_engine.R", warn = FALSE))
check(!any(grepl('left_join\\(rapm_df, by = "player_id"\\)', rb_code)) &&
        any(grepl("join_rapm_to_roster\\(", rb_code)),
      "CHECK 4 (H-2) roster_bottom_up_engine.R uses the shared join_rapm_to_roster() helper")

# ==============================================================================
# CHECK 5 (C-2 / M-1) — Python stage that exits non-zero must log [FAILED], not [COMPLETED]
# Runs in a child process so this one never holds logs.duckdb.
# ==============================================================================
cat("\n--- CHECK 5 (M-1): python stage exit-status fixture ---\n")
fixture_py <- "_tmp_phase4_fail_stage.py"
writeLines(c("import sys", "print('fixture: simulating a torch import failure')", "sys.exit(1)"), fixture_py)
fixture_r <- "_tmp_phase4_pyexit_probe.R"
writeLines(c(
  'setwd("c:/Users/kailo/kayceeslices/WNBA Analytics")',
  'source("logging_utils.R"); source("config.R")',
  'exprs <- parse("run_full_pipeline.R")',
  'for (e in exprs) {',
  '  if (is.call(e) && identical(as.character(e[[1]])[1], "<-") &&',
  '      as.character(e[[2]])[1] %in% c("run_stage", ".check_stage_output")) eval(e, .GlobalEnv)',
  '}',
  'res <- withCallingHandlers(',
  '  run_stage("_tmp_phase4_fail_stage.py", "PHASE4 M-1 fixture: python stage that exits 1"),',
  '  warning = function(w) { cat("WARNING TEXT:", conditionMessage(w), "\\n"); invokeRestart("muffleWarning") })',
  'cat("RUN_STAGE_RETURNED:", res, "\\n")'
), fixture_r)
py_out <- suppressWarnings(system2(RSCRIPT, fixture_r, stdout = TRUE, stderr = TRUE))
cat(paste0("  | ", py_out, collapse = "\n"), "\n")
unlink(c(fixture_py, fixture_r))
check(any(grepl(">>> \\[FAILED\\] _tmp_phase4_fail_stage\\.py", py_out)) &&
        any(grepl("exited with status 1", py_out)) &&
        !any(grepl("\\[COMPLETED\\] _tmp_phase4_fail_stage\\.py", py_out)) &&
        any(grepl("RUN_STAGE_RETURNED: FALSE", py_out)),
      "CHECK 5 (M-1) non-zero python exit now logs [FAILED] and returns FALSE")

# ==============================================================================
# CHECK 6 (C-2) — THE REAL THING. Run the whole pipeline and check output mtimes.
# ==============================================================================
cat("\n--- CHECK 6 (C-2): real end-to-end run of run_full_pipeline.R ---\n")
outs <- DAG |> filter(!is.na(out)) |> distinct(script, .keep_all = TRUE)
pre_mtime <- vapply(outs$out, function(p) {
  if (file.exists(p)) as.character(file.info(p)$mtime) else NA_character_
}, character(1))

run_start <- Sys.time()
cat(sprintf("  run start: %s\n", format(run_start, "%Y-%m-%d %H:%M:%S")))
pipe_out <- suppressWarnings(system2(RSCRIPT, "run_full_pipeline.R", stdout = TRUE, stderr = TRUE))
exit_code <- attr(pipe_out, "status")
exit_code <- if (is.null(exit_code)) 0L else exit_code
writeLines(pipe_out, "logs/test_phase4_pipeline_run.log")
cat("\n  --- last 40 lines of the real pipeline run ---\n")
cat(paste0("  | ", tail(pipe_out, 40), collapse = "\n"), "\n")

check(exit_code == 0, "CHECK 6a (C-2) run_full_pipeline.R exits 0",
      sprintf("exit code = %d (full console captured in logs/test_phase4_pipeline_run.log)", exit_code))

post <- tibble::tibble(
  script = outs$script,
  output = outs$out,
  mtime_before = pre_mtime,
  mtime_after = vapply(outs$out, function(p) {
    if (file.exists(p)) as.character(file.info(p)$mtime) else NA_character_
  }, character(1))
) |>
  mutate(
    advanced = !is.na(mtime_after) &
      as.numeric(difftime(as.POSIXct(mtime_after), run_start, units = "secs")) >= -1
  )
cat("\n  --- declared stage outputs: mtime vs run start ---\n")
print(as.data.frame(post), right = FALSE)

c2_stages <- c("sync_rosters.R", "injury_scraper.R", "roster_bottom_up_engine.R", "playoff_simulator.R")
c2_rows <- post |> filter(script %in% c2_stages)
check(all(c2_rows$advanced),
      "CHECK 6b (C-2) all four previously-no-op stages rewrote their declared output this run",
      sprintf("%d/4 advanced; stale: %s", sum(c2_rows$advanced),
              if (all(c2_rows$advanced)) "none" else paste(c2_rows$script[!c2_rows$advanced], collapse = ", ")))
check(all(post$advanced),
      "CHECK 6c (C-2) EVERY declared stage output's mtime is at or after the run start",
      sprintf("%d/%d fresh; stale: %s", sum(post$advanced), nrow(post),
              if (all(post$advanced)) "none" else paste(post$script[!post$advanced], collapse = ", ")))
check(!any(grepl("UNRELIABLE VALUE", pipe_out)),
      "CHECK 6d (M-7) no future.apply 'UNRELIABLE VALUE' warning in the real run")
check(any(grepl("\\[FRESH\\]", pipe_out)),
      "CHECK 6e (C-2) run_stage()'s new declared-output freshness assertion ran",
      sprintf("%d [FRESH] line(s) emitted", sum(grepl("\\[FRESH\\]", pipe_out))))

# L-4: daily_ingest.R must not merely be sourced — daily_box_ingest() must actually EXECUTE.
# The [STAGE] banner alone would also appear for a stage that no-ops, so the real evidence is a
# log line the function body itself emits (`call: daily_box_ingest()` in the structured extras).
ingest_stage  <- grepl("\\[STAGE\\] Ingest Latest WNBA Team Box Scores", pipe_out)
ingest_body   <- grepl("daily_box_ingest\\(\\)", pipe_out)
ingest_failed <- grepl("\\[FAILED\\] daily_ingest\\.R", pipe_out)
cat("\n  --- L-4: daily_ingest.R stage, real console evidence ---\n")
cat(paste0("  | ", pipe_out[ingest_stage | ingest_body], collapse = "\n"), "\n")
check(any(ingest_stage) && any(ingest_body) && !any(ingest_failed),
      "CHECK 6f (L-4) daily_ingest.R runs as an explicit stage and daily_box_ingest() executes",
      sprintf("stage banner=%s, body log lines=%d, failed=%s",
              any(ingest_stage), sum(ingest_body), any(ingest_failed)))

# ==============================================================================
# CHECK 7 (M-8) — Win_Pct is a numeric proportion in the freshly written standings
# ==============================================================================
cat("\n--- CHECK 7 (M-8): projected_wnba_standings.rds schema ---\n")
st_path <- "cache/projected_wnba_standings.rds"
if (!file.exists(st_path)) {
  bad("CHECK 7 (M-8) standings cache exists", st_path)
} else {
  st <- readRDS(st_path)
  cat(sprintf("  Win_Pct class: %s | values: %s\n", class(st$Win_Pct)[1],
              paste(utils::head(st$Win_Pct, 5), collapse = ", ")))
  check(identical(class(st$Win_Pct), "numeric"), "CHECK 7a (M-8) Win_Pct stored as numeric",
        sprintf("class = %s", class(st$Win_Pct)[1]))
  check(all(is.finite(st$Win_Pct)) && all(st$Win_Pct >= 0 & st$Win_Pct <= 1),
        "CHECK 7b (M-8) Win_Pct values all lie in [0, 1]",
        sprintf("range %.4f .. %.4f", min(st$Win_Pct), max(st$Win_Pct)))
  check(all(c("Team", "Net_Rating", "Proj_Wins", "Proj_Losses", "Win_Pct") %in% names(st)),
        "CHECK 7c (M-8) standings schema otherwise unchanged",
        paste(names(st), collapse = ", "))
}

# ==============================================================================
cat("\n")
if (length(failures) == 0) {
  cat(sprintf("=== ALL CHECKS PASSED: 0 check(s) failed ===\n"))
} else {
  cat(sprintf("=== %d CHECK(S) FAILED ===\n", length(failures)))
  for (f in failures) cat("  - ", f, "\n", sep = "")
}
quit(status = if (length(failures) == 0) 0 else 1)
