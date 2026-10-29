# ==============================================================================
# tests/test_batch_c_viz.R
# Path: tests/test_batch_c_viz.R
#
# Validation suite for Batch C NBA Visualizations (GitHub Issues #57, #58, #59):
#   1. tools/gif_rapm_race.R (Issue #57)
#   2. tools/gif_clutch_shot_worm.R (Issue #58)
#   3. tools/gif_rookie_impact_race.R (Issue #59)
#
# Validates:
#   - Each script exists and sources tools/viz_common.R
#   - Each script executes cleanly (exit status 0)
#   - Each script produces non-zero byte .gif and .png artifacts in cache/ and web/public/media/
#
# Usage:
#   Rscript tests/test_batch_c_viz.R
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

cat(sprintf("=== NBA Viz Batch C Test Suite (Repo root: %s) ===\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: File Existence & viz_common.R Sourcing
# ------------------------------------------------------------------------------
cat("\n[Test 1] Checking script files and viz_common.R dependencies...\n")

scripts <- c(
  "tools/gif_rapm_race.R",
  "tools/gif_clutch_shot_worm.R",
  "tools/gif_rookie_impact_race.R"
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
cat("\n[Test 2] Executing Batch C animation scripts and validating dual artifacts...\n")

artifacts_spec <- list(
  list(
    script = "tools/gif_rapm_race.R",
    gif = "cache/gif_rapm_race.gif",
    png = "cache/gif_rapm_race.png",
    media_gif = "web/public/media/gif_rapm_race.gif",
    media_png = "web/public/media/gif_rapm_race.png"
  ),
  list(
    script = "tools/gif_clutch_shot_worm.R",
    gif = "cache/gif_clutch_shot_worm.gif",
    png = "cache/gif_clutch_shot_worm.png",
    media_gif = "web/public/media/gif_clutch_shot_worm.gif",
    media_png = "web/public/media/gif_clutch_shot_worm.png"
  ),
  list(
    script = "tools/gif_rookie_impact_race.R",
    gif = "cache/gif_rookie_impact_race.gif",
    png = "cache/gif_rookie_impact_race.png",
    media_gif = "web/public/media/gif_rookie_impact_race.gif",
    media_png = "web/public/media/gif_rookie_impact_race.png"
  )
)

for (item in artifacts_spec) {
  cat(sprintf("\n--- Executing %s ---\n", item$script))
  script_full <- file.path(REPO_ROOT, item$script)
  res <- system2("Rscript", args = c(script_full), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status")
  if (!is.null(status) && status != 0) {
    cat(paste(res, collapse = "\n"), "\n")
    stop(sprintf("FAILED: %s exited with non-zero status %d", item$script, status))
  }
  cat(sprintf("  Executed %s successfully.\n", item$script))

  # Verify cache artifacts
  gif_full <- file.path(REPO_ROOT, item$gif)
  png_full <- file.path(REPO_ROOT, item$png)
  if (!file.exists(gif_full) || file.info(gif_full)$size == 0) {
    stop(sprintf("FAILED: Missing or 0-byte cache GIF: %s", gif_full))
  }
  if (!file.exists(png_full) || file.info(png_full)$size == 0) {
    stop(sprintf("FAILED: Missing or 0-byte cache PNG: %s", png_full))
  }

  # Verify web/public/media sync artifacts
  media_gif_full <- file.path(REPO_ROOT, item$media_gif)
  media_png_full <- file.path(REPO_ROOT, item$media_png)
  if (!file.exists(media_gif_full) || file.info(media_gif_full)$size == 0) {
    stop(sprintf("FAILED: Missing or 0-byte web media GIF: %s", media_gif_full))
  }
  if (!file.exists(media_png_full) || file.info(media_png_full)$size == 0) {
    stop(sprintf("FAILED: Missing or 0-byte web media PNG: %s", media_png_full))
  }

  cat(sprintf("  PASS: Dual artifacts verified:\n    Cache GIF: %s (%d bytes)\n    Cache PNG: %s (%d bytes)\n    Media GIF: %s (%d bytes)\n    Media PNG: %s (%d bytes)\n",
              item$gif, file.info(gif_full)$size,
              item$png, file.info(png_full)$size,
              item$media_gif, file.info(media_gif_full)$size,
              item$media_png, file.info(media_png_full)$size))
}

cat("\n=======================================================\n")
cat("ALL BATCH C VIZ TESTS PASSED CLEANLY!\n")
cat("=======================================================\n")
