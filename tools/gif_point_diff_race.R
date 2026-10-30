# ==============================================================================
# tools/gif_point_diff_race.R — 30-Team Cumulative Run Differential Race Animation
# Path: tools/gif_point_diff_race.R
#
# Generates an animated multi-line trajectory race showing cumulative run
# differential (Runs Scored minus Runs Allowed) for all 30 MLB franchises
# across the 2026 regular season.
#
# Key Features:
#   - Faceted across the 6 canonical MLB divisions (AL East, AL Central, AL West,
#     NL East, NL Central, NL West) for clarity, matching sibling implementations.
#   - Official transparent MLB franchise logos at the leading edge of each
#     team trajectory via mlbplotR::geom_mlb_logos.
#   - Zero differential dashed baseline reference in every panel.
#   - High-contrast dark front-office theme via theme_mlb_dark().
#   - Dynamic subtitle reflecting date, league run differential leader, and top surge.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Input:  cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_point_diff_race.gif
#         cache/viz/gif_point_diff_race.png
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

#' Generate Cumulative Run Differential Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param sample_step Step interval across sorted game dates (default 3)
#' @param fps Frames per second for GIF playback (default 8)
#' @param hold_frames Number of frames to hold the final standings (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_point_diff_race <- function(season = 2026,
                                         schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                         output_gif = "gif_point_diff_race.gif",
                                         output_png = "gif_point_diff_race.png",
                                         sample_step = 3,
                                         fps = 8,
                                         hold_frames = 12,
                                         cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Cumulative Run Differential Race...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
  }

  sch <- readRDS(schedule_file)
  if (nrow(sch) == 0) {
    stop("Schedule dataframe is empty.")
  }

  # Active 30 MLB franchises
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_div_map <- setNames(act_teams$division, act_teams$team_id)
  team_abbr_map <- setNames(act_teams$team_abbreviation, act_teams$team_id)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_id)

  # Filter completed regular season games
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

  long_diff <- bind_rows(
    reg %>% transmute(team_id = home_team_id, date = game_d, diff = as.integer(home_score - away_score)),
    reg %>% transmute(team_id = away_team_id, date = game_d, diff = as.integer(away_score - home_score))
  )

  daily_diff <- long_diff %>%
    group_by(team_id, date) %>%
    summarize(day_diff = sum(diff), .groups = "drop")

  all_dates <- sort(unique(daily_diff$date))
  all_teams <- sort(unique(act_teams$team_id))

  # Complete grid team x date
  grid_td <- expand_grid(team_id = all_teams, date = all_dates)
  cum_grid <- grid_td %>%
    left_join(daily_diff, by = c("team_id", "date")) %>%
    mutate(day_diff = coalesce(day_diff, 0L)) %>%
    arrange(team_id, date) %>%
    group_by(team_id) %>%
    mutate(cum_diff = cumsum(day_diff)) %>%
    ungroup() %>%
    mutate(
      team_abbr = team_abbr_map[as.character(team_id)],
      team_name = team_name_map[as.character(team_id)],
      division  = factor(team_div_map[as.character(team_id)],
                         levels = c("AL East", "AL Central", "AL West",
                                    "NL East", "NL Central", "NL West"))
    )

  min_diff <- min(cum_grid$cum_diff)
  max_diff <- max(cum_grid$cum_diff)
  y_pad <- round((max_diff - min_diff) * 0.08)
  y_limits <- c(min_diff - y_pad, max_diff + y_pad)
  date_limits <- c(min(all_dates), max(all_dates))

  # Sample animation dates
  sampled_indices <- c(seq(1, length(all_dates), by = sample_step), length(all_dates))
  anim_dates <- all_dates[sort(unique(sampled_indices))]

  tmp_dir <- file.path(tempdir(), "mlb_point_diff_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(anim_dates))

  for (idx in seq_along(anim_dates)) {
    cur_d <- anim_dates[idx]
    sub_traj <- cum_grid %>% filter(date <= cur_d)
    cur_pts  <- cum_grid %>% filter(date == cur_d)

    leader <- cur_pts %>% arrange(desc(cum_diff)) %>% slice(1)
    subtitle_txt <- sprintf("Through %s | League Differential Leader: %s (%+d RD)",
                            format(cur_d, "%B %d, %Y"), leader$team_name, leader$cum_diff)

    p <- ggplot(sub_traj, aes(x = date, y = cum_diff, group = team_id, color = division)) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      geom_line(linewidth = 0.85, alpha = 0.85) +
      geom_mlb_logos(
        data = cur_pts,
        aes(x = date, y = cum_diff, team_abbr = team_abbr),
        width = 0.075,
        inherit.aes = FALSE
      ) +
      facet_wrap(~ division, ncol = 3, scales = "fixed") +
      scale_color_manual(values = MLB_DIVISION_COLORS) +
      scale_x_date(
        date_breaks = "2 months",
        date_labels = "%b",
        limits = date_limits
      ) +
      scale_y_continuous(
        limits = y_limits,
        breaks = pretty_breaks(n = 6)
      ) +
      theme_mlb_dark(base_size = 11) +
      theme(
        legend.position = "none",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", size = 11)
      ) +
      labs(
        title = sprintf("%d MLB 30-Team Cumulative Run Differential Race", season),
        subtitle = subtitle_txt,
        x = sprintf("Date (%d Regular Season)", season),
        y = "Cumulative Run Differential (RS - RA)",
        caption = "Source: KayceeSlices MLB Analytics Engine | mlbplotR transparent franchise logos"
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
  message(sprintf(">>> [SUCCESS] Point Diff Race generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_point_diff_race()
}
