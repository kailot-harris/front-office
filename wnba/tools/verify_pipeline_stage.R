# ==============================================================================
# verify_pipeline_stage.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/tools/verify_pipeline_stage.R
#
# Generalized from a one-off script (tools/test_pbp_stage_integration.R, folded in here
# 2026-09-17) written to verify pbp_engine.R's run_full_pipeline.R wiring without paying for a
# full pipeline run (many of the other 13 stages hit live APIs and are slow). Mimics
# run_full_pipeline.R::run_stage()'s real contract checks in isolation, for ANY stage:
#   1. fn check: after source()-ing the stage script, does the declared function exist in
#      .GlobalEnv? (run_stage() only WARNS and continues if not - this script reports the
#      same way, it doesn't stop() either, matching the pipeline's own fail-safe philosophy.)
#      Supports BOTH of run_stage()'s modes (mutually exclusive, same as run_stage() itself):
#      `--entry_fn NAME` (script self-runs NAME via its own !interactive()/sys.nframe()==0
#      footer - this script only asserts NAME exists, it does not call it, matching
#      run_stage()'s own entry_fn semantics) or `--call_fn NAME` (script deliberately does
#      NOT self-run - this script actually INVOKES NAME() after sourcing, matching
#      run_stage()'s own call_fn semantics - e.g. player_metrics.R, daily_ingest.R).
#   2. output freshness check: does the declared output path's mtime advance to at/after this
#      script's own start time? (the same check behind FINDING C-2's staleness detector.)
#
# USAGE:
#   Rscript.exe tools/verify_pipeline_stage.R <script.R> --entry_fn <fn> <output_path> [...]
#   Rscript.exe tools/verify_pipeline_stage.R <script.R> --call_fn <fn> <output_path> [...]
#   e.g. Rscript.exe tools/verify_pipeline_stage.R pbp_engine.R --entry_fn compute_player_pbp_features cache/player_pbp_features.rds
#   e.g. Rscript.exe tools/verify_pipeline_stage.R player_metrics.R --call_fn compute_and_cache_player_features cache/features_cache.rds
#
# Not part of run_full_pipeline.R's DAG - this is a tools/ verification utility for use when
# adding or changing a stage, so its contract can be checked without running the other 12 stages.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")

argv <- commandArgs(trailingOnly = TRUE)
if (length(argv) < 4 || !(argv[2] %in% c("--entry_fn", "--call_fn"))) {
  stop("Usage: Rscript.exe tools/verify_pipeline_stage.R <script.R> --entry_fn|--call_fn <fn> <output_path> [output_path2 ...]")
}
script_name <- argv[1]
mode        <- argv[2]
fn_name     <- argv[3]
output_paths <- argv[-(1:3)]

if (!file.exists(script_name)) stop(sprintf("Script not found: %s", script_name))

start <- Sys.time()
message(sprintf(">>> [VERIFY STAGE] Sourcing %s (mirrors run_stage()'s source(local = FALSE))...", script_name))
source(script_name, local = FALSE)

if (exists(fn_name, envir = .GlobalEnv, mode = "function", inherits = FALSE)) {
  message(sprintf(">>> [OK] %s '%s' exists in .GlobalEnv after sourcing %s", mode, fn_name, script_name))
  if (mode == "--call_fn") {
    message(sprintf(">>> [VERIFY STAGE] Invoking %s() (call_fn mode - the script does not self-run)...", fn_name))
    get(fn_name, envir = .GlobalEnv, mode = "function", inherits = FALSE)()
  }
} else {
  message(sprintf(">>> [WARN] %s '%s' NOT found after sourcing %s (run_stage() would log a WARN here, not fail the pipeline).", mode, fn_name, script_name))
}

for (out_path in output_paths) {
  if (!file.exists(out_path)) {
    message(sprintf(">>> [WARN] declared output %s does not exist after sourcing.", out_path))
    next
  }
  mt <- file.info(out_path)$mtime
  fresh <- as.numeric(difftime(mt, start, units = "secs")) >= -1
  message(sprintf(">>> [%s] %s mtime = %s (stage start = %s)",
                  if (fresh) "FRESH" else "STALE (possible silent no-op, see finding C-2)",
                  out_path, format(mt), format(start)))
}

message(">>> [VERIFY STAGE] Done. This checks run_stage()'s contract only - it does not run the stage inside the actual DAG, so upstream-dependency assumptions (e.g. active_rosters_cache.rds already existing) are the caller's responsibility to satisfy first.")
