# ==============================================================================
# run_full_pipeline.R
# Master Production Quantitative Pipeline (Phases 1 through 5)
# ==============================================================================

pipeline_start_time <- Sys.time()
message("==================================================================")
message(sprintf(">>> NBA QUANTITATIVE ENGINE v5.0 STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
message("==================================================================")

source("config.R")

# .check_stage_output() — output-staleness assertion (Finding C-2, ported from NFL/WNBA sibling
# repos). After each stage completes, checks that every declared output file's mtime is at or
# after the stage's own start time. A silent no-op (e.g. a dead auto-run guard — the exact bug
# from issue #1) leaves the file untouched; this surfaces it immediately rather than letting
# the pipeline log "COMPLETED" and carry stale data silently.
# WARN, never stop() — fail-safe: report and continue.
.check_stage_output <- function(script_name, description, output, start) {
  if (is.null(output) || length(output) == 0) return(invisible(NULL))
  for (path in output) {
    if (!file.exists(path)) {
      message(sprintf(">>> [WARN] %s: declared output '%s' does not exist after the stage ran.",
                      script_name, path))
      next
    }
    mt <- tryCatch(file.info(path)$mtime, error = function(e) NA)
    if (length(mt) != 1 || is.na(mt)) next
    if (as.numeric(difftime(mt, start, units = "secs")) < -1) {
      age_h <- as.numeric(difftime(Sys.time(), mt, units = "hours"))
      message(sprintf(
        ">>> [WARN] %s reported success but declared output '%s' was NOT rewritten (mtime %s, %.1f h old). Possible silent no-op — see issue #1 / finding C-2.",
        script_name, path, format(mt, "%Y-%m-%d %H:%M:%S"), age_h))
    } else {
      message(sprintf(">>> [FRESH] %s -> %s (mtime %s)",
                      script_name, path, format(mt, "%Y-%m-%d %H:%M:%S")))
    }
  }
  invisible(NULL)
}

run_stage <- function(script_name, description, call_fn = NULL, output = NULL) {
  message(sprintf("\n>>> [STAGE] %s (%s)...", description, script_name))
  if (!file.exists(script_name)) {
    warning(sprintf("Script %s not found in working directory. Skipping.", script_name))
    return(FALSE)
  }
  start <- Sys.time()
  tryCatch({
    source(script_name, local = FALSE)
    if (!is.null(call_fn)) {
      if (exists(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
        get(call_fn, envir = .GlobalEnv, mode = "function", inherits = FALSE)()
      } else {
        warning(sprintf(">>> [WARN] call_fn '%s' not found as a function after sourcing %s.", call_fn, script_name))
      }
    }
    # Output-staleness check (Finding C-2, ported from NFL/WNBA Analytics sibling repos).
    # A stage that silently no-ops (e.g. a broken auto-run guard) will leave its declared
    # output file untouched; mtime < stage start exposes it rather than logging "COMPLETED".
    # WARN, never stop() — the pipeline reports and continues.
    .check_stage_output(script_name, description, output, start)
    elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
    message(sprintf(">>> [COMPLETED] %s in %.2f seconds.", script_name, elapsed))
    return(TRUE)
  }, error = function(e) {
    warning(sprintf(">>> [FAILED] %s: %s", script_name, e$message))
    return(FALSE)
  })
}


# ------------------------------------------------------------------------------
# Chronological Execution Sequence
# ------------------------------------------------------------------------------

# 1. Official Data Feed & Ingestion
run_stage("sync_rosters.R",  "Sync Active 556-Player Rosters & Mid-Season Trades",
          output = file.path(CACHE_DIR, "active_rosters_cache.rds"))
run_stage("injury_scraper.R", "Scrape Official Injury Scratches & Availability Updates")

# 2. Physics & Biometric Latent Engines (Phase 5)
run_stage("shot_quality_engine.R", "Calculate 15-Game Spatial Shot Quality (xeFG%) & Luck")
run_stage("fatigue_travel_engine.R", "Compute Haversine Flight Miles, Circadian & Altitude Drag")

# 3. Microstructure & Player Valuation Engines (Phase 4)
run_stage("rapm_engine.R", "Estimate Bayesian Stint-Level RAPM (L2 Ridge Regression)")
run_stage("roster_bottom_up_engine.R", "Generate 30-Team Bottom-Up Standings & Fair Spreads")

# 4. Market Arbitrage & Limits
run_stage("market_odds_engine.R", "Benchmark Live Books vs Pinnacle Limits & Kelly Stakes")

# 5. Advanced Proposition Distributions
run_stage("player_props_engine.R", "Price ZINB Overdispersed Player Props (PTS, REB, AST, BLK, STL)")
run_stage("copula_props_engine.R", "Simulate Joint Multivariate Gaussian Copula (PRA / SGPs)")

# 6. Postseason Simulation
run_stage("playoff_simulator.R", "Execute 8-Man Playoff Series Monte Carlo (10,000 Iterations)")

# 7. Portfolio Risk Management & Capital Preservation
run_stage("risk_management_engine.R", "Audit Drawdown State & Set Dynamic Kelly Multiplier")

# 8. Notification & Settlement
run_stage("notify_bets.R", "Dispatch Filtered Discord Webhooks (EV >= 5.0%, CLV > 0)")
run_stage("bet_tracker.r", "Grade Previous Completed Events & Update Rolling CLV%")

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL PIPELINE EXECUTED SUCCESSFULLY IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")