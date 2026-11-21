# ==============================================================================
# export_visual_media_index.R
#
# Publishes web/public/data/visual_media_index.json, the index the Gallery page
# reads at build time and the landing slideshow reads in the browser
# (front-office#210).
#
# Per item: generated_at is that file's OWN modification time (UTC ISO-8601), never
# the run's start time; duration_ms is one GIF loop (NA -> JSON null when the GIF
# cannot be read) and is absent for images. Only files actually present in the media
# directory AND described in MLB_MEDIA_METADATA are indexed: a metadata entry whose
# file (or still frame) is absent produces no item, and a file with no metadata is
# logged and omitted (no placeholder or invented caption is ever written). The JSON
# is written atomically (temp file in the same directory, then rename).
# MLB keeps three extra fields per item: previewPng, phase, categoryLabel.
# Needs R/gif_duration.R sourced.
#
# Sourced by tests/test_visual_media_index.R (functions only) and run as a pipeline
# stage by run_full_pipeline.R (the stage calls run_export_visual_media_index()).
# ==============================================================================

# Titles, categories, category labels, phases, still frames and descriptions moved
# verbatim from the former MLB_VISUAL_MEDIA_ITEMS list in web/lib/visualMedia.ts;
# order is gallery order.
# gif_payroll_efficiency_bubble.gif is intentionally absent: tools/gif_payroll_efficiency_bubble.R
# plots a hand-typed TEAM_PAYROLL_2026 table and imputes 35.0 WAR / 150.0 payroll for any
# team it cannot match, so it is not built from real data end to end. Its files are skipped
# with a warning until that script is rebuilt on real payroll data; add an entry back then.
MLB_MEDIA_METADATA <- list(
  "gif_division_standings_race.gif" = list(
    title = "6-Division Standings Win Race",
    category = "standings",
    categoryLabel = "Standings & Parity",
    phase = 1L,
    previewPng = "gif_division_standings_race.png",
    desc = "Animated cumulative win bar race across 162 games faceted into all 6 MLB divisions with dynamic re-ranking and official team logos."
  ),
  "gif_point_diff_race.gif" = list(
    title = "Cumulative Run Differential Race",
    category = "standings",
    categoryLabel = "Standings & Parity",
    phase = 1L,
    previewPng = "gif_point_diff_race.png",
    desc = "30-team cumulative run differential (+/-) trajectory race faceted across divisions with zero baseline and leading team logos."
  ),
  "gif_playoff_prob_bump.gif" = list(
    title = "Postseason Probability Progression",
    category = "standings",
    categoryLabel = "Standings & Parity",
    phase = 1L,
    previewPng = "gif_playoff_prob_bump.png",
    desc = "AL and NL simulated postseason qualification progression race across chronological milestone dates with seed thresholds."
  ),
  "gif_pythag_luck_scatter.gif" = list(
    title = "Pythagorean Luck & RS vs. RA Scatter",
    category = "standings",
    categoryLabel = "Standings & Parity",
    phase = 1L,
    previewPng = "gif_pythag_luck_scatter.png",
    desc = "4-quadrant dynamic scatter animation tracking cumulative Runs Scored vs Runs Allowed with Pythagorean luck halos."
  ),
  "gif_bullpen_fatigue_race.gif" = list(
    title = "Bullpen Fatigue & Arm-Stress Race",
    category = "standings",
    categoryLabel = "Standings & Parity",
    phase = 1L,
    previewPng = "gif_bullpen_fatigue_race.png",
    desc = "30-team composite bullpen fatigue trajectory race across 162 games with 70 and 85 exhaustion warning thresholds."
  ),
  "gif_bracket_progression.gif" = list(
    title = "12-Team Postseason Bracket Progression",
    category = "postseason",
    categoryLabel = "October Postseason",
    phase = 2L,
    previewPng = "gif_bracket_progression.png",
    desc = "The real 2026 postseason bracket, round by round. Under each team: its regular-season record, or the score of the series it won to get there."
  ),
  "gif_world_series_wpa_worm.gif" = list(
    title = "World Series Win Probability, Play by Play",
    category = "postseason",
    categoryLabel = "October Postseason",
    phase = 2L,
    previewPng = "gif_world_series_wpa_worm.png",
    desc = "Win probability after every plate appearance of all five 2026 World Series games, with the play that moved it."
  ),
  "gif_pennant_showdown.gif" = list(
    title = "Pennant Clinch Showdown & WS Banner",
    category = "postseason",
    categoryLabel = "October Postseason",
    phase = 2L,
    previewPng = "gif_pennant_showdown.png",
    desc = "Both League Championship Series game by game with real scores, ending on the two pennant winners, their records and the World Series result."
  ),
  "gif_postseason_leverage.gif" = list(
    title = "Postseason Relief Workload & Leverage",
    category = "postseason",
    categoryLabel = "October Postseason",
    phase = 2L,
    previewPng = "gif_postseason_leverage.png",
    desc = "Batters faced by the ten most-used relievers of the 2026 postseason, round by round, coloured by how high the leverage was when they pitched."
  ),
  "gif_rolling_pythag_momentum.gif" = list(
    title = "162-Game Rolling Pythagorean Momentum",
    category = "trends",
    categoryLabel = "Season Trends",
    phase = 3L,
    previewPng = "gif_rolling_pythag_momentum.png",
    desc = "162-game rolling 10-game expected Pythagorean win % momentum curves with enlarged, high-contrast team logos."
  ),
  "gif_trade_deadline_splits.gif" = list(
    title = "Trade Deadline Inflection Splits",
    category = "trends",
    categoryLabel = "Season Trends",
    phase = 3L,
    previewPng = "gif_trade_deadline_splits.png",
    desc = "Pre vs. Post August 1st Trade Deadline performance inflection dumbbell race tracking buyer acceleration vs seller regression."
  ),
  "gif_home_away_divergence.gif" = list(
    title = "Home vs. Road Win % Divergence",
    category = "trends",
    categoryLabel = "Season Trends",
    phase = 3L,
    previewPng = "gif_home_away_divergence.png",
    desc = "Home vs. Road win percentage divergence split-bar race across all 30 MLB franchises with team logos."
  ),
  "gif_clutch_wpa_swings.gif" = list(
    title = "High-Leverage Clutch Late-Inning WPA",
    category = "trends",
    categoryLabel = "Season Trends",
    phase = 3L,
    previewPng = "gif_clutch_wpa_swings.png",
    desc = "Cumulative Win Probability Added (WPA) earned in high-leverage late-inning rallies and 1-run contests."
  ),
  "gif_lineup_power_scatter.gif" = list(
    title = "Lineup Power Matrix (ISO vs. wRC+)",
    category = "sabermetrics",
    categoryLabel = "Sabermetric Scatters",
    phase = 4L,
    previewPng = "gif_lineup_power_scatter.png",
    desc = "4-quadrant dynamic scatter animation for ISO vs. wRC+ lineup power and on-base run creation profiles."
  ),
  "gif_rotation_command_scatter.gif" = list(
    title = "Rotation Command Matrix (K-BB% vs. FIP)",
    category = "sabermetrics",
    categoryLabel = "Sabermetric Scatters",
    phase = 4L,
    previewPng = "gif_rotation_command_scatter.png",
    desc = "4-quadrant pitching staff command and dominance matrix with inverted run-prevention axis and team logos."
  ),
  "gif_baserunning_diamond.gif" = list(
    title = "Basepath Aggression & Value (SB% vs. BsR)",
    category = "sabermetrics",
    categoryLabel = "Sabermetric Scatters",
    phase = 4L,
    previewPng = "gif_baserunning_diamond.png",
    desc = "Basepath aggression and baserunning value (SB% vs wBsR) animated diamond progression across the league."
  ),
  "gif_defense_oaa_radar.gif" = list(
    title = "Defensive Range & Conversion (OAA vs. DRS)",
    category = "sabermetrics",
    categoryLabel = "Sabermetric Scatters",
    phase = 4L,
    previewPng = "gif_defense_oaa_radar.png",
    desc = "Defensive efficiency & diamond coverage (Fielding Runs vs Total Defensive Runs) dynamic radar progression."
  ),
  "gif_season_calendar_heatmap.gif" = list(
    title = "Season in 60s: 30-Team Calendar Heatmap",
    category = "meta",
    categoryLabel = "Synthesis & Retrospective",
    phase = 5L,
    previewPng = "gif_season_calendar_heatmap.png",
    desc = "30-team by 162-game chronological micro-calendar heatmap sweep with green/red outcome coding from April to October."
  ),
  "gif_trophy_lift_champions.gif" = list(
    title = "World Series Trophy Lift Champions Finale",
    category = "meta",
    categoryLabel = "Synthesis & Retrospective",
    phase = 5L,
    previewPng = "gif_trophy_lift_champions.png",
    desc = "Glowing Commissioner's Trophy crest reveal with 30 silver pennant pins, champion emblem, and celebratory gold confetti burst."
  )
)

#' @param dir      media directory
#' @param metadata named list keyed by GIF basename:
#'                 list(title, category, categoryLabel, phase, previewPng, desc)
#' @return list of items in metadata order (possibly empty)
build_media_index <- function(dir, metadata) {
  present <- if (dir.exists(dir)) list.files(dir) else character(0)
  # A described entry's still frame (previewPng) is its reduced-motion companion, not unknown.
  stills <- unlist(lapply(metadata, function(m) m$previewPng), use.names = FALSE)
  unknown <- setdiff(present, c(names(metadata), stills))
  if (length(unknown) > 0L) {
    warning(sprintf("build_media_index: no metadata for %d file(s), omitted from visual_media_index: %s",
                    length(unknown), paste(unknown, collapse = ", ")), call. = FALSE)
  }
  index <- list()
  for (bname in intersect(names(metadata), present)) {
    f <- file.path(dir, bname)
    meta <- metadata[[bname]]
    if (!(is.character(meta$previewPng) && length(meta$previewPng) == 1L &&
          meta$previewPng %in% present)) {
      warning(sprintf("build_media_index: %s has no still frame (%s) in %s, omitted from visual_media_index",
                      bname, paste(meta$previewPng, collapse = ""), dir), call. = FALSE)
      next
    }
    is_gif <- grepl("[.]gif$", bname, ignore.case = TRUE)
    item <- list(
      id            = sub("\\.[^.]+$", "", bname),
      generated_at  = format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      filename      = bname,
      title         = meta$title,
      category      = meta$category,
      categoryLabel = meta$categoryLabel,
      phase         = meta$phase,
      previewPng    = meta$previewPng,
      description   = meta$desc,
      type          = if (is_gif) "gif" else "image",
      size_bytes    = file.size(f)
    )
    if (is_gif) item$duration_ms <- gif_duration_ms(f)
    index[[length(index) + 1L]] <- item
  }
  index
}

# NA must publish as null (never the string "NA"); scoped to this index only.
visual_media_index_json <- function(index) {
  as.character(jsonlite::toJSON(index, auto_unbox = TRUE, pretty = TRUE,
                                null = "null", na = "null"))
}

# Atomic write: temp file beside the target, then rename over it; creates the directory.
write_text_atomic <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(basename(path), "."), tmpdir = dirname(path), fileext = ".tmp")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  writeLines(text, tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) {
    if (!file.copy(tmp, path, overwrite = TRUE)) stop("could not write ", path)
  }
  invisible(path)
}

run_export_visual_media_index <- function(media_dir = file.path("web", "public", "media"),
                                          out_file = file.path("web", "public", "data", "visual_media_index.json"),
                                          metadata = MLB_MEDIA_METADATA) {
  if (!exists("gif_duration_ms", mode = "function")) source("R/gif_duration.R")
  index <- build_media_index(media_dir, metadata)
  if (length(index) == 0L) stop("visual_media_index: no indexable media found in ", media_dir)
  write_text_atomic(visual_media_index_json(index), out_file)
  message(sprintf(">>> visual_media_index.json: %d items", length(index)))
  invisible(index)
}
