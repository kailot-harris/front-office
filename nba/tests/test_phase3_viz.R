# ==============================================================================
# tests/test_phase3_viz.R
# Path: tests/test_phase3_viz.R
#
# Validation suite for Phase 3 NBA Visualization:
#   1. Verifies tools/plot_shot_chart.R and tools/gif_player_shot_chart.R exist and
#      successfully source tools/viz_common.R.
#   2. Validates spatial court geometry coordinate bounds and transformation functions.
#   3. Generates a static high-res shot chart PNG from cached shots data, verifying
#      non-zero file size.
#   4. Generates an animated shot chart GIF with static PNG fallback via
#      generate_player_shot_chart_gif() and render_animated_artifact(), verifying both
#      files exist and have non-zero file sizes.
#
# Usage: Rscript tests/test_phase3_viz.R
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

cat("=== Phase 3 Viz Validation Suite ===\n")
cat(sprintf("Working root: %s\n", REPO_ROOT))

# ------------------------------------------------------------------------------
# Test 1: Verify tools exist and source tools/viz_common.R
# ------------------------------------------------------------------------------
cat("\n[Test 1] Sourcing tools/plot_shot_chart.R and tools/gif_player_shot_chart.R...\n")
plot_script <- file.path(REPO_ROOT, "tools", "plot_shot_chart.R")
gif_script  <- file.path(REPO_ROOT, "tools", "gif_player_shot_chart.R")

stopifnot(file.exists(plot_script))
stopifnot(file.exists(gif_script))

source(plot_script)
source(gif_script)

stopifnot(exists("plot_half_court_shot_chart", mode = "function"))
stopifnot(exists("export_shot_chart_png", mode = "function"))
stopifnot(exists("normalize_shot_coordinates", mode = "function"))
stopifnot(exists("generate_player_shot_chart_gif", mode = "function"))
stopifnot(exists("theme_nba_dark", mode = "function"))
stopifnot(exists("render_animated_artifact", mode = "function"))
cat("  PASS: Both tools sourced cleanly and exported expected functions.\n")

# ------------------------------------------------------------------------------
# Test 2: Court Geometry and Coordinate Transformation
# ------------------------------------------------------------------------------
cat("\n[Test 2] Testing coordinate transformations and regulation boundaries...\n")
mock_raw_shots <- data.frame(
  athlete_name_1   = c("Player A", "Player B", "Player C"),
  team_name        = c("Boston Celtics", "Los Angeles Lakers", "Golden State Warriors"),
  coordinate_x_raw = c(25, 5, 47),
  coordinate_y_raw = c(1.25, 20, 0),
  scoring_play     = c(TRUE, FALSE, TRUE),
  stringsAsFactors = FALSE
)

norm_shots <- normalize_shot_coordinates(mock_raw_shots)
stopifnot(nrow(norm_shots) == 3)
# Rim is at x=0, y=5.25. Player A coordinate_x_raw=25 => x=0, y_raw=1.25 => y=5.25 => dist = 0.0
stopifnot(identical(norm_shots$x[1], 0.0))
stopifnot(identical(norm_shots$y[1], 5.25))
stopifnot(identical(norm_shots$dist[1], 0.0))
stopifnot(identical(norm_shots$made[1], TRUE))
stopifnot(identical(norm_shots$team_abbrev[1], "BOS"))
cat("  PASS: Coordinate transformation and team abbreviation mapping verified.\n")

# ------------------------------------------------------------------------------
# Test 3: Generate static shot chart PNG & verify non-zero size
# ------------------------------------------------------------------------------
cat("\n[Test 3] Generating static shot chart PNG from sample / cache data...\n")
test_out_dir <- file.path(tempdir(), "test_phase3_out")
if (!dir.exists(test_out_dir)) dir.create(test_out_dir, recursive = TRUE)

static_png_path <- file.path(test_out_dir, "test_static_shot_chart.png")
if (file.exists(static_png_path)) unlink(static_png_path)

# Try loading cache, fallback to synthetic realistic dataset if cache not present
cached_shots <- load_nba_shots_cache(season = 2026, cache_dirs = c(file.path(REPO_ROOT, "cache"), "cache"))
if (nrow(cached_shots) < 20) {
  set.seed(42)
  cached_shots <- data.frame(
    player_name = "Test Shooter",
    team_abbrev = "BOS",
    x = rnorm(100, mean = 0, sd = 10),
    y = runif(100, min = 2, max = 35),
    made = sample(c(TRUE, FALSE), 100, replace = TRUE, prob = c(0.48, 0.52)),
    stringsAsFactors = FALSE
  )
}

sample_shots <- head(cached_shots, 75)
p_static <- plot_half_court_shot_chart(
  shot_data = sample_shots,
  player_name = sample_shots$player_name[1],
  team = sample_shots$team_abbrev[1],
  density_contours = TRUE
)

export_shot_chart_png(p_static, static_png_path, width = 8, height = 7.5, dpi = 150)

stopifnot(file.exists(static_png_path))
static_size <- file.info(static_png_path)$size
cat(sprintf("  Generated static PNG: %s (Size: %d bytes)\n", static_png_path, static_size))
stopifnot(static_size > 5000)
cat("  PASS: Static shot chart PNG verified with non-zero size.\n")

# ------------------------------------------------------------------------------
# Test 4: Generate animated shot chart GIF with PNG fallback & verify non-zero size
# ------------------------------------------------------------------------------
cat("\n[Test 4] Generating animated rolling shot evolution GIF + PNG fallback...\n")
anim_gif_path <- file.path(test_out_dir, "test_shot_evolution.gif")
anim_png_path <- file.path(test_out_dir, "test_shot_evolution.png")

if (file.exists(anim_gif_path)) unlink(anim_gif_path)
if (file.exists(anim_png_path)) unlink(anim_png_path)

anim_result <- generate_player_shot_chart_gif(
  shot_data = sample_shots,
  player_name = sample_shots$player_name[1],
  team = sample_shots$team_abbrev[1],
  gif_path = anim_gif_path,
  png_path = anim_png_path,
  n_frames = 5,
  window_mode = "cumulative",
  fps = 2,
  hold_last_frames = 2,
  width_px = 640,
  height_px = 600
)

stopifnot(file.exists(anim_gif_path))
stopifnot(file.exists(anim_png_path))

gif_size <- file.info(anim_gif_path)$size
png_size <- file.info(anim_png_path)$size

cat(sprintf("  Generated animated GIF: %s (Size: %d bytes)\n", anim_gif_path, gif_size))
cat(sprintf("  Generated fallback PNG: %s (Size: %d bytes)\n", anim_png_path, png_size))

stopifnot(gif_size > 5000)
stopifnot(png_size > 5000)
cat("  PASS: Animated GIF and fallback PNG verified with non-zero sizes.\n")

cat("\n=== All Phase 3 Visualization Tests Passed Successfully! ===\n")
