# ==============================================================================
# tools/gif_home_away_divergence.R — 30-Team Home vs Road Win % Divergence Race
# Path: tools/gif_home_away_divergence.R
#
# Generates an animated divergence split-bar race showing Home win percentage
# vs Away/Road win percentage divergence across all 30 MLB franchises through
# the 2026 season.
#
# Key Features:
#   - Calculates cumulative Home Win % and Road Win % for all 30 teams over time.
#   - Divergence metric: Home Win % - Road Win % (Home Field Advantage delta).
#   - Bi-directional split bars colored by divergence:
#       * Home Dominant (> 0, green) vs Road Resilient (< 0, orange/cyan).
#   - Official transparent MLB franchise logos at the ends of bars via mlbplotR.
#   - Teams ordered dynamically by divergence or home split dominance.
#   - Dark front-office theme via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_home_away_divergence.gif
#         cache/viz/gif_home_away_divergence.png
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

#' Generate Home vs Away Divergence Split-Bar Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param sample_step Step interval across sorted game dates (default 3)
#' @param fps Frames per second for GIF playback (default 8)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_home_away_divergence <- function(season = 2026,
                                              schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                              output_gif = "gif_home_away_divergence.gif",
                                              output_png = "gif_home_away_divergence.png",
                                              sample_step = 3,
                                              fps = 8,
                                              hold_frames = 12,
                                              cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Home vs Away Divergence Animation...", season))

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

  # Build location-specific game results
  home_games <- reg %>%
    transmute(
      team_id = home_team_id,
      date = game_d,
      is_home = TRUE,
      win = as.integer(home_score > away_score)
    )

  away_games <- reg %>%
    transmute(
      team_id = away_team_id,
      date = game_d,
      is_home = FALSE,
      win = as.integer(away_score > home_score)
    )

  all_splits <- bind_rows(home_games, away_games)
  all_dates <- sort(unique(all_splits$date))

  # Sample dates starting from day 20 to ensure both home and away games have occurred
  date_indices <- seq(20, length(all_dates), by = sample_step)
  if (date_indices[length(date_indices)] != length(all_dates)) {
    date_indices <- c(date_indices, length(all_dates))
  }
  frame_dates <- all_dates[date_indices]

  tmp_dir <- tempfile(pattern = "mlb_home_away_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  frame_files <- character()

  message(sprintf("Rendering %d animation frames...", length(frame_dates)))

  for (i in seq_along(frame_dates)) {
    cur_date <- frame_dates[i]
    cur_games <- all_splits %>% filter(date <= cur_date)

    team_summary <- cur_games %>%
      group_by(team_id) %>%
      summarize(
        home_g = sum(is_home),
        home_w = sum(win[is_home]),
        away_g = sum(!is_home),
        away_w = sum(win[!is_home]),
        home_pct = ifelse(home_g > 0, home_w / home_g, 0),
        away_pct = ifelse(away_g > 0, away_w / away_g, 0),
        divergence = home_pct - away_pct,
        .groups = "drop"
      ) %>%
      mutate(
        team_abbr = team_abbr_map[as.character(team_id)],
        div_type = ifelse(divergence >= 0, "Home Dominant", "Road Resilient")
      ) %>%
      arrange(divergence) %>%
      mutate(team_order = factor(team_abbr, levels = team_abbr))

    top_home <- team_summary %>% filter(divergence == max(divergence)) %>% slice(1)
    top_road <- team_summary %>% filter(divergence == min(divergence)) %>% slice(1)

    subtitle_txt <- sprintf(
      "Through %s | Greatest Home Edge: %s (%+.3f) | Road Warriors: %s (%+.3f)",
      format(cur_date, "%b %d, %Y"),
      top_home$team_abbr, top_home$divergence,
      top_road$team_abbr, top_road$divergence
    )

    p <- ggplot(team_summary, aes(x = divergence, y = team_order, fill = div_type)) +
      geom_vline(xintercept = 0, linetype = "solid", color = "#484F58", linewidth = 0.6) +
      geom_col(width = 0.7, alpha = 0.85) +
      mlbplotR::geom_mlb_logos(
        aes(
          x = divergence + ifelse(divergence >= 0, 0.025, -0.025),
          y = team_order,
          team_abbr = team_abbr
        ),
        width = 0.038
      ) +
      scale_fill_manual(
        values = c("Home Dominant" = "#238636", "Road Resilient" = "#1F6FEB"),
        name = "Venue Split Bias"
      ) +
      scale_x_continuous(
        labels = scales::percent_format(accuracy = 1),
        limits = c(-0.35, 0.45),
        breaks = c(-0.30, -0.15, 0, 0.15, 0.30)
      ) +
      theme_mlb_dark(base_size = 10) +
      theme(
        axis.text.y = element_text(size = rel(0.75)),
        legend.position = "top",
        legend.justification = "right"
      ) +
      labs(
        title = sprintf("%d MLB Home vs Road Win %% Divergence Race", season),
        subtitle = subtitle_txt,
        x = "Divergence Split: Home Win % minus Road Win % (Positive = Home Advantage)",
        y = "MLB Franchises (Ordered by Venue Divergence)",
        caption = "Front-Office Macro Analytics | Venue Split Analysis | mlbplotR"
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
  generate_gif_home_away_divergence(season = season)
}
