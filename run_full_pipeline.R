# ==============================================================================
# run_full_pipeline.R
# Master Production Quantitative Pipeline (Phases 1 through 5)
# ==============================================================================

pipeline_start_time <- Sys.time()
message("==================================================================")
message(sprintf(">>> NBA QUANTITATIVE ENGINE v5.0 STARTED: %s", format(pipeline_start_time, "%Y-%m-%d %H:%M:%S")))
message("==================================================================")

run_stage <- function(script_name, description) {
  message(sprintf("\n>>> [STAGE] %s (%s)...", description, script_name))
  if (!file.exists(script_name)) {
    warning(sprintf("Script %s not found in working directory. Skipping.", script_name))
    return(FALSE)
  }
  start <- Sys.time()
  tryCatch({
    source(script_name, local = FALSE)
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
run_stage("sync_rosters.R", "Sync Active 556-Player Rosters & Mid-Season Trades")
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