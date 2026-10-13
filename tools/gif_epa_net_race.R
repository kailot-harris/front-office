# ==============================================================================
# EPA Net Bar Race - Animated GIF (NFL)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/gif_epa_net_race.R
#
# Closes GitHub issue #30. Phase 9 (docs/task_assignments_phase8.md, task P9-E), Wave 1 - no
# dependency on the Elo infra work, reads only CACHE_EPA_METRICS (see epa_metrics_engine.R).
# One-off visualization utility, not part of run_full_pipeline.R's DAG (per CLAUDE.md's Folder
# layout section), so this file runs top-level end to end rather than exposing a run_stage()-
# style callable.
#
# Animated RANKED bar race of net_epa = off_epa_per_play_roll - def_epa_per_play_allowed_roll,
# one frame per week of CURRENT_SEASON. This is deliberately NOT team_ratings_engine.R's rating
# formula (net rating points) - per the task brief's explicit scope note, this chart visualizes
# raw rolling EPA/play directly; net_epa here is a simple difference of the two EPA metrics
# already produced by epa_metrics_engine.R, not a power rating. No modeling constant (e.g. a
# league-average literal) is needed for this chart at all - it's a straight ranking of net_epa,
# so there's nothing here to accidentally hardcode/duplicate from config.R.
#
# Partial-window / short-history handling: identical situation and identical fallback as
# tools/gif_epa_quadrant_scatter.R documents in its header comment (epa_metrics_engine.R's
# .roll_mean_trailing() borrows trailing games from the end of the PRIOR season for a team's
# early CURRENT_SEASON games, only truly shrinking the window for a team's first-ever games in
# its entire pbp history). Same diagnostic block as that script: logs (not drops) any
# CURRENT_SEASON team-game row with games_in_window < ROLLING_WINDOW_SIZE.
#
# Dark theme: theme_elo_dark() + the bg_dark/panel_dark/grid_dark/text_light palette copied
# verbatim from docs/week5_elo_analysis.qmd, same as tools/gif_epa_quadrant_scatter.R, for visual
# consistency with the existing cache/elo_scatter_animation.gif. Frame-join-to-GIF mechanics
# (per-week ggsave() PNG frames joined via magick::image_animate(), final frame held a few extra
# ticks) are the same pattern as that .qmd's scatter animation section.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\tools\gif_epa_net_race.R"
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
.LOG_SCRIPT <- "gif_epa_net_race.R"

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
  arrange(team, game_date, week) |>
  mutate(net_epa = off_epa_per_play_roll - def_epa_per_play_allowed_roll)

if (nrow(cur_season_epa) == 0) {
  stop(sprintf("No CACHE_EPA_METRICS rows for CURRENT_SEASON (%d).", CURRENT_SEASON))
}

# ---- Partial-window diagnostic (see header comment) - never silently drop a short-history team.
short_window_rows <- cur_season_epa |> filter(games_in_window < ROLLING_WINDOW_SIZE)
if (nrow(short_window_rows) > 0) {
  log_warn(sprintf(
    "%d CURRENT_SEASON team-game rows have games_in_window < ROLLING_WINDOW_SIZE (%d); teams: %s. Kept in the race, not dropped (per epa_metrics_engine.R's documented partial-window fallback).",
    nrow(short_window_rows), ROLLING_WINDOW_SIZE,
    paste(unique(short_window_rows$team), collapse = ", ")
  ), call = "gif_epa_net_race.R")
} else {
  log_info(sprintf(
    "No CURRENT_SEASON team-game rows with games_in_window < ROLLING_WINDOW_SIZE (%d) - every current-season team already has a full trailing window (borrowed from prior-season games per epa_metrics_engine.R's documented fallback).",
    ROLLING_WINDOW_SIZE
  ), call = "gif_epa_net_race.R")
}

max_week <- max(cur_season_epa$week)
week_seq <- sort(unique(cur_season_epa$week))
n_teams  <- length(unique(cur_season_epa$team))

# ---- Per-frame snapshot: for week w, each team's MOST RECENT played game at or before week w
# (fill-forward across byes, same approach as tools/gif_epa_quadrant_scatter.R), ranked by
# net_epa descending (rank 1 = best net EPA/play that frame).
snap_all <- bind_rows(lapply(week_seq, function(w) {
  cur_season_epa |>
    filter(week <= w) |>
    group_by(team) |>
    slice_max(game_date, n = 1, with_ties = FALSE) |>
    ungroup() |>
    transmute(team, net_epa, frame_week = w) |>
    arrange(desc(net_epa)) |>
    mutate(rank = row_number())
}))

# Fixed x-axis (net_epa) limits across all frames so the bars don't rescale jarringly frame to
# frame - computed live from the data itself.
xr <- range(snap_all$net_epa, na.rm = TRUE)
pad_x <- diff(xr) * 0.15
anim_xlim <- xr + c(-pad_x, pad_x * 3)  # extra right-side pad for team logos past the bar end

frame_dir <- file.path(WORKTREE_CACHE_DIR, "epa_net_race_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  frame_df <- snap_all |> filter(frame_week == w) |> arrange(rank)

  p_frame <- ggplot(frame_df, aes(x = net_epa, y = reorder(team, -rank))) +
    geom_col(aes(fill = net_epa >= 0), width = 0.7, show.legend = FALSE) +
    scale_fill_manual(values = c(`TRUE` = "#3CC1A7", `FALSE` = "#C1503C")) +
    geom_vline(xintercept = 0, color = "grey60", linewidth = 0.5) +
    geom_nfl_logos(aes(team_abbr = team), width = 0.035,
                    x = frame_df$net_epa + sign(frame_df$net_epa + 1e-9) * pad_x * 0.3) +
    coord_cartesian(xlim = anim_xlim) +
    theme_elo_dark() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    labs(
      x = "Net EPA/play (rolling offense - rolling defense allowed)",
      y = NULL,
      title = sprintf("Net EPA Race - Through Week %d, %d", w, CURRENT_SEASON),
      subtitle = sprintf("Ranked 1-%d, best net EPA/play on top", n_teams)
    )

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 8, height = 10, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final (current) frame a few extra ticks so the GIF doesn't loop too fast - same
# pattern as docs/week5_elo_analysis.qmd's scatter animation.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_epa_net_race.gif")
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated EPA net race GIF to %s (%d frames + hold).", gif_path, length(week_seq)),
         call = "gif_epa_net_race.R", out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))
