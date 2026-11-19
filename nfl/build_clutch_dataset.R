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
#   5. 4th Down Conversion Rate (%)
#   6. Situational Archetype Tagging & Sample Qualification (MIN_CLUTCH_PASS_ATTEMPTS = 20L)
#
# Exports:
#   - web/public/data/clutch_leverage_metrics.json
#   - cache/clutch_leverage_metrics.rds
#
# Data window (front-office#109)
#   Seasons: play-by-play from the last cache/nfl_pbp_*.rds by file name; if
#     none, CACHE_PBP (cache/pbp_cache.rds); if neither, CURRENT_SEASON
#     downloaded with nflreadr. Whatever file is read, only rows with
#     season == CURRENT_SEASON are kept (so a multi-season cache such as
#     pbp_cache.rds can never mix seasons); if no rows for CURRENT_SEASON
#     remain, the build stops without writing anything. Every profile carries
#     the season and the latest week found in the data (season, throughWeek).
#     No season-type filter: playoff games count if present.
#   Filters: a clutch play is in the 4th quarter or overtime and either has a
#     score margin of 8 or less, or comes in the last 5 minutes with win
#     probability from 10% to 90%. QBs come from player_qb_profiles.json, and
#     their plays match passer_player_id / passer_player_name plus QB scrambles
#     (qb_scramble == 1) matched via rusher_player_id / rusher_player_name
#     (NFL_analytics#168).
#   Minimum sample: MIN_CLUTCH_PASS_ATTEMPTS (20 clutch pass attempts; was 5
#     before #80). QBs below it stay in the output with their attempt counts
#     and empty metrics, marked "Insufficient Sample", and get no archetype.
#     The value is exported on every profile (minClutchAttempts) so the page
#     states the threshold actually used.
#   Counts: clutchAttempts / baselineAttempts count pass_attempt == 1 rows
#     (passes, sacks and spikes; used for sample qualification and CPOE);
#     clutchPlays / baselinePlays count pass == 1 | qb_dropback == 1 |
#     qb_scramble == 1 rows (passes, sacks and scrambles, but not spikes).
#     Because scrambles have pass_attempt == 0, plays can exceed attempts.
#   4th down metric: fourthDownConversionRate computes converted / total 4th-down
#     QB plays and emits NA_real_ (JSON null) when 0 4th-down plays exist.
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

# ------------------------------------------------------------------------------
# Pure helper functions (extracted for unit testing via load_ast_symbols)
# ------------------------------------------------------------------------------

is_flag_one <- function(df, col) {
  if (col %in% names(df)) !is.na(df[[col]]) & df[[col]] == 1 else rep(FALSE, nrow(df))
}

add_clutch_flag <- function(pbp) {
  score_diff_abs <- abs(pbp$score_differential)
  qtr_ge_4 <- !is.na(pbp$qtr) & pbp$qtr >= 4
  pbp$score_diff_abs <- score_diff_abs
  pbp$is_clutch <- (
    (qtr_ge_4 & !is.na(score_diff_abs) & score_diff_abs <= 8) |
    (qtr_ge_4 & !is.na(pbp$half_seconds_remaining) & pbp$half_seconds_remaining <= 300 &
     !is.na(pbp$wp) & pbp$wp >= 0.10 & pbp$wp <= 0.90)
  )
  pbp
}

extract_qb_clutch_plays <- function(pbp, pname, gid = NULL) {
  abbr_name <- paste0(substr(pname, 1, 1), ".", sub(".* ", "", pname))
  has_gid <- !is.null(gid) && length(gid) == 1L && !is.na(gid) && nzchar(as.character(gid))
  n_rows <- nrow(pbp)
  if (n_rows == 0L) return(pbp)

  passer_match <- rep(FALSE, n_rows)
  has_passer_id <- "passer_player_id" %in% names(pbp)
  has_passer_name <- "passer_player_name" %in% names(pbp)
  if (has_gid && has_passer_id) {
    passer_match <- passer_match | (!is.na(pbp$passer_player_id) & pbp$passer_player_id == gid)
    if (has_passer_name) {
      passer_match <- passer_match | (
        is.na(pbp$passer_player_id) &
          !is.na(pbp$passer_player_name) &
          (pbp$passer_player_name == pname | pbp$passer_player_name == abbr_name)
      )
    }
  } else if (has_passer_name) {
    passer_match <- passer_match | (
      !is.na(pbp$passer_player_name) &
        (pbp$passer_player_name == pname | pbp$passer_player_name == abbr_name)
    )
  }

  # Include QB scrambles (passer_player_* are NA on scrambles; match rusher_player_*).
  scramble_match <- rep(FALSE, n_rows)
  if ("qb_scramble" %in% names(pbp)) {
    is_scramble <- !is.na(pbp$qb_scramble) & pbp$qb_scramble == 1
    rusher_match <- rep(FALSE, n_rows)
    has_rusher_id <- "rusher_player_id" %in% names(pbp)
    has_rusher_name <- "rusher_player_name" %in% names(pbp)
    if (has_gid && has_rusher_id) {
      rusher_match <- rusher_match | (!is.na(pbp$rusher_player_id) & pbp$rusher_player_id == gid)
      if (has_rusher_name) {
        rusher_match <- rusher_match | (
          is.na(pbp$rusher_player_id) &
            !is.na(pbp$rusher_player_name) &
            (pbp$rusher_player_name == pname | pbp$rusher_player_name == abbr_name)
        )
      }
    } else if (has_rusher_name) {
      rusher_match <- rusher_match | (
        !is.na(pbp$rusher_player_name) &
          (pbp$rusher_player_name == pname | pbp$rusher_player_name == abbr_name)
      )
    }
    scramble_match <- is_scramble & rusher_match
  }

  pbp[passer_match | scramble_match, , drop = FALSE]
}

compute_qb_clutch_profile <- function(
  pbp,
  pname,
  pteam,
  gid = NULL,
  is_starter = FALSE,
  headshot = "",
  season = CURRENT_SEASON,
  through_week = NA_integer_,
  min_clutch_attempts = 20L,
  fallback_player_id = sprintf("NFL-%s-00", pteam)
) {
  if (!"is_clutch" %in% names(pbp)) {
    pbp <- add_clutch_flag(pbp)
  }

  qb_plays <- extract_qb_clutch_plays(pbp, pname = pname, gid = gid)

  is_dropback <- is_flag_one(qb_plays, "pass") |
    is_flag_one(qb_plays, "qb_dropback") |
    is_flag_one(qb_plays, "qb_scramble")
  is_pass_att <- is_flag_one(qb_plays, "pass_attempt")
  is_clutch_row <- !is.na(qb_plays$is_clutch) & qb_plays$is_clutch

  # Baseline (all regular passes / dropbacks, including QB scrambles)
  baseline_plays <- qb_plays[is_dropback, , drop = FALSE]
  baseline_pass_att <- qb_plays[is_pass_att, , drop = FALSE]

  # Clutch plays (high-leverage passes / dropbacks, including QB scrambles)
  clutch_plays <- qb_plays[is_clutch_row & is_dropback, , drop = FALSE]
  clutch_pass_att <- qb_plays[is_clutch_row & is_pass_att, , drop = FALSE]

  n_clutch_att <- nrow(clutch_pass_att)
  n_clutch_plays <- nrow(clutch_plays)
  n_base_att <- nrow(baseline_pass_att)
  n_base_plays <- nrow(baseline_plays)

  player_id <- if (!is.null(gid) && length(gid) == 1L && !is.na(gid) && nzchar(as.character(gid))) {
    gid
  } else {
    fallback_player_id
  }

  has_sample <- n_clutch_att >= min_clutch_attempts

  if (has_sample) {
    # 1. Clutch EPA and Baseline EPA
    c_epa_vals <- clutch_plays$epa[!is.na(clutch_plays$epa)]
    b_epa_vals <- baseline_plays$epa[!is.na(baseline_plays$epa)]
    c_epa <- if (length(c_epa_vals) > 0L) round(mean(c_epa_vals), 3) else NA_real_
    b_epa <- if (length(b_epa_vals) > 0L) round(mean(b_epa_vals), 3) else NA_real_
    c_epa_delta <- if (!is.na(c_epa) && !is.na(b_epa)) round(c_epa - b_epa, 3) else NA_real_

    # 2. Success rates
    c_sr_vals <- clutch_plays$success[!is.na(clutch_plays$success)]
    b_sr_vals <- baseline_plays$success[!is.na(baseline_plays$success)]
    c_sr <- if (length(c_sr_vals) > 0L) round(mean(c_sr_vals) * 100, 1) else NA_real_
    b_sr <- if (length(b_sr_vals) > 0L) round(mean(b_sr_vals) * 100, 1) else NA_real_

    # 3. Clutch CPOE (pass attempts only; scrambles have pass_attempt == 0)
    cpoe_vals <- clutch_pass_att$cpoe[!is.na(clutch_pass_att$cpoe)]
    c_cpoe <- if (length(cpoe_vals) > 0L) round(mean(cpoe_vals), 1) else 0.0

    # 4. Turnover fragility under pressure: Delta TOV rate
    # Turnovers = interceptions + lost fumbles
    c_to_count <- sum(is_flag_one(clutch_plays, "interception")) + sum(is_flag_one(clutch_plays, "fumble_lost"))
    b_to_count <- sum(is_flag_one(baseline_plays, "interception")) + sum(is_flag_one(baseline_plays, "fumble_lost"))
    c_to_rate <- (c_to_count / max(1, n_clutch_plays)) * 100
    b_to_rate <- (b_to_count / max(1, n_base_plays)) * 100
    tov_fragility <- round(c_to_rate - b_to_rate, 1)

    # 5. 4th down conversion rate (%)
    qb_4th_plays <- if ("down" %in% names(qb_plays)) {
      qb_plays[!is.na(qb_plays$down) & qb_plays$down == 4, , drop = FALSE]
    } else {
      qb_plays[0, , drop = FALSE]
    }
    fourth_conv_rate <- if (nrow(qb_4th_plays) > 0L) {
      round((sum(is_flag_one(qb_4th_plays, "fourth_down_converted")) / nrow(qb_4th_plays)) * 100, 1)
    } else {
      NA_real_
    }

    # 6. Situational Archetype Tag
    archetype <- if (!is.na(c_epa_delta) && !is.na(c_sr) && c_epa_delta >= 0.12 && c_sr >= 50.0) {
      "Elite Ice-in-Veins Finisher"
    } else if (!is.na(c_cpoe) && !is.na(c_epa) && c_cpoe >= 3.5 && c_epa >= 0.05) {
      "High-Leverage Shotmaker"
    } else if (!is.na(c_epa) && !is.na(tov_fragility) && c_epa >= 0.10 && tov_fragility <= 0.0) {
      "Poised Late-Game Closer"
    } else if ((!is.na(c_epa_delta) && c_epa_delta <= -0.12) || (!is.na(tov_fragility) && tov_fragility >= 4.0)) {
      "Fragile Under Pressure"
    } else if (!is.na(c_sr) && c_sr >= 45.0) {
      "Efficient Situational Closer"
    } else {
      "Game Manager Under Pressure"
    }

    list(
      playerId = player_id,
      playerName = pname,
      team = pteam,
      position = "QB",
      isStarter = is_starter,
      headshotUrl = headshot,
      season = season,
      throughWeek = through_week,
      minClutchAttempts = min_clutch_attempts,
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
      fourthDownConversionRate = fourth_conv_rate,
      clutchArchetype = archetype,
      provenance = "REAL_CURRENT_SEASON"
    )
  } else {
    # Low sample player: emit typed null for rate and efficiency metrics
    list(
      playerId = player_id,
      playerName = pname,
      team = pteam,
      position = "QB",
      isStarter = is_starter,
      headshotUrl = headshot,
      season = season,
      throughWeek = through_week,
      minClutchAttempts = min_clutch_attempts,
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
      fourthDownConversionRate = NA_real_,
      clutchArchetype = "Insufficient Sample",
      provenance = "INSUFFICIENT_SAMPLE"
    )
  }
}

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

# Keep only the current season (front-office#109 / NFL#80): a fallback to the
# multi-season pbp_cache.rds must never mix seasons into one board.
if (!"season" %in% names(pbp)) {
  stop(sprintf("Play-by-play file %s has no 'season' column; cannot filter to CURRENT_SEASON (%d).",
               pbp_file, CURRENT_SEASON))
}
pbp <- pbp %>% filter(season == CURRENT_SEASON)
if (nrow(pbp) == 0) {
  stop(sprintf("Play-by-play file %s has no rows for CURRENT_SEASON (%d); refusing to write an empty clutch board.",
               pbp_file, CURRENT_SEASON))
}
DATA_SEASON <- as.integer(CURRENT_SEASON)
DATA_THROUGH_WEEK <- as.integer(max(pbp$week, na.rm = TRUE))
cat(sprintf(">>> [CLUTCH ENGINE] Kept %d events for season %d (through week %d).\n",
            nrow(pbp), DATA_SEASON, DATA_THROUGH_WEEK))

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
pbp <- add_clutch_flag(pbp)

clutch_play_count <- sum(pbp$is_clutch, na.rm = TRUE)
cat(sprintf(">>> [CLUTCH ENGINE] Identified %d high-leverage late-game clutch plays (%.1f%% of sample).\n",
            clutch_play_count, (clutch_play_count / nrow(pbp)) * 100))

# Minimum clutch pass attempts for a QB to be ranked and given an archetype
# (NFL#80). Raised from 5L: on 2026-11-10 a 7-attempt sample topped the board.
# 20 is a judgement call, not a derived value; the owner may tune it. The
# qualification counts at 5/10/15/20/25/30 are in the PR that set it.
MIN_CLUTCH_PASS_ATTEMPTS <- 20L
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

  clutch_profiles[[i]] <- compute_qb_clutch_profile(
    pbp = pbp,
    pname = pname,
    pteam = pteam,
    gid = gid,
    is_starter = is_starter,
    headshot = headshot,
    season = DATA_SEASON,
    through_week = DATA_THROUGH_WEEK,
    min_clutch_attempts = MIN_CLUTCH_PASS_ATTEMPTS,
    fallback_player_id = sprintf("NFL-%s-%02d", pteam, i)
  )
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
