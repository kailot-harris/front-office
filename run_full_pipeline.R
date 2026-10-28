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
# WARN by default (fail-safe: report and continue). Critical stages pass strict = TRUE to turn
# a missing/stale output into a hard stage failure (issue #18).
.check_stage_output <- function(script_name, description, output, start, strict = FALSE) {
  if (is.null(output) || length(output) == 0) return(invisible(NULL))
  problems <- character(0)
  for (path in output) {
    if (!file.exists(path)) {
      problems <- c(problems, sprintf("declared output '%s' does not exist after the stage ran", path))
      next
    }
    mt <- tryCatch(file.info(path)$mtime, error = function(e) NA)
    if (length(mt) != 1 || is.na(mt)) next
    if (as.numeric(difftime(mt, start, units = "secs")) < -1) {
      age_h <- as.numeric(difftime(Sys.time(), mt, units = "hours"))
      problems <- c(problems, sprintf(
        "declared output '%s' was NOT rewritten (mtime %s, %.1f h old). Possible silent no-op — see issue #1 / finding C-2",
        path, format(mt, "%Y-%m-%d %H:%M:%S"), age_h))
    } else {
      message(sprintf(">>> [FRESH] %s -> %s (mtime %s)",
                      script_name, path, format(mt, "%Y-%m-%d %H:%M:%S")))
    }
  }
  if (length(problems) > 0) {
    msg <- sprintf(">>> [%s] %s: %s", if (isTRUE(strict)) "FAIL" else "WARN",
                   script_name, paste(problems, collapse = "; "))
    if (isTRUE(strict)) stop(msg, call. = FALSE)
    message(msg)
  }
  invisible(NULL)
}

run_stage <- function(script_name, description, call_fn = NULL, output = NULL,
                      strict_output = FALSE) {
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
    .check_stage_output(script_name, description, output, start, strict = strict_output)
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
# daily_ingest.R runs FIRST: it is the only stage that pulls new box scores from the
# hoopR API, and every downstream stage (ratings, reconciliation, bet grading) reads
# CACHE_TEAM_BOX. It was previously absent from this orchestrator and from
# schedule_daily.bat, so ingestion never ran on a scheduled run and the box-score cache
# sat frozen at the end of the prior season while the models kept re-running over it.
# No `output =` declared on purpose: daily_box_ingest() deliberately skips the write when
# there are no new records ("Cache is already up to date"), so a declared output would
# trip .check_stage_output's staleness WARN on every quiet day. It self-executes on
# source(), so it needs no call_fn.
run_stage("daily_ingest.R", "Ingest New Official Box Scores (hoopR)")
run_stage("sync_rosters.R",  "Sync Active 556-Player Rosters & Mid-Season Trades",
          output = file.path(CACHE_DIR, "active_rosters_cache.rds"))
run_stage("injury_scraper.R", "Scrape Official Injury Scratches & Availability Updates")

# 2. Physics & Biometric Latent Engines (Phase 5)
run_stage("shot_quality_engine.R", "Calculate 15-Game Spatial Shot Quality (xeFG%) & Luck")
run_stage("fatigue_travel_engine.R", "Compute Haversine Flight Miles, Circadian & Altitude Drag")

# 3. Microstructure & Player Valuation Engines (Phase 4)
# Play-by-play extraction must precede the engines that consume it:
# build_coaching_dataset.R falls back to per-coach synthetic bands without
# pbp_timeout_cache.rds.
#
# rapm_engine.R no longer reads stint_lineups.rds -- it fits a possession-level
# design on hoopR's published possession table instead, which is what makes ORAPM
# and DRAPM separable (see that file's header). The stint stage is kept because the
# stint table is still the only on/off and lineup-synergy dataset in the repo, but
# nothing downstream of it runs today, so a failure here no longer breaks RAPM.
run_stage("build_stint_dataset.R", "Extract Stint-Level Lineups from Play-by-Play",
          output = file.path(CACHE_DIR, "stint_lineups.rds"))
run_stage("rapm_engine.R", "Estimate Possession-Level ORAPM/DRAPM (L2 Ridge Regression)",
          output = file.path(CACHE_DIR, "rapm_ratings.rds"))
run_stage("roster_bottom_up_engine.R", "Generate 30-Team Bottom-Up Standings & Fair Spreads")
run_stage("build_tactical_events_dataset.R", "Extract After-Timeout Possessions & Challenge Outcomes",
          output = file.path(CACHE_DIR, "pbp_timeout_cache.rds"))

# Season-long projections (issue #18). This stage consumes the shot-quality,
# RAPM, and bottom-up engines above and writes BOTH cache/ and web/public/data/.
# Every projection-dependent stage below (coaching, clutch, defense, DNA,
# playoffs, matchups) reads web/public/data/projections_*.json, so this must run
# before them. strict_output turns a missing/stale artifact into a hard failure,
# and a failed run aborts the pipeline rather than letting those stages publish
# pages built from older projections.
if (!run_stage(
  "season_simulator.R",
  "Simulate 1,000-Season Team & Player Projections and Publish to web/public/data",
  output = c(
    file.path(CACHE_DIR, "projections_season_teams.json"),
    file.path(CACHE_DIR, "projections_season_players.json"),
    file.path(CACHE_DIR, "projections_models_metadata.json"),
    file.path(WEB_DATA_DIR, "projections_season_teams.json"),
    file.path(WEB_DATA_DIR, "projections_season_players.json"),
    file.path(WEB_DATA_DIR, "projections_models_metadata.json")
  ),
  strict_output = TRUE
)) {
  stop("season_simulator.R failed or did not republish projections; aborting before projection-dependent stages so no page can read stale projections.",
       call. = FALSE)
}

# Offseason profiles. These were absent from the pipeline entirely, so the daily
# run refreshed projections_season_teams while offseason_teams kept the previous
# day's baseline_wins -- the mismatch the cross-dataset check in
# web/tests/contracts/referential.test.ts catches. Order matters: the sync owns
# baseline_wins (build_offseason_dataset.R deliberately preserves whatever is
# already in the file, per the issue #19 contract), so it must run first, and
# both must run after season_simulator.R above.
run_stage("scripts/sync_offseason_wins.R", "Sync Offseason baseline_wins to Current Projections",
          output = file.path(WEB_DATA_DIR, "offseason_teams.json"))
run_stage("build_offseason_dataset.R", "Rebuild Offseason Team Profiles & Draft Models from the Transaction Catalog",
          output = c(
            file.path(WEB_DATA_DIR, "offseason_teams.json"),
            file.path(WEB_DATA_DIR, "offseason_draft.json")
          ))

run_stage("build_coaching_dataset.R", "Compile Coaching Staff Registry, Tactical ATOs & CVA Impact",
          output = file.path(CACHE_DIR, "coaching_metrics.rds"))
run_stage("build_cba_cap_dataset.R", "Calculate 30-Team CBA Cap Sheets, Aprons & Luxury Tax Penalties")
run_stage("build_player_dna_dataset.R", "Embed 16-D Player DNA Vectors & Nearest Historical Twins",
          output = file.path(CACHE_DIR, "player_dna_profiles.rds"))
run_stage("build_defense_dataset.R", "Compute Positional Versatility Entropy & Rim Deterrence Residuals",
          output = file.path(CACHE_DIR, "defensive_metrics.rds"))
run_stage("build_clutch_dataset.R", "Analyze Leverage Index Filtering & Unassisted Shot Creation (USCI)",
          output = file.path(CACHE_DIR, "clutch_leverage_metrics.rds"))

# 7. Postseason Simulation
run_stage("playoff_simulator.R", "Execute 8-Man Playoff Series Monte Carlo (10,000 Iterations)")

# 8. Forecast Accuracy Governance & Logging (betting stages pruned per Phase 1, Issue #15)
run_stage("prediction_accuracy_logger.R", "Reconcile Outcomes & Log Pre-Game Win Probabilities",
          output = file.path(CACHE_DIR, "prediction_accuracy_log.rds"))

# 8.5. Forecast Accuracy Governance & Calibration Engine (Issue #17)
run_stage("accuracy_governance.R", "Compute Forecast Accuracy Governance & Calibration Diagnostics",
          output = file.path(CACHE_DIR, "accuracy_governance.rds"))

# 9. Web-Facing Per-Game Slates (must run AFTER prediction_accuracy_logger.R, which
# writes the graded prediction log this stage reads, and after the box-score cache
# ingestion that supplies the real final scores it joins on game_id.)
run_stage("build_matchups_dataset.R", "Assemble Weekly Matchup Slates, Projections & Graded Results",
          output = file.path(CACHE_DIR, "matchups_cache.rds"))

# Final projection publish guard (issue #18). Every page above reads these three
# files; assert the scheduled run actually left fresh copies and that the
# metadata's generated_at/season_label describe this run -- not a previous one.
projection_web_json <- file.path(
  WEB_DATA_DIR,
  c("projections_season_teams.json",
    "projections_season_players.json",
    "projections_models_metadata.json")
)
missing_projections <- projection_web_json[!file.exists(projection_web_json)]
if (length(missing_projections) > 0) {
  stop(sprintf("Pipeline finished without publishing projection artifact(s): %s",
               paste(missing_projections, collapse = ", ")), call. = FALSE)
}
projection_mtimes <- file.info(projection_web_json)$mtime
stale_projections <- projection_web_json[
  is.na(projection_mtimes) |
    as.numeric(difftime(projection_mtimes, pipeline_start_time, units = "secs")) < -1
]
if (length(stale_projections) > 0) {
  stop(sprintf("Pipeline finished with projection artifact(s) older than the run: %s",
               paste(stale_projections, collapse = ", ")), call. = FALSE)
}
projection_meta <- jsonlite::fromJSON(file.path(WEB_DATA_DIR, "projections_models_metadata.json"))
projection_generated_at <- as.POSIXct(
  projection_meta$generated_at,
  format = "%Y-%m-%dT%H:%M:%SZ",
  tz = "UTC"
)
expected_season_label <- sprintf("%d-%d", CURRENT_SEASON - 1L, CURRENT_SEASON)
if (is.na(projection_generated_at) ||
    as.numeric(difftime(projection_generated_at, pipeline_start_time, units = "secs")) < -2 ||
    !identical(projection_meta$season_label, expected_season_label)) {
  stop(sprintf(
    "Projection publish guard failed: generated_at=%s season_label=%s (expected %s or newer).",
    projection_meta$generated_at, projection_meta$season_label, expected_season_label
  ), call. = FALSE)
}
message(sprintf(">>> [CONTRACT] Projections published by this run: %s (%s)",
                projection_meta$generated_at, projection_meta$season_label))

pipeline_total_time <- as.numeric(difftime(Sys.time(), pipeline_start_time, units = "secs"))
message("\n==================================================================")
message(sprintf(">>> FULL PIPELINE EXECUTED SUCCESSFULLY IN %.2f SECONDS", pipeline_total_time))
message("==================================================================")
