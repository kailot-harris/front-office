# ==============================================================================
# tools/viz_elo_trajectories.R — 30-Team MLB Elo Rating Trajectories Over Season
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/tools/viz_elo_trajectories.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24)
# Visualizes the daily evolution of Elo ratings across all 30 MLB franchises,
# faceted by division or highlighted by league, marking key rating gainers/decliners.
#
# Input:  cache/ratings/mlb_elo_history.rds
# Output: cache/viz/elo_trajectories_2024.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
})

source("config.R")
source("tools/viz_theme.R")

generate_viz_elo_trajectories <- function(season = 2024,
                                          history_file = cache_path("ratings", "mlb_elo_history.rds"),
                                          output_file  = sprintf("elo_trajectories_%d.png", season)) {

  message(sprintf(">>> [VIZ] Generating Elo trajectories visualization for %d...", season))
  
  if (!file.exists(history_file)) {
    stop(sprintf("Elo history file not found at '%s'. Run mlb_elo_engine.R first.", history_file))
  }
  
  elo_hist <- readRDS(history_file)
  if (nrow(elo_hist) == 0) {
    stop("Elo history dataframe is empty.")
  }
  
  # Fetch team table for canonical division mapping
  teams_meta <- as.data.frame(get_mlb_team_table())
  mlb_teams <- teams_meta[which(teams_meta[["sport_id"]] == 1 & !is.na(teams_meta[["division_name"]])),
                          c("team_id", "team_abbreviation", "division_name")]
  mlb_teams$division <- standardize_division(mlb_teams$division_name)
  
  # Build long team-game trajectory
  elo_hist$date <- as.Date(substr(elo_hist$game_date, 1, 10))
  
  home_traj <- data.frame(
    game_pk   = elo_hist$game_pk,
    date      = elo_hist$date,
    team_id   = elo_hist$home_team_id,
    team_name = elo_hist$home_team_name,
    post_elo  = elo_hist$post_home_elo,
    stringsAsFactors = FALSE
  )
  
  away_traj <- data.frame(
    game_pk   = elo_hist$game_pk,
    date      = elo_hist$date,
    team_id   = elo_hist$away_team_id,
    team_name = elo_hist$away_team_name,
    post_elo  = elo_hist$post_away_elo,
    stringsAsFactors = FALSE
  )
  
  traj <- rbind(home_traj, away_traj)
  traj <- traj[order(traj$team_id, traj$date, traj$game_pk), ]
  
  # Add initial baseline rating (1500 on Opening Day minus 1 day)
  min_date <- min(traj$date) - 1
  team_inits <- do.call(rbind, lapply(unique(traj$team_id), function(tid) {
    t_name <- traj$team_name[traj$team_id == tid][1]
    data.frame(
      game_pk   = 0,
      date      = min_date,
      team_id   = tid,
      team_name = t_name,
      post_elo  = 1500.0,
      stringsAsFactors = FALSE
    )
  }))
  
  full_traj <- rbind(team_inits, traj)
  full_traj <- full_traj[order(full_traj$team_id, full_traj$date), ]
  
  # Join division metadata
  full_traj <- merge(full_traj, mlb_teams[, c("team_id", "team_abbreviation", "division")],
                     by = "team_id", all.x = TRUE)
  full_traj$division[is.na(full_traj$division)] <- "Other"
  
  # Compute start/end elo to find top gainers and decliners
  team_endpoints <- full_traj %>%
    group_by(team_id, team_name, team_abbreviation, division) %>%
    summarise(
      start_elo = first(post_elo),
      final_elo = last(post_elo),
      max_date  = max(date),
      elo_gain  = last(post_elo) - first(post_elo),
      .groups   = "drop"
    ) %>%
    arrange(desc(final_elo))
  
  top_team <- team_endpoints[which.max(team_endpoints$final_elo), ]
  bottom_team <- team_endpoints[which.min(team_endpoints$final_elo), ]
  top_gainer <- team_endpoints[which.max(team_endpoints$elo_gain), ]
  top_decliner <- team_endpoints[which.min(team_endpoints$elo_gain), ]
  
  # Division factor order
  div_order <- c("AL East", "AL Central", "AL West", "NL East", "NL Central", "NL West")
  full_traj$division <- factor(full_traj$division, levels = div_order)
  team_endpoints$division <- factor(team_endpoints$division, levels = div_order)
  
  # Plot construction: Faceted by division for maximum clarity across 30 teams
  p <- ggplot(full_traj, aes(x = date, y = post_elo, group = team_name, color = division)) +
    # Reference baseline line at 1500
    geom_hline(yintercept = 1500, linetype = "dashed", color = "#484F58", linewidth = 0.5) +
    
    # Rating trajectories
    geom_line(linewidth = 0.85, alpha = 0.85) +
    
    # End of season team points
    geom_point(
      data = team_endpoints,
      aes(x = max_date, y = final_elo, color = division),
      size = 2.2, shape = 16
    ) +
    
    # End of season team abbreviations
    geom_text(
      data = team_endpoints,
      aes(x = max_date + 2, y = final_elo, label = sprintf("%s (%.0f)", team_abbreviation, final_elo)),
      size = 2.7, hjust = 0, fontface = "bold", color = "#E6EDF3",
      check_overlap = TRUE
    ) +
    
    # Facet by Division
    facet_wrap(~ division, ncol = 3, scales = "fixed") +
    
    # Scales & Aesthetics
    scale_color_manual(values = MLB_DIVISION_COLORS) +
    scale_x_date(
      date_breaks = "2 months",
      date_labels = "%b",
      expand = expansion(mult = c(0.02, 0.18))
    ) +
    scale_y_continuous(
      breaks = seq(1400, 1600, 40),
      limits = c(min(1420, min(full_traj$post_elo) - 10), max(1580, max(full_traj$post_elo) + 10))
    ) +
    
    # Theming
    theme_mlb_dark(base_size = 11) +
    theme(
      legend.position = "none",
      panel.grid.minor = element_blank()
    ) +
    
    # Titles & Annotations
    labs(
      title = sprintf("%d MLB 30-Team Elo Rating Trajectories", season),
      subtitle = sprintf(
        "Evolution of game-by-game Elo ratings adjusted for starting pitcher quality and rest\nLeader: %s (%.1f) | Biggest Gainer: %s (+%.1f) | Biggest Drop: %s (%.1f)",
        top_team$team_name, top_team$final_elo,
        top_gainer$team_name, top_gainer$elo_gain,
        top_decliner$team_name, top_decliner$elo_gain
      ),
      x = sprintf("Date (%d Regular Season)", season),
      y = "Elo Rating (1500 = League Average Baseline)",
      caption = "Source: MLB Stats API & KayceeSlices MLB Analytics Engine | Tangotiger rGS & Rest Adjusted"
    )
  
  # Save PNG
  saved_path <- save_mlb_plot(p, output_file, width = 12, height = 7.5, dpi = 300)
  return(invisible(saved_path))
}

if (sys.nframe() == 0) {
  generate_viz_elo_trajectories()
}
