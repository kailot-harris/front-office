# Ad-hoc & pipeline visualization: stylized graphic of today's (Sys.Date()) NBA game predictions,
# built from prediction_accuracy_log.rds (or latest_value_bets.rds if available).
# Generates both date-stamped and canonical today PNG and GIF artifacts.
PROJECT_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "config.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "config.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    "c:/Users/kailo/kayceeslices/front-office/NBA Analytics"
  }
})
setwd(PROJECT_ROOT)
source("config.R")
library(ggplot2)
library(dplyr)
library(magick)

# Determine target date: CLI arg --date=YYYY-MM-DD, or Sys.Date()
TARGET_DATE <- Sys.Date()
for (arg in commandArgs(trailingOnly = TRUE)) {
  if (grepl("^--date=", arg)) {
    TARGET_DATE <- as.Date(sub("^--date=", "", arg))
  }
}

# Source data: prefer prediction_accuracy_log.rds, fallback to latest_value_bets.rds
pred_log_file <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
val_bets_file <- file.path(CACHE_DIR, "latest_value_bets.rds")

if (file.exists(pred_log_file)) {
  pred_log <- readRDS(pred_log_file)
  today_games <- pred_log |> filter(as.Date(game_date) == TARGET_DATE)
  if (nrow(today_games) == 0 && !is.null(TARGET_DATE)) {
    # If no games on TARGET_DATE, find closest date with games
    all_dates <- sort(unique(as.Date(pred_log$game_date)))
    future_dates <- all_dates[all_dates >= TARGET_DATE]
    fallback_date <- if (length(future_dates) > 0) future_dates[1] else tail(all_dates, 1)
    message(sprintf("No games on %s; falling back to %s", TARGET_DATE, fallback_date))
    TARGET_DATE <- fallback_date
    today_games <- pred_log |> filter(as.Date(game_date) == TARGET_DATE)
  }
  
  df <- today_games |>
    mutate(
      home_win_prob = predicted_home_win_prob,
      home_prob_pct = home_win_prob * 100,
      matchup = paste0(away_team, " @ ", home_team),
      picked_winner_prob = ifelse(predicted_winner == home_team, home_win_prob, 1 - home_win_prob),
      pick_label = sprintf("Model pick: %s (%.1f%% win prob) \u00b7 %s", predicted_winner, picked_winner_prob * 100, status)
    ) |>
    arrange(home_win_prob) |>
    mutate(matchup = factor(matchup, levels = matchup))
} else if (file.exists(val_bets_file)) {
  vb <- readRDS(val_bets_file)
  today_games <- vb |> filter(as.Date(game_date) == TARGET_DATE)
  df <- today_games |>
    mutate(
      away_team = trimws(sub(".*vs\\.\\s*", "", Matchup)),
      home_team = trimws(sub("\\s*vs\\..*", "", Matchup)),
      picked_home = Team == home_team,
      home_win_prob = ifelse(picked_home, Model_Win_Prob, 1 - Model_Win_Prob),
      home_prob_pct = home_win_prob * 100,
      matchup = paste0(away_team, " @ ", home_team),
      pick_label = sprintf("Model pick: %s (%.1f%% win prob) \u00b7 %s", Team, Model_Win_Prob * 100, Status)
    ) |>
    arrange(home_win_prob) |>
    mutate(matchup = factor(matchup, levels = matchup))
} else {
  stop("Neither prediction_accuracy_log.rds nor latest_value_bets.rds found.")
}

if (nrow(df) == 0) {
  stop(sprintf("No games found for date %s", TARGET_DATE))
}

bg        <- "#0b1120"
panel_bg  <- "#111a2e"
grid_col  <- "#22304a"
away_col  <- "#ff6b57"
home_col  <- "#3fd0c9"
text_col  <- "#e7ecf5"
subtext_col <- "#9fb0c9"

p <- ggplot(df, aes(y = matchup)) +
  geom_vline(xintercept = 50, linetype = "dashed", color = grid_col, linewidth = 0.6) +
  geom_segment(aes(x = 50, xend = home_prob_pct, yend = matchup),
               color = ifelse(df$home_prob_pct >= 50, home_col, away_col),
               linewidth = 3.2, lineend = "round") +
  geom_point(aes(x = home_prob_pct),
             color = ifelse(df$home_prob_pct >= 50, home_col, away_col),
             size = 5.5) +
  geom_text(aes(x = home_prob_pct,
                label = sprintf("%.0f%%", home_prob_pct),
                hjust = ifelse(df$home_prob_pct >= 50, -0.55, 1.55)),
            color = text_col, size = 3.4, fontface = "bold") +
  geom_text(aes(x = 4, y = matchup, label = pick_label),
            hjust = 0, vjust = 3.2, color = subtext_col, size = 2.9, fontface = "italic") +
  scale_x_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
                     labels = c("0%", "25%", "50%", "75%", "100%"),
                     expand = c(0, 0)) +
  scale_y_discrete(expand = expansion(add = 0.9)) +
  labs(
    title    = paste0("NBA \u2014 Model Projections for ", format(TARGET_DATE, "%b %d, %Y")),
    subtitle = paste0("Home win probability (dot) \u00b7 Season ", CURRENT_SEASON,
                       " \u00b7 Generated ", format(Sys.Date(), "%b %d, %Y")),
    x = "Home team win probability",
    y = NULL,
    caption = "Dot right of the dashed 50% line = home favored \u00b7 left = away favored \u00b7 kayceeslices/NBA Analytics"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background   = element_rect(fill = bg, color = NA),
    panel.background  = element_rect(fill = panel_bg, color = NA),
    panel.grid.major.x = element_line(color = grid_col, linewidth = 0.3),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    axis.text          = element_text(color = text_col),
    axis.title.x       = element_text(color = subtext_col, margin = margin(t = 10)),
    axis.text.y        = element_text(color = text_col, face = "bold", size = 11),
    plot.title         = element_text(color = text_col, face = "bold", size = 20, margin = margin(b = 4)),
    plot.subtitle      = element_text(color = subtext_col, size = 11, margin = margin(b = 14)),
    plot.caption       = element_text(color = subtext_col, size = 8, margin = margin(t = 12)),
    plot.margin        = margin(20, 30, 16, 16)
  )

date_str <- format(TARGET_DATE, "%Y-%m-%d")
filename_png <- sprintf("nba_predictions_%s.png", date_str)
filename_gif <- sprintf("nba_predictions_%s.gif", date_str)

out_path_png <- file.path(CACHE_DIR, filename_png)
out_path_gif <- file.path(CACHE_DIR, filename_gif)

# 1. Save Date-stamped PNG
ggsave(out_path_png, p, width = 10, height = max(6, 1.2 + 0.7 * nrow(df)), dpi = 200, bg = bg)
cat("Saved PNG:", out_path_png, "\n")

# 2. Save Date-stamped GIF via magick
img <- magick::image_read(out_path_png)
magick::image_write(img, out_path_gif, format = "gif")
cat("Saved GIF:", out_path_gif, "\n")

# 3. Also write canonical "nba_predictions_today" PNG and GIF to cache
today_png <- file.path(CACHE_DIR, "nba_predictions_today.png")
today_gif <- file.path(CACHE_DIR, "nba_predictions_today.gif")
file.copy(out_path_png, today_png, overwrite = TRUE)
file.copy(out_path_gif, today_gif, overwrite = TRUE)

# 4. Sync all to web/public/media/
web_media_dir <- file.path(PROJECT_ROOT, "web", "public", "media")
if (!dir.exists(web_media_dir)) dir.create(web_media_dir, recursive = TRUE)

file.copy(out_path_png, file.path(web_media_dir, filename_png), overwrite = TRUE)
file.copy(out_path_gif, file.path(web_media_dir, filename_gif), overwrite = TRUE)
file.copy(today_png, file.path(web_media_dir, "nba_predictions_today.png"), overwrite = TRUE)
file.copy(today_gif, file.path(web_media_dir, "nba_predictions_today.gif"), overwrite = TRUE)

cat("Synced all prediction graphics to:", web_media_dir, "\n")
