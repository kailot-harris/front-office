# ==============================================================================
# tools/gif_postseason_leverage.R — postseason relief workload and leverage
# Path: tools/gif_postseason_leverage.R
#
# Animates, round by round, how many batters the most-used postseason relievers
# faced and how high the leverage was when they pitched.
#
# Data (real, no fallback):
#   - cache/ingest/mlb_schedule_<season>.rds   postseason game ids by round
#   - web/public/data/world_series.json        World Series game ids
#   - MLB Stats API win probability feed       pitcher and leverage index for
#     every plate appearance (via tools/postseason_feed.R)
# A reliever is any pitcher other than his team's first pitcher of the game.
# Every number is counted from those feeds; nothing is typed in by hand, and
# there is no modelled "fatigue" score. If a feed is unavailable the script
# stops and renders nothing.
#
# Output: cache/viz/gif_postseason_leverage.gif
#         cache/viz/gif_postseason_leverage.png
# ==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(scales)
  library(dplyr)
  library(tidyr)
  library(mlbplotR)
  library(gifski)
})

source("config.R")
source("tools/viz_theme.R")
source("tools/postseason_feed.R")

#' Generate Postseason Relief Workload & Leverage GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_<season>.rds
#' @param n_relievers Number of relievers to show (default 10)
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 1)
#' @param hold_frames Number of frames to hold the final state (default 4)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_postseason_leverage <- function(season = 2026,
                                             schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                             n_relievers = 10,
                                             output_gif = "gif_postseason_leverage.gif",
                                             output_png = "gif_postseason_leverage.png",
                                             fps = 1,
                                             hold_frames = 4,
                                             cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Postseason Relief Workload & Leverage chart...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("[SKIP-NO-DATA] %s was not found; nothing rendered.", schedule_file), call. = FALSE)
  }
  rounds <- c(F = "Wild Card Series", D = "Division Series", L = "League Championship Series", W = "World Series")

  sch <- as.data.frame(readRDS(schedule_file)) %>%
    filter(game_type %in% c("F", "D", "L"), status_detailed_state == "Final") %>%
    transmute(game_pk = as.integer(game_pk), game_type,
              home_id = as.character(teams_home_team_id), away_id = as.character(teams_away_team_id))

  # The World Series comes from the published results summary, which is kept
  # current by the results refresh even when the schedule cache is behind.
  ws <- ps_world_series()
  abbr <- ps_team_abbr()
  ws_games <- bind_rows(lapply(ws$completed, function(g) {
    data.frame(game_pk = as.integer(g$game_pk), game_type = "W",
               home_abbr = g$home_team, away_abbr = g$away_team, stringsAsFactors = FALSE)
  }))
  games <- bind_rows(
    sch %>% transmute(game_pk, game_type, home_abbr = unname(abbr[home_id]), away_abbr = unname(abbr[away_id])),
    ws_games
  ) %>% distinct(game_pk, .keep_all = TRUE)
  if (nrow(games) == 0 || anyNA(games$home_abbr) || anyNA(games$away_abbr)) {
    stop("[SKIP-NO-DATA] postseason games could not be resolved to teams; nothing rendered.", call. = FALSE)
  }

  pa <- bind_rows(lapply(seq_len(nrow(games)), function(i) {
    g <- games[i, ]
    ps_fetch_wp(g$game_pk) %>%
      mutate(game_type = g$game_type,
             team_abbr = ifelse(top, g$home_abbr, g$away_abbr)) %>%
      group_by(team_abbr) %>%
      mutate(is_relief = pitcher_id != pitcher_id[which.min(ab)]) %>%
      ungroup()
  }))
  relief <- pa %>% filter(is_relief, !is.na(li)) %>%
    mutate(round_num = match(game_type, names(rounds)))

  totals <- relief %>%
    group_by(pitcher_id) %>%
    summarise(pitcher_name = last(pitcher), team_abbr = last(team_abbr), bf_total = n(), .groups = "drop") %>%
    arrange(desc(bf_total)) %>%
    head(n_relievers) %>%
    arrange(bf_total) %>%
    mutate(order = row_number())
  if (nrow(totals) < n_relievers) {
    stop("[SKIP-NO-DATA] too few relief appearances on record; nothing rendered.", call. = FALSE)
  }
  x_max <- max(totals$bf_total)
  li_rng <- range(relief %>% filter(pitcher_id %in% totals$pitcher_id) %>%
                    group_by(pitcher_id) %>% summarise(li = mean(li)) %>% pull(li))

  round_nums <- sort(unique(relief$round_num))

  tmp_dir <- file.path(tempdir(), "mlb_postseason_leverage_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(round_nums))

  for (idx in seq_along(round_nums)) {
    rn <- round_nums[idx]
    df <- totals %>%
      left_join(
        relief %>% filter(round_num <= rn) %>% group_by(pitcher_id) %>%
          summarise(bf = n(), app = n_distinct(game_pk), li = mean(li), .groups = "drop"),
        by = "pitcher_id"
      ) %>%
      mutate(bf = coalesce(bf, 0L), app = coalesce(app, 0L))

    p <- ggplot(df, aes(x = bf, y = order)) +
      geom_col(aes(fill = li), width = 0.68, orientation = "y") +
      scale_fill_gradient(low = "#38BDF8", high = "#EF4444", limits = c(floor(li_rng[1] * 10) / 10, ceiling(li_rng[2] * 10) / 10),
                          na.value = "#334155", name = "Average leverage index\n(1.0 = an average situation)") +
      geom_mlb_logos(aes(x = -x_max * 0.045, y = order, team_abbr = team_abbr), width = 0.05, inherit.aes = FALSE) +
      geom_text(aes(x = bf + x_max * 0.015, y = order,
                    label = ifelse(bf == 0, sprintf("%s: yet to pitch in relief", pitcher_name),
                                   sprintf("%s: %d batters, %d games, %.2f leverage", pitcher_name, bf, app, li))),
                color = "#E2E8F0", size = 3.3, hjust = 0) +
      scale_x_continuous(limits = c(-x_max * 0.08, x_max * 1.75), breaks = pretty(c(0, x_max))) +
      scale_y_continuous(breaks = NULL) +
      theme_mlb_dark(base_size = 11) +
      theme(
        axis.title.y = element_blank(),
        axis.text.y  = element_blank(),
        axis.ticks.y = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank(),
        legend.position = "bottom"
      ) +
      labs(
        title = sprintf("%d Postseason Relief Workload and Leverage", season),
        subtitle = sprintf("Through the %s. The %d relievers who faced the most batters this postseason.",
                           rounds[[rn]], n_relievers),
        x = "Batters faced in relief (cumulative)",
        caption = "Source: MLB Stats API play-by-play and leverage index. A reliever is any pitcher after his team's first of the game."
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 11.5, height = 7.2, dpi = 110, bg = "#0B0F17")
    frame_files[idx] <- fpath
  }

  target_gif <- cache_path("viz", output_gif)
  target_png <- cache_path("viz", output_png)

  file.copy(tail(frame_files, 1), target_png, overwrite = TRUE)

  final_frames <- c(frame_files, rep(tail(frame_files, 1), hold_frames))

  gifski::gifski(
    png_files = final_frames,
    gif_file  = target_gif,
    width     = 1150,
    height    = 720,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  message(sprintf(">>> [SUCCESS] Postseason relief chart generated (%d games):\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  nrow(games), target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_postseason_leverage()
}
