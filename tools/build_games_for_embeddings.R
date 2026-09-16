# ==============================================================================
# build_games_for_embeddings.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/build_games_for_embeddings.R
#
# Task P1b (wnba_odds_embeddings_agent, GAP_REMEDIATION_PLAN.md / agent7.md).
# Derives a REAL cache/games_for_embeddings.csv (home_team, away_team, home_win)
# from T1's real box_scores_cache.rds (3,906 team-game rows, 2019-2026 real WNBA
# games), replacing team_embeddings.py's mock-data fallback path.
#
# Schema inspected first via str()/names() (not guessed) — see task_assignments.md
# T1 Handoff Notes and this agent's own inspection:
#   - box_scores_cache.rds is ONE ROW PER TEAM-GAME (3,906 rows = 1,953 games x 2
#     teams), keyed by `game_id`.
#   - `team_home_away` ("home"/"away") is the home/away indicator field.
#   - `team_winner` (logical) is TRUE for the winning team's row.
#   - Verified empirically: every one of the 1,953 distinct game_ids has EXACTLY
#     ONE row with team_home_away == "home" — a clean 1:1 game_id -> home-row
#     mapping, no need to pair two separate team rows manually; the home row's
#     own `opponent_team_abbreviation` already IS the away team for that game.
#
# Output: cache/games_for_embeddings.csv, one row per real game:
#   home_team  = team_abbreviation of the home-row (e.g. "LV")
#   away_team  = opponent_team_abbreviation of the home-row (e.g. "SEA")
#   home_win   = 1 if the home team won (team_winner == TRUE on the home row), else 0
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)
source("config.R")

box_path <- CACHE_TEAM_BOX
if (!file.exists(box_path)) stop("box_scores_cache.rds not found at ", box_path, " — run daily_ingest.R first.")

box <- readRDS(box_path)

cat(sprintf("[BUILD] Loaded box_scores_cache.rds: %d team-game rows.\n", nrow(box)))

home_rows <- box |> filter(team_home_away == "home")

n_games_total <- length(unique(box$game_id))
n_home_rows   <- nrow(home_rows)

if (n_home_rows != n_games_total) {
  warning(sprintf(
    "[BUILD] Expected exactly 1 home row per game_id (%d games) but found %d home rows — some games may be missing a home row or duplicated. Proceeding with what's available.",
    n_games_total, n_home_rows
  ))
}

games_df <- home_rows |>
  transmute(
    home_team = team_abbreviation,
    away_team = opponent_team_abbreviation,
    home_win  = as.integer(team_winner)
  ) |>
  filter(!is.na(home_team), !is.na(away_team), !is.na(home_win))

cat(sprintf("[BUILD] Built %d real game rows (home_team/away_team/home_win) from %d real seasons of box_scores_cache.rds.\n",
            nrow(games_df), length(unique(box$season))))
cat("[BUILD] home_win distribution:\n")
print(table(games_df$home_win))

out_path <- file.path(CACHE_DIR, "games_for_embeddings.csv")
write_csv(games_df, out_path)
cat(sprintf("[BUILD] Wrote real training CSV to: %s (%d rows)\n", out_path, nrow(games_df)))
