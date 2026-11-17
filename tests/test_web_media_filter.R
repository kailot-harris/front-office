# tests/test_web_media_filter.R
# Offline tests for web_media_filter.R: per-week PNGs only for the active week; no GIF age rule.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("web_media_filter.R")

pick <- function(res, f) res$keep[res$filename == f]

files <- c("week5_projections.png", "week7_projections.png", "week11_projections.png",
           "week1_projections.png", "elo_trajectory.png", "gif_elo_heatmap.png",
           "gif_fresh.gif", "gif_ancient.gif")
res <- select_publishable_media(files, 11L)

ok("current-week PNG kept (week 11)", pick(res, "week11_projections.png"))
ok("older per-week PNGs dropped (weeks 5, 7, 1)",
   !any(pick(res, "week5_projections.png"), pick(res, "week7_projections.png"),
        pick(res, "week1_projections.png")))
ok("week 1 is not confused with week 11 (no prefix match)", !pick(res, "week1_projections.png"))
ok("non-week PNGs kept", pick(res, "elo_trajectory.png") && pick(res, "gif_elo_heatmap.png"))
ok("GIFs are kept regardless of age (no age rule)", pick(res, "gif_fresh.gif") && pick(res, "gif_ancient.gif"))
ok("every dropped file has a reason", all(nzchar(res$reason[!res$keep])) && all(res$reason[!res$keep] != "kept"))

res_na <- select_publishable_media(c("week11_projections.png", "elo_trajectory.png"), NA_integer_)
ok("unknown active week: per-week PNGs dropped (fail safe), others kept",
   !res_na$keep[1] && res_na$keep[2])
ok("empty input returns empty frame", nrow(select_publishable_media(character(0), 11L)) == 0L)

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All web_media_filter tests passed\n")
