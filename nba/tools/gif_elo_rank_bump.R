# ==============================================================================
# tools/gif_elo_rank_bump.R
# Path: tools/gif_elo_rank_bump.R
#
# NBA Elo Rank Bump Chart Animation (Season 2026-27)
# Animates the daily evolution of all 30 NBA teams' Elo ratings and ranks.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark() and official team primary colors
#   - renders dual artifacts: gif_elo_rank_bump.gif and gif_elo_rank_bump.png
#     (reduced-motion static final frame) via render_animated_artifact()
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds (preseason baseline seed ratings)
#   - Falls back gracefully to synthesized baseline if cache is missing
#
# Usage:
#   Rscript tools/gif_elo_rank_bump.R
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

all_teams <- sort(names(NBA_TEAM_COLORS))

# ------------------------------------------------------------------------------
# 1. Load Data & Compute Elo Trajectory
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")
ens_file <- find_cache_file("ensemble_team_ratings.rds")

# Initialize team ratings (base 1500)
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
history[[1]] <- data.frame(
  step = 0L,
  date_label = "Season Open",
  team = all_teams,
  elo = as.numeric(elo_cur[all_teams]),
  stringsAsFactors = FALSE
)

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  box$opp_clean  <- resolve_team_abbr(box$opponent_team_abbreviation)

  # Completed paired games
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

    history[[length(history) + 1]] <- data.frame(
      step = as.integer(idx),
      date_label = format(as.Date(d), "%b %d"),
      team = all_teams,
      elo = as.numeric(elo_cur[all_teams]),
      stringsAsFactors = FALSE
    )
  }
}

# If no games were found or only baseline exists, add mock progression steps for testing
if (length(history) <= 1) {
  for (i in 1:4) {
    sim_shift <- setNames(sin(seq_along(all_teams) + i) * 8, all_teams)
    elo_cur <- elo_cur + sim_shift
    history[[length(history) + 1]] <- data.frame(
      step = as.integer(i),
      date_label = sprintf("Day %d", i),
      team = all_teams,
      elo = as.numeric(elo_cur[all_teams]),
      stringsAsFactors = FALSE
    )
  }
}

hist_df <- do.call(rbind, history)
hist_df <- hist_df %>%
  group_by(step) %>%
  mutate(rank = rank(-elo, ties.method = "first")) %>%
  ungroup()

all_steps <- sort(unique(hist_df$step))
step_labels_map <- hist_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_elo_rank_bump_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)
max_step <- max(all_steps)

for (s in all_steps) {
  frame_lines <- hist_df %>% filter(step <= s)
  frame_pts   <- hist_df %>% filter(step == s)

  cur_label <- step_labels[[as.character(s)]]

  p_frame <- ggplot(frame_lines, aes(x = step, y = rank, group = team, color = team)) +
    geom_line(linewidth = 1.05, alpha = 0.85) +
    geom_point(data = frame_pts, aes(x = step, y = rank, fill = team),
               shape = 21, size = 3.6, color = NBA_COLORS$text, stroke = 1.1) +
    geom_text(data = frame_pts, aes(x = step + 0.12, y = rank, label = team),
              hjust = 0, vjust = 0.35, color = NBA_COLORS$text, fontface = "bold", size = 2.7) +
    scale_y_reverse(breaks = c(1, 5, 10, 15, 20, 25, 30), limits = c(30.6, 0.4)) +
    scale_x_continuous(breaks = all_steps, labels = step_labels, limits = c(-0.3, max_step + 0.8)) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "NBA Elo Rank Bump Race (2026-27)",
      subtitle = sprintf("Daily team power trajectory through %s (Rank 1 = Highest Elo)", cur_label),
      x = "Date",
      y = "Elo Rank (1 to 30)",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Elo Model"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 6.8, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG)
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_elo_rank_bump.gif")
out_png <- file.path(out_cache_dir, "gif_elo_rank_bump.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 680
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

cat(sprintf("[SUCCESS] Generated Elo Rank Bump:\n  GIF: %s (%d bytes)\n  PNG: %s (%d bytes)\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size))
