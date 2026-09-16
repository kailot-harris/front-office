# ==============================================================================
# Lineup Synergy, Combinatorics & Staggering Metrics (WNBA)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/lineup_synergy.R
#
# Ported from NBA Analytics/lineup_synergy.R (T2 / wnba_rating_engine_agent). Per
# WNBA_REPLICATION_PLAN.md §(b)/(d), this ports as-is: none of its logic hardcodes NBA-specific
# minutes/roster constants that need recalibration (it operates purely on per-game minutes
# ranks/shares, which are scale-free across a 40-minute WNBA game vs a 48-minute NBA game -
# the top-5/HHI/overlap math doesn't need a game-length constant at all). Function signature
# verified against WNBA's actual player_metrics.R output (get_player_box_scores_chunked()
# returns the same column set: game_id, team_id, minutes, points, athlete_id - all present in
# T1's cache/player_box_scores_cache.rds, confirmed by inspection before writing this file).
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("player_metrics.R")

get_lineup_features <- function(seasons = ALL_SEASONS) {
  raw_box <- get_player_box_scores_chunked(seasons)

  cleaned <- raw_box |>
    mutate(
      minutes = suppressWarnings(as.numeric(minutes)),
      minutes = replace_na(minutes, 0),
      points  = suppressWarnings(as.numeric(points)),
      points  = replace_na(points, 0),
      athlete_id = as.integer(athlete_id),
      game_id = as.character(game_id),
      team_id = as.integer(team_id)
    )

  lineup_metrics <- cleaned |>
    group_by(game_id, team_id) |>
    arrange(desc(minutes)) |>
    summarise(
      top5_combined_pts = sum(head(points, 5), na.rm = TRUE),

      # Herfindahl-Hirschman Index of minute distribution
      minutes_hhi = {
        total_m <- sum(minutes)
        if (total_m > 0) sum((minutes / total_m)^2) else 0.20
      },

      # Star overlap: proportion of games where top-2 minute earners both played >= 30 mins.
      # NOTE: unchanged from the NBA original's 30-minute threshold. WNBA games are 40 minutes
      # (vs NBA's 48), so 30 minutes is proportionally a much heavier workload for a WNBA
      # player (75% of the game) than for an NBA player (62.5%) - this threshold is a
      # reasonable candidate for future WNBA-specific recalibration (e.g. ~25 min / 62.5% of
      # 40 to match the NBA proportion), but WNBA_REPLICATION_PLAN.md does not call this out as
      # a required Tier 3 change and it's out of scope to silently invent a new threshold here
      # without validating it against real WNBA minutes distributions first.
      star_overlap_pct = {
        m_vec <- head(minutes, 2)
        if (length(m_vec) >= 2 && min(m_vec) >= 30) 1.0 else 0.0
      },

      # Proxy for unit stability (continuity of minutes within the game)
      lineup_continuity_score = round(pmin(1.0, sum(head(minutes, 5)) / pmax(1, sum(minutes))), 3),
      .groups = "drop"
    )

  return(lineup_metrics)
}
