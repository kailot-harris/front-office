# ==============================================================================
# tools/gif_net_rating_quadrant.R
# Path: tools/gif_net_rating_quadrant.R
#
# WNBA Offense vs. Defense Net Rating Quadrant Animation (CURRENT_SEASON,
# config.R). Gallery chart #4 of GitHub issue kailot-harris/front-office#145
# (part of #140's "gallery phase 2" batch), built on #144's phase-1 shared viz
# plumbing (tools/viz_common.R / tools/viz_gallery_helpers.R).
#
# NBA counterpart: ../NBA Analytics/tools/gif_net_rating_quadrant.R. That
# script plots all 30 NBA teams' per-100-possession offensive/defensive
# ratings, animated by game date, with a hardcoded "contender leverage" style
# quadrant presentation. This WNBA port is adapted, not copy-pasted, in three
# load-bearing ways:
#   1. All 15 WNBA teams (no conferences/divisions since 2022), not 30, and
#      WNBA_TEAMS' non-3-letter abbreviations (GS, LA, LV, NY) via
#      resolve_team_abbr()/get_wnba_team_color().
#   2. Offense/defense axes are the plain box-score split this repo already
#      has -- cumulative points scored/allowed per game through a cutoff date
#      -- not a per-100-possessions formula (this repo's CACHE_TEAM_BOX has no
#      possession-count columns the way the NBA repo's matchups file does).
#      This is NOT a second net-rating model: it is the same
#      mean(team_score - opponent_team_score) building block
#      tools/finals_series_backtest.R's ratings_as_of() already uses, just
#      kept as two summands (off, def) instead of pre-subtracted, because a
#      quadrant chart needs both axes separately.
#   3. The "net rating" half of the brief -- the signed, playoff-leverage-
#      adjusted number that actually says whether a team is good, not just
#      where its box-score averages sit -- is NOT re-derived here. Each
#      team's adjusted net rating (shown as the quadrant reference-line
#      offset and the logo halo's fill color) comes straight from
#      playoff_simulator.R's get_playoff_adjusted_rating(), the SAME function
#      tools/build_net_rating_trajectory_gif.R and
#      tools/finals_series_backtest.R already use for this. Per the issue
#      brief: reuse the existing adjusted-net-rating system rather than invent
#      a second one.
#
# Foundation & theme:
#   - sources tools/viz_common.R (theme_wnba_dark(), WNBA_TEAM_COLORS,
#     get_wnba_team_color(), viz_logo_map(), viz_stop_no_data(),
#     render_animated_artifact())
#   - sources tools/viz_gallery_helpers.R (viz_repo_root(), viz_cache_dir(),
#     viz_render_frames())
#   - renders dual artifacts via viz_render_frames(): gif_net_rating_quadrant.gif
#     and gif_net_rating_quadrant.png (reduced-motion static final frame),
#     written to cache/ and (when web/public/media exists) mirrored there too.
#
# Zero-fallback contract (issue #140/#144, overriding CLAUDE.md's general
# "fall back to a clearly labeled synthetic value" house rule for this chart
# family specifically): if the real team-box cache or any CURRENT_SEASON
# completed regular-season game is unavailable, this script stops via
# viz_stop_no_data() with nothing rendered. It never invents a score, a
# rating, or a team position.
#
# Data inputs:
#   - config.R's CACHE_TEAM_BOX (data/box_scores_cache.rds): wehoop
#     load_wnba_team_box()-shaped, long (one row per team per game), the same
#     cache tools/gif_elo_rank_bump.R and tools/gif_point_diff_race.R read.
#     data/ is git-ignored like cache/, so a fresh git worktree has no local
#     copy -- find_team_box_cache() below mirrors
#     tools/gif_elo_rank_bump.R's own ancestor-climbing search for this exact
#     problem (overridable via the WNBA_VIZ_DATA_DIR env var), locating the
#     SAME real file rather than a substitute.
#   - playoff_simulator.R's get_playoff_adjusted_rating() (sourced with
#     WNBA_PLAYOFF_SIM_NO_AUTORUN=1 per issue #157's documented pattern --
#     see export_web_json.R -- so sourcing this file does not also run its
#     30,000-series playoff demo and write cache/playoff_series_wnba_demo.rds).
#
# Collision avoidance: with 15 teams on a 2-D scatter, several land within a
# few points of each other in BOTH axes at once -- plain 1-D jitter (as in
# tools/gif_point_diff_race.R's jitter_apart(), which only separates along one
# axis) is not enough here. jitter_apart_2d() below adapts the same idea
# (bounded nudge, axis-aligned connector, never a diagonal that could be
# mistaken for a trend) to two dimensions via pairwise repulsion in
# axis-range-normalized space, then an L-shaped (horizontal-then-vertical)
# connector from each team's true (off, def) point to its jittered logo spot.
#
# Usage:
#   Rscript tools/gif_net_rating_quadrant.R
# ==============================================================================

# Known environment quirk on this machine (see tools/gif_elo_rank_bump.R):
# this worktree's renv project library is missing packages this script needs
# (dplyr/ggplot2/gifski/ggimage), while a complete, working set is installed
# in the ordinary user library. Prepend it so library() calls below resolve
# there too, without disabling renv outright.
.user_lib <- "C:/Users/kailo/AppData/Local/R/win-library/4.5"
if (dir.exists(.user_lib)) .libPaths(c(.user_lib, .libPaths()))

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_net_rating_quadrant.R"

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
# normalize_team_abbreviation()/filter_real_franchises() (CONN -> CON,
# exhibition-row drop) live in player_metrics.R, which CLAUDE.md names as the
# safe source site (pure function definitions, no auto-run side effects).
source("player_metrics.R")
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

# get_playoff_adjusted_rating() -- see header comment #3 above. ISSUE #157:
# source with the no-autorun env var set FIRST, exactly as export_web_json.R
# does, so this does not also trigger playoff_simulator.R's 30,000-series
# demo simulation as a side effect of wanting one function from it.
Sys.setenv(WNBA_PLAYOFF_SIM_NO_AUTORUN = "1")
if (!exists("get_playoff_adjusted_rating")) source("playoff_simulator.R")

VIZ_ROOT      <- viz_repo_root()
VIZ_CACHE_DIR <- viz_cache_dir(VIZ_ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real team-box cache. data/ is git-ignored, so a fresh
#    worktree has no copy of its own -- climb ancestor directories looking for
#    one that does, mirroring tools/gif_elo_rank_bump.R's find_team_box_cache()
#    exactly (same cache file, same search strategy, no synthetic fallback).
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
# 2. Load, normalize, and filter to CURRENT_SEASON's completed regular season
#    (season_type == 2 in wehoop's WNBA team-box feed; 3 is postseason).
#    filter_real_franchises() handles both the exhibition/All-Star row drop
#    and the CONN -> CON historical-abbreviation normalization (CLAUDE.md's
#    "Data quirks" section) before any aggregation below.
# ------------------------------------------------------------------------------
box_raw <- readRDS(box_file)
required_cols <- c("season", "season_type", "game_date", "team_abbreviation",
                    "team_score", "opponent_team_score")
missing_cols <- setdiff(required_cols, names(box_raw))
if (length(missing_cols) > 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s is missing expected column(s): %s.", basename(box_file), paste(missing_cols, collapse = ", ")))
}

box <- filter_real_franchises(box_raw) %>%
  filter(season == CURRENT_SEASON, season_type == 2) %>%
  mutate(
    game_day = as.Date(game_date),
    team_score = suppressWarnings(as.numeric(team_score)),
    opponent_team_score = suppressWarnings(as.numeric(opponent_team_score))
  ) %>%
  filter(!is.na(team_score), !is.na(opponent_team_score))

if (nrow(box) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "no completed %d regular-season rows were found in %s.", CURRENT_SEASON, basename(box_file)))
}

all_teams <- sort(names(WNBA_TEAMS))

# ------------------------------------------------------------------------------
# 3. Per (team, game_day) scoring, then cumulative offense/defense snapshots
#    at weekly boundaries -- same weekly-bucket construction
#    tools/gif_elo_rank_bump.R uses, so this chart and the Elo rank-bump chart
#    animate on the same cadence/calendar.
# ------------------------------------------------------------------------------
team_day <- box %>%
  transmute(team = team_abbreviation, game_day, team_score, opponent_team_score) %>%
  group_by(team, game_day) %>%
  summarize(
    pts_for     = sum(team_score),
    pts_against = sum(opponent_team_score),
    games       = n(),
    .groups = "drop"
  ) %>%
  arrange(game_day)

first_date <- min(team_day$game_day)
team_day$week_bucket <- as.integer(difftime(team_day$game_day, first_date, units = "days")) %/% 7L

cum_for     <- setNames(rep(0.0, length(all_teams)), all_teams)
cum_against <- setNames(rep(0.0, length(all_teams)), all_teams)
cum_games   <- setNames(rep(0L,  length(all_teams)), all_teams)

snapshots <- list()
idx <- 0L
for (wk in sort(unique(team_day$week_bucket))) {
  wk_rows <- team_day[team_day$week_bucket == wk, ]
  for (i in seq_len(nrow(wk_rows))) {
    tm <- wk_rows$team[i]
    cum_for[tm]     <- cum_for[[tm]]     + wk_rows$pts_for[i]
    cum_against[tm] <- cum_against[[tm]] + wk_rows$pts_against[i]
    cum_games[tm]   <- cum_games[[tm]]   + wk_rows$games[i]
  }
  played <- all_teams[cum_games[all_teams] > 0]
  if (length(played) == 0) next
  idx <- idx + 1L
  snapshots[[idx]] <- tibble::tibble(
    step        = as.integer(idx),
    week_label  = format(max(wk_rows$game_day), "%b %d"),
    team        = played,
    games       = as.integer(cum_games[played]),
    off_rtg     = as.numeric(cum_for[played]     / cum_games[played]),
    def_rtg     = as.numeric(cum_against[played] / cum_games[played])
  )
}

if (length(snapshots) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "no weekly offense/defense snapshots could be built from %s for %d.", basename(box_file), CURRENT_SEASON))
}

quad_df <- bind_rows(snapshots) %>%
  mutate(
    raw_net  = off_rtg - def_rtg,
    team_full = WNBA_TEAMS[team],
    # Reuse the EXISTING playoff-adjusted net rating system end to end (see
    # header comment #3) rather than re-deriving a second net-rating formula.
    net_adj  = vapply(seq_len(n()), function(i) get_playoff_adjusted_rating(team_full[i], raw_net[i]), numeric(1))
  )

all_steps <- sort(unique(quad_df$step))
max_step  <- max(all_steps)
step_label_map <- quad_df %>% distinct(step, week_label) %>% arrange(step)
step_labels <- setNames(step_label_map$week_label, as.character(step_label_map$step))

# Fixed plot bounds across the whole animation (padding so no frame's points
# sit flush against the panel edge), matching the NBA counterpart's approach.
x_min <- floor(min(quad_df$off_rtg) - 2)
x_max <- ceiling(max(quad_df$off_rtg) + 2)
y_min <- floor(min(quad_df$def_rtg) - 2)
y_max <- ceiling(max(quad_df$def_rtg) + 2)

TEAM_LOGOS <- viz_logo_map(cache_dir = VIZ_CACHE_DIR, script = SCRIPT_NAME)

# Diverging fill for each team's adjusted net rating (the logo halo behind
# each team's logo), centered on 0 -- below-average defenses/offenses read
# red, above-average read teal, exactly WNBA_COLORS' existing negative/accent
# pair used elsewhere in this gallery.
net_adj_abs_max <- max(abs(quad_df$net_adj), 1)

# ------------------------------------------------------------------------------
# 4. 2-D logo collision avoidance -- see header comment above. Operates in
#    axis-range-normalized space (off_rtg's and def_rtg's ranges are similar
#    but not identical) so "too close" means the same thing on both axes,
#    then converts back to data units.
# ------------------------------------------------------------------------------
x_range <- x_max - x_min
y_range <- y_max - y_min

jitter_apart_2d <- function(x, y, min_gap, x_lo, x_hi, y_lo, y_hi, iters = 40) {
  n <- length(x)
  if (n <= 1) return(list(x = x, y = y))
  nx <- x / x_range
  ny <- y / y_range
  for (it in seq_len(iters)) {
    moved <- FALSE
    for (i in 1:(n - 1)) {
      for (j in (i + 1):n) {
        dx <- nx[j] - nx[i]
        dy <- ny[j] - ny[i]
        d  <- sqrt(dx^2 + dy^2)
        if (d < min_gap) {
          moved <- TRUE
          if (d < 1e-6) {
            ang <- (i * 7 + j * 13) %% 360 * (pi / 180)
            dx <- cos(ang); dy <- sin(ang); d <- 1
          }
          push <- (min_gap - d) / 2
          ux <- dx / d; uy <- dy / d
          nx[i] <- nx[i] - ux * push; ny[i] <- ny[i] - uy * push
          nx[j] <- nx[j] + ux * push; ny[j] <- ny[j] + uy * push
        }
      }
    }
    if (!moved) break
  }
  list(
    x = pmin(pmax(nx * x_range, x_lo), x_hi),
    y = pmin(pmax(ny * y_range, y_lo), y_hi)
  )
}

# A logo is ~0.06 of the panel height in geom_image units (same size= used in
# tools/gif_point_diff_race.R); require centers at least that much apart in
# BOTH normalized axes so two logos never overlap regardless of which axis
# the crowding happens on.
LOGO_MIN_GAP <- 0.11
LOGO_HALF    <- 0.04

# ------------------------------------------------------------------------------
# 5. Build one ggplot per animation frame
# ------------------------------------------------------------------------------
plots <- vector("list", length(all_steps))
for (i in seq_along(all_steps)) {
  s <- all_steps[i]
  frame_data <- quad_df %>% filter(step == s) %>% arrange(team)
  cur_label  <- step_labels[[as.character(s)]]

  mean_off <- mean(frame_data$off_rtg)
  mean_def <- mean(frame_data$def_rtg)

  jittered <- jitter_apart_2d(
    frame_data$off_rtg, frame_data$def_rtg, LOGO_MIN_GAP,
    x_lo = x_min + LOGO_HALF * x_range, x_hi = x_max - LOGO_HALF * x_range,
    y_lo = y_min + LOGO_HALF * y_range, y_hi = y_max - LOGO_HALF * y_range
  )
  frame_data$logo_x <- jittered$x
  frame_data$logo_y <- jittered$y
  # L-shaped (horizontal-then-vertical) connector elbow: never a diagonal,
  # which on THIS chart would be especially easy to misread as implying a
  # correlation between the jitter and the two real axes.
  frame_data$elbow_x <- frame_data$logo_x
  frame_data$logo_fill <- frame_data$net_adj

  plots[[i]] <- ggplot(frame_data, aes(x = off_rtg, y = def_rtg)) +
    geom_vline(xintercept = mean_off, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.75) +
    geom_hline(yintercept = mean_def, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.75) +
    annotate("text", x = x_max - 0.5, y = y_min + 0.8, label = "Contenders (High Off / Elite Def)",
             color = WNBA_COLORS$accent, fontface = "bold", size = 3.4, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_min + 0.8, label = "Defensive Grinders (Low Off / Elite Def)",
             color = WNBA_COLORS$subtext, fontface = "italic", size = 3.0, hjust = 0) +
    annotate("text", x = x_max - 0.5, y = y_max - 0.6, label = "Offensive Juggernauts (High Off / Porous Def)",
             color = WNBA_COLORS$subtext, fontface = "italic", size = 3.0, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_max - 0.6, label = "Rebuilding (Low Off / Porous Def)",
             color = WNBA_COLORS$negative, fontface = "bold", size = 3.0, hjust = 0) +
    # Axis-aligned connector from each team's true (off, def) point to its
    # (possibly jittered) logo position -- horizontal leg first, then
    # vertical, same non-diagonal construction as
    # tools/gif_point_diff_race.R's leader lines.
    geom_segment(aes(x = off_rtg, xend = elbow_x, y = def_rtg, yend = def_rtg),
                 color = WNBA_COLORS$subtext, linetype = "dotted", linewidth = 0.5, alpha = 0.8) +
    geom_segment(aes(x = elbow_x, xend = elbow_x, y = def_rtg, yend = logo_y),
                 color = WNBA_COLORS$subtext, linetype = "dotted", linewidth = 0.5, alpha = 0.8) +
    # True value: a small solid dot at the real (off, def) coordinate.
    geom_point(size = 2.2, color = WNBA_COLORS$text, alpha = 0.9) +
    # Halo behind the logo, filled by adjusted net rating (reused from
    # get_playoff_adjusted_rating(), see header comment #3) so color still
    # conveys "is this team actually good," not just where its box-score
    # averages sit.
    geom_point(aes(x = logo_x, y = logo_y, fill = logo_fill),
               shape = 21, size = 7.6, color = WNBA_COLORS$border, stroke = 0.4) +
    ggimage::geom_image(aes(x = logo_x, y = logo_y, image = TEAM_LOGOS[team]),
                         size = 0.052, by = "width") +
    scale_x_continuous(limits = c(x_min, x_max)) +
    # Invert Y so fewer points allowed (better defense) sits near the top.
    scale_y_reverse(limits = c(y_max, y_min)) +
    scale_fill_gradient2(
      low = WNBA_COLORS$negative, mid = WNBA_COLORS$grid, high = WNBA_COLORS$accent,
      midpoint = 0, limits = c(-net_adj_abs_max, net_adj_abs_max), guide = "none"
    ) +
    theme_wnba_dark() +
    labs(
      title = sprintf("WNBA Net Rating Quadrant (%d)", CURRENT_SEASON),
      subtitle = sprintf("Offense vs. Defense (Points per Game) through %s -- Top-Right is Elite", cur_label),
      x = "Offensive Rating (Points Scored per Game)",
      y = "Defensive Rating (Points Allowed per Game -- Inverted: Lower is Better)",
      caption = "Dashed lines = current league averages. Logo halo = playoff-adjusted net rating (playoff_simulator.R)."
    )
}

# ------------------------------------------------------------------------------
# 6. Encode animated artifact (GIF + reduced-motion PNG)
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_net_rating_quadrant",
  root       = VIZ_ROOT,
  cache_dir  = VIZ_CACHE_DIR,
  fps        = 2,
  hold_last_frames = 6,
  width      = 1100,
  height     = 750
)
