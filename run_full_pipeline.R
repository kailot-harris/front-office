# ==============================================================================
# run_full_pipeline.R — MLB Analytics Pipeline Orchestrator (Phase 1, Wave 2)
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/run_full_pipeline.R
#
# Issue #14 (Phase 1, Wave 2): Wire Wave 1's four scripts into a single
# orchestrator via run_stage() try/catch, as a skeleton extensible for
# Phase 2+ stages — not a folder of stubs.
#
# Design:
#   run_stage() fail-safe infrastructure is ported from the NFL Analytics
#   sibling repo's run_full_pipeline.R (which itself is from the WNBA Analytics
#   repo). That is proven, hardened, sport-agnostic infrastructure.
#
# Wave 1 stage scripts and their exposed callable functions (Issue #13):
#   1. mlb_ingest.R        -> run_mlb_ingest()
#   2. mlb_stats_sync.R    -> run_stats_sync()
#   3. mlb_injury_scraper.R -> run_injury_scraper()
#   4. mlb_id_crosswalk.R  -> run_id_crosswalk()
#
# All four use the `call_fn` contract (no sys.nframe()==0 auto-run guard).
# Each script source()s config.R and logging_utils.R internally, but this
# orchestrator also sources both explicitly (see FINDING M-2 rationale below).
#
# Success criteria (Issue #14):
#   1. Calls all four Wave 1 functions, each wrapped in its own run_stage().
#   2. No config.R constant (cache paths, season windows) duplicated at a call
#      site — all referenced from config.R via cache_path().
#   3. DAG structure allows a Phase 2 stage to be added without restructuring.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/MLB Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

# Sourced before anything else so every stage's source()'d script can also call
# log_info()/log_warn()/log_error().
source("logging_utils.R")
# FINDING M-2 (docs/SECURITY_TECHNICAL_REVIEW.md, WNBA Analytics repo — same
# rationale applies here): an orchestrator that uses cache_path()/MLB_CACHE_*
# constants without sourcing config.R itself only "works" if some other stage's
# script happens to source config.R first and leak the constants into .GlobalEnv
# as a side effect (run_stage() sources with local = FALSE). Since run_stage()
# deliberately swallows a stage failure and continues, a failing early stage
# would leave those constants undefined and kill the pipeline at top level,
# OUTSIDE any run_stage() protection — the fail-safe inverted. Constants are
# therefore an explicit dependency of the orchestrator, sourced here rather than
# relied upon as a side effect of a later source() call.
source("config.R")
.LOG_SCRIPT <- "run_full_pipeline.R"

pipeline_start_time <- Sys.time()
message("==================================================================")
message(sprintf(">>> MLB QUANTITATIVE ENGINE STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
message("==================================================================")
log_info("Pipeline run started.", script = "run_full_pipeline.R")

# ---------------------------------------------------------------------------
# run_stage() — fail-safe stage runner
# ---------------------------------------------------------------------------
# Ported from the NFL Analytics sibling repo (which itself is from the WNBA
# Analytics repo). Any stage script's error is caught, logged, and the pipeline
# continues to the next stage rather than aborting.
#
# Stack-trace capture technique: tryCatch() is an EXITING handler — by the time
# its `error =` function runs, R has already unwound the call stack back to the
# tryCatch() call itself, so sys.calls() inside that handler would only show
# this function's own frame, not the deeper call chain that actually failed. To
# capture the real call chain, an inner withCallingHandlers() (a NON-exiting
# handler, which runs at the point of the error signal, before any unwinding)
# records sys.calls() into `captured_calls` and then lets the condition
# propagate normally up to the outer tryCatch(), which does the actual logging +
# fail-safe continue.
#
# `call_fn` (optional) — the name of a function to invoke in .GlobalEnv after
#   sourcing the stage script. Used when the script deliberately does NOT
#   auto-run on source() (this repo's convention for all Wave 1 scripts).
# `entry_fn` (optional, mutually exclusive with call_fn) — the name of a
#   function the stage script is expected to auto-run itself on source().
#   run_stage() does NOT call it; it only asserts the function exists in
#   .GlobalEnv afterward and logs a WARN if it does not. Not used by any stage
#   in this skeleton, kept for parity with the sibling original's contract.
#
# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md, WNBA Analytics repo),
# staleness detector. Asserts that every output a stage DECLARES it produces
# has an mtime at or after that stage's own start time. A stage that no-ops
# (broken auto-run guard), or whose writer silently errored inside its own
# tryCatch, will leave a stale file behind and is reported here instead of
# being indistinguishable from success. WARN, never stop() — the repo's
# fail-safe principle is that the pipeline reports and continues. A 1-second
# tolerance absorbs filesystem mtime granularity.
.check_stage_output <- function(script_name, description, output, start) {
  if (is.null(output) || length(output) == 0) return(invisible(NULL))
  for (path in output) {
    if (!file.exists(path)) {
      message(sprintf(">>> [WARN] %s: declared output %s does not exist after the stage ran.",
                      script_name, path))
      log_warn(sprintf("Declared stage output missing: %s", path),
               script = "run_full_pipeline.R", stage = script_name,
               description = description, output = path)
      next
    }
    mt <- tryCatch(file.info(path)$mtime, error = function(e) NA)
    if (length(mt) != 1 || is.na(mt)) next
    if (as.numeric(difftime(mt, start, units = "secs")) < -1) {
      age_h <- as.numeric(difftime(Sys.time(), mt, units = "hours"))
      message(sprintf(
        ">>> [WARN] %s reported success but its declared output %s was NOT rewritten (mtime %s, %.1f hours old). Possible silent no-op — see finding C-2.",
        script_name, path, format(mt, "%Y-%m-%d %H:%M:%S"), age_h))
      log_warn(sprintf("Stale stage output (possible silent no-op, C-2): %s", path),
               script = "run_full_pipeline.R", stage = script_name, description = description,
               output = path, output_mtime = format(mt, "%Y-%m-%d %H:%M:%S"),
               stage_start = format(start, "%Y-%m-%d %H:%M:%S"),
               hours_stale = round(age_h, 2))
    } else {
      message(sprintf(">>> [FRESH] %s -> %s (mtime %s)", script_name, path,
                      format(mt, "%Y-%m-%d %H:%M:%S")))
    }
  }
  invisible(NULL)
}

run_stage <- function(script_name, description, call_fn = NULL, entry_fn = NULL, output = NULL) {
  message(sprintf("\n>>> [STAGE] %s (%s)...", description, script_name))
  if (!is.null(call_fn) && !is.null(entry_fn)) {
    stop("run_stage(): pass either call_fn (invoke) or entry_fn (verify), not both.")
  }
  if (!file.exists(script_name)) {
    warning(sprintf("Script %s not found in working directory. Skipping.", script_name))
    log_warn(sprintf("Stage script not found, skipping: %s", script_name),
             script = "run_full_pipeline.R", stage = script_name, description = description)
    return(FALSE)
  }
  start <- Sys.time()
  captured_calls <- NULL
  result <- tryCatch({
    withCallingHandlers({
      source(script_name, local = FALSE)
      if (!is.null(call_fn)) {
        if (exists(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
          get(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)()
        } else {
          warning(sprintf("call_fn '%s' not found as a function after sourcing %s.", call_fn, script_name))
        }
      }
      # C-2: declared-entry-point existence check (does not invoke — the script self-runs).
      if (!is.null(entry_fn) &&
          !exists(entry_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
        message(sprintf(">>> [WARN] Declared entry point '%s()' not found after sourcing %s.",
                        entry_fn, script_name))
        log_warn(sprintf("Declared entry point '%s()' missing after sourcing %s.", entry_fn, script_name),
                 script = "run_full_pipeline.R", stage = script_name, entry_fn = entry_fn)
      }
      # C-2: declared-output freshness check.
      .check_stage_output(script_name, description, output, start)
      elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
      message(sprintf(">>> [COMPLETED] %s in %.2f seconds.", script_name, elapsed))
      log_info(sprintf("Stage completed: %s", script_name), script = "run_full_pipeline.R",
               stage = script_name, description = description, elapsed_sec = round(elapsed, 2))
      return(TRUE)
    }, error = function(e) {
      # Non-exiting: runs BEFORE stack unwind, so sys.calls() here is the real chain.
      captured_calls <<- sys.calls()
    })
  }, error = function(e) {
    stack_trace <- if (!is.null(captured_calls) && length(captured_calls) > 0) {
      trace_lines <- vapply(captured_calls, function(cl) {
        d <- tryCatch(paste(deparse(cl), collapse = " "), error = function(e2) "<unprintable call>")
        substr(d, 1, 200)
      }, character(1))
      paste(trace_lines, collapse = "  <-  ")
    } else {
      "<no call stack captured>"
    }
    log_error(
      sprintf("Stage failed: %s (%s)", script_name, description),
      condition = e,
      script = "run_full_pipeline.R",
      stage = script_name,
      stack_trace = stack_trace
    )
    # Fail-safe behavior: warn on console and let run_full_pipeline.R continue
    # to the next run_stage() call (do NOT stop() / re-throw here).
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    FALSE
  })

  # Memory-reduction (same rationale as NFL/WNBA siblings): force gc() between
  # stages so a large stage's temporary objects are reclaimed before the next
  # stage starts allocating its own large objects.
  gc(verbose = FALSE)

  result
}

# ------------------------------------------------------------------------------
# Chronological Execution Sequence — Wave 1 (four real ingestion stages)
# ------------------------------------------------------------------------------
# Ordering rationale:
#   1. ID crosswalk first — builds the canonical player-ID join table that every
#      later stage (and Phase 2+) joining player-level data across sources must
#      use. No Wave 1 stage currently *reads* it, but placing it first ensures
#      the table is available immediately if a later-added stage needs it.
#   2. MLB Stats API + Statcast ingestion — the core schedule/boxscore/pitch-
#      level data that Phase 2's rating engine will build on.
#   3. FanGraphs stats sync — leaderboard/advanced-metrics/park-factor data.
#      Independent of stage 2 in Wave 1, but logically follows the raw game
#      data it will eventually be joined with.
#   4. ESPN injury scraper — the most self-contained stage; placed last so that
#      if it fails (ESPN feeds are less reliable than MLB's own API), the three
#      higher-value data sources are already cached.
#
# No two Wave 1 scripts write to the same cache subdirectory (enforced by
# config.R's MLB_CACHE_STAGES + cache_path()), per Issue #13's success
# criterion 3.

# 1. Cross-vendor player-ID crosswalk.
# Writes cache/id_crosswalk/mlb_id_crosswalk.rds (via cache_path("id_crosswalk", ...)).
run_stage("mlb_id_crosswalk.R", "Build MLB Cross-Vendor Player-ID Crosswalk (Chadwick + ESPN)",
          call_fn = "run_id_crosswalk",
          output  = cache_path("id_crosswalk", "mlb_id_crosswalk.rds", create = FALSE))

# 2. MLB Stats API schedule/box-score + Statcast pitch-level ingestion.
# Writes cache/ingest/ (multiple season-keyed .rds files via cache_path("ingest", ...)).
# No single canonical output file to declare — the schedule file for the
# default season is the best proxy.
run_stage("mlb_ingest.R", "Ingest MLB Schedule, Box Scores & Statcast Pitch Data",
          call_fn = "run_mlb_ingest",
          output  = cache_path("ingest", "mlb_schedule_2024.rds", create = FALSE))

# 3. FanGraphs leaderboard sync (batter/pitcher leaders + park factors).
# Writes cache/stats_sync/ (fg_batters.rds, fg_pitchers.rds, fg_park.rds via
# cache_path("stats_sync", ...)).
run_stage("mlb_stats_sync.R", "Sync FanGraphs Batter/Pitcher Leaderboards & Park Factors",
          call_fn = "run_stats_sync",
          output  = c(cache_path("stats_sync", "fg_batters.rds", create = FALSE),
                      cache_path("stats_sync", "fg_pitchers.rds", create = FALSE),
                      cache_path("stats_sync", "fg_park.rds", create = FALSE)))

# 4. ESPN MLB injury feed scraper.
# Writes cache/injury/mlb_injuries.rds (via cache_path("injury", ...)).
run_stage("mlb_injury_scraper.R", "Scrape ESPN MLB Injury Feed (Player-Card ID parsing)",
          call_fn = "run_injury_scraper",
          output  = cache_path("injury", "mlb_injuries.rds", create = FALSE))

# ------------------------------------------------------------------------------
# FUTURE STAGES — extension point (Phase 2+)
# ------------------------------------------------------------------------------
# Per Issue #14's success criterion 3 and the NFL sibling's convention, this
# skeleton deliberately does NOT add stub run_stage() calls for scripts that
# don't exist yet — doing so would immediately fail with "script not found".
# A later phase should insert its own run_stage() calls HERE, in roughly this
# order, as each script is actually built:
#
# Phase 2 (Issue #15-#17): Rating engine
#   - tools/derive_mlb_constants.R  (Pythagorean exponent, Elo constants,
#     park factors — fills in config.R's NULL placeholders)
#   - mlb_pythagorean.R             (Pythagorean win-expectation baseline)
#   - mlb_elo_engine.R              (Elo ratings w/ starting-pitcher adjustment)
#
# Phase 3 (Issue #18): Specialty models
#   - mlb_marcel_baseline.R         (Marcel projection system)
#   - mlb_bullpen_fatigue.R         (Bullpen fatigue signal)
#
# Phase 4 (Issue #19): Postseason bracket simulator
# Phase 5 (Issue #20): Risk management engine
# Phase 6 (Issue #21): Market odds engine
# Phase 7 (Issue #22): Discord alert dispatcher
# Phase 8 (Issue #23): Early-season calibration review
# ------------------------------------------------------------------------------

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL MLB PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
log_info(sprintf("Pipeline run finished in %.2f seconds.", pipeline_total_time), script = "run_full_pipeline.R")
