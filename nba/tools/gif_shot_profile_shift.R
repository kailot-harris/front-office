# ==============================================================================
# tools/gif_shot_profile_shift.R
#
# Team shot-profile shift: share of each team's field-goal attempts that are
# three-pointers, this season against last season.
#
# Data (all real, no fallback):
#   - cache/nba_shots_2026.rds  2025-26 shot records (hoopR)
#   - cache/nba_pbp_2027.rds    2026-27 play-by-play (hoopR), refreshed when stale
#
# A shot is a three when it is at least 23.75 ft from the rim, or in the corner
# (22 ft or more from the centre line and within 14 ft of the baseline). The
# same geometric rule is applied to both seasons so the comparison is like for
# like. Free throws and shots without court coordinates are dropped.
#
# Usage: Rscript tools/gif_shot_profile_shift.R
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(ggplot2) })

SCRIPT <- "tools/gif_shot_profile_shift.R"
ROOT <- local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  normalizePath(if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd(), winslash = "/")
})
source(file.path(ROOT, "tools", "viz_common.R"))
source(file.path(ROOT, "tools", "viz_gallery_helpers.R"))
CACHE <- viz_cache_dir(ROOT)

classify <- function(df) {
  df %>%
    filter(!grepl("Free Throw", type_text, ignore.case = TRUE),
           !is.na(coordinate_x_raw), !is.na(coordinate_y_raw),
           coordinate_x_raw >= 0, coordinate_x_raw <= 50,
           coordinate_y_raw >= -5, coordinate_y_raw <= 45) %>%
    mutate(x = coordinate_x_raw - 25, y = coordinate_y_raw + 4,
           dist = sqrt(x^2 + (y - 5.25)^2),
           is_three = dist >= 23.75 | (abs(x) >= 22 & y <= 14))
}

# --- Last season ---------------------------------------------------------------
last_path <- file.path(CACHE, "nba_shots_2026.rds")
if (!file.exists(last_path)) viz_stop_no_data(SCRIPT, "cache/nba_shots_2026.rds was not found.")
last <- classify(as.data.frame(readRDS(last_path)))
last$team <- viz_team_abbr(last$team_abbrev)
last_share <- last %>% filter(team %in% names(NBA_TEAM_COLORS)) %>%
  group_by(team) %>% summarise(last_share = mean(is_three), last_n = n(), .groups = "drop")

# --- This season ---------------------------------------------------------------
pbp <- viz_load_season(CACHE, "nba_pbp", 2027, hoopR::load_nba_pbp, SCRIPT)
cur <- pbp %>% filter(shooting_play %in% TRUE) %>% classify()
cur$team <- viz_team_abbr(ifelse(cur$team_id == cur$home_team_id, cur$home_team_abbrev, cur$away_team_abbrev))
cur <- cur %>% filter(team %in% names(NBA_TEAM_COLORS)) %>% mutate(game_date = as.Date(game_date))

if (nrow(last_share) < 30 || length(unique(cur$team)) < 30 || length(unique(cur$game_id)) < 60) {
  viz_stop_no_data(SCRIPT, sprintf("not enough shot data (%d teams last season, %d teams and %d games this season).",
                                   nrow(last_share), length(unique(cur$team)), length(unique(cur$game_id))))
}
cat(sprintf("[shot profile] league three-point share: 2025-26 %.1f%% (%s shots), 2026-27 %.1f%% (%s shots, %d games)\n",
            100 * mean(last$is_three), format(nrow(last), big.mark = ","),
            100 * mean(cur$is_three), format(nrow(cur), big.mark = ","), length(unique(cur$game_id))))

final <- cur %>% group_by(team) %>% summarise(share = mean(is_three), .groups = "drop") %>%
  inner_join(last_share, by = "team") %>% mutate(delta = share - last_share)
team_order <- final %>% arrange(delta) %>% pull(team)
x_rng <- range(c(final$share, final$last_share)) + c(-0.04, 0.04)
LOGOS <- viz_logo_map(CACHE, SCRIPT)

cuts <- viz_frame_dates(cur$game_date, n = 10)
cuts <- cuts[cuts >= sort(unique(cur$game_date))[min(5, length(unique(cur$game_date)))]]

plots <- lapply(cuts, function(d) {
  snap <- cur %>% filter(game_date <= d) %>% group_by(team) %>%
    summarise(share = mean(is_three), n = n(), .groups = "drop") %>%
    inner_join(last_share, by = "team") %>%
    mutate(team = factor(team, levels = team_order), up = share >= last_share)
  ggplot(snap, aes(y = team)) +
    geom_segment(aes(x = last_share, xend = share, yend = team, colour = up), linewidth = 1.6, alpha = 0.85) +
    geom_point(aes(x = last_share), shape = 21, size = 3, stroke = 1, fill = NBA_COLORS$bg, colour = "#94A3B8") +
    geom_point(aes(x = share, colour = up), size = 3.4) +
    ggimage::geom_image(aes(x = x_rng[1] + 0.006, image = LOGOS[as.character(team)]), size = 0.026, by = "height") +
    scale_colour_manual(values = c(`TRUE` = "#38BDF8", `FALSE` = "#F59E0B"), guide = "none") +
    scale_x_continuous(labels = function(v) paste0(round(100 * v), "%"), limits = x_rng) +
    scale_y_discrete(drop = FALSE) +
    labs(title = "Who Changed Their Shot Diet? Three-Point Share, 2026-27 vs 2025-26",
         subtitle = sprintf("Through %s. Hollow dot: last season. Solid dot: this season (blue = more threes, amber = fewer).",
                            format(d, "%b %d")),
         x = "Share of field-goal attempts taken from three", y = NULL,
         caption = "Source: ESPN play-by-play via hoopR. Threes classified by court location in both seasons.") +
    theme_nba_dark(base_size = 12) +
    theme(panel.grid.major.y = element_blank(), axis.text.y = element_blank(), axis.ticks.y = element_blank())
})

viz_render_frames(plots, "gif_shot_profile_shift", ROOT, CACHE, fps = 2, hold_last_frames = 8,
                  width = 1000, height = 820)
