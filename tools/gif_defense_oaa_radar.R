# ==============================================================================
# tools/gif_defense_oaa_radar.R — Defensive Efficiency & Diamond Coverage Radar/Scatter
# Path: tools/gif_defense_oaa_radar.R
#
# Generates an animated multi-dimensional defensive efficiency and diamond
# coverage progression tracking 30 MLB franchises:
#   - X-axis: Fielding / Positional Defensive Value (FanGraphs Fielding Runs)
#   - Y-axis: Total Defensive Runs Above Average (FanGraphs Defense = Fielding + Positional)
#   - Dynamic diamond-coverage radar/quadrant mapping
#
# Quadrants (centered at league averages):
#   - Top-Right: Gold Glove Caliber / Elite Diamond Coverage (High Fielding & High Total Def)
#   - Top-Left: High Positional Difficulty / Premium Infield Alignment
#   - Bottom-Right: Raw Range Accumulators with Neutral Conversion
#   - Bottom-Left: Defensive Liability / Negative Run Prevention
#
# Features:
#   - Official transparent MLB franchise logos at dynamic coordinates
#   - Division-colored halo markers and front-office dark styling via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/stats_sync/fg_batters.rds
# Output: cache/viz/gif_defense_oaa_radar.gif
#         cache/viz/gif_defense_oaa_radar.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
  library(tidyr)
  library(mlbplotR)
  library(gifski)
})

source("config.R")
source("tools/viz_theme.R")

#' Generate Defensive Efficiency & Diamond Coverage GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param batters_file Path to fg_batters.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param n_frames Number of milestone frames across simulated progression (default 18)
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_defense_oaa_radar <- function(season = 2026,
                                           batters_file = cache_path("stats_sync", "fg_batters.rds"),
                                           output_gif = "gif_defense_oaa_radar.gif",
                                           output_png = "gif_defense_oaa_radar.png",
                                           n_frames = 18,
                                           fps = 6,
                                           hold_frames = 12,
                                           cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Defensive Efficiency & Diamond Coverage Animation...", season))

  if (!file.exists(batters_file)) {
    alt_file <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "stats_sync", "fg_batters.rds")
    if (file.exists(alt_file)) {
      batters_file <- alt_file
    } else {
      stop(sprintf("Batters file not found at '%s'. Run mlb_stats_sync.R first.", batters_file))
    }
  }

  batters <- readRDS(batters_file)
  if (nrow(batters) == 0) {
    stop("Batters dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_div_map <- setNames(act_teams$division, act_teams$team_abbreviation)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_abbreviation)

  # Check Fielding and Defense columns
  field_col <- if ("Fielding" %in% names(batters)) "Fielding" else "Defense"
  def_col <- if ("Defense" %in% names(batters)) "Defense" else "Fielding"

  # Aggregate team totals for Fielding and Defense
  team_stats <- batters %>%
    filter(
      !is.na(team_name),
      team_name %in% act_teams$team_abbreviation
    ) %>%
    group_by(team_name) %>%
    summarize(
      total_fielding = sum(.data[[field_col]], na.rm = TRUE),
      total_def = sum(.data[[def_col]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      division = team_div_map[team_name],
      team_full = team_name_map[team_name]
    )

  if (nrow(team_stats) == 0) {
    stop("No qualified team defensive stats found.")
  }

  lg_fielding <- mean(team_stats$total_fielding, na.rm = TRUE)
  lg_def <- mean(team_stats$total_def, na.rm = TRUE)

  x_min <- min(team_stats$total_fielding) - 4.0
  x_max <- max(team_stats$total_fielding) + 4.0
  y_min <- min(team_stats$total_def) - 4.0
  y_max <- max(team_stats$total_def) + 4.0

  frame_dir <- file.path(cache_path("viz", create = TRUE), "frames_defense_radar")
  if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  frame_files <- character()

  for (f in 1:n_frames) {
    pct <- f / n_frames
    progress <- 3 * pct^2 - 2 * pct^3

    frame_data <- team_stats %>%
      mutate(
        cur_fielding = lg_fielding + (total_fielding - lg_fielding) * progress,
        cur_def = lg_def + (total_def - lg_def) * progress
      )

    p <- ggplot(frame_data, aes(x = cur_fielding, y = cur_def)) +
      # Diamond coverage concentric radar rings
      annotate("path",
               x = lg_fielding + 10 * cos(seq(0, 2*pi, length.out = 100)),
               y = lg_def + 10 * sin(seq(0, 2*pi, length.out = 100)),
               color = "#30363D", linetype = "dotted", linewidth = 0.5) +
      annotate("path",
               x = lg_fielding + 20 * cos(seq(0, 2*pi, length.out = 100)),
               y = lg_def + 20 * sin(seq(0, 2*pi, length.out = 100)),
               color = "#30363D", linetype = "dotted", linewidth = 0.5) +

      # Quadrant dividing lines
      geom_vline(xintercept = lg_fielding, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +
      geom_hline(yintercept = lg_def, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +

      # Quadrant labels
      annotate("text", x = x_max - 0.5, y = y_max - 0.5, label = "ELITE RUN PREVENTION / GOLD GLOVE\n(High Fielding / High Net Def Runs)",
               hjust = 1, vjust = 1, color = "#58A6FF", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_max - 0.5, label = "PREMIUM POSITIONAL PROFILE\n(High Positional / Moderate Fielding)",
               hjust = 0, vjust = 1, color = "#7EE787", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_max - 0.5, y = y_min + 0.5, label = "GLOVE SPECIALISTS / RANGE FOCUS\n(High Fielding / Low Positional Adj)",
               hjust = 1, vjust = 0, color = "#FFA657", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_min + 0.5, label = "DEFENSIVE REBUILD / COVERAGE GAPS\n(Low Fielding / Negative Def Runs)",
               hjust = 0, vjust = 0, color = "#FF7B72", fontface = "bold", size = 3, alpha = 0.8) +

      # Team Division halos
      geom_point(aes(color = division), size = 7, alpha = 0.45) +
      scale_color_manual(values = MLB_DIVISION_COLORS, name = "Division") +

      # Team Logos
      geom_mlb_logos(aes(team_abbr = team_name), width = 0.055, alpha = 0.95) +

      # Scales
      scale_x_continuous(labels = scales::number_format(accuracy = 0.1), limits = c(x_min, x_max)) +
      scale_y_continuous(labels = scales::number_format(accuracy = 0.1), limits = c(y_min, y_max)) +
      labs(
        title = sprintf("MLB %d Defensive Efficiency & Diamond Coverage Radar", season),
        subtitle = sprintf("Convergence Frame %d/%d — FanGraphs Fielding Runs vs. Net Defense Runs (Lg Avg: %.1f Fielding, %.1f Def)",
                           f, n_frames, lg_fielding, lg_def),
        x = "Fielding Runs Above Average — Range, Arm & Conversion Value",
        y = "Total Defensive Runs (Fielding + Positional Adjustment) — Run Prevention",
        caption = "Front-Office Analytics Engine | FanGraphs Defense / OAA Tracking | mlbplotR"
      ) +
      theme_mlb_dark() +
      theme(
        legend.position = "bottom",
        legend.direction = "horizontal",
        plot.title = element_text(size = rel(1.2), face = "bold", color = "#FFFFFF"),
        plot.subtitle = element_text(size = rel(0.85), color = "#8B949E")
      )

    frame_path <- file.path(frame_dir, sprintf("frame_%03d.png", f))
    ggsave(frame_path, plot = p, width = 10, height = 7.5, dpi = 120, device = "png")
    frame_files <- c(frame_files, frame_path)
  }

  final_frame <- tail(frame_files, 1)
  for (h in 1:hold_frames) {
    hold_path <- file.path(frame_dir, sprintf("frame_hold_%03d.png", h))
    file.copy(final_frame, hold_path, overwrite = TRUE)
    frame_files <- c(frame_files, hold_path)
  }

  out_png_path <- cache_path("viz", output_png)
  file.copy(final_frame, out_png_path, overwrite = TRUE)
  message(sprintf(">>> [PNG] Exported static final frame: %s", out_png_path))

  out_gif_path <- cache_path("viz", output_gif)
  gifski(
    png_files = frame_files,
    gif_file = out_gif_path,
    width = 1200,
    height = 900,
    delay = 1 / fps
  )
  message(sprintf(">>> [GIF] Rendered animation: %s (%.1f MB)", out_gif_path, file.size(out_gif_path) / 1e6))

  if (cleanup_frames && dir.exists(frame_dir)) {
    unlink(frame_dir, recursive = TRUE)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [DONE] Completed Defensive OAA Radar in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (!interactive() && identical(environment(), globalenv())) {
  generate_gif_defense_oaa_radar()
}
