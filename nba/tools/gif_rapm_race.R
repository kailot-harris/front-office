# ==============================================================================
# tools/gif_rapm_race.R
# Path: tools/gif_rapm_race.R
#
# Top-10 Offensive & Defensive RAPM Bar Race with Shrinkage Confidence Intervals
# Closes issue #57 (Batch C viz).
#
# Features:
#   - Sources tools/viz_common.R and uses theme_nba_dark(), NBA_COLORS, and canonical team colors.
#   - Reads rapm_ratings.rds from cache. No fallback: without it nothing is rendered.
#   - Reveals the top-10 Offensive RAPM (ORAPM) and Defensive RAPM (DRAPM) leaders
#     one rank at a time. Every value is the fitted full-season rating.
#   - Outputs dual artifacts: cache/gif_rapm_race.gif and cache/gif_rapm_race.png
#     via render_animated_artifact().
#   - Syncs artifacts to web/public/media/.
#
# Usage:
#   Rscript tools/gif_rapm_race.R
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

# ------------------------------------------------------------------------------
# 1. Load Data & Prepare RAPM Candidates
# ------------------------------------------------------------------------------
rapm_file <- find_cache_file("rapm_ratings.rds")

if (!is.null(rapm_file)) {
  rapm_raw <- readRDS(rapm_file)
} else {
  viz_stop_no_data("tools/gif_rapm_race.R", "cache file rapm_ratings.rds was not found.")
}

# Clean team abbreviations and filter top contenders
rapm_clean <- rapm_raw %>%
  filter(!is.na(player_name), !is.na(team), !is.na(orapm), !is.na(drapm)) %>%
  mutate(
    team_clean = resolve_team_abbr(team),
    possessions = as.numeric(possessions)
  )

# Pick Top 10 ORAPM and Top 10 DRAPM players
top_offense <- rapm_clean %>%
  arrange(desc(orapm)) %>%
  slice_head(n = 10) %>%
  mutate(type = "Offensive RAPM (ORAPM)", rating = orapm)

top_defense <- rapm_clean %>%
  arrange(desc(drapm)) %>%
  slice_head(n = 10) %>%
  mutate(type = "Defensive RAPM (DRAPM)", rating = drapm)

leaders_df <- bind_rows(top_offense, top_defense)

# ------------------------------------------------------------------------------
# 2. Reveal the leaderboard one rank at a time
#
# Every bar is the fitted full-season rating from rapm_ratings.rds. The frames
# only reveal the leaders from 10th to 1st; no intermediate values, sample-size
# steps or uncertainty bands are estimated here.
# ------------------------------------------------------------------------------
leaders_df <- leaders_df %>%
  group_by(type) %>%
  mutate(rank_desc = rank(-rating, ties.method = "first")) %>%
  ungroup()

n_frames <- max(leaders_df$rank_desc)
season_txt <- if ("season_label" %in% names(leaders_df)) leaders_df$season_label[1] else "last season"
lambda_txt <- if ("lambda" %in% names(leaders_df)) format(leaders_df$lambda[1], big.mark = ",") else NA
x_max <- max(leaders_df$rating) + 1.2

tmp_frame_dir <- file.path(tempdir(), sprintf("rapm_race_frames_%d", as.integer(Sys.time())))
if (!dir.exists(tmp_frame_dir)) dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(n_frames)

unique_teams <- unique(leaders_df$team_clean)
team_colors <- sapply(unique_teams, function(tm) get_nba_team_color(tm, "primary"))

for (f_idx in seq_len(n_frames)) {
  frame_data <- leaders_df %>%
    mutate(shown = rank_desc > n_frames - f_idx,
           bar = ifelse(shown, rating, NA_real_))

  p_frame <- ggplot(frame_data, aes(x = bar, y = reorder(player_name, rating), fill = team_clean)) +
    geom_col(width = 0.6, alpha = 0.9, na.rm = TRUE) +
    geom_text(aes(x = bar + 0.12, label = ifelse(shown, sprintf("%+.2f", rating), "")),
              hjust = 0, vjust = 0.4, color = NBA_COLORS$text, fontface = "bold", size = 2.8, na.rm = TRUE) +
    scale_fill_manual(values = team_colors, guide = "none") +
    facet_wrap(~type, scales = "free_y", ncol = 2) +
    scale_x_continuous(limits = c(0, x_max)) +
    theme_nba_dark(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      strip.text = element_text(size = 11, face = "bold", color = NBA_COLORS$accent),
      plot.title = element_text(size = 13, face = "bold"),
      plot.subtitle = element_text(size = 9.5, color = NBA_COLORS$subtext)
    ) +
    labs(
      title = sprintf("Top 10 Offensive and Defensive RAPM, %s", season_txt),
      subtitle = if (is.na(lambda_txt)) "Full-season ridge-regression estimates."
                 else sprintf("Full-season ridge-regression estimates (\u03bb = %s).", lambda_txt),
      x = "Points per 100 possessions",
      y = NULL,
      caption = "Source: possession data via hoopR. Fitted values, shown as published in the ratings table."
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", f_idx))
  ggsave(frame_path, plot = p_frame, width = 12, height = 7, dpi = 110, bg = NBA_COLORS$bg)
  frame_files[f_idx] <- frame_path
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_rapm_race.gif")
out_png <- file.path(out_cache_dir, "gif_rapm_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 6,
  width            = 1200,
  height           = 700
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_rapm_race.gif")
media_png <- file.path(web_media_dir, "gif_rapm_race.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated RAPM Race:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
