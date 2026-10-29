# ==============================================================================
# tools/gif_elo_delta_race.R
# Path: tools/gif_elo_delta_race.R
#
# NBA Elo Delta Power Rankings Bar Race Animation (Season 2026-27 - Issue #52)
# Animates week-over-week / rolling Elo rating deltas across all 30 NBA teams,
# displaying high-momentum risers and fallers.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and canonical team colors
#   - renders dual artifacts: gif_elo_delta_race.gif and gif_elo_delta_race.png
#     (reduced-motion static final frame) via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads ensemble_team_ratings.rds (preseason baseline seed ratings)
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_elo_delta_race.R
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
# 1. Load Data & Compute Elo History and Step-over-Step Deltas
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
  date_label = "Season Open",
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

hist_df <- bind_rows(history)

# Compute delta relative to prior step (or season baseline for step 0)
hist_df <- hist_df %>%
  group_by(team) %>%
  arrange(step) %>%
  mutate(
    prev_elo = lag(elo, default = first(elo)),
    delta_elo = elo - prev_elo,
    cum_delta = elo - first(elo)
  ) %>%
  ungroup()

# We display frames for steps >= 1 (where meaningful delta has occurred)
active_steps <- sort(unique(hist_df$step[hist_df$step >= 1L]))
if (length(active_steps) == 0) {
  active_steps <- sort(unique(hist_df$step))
}

step_labels_map <- hist_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames (Horizontal Bar Race Ranked by Delta Elo)
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_elo_delta_race_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)
x_min <- min(hist_df$delta_elo) - 5
x_max <- max(hist_df$delta_elo) + 8
if (x_min > -15) x_min <- -15
if (x_max < 15) x_max <- 15

for (s in active_steps) {
  frame_data <- hist_df %>%
    filter(step == s) %>%
    arrange(delta_elo) %>%
    mutate(
      bar_order = row_number(),
      label_str = sprintf("%+0.1f", delta_elo),
      is_positive = delta_elo >= 0
    )

  cur_label <- step_labels[[as.character(s)]]

  p_frame <- ggplot(frame_data, aes(x = delta_elo, y = reorder(team, bar_order), fill = team)) +
    geom_vline(xintercept = 0, color = NBA_COLORS$grid, linewidth = 0.8, linetype = "dashed") +
    geom_col(width = 0.75, alpha = 0.9, color = NBA_COLORS$border) +
    geom_text(
      aes(
        x = ifelse(delta_elo >= 0, delta_elo + 0.6, delta_elo - 0.6),
        label = label_str,
        hjust = ifelse(delta_elo >= 0, 0, 1)
      ),
      color = NBA_COLORS$text,
      size = 2.6,
      fontface = "bold"
    ) +
    scale_x_continuous(limits = c(x_min, x_max), breaks = scales::pretty_breaks(n = 6)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark(base_size = 10) +
    theme(
      axis.text.y = element_text(size = 7.5, face = "bold"),
      panel.grid.major.y = element_blank()
    ) +
    labs(
      title = "NBA Week-over-Week Elo Momentum Race (2026-27)",
      subtitle = sprintf("Power rankings Elo shift through %s (Ranked from Biggest Drop to Highest Surge)", cur_label),
      x = "Elo Rating Delta (\u0394)",
      y = "NBA Franchise",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Elo Delta Momentum"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7.5, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_elo_delta_race.gif")
out_png <- file.path(out_cache_dir, "gif_elo_delta_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 750
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_elo_delta_race.gif")
media_png <- file.path(web_media_dir, "gif_elo_delta_race.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Elo Delta Race:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
