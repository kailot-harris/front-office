# ==============================================================================
# GIF: Elo Week-Over-Week Delta Bar Race
# Path: tools/gif_elo_delta_race.R
#
# Closes GitHub issue #22 (Phase 9 / docs/task_assignments_phase8.md task P9-G). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_point_diff_race.R / tools/gif_epa_net_race.R). Reads tools/
# elo_history_data.R's get_elo_history()$trajectory only (which itself reads CACHE_SCHEDULES /
# CACHE_FATIGUE_METRICS, read-only); writes nothing back to any cache file except this script's
# own output GIF.
#
# Animated horizontal bar race of each team's SINGLE-STEP Elo CHANGE from the immediately prior
# week (delta = elo - lag(elo), per team, ordered by week) - NOT cumulative/rolling, and NOT the
# same computation as tools/gif_elo_volatility_race.R (#23), which instead plots the rolling
# standard deviation of these same per-team deltas. Re-sorted (ranked) each frame, signed color
# (gain vs. loss), same dark theme + nflplotR::geom_nfl_logos() team-identity pattern as
# cache/elo_scatter_animation.gif and tools/gif_epa_net_race.R for visual consistency.
#
# trajectory's rows are PRE-GAME Elo per week played, plus one final "current rating" point at
# week = max(played week) + 1 (see tools/elo_history_data.R's header comment). A team's delta at
# that final point is therefore last-pregame-rating -> current-rating, i.e. the Elo movement
# from its most recent game result - still a legitimate single-step delta, not a lookahead.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR (config.R:22), which points at the main
# repo checkout and is NOT overridden by this script's own setwd(). CACHE_SCHEDULES /
# CACHE_FATIGUE_METRICS (read via get_elo_history()) therefore still correctly resolve to the
# shared main-repo cache (read-only, real-data input), while this script's own GIF/frame OUTPUT
# is written under WORKTREE_CACHE_DIR so it lands inside this worktree's own cache/, not the
# shared main-repo one. Same pattern as tools/gif_point_diff_race.R / tools/gif_epa_net_race.R.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\.claude\worktrees\agent-a71af4f0d8862dce5\tools\gif_elo_delta_race.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
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
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_elo_delta_race.R"
source("tools/elo_history_data.R")

# ---- Dark theme, copied verbatim from docs/week5_elo_analysis.qmd (see CLAUDE.md / brief) ----
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

result     <- get_elo_history()
trajectory <- result$trajectory

if (nrow(trajectory) == 0) {
  stop("get_elo_history()$trajectory is empty - nothing to animate.")
}

# ---- Single-step delta: elo - lag(elo), per team, ordered by week. ----
# NOT cumulative/rolling - this is the raw week-to-week change only (issue #22's explicit
# scope). A team's first played week has no prior week, so its delta is genuinely NA (dropped
# from that frame's bars, not coerced to 0 - same "don't silently zero-fill" discipline #23
# requires explicitly, applied here too since lag() produces a real NA for week 1).
deltas <- trajectory |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(delta = elo - lag(elo)) |>
  ungroup()

week_seq <- sort(unique(deltas$week))
n_teams  <- length(unique(deltas$team))

# Fixed x-axis (delta) limits across all frames, computed from the real non-NA deltas only.
xr <- range(deltas$delta, na.rm = TRUE)
pad_x <- diff(xr) * 0.15
anim_xlim <- xr + c(-pad_x, pad_x * 3)  # extra right-side pad for team logos past the bar end

frame_dir <- file.path(WORKTREE_CACHE_DIR, "elo_delta_race_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  frame_df <- deltas |>
    filter(week == w, !is.na(delta)) |>
    arrange(desc(delta)) |>
    mutate(rank = row_number())

  if (nrow(frame_df) == 0) next  # week 1 (every team's delta is NA) - no bars to draw, skip frame

  p_frame <- ggplot(frame_df, aes(x = delta, y = reorder(team, -rank))) +
    geom_col(aes(fill = delta >= 0), width = 0.7, show.legend = FALSE) +
    scale_fill_manual(values = c(`TRUE` = "#3CC1A7", `FALSE` = "#C1503C")) +
    geom_vline(xintercept = 0, color = "grey60", linewidth = 0.5) +
    geom_nfl_logos(aes(team_abbr = team), width = 0.035,
                    x = frame_df$delta + sign(frame_df$delta + 1e-9) * pad_x * 0.3) +
    coord_cartesian(xlim = anim_xlim) +
    theme_elo_dark() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    labs(
      x = "Elo change vs. prior week (pre-game rating; final point = current rating)",
      y = NULL,
      title = sprintf("Elo Delta Race - Week %d, %d", w, CURRENT_SEASON),
      subtitle = sprintf("Ranked 1-%d, biggest single-week gain on top", nrow(frame_df))
    )

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 8, height = 10, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

if (length(frame_files) == 0) {
  stop("No frames produced - every team's delta was NA in every week.")
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast - same pattern as
# docs/week5_elo_analysis.qmd's scatter animation / tools/gif_epa_net_race.R.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_elo_delta_race.gif")
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated Elo delta race GIF to %s (%d frames + hold).", gif_path, length(frame_files)),
         call = "gif_elo_delta_race.R", out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Sanity check: plotted delta vs. manual trajectory arithmetic, 2-3 spot-check teams, one
# specific week (success criterion 3). Pick the last fully-populated week and 3 teams spanning
# the rank range that week.
check_week <- tail(week_seq, 1)
check_frame <- deltas |> filter(week == check_week, !is.na(delta)) |> arrange(desc(delta))
check_teams <- unique(c(head(check_frame$team, 1),
                        check_frame$team[ceiling(nrow(check_frame) / 2)],
                        tail(check_frame$team, 1)))

cat(sprintf("\nSanity check - plotted delta vs. manual trajectory arithmetic, week %d:\n", check_week))
for (tm in check_teams) {
  traj_tm <- trajectory |> filter(team == tm) |> arrange(week)
  cur_elo  <- traj_tm$elo[traj_tm$week == check_week]
  prior_wk <- max(traj_tm$week[traj_tm$week < check_week])
  prior_elo <- traj_tm$elo[traj_tm$week == prior_wk]
  manual_delta <- cur_elo - prior_elo
  plotted_delta <- check_frame$delta[check_frame$team == tm]
  cat(sprintf("  %s: week %d elo=%.2f, week %d elo=%.2f, manual_delta=%.4f, plotted_delta=%.4f, match=%s\n",
              tm, prior_wk, prior_elo, check_week, cur_elo, manual_delta, plotted_delta,
              isTRUE(all.equal(manual_delta, plotted_delta))))
}
