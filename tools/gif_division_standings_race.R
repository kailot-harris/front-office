# ==============================================================================
# tools/gif_division_standings_race.R — 6-Division Cumulative Win Race Animation
# Path: tools/gif_division_standings_race.R
#
# Generates a 6-division faceted horizontal bar race animating cumulative wins
# across all 30 MLB franchises through the 2026 regular season.
#
# Key Features:
#   - Faceted across the 6 canonical MLB divisions (AL East, AL Central, AL West,
#     NL East, NL Central, NL West) using MLB_DIVISION_COLORS.
#   - Teams dynamically reorder inside each division panel by cumulative wins.
#   - Official transparent MLB franchise logos positioned at the bar heads via
#     mlbplotR::geom_mlb_logos.
#   - Full dark front-office theme via theme_mlb_dark().
#   - Encoded with high-performance gifski engine with final frame hold.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Input:  cache/ingest/mlb_schedule_2026.rds
# Output: cache/viz/gif_division_standings_race.gif
#         cache/viz/gif_division_standings_race.png
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

#' Generate 6-Division Standings Win Race GIF
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
generate_gif_division_standings_race <- function(season = 2026,
                                                 schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                                 output_gif = "gif_division_standings_race.gif",
                                                 output_png = "gif_division_standings_race.png",
                                                 sample_step = 3,
                                                 fps = 8,
                                                 hold_frames = 12,
                                                 cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d 6-Division Standings Win Race...", season))

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

  # Build game-level results
  long_results <- bind_rows(
    reg %>% transmute(team_id = home_team_id, date = game_d, win = as.integer(home_score > away_score)),
    reg %>% transmute(team_id = away_team_id, date = game_d, win = as.integer(away_score > home_score))
  )

  # Aggregate wins by team and date
  daily_wins <- long_results %>%
    group_by(team_id, date) %>%
    summarize(daily_w = sum(win), .groups = "drop")

  all_dates <- sort(unique(daily_wins$date))
  all_teams <- sort(unique(act_teams$team_id))

  # Complete team x date grid
  grid_td <- expand_grid(team_id = all_teams, date = all_dates)
  cum_grid <- grid_td %>%
    left_join(daily_wins, by = c("team_id", "date")) %>%
    mutate(daily_w = coalesce(daily_w, 0L)) %>%
    arrange(team_id, date) %>%
    group_by(team_id) %>%
    mutate(cum_wins = cumsum(daily_w)) %>%
    ungroup() %>%
    mutate(
      team_abbr = team_abbr_map[as.character(team_id)],
      team_name = team_name_map[as.character(team_id)],
      division  = factor(team_div_map[as.character(team_id)],
                         levels = c("AL East", "AL Central", "AL West",
                                    "NL East", "NL Central", "NL West"))
    )

  max_wins_season <- max(cum_grid$cum_wins)

  # Sample dates for animation pacing
  sampled_indices <- c(seq(1, length(all_dates), by = sample_step), length(all_dates))
  anim_dates <- all_dates[sort(unique(sampled_indices))]

  tmp_dir <- file.path(tempdir(), "mlb_division_standings_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(anim_dates))

  for (idx in seq_along(anim_dates)) {
    cur_d <- anim_dates[idx]
    frame_df <- cum_grid %>%
      filter(date == cur_d) %>%
      group_by(division) %>%
      arrange(cum_wins, desc(team_abbr), .by_group = TRUE) %>%
      mutate(rank_order = row_number()) %>%
      ungroup()

    leader <- frame_df %>% filter(cum_wins == max(cum_wins)) %>% slice(1)
    subtitle_txt <- sprintf("Through %s | MLB Win Leader: %s (%d W)",
                            format(cur_d, "%B %d, %Y"), leader$team_name, leader$cum_wins)

    p <- ggplot(frame_df, aes(x = cum_wins, y = rank_order, fill = division)) +
      geom_col(width = 0.68, show.legend = FALSE, alpha = 0.90) +
      geom_mlb_logos(
        aes(x = cum_wins + (max_wins_season * 0.055), y = rank_order, team_abbr = team_abbr),
        width = 0.09,
        inherit.aes = FALSE
      ) +
      geom_text(
        aes(x = pmax(cum_wins - 3.5, 1.5), label = sprintf("%d", cum_wins)),
        color = "#FFFFFF",
        fontface = "bold",
        size = 3.2,
        hjust = 1
      ) +
      facet_wrap(~ division, ncol = 3, scales = "free_y") +
      scale_fill_manual(values = MLB_DIVISION_COLORS) +
      scale_x_continuous(
        limits = c(0, max_wins_season + 14),
        breaks = seq(0, 120, by = 20)
      ) +
      scale_y_continuous(breaks = NULL) +
      theme_mlb_dark(base_size = 11) +
      theme(
        axis.title.y = element_blank(),
        axis.text.y  = element_blank(),
        axis.ticks.y = element_blank(),
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        strip.text = element_text(face = "bold", size = 11)
      ) +
      labs(
        title = sprintf("%d MLB 6-Division Standings Win Race", season),
        subtitle = subtitle_txt,
        x = "Cumulative Regular Season Wins",
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
  message(sprintf(">>> [SUCCESS] Division Standings Race generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_division_standings_race()
}
