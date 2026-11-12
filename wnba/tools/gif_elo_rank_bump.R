# ==============================================================================
# tools/gif_elo_rank_bump.R
# Path: tools/gif_elo_rank_bump.R
#
# WNBA Elo Rank Bump Chart Animation (CURRENT_SEASON, config.R).
# Animates the week-by-week evolution of all 15 WNBA teams' Elo ratings and
# ranks across the current regular season. Gallery chart #1 of GitHub issue
# kailot-harris/front-office#145 (part of #140's "gallery phase 2" batch),
# built on #144's phase-1 shared viz plumbing (tools/viz_common.R /
# tools/viz_gallery_helpers.R).
#
# NBA counterpart: ../NBA Analytics/tools/gif_elo_rank_bump.R. That script
# seeds its Elo trajectory from a separate preseason file
# (ensemble_team_ratings.rds) before animating one NBA season's daily games.
# WNBA has no equivalent preseason-seed cache. Per #145's brief this is
# adapted, not copy-pasted: the SAME rating model this repo already uses --
# roster_bottom_up_engine.R:75's compute_elo_ratings() (K=20 logistic update,
# 1500 baseline, 0.75 offseason regression toward 1500 at each season
# boundary, fed by config.R's CACHE_TEAM_BOX regular-season games) -- is run
# unchanged over every real completed game BEFORE CURRENT_SEASON to produce
# the entering-CURRENT_SEASON rating state (this repo's real equivalent of a
# "preseason seed," since compute_elo_ratings() already carries ratings
# across season boundaries with 0.75 regression). compute_elo_ratings()
# itself only returns the FINAL rating snapshot, so it is not called directly
# here -- this script re-runs the identical per-game update loop but records
# a snapshot of all 15 teams' ratings/ranks at each CURRENT_SEASON week
# boundary (grouping games into real calendar weeks from the season's first
# game date) instead of only the end state, which is what the rank-bump
# animation needs.
#
# Foundation & theme:
#   - sources tools/viz_common.R (theme_wnba_dark(), WNBA_TEAM_COLORS,
#     get_wnba_team_color(), viz_logo_map(), viz_stop_no_data(),
#     render_animated_artifact())
#   - sources tools/viz_gallery_helpers.R (viz_repo_root(), viz_cache_dir(),
#     viz_render_frames())
#   - renders dual artifacts via viz_render_frames(): gif_elo_rank_bump.gif
#     and gif_elo_rank_bump.png (reduced-motion static final frame), written
#     to cache/ and (when web/public/media exists) mirrored there too.
#
# Zero-fallback contract (issue #140/#144, overriding CLAUDE.md's general
# "fall back to a clearly labeled synthetic value" house rule for this chart
# family specifically): if the real team-box cache or any CURRENT_SEASON
# completed game is unavailable, this script stops via viz_stop_no_data()
# with nothing rendered. It never invents a rating, a game result, or a rank.
#
# Data inputs:
#   - config.R's CACHE_TEAM_BOX (data/box_scores_cache.rds): wehoop
#     load_wnba_team_box()-shaped, long (one row per team per game), the same
#     cache compute_elo_ratings() reads. data/ is git-ignored like cache/, so
#     a fresh git worktree has no local copy -- find_team_box_cache() below
#     climbs to an ancestor checkout that does (mirroring the
#     WNBA_VIZ_CACHE_DIR convention viz_gallery_helpers.R already documents
#     for cache/); this locates the SAME real file, never a substitute, and
#     is overridable via the WNBA_VIZ_DATA_DIR env var.
#
# Usage:
#   Rscript tools/gif_elo_rank_bump.R
# ==============================================================================

# Known environment quirk on this machine: the active R installation's renv
# project library (both this worktree's and the main checkout's) is missing
# packages this script needs (dplyr/ggplot2/gifski/ggimage), while a complete,
# working set is installed in the ordinary user library. Prepend it so
# library() calls below resolve there too, without disabling renv outright.
.user_lib <- "C:/Users/kailo/AppData/Local/R/win-library/4.5"
if (dir.exists(.user_lib)) .libPaths(c(.user_lib, .libPaths()))

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_elo_rank_bump.R"

# ------------------------------------------------------------------------------
# 0. Resolve repo root and source shared plumbing. Per CLAUDE.md, tools/
#    scripts setwd() to the absolute project root before source()-ing
#    siblings by bare filename.
# ------------------------------------------------------------------------------
.args  <- commandArgs(trailingOnly = FALSE)
.fpath <- sub("^--file=", "", .args[grepl("^--file=", .args)])
SCRIPT_DIR <- if (length(.fpath) == 1L) {
  dirname(normalizePath(.fpath, winslash = "/", mustWork = FALSE))
} else {
  file.path(getwd(), "tools")
}
PROJECT_ROOT <- normalizePath(file.path(SCRIPT_DIR, ".."), winslash = "/", mustWork = FALSE)
if (dir.exists(PROJECT_ROOT)) setwd(PROJECT_ROOT)

source("config.R")
# normalize_team_abbreviation() (CONN -> CON) lives in player_metrics.R, which
# CLAUDE.md names as the safe source site (pure function definitions, no
# auto-run side effects) -- do not reimplement this helper locally.
source("player_metrics.R")
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

VIZ_ROOT       <- viz_repo_root()
VIZ_CACHE_DIR  <- viz_cache_dir(VIZ_ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real team-box cache (see header comment above).
# ------------------------------------------------------------------------------
find_team_box_cache <- function() {
  env_dir <- Sys.getenv("WNBA_VIZ_DATA_DIR", "")
  candidates <- c(
    if (nzchar(env_dir)) file.path(env_dir, "box_scores_cache.rds") else NA_character_,
    CACHE_TEAM_BOX
  )
  anc <- PROJECT_DIR
  for (i in 1:4) {
    anc <- dirname(anc)
    candidates <- c(candidates, file.path(anc, "data", "box_scores_cache.rds"))
  }
  candidates <- candidates[!is.na(candidates)]
  for (cand in candidates) {
    if (file.exists(cand)) return(normalizePath(cand, winslash = "/"))
  }
  NULL
}

box_file <- find_team_box_cache()
if (is.null(box_file)) {
  viz_stop_no_data(SCRIPT_NAME, "box_scores_cache.rds (config.R's CACHE_TEAM_BOX) is missing.")
}

# ------------------------------------------------------------------------------
# 2. Elo computation -- same update rule as roster_bottom_up_engine.R:75's
#    compute_elo_ratings(), but snapshotting the full 15-team rating/rank
#    state at each CURRENT_SEASON week boundary instead of only the final
#    value. See header comment for why this re-implements the loop rather
#    than calling compute_elo_ratings() directly.
# ------------------------------------------------------------------------------
all_teams <- sort(names(WNBA_TEAMS))

games <- readRDS(box_file) |>
  normalize_team_abbreviation() |>
  filter(
    as.character(season_type) %in% c("2", "Regular Season"),
    team_abbreviation %in% names(WNBA_TEAMS),
    opponent_team_abbreviation %in% names(WNBA_TEAMS),
    team_home_away == "home"            # collapse the long table to one row per game
  ) |>
  transmute(
    game_id, game_date = as.Date(game_date), season,
    h_team  = team_abbreviation,
    a_team  = opponent_team_abbreviation,
    h_score = suppressWarnings(as.numeric(team_score)),
    a_score = suppressWarnings(as.numeric(opponent_team_score))
  ) |>
  filter(!is.na(h_score), !is.na(a_score), h_score != a_score) |>
  distinct(game_id, .keep_all = TRUE) |>
  arrange(game_date)

if (nrow(games) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("%s has no usable completed regular-season games.", basename(box_file)))
}

cur_games <- games |> filter(season == CURRENT_SEASON) |> arrange(game_date, game_id)
if (nrow(cur_games) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("no completed %s regular-season games were found in %s.",
                                         CURRENT_SEASON, basename(box_file)))
}

prior_games <- games |> filter(season < CURRENT_SEASON) |> arrange(game_date, game_id)

K <- 20
apply_game <- function(ratings, h_team, a_team, h_score, a_score) {
  h_win <- h_score > a_score
  exp_h <- 1 / (1 + 10^((ratings[a_team] - ratings[h_team]) / 400))
  ratings[h_team] <- ratings[h_team] + K * (as.numeric(h_win)  - exp_h)
  ratings[a_team]  <- ratings[a_team]  + K * (as.numeric(!h_win) - (1 - exp_h))
  ratings
}

ratings <- setNames(rep(1500, length(all_teams)), all_teams)

# Preseason prior for CURRENT_SEASON: run every real completed game BEFORE
# CURRENT_SEASON through the identical recurrence, applying the same 0.75
# offseason regression at each season boundary (including the final
# boundary into CURRENT_SEASON) that compute_elo_ratings() applies -- this
# IS this repo's real preseason prior, carried forward from actual games
# rather than a separately-fit ensemble file.
last_season <- NA
if (nrow(prior_games) > 0) {
  for (i in seq_len(nrow(prior_games))) {
    s <- prior_games$season[i]
    if (!is.na(last_season) && s != last_season) {
      ratings <- 1500 + 0.75 * (ratings - 1500)
    }
    last_season <- s
    ratings <- apply_game(ratings, prior_games$h_team[i], prior_games$a_team[i],
                           prior_games$h_score[i], prior_games$a_score[i])
  }
  ratings <- 1500 + 0.75 * (ratings - 1500)   # offseason regression into CURRENT_SEASON
}

history <- list()
history[[1]] <- data.frame(
  week = 0L, week_label = "Preseason",
  team = all_teams, elo = as.numeric(ratings[all_teams]),
  stringsAsFactors = FALSE
)

first_date <- min(cur_games$game_date)
cur_games$week_bucket <- as.integer(difftime(cur_games$game_date, first_date, units = "days")) %/% 7L

idx <- 1L
for (wk in sort(unique(cur_games$week_bucket))) {
  wk_games <- cur_games[cur_games$week_bucket == wk, ]
  wk_games <- wk_games[order(wk_games$game_date, wk_games$game_id), ]
  for (i in seq_len(nrow(wk_games))) {
    ratings <- apply_game(ratings, wk_games$h_team[i], wk_games$a_team[i],
                           wk_games$h_score[i], wk_games$a_score[i])
  }
  idx <- idx + 1L
  history[[idx]] <- data.frame(
    week = as.integer(idx - 1L),
    week_label = format(max(wk_games$game_date), "%b %d"),
    team = all_teams, elo = as.numeric(ratings[all_teams]),
    stringsAsFactors = FALSE
  )
}

hist_df <- do.call(rbind, history) |>
  group_by(week) |>
  mutate(rank = rank(-elo, ties.method = "first")) |>
  ungroup()

steps <- sort(unique(hist_df$week))
max_step <- max(steps)
step_labels_map <- hist_df |> distinct(week, week_label) |> arrange(week)
step_labels <- setNames(step_labels_map$week_label, as.character(step_labels_map$week))

team_colors <- setNames(
  vapply(all_teams, function(tm) get_wnba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

TEAM_LOGOS <- viz_logo_map(script = SCRIPT_NAME)

# ------------------------------------------------------------------------------
# 3. Render animation frames and encode GIF + reduced-motion PNG via the
#    shared gallery helper (writes into cache/ and, when it exists,
#    web/public/media/).
# ------------------------------------------------------------------------------
plots <- list()
for (s in steps) {
  frame_lines <- hist_df |> filter(week <= s)
  frame_pts   <- hist_df |> filter(week == s)
  cur_label   <- step_labels[[as.character(s)]]

  p <- ggplot(frame_lines, aes(x = week, y = rank, group = team, color = team)) +
    geom_line(linewidth = 1.05, alpha = 0.85) +
    geom_point(data = frame_pts, aes(x = week, y = rank, fill = team),
               shape = 21, size = 3.6, color = WNBA_COLORS$text, stroke = 1.1) +
    ggimage::geom_image(data = frame_pts, aes(x = week + 0.4, y = rank, image = TEAM_LOGOS[team]),
                         size = 0.05, by = "height", inherit.aes = FALSE) +
    scale_y_reverse(breaks = seq(1, 15, by = 2), limits = c(15.6, 0.4)) +
    scale_x_continuous(breaks = steps, labels = step_labels, limits = c(-0.3, max_step + 0.9)) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_wnba_dark() +
    theme(axis.text.x = element_text(angle = 40, hjust = 1)) +
    labs(
      title    = sprintf("WNBA Elo Rank Bump Race (%s)", CURRENT_SEASON),
      subtitle = sprintf("Weekly team power trajectory through %s (Rank 1 = Highest Elo)", cur_label),
      x = "Week ending",
      y = "Elo Rank (1 to 15)",
      caption = "Elo model: K=20 logistic update, 1500 baseline, 0.75 offseason regression (roster_bottom_up_engine.R)"
    )

  plots[[length(plots) + 1]] <- p
}

viz_render_frames(
  plots      = plots,
  name       = "gif_elo_rank_bump",
  root       = VIZ_ROOT,
  cache_dir  = VIZ_CACHE_DIR,
  fps        = 1.5,
  hold_last_frames = 6,
  width      = 1000,
  height     = 700
)
