# ==============================================================================
# run_full_pipeline.R (WNBA port)
# Master Production Quantitative Pipeline (Phases 1 through 5) — WNBA Edition
# Path: run_full_pipeline.R
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

PROJECT_DIR <- here::here()   # issue #90: derived portably; never hardcode the repo root
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
# Issue #45 (Slice 1 of #43): stage metadata (script/description/call_fn|entry_fn/output, plus
# the new declared `inputs` field) now lives in pipeline_stages.R's PIPELINE_STAGES registry
# instead of being hardcoded at each run_stage() call site below. Sourced after config.R
# because several registry entries reference config.R's CACHE_* constants directly so they
# resolve to the same real paths the pre-refactor call sites used.
source("pipeline_stages.R")
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

# Issue #45: thin wrapper that looks a stage up in PIPELINE_STAGES (pipeline_stages.R) by id
# and calls run_stage() with exactly the fields that registry entry carries -- replaces the
# old pattern of hardcoding script/description/call_fn/entry_fn/output at each call site.
run_registered_stage <- function(id) {
  stage <- get_pipeline_stage(id)
  run_stage(stage$script, stage$description, call_fn = stage$call_fn, entry_fn = stage$entry_fn,
            output = stage$output)
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
run_registered_stage("data_health_probe")

# 0.5. Box-Score Ingestion
# FINDING L-4 (docs/SECURITY_TECHNICAL_REVIEW.md), coordinated with agent_props (P4-E):
# daily_ingest.R was never a DAG stage. Box-score ingestion happened only as an implicit side
# effect of prediction_accuracy_logger.R sourcing daily_ingest.R — an invisible dependency that
# ran the ingest at an arbitrary point in the DAG for reasons unrelated to ingestion.
# agent_props removed that side effect in this same wave, so the ingest now needs its own
# explicit stage here or it does not run AT ALL (every downstream engine would quietly consume a
# frozen data/box_scores_cache.rds — the C-2 failure mode again, one layer up).
# Placed after the health probe (so a corrupt cache is reported first) and before the IO block
# below, which loads the caches this stage refreshes.
#
# TWO DELIBERATE CHOICES, both per agent_props' spec — do not "tidy" either one:
#  1. `call_fn`, NOT `entry_fn`. daily_ingest.R's own footer guard is `sys.nframe() == 0`, which
#     stays dormant under run_stage()'s source(). That is CORRECT here and is deliberately NOT
#     swept into this wave's C-2 `!interactive()` migration: the guard firing on source AND this
#     call_fn invoking the function would double-ingest.
#  2. NO `output =` declaration, even though this stage owns CACHE_TEAM_BOX. daily_box_ingest()
#     legitimately skips the write when there are no new games ("Team box cache already up to
#     date; no write necessary", daily_ingest.R:124), so asserting freshness here would fire a
#     false staleness WARN on every quiet day and train the operator to ignore the check.
run_registered_stage("daily_ingest")

# Optimize Base Cache I/O: Load large, relatively static caches into Global Env once.
# Note: GLOBAL_PLAYER_BOX is static during the pipeline (updated by daily_ingest.R).
if (file.exists(file.path(CACHE_DIR, "player_box_scores_cache.rds"))) {
  GLOBAL_PLAYER_BOX <- readRDS(file.path(CACHE_DIR, "player_box_scores_cache.rds"))
  message(">>> [IO] Loaded player_box_scores_cache.rds into GLOBAL_PLAYER_BOX.")
} else {
  GLOBAL_PLAYER_BOX <- NULL
}

# 0.7. Player Team-Game Features (BPM / minutes-concentration) — Tier 1 fix (2026-09-17).
# config.R has declared CACHE_FEATURES ("cache/features_cache.rds") since Phase 0, and
# tools/data_health_probe.R has checked for it the whole time, but no stage ever produced
# it — player_metrics.R::get_player_features() was fully implemented and real-data-backed
# from the start, just never wired into this DAG. Three separate remediation waves
# (docs/task_assignments_phase4.md) flagged the resulting "cache/features_cache.rds
# missing" health-probe warning as "pre-existing and unrelated" without tracing it this
# far. `call_fn`, not `entry_fn`: player_metrics.R is deliberately side-effect-free on a
# bare source() (roster_bottom_up_engine.R already sources it below purely for its
# function definitions, and must not trigger a recompute as a side effect of that).
# Placed here (not earlier) because its only real dependency is CACHE_PLAYER_BOX, just
# loaded above.
run_registered_stage("player_metrics")

# 1. Official Data Feed & Ingestion
# Output: cache/active_rosters_cache.rds (T1 Handoff Notes: 209 rows x 7 cols, 15 teams)
run_registered_stage("sync_rosters")

# Load updated rosters into Global Env for downstream engines.
if (file.exists(file.path(CACHE_DIR, "active_rosters_cache.rds"))) {
  GLOBAL_ACTIVE_ROSTERS <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
  message(">>> [IO] Loaded active_rosters_cache.rds into GLOBAL_ACTIVE_ROSTERS.")
} else {
  GLOBAL_ACTIVE_ROSTERS <- NULL
}

# Output: cache/injury_data_cache.rds (T1 Handoff Notes: 42 rows, data_source column added)
run_registered_stage("injury_scraper")
# Output: logs/analytics.duckdb (tables `team_embeddings` + `team_similarity`), PLUS
# data/team_embeddings.csv + data/team_similarity_matrix.csv (config.R's CACHE_EMBEDDINGS /
# CACHE_SIMILARITY). CORRECTED IN PHASE 4 (agent_pipeline): this comment used to warn that the two
# CSVs were stale artifacts nothing in the DAG refreshed (team_embeddings.py only wrote duckdb).
# RE-CORRECTED 2026-09-17 (orphaned-cache-audit skill run): team_embeddings.py's save_to_db() now
# writes both CSVs again, additively alongside duckdb — load_embeddings.R and
# tools/ml_cv_benchmark.R still read the CSVs and app.R's wide-shape fallback path still expects
# them, so retiring the CSVs instead of restoring their producer would have broken real consumers.
run_registered_stage("team_embeddings")

# 1.5. Prediction-Accuracy Logging — Reconciliation
run_registered_stage("prediction_accuracy_logger_reconcile")

# ------------------------------------------------------------------------------
# Parallel Execution Setup (Task P3-3.3)
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(future)
  library(future.apply)
})

# MEMORY-ADAPTIVE PLAN SELECTION (2026-09-17): a real run on this machine was OOM-killed by the
# OS twice in the "Latent Engines Group" below, BEFORE reaching any live-API stage — each
# `multisession` element is a full separate R process (its own package loads, no memory sharing
# with the parent), and this machine's actual free RAM at run time (checked here, not assumed)
# can be well below what 3 concurrent worker processes need, e.g. when a normal interactive
# Chrome session with many tabs is also open (confirmed present during the kill: ~40 chrome.exe
# processes, ~2.3GB, ordinary browser tabs — not anything this pipeline launched or should ever
# touch/kill). Rather than hardcoding `plan(sequential)` (which would needlessly slow down every
# future run, including the scheduled nightly one in schedule_daily.bat where this contention
# likely won't exist), check real available memory and degrade gracefully, same fail-safe
# philosophy as the rest of this repo (check response validity, fall back, never hard-crash).
# Windows-only check (this repo only runs on Windows per CLAUDE.md); any failure to determine
# free memory conservatively assumes low memory and falls back to sequential.
MIN_FREE_MB_FOR_PARALLEL <- 4096
get_free_memory_mb <- function() {
  tryCatch({
    out <- system2("powershell.exe", c("-NoProfile", "-Command",
      "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"), stdout = TRUE)
    as.numeric(trimws(out[length(out)])) / 1024  # FreePhysicalMemory is in KB
  }, error = function(e) NA_real_)
}
free_mb <- get_free_memory_mb()
if (is.na(free_mb) || free_mb < MIN_FREE_MB_FOR_PARALLEL) {
  message(sprintf(">>> [MEMORY] Free RAM %s below the %dMB parallel-safety threshold (or undetectable) — using plan(sequential) for this run to avoid an OOM kill. See run_full_pipeline.R's 2026-09-17 comment for why.",
                  if (is.na(free_mb)) "UNKNOWN" else sprintf("%.0fMB", free_mb), MIN_FREE_MB_FOR_PARALLEL))
  plan(sequential)
} else {
  message(sprintf(">>> [MEMORY] Free RAM %.0fMB clears the %dMB threshold — using plan(multisession) as normal.",
                  free_mb, MIN_FREE_MB_FOR_PARALLEL))
  plan(multisession) # Use background R sessions for parallel stages
}

# 2. Physics & Biometric Latent Engines (Phase 3) - Parallel Group 1
# These are independent and only depend on the base ingestion.
message("\n>>> [PARALLEL] Launching Latent Engines Group...")
# Issue #45: group membership (shot_quality_engine.R / fatigue_travel_engine.R /
# rapm_engine.R) now comes from pipeline_stages.R's PIPELINE_STAGES registry (each entry's
# group = "latent_engines") instead of this inline list literal.
latent_engines <- get_pipeline_stage_group("latent_engines")

# Execute in parallel and wait for all to complete.
# FINDING M-7: `future.seed = TRUE` (was absent). Without it future.apply emits "UNRELIABLE
# VALUE: ... unexpectedly generated random numbers without declaring so", and each worker's
# set.seed()-based reproducibility guarantee does not hold — props pricing and Monte Carlo output
# drifted run-to-run for reasons unrelated to code changes. TRUE gives each element a
# statistically sound L'Ecuyer-CMRG stream derived reproducibly from the parent's RNG state.
future_lapply(latent_engines, function(e) {
  run_stage(e$script, e$description, call_fn = e$call_fn, entry_fn = e$entry_fn, output = e$output)
}, future.seed = TRUE)

# 2.5. Play-by-Play Player Features (pbp_engine.R) - deliberately SEQUENTIAL, not folded into
# the future.apply "Latent Engines" group above. Empirically this machine OOM-killed the whole
# pipeline the first time it ran here: each future_lapply `multisession` element is a SEPARATE
# full R process (its own package loads, no memory sharing with the parent or siblings), and
# pbp_engine.R's own working set (cache/wnba_espn_pbp_cache.rds, 763k rows / ~30MB on disk,
# considerably larger deserialized) pushed 4 concurrent worker processes over this machine's
# available RAM (16GB total, ~5GB free once the other 3 engines' own caches were also loaded).
# Nothing in the parallel group above depends on pbp_engine.R, and its only real consumer
# (player_props_engine.R, in the LATER "Props Engines Group") doesn't run for a while yet, so
# running it here sequentially costs wall-clock time, not correctness, and keeps peak
# concurrent memory back down at the original 3-worker footprint.
run_registered_stage("pbp_engine")

# 3. Microstructure & Player Valuation Engines
# depends on rapm_engine.R
# Output: cache/projected_wnba_standings.rds
run_registered_stage("roster_bottom_up_engine")

# 4. Market Arbitrage & Limits
# depends on roster_bottom_up_engine.R, shot_quality_engine.R, fatigue_travel_engine.R
# Output: cache/latest_value_bets.rds, cache/odds_history.rds

# 4.5. Prediction-Accuracy Logging — Log Today's Predictions
run_registered_stage("prediction_accuracy_logger_log")

# 5. Advanced Proposition Distributions - Parallel Group 2
# depends on market_odds_engine.R

# 6. Postseason Simulation
# Output: cache/playoff_series_wnba_demo.rds
run_registered_stage("playoff_simulator")

# 6b. Current-Season Playoff Bracket: resolved results beside per-series predictions (#92)
# Output: cache/playoff_bracket_2026.rds (CACHE_PLAYOFF_BRACKET_CURRENT)
run_registered_stage("playoff_bracket_current")

# 6c. Finals Per-Game Predictions: home court, rest and P(game played) per game (#94)
# Output: cache/finals_game_predictions_2026.rds (CACHE_FINALS_GAME_PREDICTIONS)
# Must follow 6b: it reads the Finals matchup and played results off that artifact.
run_registered_stage("finals_game_predictions")

# 7. Portfolio Risk Management & Capital Preservation
# Output: cache/risk_state.rds

# 8. Notification & Settlement
# Discord: reads Sys.getenv("DISCORD_WEBHOOK", "") only
# Output: cache/rolling_bet_metrics.rds (every run) and cache/betting_ledger.rds (CONDITIONAL —
# only rewritten when at least one pending bet actually grades; on a slate where every bet is
# still unresolved the ledger is legitimately untouched). Only the unconditional output is
# declared for the freshness assertion, so a quiet night does not produce a false staleness WARN.

# 9. Next.js Static Web JSON Export (Phase 1)
# Output: web/public/data/projections_season_teams.json (+ players, metadata, diagnostics, playoffs)
# 8.5. Forecast Accuracy Governance (Issue #17)
run_registered_stage("accuracy_governance")

run_registered_stage("export_web_json")

# 10. WNBA 14-Zone Shot Chart Spatial Extraction (Phase 3)
# Output: web/public/data/shots_index.json (+ shots_metadata.json, web/public/data/shots/*.json)
run_registered_stage("shot_chart_dataset")

# 11. WNBA Offseason Moves & Roster Landscape (Phase 3)
# Output: web/public/data/offseason_transactions.json (+ offseason_teams.json, offseason_draft.json)
run_registered_stage("offseason_dataset")

# 12. WNBA Coaching Staff & Tactical Analytics (Phase 3)
# Output: web/public/data/coaching_metrics.json (+ cache/coaching_metrics.rds)
run_registered_stage("coaching_dataset")

# 13. WNBA Defensive Versatility & Rim Deterrence (Phase 3)
# Output: web/public/data/defensive_metrics.json (+ cache/defensive_metrics.rds)
run_registered_stage("defense_dataset")

# 14. WNBA High-Dimensional Player DNA & Historical Twins (Phase 3)
# Output: web/public/data/player_dna_profiles.json (+ cache/player_dna_profiles.rds)
run_registered_stage("player_dna_dataset")

# 15. WNBA True Clutch & Leverage Creation Index (Phase 3)
# Output: web/public/data/clutch_leverage_metrics.json (+ cache/clutch_leverage_metrics.rds)
run_registered_stage("clutch_dataset")

# 16. WNBA Hard Salary Cap, Rookie Scale & 11-vs-12 Player Roster Crunch (Phase 3)
# Output: web/public/data/cba_cap_sheet.json (+ cache/cba_cap_sheet.rds)
run_registered_stage("cba_cap_dataset")

# 17. Per-game Matchups: week ribbon, graded past weeks, pending future weeks (#74)
# Output: web/public/data/matchups_slates.json (+ cache/matchups_cache.rds)
# Last of the dataset stages because it depends on the most producers -- the schedule and
# box scores (stage 2), the reconciled accuracy log (stages 7 and 11) and the projected
# standings (stage 10). See the ordering note in pipeline_stages.R.
run_registered_stage("matchups_dataset")

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
