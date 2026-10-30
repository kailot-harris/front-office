# ==============================================================================
# tools/gif_lineup_power_scatter.R — Dynamic Lineup Power & Run Creation Matrix
# Path: tools/gif_lineup_power_scatter.R
#
# Generates an animated 4-quadrant dynamic scatter race tracking MLB lineups
# across offensive power and run-creation efficiency:
#   - X-axis: Isolated Power (ISO) - Extra-base slugging potency
#   - Y-axis: Weighted Runs Created Plus (wRC+) - Overall offensive run generation
#
# Quadrants (centered at league averages):
#   - Top-Right: Elite Sluggers / Complete Offenses (High ISO, High wRC+)
#   - Top-Left: Contact-Heavy / High-OBP Run Producers (Modest ISO, High wRC+)
#   - Bottom-Right: Power-Only / Three-True-Outcomes Volatile (High ISO, Low wRC+)
#   - Bottom-Left: Sub-Par Run Production (Low ISO, Low wRC+)
#
# Features:
#   - mlbplotR transparent franchise logos at animated coordinates
#   - Division-colored halo rings or trails
#   - Minimal dark front-office aesthetic via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/stats_sync/fg_batters.rds
# Output: cache/viz/gif_lineup_power_scatter.gif
#         cache/viz/gif_lineup_power_scatter.png
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

#' Generate Dynamic Lineup Power & Run Creation Scatter GIF
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
generate_gif_lineup_power_scatter <- function(season = 2026,
                                              batters_file = cache_path("stats_sync", "fg_batters.rds"),
                                              output_gif = "gif_lineup_power_scatter.gif",
                                              output_png = "gif_lineup_power_scatter.png",
                                              n_frames = 18,
                                              fps = 6,
                                              hold_frames = 12,
                                              cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Lineup Power & Run Creation Scatter Animation...", season))

  if (!file.exists(batters_file)) {
    # Fallback to base MLB Analytics directory if running in worktree
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

  # Active 30 MLB franchises
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_div_map <- setNames(act_teams$division, act_teams$team_abbreviation)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_abbreviation)

  # Aggregate team-level ISO and wRC+ weighted by PA
  team_stats <- batters %>%
    filter(
      !is.na(team_name),
      team_name %in% act_teams$team_abbreviation,
      !is.na(PA), PA > 0,
      !is.na(ISO), !is.na(wRC_plus)
    ) %>%
    group_by(team_name) %>%
    summarize(
      total_pa = sum(PA, na.rm = TRUE),
      team_iso = sum(ISO * PA, na.rm = TRUE) / sum(PA, na.rm = TRUE),
      team_wrc_plus = sum(wRC_plus * PA, na.rm = TRUE) / sum(PA, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      division = team_div_map[team_name],
      team_full = team_name_map[team_name]
    )

  if (nrow(team_stats) == 0) {
    stop("No qualified team batting stats found.")
  }

  lg_iso <- mean(team_stats$team_iso, na.rm = TRUE)
  lg_wrc <- mean(team_stats$team_wrc_plus, na.rm = TRUE)

  # Axis limits with padding
  x_min <- max(0.100, min(team_stats$team_iso) - 0.025)
  x_max <- max(team_stats$team_iso) + 0.025
  y_min <- max(60, min(team_stats$team_wrc_plus) - 8)
  y_max <- max(team_stats$team_wrc_plus) + 8

  # Generate smooth progression frames from baseline towards final stats
  frame_dir <- file.path(cache_path("viz", create = TRUE), "frames_lineup_power")
  if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  frame_files <- character()

  for (f in 1:n_frames) {
    pct <- f / n_frames
    # Cubic easing for dynamic movement
    progress <- 3 * pct^2 - 2 * pct^3

    frame_data <- team_stats %>%
      mutate(
        cur_iso = lg_iso + (team_iso - lg_iso) * progress,
        cur_wrc_plus = lg_wrc + (team_wrc_plus - lg_wrc) * progress
      )

    p <- ggplot(frame_data, aes(x = cur_iso, y = cur_wrc_plus)) +
      # Quadrant dividing lines
      geom_vline(xintercept = lg_iso, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +
      geom_hline(yintercept = lg_wrc, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +
      
      # Quadrant labels
      annotate("text", x = x_max - 0.005, y = y_max - 2, label = "ELITE RUN PRODUCTION\n(High ISO / High wRC+)",
               hjust = 1, vjust = 1, color = "#58A6FF", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.005, y = y_max - 2, label = "CONTACT & DISCIPLINE\n(Low ISO / High wRC+)",
               hjust = 0, vjust = 1, color = "#7EE787", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_max - 0.005, y = y_min + 2, label = "THREE-TRUE-OUTCOME\n(High ISO / Low wRC+)",
               hjust = 1, vjust = 0, color = "#FFA657", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.005, y = y_min + 2, label = "DEVELOPMENTAL\n(Low ISO / Low wRC+)",
               hjust = 0, vjust = 0, color = "#FF7B72", fontface = "bold", size = 3, alpha = 0.8) +

      # Team Division halos
      geom_point(aes(color = division), size = 7, alpha = 0.45) +
      scale_color_manual(values = MLB_DIVISION_COLORS, name = "Division") +

      # MLB Team Logos
      geom_mlb_logos(aes(team_abbr = team_name), width = 0.055, alpha = 0.95) +

      # Formatting and Theme
      scale_x_continuous(labels = scales::number_format(accuracy = 0.001), limits = c(x_min, x_max)) +
      scale_y_continuous(labels = scales::number_format(accuracy = 1), limits = c(y_min, y_max)) +
      labs(
        title = sprintf("MLB %d Lineup Power vs. Run Creation Matrix", season),
        subtitle = sprintf("Convergence Frame %d/%d — FanGraphs Team Isolated Power (ISO) vs. wRC+ (Lg Avg: %.3f ISO, %.0f wRC+)",
                           f, n_frames, lg_iso, lg_wrc),
        x = "Isolated Power (ISO) — Extra-Base Hit Slugging Magnitude",
        y = "Weighted Runs Created Plus (wRC+) — Park & League Normalized",
        caption = "Front-Office Analytics Engine | FanGraphs Tracking Data | mlbplotR"
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

  # Append hold frames on the final state
  final_frame <- tail(frame_files, 1)
  for (h in 1:hold_frames) {
    hold_path <- file.path(frame_dir, sprintf("frame_hold_%03d.png", h))
    file.copy(final_frame, hold_path, overwrite = TRUE)
    frame_files <- c(frame_files, hold_path)
  }

  # Write final static PNG
  out_png_path <- cache_path("viz", output_png)
  file.copy(final_frame, out_png_path, overwrite = TRUE)
  message(sprintf(">>> [PNG] Exported static final frame: %s", out_png_path))

  # Build GIF
  out_gif_path <- cache_path("viz", output_gif)
  gifski(
    png_files = frame_files,
    gif_file = out_gif_path,
    width = 1200,
    height = 900,
    delay = 1 / fps
  )
  message(sprintf(">>> [GIF] Rendered animation: %s (%.1f MB)", out_gif_path, file.size(out_gif_path) / 1e6))

  # Cleanup temporary frames
  if (cleanup_frames && dir.exists(frame_dir)) {
    unlink(frame_dir, recursive = TRUE)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [DONE] Completed Lineup Power Scatter in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (!interactive() && identical(environment(), globalenv())) {
  generate_gif_lineup_power_scatter()
}
