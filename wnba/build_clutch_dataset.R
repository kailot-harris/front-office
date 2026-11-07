# ==============================================================================
# build_clutch_dataset.R
# Path: build_clutch_dataset.R
#
# Feature 6: WNBA True Clutch & Leverage Performance
# Analyzes real high-leverage late-game performance (Score margin <= 5 pts, <= 5:00 4Q/OT):
# 1. Clutch FGA (Field Goal Attempts in clutch window)
# 2. Clutch Points (Points scored in clutch window)
# 3. Clutch FG% (Real field goal percentage in clutch window)
# 4. Clutch PPP (Points per shot attempt in clutch window)
# 5. Clutch Scoring Plays (Total scoring plays in clutch window)
# 6. Provenance & Sample Qualification (REAL_CURRENT_SEASON, REAL_HISTORICAL_FALLBACK, INSUFFICIENT_SAMPLE)
#
# All metrics are derived strictly from real play-by-play tracking
# in cache/player_pbp_features.rds. Synthetic heuristic formulas
# and manual star player overrides have been eliminated (Issue #132).
#
# Ingests:
#   - web/public/data/projections_season_players.json
#   - cache/player_pbp_features.rds (real PBP clutch stats)
# Exports:
#   - web/public/data/clutch_leverage_metrics.json
#   - cache/clutch_leverage_metrics.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global configuration
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [CLUTCH ENGINE] Initializing WNBA True Clutch & Leverage Engine...\n")

# Load existing player projections
proj_players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d WNBA player projections for 2026 season.\n", nrow(players_df)))

# Load real PBP features if available
pbp_feat_path <- file.path(CACHE_DIR, "player_pbp_features.rds")
has_pbp_feat <- file.exists(pbp_feat_path)
pbp_features_df <- if (has_pbp_feat) readRDS(pbp_feat_path) else NULL

if (has_pbp_feat) {
  cat(sprintf(">>> Ingested real play-by-play clutch features for %d players.\n", nrow(pbp_features_df)))
} else {
  warning(">>> [CLUTCH ENGINE] player_pbp_features.rds missing; all players will emit INSUFFICIENT_SAMPLE provenance.")
}

MIN_CLUTCH_FGA <- 5L

clutch_profiles <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  p_id <- as.character(p$player_id)
  pos <- p$position
  team <- p$team

  # Match with real PBP clutch features
  real_pbp <- NULL
  if (!is.null(pbp_features_df) && p_id %in% as.character(pbp_features_df$player_id)) {
    real_pbp <- pbp_features_df %>% filter(as.character(player_id) == p_id) %>% slice(1)
  }

  has_sufficient_sample <- !is.null(real_pbp) &&
                           nrow(real_pbp) > 0 &&
                           !is.na(real_pbp$clutch_fga) &&
                           real_pbp$clutch_fga >= MIN_CLUTCH_FGA

  if (has_sufficient_sample) {
    c_fga   <- as.integer(real_pbp$clutch_fga)
    c_pts   <- as.integer(round(real_pbp$clutch_points))
    c_sc_pl <- as.integer(real_pbp$clutch_scoring_plays)
    c_fg_pct <- round(as.numeric(real_pbp$clutch_fg_pct) * 100, 1)
    c_ppp   <- round(c_pts / c_fga, 2)
    c_prov  <- as.character(real_pbp$data_source)

    c_archetype <- if (c_fg_pct >= 55.0 && c_pts >= 30) {
      "Elite High-Volume Closer"
    } else if (c_fg_pct >= 50.0 && c_fga >= 20) {
      "High-Leverage Shot Maker"
    } else if (c_fg_pct >= 50.0) {
      "Efficient Late-Game Finisher"
    } else if (c_fga >= 20) {
      "Heavy-Volume Pressure Shooter"
    } else {
      "Situational Clutch Contributor"
    }
  } else {
    c_fga   <- if (!is.null(real_pbp) && nrow(real_pbp) > 0 && !is.na(real_pbp$clutch_fga)) as.integer(real_pbp$clutch_fga) else 0L
    c_pts   <- if (!is.null(real_pbp) && nrow(real_pbp) > 0 && !is.na(real_pbp$clutch_points) && c_fga > 0) as.integer(round(real_pbp$clutch_points)) else NA_integer_
    c_sc_pl <- if (!is.null(real_pbp) && nrow(real_pbp) > 0 && !is.na(real_pbp$clutch_scoring_plays) && c_fga > 0) as.integer(real_pbp$clutch_scoring_plays) else NA_integer_
    c_fg_pct <- NA_real_
    c_ppp   <- NA_real_
    c_prov  <- "INSUFFICIENT_SAMPLE"
    c_archetype <- "Insufficient Clutch Sample"
  }

  clutch_profiles[[i]] <- list(
    season = 2026L,
    playerId = p_id,
    playerName = name,
    team = team,
    position = pos,
    clutchArchetype = c_archetype,
    clutchFga = c_fga,
    clutchPoints = c_pts,
    clutchFgPct = c_fg_pct,
    clutchScoringPlays = c_sc_pl,
    clutchPpp = c_ppp,
    provenance = c_prov
  )
}

# ------------------------------------------------------------------------------
# Export JSON & RDS
# ------------------------------------------------------------------------------
output_json <- file.path(PROJECT_DIR, "web", "public", "data", "clutch_leverage_metrics.json")
jsonlite::write_json(clutch_profiles, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf(">>> [SUCCESS] Wrote %d Clutch profiles to '%s'.\n", length(clutch_profiles), output_json))

cache_rds <- file.path(CACHE_DIR, "clutch_leverage_metrics.rds")
saveRDS(clutch_profiles, cache_rds)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_rds))
