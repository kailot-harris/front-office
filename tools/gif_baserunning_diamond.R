# ==============================================================================
# tools/gif_baserunning_diamond.R — Basepath Aggression & Baserunning Value Matrix
# Path: tools/gif_baserunning_diamond.R
#
# Generates an animated diamond scatter and progression tracking 30 MLB
# franchises across baserunning value and basepath efficiency:
#   - X-axis: Stolen Base Success Rate (SB / (SB + CS) %) — Tactical efficiency
#   - Y-axis: FanGraphs Base Running Runs (wBsR) — Comprehensive baserunning value
#
# Quadrants (centered at league averages):
#   - Top-Right: Dynamic Speed / Elite Value (High BsR, High SB%)
#   - Top-Left: Opportunistic Extra-Base Takers (High BsR, Modest SB%)
#   - Bottom-Right: High-Volume / Low-Value Stealers (Low BsR, High SB%)
#   - Bottom-Left: Passive / Value-Negative Baserunning (Low BsR, Low SB%)
#
# Features:
#   - Diamond-themed geometry with base-to-base progression
#   - Official transparent MLB franchise logos at dynamic coordinates
#   - Division-colored halo markers and front-office dark styling via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/stats_sync/fg_batters.rds
# Output: cache/viz/gif_baserunning_diamond.gif
#         cache/viz/gif_baserunning_diamond.png
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

#' Generate Basepath Aggression & Value Diamond GIF
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
generate_gif_baserunning_diamond <- function(season = 2026,
                                             batters_file = cache_path("stats_sync", "fg_batters.rds"),
                                             output_gif = "gif_baserunning_diamond.gif",
                                             output_png = "gif_baserunning_diamond.png",
                                             n_frames = 18,
                                             fps = 6,
                                             hold_frames = 12,
                                             cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Baserunning & Diamond Aggression Animation...", season))

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

  # Check BsR column (wBsR or BsR)
  bsr_col <- if ("wBsR" %in% names(batters)) {
    "wBsR"
  } else if ("BaseRunning" %in% names(batters)) {
    "BaseRunning"
  } else {
    "Spd"
  }

  # Aggregate team totals for SB, CS, and BsR
  team_stats <- batters %>%
    filter(
      !is.na(team_name),
      team_name %in% act_teams$team_abbreviation
    ) %>%
    group_by(team_name) %>%
    summarize(
      total_sb = sum(SB, na.rm = TRUE),
      total_cs = sum(CS, na.rm = TRUE),
      total_bsr = sum(.data[[bsr_col]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      attempts = total_sb + total_cs,
      sb_pct = ifelse(attempts > 0, (total_sb / attempts) * 100, 75),
      division = team_div_map[team_name],
      team_full = team_name_map[team_name]
    )

  if (nrow(team_stats) == 0) {
    stop("No qualified team baserunning stats found.")
  }

  lg_sb_pct <- mean(team_stats$sb_pct, na.rm = TRUE)
  lg_bsr <- mean(team_stats$total_bsr, na.rm = TRUE)

  x_min <- min(team_stats$sb_pct) - 3.0
  x_max <- max(team_stats$sb_pct) + 3.0
  y_min <- min(team_stats$total_bsr) - 3.0
  y_max <- max(team_stats$total_bsr) + 3.0

  frame_dir <- file.path(cache_path("viz", create = TRUE), "frames_baserunning")
  if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  frame_files <- character()

  for (f in 1:n_frames) {
    pct <- f / n_frames
    progress <- 3 * pct^2 - 2 * pct^3

    frame_data <- team_stats %>%
      mutate(
        cur_sb_pct = lg_sb_pct + (sb_pct - lg_sb_pct) * progress,
        cur_bsr = lg_bsr + (total_bsr - lg_bsr) * progress
      )

    p <- ggplot(frame_data, aes(x = cur_sb_pct, y = cur_bsr)) +
      # Diamond coordinate overlay (subtle diamond backdrop in the plot space)
      geom_segment(aes(x = (x_min + x_max)/2, y = y_max, xend = x_max, yend = (y_min + y_max)/2),
                   color = "#30363D", linetype = "dotted", linewidth = 0.5) +
      geom_segment(aes(x = x_max, y = (y_min + y_max)/2, xend = (x_min + x_max)/2, yend = y_min),
                   color = "#30363D", linetype = "dotted", linewidth = 0.5) +
      geom_segment(aes(x = (x_min + x_max)/2, y = y_min, xend = x_min, yend = (y_min + y_max)/2),
                   color = "#30363D", linetype = "dotted", linewidth = 0.5) +
      geom_segment(aes(x = x_min, y = (y_min + y_max)/2, xend = (x_min + x_max)/2, yend = y_max),
                   color = "#30363D", linetype = "dotted", linewidth = 0.5) +

      # Quadrant dividing lines
      geom_vline(xintercept = lg_sb_pct, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +
      geom_hline(yintercept = lg_bsr, linetype = "dashed", color = "#8B949E", alpha = 0.6, linewidth = 0.6) +

      # Quadrant labels
      annotate("text", x = x_max - 0.5, y = y_max - 0.5, label = "ELITE BASEPATH WEAPONS\n(High SB% / Positive BsR)",
               hjust = 1, vjust = 1, color = "#58A6FF", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_max - 0.5, label = "AGGRESSIVE RUN ADVANCEMENT\n(Moderate SB% / High BsR)",
               hjust = 0, vjust = 1, color = "#7EE787", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_max - 0.5, y = y_min + 0.5, label = "DISCRETE THIEVES\n(High SB% / Neutral BsR)",
               hjust = 1, vjust = 0, color = "#FFA657", fontface = "bold", size = 3, alpha = 0.8) +
      annotate("text", x = x_min + 0.5, y = y_min + 0.5, label = "CONSERVATIVE / VALUE LEAK\n(Low SB% / Negative BsR)",
               hjust = 0, vjust = 0, color = "#FF7B72", fontface = "bold", size = 3, alpha = 0.8) +

      # Team Division halos
      geom_point(aes(color = division), size = 7, alpha = 0.45) +
      scale_color_manual(values = MLB_DIVISION_COLORS, name = "Division") +

      # Team Logos
      geom_mlb_logos(aes(team_abbr = team_name), width = 0.055, alpha = 0.95) +

      # Scales
      scale_x_continuous(labels = function(x) paste0(round(x, 0), "%"), limits = c(x_min, x_max)) +
      scale_y_continuous(labels = scales::number_format(accuracy = 0.1), limits = c(y_min, y_max)) +
      labs(
        title = sprintf("MLB %d Basepath Aggression & Baserunning Value Matrix", season),
        subtitle = sprintf("Convergence Frame %d/%d — FanGraphs Stolen Base Success %% vs. Net BsR Runs (Lg Avg: %.1f%% SB, %.1f BsR)",
                           f, n_frames, lg_sb_pct, lg_bsr),
        x = "Stolen Base Success Rate (SB / [SB + CS] %) — Basepath Efficiency",
        y = "Baserunning Runs Above Average (BsR / wBsR) — Cumulative Run Value",
        caption = "Front-Office Analytics Engine | FanGraphs Baserunning Tracking | mlbplotR"
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
  message(sprintf(">>> [DONE] Completed Baserunning Diamond in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (!interactive() && identical(environment(), globalenv())) {
  generate_gif_baserunning_diamond()
}
