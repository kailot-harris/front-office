# ==============================================================================
# tools/viz_gallery_helpers.R
#
# Shared plumbing for the gallery charts added in November 2026
# (gif_shot_profile_shift, gif_rotation_minutes_stream, gif_proj_vs_actual_wins,
# gif_timeout_effect). Source tools/viz_common.R first.
#
# Everything here reads real data or stops. Nothing falls back to made-up
# values: a chart with no data is not rendered (see viz_stop_no_data()).
# ==============================================================================

# Repo root, resolved from the calling script's --file= argument so the scripts
# work from any working directory.
viz_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
}

# cache/ is git-ignored, so a git worktree has none of its own. NBA_VIZ_CACHE_DIR
# points a worktree at the main checkout's cache.
viz_cache_dir <- function(root) {
  env <- Sys.getenv("NBA_VIZ_CACHE_DIR", "")
  d <- if (nzchar(env)) env else file.path(root, "cache")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  normalizePath(d, winslash = "/")
}

# Read a per-season hoopR cache file, refreshing it from hoopR when it is
# missing or older than max_age_hours. If the refresh fails the existing file
# is used and its age is reported; with no file at all the script stops.
viz_load_season <- function(cache_dir, prefix, season, loader, script, max_age_hours = 18) {
  path <- file.path(cache_dir, sprintf("%s_%d.rds", prefix, season))
  age_h <- if (file.exists(path)) as.numeric(difftime(Sys.time(), file.mtime(path), units = "hours")) else Inf
  if (age_h > max_age_hours) {
    fresh <- tryCatch(loader(seasons = season), error = function(e) {
      message(sprintf("[viz] hoopR refresh of %s failed: %s", basename(path), conditionMessage(e)))
      NULL
    })
    if (!is.null(fresh) && nrow(fresh) > 0) {
      saveRDS(fresh, path)
      message(sprintf("[viz] refreshed %s from hoopR (%s rows)", basename(path), format(nrow(fresh), big.mark = ",")))
      return(as.data.frame(fresh))
    }
  }
  if (!file.exists(path)) viz_stop_no_data(script, sprintf("%s is missing and could not be fetched.", basename(path)))
  if (is.finite(age_h) && age_h > max_age_hours) {
    message(sprintf("[viz] using existing %s, %.0f hours old", basename(path), age_h))
  }
  as.data.frame(readRDS(path))
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
                    dpi = 100, bg = NBA_COLORS$bg)
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
