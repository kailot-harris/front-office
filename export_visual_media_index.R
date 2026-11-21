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
# directory AND described in WNBA_MEDIA_METADATA are indexed: a metadata entry whose
# file is absent produces no item, and a file with no metadata is logged and omitted
# (no placeholder item is ever written). The JSON is written atomically (temp file
# in the same directory, then rename). Needs R/gif_duration.R sourced.
#
# Sourced by tests/test_visual_media_index.R (functions only) and run as a pipeline
# stage by run_full_pipeline.R (the stage calls run_export_visual_media_index()).
# ==============================================================================

# Titles, categories and descriptions moved verbatim from the former
# WNBA_GALLERY_ITEMS list in web/components/GalleryClient.tsx; order is gallery order.
# gif_finals_closing_stretch.gif is intentionally absent: it was a "not yet rendered"
# placeholder with no media on disk (wehoop has not ingested that game's play-by-play).
# Add its entry back once tools/gif_finals_closing_stretch.R has rendered from real data.
# None of the listed charts is rendered from simulated data. The tools/ scripts refuse
# synthetic rows and abort instead.
WNBA_MEDIA_METADATA <- list(
  "gif_elo_rank_bump.gif" = list(
    title = "League-Wide Elo Rating & Rank Evolution",
    category = "standings",
    desc = "Animated bump chart illustrating all 15 WNBA teams Elo rating movements and ranking transitions across the season."
  ),
  "gif_point_diff_race.gif" = list(
    title = "Cumulative Point Differential Race",
    category = "standings",
    desc = "Animated race chart displaying cumulative scoring differential trajectories across all 15 WNBA franchises."
  ),
  "gif_standings_race.gif" = list(
    title = "League-Wide Standings Wins Race",
    category = "standings",
    desc = "Animated cumulative regular-season wins race across all 15 WNBA teams in one combined table \u2014 the league has run no conferences or divisions since 2022."
  ),
  "gif_net_rating_quadrant.gif" = list(
    title = "Offensive vs Defensive Efficiency Dynamics",
    category = "efficiency",
    desc = "Evolution of offensive rating vs defensive rating across all 15 teams with championship quadrant dividers."
  ),
  "gif_pace_efficiency_quadrant.gif" = list(
    title = "Pace vs Net Rating Efficiency Matrix",
    category = "efficiency",
    desc = "Pace (possessions/40 min) vs Net Rating scatter animating team tactical styles from fast & dominant to methodical grinders."
  ),
  "gif_shot_profile_shift.gif" = list(
    title = "Team Shot-Profile Shift: Three-Point Share vs Last Season",
    category = "shots",
    desc = "Share of each team's field-goal attempts taken from three this season against last season (2026 vs. 2025). Known limitation, documented in the rendering script itself: this chart currently classifies arc distance using the NBA's unchanged 23.75ft threshold rather than the WNBA's real ~22.1ft arc, which understates the league's true 3PT attempt share."
  ),
  "gif_rapm_leaders_2026.gif" = list(
    title = "Top-10 Offensive & Defensive RAPM \u2014 2026",
    category = "players",
    desc = "The top 10 players by Offensive and Defensive Regularized Adjusted Plus-Minus (ORAPM/DRAPM) from the full 2026 season, revealed from 10th to 1st."
  ),
  "gif_rapm_leaders_by_season.gif" = list(
    title = "RAPM Leaders Across Seasons",
    category = "players",
    desc = "Top RAPM leaders animated across 8 seasons (2019-2026), each an independent per-season fit."
  ),
  "gif_upset_timeline.gif" = list(
    title = "Underdog Upset Timeline & Giant-Killer Tracker",
    category = "predictions",
    desc = "Chronological timeline of genuine, resolved upsets where pre-game win expectation favored the loser, tracking giant-killing franchises."
  ),
  "gif_forecast_calibration.gif" = list(
    title = "Forecast Calibration: Predicted vs Actual",
    category = "predictions",
    desc = "Predicted-vs-actual calibration plot built only from genuine, resolved model forecasts."
  ),
  "gif_playoff_bracket_progression.gif" = list(
    title = "2026 Playoff Bracket Progression",
    category = "playoffs",
    desc = "The 2026 playoff bracket progressing round-by-round \u2014 Round 1 to Semifinals to Finals \u2014 built from real series results."
  )
)

#' @param dir      media directory
#' @param metadata named list keyed by basename: list(title, category, desc)
#' @return list of items in metadata order (possibly empty)
build_media_index <- function(dir, metadata) {
  present <- if (dir.exists(dir)) list.files(dir) else character(0)
  unknown <- setdiff(present, names(metadata))
  # A described GIF's still frame (<stem>.png) is its reduced-motion companion, not unknown.
  stems <- sub("[.]gif$", "", grep("[.]gif$", names(metadata), value = TRUE))
  unknown <- setdiff(unknown, paste0(stems, ".png"))
  if (length(unknown) > 0L) {
    warning(sprintf("build_media_index: no metadata for %d file(s), omitted from visual_media_index: %s",
                    length(unknown), paste(unknown, collapse = ", ")), call. = FALSE)
  }
  index <- list()
  for (bname in intersect(names(metadata), present)) {
    f <- file.path(dir, bname)
    meta <- metadata[[bname]]
    is_gif <- grepl("[.]gif$", bname, ignore.case = TRUE)
    item <- list(
      id           = sub("\\.[^.]+$", "", bname),
      generated_at = format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      filename     = bname,
      title        = meta$title,
      category     = meta$category,
      description  = meta$desc,
      type         = if (is_gif) "gif" else "image",
      size_bytes   = file.size(f)
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
                                          metadata = WNBA_MEDIA_METADATA) {
  if (!exists("gif_duration_ms", mode = "function")) source("R/gif_duration.R")
  index <- build_media_index(media_dir, metadata)
  if (length(index) == 0L) stop("visual_media_index: no indexable media found in ", media_dir)
  write_text_atomic(visual_media_index_json(index), out_file)
  message(sprintf(">>> visual_media_index.json: %d items", length(index)))
  invisible(index)
}
