# ==============================================================================
# tests/test_viz_common.R
# Path: tests/test_viz_common.R
#
# Unit tests for tools/viz_common.R:
#   1. theme_nba_dark() produces valid ggplot2 theme object with expected dark colors
#   2. NBA_COLORS, NBA_CONFERENCE_COLORS, NBA_DIVISION_COLORS, NBA_TEAM_COLORS integrity
#   3. resolve_team_abbr() and get_nba_team_color() correctly resolve canonical colors
#   4. render_animated_artifact() renders a 3-frame animation, holding last frames,
#      and outputs both non-zero .gif and reduced-motion .png still.
#
# Usage: Rscript tests/test_viz_common.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

viz_common_path <- file.path(REPO_ROOT, "tools", "viz_common.R")
if (!file.exists(viz_common_path)) {
  stop(sprintf("Cannot find %s", viz_common_path))
}
source(viz_common_path)

cat("=== Running tests for tools/viz_common.R ===\n")

# ------------------------------------------------------------------------------
# Test 1: Symbols and definitions exist
# ------------------------------------------------------------------------------
cat("[Test 1] Verifying symbol exports...\n")
stopifnot(exists("theme_nba_dark", mode = "function"))
stopifnot(exists("NBA_COLORS"))
stopifnot(exists("NBA_CONFERENCE_COLORS"))
stopifnot(exists("NBA_DIVISION_COLORS"))
stopifnot(exists("NBA_TEAM_COLORS"))
stopifnot(exists("get_nba_team_color", mode = "function"))
stopifnot(exists("resolve_team_abbr", mode = "function"))
stopifnot(exists("get_nba_logo_url", mode = "function"))
stopifnot(exists("get_nba_logo_path", mode = "function"))
stopifnot(exists("read_nba_logo_grob", mode = "function"))
stopifnot(exists("render_animated_artifact", mode = "function"))
cat("  PASS: All core exports and helper functions exist.\n")

# ------------------------------------------------------------------------------
# Test 2: theme_nba_dark() produces a ggplot2 theme with expected dark styling
# ------------------------------------------------------------------------------
cat("[Test 2] Verifying theme_nba_dark() ggplot2 styling...\n")
th <- theme_nba_dark()
stopifnot(inherits(th, "theme"))
stopifnot(identical(th$plot.background$fill, NBA_COLORS$bg))
stopifnot(identical(th$panel.background$fill, NBA_COLORS$panel))
stopifnot(identical(th$panel.grid.major$colour, NBA_COLORS$grid))

p <- ggplot(data.frame(x = 1:5, y = 1:5), aes(x, y)) +
  geom_point(color = NBA_COLORS$accent) +
  labs(title = "Test Plot", subtitle = "Dark Theme", caption = "NBA Analytics") +
  theme_nba_dark()
stopifnot(inherits(p, "ggplot"))
cat("  PASS: theme_nba_dark() applied successfully.\n")

# ------------------------------------------------------------------------------
# Test 3: Palette completeness and team color resolution
# ------------------------------------------------------------------------------
cat("[Test 3] Verifying team palettes and get_nba_team_color()...\n")
stopifnot(length(NBA_TEAM_COLORS) == 30L)
stopifnot(length(NBA_DIVISION_COLORS) == 6L)
stopifnot(length(NBA_CONFERENCE_COLORS) == 2L)

bos_primary <- get_nba_team_color("BOS", "primary")
stopifnot(identical(bos_primary, "#007A33"))

celtics_primary <- get_nba_team_color("Celtics", "primary")
stopifnot(identical(celtics_primary, "#007A33"))

nyk_sec <- get_nba_team_color("NYK", "secondary")
stopifnot(identical(nyk_sec, "#F58426"))

# Vectorized test
mult_colors <- get_nba_team_color(c("BOS", "LAL", "GSW"), "primary")
stopifnot(length(mult_colors) == 3L)
stopifnot(mult_colors[2] == "#552583")
cat("  PASS: Team color palettes and resolvers verified.\n")

# ------------------------------------------------------------------------------
# Test 4: render_animated_artifact() produces dual artifacts (GIF + PNG)
# ------------------------------------------------------------------------------
cat("[Test 4] Verifying render_animated_artifact() with dummy 3-frame animation...\n")
test_tmp_dir <- file.path(tempdir(), "test_nba_viz_common")
if (dir.exists(test_tmp_dir)) unlink(test_tmp_dir, recursive = TRUE)
dir.create(test_tmp_dir, recursive = TRUE)

frame_files <- file.path(test_tmp_dir, sprintf("frame_%d.png", 1:3))
for (i in 1:3) {
  df <- data.frame(step = 1:i, val = (1:i)^2)
  p_frame <- ggplot(df, aes(x = step, y = val)) +
    geom_line(color = NBA_COLORS$accent, linewidth = 1.2) +
    geom_point(color = NBA_COLORS$text, size = 3) +
    labs(title = sprintf("Step %d", i)) +
    theme_nba_dark()

  ggsave(frame_files[i], plot = p_frame, width = 6, height = 4, dpi = 100, bg = NBA_COLORS$bg)
  stopifnot(file.exists(frame_files[i]))
}

out_gif <- file.path(test_tmp_dir, "test_animation.gif")
out_png <- file.path(test_tmp_dir, "test_animation_still.png")

result <- render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 2,
  width            = 600,
  height           = 400
)

# Assertions on outputs
stopifnot(file.exists(out_gif))
stopifnot(file.exists(out_png))

gif_size <- file.info(out_gif)$size
png_size <- file.info(out_png)$size

cat(sprintf("  Generated GIF: %s (size: %d bytes)\n", out_gif, gif_size))
cat(sprintf("  Generated PNG: %s (size: %d bytes)\n", out_png, png_size))

stopifnot(gif_size > 0)
stopifnot(png_size > 0)

# Verify still PNG matches the 3rd (final) frame byte size
final_frame_size <- file.info(frame_files[3])$size
stopifnot(png_size == final_frame_size)

# Clean up temporary test files
unlink(test_tmp_dir, recursive = TRUE)
cat("  PASS: render_animated_artifact() successfully validated.\n")

cat("\n>>> ALL TESTS PASSED SUCCESSFULLY! <<<\n")
