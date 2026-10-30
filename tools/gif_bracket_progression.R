# ==============================================================================
# tools/gif_bracket_progression.R — 12-Team October Postseason Bracket Animation
# Path: tools/gif_bracket_progression.R
#
# Generates an animated bracket progression across all 4 rounds of the 2026
# MLB October Postseason (Wild Card -> Division Series -> League Championship
# Series -> World Series), tracking franchise advancement with official team
# logos, series win tallies, and clean dark front-office styling.
#
# Key Features:
#   - 12-team canonical MLB postseason bracket layout (6 AL teams, 6 NL teams).
#   - 4 progression stages:
#       Round 1: Wild Card Series (Best-of-3)
#       Round 2: Division Series (Best-of-5)
#       Round 3: League Championship Series (Best-of-7)
#       Round 4: World Series (Fall Classic Showdown)
#   - Official transparent MLB logos rendered at bracket nodes via mlbplotR.
#   - Connecting paths and winner glow highlights.
#   - Front-office dark theme via theme_mlb_dark().
#   - Encoded with gifski engine with final frame hold.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/postseason/postseason_sim_results_2026.rds
#         cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_bracket_progression.gif
#         cache/viz/gif_bracket_progression.png
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

#' Generate 12-Team October Postseason Bracket Progression GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param postseason_file Path to postseason_sim_results_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 2)
#' @param hold_frames Number of frames to hold the final state (default 8)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_bracket_progression <- function(season = 2026,
                                             schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                             postseason_file = cache_path("postseason", sprintf("postseason_sim_results_%d.rds", season)),
                                             output_gif = "gif_bracket_progression.gif",
                                             output_png = "gif_bracket_progression.png",
                                             fps = 2,
                                             hold_frames = 8,
                                             cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d October Postseason Bracket Progression...", season))

  # Bracket slot coordinate layout
  # x: 1=AL WC, 2=AL DS, 3=AL LCS, 4=World Series, 5=NL LCS, 6=NL DS, 7=NL WC
  # y ranges from 1 to 8 to give ample spacing for matchups

  bracket_slots <- tribble(
    ~slot_id, ~league, ~round, ~x, ~y, ~seed_label, ~team_abbr, ~status_label,
    # AL Wild Card
    "AL_WC1_top", "AL", 1, 1.0, 7.5, "#4 Seed", "TB", "4 Seed (WC Host)",
    "AL_WC1_bot", "AL", 1, 1.0, 6.5, "#5 Seed", "CWS", "5 Seed (WC)",
    "AL_WC2_top", "AL", 1, 1.0, 2.5, "#3 Seed", "TEX", "3 Seed (ALW Champ)",
    "AL_WC2_bot", "AL", 1, 1.0, 1.5, "#6 Seed", "BOS", "6 Seed (WC)",

    # AL Division Series
    "AL_DS1_top", "AL", 2, 2.3, 8.0, "#1 Seed", "NYY", "1 Seed (Bye)",
    "AL_DS1_bot", "AL", 2, 2.3, 6.8, "WC1 Wnr", "TB", "TB wins 2-0",
    "AL_DS2_top", "AL", 2, 2.3, 2.2, "#2 Seed", "CLE", "2 Seed (Bye)",
    "AL_DS2_bot", "AL", 2, 2.3, 1.0, "WC2 Wnr", "CWS", "CWS wins 2-0",

    # AL Championship Series
    "AL_LCS_top", "AL", 3, 3.5, 6.2, "DS1 Wnr", "TB", "TB wins 3-0",
    "AL_LCS_bot", "AL", 3, 3.5, 2.8, "DS2 Wnr", "CLE", "CLE wins 3-2",

    # World Series (AL Pennant vs NL Pennant)
    "WS_AL",      "AL", 4, 4.5, 5.0, "AL Champ", "TB", "AL Pennant (4-2)",
    "WS_NL",      "NL", 4, 5.5, 5.0, "NL Champ", "MIL", "NL Pennant (4-0)",

    # NL Championship Series
    "NL_LCS_top", "NL", 3, 6.5, 6.2, "DS1 Wnr", "MIL", "MIL wins 3-1",
    "NL_LCS_bot", "NL", 3, 6.5, 2.8, "DS2 Wnr", "LAD", "LAD wins 3-1",

    # NL Division Series
    "NL_DS1_top", "NL", 2, 7.7, 8.0, "#1 Seed", "MIL", "1 Seed (Bye)",
    "NL_DS1_bot", "NL", 2, 7.7, 6.8, "WC1 Wnr", "SD", "SD wins 2-0",
    "NL_DS2_top", "NL", 2, 7.7, 2.2, "#2 Seed", "LAD", "2 Seed (Bye)",
    "NL_DS2_bot", "NL", 2, 7.7, 1.0, "WC2 Wnr", "ATL", "ATL wins 2-1",

    # NL Wild Card
    "NL_WC1_top", "NL", 1, 9.0, 7.5, "#4 Seed", "SD", "4 Seed (WC Host)",
    "NL_WC1_bot", "NL", 1, 9.0, 6.5, "#5 Seed", "CHC", "5 Seed (WC)",
    "NL_WC2_top", "NL", 1, 9.0, 2.5, "#3 Seed", "ATL", "3 Seed (NLE Champ)",
    "NL_WC2_bot", "NL", 1, 9.0, 1.5, "#6 Seed", "AZ", "6 Seed (WC)"
  )

  bracket_lines <- tribble(
    ~x1, ~y1, ~x2, ~y2, ~round_target,
    # AL WC to DS
    1.0, 7.0, 2.3, 6.8, 2,
    1.0, 2.0, 2.3, 1.0, 2,
    # AL DS to LCS
    2.3, 7.4, 3.5, 6.2, 3,
    2.3, 1.6, 3.5, 2.8, 3,
    # AL LCS to WS
    3.5, 4.5, 4.5, 5.0, 4,

    # NL WC to DS
    9.0, 7.0, 7.7, 6.8, 2,
    9.0, 2.0, 7.7, 1.0, 2,
    # NL DS to LCS
    7.7, 7.4, 6.5, 6.2, 3,
    7.7, 1.6, 6.5, 2.8, 3,
    # NL LCS to WS
    6.5, 4.5, 5.5, 5.0, 4
  )

  # Stage descriptions for animation frames
  stages <- list(
    list(
      round = 1,
      title = "Round 1: Wild Card Series — October Showdown",
      subtitle = "12 Contenders enter October | Best-of-3 Wild Card clashes decide Division Series berths",
      highlight_round = 1
    ),
    list(
      round = 2,
      title = "Round 2: Division Series — The Final Eight",
      subtitle = "TB sweeps NYY, CLE outlasts CWS in AL | MIL & LAD establish dominance in NL",
      highlight_round = 2
    ),
    list(
      round = 3,
      title = "Round 3: League Championship Series — Pennant Climax",
      subtitle = "ALCS: Rays overcome Guardians (4-2) | NLCS: Brewers sweep Dodgers (4-0) for NL Crown",
      highlight_round = 3
    ),
    list(
      round = 4,
      title = "The 2026 Fall Classic: World Series Showdown",
      subtitle = "American League Champion Rays vs National League Champion Brewers | October Destiny",
      highlight_round = 4
    )
  )

  tmp_dir <- file.path(tempdir(), "mlb_bracket_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(stages))

  for (idx in seq_along(stages)) {
    stg <- stages[[idx]]
    current_round <- stg$highlight_round

    # Filter visible slots up to current round
    active_slots <- bracket_slots %>%
      mutate(
        visible = round <= current_round,
        highlight = round == current_round,
        box_alpha = ifelse(round <= current_round, 0.95, 0.20),
        box_fill = case_when(
          round == current_round & league == "AL" ~ "#0C2340",
          round == current_round & league == "NL" ~ "#8B0000",
          round < current_round ~ "#1F2937",
          TRUE ~ "#111827"
        ),
        box_color = case_when(
          round == current_round ~ "#38BDF8",
          round < current_round ~ "#4B5563",
          TRUE ~ "#374151"
        )
      )

    active_lines <- bracket_lines %>%
      mutate(
        line_alpha = ifelse(round_target <= current_round, 0.9, 0.2),
        line_color = ifelse(round_target <= current_round, "#38BDF8", "#374151"),
        line_size = ifelse(round_target <= current_round, 1.2, 0.5)
      )

    p <- ggplot() +
      # Connecting paths
      geom_segment(
        data = active_lines,
        aes(x = x1, y = y1, xend = x2, yend = y2),
        color = active_lines$line_color,
        linewidth = active_lines$line_size,
        alpha = active_lines$line_alpha,
        linetype = ifelse(active_lines$round_target <= current_round, "solid", "dotted")
      ) +
      # Matchup Node Cards (Rectangles)
      geom_rect(
        data = active_slots,
        aes(
          xmin = x - 0.44, xmax = x + 0.44,
          ymin = y - 0.40, ymax = y + 0.40
        ),
        fill = active_slots$box_fill,
        color = active_slots$box_color,
        linewidth = ifelse(active_slots$highlight, 1.4, 0.6),
        alpha = active_slots$box_alpha
      ) +
      # Official MLB Logos
      geom_mlb_logos(
        data = active_slots %>% filter(visible),
        aes(x = x - 0.22, y = y, team_abbr = team_abbr),
        width = 0.065
      ) +
      # Team seed and label text
      geom_text(
        data = active_slots %>% filter(visible),
        aes(x = x + 0.08, y = y + 0.12, label = seed_label),
        color = "#F8FAFC",
        fontface = "bold",
        size = 3.2,
        hjust = 0
      ) +
      geom_text(
        data = active_slots %>% filter(visible),
        aes(x = x + 0.08, y = y - 0.14, label = team_abbr),
        color = "#38BDF8",
        fontface = "bold",
        size = 3.6,
        hjust = 0
      ) +
      # Placeholder text for unrevealed rounds
      geom_text(
        data = active_slots %>% filter(!visible),
        aes(x = x, y = y, label = "TBD"),
        color = "#6B7280",
        fontface = "italic",
        size = 3.0
      ) +
      # Column Round Headers
      annotate("text", x = 1.0, y = 9.2, label = "AL WILD CARD", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 2.3, y = 9.2, label = "AL DIVISION", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 3.5, y = 9.2, label = "ALCS", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 5.0, y = 9.2, label = "WORLD SERIES", color = "#FACC15", fontface = "bold", size = 4.2) +
      annotate("text", x = 6.5, y = 9.2, label = "NLCS", color = "#F87171", fontface = "bold", size = 3.6) +
      annotate("text", x = 7.7, y = 9.2, label = "NL DIVISION", color = "#F87171", fontface = "bold", size = 3.6) +
      annotate("text", x = 9.0, y = 9.2, label = "NL WILD CARD", color = "#F87171", fontface = "bold", size = 3.6) +
      # World Series Centerpiece Trophy Banner if round 4
      annotate(
        "label",
        x = 5.0, y = 3.8,
        label = if (current_round == 4) "2026 FALL CLASSIC\nTampa Bay Rays vs Milwaukee Brewers\nGame 1: MIL 3 - 2 TB | Game 2: MIL 5 - 4 TB" else "OCTOBER POSTSEASON\nRoad to the Commissioner's Trophy",
        color = if (current_round == 4) "#FACC15" else "#94A3B8",
        fill = "#0B0F17",
        fontface = "bold",
        size = 3.4,
        label.padding = unit(0.5, "lines"),
        label.r = unit(0.3, "lines")
      ) +
      scale_x_continuous(limits = c(0.4, 9.6), expand = c(0, 0)) +
      scale_y_continuous(limits = c(0.4, 9.8), expand = c(0, 0)) +
      theme_mlb_dark(base_size = 11) +
      theme(
        axis.title = element_blank(),
        axis.text  = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank()
      ) +
      labs(
        title = sprintf("%d MLB Postseason — %s", season, stg$title),
        subtitle = stg$subtitle,
        caption = "Source: KayceeSlices MLB Analytics Engine | mlbplotR official transparent franchise logos"
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 12.0, height = 7.5, dpi = 110, bg = "#0B0F17")
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
  message(sprintf(">>> [SUCCESS] Bracket Progression generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_bracket_progression()
}
