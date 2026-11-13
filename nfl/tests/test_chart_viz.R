# ==============================================================================
# tests/test_chart_viz.R
#
# Minimal chart-script test harness for kailot-harris/front-office#142 (NFL
# share), ported from the pattern in NBA Analytics/tests/test_batch_a_viz.R.
#
# The problem this closes: before this task, this repo's chart tests (there
# were none at all for tools/gif_*.R / tools/plot_*.R) only ever checked "did
# a file get produced" - so on a cache-less runner, a fabricated-data fallback
# path would have been the only path ever exercised, and it would have
# "passed". This harness instead classifies every run into three distinct,
# separately-reported outcomes:
#
#   PASS  - script exited 0 and produced a non-zero-byte artifact (real data
#           was available and rendered).
#   SKIP  - script exited non-zero AND its output contains the
#           tools/viz_common.R VIZ_NO_DATA_MARKER ("[SKIP-NO-DATA]") - i.e. it
#           correctly refused to fabricate a chart rather than drawing one
#           from invented values. Expected on a fresh clone / cache-less CI
#           runner; not a failure.
#   FAIL  - script exited non-zero with NO no-data marker (a real error), or
#           exited 0 but produced no/empty artifact.
#
# Part A below proves the SKIP vs FAIL classification logic itself, using two
# throwaway temp scripts (one that calls viz_stop_no_data(), one that errors
# normally) - this does not depend on this machine's cache/ state, so it
# demonstrates a real skip-vs-failure distinction deterministically in any
# environment, including a cache-less CI runner with no real nflverse data.
#
# Part B then exercises a couple of this repo's real tools/plot_*.R scripts
# against whatever cache/ this machine actually has, reporting PASS/SKIP/FAIL
# for real. Part B is advisory: a FAIL there (e.g. missing cache/ on a fresh
# CI runner with no nflverse data fetched) is logged distinctly but is not
# itself asserted into this file's pass/fail count, since this repo's chart
# scripts do not yet all call viz_stop_no_data() on every missing-input path
# (tracked separately; out of scope for this task per front-office#142's NFL
# brief, which is the static check + this harness, not rewriting every
# chart script's fallback branches).
#
# Usage:
#   Rscript tests/test_chart_viz.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "tools", "viz_common.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "tools", "viz_common.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

cat(sprintf("=== NFL Chart Viz Test Suite (Repo root: %s) ===\n", REPO_ROOT))
source(file.path(REPO_ROOT, "tools", "viz_common.R"))

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

#' Run an R script in its own process and classify the outcome.
#' Returns a list(status = "PASS"|"SKIP"|"FAIL", output = character vector).
classify_run <- function(script_path, artifact_path = NULL) {
  res <- system2("Rscript", shQuote(script_path), stdout = TRUE, stderr = TRUE)
  st <- attr(res, "status")
  st <- if (is.null(st)) 0L else st

  no_data <- grep(VIZ_NO_DATA_MARKER, res, fixed = TRUE, value = TRUE)
  if (st != 0L) {
    if (length(no_data)) {
      return(list(status = "SKIP", output = res, detail = sub("^Error: ", "", no_data[1])))
    }
    return(list(status = "FAIL", output = res, detail = sprintf("exit status %d", st)))
  }

  if (!is.null(artifact_path)) {
    if (!file.exists(artifact_path) || file.info(artifact_path)$size <= 0) {
      return(list(status = "FAIL", output = res, detail = sprintf("no/empty artifact at %s", artifact_path)))
    }
  }
  list(status = "PASS", output = res, detail = "rendered")
}

# ------------------------------------------------------------------------------
# Part A: prove SKIP vs FAIL classification is distinct and deterministic,
# independent of this machine's cache/ state.
# ------------------------------------------------------------------------------
cat("\n[Part A] SKIP-vs-FAIL classification (synthetic, cache-independent)...\n")

tmp_skip <- tempfile(fileext = ".R")
writeLines(c(
  sprintf('source("%s")', gsub("\\\\", "/", file.path(REPO_ROOT, "tools", "viz_common.R"))),
  'viz_stop_no_data("fixture", "no real input for this synthetic test.")'
), tmp_skip)

tmp_fail <- tempfile(fileext = ".R")
writeLines('stop("deliberate ordinary error - not a no-data skip.")', tmp_fail)

on.exit({
  unlink(tmp_skip)
  unlink(tmp_fail)
}, add = TRUE)

skip_result <- classify_run(tmp_skip)
fail_result <- classify_run(tmp_fail)

cat(sprintf("  SKIP fixture classified as: %s (%s)\n", skip_result$status, skip_result$detail))
cat(sprintf("  FAIL fixture classified as: %s (%s)\n", fail_result$status, fail_result$detail))

ok("viz_stop_no_data() fixture is classified SKIP, not FAIL", identical(skip_result$status, "SKIP"))
ok("ordinary stop() fixture is classified FAIL, not SKIP", identical(fail_result$status, "FAIL"))
ok("SKIP and FAIL fixtures are reported as distinct outcomes",
   !identical(skip_result$status, fail_result$status))

# ------------------------------------------------------------------------------
# Part B: exercise real chart scripts against this machine's actual cache/
# state. Advisory only (not counted into `failures`) - see header comment.
# ------------------------------------------------------------------------------
cat("\n[Part B] Real chart script runs against this machine's cache/ (advisory)...\n")

real_specs <- list(
  list(script = "tools/plot_week5_projections.R", artifact = NULL),
  list(script = "tools/gif_elo_heatmap.R",        artifact = "cache/gif_elo_heatmap.png")
)

for (spec in real_specs) {
  script_path <- file.path(REPO_ROOT, spec$script)
  if (!file.exists(script_path)) {
    cat(sprintf("  SKIP: %s not found - skipping (advisory, not counted)\n", spec$script))
    next
  }
  artifact_path <- if (!is.null(spec$artifact)) file.path(REPO_ROOT, spec$artifact) else NULL
  res <- classify_run(script_path, artifact_path)
  cat(sprintf("  %s: %s (%s)\n", res$status, spec$script, res$detail))
  if (res$status == "FAIL") {
    cat(paste("   ", tail(res$output, 5), collapse = "\n"), "\n")
  }
}

cat(sprintf("\n=== %d assertion(s) failed ===\n", failures))
if (failures > 0L) quit(status = 1L, save = "no")
