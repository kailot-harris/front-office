# ==============================================================================
# tools/viz_bullpen_fatigue.R — Reliever High-Stress Workload & Bullpen Vulnerability
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/viz_bullpen_fatigue.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24)
# Visualizes reliever arm stress and bullpen vulnerability scores across all 30 teams:
#   - X-axis: High-stress reliever count (or season high-stress appearances)
#   - Y-axis: Bullpen Vulnerability Score (composite workload index)
#   - Color:  Workload grade (Well Rested, Elevated Workload, High Vulnerability)
#   - Facets/Annotations: Team labels and high-risk threshold zones
#
# Inputs:  cache/specialty/bullpen_team_status.rds
#          cache/specialty/bullpen_fatigue_daily.rds (optional supplement)
# Output:  cache/viz/bullpen_fatigue_status.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
})

source("config.R")
source("tools/viz_theme.R")
source("tools/mlb_logo_utils.R")

generate_viz_bullpen_fatigue <- function(status_file = cache_path("specialty", "bullpen_team_status.rds"),
                                         daily_file  = cache_path("specialty", "bullpen_fatigue_daily.rds"),
                                         output_file = "bullpen_fatigue_status.png") {
  message(">>> [VIZ] Generating Bullpen Fatigue & Arm-Stress status visualization...")
  
  if (!file.exists(status_file)) {
    stop(sprintf("Bullpen status file not found at '%s'. Run mlb_bullpen_fatigue.R first.", status_file))
  }
  
  status_df <- readRDS(status_file)
  if (nrow(status_df) == 0) {
    stop("Bullpen team status dataframe is empty.")
  }
  
  # Fetch team table for abbreviations, team_id, and division info
  teams_meta <- as.data.frame(get_mlb_team_table())
  mlb_teams <- teams_meta[which(teams_meta[["sport_id"]] == 1 & !is.na(teams_meta[["division_name"]])),
                          c("team_id", "team_full_name", "team_abbreviation", "division_name")]
  names(mlb_teams)[2] <- "team"
  mlb_teams$division <- standardize_division(mlb_teams$division_name)
  
  df <- merge(status_df, mlb_teams, by = "team", all.x = TRUE)
  df$team_abbreviation[is.na(df$team_abbreviation)] <- substr(df$team[is.na(df$team_abbreviation)], 1, 3)
  
  # If daily log exists, extract cumulative season high-stress appearances
  if (file.exists(daily_file)) {
    daily_df <- readRDS(daily_file)
    if (nrow(daily_df) > 0 && "fatigue_status" %in% names(daily_df)) {
      stress_apps <- daily_df[daily_df$fatigue_status %in% c("Fatigued", "Exhausted"), ]
      stress_counts <- as.data.frame(table(stress_apps$team), stringsAsFactors = FALSE)
      names(stress_counts) <- c("team", "season_high_stress_apps")
      df <- merge(df, stress_counts, by = "team", all.x = TRUE)
      df$season_high_stress_apps[is.na(df$season_high_stress_apps)] <- 0
    }
  }
  
  # Ensure we have a high-stress metric for x-axis
  # If season_high_stress_apps exists, use it as primary x-axis, else use relievers_fatigued
  has_season_apps <- "season_high_stress_apps" %in% names(df) && any(df$season_high_stress_apps > 0)
  
  if (has_season_apps) {
    df$x_metric <- df$season_high_stress_apps
    x_label <- "Season High-Stress Reliever Appearances (Fatigued / Exhausted Outings)"
  } else {
    df$x_metric <- df$relievers_fatigued
    x_label <- "Active Relievers Under High Stress (Fatigued / Exhausted)"
  }
  
  # Workload grade palette mapping
  grade_levels <- c("Well Rested", "Moderate Workload", "Elevated Workload", "High Vulnerability")
  df$vulnerability_grade <- factor(df$vulnerability_grade, levels = grade_levels)
  
  # Jitter slightly if many points share same coordinates
  set.seed(42)
  df$x_jitter <- jitter(df$x_metric, amount = if (has_season_apps) 0.3 else 0.08)
  df$y_jitter <- jitter(df$bullpen_vulnerability, amount = 0.5)
  
  p <- ggplot(df, aes(x = x_jitter, y = y_jitter)) +
    # Critical threshold zones
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 80, ymax = Inf,
             fill = "#E06C75", alpha = 0.07) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 40, ymax = 80,
             fill = "#D19A66", alpha = 0.07) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = 40,
             fill = "#7EE787", alpha = 0.07) +
             
    # Threshold divider lines
    geom_hline(yintercept = 80, linetype = "dashed", color = "#E06C75", linewidth = 0.5, alpha = 0.6) +
    geom_hline(yintercept = 40, linetype = "dashed", color = "#D19A66", linewidth = 0.5, alpha = 0.6) +
    
    # Points
    geom_point(aes(color = vulnerability_grade, size = avg_bullpen_fatigue), alpha = 0.9) +
    
    # Labels
    geom_text(
      aes(label = team_abbreviation),
      size = 2.6,
      fontface = "bold",
      color = "#E6EDF3",
      nudge_y = -3.2,
      check_overlap = FALSE
    ) +
    
    # Color & Size Scales
    scale_color_manual(
      values = MLB_WORKLOAD_COLORS,
      drop = FALSE,
      name = "Vulnerability Grade"
    ) +
    scale_size_continuous(range = c(3.0, 6.5), name = "Avg Fatigue Score") +
    
    # Theming
    theme_mlb_dark(base_size = 11) +
    theme(
      legend.position = "right",
      panel.grid.minor = element_blank()
    ) +
    
    # Titles & Annotations
    labs(
      title = "MLB Bullpen Fatigue & Arm-Stress Diagnostic Quadrants",
      subtitle = "Evaluation of Relief Corps High-Leverage Workload, Back-to-Back Outings, and Vulnerability",
      x = x_label,
      y = "Bullpen Vulnerability Score (0 = Fully Rested, 100+ = Critical Fatigue)",
      caption = "Source: KayceeSlices MLB Analytics Engine | Workload & Velocity Delta Adjusted"
    )

  # Layer official team logos on top of points
  x_range <- diff(range(df$x_jitter, na.rm = TRUE))
  y_range <- diff(range(df$y_jitter, na.rm = TRUE))
  logo_dx <- max(0.35, x_range * 0.022)
  logo_dy <- max(1.6, y_range * 0.026)

  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    tid <- row$team_id
    logo_path <- get_team_logo_path(tid)
    if (!is.null(logo_path) && file.exists(logo_path)) {
      img <- tryCatch(png::readPNG(logo_path), error = function(e) NULL)
      if (!is.null(img)) {
        logo_grob <- grid::rasterGrob(img, interpolate = TRUE)
        p <- p + annotation_custom(
          grob = logo_grob,
          xmin = row$x_jitter - logo_dx,
          xmax = row$x_jitter + logo_dx,
          ymin = row$y_jitter - logo_dy,
          ymax = row$y_jitter + logo_dy
        )
      }
    }
  }

  # Save PNG
  saved_path <- save_mlb_plot(p, output_file, width = 11, height = 7.5, dpi = 300)
  return(invisible(saved_path))
}

if (sys.nframe() == 0) {
  generate_viz_bullpen_fatigue()
}
