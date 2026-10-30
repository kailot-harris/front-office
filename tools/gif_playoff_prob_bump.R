# ==============================================================================
# tools/gif_playoff_prob_bump.R — MLB Postseason Probability Bump / Progression
# Path: tools/gif_playoff_prob_bump.R
#
# Generates an animated multi-line bump and progression race illustrating
# postseason qualification probability across the 2026 season for AL and NL.
#
# Key Features:
#   - Faceted across American League and National League (or top contending teams).
#   - Dynamic rank & probability trajectory calculated across chronological milestone
#     dates combining completed regular season wins and adjusted Elo trajectory.
#   - Leading points decorated with official transparent MLB team logos via
#     mlbplotR::geom_mlb_logos.
#   - Cutoff reference line indicating postseason clinch threshold (top 6 seeds).
#   - Dark front-office theme via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
#         cache/ratings/mlb_elo_history.rds
#         cache/postseason/postseason_team_probabilities.rds
# Output: cache/viz/gif_playoff_prob_bump.gif
#         cache/viz/gif_playoff_prob_bump.png
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

#' Generate Postseason Probability Progression Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param elo_file Path to mlb_elo_history.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param n_frames Number of chronological milestone frames (default 16)
#' @param fps Frames per second for GIF playback (default 5)
#' @param hold_frames Number of frames to hold the final standings (default 10)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_playoff_prob_bump <- function(season = 2026,
                                           schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                           elo_file = cache_path("ratings", "mlb_elo_history.rds"),
                                           output_gif = "gif_playoff_prob_bump.gif",
                                           output_png = "gif_playoff_prob_bump.png",
                                           n_frames = 16,
                                           fps = 5,
                                           hold_frames = 10,
                                           cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Postseason Probability Progression Race...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
  }

  sch <- readRDS(schedule_file)
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  act_teams$league <- ifelse(grepl("^AL", act_teams$division), "American League", "National League")

  reg <- sch %>%
    filter(
      game_type == "R",
      !is.na(home_score),
      !is.na(away_score),
      home_team_id %in% act_teams$team_id,
      away_team_id %in% act_teams$team_id
    ) %>%
    mutate(game_d = as.Date(official_date))

  all_dates <- sort(unique(reg$game_d))
  milestone_dates <- all_dates[round(seq(10, length(all_dates), length.out = n_frames))]

  # Elo ratings lookup if available
  elo_df <- if (file.exists(elo_file)) readRDS(elo_file) else data.frame()
  if (nrow(elo_df) > 0) {
    elo_df$date <- as.Date(substr(elo_df$game_date, 1, 10))
  }

  prog_list <- list()

  for (f_idx in seq_along(milestone_dates)) {
    cur_d <- milestone_dates[f_idx]
    sub_reg <- reg %>% filter(game_d <= cur_d)
    sub_elo <- if (nrow(elo_df) > 0) elo_df %>% filter(date <= cur_d) else data.frame()

    team_stats <- act_teams %>%
      rowwise() %>%
      mutate(
        wins = sum(sub_reg$home_team_id == team_id & sub_reg$home_score > sub_reg$away_score) +
               sum(sub_reg$away_team_id == team_id & sub_reg$away_score > sub_reg$home_score),
        games = sum(sub_reg$home_team_id == team_id | sub_reg$away_team_id == team_id),
        latest_elo = {
          if (nrow(sub_elo) > 0) {
            te <- sub_elo %>% filter(home_team_id == team_id | away_team_id == team_id)
            if (nrow(te) > 0) {
              lr <- tail(te, 1)
              if (lr$home_team_id == team_id) lr$post_home_elo else lr$post_away_elo
            } else 1500
          } else 1500
        }
      ) %>%
      ungroup()

    # Projected wins = current wins + remaining * (win prob from elo)
    team_stats <- team_stats %>%
      mutate(
        rem = pmax(162 - games, 0),
        elo_prob = 1 / (1 + 10^((1500 - latest_elo) / 400)),
        proj_wins = wins + rem * elo_prob
      ) %>%
      group_by(league) %>%
      arrange(desc(proj_wins), desc(wins), desc(latest_elo), .by_group = TRUE) %>%
      mutate(
        league_rank = row_number(),
        threshold_wins = proj_wins[7],
        prob_playoff = round(100 / (1 + exp((threshold_wins - proj_wins) * 0.70)), 1),
        prob_playoff = case_when(
          league_rank <= 4 ~ pmax(prob_playoff, 80.0),
          league_rank <= 6 ~ pmax(prob_playoff, 55.0),
          league_rank >= 12 ~ pmin(prob_playoff, 5.0),
          TRUE ~ prob_playoff
        ),
        step_idx = f_idx,
        date = cur_d
      ) %>%
      ungroup()

    prog_list[[f_idx]] <- team_stats
  }

  bump_df <- bind_rows(prog_list)

  tmp_dir <- file.path(tempdir(), "mlb_playoff_prob_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(milestone_dates))

  for (idx in seq_along(milestone_dates)) {
    cur_d <- milestone_dates[idx]
    sub_data <- bump_df %>% filter(date <= cur_d)
    cur_pts  <- bump_df %>% filter(date == cur_d)

    top_al <- cur_pts %>% filter(league == "American League") %>% arrange(desc(prob_playoff)) %>% slice(1)
    top_nl <- cur_pts %>% filter(league == "National League") %>% arrange(desc(prob_playoff)) %>% slice(1)

    subtitle_txt <- sprintf("Through %s | Clinch Leaders: AL %s (%.0f%%) \u00b7 NL %s (%.0f%%)",
                            format(cur_d, "%B %d, %Y"), top_al$team_abbreviation, top_al$prob_playoff,
                            top_nl$team_abbreviation, top_nl$prob_playoff)

    p <- ggplot(sub_data, aes(x = date, y = prob_playoff, group = team_id, color = division)) +
      # 50% leverage bubble line and 90% lock line
      geom_hline(yintercept = 50, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      geom_hline(yintercept = 90, linetype = "dotted", color = "#30363D", linewidth = 0.5) +
      geom_line(linewidth = 0.85, alpha = 0.85) +
      geom_mlb_logos(
        data = cur_pts,
        aes(x = date, y = prob_playoff, team_abbr = team_abbreviation),
        width = 0.065,
        inherit.aes = FALSE
      ) +
      facet_wrap(~ league, ncol = 2) +
      scale_color_manual(values = MLB_DIVISION_COLORS) +
      scale_x_date(
        date_breaks = "2 months",
        date_labels = "%b",
        limits = c(min(milestone_dates), max(milestone_dates))
      ) +
      scale_y_continuous(
        limits = c(-2, 105),
        breaks = seq(0, 100, by = 25),
        labels = function(x) paste0(x, "%")
      ) +
      theme_mlb_dark(base_size = 11) +
      theme(
        legend.position = "none",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", size = 11)
      ) +
      labs(
        title = sprintf("%d MLB Postseason Probability Progression Race", season),
        subtitle = subtitle_txt,
        x = sprintf("Date (%d Regular Season)", season),
        y = "Simulated Postseason Probability (%)",
        caption = "Top 6 seeds per league qualify | Source: KayceeSlices MLB Analytics Engine"
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
  message(sprintf(">>> [SUCCESS] Playoff Prob Progression generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_playoff_prob_bump()
}
