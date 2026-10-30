# ==============================================================================
# tools/gif_bullpen_fatigue_race.R — 30-Team Bullpen Fatigue Index Progression
# Path: tools/gif_bullpen_fatigue_race.R
#
# Generates an animated multi-line trajectory race and small-multiples tracking
# bullpen workload, arm-stress, and fatigue index progression across all 30
# MLB franchises.
#
# Key Features:
#   - Faceted across the 6 canonical MLB divisions (AL East, AL Central, AL West,
#     NL East, NL Central, NL West) using MLB_DIVISION_COLORS.
#   - Trajectory curves tracking daily/rolling team bullpen fatigue index (0-100).
#   - Official transparent MLB franchise logos at the leading edge of each
#     team trajectory via mlbplotR::geom_mlb_logos.
#   - Workload stress threshold lines:
#       * 40: Moderate Workload
#       * 70: Elevated Workload / Arm Stress
#       * 85: High Vulnerability / Exhaustion Zone
#   - Full dark front-office theme via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Input:  cache/specialty/bullpen_fatigue_daily_2026.rds (or bullpen_fatigue_daily.rds)
# Output: cache/viz/gif_bullpen_fatigue_race.gif
#         cache/viz/gif_bullpen_fatigue_race.png
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

#' Generate Bullpen Fatigue Trajectory Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param daily_file Path to bullpen_fatigue_daily_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_bullpen_fatigue_race <- function(season = 2026,
                                              daily_file = cache_path("specialty", sprintf("bullpen_fatigue_daily_%d.rds", season)),
                                              output_gif = "gif_bullpen_fatigue_race.gif",
                                              output_png = "gif_bullpen_fatigue_race.png",
                                              fps = 6,
                                              hold_frames = 12,
                                              cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Bullpen Fatigue Trajectory Race...", season))

  if (!file.exists(daily_file)) {
    fallback_file <- cache_path("specialty", "bullpen_fatigue_daily.rds")
    if (file.exists(fallback_file)) {
      daily_file <- fallback_file
    } else {
      stop(sprintf("Bullpen daily fatigue file not found at '%s'. Run mlb_bullpen_fatigue.R first.", daily_file))
    }
  }

  bf_raw <- readRDS(daily_file)
  if (nrow(bf_raw) == 0) {
    stop("Bullpen daily fatigue dataframe is empty.")
  }

  # Active 30 MLB franchises
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)

  # Create lookup dictionary mapping both full name and abbreviation to standard abbreviation
  name_to_abbr <- setNames(act_teams$team_abbreviation, act_teams$team_full_name)
  for (i in seq_len(nrow(act_teams))) {
    name_to_abbr[act_teams$team_abbreviation[i]] <- act_teams$team_abbreviation[i]
  }

  team_div_map <- setNames(act_teams$division, act_teams$team_abbreviation)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_abbreviation)

  bf <- bf_raw %>%
    mutate(
      date = as.Date(game_date),
      team_abbr = name_to_abbr[team]
    ) %>%
    filter(!is.na(team_abbr))

  # If season dates exist, filter to season
  d_2026 <- bf %>% filter(date >= as.Date(sprintf("%d-01-01", season)))
  if (nrow(d_2026) > 0) {
    bf <- d_2026
  }

  # Aggregate mean bullpen fatigue and count of fatigued/exhausted relievers per team per date
  daily_team_fatigue <- bf %>%
    group_by(team_abbr, date) %>%
    summarize(
      bullpen_fatigue = round(mean(fatigue_score), 1),
      high_stress_relievers = sum(fatigue_status %in% c("Fatigued", "Exhausted")),
      .groups = "drop"
    )

  all_dates <- sort(unique(daily_team_fatigue$date))
  all_teams <- sort(unique(act_teams$team_abbreviation))

  # Complete team x date grid
  grid_td <- expand_grid(team_abbr = all_teams, date = all_dates)
  team_traj <- grid_td %>%
    left_join(daily_team_fatigue, by = c("team_abbr", "date")) %>%
    arrange(team_abbr, date) %>%
    group_by(team_abbr) %>%
    tidyr::fill(bullpen_fatigue, high_stress_relievers, .direction = "down") %>%
    ungroup() %>%
    mutate(
      bullpen_fatigue = coalesce(bullpen_fatigue, 20.0),
      high_stress_relievers = coalesce(high_stress_relievers, 0L),
      team_name = team_name_map[team_abbr],
      division  = factor(team_div_map[team_abbr],
                         levels = c("AL East", "AL Central", "AL West",
                                    "NL East", "NL Central", "NL West"))
    )

  tmp_dir <- file.path(tempdir(), "mlb_bullpen_fatigue_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(all_dates))

  for (idx in seq_along(all_dates)) {
    cur_d <- all_dates[idx]
    sub_traj <- team_traj %>% filter(date <= cur_d)
    cur_pts  <- team_traj %>% filter(date == cur_d)

    top_stressed <- cur_pts %>% arrange(desc(bullpen_fatigue)) %>% slice(1)
    subtitle_txt <- sprintf("Through %s | Peak Bullpen Stress: %s (Index: %.0f / 100)",
                            format(cur_d, "%B %d, %Y"), top_stressed$team_name, top_stressed$bullpen_fatigue)

    p <- ggplot(sub_traj, aes(x = date, y = bullpen_fatigue, group = team_abbr, color = division)) +
      # Arm-stress reference zones
      geom_hline(yintercept = 70, linetype = "dashed", color = "#D19A66", linewidth = 0.5) +
      geom_hline(yintercept = 85, linetype = "dotted", color = "#E06C75", linewidth = 0.6) +
      geom_line(linewidth = 0.85, alpha = 0.85) +
      geom_mlb_logos(
        data = cur_pts,
        aes(x = date, y = bullpen_fatigue, team_abbr = team_abbr),
        width = 0.08,
        inherit.aes = FALSE
      ) +
      facet_wrap(~ division, ncol = 3, scales = "fixed") +
      scale_color_manual(values = MLB_DIVISION_COLORS) +
      scale_x_date(
        date_breaks = "1 week",
        date_labels = "%b %d",
        limits = c(min(all_dates), max(all_dates))
      ) +
      scale_y_continuous(
        limits = c(0, 108),
        breaks = seq(0, 100, by = 25)
      ) +
      theme_mlb_dark(base_size = 11) +
      theme(
        legend.position = "none",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", size = 11)
      ) +
      labs(
        title = sprintf("%d MLB Bullpen Fatigue & Arm-Stress Progression Race", season),
        subtitle = subtitle_txt,
        x = sprintf("Date (%d Regular Season)", season),
        y = "Composite Bullpen Fatigue Index (0-100)",
        caption = "Dashed: Elevated (70) | Dotted: Exhaustion Alert (85) | Source: KayceeSlices MLB Analytics"
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 11.5, height = 7.2, dpi = 110, bg = "#161B22")
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
    width     = 1150,
    height    = 720,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  message(sprintf(">>> [SUCCESS] Bullpen Fatigue Race generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_bullpen_fatigue_race()
}
