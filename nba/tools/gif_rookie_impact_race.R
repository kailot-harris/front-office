# ==============================================================================
# tools/gif_rookie_impact_race.R
# Path: tools/gif_rookie_impact_race.R
#
# Rookie Class Scoring Volume & True Shooting Efficiency Accumulator Race (Issue #59)
#
# Features:
#   - Sources tools/viz_common.R and uses theme_nba_dark(), NBA_COLORS, and canonical team colors.
#   - Tracks rookie scoring volume (cumulative points) vs. efficiency (True Shooting % TS)
#     across the rookie class timeline.
#   - Reads player box scores from cache (cache/nba_player_box_2026.rds or 2027.rds)
#     with robust fallback if missing.
#   - Animates progressive point accumulation bubbles sized by game appearances and colored by team.
#   - Outputs dual artifacts: cache/gif_rookie_impact_race.gif and cache/gif_rookie_impact_race.png
#     via render_animated_artifact().
#   - Syncs artifacts to web/public/media/.
#
# Usage:
#   Rscript tools/gif_rookie_impact_race.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# Locate root directory and source visualization foundations
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

viz_common_path <- file.path(SCRIPT_DIR, "tools", "viz_common.R")
if (!file.exists(viz_common_path)) {
  viz_common_path <- file.path(getwd(), "tools", "viz_common.R")
}
source(viz_common_path)

config_path <- file.path(SCRIPT_DIR, "config.R")
if (file.exists(config_path)) {
  source(config_path)
}

# Resolve cache file helper
find_cache_file <- function(filename) {
  candidates <- c(
    if (exists("CACHE_DIR")) file.path(CACHE_DIR, filename) else NULL,
    if (exists("PROJECT_DIR")) file.path(PROJECT_DIR, "cache", filename) else NULL,
    file.path(SCRIPT_DIR, "cache", filename),
    file.path(getwd(), "cache", filename),
    file.path("..", "NBA Analytics", "cache", filename),
    file.path("C:/Users/kailo/kayceeslices/front-office/NBA Analytics/cache", filename)
  )
  for (cand in candidates) {
    if (!is.null(cand) && file.exists(cand)) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  return(NULL)
}

out_cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

web_media_dir <- file.path(SCRIPT_DIR, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
# 1. Load Data & Prepare Rookie Trajectory
# ------------------------------------------------------------------------------
pbox_file <- find_cache_file("nba_player_box_2026.rds")
if (is.null(pbox_file)) pbox_file <- find_cache_file("nba_player_box_2027.rds")

rookie_names <- c(
  "Stephon Castle", "Matas Buzelis", "Reed Sheppard", "Donovan Clingan",
  "Bub Carrington", "Jaylen Wells", "Kel'el Ware", "Tristan da Silva",
  "Alex Sarr", "Zaccharie Risacher", "Cody Williams", "Jared McCain",
  "Yves Missi", "Dalton Knecht", "Zach Edey"
)

if (!is.null(pbox_file)) {
  pbox <- readRDS(pbox_file)
  rookie_box <- pbox %>%
    filter(athlete_display_name %in% rookie_names) %>%
    mutate(
      game_date = as.Date(game_date),
      points = as.numeric(points),
      fga = as.numeric(field_goals_attempted),
      fta = as.numeric(free_throws_attempted),
      team_clean = resolve_team_abbr(team_abbreviation)
    ) %>%
    filter(!is.na(points), !is.na(game_date)) %>%
    arrange(game_date)
} else {
  # Synthetic rookie season dataset
  set.seed(42)
  dates <- seq(as.Date("2025-10-22"), as.Date("2026-04-12"), by = "3 days")
  rows <- list()
  for (rn in rookie_names) {
    tm <- sample(c("SAS", "CHI", "HOU", "POR", "WAS", "MEM", "MIA", "ORL", "ATL", "LAL"), 1)
    pts_per_gm <- rnorm(length(dates), mean = 13, sd = 4)
    rows[[rn]] <- tibble(
      athlete_display_name = rn,
      game_date = dates,
      points = pmax(2, round(pts_per_gm)),
      fga = pmax(3, round(pts_per_gm * 0.8)),
      fta = pmax(0, round(pts_per_gm * 0.25)),
      team_clean = tm
    )
  }
  rookie_box <- bind_rows(rows)
}

# Create 8 progressive milestone cutoffs across the season
unique_dates <- sort(unique(rookie_box$game_date))
milestone_indices <- round(seq(from = 15, to = length(unique_dates), length.out = 8))
milestone_dates <- unique_dates[milestone_indices]

# Compute progressive cumulative metrics at each milestone
tmp_frame_dir <- file.path(tempdir(), sprintf("rookie_race_frames_%d", as.integer(Sys.time())))
if (!dir.exists(tmp_frame_dir)) dir.create(tmp_frame_dir, recursive = TRUE)

n_frames <- length(milestone_dates)
frame_files <- character(n_frames)

unique_teams <- unique(rookie_box$team_clean)
team_colors <- sapply(unique_teams, function(tm) get_nba_team_color(tm, "primary"))

for (f_idx in seq_along(milestone_dates)) {
  cut_date <- milestone_dates[f_idx]
  
  accum_df <- rookie_box %>%
    filter(game_date <= cut_date) %>%
    group_by(athlete_display_name, team_clean) %>%
    summarize(
      cum_pts = sum(points, na.rm = TRUE),
      cum_fga = sum(fga, na.rm = TRUE),
      cum_fta = sum(fta, na.rm = TRUE),
      games_played = n(),
      .groups = "drop"
    ) %>%
    mutate(
      denom = 2 * (cum_fga + 0.44 * cum_fta),
      ts_pct = ifelse(denom > 0, (cum_pts / denom) * 100, 50.0)
    ) %>%
    # Top 10 by points at current date
    arrange(desc(cum_pts)) %>%
    slice_head(n = 10)

  p_frame <- ggplot(accum_df, aes(x = cum_pts, y = ts_pct, color = team_clean, fill = team_clean)) +
    # Reference league average TS% band (57.5%)
    geom_hline(yintercept = 57.5, linetype = "dashed", color = NBA_COLORS$subtext, linewidth = 0.6) +
    annotate("text", x = 150, y = 58.2, label = "League Avg TS% (57.5%)",
             color = NBA_COLORS$subtext, size = 2.8, hjust = 0) +
    # Rookie bubbles sized by games played
    geom_point(aes(size = games_played), alpha = 0.85, stroke = 1.2) +
    geom_text(aes(label = sprintf("%s\n(%d pts, %.1f%%)", athlete_display_name, round(cum_pts), ts_pct)),
              vjust = -0.7, hjust = 0.5, color = NBA_COLORS$text, fontface = "bold", size = 2.7) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    scale_size_continuous(range = c(3, 9), name = "Games Played") +
    scale_x_continuous(limits = c(50, 1800), breaks = seq(200, 1600, by = 300)) +
    scale_y_continuous(limits = c(45, 68), breaks = seq(46, 66, by = 4)) +
    theme_nba_dark(base_size = 11) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(size = 13, face = "bold"),
      plot.subtitle = element_text(size = 9.5, color = NBA_COLORS$subtext)
    ) +
    labs(
      title = "NBA Rookie Class Scoring Volume & True Shooting Efficiency Race",
      subtitle = sprintf("Through %s \u00b7 Cumulative Points vs. True Shooting %% (TS%%) \u00b7 Bubble size = Games Played",
                         format(cut_date, "%B %d, %Y")),
      x = "Cumulative Points Scored",
      y = "True Shooting Percentage (TS %)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Rookie Tracking & Box Score Engine (#59)"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", f_idx))
  ggsave(frame_path, plot = p_frame, width = 11, height = 7, dpi = 110, bg = NBA_COLORS$bg)
  frame_files[f_idx] <- frame_path
}

# ------------------------------------------------------------------------------
# 2. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_rookie_impact_race.gif")
out_png <- file.path(out_cache_dir, "gif_rookie_impact_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 6,
  width            = 1100,
  height           = 700
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_rookie_impact_race.gif")
media_png <- file.path(web_media_dir, "gif_rookie_impact_race.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Rookie Impact Race:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
