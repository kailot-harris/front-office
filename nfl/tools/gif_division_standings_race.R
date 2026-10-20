# ==============================================================================
# GIF: Division Standings Win Race (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_division_standings_race.R
#
# Closes GitHub issue #25 (Phase 9 / docs/task_assignments_phase8.md task P9-D). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/weekly_accuracy_report.R / tools/plot_week5_projections.R / this task's
# sibling tools/gif_point_diff_race.R). Reads CACHE_SCHEDULES only (read-only); writes nothing
# back to that cache or any other cache file.
#
# Builds an animated bar race of each team's cumulative win count by week, for CURRENT_SEASON's
# completed REGULAR-SEASON games only (game_type == "REG" - ties are NOT counted as wins for
# either side, matching the real W-L-T standings definition), faceted into 8 small-multiple
# panels - one per NFL_DIVISIONS entry - with the 4 teams inside each panel re-ranked by
# cumulative wins every frame for a genuine "race" (bars reorder, not just grow). Reuses
# docs/week5_elo_analysis.qmd's theme_elo_dark() dark theme (copied verbatim below, per this
# task's brief) and nflplotR::geom_nfl_logos() for team identity, plus the same
# ggsave-per-frame + magick::image_animate() GIF-assembly approach that script already uses for
# cache/elo_scatter_animation.gif, for visual consistency across both GIFs.
#
# NOTE ON WORKTREE ISOLATION: same as tools/gif_point_diff_race.R's own header note - this
# agent's work is isolated to the git worktree at WORKTREE_DIR below, unlike config.R's own
# hardcoded PROJECT_DIR (config.R:20-21), which points at the main repo checkout and is NOT
# overridden by this script's own setwd() below. CACHE_SCHEDULES therefore still correctly
# resolves to the main repo's cache (a shared, read-only, real-data input), while this script's
# own GIF/frame OUTPUT is written under WORKTREE_CACHE_DIR instead, so it lands inside this
# worktree's own cache/ rather than silently writing into the main repo's cache/ - same pattern
# as tools/derive_min_sample_games_for_stake.R.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_division_standings_race.R"
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

# ---- Data: cumulative wins by week, CURRENT_SEASON, completed REG games ----
sch <- readRDS(CACHE_SCHEDULES)

completed <- sch |>
  filter(season == CURRENT_SEASON, game_type == "REG", !is.na(home_score), !is.na(away_score))

if (nrow(completed) == 0) {
  stop("No completed CURRENT_SEASON REG games found in CACHE_SCHEDULES - nothing to animate.")
}

long_results <- bind_rows(
  completed |> transmute(team = home_team, week,
                          win = as.integer(home_score > away_score)),
  completed |> transmute(team = away_team, week,
                          win = as.integer(away_score > home_score))
) |>
  filter(team %in% names(NFL_TEAMS))
# Ties (home_score == away_score) contribute win = 0 for both sides, matching the real
# W-L-T standings definition (a tie is not a win for either team).

cum_wins <- long_results |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(cum_w = cumsum(win)) |>
  ungroup()

max_week  <- max(cum_wins$week)
all_weeks <- sort(unique(cum_wins$week))

# Fill a complete team x week grid so bye weeks carry forward the team's last known cumulative
# win total (flat segment) instead of a gap/NA.
grid_tw <- expand_grid(team = names(NFL_TEAMS), week = all_weeks)
cum_filled <- grid_tw |>
  left_join(cum_wins |> select(team, week, cum_w), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(cum_w, .direction = "down") |>
  ungroup() |>
  mutate(cum_w = tidyr::replace_na(cum_w, 0L),
         division = NFL_DIVISIONS[team])

y_max <- max(cum_filled$cum_w, na.rm = TRUE)

frame_dir <- file.path(WORKTREE_CACHE_DIR, "division_standings_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  frame_df <- cum_filled |>
    filter(week == w) |>
    group_by(division) |>
    arrange(division, desc(cum_w), team) |>
    mutate(rank_in_div = row_number()) |>
    ungroup()

  p_frame <- ggplot(frame_df, aes(x = rank_in_div, y = cum_w, fill = division)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    geom_nfl_logos(aes(team_abbr = team, y = cum_w + 0.35), width = 0.09) +
    scale_fill_manual(values = division_colors) +
    scale_x_continuous(breaks = 1:4, labels = NULL) +
    scale_y_continuous(limits = c(0, y_max + 1), breaks = seq(0, y_max + 1, by = 2)) +
    facet_wrap(~division, ncol = 4) +
    theme_elo_dark() +
    theme(axis.title.x = element_blank()) +
    labs(y = "Cumulative wins",
         title = sprintf("Division standings (wins) through Week %d, %d", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 12, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_division_standings_race.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Sanity check: final-frame cumulative wins vs. a direct CACHE_SCHEDULES computation ----
# (success criterion 4 - "ad-hoc numeric comparison" against CACHE_SCHEDULES)
final_frame <- cum_filled |> filter(week == max_week) |> arrange(desc(cum_w))
check_teams <- c(head(final_frame$team, 1), final_frame$team[ceiling(nrow(final_frame) / 2)], tail(final_frame$team, 1))

cat("\nSanity check - animated final-week cumulative wins vs. direct recomputation from CACHE_SCHEDULES:\n")
for (tm in check_teams) {
  direct_w <- sum(completed$home_team == tm & completed$home_score > completed$away_score) +
              sum(completed$away_team == tm & completed$away_score > completed$home_score)
  anim_w <- final_frame$cum_w[final_frame$team == tm]
  cat(sprintf("  %s: animated=%d  direct=%d  match=%s\n", tm, anim_w, direct_w, isTRUE(anim_w == direct_w)))
}
