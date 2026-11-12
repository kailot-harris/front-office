# ==============================================================================
# tools/gif_shot_profile_shift.R
# Path: tools/gif_shot_profile_shift.R
#
# WNBA Team Shot-Profile Shift: three-point-attempt share, CURRENT_SEASON
# (config.R, 2026) vs. the season before it (2025). Gallery chart #6 of
# GitHub issue #145 (part of #140's gallery-chart epic, phase 2). Mirrors the
# NBA Analytics repo's tools/gif_shot_profile_shift.R (same NBA counterpart,
# read-only reference) but ported onto this repo's own phase-1 plumbing
# (tools/viz_common.R, tools/viz_gallery_helpers.R) and this repo's own data
# model -- 15 WNBA franchises, no conferences/divisions, non-3-letter
# abbreviations (GS, LA, LV, NY), and a shot feed with a genuinely different
# schema from the NBA original's ESPN play-by-play coordinates.
#
# CLASSIFICATION RULE -- deliberately UNCHANGED from the NBA original, per
# issue #145's instruction not to invent a different threshold for WNBA since
# the court dimensions are the same: a shot is a three when it is at least
# 23.75 ft from the rim, OR in the corner (22 ft or more from the court
# centerline and within 14 ft of the baseline). Applied identically to both
# seasons so the comparison is like for like.
#
# CAVEAT (flag for a future reviewer, not acted on here per explicit
# instruction): the WNBA's real top-of-the-arc three-point line sits at
# roughly 22.1 ft from the rim, inside the NBA's 23.75 ft arc distance ported
# above. A first real run of this script (2026-11-12) found league three-point
# share of only ~10% both seasons -- implausibly low for a league that
# actually shoots roughly 30%+ of its attempts from three -- consistent with
# this threshold under-counting above-the-break WNBA threes that fall short
# of 23.75 ft. The classification is kept exactly as issue #145 specifies
# (do not invent a different threshold for WNBA); this note exists so a human
# revisiting this chart's numbers knows why they look low and that the fix,
# if wanted, is a WNBA-specific arc distance, not a bug in this script's
# plumbing or data.
#
# WHY GEOMETRIC RECLASSIFICATION, NOT THE FEED'S OWN shot_value COLUMN:
#   wehoop::load_wnba_stats_shots() already carries a `shot_value` column (2
#   or 3) per shot_quality_engine.R's own documented schema notes below -- but
#   issue #145 asks for the SAME court-location classification rule the NBA
#   script applies (dist-from-rim / corner geometry), not the feed's own
#   pre-labeled value, so this chart's three-point definition is identically
#   derived across both sports' gallery charts rather than mixing a
#   geometry-derived NBA rule with a feed-labeled WNBA one.
#
# SCHEMA, confirmed against this repo's own shot_quality_engine.R (which
# already pulls this exact feed) rather than assumed:
#   wehoop::load_wnba_stats_shots(seasons = <year>) returns one row per real
#   shot ATTEMPT (field goals only, no free throws, per shot_quality_engine.R)
#   with: `shot_distance` (ft), `x_legacy`/`y_legacy` (court coordinates, same
#   1/10-ft convention as stats.nba.com's LOC_X/LOC_Y: x_legacy in
#   [-250, 250], y_legacy >= -50), `shot_result` ("Made"/"Missed"),
#   `shot_value` (2 or 3, unused here -- see above), `team_tricode`, `game_id`
#   (WNBA-Stats-API namespace, chronologically ordered ascending within a
#   season per shot_quality_engine.R's own sort-order note -- there is no
#   date column on this feed, confirmed by that same file).
#
# TEAM TRICODE MAPPING: most WNBA-Stats-API team_tricode values either equal
# this repo's own WNBA_TEAMS abbreviation or are already covered by
# tools/viz_common.R's resolve_team_abbr() (.ALT_ABBR_TO_STANDARD covers
# NYL->NY, PHO->PHX, LVA->LV, GSV->GS, WAS->WSH). Two are NOT covered there
# and would otherwise fall through unresolved: LAS (LA Sparks) and PDX
# (Portland Fire) -- empirically confirmed by shot_quality_engine.R's own
# TEAM_TRICODE_MAP (LAS = "LA", PDX = "POR"). Rather than editing the shared,
# out-of-scope viz_common.R, those two are normalized locally below before
# handing everything to resolve_team_abbr() for the rest.
#
# NO PER-GAME DATE: because this feed has no date column, animation frames
# are cut by cumulative GAME COUNT within CURRENT_SEASON (ascending game_id,
# confirmed chronological order -- see above) rather than by calendar date
# (viz_frame_dates() needs real Date values this feed cannot supply). Last
# season (2025) is used only as a single frozen season-total baseline per
# team, exactly as the NBA original's own "last season" cache is a static
# comparison point, never itself animated.
#
# Data (all real, no fallback):
#   - tools/viz_gallery_helpers.R::viz_load_shots_season(2025, ...) -- last
#     season's shots, static baseline.
#   - tools/viz_gallery_helpers.R::viz_load_shots_season(2026, ...) -- this
#     season's shots, animated progressively by game count.
#   Per issue #145, the script stops via viz_stop_no_data() if EITHER
#   season's shot cache is missing and cannot be refreshed -- not just
#   CURRENT_SEASON's.
#
# Usage: Rscript tools/gif_shot_profile_shift.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

# ------------------------------------------------------------------------------
# 0. Locate repo root, source phase-1 plumbing, setwd() per CLAUDE.md
# ------------------------------------------------------------------------------
.SCRIPT_FILE_HINT <- "tools/gif_shot_profile_shift.R"

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
LAST_SEASON <- CURRENT_SEASON - 1L

# ------------------------------------------------------------------------------
# 1. Load both seasons' real shot data (viz_load_shots_season() stops via
#    viz_stop_no_data() -- no synthetic fallback -- if either is unavailable)
# ------------------------------------------------------------------------------
last_raw <- viz_load_shots_season(LAST_SEASON, CACHE_DIR_RESOLVED, .SCRIPT_FILE_HINT)
cur_raw  <- viz_load_shots_season(CURRENT_SEASON, CACHE_DIR_RESOLVED, .SCRIPT_FILE_HINT)

required_cols <- c("x_legacy", "y_legacy", "shot_value", "team_tricode", "game_id")
for (nm in c("last_raw", "cur_raw")) {
  df <- get(nm)
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
      "the %s shots cache is missing expected column(s): %s.",
      if (nm == "last_raw") LAST_SEASON else CURRENT_SEASON, paste(missing_cols, collapse = ", ")
    ))
  }
}

# ------------------------------------------------------------------------------
# 2. Team tricode normalization (see header note) + court-location three-point
#    classification (same NBA threshold, see header note -- NOT re-derived)
# ------------------------------------------------------------------------------
# Covers the two WNBA-Stats-API tricodes tools/viz_common.R's resolve_team_abbr()
# does not already map (LAS, PDX) -- confirmed via shot_quality_engine.R's own
# empirically-derived TEAM_TRICODE_MAP, not guessed.
.LOCAL_TRICODE_FIX <- c(LAS = "LA", PDX = "POR")

normalize_and_classify <- function(df) {
  df %>%
    filter(!is.na(x_legacy), !is.na(y_legacy), shot_value %in% c(2, 3)) %>%
    mutate(
      team_tricode_fixed = ifelse(team_tricode %in% names(.LOCAL_TRICODE_FIX),
                                   unname(.LOCAL_TRICODE_FIX[team_tricode]), team_tricode),
      team = viz_team_abbr(team_tricode_fixed),
      x = x_legacy / 10, y = y_legacy / 10,
      dist = sqrt(x^2 + (y - 5.25)^2),
      is_three = dist >= 23.75 | (abs(x) >= 22 & y <= 14)
    ) %>%
    filter(team %in% names(WNBA_TEAM_COLORS))
}

last <- normalize_and_classify(last_raw)
cur  <- normalize_and_classify(cur_raw)

# ------------------------------------------------------------------------------
# 3. Season-level baseline (last season) and sufficiency checks
# ------------------------------------------------------------------------------
last_share <- last %>%
  group_by(team) %>%
  summarise(last_share = mean(is_three), last_n = n(), .groups = "drop")

cur_games_sorted <- sort(unique(as.numeric(as.character(cur$game_id))))
n_teams_last <- nrow(last_share)
n_teams_cur  <- length(unique(cur$team))
n_games_cur  <- length(cur_games_sorted)

if (n_teams_last < 10 || n_teams_cur < 10 || n_games_cur < 5) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "not enough shot data (%d teams in %d, %d teams and %d games in %d).",
    n_teams_last, LAST_SEASON, n_teams_cur, n_games_cur, CURRENT_SEASON
  ))
}

cat(sprintf(
  "[shot profile] league three-point share: %d %.1f%% (%s shots), %d %.1f%% (%s shots, %d games)\n",
  LAST_SEASON, 100 * mean(last$is_three), format(nrow(last), big.mark = ","),
  CURRENT_SEASON, 100 * mean(cur$is_three), format(nrow(cur), big.mark = ","), n_games_cur
))

# ------------------------------------------------------------------------------
# 4. Final (season-to-date) snapshot, team order, axis range, logos
# ------------------------------------------------------------------------------
final <- cur %>%
  group_by(team) %>%
  summarise(share = mean(is_three), .groups = "drop") %>%
  inner_join(last_share, by = "team") %>%
  mutate(delta = share - last_share)

if (nrow(final) < 10) {
  viz_stop_no_data(.SCRIPT_FILE_HINT, sprintf(
    "only %d teams had three-point share data in both %d and %d after joining.",
    nrow(final), LAST_SEASON, CURRENT_SEASON
  ))
}

team_order <- final %>% arrange(delta) %>% pull(team)
x_rng <- range(c(final$share, final$last_share)) + c(-0.04, 0.04)
LOGOS <- viz_logo_map(cache_dir = CACHE_DIR_RESOLVED, script = .SCRIPT_FILE_HINT)
LOGOS <- LOGOS[team_order]

# ------------------------------------------------------------------------------
# 5. Animation frames, cut by cumulative GAME COUNT (ascending game_id) since
#    this feed has no date column (see header note)
# ------------------------------------------------------------------------------
n_frames <- min(10L, n_games_cur)
cut_idx <- unique(round(seq(1, n_games_cur, length.out = n_frames)))
cut_idx[length(cut_idx)] <- n_games_cur
game_cuts <- cur_games_sorted[cut_idx]

cur$game_id_num <- as.numeric(as.character(cur$game_id))

plots <- lapply(game_cuts, function(cutoff) {
  games_through <- sum(cur_games_sorted <= cutoff)
  snap <- cur %>%
    filter(game_id_num <= cutoff) %>%
    group_by(team) %>%
    summarise(share = mean(is_three), n = n(), .groups = "drop") %>%
    inner_join(last_share, by = "team") %>%
    mutate(team = factor(team, levels = team_order), up = share >= last_share)

  ggplot(snap, aes(y = team)) +
    geom_segment(aes(x = last_share, xend = share, yend = team, colour = up), linewidth = 1.6, alpha = 0.85) +
    geom_point(aes(x = last_share), shape = 21, size = 3, stroke = 1, fill = WNBA_COLORS$bg, colour = "#94A3B8") +
    geom_point(aes(x = share, colour = up), size = 3.4) +
    ggimage::geom_image(aes(x = x_rng[1] + 0.006, image = LOGOS[as.character(team)]), size = 0.026, by = "height") +
    scale_colour_manual(values = c(`TRUE` = "#38BDF8", `FALSE` = "#F59E0B"), guide = "none") +
    scale_x_continuous(labels = function(v) paste0(round(100 * v), "%"), limits = x_rng) +
    scale_y_discrete(drop = FALSE) +
    labs(
      title = sprintf("Who Changed Their Shot Diet? Three-Point Share, %d vs %d", CURRENT_SEASON, LAST_SEASON),
      subtitle = sprintf(
        "Through %d of %d games this season. Hollow dot: %d season. Solid dot: %d season (blue = more threes, amber = fewer).",
        games_through, n_games_cur, LAST_SEASON, CURRENT_SEASON
      ),
      x = "Share of field-goal attempts taken from three", y = NULL,
      caption = "Source: WNBA Stats API shot data via wehoop. Threes classified by court location in both seasons."
    ) +
    theme_wnba_dark(base_size = 12) +
    theme(panel.grid.major.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
})

# ------------------------------------------------------------------------------
# 6. Encode animated artifact (GIF + reduced-motion PNG)
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_shot_profile_shift",
  root       = ROOT,
  cache_dir  = CACHE_DIR_RESOLVED,
  fps        = 2,
  hold_last_frames = 8,
  width      = 1000,
  height     = 820
)
