# ==============================================================================
# tests/test_batch_a_viz.R
# Path: tests/test_batch_a_viz.R
#
# Validation suite for Batch A NBA Visualizations (GitHub Issues #50, #51, #52):
#   1. tools/gif_division_standings_race.R (Issue #50)
#   2. tools/gif_elo_heatmap.R (Issue #51)
#   3. tools/gif_elo_delta_race.R (Issue #52)
#
# Validates:
#   - Each script exists and sources tools/viz_common.R
#   - Each script executes cleanly (exit status 0)
#   - Each script produces non-zero byte .gif and .png artifacts in cache/ and web/public/media/
#
# Usage:
#   Rscript tests/test_batch_a_viz.R
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

cat(sprintf("=== NBA Viz Batch A Test Suite (Repo root: %s) ===\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: File Existence & viz_common.R Sourcing
# ------------------------------------------------------------------------------
cat("\n[Test 1] Checking script files and viz_common.R dependencies...\n")

scripts <- c(
  "tools/gif_division_standings_race.R",
  "tools/gif_elo_heatmap.R",
  "tools/gif_elo_delta_race.R"
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
cat("\n[Test 2] Executing Batch A animation scripts and validating dual artifacts...\n")

artifacts_spec <- list(
  list(
    script = "tools/gif_division_standings_race.R",
    gif = "cache/gif_division_standings_race.gif",
    png = "cache/gif_division_standings_race.png",
    media_gif = "web/public/media/gif_division_standings_race.gif",
    media_png = "web/public/media/gif_division_standings_race.png"
  ),
  list(
    script = "tools/gif_elo_heatmap.R",
    gif = "cache/gif_elo_heatmap.gif",
    png = "cache/gif_elo_heatmap.png",
    media_gif = "web/public/media/gif_elo_heatmap.gif",
    media_png = "web/public/media/gif_elo_heatmap.png"
  ),
  list(
    script = "tools/gif_elo_delta_race.R",
    gif = "cache/gif_elo_delta_race.gif",
    png = "cache/gif_elo_delta_race.png",
    media_gif = "web/public/media/gif_elo_delta_race.gif",
    media_png = "web/public/media/gif_elo_delta_race.png"
  )
)

for (spec in artifacts_spec) {
  script_path <- file.path(REPO_ROOT, spec$script)
  gif_path    <- file.path(REPO_ROOT, spec$gif)
  png_path    <- file.path(REPO_ROOT, spec$png)
  media_gif   <- file.path(REPO_ROOT, spec$media_gif)
  media_png   <- file.path(REPO_ROOT, spec$media_png)

  cat(sprintf("\n  -> Executing: %s\n", spec$script))
  res <- system2("Rscript", args = c(script_path), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) {
    cat(paste(res, collapse = "\n"), "\n")
    stop(sprintf("FAILED: %s exited with non-zero status %d", spec$script, status))
  }

  # Verify Cache GIF
  if (!file.exists(gif_path)) {
    stop(sprintf("FAILED: Target GIF %s was not created!", gif_path))
  }
  gif_size <- file.info(gif_path)$size
  if (is.na(gif_size) || gif_size <= 0) {
    stop(sprintf("FAILED: Target GIF %s has zero size!", gif_path))
  }

  # Verify Cache PNG
  if (!file.exists(png_path)) {
    stop(sprintf("FAILED: Target PNG %s was not created!", png_path))
  }
  png_size <- file.info(png_path)$size
  if (is.na(png_size) || png_size <= 0) {
    stop(sprintf("FAILED: Target PNG %s has zero size!", png_path))
  }

  # Verify Media GIF
  if (!file.exists(media_gif)) {
    stop(sprintf("FAILED: Media GIF %s was not created!", media_gif))
  }
  m_gif_size <- file.info(media_gif)$size
  if (is.na(m_gif_size) || m_gif_size <= 0) {
    stop(sprintf("FAILED: Media GIF %s has zero size!", media_gif))
  }

  # Verify Media PNG
  if (!file.exists(media_png)) {
    stop(sprintf("FAILED: Media PNG %s was not created!", media_png))
  }
  m_png_size <- file.info(media_png)$size
  if (is.na(m_png_size) || m_png_size <= 0) {
    stop(sprintf("FAILED: Media PNG %s has zero size!", media_png))
  }

  cat(sprintf("  PASS: %s successfully generated non-zero artifacts:\n    Cache GIF: %s (%d bytes)\n    Cache PNG: %s (%d bytes)\n    Media GIF: %s (%d bytes)\n    Media PNG: %s (%d bytes)\n",
              spec$script, gif_path, gif_size, png_path, png_size, media_gif, m_gif_size, media_png, m_png_size))
}

cat("\n>>> ALL BATCH A TESTS PASSED SUCCESSFULLY! <<<\n")
