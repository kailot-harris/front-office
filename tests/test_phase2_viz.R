# ==============================================================================
# tests/test_phase2_viz.R
# Path: tests/test_phase2_viz.R
#
# Test suite for Phase 2 NBA Visualization Tools:
#   1. tools/gif_elo_rank_bump.R
#   2. tools/gif_net_rating_quadrant.R
#   3. tools/gif_point_diff_race.R
#
# Validates:
#   - Each script exists and sources tools/viz_common.R
#   - Each script executes cleanly (exit status 0)
#   - Each script produces both the target .gif and reduced-motion .png artifacts
#     with non-zero byte size
#
# Usage:
#   Rscript tests/test_phase2_viz.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

cat(sprintf("=== NBA Viz Phase 2 Test Suite (Repo root: %s) ===\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: File Existence & viz_common.R Sourcing
# ------------------------------------------------------------------------------
cat("\n[Test 1] Checking script files and viz_common.R dependencies...\n")

scripts <- c(
  "tools/gif_elo_rank_bump.R",
  "tools/gif_net_rating_quadrant.R",
  "tools/gif_point_diff_race.R"
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
  cat(sprintf("  PASS: %s exists and sources viz_common.R\n", s))
}

# ------------------------------------------------------------------------------
# Test 2: Execution and Dual Artifact Generation
# ------------------------------------------------------------------------------
cat("\n[Test 2] Executing Phase 2 animation scripts and validating dual artifacts...\n")

artifacts_spec <- list(
  list(
    script = "tools/gif_elo_rank_bump.R",
    gif = "cache/gif_elo_rank_bump.gif",
    png = "cache/gif_elo_rank_bump.png"
  ),
  list(
    script = "tools/gif_net_rating_quadrant.R",
    gif = "cache/gif_net_rating_quadrant.gif",
    png = "cache/gif_net_rating_quadrant.png"
  ),
  list(
    script = "tools/gif_point_diff_race.R",
    gif = "cache/gif_point_diff_race.gif",
    png = "cache/gif_point_diff_race.png"
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

cat("\n>>> ALL PHASE 2 TESTS PASSED SUCCESSFULLY! <<<\n")
