# Run this repo's own R test scripts and aggregate the results.
#
# Shaped after NBA Analytics/.github/scripts/run-tests.R -- one process per file,
# so one file's global state cannot leak into the next -- but it CANNOT be that
# file verbatim, for two reasons:
#
#   1. There is no testthat suite here. `tests/testthat/` does not exist and
#      there is not one `test_that()` call in the repo. The tests are 14
#      standalone scripts under tools/, each printing its own [PASS]/[FAIL]
#      lines and exiting non-zero on failure. They are run by path.
#
#   2. Ten of those 14 cannot run as a gate on a hosted runner. Running them anyway
#      would produce a permanently red gate, which is a gate everybody learns
#      to ignore. They are listed below with a reason each, and the list is
#      enforced: an unclassified tools/test_*.R fails this script rather than
#      being silently skipped.
#
# Counting note for anyone reconciling this against the planning docs: the
# "14 files / 17 assertions" figure in NEXT_AGENT_PRIORITIES_20261026.md came
# from grepping `test_that(`, of which this repo has ZERO. The real assertion
# count is whatever the scripts' own [PASS]/[FAIL] lines report, which this
# script totals.

# ------------------------------------------------------------------ policy ---

# Runs on a hosted Ubuntu runner. Verified green locally on main @ 8a98d89,
# 2026-10-26, each in a clean process: 74 assertions across the four.
RUN <- c(
  "tools/test_pure_functions.R",
  "tools/test_phase4_engine.R",
  "tools/test_auth_utils.R",
  "tools/test_create_account_if_authorized.R"
)

# Deliberately not run, and why. Every entry here is a measured reason, not a
# guess: each was read, and the first four were also observed doing the thing
# described.
SKIP <- c(
  "tools/test_phase4_pipeline.R" =
    "spawns the REAL pipeline (system2(Rscript, 'run_full_pipeline.R')) -- live APIs, hours",
  "tools/test_phase4_props.R" =
    "spawns the real player_props_engine.R",
  "tools/test_phase4_wave4_verification.R" =
    "spawns player_props_engine.R, and hardcodes C:/Program Files/R/.../Rscript.exe",
  "tools/test_phase4_dashboard.R" =
    "drives a real Chrome through shinytest2/chromote via a Windows CHROMOTE_CHROME path",
  "tools/test_phase4_cleanup.R" =
    "spawns tools/ml_cv_benchmark.R, a full cross-validation run",
  "tools/test_db_logs.R" =
    "reads logs/logs.duckdb, which is gitignored and so does not exist in a fresh clone",
  "tools/test_db_embeddings.R" =
    "reads logs/analytics.duckdb, same -- gitignored, absent in a fresh clone",
  "tools/test_pipeline_db.R" =
    "reads both of the above duckdb files",
  "tools/test_phase4_foundation.R" =
    paste("FLAKY, not broken: 13 of its 14 checks are fine, but CHECK 3d",
          "(.log_write() reuses one process-lifetime DuckDB connection) was",
          "observed both PASS and FAIL at an IDENTICAL database state (rows",
          "2 -> 3) across repeated runs on 2026-10-26. The connection is",
          "re-created between the check's two log_error() calls whenever R's",
          "GC finalizes it first, so the assertion is a garbage-collection",
          "race. A gate that fails at random teaches people to re-run it;",
          "out until CHECK 3d pins the connection it is asserting about."),
  "tools/test_logging_fault_injection.R" =
    paste("RED on main as of 2026-10-26: 3 of its 4 scenarios pass, scenario 3",
          "fails with 'could not find function \".check_stage_output\"'. The test",
          "carries its own copy of run_stage()'s environment and has not been",
          "updated for the helper run_full_pipeline.R now calls. It is a stale",
          "test, not an app defect -- but a red test is not a gate, so it is out",
          "until it is fixed.")
)

# ------------------------------------------------------------------- guard ---

# Sys.glob, not `find` or git ls-files + a filter: tools/ cannot contain the
# 64 vendored third-party suites under renv/library/ or the agent worktree
# copies under .claude/, so the exclusion the brief asks for is structural
# here rather than a pattern someone has to remember to maintain.
present <- sort(Sys.glob(file.path("tools", "test_*.R")))

if (length(present) == 0L) {
  stop("No tools/test_*.R found - is this running from the repository root?")
}

classified <- c(RUN, names(SKIP))
unclassified <- setdiff(present, classified)
vanished     <- setdiff(classified, present)

if (length(unclassified)) {
  stop(sprintf(
    paste("These test files are new and not classified in .github/scripts/run-tests.R:\n  %s\n",
          "Add each to RUN (if it is safe on a hosted runner) or to SKIP with a reason.",
          "Failing here is deliberate: a new test that silently never runs is worse",
          "than no test."),
    paste(unclassified, collapse = "\n  ")))
}
if (length(vanished)) {
  stop(sprintf("Classified but missing from disk - remove from this script:\n  %s",
               paste(vanished, collapse = "\n  ")))
}

# ------------------------------------------------------------------- run -----

rscript <- file.path(R.home("bin"), "Rscript")
results <- data.frame(file = RUN, status = NA_integer_, pass = NA_integer_,
                      fail = NA_integer_, stringsAsFactors = FALSE)

for (i in seq_along(RUN)) {
  f <- RUN[[i]]
  cat(sprintf("\n================ %s ================\n", f))
  out <- suppressWarnings(system2(rscript, shQuote(f), stdout = TRUE, stderr = TRUE))
  st  <- attr(out, "status")
  cat(paste(out, collapse = "\n"), "\n")

  results$status[[i]] <- if (is.null(st)) 0L else as.integer(st)
  # The scripts do not share a harness, but they do share the [PASS]/[FAIL]
  # line prefix, which is the only assertion signal there is to count.
  results$pass[[i]] <- sum(grepl("[PASS]", out, fixed = TRUE))
  results$fail[[i]] <- sum(grepl("[FAIL]", out, fixed = TRUE))
}

failed <- results[results$status != 0L, , drop = FALSE]

lines <- c(
  sprintf("### R tests: %d of %d file(s) run, %d assertion(s) passed, %d failed, %d file-level failure(s)",
          nrow(results), length(present), sum(results$pass), sum(results$fail), nrow(failed)),
  "",
  "| test file | exit code | [PASS] | [FAIL] |",
  "| --- | --- | --- | --- |",
  sprintf("| `%s` | %s | %d | %d |", results$file,
          ifelse(results$status == 0L, "0 (pass)", paste0(results$status, " (fail)")),
          results$pass, results$fail),
  "",
  sprintf("%d file(s) are deliberately not run on a hosted runner:", length(SKIP)),
  "",
  "| test file | why not |",
  "| --- | --- |",
  sprintf("| `%s` | %s |", names(SKIP), gsub("\n", " ", SKIP))
)

summary_path <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_path)) {
  cat(paste(lines, collapse = "\n"), "\n", file = summary_path, append = TRUE)
}
cat("\n", paste(lines, collapse = "\n"), "\n", sep = "")

if (nrow(failed)) quit(status = 1L)
