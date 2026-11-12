# ==============================================================================
# tools/gif_proj_vs_actual_wins.R
#
# Pre-season projection against results so far: each team's projected win rate
# from before opening night against its actual win rate to date.
#
# Data (real, no fallback):
#   - data/preseason_team_projections_2026-27.csv
#       The ensemble win projections exactly as published on 2026-10-18, two
#       days before opening night (web/public/data/projections_season_teams.json
#       at commit bae5652). Frozen so later model runs cannot move the baseline.
#   - cache/matchups_team_box_2027.rds  completed 2026-27 games
#
# Usage: Rscript tools/gif_proj_vs_actual_wins.R
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(ggplot2) })

SCRIPT <- "tools/gif_proj_vs_actual_wins.R"
ROOT <- local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  normalizePath(if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd(), winslash = "/")
})
source(file.path(ROOT, "tools", "viz_common.R"))
source(file.path(ROOT, "tools", "viz_gallery_helpers.R"))
CACHE <- viz_cache_dir(ROOT)

pre_path <- file.path(ROOT, "data", "preseason_team_projections_2026-27.csv")
box_path <- file.path(CACHE, "matchups_team_box_2027.rds")
if (!file.exists(pre_path)) viz_stop_no_data(SCRIPT, "data/preseason_team_projections_2026-27.csv was not found.")
if (!file.exists(box_path)) viz_stop_no_data(SCRIPT, "cache/matchups_team_box_2027.rds was not found.")

pre <- read.csv(pre_path, stringsAsFactors = FALSE) %>% mutate(proj_pct = proj_wins / 82)
box <- as.data.frame(readRDS(box_path))
box$team <- viz_team_abbr(box$team_abbreviation)
games <- box %>% filter(team %in% pre$team) %>%
  transmute(game_id, game_date = as.Date(game_date), team, pts = as.numeric(team_score)) %>%
  group_by(game_id) %>% filter(n() == 2, !any(is.na(pts)), pts[1] != pts[2]) %>%
  mutate(won = pts == max(pts)) %>% ungroup()
if (length(unique(games$game_id)) < 60 || length(unique(games$team)) < 30) {
  viz_stop_no_data(SCRIPT, sprintf("only %d completed games for %d teams.", length(unique(games$game_id)), length(unique(games$team))))
}

LOGOS <- viz_logo_map(CACHE, SCRIPT)
cuts <- viz_frame_dates(games$game_date, n = 12)
cuts <- cuts[cuts >= sort(unique(games$game_date))[min(6, length(unique(games$game_date)))]]

plots <- lapply(cuts, function(d) {
  snap <- games %>% filter(game_date <= d) %>% group_by(team) %>%
    summarise(w = sum(won), g = n(), .groups = "drop") %>% mutate(pct = w / g) %>%
    inner_join(pre, by = "team") %>% mutate(gap = pct - proj_pct)
  mae <- mean(abs(snap$gap))
  ggplot(snap, aes(proj_pct, pct)) +
    geom_abline(slope = 1, intercept = 0, colour = "#64748B", linetype = "dashed") +
    annotate("text", x = 0.22, y = 0.97, hjust = 0, colour = "#94A3B8", size = 3.6, label = "Ahead of projection") +
    annotate("text", x = 0.78, y = 0.03, hjust = 1, colour = "#94A3B8", size = 3.6, label = "Behind projection") +
    ggimage::geom_image(aes(image = LOGOS[team]), size = 0.055, by = "width") +
    scale_x_continuous(labels = function(v) paste0(round(100 * v), "%"), limits = c(0.2, 0.8)) +
    scale_y_continuous(labels = function(v) paste0(round(100 * v), "%"), limits = c(0, 1)) +
    labs(title = "Pre-Season Projection vs Results So Far (2026-27)",
         subtitle = sprintf("Through %s, %d to %d games per team. Teams are off their projected win rate by %.0f percentage points on average.",
                            format(d, "%b %d"), min(snap$g), max(snap$g), 100 * mae),
         x = "Projected win rate, published Oct 18 before opening night", y = "Actual win rate so far",
         caption = "Dashed line: results match the projection. Early-season win rates swing widely on few games.") +
    theme_nba_dark(base_size = 12)
})

viz_render_frames(plots, "gif_proj_vs_actual_wins", ROOT, CACHE, fps = 2, hold_last_frames = 8,
                  width = 1000, height = 760)
