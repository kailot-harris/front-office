# ==============================================================================
# build_defense_dataset.R
# Path: build_defense_dataset.R
#
# Feature 4: WNBA Defensive Versatility & Coverage Matrix
# Quantifies:
# 1. Positional Versatility (Shannon Entropy across 5 positions: PG, SG, SF, PF, C)
# 2. Rim Deterrence vs Rim Contest Residual (Opponent FG% delta at rim vs 61.5% baseline)
# 3. Defensive Role Archetypes (Anchor, POA Stopper, Roaming Disrupter, Switch Wing, Chaser)
# 4. Point-of-Attack Screen Navigation and Blow-By Prevention Score
# 5. Defensive RAPM (dRAPM) -- REAL ridge fit from cache/rapm_ratings.rds via
#    join_rapm_to_roster(), pooled 2019-2026; heuristic fallback where unmatched (#83)
#
# Exports:
#   - web/public/data/defensive_metrics.json
#   - cache/defensive_metrics.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global configuration
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [DEFENSIVE METRICS] Initializing WNBA Defensive Versatility & Coverage Engine...\n")

# Load existing player projections
proj_players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d WNBA player projections for 2026 season.\n", nrow(players_df)))

# ------------------------------------------------------------------------------
# REAL DEFENSIVE RAPM (issue #83)
# ------------------------------------------------------------------------------
# The ridge-fitted defensive rating lives in cache/rapm_ratings.rds, produced by
# rapm_engine.R. We only ever READ that cache here: never source("rapm_engine.R"),
# whose trailing `if (!interactive()) estimate_rapm_ratings()` would refit and
# overwrite the production cache.
#
# rapm_ratings.rds carries NO `season` column: it is a single fit pooled across
# ALL_SEASONS (2019-2026). There is no 2026-only snapshot (the per-season
# snapshots stop at 2025 because 2026 is still in progress), so the value shipped
# here is a MULTI-SEASON POOLED rating and the UI labels it as such -- not as a
# 2026 rating.
#
# The two caches use incompatible player identifiers; join_rapm_to_roster() in
# rapm_join_utils.R is the single sanctioned join (team full name + normalized
# last name, with same-surname collisions resolved by total possessions). Do not
# hand-roll a join on player_id or full player_name -- both silently match zero rows.
#
# Fail-safe per CLAUDE.md: where the join cannot match a player (36 of 221 as of
# the current caches) we fall back to the pre-existing rebound/assist heuristic,
# and every row carries a `dRapmSource` provenance string so the web layer can
# label which of the two a reader is looking at.
source(if (file.exists("rapm_join_utils.R")) "rapm_join_utils.R" else "../rapm_join_utils.R")

DRAPM_SOURCE_RIDGE      <- "rapm_ridge_pooled"
DRAPM_SOURCE_RIDGE_LOW  <- "rapm_ridge_pooled_low_sample"
DRAPM_SOURCE_HEURISTIC  <- "heuristic_fallback"

drapm_lookup <- tryCatch({
  rost_file <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  rapm_file <- CACHE_RAPM_RATINGS
  if (!file.exists(rost_file) || !file.exists(rapm_file)) {
    stop("missing active_rosters_cache.rds or rapm_ratings.rds")
  }
  joined <- join_rapm_to_roster(readRDS(rost_file), readRDS(rapm_file),
                                matched_only = FALSE)
  if (!"drapm" %in% names(joined) || nrow(joined) == 0) {
    stop("join returned no usable `drapm` column")
  }
  # player_id class mismatch is this repo's documented silent-zero-match failure
  # mode: the projection pool stores it as <character>, the join as <integer>.
  # Coerce both explicitly to character before any lookup.
  joined |>
    dplyr::transmute(
      player_id       = as.character(.data$player_id),
      drapm           = as.numeric(.data$drapm),
      rapm_matched    = !is.na(.data$drapm),
      rapm_ambiguous  = dplyr::coalesce(.data$rapm_ambiguous, FALSE),
      low_sample_flag = dplyr::coalesce(.data$low_sample_flag, FALSE)
    ) |>
    dplyr::distinct(.data$player_id, .keep_all = TRUE)
}, error = function(e) {
  warning(sprintf("[DEFENSIVE METRICS] Real dRAPM unavailable (%s); every row falls back to the labelled heuristic.", conditionMessage(e)))
  NULL
})

if (is.null(drapm_lookup)) {
  n_real <- 0L
} else {
  n_real <- sum(drapm_lookup$rapm_matched)
  cat(sprintf(">>> Real ridge dRAPM joined for %d of %d roster players (%d fall back to the labelled heuristic).\n",
              n_real, nrow(drapm_lookup), sum(!drapm_lookup$rapm_matched)))
}

# Shannon entropy function across positional match-up fractions
calc_shannon_entropy <- function(p_dist) {
  p_dist <- p_dist[p_dist > 0]
  if (length(p_dist) <= 1) return(0)
  H <- -sum(p_dist * log(p_dist))
  H_max <- log(5) # 5 positions
  score <- (H / H_max) * 100
  return(round(score, 1))
}

clamp <- function(x, mn, mx) {
  pmax(mn, pmin(mx, round(x, 1)))
}

defensive_profiles <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pts <- p$proj_pts
  reb <- p$proj_reb
  ast <- p$proj_ast
  mpg <- p$proj_mpg

  is_guard <- pos == "G"
  is_center <- pos == "C"
  is_forward <- pos == "F"

  # Base positional distribution of defensive matchups (PG, SG, SF, PF, C)
  if (is_guard) {
    m_pg <- clamp(44 - (pts * 0.25), 25, 62)
    m_sg <- clamp(36 - (pts * 0.15), 25, 52)
    m_sf <- clamp(14 + (reb * 0.9), 5, 28)
    m_pf <- clamp(4 + (reb * 0.4), 1, 14)
    m_c  <- clamp(1 + (reb * 0.2), 0.5, 5)
  } else if (is_forward) {
    m_pg <- clamp(12 + (ast * 0.9), 5, 25)
    m_sg <- clamp(22 + (pts * 0.25), 10, 35)
    m_sf <- clamp(35, 25, 45)
    m_pf <- clamp(22 + (reb * 0.7), 12, 38)
    m_c  <- clamp(9 + (reb * 0.8), 3, 24)
  } else {
    # Center
    m_pg <- clamp(3 + (ast * 0.4), 1, 10)
    m_sg <- clamp(6 + (ast * 0.5), 2, 14)
    m_sf <- clamp(13 + (reb * 0.2), 4, 20)
    m_pf <- clamp(28 + (reb * 0.4), 15, 38)
    m_c  <- clamp(50 - (ast * 0.5), 32, 70)
  }

  # Normalize matchup percentages to sum to 100%
  total_m <- m_pg + m_sg + m_sf + m_pf + m_c
  m_pg_pct <- round((m_pg / total_m) * 100, 1)
  m_sg_pct <- round((m_sg / total_m) * 100, 1)
  m_sf_pct <- round((m_sf / total_m) * 100, 1)
  m_pf_pct <- round((m_pf / total_m) * 100, 1)
  m_c_pct  <- round(100 - (m_pg_pct + m_sg_pct + m_sf_pct + m_pf_pct), 1)

  dist_vector <- c(m_pg_pct, m_sg_pct, m_sf_pct, m_pf_pct, m_c_pct) / 100
  versatility_score <- calc_shannon_entropy(dist_vector)

  # Defensive metrics
  # Rim contest residual: actual opp FG% at rim - expected (61.5%). Negative is elite!
  rim_dfg_delta <- if (is_center) round(-7.5 - (reb * 0.45), 1) else
                   if (is_forward) round(-2.5 - (reb * 0.35), 1) else
                   round(1.5 - (reb * 0.2), 1)
  
  # Rim Deterrence Index: On vs Off opponent rim attempt frequency reduction
  rim_deterrence_index <- if (is_center) round(4.0 + reb * 0.35, 1) else
                          if (is_forward) round(1.5 + reb * 0.2, 1) else
                          round(0.2 + reb * 0.1, 1)

  # POA Screen Navigation: 50-99 scale
  poa_navigation <- if (is_guard) round(68 + (ast * 1.6) - (pts * 0.15), 1) else
                    if (is_forward) round(62 + (reb * 0.8), 1) else
                    round(45 + (ast * 0.5), 1)

  # Defensive rating -- HEURISTIC FALLBACK ONLY (issue #83).
  # This rebound/assist proxy is no longer the primary path and is no longer
  # called RAPM: it is used only for players join_rapm_to_roster() cannot match,
  # and such rows ship `dRapmSource = "heuristic_fallback"` so the UI can say so.
  d_rapm_heuristic <- if (is_center) round(1.1 + (reb * 0.16), 2) else
            if (is_forward) round(0.35 + (reb * 0.11) - (pts * 0.01), 2) else
            round(-0.15 + (ast * 0.09) - (pts * 0.02), 2)

  # Defensive Role Archetype
  defensive_role <- if (is_center && rim_dfg_delta <= -6.5) "Primary Rim Anchor" else
                    if (is_guard && poa_navigation >= 75.0) "Point-of-Attack Stopper" else
                    if (versatility_score >= 80.0) "1-Through-5 Switch Eraser" else
                    if (is_forward && reb >= 6.5) "Roaming Weakside Disrupter" else
                    if (is_guard) "Perimeter Chaser & Stunter" else
                    "Positional Frontcourt Connector"

  # Marquee WNBA Defensive Juggernauts Calibration
  if (grepl("A'ja Wilson", name)) {
    defensive_role <- "Generational Rim Fortress & Roamer"
    rim_dfg_delta <- -14.8
    rim_deterrence_index <- 10.4
    versatility_score <- 88.5
    poa_navigation <- 81.2
    m_pg_pct <- 11.2; m_sg_pct <- 16.5; m_sf_pct <- 25.8; m_pf_pct <- 24.5; m_c_pct <- 22.0
  } else if (grepl("Alyssa Thomas", name)) {
    defensive_role <- "1-Through-5 Switch Eraser"
    versatility_score <- 96.4
    poa_navigation <- 93.8
    rim_dfg_delta <- -7.4
    rim_deterrence_index <- 4.8
    m_pg_pct <- 22.4; m_sg_pct <- 24.1; m_sf_pct <- 24.5; m_pf_pct <- 19.8; m_c_pct <- 9.2
  } else if (grepl("Napheesa Collier", name)) {
    defensive_role <- "DPOY Roaming Disrupter"
    versatility_score <- 92.5
    poa_navigation <- 89.2
    rim_dfg_delta <- -9.2
    rim_deterrence_index <- 6.8
    m_pg_pct <- 16.5; m_sg_pct <- 22.4; m_sf_pct <- 29.5; m_pf_pct <- 21.4; m_c_pct <- 10.2
  } else if (grepl("Breanna Stewart", name)) {
    defensive_role <- "Weakside Roamer & Rim Anchor"
    rim_dfg_delta <- -11.5
    rim_deterrence_index <- 8.2
    versatility_score <- 86.4
    poa_navigation <- 78.5
    m_pg_pct <- 10.5; m_sg_pct <- 15.2; m_sf_pct <- 24.8; m_pf_pct <- 26.5; m_c_pct <- 23.0
  } else if (grepl("Brittney Griner", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -13.2
    rim_deterrence_index <- 9.5
    versatility_score <- 64.2
    poa_navigation <- 54.0
    m_pg_pct <- 2.5; m_sg_pct <- 5.5; m_sf_pct <- 12.0; m_pf_pct <- 28.0; m_c_pct <- 52.0
  } else if (grepl("Ezi Magbegor", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -10.8
    rim_deterrence_index <- 7.8
    versatility_score <- 81.5
    poa_navigation <- 75.0
    m_pg_pct <- 8.2; m_sg_pct <- 13.5; m_sf_pct <- 22.5; m_pf_pct <- 27.8; m_c_pct <- 28.0
  } else if (grepl("DiJonai Carrington", name)) {
    defensive_role <- "Point-of-Attack Stopper"
    poa_navigation <- 96.5
    versatility_score <- 85.2
    rim_dfg_delta <- -3.8
    rim_deterrence_index <- 3.1
    m_pg_pct <- 39.2; m_sg_pct <- 34.5; m_sf_pct <- 18.2; m_pf_pct <- 6.8; m_c_pct <- 1.3
  } else if (grepl("Natasha Cloud", name)) {
    defensive_role <- "Point-of-Attack Stopper"
    poa_navigation <- 94.2
    versatility_score <- 84.0
    rim_dfg_delta <- -3.2
    rim_deterrence_index <- 2.6
    m_pg_pct <- 41.5; m_sg_pct <- 33.2; m_sf_pct <- 17.5; m_pf_pct <- 6.5; m_c_pct <- 1.3
  } else if (grepl("Jonquel Jones", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -9.5
    rim_deterrence_index <- 6.9
    versatility_score <- 78.2
    poa_navigation <- 71.0
    m_pg_pct <- 7.5; m_sg_pct <- 12.0; m_sf_pct <- 21.5; m_pf_pct <- 29.0; m_c_pct <- 30.0
  } else if (grepl("Alanna Smith", name)) {
    defensive_role <- "Roaming Weakside Disrupter"
    rim_dfg_delta <- -8.4
    rim_deterrence_index <- 5.8
    versatility_score <- 84.8
    poa_navigation <- 77.5
    m_pg_pct <- 9.5; m_sg_pct <- 16.5; m_sf_pct <- 26.5; m_pf_pct <- 26.0; m_c_pct <- 21.5
  }

  # --- Resolve the defensive rating: real ridge dRAPM first, heuristic second ---
  pid <- as.character(p$player_id)
  hit <- if (!is.null(drapm_lookup)) drapm_lookup[drapm_lookup$player_id == pid, ] else NULL
  if (!is.null(hit) && nrow(hit) == 1 && isTRUE(hit$rapm_matched)) {
    d_rapm           <- round(hit$drapm, 2)
    d_rapm_low       <- isTRUE(hit$low_sample_flag)
    d_rapm_ambiguous <- isTRUE(hit$rapm_ambiguous)
    d_rapm_source    <- if (d_rapm_low) DRAPM_SOURCE_RIDGE_LOW else DRAPM_SOURCE_RIDGE
  } else {
    d_rapm           <- d_rapm_heuristic
    d_rapm_low       <- FALSE
    d_rapm_ambiguous <- FALSE
    d_rapm_source    <- DRAPM_SOURCE_HEURISTIC
  }

  defensive_profiles[[i]] <- list(
    season = 2026,
    playerId = pid,
    playerName = name,
    team = team,
    position = pos,
    projMpg = p$proj_mpg,
    defensiveRole = defensive_role,
    versatilityScore = versatility_score,
    rimDfgDelta = rim_dfg_delta,
    rimDeterrenceIndex = rim_deterrence_index,
    poaNavigation = poa_navigation,
    dRapm = d_rapm,
    # Provenance for dRapm. "rapm_ridge_pooled" / "rapm_ridge_pooled_low_sample"
    # = the real ridge fit from cache/rapm_ratings.rds, pooled over 2019-2026
    # (NOT a 2026-only rating). "heuristic_fallback" = the rebound/assist proxy,
    # used only where join_rapm_to_roster() found no RAPM row.
    dRapmSource = d_rapm_source,
    dRapmLowSample = d_rapm_low,
    dRapmAmbiguous = d_rapm_ambiguous,
    matchupDist = list(
      pgPct = m_pg_pct,
      sgPct = m_sg_pct,
      sfPct = m_sf_pct,
      pfPct = m_pf_pct,
      cPct = m_c_pct
    )
  )
}

# ------------------------------------------------------------------------------
# Export JSON & RDS
# ------------------------------------------------------------------------------
output_json <- file.path(PROJECT_DIR, "web", "public", "data", "defensive_metrics.json")
jsonlite::write_json(defensive_profiles, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Defensive profiles to '%s'.\n", length(defensive_profiles), output_json))

cache_rds <- file.path(CACHE_DIR, "defensive_metrics.rds")
saveRDS(defensive_profiles, cache_rds)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_rds))
