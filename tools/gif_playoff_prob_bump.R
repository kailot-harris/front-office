# ==============================================================================
# tools/gif_playoff_prob_bump.R
# Path: tools/gif_playoff_prob_bump.R
#
# Playoff probability over time
#
# Animates each team's model playoff probability across the projection updates
# published so far this season, for the teams whose probability moved most.
#
# Data (real, no fallback):
#   - git history of web/public/data/projections_season_teams.json
#     (ensemble_playoff_prob as published on each update)
#   With fewer than 3 published snapshots the chart is not rendered.
#
# Usage:
#   Rscript tools/gif_playoff_prob_bump.R
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

# ------------------------------------------------------------------------------
# 1. Load the published playoff-probability history
#
# Every point on this chart is a number the site actually published: the
# ensemble playoff probability in web/public/data/projections_season_teams.json
# as committed on each projection update. The history is read from git, so
# nothing is interpolated or adjusted between updates. A shallow clone has no
# history and the chart is not rendered there.
# ------------------------------------------------------------------------------
SCRIPT_NAME <- "tools/gif_playoff_prob_bump.R"
PROJ_JSON <- "web/public/data/projections_season_teams.json"
MIN_SNAPSHOTS <- 3
N_TEAMS <- 14

q_arg <- function(x) shQuote(x, type = if (.Platform$OS.type == "windows") "cmd" else "sh")
git_lines <- function(args) {
  out <- tryCatch(
    suppressWarnings(system2("git", c("-C", q_arg(SCRIPT_DIR), args), stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0)
  )
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) character(0) else out
}

CONFERENCE_MAP <- c(
  ATL = "East", BOS = "East", BKN = "East", CHA = "East", CHI = "East", CLE = "East",
  DET = "East", IND = "East", MIA = "East", MIL = "East", NYK = "East", ORL = "East",
  PHI = "East", TOR = "East", WAS = "East",
  DAL = "West", DEN = "West", GSW = "West", HOU = "West", LAC = "West", LAL = "West",
  MEM = "West", MIN = "West", NOP = "West", OKC = "West", PHX = "West", POR = "West",
  SAC = "West", SAS = "West", UTA = "West"
)

log_lines <- git_lines(c("log", q_arg("--format=%H %ad"), "--date=short", "--", q_arg(PROJ_JSON)))
commits <- data.frame(
  sha = sub(" .*$", "", log_lines),
  date = as.Date(sub("^[^ ]+ ", "", log_lines)),
  stringsAsFactors = FALSE
)
# git log is newest first, so this keeps the last update published on each date.
commits <- commits[!duplicated(commits$date), , drop = FALSE]
commits <- commits[order(commits$date), , drop = FALSE]

snapshots <- lapply(seq_len(nrow(commits)), function(k) {
  raw <- git_lines(c("show", q_arg(sprintf("%s:%s", commits$sha[k], PROJ_JSON))))
  rows <- tryCatch(jsonlite::fromJSON(paste(raw, collapse = "\n")), error = function(e) NULL)
  if (!is.data.frame(rows) || !all(c("team", "ensemble_playoff_prob") %in% names(rows))) return(NULL)
  out <- data.frame(
    date = commits$date[k],
    team = resolve_team_abbr(rows$team),
    prob = as.numeric(rows$ensemble_playoff_prob),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$team) & out$team %in% names(CONFERENCE_MAP) & !is.na(out$prob), , drop = FALSE]
  if (nrow(out) < 30) NULL else out
})
history_df <- bind_rows(snapshots)

if (nrow(history_df) == 0 || length(unique(history_df$date)) < MIN_SNAPSHOTS) {
  viz_stop_no_data(
    SCRIPT_NAME,
    sprintf("fewer than %d published snapshots of %s were found in git history.", MIN_SNAPSHOTS, PROJ_JSON)
  )
}

# ------------------------------------------------------------------------------
# 2. Pick the teams to draw: the ones whose published probability moved most.
#    Chosen from the data on every run, not from a fixed list.
# ------------------------------------------------------------------------------
movement <- history_df %>%
  group_by(team) %>%
  summarise(range = max(prob) - min(prob), .groups = "drop") %>%
  arrange(desc(range), team)
target_teams <- head(movement$team, N_TEAMS)

snap_dates <- sort(unique(history_df$date))
timeline_df <- history_df %>%
  filter(team %in% target_teams) %>%
  mutate(
    step = match(date, snap_dates) - 1L,
    date_label = format(date, "%b %d"),
    conf = CONFERENCE_MAP[team]
  ) %>%
  select(step, date_label, team, conf, prob) %>%
  arrange(step, team)

all_steps <- sort(unique(timeline_df$step))
max_step  <- max(all_steps)

step_labels_map <- timeline_df %>%
  distinct(step, date_label) %>%
  arrange(step)
step_labels <- setNames(step_labels_map$date_label, step_labels_map$step)

team_colors <- setNames(
  vapply(target_teams, function(tm) get_nba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  target_teams
)

# ------------------------------------------------------------------------------
# 3. Render Animation Frames
# ------------------------------------------------------------------------------
tmp_frame_dir <- file.path(tempdir(), sprintf("nba_playoff_bump_frames_%d", Sys.getpid()))
if (dir.exists(tmp_frame_dir)) unlink(tmp_frame_dir, recursive = TRUE)
dir.create(tmp_frame_dir, recursive = TRUE)

frame_files <- character(0)

TEAM_LOGOS <- viz_logo_map(script = SCRIPT_NAME)

for (s in all_steps) {
  frame_lines <- timeline_df %>% filter(step <= s)
  frame_pts   <- timeline_df %>% filter(step == s)
  cur_label   <- step_labels[[as.character(s)]]

  p_frame <- ggplot(frame_lines, aes(x = step, y = prob, group = team, color = team)) +
    # Shaded threshold zones: Direct Playoff Lock (>85%), Play-in Bubble (35-85%), Lottery Risk (<35%)
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.85, ymax = 1.00,
             fill = "#10b981", alpha = 0.07) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.35, ymax = 0.85,
             fill = "#f59e0b", alpha = 0.06) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.00, ymax = 0.35,
             fill = "#ef4444", alpha = 0.07) +
    # Zone boundary reference lines
    geom_hline(yintercept = 0.85, linetype = "dashed", color = "#10b981", linewidth = 0.5, alpha = 0.7) +
    geom_hline(yintercept = 0.50, linetype = "dotted", color = NBA_COLORS$grid, linewidth = 0.6) +
    geom_hline(yintercept = 0.35, linetype = "dashed", color = "#ef4444", linewidth = 0.5, alpha = 0.7) +
    # Zone text labels
    annotate("text", x = -0.15, y = 0.93, label = "LIKELY IN (85% OR HIGHER)",
             color = "#10b981", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9) +
    annotate("text", x = -0.15, y = 0.52, label = "IN THE RACE (35% TO 85%)",
             color = "#f59e0b", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9) +
    annotate("text", x = -0.15, y = 0.18, label = "LONG SHOT (UNDER 35%)",
             color = "#ef4444", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9)

  if (s > 0) {
    p_frame <- p_frame + geom_line(linewidth = 1.15, alpha = 0.85)
  }

  p_frame <- p_frame +
    geom_point(data = frame_pts, aes(x = step, y = prob, fill = team),
               shape = 21, size = 3.6, color = NBA_COLORS$text, stroke = 1.0) +
    ggimage::geom_image(data = frame_pts, aes(x = step + 0.36, y = prob, image = TEAM_LOGOS[team]),
                        size = 0.034, by = "height", inherit.aes = FALSE) +
    geom_text(data = frame_pts,
              aes(x = step + 0.72, y = prob, label = sprintf("%.0f%%", prob * 100)),
              hjust = 0, vjust = 0.4, fontface = "bold", size = 2.8, color = NBA_COLORS$text) +
    scale_y_continuous(
      limits = c(0.00, 1.03),
      breaks = seq(0.0, 1.0, by = 0.2),
      labels = scales::percent_format(accuracy = 1)
    ) +
    scale_x_continuous(
      breaks = all_steps,
      labels = step_labels,
      limits = c(-0.3, max_step + 1.25)
    ) +
    scale_color_manual(values = team_colors, guide = "none") +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_nba_dark() +
    labs(
      title = "Playoff Probability Over Time (2026-27)",
      subtitle = sprintf("Model playoff probability at each published projection update, through %s. The %d teams whose odds moved most.", cur_label, length(target_teams)),
      x = "Projection update",
      y = "Playoff Probability",
      caption = "Source: ensemble season projections exactly as published on each date."
    )

  frame_path <- file.path(tmp_frame_dir, sprintf("frame_%03d.png", s))
  ggsave(frame_path, plot = p_frame, width = 10.5, height = 6.8, dpi = 120, bg = NBA_COLORS$bg)
  frame_files <- c(frame_files, frame_path)
}

# ------------------------------------------------------------------------------
# 4. Encode Animated Artifact (GIF + PNG)
# ------------------------------------------------------------------------------
out_gif <- file.path(out_cache_dir, "gif_playoff_prob_bump.gif")
out_png <- file.path(out_cache_dir, "gif_playoff_prob_bump.png")

render_animated_artifact(
  frame_paths      = frame_files,
  gif_path         = out_gif,
  png_path         = out_png,
  fps              = 1.5,
  hold_last_frames = 6,
  width            = 1050,
  height           = 680
)

unlink(tmp_frame_dir, recursive = TRUE)

cat(sprintf("[SUCCESS] Generated Playoff Probability Bump Chart:\n  GIF: %s (%d bytes)\n  PNG: %s (%d bytes)\n",
            out_gif, file.info(out_gif)$size, out_png, file.info(out_png)$size))
