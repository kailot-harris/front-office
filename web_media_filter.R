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
