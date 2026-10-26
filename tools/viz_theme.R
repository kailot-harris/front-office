# ==============================================================================
# tools/viz_theme.R — Publication-Ready Dark Theme & Palettes for MLB Viz Suite
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/viz_theme.R
#
# Phase 9: Shared Visual Theme & Utilities (Issue #24)
# Minimal dark aesthetic inspired by modern analytics dashboards:
#   - Background: #161B22
#   - Panel:      #21262D
#   - Gridlines:  #30363D
#   - Text:       #E6EDF3 (primary), #8B949E (secondary / captions)
#   - Accents:    Division color palette & diverging luck gradients
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
})

source("config.R")

# Ensure cache/viz directory exists
ensure_viz_dir <- function() {
  viz_dir <- cache_path("viz", create = TRUE)
  if (!dir.exists(viz_dir)) {
    dir.create(viz_dir, recursive = TRUE, showWarnings = FALSE)
  }
  return(viz_dir)
}

# MLB Dark Theme for ggplot2
theme_mlb_dark <- function(base_size = 11, base_family = "") {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(
      # Canvas & Background
      plot.background = element_rect(fill = "#161B22", color = NA),
      panel.background = element_rect(fill = "#21262D", color = NA),
      panel.border = element_rect(color = "#30363D", fill = NA, linewidth = 0.6),
      
      # Gridlines
      panel.grid.major = element_line(color = "#30363D", linewidth = 0.4),
      panel.grid.minor = element_line(color = "#21262D", linewidth = 0.2),
      
      # Text hierarchy
      text = element_text(color = "#E6EDF3"),
      plot.title = element_text(
        face = "bold", size = rel(1.35), color = "#FFFFFF",
        margin = margin(b = 6)
      ),
      plot.subtitle = element_text(
        size = rel(0.95), color = "#8B949E",
        margin = margin(b = 12)
      ),
      plot.caption = element_text(
        size = rel(0.75), color = "#8B949E",
        margin = margin(t = 10), hjust = 1
      ),
      
      # Axes
      axis.title = element_text(face = "bold", size = rel(0.9), color = "#C9D1D9"),
      axis.title.x = element_text(margin = margin(t = 8)),
      axis.title.y = element_text(margin = margin(r = 8)),
      axis.text = element_text(size = rel(0.8), color = "#8B949E"),
      axis.ticks = element_line(color = "#30363D", linewidth = 0.4),
      
      # Legends
      legend.background = element_rect(fill = "#161B22", color = "#30363D", linewidth = 0.4),
      legend.key = element_rect(fill = "transparent", color = NA),
      legend.title = element_text(face = "bold", size = rel(0.85), color = "#E6EDF3"),
      legend.text = element_text(size = rel(0.8), color = "#C9D1D9"),
      legend.position = "right",
      
      # Strip (facet labels)
      strip.background = element_rect(fill = "#1F242C", color = "#30363D"),
      strip.text = element_text(face = "bold", size = rel(0.85), color = "#E6EDF3", margin = margin(t = 4, b = 4)),
      
      # Margin
      plot.margin = margin(16, 16, 14, 16)
    )
}

# Division Color Palette (30 MLB teams grouped by division)
MLB_DIVISION_COLORS <- c(
  "AL East"    = "#58A6FF", # Crisp Blue
  "AL Central" = "#7EE787", # Mint Green
  "AL West"    = "#FFA657", # Amber Orange
  "NL East"    = "#D2A8FF", # Lavender Purple
  "NL Central" = "#79C0FF", # Cyan Sky
  "NL West"    = "#FF7B72"  # Coral Red
)

# Canonical Division Name mapping helper
standardize_division <- function(div_name) {
  if (is.null(div_name) || length(div_name) == 0) return(character(0))
  div <- as.character(div_name)
  div <- gsub("^American League ", "AL ", div)
  div <- gsub("^National League ", "NL ", div)
  div
}

# Performance Divergence / Luck Palette
MLB_LUCK_COLORS <- list(
  unlucky  = "#E06C75", # Crimson / Red (Negative luck / underperforming run diff)
  neutral  = "#8B949E", # Slate Grey
  lucky    = "#98C379"  # Emerald Green (Positive luck / outperforming run diff)
)

# Bullpen Fatigue / Vulnerability Workload Palette
MLB_WORKLOAD_COLORS <- c(
  "Well Rested"        = "#7EE787", # Mint Green (Low)
  "Low Vulnerability"  = "#7EE787",
  "Moderate Workload"  = "#E5C07B", # Gold / Yellow (Moderate)
  "Elevated Workload"  = "#D19A66", # Orange (Elevated)
  "High Vulnerability" = "#E06C75"  # Crimson (High)
)

# Helper for saving standard 300 DPI visualization artifacts
save_mlb_plot <- function(plot, filename, width = 11, height = 7, dpi = 300) {
  ensure_viz_dir()
  full_path <- cache_path("viz", filename)
  ggsave(
    filename = full_path,
    plot = plot,
    width = width,
    height = height,
    dpi = dpi,
    device = "png",
    bg = "#161B22"
  )
  message(sprintf(">>> Saved visualization: %s (%.1f x %.1f in @ %d dpi)",
                  full_path, width, height, dpi))
  invisible(full_path)
}
