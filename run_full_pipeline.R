# ==============================================================================
# run_full_pipeline.R
# NFL Analytics Pipeline Orchestrator — Wave 1 Skeleton
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/run_full_pipeline.R
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

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
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
    # Fail-safe behavior: warn on console and let run_full_pipeline.R continue to the next
    # run_stage() call (do NOT stop() / re-throw here).
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    FALSE
  })

  # Memory-reduction Option 1 (docs/memory_optimization_plan.md): every stage runs source()'d
  # into this SAME long-lived R process (deliberate, per this file's own header - stages share
  # .GlobalEnv so later stages can read earlier ones' cache-writer functions). That means a
  # stage's large local objects (e.g. daily_ingest.R's pre-trim PBP data, team_ratings_engine.R's
  # historical walk-forward rebuild) are only eligible for garbage collection once R itself
  # decides to run one - not necessarily before the NEXT stage starts allocating its own large
  # objects. An explicit gc() here forces that reclaim between every stage rather than leaving it
  # to chance, directly targeting the cross-stage accumulation failure mode (as opposed to any
  # single stage's own peak usage, which Option 2's CACHE_PBP column-trim addresses instead).
  gc(verbose = FALSE)

  result
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

# 6. Fatigue/travel & short-rest engine (Phase 3, task P3-B; engine itself built under P3-A).
# Writes CACHE_FATIGUE_METRICS (config.R). Reads CACHE_SCHEDULES from stage 1 above.
run_stage("fatigue_engine.R", "Compute Travel/Circadian & Short-Rest Fatigue Metrics",
          call_fn = "run_fatigue_engine",
          output   = CACHE_FATIGUE_METRICS)

# 7. Playoff bracket simulator (Phase 4, task P4-B; engine itself built under P4-A).
# Writes CACHE_PLAYOFF_SIMULATION (config.R). Reads CACHE_TEAM_RATINGS from stage 5 and
# CACHE_SCHEDULES from stage 1 above.
run_stage("playoff_simulator.R", "Simulate Full NFL Playoff Bracket (reseeding, Monte Carlo)",
          call_fn = "run_playoff_simulator",
          output   = CACHE_PLAYOFF_SIMULATION)

# 7.5. Playoff-clinching probability engine (issues #11-#14/#16; wired in under issue #15).
# Writes CACHE_PLAYOFF_ODDS (config.R). Reads CACHE_TEAM_RATINGS from stage 5
# (team_ratings_engine.R) and CACHE_SCHEDULES from stage 1 (daily_ingest.R) — exactly the same
# dependency shape as stage 7's playoff_simulator.R immediately above, which run_playoff_odds_
# engine() reuses (.seed_conference()) rather than duplicates (see this script's own header).
# There is no dependency between the two playoff-related stages ON EACH OTHER — either order
# relative to stage 7 would be correct — placed directly after it (not before) so the two
# playoff stages read as one grouped block in this file, matching docs/SPEC_playoff_odds_table.md
# decision #6's framing of it as "the other playoff-bracket stage." Runs every pipeline
# execution with no cadence gate (per spec decision #6 — unlike stage 9.5/11's bet-ledger/
# accuracy-tracker no-op days, run_playoff_odds_engine() always recomputes its
# N_SEASON_SIMULATIONS-trial Monte Carlo and always rewrites CACHE_PLAYOFF_ODDS). Also dispatches
# its own AFC/NFC two-field embed to NFL_DISCORD_WEBHOOK (issue #14) — a second real Discord post
# this pipeline run, independent of stage 10's notify_bets.R dispatch below.
run_stage("playoff_odds_engine.R", "Compute NFL Playoff-Clinching Probabilities (Monte Carlo season simulation)",
          call_fn = "run_playoff_odds_engine",
          output   = CACHE_PLAYOFF_ODDS)

# 8. Market odds / value-betting engine (Phase 6, task P6-B; engine itself built under P6-A).
# Writes CACHE_LATEST_VALUE_BETS and CACHE_ODDS_HISTORY (config.R) — two outputs from one stage,
# declared together per the daily_ingest.R / team_ratings_engine.R stages' multi-output precedent
# above. Reads cache/projected_matchups.rds (stage 5, team_ratings_engine.R) as its sole model-
# probability source and cache/fatigue_metrics.rds (stage 6, fatigue_engine.R) for the fatigue
# adjustment layered on top — must therefore come after both.
run_stage("market_odds_engine.R", "Fetch Live NFL Odds & Identify +EV Value Bets",
          call_fn = "run_market_odds_engine",
          output   = c(CACHE_LATEST_VALUE_BETS, CACHE_ODDS_HISTORY))

# 9. Real bet ledger writer/grader (model-quality remediation, Known Issue #2).
# Writes CACHE_BETTING_LEDGER (config.R). Reads cache/latest_value_bets.rds (stage 8 above) to
# record today's real, staked value picks as PENDING, and cache/schedules_cache.rds (stage 1)
# to grade any already-recorded picks whose games have since completed — must therefore come
# after stage 8.
#
# EXPECTED BENIGN C-2 WARNING: unlike every other stage, bet_tracker.r only rewrites
# CACHE_BETTING_LEDGER when there is a real new pick to append OR a real pending bet whose
# game has completed to grade - on a run with neither (no staked value bets this slate, and
# nothing outstanding to resolve), the file is legitimately untouched and
# .check_stage_output() will WARN it as possibly-stale. That is a true "nothing changed"
# report, not the silent-no-op failure mode C-2 exists to catch - do not "fix" it by forcing
# a write every run just to silence the WARN.
run_stage("bet_tracker.r", "Record & Grade Real Value-Bet Ledger (CLV tracking)",
          call_fn = "run_bet_tracker",
          output   = CACHE_BETTING_LEDGER)

# 9.5. Risk management engine (Phase 5, task P5-B; engine itself built under P5-A).
# Writes CACHE_RISK_STATE (config.R). Reads CACHE_BETTING_LEDGER (stage 9 above) — falls back to a
# clearly-labeled SYNTHETIC_FALLBACK ledger if it doesn't exist or has zero RESOLVED bets yet (see
# risk_management_engine.R header and docs/task_assignments_phase4.md). Deliberately moved to run
# AFTER stage 9 (was stage 8, before market_odds_engine.R/bet_tracker.r) so that any bet graded
# earlier in THIS SAME pipeline invocation is reflected in this run's risk state immediately,
# instead of one cycle behind — this closes the ordering gap documented in docs/HANDOFF.md's Known
# Issue #3. No other stage reads CACHE_RISK_STATE, so this reorder has no other dependency impact.
run_stage("risk_management_engine.R", "Compute Bankroll Drawdown / Kelly-Tier Risk State",
          call_fn = "run_risk_management",
          output   = CACHE_RISK_STATE)

# 10. Discord alpha/CLV alert dispatcher (Phase 7, task P7-B; engine itself built under P7-A).
# Terminal notification stage — no cache output of its own (matches WNBA's own run_stage() call
# for notify_bets.R, which also declares no `output`), so it is intentionally absent from the
# pipeline-freshness-audit skill's manifest (.claude/skills/pipeline-freshness-audit) — nothing to
# track, not a gap. Reads cache/latest_value_bets.rds (stage 9, market_odds_engine.R) as its sole
# input — must therefore come after it. Dispatches to NFL_DISCORD_WEBHOOK if visible to this R
# process, else cleanly falls back to a console-only preview (see notify_bets.R header).
run_stage("notify_bets.R", "Dispatch NFL Discord Alpha & CLV Bet Alerts",
          call_fn = "run_notify_bets")

# 11. Season-to-date model accuracy trajectory tracker (issue #7; engine itself built under
# issue #5, Discord dispatch under issue #6). Detects newly-completed/graded CURRENT_SEASON games
# since the last recorded run and appends one row to CACHE_ACCURACY_HISTORY (config.R) — see
# accuracy_tracker.R's own header and docs/SPEC_accuracy_trajectory_monitoring.md decisions #3-#5.
# No `output` declared here, deliberately, same rationale as stage 10's bet_tracker.r comment
# above: run_accuracy_tracker() only appends to CACHE_ACCURACY_HISTORY when there is at least one
# newly-graded game since the last run — on a normal no-new-games day (bye weeks, mid-week, or a
# day with no games completed since the last run) it is a clean no-op that returns without
# touching the file at all, which is indistinguishable from the C-2 "possibly stale/silent no-op"
# case .check_stage_output() warns about. Declaring `output = CACHE_ACCURACY_HISTORY` would make
# that legitimate every-day-without-new-games outcome throw a false-positive staleness WARN, so
# `output` is intentionally omitted (matches notify_bets.R's own no-`output` convention directly
# above, for the same "last stage, no unconditional per-run write" reason).
run_stage("accuracy_tracker.R", "Track Season-to-Date Model Accuracy Trajectory",
          call_fn = "run_accuracy_tracker")

# ------------------------------------------------------------------------------
# Stage 14: Web data export (TERMINAL stage).
# ------------------------------------------------------------------------------
# Regenerates every JSON dataset the Next.js app under web/ consumes, from the caches the
# stages above just wrote. This was previously a detached tools/ one-off that only ever ran
# when invoked by hand, which meant a fully successful pipeline run could still leave the
# published site showing days-old numbers (observed: pipeline fresh, JSON four days stale,
# publishing a stale active_week). It must stay LAST: it is a pure consumer of every upstream
# cache and produces nothing any other stage reads.
#
# Unlike notify_bets.R / accuracy_tracker.R / bet_tracker.r above (which deliberately omit
# `output` because a day with nothing new is a legitimate no-op), this stage rewrites the nine
# files in WEB_DATA_FILES on every run, so declaring them is right. WEB_DATA_FILES is
# config.R's single source of truth for that list - do not restate the paths here.
#
# Scope of the C-2 guarantee, stated precisely so nobody over-trusts it: .check_stage_output()
# compares mtimes only. It will WARN if a declared file is not touched at all - e.g. the
# exporter dies partway, or a numbered section is removed without updating the list. It CANNOT
# detect a file whose bytes were merely republished verbatim, because that still advances the
# mtime. That applies to salary_cap_profiles.json on a run where its live
# nflreadr::load_contracts() fetch fails and it falls back, and to coaching_profiles.json,
# which is a hand-seeded static artifact with no upstream source and is therefore excluded
# from WEB_DATA_FILES entirely. For those paths the exporter's own log_warn() in
# logs/nfl_pipeline.log - naming the file and the reason - is the staleness signal, not this
# assertion. See config.R's WEB_* block for the full rationale.
run_stage("export_web_datasets.R", "Export Web Application JSON Datasets (web/public/data)",
          call_fn = "run_export_web_datasets",
          output = WEB_DATA_FILES)

# ------------------------------------------------------------------------------
# FUTURE STAGES — extension point, not yet implemented (see docs/task_assignments_phase0.md's
# Constraints section and docs/NFL_REPLICATION_PLAN.md §1's later-phase list). Per that
# Constraints note, this wave deliberately does NOT add stub run_stage() calls for scripts that
# don't exist yet — doing so would immediately fail with "script not found". A later wave should
# insert its own run_stage() calls HERE, in roughly this order, as each script is actually built:
#   embeddings (the fatigue/embeddings DAG node's other half, per REPLICATION_PLAN §1 — fatigue
#   itself is now wired in as stage 6 above) -> player props pricing (the market/props node's
#   other half, now that market odds is wired in as stage 9 above) -> live/dashboard.
# ------------------------------------------------------------------------------

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL NFL PIPELINE EXECUTED IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
log_info(sprintf("Pipeline run finished in %.2f seconds.", pipeline_total_time), script = "run_full_pipeline.R")
