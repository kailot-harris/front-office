# ==============================================================================
# tools/gif_rapm_leaders_2026.R
#
# Chart #7 of the WNBA gallery (issue #145, part of phase 2 of #140's
# gallery-chart epic; NBA counterpart: ../NBA Analytics/tools/gif_rapm_race.R).
#
# Top 10 Offensive and Top 10 Defensive RAPM leaders for the SINGLE 2026
# season (not the ALL_SEASONS-pooled fit config.R's CACHE_RAPM_RATINGS /
# cache/rapm_ratings.rds holds).
#
# WHAT DIFFERS FROM THE NBA ORIGINAL, AND WHY:
#   - The NBA original reads a single pre-fitted rapm_ratings.rds (its own
#     engine produces one ALL_SEASONS-style file and that's what's shipped).
#     This repo's rapm_engine.R::fit_rapm_ratings() supports a real
#     seasons = <year> fit via team_attribution = "season_pooled" (this is
#     exactly the path tools/generate_historical_season_snapshots.R already
#     uses to produce cache/rapm_ratings_<year>.rds for 2019-2025), so this
#     script calls that directly for 2026 instead of substituting the
#     ALL_SEASONS-pooled file -- a pooled fit would silently mix 2019-2025
#     data into a chart titled "2026".
#   - The fit result is cached to cache/rapm_ratings_2026.rds (same naming
#     convention as the other per-season snapshot files already in cache/)
#     so a re-run within the same day doesn't re-solve the ridge regression
#     unnecessarily. Sourcing rapm_engine.R itself also re-runs/overwrites
#     the ALL_SEASONS cache/rapm_ratings.rds as a side effect of its own
#     `if (!interactive()) estimate_rapm_ratings()` top-level call -- this is
#     pre-existing behavior shared with tools/generate_historical_season_snapshots.R,
#     not something introduced or fixed here.
#   - team is a full franchise name (e.g. "Phoenix Mercury"), not an
#     abbreviation -- resolve_team_abbr()/get_wnba_team_color() handle that
#     via the nickname map in viz_common.R.
#   - Uses the real leaderboard_eligible/low_sample_flag columns
#     fit_rapm_ratings() already attaches (documented in config.R near
#     "Leaderboard rank-eligibility cut") to exclude noisy low-possession
#     players from the top-10, rather than a plain top-n by rating alone.
#   - Zero-fallback contract: stops via viz_stop_no_data() with nothing
#     rendered if the 2026 PBP/possession cache has no usable data -- no
#     synthetic ratings, matching tools/viz_common.R's documented policy.
#
# Usage:
#   Rscript tools/gif_rapm_leaders_2026.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_rapm_leaders_2026.R"
TARGET_SEASON <- 2026

# tools/ scripts setwd() to the absolute project root before source()-ing
# siblings by bare filename (CLAUDE.md convention).
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
setwd(SCRIPT_DIR)

source("config.R")
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

ROOT <- viz_repo_root()
CACHE_D <- viz_cache_dir(ROOT)

# ------------------------------------------------------------------------------
# 1. Fit (or reuse a same-day cached fit of) the 2026-only RAPM ratings.
#
# No fallback: if the real possession cache has no 2026 rows, fit_rapm_ratings()
# itself hard-stops (team_attribution = "season_pooled" never falls through to
# the career-pooled box-score fallback -- see rapm_engine.R's documented
# contract), and that stop() is converted below into this script's own
# viz_stop_no_data() zero-fallback marker rather than a bare crash.
# ------------------------------------------------------------------------------
season_rapm_path <- file.path(CACHE_D, sprintf("rapm_ratings_%d.rds", TARGET_SEASON))
age_h <- if (file.exists(season_rapm_path)) {
  as.numeric(difftime(Sys.time(), file.mtime(season_rapm_path), units = "hours"))
} else {
  Inf
}

rapm_raw <- NULL
if (age_h <= 18) {
  rapm_raw <- tryCatch(as.data.frame(readRDS(season_rapm_path)), error = function(e) NULL)
}

if (is.null(rapm_raw)) {
  source("rapm_engine.R")
  fit_result <- tryCatch(
    fit_rapm_ratings(seasons = TARGET_SEASON, lambda = RAPM_LAMBDA, team_attribution = "season_pooled"),
    error = function(e) {
      message(sprintf("[viz] fit_rapm_ratings(seasons = %d) failed: %s", TARGET_SEASON, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(fit_result) || nrow(fit_result) == 0) {
    viz_stop_no_data(SCRIPT_NAME, sprintf(
      "fit_rapm_ratings(seasons = %d, team_attribution = 'season_pooled') returned no rows -- no real %d possession data in cache/wnba_pbp_cache.rds.",
      TARGET_SEASON, TARGET_SEASON))
  }
  fit_result$season <- TARGET_SEASON
  saveRDS(fit_result, season_rapm_path)
  rapm_raw <- as.data.frame(fit_result)
}

# ------------------------------------------------------------------------------
# 2. Clean + pick Top 10 ORAPM and Top 10 DRAPM leaders.
#
# Restricted to leaderboard_eligible (fit_rapm_ratings()'s own low-sample
# honesty cut, see config.R) when that column is present, so the "leaders"
# are not noisy low-possession outliers.
# ------------------------------------------------------------------------------
rapm_clean <- rapm_raw %>%
  filter(!is.na(player_name), !is.na(team), !is.na(orapm), !is.na(drapm))

if ("leaderboard_eligible" %in% names(rapm_clean)) {
  rapm_eligible <- dplyr::filter(rapm_clean, .data$leaderboard_eligible)
  if (nrow(rapm_eligible) >= 10) rapm_clean <- rapm_eligible
}

if (nrow(rapm_clean) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("no eligible %d RAPM rows after filtering NAs.", TARGET_SEASON))
}

rapm_clean <- rapm_clean %>%
  mutate(team_abbr = viz_team_abbr(team))

top_offense <- rapm_clean %>%
  arrange(desc(orapm)) %>%
  slice_head(n = 10) %>%
  mutate(type = "Offensive RAPM (ORAPM)", rating = orapm)

top_defense <- rapm_clean %>%
  arrange(desc(drapm)) %>%
  slice_head(n = 10) %>%
  mutate(type = "Defensive RAPM (DRAPM)", rating = drapm)

leaders_df <- bind_rows(top_offense, top_defense) %>%
  group_by(type) %>%
  mutate(rank_desc = rank(-rating, ties.method = "first")) %>%
  ungroup()

n_frames <- max(leaders_df$rank_desc)
x_max <- max(leaders_df$rating) + 1.2
lambda_txt <- if ("lambda" %in% names(leaders_df)) format(leaders_df$lambda[1], big.mark = ",") else NA

unique_teams <- unique(leaders_df$team_abbr)
team_colors <- sapply(unique_teams, function(tm) get_wnba_team_color(tm, "primary"))

# ------------------------------------------------------------------------------
# 3. Build one frame per rank reveal (10th -> 1st), reusing
#    viz_gallery_helpers.R::viz_render_frames() for the GIF/PNG encode + the
#    web/public/media sync.
# ------------------------------------------------------------------------------
plots <- vector("list", n_frames)
for (f_idx in seq_len(n_frames)) {
  frame_data <- leaders_df %>%
    mutate(shown = rank_desc > n_frames - f_idx,
           bar = ifelse(shown, rating, NA_real_))

  plots[[f_idx]] <- ggplot(frame_data, aes(x = bar, y = reorder(player_name, rating), fill = team_abbr)) +
    geom_col(width = 0.6, alpha = 0.9, na.rm = TRUE) +
    geom_text(aes(x = bar + 0.12, label = ifelse(shown, sprintf("%+.2f", rating), "")),
              hjust = 0, vjust = 0.4, color = WNBA_COLORS$text, fontface = "bold", size = 2.8, na.rm = TRUE) +
    scale_fill_manual(values = team_colors, guide = "none") +
    facet_wrap(~type, scales = "free_y", ncol = 2) +
    scale_x_continuous(limits = c(0, x_max)) +
    theme_wnba_dark(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      strip.text = element_text(size = 11, face = "bold", color = WNBA_COLORS$accent),
      plot.title = element_text(size = 13, face = "bold"),
      plot.subtitle = element_text(size = 9.5, color = WNBA_COLORS$subtext)
    ) +
    labs(
      title = sprintf("Top 10 Offensive and Defensive RAPM, %d", TARGET_SEASON),
      subtitle = if (is.na(lambda_txt)) sprintf("Single-season (%d) ridge-regression estimates.", TARGET_SEASON)
                 else sprintf("Single-season (%d) ridge-regression estimates (\u03bb = %s).", TARGET_SEASON, lambda_txt),
      x = "Points per 100 possessions",
      y = NULL,
      caption = "Source: WNBA Stats API possession data via wehoop. Fitted values, season-pooled team attribution."
    )
}

viz_render_frames(plots, "gif_rapm_leaders_2026", ROOT, CACHE_D, fps = 2, hold_last_frames = 6,
                   width = 1200, height = 700)