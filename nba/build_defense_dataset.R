# ==============================================================================
# build_defense_dataset.R
# Feature 5: Defensive Versatility & Coverage Matrix
# Quantifies:
# 1. Positional Versatility (Shannon Entropy across 5 positions: PG, SG, SF, PF, C)
# 2. Rim Deterrence vs Rim Contest Residual (Opponent FG% delta at rim)
# 3. Defensive Role Archetype (Anchor, POA Stopper, Roaming Disrupter, Switch Wing, Chaser)
# 4. Point-of-Attack Screen Navigation and Blow-By Prevention Score
#
# All affine clamp heuristics, synthetic matchup formulas, and hardcoded player
# overrides have been eliminated (Issue #82, following WNBA Issue #144 precedent).
# All metrics are derived from empirical PBP events (cache/nba_pbp_<CURRENT_SEASON>.rds),
# regular-season box scores (cache/nba_player_box_<CURRENT_SEASON>.rds), and ridge RAPM
# (cache/rapm_ratings.rds).
#
# Exports defensive_metrics.json for Next.js web application.
#
# Data window (front-office#109):
#   Seasons: the current season (CURRENT_SEASON in config.R, labelled via
#     season_label(); 2027 = 2026-27): cache/nba_pbp_<CURRENT_SEASON>.rds and
#     cache/nba_player_box_<CURRENT_SEASON>.rds (the script stops if either is
#     missing; no fallback to another season, front-office#191). The JSON exports
#     season, throughDate (latest game_date in the play-by-play input), generatedAt
#     and rapmSeason.
#     cache/rapm_ratings.rds (optional; without it, or for a player not found in
#     it, dRAPM is a fixed value by position) is NOT current-season: possession
#     data for the in-progress season is not published, so rapm_engine.R fits the
#     last completed season. Its season is read from the file's season_label column
#     and exported as rapmSeason (never presented as current-season data).
#     The player list comes from the 2026-27 season projections. No
#     season-type filter is applied to the play-by-play or box scores.
#   Filters: box-score rows with more than 0 minutes. Matchup events are plays whose
#     text contains "block" or "steal", and "Shooting Foul" plays paired with the
#     next play's player as the shooter; an event counts only when the opponent's
#     position is known. Rim and point-of-attack scores are weighted formulas over
#     those rates, not measured opponent shooting.
#   Minimum sample: none. Every projected player is listed. Per-36 rates use at least
#     40 minutes (eff_min). No imputation (front-office#191): a player with no
#     current-season box row has every box-derived metric (rim, POA, role) published
#     as null, a player with no observed matchup events (or no box row) has null
#     matchupDist/versatilityScore, and a player absent from the RAPM fit has null
#     dRapm (no position constants, no projection stand-ins). Role and POA also
#     require dRapm / their inputs, so they are null when any input is null. Where
#     matchup events exist, shares add 15 position-based prior events (smoothing).
#     Player DNA reads this file, so both boards null the same players.
#   Known issues: #82 (formula proxies, role thresholds).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [DEFENSIVE METRICS] Initializing Defensive Versatility & Coverage Engine...\n")

# Load existing player projections
proj_players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS  # config.R
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for %s season.\n", nrow(players_df), season_label()))

# Load empirical data caches
box_file <- current_season_cache("player_box")  # stop()s if missing
pbp_file <- current_season_cache("pbp")          # stop()s if missing
rapm_file <- file.path(CACHE_DIR, "rapm_ratings.rds")

has_rapm <- file.exists(rapm_file)

box_df <- readRDS(box_file)
pbp <- readRDS(pbp_file)
rapm_df <- if (has_rapm) readRDS(rapm_file) else NULL
through_date <- data_through_date(pbp, box_df)
cat(sprintf(">>> Season %s, data through %s (earlier of play-by-play and player box).\n", season_label(), through_date))
rapm_season <- if (!is.null(rapm_df) && "season_label" %in% names(rapm_df)) {
  u <- unique(as.character(rapm_df$season_label)); if (length(u) == 1L) u else NA_character_
} else NA_character_
if (!is.null(rapm_df) && !identical(rapm_season, season_label())) {
  cat(sprintf(">>> [NOTE] rapm_ratings.rds covers %s, not %s; dRAPM is published with rapmSeason so it is not read as current-season.\n",
              ifelse(is.na(rapm_season), "an unknown season", rapm_season), season_label()))
}

# Clean name helper for RAPM alignment
clean_name <- function(x) {
  x <- gsub("[éèêë]", "e", x, ignore.case = TRUE)
  x <- gsub("[áàâä]", "a", x, ignore.case = TRUE)
  x <- gsub("[íìîï]", "i", x, ignore.case = TRUE)
  x <- gsub("[óòôö]", "o", x, ignore.case = TRUE)
  x <- gsub("[úùûü]", "u", x, ignore.case = TRUE)
  x <- gsub("[ćč]", "c", x, ignore.case = TRUE)
  x <- gsub("[ñ]", "n", x, ignore.case = TRUE)
  x <- gsub("[š]", "s", x, ignore.case = TRUE)
  x <- gsub("[ž]", "z", x, ignore.case = TRUE)
  x <- gsub("\\s+(jr\\.?|sr\\.?|ii|iii|iv)$", "", x, ignore.case = TRUE)
  tolower(gsub("[^a-z]", "", x))
}

rapm_lookup <- if (!is.null(rapm_df)) {
  rapm_clean <- rapm_df %>%
    mutate(c_name = clean_name(player_name)) %>%
    distinct(c_name, .keep_all = TRUE)
  setNames(rapm_clean$drapm, rapm_clean$c_name)
} else {
  numeric(0)
}

# ------------------------------------------------------------------------------
# 1. Shooter Detailed Position Mapping (PG, SG, SF, PF, C) from Box Scores
# ------------------------------------------------------------------------------
p_stats <- box_df %>%
  filter(!is.na(minutes), as.numeric(minutes) > 0) %>%
  group_by(athlete_id = as.character(athlete_id)) %>%
  summarise(
    pos = names(which.max(table(athlete_position_abbreviation))),
    games = n(),
    ast_pg = sum(as.numeric(assists), na.rm = TRUE) / games,
    reb_pg = sum(as.numeric(rebounds), na.rm = TRUE) / games,
    .groups = "drop"
  ) %>%
  mutate(
    detailed_pos = case_when(
      pos == "G" & ast_pg >= 3.8 ~ "PG",
      pos == "G" ~ "SG",
      pos == "F" & reb_pg >= 5.8 ~ "PF",
      pos == "F" ~ "SF",
      TRUE ~ "C"
    )
  )

pos_map <- setNames(p_stats$detailed_pos, p_stats$athlete_id)

# ------------------------------------------------------------------------------
# 2. Extract Empirical Defensive Events from PBP
# ------------------------------------------------------------------------------
# Blocks: athlete_id_2 (defender) vs athlete_id_1 (shooter)
blk_events <- pbp %>%
  filter(grepl("block", text, ignore.case = TRUE), !is.na(athlete_id_2), !is.na(athlete_id_1)) %>%
  transmute(
    def_id = as.character(athlete_id_2),
    opp_id = as.character(athlete_id_1)
  )

# Steals: athlete_id_2 (defender) vs athlete_id_1 (ballhandler)
stl_events <- pbp %>%
  filter(grepl("steal", text, ignore.case = TRUE), !is.na(athlete_id_2), !is.na(athlete_id_1)) %>%
  transmute(
    def_id = as.character(athlete_id_2),
    opp_id = as.character(athlete_id_1)
  )

# Shooting fouls: athlete_id_1 is defender committing foul, lead athlete_id_1 is shooter
pbp_lead <- lead(pbp$athlete_id_1)
foul_events <- pbp %>%
  mutate(next_athlete = pbp_lead) %>%
  filter(grepl("Shooting Foul", type_text), !is.na(athlete_id_1), !is.na(next_athlete)) %>%
  transmute(
    def_id = as.character(athlete_id_1),
    opp_id = as.character(next_athlete)
  )

all_def_events <- bind_rows(blk_events, stl_events, foul_events) %>%
  mutate(opp_pos = pos_map[opp_id]) %>%
  filter(!is.na(opp_pos))

cat(sprintf(">>> Processed %d empirical defensive interactions across PBP.\n", nrow(all_def_events)))

def_matchups <- all_def_events %>%
  group_by(def_id) %>%
  summarise(
    n_events = n(),
    n_pg = sum(opp_pos == "PG"),
    n_sg = sum(opp_pos == "SG"),
    n_sf = sum(opp_pos == "SF"),
    n_pf = sum(opp_pos == "PF"),
    n_c  = sum(opp_pos == "C"),
    .groups = "drop"
  )

# ------------------------------------------------------------------------------
# 3. Defensive Box Score Rates
# ------------------------------------------------------------------------------
box_def <- box_df %>%
  filter(!is.na(minutes), as.numeric(minutes) > 0) %>%
  group_by(athlete_id = as.character(athlete_id)) %>%
  summarise(
    min_tot = sum(as.numeric(minutes), na.rm = TRUE),
    blk_tot = sum(as.numeric(blocks), na.rm = TRUE),
    stl_tot = sum(as.numeric(steals), na.rm = TRUE),
    dreb_tot = sum(as.numeric(defensive_rebounds), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    eff_min = pmax(min_tot, 40.0),
    blk_per36 = (blk_tot / eff_min) * 36,
    stl_per36 = (stl_tot / eff_min) * 36,
    dreb_per36 = (dreb_tot / eff_min) * 36
  )

box_def_map <- setNames(split(box_def, box_def$athlete_id), box_def$athlete_id)
matchup_map <- setNames(split(def_matchups, def_matchups$def_id), def_matchups$def_id)

max_blk <- max(box_def$blk_per36, na.rm = TRUE)
if (is.na(max_blk) || max_blk == 0) max_blk <- 4.5
max_stl <- max(box_def$stl_per36, na.rm = TRUE)
if (is.na(max_stl) || max_stl == 0) max_stl <- 3.5

# Shannon entropy function across positional match-up fractions
calc_shannon_entropy <- function(p_dist) {
  p_dist <- p_dist[p_dist > 0]
  if (length(p_dist) <= 1) return(0)
  H <- -sum(p_dist * log(p_dist))
  H_max <- log(5) # 5 positions
  score <- (H / H_max) * 100
  return(round(score, 1))
}

# Empirical positional priors for matchup smoothing (15 pseudo-counts)
prior_guard   <- c(pg = 6.0, sg = 6.0, sf = 2.0, pf = 0.8, c = 0.2)
prior_forward <- c(pg = 2.5, sg = 3.5, sf = 5.0, pf = 3.0, c = 1.0)
prior_center  <- c(pg = 0.8, sg = 1.2, sf = 3.0, pf = 4.0, c = 6.0)

defensive_profiles <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pid <- as.character(p$player_id)
  c_name <- clean_name(name)

  is_guard <- pos == "G"
  is_center <- pos == "C"
  is_forward <- pos == "F"

  # Real dRAPM from ridge regression
  # Not in the RAPM fit -> NA (published as null); never a position constant.
  d_rapm <- if (c_name %in% names(rapm_lookup)) round(unname(rapm_lookup[c_name]), 2) else NA_real_

  # Defensive box stats
  b_stat <- box_def_map[[pid]]
  # No current-season box row -> NA (published as null); never a projection stand-in.
  has_box_row <- !is.null(b_stat)
  blk_per36 <- if (has_box_row) b_stat$blk_per36 else NA_real_
  stl_per36 <- if (has_box_row) b_stat$stl_per36 else NA_real_
  dreb_per36 <- if (has_box_row) b_stat$dreb_per36 else NA_real_

  # Matchup distribution derived from empirical PBP events with Bayes smoothing
  prior <- if (is_guard) prior_guard else if (is_forward) prior_forward else prior_center
  m_row <- matchup_map[[pid]]

  obs_pg <- if (!is.null(m_row)) m_row$n_pg else 0
  obs_sg <- if (!is.null(m_row)) m_row$n_sg else 0
  obs_sf <- if (!is.null(m_row)) m_row$n_sf else 0
  obs_pf <- if (!is.null(m_row)) m_row$n_pf else 0
  obs_c  <- if (!is.null(m_row)) m_row$n_c  else 0

  # Matchup shares need observed events AND a box row: with neither, the 15-event
  # positional prior would be the whole published value, so it is published as null.
  has_matchups <- has_box_row && !is.null(m_row)

  smooth_pg <- obs_pg + prior["pg"]
  smooth_sg <- obs_sg + prior["sg"]
  smooth_sf <- obs_sf + prior["sf"]
  smooth_pf <- obs_pf + prior["pf"]
  smooth_c  <- obs_c  + prior["c"]

  total_m <- smooth_pg + smooth_sg + smooth_sf + smooth_pf + smooth_c
  m_pg_pct <- round((smooth_pg / total_m) * 100, 1)
  m_sg_pct <- round((smooth_sg / total_m) * 100, 1)
  m_sf_pct <- round((smooth_sf / total_m) * 100, 1)
  m_pf_pct <- round((smooth_pf / total_m) * 100, 1)
  m_c_pct  <- round(100 - (m_pg_pct + m_sg_pct + m_sf_pct + m_pf_pct), 1)

  dist_vector <- c(m_pg_pct, m_sg_pct, m_sf_pct, m_pf_pct, m_c_pct) / 100
  versatility_score <- if (has_matchups) calc_shannon_entropy(dist_vector) else NA_real_
  if (!has_matchups) m_pg_pct <- m_sg_pct <- m_sf_pct <- m_pf_pct <- m_c_pct <- NA_real_

  # Rim contest metrics derived empirically from blk_per36, dreb_per36, and frontcourt presence
  # (NA whenever any input is NA: no box row, or no observed matchups)
  rim_presence <- (m_c_pct + m_pf_pct) / 100
  rim_factor <- (blk_per36 / max_blk) * 0.65 + (pmin(dreb_per36, 12.0) / 12.0) * 0.20 + rim_presence * 0.15
  rim_dfg_delta <- round(2.2 - rim_factor * 16.5, 1)
  rim_deterrence_index <- round(pmax(0.1, rim_factor * 10.0), 1)

  # POA Screen Navigation derived empirically from steals, perimeter matchups, and dRAPM
  perim_share <- (m_pg_pct + m_sg_pct) / 100
  poa_factor <- (stl_per36 / max_stl) * 0.45 + perim_share * 0.35 + (pmax(0, d_rapm + 1.0) / 6.0) * 0.20
  poa_navigation <- round(45.0 + poa_factor * 52.0, 1)

  # Defensive Role Archetype dynamically assigned from empirical profile
  role_inputs <- c(rim_dfg_delta, poa_navigation, versatility_score, dreb_per36)
  defensive_role <- if (anyNA(role_inputs)) NA_character_ else
                    if (is_center && rim_dfg_delta <= -6.0) "Primary Rim Anchor" else
                    if (is_guard && poa_navigation >= 75.0) "Point-of-Attack Stopper" else
                    if (versatility_score >= 82.0) "1-Through-5 Switch Eraser" else
                    if (is_forward && dreb_per36 >= 5.5) "Roaming Weakside Disrupter" else
                    if (is_guard) "Perimeter Chaser & Stunter" else
                    "Positional Frontcourt Connector"

  defensive_profiles[[i]] <- list(
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
    matchupDist = if (has_matchups) list(
      pgPct = m_pg_pct,
      sgPct = m_sg_pct,
      sfPct = m_sf_pct,
      pfPct = m_pf_pct,
      cPct = m_c_pct
    ) else NA
  )
}

# ------------------------------------------------------------------------------
# Export JSON & RDS
# ------------------------------------------------------------------------------
output_json <- WEB_JSON_DEFENSIVE_METRICS  # config.R
defense_payload <- list(
  season = season_label(),
  throughDate = through_date,
  generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  rapmSeason = if (is.na(rapm_season)) NULL else rapm_season,
  profiles = defensive_profiles
)
jsonlite::write_json(defense_payload, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf(">>> [SUCCESS] Wrote %d Defensive profiles to '%s'.\n", length(defensive_profiles), output_json))

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(defensive_profiles, "cache/defensive_metrics.rds")
cat(">>> [SUCCESS] Cached RDS in 'cache/defensive_metrics.rds'.\n")
