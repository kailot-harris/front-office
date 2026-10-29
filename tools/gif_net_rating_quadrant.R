# ==============================================================================
# tools/gif_net_rating_quadrant.R
# Path: tools/gif_net_rating_quadrant.R
#
# NBA Offensive vs. Defensive Efficiency Net Rating Quadrant Scatter Animation
# Animates team positions on the classic NBA efficiency matrix:
#   - X-axis: Offensive Rating (Points scored per 100 possessions)
#   - Y-axis: Defensive Rating (Points allowed per 100 possessions, reversed so top-right is elite)
#   - Quadrant reference lines: Live league averages for the current frame
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark() and official team primary colors
#   - renders dual artifacts: gif_net_rating_quadrant.gif and gif_net_rating_quadrant.png
#     (reduced-motion static final frame) via render_animated_artifact()
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds or projected_30_team_standings.rds for baseline
#   - Falls back gracefully to synthesized baseline if cache is missing
#
# Usage:
#   Rscript tools/gif_net_rating_quadrant.R
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

# Ensure output cache directory exists
out_cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

all_teams <- sort(names(NBA_TEAM_COLORS))

# ------------------------------------------------------------------------------
# 1. Load Data & Compute Efficiency Trajectory
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")
ens_file <- find_cache_file("ensemble_team_ratings.rds")

quad_history <- list()

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  dates <- sort(unique(box$game_date))

  for (idx in seq_along(dates)) {
    d <- dates[idx]
    sub_box <- box[box$game_date <= d, ]

    stats <- sub_box %>%
      group_by(team = team_clean) %>%
      summarize(
        games = n(),
        pts_for = sum(as.numeric(team_score)),
        pts_against = sum(as.numeric(opponent_team_score)),
        # Standard NBA possessions: FGA + 0.44 * FTA - ORB + TOV
        poss = sum(as.numeric(field_goals_attempted) + 0.44 * as.numeric(free_throws_attempted) -
                   as.numeric(offensive_rebounds) + as.numeric(turnovers)),
        .groups = "drop"
      ) %>%
      mutate(
        off_rtg = ifelse(poss > 0, 100 * pts_for / poss, 112.0),
        def_rtg = ifelse(poss > 0, 100 * pts_against / poss, 112.0),
        net_rtg = off_rtg - def_rtg,
        step = as.integer(idx),
        date_label = format(as.Date(d), "%b %d")
      )

    # Ensure all 30 teams are present in frame
    missing_teams <- setdiff(all_teams, stats$team)
    if (length(missing_teams) > 0) {
      missing_df <- tibble(
        team = missing_teams,
        games = 0L,
        pts_for = 0,
        pts_against = 0,
        poss = 0,
        off_rtg = 112.0,
        def_rtg = 112.0,
        net_rtg = 0.0,
        step = as.integer(idx),
        date_label = format(as.Date(d), "%b %d")
      )
      stats <- bind_rows(stats, missing_df)
    }

    quad_history[[idx]] <- stats
  }
}

# Fallback if no games available
if (length(quad_history) == 0) {
  base_net <- setNames(rep(0, length(all_teams)), all_teams)
  if (!is.null(ens_file)) {
    ens <- tryCatch(readRDS(ens_file), error = function(e) NULL)
    if (!is.null(ens) && "team" %in% names(ens) && "ensemble_net_rating" %in% names(ens)) {
      for (i in seq_len(nrow(ens))) {
        tm <- resolve_team_abbr(ens$team[i])
        if (!is.na(tm) && tm %in% all_teams) {
          base_net[tm] <- as.numeric(ens$ensemble_net_rating[i])
        }
      }
    }
  }

  for (i in 1:4) {
    quad_history[[i]] <- tibble(
      team = all_teams,
      games = i,
      pts_for = 110 * i,
      pts_against = 110 * i,
      poss = 100 * i,
      off_rtg = 112 + base_net / 2 + sin(seq_along(all_teams) + i) * 2,
      def_rtg = 112 - base_net / 2 - cos(seq_along(all_teams) + i) * 2,
      net_rtg = base_net + sin(seq_along(all_teams) + i) * 4,
      step = as.integer(i),
      date_label = sprintf("Day %d", i)
    )
  }
}

quad_df <- bind_rows(quad_history)
all_steps <- sort(unique(quad_df$step))

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_net_rating_quad_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)

# Establish coordinate bounds across whole series with safety padding
x_min <- floor(min(quad_df$off_rtg) - 2)
x_max <- ceiling(max(quad_df$off_rtg) + 2)
y_min <- floor(min(quad_df$def_rtg) - 2)
y_max <- ceiling(max(quad_df$def_rtg) + 2)

for (s in all_steps) {
  frame_data <- quad_df %>% filter(step == s)
  cur_label <- frame_data$date_label[1]

  mean_off <- mean(frame_data$off_rtg)
  mean_def <- mean(frame_data$def_rtg)

  # Note: Y-axis is reversed (lower def rtg allowed is better defense -> placed near top)
  p_frame <- ggplot(frame_data, aes(x = off_rtg, y = def_rtg)) +
    # Quadrant lines at current frame league averages
    geom_vline(xintercept = mean_off, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.75) +
    geom_hline(yintercept = mean_def, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.75) +
    # Quadrant text labels
    annotate("text", x = x_max - 0.5, y = y_min + 0.8, label = "Contenders (High Off / Elite Def)",
             color = NBA_COLORS$accent, fontface = "bold", size = 3.6, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_min + 0.8, label = "Defensive Grinders (Low Off / Elite Def)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.3, hjust = 0) +
    annotate("text", x = x_max - 0.5, y = y_max - 0.6, label = "Offensive Juggernauts (High Off / Porous Def)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.3, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_max - 0.6, label = "Rebuilding (Low Off / Porous Def)",
             color = NBA_COLORS$negative, fontface = "bold", size = 3.3, hjust = 0) +
    # Team bubbles
    geom_point(aes(fill = team), shape = 21, size = 5.2, color = NBA_COLORS$text, stroke = 1.1) +
    geom_text(aes(label = team), color = NBA_COLORS$text, vjust = -1.15, fontface = "bold", size = 2.8) +
    scale_x_continuous(limits = c(x_min, x_max), breaks = seq(90, 130, by = 5)) +
    # Invert Y so lower points allowed (better defense) is at the top
    scale_y_reverse(limits = c(y_max, y_min), breaks = seq(90, 130, by = 5)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "NBA Efficiency Landscape \u2014 Net Rating Quadrant",
      subtitle = sprintf("Offensive vs. Defensive Rating per 100 Possessions through %s (Top-Right is Elite)", cur_label),
      x = "Offensive Rating (Pts Scored / 100 Poss)",
      y = "Defensive Rating (Pts Allowed / 100 Poss \u2014 Inverted: Lower is Better)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Dashed lines indicate current league averages"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG)
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_net_rating_quadrant.gif")
out_png <- file.path(out_cache_dir, "gif_net_rating_quadrant.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 700
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

cat(sprintf("[SUCCESS] Generated Net Rating Quadrant:\n  GIF: %s (%d bytes)\n  PNG: %s (%d bytes)\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size))
