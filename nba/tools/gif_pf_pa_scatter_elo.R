# ==============================================================================
# tools/gif_pf_pa_scatter_elo.R
# Path: tools/gif_pf_pa_scatter_elo.R
#
# NBA Points Scored vs. Allowed Scatter with Elo Bubble Scaling (Issue #54)
# Animates team scoring profiles:
#   - X-axis: Points Scored Per Game (Offensive Output)
#   - Y-axis: Points Allowed Per Game (Defensive Resistance, inverted so lower is top)
#   - Bubble Size: Scaled by current dynamic Elo rating
#   - Parity diagonal: Line of zero net scoring differential (PF = PA)
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and canonical team colors
#   - renders dual artifacts: gif_pf_pa_scatter_elo.gif and
#     gif_pf_pa_scatter_elo.png (reduced-motion static final frame)
#     via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds (preseason baseline Elo ratings)
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_pf_pa_scatter_elo.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# Locate root directory and source visualization foundations
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- args[grepl("^--file=", args)]
  base <- if (length(f) == 1L) dirname(normalizePath(sub("^--file=", "", f))) else getwd()
  repo <- if (file.exists(file.path(base, "tools", "viz_common.R"))) base else dirname(base)
  normalizePath(repo, winslash = "/", mustWork = FALSE)
})

viz_common_path <- file.path(SCRIPT_DIR, "tools", "viz_common.R")
if (!file.exists(viz_common_path)) {
  viz_common_path <- file.path(getwd(), "tools", "viz_common.R")
}
source(viz_common_path)

config_path <- file.path(SCRIPT_DIR, "config.R")
if (file.exists(config_path)) {
  source(config_path)
}

# Resolve cache file helper
find_cache_file <- function(filename) {
  candidates <- c(
    if (exists("CACHE_DIR")) file.path(CACHE_DIR, filename) else NULL,
    if (exists("PROJECT_DIR")) file.path(PROJECT_DIR, "cache", filename) else NULL,
    file.path(SCRIPT_DIR, "cache", filename),
    file.path(getwd(), "cache", filename),
    file.path("..", "NBA Analytics", "cache", filename),
    file.path("C:/Users/kailo/kayceeslices/front-office/NBA Analytics/cache", filename)
  )
  for (cand in candidates) {
    if (!is.null(cand) && file.exists(cand)) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  return(NULL)
}

out_cache_dir <- file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

web_media_dir <- file.path(SCRIPT_DIR, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

all_teams <- sort(names(NBA_TEAM_COLORS))

# ------------------------------------------------------------------------------
# 1. Load Data & Compute Scoring Trajectory and Dynamic Elo
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")
ens_file <- find_cache_file("ensemble_team_ratings.rds")

# Initialize baseline ratings (base 1500)
elo_cur <- setNames(rep(1500.0, length(all_teams)), all_teams)

if (!is.null(ens_file)) {
  ens <- tryCatch(readRDS(ens_file), error = function(e) NULL)
  if (!is.null(ens) && "team" %in% names(ens) && "ensemble_net_rating" %in% names(ens)) {
    for (i in seq_len(nrow(ens))) {
      tm <- resolve_team_abbr(ens$team[i])
      if (!is.na(tm) && tm %in% all_teams) {
        elo_cur[tm] <- 1500 + as.numeric(ens$ensemble_net_rating[i]) * 25
      }
    }
  }
}

scatter_history <- list()

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  dates <- sort(unique(box$game_date))

  # Build unique games for Elo simulation
  home_rows <- box[box$team_home_away == "home", ]
  away_rows <- box[box$team_home_away == "away", ]
  games_df <- merge(
    home_rows[, c("game_id", "game_date", "team_clean", "team_score")],
    away_rows[, c("game_id", "team_clean", "team_score")],
    by = "game_id",
    suffixes = c("_home", "_away")
  )
  games_df <- games_df[order(games_df$game_date, games_df$game_id), ]

  # Map of elo by date
  elo_by_date <- list()
  for (idx in seq_along(dates)) {
    d <- dates[idx]
    day_games <- games_df[games_df$game_date == d, ]
    if (nrow(day_games) > 0) {
      for (g in seq_len(nrow(day_games))) {
        h <- day_games$team_clean_home[g]
        a <- day_games$team_clean_away[g]
        hs <- as.numeric(day_games$team_score_home[g])
        as_pts <- as.numeric(day_games$team_score_away[g])

        if (!is.na(h) && !is.na(a) && h %in% all_teams && a %in% all_teams) {
          # Home court advantage 100
          elo_h_adj <- elo_cur[h] + 100
          elo_a_adj <- elo_cur[a]
          exp_h <- 1 / (1 + 10^((elo_a_adj - elo_h_adj) / 400))
          act_h <- ifelse(hs > as_pts, 1.0, ifelse(hs == as_pts, 0.5, 0.0))
          mov <- abs(hs - as_pts)
          elo_diff <- ifelse(act_h == 1, elo_h_adj - elo_a_adj, elo_a_adj - elo_h_adj)
          mov_mult <- log(pmax(mov, 1) + 1) * (2.2 / ((elo_diff * 0.001) + 2.2))
          k <- 20 * mov_mult
          delta <- k * (act_h - exp_h)
          elo_cur[h] <- elo_cur[h] + delta
          elo_cur[a] <- elo_cur[a] - delta
        }
      }
    }
    elo_by_date[[as.character(d)]] <- elo_cur
  }

  for (idx in seq_along(dates)) {
    d <- dates[idx]
    sub_box <- box[box$game_date <= d, ]
    d_elo <- elo_by_date[[as.character(d)]]

    stats <- sub_box %>%
      group_by(team = team_clean) %>%
      summarize(
        games = n(),
        pts_for = sum(as.numeric(team_score)),
        pts_against = sum(as.numeric(opponent_team_score)),
        .groups = "drop"
      ) %>%
      mutate(
        ppg_for = pts_for / pmax(games, 1),
        ppg_against = pts_against / pmax(games, 1),
        diff = ppg_for - ppg_against,
        elo = as.numeric(d_elo[team]),
        step = as.integer(idx),
        date_label = format(as.Date(d), "%b %d")
      )

    missing_teams <- setdiff(all_teams, stats$team)
    if (length(missing_teams) > 0) {
      missing_df <- tibble(
        team = missing_teams,
        games = 0L,
        pts_for = 0,
        pts_against = 0,
        ppg_for = 112.0,
        ppg_against = 112.0,
        diff = 0.0,
        elo = as.numeric(d_elo[missing_teams]),
        step = as.integer(idx),
        date_label = format(as.Date(d), "%b %d")
      )
      stats <- bind_rows(stats, missing_df)
    }

    scatter_history[[idx]] <- stats
  }
}

if (length(scatter_history) == 0) {
  for (i in 1:5) {
    scatter_history[[i]] <- tibble(
      team = all_teams,
      games = i,
      pts_for = 112 * i + sin(seq_along(all_teams) + i) * 6,
      pts_against = 112 * i - sin(seq_along(all_teams) + i) * 5,
      ppg_for = 112 + sin(seq_along(all_teams) + i) * 5,
      ppg_against = 112 - cos(seq_along(all_teams) + i) * 5,
      diff = 10 * sin(seq_along(all_teams) + i),
      elo = 1500 + sin(seq_along(all_teams) + i) * 80,
      step = as.integer(i),
      date_label = sprintf("Day %d", i)
    )
  }
}

scatter_df <- bind_rows(scatter_history)
all_steps <- sort(unique(scatter_df$step))

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_pf_pa_scatter_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)

x_min <- floor(min(scatter_df$ppg_for) - 2)
x_max <- ceiling(max(scatter_df$ppg_for) + 2)
y_min <- floor(min(scatter_df$ppg_against) - 2)
y_max <- ceiling(max(scatter_df$ppg_against) + 2)

for (s in all_steps) {
  frame_data <- scatter_df %>% filter(step == s)
  cur_label <- frame_data$date_label[1]

  mean_pf <- mean(frame_data$ppg_for)
  mean_pa <- mean(frame_data$ppg_against)

  # Note: Y-axis is reversed (lower PA is better defense -> placed near top)
  p_frame <- ggplot(frame_data, aes(x = ppg_for, y = ppg_against)) +
    # Parity diagonal (y = x)
    geom_abline(intercept = 0, slope = 1, linetype = "dotted", color = NBA_COLORS$grid, linewidth = 0.8) +
    # League average reference lines
    geom_vline(xintercept = mean_pf, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.6) +
    geom_hline(yintercept = mean_pa, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.6) +
    # Quadrant annotations
    annotate("text", x = x_max - 0.5, y = y_min + 0.8, label = "Dominant Contenders (High PF / Low PA)",
             color = NBA_COLORS$accent, fontface = "bold", size = 3.4, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_min + 0.8, label = "Defensive Specialists (Low PF / Low PA)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 0) +
    annotate("text", x = x_max - 0.5, y = y_max - 0.8, label = "High-Scoring Shootouts (High PF / High PA)",
             color = NBA_COLORS$subtext, fontface = "italic", size = 3.2, hjust = 1) +
    annotate("text", x = x_min + 0.5, y = y_max - 0.8, label = "Struggling Lottery (Low PF / High PA)",
             color = NBA_COLORS$negative, fontface = "bold", size = 3.2, hjust = 0) +
    # Bubble points scaled by Elo
    geom_point(aes(fill = team, size = elo), shape = 21, color = NBA_COLORS$text, stroke = 1.0, alpha = 0.9) +
    scale_size_continuous(range = c(3.5, 9.0), guide = "none") +
    geom_text(aes(label = team), color = NBA_COLORS$text, vjust = -1.15, fontface = "bold", size = 2.8) +
    scale_x_continuous(limits = c(x_min, x_max), breaks = scales::pretty_breaks(n = 6)) +
    # Invert Y so lower points allowed (better defense) is at the top
    scale_y_reverse(limits = c(y_max, y_min), breaks = scales::pretty_breaks(n = 6)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "NBA Points Scored vs. Allowed Profile with Elo Weighting",
      subtitle = sprintf("Points For vs. Points Against per game through %s (Bubble size proportional to Elo)", cur_label),
      x = "Points For Per Game (Offensive Output)",
      y = "Points Allowed Per Game (Inverted: Lower is Better Defense)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Dotted diagonal: Even Differential \u00b7 Bubble: Elo Rating"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_pf_pa_scatter_elo.gif")
out_png <- file.path(out_cache_dir, "gif_pf_pa_scatter_elo.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 700
)

unlink(tmp_frame_dir, recursive = TRUE)

media_gif <- file.path(web_media_dir, "gif_pf_pa_scatter_elo.gif")
media_png <- file.path(web_media_dir, "gif_pf_pa_scatter_elo.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated PF/PA Scatter with Elo:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
