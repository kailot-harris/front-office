# Ad-hoc visualization: stylized PNG of today's (Sys.Date()) NBA game predictions, built from the
# freshly regenerated CACHE_VALUE_BETS (latest_value_bets.rds — game_date / Matchup / Team /
# Model_Win_Prob / Line columns per market_odds_engine.R's output schema). Not part of
# run_full_pipeline.R's DAG - a one-off chart, same category as NFL's tools/plot_week6_projections.R.
setwd("c:/Users/kailo/kayceeslices/front-office/NBA Analytics")
source("config.R")
library(ggplot2)
library(dplyr)

TARGET_DATE <- as.Date("2026-10-20")

vb <- readRDS(file.path(CACHE_DIR, "latest_value_bets.rds"))
today_games <- vb |> filter(game_date == TARGET_DATE)

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

out_path <- file.path(CACHE_DIR, "nba_predictions_2026-10-20.png")
ggsave(out_path, p, width = 10, height = 7, dpi = 200, bg = bg)
cat("Saved:", out_path, "\n")
