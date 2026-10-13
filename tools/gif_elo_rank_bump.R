# ==============================================================================
# GIF: Elo Rank Bump Chart (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_elo_rank_bump.R
#
# Closes GitHub issue #20 (Phase 9 / docs/task_assignments_phase8.md task P9-F). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_point_diff_race.R / tools/gif_division_standings_race.R /
# tools/gif_epa_net_race.R). Reads tools/elo_history_data.R's get_elo_history() output only
# (which itself reads CACHE_SCHEDULES / CACHE_FATIGUE_METRICS, read-only); writes nothing back
# to any cache file other than this script's own output GIF.
#
# Converts each team's weekly Elo RATING into a weekly RANK (rank(-elo), 1 = highest Elo that
# week) from get_elo_history()$trajectory, then animates a "bump chart" line race: one line per
# team, x = week, y = rank (axis reversed so rank 1 sits at the top), color = division, with
# nflplotR::geom_nfl_logos() marking each team's current-frame position. Each animation frame
# cumulatively reveals weeks 1..w (the line race "grows" rightward week by week) rather than
# jump-cutting between independent per-week snapshots, so the bump chart's characteristic
# crossing lines are visible as motion, not just a static end-state.
#
# trajectory's rows come from get_elo_history() per the Interface Contract (docs/
# task_assignments_phase8.md): team/week/elo (pre-game Elo for weeks a team played, plus one
# final synthetic week = max(long_games$week) + 1 holding each team's current_elo). A team on a
# bye in week w has NO trajectory row for week w (its rating simply didn't change that week), so
# a naive per-week join would show gaps instead of a flat/held rank. Fixed below via a complete
# team x week grid + tidyr::fill(.direction = "down") per team - same bye-week-carries-forward
# pattern tools/gif_division_standings_race.R already uses for cumulative wins.
#
# Dark theme: theme_elo_dark() + bg_dark/panel_dark/grid_dark/text_light + division_colors,
# copied verbatim from docs/week5_elo_analysis.qmd (per this task's brief), for visual
# consistency with the existing cache/elo_scatter_animation.gif and the other Phase 9 GIFs.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\.claude\worktrees\agent-a9109db7db5e8351c\tools\gif_elo_rank_bump.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
# ==============================================================================

# NOTE ON WORKTREE ISOLATION: config.R's PROJECT_DIR/CACHE_DIR are hardcoded to the main repo
# checkout (config.R:20-21ish) and are NOT overridden by this script's own setwd() below - so
# every CACHE_* read (via get_elo_history() -> CACHE_SCHEDULES / CACHE_FATIGUE_METRICS) still
# correctly resolves to the main repo's shared, read-only cache. This script's own GIF/frame
# OUTPUT, however, is written under WORKTREE_CACHE_DIR so it lands inside THIS worktree's cache/
# rather than silently writing into the main repo's cache/ - same pattern as every other Phase 9
# gif_*.R script (e.g. tools/gif_epa_net_race.R, tools/gif_division_standings_race.R).
WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a9109db7db5e8351c"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(nflplotR)
  library(magick)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_elo_rank_bump.R"
source("tools/elo_history_data.R")

# ---- Shared dark theme + division colors (copied verbatim from docs/week5_elo_analysis.qmd) ----
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

division_colors <- c(
  "AFC East" = "#0D3B5C", "AFC North" = "#115677", "AFC South" = "#15708D", "AFC West" = "#198595",
  "NFC East" = "#219A9B", "NFC North" = "#2CB0A1", "NFC South" = "#3CC1A7", "NFC West" = "#4FD1AE"
)

# ---- Data: get_elo_history() through the latest completed week (max_week = NULL default) ----
hist <- get_elo_history()
trajectory <- hist$trajectory

if (nrow(trajectory) == 0) {
  stop("get_elo_history()$trajectory is empty - nothing to animate.")
}

last_real_week <- max(hist$long_games$week)
current_pseudo_week <- last_real_week + 1L  # trajectory's synthetic "current rating" row
all_weeks <- sort(unique(trajectory$week))
teams <- sort(unique(trajectory$team))
n_teams <- length(teams)

# ---- Fill bye-week gaps: complete team x week grid, carry last known Elo/division forward ----
grid_tw <- expand_grid(team = teams, week = all_weeks)
filled <- grid_tw |>
  left_join(trajectory |> select(team, week, elo, division), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(elo, division, .direction = "down") |>
  ungroup()

missing_after_fill <- filled |> filter(is.na(elo))
if (nrow(missing_after_fill) > 0) {
  log_warn(sprintf(
    "%d team-week rows still NA after down-fill (team missing from week 1 onward) - these teams: %s. Dropped from the race rather than guessed.",
    nrow(missing_after_fill), paste(unique(missing_after_fill$team), collapse = ", ")
  ), call = .LOG_SCRIPT)
  filled <- filled |> filter(!is.na(elo))
}

# ---- Rank per week: rank(-elo), 1 = highest Elo that week (per success criterion 1) ----
ranked <- filled |>
  group_by(week) |>
  mutate(rank = rank(-elo)) |>
  ungroup()

week_labels <- ifelse(all_weeks >= current_pseudo_week, "Current", as.character(all_weeks))

frame_dir <- file.path(WORKTREE_CACHE_DIR, "elo_rank_bump_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  frame_lines <- ranked |> filter(week <= w)
  frame_pts   <- ranked |> filter(week == w)

  p_frame <- ggplot(frame_lines, aes(x = week, y = rank, group = team, color = division)) +
    geom_line(linewidth = 0.8, alpha = 0.85, show.legend = FALSE) +
    geom_nfl_logos(data = frame_pts, aes(team_abbr = team, x = week, y = rank),
                    width = 0.028, inherit.aes = FALSE) +
    scale_y_reverse(breaks = 1:n_teams) +
    scale_x_continuous(breaks = all_weeks, labels = week_labels) +
    scale_color_manual(values = division_colors) +
    coord_cartesian(xlim = range(all_weeks) + c(-0.3, 0.3)) +
    theme_elo_dark() +
    labs(
      x = "Week", y = "Elo rank (1 = highest)",
      title = sprintf("Elo Rank Bump Chart - Through %s, %d",
                       ifelse(w >= current_pseudo_week, "Current", sprintf("Week %d", w)),
                       CURRENT_SEASON)
    )

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 9, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_elo_rank_bump.gif")
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated Elo rank bump chart GIF to %s (%d frames + hold).", gif_path, length(all_weeks)),
         call = .LOG_SCRIPT, out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Sanity check (success criterion 3): final-frame rank order vs current_ratings sorted by
# current_elo descending (rank 1 = highest Elo). ----
final_frame_order <- ranked |> filter(week == max(all_weeks)) |> arrange(rank) |> pull(team)
current_ratings_order <- hist$current_ratings |> arrange(desc(current_elo)) |> pull(team)
# current_ratings may include teams trajectory's !is.na(division) filter already excludes
# consistently (both pipelines filter via NFL_DIVISIONS), so these two vectors should match
# exactly in both membership and order.
common_teams <- intersect(final_frame_order, current_ratings_order)
match_result <- isTRUE(all(
  final_frame_order[final_frame_order %in% common_teams] ==
    current_ratings_order[current_ratings_order %in% common_teams]
))

cat("\nSanity check - final-frame rank order vs current_ratings sorted by current_elo desc:\n")
cat(sprintf("  n teams compared: %d\n", length(common_teams)))
cat(sprintf("  orders match: %s\n", match_result))
if (!match_result) {
  cat("  final_frame_order: ", paste(final_frame_order, collapse = ", "), "\n")
  cat("  current_ratings_order: ", paste(current_ratings_order, collapse = ", "), "\n")
}
