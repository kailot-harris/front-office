# ==============================================================================
# tools/viz_gallery_helpers.R
#
# Ported from the NBA Analytics repo's tools/viz_gallery_helpers.R (GitHub
# issue #144, part of #140's gallery-chart epic). Shared plumbing for the
# WNBA gallery charts that will be added in phases 2-4 of #140 (12 charts,
# tools/gif_*.R -- separate issues, not part of this port). Source
# tools/viz_common.R first.
#
# Everything here reads real data or stops via viz_stop_no_data(). Nothing
# falls back to made-up values -- this deliberately does NOT follow
# CLAUDE.md's general house rule ("fall back to a clearly labeled synthetic
# value, never hard-crash"); issue #140/#144 require zero-synthetic gallery
# charts, matching this repo's zero-betting / zero-synthetic-data policy.
#
# WHAT DIFFERS FROM THE NBA VERSION, AND WHY:
#   - Three per-season cache loaders (team box, play-by-play, shots) instead
#     of the NBA original's single generic viz_load_season() with no
#     pre-wired callers. This repo's existing cache constants (CACHE_TEAM_BOX,
#     CACHE_PBP_RAW in config.R) are single COMBINED files across all seasons,
#     not per-season -- these are genuinely new cache artifacts, not a reuse
#     of those. They are kept as filename literals local to this file rather
#     than promoted to config.R, because (per config.R's own "two-consumer"
#     threshold comment on CACHE_PBP_RAW) nothing outside this file's own
#     wrapper functions reads these paths yet; promote them to config.R if a
#     second consumer (beyond viz_load_*_season()) ever needs the literal.
#   - The loader functions passed to viz_load_season() are wehoop's WNBA
#     calls (wehoop::load_wnba_team_box(), wehoop::load_wnba_pbp(),
#     wehoop::load_wnba_stats_shots()), matching the exact functions
#     daily_ingest.R/pbp_engine.R already use elsewhere in this repo -- see
#     CLAUDE.md's exhibition-row / CONN-vs-CON data-quirk notes, which apply
#     equally to data fetched through these loaders.
# ==============================================================================

# Repo root, resolved from the calling script's --file= argument so the
# scripts work from any working directory.
viz_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
}

# cache/ is git-ignored, so a git worktree has none of its own. WNBA_VIZ_CACHE_DIR
# points a worktree at the main checkout's cache.
viz_cache_dir <- function(root) {
  env <- Sys.getenv("WNBA_VIZ_CACHE_DIR", "")
  d <- if (nzchar(env)) env else file.path(root, "cache")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  normalizePath(d, winslash = "/")
}

# Read a per-season hoopR/wehoop cache file, refreshing it from wehoop when it
# is missing or older than max_age_hours. If the refresh fails the existing
# file is used and its age is reported; with no file at all the script stops
# via viz_stop_no_data() -- no synthetic fallback.
viz_load_season <- function(cache_dir, prefix, season, loader, script, max_age_hours = 18) {
  path <- file.path(cache_dir, sprintf("%s_%d.rds", prefix, season))
  age_h <- if (file.exists(path)) as.numeric(difftime(Sys.time(), file.mtime(path), units = "hours")) else Inf
  if (age_h > max_age_hours) {
    fresh <- tryCatch(loader(seasons = season), error = function(e) {
      message(sprintf("[viz] wehoop refresh of %s failed: %s", basename(path), conditionMessage(e)))
      NULL
    })
    if (!is.null(fresh) && nrow(fresh) > 0) {
      saveRDS(fresh, path)
      message(sprintf("[viz] refreshed %s from wehoop (%s rows)", basename(path), format(nrow(fresh), big.mark = ",")))
      return(as.data.frame(fresh))
    }
  }
  if (!file.exists(path)) viz_stop_no_data(script, sprintf("%s is missing and could not be fetched.", basename(path)))
  if (is.finite(age_h) && age_h > max_age_hours) {
    message(sprintf("[viz] using existing %s, %.0f hours old", basename(path), age_h))
  }
  as.data.frame(readRDS(path))
}

# ------------------------------------------------------------------------------
# Per-season cache loaders (team box, play-by-play, shots)
# ------------------------------------------------------------------------------
# Each is a thin wrapper around viz_load_season() pinning the cache-file
# prefix and the matching wehoop loader call, so a gallery chart script does
# not have to know either detail. `script` is passed straight through to
# viz_stop_no_data() so the [SKIP-NO-DATA] message names the calling chart,
# not this helper file.

# One row per (team, game), per season. Backs any chart aggregating team-level
# box-score stats (e.g. net rating quadrant, rotation/minutes charts) by
# season rather than this repo's single all-seasons CACHE_TEAM_BOX.
viz_load_team_box_season <- function(season, cache_dir, script, max_age_hours = 18) {
  viz_load_season(
    cache_dir = cache_dir,
    prefix    = "viz_team_box",
    season    = season,
    loader    = function(seasons) wehoop::load_wnba_team_box(seasons = seasons),
    script    = script,
    max_age_hours = max_age_hours
  )
}

# ESPN event-level play-by-play, one row per event, per season. Backs any
# chart that needs event sequencing (e.g. timeout-effect, rotation/minutes
# streams) -- the same source daily_ingest.R's CACHE_PBP_RAW/pbp_engine.R
# already use, just split by season instead of kept as one combined file.
viz_load_pbp_season <- function(season, cache_dir, script, max_age_hours = 18) {
  viz_load_season(
    cache_dir = cache_dir,
    prefix    = "viz_pbp",
    season    = season,
    loader    = function(seasons) wehoop::load_wnba_pbp(seasons = seasons),
    script    = script,
    max_age_hours = max_age_hours
  )
}

# WNBA Stats API shot-location records, one row per shot attempt, per season.
# Backs shot-profile/shot-chart-style gallery charts. Distinct from
# build_shot_chart_dataset.R's existing shot source (ESPN PBP coordinates via
# CACHE_PBP_RAW) -- this is the WNBA Stats API feed wehoop also exposes
# (load_wnba_stats_shots()), named per-season here because that's the grain
# gallery charts need and no combined-season cache for it exists yet.
viz_load_shots_season <- function(season, cache_dir, script, max_age_hours = 18) {
  viz_load_season(
    cache_dir = cache_dir,
    prefix    = "viz_shots",
    season    = season,
    loader    = function(seasons) wehoop::load_wnba_stats_shots(seasons = seasons),
    script    = script,
    max_age_hours = max_age_hours
  )
}

# Vectorised wrapper: resolve_team_abbr() walks its input one element at a time,
# which is slow on play-by-play sized vectors.
viz_team_abbr <- function(x) {
  u <- unique(x)
  map <- setNames(resolve_team_abbr(u), u)
  unname(map[as.character(x)])
}

# Save a list of ggplots as frames, encode GIF + final-frame PNG into cache/,
# and copy both into web/public/media/.
viz_render_frames <- function(plots, name, root, cache_dir, fps = 2, hold_last_frames = 6,
                              width = 1000, height = 700) {
  frame_dir <- file.path(tempdir(), paste0(name, "_frames"))
  if (dir.exists(frame_dir)) unlink(frame_dir, recursive = TRUE)
  dir.create(frame_dir, recursive = TRUE)
  paths <- character(length(plots))
  for (i in seq_along(plots)) {
    paths[i] <- file.path(frame_dir, sprintf("frame_%03d.png", i))
    ggplot2::ggsave(paths[i], plot = plots[[i]], width = width / 100, height = height / 100,
                    dpi = 100, bg = WNBA_COLORS$bg)
  }
  gif <- file.path(cache_dir, paste0(name, ".gif"))
  png <- file.path(cache_dir, paste0(name, ".png"))
  render_animated_artifact(paths, gif, png, fps = fps, hold_last_frames = hold_last_frames,
                           width = width, height = height)
  media <- file.path(root, "web", "public", "media")
  if (!dir.exists(media)) dir.create(media, recursive = TRUE)
  file.copy(gif, file.path(media, basename(gif)), overwrite = TRUE)
  file.copy(png, file.path(media, basename(png)), overwrite = TRUE)
  unlink(frame_dir, recursive = TRUE)
  cat(sprintf("[SUCCESS] %s: %d frames\n  GIF: %s (%d bytes)\n  PNG: %s (%d bytes)\n",
              name, length(plots), file.path(media, basename(gif)), file.info(gif)$size,
              file.path(media, basename(png)), file.info(png)$size))
  invisible(list(gif = gif, png = png))
}

# Pick about n evenly spaced cut-off dates, always including the last one.
viz_frame_dates <- function(dates, n = 10) {
  d <- sort(unique(as.Date(dates)))
  if (length(d) <= n) return(d)
  d[unique(round(seq(1, length(d), length.out = n)))]
}
