# ==============================================================================
# test_logging_fault_injection.R (WNBA — NEW FILE, Task P5, wnba_logging_agent)
# Path: tools/test_logging_fault_injection.R
#
# Deliberately triggers real failure modes (NOT happy-path calls) and asserts, by actually
# reading the resulting logs/wnba_pipeline.log contents after each scenario runs, that
# logging_utils.R's log_info/log_warn/log_error captured them correctly. Per agent11.md's
# constraint, this script must actually be executed via Rscript.exe and the real resulting
# log lines inspected as evidence — this file does not "assert the code should work," it
# re-reads the log file after each scenario and checks the real line is present.
#
# Run:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "test_logging_fault_injection.R"
#
# Scenarios:
#   1. Broken URL / unreachable host  -> real connection error captured by log_error().
#   2. (removed) Exercised risk_management_engine.R's ledger loading. That script was
#      deleted under the zero-betting policy, so the scenario had nothing left to test.
#   3. run_stage() catching a deliberately-thrown error from a dummy stage script -> log_error()
#      captures the real message/stage name, run_stage() returns FALSE (fail-safe), and the
#      pipeline (this test) successfully proceeds to run a subsequent stage afterward.
# ==============================================================================

# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("test_logging_fault_injection.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
source("logging_utils.R")
.LOG_SCRIPT <- "test_logging_fault_injection.R"

pass_count <- 0L
fail_count <- 0L
results <- list()

record <- function(scenario, passed, detail) {
  results[[length(results) + 1]] <<- list(scenario = scenario, passed = passed, detail = detail)
  if (passed) pass_count <<- pass_count + 1L else fail_count <<- fail_count + 1L
  cat(sprintf("[%s] %s -- %s\n", if (passed) "PASS" else "FAIL", scenario, detail))
}

# Read the tail of the real log file fresh from disk (not from in-memory state) so assertions
# are checking actual persisted evidence, matching the brief's "inspect the actual resulting
# log file contents as your evidence" requirement.
read_log_tail <- function(n = 400) {
  if (!file.exists(LOG_FILE)) return(character(0))
  lines <- readLines(LOG_FILE, warn = FALSE)
  tail(lines, n)
}

log_marker <- function(tag) log_info(sprintf("=== FAULT INJECTION TEST MARKER: %s ===", tag), script = "test_logging_fault_injection.R")

cat("\n==================================================================\n")
cat(" WNBA LOGGING FAULT-INJECTION TEST SUITE\n")
cat(sprintf(" Log file under test: %s\n", LOG_FILE))
cat("==================================================================\n\n")

# ------------------------------------------------------------------------------
# SCENARIO 1: broken URL / unreachable host -> real connection error via log_error()
# ------------------------------------------------------------------------------
cat("\n--- SCENARIO 1: broken URL / unreachable host ---\n")
marker1 <- sprintf("SCENARIO1_%s", format(Sys.time(), "%Y%m%d%H%M%OS3"))
log_marker(marker1)

suppressPackageStartupMessages(library(httr2))

broken_url <- "http://this-host-does-not-exist.wnba-fault-injection-test.invalid/odds"

fetch_broken <- function(url) {
  tryCatch({
    request(url) |> req_timeout(3) |> req_perform()
  }, error = function(e) {
    log_error("Deliberate fault-injection: broken-host fetch failed.", condition = e,
              call = "fetch_broken()", url = url)
    NULL
  })
}

s1_result <- fetch_broken(broken_url)

s1_log <- read_log_tail()
s1_marker_idx <- which(grepl(marker1, s1_log, fixed = TRUE))
s1_after <- if (length(s1_marker_idx) > 0) s1_log[(max(s1_marker_idx) + 1):length(s1_log)] else character(0)
s1_error_lines <- s1_after[grepl("\\[ERROR\\] \\[test_logging_fault_injection.R\\].*broken-host fetch failed", s1_after)]

s1_pass <- is.null(s1_result) &&
  length(s1_error_lines) >= 1 &&
  any(grepl("condition_class:", s1_error_lines)) &&
  any(grepl("condition_message:", s1_error_lines)) &&
  !any(grepl("condition_message: an error occurred$", s1_error_lines, ignore.case = TRUE))

record(
  "1. Broken URL / unreachable host",
  s1_pass,
  if (s1_pass) sprintf("log_error() captured real connection error. Line: %s", s1_error_lines[1])
  else sprintf("Expected ERROR line with real condition not found. Captured lines: %s", paste(s1_after, collapse = " || "))
)

# Pull one top-level `name <- function(...)` definition out of a parsed file, so a
# scenario can evaluate the real production function body without sourcing (and
# thereby running) the whole script.
extract_fun_def <- function(exprs, fun_name) {
  for (e in as.list(exprs)) {
    if (is.call(e) && length(e) >= 2 && identical(e[[1]], as.name("<-"))) {
      lhs <- e[[2]]
      if (is.symbol(lhs) && as.character(lhs) == fun_name) return(e)
    }
  }
  NULL
}

# ------------------------------------------------------------------------------
# SCENARIO 3: run_stage() catches a deliberately-thrown error from a dummy stage script,
# logs it via log_error(), returns FALSE (fail-safe), and the pipeline correctly continues
# to the next stage afterward.
# ------------------------------------------------------------------------------
cat("\n--- SCENARIO 3: run_stage() deliberate stage failure + continuation ---\n")
marker3 <- sprintf("SCENARIO3_%s", format(Sys.time(), "%Y%m%d%H%M%OS3"))
log_marker(marker3)

# Extract the REAL .check_stage_output() and run_stage() definitions from run_full_pipeline.R
# by parsing (not sourcing the whole file, which would run the entire real pipeline against
# live network/cache state).
rfp_exprs <- parse(file = "run_full_pipeline.R")
check_stage_output_def <- extract_fun_def(rfp_exprs, ".check_stage_output")
stopifnot(!is.null(check_stage_output_def))
eval(check_stage_output_def, envir = .GlobalEnv)
run_stage_def <- extract_fun_def(rfp_exprs, "run_stage")
stopifnot(!is.null(run_stage_def))
eval(run_stage_def, envir = .GlobalEnv)

failing_stage_path <- file.path(tempdir(), "test_dummy_failing_stage_TEST.R")
writeLines('stop("Deliberate fault-injection error: dummy stage intentionally failed.")', failing_stage_path)

succeeding_stage_path <- file.path(tempdir(), "test_dummy_succeeding_stage_TEST.R")
writeLines('cat("[TEST] dummy succeeding stage executed fine.\\n")', succeeding_stage_path)

s3_fail_result <- run_stage(failing_stage_path, "Fault Injection Dummy Failing Stage")
s3_success_result <- run_stage(succeeding_stage_path, "Fault Injection Dummy Succeeding Stage (post-failure continuation check)")

unlink(failing_stage_path)
unlink(succeeding_stage_path)

s3_log <- read_log_tail()
s3_marker_idx <- which(grepl(marker3, s3_log, fixed = TRUE))
s3_after <- if (length(s3_marker_idx) > 0) s3_log[(max(s3_marker_idx) + 1):length(s3_log)] else character(0)
s3_error_lines <- s3_after[grepl("\\[ERROR\\] \\[run_full_pipeline.R\\].*Stage failed", s3_after) &
                              grepl(basename(failing_stage_path), s3_after, fixed = TRUE)]
s3_completed_lines <- s3_after[grepl("\\[INFO\\] \\[run_full_pipeline.R\\].*Stage completed", s3_after) &
                                  grepl(basename(succeeding_stage_path), s3_after, fixed = TRUE)]

s3_pass <- identical(s3_fail_result, FALSE) &&
  identical(s3_success_result, TRUE) &&
  length(s3_error_lines) >= 1 &&
  any(grepl("condition_message: Deliberate fault-injection error", s3_error_lines)) &&
  any(grepl("stack_trace:", s3_error_lines)) &&
  length(s3_completed_lines) >= 1

record(
  "3. run_stage() dummy failure + fail-safe continuation",
  s3_pass,
  if (s3_pass) sprintf("run_stage() returned FALSE on failure, TRUE on next stage. ERROR line: %s | Continuation line: %s",
                        s3_error_lines[1], s3_completed_lines[1])
  else sprintf("Expected FALSE/TRUE + log lines not found. fail_result=%s success_result=%s captured=%s",
               s3_fail_result, s3_success_result, paste(s3_after, collapse = " || "))
)

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat("\n==================================================================\n")
cat(sprintf(" FAULT-INJECTION TEST SUMMARY: %d PASSED, %d FAILED (of %d)\n", pass_count, fail_count, length(results)))
cat("==================================================================\n")
for (r in results) {
  cat(sprintf("  [%s] %s\n", if (r$passed) "PASS" else "FAIL", r$scenario))
}

if (fail_count > 0) {
  quit(status = 1, save = "no")
} else {
  quit(status = 0, save = "no")
}
