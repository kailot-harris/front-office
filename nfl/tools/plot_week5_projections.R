# Ad-hoc visualization: stylized PNG of week 5 (CURRENT_SEASON) game projections, built from the
# freshly regenerated CACHE_PROJECTED_MATCHUPS (home_win_prob / projected_margin columns per
# config.R's documented schema). Not part of run_full_pipeline.R's DAG - a one-off chart, same
# category as tools/weekly_accuracy_report.R.
setwd("c:/Users/kailo/kayceeslices/front-office/nfl analytics")
source("config.R")
library(ggplot2)
library(dplyr)

pm <- readRDS(CACHE_PROJECTED_MATCHUPS)
WEEK <- 5
w5 <- pm |> filter(week == WEEK, season == CURRENT_SEASON)

df <- w5 |>
  mutate(
    favored_team = ifelse(home_win_prob >= 0.5, home_team, away_team),
    favored_prob = ifelse(home_win_prob >= 0.5, home_win_prob, 1 - home_win_prob),
    matchup = paste0(away_team, " @ ", home_team),
    margin_label = sprintf("%s by %.1f", favored_team, abs(projected_margin)),
    home_prob_pct = home_win_prob * 100
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
  geom_text(aes(x = 4, label = margin_label),
            hjust = 0, color = subtext_col, size = 2.9, fontface = "italic") +
  scale_x_continuous(limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
                     labels = c("0%", "25%", "50%", "75%", "100%"),
                     expand = c(0, 0)) +
  labs(
    title    = paste0("NFL Week ", WEEK, " \u2014 Model Projections"),
    subtitle = paste0("Home win probability (dot) \u00b7 Season ", CURRENT_SEASON,
                       " \u00b7 Generated ", format(Sys.Date(), "%b %d, %Y")),
    x = "Home team win probability",
    y = NULL,
    caption = "Dot right of the dashed 50% line = home favored \u00b7 left = away favored \u00b7 kayceeslices/NFL Analytics"
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

out_path <- "cache/week5_projections.png"
ggsave(out_path, p, width = 10, height = 7.2, dpi = 200, bg = bg)
cat("Saved:", out_path, "\n")
