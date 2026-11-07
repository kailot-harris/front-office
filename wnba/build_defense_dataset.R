# ==============================================================================
# build_defense_dataset.R
# Path: build_defense_dataset.R
#
# Feature 4: WNBA Defensive Versatility & Coverage Matrix (Rectified, Issue #133)
# Quantifies:
# 1. Positional Versatility (Shannon Entropy across 5 positions: PG, SG, SF, PF, C)
#    derived from real possession lineups in wehoop::load_wnba_stats_possessions()
# 2. Rim Deterrence vs Rim Contest Residual (Opponent FG% delta at rim vs empirical baseline)
#    derived from real shot coordinates in wehoop::load_wnba_stats_shots()
# 3. Defensive Role Archetypes (Primary Rim Anchor, 1-Through-5 Switch Eraser,
#    Roaming Weakside Disrupter, Point-of-Attack Stopper, Perimeter Chaser, Positional Connector)
# 4. Defensive RAPM (dRAPM) -- REAL ridge fit from cache/rapm_ratings.rds via
#    join_rapm_to_roster(), pooled 2019-2026 (#83)
# 5. Full provenance flags for all surviving metrics (Issue #133)
#
# All affine rebound heuristics, synthetic screen navigation scores, and
# hand-curated marquee player overrides have been eliminated.
#
# Exports:
#   - web/public/data/defensive_metrics.json
#   - cache/defensive_metrics.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(data.table)
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
# 1. REAL DEFENSIVE RAPM (issue #83, #91)
# ------------------------------------------------------------------------------
rapm_utils_path <- if (file.exists("rapm_join_utils.R")) "rapm_join_utils.R" else "../rapm_join_utils.R"
source(rapm_utils_path)

DRAPM_SOURCE_RIDGE      <- "rapm_ridge_pooled"
DRAPM_SOURCE_RIDGE_LOW  <- "rapm_ridge_pooled_low_sample"
DRAPM_SOURCE_FALLBACK   <- "heuristic_fallback"

rost_file <- file.path(CACHE_DIR, "active_rosters_cache.rds")
rapm_file <- CACHE_RAPM_RATINGS

drapm_lookup <- tryCatch({
  if (!file.exists(rost_file) || !file.exists(rapm_file)) {
    stop("missing active_rosters_cache.rds or rapm_ratings.rds")
  }
  joined <- join_rapm_to_roster(readRDS(rost_file), readRDS(rapm_file), matched_only = FALSE)
  if (!"drapm" %in% names(joined) || nrow(joined) == 0) {
    stop("join returned no usable `drapm` column")
  }
  joined |>
    dplyr::transmute(
      player_id       = as.character(.data$player_id),
      rapm_player_id  = as.character(.data$rapm_player_id),
      drapm           = as.numeric(.data$drapm),
      rapm_matched    = !is.na(.data$drapm),
      rapm_ambiguous  = dplyr::coalesce(.data$rapm_ambiguous, FALSE),
      low_sample_flag = dplyr::coalesce(.data$low_sample_flag, FALSE)
    ) |>
    dplyr::distinct(.data$player_id, .keep_all = TRUE)
}, error = function(e) {
  warning(sprintf("[DEFENSIVE METRICS] Real dRAPM join failed: %s", conditionMessage(e)))
  NULL
})

if (is.null(drapm_lookup)) {
  n_real <- 0L
} else {
  n_real <- sum(drapm_lookup$rapm_matched)
  cat(sprintf(">>> Real ridge dRAPM joined for %d of %d roster players.\n",
              n_real, nrow(drapm_lookup)))
}

# ------------------------------------------------------------------------------
# 2. REAL SHOTS & POSSESSION LINEUPS (Issue #133)
# ------------------------------------------------------------------------------
shots_cache_path <- file.path(CACHE_DIR, "wnba_shots_cache.rds")
pbp_cache_path <- file.path(CACHE_DIR, "wnba_pbp_cache.rds")
cw_cache_path <- file.path(CACHE_DIR, "player_id_crosswalk.rds")
box_cache_path <- file.path(CACHE_DIR, "player_box_scores_cache.rds")

has_real_shots <- file.exists(shots_cache_path) && file.exists(pbp_cache_path)

if (!has_real_shots) {
  stop("Missing wnba_shots_cache.rds or wnba_pbp_cache.rds in cache/")
}

cat(">>> Processing real shot locations and possession lineups...\n")
shots <- as.data.table(readRDS(shots_cache_path))
pbp <- readRDS(pbp_cache_path)
poss <- as.data.table(pbp$possessions)
cw <- if (file.exists(cw_cache_path)) as.data.table(readRDS(cw_cache_path)) else NULL
box <- if (file.exists(box_cache_path)) as.data.table(readRDS(box_cache_path)) else NULL

# Parse clock in shots (ISO 8601 duration "PT09M18.00S" -> seconds remaining)
shots[, clock_m := as.numeric(str_match(clock, "PT(\\d+)M")[, 2])]
shots[, clock_s := as.numeric(str_match(clock, "M(\\d+(?:\\.\\d+)?)S")[, 2])]
shots[is.na(clock_m), clock_m := 0]
shots[is.na(clock_s), clock_s := 0]
shots[, sec := round(clock_m * 60 + clock_s)]
shots[, `:=`(clock_m = NULL, clock_s = NULL)]

shots[, game_id := as.character(game_id)]
shots[, period := as.integer(period)]
poss[, game_id := as.character(game_id)]
poss[, period := as.integer(period)]
poss[, start_sec := round(pmax(start_seconds_remaining, end_seconds_remaining))]
poss[, end_sec := round(pmin(start_seconds_remaining, end_seconds_remaining))]

# Match shots to possessions via foverlaps
shots[, sec_start := sec]
shots[, sec_end := sec]
setkey(poss, game_id, period, end_sec, start_sec)

matched <- foverlaps(
  shots, poss,
  by.x = c("game_id", "period", "sec_start", "sec_end"),
  type = "within", mult = "first"
)

# ------------------------------------------------------------------------------
# 3. SHOOTER DETAILED POSITION MAPPING (PG, SG, SF, PF, C)
# ------------------------------------------------------------------------------
# Map shooter person_id -> detailed position using box scores & crosswalk
if (!is.null(box) && !is.null(cw)) {
  p_stats <- box[, .(
    pos = names(which.max(table(athlete_position_abbreviation))),
    ast_pg = mean(assists, na.rm = TRUE),
    reb_pg = mean(rebounds, na.rm = TRUE)
  ), by = .(athlete_id = as.character(athlete_id))]

  p_stats[, detailed_pos := fifelse(
    pos == "G", fifelse(ast_pg >= 3.0, "PG", "SG"),
    fifelse(pos == "F", fifelse(reb_pg <= 5.0, "SF", "PF"), "C")
  )]

  cw_map <- unique(cw[!is.na(wnba_player_id) & !is.na(espn_athlete_id), .(
    person_id = as.integer(wnba_player_id),
    espn_id = as.character(espn_athlete_id)
  )])
  pos_map <- merge(cw_map, p_stats, by.x = "espn_id", by.y = "athlete_id", all.x = TRUE)
  setkey(pos_map, person_id)

  matched <- merge(matched, pos_map[, .(person_id, shooter_pos = detailed_pos)], by = "person_id", all.x = TRUE)
  matched[is.na(shooter_pos), shooter_pos := "SF"]
} else {
  matched[, shooter_pos := "SF"]
}

# Baseline league rim FG% across all matched rim shots (distance <= 4 ft)
rim_shots_all <- matched[shot_distance <= 4 & !is.na(defense_team_id)]
league_rim_fg_pct <- if (nrow(rim_shots_all) > 0) {
  mean(rim_shots_all$shot_result == "Made") * 100
} else {
  56.9
}
cat(sprintf(">>> Empirical League Rim Baseline FG%%: %.1f%%\n", league_rim_fg_pct))

# ------------------------------------------------------------------------------
# 4. VECTORIZED DEFENDER AGGREGATION
# ------------------------------------------------------------------------------
# Long format of defensive shots across all 5 defenders on court
matched_long <- rbindlist(list(
  matched[, .(game_id, shooter_pos, shot_distance, shot_result, defense_team_id, def_player = def_player_1)],
  matched[, .(game_id, shooter_pos, shot_distance, shot_result, defense_team_id, def_player = def_player_2)],
  matched[, .(game_id, shooter_pos, shot_distance, shot_result, defense_team_id, def_player = def_player_3)],
  matched[, .(game_id, shooter_pos, shot_distance, shot_result, defense_team_id, def_player = def_player_4)],
  matched[, .(game_id, shooter_pos, shot_distance, shot_result, defense_team_id, def_player = def_player_5)]
))
matched_long <- matched_long[!is.na(def_player)]

defender_shot_stats <- matched_long[, .(
  total_shots = .N,
  rim_shots   = sum(shot_distance <= 4, na.rm = TRUE),
  rim_made    = sum(shot_distance <= 4 & shot_result == "Made", na.rm = TRUE),
  pg_shots    = sum(shooter_pos == "PG", na.rm = TRUE),
  sg_shots    = sum(shooter_pos == "SG", na.rm = TRUE),
  sf_shots    = sum(shooter_pos == "SF", na.rm = TRUE),
  pf_shots    = sum(shooter_pos == "PF", na.rm = TRUE),
  c_shots     = sum(shooter_pos == "C", na.rm = TRUE),
  primary_team_id = as.character(names(which.max(table(defense_team_id))))
), by = .(def_player)]
setkey(defender_shot_stats, def_player)

# Aggregate defensive possessions per defender
poss_long <- rbindlist(list(
  poss[, .(defense_team_id, def_player = def_player_1)],
  poss[, .(defense_team_id, def_player = def_player_2)],
  poss[, .(defense_team_id, def_player = def_player_3)],
  poss[, .(defense_team_id, def_player = def_player_4)],
  poss[, .(defense_team_id, def_player = def_player_5)]
))
defender_poss <- poss_long[!is.na(def_player), .(total_poss = .N), by = .(def_player)]
setkey(defender_poss, def_player)

team_poss <- poss[, .(team_total_poss = .N), by = .(defense_team_id = as.character(defense_team_id))]
setkey(team_poss, defense_team_id)

team_rim <- matched[shot_distance <= 4, .(team_rim_shots = .N), by = .(defense_team_id = as.character(defense_team_id))]
setkey(team_rim, defense_team_id)

# ------------------------------------------------------------------------------
# 5. Shannon Entropy Function
# ------------------------------------------------------------------------------
calc_shannon_entropy <- function(p_dist) {
  p_dist <- p_dist[p_dist > 0]
  if (length(p_dist) <= 1) return(0)
  H <- -sum(p_dist * log(p_dist))
  H_max <- log(5) # 5 positions: PG, SG, SF, PF, C
  round((H / H_max) * 100, 1)
}

# ------------------------------------------------------------------------------
# 6. ASSEMBLE DEFENSIVE PROFILES
# ------------------------------------------------------------------------------
defensive_profiles <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pid <- as.character(p$player_id)

  # Check RAPM lookup
  hit <- if (!is.null(drapm_lookup)) drapm_lookup[drapm_lookup$player_id == pid, ] else NULL
  has_rapm_match <- !is.null(hit) && nrow(hit) == 1 && isTRUE(hit$rapm_matched)

  if (has_rapm_match) {
    d_rapm           <- round(hit$drapm, 2)
    d_rapm_low       <- isTRUE(hit$low_sample_flag)
    d_rapm_ambiguous <- isTRUE(hit$rapm_ambiguous)
    d_rapm_source    <- if (d_rapm_low) DRAPM_SOURCE_RIDGE_LOW else DRAPM_SOURCE_RIDGE
    wnba_pid         <- suppressWarnings(as.integer(hit$rapm_player_id))
  } else {
    d_rapm           <- 0.00
    d_rapm_low       <- TRUE
    d_rapm_ambiguous <- FALSE
    d_rapm_source    <- DRAPM_SOURCE_FALLBACK
    wnba_pid         <- NA_integer_
  }

  # Lookup defender stats in aggregated real data
  d_stats <- if (!is.na(wnba_pid)) defender_shot_stats[def_player == wnba_pid] else NULL
  has_real_stats <- !is.null(d_stats) && nrow(d_stats) == 1 && d_stats$total_shots > 0

  if (has_real_stats) {
    n_shots <- d_stats$total_shots
    n_rim   <- d_stats$rim_shots
    n_made  <- d_stats$rim_made

    # Rim DFG% Delta
    if (n_rim >= 10) {
      opp_rim_fg_pct <- (n_made / n_rim) * 100
      rim_dfg_delta  <- round(opp_rim_fg_pct - league_rim_fg_pct, 1)
      rim_source     <- "wehoop_shots_lineups"
      rim_sample     <- n_rim
    } else {
      rim_dfg_delta  <- 0.0
      rim_source     <- "insufficient_sample"
      rim_sample     <- n_rim
    }

    # Rim Deterrence Index: On vs Off opponent rim attempt frequency
    d_poss_row <- defender_poss[def_player == wnba_pid]
    n_on_poss <- if (nrow(d_poss_row) > 0) d_poss_row$total_poss else 0

    tm_id <- d_stats$primary_team_id
    tm_poss_row <- team_poss[defense_team_id == tm_id]
    tm_rim_row <- team_rim[defense_team_id == tm_id]

    n_tm_poss <- if (nrow(tm_poss_row) > 0) tm_poss_row$team_total_poss else 0
    n_tm_rim  <- if (nrow(tm_rim_row) > 0) tm_rim_row$team_rim_shots else 0

    n_off_poss <- max(0, n_tm_poss - n_on_poss)
    n_off_rim  <- max(0, n_tm_rim - n_rim)

    rim_freq_on  <- if (n_on_poss > 0) (n_rim / n_on_poss) * 100 else 0
    rim_freq_off <- if (n_off_poss > 0) (n_off_rim / n_off_poss) * 100 else rim_freq_on
    rim_deterrence_index <- round(pmax(0, rim_freq_off - rim_freq_on), 1)

    # Positional Matchup Distribution from real defended shots
    if (n_shots >= 20) {
      pg_cnt <- d_stats$pg_shots
      sg_cnt <- d_stats$sg_shots
      sf_cnt <- d_stats$sf_shots
      pf_cnt <- d_stats$pf_shots
      c_cnt  <- d_stats$c_shots
      tot_cnt <- pg_cnt + sg_cnt + sf_cnt + pf_cnt + c_cnt

      m_pg_pct <- round((pg_cnt / tot_cnt) * 100, 1)
      m_sg_pct <- round((sg_cnt / tot_cnt) * 100, 1)
      m_sf_pct <- round((sf_cnt / tot_cnt) * 100, 1)
      m_pf_pct <- round((pf_cnt / tot_cnt) * 100, 1)
      m_c_pct  <- round(100 - (m_pg_pct + m_sg_pct + m_sf_pct + m_pf_pct), 1)

      matchup_source <- "wehoop_possession_lineups"
      matchup_sample <- n_shots
    } else {
      # Fallback to positional baseline prior
      if (pos == "G") {
        m_pg_pct <- 42.0; m_sg_pct <- 38.0; m_sf_pct <- 14.0; m_pf_pct <- 5.0; m_c_pct <- 1.0
      } else if (pos == "F") {
        m_pg_pct <- 12.0; m_sg_pct <- 22.0; m_sf_pct <- 35.0; m_pf_pct <- 22.0; m_c_pct <- 9.0
      } else {
        m_pg_pct <- 3.0; m_sg_pct <- 6.0; m_sf_pct <- 13.0; m_pf_pct <- 28.0; m_c_pct <- 50.0
      }
      matchup_source <- "position_prior_fallback"
      matchup_sample <- n_shots
    }

  } else {
    # Unmatched / no historical possessions
    rim_dfg_delta        <- 0.0
    rim_deterrence_index <- 0.0
    rim_source           <- "position_prior_fallback"
    rim_sample           <- 0L

    if (pos == "G") {
      m_pg_pct <- 42.0; m_sg_pct <- 38.0; m_sf_pct <- 14.0; m_pf_pct <- 5.0; m_c_pct <- 1.0
    } else if (pos == "F") {
      m_pg_pct <- 12.0; m_sg_pct <- 22.0; m_sf_pct <- 35.0; m_pf_pct <- 22.0; m_c_pct <- 9.0
    } else {
      m_pg_pct <- 3.0; m_sg_pct <- 6.0; m_sf_pct <- 13.0; m_pf_pct <- 28.0; m_c_pct <- 50.0
    }
    matchup_source <- "position_prior_fallback"
    matchup_sample <- 0L
  }

  dist_vector <- c(m_pg_pct, m_sg_pct, m_sf_pct, m_pf_pct, m_c_pct) / 100
  versatility_score <- calc_shannon_entropy(dist_vector)

  # Defensive Role Archetype derived strictly from real metrics
  defensive_role <- if (pos == "C" && rim_dfg_delta <= -4.0) "Primary Rim Anchor" else
                    if (versatility_score >= 85.0) "1-Through-5 Switch Eraser" else
                    if (pos == "F" && rim_dfg_delta <= -2.0) "Roaming Weakside Disrupter" else
                    if (pos == "G" && d_rapm >= 0.5) "Point-of-Attack Stopper" else
                    if (pos == "G") "Perimeter Chaser & Stunter" else
                    "Positional Frontcourt Connector"

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
    dRapm = d_rapm,
    dRapmSource = d_rapm_source,
    dRapmLowSample = d_rapm_low,
    dRapmAmbiguous = d_rapm_ambiguous,
    rimDefenseSource = rim_source,
    rimDefenseSample = rim_sample,
    matchupSource = matchup_source,
    matchupSample = matchup_sample,
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
