# ==============================================================================
# tools/gif_rotation_minutes_stream.R
#
# Rotation minutes stream: how one team's minutes have been split between its
# players, game by game.
#
# Data (real, no fallback):
#   - cache/nba_player_box_2027.rds  2026-27 player box scores (hoopR),
#     refreshed when stale
#
# The team is not hand-picked. The chart shows the team whose rotation has
# changed the most: for every pair of consecutive games we take half the sum of
# absolute changes in each player's share of team minutes, and average that
# over the season. Set NBA_ROTATION_TEAM (e.g. "BOS") to chart a specific team.
#
# Usage: Rscript tools/gif_rotation_minutes_stream.R
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(ggplot2) })

SCRIPT <- "tools/gif_rotation_minutes_stream.R"
ROOT <- local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  normalizePath(if (length(f) == 1L) file.path(dirname(normalizePath(f)), "..") else getwd(), winslash = "/")
})
source(file.path(ROOT, "tools", "viz_common.R"))
source(file.path(ROOT, "tools", "viz_gallery_helpers.R"))
CACHE <- viz_cache_dir(ROOT)

box <- viz_load_season(CACHE, "nba_player_box", 2027, hoopR::load_nba_player_box, SCRIPT)
box <- box %>% filter(season_type == 2) %>%
  mutate(team = viz_team_abbr(team_abbreviation), minutes = coalesce(as.numeric(minutes), 0),
         game_date = as.Date(game_date)) %>%
  filter(team %in% names(NBA_TEAM_COLORS))
if (length(unique(box$game_id)) < 60) {
  viz_stop_no_data(SCRIPT, sprintf("only %d games of player box data are available.", length(unique(box$game_id))))
}

shares <- box %>% group_by(team, game_id) %>% mutate(share = minutes / sum(minutes)) %>% ungroup() %>%
  group_by(team) %>% mutate(game_no = dense_rank(paste(game_date, game_id))) %>% ungroup()

churn <- shares %>% select(team, game_no, athlete_id, share) %>%
  complete(nesting(team, athlete_id), game_no, fill = list(share = 0)) %>%
  group_by(team) %>% filter(game_no <= max(shares$game_no[shares$team == team[1]])) %>%
  arrange(team, athlete_id, game_no) %>% group_by(team, athlete_id) %>%
  mutate(d = abs(share - lag(share))) %>% group_by(team, game_no) %>%
  summarise(turnover = sum(d, na.rm = TRUE) / 2, .groups = "drop") %>% filter(game_no > 1) %>%
  group_by(team) %>% summarise(churn = mean(turnover), games = n() + 1, .groups = "drop") %>% arrange(desc(churn))

forced <- toupper(Sys.getenv("NBA_ROTATION_TEAM", ""))
team_pick <- if (nzchar(forced) && forced %in% churn$team) forced else churn$team[1]
team_churn <- churn$churn[churn$team == team_pick]
cat(sprintf("[rotation] charting %s: average %.1f%% of minutes change hands between games (league median %.1f%%)\n",
            team_pick, 100 * team_churn, 100 * median(churn$churn)))

tm <- shares %>% filter(team == team_pick)
n_games <- max(tm$game_no)
top <- tm %>% group_by(athlete_display_name) %>% summarise(m = sum(minutes), .groups = "drop") %>%
  arrange(desc(m)) %>% slice_head(n = 9) %>% pull(athlete_display_name)
stream <- tm %>% mutate(player = ifelse(athlete_display_name %in% top, athlete_display_name, "Everyone else")) %>%
  group_by(game_no, player) %>% summarise(minutes = sum(minutes), .groups = "drop") %>%
  complete(game_no = 1:n_games, player = c(top, "Everyone else"), fill = list(minutes = 0)) %>%
  mutate(player = factor(player, levels = c(top, "Everyone else")))
game_dates <- tm %>% distinct(game_no, game_date) %>% arrange(game_no)

pal <- c("#38BDF8", "#F59E0B", "#34D399", "#F472B6", "#A78BFA", "#FB7185", "#FACC15", "#2DD4BF", "#C084FC", "#475569")
names(pal) <- c(top, "Everyone else")

plots <- lapply(2:n_games, function(k) {
  ggplot(stream %>% filter(game_no <= k), aes(game_no, minutes, fill = player)) +
    geom_area(position = "stack", colour = NBA_COLORS$bg, linewidth = 0.3, alpha = 0.95) +
    scale_fill_manual(values = pal, drop = FALSE, name = NULL) +
    scale_x_continuous(limits = c(1, n_games), breaks = seq(1, n_games, by = max(1, n_games %/% 6)),
                       expand = expansion(mult = 0.01)) +
    scale_y_continuous(limits = c(0, max(265, max(tapply(stream$minutes, stream$game_no, sum)))),
                       expand = expansion(mult = c(0, 0.02))) +
    labs(title = sprintf("Where the Minutes Went: %s Rotation, 2026-27", team_pick),
         subtitle = sprintf("Through game %d (%s). %s has the least settled rotation in the league: %.0f%% of its minutes change hands from one game to the next.",
                            k, format(game_dates$game_date[game_dates$game_no == k], "%b %d"), team_pick, 100 * team_churn),
         x = "Team game number", y = "Minutes played",
         caption = "Source: ESPN box scores via hoopR. Nine highest-minute players shown individually.") +
    theme_nba_dark(base_size = 12) +
    theme(legend.position = "right", plot.subtitle = element_text(size = 9.5))
})

viz_render_frames(plots, "gif_rotation_minutes_stream", ROOT, CACHE, fps = 2, hold_last_frames = 8,
                  width = 1100, height = 650)
