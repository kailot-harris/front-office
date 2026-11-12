# ==============================================================================
# tools/gif_timeout_effect.R
#
# After-timeout execution: points per possession each team scored on the first
# possession after its own full timeouts, against what it allowed on the first
# possession after an opponent's.
#
# Data (real, no fallback):
#   - cache/pbp_timeout_cache.rds  built by build_tactical_events_dataset.R from
#     play-by-play. It covers the last COMPLETED season; the chart labels the
#     season it finds rather than assuming one.
#
# Usage: Rscript tools/gif_timeout_effect.R
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(ggplot2) })

SCRIPT <- "tools/gif_timeout_effect.R"
ROOT <- local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  normalizePath(if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd(), winslash = "/")
})
source(file.path(ROOT, "tools", "viz_common.R"))
source(file.path(ROOT, "tools", "viz_gallery_helpers.R"))
CACHE <- viz_cache_dir(ROOT)

path <- file.path(CACHE, "pbp_timeout_cache.rds")
if (!file.exists(path)) viz_stop_no_data(SCRIPT, "cache/pbp_timeout_cache.rds was not found.")
ato <- as.data.frame(readRDS(path)) %>% filter(event_type %in% c("ato_offense", "ato_defense"))
season <- as.integer(names(sort(table(ato$season), decreasing = TRUE))[1])
ato <- ato %>% filter(season == !!season)
ato$team <- viz_team_abbr(ato$team)
ato <- ato %>% filter(team %in% names(NBA_TEAM_COLORS))
if (length(unique(ato$game_id)) < 200 || length(unique(ato$team)) < 30) {
  viz_stop_no_data(SCRIPT, sprintf("only %d games for %d teams in the timeout cache.", length(unique(ato$game_id)), length(unique(ato$team))))
}
season_label <- sprintf("%d-%02d", season - 1, season %% 100)

# ESPN game ids increase through a season, so they order the games in time.
gids <- sort(unique(as.numeric(ato$game_id)))
ato$game_ix <- match(as.numeric(ato$game_id), gids)
cut_ix <- unique(round(seq(length(gids) * 0.3, length(gids), length.out = 10)))

summarise_to <- function(ix) {
  ato %>% filter(game_ix <= ix) %>% group_by(team, event_type) %>%
    summarise(ppp = sum(points) / sum(possessions), poss = sum(possessions), .groups = "drop") %>%
    pivot_wider(names_from = event_type, values_from = c(ppp, poss))
}
final <- summarise_to(length(gids))
cat(sprintf("[timeout] %s: %d games, %s after-timeout possessions, league %.3f points per possession\n",
            season_label, length(gids), format(sum(ato$possessions[ato$event_type == "ato_offense"]), big.mark = ","),
            sum(ato$points[ato$event_type == "ato_offense"]) / sum(ato$possessions[ato$event_type == "ato_offense"])))

early <- summarise_to(cut_ix[1])
lim <- range(c(early$ppp_ato_offense, early$ppp_ato_defense, final$ppp_ato_offense, final$ppp_ato_defense)) + c(-0.03, 0.03)
LOGOS <- viz_logo_map(CACHE, SCRIPT)

plots <- lapply(cut_ix, function(ix) {
  snap <- summarise_to(ix)
  lg <- sum(ato$points[ato$game_ix <= ix & ato$event_type == "ato_offense"]) /
    sum(ato$possessions[ato$game_ix <= ix & ato$event_type == "ato_offense"])
  ggplot(snap, aes(ppp_ato_offense, ppp_ato_defense)) +
    geom_vline(xintercept = lg, colour = "#64748B", linetype = "dashed") +
    geom_hline(yintercept = lg, colour = "#64748B", linetype = "dashed") +
    annotate("text", x = lim[2], y = lim[1], hjust = 1, vjust = 0, colour = "#94A3B8", size = 3.6,
             label = "Scores and gets stops out of timeouts") +
    annotate("text", x = lim[1], y = lim[2], hjust = 0, vjust = 1, colour = "#94A3B8", size = 3.6,
             label = "Loses both ends out of timeouts") +
    ggimage::geom_image(aes(image = LOGOS[team]), size = 0.055, by = "width") +
    scale_x_continuous(limits = lim) +
    scale_y_reverse(limits = rev(lim)) +
    labs(title = sprintf("Who Wins the Huddle? After-Timeout Execution, %s", season_label),
         subtitle = sprintf("Through %s of %s games. Dashed lines: league average (%.2f points per possession).",
                            format(ix, big.mark = ","), format(length(gids), big.mark = ","), lg),
         x = "Points per possession scored after own timeout",
         y = "Points per possession allowed after opponent timeout (better at top)",
         caption = "First possession after each full timeout, from ESPN play-by-play via hoopR.") +
    theme_nba_dark(base_size = 12)
})

viz_render_frames(plots, "gif_timeout_effect", ROOT, CACHE, fps = 2, hold_last_frames = 8,
                  width = 1000, height = 760)
