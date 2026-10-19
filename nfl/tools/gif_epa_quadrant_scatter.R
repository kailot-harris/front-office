# ==============================================================================
# EPA Quadrant Scatter - Animated GIF (NFL)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/gif_epa_quadrant_scatter.R
#
# Closes GitHub issue #29. Phase 9 (docs/task_assignments_phase8.md, task P9-E), Wave 1 - no
# dependency on the Elo infra work, reads only CACHE_EPA_METRICS (already has rolling
# per-team-per-game off_epa_per_play_roll / def_epa_per_play_allowed_roll - see
# epa_metrics_engine.R). One-off visualization utility, not part of run_full_pipeline.R's DAG
# (per CLAUDE.md's Folder layout section, tools/ scripts are not DAG stages and run top-level),
# so this file is read-run end to end, not invoked via a run_full_pipeline.R-style callable.
#
# Classic "quadrant" chart: offensive EPA/play (x) vs. defensive EPA/play allowed (y), one frame
# per week of CURRENT_SEASON, animated. Quadrant reference lines are the CURRENT FRAME's live
# cross-team average (mean of the x/y values of every team actually plotted in that frame) -
# per this repo's CLAUDE.md "Constants convention" (never hardcode a derived constant / never
# re-type a modeling literal at a call site), these lines are recomputed fresh every frame from
# the data that frame reflects, NOT a single value borrowed from a later frame or a prior season.
# This also means the lines are expected to shift frame-to-frame as the season's sample grows -
# that is intentional, not a bug to "stabilize".
#
# Partial-window / short-history handling: epa_metrics_engine.R's .roll_mean_trailing() already
# documents (see that file's header + inline comment above .roll_mean_trailing()) that a team's
# very first (ROLLING_WINDOW_SIZE - 1) games in its ENTIRE pbp history get a shrunk window rather
# than NA/error, and that CURRENT_SEASON's early games borrow trailing games from the end of the
# PRIOR season rather than resetting at the season boundary. Live-checked against the real
# CACHE_EPA_METRICS below (see the diagnostic block right after the cache is loaded): every one
# of the 32 current-season teams already has games_in_window == ROLLING_WINDOW_SIZE by
# CURRENT_SEASON's week 1 (they all have 2025-season trailing games to borrow from), so in
# practice no CURRENT_SEASON team is ever dropped or shown as a partial-window outlier this
# season - but the script still computes and prints a per-frame diagnostic of any team whose
# games_in_window < ROLLING_WINDOW_SIZE (would only occur for a true expansion-team-style case
# with zero prior-season history) rather than silently assuming the current season is always
# full-window, and keeps any such team ON the chart rather than dropping it.
#
# Dark theme: theme_elo_dark() + the bg_dark/panel_dark/grid_dark/text_light palette are copied
# verbatim from docs/week5_elo_analysis.qmd (same colors, same ggplot theme object) for visual
# consistency with the existing cache/elo_scatter_animation.gif. Frame-join-to-GIF mechanics
# (per-week ggsave() PNG frames joined via magick::image_animate(), final frame held a few extra
# ticks) are the same pattern as that .qmd's "Animated: Team Strength vs. Schedule Strength"
# section.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\tools\gif_epa_quadrant_scatter.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
# ==============================================================================

# NOTE: this agent's work is isolated to the git worktree at WORKTREE_DIR below, unlike every
# sibling tools/*.R script's hardcoded PROJECT_DIR (which points at the main repo checkout).
# source("config.R") below re-hardcodes its own PROJECT_DIR/CACHE_DIR to the main repo path
# (config.R:22-23) regardless of our setwd() - WORKTREE_CACHE_DIR is therefore tracked
# separately so this script's own output GIF/frames land inside the worktree (not silently
# written into the main repo's cache/), while every READ of an existing CACHE_* path (here,
# CACHE_EPA_METRICS) still correctly resolves to config.R's main-repo path (that input cache is
# shared, read-only, real data - not something this task regenerates). Same pattern as
# tools/derive_min_sample_games_for_stake.R's own WORKTREE_DIR handling.
WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a3bf5020eee07ccdb"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(nflplotR)
  library(magick)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_epa_quadrant_scatter.R"

if (!file.exists(CACHE_EPA_METRICS)) {
  stop("CACHE_EPA_METRICS does not exist - run run_epa_metrics() (epa_metrics_engine.R) first.")
}

# ---- Dark theme, copied verbatim from docs/week5_elo_analysis.qmd (see header comment) ----
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

epa <- readRDS(CACHE_EPA_METRICS)

cur_season_epa <- epa |>
  filter(season == CURRENT_SEASON) |>
  arrange(team, game_date, week)

if (nrow(cur_season_epa) == 0) {
  stop(sprintf("No CACHE_EPA_METRICS rows for CURRENT_SEASON (%d).", CURRENT_SEASON))
}

# ---- Partial-window diagnostic (see header comment) - never silently drop a short-history team.
short_window_rows <- cur_season_epa |> filter(games_in_window < ROLLING_WINDOW_SIZE)
if (nrow(short_window_rows) > 0) {
  log_warn(sprintf(
    "%d CURRENT_SEASON team-game rows have games_in_window < ROLLING_WINDOW_SIZE (%d); teams: %s. Kept on chart, not dropped (per epa_metrics_engine.R's documented partial-window fallback).",
    nrow(short_window_rows), ROLLING_WINDOW_SIZE,
    paste(unique(short_window_rows$team), collapse = ", ")
  ), call = "gif_epa_quadrant_scatter.R")
} else {
  log_info(sprintf(
    "No CURRENT_SEASON team-game rows with games_in_window < ROLLING_WINDOW_SIZE (%d) - every current-season team already has a full trailing window (borrowed from prior-season games per epa_metrics_engine.R's documented fallback).",
    ROLLING_WINDOW_SIZE
  ), call = "gif_epa_quadrant_scatter.R")
}

max_week <- max(cur_season_epa$week)
week_seq <- sort(unique(cur_season_epa$week))

# ---- Per-frame snapshot: for week w, each team's MOST RECENT played game at or before week w
# (handles byes - a team's chart position doesn't vanish/reset just because it didn't play in
# week w itself, it holds its last known rolling value, same "fill forward" idea as the Elo
# trajectory chart in docs/week5_elo_analysis.qmd).
snap_all <- bind_rows(lapply(week_seq, function(w) {
  cur_season_epa |>
    filter(week <= w) |>
    group_by(team) |>
    slice_max(game_date, n = 1, with_ties = FALSE) |>
    ungroup() |>
    transmute(team, off_epa_roll = off_epa_per_play_roll,
              def_epa_roll = def_epa_per_play_allowed_roll, frame_week = w)
}))

# Fixed axis limits across all frames (full-season range) so the animation doesn't jitter the
# plot box frame-to-frame - computed live from the data itself, not a hardcoded literal.
xr <- range(snap_all$off_epa_roll, na.rm = TRUE)
yr <- range(snap_all$def_epa_roll, na.rm = TRUE)
pad_x <- diff(xr) * 0.12
pad_y <- diff(yr) * 0.12
anim_xlim <- xr + c(-pad_x, pad_x)
anim_ylim <- yr + c(-pad_y, pad_y)

frame_dir <- file.path(WORKTREE_CACHE_DIR, "epa_quadrant_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  frame_df <- snap_all |> filter(frame_week == w)

  # Live per-frame league-average reference lines (see header comment - never hardcoded, never
  # borrowed from a different frame/season).
  avg_off <- mean(frame_df$off_epa_roll, na.rm = TRUE)
  avg_def <- mean(frame_df$def_epa_roll, na.rm = TRUE)

  p_frame <- ggplot(frame_df, aes(x = off_epa_roll, y = def_epa_roll)) +
    geom_vline(xintercept = avg_off, linetype = "dashed", color = "grey60") +
    geom_hline(yintercept = avg_def, linetype = "dashed", color = "grey60") +
    geom_nfl_logos(aes(team_abbr = team), width = 0.05) +
    coord_cartesian(xlim = anim_xlim, ylim = anim_ylim) +
    # y-axis is EPA/play ALLOWED - flip it so "up" visually means "better defense" (lower EPA
    # allowed), matching the usual quadrant-chart convention (top-right = good offense + good
    # defense) rather than leaving it in raw ascending-allowed-EPA order.
    scale_y_reverse() +
    theme_elo_dark() +
    labs(
      x = "Offensive EPA/play (rolling)",
      y = "Defensive EPA/play allowed (rolling) - reversed, up = better defense",
      title = sprintf("EPA Quadrant - Through Week %d, %d", w, CURRENT_SEASON),
      subtitle = sprintf("Dashed lines = this frame's live league-average (off %.3f, def-allowed %.3f)",
                          avg_off, avg_def)
    )

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 9, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final (current) frame a few extra ticks so the GIF doesn't loop too fast - same
# pattern as docs/week5_elo_analysis.qmd's scatter animation.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_epa_quadrant_scatter.gif")
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated EPA quadrant scatter GIF to %s (%d frames + hold).", gif_path, length(week_seq)),
         call = "gif_epa_quadrant_scatter.R", out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))
