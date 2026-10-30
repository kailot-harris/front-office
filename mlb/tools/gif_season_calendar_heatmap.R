# ==============================================================================
# tools/gif_season_calendar_heatmap.R — Season in 60 Seconds: 30-Team Micro-Calendar Heatmap
# Path: tools/gif_season_calendar_heatmap.R
#
# Generates an animated chronological micro-calendar heatmap sweep visualizing
# the full 162-game regular season for all 30 MLB franchises:
#   - 30 team rows sorted by division and final win percentage
#   - 162 game column blocks sweeping from Game 1 (March/April) to Game 162 (September/October)
#   - Color encoding:
#       * Green (#2EA043 / #3FB950) = Win
#       * Red (#DA3633 / #F85149)   = Loss
#       * Neutral Dark (#21262D)   = Unplayed / Future Game
#
# Features:
#   - Official transparent MLB franchise logos positioned at the left axis headers via mlbplotR
#   - Month divider markers (Apr, May, Jun, Jul, Aug, Sep) at milestone game markers
#   - Dynamic sweeping cursor / scanner highlighting the current game progress column
#   - Division strip / color accents
#   - Clean dark front-office styling via theme_mlb_dark()
#   - Dual artifact export: animated GIF and static final-frame PNG
#
# Input:  cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_season_calendar_heatmap.gif
#         cache/viz/gif_season_calendar_heatmap.png
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

#' Generate 30-Team 162-Game Micro-Calendar Heatmap Sweep GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param sample_step Game milestone increment between animation frames (default 6)
#' @param fps Frames per second for GIF playback (default 8)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_season_calendar_heatmap <- function(season = 2026,
                                                 schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                                 output_gif = "gif_season_calendar_heatmap.gif",
                                                 output_png = "gif_season_calendar_heatmap.png",
                                                 sample_step = 6,
                                                 fps = 8,
                                                 hold_frames = 12,
                                                 cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Season in 60 Seconds Micro-Calendar Heatmap...", season))

  # Locate schedule file with worktree fallback
  if (!file.exists(schedule_file)) {
    alt_sch <- file.path(MLB_ROOT_DIR, "..", "MLB Analytics", "cache", "ingest", sprintf("mlb_schedule_%d.rds", season))
    if (file.exists(alt_sch)) {
      schedule_file <- alt_sch
    } else {
      stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
    }
  }

  sch <- readRDS(schedule_file)
  if (nrow(sch) == 0) {
    stop("Schedule dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)

  # Filter regular-season completed games
  reg <- sch %>%
    filter(
      game_type == "R",
      !is.na(home_score),
      !is.na(away_score),
      home_team_id %in% act_teams$team_id,
      away_team_id %in% act_teams$team_id
    ) %>%
    arrange(as.Date(official_date), game_pk)

  if (nrow(reg) == 0) {
    stop("No regular season games found in schedule.")
  }

  # Build per-team chronological game-by-game results
  home_games <- reg %>%
    transmute(
      team_id = home_team_id,
      date = as.Date(official_date),
      game_pk = game_pk,
      is_win = as.integer(home_score > away_score)
    )
  away_games <- reg %>%
    transmute(
      team_id = away_team_id,
      date = as.Date(official_date),
      game_pk = game_pk,
      is_win = as.integer(away_score > home_score)
    )

  all_games <- bind_rows(home_games, away_games) %>%
    arrange(team_id, date, game_pk) %>%
    group_by(team_id) %>%
    mutate(
      game_num = row_number()
    ) %>%
    filter(game_num <= 162) %>%
    ungroup()

  # Calculate team season win totals to order rows gracefully (group by division, then wins)
  team_summary <- all_games %>%
    group_by(team_id) %>%
    summarize(
      total_wins = sum(is_win),
      total_games = n(),
      win_pct = total_wins / total_games,
      .groups = "drop"
    ) %>%
    left_join(
      act_teams %>% select(team_id, team_abbreviation, team_full_name, division),
      by = "team_id"
    ) %>%
    arrange(desc(division), win_pct) %>%
    mutate(
      y_rank = row_number(),
      logo_abbr = case_when(
        team_abbreviation == "CHW" ~ "CWS",
        team_abbreviation == "ARI" ~ "AZ",
        TRUE ~ team_abbreviation
      )
    )

  all_games <- all_games %>%
    left_join(team_summary %>% select(team_id, y_rank, team_abbreviation, logo_abbr, division), by = "team_id")

  # Full 30-team x 162-game grid
  grid_df <- tidyr::expand_grid(
    team_id = team_summary$team_id,
    game_num = 1:162
  ) %>%
    left_join(team_summary %>% select(team_id, y_rank, team_abbreviation, logo_abbr, division), by = "team_id") %>%
    left_join(all_games %>% select(team_id, game_num, is_win, date), by = c("team_id", "game_num"))

  # Animation milestone frames across 162 games
  milestones <- c(seq(6, 162, by = sample_step), 162)
  milestones <- sort(unique(milestones))
  n_milestones <- length(milestones)

  # Setup frame directory
  viz_dir <- ensure_viz_dir()
  frame_dir <- file.path(viz_dir, "frames_calendar_heatmap")
  if (dir.exists(frame_dir)) unlink(frame_dir, recursive = TRUE)
  dir.create(frame_dir, recursive = TRUE, showWarnings = FALSE)

  message(sprintf("Rendering %d animation frames for Season Calendar Heatmap...", n_milestones + hold_frames))

  frame_files <- character(n_milestones + hold_frames)
  total_frames <- n_milestones + hold_frames

  # Month marker benchmarks (average regular season game milestones)
  # Apr: ~G28, May: ~G55, Jun: ~G81, Jul: ~G107, Aug: ~G134, Sep/Oct: 162
  month_breaks <- tibble(
    x = c(28, 55, 81, 107, 134),
    label = c("END APR", "END MAY", "MIDSEASON", "TRADE DL", "PENNANT RACE")
  )

  for (f in seq_len(total_frames)) {
    cur_step <- min(f, n_milestones)
    cur_max_g <- milestones[cur_step]

    # Assign frame status
    frame_grid <- grid_df %>%
      mutate(
        status = case_when(
          game_num > cur_max_g ~ "Future",
          is_win == 1 ~ "Win",
          is_win == 0 ~ "Loss",
          TRUE ~ "Future"
        )
      )

    p <- ggplot(frame_grid, aes(x = game_num, y = y_rank)) +
      # Grid heat blocks
      geom_tile(aes(fill = status), color = "#161B22", linewidth = 0.3) +
      scale_fill_manual(
        values = c(
          "Win" = "#2EA043",
          "Loss" = "#DA3633",
          "Future" = "#21262D"
        ),
        guide = guide_legend(override.aes = list(linewidth = 0.5))
      ) +
      # Month divider lines
      geom_vline(data = month_breaks, aes(xintercept = x), linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      # Sweeping current game scanner beam
      geom_vline(xintercept = cur_max_g, color = "#FACC15", linewidth = 1.2, alpha = 0.85) +
      # Team logos on left axis (x = -4)
      geom_mlb_logos(
        data = team_summary,
        aes(x = -4.5, y = y_rank, team_abbr = logo_abbr),
        width = 0.042,
        inherit.aes = FALSE
      ) +
      # Scales
      scale_x_continuous(
        limits = c(-8, 166),
        breaks = c(1, 28, 55, 81, 107, 134, 162),
        labels = c("Gm 1", "Apr", "May", "All-Star", "Aug", "Sep", "Gm 162"),
        expand = expansion(mult = c(0, 0.02))
      ) +
      scale_y_continuous(
        limits = c(0.4, 30.6),
        breaks = NULL,
        expand = expansion(mult = c(0.01, 0.01))
      ) +
      theme_mlb_dark() +
      labs(
        title = sprintf("%d MLB Season in 60 Seconds — 30-Team Micro-Calendar Heatmap", season),
        subtitle = sprintf(
          "Game %d of 162 | Chronological Sweep Across 4,860 Individual Franchise Battles (Green = Win, Red = Loss)",
          cur_max_g
        ),
        x = "Regular Season Chronological Progression (Games 1 to 162)",
        y = "MLB Franchises (Ordered by Division & Record)",
        fill = "Game Outcome",
        caption = "Source: KayceeSlices MLB Analytics Engine | 30 MLB Franchises | mlbplotR transparent franchise logos"
      ) +
      theme(
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        legend.position = "top",
        legend.direction = "horizontal",
        legend.title = element_text(size = 9, face = "bold"),
        legend.text = element_text(size = 8),
        axis.title.y = element_text(margin = margin(r = 12))
      )

    frame_path <- file.path(frame_dir, sprintf("frame_%03d.png", f))
    ggsave(frame_path, plot = p, width = 12, height = 8, dpi = 140, bg = "#161B22")
    frame_files[f] <- frame_path

    if (f %% 5 == 0 || f == total_frames) {
      message(sprintf("  Rendered frame %d / %d", f, total_frames))
    }
  }

  # Export static final frame
  out_png_path <- cache_path("viz", output_png)
  final_frame <- frame_files[n_milestones]
  file.copy(final_frame, out_png_path, overwrite = TRUE)
  message(sprintf(">>> [PNG] Exported static final frame: %s", out_png_path))

  # Build GIF
  out_gif_path <- cache_path("viz", output_gif)
  gifski(
    png_files = frame_files,
    gif_file = out_gif_path,
    width = 1200,
    height = 800,
    delay = 1 / fps
  )
  message(sprintf(">>> [GIF] Rendered animation: %s (%.1f MB)", out_gif_path, file.size(out_gif_path) / 1e6))

  # Cleanup temporary frames
  if (cleanup_frames && dir.exists(frame_dir)) {
    unlink(frame_dir, recursive = TRUE)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [DONE] Completed Season Calendar Heatmap GIF in %.1f seconds.", elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (sys.nframe() == 0L && !interactive() && !exists(".is_sourced_test")) {
  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else 2026
  generate_gif_season_calendar_heatmap(season = season)
}
