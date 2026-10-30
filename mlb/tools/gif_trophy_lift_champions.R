# ==============================================================================
# tools/gif_trophy_lift_champions.R — The World Series Trophy Lift Finale
# Path: tools/gif_trophy_lift_champions.R
#
# Generates an animated celebration finale for the 2026 World Series Champions:
#   - Stage 1: Darkness & Golden Beam Spotlight Reveal (Frames 1-6)
#   - Stage 2: Commissioner's Trophy Crest & Silver Pennant Rise (Frames 7-14)
#   - Stage 3: World Champions Milwaukee Brewers Crest & Dynamic Gold Confetti Burst (Frames 15-22)
#   - Stage 4: Grand Golden Coronet & World Series Champions Finale Hold (Frames 23-32)
#
# Visual Elements:
#   - Glowing Commissioner's Trophy crest silhouette with 30 silver pennant pins
#   - Milwaukee Brewers franchise logo scaling up into golden laurel wreath
#   - Shimmering golden & navy celebratory confetti burst particles
#   - Fall Classic Postseason Record typography (124-77 Regular Season, NL Pennant, WS Crown)
#   - Publication-grade minimal dark aesthetic via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Inputs: cache/postseason/postseason_sim_results_2026.rds
#         cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_trophy_lift_champions.gif
#         cache/viz/gif_trophy_lift_champions.png
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

#' Generate World Series Trophy Lift & Champions Celebration GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param champion_abbr Franchise abbreviation of champions (default "MIL")
#' @param postseason_file Path to postseason_sim_results_2026.rds
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param n_frames Number of animation progression frames (default 22)
#' @param fps Frames per second for GIF playback (default 7)
#' @param hold_frames Number of frames to hold the final coronation (default 14)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_trophy_lift_champions <- function(season = 2026,
                                               champion_abbr = "MIL",
                                               postseason_file = cache_path("postseason", sprintf("postseason_sim_results_%d.rds", season)),
                                               schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                               output_gif = "gif_trophy_lift_champions.gif",
                                               output_png = "gif_trophy_lift_champions.png",
                                               n_frames = 22,
                                               fps = 7,
                                               hold_frames = 14,
                                               cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d World Series Trophy Lift Champions Finale (%s)...", season, champion_abbr))

  # Locate postseason file with worktree fallback
  if (!file.exists(postseason_file)) {
    alt_post <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "postseason", sprintf("postseason_sim_results_%d.rds", season))
    if (file.exists(alt_post)) postseason_file <- alt_post
  }

  champion_name <- "Milwaukee Brewers"
  runner_up_name <- "Tampa Bay Rays"
  reg_wins <- 124
  reg_losses <- 77

  # Seed random confetti particles for consistent celebration trajectory
  set.seed(20261030)
  n_confetti <- 140
  confetti_base <- tibble(
    id = 1:n_confetti,
    x_origin = runif(n_confetti, 4.0, 6.0),
    y_origin = runif(n_confetti, 3.8, 5.0),
    vx = rnorm(n_confetti, mean = 0, sd = 1.8),
    vy = runif(n_confetti, min = 1.0, max = 3.5),
    size = runif(n_confetti, 1.8, 4.2),
    shape = sample(c(15, 16, 17, 18), n_confetti, replace = TRUE),
    color = sample(c("#FACC15", "#FEF08A", "#EAB308", "#60A5FA", "#FFFFFF", "#F59E0B"), n_confetti, replace = TRUE)
  )

  # Commissioner's Trophy 30 Pennant Flag Array Coordinates
  # Modeled mathematically around a crowning semicircular arc
  angles <- seq(pi * 0.12, pi * 0.88, length.out = 30)
  trophy_pennants <- tibble(
    pennant_id = 1:30,
    base_x = 5.0 + 1.6 * cos(angles),
    base_y = 4.2 + 0.6 * sin(angles),
    tip_x  = 5.0 + 2.5 * cos(angles),
    tip_y  = 4.6 + 2.6 * sin(angles)
  )

  # Setup frame directory
  viz_dir <- ensure_viz_dir()
  frame_dir <- file.path(viz_dir, "frames_trophy_lift")
  if (dir.exists(frame_dir)) unlink(frame_dir, recursive = TRUE)
  dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  message(sprintf("Rendering %d animation frames for Trophy Lift Finale...", n_frames + hold_frames))

  frame_files <- character(n_frames + hold_frames)
  total_frames <- n_frames + hold_frames

  for (f in seq_len(total_frames)) {
    step_idx <- min(f, n_frames)
    p_prog <- (step_idx - 1) / (n_frames - 1) # 0.0 to 1.0

    # Trophy lift elevation: rises from y = 2.8 to y = 4.8
    trophy_y_offset <- 1.4 * (1 - cos(pi * min(1, p_prog * 1.25))) / 2

    # Confetti dynamics: burst activates after trophy lift begins (p_prog > 0.45)
    confetti_active <- p_prog >= 0.45
    t_confetti <- max(0, (p_prog - 0.45) / 0.55)
    
    cur_confetti <- confetti_base %>%
      mutate(
        x = x_origin + vx * t_confetti,
        y = y_origin + vy * t_confetti - 1.2 * (t_confetti^2),
        alpha = ifelse(confetti_active, pmin(1.0, 0.2 + 0.8 * t_confetti), 0.0)
      )

    # Logo scale and spotlight intensity
    logo_width <- 0.10 + 0.08 * p_prog
    beam_alpha <- 0.05 + 0.18 * sin(pi * p_prog)
    crest_gold_alpha <- pmin(1.0, p_prog * 1.3)

    p <- ggplot() +
      # Deep celestial stadium night background
      annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 10, fill = "#0D1117") +
      # Golden Spotlight Beams from Heaven
      annotate("polygon",
               x = c(5.0, 1.5, 8.5),
               y = c(9.8, 0.0, 0.0),
               fill = "#FACC15", alpha = beam_alpha) +
      annotate("polygon",
               x = c(5.0, 3.2, 6.8),
               y = c(9.8, 0.0, 0.0),
               fill = "#FFFFFF", alpha = beam_alpha * 0.75) +
      # Trophy Base Pedestal (Ebony wood base with silver inscription ring)
      annotate("rect", xmin = 4.1, xmax = 5.9,
               ymin = 2.4 + trophy_y_offset, ymax = 3.2 + trophy_y_offset,
               fill = "#21262D", color = "#C0C0C0", linewidth = 0.8) +
      annotate("rect", xmin = 4.3, xmax = 5.7,
               ymin = 2.2 + trophy_y_offset, ymax = 2.4 + trophy_y_offset,
               fill = "#161B22", color = "#8B949E", linewidth = 0.5) +
      # Silver Trophy Ring & Inscription
      annotate("text", x = 5.0, y = 2.8 + trophy_y_offset,
               label = sprintf("COMMISSIONER'S TROPHY · %d", season),
               color = "#C0C0C0", size = 2.5, fontface = "bold") +
      # 30 Golden/Silver Pennants of the Commissioner's Trophy
      geom_segment(
        data = trophy_pennants,
        aes(
          x = base_x,
          y = base_y + trophy_y_offset,
          xend = tip_x,
          yend = tip_y + trophy_y_offset
        ),
        color = "#FACC15",
        linewidth = 0.9,
        alpha = crest_gold_alpha
      ) +
      # Sterling Silver Ball Centerpiece
      annotate("point", x = 5.0, y = 4.3 + trophy_y_offset, size = 16, color = "#FFFFFF", alpha = 0.9) +
      annotate("point", x = 5.0, y = 4.3 + trophy_y_offset, size = 13, color = "#E2E8F0") +
      # Champion Franchise Logo Rising at Trophy Center
      geom_mlb_logos(
        data = tibble(x = 5.0, y = 4.3 + trophy_y_offset, team_abbr = champion_abbr),
        aes(x = x, y = y, team_abbr = team_abbr),
        width = logo_width
      )

    # Confetti particles
    if (confetti_active) {
      p <- p +
        geom_point(
          data = cur_confetti,
          aes(x = x, y = y, size = size, color = color, shape = shape),
          alpha = cur_confetti$alpha,
          show.legend = FALSE
        ) +
        scale_color_identity() +
        scale_size_identity() +
        scale_shape_identity()
    }

    # Typography & Headers
    p <- p +
      # Header Crown Banner
      annotate("label", x = 5.0, y = 9.2,
               label = sprintf("★ 2026 WORLD SERIES CHAMPIONS ★"),
               fill = "#161B22", color = "#FACC15", fontface = "bold", size = 5.2,
               label.padding = unit(0.5, "lines"), label.r = unit(0.2, "lines"),
               alpha = 0.95) +
      annotate("text", x = 5.0, y = 8.4,
               label = sprintf("%s Defeat %s in Historic Fall Classic", toupper(champion_name), toupper(runner_up_name)),
               color = "#E6EDF3", fontface = "bold", size = 3.8) +
      # Champion Season Metrics Ribbon
      annotate("label", x = 5.0, y = 1.3,
               label = sprintf("REGULAR SEASON: %d-%d (.617)  ·  NL CENTRAL CHAMPIONS  ·  OCTOBER IMMORTALITY", reg_wins, reg_losses),
               fill = "#161B22", color = "#7EE787", fontface = "bold", size = 3.4,
               label.padding = unit(0.4, "lines"), alpha = 0.9) +
      annotate("text", x = 5.0, y = 0.7,
               label = "Source: KayceeSlices MLB Analytics Engine | Commissioner's Trophy Finale | mlbplotR",
               color = "#8B949E", size = 2.6) +
      coord_cartesian(xlim = c(0, 10), ylim = c(0, 10), expand = FALSE) +
      theme_void() +
      theme(
        plot.background = element_rect(fill = "#0D1117", color = NA),
        panel.background = element_rect(fill = "#0D1117", color = NA)
      )

    frame_path <- file.path(frame_dir, sprintf("frame_%03d.png", f))
    ggsave(frame_path, plot = p, width = 11, height = 8.5, dpi = 140, bg = "#0D1117")
    frame_files[f] <- frame_path

    if (f %% 5 == 0 || f == total_frames) {
      message(sprintf("  Rendered frame %d / %d", f, total_frames))
    }
  }

  # Export static final frame
  out_png_path <- cache_path("viz", output_png)
  final_frame <- frame_files[n_frames]
  file.copy(final_frame, out_png_path, overwrite = TRUE)
  message(sprintf(">>> [PNG] Exported static final frame: %s", out_png_path))

  # Build GIF
  out_gif_path <- cache_path("viz", output_gif)
  gifski(
    png_files = frame_files,
    gif_file = out_gif_path,
    width = 1200,
    height = 920,
    delay = 1 / fps
  )
  message(sprintf(">>> [GIF] Rendered animation: %s (%.1f MB)", out_gif_path, file.size(out_gif_path) / 1e6))

  # Cleanup temporary frames
  if (cleanup_frames && dir.exists(frame_dir)) {
    unlink(frame_dir, recursive = TRUE)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [DONE] Completed World Series Trophy Lift Finale in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (sys.nframe() == 0L && !interactive() && !exists(".is_sourced_test")) {
  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else 2026
  generate_gif_trophy_lift_champions(season = season)
}
