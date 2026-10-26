# ==============================================================================
# Embedding Loader & Tidy Joining Helper (WNBA port)
# Path: load_embeddings.R
#
# Ported AS-IS from the NBA Analytics repo's load_embeddings.R — this is a trivial
# CSV loader with no team-count-specific logic beyond reading whatever
# team_embeddings.py wrote to CACHE_EMBEDDINGS (config.R), which already points at
# this project's team_embeddings.csv. No changes needed for the WNBA's 15-team
# roster vs. the NBA's 30.
#
# SCHEMA CHANGE (task P1, wnba_odds_embeddings_agent, 2026-09-12): once
# team_embeddings.py trains on the REAL cache/games_for_embeddings.csv built by
# build_games_for_embeddings.R (real home_team/away_team WNBA_TEAMS abbreviations,
# e.g. "ATL"/"LV", instead of the mock generator's bare integer team IDs 1..15),
# team_embeddings.csv's `team_id` column is now a real WNBA team abbreviation
# STRING, not an integer. The original `mutate(team_id = as.integer(team_id))`
# line silently produced all-NA team_id (`as.integer("ATL")` -> NA + a coercion
# warning) once that happened — caught by actually re-running this loader against
# the real-trained CSV, not assumed to still work. Fixed by keeping team_id as
# character; every downstream caller found (app.R's Team Embeddings tab) only
# uses team_id for a text label (`paste("Team", team_id)`), never a numeric join,
# so this is a safe, real fix and not a functional regression.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")

get_team_embeddings <- function() {
  if (!file.exists(CACHE_EMBEDDINGS)) {
    warning("Embeddings CSV does not exist yet. Run team_embeddings.py first.")
    return(NULL)
  }

  emb <- read_csv(CACHE_EMBEDDINGS, show_col_types = FALSE) |>
    mutate(team_id = as.character(team_id))
  return(emb)
}
