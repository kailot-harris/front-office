# ==============================================================================
# tests/test_phase4_viz.R
# Path: tests/test_phase4_viz.R
#
# Validation suite for Phase 4 NBA Visualization:
#   1. Verifies tools/build_series_trajectory_gif.R and tools/gif_playoff_prob_bump.R
#      exist and successfully source tools/viz_common.R.
#   2. Executes both scripts cleanly (exit status 0).
#   3. Validates that both scripts produce both their corresponding .gif and .png
#      artifacts with non-zero byte size.
#
# Usage:
#   Rscript tests/test_phase4_viz.R
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

cat(sprintf("=== NBA Viz Phase 4 Validation Suite (Repo root: %s) ===\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: File Existence & viz_common.R Sourcing Check
# ------------------------------------------------------------------------------
cat("\n[Test 1] Verifying Phase 4 scripts exist and source tools/viz_common.R...\n")

scripts <- c(
  "tools/build_series_trajectory_gif.R",
  "tools/gif_playoff_prob_bump.R"
)

for (s in scripts) {
  full_path <- file.path(REPO_ROOT, s)
  if (!file.exists(full_path)) {
    stop(sprintf("FAILED: Script %s does not exist!", full_path))
  }
  lines <- readLines(full_path, warn = FALSE)
  has_source <- any(grepl("viz_common\\.R", lines))
  if (!has_source) {
    stop(sprintf("FAILED: Script %s does not source tools/viz_common.R!", s))
  }
  cat(sprintf("  PASS: %s exists and sources tools/viz_common.R\n", s))
}

# ------------------------------------------------------------------------------
# Test 2: Execution and Dual Artifact Generation
# ------------------------------------------------------------------------------
cat("\n[Test 2] Executing Phase 4 visualization scripts and validating dual artifacts...\n")

artifacts_spec <- list(
  list(
    script = "tools/build_series_trajectory_gif.R",
    gif = "cache/build_series_trajectory_gif.gif",
    png = "cache/build_series_trajectory_gif.png"
  ),
  list(
    script = "tools/gif_playoff_prob_bump.R",
    gif = "cache/gif_playoff_prob_bump.gif",
    png = "cache/gif_playoff_prob_bump.png"
  )
)

for (spec in artifacts_spec) {
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
}

cat("\n>>> ALL PHASE 4 VALIDATION TESTS PASSED SUCCESSFULLY! <<<\n")
