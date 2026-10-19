# ==============================================================================
# Elo Heatmap: Team x Week Elo Rating Grid
# Path: tools/gif_elo_heatmap.R
#
# Closes GitHub issue #21 (Phase 9 / docs/task_assignments_phase8.md task P9-F). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_elo_rank_bump.R and the other Phase 9 gif_*.R scripts). Reads
# tools/elo_history_data.R's get_elo_history() output only (itself reads CACHE_SCHEDULES /
# CACHE_FATIGUE_METRICS, read-only); writes nothing back to any cache file other than this
# script's own output image.
#
# STATIC vs ANIMATED decision (documented per this task's brief, success criterion 2): STATIC
# PNG, not an animated GIF. A heatmap's entire value proposition is showing the full team x week
# grid at once so a reader can scan for patterns (a team's hot/cold streak, a week where many
# teams swung) in one glance - progressively revealing columns week by week would only ever HIDE
# information a static heatmap already shows for free, unlike the rank-bump line race (gif_elo_
# rank_bump.R, issue #20) or the bar races (gif_epa_net_race.R, gif_division_standings_race.R),
# where the animation itself encodes the "race" dynamic that's the whole point of those charts.
# The brief explicitly allows "static or progressively revealed per your judgment" and a
# ".gif or .png" output, so this script renders one ggplot2 object directly to PNG via ggsave()
# rather than building per-frame PNGs + magick::image_animate().
#
# Rows = teams, ordered top-to-bottom by current_elo descending (best team at top). Columns =
# week (1..last played week, plus a final "Current" column holding each team's current_elo, same
# synthetic week get_elo_history()$trajectory already appends). Fill = Elo rating, diverging
# color scale centered on ELO_INITIAL_RATING (tools/elo_model.R's baseline starting rating for
# every team) so a tile's color intuitively reads as "above/below average" rather than just a
# raw heat ramp. Bye weeks are filled forward (a team's rating didn't change that week) using the
# same tidyr::fill(.direction = "down") pattern as gif_elo_rank_bump.R / gif_division_standings_
# race.R, so no column has a gap tile for a team on a bye.
#
# Team identity: nflplotR::geom_nfl_logos() placed in a column to the left of week 1 (one logo
# per row), replacing plain text y-axis labels - same "team identity via logos, not text" intent
# as the brief's geom_nfl_logos() requirement, adapted to a heatmap's discrete-row layout instead
# of the rank-bump chart's x/y point layout.
#
# Dark theme: theme_elo_dark() copied verbatim from docs/week5_elo_analysis.qmd (per this task's
# brief), for visual consistency with the other Phase 9 GIFs/images.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\.claude\worktrees\agent-a9109db7db5e8351c\tools\gif_elo_heatmap.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
# ==============================================================================

# NOTE ON WORKTREE ISOLATION: same as tools/gif_elo_rank_bump.R's own header note - config.R's
# PROJECT_DIR/CACHE_DIR point at the main repo checkout regardless of this script's setwd()
# below, so every CACHE_* read still correctly resolves to the main repo's shared, read-only
# cache, while this script's own output PNG is written under WORKTREE_CACHE_DIR so it lands
# inside THIS worktree's cache/ rather than the main repo's.
WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a9109db7db5e8351c"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(nflplotR)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_elo_heatmap.R"
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

# ---- Data: get_elo_history() through the latest completed week (max_week = NULL default) ----
hist <- get_elo_history()
trajectory <- hist$trajectory
current_ratings <- hist$current_ratings

if (nrow(trajectory) == 0) {
  stop("get_elo_history()$trajectory is empty - nothing to plot.")
}

last_real_week <- max(hist$long_games$week)
current_pseudo_week <- last_real_week + 1L
all_weeks <- sort(unique(trajectory$week))
teams <- sort(unique(trajectory$team))

# ---- Fill bye-week gaps: complete team x week grid, carry last known Elo forward (same pattern
# as gif_elo_rank_bump.R) ----
grid_tw <- expand_grid(team = teams, week = all_weeks)
filled <- grid_tw |>
  left_join(trajectory |> select(team, week, elo), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(elo, .direction = "down") |>
  ungroup()

missing_after_fill <- filled |> filter(is.na(elo))
if (nrow(missing_after_fill) > 0) {
  log_warn(sprintf(
    "%d team-week rows still NA after down-fill (team missing from week 1 onward) - these teams: %s. Dropped from the heatmap rather than guessed.",
    nrow(missing_after_fill), paste(unique(missing_after_fill$team), collapse = ", ")
  ), call = .LOG_SCRIPT)
  filled <- filled |> filter(!is.na(elo))
}

# ---- Row order: current_elo descending (best team at top) ----
team_order <- current_ratings |> arrange(desc(current_elo)) |> pull(team)
team_order <- team_order[team_order %in% unique(filled$team)]
filled <- filled |> mutate(team = factor(team, levels = rev(team_order)))  # rev(): first factor
# level plots at the BOTTOM in ggplot2's discrete-axis convention, so the lowest-rated team needs
# to be first in level order for the highest-rated team (last in team_order) to land at the top.

week_labels <- ifelse(all_weeks >= current_pseudo_week, "Current", as.character(all_weeks))

# Logo column: placed one slot to the left of week 1 on the x-axis.
logo_x <- min(all_weeks) - 1
logo_df <- data.frame(team = factor(team_order, levels = rev(team_order)), x = logo_x)

p <- ggplot(filled, aes(x = week, y = team, fill = elo)) +
  geom_tile(color = grid_dark, linewidth = 0.3) +
  geom_nfl_logos(data = logo_df, aes(team_abbr = team, x = x, y = team), inherit.aes = FALSE,
                  width = 0.028) +
  scale_fill_gradient2(
    low = "#C1503C", mid = panel_dark, high = "#3CC1A7",
    midpoint = ELO_INITIAL_RATING, name = "Elo"
  ) +
  scale_x_continuous(breaks = all_weeks, labels = week_labels,
                      expand = expansion(add = c(1.2, 0.5))) +
  theme_elo_dark() +
  theme(axis.text.y = element_blank(), panel.grid.major = element_blank()) +
  labs(
    x = "Week", y = NULL,
    title = sprintf("Elo Heatmap - %d (through %s)", CURRENT_SEASON,
                     ifelse(current_pseudo_week %in% all_weeks, "Current", sprintf("Week %d", last_real_week))),
    subtitle = sprintf("Rows ordered by current Elo (best at top); diverging scale centered on ELO_INITIAL_RATING = %d",
                        ELO_INITIAL_RATING)
  )

png_path <- file.path(WORKTREE_CACHE_DIR, "gif_elo_heatmap.png")
ggsave(png_path, p, width = 10, height = 12, dpi = 130, bg = bg_dark)

log_info(sprintf("Wrote static Elo heatmap PNG to %s.", png_path), call = .LOG_SCRIPT, out_path = png_path)
cat(sprintf("Done. PNG written to: %s\n", png_path))

# ---- Sanity check (success criterion 4): 2-3 spot-checked team/week cells vs trajectory's raw
# numbers ----
set.seed(42)
spot_rows <- trajectory |> filter(team %in% team_order) |> slice_sample(n = 3)

cat("\nSanity check - spot-checked team/week cells (heatmap-plotted 'filled' value vs raw trajectory elo):\n")
for (i in seq_len(nrow(spot_rows))) {
  tm <- spot_rows$team[i]; wk <- spot_rows$week[i]; raw_elo <- spot_rows$elo[i]
  plotted_elo <- filled |> filter(as.character(team) == tm, week == wk) |> pull(elo)
  cat(sprintf("  team=%s week=%s  raw_trajectory_elo=%.2f  plotted_elo=%.2f  match=%s\n",
              tm, wk, raw_elo, plotted_elo, isTRUE(isTRUE(all.equal(raw_elo, plotted_elo)))))
}
