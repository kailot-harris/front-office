# ==============================================================================
# tools/gif_rotation_command_scatter.R — Dynamic Pitching Staff Command & Dominance Matrix
# Path: tools/gif_rotation_command_scatter.R
#
# Generates an animated dynamic quadrant scatter race tracking 30 MLB pitching
# staffs across strikeout dominance, strike-zone command, and run prevention:
#   - X-axis: Strikeout minus Walk percentage (K-BB%) — Pure command / strike dominance
#   - Y-axis: Fielding Independent Pitching (FIP) or Earned Run Average (ERA) [reversed axis]
#
# Quadrants (centered at league averages):
#   - Top-Right: Elite Pitching Dominance (High K-BB%, Low ERA/FIP)
#   - Top-Left: Soft-Contact / Low-FIP Pitching (Modest K-BB%, Low ERA/FIP)
#   - Bottom-Right: High-Strikeout / High-Volatility Staffs (High K-BB%, High ERA/FIP)
#   - Bottom-Left: Vulnerable / Low-Strikeout Staffs (Low K-BB%, High ERA/FIP)
#
# Features:
#   - Dynamic quadrant lines anchored to league averages
#   - Official transparent MLB franchise logos at animated coordinates
#   - Division-colored halos and dark front-office theme via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/stats_sync/fg_pitchers.rds
# Output: cache/viz/gif_rotation_command_scatter.gif
#         cache/viz/gif_rotation_command_scatter.png
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

#' Generate Dynamic Pitching Staff Command Scatter GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param pitchers_file Path to fg_pitchers.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param metric_y Pitching efficiency metric for Y-axis: "FIP" or "ERA" (default "FIP")
#' @param n_frames Number of milestone frames across simulated progression (default 18)
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_rotation_command_scatter <- function(season = 2026,
                                                  pitchers_file = cache_path("stats_sync", "fg_pitchers.rds"),
                                                  output_gif = "gif_rotation_command_scatter.gif",
                                                  output_png = "gif_rotation_command_scatter.png",
                                                  metric_y = c("FIP", "ERA"),
                                                  n_frames = 18,
                                                  fps = 6,
                                                  hold_frames = 12,
                                                  cleanup_frames = TRUE) {
  start_time <- Sys.time()
  metric_y <- match.arg(metric_y)
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Pitching Staff Command & Dominance Scatter (K-BB%% vs %s)...", season, metric_y))

  if (!file.exists(pitchers_file)) {
    alt_file <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "stats_sync", "fg_pitchers.rds")
    if (file.exists(alt_file)) {
      pitchers_file <- alt_file
    } else {
      stop(sprintf("Pitchers file not found at '%s'. Run mlb_stats_sync.R first.", pitchers_file))
    }
  }

  pitchers <- readRDS(pitchers_file)
  if (nrow(pitchers) == 0) {
    stop("Pitchers dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_div_map <- setNames(act_teams$division, act_teams$team_abbreviation)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_abbreviation)

  # Check column names for K-BB%
  k_bb_col <- if ("K-BB_pct" %in% names(pitchers)) {
    "K-BB_pct"
  } else if ("K_minus_BB_pct" %in% names(pitchers)) {
    "K_minus_BB_pct"
  } else {
    "K_pct"
  }

  # Aggregate team-level IP-weighted stats
  team_stats <- pitchers %>%
    filter(
      !is.na(team_name),
      team_name %in% act_teams$team_abbreviation,
      !is.na(IP), IP > 0,
      !is.na(.data[[k_bb_col]]),
      !is.na(.data[[metric_y]])
    ) %>%
    group_by(team_name) %>%
    summarize(
      total_ip = sum(IP, na.rm = TRUE),
      team_k_bb = sum(.data[[k_bb_col]] * IP, na.rm = TRUE) / sum(IP, na.rm = TRUE),
      team_y = sum(.data[[metric_y]] * IP, na.rm = TRUE) / sum(IP, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      division = team_div_map[team_name],
      team_full = team_name_map[team_name]
    )

  if (nrow(team_stats) == 0) {
    stop("No qualified team pitching stats found.")
  }

  # Convert K-BB% to percentage scale (e.g. 15.2%) if stored as decimal (0.152)
  if (median(team_stats$team_k_bb, na.rm = TRUE) < 1.0) {
    team_stats$team_k_bb <- team_stats$team_k_bb * 100
  }

  lg_k_bb <- mean(team_stats$team_k_bb, na.rm = TRUE)
  lg_y <- mean(team_stats$team_y, na.rm = TRUE)

  # Scale limits
  x_min <- min(team_stats$team_k_bb) - 2.5
  x_max <- max(team_stats$team_k_bb) + 2.5
  # Note: Inverted Y axis, so lower ERA/FIP is plotted higher
  y_top <- min(team_stats$team_y) - 0.40  # best/lowest
  y_bot <- max(team_stats$team_y) + 0.40  # worst/highest

  frame_dir <- file.path(cache_path("viz", create = TRUE), "frames_rotation_command")
  if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  frame_files <- character()

  for (f in 1:n_frames) {
    pct <- f / n_frames
    progress <- 3 * pct^2 - 2 * pct^3

    frame_data <- team_stats %>%
      mutate(
        cur_k_bb = lg_k_bb + (team_k_bb - lg_k_bb) * progress,
        cur_y = lg_y + (team_y - lg_y) * progress
      )

    p <- ggplot(frame_data, aes(x = cur_k_bb, y = cur_y)) +
      # Center crosshairs
      geom_vline(xintercept = lg_k_bb, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +
      geom_hline(yintercept = lg_y, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +

      # Quadrant annotations (Y is inverted: smaller values are at top)
      annotate("text", x = x_max - 0.5, y = y_top + 0.15, label = "DOMINANT ROTATION / STAFF\n(High K-BB% / Low ERA-FIP)",
               hjust = 1, vjust = 0, color = "#58A6FF", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_top + 0.15, label = "CONTACT-MANAGEMENT STAFF\n(Low K-BB% / Low ERA-FIP)",
               hjust = 0, vjust = 0, color = "#7EE787", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_max - 0.5, y = y_bot - 0.15, label = "VOLATILE / HIGH-K UNDERPERFORMERS\n(High K-BB% / Elevated ERA-FIP)",
               hjust = 1, vjust = 1, color = "#FFA657", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_bot - 0.15, label = "VULNERABLE / REBUILDING STAFF\n(Low K-BB% / Elevated ERA-FIP)",
               hjust = 0, vjust = 1, color = "#FF7B72", fontface = "bold", size = 3, alpha = 0.8) +

      # Division color halo
      geom_point(aes(color = division), size = 7, alpha = 0.45) +
      scale_color_manual(values = MLB_DIVISION_COLORS, name = "Division") +

      # Team Logos
      geom_mlb_logos(aes(team_abbr = team_name), width = 0.055, alpha = 0.95) +

      # Invert Y scale so elite pitching appears on top
      scale_x_continuous(labels = function(x) paste0(round(x, 1), "%"), limits = c(x_min, x_max)) +
      scale_y_reverse(labels = scales::number_format(accuracy = 0.01), limits = c(y_bot, y_top)) +
      labs(
        title = sprintf("MLB %d Pitching Staff Command & Dominance Matrix", season),
        subtitle = sprintf("Convergence Frame %d/%d — FanGraphs Strikeout-Walk Delta (K-BB%%) vs. %s (Lg Avg: %.1f%% K-BB, %.2f %s)",
                           f, n_frames, metric_y, lg_k_bb, lg_y, metric_y),
        x = "Command Differential (K - BB %) — Strike-Zone Control & Whiff Rate",
        y = sprintf("Run Prevention: %s (Reversed Axis — Better Pitching on Top)", metric_y),
        caption = "Front-Office Analytics Engine | FanGraphs Pitcher Tracking | mlbplotR"
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
  message(sprintf(">>> [DONE] Completed Pitching Command Scatter in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (!interactive() && identical(environment(), globalenv())) {
  generate_gif_rotation_command_scatter()
}
