# ==============================================================================
# GIF: Playoff Probability Bump Chart (Weeks 1..5, playoff-odds history)
# Path: tools/gif_playoff_prob_bump.R
#
# Closes GitHub issue #31 (Phase 9 / docs/task_assignments_phase8.md task P9-I). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_point_diff_race.R / tools/gif_division_standings_race.R /
# tools/gif_epa_net_race.R). Reads CACHE_PLAYOFF_ODDS_HISTORY only (read-only); writes nothing
# back to that cache or any other cache file.
#
# Builds an animated line/bump chart of each NFL_TEAMS team's playoff_prob by week, using
# CACHE_PLAYOFF_ODDS_HISTORY (schema: week, team, division_win_prob, playoff_prob, bye_prob -
# verified live against the real cache before writing this script: 160 rows = 5 weeks x 32
# teams, exact names() match to the contract in this task's brief). Reuses
# docs/week5_elo_analysis.qmd's theme_elo_dark() dark theme (copied verbatim below) and
# nflplotR::geom_nfl_logos() for team identity, plus the same ggsave-per-frame +
# magick::image_animate() GIF-assembly approach tools/gif_point_diff_race.R already uses, for
# visual consistency across all Phase 9 GIFs.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR (config.R:22-23), which points at the main
# repo checkout and is NOT overridden by this script's own setwd() below. CACHE_PLAYOFF_ODDS_
# HISTORY therefore still correctly resolves to the main repo's cache (a shared, read-only, real
# -data input - exactly what this task is allowed to read), while this script's own GIF/frame
# OUTPUT is written under WORKTREE_CACHE_DIR instead, so it lands inside this worktree's own
# cache/ rather than silently writing into the main repo's cache/.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_playoff_prob_bump.R"
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

# ---- Data: verify schema contract before any plotting ----
po_hist <- readRDS(CACHE_PLAYOFF_ODDS_HISTORY)
expected_names <- c("week", "team", "division_win_prob", "playoff_prob", "bye_prob")
if (!identical(names(po_hist), expected_names)) {
  stop(sprintf("CACHE_PLAYOFF_ODDS_HISTORY schema mismatch. Expected: %s. Got: %s",
               paste(expected_names, collapse = ", "), paste(names(po_hist), collapse = ", ")))
}

po_hist <- po_hist |>
  filter(team %in% names(NFL_TEAMS)) |>
  mutate(division = NFL_DIVISIONS[team])

max_week  <- max(po_hist$week)
all_weeks <- sort(unique(po_hist$week))

frame_dir <- file.path(WORKTREE_CACHE_DIR, "playoff_prob_bump_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  lines_df <- po_hist |> filter(week <= w)
  tips_df  <- po_hist |> filter(week == w)

  p_frame <- ggplot(lines_df, aes(x = week, y = playoff_prob, group = team, color = division)) +
    geom_line(linewidth = 0.6, alpha = 0.85, show.legend = FALSE) +
    geom_hline(yintercept = 0.5, linetype = "dashed", color = "grey60") +
    geom_nfl_logos(data = tips_df, aes(x = week, y = playoff_prob, team_abbr = team), width = 0.04) +
    scale_color_manual(values = division_colors) +
    scale_x_continuous(breaks = all_weeks, limits = range(all_weeks)) +
    scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
    theme_elo_dark() +
    labs(x = "Week", y = "Playoff probability",
         title = sprintf("Playoff probability through Week %d, %d", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_playoff_prob_bump.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Trend check (success criterion 2): playoff_prob should trend toward more decisive ----
# (closer to 0 or 1) in later weeks for most teams, i.e. mean distance-from-0.5 should rise.
decisiveness <- po_hist |>
  group_by(week) |>
  summarise(mean_abs_dist_from_half = mean(abs(playoff_prob - 0.5)), .groups = "drop") |>
  arrange(week)

cat("\nDecisiveness check - mean |playoff_prob - 0.5| by week (should trend up):\n")
print(decisiveness)

first_week_val <- decisiveness$mean_abs_dist_from_half[decisiveness$week == min(all_weeks)]
last_week_val  <- decisiveness$mean_abs_dist_from_half[decisiveness$week == max_week]
cat(sprintf("\nWeek %d mean |dist from 0.5| = %.4f -> Week %d = %.4f (trend %s)\n",
            min(all_weeks), first_week_val, max_week, last_week_val,
            ifelse(last_week_val > first_week_val, "UP (more decisive, as expected)", "NOT up")))
