# ==============================================================================
# GIF: Division Cumulative Point-Differential Stacked Area Chart (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_division_pd_area.R
#
# Ad-hoc, on-demand visualization script, same category as tools/gif_point_diff_race.R -
# not wired into run_full_pipeline.R's DAG. Reads CACHE_SCHEDULES only (read-only).
#
# For each of the 8 NFL_DIVISIONS, sums its 4 teams' cumulative point differential
# (points-for minus points-against) by week, for CURRENT_SEASON's completed REG games only
# (same game_type == "REG" filter as tools/gif_point_diff_race.R, for the same reason: exclude
# any future playoff games once the season reaches them). Animates a stacked area chart,
# revealing one additional week per frame. ggplot2's position_stack() stacks positive-valued
# divisions above zero and negative-valued divisions below zero in a given frame, so the chart
# reads as "how much combined point-differential cushion/deficit has each division's 4 teams
# built up" rather than a literal running total (there is no single meaningful grand total to
# stack toward - division PD values are independent, zero-centered quantities).
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\tools\gif_division_pd_area.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
# ==============================================================================

setwd("c:/Users/kailo/kayceeslices/NFL Analytics")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(magick)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_division_pd_area.R"

sch <- readRDS(CACHE_SCHEDULES)

completed <- sch |>
  filter(season == CURRENT_SEASON, game_type == "REG", !is.na(home_score), !is.na(away_score))

if (nrow(completed) == 0) stop("No completed CURRENT_SEASON REG games found in CACHE_SCHEDULES.")

long_diff <- bind_rows(
  completed |> transmute(team = home_team, week, diff = home_score - away_score),
  completed |> transmute(team = away_team, week, diff = away_score - home_score)
) |>
  filter(team %in% names(NFL_DIVISIONS)) |>
  mutate(division = unname(NFL_DIVISIONS[team]))

all_weeks <- sort(unique(long_diff$week))

# Complete team x week grid (bye weeks carry the team's last cumulative PD forward flat), same
# pattern as tools/gif_point_diff_race.R, then rolled up to division-level sums per week.
grid_tw <- expand_grid(team = names(NFL_DIVISIONS), week = all_weeks)
cum_team <- grid_tw |>
  left_join(long_diff |> select(team, week, diff), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(diff = tidyr::replace_na(diff, 0), cum_pd = cumsum(diff)) |>
  ungroup() |>
  mutate(division = unname(NFL_DIVISIONS[team]))

div_weekly <- cum_team |>
  group_by(division, week) |>
  summarise(division_pd = sum(cum_pd), .groups = "drop")

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
      panel.grid.major  = element_line(color = grid_dark),
      panel.grid.minor  = element_blank(),
      text              = element_text(color = text_light),
      axis.text         = element_text(color = text_light),
      plot.title        = element_text(color = text_light),
      legend.text       = element_text(color = text_light),
      legend.title      = element_text(color = text_light)
    )
}

division_colors <- c(
  "AFC East" = "#0D3B5C", "AFC North" = "#115677", "AFC South" = "#15708D", "AFC West" = "#198595",
  "NFC East" = "#219A9B", "NFC North" = "#2CB0A1", "NFC South" = "#3CC1A7", "NFC West" = "#4FD1AE"
)

yr <- range(div_weekly$division_pd)
pad_y <- max(diff(yr) * 0.1, 5)
anim_ylim <- yr + c(-pad_y, pad_y)

frame_dir <- "cache/division_pd_area_anim_frames"
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  frame_df <- div_weekly |> filter(week <= w)

  p_frame <- ggplot(frame_df, aes(x = week, y = division_pd, fill = division)) +
    geom_area(position = "stack", alpha = 0.9, color = bg_dark, linewidth = 0.2) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey70") +
    scale_fill_manual(values = division_colors) +
    scale_x_continuous(breaks = all_weeks, limits = range(all_weeks)) +
    coord_cartesian(ylim = anim_ylim) +
    theme_elo_dark() +
    labs(x = "Week", y = "Division cumulative point differential (stacked)",
         fill = "Division",
         title = sprintf("Division Point-Differential Build-Up through Week %d, %d", w, CURRENT_SEASON),
         subtitle = "Each band = sum of its 4 teams' cumulative PF \u2212 PA; positive divisions stack above zero, negative below")

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- "cache/gif_division_pd_area.gif"
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated division PD stacked-area GIF to %s (%d frames + hold).", gif_path, length(all_weeks)),
         call = .LOG_SCRIPT, out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Sanity check: final-week division_pd vs. direct recomputation for 2-3 divisions ----
final_w <- max(all_weeks)
cat("\nSanity check - final-week division cumulative PD vs. direct recomputation:\n")
check_divs <- c("AFC East", "NFC West", "NFC North")
for (d in check_divs) {
  teams_in_div <- names(NFL_DIVISIONS[NFL_DIVISIONS == d])
  direct_pd <- sum(sapply(teams_in_div, function(tm) {
    sum(completed$home_score[completed$home_team == tm]) + sum(completed$away_score[completed$away_team == tm]) -
      sum(completed$away_score[completed$home_team == tm]) - sum(completed$home_score[completed$away_team == tm])
  }))
  anim_pd <- div_weekly$division_pd[div_weekly$division == d & div_weekly$week == final_w]
  cat(sprintf("  %s: animated=%d  direct=%d  match=%s\n", d, anim_pd, direct_pd, isTRUE(anim_pd == direct_pd)))
}
