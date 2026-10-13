# ==============================================================================
# GIF: Turnover Margin Cumulative Race (Weeks 1..5, turnover history)
# Path: tools/gif_turnover_margin_race.R
#
# Closes GitHub issue #33 (Phase 9 / docs/task_assignments_phase8.md task P9-I). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_point_diff_race.R / tools/gif_division_standings_race.R). Reads
# CACHE_TURNOVER_HISTORY only (read-only); writes nothing back to that cache or any other cache
# file.
#
# Builds an animated horizontal bar race of each NFL_TEAMS team's cumulative_margin (running
# turnover margin) by week, re-ranking all teams top-to-bottom every frame, using
# CACHE_TURNOVER_HISTORY (schema: week, team, takeaways, giveaways, turnover_margin,
# cumulative_margin - verified live against the real cache before writing this script: 158
# rows, 5 weeks x 32 teams [2 missing team-weeks, e.g. a bye or an as-yet-unplayed game, handled
# below by carrying forward the last known cumulative_margin rather than treating as 0]; exact
# names() match to the contract in this task's brief). Reuses docs/week5_elo_analysis.qmd's
# theme_elo_dark() dark theme (copied verbatim below) and nflplotR::geom_nfl_logos() for team
# identity, plus the same ggsave-per-frame + magick::image_animate() GIF-assembly approach
# tools/gif_point_diff_race.R / tools/gif_division_standings_race.R already use, for visual
# consistency across all Phase 9 GIFs.
#
# NOTE ON WORKTREE ISOLATION: same as this task's sibling scripts' own header notes - this
# agent's work is isolated to the git worktree at WORKTREE_DIR below, unlike config.R's own
# hardcoded PROJECT_DIR (config.R:22-23), which points at the main repo checkout and is NOT
# overridden by this script's own setwd() below. CACHE_TURNOVER_HISTORY therefore still
# correctly resolves to the main repo's cache (shared, read-only, real-data input), while this
# script's own GIF/frame OUTPUT is written under WORKTREE_CACHE_DIR instead, so it lands inside
# this worktree's own cache/ rather than silently writing into the main repo's cache/.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_turnover_margin_race.R"
# ==============================================================================

WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a1a1fa60ff5872781"
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

# ---- Data: verify schema contract before any plotting ----
tu_hist <- readRDS(CACHE_TURNOVER_HISTORY)
expected_names <- c("week", "team", "takeaways", "giveaways", "turnover_margin", "cumulative_margin")
if (!identical(names(tu_hist), expected_names)) {
  stop(sprintf("CACHE_TURNOVER_HISTORY schema mismatch. Expected: %s. Got: %s",
               paste(expected_names, collapse = ", "), paste(names(tu_hist), collapse = ", ")))
}

tu_hist <- tu_hist |> filter(team %in% names(NFL_TEAMS))

max_week  <- max(tu_hist$week)
all_weeks <- sort(unique(tu_hist$week))

# Fill a complete team x week grid so any missing team-week (bye, not-yet-played) carries
# forward the team's last known cumulative_margin (flat segment) instead of a gap/NA.
grid_tw <- expand_grid(team = names(NFL_TEAMS), week = all_weeks)
cum_filled <- grid_tw |>
  left_join(tu_hist |> select(team, week, cumulative_margin), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(cumulative_margin, .direction = "down") |>
  ungroup() |>
  mutate(cumulative_margin = tidyr::replace_na(cumulative_margin, 0),
         division = NFL_DIVISIONS[team])

y_range <- range(cum_filled$cumulative_margin, na.rm = TRUE)
pad_y <- max(diff(y_range) * 0.1, 1)

frame_dir <- file.path(WORKTREE_CACHE_DIR, "turnover_margin_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  frame_df <- cum_filled |>
    filter(week == w) |>
    arrange(desc(cumulative_margin)) |>
    mutate(rank = row_number(),
           team = factor(team, levels = rev(team[order(rank)])))

  p_frame <- ggplot(frame_df, aes(x = team, y = cumulative_margin, fill = division)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    geom_nfl_logos(aes(team_abbr = as.character(team),
                        y = cumulative_margin + sign(cumulative_margin + 1e-9) * (pad_y * 0.35)),
                    width = 0.028) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
    scale_fill_manual(values = division_colors) +
    scale_y_continuous(limits = y_range + c(-pad_y, pad_y)) +
    coord_flip() +
    theme_elo_dark() +
    theme(axis.title.y = element_blank(), axis.text.y = element_blank()) +
    labs(y = "Cumulative turnover margin",
         title = sprintf("Turnover margin race through Week %d, %d", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 9, height = 10, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_turnover_margin_race.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Sanity check (success criterion 4): final-frame cumulative_margin vs. a manual running ----
# sum of turnover_margin, spot-checked against 2-3 teams.
final_frame <- cum_filled |> filter(week == max_week) |> arrange(desc(cumulative_margin))
check_teams <- c(head(final_frame$team, 1), final_frame$team[ceiling(nrow(final_frame) / 2)], tail(final_frame$team, 1))

cat("\nSanity check - animated final-week cumulative_margin vs. manual running sum of turnover_margin:\n")
for (tm in check_teams) {
  manual_sum <- sum(tu_hist$turnover_margin[tu_hist$team == tm & tu_hist$week <= max_week], na.rm = TRUE)
  anim_val   <- final_frame$cumulative_margin[final_frame$team == tm]
  cat(sprintf("  %s: animated=%.1f  manual_running_sum=%.1f  match=%s\n", tm, anim_val, manual_sum, isTRUE(abs(anim_val - manual_sum) < 1e-9)))
}
