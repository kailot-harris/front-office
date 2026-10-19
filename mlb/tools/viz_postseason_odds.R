# ==============================================================================
# tools/viz_postseason_odds.R — 12-Team Postseason Advancement & Championship Odds
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/tools/viz_postseason_odds.R
#
# Phase 9: Quantitative Visualization Suite (Issue #24)
# Visualizes Monte Carlo simulated probabilities across all 12 MLB postseason teams:
#   - Progression rounds: Division Series (DS), League Championship (LCS), Pennant, World Series Champion
#   - Grouped and ordered by World Series championship probability
#   - Distinguishes AL and NL seeds, displaying Elo ratings and regular season records
#
# Input:  cache/postseason/postseason_team_probabilities.rds
# Output: cache/viz/postseason_championship_odds.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
  library(tidyr)
})

source("config.R")
source("tools/viz_theme.R")
source("tools/mlb_logo_utils.R")

generate_viz_postseason_odds <- function(season = 2024,
                                         probs_file  = cache_path("postseason", "postseason_team_probabilities.rds"),
                                         output_file = "postseason_championship_odds.png") {
  message(sprintf(">>> [VIZ] Generating Postseason Championship Odds visualization for %d...", season))
  
  if (!file.exists(probs_file)) {
    stop(sprintf("Postseason probabilities file not found at '%s'. Run mlb_postseason_simulator.R first.", probs_file))
  }
  
  ps_df <- readRDS(probs_file)
  if (nrow(ps_df) == 0) {
    stop("Postseason probabilities dataframe is empty.")
  }
  
  # Fetch team table for abbreviations
  teams_meta <- as.data.frame(get_mlb_team_table())
  mlb_teams <- teams_meta[which(teams_meta[["sport_id"]] == 1 & !is.na(teams_meta[["division_name"]])),
                          c("team_id", "team_abbreviation")]
  
  df <- merge(ps_df, mlb_teams, by = "team_id", all.x = TRUE)
  df$team_abbreviation[is.na(df$team_abbreviation)] <- substr(df$team_name[is.na(df$team_abbreviation)], 1, 3)
  
  # Construct readable team label: e.g. "LAD (#1 NL, 98-64)"
  df$team_label <- sprintf("%s (#%d %s | %.0f Elo)",
                           df$team_name, df$seed, df$league, df$elo_rating)
  
  # Order teams by World Series Championship Probability
  df <- df[order(df$pct_ws, df$pct_pennant, df$pct_lcs), ]
  df$team_label <- factor(df$team_label, levels = df$team_label)
  df$y_idx <- seq_len(nrow(df))
  
  # Base ggplot
  p <- ggplot(df, aes(x = pct_ws, y = team_label)) +
    # Background subtle bar for Pennant probability
    geom_col(aes(x = pct_pennant), fill = "#58A6FF", alpha = 0.25, width = 0.6) +
    
    # Primary bar for World Series Title probability
    geom_col(aes(fill = league), width = 0.6, alpha = 0.9) +
    
    # Text labels showing WS% and Pennant% (offset to allow room for logo)
    geom_text(
      aes(
        label = sprintf("WS: %.1f%%  (Pennant: %.1f%% | LCS: %.1f%%)",
                        pct_ws, pct_pennant, pct_lcs),
        x = pct_ws + 1.8
      ),
      hjust = 0,
      size = 3.2,
      fontface = "bold",
      color = "#E6EDF3"
    ) +
    
    # League color fills
    scale_fill_manual(
      values = c("AL" = "#E06C75", "NL" = "#58A6FF"),
      name = "League"
    ) +
    
    # Scales
    scale_x_continuous(
      labels = function(x) paste0(x, "%"),
      limits = c(0, max(df$pct_pennant) + 8),
      breaks = seq(0, 40, 5),
      expand = expansion(mult = c(0.01, 0.05))
    ) +
    
    # Theming
    theme_mlb_dark(base_size = 11) +
    theme(
      legend.position = "right",
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      axis.text.y = element_text(face = "bold", size = 9, color = "#FFFFFF")
    ) +
    
    # Titles & Annotations
    labs(
      title = sprintf("%d MLB Postseason Monte Carlo Championship Odds (10,000 Simulations)", season),
      subtitle = "Simulated probabilities through Wild Card, Division Series, League Championship, and World Series\nOrdered by title likelihood; shaded blue backdrop indicates League Pennant probability",
      x = "World Series Championship Probability (%)",
      y = "Playoff Seed & Team Strength",
      caption = "Source: KayceeSlices MLB Analytics Engine | 12-Team Bracket Monte Carlo Simulation"
    )
  
  # Layer Team Logo Images onto the end of each World Series bar
  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    logo_path <- get_team_logo_path(row$team_id)
    if (!is.null(logo_path) && file.exists(logo_path)) {
      img <- tryCatch(png::readPNG(logo_path), error = function(e) NULL)
      if (!is.null(img)) {
        logo_grob <- grid::rasterGrob(img, interpolate = TRUE)
        # Position logo at end of WS bar
        logo_x <- row$pct_ws + 0.8
        logo_y <- row$y_idx
        p <- p + annotation_custom(
          grob = logo_grob,
          xmin = logo_x - 0.65,
          xmax = logo_x + 0.65,
          ymin = logo_y - 0.42,
          ymax = logo_y + 0.42
        )
      }
    }
  }

  # Save PNG
  saved_path <- save_mlb_plot(p, output_file, width = 11.5, height = 7.5, dpi = 300)
  return(invisible(saved_path))
}

if (sys.nframe() == 0) {
  generate_viz_postseason_odds()
}

