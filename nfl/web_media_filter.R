# ==============================================================================
# web_media_filter.R
#
# Pure selection rule for which cache/ images and GIFs the web gallery may show.
# Sourced by export_web_datasets.R (which passes in the real mtimes, active week
# and clock) and by tests/test_web_media_filter.R (which passes fixtures).
#
# Rules:
#   * `week<N>_*.png` per-week charts are shown only when N == the active week.
#     Their generator scripts hardcode WEEK, so older ones are stale by design.
#     If the active week is unknown they are all dropped (fail safe).
#   * `.gif` files are shown only if modified within `max_gif_age_days`
#     (config.R MEDIA_GIF_MAX_AGE_DAYS) of `now`.
#   * Every other PNG (elo_*, heatmaps, ...) is not week-specific and is kept.
# ==============================================================================

#' @param filenames basenames (e.g. "week7_projections.png")
#' @param mtimes    POSIXct modification times, same length as filenames
#' @param active_week integer or NA
#' @param now POSIXct
#' @param max_gif_age_days numeric
#' @return data.frame(filename, keep, reason)
select_publishable_media <- function(filenames, mtimes, active_week, now, max_gif_age_days) {
  n <- length(filenames)
  keep <- rep(TRUE, n)
  reason <- rep("kept", n)
  for (i in seq_len(n)) {
    f <- filenames[i]
    wk <- regmatches(f, regexec("^week([0-9]+)_.*\\.png$", f, ignore.case = TRUE))[[1]]
    if (length(wk) == 2L) {
      if (is.na(active_week) || as.integer(wk[2]) != as.integer(active_week)) {
        keep[i] <- FALSE
        reason[i] <- sprintf("per-week chart for week %s, active week is %s", wk[2],
                             if (is.na(active_week)) "unknown" else active_week)
      }
    } else if (grepl("\\.gif$", f, ignore.case = TRUE)) {
      age <- as.numeric(difftime(now, mtimes[i], units = "days"))
      if (is.na(age) || age > max_gif_age_days) {
        keep[i] <- FALSE
        reason[i] <- sprintf("gif is %s days old (limit %s)",
                             if (is.na(age)) "NA" else format(round(age, 1)), max_gif_age_days)
      }
    }
  }
  data.frame(filename = filenames, keep = keep, reason = reason, stringsAsFactors = FALSE)
}

#' Should cache/<filename> be copied into the published media dir?
#' Uses cache/gif_render_outcome.json written by render_weekly_gifs.R every run. A file whose
#' tools/<stem>.R script FAILED this run is never copied (its cache file is a leftover from an
#' older render); one whose script exited 0 must have been written at/after the run start
#' (2 s slack). With no outcome file, or a stage that skipped (empty lists), every file is
#' eligible; the exporter's copy.date = TRUE still keeps the real render time.
#' @return list(copy = logical, reason = character)
gif_cache_copy_ok <- function(filename, cache_file, outcome_path) {
  if (!file.exists(outcome_path)) return(list(copy = TRUE, reason = ""))
  oc <- tryCatch(jsonlite::fromJSON(outcome_path), error = function(e) NULL)
  if (is.null(oc)) return(list(copy = TRUE, reason = ""))
  script <- paste0(tools::file_path_sans_ext(filename), ".R")
  if (script %in% oc$failed) {
    return(list(copy = FALSE, reason = sprintf("%s failed this run; cache copy is a stale render", script)))
  }
  if (script %in% oc$rendered) {
    run_at <- as.POSIXct(oc$run_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (!is.na(run_at) && file.exists(cache_file) && file.mtime(cache_file) < run_at - 2) {
      return(list(copy = FALSE, reason = sprintf("%s exited 0 but did not rewrite %s", script, filename)))
    }
  }
  list(copy = TRUE, reason = "")
}
