# ==============================================================================
# GIF: Upset Timeline (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_upset_timeline.R
#
# Closes GitHub issue #26 (Phase 9 / docs/task_assignments_phase8.md task P9-H). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/weekly_accuracy_report.R / tools/gif_point_diff_race.R). Reads
# get_elo_history()'s $long_games (which itself reads CACHE_SCHEDULES/CACHE_FATIGUE_METRICS)
# only - writes nothing back to any cache file.
#
# Upset-detection logic below is copied VERBATIM from docs/week5_elo_analysis.qmd's tbl-upsets
# chunk (a game is an upset when the winning team's pre-game Elo win probability team_win_prob
# was below 0.5) per this task's brief, so the qmd's rendered table and this GIF can never drift
# apart. Reuses the shared theme_elo_dark() dark theme (copied verbatim, same as every other
# Phase 9 GIF script) and nflplotR::geom_nfl_logos() for team identity, plus the same
# ggsave-per-frame + magick::image_animate() GIF-assembly approach used by
# cache/elo_scatter_animation.gif / tools/gif_point_diff_race.R.
#
# Visualized as a timeline/strip plot by week: one point per upset game, x = week, y = underdog
# team (ordered by total upset count), size/color = upset magnitude (0.5 - team_win_prob), with
# the underdog's logo marking each point.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR, which points at the main repo checkout and
# is NOT overridden by this script's own setwd() below. CACHE_SCHEDULES/CACHE_FATIGUE_METRICS
# (read via get_elo_history()) therefore still correctly resolve to the main repo's cache (a
# shared, read-only, real-data input - exactly what this task is allowed to read), while this
# script's own GIF/frame OUTPUT is written under WORKTREE_CACHE_DIR instead, so it lands inside
# this worktree's own cache/ rather than silently writing into the main repo's cache/ - same
# pattern as tools/gif_point_diff_race.R / tools/gif_epa_quadrant_scatter.R.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_upset_timeline.R"
# ==============================================================================

WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(nflplotR)
  library(magick)
  library(knitr)
})

source("config.R")
source("tools/elo_history_data.R")

# ---- Shared dark theme (copied verbatim from docs/week5_elo_analysis.qmd) ----
bg_dark     <- "#1e2228"
panel_dark  <- "#262b33"
grid_dark   <- "#3a4049"
text_light  <- "#d8dee5"

theme_elo_dark <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.background  = element_rect(fill = bg_dark, color = NA),
      panel.background = element_rect(fill = panel_dark, color = NA),
      legend.background = element_rect(fill = bg_dark, color = NA),
      legend.key        = element_rect(fill = panel_dark, color = NA),
      strip.background  = element_rect(fill = panel_dark, color = NA),
      panel.grid.major  = element_line(color = grid_dark),
      panel.grid.minor  = element_blank(),
      text              = element_text(color = text_light),
      axis.text         = element_text(color = text_light),
      strip.text        = element_text(color = text_light, face = "bold"),
      plot.title        = element_text(color = text_light)
    )
}

# ---- Data: get_elo_history() through the latest completed week (same as the qmd's default) ----
result <- get_elo_history()
long_games <- result$long_games

# ---- Upset detection - VERBATIM from docs/week5_elo_analysis.qmd's tbl-upsets chunk ----
upsets <- long_games |>
  filter(team_win == 1, team_win_prob < 0.5) |>
  transmute(week, underdog = team, favorite = opp,
            underdog_win_prob = round(team_win_prob, 3),
            underdog_elo = round(team_elo_pre, 0),
            favorite_elo = round(opp_elo_pre, 0),
            upset_magnitude = round(0.5 - team_win_prob, 3)) |>
  arrange(desc(upset_magnitude))

cat("Upsets detected (verbatim tbl-upsets logic):\n")
print(kable(upsets))

if (nrow(upsets) == 0) {
  stop("No upsets detected through the latest completed week - nothing to animate.")
}

max_week <- max(long_games$week)

# Order underdog teams by total upset count (most upset-prone at top) for a stable y-axis.
team_order <- upsets |> count(underdog, sort = TRUE) |> pull(underdog)
upsets <- upsets |> mutate(underdog = factor(underdog, levels = rev(team_order)))

frame_dir <- file.path(WORKTREE_CACHE_DIR, "upset_timeline_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in 1:max_week) {
  cur <- upsets |> filter(week <= w)

  p_frame <- ggplot(cur, aes(x = week, y = underdog)) +
    geom_point(aes(size = upset_magnitude, color = upset_magnitude), alpha = 0.85) +
    geom_nfl_logos(aes(team_abbr = as.character(underdog)), width = 0.035) +
    scale_size_continuous(range = c(4, 12), limits = c(0, max(upsets$upset_magnitude))) +
    scale_color_viridis_c(option = "plasma", limits = c(0, max(upsets$upset_magnitude))) +
    scale_x_continuous(breaks = 1:max_week, limits = c(0.5, max_week + 0.5)) +
    theme_elo_dark() +
    theme(legend.position = "right") +
    labs(x = "Week", y = NULL, size = "Upset magnitude", color = "Upset magnitude",
         title = sprintf("Upset timeline through Week %d, %d", w, CURRENT_SEASON),
         subtitle = "Underdog won despite pre-game Elo win probability below 50%")

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_upset_timeline.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Cross-check: full upsets table used here vs. the qmd's tbl-upsets logic - same games ----
cat(sprintf("\nCross-check: %d total upsets detected through Week %d (same filter as qmd's tbl-upsets).\n",
            nrow(upsets), max_week))
