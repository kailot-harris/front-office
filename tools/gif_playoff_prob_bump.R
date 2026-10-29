# ==============================================================================
# tools/gif_playoff_prob_bump.R
# Path: tools/gif_playoff_prob_bump.R
#
# NBA Playoff Seed & Play-In Leverage Probability Bump Chart Animation
#
# Animates the daily/weekly evolution of playoff seed certainty and play-in
# bubble leverage probabilities across the Eastern and Western conferences.
# Incorporates clutch leverage metrics and projected team win trajectories to
# visualize which teams are securing top-6 playoff locks vs fighting through the
# 7-10 play-in leverage zone.
#
# Foundation & Theme:
#   - sources tools/viz_common.R
#   - uses theme_nba_dark() and official team primary colors
#   - renders dual artifacts: cache/gif_playoff_prob_bump.gif and
#     cache/gif_playoff_prob_bump.png (reduced-motion static final frame)
#     via render_animated_artifact()
#
# Data inputs:
#   - Reads cache/projected_30_team_standings.rds (baseline projected standings)
#   - Reads cache/clutch_leverage_metrics.rds (high-leverage clutch metrics)
#   - Reads cache/matchups_team_box_2027.rds (completed regular season games)
#   - Falls back gracefully to synthesized baseline if cache files are missing
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
# 1. Load Standings, Projections & Clutch Leverage Metrics
# ------------------------------------------------------------------------------
standings_file <- find_cache_file("projected_30_team_standings.rds")
clutch_file    <- find_cache_file("clutch_leverage_metrics.rds")
proj_teams_file <- find_cache_file("projections_season_teams.rds")
box_file       <- find_cache_file("matchups_team_box_2027.rds")

# Conference alignment lookup
CONFERENCE_MAP <- c(
  ATL = "East", BOS = "East", BKN = "East", CHA = "East", CHI = "East", CLE = "East",
  DET = "East", IND = "East", MIA = "East", MIL = "East", NYK = "East", ORL = "East",
  PHI = "East", TOR = "East", WAS = "East",
  DAL = "West", DEN = "West", GSW = "West", HOU = "West", LAC = "West", LAL = "West",
  MEM = "West", MIN = "West", NOP = "West", OKC = "West", PHX = "West", POR = "West",
  SAC = "West", SAS = "West", UTA = "West"
)

# Load team clutch leverage adjustment factor
team_clutch_boost <- setNames(rep(0.0, length(CONFERENCE_MAP)), names(CONFERENCE_MAP))
if (!is.null(clutch_file)) {
  clutch_data <- tryCatch(readRDS(clutch_file), error = function(e) NULL)
  if (!is.null(clutch_data) && is.list(clutch_data)) {
    c_df <- tryCatch({
      do.call(rbind, lapply(clutch_data, function(x) {
        data.frame(team = resolve_team_abbr(x$team), cDwpa = as.numeric(x$cDwpa), stringsAsFactors = FALSE)
      }))
    }, error = function(e) NULL)
    if (!is.null(c_df) && nrow(c_df) > 0) {
      agg_c <- aggregate(cDwpa ~ team, data = c_df, FUN = mean)
      for (r in seq_len(nrow(agg_c))) {
        tm <- agg_c$team[r]
        if (!is.na(tm) && tm %in% names(team_clutch_boost)) {
          # High clutch win probability added provides positive playoff leverage resilience
          team_clutch_boost[tm] <- (agg_c$cDwpa[r] - 1.0) * 0.05
        }
      }
    }
  }
}

# Baseline playoff probabilities
base_playoff_prob <- setNames(rep(0.50, length(CONFERENCE_MAP)), names(CONFERENCE_MAP))

if (!is.null(proj_teams_file)) {
  pt_data <- tryCatch(readRDS(proj_teams_file), error = function(e) NULL)
  if (!is.null(pt_data) && "team" %in% names(pt_data) && "ensemble_playoff_prob" %in% names(pt_data)) {
    for (i in seq_len(nrow(pt_data))) {
      tm <- resolve_team_abbr(pt_data$team[i])
      if (!is.na(tm) && tm %in% names(base_playoff_prob)) {
        base_playoff_prob[tm] <- as.numeric(pt_data$ensemble_playoff_prob[i])
      }
    }
  }
} else if (!is.null(standings_file)) {
  std_data <- tryCatch(as.data.frame(readRDS(standings_file)), error = function(e) NULL)
  if (!is.null(std_data) && "Team" %in% names(std_data)) {
    for (i in seq_len(nrow(std_data))) {
      tm <- resolve_team_abbr(std_data$Team[i])
      rnk <- as.numeric(std_data$Rank[i])
      if (!is.na(tm) && tm %in% names(base_playoff_prob)) {
        # Logistic curve mapping rank to playoff probability
        base_playoff_prob[tm] <- 1 / (1 + exp((rnk - 16) * 0.45))
      }
    }
  }
}

# Focus on marquee competitive bubble & leverage contenders across conferences (Top 14 contenders in play-in / seed race)
# Highlight teams navigating playoff seed leverage (locks, play-in race, bubble)
target_teams <- c("BOS", "NYK", "CLE", "MIA", "DET", "IND", "ORL", "OKC", "SAS", "GSW", "DEN", "HOU", "MIN", "LAL")
target_teams <- intersect(target_teams, names(CONFERENCE_MAP))

# ------------------------------------------------------------------------------
# 2. Build Daily / Weekly Leverage Progression Timeline
# ------------------------------------------------------------------------------
timeline <- list()

# Step 0: Preseason Baseline
prob_cur <- base_playoff_prob

timeline[[1]] <- tibble(
  step       = 0L,
  date_label = "Preseason",
  team       = target_teams,
  conf       = CONFERENCE_MAP[target_teams],
  prob       = pmax(0.01, pmin(0.99, as.numeric(prob_cur[target_teams])))
)

# Evolve probabilities over completed game dates if box scores are present
if (!is.null(box_file)) {
  box <- tryCatch(readRDS(box_file), error = function(e) NULL)
  if (!is.null(box) && "game_date" %in% names(box)) {
    box$team_clean <- resolve_team_abbr(box$team_abbreviation)
    box$opp_clean  <- resolve_team_abbr(box$opponent_team_abbreviation)
    dates <- sort(unique(as.character(box$game_date)))

    for (idx in seq_along(dates)) {
      d <- dates[idx]
      d_games <- box[as.character(box$game_date) == d, ]
      if (nrow(d_games) > 0) {
        for (g in seq_len(nrow(d_games))) {
          tm <- d_games$team_clean[g]
          won <- isTRUE(d_games$team_winner[g])
          margin <- as.numeric(d_games$team_score[g]) - as.numeric(d_games$opponent_team_score[g])

          if (!is.na(tm) && tm %in% names(prob_cur)) {
            # Leverage swing proportional to win/loss and clutch profile
            swing <- (if (won) 0.025 else -0.025) + (margin * 0.001) + team_clutch_boost[tm] * 0.01
            prob_cur[tm] <- pmax(0.005, pmin(0.995, prob_cur[tm] + swing))
          }
        }
      }

      timeline[[length(timeline) + 1L]] <- tibble(
        step       = as.integer(idx),
        date_label = format(as.Date(d), "%b %d"),
        team       = target_teams,
        conf       = CONFERENCE_MAP[target_teams],
        prob       = pmax(0.01, pmin(0.99, as.numeric(prob_cur[target_teams])))
      )
    }
  }
}

# If fewer than 4 steps were generated, synthesize multi-week progression
if (length(timeline) <= 3) {
  for (w in (length(timeline)):6) {
    for (tm in target_teams) {
      shift <- sin(which(target_teams == tm) + w) * 0.035 + team_clutch_boost[tm] * 0.02
      prob_cur[tm] <- pmax(0.02, pmin(0.99, prob_cur[tm] + shift))
    }
    timeline[[length(timeline) + 1L]] <- tibble(
      step       = as.integer(w),
      date_label = sprintf("Week %d", w),
      team       = target_teams,
      conf       = CONFERENCE_MAP[target_teams],
      prob       = pmax(0.01, pmin(0.99, as.numeric(prob_cur[target_teams])))
    )
  }
}

timeline_df <- bind_rows(timeline)
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
    annotate("text", x = -0.15, y = 0.93, label = "TOP-6 PLAYOFF LOCK ZONE (\u226585%)",
             color = "#10b981", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9) +
    annotate("text", x = -0.15, y = 0.52, label = "PLAY-IN LEVERAGE ZONE (35% - 85%)",
             color = "#f59e0b", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9) +
    annotate("text", x = -0.15, y = 0.18, label = "HIGH LOTTERY LEVERAGE RISK (<35%)",
             color = "#ef4444", hjust = 0, size = 2.7, fontface = "bold", alpha = 0.9)

  if (s > 0) {
    p_frame <- p_frame + geom_line(linewidth = 1.15, alpha = 0.85)
  }

  p_frame <- p_frame +
    geom_point(data = frame_pts, aes(x = step, y = prob, fill = team),
               shape = 21, size = 3.6, color = NBA_COLORS$text, stroke = 1.0) +
    geom_text(data = frame_pts,
              aes(x = step + 0.14, y = prob, label = sprintf("%s (%.0f%%)", team, prob * 100)),
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
      title = "NBA Playoff Seed & Play-In Leverage Probability Bump (2026-27)",
      subtitle = sprintf("Dynamic playoff probability bump through %s \u00b7 Clutch leverage index integrated", cur_label),
      x = "Timeline",
      y = "Playoff Probability",
      caption = "Antigravity NBA Quantitative Engine \u00b7 Season Standings & Clutch Leverage Simulator"
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
