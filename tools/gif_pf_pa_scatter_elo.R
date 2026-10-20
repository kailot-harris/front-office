# ==============================================================================
# GIF: PF vs. PA Scatter, bubble = Elo (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_pf_pa_scatter_elo.R
#
# Closes GitHub issue #27 (Phase 9 / docs/task_assignments_phase8.md task P9-H). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG. Reads
# CACHE_SCHEDULES (for cumulative PF/PA by week) and get_elo_history()$trajectory (for that
# week's pre-game Elo) - both read-only; writes nothing back to either.
#
# Builds an animated scatter: x = cumulative points-for, y = cumulative points-against (two
# separate axes, NOT a differential - per this task's brief), bubble size/color = that week's
# Elo rating, one bubble per team per frame, animated by week. Reuses the shared theme_elo_dark()
# dark theme (copied verbatim, same as every other Phase 9 GIF script) and
# nflplotR::geom_nfl_logos() for team identity.
#
# NOTE ON WORKTREE ISOLATION: this agent's work is isolated to the git worktree at WORKTREE_DIR
# below, unlike config.R's own hardcoded PROJECT_DIR, which points at the main repo checkout and
# is NOT overridden by this script's own setwd() below. CACHE_SCHEDULES therefore still correctly
# resolves to the main repo's cache (a shared, read-only, real-data input), while this script's
# own GIF/frame OUTPUT is written under WORKTREE_CACHE_DIR instead, so it lands inside this
# worktree's own cache/ rather than silently writing into the main repo's cache/.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_pf_pa_scatter_elo.R"
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

# ---- Data: cumulative PF/PA by week from CACHE_SCHEDULES, CURRENT_SEASON completed REG games --
sch <- readRDS(CACHE_SCHEDULES)

completed <- sch |>
  filter(season == CURRENT_SEASON, game_type == "REG", !is.na(home_score), !is.na(away_score))

if (nrow(completed) == 0) {
  stop("No completed CURRENT_SEASON REG games found in CACHE_SCHEDULES - nothing to animate.")
}

long_pfpa <- bind_rows(
  completed |> transmute(team = home_team, week, pf = home_score, pa = away_score),
  completed |> transmute(team = away_team, week, pf = away_score, pa = home_score)
) |>
  filter(team %in% names(NFL_TEAMS))

cum_pfpa <- long_pfpa |>
  arrange(team, week) |>
  group_by(team) |>
  mutate(cum_pf = cumsum(pf), cum_pa = cumsum(pa)) |>
  ungroup()

max_week  <- max(cum_pfpa$week)
all_weeks <- sort(unique(cum_pfpa$week))

# Fill a complete team x week grid so bye weeks carry forward cumulative PF/PA (flat), teams with
# no games yet (defensive only) get 0.
grid_tw <- expand_grid(team = names(NFL_TEAMS), week = all_weeks)
pfpa_filled <- grid_tw |>
  left_join(cum_pfpa |> select(team, week, cum_pf, cum_pa), by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(cum_pf, cum_pa, .direction = "down") |>
  ungroup() |>
  mutate(cum_pf = tidyr::replace_na(cum_pf, 0),
         cum_pa = tidyr::replace_na(cum_pa, 0),
         division = NFL_DIVISIONS[team])

# ---- Join to get_elo_history()$trajectory for that week's pre-game Elo ----
result <- get_elo_history()
trajectory <- result$trajectory  # columns: team, week, elo, division

elo_by_team_week <- trajectory |> select(team, week, elo)

pfpa_elo <- pfpa_filled |>
  left_join(elo_by_team_week, by = c("team", "week")) |>
  arrange(team, week) |>
  group_by(team) |>
  tidyr::fill(elo, .direction = "downup") |>
  ungroup()

xr <- range(pfpa_elo$cum_pf, na.rm = TRUE); yr <- range(pfpa_elo$cum_pa, na.rm = TRUE)
pad_x <- max(diff(xr) * 0.1, 5); pad_y <- max(diff(yr) * 0.1, 5)
anim_xlim <- xr + c(-pad_x, pad_x); anim_ylim <- yr + c(-pad_y, pad_y)
elo_range <- range(pfpa_elo$elo, na.rm = TRUE)

frame_dir <- file.path(WORKTREE_CACHE_DIR, "pf_pa_scatter_anim_frames")
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in all_weeks) {
  cur <- pfpa_elo |> filter(week == w)

  p_frame <- ggplot(cur, aes(x = cum_pf, y = cum_pa)) +
    geom_point(aes(size = elo, color = elo), alpha = 0.75) +
    geom_nfl_logos(aes(team_abbr = team), width = 0.04) +
    scale_size_continuous(range = c(4, 12), limits = elo_range) +
    scale_color_viridis_c(option = "plasma", limits = elo_range) +
    coord_cartesian(xlim = anim_xlim, ylim = anim_ylim) +
    theme_elo_dark() +
    theme(legend.position = "right") +
    labs(x = "Cumulative points for", y = "Cumulative points against",
         size = "Elo", color = "Elo",
         title = sprintf("PF vs. PA through Week %d, %d (bubble = Elo)", w, CURRENT_SEASON))

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 8, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

# Hold on the final frame a few extra ticks so the GIF doesn't loop too fast.
frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- file.path(WORKTREE_CACHE_DIR, "gif_pf_pa_scatter_elo.gif")
magick::image_write(gif, gif_path)

cat(sprintf("Wrote %s (%d weekly frames + 4 hold frames)\n", gif_path, length(frame_files)))

# ---- Spot-check: final-frame cumulative PF/PA vs. a direct CACHE_SCHEDULES computation ----
final_frame <- pfpa_elo |> filter(week == max_week) |> arrange(desc(cum_pf))
check_teams <- unique(c(head(final_frame$team, 1),
                         final_frame$team[ceiling(nrow(final_frame) / 2)],
                         tail(final_frame$team, 1)))

cat("\nSpot-check - animated final-week cumulative PF/PA vs. direct recomputation from CACHE_SCHEDULES:\n")
for (tm in check_teams) {
  direct_pf <- sum(completed$home_score[completed$home_team == tm]) + sum(completed$away_score[completed$away_team == tm])
  direct_pa <- sum(completed$away_score[completed$home_team == tm]) + sum(completed$home_score[completed$away_team == tm])
  anim_pf   <- final_frame$cum_pf[final_frame$team == tm]
  anim_pa   <- final_frame$cum_pa[final_frame$team == tm]
  cat(sprintf("  %s: animated PF=%d PA=%d  direct PF=%d PA=%d  match=%s\n",
              tm, anim_pf, anim_pa, direct_pf, direct_pa,
              isTRUE(anim_pf == direct_pf) && isTRUE(anim_pa == direct_pa)))
}
