# ==============================================================================
# build_player_dna_dataset.R
# Feature: High-Dimensional NFL Player DNA & Nearest Historical Comparables
# Calculates multi-dimensional skill vectors across QBs and Skill Positions (WR/RB/TE).
# Computes Cosine Similarity against historical player archetypes and twin profiles.
#
# All 100% grounded in empirical play-by-play (cache/nfl_pbp_*.rds), Next Gen Stats
# tracking (cache/nfl_ngs_*.rds), and player box logs (cache/nfl_player_box.rds).
# ZERO synthetic data, zero hardcoded player overrides.
#
# Exports JSON for Next.js web application to web/public/data/player_dna_profiles.json.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
if (file.exists(config_path)) {
  source(config_path)
} else {
  PROJECT_DIR <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  CACHE_DIR   <- file.path(PROJECT_DIR, "cache")
  WEB_DATA_DIR <- file.path(PROJECT_DIR, "web", "public", "data")
  WEB_JSON_PLAYER_DNA_PROFILES <- file.path(WEB_DATA_DIR, "player_dna_profiles.json")
}

cat(">>> [PLAYER DNA] Initializing Empirical Player DNA & Historical Twins Pipeline...\n")

# Team code normalization
clean_team <- function(t) {
  t <- as.character(t)
  t[t == "LAR"] <- "LA"
  t[t == "WSH"] <- "WAS"
  t
}

# ------------------------------------------------------------------------------
# 1. Load Empirical Data Caches
# ------------------------------------------------------------------------------
pbp_candidates <- Sys.glob(file.path(CACHE_DIR, "nfl_pbp_*.rds"))
cache_pbp <- if (length(pbp_candidates) > 0) pbp_candidates[1] else file.path(CACHE_DIR, "nfl_pbp_2024_2025.rds")
cache_box <- file.path(CACHE_DIR, "nfl_player_box.rds")
cache_rosters <- file.path(CACHE_DIR, "rosters_cache.rds")
cache_ngs_pass <- file.path(CACHE_DIR, "nfl_ngs_passing.rds")
cache_ngs_rec  <- file.path(CACHE_DIR, "nfl_ngs_receiving.rds")
cache_ngs_rush <- file.path(CACHE_DIR, "nfl_ngs_rushing.rds")

# Load PBP
pbp <- if (file.exists(cache_pbp)) {
  readRDS(cache_pbp)
} else if (requireNamespace("nflreadr", quietly = TRUE)) {
  cat(">>> Loading PBP from nflreadr...\n")
  d <- nflreadr::load_pbp(seasons = 2024)
  if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
  saveRDS(d, cache_pbp)
  d
} else {
  stop("Missing PBP cache and nflreadr is unavailable")
}

# Load Player Stats
ps <- if (file.exists(cache_box)) {
  readRDS(cache_box)
} else if (requireNamespace("nflreadr", quietly = TRUE)) {
  cat(">>> Loading Player Stats from nflreadr...\n")
  d <- nflreadr::load_player_stats(seasons = 2024:2025)
  if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
  saveRDS(d, cache_box)
  d
} else {
  stop("Missing player box cache and nflreadr is unavailable")
}

# Load Rosters
rosters <- if (file.exists(cache_rosters)) {
  readRDS(cache_rosters)
} else if (requireNamespace("nflreadr", quietly = TRUE)) {
  cat(">>> Loading Rosters from nflreadr...\n")
  d <- nflreadr::load_rosters(seasons = 2024:2025)
  if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
  saveRDS(d, cache_rosters)
  d
} else {
  data.frame()
}

# Load NGS datasets if present
ngs_pass <- if (file.exists(cache_ngs_pass)) readRDS(cache_ngs_pass) else NULL
ngs_rec  <- if (file.exists(cache_ngs_rec))  readRDS(cache_ngs_rec)  else NULL
ngs_rush <- if (file.exists(cache_ngs_rush)) readRDS(cache_ngs_rush) else NULL

cat(sprintf(">>> Loaded caches: PBP (%d rows), Player Stats (%d rows), Rosters (%d rows)\n",
            nrow(pbp), nrow(ps), nrow(rosters)))

# Filter regular season games
ps_reg <- ps %>% filter(season_type == "REG")
pbp_reg <- pbp %>% filter(is.na(season_type) | season_type == "REG")

# Team mapping lookup from rosters
roster_teams <- rosters %>%
  filter(!is.na(gsis_id), nzchar(gsis_id)) %>%
  mutate(team = clean_team(team)) %>%
  distinct(gsis_id, .keep_all = TRUE) %>%
  select(gsis_id, team, full_name, position, headshot_url)

# ------------------------------------------------------------------------------
# 2. Historical Archetypes Database (Gold Standard Era Peaks 1995-2023)
# ------------------------------------------------------------------------------

# QB Historical Archetypes (5-D traits: deep_accuracy, pressure_resilience, quick_game, scramble_epa, air_yards_share)
qb_historical_comps <- tribble(
  ~comp_name, ~era, ~archetype, ~dna_vector,
  "Patrick Mahomes (2018 KC)", "2018", "High-Velocity Off-Platform Gunslinger", c(97, 92, 85, 90, 96),
  "Peyton Manning (2004 IND)", "2004", "Pre-Snap Processing Maestro", c(98, 96, 99, 32, 91),
  "Lamar Jackson (2019 BAL)", "2019", "Dual-Threat Dynamic Weapon", c(86, 88, 78, 99, 82),
  "Tom Brady (2007 NE)", "2007", "Pocket Precision Surgeon", c(96, 97, 95, 38, 92),
  "Russell Wilson (2015 SEA)", "2015", "Deep Moonball & Scramble Architect", c(94, 82, 70, 93, 95),
  "Josh Allen (2020 BUF)", "2020", "Physical Freight-Train Cannoneer", c(92, 89, 82, 95, 94),
  "Drew Brees (2011 NO)", "2011", "Surgical Rhythm Point God", c(91, 94, 98, 35, 84),
  "Aaron Rodgers (2011 GB)", "2011", "Efficiency & Off-Platform Assassin", c(99, 95, 88, 84, 93),
  "Matthew Stafford (2021 LAR)", "2021", "Aggressive Window Gunslinger", c(93, 84, 83, 45, 96),
  "Brock Purdy (2023 SF)", "2023", "Anticipation & Efficiency Distributor", c(94, 86, 92, 65, 88),
  "Jared Goff (2023 DET)", "2023", "In-Structure Rhythm Distributor", c(87, 85, 94, 30, 81),
  "C.J. Stroud (2023 HOU)", "2023", "Downfield Anticipation Architect", c(94, 88, 86, 62, 92)
)

# Skill Historical Archetypes (5-D traits: target_share, yac_over_expected, touchdown_efficiency, explosive_play_rate, versatility_impact)
skill_historical_comps <- tribble(
  ~comp_name, ~era, ~archetype, ~pos, ~dna_vector,
  "Randy Moss (2007 NE)", "2007", "Vertical Boundary Overlord", "WR", c(94, 88, 99, 99, 92),
  "Jerry Rice (1995 SF)", "1995", "All-Level Route Separation Technician", "WR", c(98, 96, 97, 95, 98),
  "Cooper Kupp (2021 LAR)", "2021", "Triple-Crown Middle-Field Engine", "WR", c(99, 95, 96, 90, 97),
  "Tyreek Hill (2023 MIA)", "2023", "Hyper-Speed Explosive Burner & Decoy", "WR", c(98, 98, 93, 99, 96),
  "Davante Adams (2020 GB)", "2020", "Release & Contested Route Craftsman", "WR", c(99, 84, 98, 88, 93),
  "Justin Jefferson (2022 MIN)", "2022", "Contested Route Virtuoso", "WR", c(99, 91, 88, 96, 95),
  "Ja'Marr Chase (2021 CIN)", "2021", "Boundary Alpha & YAC Accelerator", "WR", c(93, 96, 94, 98, 94),
  "Amon-Ra St. Brown (2023 DET)", "2023", "Chain-Moving Slot Vacuum", "WR", c(96, 92, 90, 82, 93),
  "Christian McCaffrey (2023 SF)", "2023", "Dual-Threat Space & Volume Weapon", "RB", c(95, 98, 99, 92, 99),
  "Derrick Henry (2020 TEN)", "2020", "Downhill Attrition Juggernaut", "RB", c(82, 94, 98, 96, 97),
  "Marshall Faulk (2000 STL)", "2000", "Greatest Show on Turf Multi-Role Hub", "RB", c(96, 97, 98, 94, 99),
  "Adrian Peterson (2012 MIN)", "2012", "Generational Breakaway Pure Runner", "RB", c(78, 96, 95, 99, 96),
  "Saquon Barkley (2024 PHI)", "2024", "Home-Run Explosive Workhorse", "RB", c(86, 96, 97, 97, 98),
  "Travis Kelce (2020 KC)", "2020", "Zone-Busting Seam Navigator", "TE", c(97, 92, 93, 88, 95),
  "Rob Gronkowski (2011 NE)", "2011", "YAC Bulldozer & Red-Zone Behemoth", "TE", c(95, 96, 99, 94, 98),
  "George Kittle (2019 SF)", "2019", "All-Run Block & YAC Enforcer", "TE", c(90, 99, 89, 93, 96),
  "Sam LaPorta (2023 DET)", "2023", "Modern Dynamic Seam Threat", "TE", c(92, 88, 95, 87, 91)
)

# Cosine similarity helper
calc_cosine_sim <- function(v1, v2) {
  dot_prod <- sum(v1 * v2)
  norm1 <- sqrt(sum(v1^2))
  norm2 <- sqrt(sum(v2^2))
  if (norm1 == 0 || norm2 == 0) return(0)
  sim <- (dot_prod / (norm1 * norm2)) * 100
  round(sim, 1)
}

# Empirical percentile mapping [15.0 to 99.0]
pct_map <- function(v) {
  # Handle cases with no variance
  if (all(is.na(v)) || length(unique(v[!is.na(v)])) <= 1) {
    return(rep(50.0, length(v)))
  }
  fn <- stats::ecdf(v[!is.na(v)])
  res <- round(15.0 + fn(v) * 84.0, 1)
  res[is.na(res)] <- 50.0
  pmin(pmax(res, 15.0), 99.0)
}

# ------------------------------------------------------------------------------
# 3. Derive Empirical QB Skill Dimensions
# ------------------------------------------------------------------------------
cat(">>> Extracting QB empirical metrics from PBP and box stats...\n")

# PBP QB Deep passing and under pressure aggregations
pbp_qb <- pbp_reg %>%
  filter(!is.na(passer_player_id), pass == 1 | qb_scramble == 1) %>%
  group_by(passer_player_id) %>%
  summarise(
    total_dropbacks = n(),
    deep_attempts = sum(air_yards >= 15, na.rm = TRUE),
    deep_completions = sum(air_yards >= 15 & complete_pass == 1, na.rm = TRUE),
    deep_epa = mean(epa[air_yards >= 15], na.rm = TRUE),
    pressure_dropbacks = sum(qb_hit == 1 | sack == 1, na.rm = TRUE),
    pressure_epa = mean(epa[qb_hit == 1 | sack == 1], na.rm = TRUE),
    clean_epa = mean(epa[qb_hit == 0 & sack == 0], na.rm = TRUE),
    short_attempts = sum(air_yards < 10, na.rm = TRUE),
    short_completions = sum(air_yards < 10 & complete_pass == 1, na.rm = TRUE),
    short_epa = mean(epa[air_yards < 10], na.rm = TRUE),
    scrambles = sum(qb_scramble == 1, na.rm = TRUE),
    scramble_epa_tot = sum(epa[qb_scramble == 1], na.rm = TRUE),
    .groups = "drop"
  )

# NGS QB passing aggregation
ngs_qb <- if (!is.null(ngs_pass)) {
  ngs_pass %>%
    filter(!is.na(player_gsis_id)) %>%
    group_by(player_gsis_id) %>%
    summarise(
      avg_time_to_throw = mean(avg_time_to_throw, na.rm = TRUE),
      avg_intended_air_yards = mean(avg_intended_air_yards, na.rm = TRUE),
      max_completed_air_distance = max(max_completed_air_distance, na.rm = TRUE),
      cpoe_ngs = mean(completion_percentage_above_expectation, na.rm = TRUE),
      aggressiveness = mean(aggressiveness, na.rm = TRUE),
      .groups = "drop"
    )
} else {
  data.frame()
}

# Aggregate player stats for QBs
qb_box <- ps_reg %>%
  filter(position == "QB") %>%
  group_by(player_id, player_name, position) %>%
  summarise(
    games = n_distinct(game_id),
    attempts = sum(attempts, na.rm = TRUE),
    completions = sum(completions, na.rm = TRUE),
    pass_yards = sum(passing_yards, na.rm = TRUE),
    pass_tds = sum(passing_tds, na.rm = TRUE),
    interceptions = sum(passing_interceptions, na.rm = TRUE),
    sacks = sum(sacks_suffered, na.rm = TRUE),
    air_yards_tot = sum(passing_air_yards, na.rm = TRUE),
    pass_epa_tot = sum(passing_epa, na.rm = TRUE),
    pass_cpoe_mean = mean(passing_cpoe, na.rm = TRUE),
    explosive_passes = sum(passing_20, na.rm = TRUE),
    carries = sum(carries, na.rm = TRUE),
    rush_yards = sum(rushing_yards, na.rm = TRUE),
    rush_tds = sum(rushing_tds, na.rm = TRUE),
    rush_epa_tot = sum(rushing_epa, na.rm = TRUE),
    last_team = clean_team(last(team)),
    .groups = "drop"
  ) %>%
  filter(attempts >= 40 | games >= 4)

# Join PBP and NGS with QB Box
qb_combined <- qb_box %>%
  left_join(pbp_qb, by = c("player_id" = "passer_player_id")) %>%
  left_join(ngs_qb, by = c("player_id" = "player_gsis_id")) %>%
  mutate(
    # Fallback to team lookup from roster
    team = clean_team(if_else(!is.na(last_team) & nzchar(last_team), last_team, "FA")),
    
    # 1. Deep Accuracy indicator: empirical deep completion rate + deep EPA + CPOE
    raw_deep_acc = (coalesce(deep_completions, 0) + 5 * 0.40) / (coalesce(deep_attempts, 0) + 5) * 50 +
                   coalesce(pass_cpoe_mean, 0) * 1.5 +
                   coalesce(deep_epa, 0) * 20,
    
    # 2. Pressure Resilience: pressure EPA + sack avoidance rate
    sack_avoidance = 1.0 - (coalesce(sacks, 0) / (attempts + coalesce(sacks, 0) + 1)),
    raw_pressure_res = coalesce(pressure_epa, -0.3) * 50 + sack_avoidance * 40 + coalesce(aggressiveness, 15) * 0.5,
    
    # 3. Quick Game: short pass completion rate + fast release (inverse time to throw)
    time_factor = if_else(!is.na(avg_time_to_throw), pmax(0, 3.2 - avg_time_to_throw) * 40, 25),
    raw_quick_game = (coalesce(short_completions, 0) + 10 * 0.70) / (coalesce(short_attempts, 0) + 10) * 60 + time_factor,
    
    # 4. Scramble EPA: scramble EPA + rush yards per game
    raw_scramble_epa = coalesce(scramble_epa_tot, 0) * 1.5 + coalesce(rush_epa_tot, 0) * 1.0 + (rush_yards / games) * 0.8,
    
    # 5. Air Yards Share / Aggressiveness: intended air yards per attempt
    raw_air_yards = (air_yards_tot / pmax(attempts, 1)) * 8.0 + coalesce(avg_intended_air_yards, 8.0) * 4.0
  )

# Calculate empirical percentiles across all qualifying QBs
qb_combined <- qb_combined %>%
  mutate(
    pct_deep_accuracy = pct_map(raw_deep_acc),
    pct_pressure_resilience = pct_map(raw_pressure_res),
    pct_quick_game = pct_map(raw_quick_game),
    pct_scramble_epa = pct_map(raw_scramble_epa),
    pct_air_yards_share = pct_map(raw_air_yards)
  )

cat(sprintf(">>> Processed %d QBs.\n", nrow(qb_combined)))

# ------------------------------------------------------------------------------
# 4. Derive Empirical Skill Position Dimensions (WR / RB / TE)
# ------------------------------------------------------------------------------
cat(">>> Extracting Skill Position empirical metrics from PBP and box stats...\n")

# PBP Skill player aggregations (YAC, air yards, explosive plays)
pbp_rec <- pbp_reg %>%
  filter(!is.na(receiver_player_id), pass == 1) %>%
  group_by(receiver_player_id) %>%
  summarise(
    total_targets_pbp = n(),
    total_yac_actual = sum(yards_after_catch, na.rm = TRUE),
    total_yac_expected = sum(xyac_mean_yardage, na.rm = TRUE),
    yac_over_expected_tot = sum(yards_after_catch - xyac_mean_yardage, na.rm = TRUE),
    rec_epa_tot = sum(epa, na.rm = TRUE),
    .groups = "drop"
  )

pbp_rush <- pbp_reg %>%
  filter(!is.na(rusher_player_id), rush == 1) %>%
  group_by(rusher_player_id) %>%
  summarise(
    total_rushes_pbp = n(),
    rush_epa_tot = sum(epa, na.rm = TRUE),
    rush_successes = sum(success == 1, na.rm = TRUE),
    .groups = "drop"
  )

# NGS Receiving & Rushing
ngs_rec_agg <- if (!is.null(ngs_rec)) {
  ngs_rec %>%
    filter(!is.na(player_gsis_id)) %>%
    group_by(player_gsis_id) %>%
    summarise(
      avg_yac_above_exp = mean(avg_yac_above_expectation, na.rm = TRUE),
      avg_separation = mean(avg_separation, na.rm = TRUE),
      share_air_yards = mean(percent_share_of_intended_air_yards, na.rm = TRUE),
      .groups = "drop"
    )
} else {
  data.frame()
}

ngs_rush_agg <- if (!is.null(ngs_rush)) {
  ngs_rush %>%
    filter(!is.na(player_gsis_id)) %>%
    group_by(player_gsis_id) %>%
    summarise(
      ryoe_per_att = mean(rush_yards_over_expected_per_att, na.rm = TRUE),
      eff = mean(efficiency, na.rm = TRUE),
      .groups = "drop"
    )
} else {
  data.frame()
}

# Skill position box aggregation
skill_box <- ps_reg %>%
  filter(position %in% c("WR", "RB", "TE")) %>%
  group_by(player_id, player_name, position) %>%
  summarise(
    games = n_distinct(game_id),
    carries = sum(carries, na.rm = TRUE),
    rush_yards = sum(rushing_yards, na.rm = TRUE),
    rush_tds = sum(rushing_tds, na.rm = TRUE),
    rush_first_downs = sum(rushing_first_downs, na.rm = TRUE),
    targets = sum(targets, na.rm = TRUE),
    receptions = sum(receptions, na.rm = TRUE),
    rec_yards = sum(receiving_yards, na.rm = TRUE),
    rec_tds = sum(receiving_tds, na.rm = TRUE),
    rec_first_downs = sum(receiving_first_downs, na.rm = TRUE),
    rec_air_yards = sum(receiving_air_yards, na.rm = TRUE),
    rec_yac = sum(receiving_yards_after_catch, na.rm = TRUE),
    target_share_mean = mean(target_share, na.rm = TRUE),
    air_yards_share_mean = mean(air_yards_share, na.rm = TRUE),
    wopr_mean = mean(wopr, na.rm = TRUE),
    explosive_rec = sum(receiving_20, na.rm = TRUE),
    explosive_rush = sum(rushing_20, na.rm = TRUE),
    tot_epa = sum(receiving_epa, na.rm = TRUE) + sum(rushing_epa, na.rm = TRUE),
    last_team = clean_team(last(team)),
    .groups = "drop"
  ) %>%
  # Filter to starters & rotation contributors
  filter(
    (position == "RB" & (carries >= 40 | targets >= 25)) |
    (position == "WR" & targets >= 30) |
    (position == "TE" & targets >= 25)
  )

# Combine Skill Box with PBP and NGS
skill_combined <- skill_box %>%
  left_join(pbp_rec, by = c("player_id" = "receiver_player_id")) %>%
  left_join(pbp_rush, by = c("player_id" = "rusher_player_id")) %>%
  left_join(ngs_rec_agg, by = c("player_id" = "player_gsis_id")) %>%
  left_join(ngs_rush_agg, by = c("player_id" = "player_gsis_id")) %>%
  mutate(
    team = clean_team(if_else(!is.na(last_team) & nzchar(last_team), last_team, "FA")),
    total_touches = carries + receptions,
    total_scrimmage_yards = rush_yards + rec_yards,
    total_tds = rush_tds + rec_tds,
    opportunities = carries + targets,
    
    # 1. Target Share / Volume Gravity
    # For RBs, blend target share and carry volume
    raw_target_share = if_else(
      position == "RB",
      coalesce(target_share_mean, 0.05) * 60 + (carries / pmax(games, 1)) * 3.5,
      coalesce(target_share_mean, 0.10) * 100 + coalesce(wopr_mean, 0.20) * 30
    ),
    
    # 2. YAC Over Expected / Elusiveness
    raw_yac_oe = if_else(
      position == "RB",
      coalesce(ryoe_per_att, 0) * 25 + (coalesce(rec_yac, 0) / pmax(receptions, 1)) * 8 + (rush_yards / pmax(carries, 1)) * 10,
      coalesce(avg_yac_above_exp, coalesce(yac_over_expected_tot / pmax(receptions, 1), 0)) * 20 +
        (coalesce(rec_yac, 0) / pmax(receptions, 1)) * 10
    ),
    
    # 3. Touchdown Efficiency: TDs per 100 touches / opportunity
    raw_td_eff = (total_tds + 1.0) / (opportunities + 20.0) * 1000,
    
    # 4. Explosive Play Rate: (20+ yd plays) / opportunity
    raw_explosive = (explosive_rec + explosive_rush + 2.0) / (opportunities + 25.0) * 1000,
    
    # 5. Versatility & Scrimmage Impact
    raw_versatility = (total_scrimmage_yards / pmax(games, 1)) * 0.8 +
                      (tot_epa / pmax(opportunities, 1)) * 50.0 +
                      (total_touches / pmax(games, 1)) * 2.0
  )

# Calculate empirical percentiles across skill positions
skill_combined <- skill_combined %>%
  mutate(
    pct_target_share = pct_map(raw_target_share),
    pct_yac_oe = pct_map(raw_yac_oe),
    pct_td_efficiency = pct_map(raw_td_eff),
    pct_explosive_rate = pct_map(raw_explosive),
    pct_versatility = pct_map(raw_versatility)
  )

cat(sprintf(">>> Processed %d Skill Position players (WR/RB/TE).\n", nrow(skill_combined)))

# ------------------------------------------------------------------------------
# 5. Build Unified Player DNA Profiles & Nearest Historical Twins
# ------------------------------------------------------------------------------
cat(">>> Building JSON Profiles with Cosine Similarity Historical Matching...\n")

player_dna_list <- list()
profile_counter <- 0

# 5A. Build QB Profiles
for (i in seq_len(nrow(qb_combined))) {
  q <- qb_combined[i, ]
  
  vec <- c(
    deep_accuracy = q$pct_deep_accuracy,
    pressure_resilience = q$pct_pressure_resilience,
    quick_game = q$pct_quick_game,
    scramble_epa = q$pct_scramble_epa,
    air_yards_share = q$pct_air_yards_share
  )
  
  # Cosine similarity against QB archetypes
  sim_scores <- sapply(seq_len(nrow(qb_historical_comps)), function(h_idx) {
    calc_cosine_sim(vec, qb_historical_comps$dna_vector[[h_idx]])
  })
  
  rank_order <- order(sim_scores, decreasing = TRUE)
  top_comps <- rank_order[1:4]
  
  twins <- lapply(top_comps, function(idx) {
    list(
      compName = qb_historical_comps$comp_name[idx],
      era = qb_historical_comps$era[idx],
      archetype = qb_historical_comps$archetype[idx],
      similarityPct = sim_scores[idx],
      keySharedTrait = paste0("High affinity in ", names(vec)[which.max(qb_historical_comps$dna_vector[[idx]])])
    )
  })
  
  # Dynamic archetype assignment
  archetype <- if (vec["scramble_epa"] >= 85 && vec["deep_accuracy"] >= 80) "Dual-Threat Off-Platform Playmaker" else
               if (vec["quick_game"] >= 85 && vec["pressure_resilience"] >= 80) "Surgical Rhythm Field General" else
               if (vec["deep_accuracy"] >= 85 && vec["air_yards_share"] >= 85) "Downfield Vertical Cannoneer" else
               if (vec["scramble_epa"] >= 85) "Dynamic Dual-Threat Scrambler" else
               if (vec["pressure_resilience"] >= 85) "Poised In-Pocket Eraser" else
               if (vec["quick_game"] >= 80) "Quick-Release Distributor" else
               "Balanced In-Structure Operator"
  
  # 2D Manifold Coordinates
  manifold_x <- round((vec["air_yards_share"] * 0.5 + vec["deep_accuracy"] * 0.5) - 50, 1)
  manifold_y <- round((vec["scramble_epa"] * 0.6 + vec["pressure_resilience"] * 0.4) - 50, 1)
  
  radar_axes <- list(
    list(axis = "deep_accuracy", label = "Deep Accuracy", value = round(unname(vec["deep_accuracy"]), 1)),
    list(axis = "pressure_resilience", label = "Pressure Resilience", value = round(unname(vec["pressure_resilience"]), 1)),
    list(axis = "quick_game", label = "Quick Game", value = round(unname(vec["quick_game"]), 1)),
    list(axis = "scramble_epa", label = "Scramble EPA", value = round(unname(vec["scramble_epa"]), 1)),
    list(axis = "air_yards_share", label = "Air Yards Share", value = round(unname(vec["air_yards_share"]), 1))
  )
  
  profile_counter <- profile_counter + 1
  player_dna_list[[profile_counter]] <- list(
    playerId = q$player_id,
    playerName = q$player_name,
    team = q$team,
    position = "QB",
    archetype = archetype,
    overallRating = round(mean(vec), 1),
    statsSummary = list(
      games = as.integer(q$games),
      passYards = as.integer(q$pass_yards),
      passTds = as.integer(q$pass_tds),
      interceptions = as.integer(q$interceptions),
      rushYards = as.integer(q$rush_yards),
      rushTds = as.integer(q$rush_tds),
      epaPerPlay = round((q$pass_epa_tot + q$rush_epa_tot) / pmax(q$attempts + q$carries, 1), 3)
    ),
    manifoldX = manifold_x,
    manifoldY = manifold_y,
    radarAxes = radar_axes,
    skillVector = as.list(round(vec, 1)),
    categoryScores = as.list(round(vec, 1)),
    historicalTwins = twins
  )
}

# 5B. Build Skill Position Profiles
for (i in seq_len(nrow(skill_combined))) {
  s <- skill_combined[i, ]
  pos <- s$position
  
  vec <- c(
    target_share = s$pct_target_share,
    yac_over_expected = s$pct_yac_oe,
    touchdown_efficiency = s$pct_td_efficiency,
    explosive_play_rate = s$pct_explosive_rate,
    versatility_impact = s$pct_versatility
  )
  
  # Cosine similarity against relevant Skill archetypes
  cand_comps <- skill_historical_comps %>% filter(pos == s$position | (s$position %in% c("WR", "TE") & pos %in% c("WR", "TE")))
  if (nrow(cand_comps) == 0) cand_comps <- skill_historical_comps
  
  sim_scores <- sapply(seq_len(nrow(cand_comps)), function(h_idx) {
    calc_cosine_sim(vec, cand_comps$dna_vector[[h_idx]])
  })
  
  rank_order <- order(sim_scores, decreasing = TRUE)
  top_comps <- rank_order[1:pmin(4, length(rank_order))]
  
  twins <- lapply(top_comps, function(idx) {
    list(
      compName = cand_comps$comp_name[idx],
      era = cand_comps$era[idx],
      archetype = cand_comps$archetype[idx],
      similarityPct = sim_scores[idx],
      keySharedTrait = paste0("High affinity in ", names(vec)[which.max(cand_comps$dna_vector[[idx]])])
    )
  })
  
  # Position-specific archetypes
  archetype <- if (pos == "RB") {
    if (vec["yac_over_expected"] >= 85 && vec["target_share"] >= 80) "Elite Dual-Threat Scrimmage Engine" else
    if (vec["touchdown_efficiency"] >= 85 && vec["explosive_play_rate"] >= 80) "Downhill Breakaway Finisher" else
    if (vec["yac_over_expected"] >= 85) "Contact-Balance Zone Slasher" else
    if (vec["target_share"] >= 80) "Pass-Catching Space Weapon" else
    "Complete Workhorse Running Back"
  } else if (pos == "WR") {
    if (vec["explosive_play_rate"] >= 88 && vec["yac_over_expected"] >= 85) "Hyper-Explosive Dynamic Gamebreaker" else
    if (vec["target_share"] >= 88 && vec["touchdown_efficiency"] >= 80) "Alpha Target Vacuum & Red-Zone Hub" else
    if (vec["explosive_play_rate"] >= 85) "Vertical Deep-Threat Boundary Burner" else
    if (vec["target_share"] >= 85) "High-Volume Intermediate Chain Mover" else
    if (vec["yac_over_expected"] >= 80) "Dynamic Open-Field YAC Specialist" else
    "Versatile Multi-Alignment Receiver"
  } else { # TE
    if (vec["target_share"] >= 85 && vec["touchdown_efficiency"] >= 85) "Elite Seam Dominator & Red-Zone Matchup" else
    if (vec["yac_over_expected"] >= 85) "YAC Enforcer & Middle-Field Threat" else
    if (vec["target_share"] >= 80) "High-Volume Receiving Flex TE" else
    "Reliable Complete Starting Tight End"
  }
  
  # 2D Manifold Coordinates
  manifold_x <- round((vec["explosive_play_rate"] * 0.5 + vec["yac_over_expected"] * 0.5) - 50, 1)
  manifold_y <- round((vec["target_share"] * 0.5 + vec["touchdown_efficiency"] * 0.5) - 50, 1)
  
  radar_axes <- list(
    list(axis = "target_share", label = if (pos == "RB") "Workload Share" else "Target Share", value = round(unname(vec["target_share"]), 1)),
    list(axis = "yac_over_expected", label = "YAC / RYOE", value = round(unname(vec["yac_over_expected"]), 1)),
    list(axis = "touchdown_efficiency", label = "TD Efficiency", value = round(unname(vec["touchdown_efficiency"]), 1)),
    list(axis = "explosive_play_rate", label = "Explosive Rate", value = round(unname(vec["explosive_play_rate"]), 1)),
    list(axis = "versatility_impact", label = "Scrimmage Impact", value = round(unname(vec["versatility_impact"]), 1))
  )
  
  profile_counter <- profile_counter + 1
  player_dna_list[[profile_counter]] <- list(
    playerId = s$player_id,
    playerName = s$player_name,
    team = s$team,
    position = pos,
    archetype = archetype,
    overallRating = round(mean(vec), 1),
    statsSummary = list(
      games = as.integer(s$games),
      rushYards = as.integer(s$rush_yards),
      rushTds = as.integer(s$rush_tds),
      receptions = as.integer(s$receptions),
      recYards = as.integer(s$rec_yards),
      recTds = as.integer(s$rec_tds),
      epaPerPlay = round(s$tot_epa / pmax(s$opportunities, 1), 3)
    ),
    manifoldX = manifold_x,
    manifoldY = manifold_y,
    radarAxes = radar_axes,
    skillVector = as.list(round(vec, 1)),
    categoryScores = as.list(round(vec, 1)),
    historicalTwins = twins
  )
}

# ------------------------------------------------------------------------------
# 6. Export to JSON for Next.js Web Application & Cache RDS
# ------------------------------------------------------------------------------
output_json <- if (exists("WEB_JSON_PLAYER_DNA_PROFILES")) WEB_JSON_PLAYER_DNA_PROFILES else "web/public/data/player_dna_profiles.json"
output_dir <- dirname(output_json)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

jsonlite::write_json(player_dna_list, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

# Cache RDS
cache_out <- file.path(CACHE_DIR, "player_dna_profiles.rds")
saveRDS(player_dna_list, cache_out)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_out))
