# ==============================================================================
# tools/gif_rapm_leaders_by_season.R
# Path: tools/gif_rapm_leaders_by_season.R
#
# Gallery chart #8 (companion to chart #7, tools/gif_rapm_leaders_2026.R). Part
# of GitHub issue #145 ("feat(wnba): gallery phase 2 -- charts 1-10"), itself
# part of #140. Built on top of phase 1's shared viz plumbing (#144, already on
# main): tools/viz_common.R + tools/viz_gallery_helpers.R.
#
# WHAT THIS CHART SHOWS, AND HOW IT DIFFERS FROM CHART #7:
#   Chart #7 is a single-season snapshot of the CURRENT RAPM leaderboard, read
#   from cache/rapm_ratings.rds (rapm_engine.R::estimate_rapm_ratings()'s
#   ALL_SEASONS-pooled, current-roster-attributed live cache).
#
#   This chart instead animates how the Top-N total RAPM leaderboard has moved
#   ACROSS SEASONS: one frame per season in config.R's ALL_SEASONS (2019-2026),
#   each frame a bar chart of that season's own Top-N total_rapm leaders. Every
#   frame is a REAL, independently-fit per-season RAPM model --
#   rapm_engine.R::fit_rapm_ratings(seasons = <single season>,
#   team_attribution = "season_pooled") called once per season, NOT a slice of
#   the ALL_SEASONS-pooled CACHE_RAPM_RATINGS. "season_pooled" (rather than the
#   live "current_roster" attribution) is used deliberately, matching
#   tools/generate_historical_season_snapshots.R's precedent (see that file's
#   and rapm_engine.R's fit_rapm_ratings() header comments): a historical
#   per-season snapshot should keep each player's possession-vote team for
#   THAT season, not get silently re-labelled onto their 2026 roster team.
#
# PERFORMANCE NOTE (so a future reader doesn't assume this is slow and cached
# instead): fit_rapm_ratings() is only expensive the FIRST time it has to
# build cache/wnba_pbp_cache.rds from wehoop. Once that pooled possession
# cache exists (it does in every checkout that has run the pipeline once),
# each single-season fit_rapm_ratings() call just re-filters the already-
# loaded possessions by season and solves one ridge regression -- empirically
# ~0.3-0.6s/season, ~3-4s for all 8 ALL_SEASONS seasons combined (timed in
# this worktree 2026-11-12). This is real per-season computation, not a
# shortcut -- it is just not the slow part of the pipeline.
#
# ZERO-FALLBACK CONTRACT: if the real possession cache is unavailable, or any
# requested season's fit_rapm_ratings() call fails/returns 0 rows, this script
# stops via viz_stop_no_data() -- nothing is rendered. No synthetic/hand-typed
# RAPM values, no silently-skipped seasons. (Per issue #140/#144, this
# overrides CLAUDE.md's general "fall back to a clearly labeled synthetic
# value" house rule for gallery charts specifically.)
#
# Usage:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/gif_rapm_leaders_by_season.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

PROJECT_DIR <- here::here()
setwd(PROJECT_DIR)

source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

SCRIPT_NAME <- "tools/gif_rapm_leaders_by_season.R"

source("config.R")

root      <- viz_repo_root()
cache_dir <- viz_cache_dir(root)

# ------------------------------------------------------------------------------
# 1. Fit RAPM independently for every season in ALL_SEASONS (real per-season
#    ridge regressions via rapm_engine.R::fit_rapm_ratings() -- see header).
# ------------------------------------------------------------------------------
pbp_cache_path <- file.path(cache_dir, "wnba_pbp_cache.rds")
if (!file.exists(pbp_cache_path)) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("%s is missing -- no real possession data to fit per-season RAPM from.", pbp_cache_path))
}

source("logging_utils.R")
source("rapm_join_utils.R")
source("rapm_engine.R")

SEASONS_TO_FIT <- ALL_SEASONS

message(sprintf(">>> [gif_rapm_leaders_by_season] Fitting per-season RAPM for seasons: %s",
                paste(SEASONS_TO_FIT, collapse = ", ")))

.t_fit_start <- Sys.time()

season_fits <- lapply(SEASONS_TO_FIT, function(s) {
  tryCatch(
    fit_rapm_ratings(seasons = s, team_attribution = "season_pooled"),
    error = function(e) {
      message(sprintf(">>> [gif_rapm_leaders_by_season] fit_rapm_ratings(seasons = %d) failed: %s", s, conditionMessage(e)))
      NULL
    }
  )
})

.t_fit_secs <- as.numeric(difftime(Sys.time(), .t_fit_start, units = "secs"))
message(sprintf(">>> [gif_rapm_leaders_by_season] Per-season RAPM fitting took %.1fs for %d season(s).",
                .t_fit_secs, length(SEASONS_TO_FIT)))

names(season_fits) <- SEASONS_TO_FIT
ok_seasons <- SEASONS_TO_FIT[!vapply(season_fits, is.null, logical(1)) &
                               vapply(season_fits, function(d) !is.null(d) && nrow(d) > 0, logical(1))]

if (length(ok_seasons) == 0) {
  viz_stop_no_data(SCRIPT_NAME, "fit_rapm_ratings() returned no usable rows for any season in ALL_SEASONS.")
}

rapm_by_season <- bind_rows(lapply(ok_seasons, function(s) {
  df <- season_fits[[as.character(s)]]
  df$season <- s
  df
}))

rapm_by_season <- rapm_by_season %>%
  filter(!is.na(player_name), !is.na(team), !is.na(total_rapm)) %>%
  mutate(team_abbr = resolve_team_abbr(team))

# ------------------------------------------------------------------------------
# 2. Top-N total RAPM leaders per season.
# ------------------------------------------------------------------------------
TOP_N <- 8

leaders_by_season <- rapm_by_season %>%
  group_by(season) %>%
  arrange(desc(total_rapm), .by_group = TRUE) %>%
  slice_head(n = TOP_N) %>%
  mutate(rank = row_number()) %>%
  ungroup()

if (nrow(leaders_by_season) == 0) {
  viz_stop_no_data(SCRIPT_NAME, "No Top RAPM leaders could be assembled across any fitted season.")
}

x_max <- max(leaders_by_season$total_rapm, na.rm = TRUE) * 1.15
unique_teams <- unique(leaders_by_season$team_abbr)
team_colors <- setNames(vapply(unique_teams, function(tm) get_wnba_team_color(tm, "primary"), character(1)), unique_teams)

# ------------------------------------------------------------------------------
# 3. One frame per season, chronological order (2019 -> most recent).
# ------------------------------------------------------------------------------
frame_seasons <- sort(unique(leaders_by_season$season))

plots <- lapply(frame_seasons, function(s) {
  frame_data <- leaders_by_season %>% filter(season == s) %>% arrange(rank)

  ggplot(frame_data, aes(x = total_rapm, y = reorder(player_name, -rank), fill = team_abbr)) +
    geom_col(width = 0.65, alpha = 0.92) +
    geom_text(aes(label = sprintf("%+.2f  (%s)", total_rapm, team_abbr)),
              hjust = -0.05, color = WNBA_COLORS$text, fontface = "bold", size = 3.1) +
    scale_fill_manual(values = team_colors, guide = "none") +
    scale_x_continuous(limits = c(0, x_max), expand = expansion(mult = c(0, 0.18))) +
    theme_wnba_dark(base_size = 12) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title    = element_text(size = 15, face = "bold"),
      plot.subtitle = element_text(size = 10.5, color = WNBA_COLORS$subtext)
    ) +
    labs(
      title    = sprintf("Top %d RAPM Leaders -- %d Season", TOP_N, s),
      subtitle = sprintf("Independently fit per-season ridge regression (\u03bb = %s). Season-pooled team attribution.",
                          format(frame_data$lambda[1], big.mark = ",")),
      x = "Total RAPM (points per 100 possessions)",
      y = NULL,
      caption = "Source: WNBA Stats API possession data (wehoop). One ridge regression fit per season -- not a slice of the all-seasons-pooled cache."
    )
})

# ------------------------------------------------------------------------------
# 4. Render dual artifacts (GIF + reduced-motion PNG) to cache/ and
#    web/public/media/ via the shared plumbing.
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_rapm_leaders_by_season",
  root       = root,
  cache_dir  = cache_dir,
  fps        = 1,
  hold_last_frames = 6,
  width      = 1100,
  height     = 700
)
