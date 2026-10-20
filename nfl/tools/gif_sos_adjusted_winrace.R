# ==============================================================================
# GIF: SOS-Adjusted Win Race (surprise_index ranked bar race, Weeks 1..current)
# Path: tools/gif_sos_adjusted_winrace.R
#
# Closes GitHub issue #28 (Phase 9 / docs/task_assignments_phase8.md task P9-H). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG. Calls
# get_elo_history(max_week = W) once per week W in 1:(latest completed week) and uses
# team_performance$surprise_index DIRECTLY (already computed by that function, per this task's
# brief) - the surprise_index formula (actual win% minus Elo-implied expected win%) is NOT
# recomputed here. Reuses the shared theme_elo_dark() dark theme (copied verbatim, same as every
# other Phase 9 GIF script) and nflplotR::geom_nfl_logos() for team identity.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR, which points at the main repo checkout and
# is NOT overridden by this script's own setwd() below. CACHE_SCHEDULES/CACHE_FATIGUE_METRICS
# (read inside get_elo_history()) therefore still correctly resolve to the main repo's cache (a
# shared, read-only, real-data input), while this script's own GIF/frame OUTPUT is written under
# WORKTREE_CACHE_DIR instead, so it lands inside this worktree's own cache/ rather than silently
# writing into the main repo's cache/.
#
# COST NOTE: get_elo_history(max_week = W) re-runs the full Elo walk-forward once per week (not
# once total), so this script's total cost is roughly (latest completed week) times a single
# get_elo_history() call. For the current ~5-week season this is cheap (seconds); if this script
# is still in use once the season is much longer, that multiplier is worth revisiting (same cost
# shape issue flagged for P9-B's playoff-odds backfill in docs/task_assignments_phase8.md).
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_sos_adjusted_winrace.R"
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

division_colors <- c(
  "AFC East" = "#0D3B5C", "AFC North" = "#115677", "AFC South" = "#15708D", "AFC West" = "#198595",
  "NFC East" = "#219A9B", "NFC North" = "#2CB0A1", "NFC South" = "#3CC1A7", "NFC West" = "#4FD1AE"
)

# ---- Determine latest completed week from an unfiltered get_elo_history() call ----
result_full <- get_elo_history()
max_week <- max(result_full$long_games$week)

# ---- Build one frame's data per week by calling get_elo_history(max_week = w) ----
weekly_performance <- lapply(1:max_week, function(w) {
  res_w <- get_elo_history(max_week = w)
  res_w$team_performance |>
    transmute(team, division, surprise_index, week = w)
})
weekly_performance <- bind_rows(weekly_performance)

if (nrow(weekly_performance) == 0) {
  stop("get_elo_history(max_week = w) returned no team_performance rows for any week - nothing to animate.")
}

xr <- range(weekly_performance$surprise_index, na.rm = TRUE)
pad_x <- max(diff(xr) * 0.15, 0.02)
anim_xlim <- xr + c(-pad_x, pad_x)

n_teams <- length(unique(weekly_performance$team))

frame_dir <- file.path(WORKTREE_CACHE_DIR, "sos_winrace_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in 1:max_week) {
  cur <- weekly_performance |>
    filter(week == w) |>
    arrange(desc(surprise_index)) |>
    mutate(rank = row_number(),
           team = factor(team, levels = rev(team[order(surprise_index)])))

  p_frame <- ggplot(cur, aes(x = surprise_index, y = reorder(team, surprise_index), fill = division)) +
    geom_col(show.legend = FALSE) +
    geom_nfl_logos(aes(team_abbr = as.character(team)), width = 0.03, x = cur$surprise_index +
                     sign(cur$surprise_index + 1e-9) * pad_x * 0.25) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey60") +
    scale_fill_manual(values = division_colors) +
    coord_cartesian(xlim = anim_xlim) +
    theme_elo_dark() +
    theme(axis.title.y = element_blank()) +
    labs(x = "Surprise index (actual win% \u2212 Elo-expected win%)",
         title = sprintf("SOS-adjusted win race through Week %d, %d", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 9, height = max(6, n_teams * 0.22), dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_sos_adjusted_winrace.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Confirm ranking changes between week 2 and week 5 (or latest week, if < 5) ----
week_a <- 2
week_b <- min(5, max_week)

rank_a <- weekly_performance |> filter(week == week_a) |> arrange(desc(surprise_index)) |>
  mutate(rank = row_number()) |> select(team, rank_a = rank)
rank_b <- weekly_performance |> filter(week == week_b) |> arrange(desc(surprise_index)) |>
  mutate(rank = row_number()) |> select(team, rank_b = rank)

rank_cmp <- inner_join(rank_a, rank_b, by = "team") |> mutate(changed = rank_a != rank_b)

cat(sprintf("\nRanking comparison: Week %d vs. Week %d surprise_index rank:\n", week_a, week_b))
cat(sprintf("  %d of %d teams changed rank.\n", sum(rank_cmp$changed), nrow(rank_cmp)))
print(rank_cmp |> filter(changed) |> arrange(rank_b) |> head(10))
