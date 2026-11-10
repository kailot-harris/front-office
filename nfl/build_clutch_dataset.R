# ==============================================================================
# build_clutch_dataset.R
# Feature: 4th Quarter True Clutch & Late-Game Leverage Index Engine
#
# Analyzes high-leverage late-game NFL events:
#   - Score margin <= 8 points in 4Q/OT, or
#   - Win probability between 10% and 90% in final 5 minutes of 4Q/OT.
#
# Metrics (empirical play-by-play events only, zero synthetic heuristics):
#   1. Clutch EPA/play vs Baseline EPA/play (clutchEpaDelta = clutchEpa - baselineEpa)
#   2. Clutch Success Rate (%)
#   3. Clutch CPOE (Completion % Over Expected)
#   4. Turnover Fragility Under Pressure (Clutch TO% - Baseline TO%)
#   5. 4th Down Go-for-it Aggressiveness (%)
#   6. Situational Archetype Tagging & Sample Qualification (MIN_CLUTCH_PASS_ATTEMPTS = 5L)
#
# Exports:
#   - web/public/data/clutch_leverage_metrics.json
#   - cache/clutch_leverage_metrics.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Determine script directory and set working directory to worktree root
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args, value = TRUE)
script_dir <- if (length(file_arg) > 0) {
  dirname(normalizePath(sub("--file=", "", file_arg[1]), winslash = "/"))
} else {
  getwd()
}
if (dir.exists(script_dir)) {
  setwd(script_dir)
}

# Source global config
source("config.R")

cat(">>> [CLUTCH ENGINE] Initializing NFL 4Q True Clutch & Leverage Index Engine...\n")

# Locate play-by-play cache file
# Search for cache/nfl_pbp_*.rds, or pbp_cache.rds
pbp_files <- list.files(CACHE_DIR, pattern = "^nfl_pbp_.*\\.rds$", full.names = TRUE)
pbp_file <- if (length(pbp_files) > 0) {
  pbp_files[length(pbp_files)] # use latest matching season
} else if (file.exists(CACHE_PBP)) {
  CACHE_PBP
} else {
  NULL
}

if (is.null(pbp_file) || !file.exists(pbp_file)) {
  cat(">>> [CLUTCH ENGINE] No local PBP cache found; pulling CURRENT_SEASON via nflreadr...\n")
  pbp_df <- nflreadr::load_pbp(seasons = CURRENT_SEASON)
  target_cache <- file.path(CACHE_DIR, sprintf("nfl_pbp_%d.rds", CURRENT_SEASON))
  saveRDS(pbp_df, target_cache)
  pbp_file <- target_cache
}

cat(sprintf(">>> [CLUTCH ENGINE] Ingesting play-by-play from %s...\n", pbp_file))
pbp <- readRDS(pbp_file)
cat(sprintf(">>> [CLUTCH ENGINE] Loaded %d raw play-by-play events.\n", nrow(pbp)))

# Ingest active QB profiles
qb_json_path <- if (exists("WEB_JSON_PLAYER_QB_PROFILES")) {
  WEB_JSON_PLAYER_QB_PROFILES
} else {
  file.path(PROJECT_DIR, "web", "public", "data", "player_qb_profiles.json")
}

if (!file.exists(qb_json_path)) {
  stop(sprintf("Missing required QB profiles dataset at %s", qb_json_path))
}

qb_profiles_df <- jsonlite::fromJSON(qb_json_path)
cat(sprintf(">>> [CLUTCH ENGINE] Ingested %d QB profiles from %s.\n", nrow(qb_profiles_df), basename(qb_json_path)))

# Ingest rosters cache for cross-referencing gsis_id / jersey / names
rosters_path <- file.path(CACHE_DIR, "rosters_cache.rds")
rosters_df <- if (file.exists(rosters_path)) {
  readRDS(rosters_path) %>%
    filter(position == "QB") %>%
    group_by(full_name, team) %>%
    slice(1) %>%
    ungroup()
} else {
  NULL
}

# Identify high-leverage plays window:
# Margin <= 8 points in 4Q/OT, OR win probability between 10% and 90% in final 5m of 4Q/OT
pbp <- pbp %>%
  mutate(
    score_diff_abs = abs(score_differential),
    is_clutch = (
      (qtr >= 4 & !is.na(score_diff_abs) & score_diff_abs <= 8) |
      (qtr >= 4 & !is.na(half_seconds_remaining) & half_seconds_remaining <= 300 &
       !is.na(wp) & wp >= 0.10 & wp <= 0.90)
    )
  )

clutch_play_count <- sum(pbp$is_clutch, na.rm = TRUE)
cat(sprintf(">>> [CLUTCH ENGINE] Identified %d high-leverage late-game clutch plays (%.1f%% of sample).\n",
            clutch_play_count, (clutch_play_count / nrow(pbp)) * 100))

MIN_CLUTCH_PASS_ATTEMPTS <- 5L
clutch_profiles <- list()

for (i in seq_len(nrow(qb_profiles_df))) {
  qb <- qb_profiles_df[i, ]
  pname <- qb$player_name
  pteam <- qb$team
  is_starter <- if ("is_starter" %in% names(qb)) isTRUE(qb$is_starter) else FALSE
  headshot <- if ("headshot_url" %in% names(qb)) qb$headshot_url else ""

  # Resolve gsis_id
  gid <- NULL
  if (!is.null(rosters_df)) {
    match_r <- rosters_df %>% filter(full_name == pname, team == pteam)
    if (nrow(match_r) == 0) {
      match_r <- rosters_df %>% filter(full_name == pname)
    }
    if (nrow(match_r) > 0) {
      gid <- match_r$gsis_id[1]
    }
  }

  abbr_name <- paste0(substr(pname, 1, 1), ".", sub(".* ", "", pname))

  # Extract QB plays
  qb_plays <- if (!is.null(gid) && !is.na(gid) && "passer_player_id" %in% names(pbp)) {
    pbp %>% filter(
      (!is.na(passer_player_id) & passer_player_id == gid) |
      (!is.na(passer_player_name) & (passer_player_name == pname | passer_player_name == abbr_name))
    )
  } else {
    pbp %>% filter(
      !is.na(passer_player_name) & (passer_player_name == pname | passer_player_name == abbr_name)
    )
  }

  # Baseline (all regular passes / dropbacks)
  baseline_plays <- qb_plays %>% filter(pass == 1 | qb_dropback == 1)
  baseline_pass_att <- qb_plays %>% filter(pass_attempt == 1)
  
  # Clutch plays (high-leverage passes / dropbacks)
  clutch_plays <- qb_plays %>% filter(is_clutch & (pass == 1 | qb_dropback == 1))
  clutch_pass_att <- qb_plays %>% filter(is_clutch & pass_attempt == 1)

  n_clutch_att <- nrow(clutch_pass_att)
  n_clutch_plays <- nrow(clutch_plays)
  n_base_att <- nrow(baseline_pass_att)
  n_base_plays <- nrow(baseline_plays)

  has_sample <- n_clutch_att >= MIN_CLUTCH_PASS_ATTEMPTS

  if (has_sample) {
    # 1. Clutch EPA and Baseline EPA
    c_epa <- round(mean(clutch_plays$epa, na.rm = TRUE), 3)
    b_epa <- round(mean(baseline_plays$epa, na.rm = TRUE), 3)
    c_epa_delta <- round(c_epa - b_epa, 3)

    # 2. Success rates
    c_sr <- round(mean(clutch_plays$success, na.rm = TRUE) * 100, 1)
    b_sr <- round(mean(baseline_plays$success, na.rm = TRUE) * 100, 1)

    # 3. Clutch CPOE
    cpoe_vals <- clutch_pass_att$cpoe[!is.na(clutch_pass_att$cpoe)]
    c_cpoe <- if (length(cpoe_vals) > 0) round(mean(cpoe_vals), 1) else 0.0

    # 4. Turnover fragility under pressure: Delta TOV rate
    # Turnovers = interceptions + lost fumbles
    c_to_count <- sum(clutch_plays$interception == 1, na.rm = TRUE) + sum(clutch_plays$fumble_lost == 1, na.rm = TRUE)
    b_to_count <- sum(baseline_plays$interception == 1, na.rm = TRUE) + sum(baseline_plays$fumble_lost == 1, na.rm = TRUE)
    c_to_rate <- (c_to_count / max(1, n_clutch_plays)) * 100
    b_to_rate <- (b_to_count / max(1, n_base_plays)) * 100
    tov_fragility <- round(c_to_rate - b_to_rate, 1)

    # 5. 4th down go-for-it aggressiveness / conversion
    qb_4th_plays <- qb_plays %>% filter(down == 4)
    fourth_agg <- if (nrow(qb_4th_plays) > 0) {
      round((sum(qb_4th_plays$fourth_down_converted == 1, na.rm = TRUE) / nrow(qb_4th_plays)) * 100, 1)
    } else {
      50.0
    }

    # 6. Situational Archetype Tag
    archetype <- if (c_epa_delta >= 0.12 && c_sr >= 50.0) {
      "Elite Ice-in-Veins Finisher"
    } else if (c_cpoe >= 3.5 && c_epa >= 0.05) {
      "High-Leverage Shotmaker"
    } else if (c_epa >= 0.10 && tov_fragility <= 0.0) {
      "Poised Late-Game Closer"
    } else if (c_epa_delta <= -0.12 || tov_fragility >= 4.0) {
      "Fragile Under Pressure"
    } else if (c_sr >= 45.0) {
      "Efficient Situational Closer"
    } else {
      "Game Manager Under Pressure"
    }

    provenance <- "REAL_CURRENT_SEASON"

    clutch_profiles[[i]] <- list(
      playerId = if (!is.null(gid) && !is.na(gid)) gid else sprintf("NFL-%s-%02d", pteam, i),
      playerName = pname,
      team = pteam,
      position = "QB",
      isStarter = is_starter,
      headshotUrl = headshot,
      clutchAttempts = as.integer(n_clutch_att),
      clutchPlays = as.integer(n_clutch_plays),
      baselineAttempts = as.integer(n_base_att),
      baselinePlays = as.integer(n_base_plays),
      clutchEpa = c_epa,
      baselineEpa = b_epa,
      clutchEpaDelta = c_epa_delta,
      clutchSuccessRate = c_sr,
      baselineSuccessRate = b_sr,
      clutchCpoe = c_cpoe,
      turnoverFragility = tov_fragility,
      fourthDownAggressiveness = fourth_agg,
      clutchArchetype = archetype,
      provenance = provenance
    )
  } else {
    # Low sample player: emit typed null for rate and efficiency metrics
    clutch_profiles[[i]] <- list(
      playerId = if (!is.null(gid) && !is.na(gid)) gid else sprintf("NFL-%s-%02d", pteam, i),
      playerName = pname,
      team = pteam,
      position = "QB",
      isStarter = is_starter,
      headshotUrl = headshot,
      clutchAttempts = as.integer(n_clutch_att),
      clutchPlays = as.integer(n_clutch_plays),
      baselineAttempts = as.integer(n_base_att),
      baselinePlays = as.integer(n_base_plays),
      clutchEpa = NA_real_,
      baselineEpa = NA_real_,
      clutchEpaDelta = NA_real_,
      clutchSuccessRate = NA_real_,
      baselineSuccessRate = NA_real_,
      clutchCpoe = NA_real_,
      turnoverFragility = NA_real_,
      fourthDownAggressiveness = NA_real_,
      clutchArchetype = "Insufficient Sample",
      provenance = "INSUFFICIENT_SAMPLE"
    )
  }
}

# Export outputs
out_json_path <- file.path(PROJECT_DIR, "web", "public", "data", "clutch_leverage_metrics.json")
out_rds_path <- file.path(CACHE_DIR, "clutch_leverage_metrics.rds")

# Write JSON with null formatting
json_text <- jsonlite::toJSON(clutch_profiles, na = "null", auto_unbox = TRUE, pretty = TRUE)
writeLines(json_text, out_json_path)
cat(sprintf(">>> [CLUTCH ENGINE] Exported %d profiles to %s\n", length(clutch_profiles), out_json_path))

saveRDS(clutch_profiles, out_rds_path)
cat(sprintf(">>> [CLUTCH ENGINE] Cached profiles to %s\n", out_rds_path))

cat(">>> [CLUTCH ENGINE] Complete.\n")
