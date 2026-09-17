# ==============================================================================
# run_full_pipeline.R
# NFL Analytics Pipeline Orchestrator — Wave 1 Skeleton
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/run_full_pipeline.R
#
# Task P1-D (nfl_pipeline_skeleton_agent, docs/task_assignments_phase0.md). Per that file's
# Constraints section, this is deliberately a SKELETON sized to the three real Wave-1 ingestion
# stages (daily_ingest.R / sync_rosters.R / injury_scraper.R) — not a full later-phase DAG with
# stub stages bolted on for engines that don't exist yet (metrics/ratings/fatigue/embeddings/
# market/props/risk/notify per docs/NFL_REPLICATION_PLAN.md §1). Adding a fake run_stage() call
# for a script that doesn't exist would immediately fail with "script not found" — see the
# extension point comment near the bottom instead.
#
# `run_stage()` itself (including the C-2 `.check_stage_output()` staleness assertion and the
# withCallingHandlers/tryCatch stack-trace capture) is copied essentially verbatim from the WNBA
# Analytics sibling repo's run_full_pipeline.R — that is proven, hardened, sport-agnostic
# infrastructure, not something to rewrite from scratch here.
#
# All three Wave-1 scripts in THIS repo use the `call_fn` contract, never `entry_fn`: none of
# daily_ingest.R / sync_rosters.R / injury_scraper.R has a `sys.nframe() == 0` (or
# `!interactive()`) auto-run footer — per CLAUDE.md's "Process / conventions" section and
# docs/NFL_REPLICATION_PLAN.md §1, that guard class silently no-ops under source() while still
# reporting success (the exact bug the WNBA repo hit). Each of these three scripts instead
# exposes exactly one callable (run_daily_ingest() / run_sync_rosters() / run_injury_scraper(),
# per docs/task_assignments_phase0.md's Interface Contracts table) that this orchestrator must
# invoke explicitly — `entry_fn` (which only verifies a self-run function exists, never calls it)
# would leave every stage a no-op here.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

# Sourced before anything else so every stage's source()'d script can also call
# log_info()/log_warn()/log_error() if it has been wired to do so.
source("logging_utils.R")
# FINDING M-2 (docs/SECURITY_TECHNICAL_REVIEW.md, WNBA Analytics repo — same rationale applies
# here): an orchestrator that uses CACHE_DIR/CACHE_*-style constants without sourcing config.R
# itself only "works" if some other stage's script happens to source config.R first and leak the
# constants into .GlobalEnv as a side effect (run_stage() sources with local = FALSE). Since
# run_stage() deliberately swallows a stage failure and continues, a failing early stage would
# leave those constants undefined and kill the pipeline at top level, OUTSIDE any run_stage()
# protection — the fail-safe inverted. Constants are therefore an explicit dependency of the
# orchestrator, sourced here rather than relied upon as a side effect of a later source() call.
source("config.R")
.LOG_SCRIPT <- "run_full_pipeline.R"

pipeline_start_time <- Sys.time()
message("==================================================================")
message(sprintf(">>> NFL QUANTITATIVE ENGINE STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
message("==================================================================")
log_info(sprintf("Pipeline run started."), script = "run_full_pipeline.R")

# run_stage() — fail-safe design ported from the WNBA Analytics repo: any stage script's error is
# caught, logged, and the pipeline continues to the next stage rather than aborting.
#
# Stack-trace capture technique: tryCatch() is an EXITING handler — by the time its `error =`
# function runs, R has already unwound the call stack back to the tryCatch() call itself, so
# sys.calls() inside that handler would only show this function's own frame, not the deeper
# call chain that actually failed. To capture the real call chain, an inner
# withCallingHandlers() (a NON-exiting handler, which runs at the point of the error signal,
# before any unwinding) records sys.calls() into `captured_calls` and then lets the condition
# propagate normally up to the outer tryCatch(), which does the actual logging + fail-safe
# continue.
#
# `call_fn` (optional) — the name of a function to invoke in .GlobalEnv after sourcing the stage
#   script. Used when the script deliberately does NOT auto-run on source() (this repo's
#   convention for all Wave-1 scripts — see header comment above).
# `entry_fn` (optional, mutually exclusive with call_fn) — the name of a function the stage
#   script is expected to auto-run itself on source(). run_stage() does NOT call it; it only
#   asserts the function exists in .GlobalEnv afterward and logs a WARN if it does not. Not used
#   by any stage in this skeleton (see above), kept for parity with the WNBA original's contract
#   so a future stage script that DOES self-run can opt into it without changing run_stage().
#
# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md, WNBA Analytics repo), staleness detector.
# Asserts that every output a stage DECLARES it produces has an mtime at or after that stage's
# own start time. A stage that no-ops (broken auto-run guard), or whose writer silently errored
# inside its own tryCatch, will leave a stale file behind and is reported here instead of being
# indistinguishable from success. WARN, never stop() — the repo's fail-safe principle is that the
# pipeline reports and continues. A 1-second tolerance absorbs filesystem mtime granularity.
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
  tryCatch({
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
    # Fail-safe behavior: warn on console and let run_full_pipeline.R continue to the next
    # run_stage() call (do NOT stop() / re-throw here).
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    return(FALSE)
  })
}

# ------------------------------------------------------------------------------
# Chronological Execution Sequence — Wave 1 (real ingestion stages only)
# ------------------------------------------------------------------------------
# Order: schedules/PBP ingestion, then rosters, then injuries. Nothing in this skeleton
# programmatically enforces the dependency, but injuries logically follow rosters (knowing which
# players/teams currently exist is a more natural precondition for an injury report than the
# reverse), and both follow the core schedule/PBP ingest that everything else in the eventual DAG
# will build on.

# 1. Play-by-play & schedule ingestion.
# Writes CACHE_PBP and CACHE_SCHEDULES (config.R) — two outputs from one stage, declared together
# per the WNBA repo's market_odds_engine.R multi-output-stage precedent.
run_stage("daily_ingest.R", "Ingest NFL Play-by-Play & Schedule Data (nflreadr)",
          call_fn = "run_daily_ingest",
          output   = c(CACHE_PBP, CACHE_SCHEDULES))

# 2. Roster synchronization.
# Writes CACHE_ROSTERS (config.R).
run_stage("sync_rosters.R", "Sync NFL Rosters (nflreadr::load_rosters)",
          call_fn = "run_sync_rosters",
          output   = CACHE_ROSTERS)

# 3. Injury report ingestion.
# Writes CACHE_INJURY_DATA (config.R). Placed after rosters (see ordering note above).
run_stage("injury_scraper.R", "Scrape NFL Injury Reports (nflreadr primary + ESPN live secondary)",
          call_fn = "run_injury_scraper",
          output   = CACHE_INJURY_DATA)

# 4. EPA/CPOE metrics engine (Phase 2, task P2-A).
# Writes CACHE_EPA_METRICS (config.R). Reads CACHE_PBP from stage 1 above.
run_stage("epa_metrics_engine.R", "Compute Rolling Team EPA/CPOE Metrics",
          call_fn = "run_epa_metrics",
          output   = CACHE_EPA_METRICS)

# 5. Team ratings & projected-matchup engine (Phase 2, task P2-B).
# Writes CACHE_TEAM_RATINGS and CACHE_PROJECTED_MATCHUPS (config.R) — two outputs from one stage,
# declared together per the daily_ingest.R stage's multi-output precedent above.
run_stage("team_ratings_engine.R", "Compute Team Power Ratings & Projected Matchups",
          call_fn = "run_team_ratings",
          output   = c(CACHE_TEAM_RATINGS, CACHE_PROJECTED_MATCHUPS))

# ------------------------------------------------------------------------------
# FUTURE STAGES — extension point, not yet implemented (see docs/task_assignments_phase0.md's
# Constraints section and docs/NFL_REPLICATION_PLAN.md §1's later-phase list). Per that
# Constraints note, this wave deliberately does NOT add stub run_stage() calls for scripts that
# don't exist yet — doing so would immediately fail with "script not found". A later wave should
# insert its own run_stage() calls HERE, in roughly this order, as each script is actually built:
#   fatigue/travel & embeddings -> market/props pricing (requires a human-provisioned Odds API
#   key, per REPLICATION_PLAN §2) -> risk management -> notification/settlement -> live/dashboard.
# ------------------------------------------------------------------------------

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL NFL PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
log_info(sprintf("Pipeline run finished in %.2f seconds.", pipeline_total_time), script = "run_full_pipeline.R")
