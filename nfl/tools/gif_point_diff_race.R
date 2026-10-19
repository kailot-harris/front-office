# ==============================================================================
# GIF: Cumulative Point-Differential Race (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_point_diff_race.R
#
# Closes GitHub issue #24 (Phase 9 / docs/task_assignments_phase8.md task P9-D). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/weekly_accuracy_report.R / tools/plot_week5_projections.R). Reads
# CACHE_SCHEDULES only (read-only); writes nothing back to that cache or any other cache file.
#
# Builds an animated line race of each NFL_TEAMS team's cumulative point differential
# (points-for minus points-against) by week, for CURRENT_SEASON's completed REGULAR-SEASON
# games only (game_type == "REG" - excludes any future playoff games from the season-long
# differential; CURRENT_SEASON has no playoff games yet as of this script's creation in any
# case, so this filter is a no-op today but keeps the script correct once playoffs begin).
# Reuses docs/week5_elo_analysis.qmd's theme_elo_dark() dark theme (copied verbatim below, per
# this task's brief) and nflplotR::geom_nfl_logos() for team identity, plus the same
# ggsave-per-frame + magick::image_animate() GIF-assembly approach that script already uses for
# cache/elo_scatter_animation.gif, for visual consistency across both GIFs.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below (per this task's dispatch instructions), unlike config.R's own hardcoded PROJECT_DIR
# (config.R:20-21), which points at the main repo checkout and is NOT overridden by this
# script's own setwd() below. CACHE_SCHEDULES therefore still correctly resolves to the main
# repo's cache (a shared, read-only, real-data input - exactly what this task is allowed to
# read), while this script's own GIF/frame OUTPUT is written under WORKTREE_CACHE_DIR instead,
# so it lands inside this worktree's own cache/ rather than silently writing into the main
# repo's cache/ - same pattern as tools/derive_min_sample_games_for_stake.R.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_point_diff_race.R"
# ==============================================================================

WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a2db751154571a815"
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

division_colors <- c(
  "AFC East" = "#0D3B5C", "AFC North" = "#115677", "AFC South" = "#15708D", "AFC West" = "#198595",
  "NFC East" = "#219A9B", "NFC North" = "#2CB0A1", "NFC South" = "#3CC1A7", "NFC West" = "#4FD1AE"
)

# ---- Data: cumulative point differential by week, CURRENT_SEASON, completed REG games ----
sch <- readRDS(CACHE_SCHEDULES)

completed <- sch |>
  filter(season == CURRENT_SEASON, game_type == "REG", !is.na(home_score), !is.na(away_score))

if (nrow(completed) == 0) {
  stop("No completed CURRENT_SEASON REG games found in CACHE_SCHEDULES - nothing to animate.")
}

long_diff <- bind_rows(
  completed |> transmute(team = home_team, week, diff = home_score - away_score),
  completed |> transmute(team = away_team, week, diff = away_score - home_score)
) |>
  filter(team %in% names(NFL_TEAMS))

cum_diff <- long_diff |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(cum_pd = cumsum(diff)) |>
  ungroup()

max_week  <- max(cum_diff$week)
all_weeks <- sort(unique(cum_diff$week))

# Fill a complete team x week grid so bye weeks carry forward the team's last known cumulative
# value (a flat line segment) instead of a gap; teams with no games yet (shouldn't happen once
# the season starts, but kept defensive) get 0.
grid_tw <- expand_grid(team = names(NFL_TEAMS), week = all_weeks)
cum_filled <- grid_tw |>
  left_join(cum_diff |> select(team, week, cum_pd), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(cum_pd, .direction = "down") |>
  ungroup() |>
  mutate(cum_pd = tidyr::replace_na(cum_pd, 0),
         division = NFL_DIVISIONS[team])

yr <- range(cum_filled$cum_pd, na.rm = TRUE)
pad_y <- max(diff(yr) * 0.08, 5)
anim_ylim <- yr + c(-pad_y, pad_y)

frame_dir <- file.path(WORKTREE_CACHE_DIR, "point_diff_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  lines_df <- cum_filled |> filter(week <= w)
  tips_df  <- cum_filled |> filter(week == w)

  p_frame <- ggplot(lines_df, aes(x = week, y = cum_pd, group = team, color = division)) +
    geom_line(linewidth = 0.6, alpha = 0.85, show.legend = FALSE) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
    geom_nfl_logos(data = tips_df, aes(x = week, y = cum_pd, team_abbr = team), width = 0.045) +
    scale_color_manual(values = division_colors) +
    scale_x_continuous(breaks = all_weeks, limits = range(all_weeks)) +
    coord_cartesian(ylim = anim_ylim) +
    theme_elo_dark() +
    labs(x = "Week", y = "Cumulative point differential (PF \u2212 PA)",
         title = sprintf("Cumulative point differential through Week %d, %d", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_point_diff_race.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Sanity check: final-frame cumulative PD vs. a direct CACHE_SCHEDULES computation ----
# (success criterion 3 - "ad-hoc numeric comparison" against 2-3 teams)
final_frame <- cum_filled |> filter(week == max_week) |> arrange(desc(cum_pd))
check_teams <- c(head(final_frame$team, 1), final_frame$team[ceiling(nrow(final_frame) / 2)], tail(final_frame$team, 1))

cat("\nSanity check - animated final-week cumulative PD vs. direct recomputation from CACHE_SCHEDULES:\n")
for (tm in check_teams) {
  direct_pf <- sum(completed$home_score[completed$home_team == tm]) + sum(completed$away_score[completed$away_team == tm])
  direct_pa <- sum(completed$away_score[completed$home_team == tm]) + sum(completed$home_score[completed$away_team == tm])
  direct_pd <- direct_pf - direct_pa
  anim_pd   <- final_frame$cum_pd[final_frame$team == tm]
  cat(sprintf("  %s: animated=%d  direct=%d  match=%s\n", tm, anim_pd, direct_pd, isTRUE(anim_pd == direct_pd)))
}
