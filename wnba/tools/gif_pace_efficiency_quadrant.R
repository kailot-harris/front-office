# ==============================================================================
# tools/gif_pace_efficiency_quadrant.R
# Path: tools/gif_pace_efficiency_quadrant.R
#
# WNBA Pace vs. Net Rating Tactical Efficiency Quadrant Animation (regular
# season, config.R's CURRENT_SEASON). Gallery chart #5 of GitHub issue #145
# (part of #140's gallery-chart epic, phase 2). Mirrors the NBA Analytics
# repo's tools/gif_pace_efficiency_quadrant.R (same NBA counterpart, read-only
# reference) but ported onto this repo's own phase-1 plumbing
# (tools/viz_common.R, tools/viz_gallery_helpers.R) and this repo's own data
# model -- 15 WNBA franchises, no conferences/divisions, non-3-letter
# abbreviations (GS, LA, LV, NY), and a box-score cache keyed by (team,
# game_date) rather than the NBA repo's per-season
# matchups_team_box_<season>.rds file.
#
# Chart: one logo per team, positioned at (pace, net rating) -- pace estimated
# per CLAUDE.md/CACHE_TEAM_BOX's actual schema (see step 2 below) and net
# rating = offensive rating minus defensive rating, both cumulative through
# the frame's cutoff date, animated frame by frame as the season progresses.
# Quadrant reference lines are the live cross-team means for that frame (mean
# pace, net rating == 0), matching the NBA original's "live league averages"
# convention. Colored/logo'd via get_wnba_team_color()/viz_logo_map();
# zero-fallback contract (see viz_stop_no_data() below) -- no synthetic
# history is ever drawn.
#
# Foundation & Theme:
#   - sources tools/viz_common.R and tools/viz_gallery_helpers.R
#   - uses theme_wnba_dark() and official team primary colors
#   - renders dual artifacts via viz_gallery_helpers.R::viz_render_frames():
#     gif_pace_efficiency_quadrant.gif and gif_pace_efficiency_quadrant.png
#     (reduced-motion static final frame), written to cache/ and (when
#     present) copied to web/public/media/.
#
# Data input:
#   - config.R's CACHE_TEAM_BOX (data/box_scores_cache.rds), one row per
#     (team, game) across every season this repo has ingested. Filtered to
#     CURRENT_SEASON's regular season (season_type == 2) before aggregating.
#   - CACHE_TEAM_BOX lives under data/, which (like cache/) is gitignored, so
#     a fresh git worktree has no copy of its own -- see find_team_box_file()
#     below, which mirrors gif_point_diff_race.R's own helper of the same
#     name/contract (WNBA_VIZ_DATA_DIR env-var convention plus a hardcoded
#     main-checkout fallback). No part of this is a synthetic-data path:
#     every candidate is a real on-disk cache file or nothing is rendered.
#
# Possession/pace estimate: this repo's CACHE_TEAM_BOX schema (confirmed by
# direct inspection -- it differs from the NBA repo's hoopR box score schema
# in column availability) has field_goals_attempted, free_throws_attempted,
# offensive_rebounds and turnovers per team per game, but no stored
# possessions/pace column and no minutes-played column. This chart uses the
# same standard single-team possession estimate the NBA counterpart uses
# (FGA + 0.44*FTA - OREB + TOV), which only needs columns this cache actually
# has; "pace" here is possessions-per-game (no minutes column to normalize to
# per-48 like the NBA original -- WNBA games are 40 minutes across 4x10,
# stable across the whole dataset, so per-game is the comparable unit, not a
# simplification that changes the chart's meaning).
#
# Usage:
#   Rscript tools/gif_pace_efficiency_quadrant.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# 0. Locate repo root, source phase-1 plumbing, setwd() per CLAUDE.md
# ------------------------------------------------------------------------------
.SCRIPT_FILE_HINT <- "tools/gif_pace_efficiency_quadrant.R"

ROOT <- tryCatch(viz_repo_root(), error = function(e) NULL)
if (is.null(ROOT) || !nzchar(ROOT)) {
  # viz_repo_root() is defined in viz_gallery_helpers.R, which we have not
  # sourced yet -- resolve it ourselves from commandArgs the same way that
  # helper does, purely so we can find viz_common.R/viz_gallery_helpers.R to
  # source them.
  .args <- commandArgs(trailingOnly = FALSE)
  .f <- sub("^--file=", "", .args[grepl("^--file=", .args)])
  .base <- if (length(.f) == 1L) file.path(dirname(normalizePath(.f)), "..") else getwd()
  ROOT <- normalizePath(.base, winslash = "/", mustWork = FALSE)
}
setwd(ROOT)

source(file.path(ROOT, "tools", "viz_common.R"))
source(file.path(ROOT, "tools", "viz_gallery_helpers.R"))
if (!exists("CACHE_TEAM_BOX", envir = .GlobalEnv)) {
  source(file.path(ROOT, "config.R"))
}

CACHE_DIR_RESOLVED <- viz_cache_dir(ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real team-box cache (CACHE_TEAM_BOX), worktree-safe
# ------------------------------------------------------------------------------
# data/ is gitignored in this repo (config.R's CACHE_TEAM_BOX points at
# data/box_scores_cache.rds), so a fresh git worktree built for this chart has
# no copy of its own. Mirrors gif_point_diff_race.R's find_team_box_file()
# exactly (same WNBA_VIZ_DATA_DIR env-var convention plus a hardcoded
# main-checkout fallback). No candidate here is synthetic data -- every one
# is a real on-disk cache file or the search comes up empty and the chart
# does not render.
find_team_box_file <- function() {
  candidates <- c(
    if (exists("CACHE_TEAM_BOX", envir = .GlobalEnv)) get("CACHE_TEAM_BOX", envir = .GlobalEnv) else NULL,
    {
      d <- Sys.getenv("WNBA_VIZ_DATA_DIR", "")
      if (nzchar(d)) file.path(d, "box_scores_cache.rds") else NULL
    },
    file.path(ROOT, "data", "box_scores_cache.rds"),
    "C:/Users/kailo/kayceeslices/front-office/WNBA Analytics/data/box_scores_cache.rds"
  )
  for (cand in candidates) {
    if (!is.null(cand) && nzchar(cand) && file.exists(cand)) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  NULL
}

box_file <- find_team_box_file()
if (is.null(box_file)) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, "box_scores_cache.rds (config.R's CACHE_TEAM_BOX) could not be found in this worktree or its usual fallback locations.")
}

box <- as.data.frame(readRDS(box_file))
required_cols <- c("season", "season_type", "game_date", "team_abbreviation",
                    "team_score", "opponent_team_score",
                    "field_goals_attempted", "free_throws_attempted",
                    "offensive_rebounds", "turnovers")
missing_cols <- setdiff(required_cols, names(box))
if (length(missing_cols) > 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("%s is missing expected column(s): %s.", basename(box_file), paste(missing_cols, collapse = ", ")))
}

# ------------------------------------------------------------------------------
# 2. Filter to CURRENT_SEASON's regular season, real franchises only
# ------------------------------------------------------------------------------
# season_type == 2 is regular season in wehoop's WNBA team-box feed (3 is
# postseason). Non-franchise exhibition/All-Star rows (CLAUDE.md's "Data
# quirks" section: DEL/WIL/ALL/USA/STE/CLA/COL/COOP/SPO, etc., varying by
# season) and the CONN/CON historical-abbreviation split are both handled by
# resolve_team_abbr() (tools/viz_common.R), this chart family's designated
# normalizer -- it already maps CONN -> CON via .ALT_ABBR_TO_STANDARD, built
# from config.R's WNBA_TEAMS, same contract as the exhibition-row filter
# CLAUDE.md documents for the ingest pipeline.
season_box <- box %>%
  filter(season == CURRENT_SEASON, season_type == 2)

if (nrow(season_box) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("no %d regular-season rows were found in %s.", CURRENT_SEASON, basename(box_file)))
}

season_box <- season_box %>%
  mutate(team_clean = resolve_team_abbr(team_abbreviation)) %>%
  filter(team_clean %in% names(WNBA_TEAMS))

if (nrow(season_box) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("no real-franchise rows remained for %d after filtering exhibition/All-Star abbreviations.", CURRENT_SEASON))
}

# ------------------------------------------------------------------------------
# 3. Per-game possession estimate, cumulative pace / off / def / net rating
# ------------------------------------------------------------------------------
# Standard single-team possession estimate (see header note on why this
# repo's CACHE_TEAM_BOX schema, unlike the NBA original's, has no stored
# possessions/minutes column to read instead).
game_rows <- season_box %>%
  transmute(
    team      = team_clean,
    game_date = as.Date(game_date),
    pts_for   = as.numeric(team_score),
    pts_against = as.numeric(opponent_team_score),
    poss      = as.numeric(field_goals_attempted) + 0.44 * as.numeric(free_throws_attempted) -
                as.numeric(offensive_rebounds) + as.numeric(turnovers)
  ) %>%
  filter(!is.na(poss), poss > 0) %>%
  arrange(team, game_date)

teams_in_data <- sort(unique(game_rows$team))
all_dates <- sort(unique(game_rows$game_date))

if (length(teams_in_data) == 0 || length(all_dates) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("no team/date combinations remained for %d after cleaning.", CURRENT_SEASON))
}

# viz_frame_dates() (tools/viz_gallery_helpers.R) picks ~n evenly spaced
# cutoff dates across the season, always including the final date, same
# helper gif_point_diff_race.R uses, so this chart's frame count/pacing
# matches the rest of the gallery.
display_dates <- viz_frame_dates(all_dates, n = 16)

# Cumulative stats as of each display date: games played, total possessions,
# pts_for/pts_against through that date, per team. A team with zero games
# played as of a given cutoff is excluded from that frame (pace/rating are
# undefined with no games -- there is nothing synthetic to substitute, per
# this chart family's zero-fallback contract) rather than drawn at some
# invented default.
quad_history <- vector("list", length(display_dates))
for (idx in seq_along(display_dates)) {
  d <- display_dates[idx]
  cum <- game_rows %>%
    filter(game_date <= d) %>%
    group_by(team) %>%
    summarize(
      games = n(),
      poss = sum(poss),
      pts_for = sum(pts_for),
      pts_against = sum(pts_against),
      .groups = "drop"
    ) %>%
    filter(games > 0, poss > 0) %>%
    mutate(
      pace = poss / games,
      off_rtg = 100 * pts_for / poss,
      def_rtg = 100 * pts_against / poss,
      net_rtg = off_rtg - def_rtg,
      step = as.integer(idx),
      date_label = format(d, "%b %d")
    )
  quad_history[[idx]] <- cum
}

quad_df <- bind_rows(quad_history)
if (nrow(quad_df) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("no team ever accumulated a positive-possession game for %d.", CURRENT_SEASON))
}

all_steps <- sort(unique(quad_df$step))
step_label_map <- quad_df %>% distinct(step, date_label) %>% arrange(step)
step_labels <- setNames(step_label_map$date_label, step_label_map$step)

# Fixed axis limits across every frame (computed once over the whole
# trajectory), so panning never happens mid-animation.
x_min <- floor(min(quad_df$pace) - 2)
x_max <- ceiling(max(quad_df$pace) + 2)
y_min <- floor(min(quad_df$net_rtg) - 3)
y_max <- ceiling(max(quad_df$net_rtg) + 3)

team_colors <- setNames(
  vapply(teams_in_data, function(tm) get_wnba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  teams_in_data
)

TEAM_LOGOS <- viz_logo_map(cache_dir = CACHE_DIR_RESOLVED, script = .SCRIPT_FILE_HINT)
TEAM_LOGOS <- TEAM_LOGOS[teams_in_data]

# ------------------------------------------------------------------------------
# 3b. 2-D logo collision avoidance (jitter apart overlapping logos)
# ------------------------------------------------------------------------------
# This is a quadrant SCATTER (unlike gif_point_diff_race.R's 1-D vertical
# race), so two teams can land close together in BOTH pace and net rating at
# once -- a straight port of that script's 1-D jitter_apart() (which only
# ever nudges one axis) would still let diagonal-neighbor logos overlap.
# jitter_apart_2d() instead relaxes BOTH coordinates together: rescale every
# point into a shared [0,1] x [0,1] square (so "distance" is comparable on
# an axis pair with very different native units -- pace in low-hundreds,
# net rating usually single digits), then repeatedly push any pair closer
# than min_gap apart along the vector connecting them (coincident points are
# nudged apart deterministically by their sorted index, not left stacked).
# After relaxation, clamp back into the unit square and rescale to the real
# axis ranges -- this guarantees every jittered logo stays inside the plot's
# own x_min/x_max/y_min/y_max, exactly like gif_point_diff_race.R's 1-D
# clamp-then-compress step (see that script's comment on 6 teams silently
# vanishing off-scale in its first draft; the equivalent 2-D failure mode
# would be a logo pushed past a corner).
jitter_apart_2d <- function(x, y, min_gap, x_lo, x_hi, y_lo, y_hi, iters = 40) {
  n <- length(x)
  if (n <= 1) return(list(x = x, y = y))

  ux <- (x - x_lo) / (x_hi - x_lo)
  uy <- (y - y_lo) / (y_hi - y_lo)

  for (iter in seq_len(iters)) {
    moved <- FALSE
    for (i in seq_len(n - 1)) {
      for (j in (i + 1):n) {
        dx <- ux[j] - ux[i]
        dy <- uy[j] - uy[i]
        dist <- sqrt(dx * dx + dy * dy)
        if (dist < min_gap) {
          moved <- TRUE
          if (dist < 1e-9) {
            # Coincident points: push apart deterministically along a fixed
            # direction derived from (i, j) rather than a diagonal that would
            # vary run to run.
            ang <- (j - i) * (pi / max(n, 2))
            dx <- cos(ang); dy <- sin(ang)
            dist <- 1
          }
          push <- (min_gap - dist) / 2
          nx <- dx / dist; ny <- dy / dist
          ux[i] <- ux[i] - nx * push
          uy[i] <- uy[i] - ny * push
          ux[j] <- ux[j] + nx * push
          uy[j] <- uy[j] + ny * push
        }
      }
    }
    if (!moved) break
  }

  # Clamp into the unit square -- keeps every logo strictly on-plot even if
  # the relaxation above pushed a point past an edge.
  ux <- pmin(pmax(ux, 0), 1)
  uy <- pmin(pmax(uy, 0), 1)

  list(
    x = x_lo + ux * (x_hi - x_lo),
    y = y_lo + uy * (y_hi - y_lo)
  )
}

# Minimum center-to-center gap, in unit-square terms: the logo image itself
# is ~0.055 of the panel width (geom_image size below), so require noticeably
# more than that diameter between any two logo centers -- the same
# "clearly bigger than one logo diameter" rule gif_point_diff_race.R's
# LOGO_MIN_GAP comment documents, just expressed as a 2-D unit-square
# distance instead of a 1-D y-gap.
LOGO_MIN_GAP_2D <- 0.11
# Inset the clamp bounds by half a logo diameter so a logo pinned to a
# corner doesn't itself get clipped by the panel border.
LOGO_INSET_X <- (x_max - x_min) * 0.035
LOGO_INSET_Y <- (y_max - y_min) * 0.035

# ------------------------------------------------------------------------------
# 4. Build one ggplot per animation frame
# ------------------------------------------------------------------------------
plots <- vector("list", length(all_steps))
for (i in seq_along(all_steps)) {
  s <- all_steps[i]
  frame_data <- quad_df %>% filter(step == s) %>% arrange(team)
  cur_label <- step_labels[[as.character(s)]]

  mean_pace <- mean(frame_data$pace)
  mean_net  <- 0

  jittered <- jitter_apart_2d(
    frame_data$pace, frame_data$net_rtg, LOGO_MIN_GAP_2D,
    x_lo = x_min + LOGO_INSET_X, x_hi = x_max - LOGO_INSET_X,
    y_lo = y_min + LOGO_INSET_Y, y_hi = y_max - LOGO_INSET_Y
  )
  frame_data$logo_x <- jittered$x
  frame_data$logo_y <- jittered$y

  p_frame <- ggplot(frame_data, aes(x = pace, y = net_rtg)) +
    geom_vline(xintercept = mean_pace, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.75) +
    geom_hline(yintercept = mean_net, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.75) +
    # Quadrant annotations
    annotate("text", x = x_max - 0.5, y = y_max - 0.8, label = "Fast & Dominant (High Pace / High Net)",
             color = WNBA_COLORS$accent, fontface = "bold", size = 3.4, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_max - 0.8, label = "Methodical & Elite (Half-Court / High Net)",
             color = WNBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 0) +
    annotate("text", x = x_max - 0.5, y = y_min + 0.8, label = "Run & Gun Vulnerable (High Pace / Low Net)",
             color = WNBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_min + 0.8, label = "Grind & Rebuild (Slow Pace / Low Net)",
             color = WNBA_COLORS$negative, fontface = "bold", size = 3.2, hjust = 0) +
    # L-shaped (horizontal-then-vertical) neutral connector from the true
    # (pace, net_rtg) value to its (possibly jittered) logo position --
    # never a straight diagonal, so it can't be mistaken for a trend/slope
    # the way gif_point_diff_race.R's leader-line comment explains for its
    # own 1-D case.
    geom_segment(data = frame_data, aes(x = pace, xend = logo_x, y = net_rtg, yend = net_rtg),
                 color = WNBA_COLORS$subtext, linetype = "dotted", linewidth = 0.5,
                 alpha = 0.8, inherit.aes = FALSE) +
    geom_segment(data = frame_data, aes(x = logo_x, xend = logo_x, y = net_rtg, yend = logo_y),
                 color = WNBA_COLORS$subtext, linetype = "dotted", linewidth = 0.5,
                 alpha = 0.8, inherit.aes = FALSE) +
    # Solid dot at the TRUE value, kept separate from the (possibly
    # jittered) logo position.
    geom_point(data = frame_data, aes(x = pace, y = net_rtg, fill = team),
               shape = 21, size = 2.6, color = WNBA_COLORS$text, stroke = 0.6,
               inherit.aes = FALSE) +
    # White halo behind each logo so it reads clearly against the quadrant
    # lines/other logos near it.
    geom_point(data = frame_data, aes(x = logo_x, y = logo_y),
               shape = 21, size = 7.6, fill = WNBA_COLORS$text, color = WNBA_COLORS$text,
               inherit.aes = FALSE) +
    ggimage::geom_image(data = frame_data, aes(x = logo_x, y = logo_y, image = TEAM_LOGOS[team]),
               size = 0.055, by = "width", inherit.aes = FALSE) +
    scale_x_continuous(limits = c(x_min, x_max), breaks = scales::pretty_breaks(n = 6)) +
    scale_y_continuous(limits = c(y_min, y_max), breaks = scales::pretty_breaks(n = 7)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_wnba_dark() +
    labs(
      title = sprintf("WNBA Pace vs. Net Rating Tactical Efficiency Quadrant (%d)", CURRENT_SEASON),
      subtitle = sprintf("Estimated Possessions/Game vs Net Rating (+/- per 100 poss) through %s", cur_label),
      x = "Pace (Estimated Possessions / Game)",
      y = "Net Rating (Points Differential / 100 Possessions)",
      caption = "Vertical line: Mean Pace \u00b7 Horizontal line: Net Zero \u00b7 Box Score Engine"
    )

  plots[[i]] <- p_frame
}

# ------------------------------------------------------------------------------
# 5. Encode animated artifact (GIF + reduced-motion PNG)
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_pace_efficiency_quadrant",
  root       = ROOT,
  cache_dir  = CACHE_DIR_RESOLVED,
  fps        = 2,
  hold_last_frames = 5,
  width      = 1200,
  height     = 700
)
