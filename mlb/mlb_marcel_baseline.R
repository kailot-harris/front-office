# ==============================================================================
# mlb_marcel_baseline.R — Tom Tango's Marcel Projection System
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_marcel_baseline.R
#
# Phase 3: Specialty Models (Issue #18)
#
# Tom Tango's Marcel ("the Monkey Forecasting System") is a deliberately
# minimal, reproducible projection baseline designed as the minimum level of
# competence expected from any forecaster (docs/MLB_REPLICATION_PLAN.md §5).
#
# Methodology & Formulas:
#   1. 3-Year Recency Weighting:
#        Batters : 5 (t-1) / 4 (t-2) / 3 (t-3)
#        Pitchers: 3 (t-1) / 2 (t-2) / 1 (t-3)
#   2. Regression to League Mean:
#        Blends weighted player performance with 1,200 PA (batters) or
#        450 BF / 100 IP (pitchers) of league-average performance:
#        Rate_proj = (W_player * Rate_player + W_reg * Rate_lg) / (W_player + W_reg)
#   3. Age Adjustment:
#        Piecewise formula:
#        - Over 29 : AgeAdj = (age - 29) * 0.003  (decline)
#        - Under 29: AgeAdj = (29 - age) * 0.006  (growth, Tango corrected sign)
#        Metric_proj = Metric_regressed * (1 - AgeAdj) or (1 + AgeAdj)
#   4. Playing Time Projection:
#        PA_proj = 0.5 * PA_(t-1) + 0.1 * PA_(t-2) + 200
#
# Role in Architecture:
#   Maintained as a benchmark baseline to compare other projection and
#   valuation models against, exactly per Tom Tango's original design intent.
#
# Interface Contract:
#   - Exposes top-level callable: run_marcel_baseline(target_season = 2025, force_refresh = FALSE)
#   - Writes outputs to cache_path("specialty", ...):
#       cache/specialty/marcel_batters_2025.rds
#       cache/specialty/marcel_pitchers_2025.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_marcel_baseline.R"

#' Compute Marcel Age Adjustment Multiplier
#'
#' @param age Numeric player age in target season
#' @param weights List of Marcel constants from config.R
#' @param higher_is_better Logical (TRUE for batting stats/wOBA/HR, FALSE for ERA/FIP)
#' @return Multiplier centered around 1.0
calc_marcel_age_factor <- function(age, weights = MLB_MARCEL_WEIGHTS, higher_is_better = TRUE) {
  if (is.na(age) || age <= 0) return(1.0)
  
  over_slope  <- weights$age_adjustment_over_29 %||% 0.003
  under_slope <- weights$age_adjustment_under_29 %||% 0.006

  if (age > 29) {
    pct_change <- -1.0 * (age - 29) * over_slope
  } else if (age < 29) {
    pct_change <- (29 - age) * under_slope
  } else {
    pct_change <- 0.0
  }

  if (!higher_is_better) {
    # For ERA/FIP: younger pitchers improve (lower ERA), older decline (higher ERA)
    pct_change <- -pct_change
  }

  1.0 + pct_change
}

#' Generate Marcel Batter Projections for a Target Season
#'
#' @param target_season Integer target projection season (e.g. 2025)
#' @param force_refresh If TRUE, forces recalculation
#' @return Tibble of projected batter stats
project_marcel_batters <- function(target_season = 2025, force_refresh = FALSE) {
  cache_file <- cache_path("specialty", sprintf("marcel_batters_%d.rds", target_season))
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached Marcel batter projections for %d", target_season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }

  log_info(sprintf("Generating Marcel batter projections for season %d", target_season),
           script = .LOG_SCRIPT)

  fg_bat_file <- cache_path("stats_sync", "fg_batters.rds")
  if (!file.exists(fg_bat_file)) {
    log_warn("FanGraphs batter cache not found; running stats_sync first", script = .LOG_SCRIPT)
    source("mlb_stats_sync.R")
    sync_fg_batters()
  }

  if (!file.exists(fg_bat_file)) {
    log_error("Cannot build Marcel projections: fg_batters.rds unavailable", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }

  bat_df <- readRDS(fg_bat_file)
  recency_w <- MLB_MARCEL_WEIGHTS$batter_recency_weights %||% c(5, 4, 3)
  reg_pa    <- MLB_MARCEL_WEIGHTS$regression_pa %||% 1200

  # Identify available seasons (target - 1, target - 2, target - 3)
  s1 <- target_season - 1
  s2 <- target_season - 2
  s3 <- target_season - 3

  # Prepare season frames with weights
  df_s1 <- bat_df %>% dplyr::filter(season == s1 | Season == s1) %>% dplyr::mutate(weight = recency_w[1])
  df_s2 <- bat_df %>% dplyr::filter(season == s2 | Season == s2) %>% dplyr::mutate(weight = recency_w[2])
  df_s3 <- bat_df %>% dplyr::filter(season == s3 | Season == s3) %>% dplyr::mutate(weight = recency_w[3])

  history_df <- dplyr::bind_rows(df_s1, df_s2, df_s3)
  if (nrow(history_df) == 0) {
    # If prior multi-year data isn't partitioned, use available rows
    history_df <- bat_df %>% dplyr::mutate(weight = recency_w[1])
  }

  # League average rates for regression
  lg_pa <- sum(history_df$PA, na.rm = TRUE)
  lg_obp <- sum(history_df$H + history_df$BB + history_df$HBP, na.rm = TRUE) / max(1, lg_pa)
  lg_slg <- sum(history_df$TB %||% (history_df$H + history_df$`2B`*1 + history_df$`3B`*2 + history_df$HR*3), na.rm = TRUE) / max(1, sum(history_df$AB, na.rm = TRUE))
  lg_hr_rate <- sum(history_df$HR, na.rm = TRUE) / max(1, lg_pa)
  lg_bb_rate <- sum(history_df$BB, na.rm = TRUE) / max(1, lg_pa)
  lg_k_rate  <- sum(history_df$SO, na.rm = TRUE) / max(1, lg_pa)

  # Group by player
  projections <- history_df %>%
    dplyr::group_by(playerid, PlayerName) %>%
    dplyr::summarise(
      xMLBAMID    = dplyr::first(xMLBAMID %||% NA_character_),
      team_name   = dplyr::last(team_name %||% ""),
      last_age    = dplyr::last(Age %||% 27),
      total_pa_raw = sum(PA, na.rm = TRUE),
      w_pa        = sum(PA * weight, na.rm = TRUE),
      w_ab        = sum(AB * weight, na.rm = TRUE),
      w_h         = sum(H * weight, na.rm = TRUE),
      w_hr        = sum(HR * weight, na.rm = TRUE),
      w_bb        = sum(BB * weight, na.rm = TRUE),
      w_k         = sum(SO * weight, na.rm = TRUE),
      w_hbp       = sum((HBP %||% 0) * weight, na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      target_age   = as.numeric(last_age) + (target_season - s1),
      age_factor   = calc_marcel_age_factor(target_age, MLB_MARCEL_WEIGHTS, higher_is_better = TRUE),

      # Playing time projection (Tango formula: 0.5 * PA1 + 0.1 * PA2 + 200)
      proj_pa      = round(min(650, max(150, 0.5 * (w_pa / recency_w[1]) + 200))),

      # Regression to league mean via 1,200 PA blend
      reg_denom    = w_pa + reg_pa,
      raw_hr_rate  = (w_hr + (reg_pa * lg_hr_rate)) / reg_denom,
      raw_bb_rate  = (w_bb + (reg_pa * lg_bb_rate)) / reg_denom,
      raw_k_rate   = (w_k  + (reg_pa * lg_k_rate))  / reg_denom,
      raw_obp      = ((w_h + w_bb + w_hbp) + (reg_pa * lg_obp)) / reg_denom,

      # Apply age adjustment
      proj_hr_rate = pmax(0.005, raw_hr_rate * age_factor),
      proj_bb_rate = pmax(0.02,  raw_bb_rate * age_factor),
      proj_k_rate  = pmax(0.05,  raw_k_rate / age_factor),
      proj_obp     = pmax(0.22,  pmin(0.48, raw_obp * age_factor)),

      proj_hr      = round(proj_hr_rate * proj_pa),
      proj_bb      = round(proj_bb_rate * proj_pa),
      proj_so      = round(proj_k_rate * proj_pa)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(desc(proj_hr), desc(proj_obp))

  saveRDS(projections, cache_file)
  log_info(sprintf("Saved Marcel projections for %d batters to %s", nrow(projections), cache_file),
           script = .LOG_SCRIPT)

  projections
}

#' Generate Marcel Pitcher Projections for a Target Season
#'
#' @param target_season Integer target projection season (e.g. 2025)
#' @param force_refresh If TRUE, forces recalculation
#' @return Tibble of projected pitcher stats
project_marcel_pitchers <- function(target_season = 2025, force_refresh = FALSE) {
  cache_file <- cache_path("specialty", sprintf("marcel_pitchers_%d.rds", target_season))
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached Marcel pitcher projections for %d", target_season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }

  log_info(sprintf("Generating Marcel pitcher projections for season %d", target_season),
           script = .LOG_SCRIPT)

  fg_pit_file <- cache_path("stats_sync", "fg_pitchers.rds")
  if (!file.exists(fg_pit_file)) {
    source("mlb_stats_sync.R")
    sync_fg_pitchers()
  }

  if (!file.exists(fg_pit_file)) {
    log_error("Cannot build Marcel projections: fg_pitchers.rds unavailable", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }

  pit_df <- readRDS(fg_pit_file)
  recency_w <- MLB_MARCEL_WEIGHTS$pitcher_recency_weights %||% c(3, 2, 1)
  reg_ip    <- 75.0 # League regression blend innings (~300 BF)

  s1 <- target_season - 1
  s2 <- target_season - 2
  s3 <- target_season - 3

  df_s1 <- pit_df %>% dplyr::filter(season == s1 | Season == s1) %>% dplyr::mutate(weight = recency_w[1])
  df_s2 <- pit_df %>% dplyr::filter(season == s2 | Season == s2) %>% dplyr::mutate(weight = recency_w[2])
  df_s3 <- pit_df %>% dplyr::filter(season == s3 | Season == s3) %>% dplyr::mutate(weight = recency_w[3])

  history_df <- dplyr::bind_rows(df_s1, df_s2, df_s3)
  if (nrow(history_df) == 0) {
    history_df <- pit_df %>% dplyr::mutate(weight = recency_w[1])
  }

  lg_ip  <- sum(history_df$IP, na.rm = TRUE)
  lg_era <- sum(history_df$ER %||% (history_df$R * 0.92), na.rm = TRUE) * 9 / max(1, lg_ip)
  lg_k9  <- sum(history_df$SO, na.rm = TRUE) * 9 / max(1, lg_ip)
  lg_bb9 <- sum(history_df$BB, na.rm = TRUE) * 9 / max(1, lg_ip)
  lg_hr9 <- sum(history_df$HR, na.rm = TRUE) * 9 / max(1, lg_ip)

  projections <- history_df %>%
    dplyr::group_by(playerid, PlayerName) %>%
    dplyr::summarise(
      xMLBAMID   = dplyr::first(xMLBAMID %||% NA_character_),
      team_name  = dplyr::last(team_name %||% ""),
      last_age   = dplyr::last(Age %||% 27),
      total_ip   = sum(IP, na.rm = TRUE),
      is_starter = dplyr::last(GS %||% 0) >= 5,
      w_ip       = sum(IP * weight, na.rm = TRUE),
      w_er       = sum((ER %||% (R * 0.92)) * weight, na.rm = TRUE),
      w_k        = sum(SO * weight, na.rm = TRUE),
      w_bb       = sum(BB * weight, na.rm = TRUE),
      w_hr       = sum(HR * weight, na.rm = TRUE),
      .groups    = "drop"
    ) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      target_age  = as.numeric(last_age) + (target_season - s1),
      age_factor  = calc_marcel_age_factor(target_age, MLB_MARCEL_WEIGHTS, higher_is_better = FALSE),

      proj_ip     = round(if (is_starter) min(200, max(60, 0.5 * (w_ip / recency_w[1]) + 60)) else min(75, max(25, 0.5 * (w_ip / recency_w[1]) + 20))),

      reg_denom   = w_ip + reg_ip,
      raw_era     = ((w_er + (reg_ip * (lg_era / 9))) * 9) / reg_denom,
      raw_k9      = ((w_k  + (reg_ip * (lg_k9 / 9))) * 9)  / reg_denom,
      raw_bb9     = ((w_bb + (reg_ip * (lg_bb9 / 9))) * 9) / reg_denom,
      raw_hr9     = ((w_hr + (reg_ip * (lg_hr9 / 9))) * 9) / reg_denom,

      proj_era    = round(pmax(1.80, pmin(7.50, raw_era * age_factor)), 2),
      proj_k9     = round(pmax(3.5,  raw_k9 / age_factor), 2),
      proj_bb9    = round(pmax(1.5,  raw_bb9 * age_factor), 2),
      proj_hr9    = round(pmax(0.4,  raw_hr9 * age_factor), 2)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(desc(proj_ip), proj_era)

  saveRDS(projections, cache_file)
  log_info(sprintf("Saved Marcel projections for %d pitchers to %s", nrow(projections), cache_file),
           script = .LOG_SCRIPT)

  projections
}

#' Master Stage Runner for Marcel Baseline Projections
#'
#' @param target_season Integer target year (defaults to 2025)
#' @param force_refresh If TRUE, forces recomputation
#' @return Named list of projected batters and pitchers
run_marcel_baseline <- function(target_season = 2025, force_refresh = FALSE) {
  log_info("Starting Marcel baseline projection stage", script = .LOG_SCRIPT,
           target_season = target_season, force_refresh = force_refresh)

  batters  <- project_marcel_batters(target_season = target_season, force_refresh = force_refresh)
  pitchers <- project_marcel_pitchers(target_season = target_season, force_refresh = force_refresh)

  res <- list(
    batters  = batters,
    pitchers = pitchers
  )

  log_info(sprintf("Completed Marcel baseline stage: %d batters, %d pitchers projected",
                   nrow(batters), nrow(pitchers)),
           script = .LOG_SCRIPT)

  invisible(res)
}
