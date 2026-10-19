# ==============================================================================
# GIF: QB Cumulative EPA/Play Trajectory Race (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_qb_epa_race.R
#
# Ad-hoc, on-demand visualization script, same category as tools/gif_point_diff_race.R /
# tools/plot_week6_projections.R - not wired into run_full_pipeline.R's DAG. Pulls
# nflreadr::load_player_stats() directly (read-only, not cached anywhere in this repo yet;
# CACHE_PBP is a team-level-only trimmed cache with no passer_player_* columns, so player-level
# EPA is not available from any existing cache).
#
# Top-10 QB selection: ranked by CURRENT_SEASON total passing_epa among QBs with >= 50 season
# attempts (filters out emergency/mop-up appearances so a 2-pass spike doesn't make the top 10).
# Per week, plots cumulative EPA per dropback = cumsum(passing_epa) / cumsum(attempts), so the
# line settles toward a QB's true-talent rate as the season progresses rather than being noisy
# week-to-week.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\tools\gif_qb_epa_race.R"
# (always an absolute path - see CLAUDE.md's Rscript.exe relative-path segfault note)
# ==============================================================================

setwd("c:/Users/kailo/kayceeslices/NFL Analytics")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(nflplotR)
  library(magick)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "gif_qb_epa_race.R"

ps <- nflreadr::load_player_stats(seasons = CURRENT_SEASON) |>
  filter(position == "QB", season_type == "REG", attempts > 0)

if (nrow(ps) == 0) stop("No QB rows returned for CURRENT_SEASON from nflreadr::load_player_stats().")

season_totals <- ps |>
  group_by(player_id, player_display_name) |>
  summarise(season_attempts = sum(attempts), season_epa = sum(passing_epa, na.rm = TRUE), .groups = "drop") |>
  filter(season_attempts >= 50) |>
  arrange(desc(season_epa))

top10_ids <- head(season_totals$player_id, 10)
log_info(sprintf("Top 10 QBs by season passing_epa (min 50 attempts): %s",
                  paste(head(season_totals$player_display_name, 10), collapse = ", ")),
         call = "gif_qb_epa_race.R")

qb_weekly <- ps |>
  filter(player_id %in% top10_ids) |>
  arrange(player_id, week) |>
  group_by(player_id) |>
  mutate(
    cum_attempts = cumsum(attempts),
    cum_epa      = cumsum(replace_na(passing_epa, 0)),
    cum_epa_per_play = cum_epa / cum_attempts,
    team = last(team)  # most recent team, for display only
  ) |>
  ungroup()

week_seq <- sort(unique(qb_weekly$week))

# Fill a complete player x week grid so a bye week carries the line forward flat instead of
# gapping, same pattern as tools/gif_point_diff_race.R.
grid_pw <- expand_grid(player_id = top10_ids, week = week_seq)
qb_filled <- grid_pw |>
  left_join(qb_weekly |> select(player_id, week, cum_epa_per_play, player_display_name, team),
            by = c("player_id", "week")) |>
  arrange(player_id, week) |>
  group_by(player_id) |>
  tidyr::fill(cum_epa_per_play, player_display_name, team, .direction = "downup") |>
  ungroup()

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
      plot.title        = element_text(color = text_light)
    )
}

qb_colors <- setNames(
  grDevices::colorRampPalette(RColorBrewer::brewer.pal(10, "Paired"))(length(top10_ids)),
  top10_ids
)

# Rank (not raw value) drives the y-axis - matches tools/gif_elo_rank_bump.R's bump-chart
# pattern. Raw cum_epa_per_play values cluster tightly together early in the season (QBs are
# separated by hundredths of EPA/play), which made team logos overlap into an unreadable blob
# when plotted on a continuous value axis; rank guarantees even vertical spacing every frame.
qb_ranked <- qb_filled |>
  group_by(week) |>
  mutate(rank = rank(-cum_epa_per_play, ties.method = "first")) |>
  ungroup()

frame_dir <- "cache/qb_epa_race_anim_frames"
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  lines_df <- qb_ranked |> filter(week <= w)
  tips_df  <- qb_ranked |> filter(week == w)

  p_frame <- ggplot(lines_df, aes(x = week, y = rank, group = player_id, color = player_id)) +
    geom_line(linewidth = 0.8, alpha = 0.9, show.legend = FALSE) +
    geom_nfl_logos(data = tips_df, aes(team_abbr = team, x = week, y = rank),
                    width = 0.032, inherit.aes = FALSE) +
    scale_color_manual(values = qb_colors) +
    scale_y_reverse(breaks = 1:length(top10_ids)) +
    scale_x_continuous(breaks = week_seq, limits = range(week_seq) + c(-0.3, 0.3)) +
    theme_elo_dark() +
    labs(x = "Week", y = "Rank by cumulative EPA/dropback (1 = best)",
         title = sprintf("Top-10 QB EPA/Play Trajectory through Week %d, %d", w, CURRENT_SEASON),
         subtitle = "Min 50 season attempts to qualify for top-10 ranking")

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- "cache/gif_qb_epa_race.gif"
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated QB EPA race GIF to %s (%d frames + hold).", gif_path, length(week_seq)),
         call = "gif_qb_epa_race.R", out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Sanity check: final-frame cum_epa_per_play vs. direct recomputation ----
final_frame <- qb_ranked |> filter(week == max(week_seq))
cat("\nSanity check - final-week cumulative EPA/play (top 3 shown):\n")
for (pid in head(top10_ids, 3)) {
  direct <- ps |> filter(player_id == pid) |>
    summarise(epa = sum(replace_na(passing_epa, 0)), att = sum(attempts))
  anim_val <- final_frame$cum_epa_per_play[final_frame$player_id == pid]
  cat(sprintf("  %s: animated=%.4f  direct=%.4f  match=%s\n",
              final_frame$player_display_name[final_frame$player_id == pid][1],
              anim_val, direct$epa / direct$att,
              isTRUE(all.equal(anim_val, direct$epa / direct$att))))
}

cat("\nFinal-week rank order (1 = best cumulative EPA/dropback):\n")
print(final_frame |> arrange(rank) |> select(rank, player_display_name, team, cum_epa_per_play))
