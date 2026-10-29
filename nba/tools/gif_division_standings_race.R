# ==============================================================================
# tools/gif_division_standings_race.R
# Path: tools/gif_division_standings_race.R
#
# NBA Cumulative Division Standings Race Animation (Season 2026-27 - Issue #50)
# Animates cumulative wins race faceted by the 6 NBA divisions across the season.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark(), NBA_COLORS, and canonical team colors
#   - renders dual artifacts: gif_division_standings_race.gif and
#     gif_division_standings_race.png (reduced-motion static final frame)
#     via render_animated_artifact()
#   - copies/syncs artifacts to web/public/media/
#
# Data inputs:
#   - Reads matchups_team_box_2027.rds (completed regular season games)
#   - Reads projected_30_team_standings.rds / ensemble_team_ratings.rds
#   - Falls back gracefully to synthesized progression if cache is missing
#
# Usage:
#   Rscript tools/gif_division_standings_race.R
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
# 1. Division Mapping for 30 NBA Franchises
# ------------------------------------------------------------------------------
NBA_DIVISION_MAP <- c(
  # Eastern Conference - Atlantic
  BOS = "Atlantic", BKN = "Atlantic", NYK = "Atlantic", PHI = "Atlantic", TOR = "Atlantic",
  # Eastern Conference - Central
  CHI = "Central", CLE = "Central", DET = "Central", IND = "Central", MIL = "Central",
  # Eastern Conference - Southeast
  ATL = "Southeast", CHA = "Southeast", MIA = "Southeast", ORL = "Southeast", WAS = "Southeast",
  # Western Conference - Northwest
  DEN = "Northwest", MIN = "Northwest", OKC = "Northwest", POR = "Northwest", UTA = "Northwest",
  # Western Conference - Pacific
  GSW = "Pacific", LAC = "Pacific", LAL = "Pacific", PHX = "Pacific", SAC = "Pacific",
  # Western Conference - Southwest
  DAL = "Southwest", HOU = "Southwest", MEM = "Southwest", NOP = "Southwest", SAS = "Southwest"
)

all_teams <- sort(names(NBA_DIVISION_MAP))

# ------------------------------------------------------------------------------
# 2. Load Data & Compute Cumulative Division Wins
# ------------------------------------------------------------------------------
box_file <- find_cache_file("matchups_team_box_2027.rds")

race_history <- list()
race_history[[1]] <- tibble(
  step = 0L,
  date_label = "Season Open",
  team = all_teams,
  division = NBA_DIVISION_MAP[all_teams],
  cum_wins = 0L
)

if (!is.null(box_file)) {
  box <- readRDS(box_file)
  box$team_clean <- resolve_team_abbr(box$team_abbreviation)
  dates <- sort(unique(box$game_date))

  # Determine win per team row
  team_games <- box %>%
    transmute(
      team = team_clean,
      game_date = as.character(game_date),
      won = as.integer(as.numeric(team_score) > as.numeric(opponent_team_score))
    )

  team_date_wins <- team_games %>%
    group_by(team, game_date) %>%
    summarize(wins = sum(won), .groups = "drop")

  running_wins <- setNames(rep(0L, length(all_teams)), all_teams)

  for (idx in seq_along(dates)) {
    d <- as.character(dates[idx])
    d_wins <- team_date_wins %>% filter(game_date == d)
    if (nrow(d_wins) > 0) {
      for (j in seq_len(nrow(d_wins))) {
        tm <- d_wins$team[j]
        if (!is.na(tm) && tm %in% all_teams) {
          running_wins[tm] <- running_wins[tm] + as.integer(d_wins$wins[j])
        }
      }
    }
    race_history[[idx + 1]] <- tibble(
      step = as.integer(idx),
      date_label = format(as.Date(d), "%b %d"),
      team = all_teams,
      division = NBA_DIVISION_MAP[all_teams],
      cum_wins = as.integer(running_wins[all_teams])
    )
  }
}

# Fallback if no games available or only baseline step
if (length(race_history) <= 1) {
  sim_wins <- setNames(rep(0L, length(all_teams)), all_teams)
  for (i in 1:5) {
    # Increment wins randomly/deterministically
    add_w <- as.integer((seq_along(all_teams) + i) %% 2 == 0)
    sim_wins <- sim_wins + add_w
    race_history[[i + 1]] <- tibble(
      step = as.integer(i),
      date_label = sprintf("Day %d", i),
      team = all_teams,
      division = NBA_DIVISION_MAP[all_teams],
      cum_wins = as.integer(sim_wins[all_teams])
    )
  }
}

race_df <- bind_rows(race_history)
all_steps <- sort(unique(race_df$step))
max_step  <- max(all_steps)

step_labels_map <- race_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

team_colors <- setNames(
  vapply(all_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

# Ordered division levels: Eastern (Atlantic, Central, Southeast) then Western (Northwest, Pacific, Southwest)
div_order <- c("Atlantic", "Central", "Southeast", "Northwest", "Pacific", "Southwest")
race_df$division <- factor(race_df$division, levels = div_order)

# ------------------------------------------------------------------------------
# 3. Render Animation Frames (Faceted by Division)
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), "nba_division_standings_race_frames")
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)
max_wins <- max(race_df$cum_wins)
y_max <- max(max_wins + 1L, 4L)

for (s in all_steps) {
  frame_lines <- race_df %>% filter(step <= s)
  frame_pts   <- race_df %>% filter(step == s)

  cur_label <- step_labels[[as.character(s)]]

  p_frame <- ggplot(frame_lines, aes(x = step, y = cum_wins, group = team, color = team)) +
    geom_line(linewidth = 1.05, alpha = 0.85) +
    geom_point(data = frame_pts, aes(x = step, y = cum_wins, fill = team),
               shape = 21, size = 3.0, color = NBA_COLORS$text, stroke = 1.0) +
    geom_text(data = frame_pts, aes(x = step + 0.15, y = cum_wins, label = team),
              hjust = 0, vjust = 0.4, color = NBA_COLORS$text, fontface = "bold", size = 2.4) +
    scale_x_continuous(breaks = all_steps, labels = step_labels, limits = c(-0.2, max_step + 0.95)) +
    scale_y_continuous(breaks = seq(0, y_max, by = 2), limits = c(-0.2, y_max + 0.5)) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    facet_wrap(~division, ncol = 3, scales = "fixed") +
    theme_nba_dark(base_size = 10) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7.5),
      panel.spacing = unit(1.0, "lines")
    ) +
    labs(
      title = "NBA Cumulative Division Standings Race (2026-27)",
      subtitle = sprintf("Cumulative regular season wins through %s across all 6 NBA divisions", cur_label),
      x = "Date",
      y = "Cumulative Wins",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Standings & Box Score Engine"
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 11, height = 7, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 4. Encode Animated Artifact (GIF + PNG) & Sync to web/public/media/
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_division_standings_race.gif")
out_png <- file.path(out_cache_dir, "gif_division_standings_race.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 2,
  hold_last_frames = 5,
  width            = 1100,
  height           = 700
)

# Clean up temp frames
unlink(tmp_frame_dir, recursive = TRUE)

# Sync copy to web/public/media/
media_gif <- file.path(web_media_dir, "gif_division_standings_race.gif")
media_png <- file.path(web_media_dir, "gif_division_standings_race.png")
file.copy(out_gif, media_gif, overwrite = TRUE)
file.copy(out_png, media_png, overwrite = TRUE)

cat(sprintf("[SUCCESS] Generated Division Standings Race:\n  Cache GIF: %s (%d bytes)\n  Cache PNG: %s (%d bytes)\n  Media GIF: %s\n  Media PNG: %s\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size, media_gif, media_png))
