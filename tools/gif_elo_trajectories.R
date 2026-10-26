# ==============================================================================
# tools/gif_elo_trajectories.R — 30-Team MLB Elo Race Trajectory Animation
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/gif_elo_trajectories.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24 / Animated Trajectories)
# Converts game-by-game Elo rating trajectories into an animated race GIF across
# all 30 MLB franchises, faceted across the 6 MLB divisions.
#
# Key Features:
#   - Uses official transparent MLB team logos at the leading point of each
#     trajectory curve via mlbplotR::geom_mlb_logos (no text names/abbreviations).
#   - Synchronized division small-multiples with static, uniform coordinate limits.
#   - Chronological calendar progression revealing cumulative team movements.
#   - Dynamic subtitle reflecting date, current league Elo leader, and top gainer.
#   - Final frame hold (1.5s) for smooth visual pacing before looping.
#   - Encoded with high-performance Rust-based gifski engine.
#
# Input:  cache/ratings/mlb_elo_history.rds
# Output: cache/viz/elo_trajectories_2026.gif
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
  library(mlbplotR)
  library(gifski)
})

source("config.R")
source("tools/viz_theme.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_elo_trajectories.R"

#' Generate Animated Elo Trajectory Race GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param history_file Path to mlb_elo_history.rds
#' @param output_file Output filename for the animated GIF
#' @param fps Frames per second for animation playback (default 10)
#' @param sample_interval_days Days between animation frames (default 3)
#' @param hold_frames Number of frames to hold final standings (default 15)
#' @param cleanup_frames Logical; delete intermediate PNG frames after encoding (default TRUE)
#' @return Invisible file path to the generated GIF
generate_gif_elo_trajectories <- function(season = 2026,
                                          history_file = cache_path("ratings", "mlb_elo_history.rds"),
                                          output_file  = sprintf("elo_trajectories_%d.gif", season),
                                          fps = 10,
                                          sample_interval_days = 3,
                                          hold_frames = 15,
                                          cleanup_frames = TRUE) {
  
  start_time <- Sys.time()
  ensure_viz_dir()
  
  log_info(sprintf("Generating %d MLB Elo Trajectories GIF...", season), script = .LOG_SCRIPT)
  
  if (!file.exists(history_file)) {
    stop(sprintf("Elo history file not found at '%s'. Run mlb_elo_engine.R first.", history_file))
  }
  
  elo_hist <- readRDS(history_file)
  if (nrow(elo_hist) == 0) {
    stop("Elo history dataframe is empty.")
  }
  
  # Fetch team table for canonical division mapping
  teams_meta <- as.data.frame(get_mlb_team_table())
  act <- teams_meta[which(teams_meta[["sport_id"]] == 1 & !is.na(teams_meta[["division_name"]])), ]
  act_teams <- data.frame(
    team_id           = as.integer(unlist(act[["team_id"]])),
    team_full_name    = as.character(unlist(act[["team_full_name"]])),
    team_abbreviation = as.character(unlist(act[["team_abbreviation"]])),
    division_name     = as.character(unlist(act[["division_name"]])),
    stringsAsFactors  = FALSE
  )
  act_teams$division <- standardize_division(act_teams$division_name)
  
  # Standardize date
  elo_hist$date <- as.Date(substr(elo_hist[["game_date"]], 1, 10))
  
  # Build long team-game trajectory
  home_traj <- data.frame(
    date     = elo_hist$date,
    team_id  = elo_hist$home_team_id,
    post_elo = elo_hist$post_home_elo,
    stringsAsFactors = FALSE
  )
  away_traj <- data.frame(
    date     = elo_hist$date,
    team_id  = elo_hist$away_team_id,
    post_elo = elo_hist$post_away_elo,
    stringsAsFactors = FALSE
  )
  traj <- rbind(home_traj, away_traj)
  traj <- traj[order(traj$team_id, traj$date), ]
  
  # Add baseline rating (1500 on Opening Day minus 1 day)
  min_date <- min(traj$date) - 1
  team_inits <- do.call(rbind, lapply(unique(traj$team_id), function(tid) {
    data.frame(
      date     = min_date,
      team_id  = tid,
      post_elo = 1500.0,
      stringsAsFactors = FALSE
    )
  }))
  
  full_traj <- rbind(team_inits, traj)
  full_traj <- merge(
    full_traj,
    act_teams[, c("team_id", "team_abbreviation", "team_full_name", "division")],
    by = "team_id",
    all.x = TRUE
  )
  
  div_order <- c("AL East", "AL Central", "AL West", "NL East", "NL Central", "NL West")
  full_traj$division <- factor(full_traj$division, levels = div_order)
  
  # Frame dates: sample every `sample_interval_days` + ensure last date is present
  all_dates <- sort(unique(full_traj$date))
  frame_dates <- all_dates[seq(1, length(all_dates), by = sample_interval_days)]
  if (tail(frame_dates, 1) != tail(all_dates, 1)) {
    frame_dates <- c(frame_dates, tail(all_dates, 1))
  }
  
  # Coordinate limits fixed across all frames
  y_min <- floor((min(full_traj$post_elo, na.rm = TRUE) - 15) / 10) * 10
  y_max <- ceiling((max(full_traj$post_elo, na.rm = TRUE) + 15) / 10) * 10
  date_limits <- c(min(all_dates), max(all_dates) + 5)
  
  # Temporary frames folder
  frame_dir <- file.path(PROJECT_DIR %||% MLB_ROOT_DIR, "cache", "viz", sprintf("frames_elo_%d", season))
  if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
  unlink(file.path(frame_dir, "*.png"))
  
  frame_files <- character(length(frame_dates))
  log_info(sprintf("Rendering %d frames for %d Elo race animation...", length(frame_dates), season), script = .LOG_SCRIPT)
  
  for (idx in seq_along(frame_dates)) {
    d <- frame_dates[idx]
    sub_traj <- full_traj[full_traj$date <= d, ]
    
    # Extract latest rating per team up to date d
    cur_pts <- sub_traj %>%
      group_by(team_id) %>%
      slice_tail(n = 1) %>%
      ungroup()
    
    # Calculate live leader and top gainer for dynamic subtitle
    cur_sorted <- cur_pts[order(-cur_pts$post_elo), ]
    top_team <- cur_sorted[1, ]
    cur_pts$gain <- cur_pts$post_elo - 1500
    top_gainer <- cur_pts[which.max(cur_pts$gain), ]
    
    subtitle_txt <- sprintf(
      "Through %s | Leader: %s (%.1f) | Top Riser: %s (%+.1f)",
      format(d, "%B %d, %Y"),
      top_team$team_full_name, top_team$post_elo,
      top_gainer$team_full_name, top_gainer$gain
    )
    
    p <- ggplot(sub_traj, aes(x = date, y = post_elo, group = team_id, color = division)) +
      # Baseline 1500 reference
      geom_hline(yintercept = 1500, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
      
      # Trajectory lines
      geom_line(linewidth = 0.85, alpha = 0.85) +
      
      # Official franchise logos at line front (no text names)
      geom_mlb_logos(
        data = cur_pts,
        aes(x = date, y = post_elo, team_abbr = team_abbreviation),
        width = 0.075,
        inherit.aes = FALSE
      ) +
      
      # Division facets
      facet_wrap(~ division, ncol = 3, scales = "fixed") +
      
      # Scales & formatting
      scale_color_manual(values = MLB_DIVISION_COLORS) +
      scale_x_date(
        date_breaks = "2 months",
        date_labels = "%b",
        limits = date_limits
      ) +
      scale_y_continuous(
        breaks = seq(y_min, y_max, 40),
        limits = c(y_min, y_max)
      ) +
      
      # Theming
      theme_mlb_dark(base_size = 11) +
      theme(
        legend.position = "none",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold", size = 11)
      ) +
      
      # Headers
      labs(
        title = sprintf("%d MLB 30-Team Elo Rating Race Trajectories", season),
        subtitle = subtitle_txt,
        x = sprintf("Date (%d Regular Season)", season),
        y = "Elo Rating (1500 = League Baseline)",
        caption = "Source: KayceeSlices MLB Analytics Engine | Tangotiger rGS & Rest Adjusted"
      )
    
    fpath <- file.path(frame_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 11.5, height = 7.2, dpi = 110, bg = "#161B22")
    frame_files[idx] <- fpath
  }
  
  # Hold on final standings
  final_frame_files <- c(frame_files, rep(tail(frame_files, 1), hold_frames))
  
  target_gif_path <- file.path(PROJECT_DIR %||% MLB_ROOT_DIR, "cache", "viz", output_file)
  
  log_info("Encoding frames to animated GIF via gifski...", script = .LOG_SCRIPT)
  gifski::gifski(
    png_files = final_frame_files,
    gif_file  = target_gif_path,
    width     = 1150,
    height    = 720,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )
  
  if (cleanup_frames) {
    unlink(frame_dir, recursive = TRUE)
  }
  
  f_size <- file.info(target_gif_path)[["size"]]
  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  
  log_info(
    sprintf("Generated Elo trajectory GIF: %s (%.1f KB, %.1fs)",
            basename(target_gif_path), f_size / 1024, elapsed),
    script = .LOG_SCRIPT
  )
  
  invisible(target_gif_path)
}

if (sys.nframe() == 0) {
  generate_gif_elo_trajectories()
}
