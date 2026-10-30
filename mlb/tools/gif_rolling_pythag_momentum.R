# ==============================================================================
# tools/gif_rolling_pythag_momentum.R — 162-Game Rolling 10-Game Expected Pythag Win %
# Path: tools/gif_rolling_pythag_momentum.R
#
# Generates an animated multi-team rolling 10-game Pythagorean expected win %
# momentum curve across the 2026 season, with team logos tracking hot streaks
# and slumps faceted across MLB divisions.
#
# Key Features:
#   - 10-game rolling expected Pythagorean win % using run scoring and runs allowed.
#   - Faceted across the 6 canonical MLB divisions (AL East, AL Central, AL West,
#     NL East, NL Central, NL West) for clear visibility.
#   - Official transparent MLB franchise logos at the leading edge of each
#     team trajectory via mlbplotR::geom_mlb_logos.
#   - Neutral 50% baseline reference line in each panel.
#   - Minimal dark front-office styling via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_rolling_pythag_momentum.gif
#         cache/viz/gif_rolling_pythag_momentum.png
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

#' Compute rolling 10-game Pythagorean win expectation
#'
#' @param rs Vector of runs scored
#' @param ra Vector of runs allowed
#' @param window Integer rolling window size (default 10)
#' @return Numeric vector of rolling pythag win percentages
calc_rolling_pythag <- function(rs, ra, window = 10) {
  n <- length(rs)
  out <- numeric(n)
  for (i in seq_len(n)) {
    start_idx <- max(1, i - window + 1)
    tot_rs <- sum(rs[start_idx:i])
    tot_ra <- sum(ra[start_idx:i])
    if (tot_rs + tot_ra == 0) {
      out[i] <- 0.500
    } else {
      # Standard Pythagorean formula with exponent 1.83
      exp_val <- 1.83
      out[i] <- (tot_rs^exp_val) / ((tot_rs^exp_val) + (tot_ra^exp_val))
    }
  }
  out
}

#' Generate Rolling Pythagorean Momentum GIF
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
generate_gif_rolling_pythag_momentum <- function(season = 2026,
                                                 schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                                 output_gif = "gif_rolling_pythag_momentum.gif",
                                                 output_png = "gif_rolling_pythag_momentum.png",
                                                 sample_step = 3,
                                                 fps = 8,
                                                 hold_frames = 12,
                                                 cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Rolling Pythagorean Momentum Animation...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
  }

  sch <- readRDS(schedule_file)
  if (nrow(sch) == 0) {
    stop("Schedule dataframe is empty.")
  }

  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_div_map <- setNames(act_teams$division, act_teams$team_id)
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
    mutate(game_d = as.Date(official_date)) %>%
    arrange(game_d, game_pk)

  if (nrow(reg) == 0) {
    stop("No completed regular-season games found in schedule.")
  }

  # Build game-level team runs
  long_games <- bind_rows(
    reg %>% transmute(team_id = home_team_id, date = game_d, rs = home_score, ra = away_score, game_pk = game_pk),
    reg %>% transmute(team_id = away_team_id, date = game_d, rs = away_score, ra = home_score, game_pk = game_pk)
  ) %>%
    arrange(team_id, date, game_pk)

  # Calculate team game number and rolling pythag
  team_rolling <- long_games %>%
    group_by(team_id) %>%
    mutate(
      game_num = row_number(),
      rolling_pythag = calc_rolling_pythag(rs, ra, window = 10),
      team_abbr = team_abbr_map[as.character(team_id)],
      division = team_div_map[as.character(team_id)]
    ) %>%
    ungroup()

  all_dates <- sort(unique(team_rolling$date))
  # Sample frames starting around game day 10
  date_indices <- seq(10, length(all_dates), by = sample_step)
  if (date_indices[length(date_indices)] != length(all_dates)) {
    date_indices <- c(date_indices, length(all_dates))
  }
  frame_dates <- all_dates[date_indices]

  divisions <- c("AL East", "AL Central", "AL West", "NL East", "NL Central", "NL West")
  team_rolling$division <- factor(team_rolling$division, levels = divisions)

  tmp_dir <- tempfile(pattern = "mlb_rolling_pythag_")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  frame_files <- character()

  message(sprintf("Rendering %d animation frames...", length(frame_dates)))

  for (i in seq_along(frame_dates)) {
    cur_date <- frame_dates[i]
    cur_data <- team_rolling %>% filter(date <= cur_date)
    
    # Head point for logo placement
    head_data <- cur_data %>%
      group_by(team_id) %>%
      filter(game_num == max(game_num)) %>%
      ungroup()

    # Dynamic top surge
    top_streak <- head_data %>% arrange(desc(rolling_pythag)) %>% slice(1)
    subtitle_txt <- sprintf(
      "Through %s | Top 10-Game Momentum: %s (%.3f Exp Win %%)",
      format(cur_date, "%b %d, %Y"),
      top_streak$team_abbr,
      top_streak$rolling_pythag
    )

    p <- ggplot(cur_data, aes(x = game_num, y = rolling_pythag, group = team_abbr, color = division)) +
      geom_hline(yintercept = 0.500, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      geom_line(alpha = 0.75, linewidth = 0.9) +
      mlbplotR::geom_mlb_logos(
        data = head_data,
        aes(x = game_num, y = rolling_pythag, team_abbr = team_abbr),
        width = 0.16
      ) +
      facet_wrap(~division, ncol = 3) +
      scale_color_manual(values = MLB_DIVISION_COLORS, guide = "none") +
      scale_y_continuous(
        labels = scales::number_format(accuracy = 0.001),
        limits = c(0.15, 0.95),
        breaks = c(0.300, 0.500, 0.700)
      ) +
      scale_x_continuous(
        limits = c(1, 165),
        breaks = c(40, 80, 120, 160)
      ) +
      theme_mlb_dark(base_size = 11) +
      labs(
        title = sprintf("%d MLB Rolling 10-Game Pythagorean Win %% Momentum", season),
        subtitle = subtitle_txt,
        x = "Regular Season Game Number",
        y = "10-Game Rolling Expected Pythagorean Win %",
        caption = "Front-Office Macro Analytics | Exponent: 1.83 | mlbplotR"
      )

    frame_path <- file.path(tmp_dir, sprintf("frame_%04d.png", i))
    ggsave(frame_path, plot = p, width = 11, height = 7, dpi = 110)
    frame_files <- c(frame_files, frame_path)
  }

  # Build final static PNG
  out_png_path <- file.path(ensure_viz_dir(), output_png)
  file.copy(frame_files[length(frame_files)], out_png_path, overwrite = TRUE)

  # Hold final frames
  final_frame <- frame_files[length(frame_files)]
  held_frames <- c(frame_files, rep(final_frame, hold_frames))

  out_gif_path <- file.path(ensure_viz_dir(), output_gif)
  message("Encoding animated GIF via gifski...")
  gifski::gifski(
    png_files = held_frames,
    gif_file = out_gif_path,
    width = 1100,
    height = 700,
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
  generate_gif_rolling_pythag_momentum(season = season)
}
