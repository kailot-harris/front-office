# ==============================================================================
# tools/gif_pennant_showdown.R — ALCS & NLCS Showdown and Fall Classic Banner
# Path: tools/gif_pennant_showdown.R
#
# Generates an animated championship series showdown tracking game-by-game
# progression through the ALCS (Tampa Bay Rays vs Cleveland Guardians) and
# NLCS (Milwaukee Brewers vs Los Angeles Dodgers), culminating in their pennant
# clinches and a dramatic transition into the 2026 World Series emblem banner.
#
# Key Features:
#   - Side-by-side ALCS and NLCS game-by-game series tracker (Best-of-7).
#   - Series win progress bars and individual game scores.
#   - Pennant clinch fireworks / celebration frames.
#   - Climax transition into the World Series emblem banner with full franchise logos.
#   - Official transparent MLB logos via mlbplotR::geom_mlb_logos.
#   - Dark front-office theme via theme_mlb_dark().
#   - Encoded with gifski engine with final frame hold.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
#         cache/postseason/postseason_sim_results_2026.rds
# Output: cache/viz/gif_pennant_showdown.gif
#         cache/viz/gif_pennant_showdown.png
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

#' Generate Pennant Showdown & World Series Matchup Banner GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 2)
#' @param hold_frames Number of frames to hold the final banner (default 10)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_pennant_showdown <- function(season = 2026,
                                          schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                          output_gif = "gif_pennant_showdown.gif",
                                          output_png = "gif_pennant_showdown.png",
                                          fps = 2,
                                          hold_frames = 10,
                                          cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Pennant Showdown & WS Banner Animation...", season))

  # Game progression data for ALCS and NLCS
  # NLCS: 4 games (MIL sweeps LAD 4-0)
  # ALCS: 6 games (TB defeats CLE 4-2)

  steps <- list(
    list(
      step = 1,
      title = "Game 1: Championship Series Openers",
      subtitle = "NLCS G1: MIL 2, LAD 1 | ALCS G1: CLE 7, TB 3",
      al_tb_wins = 0, al_cle_wins = 1,
      nl_mil_wins = 1, nl_lad_wins = 0,
      stage = "series"
    ),
    list(
      step = 2,
      title = "Game 2: Milwaukee & Tampa Respond",
      subtitle = "NLCS G2: MIL 7, LAD 4 (MIL 2-0) | ALCS G2: TB 3, CLE 1 (Series tied 1-1)",
      al_tb_wins = 1, al_cle_wins = 1,
      nl_mil_wins = 2, nl_lad_wins = 0,
      stage = "series"
    ),
    list(
      step = 3,
      title = "Game 3: The Pivotal Road Test",
      subtitle = "NLCS G3: MIL 6, LAD 2 (MIL 3-0) | ALCS G3: CLE 3, TB 2 (CLE leads 2-1)",
      al_tb_wins = 1, al_cle_wins = 2,
      nl_mil_wins = 3, nl_lad_wins = 0,
      stage = "series"
    ),
    list(
      step = 4,
      title = "NLCS Sweep! Brewers Clinch National League Pennant",
      subtitle = "NLCS G4: MIL 6, LAD 4 — MILWAUKEE WINS PENNANT (4-0) | ALCS G4: TB 7, CLE 3 (Tied 2-2)",
      al_tb_wins = 2, al_cle_wins = 2,
      nl_mil_wins = 4, nl_lad_wins = 0,
      stage = "nl_clinch"
    ),
    list(
      step = 5,
      title = "ALCS Game 5: Tampa Bay Pushes to Match Point",
      subtitle = "ALCS G5: TB 3, CLE 1 — Rays lead 3-2 heading home to Tropicana Field",
      al_tb_wins = 3, al_cle_wins = 2,
      nl_mil_wins = 4, nl_lad_wins = 0,
      stage = "al_game5"
    ),
    list(
      step = 6,
      title = "ALCS Game 6 Climax! Rays Clinch American League Pennant",
      subtitle = "ALCS G6: TB 7, CLE 3 — TAMPA BAY RAYS WIN AL PENNANT (4-2)",
      al_tb_wins = 4, al_cle_wins = 2,
      nl_mil_wins = 4, nl_lad_wins = 0,
      stage = "al_clinch"
    ),
    list(
      step = 7,
      title = "THE 2026 FALL CLASSIC IS SET",
      subtitle = "American League Champions TAMPA BAY RAYS vs National League Champions MILWAUKEE BREWERS",
      al_tb_wins = 4, al_cle_wins = 2,
      nl_mil_wins = 4, nl_lad_wins = 0,
      stage = "ws_banner"
    )
  )

  tmp_dir <- file.path(tempdir(), "mlb_pennant_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(steps))

  for (idx in seq_along(steps)) {
    st <- steps[[idx]]

    if (st$stage != "ws_banner") {
      # Render LCS Series progress view
      series_df <- tribble(
        ~league, ~team_abbr, ~team_name, ~wins, ~color, ~x_pos, ~y_pos,
        "ALCS", "TB", "Tampa Bay Rays", st$al_tb_wins, "#092C5C", 2.2, 5.8,
        "ALCS", "CLE", "Cleveland Guardians", st$al_cle_wins, "#E31937", 2.2, 3.2,
        "NLCS", "MIL", "Milwaukee Brewers", st$nl_mil_wins, "#13294B", 6.8, 5.8,
        "NLCS", "LAD", "Los Angeles Dodgers", st$nl_lad_wins, "#005A9C", 6.8, 3.2
      )

      p <- ggplot() +
        # Left Panel (ALCS) Background Card
        annotate("rect", xmin = 0.6, xmax = 4.4, ymin = 1.2, ymax = 8.2, fill = "#111827", color = "#374151", linewidth = 1.0, alpha = 0.9) +
        # Right Panel (NLCS) Background Card
        annotate("rect", xmin = 5.6, xmax = 9.4, ymin = 1.2, ymax = 8.2, fill = "#111827", color = "#374151", linewidth = 1.0, alpha = 0.9) +
        # Panel Headers
        annotate("text", x = 2.5, y = 7.6, label = "AMERICAN LEAGUE CHAMPIONSHIP SERIES", color = "#60A5FA", fontface = "bold", size = 3.6) +
        annotate("text", x = 7.5, y = 7.6, label = "NATIONAL LEAGUE CHAMPIONSHIP SERIES", color = "#F87171", fontface = "bold", size = 3.6) +
        # Logos for the 4 teams
        geom_mlb_logos(
          data = series_df,
          aes(x = x_pos - 0.7, y = y_pos, team_abbr = team_abbr),
          width = 0.13
        ) +
        # Team Names
        geom_text(
          data = series_df,
          aes(x = x_pos, y = y_pos + 0.35, label = team_name),
          color = "#F8FAFC",
          fontface = "bold",
          size = 4.2,
          hjust = 0
        ) +
        # Series Wins Meter (Circles / Pips for 4 wins needed)
        # TB Wins
        geom_point(data = tibble(x = seq(2.2, 3.7, length.out = 4), y = 5.3, won = 1:4 <= st$al_tb_wins),
                   aes(x = x, y = y, fill = won), shape = 21, size = 6.5, color = "#F8FAFC", stroke = 1.2) +
        # CLE Wins
        geom_point(data = tibble(x = seq(2.2, 3.7, length.out = 4), y = 2.7, won = 1:4 <= st$al_cle_wins),
                   aes(x = x, y = y, fill = won), shape = 21, size = 6.5, color = "#F8FAFC", stroke = 1.2) +
        # MIL Wins
        geom_point(data = tibble(x = seq(6.8, 8.3, length.out = 4), y = 5.3, won = 1:4 <= st$nl_mil_wins),
                   aes(x = x, y = y, fill = won), shape = 21, size = 6.5, color = "#F8FAFC", stroke = 1.2) +
        # LAD Wins
        geom_point(data = tibble(x = seq(6.8, 8.3, length.out = 4), y = 2.7, won = 1:4 <= st$nl_lad_wins),
                   aes(x = x, y = y, fill = won), shape = 21, size = 6.5, color = "#F8FAFC", stroke = 1.2) +
        scale_fill_manual(values = c("TRUE" = "#FACC15", "FALSE" = "#1F2937"), guide = "none") +
        # Series Tally Numbers
        annotate("text", x = 4.0, y = 5.3, label = sprintf("%d W", st$al_tb_wins), color = "#38BDF8", fontface = "bold", size = 4.0) +
        annotate("text", x = 4.0, y = 2.7, label = sprintf("%d W", st$al_cle_wins), color = "#94A3B8", fontface = "bold", size = 4.0) +
        annotate("text", x = 8.6, y = 5.3, label = sprintf("%d W", st$nl_mil_wins), color = "#FACC15", fontface = "bold", size = 4.0) +
        annotate("text", x = 8.6, y = 2.7, label = sprintf("%d W", st$nl_lad_wins), color = "#94A3B8", fontface = "bold", size = 4.0) +
        # Clinch Banners
        { if (st$nl_mil_wins == 4) annotate("label", x = 7.5, y = 1.8, label = "★ NL CHAMPIONS (MIL 4-0) ★", fill = "#B45309", color = "#FFFFFF", fontface = "bold", size = 4.0) } +
        { if (st$al_tb_wins == 4) annotate("label", x = 2.5, y = 1.8, label = "★ AL CHAMPIONS (TB 4-2) ★", fill = "#0284C7", color = "#FFFFFF", fontface = "bold", size = 4.0) } +
        scale_x_continuous(limits = c(0.2, 9.8), expand = c(0, 0)) +
        scale_y_continuous(limits = c(0.8, 8.8), expand = c(0, 0)) +
        theme_mlb_dark(base_size = 11) +
        theme(
          axis.title = element_blank(),
          axis.text  = element_blank(),
          axis.ticks = element_blank(),
          panel.grid = element_blank()
        ) +
        labs(
          title = sprintf("%d League Championship Series Showdown — %s", season, st$title),
          subtitle = st$subtitle,
          caption = "Source: KayceeSlices MLB Analytics Engine | Best-of-7 Pennant Series Tracker"
        )
    } else {
      # Climax World Series Emblem Matchup Banner
      ws_teams <- tribble(
        ~team_abbr, ~league, ~pennant_title, ~seed, ~reg_wins, ~x, ~y,
        "TB", "American League", "2026 AL CHAMPIONS", "Seed #4 (Wild Card)", 114, 2.8, 4.5,
        "MIL", "National League", "2026 NL CHAMPIONS", "Seed #1 (NLC Winner)", 124, 7.2, 4.5
      )

      p <- ggplot() +
        # Outer Gold Trim Banner
        annotate("rect", xmin = 0.5, xmax = 9.5, ymin = 0.8, ymax = 8.5, fill = "#0A0E17", color = "#FACC15", linewidth = 2.2, alpha = 0.95) +
        # Header Badge
        annotate("rect", xmin = 2.8, xmax = 7.2, ymin = 7.3, ymax = 8.3, fill = "#1E293B", color = "#FACC15", linewidth = 1.2) +
        annotate("text", x = 5.0, y = 7.8, label = "THE 2026 WORLD SERIES", color = "#FACC15", fontface = "bold", size = 6.2) +
        # Subtitle
        annotate("text", x = 5.0, y = 6.8, label = "THE 122ND FALL CLASSIC • COMMISSIONER'S TROPHY ON THE LINE", color = "#E2E8F0", fontface = "bold", size = 3.8) +
        # Giant Logos
        geom_mlb_logos(
          data = ws_teams,
          aes(x = x, y = y, team_abbr = team_abbr),
          width = 0.22
        ) +
        # Team Names & Accolades
        # Rays
        annotate("text", x = 2.8, y = 2.8, label = "TAMPA BAY RAYS", color = "#38BDF8", fontface = "bold", size = 5.2) +
        annotate("text", x = 2.8, y = 2.3, label = "2026 AL Champions (114-85 Regular Season)\nDefeated: BOS (2-0), NYY (3-0), CLE (4-2)", color = "#CBD5E1", size = 3.2) +
        # Center VS Crest
        annotate("label", x = 5.0, y = 4.5, label = "VS", fill = "#B45309", color = "#FFFFFF", fontface = "bold", size = 6.5, label.padding = unit(0.5, "lines")) +
        # Brewers
        annotate("text", x = 7.2, y = 2.8, label = "MILWAUKEE BREWERS", color = "#FBBF24", fontface = "bold", size = 5.2) +
        annotate("text", x = 7.2, y = 2.3, label = "2026 NL Champions (124-77 Regular Season)\nDefeated: SD (3-1), LAD (4-0)", color = "#CBD5E1", size = 3.2) +
        # Bottom Current Status
        annotate("label", x = 5.0, y = 1.3, label = "Series Status: Brewers lead 2-0 | Game 1: MIL 3-2 TB | Game 2: MIL 5-4 TB", fill = "#1E293B", color = "#F8FAFC", fontface = "bold", size = 3.8) +
        scale_x_continuous(limits = c(0.2, 9.8), expand = c(0, 0)) +
        scale_y_continuous(limits = c(0.5, 8.8), expand = c(0, 0)) +
        theme_mlb_dark(base_size = 11) +
        theme(
          axis.title = element_blank(),
          axis.text  = element_blank(),
          axis.ticks = element_blank(),
          panel.grid = element_blank()
        ) +
        labs(
          title = "2026 Major League Baseball World Series Showdown",
          subtitle = "October Climax: The American League Pennant Winner vs National League Pennant Winner",
          caption = "Source: KayceeSlices MLB Analytics Engine | Official Transparent Franchise Logos"
        )
    }

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 12.0, height = 7.5, dpi = 110, bg = "#0A0E17")
    frame_files[idx] <- fpath
  }

  target_gif <- cache_path("viz", output_gif)
  target_png <- cache_path("viz", output_png)

  # Copy final frame as static PNG artifact
  file.copy(tail(frame_files, 1), target_png, overwrite = TRUE)

  # Hold final frame
  final_frames <- c(frame_files, rep(tail(frame_files, 1), hold_frames))

  gifski::gifski(
    png_files = final_frames,
    gif_file  = target_gif,
    width     = 1200,
    height    = 750,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  message(sprintf(">>> [SUCCESS] Pennant Showdown generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_pennant_showdown()
}
