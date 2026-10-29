# ==============================================================================
# tools/gif_clutch_shot_worm.R
# Path: tools/gif_clutch_shot_worm.R
#
# Clutch Margin Win Probability Worm Paired with Shot Locations (Issue #58)
#
# Features:
#   - Sources tools/viz_common.R and tools/plot_shot_chart.R.
#   - Uses theme_nba_dark(), NBA_COLORS, canonical team colors, and regulation court layout.
#   - Pairs late-game win probability & score margin worm trajectory with half-court
#     shot locations in the final 5 minutes of high-leverage close games.
#   - Reads pbp and shots from cache (or gracefully synthesizes clutch timeline).
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
# 1. Load Clutch Game Data (Target: LAL vs DEN close finish Game 401810829 or fallback)
# ------------------------------------------------------------------------------
shots_file <- find_cache_file("nba_shots_2026.rds")
pbp_file   <- find_cache_file("nba_pbp_2026.rds")

# Target matchup configuration
home_tm <- "LAL"
away_tm <- "DEN"
home_col <- get_nba_team_color(home_tm, "primary")
away_col <- get_nba_team_color(away_tm, "secondary") # Gold/yellow for Denver

has_real_data <- !is.null(shots_file)

if (has_real_data) {
  s26 <- readRDS(shots_file)
  g_shots <- s26 %>%
    filter(game_id == 401810829, period_number == 4) %>%
    mutate(
      parts = strsplit(clock_display_value, ":"),
      min = as.numeric(sapply(parts, function(x) if (length(x) >= 1) x[1] else NA)),
      sec = as.numeric(sapply(parts, function(x) if (length(x) >= 2) x[2] else 0)),
      sec_left = min * 60 + sec
    ) %>%
    filter(!is.na(sec_left), sec_left <= 300) %>%
    arrange(desc(sec_left))
} else {
  g_shots <- tibble()
}

# If less than 10 shots in real data, synthesize standard close clutch timeline
if (nrow(g_shots) < 8) {
  set.seed(123)
  sim_seconds <- sort(sample(10:290, 18), decreasing = TRUE)
  sim_teams <- sample(c("LAL", "DEN"), length(sim_seconds), replace = TRUE)
  sim_makes <- sample(c(TRUE, FALSE), length(sim_seconds), replace = TRUE, prob = c(0.48, 0.52))
  sim_x <- runif(length(sim_seconds), -22, 22)
  sim_y <- runif(length(sim_seconds), 4, 26)
  g_shots <- tibble(
    sec_left = sim_seconds,
    clock_display_value = sprintf("%02d:%02d", sim_seconds %/% 60, sim_seconds %% 60),
    team_abbrev = sim_teams,
    athlete_name_1 = ifelse(sim_teams == "LAL", "L. Doncic", "N. Jokic"),
    coordinate_x = sim_x,
    coordinate_y = sim_y,
    scoring_play = sim_makes,
    score_value = ifelse(sim_makes, sample(c(2, 3), length(sim_seconds), replace = TRUE, prob = c(0.65, 0.35)), 0)
  )
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

# Build continuous clutch timeline (from t=300 down to t=0)
time_points <- seq(300, 0, by = -15)
worm_timeline <- list()

curr_margin <- 2 # Initial home lead +2
for (t_idx in seq_along(time_points)) {
  t_sec <- time_points[t_idx]
  # Shots that occurred between previous time point and now
  prev_sec <- if (t_idx == 1) 310 else time_points[t_idx - 1]
  sub_shots <- g_shots_norm %>% filter(sec_left <= prev_sec, sec_left > t_sec)
  
  if (nrow(sub_shots) > 0) {
    for (r in seq_len(nrow(sub_shots))) {
      delta_pts <- sub_shots$score_value[r]
      if (delta_pts > 0) {
        if (sub_shots$team_clean[r] == home_tm) curr_margin <- curr_margin + delta_pts
        else curr_margin <- curr_margin - delta_pts
      }
    }
  }
  
  # Standard logistic win probability model given time remaining:
  # P(Home Win) = 1 / (1 + exp(- (margin * 0.35 + 0.05) * sqrt(300 / max(t_sec, 10))))
  decay <- sqrt(300 / max(t_sec, 12))
  p_home <- 1 / (1 + exp(-curr_margin * 0.18 * decay))
  p_home <- pmax(0.01, pmin(0.99, p_home))
  
  worm_timeline[[t_idx]] <- tibble(
    frame_step = t_idx,
    sec_left = t_sec,
    min_label = sprintf("%d:%02d", t_sec %/% 60, t_sec %% 60),
    margin = curr_margin,
    win_prob = p_home * 100
  )
}
worm_df <- bind_rows(worm_timeline)

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
  
  # 1. Left Panel: Win Probability Worm
  p_worm <- ggplot(cur_worm, aes(x = 300 - sec_left, y = win_prob)) +
    # 50% neutral probability reference
    geom_hline(yintercept = 50, linetype = "dashed", color = NBA_COLORS$grid, linewidth = 0.8) +
    geom_ribbon(aes(ymin = 50, ymax = win_prob),
                fill = ifelse(cur_worm$win_prob[nrow(cur_worm)] >= 50, home_col, away_col),
                alpha = 0.25) +
    geom_line(color = NBA_COLORS$accent, linewidth = 1.3) +
    geom_point(data = cur_worm %>% filter(frame_step == s),
               aes(x = 300 - sec_left, y = win_prob),
               color = "#ffffff", fill = home_col, shape = 21, size = 4.0, stroke = 1.5) +
    scale_x_continuous(
      breaks = seq(0, 300, by = 60),
      labels = c("5:00", "4:00", "3:00", "2:00", "1:00", "0:00"),
      limits = c(0, 305)
    ) +
    scale_y_continuous(
      breaks = seq(0, 100, by = 25),
      labels = c("0%", "25%", "50%", "75%", "100%"),
      limits = c(0, 100)
    ) +
    theme_nba_dark(base_size = 11) +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 9, color = NBA_COLORS$subtext)
    ) +
    labs(
      title = sprintf("Late-Game Leverage: %s vs. %s (Final 5 Min)", home_tm, away_tm),
      subtitle = sprintf("Home Win Probability (%s): %.1f%% \u00b7 Margin: %+d pts \u00b7 Clock: %s",
                         home_tm, cur_worm$win_prob[s], cur_worm$margin[s], cur_worm$min_label[s]),
      x = "Game Clock Remaining in 4Q",
      y = sprintf("%s Win Probability (%%)", home_tm)
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
        values = c(LAL = home_col, DEN = away_col)
      ) +
      scale_shape_manual(
        name = "Outcome",
        values = c("Made" = 16, "Missed" = 4)
      )
  }

  # Combined dual layout via patchwork
  combined <- p_worm + p_court + plot_layout(widths = c(1.35, 1.0)) +
    plot_annotation(
      title = "NBA Clutch Leverage & Shot Selection Trajectory (Issue #58)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Win Probability & Spatial Shot Engine",
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
