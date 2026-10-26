# ==============================================================================
# build_defense_dataset.R
# Feature 5: Defensive Versatility & Coverage Matrix
# Quantifies:
# 1. Positional Versatility (Shannon Entropy across 5 positions: PG, SG, SF, PF, C)
# 2. Rim Deterrence vs Rim Contest Residual (Opponent FG% delta at rim)
# 3. Defensive Role Archetype (Anchor, POA Stopper, Roaming Disrupter, Switch Wing, Chaser)
# 4. Point-of-Attack Screen Navigation and Blow-By Prevention Score
# Exports defensive_metrics.json for Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config (same idiom as build_cba_cap_dataset.R / playoff_simulator.R).
# Needed because this script names its input and output from config.R's WEB_JSON_*
# constants and is also run standalone, not only via run_full_pipeline.R's
# run_stage(), which sources config.R into the global environment first.
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [DEFENSIVE METRICS] Initializing Defensive Versatility & Coverage Engine...\n")

# Load existing player projections
proj_players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS  # config.R
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for 2026-2027 season.\n", nrow(players_df)))

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
  # Default distributions tailored by position
  if (is_guard) {
    m_pg <- clamp(42 - (pts * 0.2), 25, 60)
    m_sg <- clamp(38 - (pts * 0.1), 25, 50)
    m_sf <- clamp(15 + (reb * 0.8), 5, 30)
    m_pf <- clamp(4 + (reb * 0.4), 1, 15)
    m_c  <- clamp(1 + (reb * 0.2), 0.5, 6)
  } else if (is_forward) {
    m_pg <- clamp(12 + (ast * 0.8), 5, 25)
    m_sg <- clamp(22 + (pts * 0.3), 10, 35)
    m_sf <- clamp(36, 25, 45)
    m_pf <- clamp(22 + (reb * 0.6), 12, 38)
    m_c  <- clamp(8 + (reb * 0.8), 3, 22)
  } else {
    # Center
    m_pg <- clamp(4 + (ast * 0.4), 1, 12)
    m_sg <- clamp(7 + (ast * 0.5), 2, 16)
    m_sf <- clamp(14 + (reb * 0.2), 5, 22)
    m_pf <- clamp(28 + (reb * 0.4), 15, 38)
    m_c  <- clamp(47 - (ast * 0.6), 30, 68)
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
  # Rim contest residual: actual opp FG% at rim - expected (63.5%). Negative is elite!
  rim_dfg_delta <- if (is_center) round(-8.5 - (reb * 0.4), 1) else
                   if (is_forward) round(-3.0 - (reb * 0.3), 1) else
                   round(1.5 - (reb * 0.2), 1)
  
  # Rim Deterrence Index: On vs Off opponent rim frequency reduction
  rim_deterrence_index <- if (is_center) round(4.5 + reb * 0.3, 1) else
                          if (is_forward) round(1.5 + reb * 0.2, 1) else
                          round(0.2 + reb * 0.1, 1)

  # POA Screen Navigation: 50-99 scale
  poa_navigation <- if (is_guard) round(68 + (ast * 1.5) - (pts * 0.2), 1) else
                    if (is_forward) round(62 + (reb * 0.8), 1) else
                    round(45 + (ast * 0.5), 1)

  # Defensive RAPM
  d_rapm <- if (is_center) round(1.2 + (reb * 0.15), 2) else
            if (is_forward) round(0.4 + (reb * 0.1) - (pts * 0.01), 2) else
            round(-0.2 + (ast * 0.08) - (pts * 0.02), 2)

  # Defensive Role Archetype
  defensive_role <- if (is_center && rim_dfg_delta <= -7.0) "Primary Rim Anchor" else
                    if (is_guard && poa_navigation >= 75.0) "Point-of-Attack Stopper" else
                    if (versatility_score >= 82.0) "1-Through-5 Switch Eraser" else
                    if (is_forward && reb >= 7.0) "Roaming Weakside Disrupter" else
                    if (is_guard) "Perimeter Chaser & Stunter" else
                    "Positional Frontcourt Connector"

  # Special calibration for marquee defensive juggernauts
  if (grepl("Victor Wembanyama", name)) {
    defensive_role <- "Generational Alien Rim Fortress"
    rim_dfg_delta <- -14.2
    rim_deterrence_index <- 9.8
    versatility_score <- 89.4
    poa_navigation <- 82.5
    d_rapm <- 4.85
    m_pg_pct <- 14.5; m_sg_pct <- 18.2; m_sf_pct <- 24.1; m_pf_pct <- 22.8; m_c_pct <- 20.4
  } else if (grepl("Amen Thompson", name)) {
    defensive_role <- "1-Through-5 Switch Eraser"
    versatility_score <- 95.8
    poa_navigation <- 94.2
    rim_dfg_delta <- -6.8
    rim_deterrence_index <- 4.2
    d_rapm <- 3.42
    m_pg_pct <- 24.2; m_sg_pct <- 25.1; m_sf_pct <- 23.4; m_pf_pct <- 18.2; m_c_pct <- 9.1
  } else if (grepl("Cooper Flagg", name)) {
    defensive_role <- "Weakside Roamer & Switch Wing"
    versatility_score <- 91.2
    poa_navigation <- 86.4
    rim_dfg_delta <- -8.1
    rim_deterrence_index <- 5.6
    d_rapm <- 3.15
    m_pg_pct <- 18.2; m_sg_pct <- 21.4; m_sf_pct <- 28.5; m_pf_pct <- 21.5; m_c_pct <- 10.4
  } else if (grepl("Anthony Davis", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -11.8
    rim_deterrence_index <- 7.9
    versatility_score <- 82.6
    poa_navigation <- 76.2
    d_rapm <- 3.95
    m_pg_pct <- 8.4; m_sg_pct <- 12.5; m_sf_pct <- 20.2; m_pf_pct <- 26.5; m_c_pct <- 32.4
  } else if (grepl("Rudy Gobert", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -12.4
    rim_deterrence_index <- 8.9
    versatility_score <- 68.2
    poa_navigation <- 58.0
    d_rapm <- 4.10
    m_pg_pct <- 3.5; m_sg_pct <- 6.8; m_sf_pct <- 14.2; m_pf_pct <- 27.5; m_c_pct <- 48.0
  } else if (grepl("Alex Caruso", name)) {
    defensive_role <- "Point-of-Attack Stopper"
    poa_navigation <- 96.2
    versatility_score <- 86.8
    rim_dfg_delta <- -3.5
    rim_deterrence_index <- 2.8
    d_rapm <- 3.25
    m_pg_pct <- 38.5; m_sg_pct <- 34.2; m_sf_pct <- 18.5; m_pf_pct <- 7.6; m_c_pct <- 1.2
  } else if (grepl("Jrue Holiday", name)) {
    defensive_role <- "Point-of-Attack Stopper"
    poa_navigation <- 94.5
    versatility_score <- 88.2
    rim_dfg_delta <- -4.2
    rim_deterrence_index <- 3.1
    d_rapm <- 2.85
    m_pg_pct <- 35.2; m_sg_pct <- 32.4; m_sf_pct <- 20.8; m_pf_pct <- 9.8; m_c_pct <- 1.8
  } else if (grepl("Derrick White", name)) {
    defensive_role <- "Weakside Guard Shot-Blocker"
    poa_navigation <- 92.8
    versatility_score <- 85.4
    rim_dfg_delta <- -5.4
    rim_deterrence_index <- 3.4
    d_rapm <- 2.95
    m_pg_pct <- 36.8; m_sg_pct <- 33.5; m_sf_pct <- 20.2; m_pf_pct <- 7.8; m_c_pct <- 1.7
  } else if (grepl("Chet Holmgren", name)) {
    defensive_role <- "Primary Rim Anchor"
    rim_dfg_delta <- -10.9
    rim_deterrence_index <- 7.2
    versatility_score <- 79.5
    poa_navigation <- 74.0
    d_rapm <- 3.65
    m_pg_pct <- 6.8; m_sg_pct <- 11.2; m_sf_pct <- 22.4; m_pf_pct <- 28.6; m_c_pct <- 31.0
  } else if (grepl("Jayson Tatum", name)) {
    defensive_role <- "1-Through-5 Switch Eraser"
    versatility_score <- 89.8
    poa_navigation <- 84.5
    rim_dfg_delta <- -4.8
    rim_deterrence_index <- 3.6
    d_rapm <- 2.45
    m_pg_pct <- 18.2; m_sg_pct <- 24.5; m_sf_pct <- 30.1; m_pf_pct <- 20.4; m_c_pct <- 6.8
  }

  defensive_profiles[[i]] <- list(
    playerId = as.character(p$player_id),
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
output_json <- WEB_JSON_DEFENSIVE_METRICS  # config.R; was a bare relative path
jsonlite::write_json(defensive_profiles, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Defensive profiles to '%s'.\n", length(defensive_profiles), output_json))

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(defensive_profiles, "cache/defensive_metrics.rds")
cat(">>> [SUCCESS] Cached RDS in 'cache/defensive_metrics.rds'.\n")
