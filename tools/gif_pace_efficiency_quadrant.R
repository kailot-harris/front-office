# ==============================================================================
# tools/gif_pace_efficiency_quadrant.R
# Path: tools/gif_pace_efficiency_quadrant.R
#
# NBA Pace vs. Net Rating Tactical Quadrant Scatter Animation (Issue #53)
# Animates team positions on the pace vs efficiency matrix across the season:
#   - X-axis: Pace (Possessions per 48 minutes)
#   - Y-axis: Net Rating (Offensive Rating minus Defensive Rating)
#   - Quadrant reference lines: Live league averages for the current frame
#   - Quadrants: Fast & Dominant, Methodical & Elite, Run & Gun Vulnerable, Slow & Rebuilding
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and canonical team colors
#   - renders dual artifacts: gif_pace_efficiency_quadrant.gif and
#     gif_pace_efficiency_quadrant.png (reduced-motion static final frame)
#     via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds or projected_30_team_standings.rds for baseline
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_pace_efficiency_quadrant.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# Locate root directory and source visualization foundations
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- args[grepl("^--file=", args)]
  base <- if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else getwd()
  repo <- if (file.exists(file.path(base, "tools", "viz_common.R"))) base else dirname(base)
  normalizePath(repo, winslash = "/", mustWork = FALSE)
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

out_cache_dir <- file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

web_media_dir <- file.path(SCRIPT_DIR, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

all_teams <- sort(names(NBA_TEAM_COLORS))

# ------------------------------------------------------------------------------
# 1. Load Data & Compute Pace and Net Rating Trajectory
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
        poss = sum(as.numeric(field_goals_attempted) + 0.44 * as.numeric(free_throws_attempted) -
                   as.numeric(offensive_rebounds) + as.numeric(turnovers)),
        .groups = "drop"
      ) %>%
      mutate(
        pace = ifelse(games > 0, (poss / games), 100.0),
        off_rtg = ifelse(poss > 0, 100 * pts_for / poss, 112.0),
        def_rtg = ifelse(poss > 0, 100 * pts_against / poss, 112.0),
        net_rtg = off_rtg - def_rtg,
        step = as.integer(idx),
        date_label = format(as.Date(d), "%b %d")
      )

    missing_teams <- setdiff(all_teams, stats$team)
    if (length(missing_teams) > 0) {
      missing_df <- tibble(
        team = missing_teams,
        games = 0L,
        pts_for = 0,
        pts_against = 0,
        poss = 0,
        pace = 100.0,
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

  for (i in 1:5) {
    quad_history[[i]] <- tibble(
      team = all_teams,
      games = i,
      pts_for = 110 * i,
      pts_against = 110 * i,
      poss = 100 * i,
      pace = 98 + (seq_along(all_teams) %% 9) + sin(seq_along(all_teams) + i) * 1.5,
      off_rtg = 112 + base_net / 2,
      def_rtg = 112 - base_net / 2,
      net_rtg = base_net + sin(seq_along(all_teams) + i) * 3,
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
tmp_frame_dir <- file.path(tempdir(), "nba_pace_efficiency_quad_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)

x_min <- floor(min(quad_df$pace) - 2)
x_max <- ceiling(max(quad_df$pace) + 2)
y_min <- floor(min(quad_df$net_rtg) - 3)
y_max <- ceiling(max(quad_df$net_rtg) + 3)

for (s in all_steps) {
  frame_data <- quad_df %>% filter(step == s)
  cur_label <- frame_data$date_label[1]

  mean_pace <- mean(frame_data$pace)
  mean_net  <- 0

  p_frame <- ggplot(frame_data, aes(x = pace, y = net_rtg)) +
    geom_vline(xintercept = mean_pace, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.75) +
    geom_hline(yintercept = mean_net, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.75) +
    # Quadrant annotations
    annotate("text", x = x_max - 0.5, y = y_max - 0.8, label = "Fast & Dominant (High Pace / High Net)",
             color = NBA_COLORS$accent, fontface = "bold", size = 3.4, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_max - 0.8, label = "Methodical & Elite (Half-Court / High Net)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 0) +
    annotate("text", x = x_max - 0.5, y = y_min + 0.8, label = "Run & Gun Vulnerable (High Pace / Low Net)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_min + 0.8, label = "Grind & Rebuild (Slow Pace / Low Net)",
             color = NBA_COLORS$negative, fontface = "bold", size = 3.2, hjust = 0) +
    # Team bubbles
    geom_point(aes(fill = team), shape = 21, size = 5.2, color = NBA_COLORS$text, stroke = 1.1) +
    geom_text(aes(label = team), color = NBA_COLORS$text, vjust = -1.15, fontface = "bold", size = 2.8) +
    scale_x_continuous(limits = c(x_min, x_max), breaks = scales::pretty_breaks(n = 6)) +
    scale_y_continuous(limits = c(y_min, y_max), breaks = scales::pretty_breaks(n = 7)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "NBA Pace vs. Net Rating Tactical Efficiency Quadrant",
      subtitle = sprintf("Possessions per 48 Min vs Net Rating (+/- per 100 poss) through %s", cur_label),
      x = "Pace (Estimated Possessions / 48 Min)",
      y = "Net Rating (Points Differential / 100 Possessions)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Vertical line: Mean Pace \u00b7 Horizontal line: Net Zero"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_pace_efficiency_quadrant.gif")
out_png <- file.path(out_cache_dir, "gif_pace_efficiency_quadrant.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 700
)

unlink(tmp_frame_dir, recursive = TRUE)

media_gif <- file.path(web_media_dir, "gif_pace_efficiency_quadrant.gif")
media_png <- file.path(web_media_dir, "gif_pace_efficiency_quadrant.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Pace Efficiency Quadrant:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
