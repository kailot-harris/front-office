# ==============================================================================
# run_full_pipeline.R (WNBA port)
# Master Production Quantitative Pipeline (Phases 1 through 5) — WNBA Edition
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/run_full_pipeline.R
#
# Ported from NBA Analytics/run_full_pipeline.R. Same 13-stage run_stage()-wrapped DAG
# structure and ordering as the NBA original (per the T5 brief), with every script/output
# name below cross-checked against T0-T4's ACTUAL Handoff Notes in task_assignments.md
# rather than the plan document's proposed names — see the per-stage comments for exactly
# which Handoff Notes section confirms each filename.
#
# NOTE ON STAGE 5 (rapm_engine.R): as of Task P2 (wnba_rapm_shotquality_agent,
# task_assignments_phase2.md, 2026-09-12), `rapm_engine.R` now EXISTS in this repo and is a
# real possession-level RAPM engine (wehoop::load_wnba_stats_possessions()-backed, not
# fabricated). This stage is no longer expected to skip — see rapm_engine.R's own header for
# the real-data pipeline detail. The `run_stage()` `file.exists()` guard below is left in
# place regardless (Ground Rule 5) as the correct fail-safe if the file is ever removed again.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

# Task P5 (wnba_logging_agent): structured logging utility. Sourced before anything else so
# every stage's source()'d script can also call log_info()/log_warn()/log_error() if it has
# been wired to do so (see task_assignments_phase2.md P5 Handoff Notes for the full list).
source("logging_utils.R")
# FINDING M-2 (docs/SECURITY_TECHNICAL_REVIEW.md): the orchestrator used CACHE_DIR at line ~125
# but never sourced config.R. That only worked because stage 0 (tools/data_health_probe.R) calls
# source("config.R") and run_stage() sources with local = FALSE, leaking the constants into
# .GlobalEnv as a side effect. Since run_stage()'s tryCatch deliberately swallows a stage failure
# and continues, a failing health probe would leave CACHE_DIR undefined and kill the pipeline at
# top level, OUTSIDE any run_stage() protection — the fail-safe inverted. Constants are now an
# explicit dependency of the orchestrator.
source("config.R")
.LOG_SCRIPT <- "run_full_pipeline.R"

pipeline_start_time <- Sys.time()
message("==================================================================")
message(sprintf(">>> WNBA QUANTITATIVE ENGINE v5.0 (WNBA PORT) STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
message("==================================================================")
log_info(sprintf("Pipeline run started."), script = "run_full_pipeline.R")

# run_stage() — UNCHANGED fail-safe design: any stage script's error is caught, logged, and
# the pipeline continues to the next stage (Ground Rule 3 / GAP_REMEDIATION_PLAN.md). Task P5
# adds structured logging around this WITHOUT removing that "continue to next stage" behavior
# and WITHOUT changing the existing console warning()/message() calls.
#
# Stack-trace capture technique: tryCatch() is an EXITING handler — by the time its `error =`
# function runs, R has already unwound the call stack back to the tryCatch() call itself, so
# sys.calls() inside that handler would only show this function's own frame, not the deeper
# call chain that actually failed. To capture the real call chain, an inner
# withCallingHandlers() (a NON-exiting handler, which runs at the point of the error signal,
# before any unwinding) records sys.calls() into `captured_calls` and then lets the condition
# propagate normally up to the outer tryCatch(), which does the actual logging + fail-safe
# continue.
## Task (wnba_prediction_logger_agent, docs/PREDICTION_LOGGING_PLAN.md, 2026-09-12):
## `call_fn` is a new OPTIONAL third parameter (default NULL) so a single script
## file can be wired into TWO different run_stage() call sites and have a
## DIFFERENT function invoked at each one after sourcing — needed because
## prediction_accuracy_logger.R defines two independent functions
## (reconcile_predictions() / log_todays_predictions()) that must run at two
## different DAG points, but deliberately does not auto-run either one
## unconditionally on source (see that file's header, DEVIATION #3). Default
## NULL preserves every one of the 13 pre-existing run_stage() calls below
## byte-for-byte (they never pass this argument, so behavior is unchanged).
# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md), staleness detector.
# Asserts that every output a stage DECLARES it produces has an mtime at or after that stage's
# own start time. A stage that no-ops (broken auto-run guard), or whose writer silently errored
# inside its own tryCatch, will leave a stale file behind and is reported here instead of being
# indistinguishable from success. WARN, never stop() — Ground Rule 3 / the repo's fail-safe
# principle: report and continue. A 1-second tolerance absorbs filesystem mtime granularity.
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

## PHASE 4 (findings C-2 / M-1), agent_pipeline:
##
## `entry_fn` (new, optional) — the name of the function this stage script auto-runs on source().
##   run_stage() does NOT call it (the script's own `!interactive()` footer does); it asserts the
##   function exists in .GlobalEnv after sourcing and logs a WARN if it does not. The point is to
##   make the DAG's contract VISIBLE HERE rather than buried in each file's last three lines —
##   C-2 happened precisely because that contract was invisible and untested.
##   `entry_fn` and `call_fn` are mutually exclusive: `call_fn` means "this script deliberately
##   does not self-run, invoke it for me", `entry_fn` means "this script self-runs, verify it".
##
## `output` (new, optional) — the cache file(s) this stage is declared to (re)write. After a
##   successful stage, run_stage() asserts each one's mtime advanced to at or after the stage's
##   own start time, and logs a WARN when it did not. This is the review's own suggested single
##   check that would have caught C-2 automatically: four stages logged [COMPLETED] for days while
##   their outputs sat frozen at a four-day-old mtime. Deliberately a WARN and not a stop() — the
##   repo's fail-safe principle is that the pipeline reports and continues; the point is to make
##   the silent failure loud, not to turn it into a crash.
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
  tryCatch({
    withCallingHandlers({
      if (grepl("\\.py$", script_name)) {
        # FINDING M-1: `system(sprintf("python %s", script_name))` discarded the child's exit
        # status entirely, so a Python traceback (missing torch, corrupt CSV, DuckDB lock) fell
        # straight through to the [COMPLETED] branch — the same false-success shape as C-2.
        # system2() with a vector arg list also removes the sprintf-built command string.
        # NOTE for agent_foundation (config.R is not in agent_pipeline's Wave 2 ownership):
        # the interpreter is still resolved from PATH as bare "python". A PYTHON_BIN constant in
        # config.R (defaulting to Sys.which("python"), with a startup check) is the remaining half
        # of M-1 and is logged as a follow-up in this wave's Handoff Notes.
        status <- system2("python", args = script_name)
        if (!is.numeric(status) || length(status) != 1 || is.na(status) || status != 0) {
          stop(sprintf("Python stage %s exited with status %s", script_name, paste(status, collapse = ",")))
        }
      } else {
        source(script_name, local = FALSE)
      }
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
    # UNCHANGED fail-safe behavior: warn on console and let run_full_pipeline.R continue to
    # the next run_stage() call (do NOT stop() / re-throw here).
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    return(FALSE)
  })
}

# ------------------------------------------------------------------------------
# Chronological Execution Sequence
# ------------------------------------------------------------------------------

# 0. Pre-flight Data Integrity Check
# Output: Console report / log entries. Fails if critical caches are corrupt or missing.
# FINDING C-2 (extension found by agent_pipeline, NOT in the review's list of four): this file's
# footer is `if (sys.nframe() == 0)` too, so stage 0 was a FIFTH silent no-op — it defined
# check_cache_health() and returned without running a single check. tools/data_health_probe.R is
# outside agent_pipeline's Wave 2 file ownership, so rather than edit it, the entry point is
# invoked explicitly here via the existing `call_fn` mechanism. Flagged in the Handoff Notes so a
# later wave can align its guard with the other stage scripts.
run_stage("tools/data_health_probe.R", "Run Data Health Probe",
          call_fn = "check_cache_health")

# Optimize Base Cache I/O: Load large, relatively static caches into Global Env once.
# Note: GLOBAL_PLAYER_BOX is static during the pipeline (updated by daily_ingest.R).
if (file.exists(file.path(CACHE_DIR, "player_box_scores_cache.rds"))) {
  GLOBAL_PLAYER_BOX <- readRDS(file.path(CACHE_DIR, "player_box_scores_cache.rds"))
  message(">>> [IO] Loaded player_box_scores_cache.rds into GLOBAL_PLAYER_BOX.")
} else {
  GLOBAL_PLAYER_BOX <- NULL
}

# 1. Official Data Feed & Ingestion
# Output: cache/active_rosters_cache.rds (T1 Handoff Notes: 209 rows x 7 cols, 15 teams)
run_stage("sync_rosters.R", "Sync Active WNBA Rosters (12-Player Cap) & Mid-Season Signings",
          entry_fn = "sync_active_rosters",
          output   = file.path(CACHE_DIR, "active_rosters_cache.rds"))

# Load updated rosters into Global Env for downstream engines.
if (file.exists(file.path(CACHE_DIR, "active_rosters_cache.rds"))) {
  GLOBAL_ACTIVE_ROSTERS <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
  message(">>> [IO] Loaded active_rosters_cache.rds into GLOBAL_ACTIVE_ROSTERS.")
} else {
  GLOBAL_ACTIVE_ROSTERS <- NULL
}

# Output: cache/injury_data_cache.rds (T1 Handoff Notes: 42 rows, data_source column added)
run_stage("injury_scraper.R", "Scrape Official WNBA Injury Scratches & Availability Updates",
          entry_fn = "fetch_live_wnba_injuries",
          output   = CACHE_INJURY_DATA)
# Output: data/team_embeddings.csv, data/team_similarity_matrix.csv (T1b Handoff Notes)
run_stage("team_embeddings.py", "Train Team Style Embeddings & Similarity Matrix (PyTorch)",
          output = c(CACHE_EMBEDDINGS, CACHE_SIMILARITY))

# 1.5. Prediction-Accuracy Logging — Reconciliation
run_stage("prediction_accuracy_logger.R", "Reconcile Pending Model Predictions Against Completed WNBA Games",
          call_fn = "reconcile_predictions")

# ------------------------------------------------------------------------------
# Parallel Execution Setup (Task P3-3.3)
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(future)
  library(future.apply)
})
plan(multisession) # Use background R sessions for parallel stages

# 2. Physics & Biometric Latent Engines (Phase 3) - Parallel Group 1
# These are independent and only depend on the base ingestion.
message("\n>>> [PARALLEL] Launching Latent Engines Group...")
latent_engines <- list(
  list(s = "shot_quality_engine.R", d = "Calculate WNBA Spatial Shot Quality (xeFG%) & Luck",
       f = NULL, o = "cache/team_shot_quality.rds"),
  list(s = "fatigue_travel_engine.R", d = "Compute Haversine Flight Miles & Circadian Drag",
       f = "evaluate_slate_fatigue", o = "cache/travel_fatigue_metrics.rds"),
  list(s = "rapm_engine.R", d = "Estimate Real Possession-Level RAPM (L2 Ridge Regression)",
       f = "estimate_rapm_ratings", o = "cache/rapm_ratings.rds")
)

# Execute in parallel and wait for all to complete.
# FINDING M-7: `future.seed = TRUE` (was absent). Without it future.apply emits "UNRELIABLE
# VALUE: ... unexpectedly generated random numbers without declaring so", and each worker's
# set.seed()-based reproducibility guarantee does not hold — props pricing and Monte Carlo output
# drifted run-to-run for reasons unrelated to code changes. TRUE gives each element a
# statistically sound L'Ecuyer-CMRG stream derived reproducibly from the parent's RNG state.
future_lapply(latent_engines, function(e) {
  run_stage(e$s, e$d, entry_fn = e$f, output = e$o)
}, future.seed = TRUE)

# 3. Microstructure & Player Valuation Engines
# depends on rapm_engine.R
# Output: cache/projected_wnba_standings.rds
run_stage("roster_bottom_up_engine.R", "Generate 15-Team WNBA Bottom-Up Standings & Fair Spreads",
          entry_fn = "project_all_wnba_teams",
          output   = "cache/projected_wnba_standings.rds")

# 4. Market Arbitrage & Limits
# depends on roster_bottom_up_engine.R, shot_quality_engine.R, fatigue_travel_engine.R
# Output: cache/latest_value_bets.rds, cache/odds_history.rds
run_stage("market_odds_engine.R", "Benchmark Live WNBA Books vs Sharp Limits & Kelly Stakes",
          output = file.path(CACHE_DIR, c("latest_value_bets.rds", "odds_history.rds")))

# 4.5. Prediction-Accuracy Logging — Log Today's Predictions
run_stage("prediction_accuracy_logger.R", "Log Today's Real Model Win-Probability Predictions",
          call_fn = "log_todays_predictions")

# 5. Advanced Proposition Distributions - Parallel Group 2
# depends on market_odds_engine.R
message("\n>>> [PARALLEL] Launching Props Engines Group...")
props_engines <- list(
  list(s = "player_props_engine.R", d = "Price ZINB Overdispersed WNBA Player Props",
       f = "generate_active_props_table", o = "data/latest_player_props.rds"),
  list(s = "copula_props_engine.R", d = "Simulate Joint Multivariate Gaussian Copula (PRA / SGPs)",
       f = "run_copula_suite", o = "cache/copula_wilson_pra.rds")
)

# FINDING M-7: future.seed = TRUE — see the latent-engines group above. This is the group the
# review's "UNRELIABLE VALUE" warning ('future_lapply-2') actually came from: both scripts here
# are Monte Carlo (ZINB draws / Gaussian copula simulation).
future_lapply(props_engines, function(e) {
  run_stage(e$s, e$d, entry_fn = e$f, output = e$o)
}, future.seed = TRUE)

# 6. Postseason Simulation
# Output: cache/playoff_series_wnba_demo.rds
run_stage("playoff_simulator.R", "Execute WNBA Playoff Series Monte Carlo (Bo3 First Round / Bo5 Semis / Bo7 Finals)",
          entry_fn = "simulate_playoff_suite",
          output   = "cache/playoff_series_wnba_demo.rds")

# 7. Portfolio Risk Management & Capital Preservation
# Output: cache/risk_state.rds
run_stage("risk_management_engine.R", "Audit Drawdown State & Set Dynamic Kelly Multiplier",
          entry_fn = "compute_risk_state",
          output   = "cache/risk_state.rds")

# 8. Notification & Settlement
# Discord: reads Sys.getenv("DISCORD_WEBHOOK", "") only
run_stage("notify_bets.R", "Dispatch Filtered Discord Webhooks (EV >= 3.0%, CLV >= -0.5%)")
# Output: cache/betting_ledger.rds, cache/rolling_bet_metrics.rds
run_stage("bet_tracker.r", "Grade Previous Completed WNBA Events & Update Rolling CLV%",
          output = file.path(CACHE_DIR, c("betting_ledger.rds", "rolling_bet_metrics.rds")))

# Reset parallel plan to sequential. This also shuts the multisession workers down, so by the
# time the spill merge below runs, no other process holds logs.duckdb.
plan(sequential)

# ------------------------------------------------------------------------------
# FINDING M-7 (pipeline half) — reclaim log rows dropped by DuckDB's single-writer lock
# ------------------------------------------------------------------------------
# agent_foundation's Wave 1 change has logging_utils.R hold ONE DuckDB connection for the process
# lifetime. That removes per-line connection churn, but DuckDB permits exactly one *writing
# process* per file — so while this parent process lives, a future_lapply worker cannot open
# logs.duckdb at all. Wave 1's stopgap was to spill any failed DB write to a per-PID TSV
# (logs/logs_pending_<pid>.tsv, path from LOG_SPILL_FILE()) instead of losing the row, and to hand
# the complementary half to agent_pipeline.
#
# DECISION (agent_pipeline, Phase 4 Wave 2): merge the spill files back here rather than buffering
# rows inside the workers. Rationale:
#   - Buffering in-worker would mean rewriting log_info()/log_warn()/log_error() to return rows
#     instead of writing them, and threading a return channel through run_stage() — that is a
#     change to logging_utils.R, which is not in this wave's file ownership, and it would only
#     cover rows emitted through future_lapply, not the Shiny app or a manually-launched script
#     running alongside the pipeline.
#   - Merging the spill files covers EVERY contending process uniformly, needs no cooperation from
#     the code that logged, and is idempotent (a merged file is deleted; a file that fails to
#     merge is left on disk for the next run to retry, so nothing is ever lost).
#   - It runs after plan(sequential), i.e. after the workers are gone, so the lock is free.
# The parent's own spill file is skipped: if the parent spilled, the DB is unavailable to it too,
# and the rows stay on disk for the next run.
merge_worker_log_spills <- function() {
  spill_files <- list.files(LOG_DIR, pattern = "^logs_pending_[0-9]+\\.tsv$", full.names = TRUE)
  spill_files <- setdiff(spill_files, LOG_SPILL_FILE())  # parent's own: leave for next run
  if (length(spill_files) == 0) {
    message(">>> [LOG MERGE] No worker log spill files to merge.")
    return(invisible(0L))
  }
  merged <- 0L
  for (f in spill_files) {
    ok <- tryCatch({
      rows <- utils::read.delim(f, header = FALSE, sep = "\t", quote = "",
                                stringsAsFactors = FALSE, col.names =
                                  c("timestamp", "level", "script", "message", "extra_json"),
                                colClasses = "character")
      if (nrow(rows) > 0) {
        con <- .log_get_con()
        DBI::dbExecute(con, "INSERT INTO logs (timestamp, level, script, message, extra_json) VALUES (?, ?, ?, ?, ?)",
                       params = list(as.POSIXct(rows$timestamp, tz = ""), rows$level,
                                     rows$script, rows$message, rows$extra_json))
      }
      merged <- merged + nrow(rows)
      TRUE
    }, error = function(e) {
      message(sprintf(">>> [LOG MERGE] Failed to merge %s (left on disk for the next run): %s",
                      basename(f), conditionMessage(e)))
      FALSE
    })
    if (isTRUE(ok)) unlink(f)   # only delete once the rows are safely in the table
  }
  message(sprintf(">>> [LOG MERGE] Merged %d spilled log row(s) from %d worker file(s) into logs.duckdb.",
                  merged, length(spill_files)))
  log_info(sprintf("Merged %d spilled worker log rows into logs.duckdb (M-7).", merged),
           script = "run_full_pipeline.R", spill_files = length(spill_files))
  invisible(merged)
}
# Fail-safe: a logging-maintenance failure must never take the pipeline down.
tryCatch(merge_worker_log_spills(),
         error = function(e) message(sprintf(">>> [LOG MERGE] Skipped: %s", conditionMessage(e))))

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL WNBA PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
log_info(sprintf("Pipeline run finished in %.2f seconds.", pipeline_total_time), script = "run_full_pipeline.R")
