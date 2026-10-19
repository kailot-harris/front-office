# ==============================================================================
# GIF: Rookie Offensive Snap-Share Ramp-Up Race (Weeks 1..current, CURRENT_SEASON)
# Path: tools/gif_rookie_snap_race.R
#
# Ad-hoc, on-demand visualization script, same category as tools/gif_qb_epa_race.R /
# tools/plot_week6_projections.R - not wired into run_full_pipeline.R's DAG. Reads
# CACHE_ROSTERS (read-only, for entry_year/rookie identification + pfr_id crosswalk) plus a
# direct nflreadr::load_snap_counts() pull (read-only, not cached anywhere in this repo).
#
# "Current draft class" = CACHE_ROSTERS rows where entry_year == CURRENT_SEASON (nflreadr's own
# rookie-season flag, not re-derived). Restricted to skill positions (QB/RB/WR/TE) since
# offensive-line/defensive rookies' snap-share story isn't usefully comparable on the same axis
# and CACHE_ROSTERS' practice-squad-heavy 661-row rookie population needs a narrower, more
# legible top-10 cut. Top 10 selected by total offensive snaps through the latest available
# week (a usage-weighted cut, not just skill position + drafted earliest).
#
# CACHE_ROSTERS <-> load_snap_counts() join key: pfr_id (CACHE_ROSTERS) == pfr_player_id
# (load_snap_counts()) - both are Pro-Football-Reference IDs, one of the four competing ID
# schemes CLAUDE.md's quirks section calls out; nflreadr::load_ff_playerids() crosswalk is not
# needed here since both source tables already carry the same PFR ID natively.
#
# A week with no snap_counts row for a player (inactive/not yet active-rostered, not necessarily
# a team bye) is left as a genuine gap rather than filled to 0% - filling to 0 would conflate
# "healthy scratch" with "not yet on the 53", which these early-season rookie callups need to
# stay distinguishable. geom_line() draws straight through the gap, same limitation
# tools/gif_playoff_odds_heatmap.R's header documents for its own partial-history case.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "C:\Users\kailo\kayceeslices\NFL Analytics\tools\gif_rookie_snap_race.R"
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
.LOG_SCRIPT <- "gif_rookie_snap_race.R"

ros <- readRDS(CACHE_ROSTERS)

rookies <- ros |>
  filter(season == CURRENT_SEASON, entry_year == CURRENT_SEASON,
         position %in% c("QB", "RB", "WR", "TE"), !is.na(pfr_id), pfr_id != "") |>
  arrange(gsis_id, desc(week)) |>
  distinct(gsis_id, .keep_all = TRUE) |>
  select(gsis_id, pfr_id, full_name, draft_number)

if (nrow(rookies) == 0) stop("No CURRENT_SEASON skill-position rookies found in CACHE_ROSTERS.")

sn <- nflreadr::load_snap_counts(seasons = CURRENT_SEASON) |>
  filter(pfr_player_id %in% rookies$pfr_id) |>
  inner_join(rookies, by = c("pfr_player_id" = "pfr_id")) |>
  mutate(offense_pct_num = offense_pct * 100)

if (nrow(sn) == 0) stop("No load_snap_counts() rows matched a CURRENT_SEASON rookie's pfr_id.")

season_totals <- sn |>
  group_by(gsis_id, full_name, position) |>
  summarise(total_offense_snaps = sum(offense_snaps, na.rm = TRUE), .groups = "drop") |>
  arrange(desc(total_offense_snaps))

top10 <- head(season_totals, 10)
log_info(sprintf("Top 10 CURRENT_SEASON rookies by total offensive snaps: %s",
                  paste(sprintf("%s (%s)", top10$full_name, top10$position), collapse = ", ")),
         call = .LOG_SCRIPT)

snap_weekly <- sn |>
  filter(gsis_id %in% top10$gsis_id) |>
  arrange(gsis_id, week) |>
  group_by(gsis_id) |>
  mutate(team = last(team)) |>
  ungroup()

week_seq <- sort(unique(snap_weekly$week))

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

rookie_colors <- setNames(
  grDevices::colorRampPalette(RColorBrewer::brewer.pal(10, "Paired"))(nrow(top10)),
  top10$gsis_id
)

frame_dir <- "cache/rookie_snap_race_anim_frames"
if (!dir.exists(frame_dir)) dir.create(frame_dir, recursive = TRUE)
frame_files <- character(0)

for (w in week_seq) {
  lines_df <- snap_weekly |> filter(week <= w)
  tips_df  <- lines_df |> group_by(gsis_id) |> slice_max(week, n = 1, with_ties = FALSE) |> ungroup()

  p_frame <- ggplot(lines_df, aes(x = week, y = offense_pct_num, group = gsis_id, color = gsis_id)) +
    geom_line(linewidth = 0.8, alpha = 0.9, show.legend = FALSE) +
    geom_nfl_logos(data = tips_df, aes(team_abbr = team, x = week, y = offense_pct_num),
                    width = 0.032, inherit.aes = FALSE) +
    scale_color_manual(values = rookie_colors) +
    scale_y_continuous(limits = c(0, 105), breaks = seq(0, 100, 25)) +
    scale_x_continuous(breaks = week_seq, limits = range(week_seq) + c(-0.3, 0.6)) +
    theme_elo_dark() +
    labs(x = "Week", y = "Offensive snap share (%)",
         title = sprintf("Rookie Offensive Snap-Share Ramp-Up through Week %d, %d", w, CURRENT_SEASON),
         subtitle = "Top 10 CURRENT_SEASON rookies (QB/RB/WR/TE) by total offensive snaps; gaps = inactive/not yet active-rostered that week")

  fpath <- file.path(frame_dir, sprintf("frame_%02d.png", w))
  ggsave(fpath, p_frame, width = 11, height = 7, dpi = 120, bg = bg_dark)
  frame_files <- c(frame_files, fpath)
}

frame_files_final <- c(frame_files, rep(tail(frame_files, 1), 4))
gif <- magick::image_animate(magick::image_join(magick::image_read(frame_files_final)), fps = 1, loop = 0)
gif_path <- "cache/gif_rookie_snap_race.gif"
magick::image_write(gif, gif_path)

log_info(sprintf("Wrote animated rookie snap-share race GIF to %s (%d frames + hold).", gif_path, length(week_seq)),
         call = .LOG_SCRIPT, out_path = gif_path)
cat(sprintf("Done. GIF written to: %s\n", gif_path))

# ---- Sanity check: final-week offense_pct vs. direct recomputation from load_snap_counts() ----
cat("\nSanity check - final-week offensive snap share (top 3 shown):\n")
final_w <- max(week_seq)
for (gid in head(top10$gsis_id, 3)) {
  direct_row <- sn |> filter(gsis_id == gid) |> filter(week == max(week[week <= final_w]))
  anim_row <- snap_weekly |> filter(gsis_id == gid, week == max(week))
  cat(sprintf("  %s: animated_pct=%.1f  direct_pct=%.1f  match=%s\n",
              direct_row$full_name[1], anim_row$offense_pct_num[1], direct_row$offense_pct_num[1],
              isTRUE(all.equal(anim_row$offense_pct_num[1], direct_row$offense_pct_num[1]))))
}
