# ==============================================================================
# tools/gif_pennant_showdown.R — ALCS & NLCS Showdown and Fall Classic Banner
# Path: tools/gif_pennant_showdown.R
#
# Generates an animated championship series showdown tracking game-by-game
# progression through the ALCS and
# NLCS (teams and scores read from real results), culminating in their pennant
# clinches and a dramatic transition into the 2026 World Series emblem banner.
#
# Key Features:
#   - Side-by-side ALCS and NLCS game-by-game series tracker (Best-of-7).
#   - Series win progress bars and individual game scores.
#   - Pennant clinch fireworks / celebration frames.
#   - Climax transition into the World Series emblem banner with full franchise logos.
#   - Official transparent MLB logos via mlbplotR::geom_mlb_logos.
#   - Dark front-office theme via theme_mlb_dark().
#   - Encoded with gifski engine with final frame hold.
#   - Dual artifact export: animated GIF and static final-frame PNG.
#
# Inputs: cache/ingest/mlb_schedule_2026.rds
#         cache/postseason/postseason_sim_results_2026.rds
# Output: cache/viz/gif_pennant_showdown.gif
#         cache/viz/gif_pennant_showdown.png
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

#' Generate Pennant Showdown & World Series Matchup Banner GIF
#'
#' @param season Integer MLB season year (default 2026)
#' @param output_gif Output filename for animated GIF
#' @param output_png Output filename for static final frame PNG
#' @param fps Frames per second for GIF playback (default 2)
#' @param hold_frames Number of frames to hold the final banner (default 10)
#' @param cleanup_frames Logical; remove temporary frame PNGs (default TRUE)
#' @return Invisible list of output paths
generate_gif_pennant_showdown <- function(season = 2026,
                                          output_gif = "gif_pennant_showdown.gif",
                                          output_png = "gif_pennant_showdown.png",
                                          fps = 2,
                                          hold_frames = 10,
                                          cleanup_frames = TRUE) {
  start_time <- Sys.time()
  ensure_viz_dir()
  message(sprintf(">>> [GIF] Generating %d Pennant Showdown & WS Banner Animation...", season))

  # Every score, tally and record below is read from real results.
  games  <- ps_games(season)
  series <- ps_series(games)
  rec    <- ps_records(season)
  team_names <- ps_team_names(games)

  lcs <- series[series$round == 3, , drop = FALSE]
  ws  <- series[series$round == 4, , drop = FALSE]
  if (!all(c("AL", "NL") %in% lcs$league) || nrow(ws) != 1) {
    stop("[SKIP-NO-DATA] both Championship Series and the World Series must be decided; nothing rendered.",
         call. = FALSE)
  }
  al <- lcs[lcs$league == "AL", , drop = FALSE]
  nl <- lcs[lcs$league == "NL", , drop = FALSE]
  lcs_games <- games[games$round == 3, , drop = FALSE]

  # Running tally for one league after its first k games.
  tally_after <- function(s, k) {
    g <- lcs_games[lcs_games$series == s$series & lcs_games$game_num <= k, , drop = FALSE]
    list(winner = sum(g$winner == s$winner), loser = sum(g$winner == s$loser))
  }
  # "NLCS G2: MIL 7, LAD 4" for game k, or NULL once that series is over.
  game_line <- function(s, k) {
    g <- lcs_games[lcs_games$series == s$series & lcs_games$game_num == k, , drop = FALSE]
    if (nrow(g) != 1) return(NULL)
    sprintf("%s G%d: %s %d, %s %d", s$series, k, g$winner, max(g$home_score, g$away_score),
            g$loser, min(g$home_score, g$away_score))
  }

  n_steps <- max(lcs_games$game_num)
  steps <- lapply(seq_len(n_steps), function(k) {
    a <- tally_after(al, k)
    n <- tally_after(nl, k)
    clinched <- c(
      if (a$winner == 4 && tally_after(al, k - 1)$winner < 4) sprintf("%s win the AL pennant", team_names[[al$winner]]),
      if (n$winner == 4 && tally_after(nl, k - 1)$winner < 4) sprintf("%s win the NL pennant", team_names[[nl$winner]])
    )
    list(
      title = if (length(clinched)) paste0("Game ", k, ": ", paste(clinched, collapse = "; ")) else paste("Game", k),
      subtitle = paste(c(game_line(nl, k), game_line(al, k)), collapse = "  |  "),
      al_w = a$winner, al_l = a$loser, nl_w = n$winner, nl_l = n$loser,
      stage = "series"
    )
  })
  steps[[length(steps) + 1]] <- list(
    title = "", subtitle = "",
    al_w = al$winner_wins, al_l = al$loser_wins, nl_w = nl$winner_wins, nl_l = nl$loser_wins,
    stage = "ws_banner"
  )

  # Banner text: regular-season record and the series each pennant winner won.
  rec_of <- function(team) {
    r <- rec[rec$team == team, , drop = FALSE]
    sprintf("%d-%d", r$wins, r$losses)
  }
  path_of <- function(team) {
    p <- series[series$winner == team & series$round < 4, , drop = FALSE]
    paste(sprintf("%s (%d-%d)", p$loser, p$winner_wins, p$loser_wins), collapse = ", ")
  }
  banner_line <- function(s) {
    sprintf("%d %s Champions (%s Regular Season)\nDefeated: %s", season, s$league, rec_of(s$winner), path_of(s$winner))
  }
  ws_final <- sprintf("Final: %s won the World Series %d-%d", team_names[[ws$winner]], ws$winner_wins, ws$loser_wins)

  tmp_dir <- file.path(tempdir(), "mlb_pennant_frames")
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE)
  dir.create(tmp_dir, recursive = TRUE)

  frame_files <- character(length(steps))

  for (idx in seq_along(steps)) {
    st <- steps[[idx]]

    if (st$stage != "ws_banner") {
      # Render LCS Series progress view
      # Fixed card positions; the teams and win counts come from the results.
      series_df <- tibble(
        team_abbr = c(al$winner, al$loser, nl$winner, nl$loser),
        team_name = unname(team_names[c(al$winner, al$loser, nl$winner, nl$loser)]),
        wins      = c(st$al_w, st$al_l, st$nl_w, st$nl_l),
        lead      = c(TRUE, FALSE, TRUE, FALSE),
        x_pos     = c(2.2, 2.2, 6.8, 6.8),
        y_pos     = c(5.8, 3.2, 5.8, 3.2)
      )
      pips <- series_df %>%
        tidyr::crossing(pip = 1:4) %>%
        mutate(x = x_pos + (pip - 1) * 0.5, y = y_pos - 0.5, won = pip <= wins)

      p <- ggplot() +
        # Left Panel (ALCS) Background Card
        annotate("rect", xmin = 0.6, xmax = 4.4, ymin = 1.2, ymax = 8.2, fill = "#111827", color = "#374151", linewidth = 1.0, alpha = 0.9) +
        # Right Panel (NLCS) Background Card
        annotate("rect", xmin = 5.6, xmax = 9.4, ymin = 1.2, ymax = 8.2, fill = "#111827", color = "#374151", linewidth = 1.0, alpha = 0.9) +
        # Panel Headers
        annotate("text", x = 2.5, y = 7.6, label = "AMERICAN LEAGUE CHAMPIONSHIP SERIES", color = "#60A5FA", fontface = "bold", size = 3.6) +
        annotate("text", x = 7.5, y = 7.6, label = "NATIONAL LEAGUE CHAMPIONSHIP SERIES", color = "#F87171", fontface = "bold", size = 3.6) +
        # Logos for the 4 teams
        geom_mlb_logos(
          data = series_df,
          aes(x = x_pos - 0.7, y = y_pos, team_abbr = team_abbr),
          width = 0.13
        ) +
        # Team Names
        geom_text(
          data = series_df,
          aes(x = x_pos, y = y_pos + 0.35, label = team_name),
          color = "#F8FAFC",
          fontface = "bold",
          size = 4.2,
          hjust = 0
        ) +
        # Series wins meter: four pips per team, filled for each win so far
        geom_point(data = pips, aes(x = x, y = y, fill = won), shape = 21, size = 6.5, color = "#F8FAFC", stroke = 1.2) +
        scale_fill_manual(values = c("TRUE" = "#FACC15", "FALSE" = "#1F2937"), guide = "none") +
        geom_text(data = series_df, aes(x = x_pos + 1.8, y = y_pos - 0.5, label = sprintf("%d W", wins), color = lead),
                  fontface = "bold", size = 4.0) +
        scale_color_manual(values = c("TRUE" = "#FACC15", "FALSE" = "#94A3B8"), guide = "none") +
        # Clinch Banners
        { if (st$nl_w == 4) annotate("label", x = 7.5, y = 1.8, label = sprintf("★ NL CHAMPIONS (%s %d-%d) ★", nl$winner, st$nl_w, st$nl_l), fill = "#B45309", color = "#FFFFFF", fontface = "bold", size = 4.0) } +
        { if (st$al_w == 4) annotate("label", x = 2.5, y = 1.8, label = sprintf("★ AL CHAMPIONS (%s %d-%d) ★", al$winner, st$al_w, st$al_l), fill = "#0284C7", color = "#FFFFFF", fontface = "bold", size = 4.0) } +
        scale_x_continuous(limits = c(0.2, 9.8), expand = c(0, 0)) +
        scale_y_continuous(limits = c(0.8, 8.8), expand = c(0, 0)) +
        theme_mlb_dark(base_size = 11) +
        theme(
          axis.title = element_blank(),
          axis.text  = element_blank(),
          axis.ticks = element_blank(),
          panel.grid = element_blank()
        ) +
        labs(
          x = NULL, y = NULL,
          title = sprintf("%d League Championship Series — %s", season, st$title),
          subtitle = st$subtitle,
          caption = "Source: MLB Stats API schedule and results | Best-of-7 series, one frame per game number"
        )
    } else {
      # Climax World Series Emblem Matchup Banner
      ws_teams <- tibble(team_abbr = c(al$winner, nl$winner), x = c(2.8, 7.2), y = c(4.5, 4.5))

      p <- ggplot() +
        # Outer Gold Trim Banner
        annotate("rect", xmin = 0.5, xmax = 9.5, ymin = 0.8, ymax = 8.5, fill = "#0A0E17", color = "#FACC15", linewidth = 2.2, alpha = 0.95) +
        # Header Badge
        annotate("rect", xmin = 2.8, xmax = 7.2, ymin = 7.3, ymax = 8.3, fill = "#1E293B", color = "#FACC15", linewidth = 1.2) +
        annotate("text", x = 5.0, y = 7.8, label = sprintf("THE %d WORLD SERIES", season), color = "#FACC15", fontface = "bold", size = 6.2) +
        # Subtitle
        annotate("text", x = 5.0, y = 6.8, label = "AMERICAN LEAGUE CHAMPIONS VS NATIONAL LEAGUE CHAMPIONS", color = "#E2E8F0", fontface = "bold", size = 3.8) +
        # Giant Logos
        geom_mlb_logos(
          data = ws_teams,
          aes(x = x, y = y, team_abbr = team_abbr),
          width = 0.22
        ) +
        # Team Names & Accolades
        # Rays
        annotate("text", x = 2.8, y = 2.8, label = toupper(team_names[[al$winner]]), color = "#38BDF8", fontface = "bold", size = 5.2) +
        annotate("text", x = 2.8, y = 2.3, label = banner_line(al), color = "#CBD5E1", size = 3.2) +
        # Center VS Crest
        annotate("label", x = 5.0, y = 4.5, label = "VS", fill = "#B45309", color = "#FFFFFF", fontface = "bold", size = 6.5, label.padding = unit(0.5, "lines")) +
        # NL pennant winner
        annotate("text", x = 7.2, y = 2.8, label = toupper(team_names[[nl$winner]]), color = "#FBBF24", fontface = "bold", size = 5.2) +
        annotate("text", x = 7.2, y = 2.3, label = banner_line(nl), color = "#CBD5E1", size = 3.2) +
        # Bottom Current Status
        annotate("label", x = 5.0, y = 1.3, label = ws_final, fill = "#1E293B", color = "#F8FAFC", fontface = "bold", size = 3.8) +
        scale_x_continuous(limits = c(0.2, 9.8), expand = c(0, 0)) +
        scale_y_continuous(limits = c(0.5, 8.8), expand = c(0, 0)) +
        theme_mlb_dark(base_size = 11) +
        theme(
          axis.title = element_blank(),
          axis.text  = element_blank(),
          axis.ticks = element_blank(),
          panel.grid = element_blank()
        ) +
        labs(
          x = NULL, y = NULL,
          title = sprintf("%d World Series", season),
          subtitle = "The two pennant winners, their regular-season records, and the series each won to get there",
          caption = "Source: MLB Stats API schedule and results | Logos: mlbplotR"
        )
    }

    fpath <- file.path(tmp_dir, sprintf("frame_%03d.png", idx))
    ggsave(fpath, p, width = 12.0, height = 7.5, dpi = 110, bg = "#0A0E17")
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
  message(sprintf(">>> [SUCCESS] Pennant Showdown generated:\n    GIF: %s (%d KB, %.1fs)\n    PNG: %s (%d KB)",
                  target_gif, round(file.info(target_gif)$size / 1024), elapsed,
                  target_png, round(file.info(target_png)$size / 1024)))

  invisible(list(gif = target_gif, png = target_png))
}

if (sys.nframe() == 0) {
  generate_gif_pennant_showdown()
}
