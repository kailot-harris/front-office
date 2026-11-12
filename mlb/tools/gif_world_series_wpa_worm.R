# ==============================================================================
# tools/gif_world_series_wpa_worm.R — World Series win probability chart
# Path: tools/gif_world_series_wpa_worm.R
#
# Animates the win probability of every completed World Series game, one plate
# appearance at a time.
#
# Data (real, no fallback):
#   - web/public/data/world_series.json   completed games and final scores
#   - MLB Stats API win probability feed  per plate appearance: MLB's own win
#     probability, the score, and MLB's description of the play
#     (via tools/postseason_feed.R, cached in cache/postseason/)
# Nothing on the chart is typed in by hand. If a game's feed is unavailable the
# script stops and renders nothing.
#
# Output: cache/viz/gif_world_series_wpa_worm.gif
#         cache/viz/gif_world_series_wpa_worm.png
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
source("tools/postseason_feed.R")

#' Generate World Series Win Probability GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param frame_every Draw one frame per this many plate appearances (default 4)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_world_series_wpa_worm <- function(season = 2026,
                                               output_gif = "gif_world_series_wpa_worm.gif",
                                               output_png = "gif_world_series_wpa_worm.png",
                                               fps = 6,
                                               hold_frames = 12,
                                               frame_every = 4,
                                               cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d World Series Win Probability Animation...", season))

  ws <- ps_world_series()
  team_a <- ws$home_field$team
  team_b <- ws$challenger$team
  name_a <- ws$home_field$team_name

  worm_data <- bind_rows(lapply(ws$completed, function(g) {
    a_home <- identical(g$home_team, team_a)
    a_final <- if (a_home) g$home_score else g$away_score
    b_final <- if (a_home) g$away_score else g$home_score
    ps_fetch_wp(g$game_pk) %>%
      arrange(ab) %>%
      group_by(inning) %>%
      mutate(x = inning - 1 + row_number() / n()) %>%
      ungroup() %>%
      mutate(a_score = if (a_home) home_score else away_score,
             b_score = if (a_home) away_score else home_score) %>%
      transmute(
        game_num      = g$game_number,
        game_label    = sprintf("Game %d (%s %d, %s %d)", g$game_number, team_a, a_final, team_b, b_final),
        inning_desc   = sprintf("%s %d", ifelse(top, "Top", "Bot"), inning),
        inning        = x,
        home_win_prob = if (a_home) home_wp else 1 - home_wp,
        home_score    = a_score,
        away_score    = b_score,
        event_call    = vapply(desc, function(d) paste(utils::head(strwrap(d, 78), 2), collapse = "\n"), character(1))
      )
  })) %>%
    mutate(step = row_number())

  # One frame every few plate appearances, always including each game's last.
  frame_rows <- worm_data %>%
    group_by(game_num) %>%
    filter(row_number() %% frame_every == 0 | row_number() == n()) %>%
    pull(step)
  max_inning <- max(9, ceiling(max(worm_data$inning)))
  ordinal <- function(n) paste0(n, ifelse(n %% 100 %in% 11:13, "th", c("th", "st", "nd", "rd", rep("th", 6))[n %% 10 + 1]))

  tmp_dir <- file.path(tempdir(), "mlb_ws_worm_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(frame_rows))

  for (k in seq_along(frame_rows)) {
    cur_row <- worm_data[frame_rows[k], ]
    cur_game <- cur_row$game_num

    plot_sub <- worm_data %>% filter(game_num == cur_game & step <= cur_row$step)

    leader_team <- if (cur_row$home_win_prob >= 0.5) team_a else team_b
    leader_pct <- if (cur_row$home_win_prob >= 0.5) cur_row$home_win_prob * 100 else (1 - cur_row$home_win_prob) * 100

    p <- ggplot(plot_sub, aes(x = inning, y = home_win_prob)) +
      geom_hline(yintercept = 0.50, color = "#64748B", linetype = "dashed", linewidth = 0.8) +
      annotate("rect", xmin = -0.5, xmax = max_inning + 0.5, ymin = 0.5, ymax = 1.05, fill = "#13294B", alpha = 0.15) +
      annotate("rect", xmin = -0.5, xmax = max_inning + 0.5, ymin = -0.05, ymax = 0.5, fill = "#092C5C", alpha = 0.15) +
      annotate("text", x = 0.1, y = 1.02, label = sprintf("%s FAVORED", team_a), color = "#FBBF24", fontface = "bold", size = 3.6, hjust = 0) +
      annotate("text", x = 0.1, y = -0.02, label = sprintf("%s FAVORED", team_b), color = "#38BDF8", fontface = "bold", size = 3.6, hjust = 0) +
      geom_line(color = "#FACC15", linewidth = 1.4) +
      geom_mlb_logos(
        data = cur_row,
        aes(x = inning, y = home_win_prob, team_abbr = leader_team),
        width = 0.07,
        inherit.aes = FALSE
      ) +
      labs(
        title = sprintf("%d World Series: Win Probability, Play by Play", season),
        subtitle = sprintf("%s. %s: %s %d, %s %d. %s win probability %.0f%%.",
                           cur_row$game_label, cur_row$inning_desc,
                           team_a, cur_row$home_score, team_b, cur_row$away_score,
                           leader_team, leader_pct),
        x = "Inning",
        y = sprintf("%s win probability", name_a),
        caption = paste0(cur_row$event_call, "\n\nSource: MLB Stats API win probability and play descriptions, per plate appearance.")
      ) +
      scale_x_continuous(
        limits = c(-0.5, max_inning + 0.5),
        breaks = seq(0, max_inning, by = 1),
        labels = c("Start", vapply(seq_len(max_inning), ordinal, character(1)))
      ) +
      scale_y_continuous(
        limits = c(-0.05, 1.05),
        breaks = seq(0, 1, by = 0.25),
        labels = percent_format()
      ) +
      theme_mlb_dark(base_size = 11) +
      theme(
        panel.grid.minor = element_blank(),
        axis.title.x = element_text(face = "bold", margin = margin(t = 8)),
        axis.title.y = element_text(face = "bold", margin = margin(r = 8)),
        plot.caption = element_text(hjust = 0, size = 9.5, lineheight = 1.1)
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", k))
    ggsave(fpath, p, width = 11.5, height = 7.0, dpi = 110, bg = "#0B0F17")
    frame_files[k] <- fpath
  }

  target_gif <- cache_path("viz", output_gif)
  target_png <- cache_path("viz", output_png)

  file.copy(tail(frame_files, 1), target_png, overwrite = TRUE)

  final_frames <- c(frame_files, rep(tail(frame_files, 1), hold_frames))

  gifski::gifski(
    png_files = final_frames,
    gif_file  = target_gif,
    width     = 1150,
    height    = 700,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  message(sprintf(">>> [SUCCESS] World Series win probability chart generated (%d games, %d frames):\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  length(ws$completed), length(frame_rows),
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_world_series_wpa_worm()
}
