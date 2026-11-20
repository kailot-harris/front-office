# tests/test_landing_digest_record.R - NBA#212: record (season, last_7) and
# calibration buckets from logged pregame predictions. Offline.
# Usage: Rscript tests/test_landing_digest_record.R
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(dirname(normalizePath(f)), "landing_digest_helpers.R"), chdir = FALSE)
}, envir = globalenv())

m <- rbind(mrow("a", "2026-11-01", "BOS", "NYK", 0.55, 110, 100),   # hit, 50-60, outside last 7
           mrow("b", "2026-11-15", "BOS", "NYK", 0.65, 90, 100),    # miss, 60-70
           mrow("c", "2026-11-16", "BOS", "NYK", 0.25, 90, 100),    # hit (away 75%), 70-80
           mrow("d", "2026-11-17", "BOS", "NYK", 0.50, 90, 100),    # exactly 50% -> excluded
           mrow("e", "2026-11-18", "BOS", "NYK", 0.95, 100, 100),   # tie -> excluded
           mrow("f", "2026-11-18", "BOS", "NYK", 1.00, 120, 100),   # hit, 90-100 inclusive top
           mrow("g", "2026-11-19", "BOS", "NYK", 0.70, NA, NA),     # postponed -> excluded
           mrow("h", "2026-11-19", "BOS", "NYK", 0.85, 120, 100, logged = FALSE),  # not logged: ignored
           mrow("i", "2026-11-20", "BOS", "NYK", 0.85, NA, NA))     # today pending: ignored
r <- ld_record(m, "2026-11-20", postponed_ids = "g")
check(identical(unlist(r$season), c(hits = 3L, games = 4L, excluded = 3L)), "season: 3-1, 3 excluded (50%, tie, postponed)")
check(identical(unlist(r$last_7), c(hits = 2L, games = 3L, excluded = 3L)), "last_7 drops games older than 7 days")
cal <- ld_calibration(m, "2026-11-20", postponed_ids = "g")
check(length(cal) == 5 && identical(vapply(cal, `[[`, 0, "lo"), c(50, 60, 70, 80, 90)), "five buckets 50-100 by 10")
check(all(c("lo", "hi", "predicted_mean", "actual_rate", "games") %in% names(cal[[1]])), "bucket fields")
g <- vapply(cal, `[[`, 0L, "games")
check(identical(g, c(1L, 1L, 1L, 0L, 1L)), "games per bucket (pick-side probability; 1.0 in top bucket)")
check(cal[[2]]$actual_rate == 0 && cal[[3]]$predicted_mean == 0.75, "actual_rate and predicted_mean")
check(is.na(cal[[4]]$predicted_mean) && is.na(cal[[4]]$actual_rate), "empty bucket -> null, not 0")
e <- ld_record(m[0, ], "2026-11-20")
check(e$season$games == 0 && e$season$excluded == 0, "no predictions -> honest zeros")
finish()
