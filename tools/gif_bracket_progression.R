# ==============================================================================
# tools/gif_bracket_progression.R — 12-Team October Postseason Bracket Animation
# Path: tools/gif_bracket_progression.R
#
# Generates an animated bracket progression across all 4 rounds of the 2026
# MLB October Postseason (Wild Card -> Division Series -> League Championship
# Series -> World Series), tracking franchise advancement with official team
# logos, series win tallies, and clean dark front-office styling.
#
# Key Features:
#   - 12-team canonical MLB postseason bracket layout (6 AL teams, 6 NL teams).
#   - 4 progression stages:
#       Round 1: Wild Card Series (Best-of-3)
#       Round 2: Division Series (Best-of-5)
#       Round 3: League Championship Series (Best-of-7)
#       Round 4: World Series (Fall Classic Showdown)
#   - Official transparent MLB logos rendered at bracket nodes via mlbplotR.
#   - Connecting paths and winner glow highlights.
#   - Front-office dark theme via theme_mlb_dark().
#   - Encoded with gifski engine with final frame hold.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_<season>.rds   real series results and records
#         web/public/data/world_series.json        real World Series result
# Teams, matchups, series scores and records are all read from those results.
# If the bracket cannot be filled from them the script stops and renders nothing.
# Output: cache/viz/gif_bracket_progression.gif
#         cache/viz/gif_bracket_progression.png
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

#' Generate 12-Team October Postseason Bracket Progression GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 2)
#' @param hold_frames Number of frames to hold the final state (default 8)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_bracket_progression <- function(season = 2026,
                                             output_gif = "gif_bracket_progression.gif",
                                             output_png = "gif_bracket_progression.png",
                                             fps = 2,
                                             hold_frames = 8,
                                             cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d October Postseason Bracket Progression...", season))

  # Who played, who advanced and by how much all come from real results.
  games  <- ps_games(season)
  series <- ps_series(games)
  rec    <- ps_records(season)
  rec_label <- setNames(sprintf("%d-%d", rec$wins, rec$losses), rec$team)
  team_names <- ps_team_names(games)

  # Canvas positions only: where each bracket position is drawn. "a" is the
  # upper half of a league's bracket, "b" the lower half. Which team fills a
  # position is worked out below from the series results.
  # chart-authenticity-allow: canvas x/y of each bracket position, layout only; teams are joined in from results
  slot_xy <- tribble(
    ~league, ~pos,        ~round, ~x,  ~y,
    "AL",    "wc_a_home", 1,      1.0, 7.5,
    "AL",    "wc_a_away", 1,      1.0, 6.5,
    "AL",    "wc_b_home", 1,      1.0, 2.5,
    "AL",    "wc_b_away", 1,      1.0, 1.5,
    "AL",    "ds_a_bye",  2,      2.3, 8.0,
    "AL",    "ds_a_wc",   2,      2.3, 6.8,
    "AL",    "ds_b_bye",  2,      2.3, 2.2,
    "AL",    "ds_b_wc",   2,      2.3, 1.0,
    "AL",    "lcs_a",     3,      3.5, 6.2,
    "AL",    "lcs_b",     3,      3.5, 2.8,
    "AL",    "ws",        4,      4.5, 5.0,
    "NL",    "ws",        4,      5.5, 5.0,
    "NL",    "lcs_a",     3,      6.5, 6.2,
    "NL",    "lcs_b",     3,      6.5, 2.8,
    "NL",    "ds_a_bye",  2,      7.7, 8.0,
    "NL",    "ds_a_wc",   2,      7.7, 6.8,
    "NL",    "ds_b_bye",  2,      7.7, 2.2,
    "NL",    "ds_b_wc",   2,      7.7, 1.0,
    "NL",    "wc_a_home", 1,      9.0, 7.5,
    "NL",    "wc_a_away", 1,      9.0, 6.5,
    "NL",    "wc_b_home", 1,      9.0, 2.5,
    "NL",    "wc_b_away", 1,      9.0, 1.5
  )

  won_label <- function(s) sprintf("Won %d-%d", s$winner_wins, s$loser_wins)

  fill_league <- function(lg) {
    s   <- series[series$league == lg, , drop = FALSE]
    wc  <- s[s$round == 1, , drop = FALSE]
    ds  <- s[s$round == 2, , drop = FALSE]
    lcs <- s[s$round == 3, , drop = FALSE]
    if (nrow(wc) != 2 || nrow(ds) != 2 || nrow(lcs) != 1) {
      stop(sprintf("[SKIP-NO-DATA] the %s bracket is not complete in the results on record; nothing rendered.", lg),
           call. = FALSE)
    }
    ds <- ds[order(ds$series), , drop = FALSE]
    out <- list()
    for (i in 1:2) {
      half <- c("a", "b")[i]
      d <- ds[i, , drop = FALSE]
      d_teams <- c(d$winner, d$loser)
      feeder <- wc[wc$winner %in% d_teams, , drop = FALSE]
      if (nrow(feeder) != 1) {
        stop(sprintf("[SKIP-NO-DATA] could not trace the %s wild card winner into %s; nothing rendered.", lg, d$series),
             call. = FALSE)
      }
      bye_team <- setdiff(d_teams, feeder$winner)
      wc_away  <- setdiff(c(feeder$winner, feeder$loser), feeder$first_home)
      out[[length(out) + 1]] <- data.frame(
        league = lg,
        pos = c(paste0("wc_", half, "_home"), paste0("wc_", half, "_away"),
                paste0("ds_", half, "_bye"), paste0("ds_", half, "_wc"), paste0("lcs_", half)),
        team_abbr = c(feeder$first_home, wc_away, bye_team, feeder$winner, d$winner),
        note = c(rec_label[[feeder$first_home]], rec_label[[wc_away]],
                 paste("Bye", rec_label[[bye_team]]), won_label(feeder), won_label(d)),
        stringsAsFactors = FALSE
      )
    }
    out[[length(out) + 1]] <- data.frame(league = lg, pos = "ws", team_abbr = lcs$winner,
                                         note = won_label(lcs), stringsAsFactors = FALSE)
    do.call(rbind, out)
  }

  bracket_slots <- slot_xy %>%
    inner_join(bind_rows(fill_league("AL"), fill_league("NL")), by = c("league", "pos"))
  if (nrow(bracket_slots) != nrow(slot_xy)) {
    stop("[SKIP-NO-DATA] the bracket could not be filled from the results on record; nothing rendered.", call. = FALSE)
  }

  ws <- series[series$round == 4, , drop = FALSE]
  if (nrow(ws) != 1) {
    stop("[SKIP-NO-DATA] no decided World Series on record; nothing rendered.", call. = FALSE)
  }
  ws_line <- sprintf("%s beat %s %d-%d", team_names[[ws$winner]], team_names[[ws$loser]],
                     ws$winner_wins, ws$loser_wins)

  # Connector geometry between bracket columns (layout only).
  # chart-authenticity-allow: connector line coordinates between bracket columns, layout only
  bracket_lines <- tribble(
    ~x1, ~y1, ~x2, ~y2, ~round_target,
    # AL WC to DS
    1.0, 7.0, 2.3, 6.8, 2,
    1.0, 2.0, 2.3, 1.0, 2,
    # AL DS to LCS
    2.3, 7.4, 3.5, 6.2, 3,
    2.3, 1.6, 3.5, 2.8, 3,
    # AL LCS to WS
    3.5, 4.5, 4.5, 5.0, 4,

    # NL WC to DS
    9.0, 7.0, 7.7, 6.8, 2,
    9.0, 2.0, 7.7, 1.0, 2,
    # NL DS to LCS
    7.7, 7.4, 6.5, 6.2, 3,
    7.7, 1.6, 6.5, 2.8, 3,
    # NL LCS to WS
    6.5, 4.5, 5.5, 5.0, 4
  )

  # One frame per round. The subtitle lists that round's real series results.
  round_results <- function(r) {
    s <- series[series$round == r, , drop = FALSE]
    paste(sprintf("%s beat %s %d-%d", s$winner, s$loser, s$winner_wins, s$loser_wins), collapse = "  |  ")
  }
  round_titles <- c("Wild Card Series (best of 3)", "Division Series (best of 5)",
                    "League Championship Series (best of 7)", "World Series (best of 7)")
  stages <- lapply(1:4, function(r) {
    list(round = r, title = round_titles[r], subtitle = round_results(r), highlight_round = r)
  })

  tmp_dir <- file.path(tempdir(), "mlb_bracket_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(stages))

  for (idx in seq_along(stages)) {
    stg <- stages[[idx]]
    current_round <- stg$highlight_round

    # Filter visible slots up to current round
    active_slots <- bracket_slots %>%
      mutate(
        visible = round <= current_round,
        highlight = round == current_round,
        box_alpha = ifelse(round <= current_round, 0.95, 0.20),
        box_fill = case_when(
          round == current_round & league == "AL" ~ "#0C2340",
          round == current_round & league == "NL" ~ "#8B0000",
          round < current_round ~ "#1F2937",
          TRUE ~ "#111827"
        ),
        box_color = case_when(
          round == current_round ~ "#38BDF8",
          round < current_round ~ "#4B5563",
          TRUE ~ "#374151"
        )
      )

    active_lines <- bracket_lines %>%
      mutate(
        line_alpha = ifelse(round_target <= current_round, 0.9, 0.2),
        line_color = ifelse(round_target <= current_round, "#38BDF8", "#374151"),
        line_size = ifelse(round_target <= current_round, 1.2, 0.5)
      )

    p <- ggplot() +
      # Connecting paths
      geom_segment(
        data = active_lines,
        aes(x = x1, y = y1, xend = x2, yend = y2),
        color = active_lines$line_color,
        linewidth = active_lines$line_size,
        alpha = active_lines$line_alpha,
        linetype = ifelse(active_lines$round_target <= current_round, "solid", "dotted")
      ) +
      # Matchup Node Cards (Rectangles)
      geom_rect(
        data = active_slots,
        aes(
          xmin = x - 0.44, xmax = x + 0.44,
          ymin = y - 0.40, ymax = y + 0.40
        ),
        fill = active_slots$box_fill,
        color = active_slots$box_color,
        linewidth = ifelse(active_slots$highlight, 1.4, 0.6),
        alpha = active_slots$box_alpha
      ) +
      # Official MLB Logos
      geom_mlb_logos(
        data = active_slots %>% filter(visible),
        aes(x = x - 0.22, y = y, team_abbr = team_abbr),
        width = 0.065
      ) +
      # Team seed and label text
      geom_text(
        data = active_slots %>% filter(visible),
        aes(x = x + 0.06, y = y + 0.12, label = team_abbr),
        color = "#F8FAFC",
        fontface = "bold",
        size = 3.6,
        hjust = 0
      ) +
      geom_text(
        data = active_slots %>% filter(visible),
        aes(x = x + 0.06, y = y - 0.14, label = note),
        color = "#38BDF8",
        fontface = "bold",
        size = 2.6,
        hjust = 0
      ) +
      # Placeholder text for unrevealed rounds
      geom_text(
        data = active_slots %>% filter(!visible),
        aes(x = x, y = y, label = "TBD"),
        color = "#6B7280",
        fontface = "italic",
        size = 3.0
      ) +
      # Column Round Headers
      annotate("text", x = 1.0, y = 9.2, label = "AL WILD CARD", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 2.3, y = 9.2, label = "AL DIVISION", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 3.5, y = 9.2, label = "ALCS", color = "#60A5FA", fontface = "bold", size = 3.6) +
      annotate("text", x = 5.0, y = 9.2, label = "WORLD SERIES", color = "#FACC15", fontface = "bold", size = 4.2) +
      annotate("text", x = 6.5, y = 9.2, label = "NLCS", color = "#F87171", fontface = "bold", size = 3.6) +
      annotate("text", x = 7.7, y = 9.2, label = "NL DIVISION", color = "#F87171", fontface = "bold", size = 3.6) +
      annotate("text", x = 9.0, y = 9.2, label = "NL WILD CARD", color = "#F87171", fontface = "bold", size = 3.6) +
      # World Series Centerpiece Trophy Banner if round 4
      annotate(
        "label",
        x = 5.0, y = 3.8,
        label = if (current_round == 4) sprintf("%d WORLD SERIES\n%s", season, ws_line) else "OCTOBER POSTSEASON\nRoad to the Commissioner's Trophy",
        color = if (current_round == 4) "#FACC15" else "#94A3B8",
        fill = "#0B0F17",
        fontface = "bold",
        size = 3.4,
        label.padding = unit(0.5, "lines"),
        label.r = unit(0.3, "lines")
      ) +
      scale_x_continuous(limits = c(0.4, 9.6), expand = c(0, 0)) +
      scale_y_continuous(limits = c(0.4, 9.8), expand = c(0, 0)) +
      theme_mlb_dark(base_size = 11) +
      theme(
        axis.title = element_blank(),
        axis.text  = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank()
      ) +
      labs(
        x = NULL, y = NULL,
        title = sprintf("%d MLB Postseason — %s", season, stg$title),
        subtitle = stg$subtitle,
        caption = "Source: MLB Stats API schedule and results | Label under each team: regular-season record, or the series it won to get there | Logos: mlbplotR"
      )

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 12.0, height = 7.5, dpi = 110, bg = "#0B0F17")
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
    width     = 1200,
    height    = 750,
    delay     = 1 / fps,
    loop      = TRUE,
    progress  = FALSE
  )

  if (cleanup_frames) {
    unlink(tmp_dir, recursive = TRUE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
  message(sprintf(">>> [SUCCESS] Bracket Progression generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_bracket_progression()
}
