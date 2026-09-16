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
run_stage <- function(script_name, description, call_fn = NULL) {
  message(sprintf("\n>>> [STAGE] %s (%s)...", description, script_name))
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
        system(sprintf("python %s", script_name))
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
run_stage("tools/data_health_probe.R", "Run Data Health Probe")

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
run_stage("sync_rosters.R", "Sync Active WNBA Rosters (12-Player Cap) & Mid-Season Signings")

# Load updated rosters into Global Env for downstream engines.
if (file.exists(file.path(CACHE_DIR, "active_rosters_cache.rds"))) {
  GLOBAL_ACTIVE_ROSTERS <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
  message(">>> [IO] Loaded active_rosters_cache.rds into GLOBAL_ACTIVE_ROSTERS.")
} else {
  GLOBAL_ACTIVE_ROSTERS <- NULL
}

# Output: cache/injury_data_cache.rds (T1 Handoff Notes: 42 rows, data_source column added)
run_stage("injury_scraper.R", "Scrape Official WNBA Injury Scratches & Availability Updates")
# Output: data/team_embeddings.csv, data/team_similarity_matrix.csv (T1b Handoff Notes)
run_stage("team_embeddings.py", "Train Team Style Embeddings & Similarity Matrix (PyTorch)")

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
  list(s = "shot_quality_engine.R", d = "Calculate WNBA Spatial Shot Quality (xeFG%) & Luck"),
  list(s = "fatigue_travel_engine.R", d = "Compute Haversine Flight Miles & Circadian Drag"),
  list(s = "rapm_engine.R", d = "Estimate Real Possession-Level RAPM (L2 Ridge Regression)")
)

# Execute in parallel and wait for all to complete
future_lapply(latent_engines, function(e) {
  run_stage(e$s, e$d)
})

# 3. Microstructure & Player Valuation Engines
# depends on rapm_engine.R
# Output: cache/projected_wnba_standings.rds
run_stage("roster_bottom_up_engine.R", "Generate 15-Team WNBA Bottom-Up Standings & Fair Spreads")

# 4. Market Arbitrage & Limits
# depends on roster_bottom_up_engine.R, shot_quality_engine.R, fatigue_travel_engine.R
# Output: cache/latest_value_bets.rds, cache/odds_history.rds
run_stage("market_odds_engine.R", "Benchmark Live WNBA Books vs Sharp Limits & Kelly Stakes")

# 4.5. Prediction-Accuracy Logging — Log Today's Predictions
run_stage("prediction_accuracy_logger.R", "Log Today's Real Model Win-Probability Predictions",
          call_fn = "log_todays_predictions")

# 5. Advanced Proposition Distributions - Parallel Group 2
# depends on market_odds_engine.R
message("\n>>> [PARALLEL] Launching Props Engines Group...")
props_engines <- list(
  list(s = "player_props_engine.R", d = "Price ZINB Overdispersed WNBA Player Props"),
  list(s = "copula_props_engine.R", d = "Simulate Joint Multivariate Gaussian Copula (PRA / SGPs)")
)

future_lapply(props_engines, function(e) {
  run_stage(e$s, e$d)
})

# 6. Postseason Simulation
# Output: cache/playoff_series_wnba_demo.rds
run_stage("playoff_simulator.R", "Execute WNBA Playoff Series Monte Carlo (Bo3 First Round / Bo5 Semis / Bo7 Finals)")

# 7. Portfolio Risk Management & Capital Preservation
# Output: cache/risk_state.rds
run_stage("risk_management_engine.R", "Audit Drawdown State & Set Dynamic Kelly Multiplier")

# 8. Notification & Settlement
# Discord: reads Sys.getenv("DISCORD_WEBHOOK", "") only
run_stage("notify_bets.R", "Dispatch Filtered Discord Webhooks (EV >= 3.0%, CLV >= -0.5%)")
# Output: cache/betting_ledger.rds, cache/rolling_bet_metrics.rds
run_stage("bet_tracker.r", "Grade Previous Completed WNBA Events & Update Rolling CLV%")

# Reset parallel plan to sequential
plan(sequential)

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL WNBA PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
log_info(sprintf("Pipeline run finished in %.2f seconds.", pipeline_total_time), script = "run_full_pipeline.R")
