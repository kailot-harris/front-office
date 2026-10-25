# ==============================================================================
# tools/test_phase4_cleanup.R
# ------------------------------------------------------------------------------
# Verification suite for Phase 4 task P4-F (agent_cleanup): findings L-2 (tools/
# half), L-3 and L-5.
#
# CHECK 1 (L-2) no stale "ROLLING_WINDOW_SIZE = 13" literal in ml_cv_benchmark.R
# CHECK 2 (L-3) turnover column is consistent within each feature block
# CHECK 3 (L-5) no temp_*.R scratch files remain at repo root
# CHECK 4 (L-5) .gitignore exists and ignores .Rhistory
# CHECK 5 (L-3) tools/ml_cv_benchmark.R still runs end to end after the rename
#
# CHECK 5 runs the real LOSO CV benchmark as a subprocess (several minutes). The
# benchmark writes cache/ml_benchmark_cv_results.rds; Phase 4's Wave 2 rules
# forbid mutating cached .rds artifacts, so this suite snapshots that file to a
# tempdir before the run and restores it byte-for-byte afterwards.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe tools/test_phase4_cleanup.R
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
      stop(sprintf("test_phase4_cleanup.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

failures <- 0L

report <- function(ok, id, desc, detail = "") {
  if (!ok) failures <<- failures + 1L
  cat(sprintf("[%s] %s %s%s\n", if (ok) "PASS" else "FAIL", id, desc,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("=== Phase 4 Wave 2 cleanup tests (P4-F / agent_cleanup) ===\n\n")

# ------------------------------------------------------------------------------
# CHECK 1 (L-2): the stale value-restating comment is gone.
# Equivalent of: grep -c "ROLLING_WINDOW_SIZE = 13" tools/ml_cv_benchmark.R -> 0
# ------------------------------------------------------------------------------
bench_path <- "tools/ml_cv_benchmark.R"
bench_lines <- readLines(bench_path, warn = FALSE)

stale_hits <- grep("ROLLING_WINDOW_SIZE\\s*=\\s*13", bench_lines)
cat(sprintf("  grep -c 'ROLLING_WINDOW_SIZE = 13' %s -> %d\n", bench_path, length(stale_hits)))
if (length(stale_hits) > 0) {
  cat(paste0("    line ", stale_hits, ": ", trimws(bench_lines[stale_hits]), "\n"))
}
report(length(stale_hits) == 0L, "CHECK 1 (L-2)",
       "no stale 'ROLLING_WINDOW_SIZE = 13' literal in ml_cv_benchmark.R",
       sprintf("%d match(es)", length(stale_hits)))

# The comment must still cite the constant by NAME, and the code must still read it.
cites_name <- any(grepl("ROLLING_WINDOW_SIZE", bench_lines[grepl("^\\s*#", bench_lines)]))
reads_const <- any(grepl("window_size\\s*=\\s*ROLLING_WINDOW_SIZE", bench_lines))
report(cites_name && reads_const, "CHECK 1b (L-2)",
       "comment cites the constant's name and the code still reads the live constant",
       sprintf("comment_cites_name=%s, code_reads_constant=%s", cites_name, reads_const))

# Sanity: the live value in config.R is whatever config.R says, and nothing here
# restates it. Read it rather than trusting any number written in a comment.
source("config.R")
cat(sprintf("  config.R's live ROLLING_WINDOW_SIZE = %d (read, not assumed)\n", ROLLING_WINDOW_SIZE))

# ------------------------------------------------------------------------------
# CHECK 2 (L-3): within one feature block, the four-factors turnover RATE and the
# rolling turnover COUNT must aggregate the SAME cache column.
# ------------------------------------------------------------------------------
# Extract, per feature-building function, the column feeding `tov =` and the one
# feeding `roll_tov =`.
extract_tov_pairs <- function(path) {
  lines <- readLines(path, warn = FALSE)
  # strip comment-only lines so commented-out examples can't match
  code <- lines[!grepl("^\\s*#", lines)]
  rate_col <- regmatches(code, regexpr("(?<=^\\s{0,20}tov\\s{0,5}=\\s{0,5})\\w+", code, perl = TRUE))
  roll_col <- regmatches(code,
    regexpr("(?<=roll_tov\\s{0,10}=\\s{0,10}(slide_dbl|ewma_prior)\\()\\s*\\w+", code, perl = TRUE))
  list(rate = trimws(rate_col), roll = trimws(roll_col))
}

for (p in c("tools/ml_cv_benchmark.R", "tools/ml_feature_experiments.R")) {
  pr <- extract_tov_pairs(p)
  cat(sprintf("\n  %s\n    tov rate column(s) : %s\n    roll_tov column(s) : %s\n",
              p, paste(pr$rate, collapse = ", "), paste(pr$roll, collapse = ", ")))
  all_cols <- unique(c(pr$rate, pr$roll))
  ok <- length(pr$rate) > 0 && length(pr$roll) > 0 &&
        length(all_cols) == 1L && all_cols == "total_turnovers"
  report(ok, "CHECK 2 (L-3)",
         sprintf("%s uses ONE turnover column for both rate and rolling feature", basename(p)),
         sprintf("distinct column(s) = {%s}", paste(all_cols, collapse = ", ")))
}

# No bare `turnovers` (the other, non-equal cache column) survives as a feature source.
for (p in c("tools/ml_cv_benchmark.R", "tools/ml_feature_experiments.R")) {
  code <- readLines(p, warn = FALSE)
  code <- code[!grepl("^\\s*#", code)]
  bare <- grep("(?<![_a-zA-Z])turnovers(?![_a-zA-Z])", code, perl = TRUE, value = TRUE)
  report(length(bare) == 0L, "CHECK 2b (L-3)",
         sprintf("%s has no bare `turnovers` column reference left in code", basename(p)),
         sprintf("%d occurrence(s)", length(bare)))
}

# Empirical grounding for the choice: prove the two columns really are different,
# so the fix is a real decision and not cosmetic.
if (file.exists(CACHE_TEAM_BOX)) {
  bx <- readRDS(CACHE_TEAM_BOX)
  if (all(c("turnovers", "total_turnovers") %in% names(bx))) {
    cat(sprintf("\n  cache columns -- mean(turnovers)=%.2f  mean(total_turnovers)=%.2f  identical=%s\n",
                mean(bx$turnovers, na.rm = TRUE), mean(bx$total_turnovers, na.rm = TRUE),
                identical(bx$turnovers, bx$total_turnovers)))
    report(!identical(bx$turnovers, bx$total_turnovers), "CHECK 2c (L-3)",
           "`turnovers` and `total_turnovers` are genuinely distinct columns (so the pick matters)")
  }
}

# ------------------------------------------------------------------------------
# CHECK 3 (L-5): no temp_*.R scratch files at repo root.
# ------------------------------------------------------------------------------
leftover <- Sys.glob("temp_*.R")
cat(sprintf("\n  Sys.glob('temp_*.R') from project root -> %s\n",
            if (length(leftover) == 0) "character(0)" else paste(leftover, collapse = ", ")))
report(length(leftover) == 0L, "CHECK 3 (L-5)",
       "no temp_*.R scratch files remain at repo root",
       sprintf("%d found", length(leftover)))

# The absorbed replacement must actually exist and be syntactically valid.
repl <- "tools/derive_props_distribution_params.R"
parse_ok <- file.exists(repl) && !inherits(try(parse(repl), silent = TRUE), "try-error")
report(parse_ok, "CHECK 3b (L-5)",
       "tools/derive_props_distribution_params.R exists and parses",
       sprintf("exists=%s", file.exists(repl)))

# ------------------------------------------------------------------------------
# CHECK 4 (L-5): .gitignore exists and ignores .Rhistory.
# ------------------------------------------------------------------------------
gi_path <- ".gitignore"
gi_exists <- file.exists(gi_path)
gi <- if (gi_exists) readLines(gi_path, warn = FALSE) else character(0)
gi_rules <- trimws(gi[!grepl("^\\s*#", gi) & nzchar(trimws(gi))])
has_rhistory <- ".Rhistory" %in% gi_rules
cat(sprintf("\n  .gitignore exists=%s, %d active rule(s), '.Rhistory' present=%s\n",
            gi_exists, length(gi_rules), has_rhistory))
report(gi_exists && has_rhistory, "CHECK 4 (L-5)",
       ".gitignore exists at repo root and contains .Rhistory")

# Extension agreed with the orchestrator: runtime log churn is diff noise.
log_rules <- gi_rules[grepl("^logs/", gi_rules)]
cat(sprintf("  logs/ rules: %s\n", paste(log_rules, collapse = ", ")))
report(length(log_rules) > 0L, "CHECK 4b (L-5)",
       ".gitignore also ignores runtime logs/ churn",
       sprintf("%d rule(s)", length(log_rules)))

# ------------------------------------------------------------------------------
# CHECK 5 (L-3): the CV pipeline still completes end to end after the rename.
# ------------------------------------------------------------------------------
cat("\n  Running tools/ml_cv_benchmark.R end to end (real LOSO CV, several minutes)...\n")

results_rds <- file.path("cache", "ml_benchmark_cv_results.rds")
snapshot <- file.path(tempdir(), "ml_benchmark_cv_results.PRE_P4F.rds")
had_prior <- file.exists(results_rds)
if (had_prior) {
  file.copy(results_rds, snapshot, overwrite = TRUE)
  cat(sprintf("  (snapshotted existing %s -> tempdir, will restore: Wave 2 must not mutate caches)\n",
              results_rds))
}

rscript <- file.path(R.home("bin"), "Rscript.exe")
t0 <- Sys.time()
out <- suppressWarnings(system2(rscript, "tools/ml_cv_benchmark.R",
                                stdout = TRUE, stderr = TRUE))
status <- attr(out, "status")
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
exit_code <- if (is.null(status)) 0L else as.integer(status)

cat(sprintf("  benchmark exit code = %d, elapsed = %.1f min\n", exit_code, elapsed))
cat("  ---- last 12 lines of benchmark output ----\n")
cat(paste0("  ", tail(out, 12), collapse = "\n"), "\n")

wrote_results <- file.exists(results_rds)
saved_ok <- FALSE
if (wrote_results) {
  res <- try(readRDS(results_rds), silent = TRUE)
  saved_ok <- !inherits(res, "try-error") &&
              all(c("baseline_boot_ci", "improved_boot_ci") %in% names(res))
  if (saved_ok) {
    bl <- res$baseline_boot_ci
    cat("  ---- post-rename pooled out-of-fold metrics (baseline) ----\n")
    print(bl)
  }
}

report(exit_code == 0L && saved_ok, "CHECK 5 (L-3)",
       "ml_cv_benchmark.R completes end to end after the turnover-column rename",
       sprintf("exit=%d, results object valid=%s", exit_code, saved_ok))

# Restore the pre-existing cache artifact (Wave 2 constraint: no cache mutation;
# regeneration is Wave 3's P4-G).
if (had_prior) {
  file.copy(snapshot, results_rds, overwrite = TRUE)
  cat(sprintf("  restored %s from snapshot (cache left byte-identical to pre-test state)\n",
              results_rds))
} else if (wrote_results) {
  unlink(results_rds)
  cat(sprintf("  removed %s (did not exist before this test)\n", results_rds))
}

cat(sprintf("\n=== %s: %d check(s) failed ===\n",
            if (failures == 0L) "ALL CHECKS PASSED" else "FAILURES PRESENT", failures))
quit(save = "no", status = if (failures == 0L) 0L else 1L)
