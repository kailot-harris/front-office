# ==============================================================================
# tools/gif_elo_heatmap.R
# Path: tools/gif_elo_heatmap.R
#
# NBA Elo Heatmap & Momentum Matrix Animation (Season 2026-27 - Issue #51)
# Animates a 2D tile matrix (30 teams x weeks/steps) capturing Elo ratings,
# shifts, and momentum as the season progresses.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and diverging/continuous palette
#   - renders dual artifacts: gif_elo_heatmap.gif and gif_elo_heatmap.png
#     (reduced-motion static final frame) via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds (preseason baseline seed ratings)
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_elo_heatmap.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
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

# Ensure output cache directory exists
out_cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(SCRIPT_DIR, "cache")
if (!dir.exists(out_cache_dir)) dir.create(out_cache_dir, recursive = TRUE)

web_media_dir <- file.path(SCRIPT_DIR, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

all_teams <- sort(names(NBA_TEAM_COLORS))

# ------------------------------------------------------------------------------
# 1. Load Data & Compute Elo History Across Date Steps
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

history <- list()
history[[1]] <- tibble(
  step = 0L,
  date_label = "Open",
  team = all_teams,
  elo = as.numeric(elo_cur[all_teams])
)

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  box$opp_clean  <- resolve_team_abbr(box$opponent_team_abbreviation)

  paired_games <- box[as.character(box$team_clean) < as.character(box$opp_clean), ]
  paired_games <- paired_games[order(as.Date(paired_games$game_date), paired_games$game_id), ]

  dates <- sort(unique(paired_games$game_date))
  K <- 20

  for (idx in seq_along(dates)) {
    d <- dates[idx]
    d_games <- paired_games[paired_games$game_date == d, ]
    if (nrow(d_games) > 0) {
      for (g in seq_len(nrow(d_games))) {
        t1 <- d_games$team_clean[g]
        t2 <- d_games$opp_clean[g]
        s1 <- as.numeric(d_games$team_score[g])
        s2 <- as.numeric(d_games$opponent_team_score[g])

        r1 <- elo_cur[t1]
        r2 <- elo_cur[t2]

        e1 <- 1 / (1 + 10^((r2 - r1) / 400))
        e2 <- 1 - e1

        w1 <- if (s1 > s2) 1.0 else 0.0
        w2 <- 1.0 - w1

        mov <- abs(s1 - s2)
        mult <- log(mov + 1) * (2.2 / (abs(r1 - r2) * 0.001 + 2.2))

        elo_cur[t1] <- r1 + K * mult * (w1 - e1)
        elo_cur[t2] <- r2 + K * mult * (w2 - e2)
      }
    }

    history[[length(history) + 1]] <- tibble(
      step = as.integer(idx),
      date_label = format(as.Date(d), "%b %d"),
      team = all_teams,
      elo = as.numeric(elo_cur[all_teams])
    )
  }
}

# Fallback if insufficient history
if (length(history) <= 1) {
  for (i in 1:5) {
    sim_shift <- setNames(sin(seq_along(all_teams) + i) * 8, all_teams)
    elo_cur <- elo_cur + sim_shift
    history[[length(history) + 1]] <- tibble(
      step = as.integer(i),
      date_label = sprintf("Day %d", i),
      team = all_teams,
      elo = as.numeric(elo_cur[all_teams])
    )
  }
}

full_elo_df <- bind_rows(history)
all_steps <- sort(unique(full_elo_df$step))
max_step  <- max(all_steps)

step_labels_map <- full_elo_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

# Order teams by final Elo rating (highest on top)
final_elos <- full_elo_df %>%
  filter(step == max_step) %>%
  arrange(elo)
team_order <- final_elos$team
full_elo_df$team <- factor(full_elo_df$team, levels = team_order)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames (2D Heatmap Grid Revealing Over Time)
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_elo_heatmap_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)
elo_min <- round(min(full_elo_df$elo) - 10)
elo_max <- round(max(full_elo_df$elo) + 10)
mid_elo <- 1500

for (s in all_steps) {
  # All cells exist up to max_step, but only revealed (or highlighted) up to current step s
  revealed_df <- full_elo_df %>% filter(step <= s)
  cur_label   <- step_labels[[as.character(s)]]

  p_frame <- ggplot(revealed_df, aes(x = step, y = team, fill = elo)) +
    geom_tile(color = NBA_COLORS$panel, linewidth = 0.5) +
    geom_text(aes(label = round(elo)), color = NBA_COLORS$text, size = 2.4, fontface = "bold") +
    scale_x_continuous(
      breaks = all_steps,
      labels = step_labels,
      limits = c(-0.5, max_step + 0.5),
      expand = c(0, 0)
    ) +
    scale_fill_gradient2(
      low = NBA_COLORS$negative,
      mid = NBA_COLORS$panel,
      high = NBA_COLORS$accent,
      midpoint = mid_elo,
      limits = c(elo_min, elo_max),
      name = "Elo Rating"
    ) +
    theme_nba_dark(base_size = 10) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
      axis.text.y = element_text(size = 7.5, face = "bold"),
      panel.grid = element_blank(),
      legend.position = "right"
    ) +
    labs(
      title = "NBA League-Wide Elo Momentum Heatmap (2026-27)",
      subtitle = sprintf("2D matrix of team Elo trajectory through %s (Ranked by Current Elo)", cur_label),
      x = "Season Calendar / Timeline",
      y = "Team (Sorted by Final Elo)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Elo Momentum Heatmap"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7.2, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_elo_heatmap.gif")
out_png <- file.path(out_cache_dir, "gif_elo_heatmap.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 720
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_elo_heatmap.gif")
media_png <- file.path(web_media_dir, "gif_elo_heatmap.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Elo Heatmap:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
