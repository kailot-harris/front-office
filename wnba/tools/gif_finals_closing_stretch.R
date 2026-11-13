# ==============================================================================
# tools/gif_finals_closing_stretch.R
# Path: tools/gif_finals_closing_stretch.R
#
# Finals Closing Stretch: score margin paired with shot locations in the final
# five minutes of the deciding game of the 2026 WNBA Finals. Gallery chart #12
# of GitHub issue #146 (part of #140's gallery-chart epic, phase 3). Mirrors
# the NBA Analytics repo's tools/gif_clutch_shot_worm.R ("Closing-stretch
# score margin paired with shot locations") -- read-only reference, not
# ported file-for-file -- onto this repo's own phase-1 plumbing
# (tools/viz_common.R, tools/viz_gallery_helpers.R) and WNBA data model.
#
# WHAT DIFFERS FROM THE NBA ORIGINAL, AND WHY:
#   - The NBA script picks "the most recent close finish" from a generic
#     season cache. This chart is about ONE specific, named game: the game
#     that decided the 2026 WNBA Finals. tools/finals_series_backtest.R
#     already reconstructs that series game-by-game from real box scores
#     (CACHE_TEAM_BOX) -- this script sources it (with its own and
#     playoff_simulator.R's demo autoruns disabled via their documented
#     NO_AUTORUN env vars) and reuses its load_finals_games() helper plus
#     playoff_simulator.R's PLAYOFF_FORMATS$bo7$win_threshold, rather than
#     re-deriving "who swept whom" or hardcoding "best of 7 = 4 wins" locally.
#   - Court geometry is NOT ported from the NBA repo's tools/plot_shot_chart.R
#     (out of scope, read-only reference). A minimal half-court outline is
#     built inline below, using the WNBA-specific three-point arc distance
#     (~22.1 ft from the rim) that gallery chart #6
#     (tools/gif_shot_profile_shift.R, issue #145) already found empirically
#     -- NOT the NBA's 23.75 ft, which that same chart's header comment flags
#     as the wrong constant for this league's own court.
#   - Shot coordinates use the WNBA Stats API feed's x_legacy/y_legacy
#     1/10-ft convention (same transform already validated by chart #6:
#     x = x_legacy/10, y = y_legacy/10, hoop at (0, 5.25)), not the NBA
#     script's ESPN tracking coordinate_x/coordinate_y transform.
#
# WHY TWO SEPARATE GAME-ID NAMESPACES NEED RECONCILING: viz_load_pbp_season()
# returns ESPN event-level play-by-play (game_id = ESPN's numeric event id,
# e.g. 401918311) while viz_load_shots_season() returns the WNBA Stats API
# shot feed, whose game_id is in a completely different numbering scheme (see
# tools/gif_shot_profile_shift.R's header -- that chart never needed to join
# the two feeds on game_id, only aggregate each independently by season/team).
# This chart needs BOTH feeds for the SAME single game, so the shot feed's
# matching game_id is resolved by matching each candidate game's final
# score (summed from made shots only, since this feed carries field-goal
# attempts, not free throws) against the deciding game's real final score
# from CACHE_TEAM_BOX, allowing slack for the free-throw point gap.
#
# ZERO-FALLBACK CONTRACT (per issue #140/#144/#145/#146, overriding CLAUDE.md's
# general "fall back to a synthetic value" house rule for this chart family):
# if the Finals series cannot be reconstructed, the deciding game cannot be
# identified, or the deciding game's real play-by-play / shot-location rows
# are not yet present in the relevant per-season cache, the script stops via
# viz_stop_no_data() with nothing rendered -- it never substitutes a
# different game, a modelled margin, or synthetic shot locations.
#
# KNOWN REAL-WORLD DATA GAP (confirmed when this script was first run,
# 2026-11-12): the 2026 WNBA Finals went 7 games, with Game 7 (ESPN game_id
# 401918311, GS 68 @ ATL 63, 2026-10-31) deciding the series. That game's
# final score only exists in CACHE_TEAM_BOX because tools/espn_game7_fallback.R
# already patched it in from ESPN directly -- tools/diagnose_game7_sources.R
# documents that wehoop's own schedule/box feeds lagged behind ESPN on this
# exact game. Neither tools/espn_game7_fallback.R nor anything else in this
# repo backfills event-level play-by-play or shot-location data for that
# game: as of this script's first run, viz_pbp_2026.rds (freshly refreshed
# from wehoop) has zero rows for game_id 401918311, and viz_shots_2026.rds has
# no WNBA-Stats-API game matching that final score. That means this chart
# currently has no real closing-stretch data to plot and stops via
# viz_stop_no_data() -- expected, not a bug in this script. It will render for
# real the first time either feed catches up on Game 7.
#
# Data (all real, no fallback):
#   - CACHE_TEAM_BOX (config.R, via tools/finals_series_backtest.R's
#     load_finals_games()) -- which game decided the series, and its real
#     final score.
#   - tools/viz_gallery_helpers.R::viz_load_pbp_season(CURRENT_SEASON, ...) --
#     real ESPN play-by-play, filtered to the deciding game's final period's
#     closing 5 minutes for the real score margin.
#   - tools/viz_gallery_helpers.R::viz_load_shots_season(CURRENT_SEASON, ...)
#     -- real WNBA Stats API shot locations, filtered to the same game and
#     closing window.
#
# Usage: Rscript tools/gif_finals_closing_stretch.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
})

# ------------------------------------------------------------------------------
# 0. Locate repo root, source phase-1 plumbing, setwd() per CLAUDE.md
# ------------------------------------------------------------------------------
.SCRIPT_FILE_HINT <- "tools/gif_finals_closing_stretch.R"

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
if (!exists("CURRENT_SEASON", envir = .GlobalEnv)) {
  source(file.path(ROOT, "config.R"))
}

CACHE_DIR_RESOLVED <- viz_cache_dir(ROOT)

# ------------------------------------------------------------------------------
# 1. Reconstruct the Finals series via tools/finals_series_backtest.R (never
#    re-derive "who played whom and who won" locally). Both this file's and
#    playoff_simulator.R's demo autoruns are disabled via their own documented
#    env-var guards before sourcing.
# ------------------------------------------------------------------------------
Sys.setenv(WNBA_FINALS_BACKTEST_NO_AUTORUN = "1")
Sys.setenv(WNBA_PLAYOFF_SIM_NO_AUTORUN = "1")
if (!exists("load_finals_games", mode = "function") || !exists("PLAYOFF_FORMATS")) {
  source(file.path(ROOT, "tools", "finals_series_backtest.R"))
}

# A git worktree has none of the main checkout's gitignored data/ (CLAUDE.md:
# "data/ -- loose data artifacts ... separate from cache/"), the same known,
# pre-existing environment gap tools/viz_gallery_helpers.R's viz_cache_dir()
# already works around for cache/ via WNBA_VIZ_CACHE_DIR. CACHE_TEAM_BOX has
# no equivalent override in config.R, so if it is missing here (and only
# here -- this never touches the main checkout), fall back to the sibling
# main checkout's copy by climbing past the .worktrees/<branch> segment of
# this worktree's own path.
if (!file.exists(CACHE_TEAM_BOX)) {
  .root_norm <- gsub("\\\\", "/", ROOT)
  .wt_idx <- regexpr("/\\.worktrees/", .root_norm)
  if (.wt_idx[1] > 0) {
    .main_root <- substr(.root_norm, 1, .wt_idx[1] - 1)
    .alt_team_box <- file.path(.main_root, "data", basename(CACHE_TEAM_BOX))
    if (file.exists(.alt_team_box)) {
      CACHE_TEAM_BOX <- .alt_team_box
      cat(sprintf("[finals closing stretch] worktree has no %s; using main checkout's copy at %s.\n",
                  basename(CACHE_TEAM_BOX), CACHE_TEAM_BOX))
    }
  }
}

if (!file.exists(CACHE_TEAM_BOX)) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf("%s is missing -- cannot locate the Finals series.", CACHE_TEAM_BOX))
}

# The 2026 WNBA Finals matchup -- same pair tools/finals_series_backtest.R's
# own run_finals_backtest() defaults to, and confirmed present in CACHE_TEAM_BOX
# (season_type == 3, 2026) when this script was first written.
HIGH_ABB  <- "GS"
HIGH_NAME <- "Golden State Valkyries"
LOW_ABB   <- "ATL"
LOW_NAME  <- "Atlanta Dream"

games <- load_finals_games(HIGH_ABB, LOW_ABB, CURRENT_SEASON)
if (is.null(games) || nrow(games) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "no %d postseason games found between %s and %s in %s.",
    CURRENT_SEASON, HIGH_NAME, LOW_NAME, basename(CACHE_TEAM_BOX)
  ))
}

fmt <- PLAYOFF_FORMATS[["bo7"]]
games <- games %>%
  arrange(game_day) %>%
  mutate(
    wins_high_after = cumsum(high_won),
    wins_low_after  = cumsum(!high_won)
  )

decider_rows <- which(games$wins_high_after >= fmt$win_threshold | games$wins_low_after >= fmt$win_threshold)
if (length(decider_rows) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "the %d series between %s and %s has not reached a clinching game yet (%d game(s) played, best of %d).",
    CURRENT_SEASON, HIGH_NAME, LOW_NAME, nrow(games), length(fmt$home_flags)
  ))
}
decider <- games[decider_rows[1], ]
decider_date <- as.Date(decider$game_day)

cat(sprintf(
  "[finals closing stretch] deciding game: %s %d - %s %d on %s (Game %d of the series, series reconstructed via tools/finals_series_backtest.R::load_finals_games()).\n",
  HIGH_ABB, decider$score_high, LOW_ABB, decider$score_low, decider_date, decider$game
))

# ------------------------------------------------------------------------------
# 2. Resolve the deciding game's ESPN game_id from CACHE_TEAM_BOX (the key
#    viz_load_pbp_season()'s feed uses).
# ------------------------------------------------------------------------------
if (!exists("filter_real_franchises", mode = "function")) source(file.path(ROOT, "daily_ingest.R"))
box_all <- filter_real_franchises(readRDS(CACHE_TEAM_BOX)) %>%
  filter(season == CURRENT_SEASON, season_type == 3L, as.Date(game_date) == decider_date,
         team_abbreviation %in% c(HIGH_ABB, LOW_ABB),
         opponent_team_abbreviation %in% c(HIGH_ABB, LOW_ABB))

if (nrow(box_all) == 0 || !"game_id" %in% names(box_all) || anyNA(box_all$game_id[1])) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "could not resolve an ESPN game_id for the deciding game on %s in %s.",
    decider_date, basename(CACHE_TEAM_BOX)
  ))
}
DECIDER_GAME_ID <- box_all$game_id[1]

# ------------------------------------------------------------------------------
# 3. Real play-by-play for the deciding game (viz_load_pbp_season() itself
#    stops via viz_stop_no_data() if the whole season's cache can't be found
#    or fetched at all -- the check below handles the narrower case where the
#    season cache exists but this one game's rows are missing from it, e.g.
#    a wehoop ingestion lag of the kind tools/diagnose_game7_sources.R and
#    tools/espn_game7_fallback.R already document for this exact game).
# ------------------------------------------------------------------------------
pbp_season <- viz_load_pbp_season(CURRENT_SEASON, CACHE_DIR_RESOLVED, .SCRIPT_FILE_HINT)
game_pbp <- pbp_season %>% filter(game_id == DECIDER_GAME_ID)

if (nrow(game_pbp) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "viz_pbp_%d.rds has no play-by-play rows for the deciding game (ESPN game_id %s, %s %d - %s %d on %s) -- wehoop has not ingested this game's event log yet (the same lag tools/diagnose_game7_sources.R and tools/espn_game7_fallback.R already document for this exact game's box score).",
    CURRENT_SEASON, DECIDER_GAME_ID, HIGH_ABB, decider$score_high, LOW_ABB, decider$score_low, decider_date
  ))
}

last_period <- suppressWarnings(max(game_pbp$period_number, na.rm = TRUE))
closing_pbp <- game_pbp %>%
  filter(period_number == last_period, !is.na(home_score), !is.na(away_score),
         !is.na(end_quarter_seconds_remaining)) %>%
  arrange(end_quarter_seconds_remaining)

MARGIN_WINDOW_SEC <- 300  # final five minutes of the deciding period
if (nrow(closing_pbp) == 0 || min(closing_pbp$end_quarter_seconds_remaining, na.rm = TRUE) > MARGIN_WINDOW_SEC) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "the deciding game's play-by-play (ESPN game_id %s) has no usable score rows inside the final %d seconds of period %d.",
    DECIDER_GAME_ID, MARGIN_WINDOW_SEC, last_period
  ))
}

home_abb <- resolve_team_abbr(closing_pbp$home_team_abbrev[1])
away_abb <- resolve_team_abbr(closing_pbp$away_team_abbrev[1])

# Real home-team margin at each 15-second mark of the closing window, read
# directly from the play-by-play score -- nothing modelled or estimated.
margin_at <- function(t_sec) {
  rows <- closing_pbp[closing_pbp$end_quarter_seconds_remaining >= t_sec, , drop = FALSE]
  if (nrow(rows) == 0) return(NA_real_)
  rows <- rows[rows$end_quarter_seconds_remaining == min(rows$end_quarter_seconds_remaining), , drop = FALSE]
  as.numeric(rows$home_score[nrow(rows)] - rows$away_score[nrow(rows)])
}

time_points <- seq(MARGIN_WINDOW_SEC, 0, by = -15)
margins <- vapply(time_points, margin_at, numeric(1))
# Carry the last REAL known value forward across any gap in logged events --
# never an invented value, just the most recent actual score holding until
# the next real play-by-play row updates it.
for (k in seq_along(margins)[-1]) if (is.na(margins[k])) margins[k] <- margins[k - 1]
if (is.na(margins[1]) || anyNA(margins)) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "the deciding game's play-by-play (ESPN game_id %s) does not cover the final %d seconds closely enough to build a complete margin series.",
    DECIDER_GAME_ID, MARGIN_WINDOW_SEC
  ))
}

worm_df <- tibble(
  frame_step = seq_along(time_points),
  sec_left   = time_points,
  min_label  = sprintf("%d:%02d", time_points %/% 60, time_points %% 60),
  margin     = as.integer(round(margins))
)
margin_lim <- max(6, max(abs(worm_df$margin)) + 2)

# ------------------------------------------------------------------------------
# 4. Real shot locations for the SAME game, from the WNBA Stats API feed.
#    This feed's game_id namespace does not match the ESPN id resolved above
#    (see header note), so the matching game is found by comparing each
#    candidate's own running score against the deciding game's real final
#    score (slack allowed because this feed holds field-goal attempts only,
#    not free throws).
# ------------------------------------------------------------------------------
shots_season <- viz_load_shots_season(CURRENT_SEASON, CACHE_DIR_RESOLVED, .SCRIPT_FILE_HINT)

required_shot_cols <- c("x_legacy", "y_legacy", "shot_result", "team_tricode", "game_id",
                        "score_home", "score_away", "period", "clock")
missing_shot_cols <- setdiff(required_shot_cols, names(shots_season))
if (length(missing_shot_cols) > 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "viz_shots_%d.rds is missing expected column(s): %s.",
    CURRENT_SEASON, paste(missing_shot_cols, collapse = ", ")
  ))
}

# Two WNBA-Stats-API tricodes tools/viz_common.R's resolve_team_abbr() does
# not already cover (LAS, PDX) -- same fix tools/gif_shot_profile_shift.R
# (chart #6) already applied, confirmed against shot_quality_engine.R's own
# TEAM_TRICODE_MAP. Not needed for GS/ATL specifically, kept for correctness
# since viz_team_abbr() is applied to the whole season's feed below.
.LOCAL_TRICODE_FIX <- c(LAS = "LA", PDX = "POR")
norm_tricode <- function(x) ifelse(x %in% names(.LOCAL_TRICODE_FIX), unname(.LOCAL_TRICODE_FIX[x]), x)

shots_season <- shots_season %>%
  mutate(team_abbr = viz_team_abbr(norm_tricode(team_tricode)))

candidate_games <- shots_season %>%
  filter(team_abbr %in% c(HIGH_ABB, LOW_ABB)) %>%
  group_by(game_id) %>%
  filter(dplyr::n_distinct(team_abbr) == 2) %>%
  summarise(
    final_home = suppressWarnings(max(as.numeric(score_home), na.rm = TRUE)),
    final_away = suppressWarnings(max(as.numeric(score_away), na.rm = TRUE)),
    n_shots = dplyr::n(),
    .groups = "drop"
  ) %>%
  filter(is.finite(final_home), is.finite(final_away)) %>%
  mutate(
    # Either team could be "home" in this feed's own score_home/score_away --
    # try both assignments and keep whichever is closer to the real result.
    err = pmin(
      abs(final_home - decider$score_high) + abs(final_away - decider$score_low),
      abs(final_home - decider$score_low)  + abs(final_away - decider$score_high)
    )
  ) %>%
  arrange(err)

# Allows for the feed's missing free-throw points (empirically a few points
# per team on this feed, confirmed against this exact series' other games
# when this script was first written) without matching an unrelated game.
SHOT_SCORE_MATCH_TOLERANCE <- 10

if (nrow(candidate_games) == 0 || candidate_games$err[1] > SHOT_SCORE_MATCH_TOLERANCE) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "viz_shots_%d.rds has no %s/%s game whose running score matches the deciding game's real final score (%s %d - %s %d on %s) within %d point(s) -- the WNBA Stats API shot feed has not ingested this game yet.",
    CURRENT_SEASON, HIGH_ABB, LOW_ABB, HIGH_ABB, decider$score_high, LOW_ABB, decider$score_low,
    decider_date, SHOT_SCORE_MATCH_TOLERANCE
  ))
}
DECIDER_SHOTS_GAME_ID <- candidate_games$game_id[1]

# Parse this feed's ISO-8601-style "PT09M19.00S" clock into seconds remaining
# in its period (confirmed format via direct inspection of viz_shots cache).
parse_clock_sec <- function(clock) {
  m <- regmatches(clock, regexec("^PT0?([0-9]{1,2})M([0-9.]+)S$", clock))
  vapply(m, function(x) if (length(x) == 3) as.numeric(x[2]) * 60 + as.numeric(x[3]) else NA_real_, numeric(1))
}

game_shots <- shots_season %>%
  filter(game_id == DECIDER_SHOTS_GAME_ID) %>%
  mutate(
    sec_left = parse_clock_sec(clock),
    last_period = suppressWarnings(max(period, na.rm = TRUE))
  ) %>%
  filter(period == last_period, !is.na(sec_left), sec_left <= MARGIN_WINDOW_SEC,
         !is.na(x_legacy), !is.na(y_legacy)) %>%
  mutate(
    x = x_legacy / 10, y = y_legacy / 10,
    is_made = shot_result == "Made",
    made_label = ifelse(is_made, "Made", "Missed")
  )

if (nrow(game_shots) == 0) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "viz_shots_%d.rds's matched game (game_id %s) has no shot rows inside the final %d seconds of its last period.",
    CURRENT_SEASON, DECIDER_SHOTS_GAME_ID, MARGIN_WINDOW_SEC
  ))
}

team_colors <- c(
  setNames(get_wnba_team_color(home_abb, "primary"), home_abb),
  setNames(get_wnba_team_color(away_abb, "secondary"), away_abb)
)

# ------------------------------------------------------------------------------
# 5. Minimal half-court geometry, built inline (NOT ported from the NBA repo's
#    tools/plot_shot_chart.R, which is read-only reference). Half-court width
#    (50 ft) / depth (47 ft) / hoop position (0, 5.25) / key width (16 ft) are
#    shared basketball-court dimensions, same in both leagues. The three-point
#    arc radius is NOT assumed to match the NBA (23.75 ft): it uses ~22.1 ft,
#    the real WNBA distance gallery chart #6 (tools/gif_shot_profile_shift.R)
#    already found empirically, drawn as a single constant-radius arc with no
#    NBA-style corner straight segment (unverified against an official WNBA
#    rulebook corner-specific distance -- flagged here for a future reviewer
#    the same way chart #6 flagged its own arc-distance caveat).
# ------------------------------------------------------------------------------
WNBA_THREE_PT_RADIUS_FT <- 22.1
HOOP_XY <- c(0, 5.25)

arc_pts <- function(center, radius, from_deg = 0, to_deg = 180, n = 120) {
  theta <- seq(from_deg, to_deg, length.out = n) * pi / 180
  # chart-authenticity-allow: fixed court-geometry arc coordinates, not plotted data
  data.frame(x = center[1] + radius * cos(theta), y = center[2] + radius * sin(theta))
}

court_three_pt <- arc_pts(HOOP_XY, WNBA_THREE_PT_RADIUS_FT)
# chart-authenticity-allow: fixed court-geometry key outline coordinates, not plotted data
court_key <- data.frame(x = c(-8, 8, 8, -8, -8), y = c(0, 0, 19, 19, 0))
court_ft_circle <- arc_pts(c(0, 19), 6, 0, 360, n = 120)
# chart-authenticity-allow: fixed court-geometry backboard coordinates, not plotted data
court_backboard <- data.frame(x = c(-3, 3), y = c(4, 4))
court_hoop <- arc_pts(HOOP_XY, 0.75, 0, 360, n = 60)
# chart-authenticity-allow: fixed court-geometry outline coordinates, not plotted data
court_outline <- data.frame(x = c(-25, 25, 25, -25, -25), y = c(0, 0, 47, 47, 0))

draw_half_court <- function(line_color = "#334155", lw = 0.6) {
  list(
    geom_path(data = court_outline, aes(x, y), color = line_color, linewidth = lw),
    geom_path(data = court_key, aes(x, y), color = line_color, linewidth = lw),
    geom_path(data = court_ft_circle, aes(x, y), color = line_color, linewidth = lw),
    geom_path(data = court_three_pt, aes(x, y), color = line_color, linewidth = lw),
    geom_path(data = court_backboard, aes(x, y), color = line_color, linewidth = lw),
    geom_path(data = court_hoop, aes(x, y), color = line_color, linewidth = lw)
  )
}

# ------------------------------------------------------------------------------
# 6. Animation frames: real margin worm (left) paired with accumulating real
#    shot locations (right), stepping through the same closing window.
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), paste0("finals_closing_stretch_frames_", as.integer(Sys.time())))
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

n_steps <- nrow(worm_df)
frame_files <- character(n_steps)

for (s in seq_len(n_steps)) {
  cur_worm <- worm_df %>% filter(frame_step <= s)
  cur_time <- worm_df$sec_left[s]
  cur_shots <- game_shots %>% filter(sec_left >= cur_time)

  p_worm <- ggplot(cur_worm, aes(x = MARGIN_WINDOW_SEC - sec_left, y = margin)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = WNBA_COLORS$grid, linewidth = 0.8) +
    geom_ribbon(aes(ymin = 0, ymax = margin),
                fill = if (cur_worm$margin[nrow(cur_worm)] >= 0) team_colors[[home_abb]] else team_colors[[away_abb]],
                alpha = 0.25) +
    geom_line(color = WNBA_COLORS$accent, linewidth = 1.3) +
    geom_point(data = cur_worm %>% filter(frame_step == s), aes(x = MARGIN_WINDOW_SEC - sec_left, y = margin),
               color = "#ffffff", fill = team_colors[[home_abb]], shape = 21, size = 4.0, stroke = 1.5) +
    scale_x_continuous(breaks = seq(0, MARGIN_WINDOW_SEC, by = 60),
                       labels = c("5:00", "4:00", "3:00", "2:00", "1:00", "0:00"),
                       limits = c(0, MARGIN_WINDOW_SEC + 5)) +
    scale_y_continuous(limits = c(-margin_lim, margin_lim), labels = function(v) sprintf("%+d", as.integer(v))) +
    theme_wnba_dark(base_size = 11) +
    theme(plot.title = element_text(size = 12, face = "bold"),
          plot.subtitle = element_text(size = 9, color = WNBA_COLORS$subtext)) +
    labs(
      title = sprintf("Final Five Minutes: %s at %s", away_abb, home_abb),
      subtitle = sprintf("%s margin: %+d pts · Clock: %s", home_abb, cur_worm$margin[s], cur_worm$min_label[s]),
      x = sprintf("Game Clock Remaining in Period %d", last_period),
      y = sprintf("%s lead (points)", home_abb)
    )

  p_court <- ggplot() +
    draw_half_court() +
    coord_fixed(xlim = c(-25, 25), ylim = c(0, 42)) +
    theme_wnba_dark(base_size = 11) +
    theme(axis.text = element_blank(), axis.title = element_blank(), axis.ticks = element_blank(),
          panel.grid = element_blank(), plot.title = element_text(size = 12, face = "bold"),
          plot.subtitle = element_text(size = 9, color = WNBA_COLORS$subtext),
          legend.position = "bottom", legend.margin = margin(t = -5)) +
    labs(title = "Closing Stretch: Shot Locations",
         subtitle = sprintf("Shots taken through %s: %d total", worm_df$min_label[s], nrow(cur_shots)))

  if (nrow(cur_shots) > 0) {
    p_court <- p_court +
      geom_point(data = cur_shots, aes(x = x, y = y, color = team_abbr, shape = made_label),
                 size = 3.5, stroke = 1.2, alpha = 0.88) +
      scale_color_manual(name = "Team", values = team_colors) +
      scale_shape_manual(name = "Outcome", values = c(Made = 16, Missed = 4))
  }

  combined <- p_worm + p_court + plot_layout(widths = c(1.35, 1.0)) +
    plot_annotation(
      title = "WNBA Finals, Closing Stretch: Score Margin and Shot Locations",
      subtitle = sprintf("Game %d of the %d Finals (%s), %s", decider$game, CURRENT_SEASON, decider_date,
                         if (decider$high_won) sprintf("%s clinch", HIGH_NAME) else sprintf("%s clinch", LOW_NAME)),
      caption = "Source: ESPN play-by-play and WNBA Stats API shot data via wehoop.",
      theme = theme(
        plot.background = element_rect(fill = WNBA_COLORS$bg, color = NA),
        plot.title = element_text(size = 13, face = "bold", color = WNBA_COLORS$text),
        plot.subtitle = element_text(size = 10, color = WNBA_COLORS$subtext),
        plot.caption = element_text(size = 8, color = WNBA_COLORS$subtext)
      )
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = combined, width = 12, height = 6.2, dpi = 110, bg = WNBA_COLORS$bg)
  frame_files[s] <- frame_path
}

# ------------------------------------------------------------------------------
# 7. Encode animated artifact (GIF + reduced-motion PNG) & sync to web media
# ------------------------------------------------------------------------------
out_gif <- file.path(CACHE_DIR_RESOLVED, "gif_finals_closing_stretch.gif")
out_png <- file.path(CACHE_DIR_RESOLVED, "gif_finals_closing_stretch.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 6,
  width            = 1200,
  height           = 620
)
unlink(tmp_frame_dir, recursive = TRUE)

media_dir <- file.path(ROOT, "web", "public", "media")
if (!dir.exists(media_dir)) dir.create(media_dir, recursive = TRUE)
file.copy(out_gif, file.path(media_dir, basename(out_gif)), overwrite = TRUE)
file.copy(out_png, file.path(media_dir, basename(out_png)), overwrite = TRUE)

cat(sprintf(
  "[SUCCESS] Generated Finals Closing Stretch:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media dir: %s\n",
  out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_dir
))
