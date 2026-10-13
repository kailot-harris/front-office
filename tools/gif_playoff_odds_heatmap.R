# ==============================================================================
# Playoff Odds Heatmap (Teams x Weeks grid)
# Path: tools/gif_playoff_odds_heatmap.R
#
# Closes GitHub issue #32 (Phase 9 / docs/task_assignments_phase8.md task P9-I). Ad-hoc,
# on-demand visualization script - deliberately NOT wired into run_full_pipeline.R's DAG (same
# category as tools/gif_point_diff_race.R / tools/gif_playoff_prob_bump.R). Reads
# CACHE_PLAYOFF_ODDS_HISTORY only (read-only); writes nothing back to that cache or any other
# cache file.
#
# STATIC vs ANIMATED DECISION (issue #32 explicitly leaves this to judgment, documented here):
# this script renders a STATIC PNG, not a GIF. CACHE_PLAYOFF_ODDS_HISTORY only has 5 distinct
# weeks (Weeks 1-5) - the entire teams x weeks grid is a 32x5 tile matrix that fits legibly in
# one static image with every data point visible at once, which is exactly what a heatmap is
# for (seeing the whole grid simultaneously). Animating a progressive reveal here would only
# hide columns the viewer could otherwise already see, with no "race" or trajectory element
# (unlike the bump chart in #31, which specifically benefits from watching lines move) - so a
# single static image is visually sufficient and, per the issue's own text, preferred. Output:
# cache/gif_playoff_odds_heatmap.png (keeping the "gif_" filename prefix per the brief's exact
# scope filename, despite the static output format).
#
# NOTE ON WORKTREE ISOLATION: same as tools/gif_playoff_prob_bump.R's own header note - this
# agent's work is isolated to the git worktree at WORKTREE_DIR below, unlike config.R's own
# hardcoded PROJECT_DIR (config.R:22-23), which points at the main repo checkout and is NOT
# overridden by this script's own setwd() below. CACHE_PLAYOFF_ODDS_HISTORY therefore still
# correctly resolves to the main repo's cache (shared, read-only, real-data input), while this
# script's own output is written under WORKTREE_CACHE_DIR instead, so it lands inside this
# worktree's own cache/ rather than silently writing into the main repo's cache/.
#
# Run with:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "<this worktree>\tools\gif_playoff_odds_heatmap.R"
# ==============================================================================

WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-a1a1fa60ff5872781"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

source("config.R")

# ---- Shared dark theme (copied verbatim from docs/week5_elo_analysis.qmd) ----
bg_dark     <- "#1e2228"
panel_dark  <- "#262b33"
grid_dark   <- "#3a4049"
text_light  <- "#d8dee5"

theme_elo_dark <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.background  = element_rect(fill = bg_dark, color = NA),
      panel.background = element_rect(fill = panel_dark, color = NA),
      legend.background = element_rect(fill = bg_dark, color = NA),
      legend.key        = element_rect(fill = panel_dark, color = NA),
      strip.background  = element_rect(fill = panel_dark, color = NA),
      panel.grid.major  = element_line(color = grid_dark),
      panel.grid.minor  = element_blank(),
      text              = element_text(color = text_light),
      axis.text         = element_text(color = text_light),
      strip.text        = element_text(color = text_light, face = "bold"),
      plot.title        = element_text(color = text_light)
    )
}

# ---- Data: verify schema contract before any plotting ----
po_hist <- readRDS(CACHE_PLAYOFF_ODDS_HISTORY)
expected_names <- c("week", "team", "division_win_prob", "playoff_prob", "bye_prob")
if (!identical(names(po_hist), expected_names)) {
  stop(sprintf("CACHE_PLAYOFF_ODDS_HISTORY schema mismatch. Expected: %s. Got: %s",
               paste(expected_names, collapse = ", "), paste(names(po_hist), collapse = ", ")))
}

po_hist <- po_hist |> filter(team %in% names(NFL_TEAMS))

max_week <- max(po_hist$week)

# Rows sorted by CURRENT (max week) playoff_prob, descending (highest odds at top after flip).
team_order <- po_hist |>
  filter(week == max_week) |>
  arrange(desc(playoff_prob)) |>
  pull(team)

po_hist <- po_hist |> mutate(team = factor(team, levels = rev(team_order)))

p_heatmap <- ggplot(po_hist, aes(x = factor(week), y = team, fill = playoff_prob)) +
  geom_tile(color = grid_dark, linewidth = 0.3) +
  scale_fill_gradient(low = "#1b2a3d", high = "#ffce54", limits = c(0, 1),
                       labels = scales::percent_format(accuracy = 1), name = "Playoff\nprobability") +
  theme_elo_dark() +
  theme(axis.title.y = element_blank(), panel.grid = element_blank()) +
  labs(x = "Week", y = NULL,
       title = sprintf("Playoff odds by team and week (through Week %d, %d)", max_week, CURRENT_SEASON),
       subtitle = "Rows sorted by current (latest-week) playoff probability")

png_path <- file.path(WORKTREE_CACHE_DIR, "gif_playoff_odds_heatmap.png")
ggsave(png_path, p_heatmap, width = 8, height = 11, dpi = 120, bg = bg_dark)

cat(sprintf("Wrote %s (static heatmap, %d teams x %d weeks)\n", png_path, length(unique(po_hist$team)), length(unique(po_hist$week))))

# ---- Sanity check: row order matches a direct descending sort on the latest-week data ----
direct_order <- po_hist |> filter(week == max_week) |> arrange(desc(playoff_prob)) |> pull(team) |> as.character()
cat("\nRow-order sanity check - heatmap top-5 (should match direct descending sort of Week ", max_week, " playoff_prob):\n", sep = "")
print(head(team_order, 5))
cat("Direct sort top-5:\n")
print(head(direct_order, 5))
cat(sprintf("Match: %s\n", isTRUE(all(head(team_order, 5) == head(direct_order, 5)))))
