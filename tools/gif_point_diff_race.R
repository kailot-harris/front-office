# ==============================================================================
# tools/gif_point_diff_race.R
# Path: tools/gif_point_diff_race.R
#
# WNBA Cumulative Point Differential Race Animation (regular season,
# config.R's CURRENT_SEASON). Gallery chart #2 of GitHub issue #145 (part of
# #140's gallery-chart epic, phase 2). Mirrors the NBA Analytics repo's
# tools/gif_point_diff_race.R (same NBA counterpart, read-only reference) but
# ported onto this repo's own phase-1 plumbing (tools/viz_common.R,
# tools/viz_gallery_helpers.R) and this repo's own data model -- 15 WNBA
# franchises, no conferences/divisions, non-3-letter abbreviations (GS, LA,
# LV, NY), and a box-score cache keyed by (team, game_date) rather than the
# NBA repo's per-season matchups_team_box_<season>.rds file.
#
# Chart: one line per team, cumulative (team_score - opponent_team_score)
# across every completed regular-season game of CURRENT_SEASON, animated frame
# by frame as the season progresses. Colored via get_wnba_team_color();
# zero-fallback contract (see viz_stop_no_data() below) -- no synthetic
# history is ever drawn.
#
# Foundation & Theme:
#   - sources tools/viz_common.R and tools/viz_gallery_helpers.R
#   - uses theme_wnba_dark() and official team primary colors
#   - renders dual artifacts via viz_gallery_helpers.R::viz_render_frames():
#     gif_point_diff_race.gif and gif_point_diff_race.png (reduced-motion
#     static final frame), written to cache/ and (when present) copied to
#     web/public/media/.
#
# Data input:
#   - config.R's CACHE_TEAM_BOX (data/box_scores_cache.rds), one row per
#     (team, game) across every season this repo has ingested. Filtered to
#     CURRENT_SEASON's regular season (season_type == 2) before aggregating.
#   - CACHE_TEAM_BOX lives under data/, which (like cache/) is gitignored, so
#     a fresh git worktree has no copy of its own -- see find_team_box_file()
#     below, which mirrors viz_gallery_helpers.R::viz_cache_dir()'s existing
#     WNBA_VIZ_CACHE_DIR env-var convention for exactly this problem, plus a
#     hardcoded main-checkout fallback (the same pattern the NBA original's
#     find_cache_file() uses for its own sibling-repo fallback). No part of
#     this is a synthetic-data path: every candidate is a real on-disk cache
#     file or nothing is rendered.
#
# Usage:
#   Rscript tools/gif_point_diff_race.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# 0. Locate repo root, source phase-1 plumbing, setwd() per CLAUDE.md
# ------------------------------------------------------------------------------
.SCRIPT_FILE_HINT <- "tools/gif_point_diff_race.R"

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
# no copy of its own. Mirrors viz_cache_dir()'s WNBA_VIZ_CACHE_DIR convention
# (an explicit env var pointing at the real cache) plus a hardcoded
# main-checkout fallback, exactly as the NBA original's own find_cache_file()
# does for its sibling-repo case. No candidate here is synthetic data --
# every one is a real on-disk cache file or the search comes up empty and the
# chart does not render.
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
required_cols <- c("season", "season_type", "game_date", "team_abbreviation", "team_score", "opponent_team_score")
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
# 3. Cumulative point differential per team, by game date
# ------------------------------------------------------------------------------
team_date_diff <- season_box %>%
  transmute(
    team = team_clean,
    game_date = as.character(as.Date(game_date)),
    diff = as.numeric(team_score) - as.numeric(opponent_team_score)
  ) %>%
  group_by(team, game_date) %>%
  summarize(diff = sum(diff), .groups = "drop")

teams_in_data <- sort(unique(team_date_diff$team))
all_dates <- sort(unique(team_date_diff$game_date))

if (length(teams_in_data) == 0 || length(all_dates) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("no team/date combinations remained for %d after cleaning.", CURRENT_SEASON))
}

# Full daily cumulative trajectory (one row per team per date actually
# played), step-indexed so every team shares a common x-axis even on dates it
# did not play.
running_cum <- setNames(rep(0.0, length(teams_in_data)), teams_in_data)
race_rows <- vector("list", length(all_dates) + 1L)
race_rows[[1]] <- tibble(
  step = 0L,
  game_date = all_dates[1],
  date_label = "Season Open",
  team = teams_in_data,
  cum_diff = 0.0
)

for (idx in seq_along(all_dates)) {
  d <- all_dates[idx]
  d_diffs <- team_date_diff %>% filter(game_date == d)
  if (nrow(d_diffs) > 0) {
    for (j in seq_len(nrow(d_diffs))) {
      tm <- d_diffs$team[j]
      running_cum[tm] <- running_cum[[tm]] + d_diffs$diff[j]
    }
  }
  race_rows[[idx + 1L]] <- tibble(
    step = as.integer(idx),
    game_date = d,
    date_label = format(as.Date(d), "%b %d"),
    team = teams_in_data,
    cum_diff = as.numeric(running_cum[teams_in_data])
  )
}

race_df <- bind_rows(race_rows)

# ------------------------------------------------------------------------------
# 4. Pick a manageable number of animation frames (viz_frame_dates())
# ------------------------------------------------------------------------------
# A full regular season can have 100+ distinct game dates -- rendering one
# frame per date makes an overlong, slow-to-encode GIF. viz_frame_dates()
# (tools/viz_gallery_helpers.R) picks ~n evenly spaced cutoff dates, always
# including the season's final date, same helper other gallery charts use.
display_dates <- viz_frame_dates(all_dates, n = 18)
# Map each selected display date back to its step index in race_df (step 0 is
# the synthetic "Season Open" row at race_df$step == 0; all_dates[k]
# corresponds to race_df$step == k).
display_steps <- vapply(as.character(display_dates), function(d) which(all_dates == d), integer(1))
display_steps <- c(0L, display_steps)

max_step <- max(race_df$step)
y_min <- min(race_df$cum_diff) - 8
y_max <- max(race_df$cum_diff) + 8

team_colors <- setNames(
  vapply(teams_in_data, function(tm) get_wnba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  teams_in_data
)

TEAM_LOGOS <- viz_logo_map(cache_dir = CACHE_DIR_RESOLVED, script = .SCRIPT_FILE_HINT)
TEAM_LOGOS <- TEAM_LOGOS[teams_in_data]

step_label_map <- race_df %>% distinct(step, date_label) %>% arrange(step)
step_labels <- setNames(step_label_map$date_label, step_label_map$step)

# ------------------------------------------------------------------------------
# 4b. Logo collision avoidance (jitter apart overlapping logos)
# ------------------------------------------------------------------------------
# With 15 teams, several finish a given frame within a few points of each
# other -- their logos would stack directly on top of one another at the true
# cum_diff value. jitter_apart() nudges only the LOGO's y position (never the
# line/point, which stay at the real cum_diff) just enough to keep logo
# centers at least min_gap apart, via one ascending sweep (push up) followed
# by one descending sweep (push down) so the separation is shared roughly
# evenly across a cluster rather than cascading everything upward. When a
# logo is displaced, a thin leader tick connects its true value to the
# jittered logo so the adjustment reads as a label nudge, not new data.
jitter_apart <- function(y, min_gap) {
  n <- length(y)
  if (n <= 1) return(y)
  ord <- order(y)
  y_sorted <- y[ord]
  # Ascending sweep: push each point up if it's too close to the one below it.
  for (i in 2:n) {
    if (y_sorted[i] - y_sorted[i - 1] < min_gap) {
      y_sorted[i] <- y_sorted[i - 1] + min_gap
    }
  }
  # Descending sweep: push each point down if it's too close to the one
  # above it, which re-centers clusters that only got pushed upward above.
  for (i in (n - 1):1) {
    if (y_sorted[i + 1] - y_sorted[i] < min_gap) {
      y_sorted[i] <- y_sorted[i + 1] - min_gap
    }
  }
  out <- numeric(n)
  out[ord] <- y_sorted
  out
}
# The image itself is ~0.062 of the panel height (geom_image size, by =
# "height"), i.e. roughly 0.062 * (y_max - y_min) in data units -- the first
# attempt at this gap (0.052) was smaller than that, so logos still touched.
# Use something clearly bigger than one logo diameter so centers end up a
# full logo-width-plus-margin apart, not just not-literally-touching.
LOGO_MIN_GAP <- (y_max - y_min) * 0.11

# ------------------------------------------------------------------------------
# 5. Build one ggplot per animation frame
# ------------------------------------------------------------------------------
plots <- vector("list", length(display_steps))
for (i in seq_along(display_steps)) {
  s <- display_steps[i]
  frame_lines <- race_df %>% filter(step <= s)
  frame_pts   <- race_df %>% filter(step == s) %>% arrange(team)
  frame_pts$logo_y <- jitter_apart(frame_pts$cum_diff, LOGO_MIN_GAP)
  frame_pts$logo_x <- s + max_step * 0.028
  cur_label <- step_labels[[as.character(s)]]

  plots[[i]] <- ggplot(frame_lines, aes(x = step, y = cum_diff, group = team, color = team)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.8) +
    geom_line(linewidth = 1.0, alpha = 0.55) +
    # Thin leader tick from the true value to a jittered logo (only visible
    # when jitter_apart() actually displaced that team this frame).
    geom_segment(data = frame_pts, aes(x = step, xend = logo_x, y = cum_diff, yend = logo_y),
                 linewidth = 0.45, alpha = 0.7, inherit.aes = TRUE) +
    # White halo behind each logo so it reads clearly against the other 14
    # lines crossing near it, rather than just a thin colored point.
    geom_point(data = frame_pts, aes(x = logo_x, y = logo_y),
               shape = 21, size = 7.6, fill = WNBA_COLORS$text, color = WNBA_COLORS$text,
               inherit.aes = FALSE) +
    ggimage::geom_image(data = frame_pts, aes(x = logo_x, y = logo_y, image = TEAM_LOGOS[team]),
               size = 0.062, by = "height", inherit.aes = FALSE) +
    scale_x_continuous(breaks = display_steps, labels = step_labels[as.character(display_steps)],
                        limits = c(-max_step * 0.01, max_step * 1.12)) +
    scale_y_continuous(limits = c(y_min, y_max)) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_wnba_dark() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(
      title = sprintf("WNBA Cumulative Point Differential Race (%d)", CURRENT_SEASON),
      subtitle = sprintf("Cumulative point differential trajectory through %s (Points For minus Points Against)", cur_label),
      x = "Date",
      y = "Cumulative Point Differential",
      caption = "Box Score Engine"
    )
}

# ------------------------------------------------------------------------------
# 6. Encode animated artifact (GIF + reduced-motion PNG)
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_point_diff_race",
  root       = ROOT,
  cache_dir  = CACHE_DIR_RESOLVED,
  fps        = 2,
  hold_last_frames = 5,
  width      = 1000,
  height     = 680
)
