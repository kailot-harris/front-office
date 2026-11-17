# ==============================================================================
# tools/notify_pipeline_failure.R  (NBA_analytics#161)
#
# Called by schedule_daily.bat when run_full_pipeline.R exits non-zero, i.e. when
# publish_web.R will never run. Opens (or comments on) a `pipeline-failed` GitHub
# issue with a sanitized tail of the run log.
#
#   Rscript tools/notify_pipeline_failure.R <exit_code> <log_path>
#
# Always exits 0: a notification problem must never change the scheduled run's
# exit code, which the .bat takes from PIPELINE_EXIT, not from this script.
# ==============================================================================
tryCatch({
  argv <- commandArgs(trailingOnly = TRUE)
  exit_code <- if (length(argv) >= 1L) argv[[1L]] else "unknown"
  log_path  <- if (length(argv) >= 2L) argv[[2L]] else NULL
  source(file.path("tools", "publish_web.R"))
  .pw_notify_pipeline_failure(exit_code, log_path)
}, error = function(e) {
  message(sprintf(">>> [WARN] notify_pipeline_failure: skipped: %s", conditionMessage(e)))
})
quit(status = 0L)
