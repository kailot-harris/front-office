# ==============================================================================
# tools/gif_clutch_shot_worm.R
# Path: tools/gif_clutch_shot_worm.R
#
# Closing-stretch score margin paired with shot locations
#
# Features:
#   - Sources tools/viz_common.R and tools/plot_shot_chart.R.
#   - Uses theme_nba_dark(), NBA_COLORS, canonical team colors, and regulation court layout.
#   - Pairs the real score margin through the final five minutes with half-court
#     shot locations in the final 5 minutes of high-leverage close games.
#   - Reads play-by-play and shots from cache. No fallback: with no qualifying
#     game the chart is not rendered. The margin is the play-by-play score, not
#     a modelled win probability.
#   - Outputs dual artifacts: cache/gif_clutch_shot_worm.gif and cache/gif_clutch_shot_worm.png
#     via render_animated_artifact().
#   - Syncs artifacts to web/public/media/.
#
# Usage:
#   Rscript tools/gif_clutch_shot_worm.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
})

# Locate root directory and source visualization foundations
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

viz_common_path <- file.path(SCRIPT_DIR, "tools", "viz_common.R")
if (!file.exists(viz_common_path)) {
  viz_common_path <- file.path(getwd(), "tools", "viz_common.R")
}
source(viz_common_path)

plot_shot_chart_path <- file.path(SCRIPT_DIR, "tools", "plot_shot_chart.R")
if (!file.exists(plot_shot_chart_path)) {
  plot_shot_chart_path <- file.path(getwd(), "tools", "plot_shot_chart.R")
}
source(plot_shot_chart_path)

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

out_cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

web_media_dir <- file.path(SCRIPT_DIR, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
# 1. Discover a Real Clutch Game (most recent close finish in the current-season
#    cache) instead of rendering a single frozen, hardcoded matchup every run.
# ------------------------------------------------------------------------------

# A "clutch" game is one where the score margin got within this many points at
# some point during the final 5 minutes of the 4th quarter (period_number == 4,
# end_quarter_seconds_remaining <= 300). Concrete and checkable, not just "the
# last row in the cache".
CLUTCH_MARGIN_THRESHOLD <- 8
CLUTCH_MIN_SHOTS <- 8

# Prefer the current season's caches, falling back to the prior season if the
# current one isn't populated yet.
shots_file <- find_cache_file("nba_shots_2027.rds")
if (is.null(shots_file)) shots_file <- find_cache_file("nba_shots_2026.rds")

pbp_file <- find_cache_file("nba_pbp_2027.rds")
if (is.null(pbp_file)) pbp_file <- find_cache_file("nba_pbp_2026.rds")

has_real_data <- !is.null(shots_file) && !is.null(pbp_file)

selected_game_id <- NA_integer_
home_tm <- NA_character_
away_tm <- NA_character_
g_shots <- tibble()

parse_sec_left <- function(df) {
  df %>%
    mutate(
      parts = strsplit(clock_display_value, ":"),
      min = as.numeric(sapply(parts, function(x) if (length(x) >= 1) x[1] else NA)),
      sec = as.numeric(sapply(parts, function(x) if (length(x) >= 2) x[2] else 0)),
      sec_left = min * 60 + sec
    ) %>%
    select(-parts)
}

if (has_real_data) {
  shots_all <- readRDS(shots_file)
  pbp_all   <- readRDS(pbp_file)

  # Candidate clutch games: games whose 4th-quarter margin came within
  # CLUTCH_MARGIN_THRESHOLD points at some point in the final 5 minutes.
  clutch_candidates <- pbp_all %>%
    filter(period_number == 4, end_quarter_seconds_remaining <= 300) %>%
    group_by(game_id, home_team_abbrev, away_team_abbrev, game_date) %>%
    summarise(
      min_margin = min(abs(home_score - away_score), na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(min_margin <= CLUTCH_MARGIN_THRESHOLD) %>%
    arrange(desc(game_date), min_margin)

  # Walk candidates from most-recent/closest down, picking the first one that
  # also has enough real shot data in the final 5 minutes to draw the court panel.
  for (i in seq_len(nrow(clutch_candidates))) {
    cand <- clutch_candidates[i, ]
    cand_shots <- shots_all %>%
      filter(game_id == cand$game_id, period_number == 4) %>%
      parse_sec_left() %>%
      filter(!is.na(sec_left), sec_left <= 300) %>%
      arrange(desc(sec_left))

    if (nrow(cand_shots) >= CLUTCH_MIN_SHOTS) {
      selected_game_id <- cand$game_id
      selected_game_date <- as.Date(cand$game_date)
      # Normalize through resolve_team_abbr() so these match the standard
      # abbreviations used by get_nba_team_color() and the shots' team_clean
      # below (e.g. pbp's "NY" -> "NYK").
      home_tm <- resolve_team_abbr(cand$home_team_abbrev)
      away_tm <- resolve_team_abbr(cand$away_team_abbrev)
      g_shots <- cand_shots
      break
    }
  }
}

# No qualifying clutch game found (either no cache, or nothing met the margin /
# shot-volume bar) -- fail the same clear, intentional way as missing-data cases
# elsewhere in this script rather than crashing.
if (nrow(g_shots) < CLUTCH_MIN_SHOTS) {
  viz_stop_no_data(
    "tools/gif_clutch_shot_worm.R",
    if (has_real_data) sprintf("no game in %s reached a <= %d pt margin in the final 5 minutes with >= %d tracked clutch shots.",
                                basename(shots_file), CLUTCH_MARGIN_THRESHOLD, CLUTCH_MIN_SHOTS)
    else "cache files nba_shots_2027.rds/nba_pbp_2027.rds (or their 2026 fallbacks) were not found."
  )
}

home_col <- get_nba_team_color(home_tm, "primary")
away_col <- get_nba_team_color(away_tm, "secondary")

# Actual home/away score margin at the start of the clutch window (game clock
# 5:00 remaining in the 4th), used to seed the win-probability worm below.
margin_at_start <- pbp_all %>%
  filter(game_id == selected_game_id, period_number == 4,
         end_quarter_seconds_remaining >= 300) %>%
  arrange(end_quarter_seconds_remaining) %>%
  slice_tail(n = 1)

start_margin <- if (nrow(margin_at_start) > 0) {
  home_val <- margin_at_start$home_score[1]
  away_val <- margin_at_start$away_score[1]
  if (resolve_team_abbr(margin_at_start$home_team_abbrev[1]) == home_tm) home_val - away_val else away_val - home_val
} else {
  0
}

# Normalize shot coordinates to half court (-25 to 25 x, 0 to 47 y)
g_shots_norm <- g_shots %>%
  mutate(
    team_clean = resolve_team_abbr(team_abbrev),
    # Map ESPN tracking coords (-47..47, -25..25) to court geometry
    court_x = pmax(-24, pmin(24, coordinate_y)),
    court_y = pmax(2, pmin(35, abs(coordinate_x) - 10)),
    is_made = as.logical(scoring_play),
    made_label = ifelse(is_made, "Made", "Missed")
  )

# Real home-team margin at each 15-second mark of the final five minutes, read
# from the play-by-play score. Nothing is modelled or estimated here.
game_pbp <- pbp_all %>%
  filter(game_id == selected_game_id, period_number == 4,
         !is.na(home_score), !is.na(away_score), !is.na(end_quarter_seconds_remaining))

margin_at <- function(t_sec) {
  rows <- game_pbp[game_pbp$end_quarter_seconds_remaining >= t_sec, , drop = FALSE]
  if (nrow(rows) == 0) return(NA_real_)
  rows <- rows[rows$end_quarter_seconds_remaining == min(rows$end_quarter_seconds_remaining), , drop = FALSE]
  last <- rows[nrow(rows), ]
  as.numeric(last$home_score - last$away_score)
}

time_points <- seq(300, 0, by = -15)
margins <- vapply(time_points, margin_at, numeric(1))
if (is.na(margins[1])) margins[1] <- start_margin
for (k in seq_along(margins)[-1]) if (is.na(margins[k])) margins[k] <- margins[k - 1]

worm_df <- tibble(
  frame_step = seq_along(time_points),
  sec_left = time_points,
  min_label = sprintf("%d:%02d", time_points %/% 60, time_points %% 60),
  margin = as.integer(margins)
)
margin_lim <- max(6, max(abs(worm_df$margin)) + 2)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames (Paired Win Prob Worm + Half-Court Shot Locations)
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), sprintf("clutch_worm_frames_%d", as.integer(Sys.time())))
if (!dir.exists(tmp_frame_dir)) dir.create(tmp_frame_dir, recursive = TRUE)

total_steps <- nrow(worm_df)
frame_files <- character(total_steps)

for (s in seq_len(total_steps)) {
  cur_worm <- worm_df %>% filter(frame_step <= s)
  cur_time <- worm_df$sec_left[s]
  
  # Shots accumulated up to current time (from t=300 down to cur_time)
  cur_shots <- g_shots_norm %>% filter(sec_left >= cur_time)
  
  # 1. Left Panel: real score margin
  p_worm <- ggplot(cur_worm, aes(x = 300 - sec_left, y = margin)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.8) +
    geom_ribbon(aes(ymin = 0, ymax = margin),
                fill = ifelse(cur_worm$margin[nrow(cur_worm)] >= 0, home_col, away_col),
                alpha = 0.25) +
    geom_line(color = NBA_COLORS$accent, linewidth = 1.3) +
    geom_point(data = cur_worm %>% filter(frame_step == s),
               aes(x = 300 - sec_left, y = margin),
               color = "#ffffff", fill = home_col, shape = 21, size = 4.0, stroke = 1.5) +
    scale_x_continuous(
      breaks = seq(0, 300, by = 60),
      labels = c("5:00", "4:00", "3:00", "2:00", "1:00", "0:00"),
      limits = c(0, 305)
    ) +
    scale_y_continuous(
      limits = c(-margin_lim, margin_lim),
      labels = function(v) sprintf("%+d", as.integer(v))
    ) +
    theme_nba_dark(base_size = 11) +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9, color = NBA_COLORS$subtext)
    ) +
    labs(
      title = sprintf("Final Five Minutes: %s at %s", away_tm, home_tm),
      subtitle = sprintf("%s margin: %+d pts \u00b7 Clock: %s",
                         home_tm, cur_worm$margin[s], cur_worm$min_label[s]),
      x = "Game Clock Remaining in 4Q",
      y = sprintf("%s lead (points)", home_tm)
    )

  # 2. Right Panel: Half-Court Shot Location Tracker
  p_court <- ggplot() +
    create_nba_court_elements(line_color = "#334155", linewidth = 0.6) +
    coord_fixed(xlim = c(-25, 25), ylim = c(0, 42)) +
    theme_nba_dark(base_size = 11) +
    theme(
      axis.text = element_blank(),
      axis.title = element_blank(),
      axis.ticks = element_blank(),
      panel.grid = element_blank(),
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9, color = NBA_COLORS$subtext),
      legend.position = "bottom",
      legend.margin = margin(t = -5)
    ) +
    labs(
      title = "Clutch Shot Locations",
      subtitle = sprintf("Shots taken through %s: %d total", cur_worm$min_label[s], nrow(cur_shots))
    )

  if (nrow(cur_shots) > 0) {
    p_court <- p_court +
      geom_point(
        data = cur_shots,
        aes(x = court_x, y = court_y, color = team_clean, shape = made_label),
        size = 3.5, stroke = 1.2, alpha = 0.88
      ) +
      scale_color_manual(
        name = "Team",
        values = setNames(c(home_col, away_col), c(home_tm, away_tm))
      ) +
      scale_shape_manual(
        name = "Outcome",
        values = c("Made" = 16, "Missed" = 4)
      )
  }

  # Combined dual layout via patchwork
  combined <- p_worm + p_court + plot_layout(widths = c(1.35, 1.0)) +
    plot_annotation(
      title = "Closing Stretch: Score Margin and Shot Locations",
      caption = sprintf("Game played %s. Score and shots from ESPN play-by-play via hoopR.", format(selected_game_date, "%b %d, %Y")),
      theme = theme(
        plot.background = element_rect(fill = NBA_COLORS$bg, color = NA),
        plot.title = element_text(size = 13, face = "bold", color = NBA_COLORS$text),
        plot.caption = element_text(size = 8, color = NBA_COLORS$subtext)
      )
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = combined, width = 12, height = 6.2, dpi = 110, bg = NBA_COLORS$bg)
  frame_files[s] <- frame_path
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_clutch_shot_worm.gif")
out_png <- file.path(out_cache_dir, "gif_clutch_shot_worm.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 6,
  width            = 1200,
  height           = 620
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_clutch_shot_worm.gif")
media_png <- file.path(web_media_dir, "gif_clutch_shot_worm.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Clutch Shot Worm:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
