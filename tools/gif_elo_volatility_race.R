# ==============================================================================
# GIF: Elo Volatility Bar Race (rolling std-dev of weekly Elo change)
# Path: tools/gif_elo_volatility_race.R
#
# Closes GitHub issue #23 (Phase 9 / docs/task_assignments_phase8.md task P9-G). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_elo_delta_race.R / tools/gif_point_diff_race.R). Reads tools/
# elo_history_data.R's get_elo_history()$trajectory only (read-only); writes nothing back to
# any cache file except this script's own output GIF.
#
# Distinct from tools/gif_elo_delta_race.R (#22): that script plots the single-step delta
# (direction/magnitude of the LATEST week-over-week Elo change only). This script plots the
# ROLLING standard deviation of that same per-team delta series, cumulative through each
# frame's week W - i.e. at week W, sd() of every delta the team has recorded from week 1
# through W - a "boom/bust" volatility proxy, not a restatement of the delta race.
#
# A team needs >= 2 delta observations (i.e. >= 3 played-week Elo points) for sd() to be a real
# number; R's own sd() of a single value is NA, and that NA is preserved here deliberately -
# per issue #23's explicit scope, a team with < 2 delta observations must show a genuine
# NA/missing bar, never a silently-coerced 0 (a 0 bar would misleadingly read as "this team has
# zero volatility" rather than "not enough history yet to say"). Frames simply omit a team's bar
# until its rolling sd becomes defined.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR (config.R:22), which points at the main
# repo checkout and is NOT overridden by this script's own setwd(). CACHE_SCHEDULES /
# CACHE_FATIGUE_METRICS (read via get_elo_history()) therefore still correctly resolve to the
# shared main-repo cache (read-only, real-data input), while this script's own GIF/frame OUTPUT
# is written under WORKTREE_CACHE_DIR so it lands inside this worktree's own cache/, not the
# shared main-repo one. Same pattern as tools/gif_elo_delta_race.R / tools/gif_epa_net_race.R.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\.claude\worktrees\agent-a71af4f0d8862dce5\tools\gif_elo_volatility_race.R"
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
.LOG_SCRIPT <- "gif_elo_volatility_race.R"
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

# ---- Same single-step delta as tools/gif_elo_delta_race.R (#22), computed independently here
# rather than imported, since the two scripts are intentionally decoupled call sites (brief's
# out-of-scope note: do not conflate #22 and #23 into one shared computation). ----
deltas <- trajectory |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(delta = elo - lag(elo)) |>
  ungroup()

# ---- Cumulative (expanding-window) rolling sd of delta, per team, through each delta's own
# week - built on the non-NA delta observations only (week 1 has no delta at all - excluded
# before the expanding window even starts, not fed in as a 0). The first delta observation per
# team yields n_obs = 1 -> sd() of a single value is NA (R's own semantics, preserved
# deliberately); the second delta observation (n_obs = 2) is the first week sd() becomes a real
# number. ----
roll_vol <- deltas |>
  filter(!is.na(delta)) |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(
    n_obs = row_number(),
    roll_sd = sapply(seq_len(n()), function(i) {
      if (i < 2) NA_real_ else sd(delta[seq_len(i)])
    })
  ) |>
  ungroup()

week_seq <- sort(unique(deltas$week))
n_teams  <- length(unique(deltas$team))

# Fixed x-axis (roll_sd) limits across all frames, computed from the real non-NA values only.
xr <- range(roll_vol$roll_sd, na.rm = TRUE)
if (!is.finite(xr[1])) {
  stop("No team ever reaches 2 delta observations - no rolling sd defined anywhere; cannot animate.")
}
pad_x <- max(diff(xr) * 0.15, 1e-6)
anim_xlim <- c(0, xr[2] + pad_x * 3)  # sd is non-negative; extra right-side pad for team logos

frame_dir <- file.path(WORKTREE_CACHE_DIR, "elo_volatility_race_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  # Per team, latest roll_sd value at or before this frame's week (carries forward across byes,
  # same pattern as tools/gif_epa_net_race.R's slice_max fill-forward). Teams with no row at all
  # yet (roll_sd still undefined through week w) are not in this frame -> genuinely no bar, not
  # a 0 bar.
  frame_df <- roll_vol |>
    filter(week <= w, !is.na(roll_sd)) |>
    group_by(team) |>
    slice_max(week, n = 1, with_ties = FALSE) |>
    ungroup() |>
    arrange(desc(roll_sd)) |>
    mutate(rank = row_number())

  if (nrow(frame_df) == 0) next  # no team has reached 2 delta observations yet - skip frame

  p_frame <- ggplot(frame_df, aes(x = roll_sd, y = reorder(team, -rank))) +
    geom_col(fill = "#3CC1A7", width = 0.7) +
    geom_nfl_logos(aes(team_abbr = team), width = 0.035, x = frame_df$roll_sd + pad_x * 0.6) +
    coord_cartesian(xlim = anim_xlim) +
    theme_elo_dark() +
    theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank()) +
    labs(
      x = "Rolling std-dev of weekly Elo change (weeks 1..W, boom/bust proxy)",
      y = NULL,
      title = sprintf("Elo Volatility Race - Through Week %d, %d", w, CURRENT_SEASON),
      subtitle = sprintf("%d of %d teams have >=2 delta observations this frame (most volatile on top)",
                          nrow(frame_df), n_teams)
    )

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 8, height = 10, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

if (length(frame_files) == 0) {
  stop("No frames produced - no team ever reached 2 delta observations.")
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast - same pattern as
# docs/week5_elo_analysis.qmd's scatter animation / tools/gif_epa_net_race.R.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_elo_volatility_race.gif")
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated Elo volatility race GIF to %s (%d frames + hold).", gif_path, length(frame_files)),
         call = "gif_elo_volatility_race.R", out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Inspection: first week each team's volatility bar becomes defined (>=2 delta obs), plus
# the full computed volatility series for teams with the single largest-magnitude single-week
# delta (the "known early blowout-magnitude swing" check - success criterion 4) ----
first_defined <- roll_vol |>
  filter(!is.na(roll_sd)) |>
  group_by(team) |>
  summarise(first_defined_week = min(week), .groups = "drop") |>
  arrange(first_defined_week)

cat("\nFirst week each team's volatility bar becomes defined (>=2 delta observations):\n")
print(as.data.frame(head(first_defined, 10)))

biggest_swing_team <- deltas |> filter(!is.na(delta)) |> slice_max(abs(delta), n = 1, with_ties = FALSE) |> pull(team)
cat(sprintf("\nTeam with the single largest-magnitude weekly Elo delta this season: %s\n", biggest_swing_team))
cat("Its full delta / rolling-sd series:\n")
print(as.data.frame(
  roll_vol |> filter(team == biggest_swing_team) |> select(team, week, delta, n_obs, roll_sd)
))
