# ==============================================================================
# tools/gif_turnover_margin_race.R
# Path: tools/gif_turnover_margin_race.R
#
# NBA Turnover & Four Factors Differential Margin Race Animation (Issue #55)
# Animates cumulative turnover differential bar race across all 30 NBA teams:
#   - Turnover Margin: Opponent Turnovers Forced minus Own Turnovers Committed
#   - Positive turnover margin represents ball-hawking / ball-security advantages
#   - Facets/ranks teams dynamically as season progresses
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and canonical team colors
#   - renders dual artifacts: gif_turnover_margin_race.gif and
#     gif_turnover_margin_race.png (reduced-motion static final frame)
#     via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_turnover_margin_race.R
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
# 1. Load Data & Compute Cumulative Turnover Differential Trajectory
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")

race_history <- list()
race_history[[1]] <- tibble(
  step = 0L,
  date_label = "Season Open",
  team = all_teams,
  cum_margin = 0L,
  rank = seq_along(all_teams)
)

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  dates <- sort(unique(box$game_date))

  # Build symmetric game pairings to extract opponent turnovers
  home_df <- box[box$team_home_away == "home", c("game_id", "game_date", "team_clean", "turnovers")]
  away_df <- box[box$team_home_away == "away", c("game_id", "game_date", "team_clean", "turnovers")]

  # Home team row: team = home, opp_tov = away tov
  m_home <- merge(home_df, away_df, by = c("game_id", "game_date"), suffixes = c("_team", "_opp"))
  # Away team row: team = away, opp_tov = home tov
  m_away <- merge(away_df, home_df, by = c("game_id", "game_date"), suffixes = c("_team", "_opp"))

  all_games <- rbind(m_home, m_away)
  all_games$margin <- as.integer(as.numeric(all_games$turnovers_opp) - as.numeric(all_games$turnovers_team))

  running_margin <- setNames(rep(0L, length(all_teams)), all_teams)

  for (idx in seq_along(dates)) {
    d <- dates[idx]
    d_games <- all_games[all_games$game_date == d, ]
    if (nrow(d_games) > 0) {
      for (g in seq_len(nrow(d_games))) {
        tm <- d_games$team_clean_team[g]
        if (!is.na(tm) && tm %in% all_teams) {
          running_margin[tm] <- running_margin[tm] + d_games$margin[g]
        }
      }
    }

    step_df <- tibble(
      step = as.integer(idx),
      date_label = format(as.Date(d), "%b %d"),
      team = all_teams,
      cum_margin = as.integer(running_margin[all_teams])
    ) %>%
      arrange(cum_margin, team) %>%
      mutate(rank = row_number())

    race_history[[idx + 1]] <- step_df
  }
}

if (length(race_history) <= 1) {
  sim_margin <- setNames(rep(0L, length(all_teams)), all_teams)
  for (i in 1:5) {
    delta_sim <- as.integer(sin(seq_along(all_teams) + i) * 3)
    sim_margin <- sim_margin + delta_sim
    race_history[[i + 1]] <- tibble(
      step = as.integer(i),
      date_label = sprintf("Day %d", i),
      team = all_teams,
      cum_margin = as.integer(sim_margin[all_teams])
    ) %>%
      arrange(cum_margin, team) %>%
      mutate(rank = row_number())
  }
}

race_df <- bind_rows(race_history)
active_steps <- sort(unique(race_df$step))

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# ------------------------------------------------------------------------------
# 2. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_turnover_margin_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)

x_min <- min(race_df$cum_margin) - 3
x_max <- max(race_df$cum_margin) + 5
if (x_min > -10) x_min <- -10
if (x_max < 10) x_max <- 10

for (s in active_steps) {
  frame_data <- race_df %>%
    filter(step == s) %>%
    arrange(cum_margin) %>%
    mutate(
      bar_order = row_number(),
      label_str = sprintf("%+d", cum_margin)
    )

  cur_label <- frame_data$date_label[1]

  p_frame <- ggplot(frame_data, aes(x = cum_margin, y = reorder(team, bar_order), fill = team)) +
    geom_vline(xintercept = 0, color = NBA_COLORS$grid, linewidth = 0.8, linetype = "dashed") +
    geom_col(width = 0.75, alpha = 0.9, color = NBA_COLORS$border) +
    geom_text(
      aes(
        x = ifelse(cum_margin >= 0, cum_margin + 0.4, cum_margin - 0.4),
        label = label_str,
        hjust = ifelse(cum_margin >= 0, 0, 1)
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
      title = "NBA Turnover Differential & Ball Security Margin Race",
      subtitle = sprintf("Cumulative Turnover Margin (Forced Opponent TOVs minus Committed TOVs) through %s", cur_label),
      x = "Cumulative Turnover Margin (+/-)",
      y = "NBA Franchise",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Positive indicates more opponent turnovers forced than given"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10, height = 7.5, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 3. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_turnover_margin_race.gif")
out_png <- file.path(out_cache_dir, "gif_turnover_margin_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1000,
  height           = 750
)

unlink(tmp_frame_dir, recursive = TRUE)

media_gif <- file.path(web_media_dir, "gif_turnover_margin_race.gif")
media_png <- file.path(web_media_dir, "gif_turnover_margin_race.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Turnover Margin Race:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
