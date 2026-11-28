# ==============================================================================
# tests/test_publish_log_scan.R
#
# Publish gate assertion D (.scan_stage_warnings / .assert_log_scan) in
# tools/publish_web.R: the stage scan of the pipeline log must count the
# runner's [WARN], [FAIL] and [FAILED] lines from the latest run only, and stay
# non-fatal unless fail_on_warnings is set. The log lines are written inline;
# they describe the runner's own messages, not any sports data.
#
# Usage: Rscript tests/test_publish_log_scan.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

old_wd <- getwd()
setwd(REPO_ROOT)
source(file.path(REPO_ROOT, "tools", "publish_web.R"))
setwd(old_wd)

n_pass <- 0L
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) {
    n_pass <<- n_pass + 1L
    cat("  PASS:", label, "\n")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL:", label, "\n")
  }
}

log_lines <- c(
  ">>> NBA QUANTITATIVE ENGINE v5.0 STARTED: earlier run",
  "  >>> [FAILED] build_old_stage.R: from the earlier run",
  ">>> NBA QUANTITATIVE ENGINE v5.0 STARTED: latest run",
  ">>> [OK] build_ok_stage.R",
  "  >>> [FAILED] build_momentum_dataset.R: non-numeric argument to mathematical function",
  ">>> [WARN] build_x.R: declared output 'x.json' was NOT rewritten",
  ">>> [FAIL] build_y.R: output check failed",
  "Warning message: unrelated text mentioning FAILED without the marker")

cat("\n[1] stage scan counts [FAILED] lines\n")
hits <- .scan_stage_warnings(log_lines)
check(any(grepl("[FAILED] build_momentum_dataset.R", hits, fixed = TRUE)),
      "assertion D matches a '>>> [FAILED] <stage>: <message>' line")
check(length(hits) == 3L, "assertion D counts [FAILED], [WARN] and [FAIL] lines of the latest run only")
check(!any(grepl("build_old_stage.R", hits, fixed = TRUE)), "lines before the last run-start banner are ignored")

cat("\n[2] assertion D stays non-fatal by default\n")
d <- .assert_log_scan(log_lines, fail_on_warnings = FALSE)
check(identical(d$id, "D") && isTRUE(d$pass) && isFALSE(d$fatal),
      "a [FAILED] line is reported but does not fail the gate when non-fatal")
check(grepl("^3 stage warning", d$summary), "summary reports the [FAILED] line in its count")
d_fatal <- .assert_log_scan(log_lines[c(3, 5)], fail_on_warnings = TRUE)
check(isFALSE(d_fatal$pass), "a lone [FAILED] line fails the gate when fail_on_warnings is set")

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
if (n_fail > 0L) quit(status = 1L)
