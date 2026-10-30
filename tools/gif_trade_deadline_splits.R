# ==============================================================================
# tools/gif_trade_deadline_splits.R — Pre vs Post Trade Deadline Split Race
# Path: tools/gif_trade_deadline_splits.R
#
# Generates an animated horizontal dumbbell / split bar race tracking all 30
# MLB franchises before vs after the August 1st Trade Deadline, illustrating
# win percentage acceleration vs deceleration (deadline surge vs collapse).
#
# Key Features:
#   - Pre-Deadline (Games through July 31) vs Post-Deadline (August 1 onwards)
#     win percentage split comparisons.
#   - Teams ordered dynamically by net win percentage acceleration:
#     Delta Win % = Post-Deadline Win % - Pre-Deadline Win %.
#   - Official transparent MLB franchise logos via mlbplotR::geom_mlb_logos.
#   - Color coding for buyers / surging teams (green) vs sellers / slumping (red).
#   - Minimal dark front-office styling via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_trade_deadline_splits.gif
#         cache/viz/gif_trade_deadline_splits.png
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

#' Generate Trade Deadline Inflection Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param deadline_date Character date cutoff (default "2026-08-01")
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param sample_step Step interval across post-deadline dates (default 2)
#' @param fps Frames per second for GIF playback (default 8)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_trade_deadline_splits <- function(season = 2026,
                                               deadline_date = "2026-08-01",
                                               schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                               output_gif = "gif_trade_deadline_splits.gif",
                                               output_png = "gif_trade_deadline_splits.png",
                                               sample_step = 2,
                                               fps = 8,
                                               hold_frames = 12,
                                               cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Trade Deadline Splits Animation...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
  }

  sch <- readRDS(schedule_file)
  if (nrow(sch) == 0) {
    stop("Schedule dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_abbr_map <- setNames(act_teams$team_abbreviation, act_teams$team_id)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_id)

  cutoff_d <- as.Date(deadline_date)

  reg <- sch %>%
    filter(
      game_type == "R",
      !is.na(home_score),
      !is.na(away_score),
      home_team_id %in% act_teams$team_id,
      away_team_id %in% act_teams$team_id
    ) %>%
    mutate(game_d = as.Date(official_date))

  if (nrow(reg) == 0) {
    stop("No completed regular-season games found in schedule.")
  }

  # Build game-level results
  long_results <- bind_rows(
    reg %>% transmute(team_id = home_team_id, date = game_d, win = as.integer(home_score > away_score)),
    reg %>% transmute(team_id = away_team_id, date = game_d, win = as.integer(away_score > home_score))
  )

  # Pre-deadline baseline record for each team
  pre_deadline <- long_results %>%
    filter(date < cutoff_d) %>%
    group_by(team_id) %>%
    summarize(
      pre_g = n(),
      pre_w = sum(win),
      pre_pct = pre_w / pre_g,
      .groups = "drop"
    )

  post_games <- long_results %>%
    filter(date >= cutoff_d) %>%
    arrange(date)

  post_dates <- sort(unique(post_games$date))
  if (length(post_dates) == 0) {
    stop("No regular-season games found on or after the deadline.")
  }

  # Sample post-deadline dates for progression
  step_indices <- seq(1, length(post_dates), by = sample_step)
  if (step_indices[length(step_indices)] != length(post_dates)) {
    step_indices <- c(step_indices, length(post_dates))
  }
  frame_dates <- post_dates[step_indices]

  tmp_dir <- tempfile(pattern = "mlb_deadline_splits_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  frame_files <- character()

  message(sprintf("Rendering %d animation frames...", length(frame_dates)))

  for (i in seq_along(frame_dates)) {
    cur_date <- frame_dates[i]
    
    # Calculate post-deadline record through cur_date
    cur_post <- post_games %>%
      filter(date <= cur_date) %>%
      group_by(team_id) %>%
      summarize(
        post_g = n(),
        post_w = sum(win),
        post_pct = ifelse(post_g > 0, post_w / post_g, 0),
        .groups = "drop"
      )

    split_data <- pre_deadline %>%
      inner_join(cur_post, by = "team_id") %>%
      mutate(
        delta_pct = post_pct - pre_pct,
        team_abbr = team_abbr_map[as.character(team_id)],
        surge_type = ifelse(delta_pct >= 0, "Accelerating (+)", "Decelerating (-)")
      ) %>%
      arrange(delta_pct) %>%
      mutate(team_order = factor(team_abbr, levels = team_abbr))

    top_surger <- split_data %>% filter(delta_pct == max(delta_pct)) %>% slice(1)
    top_slider <- split_data %>% filter(delta_pct == min(delta_pct)) %>% slice(1)

    subtitle_txt <- sprintf(
      "Through %s | Top Surge: %s (%+.3f) | Sharpest Drop: %s (%+.3f)",
      format(cur_date, "%b %d, %Y"),
      top_surger$team_abbr, top_surger$delta_pct,
      top_slider$team_abbr, top_slider$delta_pct
    )

    p <- ggplot(split_data, aes(y = team_order)) +
      geom_segment(
        aes(x = pre_pct, xend = post_pct, y = team_order, yend = team_order, color = surge_type),
        linewidth = 1.3, alpha = 0.85
      ) +
      geom_point(aes(x = pre_pct), color = "#8B949E", size = 2.5, shape = 21, fill = "#161B22") +
      geom_point(aes(x = post_pct, color = surge_type), size = 3) +
      mlbplotR::geom_mlb_logos(
        aes(x = post_pct + ifelse(post_pct >= pre_pct, 0.035, -0.035), y = team_order, team_abbr = team_abbr),
        width = 0.04
      ) +
      geom_vline(xintercept = 0.500, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      scale_color_manual(
        values = c("Accelerating (+)" = "#2EA043", "Decelerating (-)" = "#F85149"),
        name = "August 1 Inflection"
      ) +
      scale_x_continuous(
        labels = scales::number_format(accuracy = 0.001),
        limits = c(0.10, 0.90),
        breaks = c(0.250, 0.500, 0.750)
      ) +
      theme_mlb_dark(base_size = 10) +
      theme(
        axis.text.y = element_text(size = rel(0.75)),
        legend.position = "top",
        legend.justification = "right"
      ) +
      labs(
        title = sprintf("%d MLB Trade Deadline Inflection: Pre vs Post Aug 1 Splits", season),
        subtitle = subtitle_txt,
        x = "Win Percentage (Dumbbell: Grey Dot = Pre-Aug 1, Colored Dot/Logo = Post-Aug 1)",
        y = "MLB Franchises (Ordered by Win % Delta)",
        caption = "Front-Office Macro Analytics | Trade Deadline: Aug 1 | mlbplotR"
      )

    frame_path <- file.path(tmp_dir, sprintf("frame_%04d.png", i))
    ggsave(frame_path, plot = p, width = 10, height = 9, dpi = 110)
    frame_files <- c(frame_files, frame_path)
  }

  out_png_path <- file.path(ensure_viz_dir(), output_png)
  file.copy(frame_files[length(frame_files)], out_png_path, overwrite = TRUE)

  final_frame <- frame_files[length(frame_files)]
  held_frames <- c(frame_files, rep(final_frame, hold_frames))

  out_gif_path <- file.path(ensure_viz_dir(), output_gif)
  message("Encoding animated GIF via gifski...")
  gifski::gifski(
    png_files = held_frames,
    gif_file = out_gif_path,
    width = 1000,
    height = 900,
    delay = 1 / fps,
    loop = TRUE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(difftime(Sys.time(), start_time, units = "secs"), 1)
  message(sprintf(">>> [SUCCESS] Created %s and %s in %s seconds", output_gif, output_png, elapsed))

  invisible(list(gif = out_gif_path, png = out_png_path))
}

if (!interactive() && !exists(".is_sourced_test")) {
  args <- commandArgs(trailingOnly = TRUE)
  season <- if (length(args) > 0) as.integer(args[1]) else 2026
  generate_gif_trade_deadline_splits(season = season)
}
