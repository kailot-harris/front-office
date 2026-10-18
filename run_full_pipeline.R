# ==============================================================================
# run_full_pipeline.R — MLB Analytics Pipeline Orchestrator (Phase 1 Skeleton)
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/run_full_pipeline.R
#
# Orchestrates the staged execution of the MLB quantitative analytics pipeline.
#
# Architectural principles (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 / Issue #14):
#   - Fail-safe execution: Each stage script runs wrapped in `run_stage()` with
#     inner withCallingHandlers() for deep stack-trace capture and outer tryCatch()
#     to ensure a failure in one stage logs cleanly without crashing subsequent stages.
#   - Output staleness assertion (C-2): Verifies declared stage cache outputs exist
#     and were updated on or after the stage start time, catching silent no-ops.
#   - Single source of truth: All cache paths and configurations are derived directly
#     from config.R via cache_path().
#   - Explicit invocation: Scripts expose exactly one callable runner function
#     invoked via `call_fn` (no fragile `sys.nframe() == 0` auto-run guards).
#   - Extensible DAG structure: Clean extension points for Phase 2+ stages
#     (ratings, fatigue, projections, market odds, risk management, Discord alerts).
# ==============================================================================

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else "c:/Users/kailo/kayceeslices/MLB Analytics"
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

# Sourced first so logging and single-source-of-truth constants are always live
source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "run_full_pipeline.R"

# Stage tracking registry
.pipeline_stages_run <- list()

#' Staleness & Existence Validator for Declared Stage Outputs (C-2)
#'
#' @param script_name Name of the stage script
#' @param description Stage description
#' @param output Vector of expected output file paths
#' @param start POSIXct timestamp when the stage began
#' @param require_fresh Logical; if TRUE, warns if output was not updated during stage run
.check_stage_output <- function(script_name, description, output, start, require_fresh = FALSE) {
  if (is.null(output) || length(output) == 0) return(invisible(NULL))
  for (path in output) {
    if (!file.exists(path)) {
      message(sprintf(">>> [WARN] %s: declared output %s does not exist after stage ran.",
                      script_name, path))
      log_warn(sprintf("Declared stage output missing: %s", path),
               script = .LOG_SCRIPT, stage = script_name,
               description = description, output = path)
      next
    }
    mt <- tryCatch(file.info(path)$mtime, error = function(e) NA)
    if (length(mt) != 1 || is.na(mt)) next
    if (require_fresh && as.numeric(difftime(mt, start, units = "secs")) < -1) {
      age_h <- as.numeric(difftime(Sys.time(), mt, units = "hours"))
      message(sprintf(
        ">>> [WARN] %s reported success but declared output %s was NOT rewritten (mtime %s, %.1f hours old). Possible silent no-op.",
        script_name, basename(path), format(mt, "%Y-%m-%d %H:%M:%S"), age_h))
      log_warn(sprintf("Stale stage output (possible silent no-op): %s", path),
               script = .LOG_SCRIPT, stage = script_name, description = description,
               output = path, output_mtime = format(mt, "%Y-%m-%d %H:%M:%S"),
               stage_start = format(start, "%Y-%m-%d %H:%M:%S"),
               hours_stale = round(age_h, 2))
    } else {
      status_tag <- if (as.numeric(difftime(mt, start, units = "secs")) >= -1) "FRESH" else "CACHED"
      message(sprintf(">>> [%s] %s -> %s (mtime %s)", status_tag, script_name, basename(path),
                      format(mt, "%Y-%m-%d %H:%M:%S")))
    }
  }
  invisible(NULL)
}

#' Run a Single Pipeline Stage with Fail-Safe Try/Catch and Deep Stack-Trace Capture
#'
#' @param script_name Filename of the stage script to source
#' @param description Human-readable description of the stage
#' @param call_fn Name of the function to invoke in .GlobalEnv after sourcing
#' @param output Vector of declared output file paths to validate
#' @param require_fresh If TRUE, requires outputs to be rewritten during this run
#' @param ... Optional arguments passed to call_fn
#' @return Logical TRUE if stage succeeded, FALSE if it failed
run_stage <- function(script_name, description, call_fn = NULL, output = NULL, require_fresh = FALSE, ...) {
  message(sprintf("\n>>> [STAGE] %s (%s)...", description, script_name))
  
  if (!file.exists(script_name)) {
    warning(sprintf("Script %s not found in working directory. Skipping.", script_name))
    log_warn(sprintf("Stage script not found, skipping: %s", script_name),
             script = .LOG_SCRIPT, stage = script_name, description = description)
    .pipeline_stages_run[[length(.pipeline_stages_run) + 1]] <<- list(
      stage = script_name, desc = description, status = "SKIPPED", elapsed = 0
    )
    return(FALSE)
  }
  
  start <- Sys.time()
  captured_calls <- NULL
  fn_args <- list(...)
  
  result <- tryCatch({
    withCallingHandlers({
      source(script_name, local = FALSE)
      
      if (!is.null(call_fn)) {
        if (exists(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
          fn <- get(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)
          if (length(fn_args) > 0) {
            do.call(fn, fn_args)
          } else {
            fn()
          }
        } else {
          warning(sprintf("call_fn '%s' not found as a function after sourcing %s.", call_fn, script_name))
        }
      }
      
      # Validate declared outputs
      .check_stage_output(script_name, description, output, start, require_fresh = require_fresh)
      
      elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
      message(sprintf(">>> [COMPLETED] %s in %.2f seconds.", script_name, elapsed))
      log_info(sprintf("Stage completed: %s", script_name), script = .LOG_SCRIPT,
               stage = script_name, description = description, elapsed_sec = round(elapsed, 2))
      
      .pipeline_stages_run[[length(.pipeline_stages_run) + 1]] <<- list(
        stage = script_name, desc = description, status = "OK", elapsed = elapsed
      )
      TRUE
    }, error = function(e) {
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
    
    elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
    log_error(
      sprintf("Stage failed: %s (%s)", script_name, description),
      condition = e,
      script = .LOG_SCRIPT,
      stage = script_name,
      stack_trace = stack_trace
    )
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    
    .pipeline_stages_run[[length(.pipeline_stages_run) + 1]] <<- list(
      stage = script_name, desc = description, status = "FAILED", elapsed = elapsed
    )
    FALSE
  })
  
  # Force garbage collection between stages to keep memory bounded
  gc(verbose = FALSE)
  
  result
}

#' Run the Complete MLB Analytics Pipeline
#'
#' @param season Current season integer (defaults to 2024 or current year)
#' @param force_refresh If TRUE, forces re-fetching all data stages bypassing caches
#' @return A summary data.frame of all stage runs and their statuses
run_full_pipeline <- function(season = 2024, force_refresh = FALSE) {
  pipeline_start_time <- Sys.time()
  .pipeline_stages_run <<- list()
  
  message("==================================================================")
  message(sprintf(">>> MLB QUANTITATIVE ENGINE STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
  message(sprintf(">>> Season: %d | Force Refresh: %s", season, force_refresh))
  message("==================================================================")
  log_info(sprintf("Pipeline run started (season=%d, force_refresh=%s).", season, force_refresh),
           script = .LOG_SCRIPT)
  
  # ----------------------------------------------------------------------------
  # Stage 1: Official Game Schedules & Box Scores (MLB Stats API + Statcast)
  # ----------------------------------------------------------------------------
  run_stage(
    script_name   = "mlb_ingest.R",
    description   = "Ingest MLB Schedules, Box Scores & Statcast Pitches",
    call_fn       = "run_mlb_ingest",
    output        = c(
      cache_path("ingest", sprintf("mlb_schedule_%d.rds", season), create = FALSE),
      cache_path("ingest", sprintf("mlb_boxscores_%d.rds", season), create = FALSE)
    ),
    require_fresh = force_refresh,
    season        = season,
    force_refresh = force_refresh
  )
  
  # ----------------------------------------------------------------------------
  # Stage 2: FanGraphs Advanced Metrics & Park Factors Sync
  # ----------------------------------------------------------------------------
  run_stage(
    script_name   = "mlb_stats_sync.R",
    description   = "Sync FanGraphs Batter/Pitcher Leaders & Park Factors",
    call_fn       = "run_stats_sync",
    output        = c(
      cache_path("stats_sync", "fg_batters.rds", create = FALSE),
      cache_path("stats_sync", "fg_pitchers.rds", create = FALSE),
      cache_path("stats_sync", "fg_park.rds", create = FALSE)
    ),
    require_fresh = force_refresh,
    seasons       = c(season),
    force_refresh = force_refresh
  )
  
  # ----------------------------------------------------------------------------
  # Stage 3: ESPN MLB Injury Feed Scraper
  # ----------------------------------------------------------------------------
  run_stage(
    script_name   = "mlb_injury_scraper.R",
    description   = "Scrape ESPN MLB Injuries (with Player-Card ID Parsing)",
    call_fn       = "run_injury_scraper",
    output        = cache_path("injury", "mlb_injuries.rds", create = FALSE),
    require_fresh = force_refresh,
    force_refresh = force_refresh
  )
  
  # ----------------------------------------------------------------------------
  # Stage 4: Cross-Vendor Master Player-ID Crosswalk
  # ----------------------------------------------------------------------------
  run_stage(
    script_name   = "mlb_id_crosswalk.R",
    description   = "Build/Update 5-Way Player ID Crosswalk (MLBAM/FG/BRef/Retro/ESPN)",
    call_fn       = "run_id_crosswalk",
    output        = cache_path("id_crosswalk", "mlb_id_crosswalk.rds", create = FALSE),
    require_fresh = force_refresh,
    force_refresh = force_refresh
  )
  
  # ----------------------------------------------------------------------------
  # EXTENSION POINTS: Future Phase 2+ Pipeline Stages
  # ----------------------------------------------------------------------------
  # Phase 2: Rating Engine
  #   - run_stage("mlb_pythag_baseline.R", "Pythagorean Win Expectation Baseline", ...)
  #   - run_stage("mlb_elo_engine.R", "MLB Elo Rating Engine (w/ Pitcher Adjustment)", ...)
  # Phase 3: Specialty Models
  #   - run_stage("mlb_bullpen_fatigue.R", "Bullpen Usage & High-Leverage Fatigue Engine", ...)
  #   - run_stage("mlb_marcel_projections.R", "Marcel Baseline Projections", ...)
  # Phase 4: Postseason Bracket Simulator
  #   - run_stage("mlb_playoff_simulator.R", "Postseason Monte Carlo Bracket Simulator", ...)
  # Phase 5: Risk Management Engine
  #   - run_stage("mlb_risk_management.R", "Bankroll Drawdown & Kelly Sizing Engine", ...)
  # Phase 6: Market Odds Engine
  #   - run_stage("mlb_market_odds.R", "Fetch Live Odds & Identify +EV Value Bets", ...)
  # Phase 7: Discord Alert Dispatcher
  #   - run_stage("mlb_notify_bets.R", "Dispatch Value Bet & Line Movement Alerts", ...)
  # ----------------------------------------------------------------------------
  
  pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
  
  # Build execution summary
  summary_df <- if (length(.pipeline_stages_run) > 0) {
    dplyr::bind_rows(lapply(.pipeline_stages_run, as.data.frame))
  } else {
    data.frame(stage = character(), desc = character(), status = character(), elapsed = numeric())
  }
  
  message("\n==================================================================")
  message(sprintf(">>> FULL MLB PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
  message("------------------------------------------------------------------")
  for (i in seq_len(nrow(summary_df))) {
    message(sprintf("  [%s] %-25s : %-40s (%.2fs)",
                    summary_df$status[i], summary_df$stage[i], summary_df$desc[i], summary_df$elapsed[i]))
  }
  message("==================================================================")
  
  log_info(
    sprintf("Pipeline run finished in %.2f seconds (%d/%d stages succeeded).",
            pipeline_total_time, sum(summary_df$status == "OK"), nrow(summary_df)),
    script = .LOG_SCRIPT,
    total_elapsed = round(pipeline_total_time, 2),
    stages_ok = sum(summary_df$status == "OK"),
    stages_total = nrow(summary_df)
  )
  
  invisible(summary_df)
}

# Auto-run if executed directly via Rscript run_full_pipeline.R
if (sys.nframe() == 0) {
  run_full_pipeline()
}
