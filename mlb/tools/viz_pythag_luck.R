# ==============================================================================
# tools/viz_pythag_luck.R — Actual vs Pythagenpat Win% Quadrant Analysis
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/tools/viz_pythag_luck.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24)
# Visualizes Actual Win% vs. Pythagenpat Expected Win% in a 4-quadrant layout:
#   - Quadrant I   (Top-Right):    Elite Contenders (High Expected, High Actual)
#   - Quadrant II  (Top-Left):     Lucky / Overachievers (Actual > Expected, Outperforming Run Diff)
#   - Quadrant III (Bottom-Left):  Rebuilding / Struggling (Low Expected, Low Actual)
#   - Quadrant IV  (Bottom-Right): Unlucky / Underachievers (High Expected, Low Actual, Unfavorable Sequence)
#
# Input:  cache/pythag/mlb_pythag_standings.rds
# Output: cache/viz/pythag_luck_quadrants_2024.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
})

source("config.R")
source("tools/viz_theme.R")
source("tools/mlb_logo_utils.R")

generate_viz_pythag_luck <- function(season = 2024,
                                     standings_file = cache_path("pythag", "mlb_pythag_standings.rds"),
                                     output_file    = sprintf("pythag_luck_quadrants_%d.png", season)) {
  message(sprintf(">>> [VIZ] Generating Pythagorean luck quadrants for %d...", season))
  
  if (!file.exists(standings_file)) {
    standings_file <- cache_path("pythag", sprintf("pythag_baseline_%d.rds", season))
  }
  if (!file.exists(standings_file)) {
    stop(sprintf("Pythagorean standings file not found at '%s'. Run mlb_pythag_baseline.R first.", standings_file))
  }
  
  pythag_df <- readRDS(standings_file)
  if (nrow(pythag_df) == 0) {
    stop("Pythagorean standings dataframe is empty.")
  }
  
  # Fetch team table for abbreviations and division info
  teams_meta <- as.data.frame(get_mlb_team_table())
  mlb_teams <- teams_meta[which(teams_meta[["sport_id"]] == 1 & !is.na(teams_meta[["division_name"]])),
                          c("team_id", "team_full_name", "team_abbreviation", "division_name")]
  mlb_teams$division <- standardize_division(mlb_teams$division_name)
  
  # Merge abbreviations
  df <- if ("team_id" %in% names(pythag_df)) {
    merge(pythag_df, mlb_teams[, c("team_id", "team_abbreviation", "division")],
          by = "team_id", all.x = TRUE)
  } else {
    merge(pythag_df, mlb_teams[, c("team_full_name", "team_abbreviation", "division")],
          by.x = "team_name", by.y = "team_full_name", all.x = TRUE)
  }
  df$team_abbreviation[is.na(df$team_abbreviation)] <- substr(df$team_name[is.na(df$team_abbreviation)], 1, 3)
  
  # Standardize Pythagorean win pct column
  if (!"win_pct_pythagenpat" %in% names(df) && "exp_pythagenpat" %in% names(df)) {
    df$win_pct_pythagenpat <- df$exp_pythagenpat
  } else if (!"win_pct_pythagenpat" %in% names(df) && "pythag_win_pct" %in% names(df)) {
    df$win_pct_pythagenpat <- df$pythag_win_pct
  }

  # Ensure luck_wins is present (luck_wins_pat)
  if (!"luck_wins_pat" %in% names(df)) {
    df$luck_wins_pat <- round((df$actual_win_pct - df$win_pct_pythagenpat) * df$games_played, 1)
  }

  
  # Filter strictly to the 30 active MLB franchises
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  df <- df[which(df$team_name %in% act_teams$team_full_name), ]
  
  # Fetch team_id for logo mapping
  if (!"team_id" %in% names(df)) {
    df <- merge(df, act_teams[, c("team_id", "team_full_name")],
                by.x = "team_name", by.y = "team_full_name", all.x = TRUE)
  }

  # Axis limits and centers
  center_val <- 0.500
  xlims <- c(0.35, 0.65)
  ylims <- c(0.35, 0.65)
  
  # Label placement: nudge slightly above points
  p <- ggplot(df, aes(x = win_pct_pythagenpat, y = actual_win_pct)) +
    # Quadrant dividing lines (.500 baseline)
    geom_vline(xintercept = center_val, linetype = "dashed", color = "#484F58", linewidth = 0.6) +
    geom_hline(yintercept = center_val, linetype = "dashed", color = "#484F58", linewidth = 0.6) +
    
    # 1:1 Identity Line (Expected = Actual)
    geom_abline(intercept = 0, slope = 1, linetype = "dotted", color = "#8B949E", linewidth = 0.6) +
    
    # Quadrant Background Watermarks / Labels
    annotate("text", x = 0.64, y = 0.64, label = "ELITE CONTENDERS\n(Strong Base + Results)",
             color = "#30363D", size = 4.2, fontface = "bold.italic", hjust = 1, lineheight = 0.9) +
    annotate("text", x = 0.36, y = 0.64, label = "LUCKY / OVERACHIEVERS\n(1-Run / High-Leverage Surge)",
             color = "#30363D", size = 4.2, fontface = "bold.italic", hjust = 0, lineheight = 0.9) +
    annotate("text", x = 0.36, y = 0.36, label = "REBUILDING / STRUGGLING\n(Sub-.500 Run Diff & Record)",
             color = "#30363D", size = 4.2, fontface = "bold.italic", hjust = 0, lineheight = 0.9) +
    annotate("text", x = 0.64, y = 0.36, label = "UNLUCKY UNDERACHIEVERS\n(Strong Run Diff, Poor Sequencing)",
             color = "#30363D", size = 4.2, fontface = "bold.italic", hjust = 1, lineheight = 0.9) +
    
    # Team Points colored by luck (luck_wins_pat)
    geom_point(aes(color = luck_wins_pat, size = abs(luck_wins_pat)), alpha = 0.85) +
    
    # Team text labels
    geom_text(
      aes(
        label = sprintf("%s (%+.1f)", team_abbreviation, luck_wins_pat),
        vjust = ifelse(actual_win_pct >= win_pct_pythagenpat, -1.2, 2.0)
      ),
      size = 2.6,
      fontface = "bold",
      color = "#E6EDF3",
      lineheight = 0.85
    ) +
    
    # Color Scale: Diverging from crimson (unlucky) through slate to emerald (lucky)
    scale_color_gradient2(
      low = MLB_LUCK_COLORS$unlucky,
      mid = MLB_LUCK_COLORS$neutral,
      high = MLB_LUCK_COLORS$lucky,
      midpoint = 0,
      name = "Luck (Wins Over/Under\nPythagenpat Expected)"
    ) +
    scale_size_continuous(range = c(2.5, 6.0), guide = "none") +
    
    # Coordinates & scales
    scale_x_continuous(
      labels = scales::number_format(accuracy = 0.001),
      breaks = seq(0.350, 0.650, 0.050),
      limits = xlims
    ) +
    scale_y_continuous(
      labels = scales::number_format(accuracy = 0.001),
      breaks = seq(0.350, 0.650, 0.050),
      limits = ylims
    ) +
    
    # Theming
    theme_mlb_dark(base_size = 11) +
    theme(
      legend.position = "right",
      legend.title = element_text(size = 8.5),
      panel.grid.minor = element_blank()
    ) +
    
    # Labels
    labs(
      title = sprintf("%d MLB Pythagorean Luck & Performance Quadrants", season),
      subtitle = "Comparison of Actual Win% vs. Pythagenpat Expected Win% based on Run Differential & Run Environment\nPoints sized and colored by Luck Residuals (Wins above/below expected) with official team logos",
      x = "Pythagenpat Expected Win % (Run Differential Quality)",
      y = sprintf("Actual %d Win %%", season),
      caption = "Dotted line: Expected = Actual Win% | Dashed lines: .500 Division | Source: KayceeSlices MLB Analytics Engine"
    )

  # Layer official team logos on top of points
  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    tid <- row$team_id %||% row$team_id.x %||% row$team_id.y
    logo_path <- get_team_logo_path(tid)
    if (!is.null(logo_path) && file.exists(logo_path)) {
      img <- tryCatch(png::readPNG(logo_path), error = function(e) NULL)
      if (!is.null(img)) {
        logo_grob <- grid::rasterGrob(img, interpolate = TRUE)
        p <- p + annotation_custom(
          grob = logo_grob,
          xmin = row$win_pct_pythagenpat - 0.0055,
          xmax = row$win_pct_pythagenpat + 0.0055,
          ymin = row$actual_win_pct - 0.0055,
          ymax = row$actual_win_pct + 0.0055
        )
      }
    }
  }

  # Save PNG
  saved_path <- save_mlb_plot(p, output_file, width = 11, height = 7.5, dpi = 300)
  return(invisible(saved_path))
}


if (sys.nframe() == 0) {
  generate_viz_pythag_luck()
}
