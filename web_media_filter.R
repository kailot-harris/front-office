# ==============================================================================
# web_media_filter.R
#
# Pure selection rule for which cache/ images the web gallery may show.
# Sourced by export_web_datasets.R (which passes in the real active week) and by
# tests/test_web_media_filter.R (which passes fixtures).
#
# Rule:
#   * `week<N>_*.png` per-week charts are shown only when N == the active week.
#     Their generator scripts hardcode WEEK, so older ones are stale by design.
#     If the active week is unknown they are all dropped (fail safe).
#   * Every other file (elo_*, heatmaps, GIFs, ...) is kept. There is deliberately
#     no age rule for GIFs.
# ==============================================================================

#' @param filenames basenames (e.g. "week7_projections.png")
#' @param active_week integer or NA
#' @return data.frame(filename, keep, reason)
select_publishable_media <- function(filenames, active_week) {
  n <- length(filenames)
  keep <- rep(TRUE, n)
  reason <- rep("kept", n)
  for (i in seq_len(n)) {
    f <- filenames[i]
    wk <- regmatches(f, regexec("^week([0-9]+)_.*\\.png$", f, ignore.case = TRUE))[[1]]
    if (length(wk) == 2L &&
        (is.na(active_week) || as.integer(wk[2]) != as.integer(active_week))) {
      keep[i] <- FALSE
      reason[i] <- sprintf("per-week chart for week %s, active week is %s", wk[2],
                           if (is.na(active_week)) "unknown" else active_week)
    }
  }
  data.frame(filename = filenames, keep = keep, reason = reason, stringsAsFactors = FALSE)
}
