# ==============================================================================
# tools/gif_pythag_luck_scatter.R — Dynamic Pythagorean RS vs RA / Luck Scatter
# Path: tools/gif_pythag_luck_scatter.R
#
# Generates an animated 4-quadrant dynamic scatter animation tracking 30 MLB
# franchises across the season as their cumulative Runs Scored (RS) vs Runs
# Allowed (RA) and Pythagorean win expectations evolve against actual records.
#
# Key Features:
#   - 4 Dynamic quadrants centered at league average runs scored & allowed:
#       * Top-Right: Elite Contenders (High RS, Low RA / Strong Run Differential)
#       * Top-Left: Offense-First / Volatile High Scorers
#       * Bottom-Left: Rebuilding / Low Scoring & Heavy RA
#       * Bottom-Right: Pitching-Dominant / Defensive Stalwarts
#   - Official transparent MLB franchise logos plotted at dynamic coordinates
#     via mlbplotR::geom_mlb_logos.
#   - Points / Halos colored dynamically by Pythagorean luck (Actual W - Expected W).
#   - Minimal dark front-office styling via theme_mlb_dark().
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
#         cache/pythag/mlb_pythag_standings.rds
# Output: cache/viz/gif_pythag_luck_scatter.gif
#         cache/viz/gif_pythag_luck_scatter.png
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

#' Generate Dynamic Pythagorean Luck Scatter GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param schedule_file Path to mlb_schedule_2026.rds
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param n_frames Number of milestone frames across season (default 18)
#' @param fps Frames per second for GIF playback (default 6)
#' @param hold_frames Number of frames to hold the final state (default 12)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_pythag_luck_scatter <- function(season = 2026,
                                             schedule_file = cache_path("ingest", sprintf("mlb_schedule_%d.rds", season)),
                                             output_gif = "gif_pythag_luck_scatter.gif",
                                             output_png = "gif_pythag_luck_scatter.png",
                                             n_frames = 18,
                                             fps = 6,
                                             hold_frames = 12,
                                             cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d MLB Pythagorean Luck Scatter Animation...", season))

  if (!file.exists(schedule_file)) {
    stop(sprintf("Schedule file not found at '%s'. Run mlb_ingest.R first.", schedule_file))
  }

  sch <- readRDS(schedule_file)
  act_teams <- subset(as.data.frame(MLB_TEAMS), sport_id == 1 & active == TRUE)
  act_teams$division <- standardize_division(act_teams$division_name)
  team_abbr_map <- setNames(act_teams$team_abbreviation, act_teams$team_id)
  team_name_map <- setNames(act_teams$team_full_name, act_teams$team_id)

  reg <- sch %>%
    filter(
      game_type == "R",
      !is.na(home_score),
      !is.na(away_score),
      home_team_id %in% act_teams$team_id,
      away_team_id %in% act_teams$team_id
    ) %>%
    mutate(game_d = as.Date(official_date))

  all_dates <- sort(unique(reg$game_d))
  # Start from game day 15 so averages are meaningful
  milestone_dates <- all_dates[round(seq(15, length(all_dates), length.out = n_frames))]

  # Build game-level runs scored and allowed
  long_games <- bind_rows(
    reg %>% transmute(team_id = home_team_id, date = game_d, rs = home_score, ra = away_score,
                      win = as.integer(home_score > away_score)),
    reg %>% transmute(team_id = away_team_id, date = game_d, rs = away_score, ra = home_score,
                      win = as.integer(away_score > home_score))
  )

  # Pre-calculate global axis bounds based on final cumulative totals
  final_totals <- long_games %>%
    group_by(team_id) %>%
    summarize(tot_rs = sum(rs), tot_ra = sum(ra), .groups = "drop")
  
  max_rs <- max(final_totals$tot_rs)
  max_ra <- max(final_totals$tot_ra)
  coord_max <- max(max_rs, max_ra) + 40

  tmp_dir <- file.path(tempdir(), "mlb_pythag_scatter_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(milestone_dates))

  for (idx in seq_along(milestone_dates)) {
    cur_d <- milestone_dates[idx]
    cur_games <- long_games %>% filter(date <= cur_d)

    team_summary <- cur_games %>%
      group_by(team_id) %>%
      summarize(
        games = n(),
        wins = sum(win),
        cum_rs = sum(rs),
        cum_ra = sum(ra),
        .groups = "drop"
      ) %>%
      mutate(
        team_abbr = team_abbr_map[as.character(team_id)],
        team_name = team_name_map[as.character(team_id)],
        actual_win_pct = round(wins / games, 3),
        # Pythagenpat exponent: ( (RS + RA) / G ) ^ 0.287
        r_per_g = (cum_rs + cum_ra) / pmax(games, 1),
        pyth_exp = pmax(r_per_g ^ 0.287, 1.5),
        pyth_win_pct = round((cum_rs ^ pyth_exp) / ((cum_rs ^ pyth_exp) + (cum_ra ^ pyth_exp)), 3),
        exp_wins = round(pyth_win_pct * games, 1),
        luck_wins = round(wins - exp_wins, 1)
      )

    mean_rs <- mean(team_summary$cum_rs)
    mean_ra <- mean(team_summary$cum_ra)

    most_lucky   <- team_summary %>% arrange(desc(luck_wins)) %>% slice(1)
    most_unlucky <- team_summary %>% arrange(luck_wins) %>% slice(1)

    subtitle_txt <- sprintf(
      "Through %s | Top Overperformer: %s (%+.1f W) \u00b7 Most Unlucky: %s (%+.1f W)",
      format(cur_d, "%B %d, %Y"),
      most_lucky$team_abbr, most_lucky$luck_wins,
      most_unlucky$team_abbr, most_unlucky$luck_wins
    )

    # Inverted RA so higher is better (fewer runs allowed = stronger run prevention)
    # Or standard RS (x) vs RA (y): lower RA is top half
    # Let's use x = Cumulative Runs Scored, y = Cumulative Runs Allowed (inverted y-axis so elite is Top-Right)
    p <- ggplot(team_summary, aes(x = cum_rs, y = cum_ra)) +
      # Identity diagonal: RS == RA
      geom_abline(intercept = 0, slope = 1, linetype = "dotted", color = "#484F58", linewidth = 0.6) +
      # Quadrant dividers at current means
      geom_vline(xintercept = mean_rs, linetype = "dashed", color = "#30363D", linewidth = 0.5) +
      geom_hline(yintercept = mean_ra, linetype = "dashed", color = "#30363D", linewidth = 0.5) +
      
      # Halo point colored by luck
      geom_point(aes(color = luck_wins), size = 7, alpha = 0.6) +
      
      # Team logos
      geom_mlb_logos(
        aes(x = cum_rs, y = cum_ra, team_abbr = team_abbr),
        width = 0.055,
        inherit.aes = FALSE
      ) +
      
      # Team abbreviation and luck text
      geom_text(
        aes(x = cum_rs, y = cum_ra + (coord_max * 0.028),
            label = sprintf("%s (%+.0f)", team_abbr, luck_wins)),
        color = "#E6EDF3",
        size = 2.7,
        fontface = "bold"
      ) +
      
      # Quadrant labels (note RA is inverted: lower RA is at top)
      annotate("text", x = coord_max * 0.95, y = 20, label = "ELITE CONTENDERS\n(High RS / Low RA)",
               color = "#484F58", size = 3.8, fontface = "bold.italic", hjust = 1, vjust = 0) +
      annotate("text", x = 30, y = 20, label = "PITCHING STALWARTS\n(Low RS / Low RA)",
               color = "#484F58", size = 3.8, fontface = "bold.italic", hjust = 0, vjust = 0) +
      annotate("text", x = coord_max * 0.95, y = coord_max * 0.95, label = "OFFENSIVE SLUGGERS\n(High RS / High RA)",
               color = "#484F58", size = 3.8, fontface = "bold.italic", hjust = 1, vjust = 1) +
      annotate("text", x = 30, y = coord_max * 0.95, label = "REBUILDING / STRUGGLING\n(Low RS / High RA)",
               color = "#484F58", size = 3.8, fontface = "bold.italic", hjust = 0, vjust = 1) +
      
      scale_color_gradient2(
        low = MLB_LUCK_COLORS$unlucky,
        mid = MLB_LUCK_COLORS$neutral,
        high = MLB_LUCK_COLORS$lucky,
        midpoint = 0,
        name = "Pythagorean Luck\n(Actual W - Expected W)"
      ) +
      scale_x_continuous(limits = c(0, coord_max), breaks = pretty_breaks(n = 6)) +
      scale_y_reverse(limits = c(coord_max, 0), breaks = pretty_breaks(n = 6)) +
      theme_mlb_dark(base_size = 11) +
      theme(
        legend.position = "right",
        panel.grid.minor = element_blank()
      ) +
      labs(
        title = sprintf("%d MLB Pythagorean RS vs RA & Luck Quadrant Dynamic Scatter", season),
        subtitle = subtitle_txt,
        x = "Cumulative Runs Scored (RS)",
        y = "Cumulative Runs Allowed (RA — Inverted: Lower is Better)",
        caption = "Dotted line: 1:1 Run Parity | Halos colored by Pythagorean Luck | Source: KayceeSlices MLB Analytics"
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 11.5, height = 7.2, dpi = 110, bg = "#161B22")
    frame_files[idx] <- fpath
  }

  target_gif <- cache_path("viz", output_gif)
  target_png <- cache_path("viz", output_png)

  # Copy final frame as static PNG artifact
  file.copy(tail(frame_files, 1), target_png, overwrite = TRUE)

  # Hold final frame
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
  message(sprintf(">>> [SUCCESS] Pythag Luck Scatter generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_pythag_luck_scatter()
}
