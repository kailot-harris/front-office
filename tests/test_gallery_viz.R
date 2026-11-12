# ==============================================================================
# tests/test_gallery_viz.R
#
# Ported from the NBA Analytics repo's tests/test_phase2_viz.R (GitHub issue
# #144, part of #140's gallery-chart epic). Chart-test harness for the WNBA
# gallery charts (tools/gif_*.R) that phases 2-4 of #140 will add -- separate
# issues, not part of this plumbing port.
#
# As of this writing NO gif_*.R chart script exists yet in this repo (#144 is
# plumbing only), so `SCRIPTS` below is intentionally empty. This file still
# runs to completion -- it is meant to be the harness those later issues
# extend by appending to SCRIPTS, not something they need to rewrite.
#
# Validates, for each entry added to SCRIPTS:
#   - The script exists and sources tools/viz_common.R
#   - The script executes cleanly (exit status 0), OR exits non-zero with
#     [SKIP-NO-DATA] in stderr (an honest "no real data available" skip, not
#     a failure -- see tools/viz_common.R's VIZ_NO_DATA_MARKER/
#     viz_stop_no_data()), OR exits non-zero for any other reason (a fail)
#   - A zero-exit script produces both its .gif and reduced-motion .png
#     artifacts, non-zero size
#
# Usage:
#   Rscript.exe tests/test_gallery_viz.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

cat(sprintf("=== WNBA Gallery Viz Test Suite (Repo root: %s) ===\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Chart registry. Each entry: script path (relative to repo root), and the
# .gif/.png artifact paths it is expected to produce. Append here as phases
# 2-4 of #140 land gif_*.R scripts -- do not hardcode a chart's artifact path
# anywhere else.
# ------------------------------------------------------------------------------
SCRIPTS <- list(
  # Intentionally empty at phase 1 (#144). Example shape for the next chart
  # to register itself with:
  #   list(
  #     script = "tools/gif_<chart_name>.R",
  #     gif    = "cache/gif_<chart_name>.gif",
  #     png    = "cache/gif_<chart_name>.png"
  #   )
)

if (length(SCRIPTS) == 0) {
  cat("\n[Test] No gallery chart scripts are registered yet (phase 1 plumbing only -- see #144). Harness ran to completion with nothing to test.\n")
  cat("\n>>> GALLERY VIZ TEST SUITE: NOTHING REGISTERED, HARNESS OK <<<\n")
  quit(status = 0)
}

# ------------------------------------------------------------------------------
# Test 1: File Existence & viz_common.R Sourcing
# ------------------------------------------------------------------------------
cat("\n[Test 1] Checking script files and viz_common.R dependencies...\n")

for (spec in SCRIPTS) {
  full_path <- file.path(REPO_ROOT, spec$script)
  if (!file.exists(full_path)) {
    stop(sprintf("FAILED: Script %s does not exist!", full_path))
  }
  lines <- readLines(full_path, warn = FALSE)
  has_source <- any(grepl("viz_common\\.R", lines))
  if (!has_source) {
    stop(sprintf("FAILED: Script %s does not source tools/viz_common.R!", spec$script))
  }
  cat(sprintf("  PASS: %s exists and sources viz_common.R\n", spec$script))
}

# ------------------------------------------------------------------------------
# Test 2: Execution and three-way Pass / Skip / Fail classification
# ------------------------------------------------------------------------------
cat("\n[Test 2] Executing gallery chart scripts and classifying results...\n")

n_pass <- 0L
n_skip <- 0L

for (spec in SCRIPTS) {
  script_path <- file.path(REPO_ROOT, spec$script)
  gif_path <- file.path(REPO_ROOT, spec$gif)
  png_path <- file.path(REPO_ROOT, spec$png)

  # Remove pre-existing outputs to ensure fresh production
  if (file.exists(gif_path)) unlink(gif_path)
  if (file.exists(png_path)) unlink(png_path)

  cat(sprintf("\n  -> Executing: %s\n", spec$script))
  res <- system2(
    command = "Rscript",
    args = c(sprintf('"%s"', script_path)),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) {
    # A script that refuses to draw without its real input data is an
    # expected skip on a fresh clone or CI runner (no cache/, shallow git
    # history), not a pass and not a failure -- see viz_stop_no_data().
    no_data <- grep("[SKIP-NO-DATA]", res, fixed = TRUE, value = TRUE)
    if (length(no_data)) {
      cat(sprintf("  SKIP: %s\n", sub("^Error: ", "", no_data[1])))
      n_skip <- n_skip + 1L
      next
    }
    cat(paste(res, collapse = "\n"), "\n")
    stop(sprintf("FAILED: Script %s exited with non-zero status %d!", spec$script, status))
  }

  # Validate GIF artifact
  if (!file.exists(gif_path)) {
    stop(sprintf("FAILED: Expected GIF artifact %s was not created!", gif_path))
  }
  gif_size <- file.info(gif_path)$size
  if (is.na(gif_size) || gif_size <= 0) {
    stop(sprintf("FAILED: GIF artifact %s has size <= 0 (%d bytes)!", gif_path, gif_size))
  }

  # Validate PNG artifact
  if (!file.exists(png_path)) {
    stop(sprintf("FAILED: Expected PNG artifact %s was not created!", png_path))
  }
  png_size <- file.info(png_path)$size
  if (is.na(png_size) || png_size <= 0) {
    stop(sprintf("FAILED: PNG artifact %s has size <= 0 (%d bytes)!", png_path, png_size))
  }

  cat(sprintf("  PASS: %s successfully generated:\n    GIF: %s (%d bytes)\n    PNG: %s (%d bytes)\n",
              spec$script, gif_path, gif_size, png_path, png_size))
  n_pass <- n_pass + 1L
}

cat(sprintf("\n>>> GALLERY VIZ TEST SUITE PASSED (%d rendered, %d skipped no-data) <<<\n", n_pass, n_skip))
