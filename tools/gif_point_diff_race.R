# ==============================================================================
# tools/gif_point_diff_race.R
# Path: tools/gif_point_diff_race.R
#
# NBA Cumulative Point Differential Race Animation (Season 2026-27)
# Animates cumulative point differentials across all 30 NBA teams through each
# game date of the regular season.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark() and official team primary colors
#   - renders dual artifacts: gif_point_diff_race.gif and gif_point_diff_race.png
#     (reduced-motion static final frame) via render_animated_artifact()
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Falls back gracefully to synthesized schedule if cache is missing
#
# Usage:
#   Rscript tools/gif_point_diff_race.R
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
# 1. Load Data & Compute Cumulative Point Differential
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")

race_history <- list()
race_history[[1]] <- tibble(
  step = 0L,
  date_label = "Season Open",
  team = all_teams,
  cum_diff = 0.0
)

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  dates <- sort(unique(box$game_date))

  team_games <- box %>%
    transmute(
      team = team_clean,
      game_date = as.character(game_date),
      pts = as.numeric(team_score),
      opp_pts = as.numeric(opponent_team_score),
      diff = pts - opp_pts
    )

  team_date_diff <- team_games %>%
    group_by(team, game_date) %>%
    summarize(diff = sum(diff), .groups = "drop")

  running_cum <- setNames(rep(0.0, length(all_teams)), all_teams)

  for (idx in seq_along(dates)) {
    d <- as.character(dates[idx])
    d_diffs <- team_date_diff %>% filter(game_date == d)
    if (nrow(d_diffs) > 0) {
      for (j in seq_len(nrow(d_diffs))) {
        tm <- d_diffs$team[j]
        if (!is.na(tm) && tm %in% all_teams) {
          running_cum[tm] <- running_cum[tm] + d_diffs$diff[j]
        }
      }
    }
    race_history[[idx + 1]] <- tibble(
      step = as.integer(idx),
      date_label = format(as.Date(d), "%b %d"),
      team = all_teams,
      cum_diff = as.numeric(running_cum[all_teams])
    )
  }
}

# Fallback if no games available
if (length(race_history) <= 1) {
  sim_cum <- setNames(rep(0.0, length(all_teams)), all_teams)
  for (i in 1:4) {
    sim_cum <- sim_cum + sin(seq_along(all_teams) + i) * 6
    race_history[[i + 1]] <- tibble(
      step = as.integer(i),
      date_label = sprintf("Day %d", i),
      team = all_teams,
      cum_diff = as.numeric(sim_cum[all_teams])
    )
  }
}

race_df <- bind_rows(race_history)
all_steps <- sort(unique(race_df$step))
max_step  <- max(all_steps)

step_labels_map <- race_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_point_diff_race_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)
y_min <- min(race_df$cum_diff) - 8
y_max <- max(race_df$cum_diff) + 8

for (s in all_steps) {
  frame_lines <- race_df %>% filter(step <= s)
  frame_pts   <- race_df %>% filter(step == s)

  cur_label <- step_labels[[as.character(s)]]

  p_frame <- ggplot(frame_lines, aes(x = step, y = cum_diff, group = team, color = team)) +
    # Zero baseline reference line
    geom_hline(yintercept = 0, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.8) +
    geom_line(linewidth = 1.05, alpha = 0.85) +
    geom_point(data = frame_pts, aes(x = step, y = cum_diff, fill = team),
               shape = 21, size = 3.6, color = NBA_COLORS$text, stroke = 1.1) +
    geom_text(data = frame_pts, aes(x = step + 0.12, y = cum_diff, label = team),
              hjust = 0, vjust = 0.35, color = NBA_COLORS$text, fontface = "bold", size = 2.7) +
    scale_x_continuous(breaks = all_steps, labels = step_labels, limits = c(-0.3, max_step + 0.85)) +
    scale_y_continuous(limits = c(y_min, y_max)) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "NBA Cumulative Point Differential Race (2026-27)",
      subtitle = sprintf("Cumulative point differential trajectory through %s (Points For minus Points Against)", cur_label),
      x = "Date",
      y = "Cumulative Point Differential",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Box Score Engine"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 6.8, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG)
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_point_diff_race.gif")
out_png <- file.path(out_cache_dir, "gif_point_diff_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 680
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

cat(sprintf("[SUCCESS] Generated Point Diff Race:\n  GIF: %s (%d bytes)\n  PNG: %s (%d bytes)\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size))
