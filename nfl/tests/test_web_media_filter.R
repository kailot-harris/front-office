# tests/test_web_media_filter.R
# Offline tests for web_media_filter.R: per-week PNGs only for the active week,
# GIFs only if modified within MEDIA_GIF_MAX_AGE_DAYS (config.R).
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("config.R")
source("web_media_filter.R")

now <- as.POSIXct("2026-11-17 12:00:00", tz = "UTC")
days_ago <- function(d) now - d * 86400
pick <- function(res, f) res$keep[res$filename == f]

ok("MEDIA_GIF_MAX_AGE_DAYS is 8", identical(as.numeric(MEDIA_GIF_MAX_AGE_DAYS), 8))

files <- c("week5_projections.png", "week7_projections.png", "week11_projections.png",
           "week1_projections.png", "elo_trajectory.png", "gif_elo_heatmap.png",
           "gif_fresh.gif", "gif_edge_ok.gif", "gif_edge_old.gif", "gif_ancient.gif")
mt <- c(rep(days_ago(0), 6), days_ago(1), days_ago(7.9), days_ago(8.1), days_ago(35))
res <- select_publishable_media(files, mt, 11L, now, MEDIA_GIF_MAX_AGE_DAYS)

ok("current-week PNG kept (week 11)", pick(res, "week11_projections.png"))
ok("older per-week PNGs dropped (weeks 5, 7, 1)",
   !any(pick(res, "week5_projections.png"), pick(res, "week7_projections.png"),
        pick(res, "week1_projections.png")))
ok("week 1 is not confused with week 11 (no prefix match)", !pick(res, "week1_projections.png"))
ok("non-week PNGs kept regardless of age", pick(res, "elo_trajectory.png") && pick(res, "gif_elo_heatmap.png"))
ok("fresh GIF kept", pick(res, "gif_fresh.gif"))
ok("GIF at 7.9 days kept", pick(res, "gif_edge_ok.gif"))
ok("GIF at 8.1 days dropped", !pick(res, "gif_edge_old.gif"))
ok("35-day-old GIF dropped", !pick(res, "gif_ancient.gif"))
ok("every dropped file has a reason", all(nzchar(res$reason[!res$keep])) && all(res$reason[!res$keep] != "kept"))

res_na <- select_publishable_media(c("week11_projections.png", "elo_trajectory.png"),
                                   c(days_ago(0), days_ago(0)), NA_integer_, now, 8)
ok("unknown active week: per-week PNGs dropped (fail safe), others kept",
   !res_na$keep[1] && res_na$keep[2])

ok("NA mtime GIF is dropped",
   !select_publishable_media("g.gif", as.POSIXct(NA), 11L, now, 8)$keep)
ok("empty input returns empty frame", nrow(select_publishable_media(character(0), as.POSIXct(character(0)), 11L, now, 8)) == 0L)

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All web_media_filter tests passed\n")
