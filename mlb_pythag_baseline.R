# ==============================================================================
# mlb_pythag_baseline.R — Pythagorean Win-Expectation Baseline Engine
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_pythag_baseline.R
#
# Implements the foundational sabermetric win-expectation baselines
# (docs/MLB_REPLICATION_PLAN.md §3):
#
# 1. Pythagenpat (David Smyth) — DEFAULT:
#      exponent = ((RS + RA) / G)^0.287
#      Win% = RS^exponent / (RS^exponent + RA^exponent)
#      Clay Davenport endorsed this as simpler, more elegant, and better across
#      a wide range of run environments than fixed exponents.
#
# 2. Pythagenport (Clay Davenport / Baseball Prospectus):
#      exponent = 1.50 * log10((RS + RA) / G) + 0.45
#      Win% = RS^exponent / (RS^exponent + RA^exponent)
#
# 3. Fixed Exponent 1.83 (Baseball-Reference standard modern constant)
#
# 4. Bill James Original Exponent 2:
#      Win% = RS^2 / (RS^2 + RA^2)
#
# Success criteria (Issue #16):
#   - Exposes one callable top-level runner: run_pythag_baseline(...)
#   - Variable-exponent Pythagenpat is default; comparison forms available.
#   - Numeric constants sourced via config.R placeholders (e.g. MLB_PYTHAG_EXPONENT).
#   - Outputs cached under cache_path("pythag", ...).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_pythag_baseline.R"

#' Calculate Pythagorean Win Expectation
#'
#' @param rs Runs scored
#' @param ra Runs allowed
#' @param games Total games played (required for Pythagenpat and Pythagenport)
#' @param method One of "pythagenpat" (default), "pythagenport", "fixed_1.83", "fixed_2"
#' @param custom_exponent Optional custom numeric exponent (overrides method)
#' @return Numeric expected win percentage between 0 and 1
calc_pythagorean_win_pct <- function(rs, ra, games = NULL, method = "pythagenpat", custom_exponent = NULL) {
  # Input sanitation
  rs <- pmax(as.numeric(rs), 0)
  ra <- pmax(as.numeric(ra), 0)
  
  if (is.null(games)) games <- 162
  games <- pmax(as.numeric(games), 1)
  
  # Determine exponent
  exp_val <- if (!is.null(custom_exponent)) {
    custom_exponent
  } else if (!is.null(MLB_PYTHAG_EXPONENT)) {
    # If config.R has derived an empirical exponent, honor it
    MLB_PYTHAG_EXPONENT
  } else {
    switch(
      method,
      "pythagenpat" = {
        # Pythagenpat formula: ((RS + RA) / G)^0.287
        rpg <- (rs + ra) / games
        rpg <- pmax(rpg, 0.1) # prevent 0 or negative
        rpg^0.287
      },
      "pythagenport" = {
        # Pythagenport formula: 1.50 * log10((RS + RA) / G) + 0.45
        rpg <- (rs + ra) / games
        rpg <- pmax(rpg, 0.1)
        1.50 * log10(rpg) + 0.45
      },
      "fixed_1.83" = 1.83,
      "fixed_2"    = 2.00,
      {
        # Default fallback to Pythagenpat
        rpg <- (rs + ra) / games
        rpg <- pmax(rpg, 0.1)
        rpg^0.287
      }
    )
  }
  
  # Protect against 0/0
  total_power <- (rs^exp_val) + (ra^exp_val)
  win_pct <- ifelse(total_power > 0, (rs^exp_val) / total_power, 0.500)
  
  pmin(pmax(win_pct, 0.0), 1.0)
}

#' Build Team-Level Pythagorean Standings and Residuals from Schedule & Boxscore Cache
#'
#' @param season Year of the season (e.g. 2024)
#' @param method Formulation to use: "pythagenpat" (default), "pythagenport", "fixed_1.83", "fixed_2"
#' @return A tibble with team records, runs scored/allowed, Pythagorean expectation, and luck residual
compute_team_pythagorean_standings <- function(season = 2024, method = "pythagenpat") {
  sched_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", season), create = FALSE)
  
  if (!file.exists(sched_file)) {
    log_warn(sprintf("Schedule cache missing for %d; running ingestion first", season),
             script = .LOG_SCRIPT)
    if (file.exists("mlb_ingest.R")) {
      source("mlb_ingest.R")
      if (exists("run_mlb_ingest", mode = "function")) {
        run_mlb_ingest(season = season)
      }
    }
  }
  
  if (!file.exists(sched_file)) {
    stop(sprintf("Cannot compute Pythagorean standings: schedule cache missing for %d", season))
  }
  
  sched <- readRDS(sched_file)
  
  # Filter to completed regular season / postseason games with valid scores
  games <- sched %>%
    dplyr::filter(
      !is.na(away_score) & !is.na(home_score) &
      !is.na(away_team_name) & !is.na(home_team_name)
    )
  
  if (nrow(games) == 0) {
    log_warn("No completed games found in schedule cache", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  # Split games from both team perspectives
  home_recs <- games %>%
    dplyr::transmute(
      team_name   = home_team_name,
      team_id     = home_team_id,
      rs          = home_score,
      ra          = away_score,
      won         = ifelse(home_score > away_score, 1L, 0L),
      lost        = ifelse(home_score < away_score, 1L, 0L)
    )
  
  away_recs <- games %>%
    dplyr::transmute(
      team_name   = away_team_name,
      team_id     = away_team_id,
      rs          = away_score,
      ra          = home_score,
      won         = ifelse(away_score > home_score, 1L, 0L),
      lost        = ifelse(away_score < home_score, 1L, 0L)
    )
  
  team_totals <- dplyr::bind_rows(home_recs, away_recs) %>%
    dplyr::group_by(team_name) %>%
    dplyr::summarise(
      games_played     = dplyr::n(),
      wins             = sum(won),
      losses           = sum(lost),
      actual_win_pct   = round(sum(won) / dplyr::n(), 4),
      runs_scored      = sum(rs),
      runs_allowed     = sum(ra),
      run_differential = sum(rs) - sum(ra),
      runs_per_game    = round((sum(rs) + sum(ra)) / dplyr::n(), 2),
      .groups = "drop"
    )
  
  # Calculate expected win % across formulas
  team_standings <- team_totals %>%
    dplyr::mutate(
      exp_pythagenpat  = calc_pythagorean_win_pct(runs_scored, runs_allowed, games_played, method = "pythagenpat"),
      exp_pythagenport = calc_pythagorean_win_pct(runs_scored, runs_allowed, games_played, method = "pythagenport"),
      exp_fixed_183    = calc_pythagorean_win_pct(runs_scored, runs_allowed, games_played, method = "fixed_1.83"),
      exp_fixed_2      = calc_pythagorean_win_pct(runs_scored, runs_allowed, games_played, method = "fixed_2"),
      # Primary selected method
      pythag_win_pct   = round(calc_pythagorean_win_pct(runs_scored, runs_allowed, games_played, method = method), 4),
      expected_wins    = round(pythag_win_pct * games_played, 1),
      # Luck / sequencing residual (Actual wins minus expected wins)
      luck_wins        = round(wins - expected_wins, 1),
      method_used      = method,
      season           = as.integer(season)
    ) %>%
    dplyr::arrange(dplyr::desc(wins), dplyr::desc(run_differential))
  
  team_standings
}

#' Master Stage Runner for Pythagorean Baseline (Issue #16)
#'
#' @param season Year of the season (default 2024)
#' @param method Formulation: "pythagenpat" (default), "pythagenport", "fixed_1.83", "fixed_2"
#' @param force_refresh If TRUE, re-computes baseline even if cached
#' @return A tibble of Pythagorean team standings and residuals
run_pythag_baseline <- function(season = 2024, method = "pythagenpat", force_refresh = FALSE) {
  cache_file <- cache_path("pythag", sprintf("pythag_baseline_%d.rds", season))
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached Pythagorean baseline for %d from disk", season),
             script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  log_info(sprintf("Computing Pythagorean baseline for season %d (method: %s)", season, method),
           script = .LOG_SCRIPT)
  
  standings <- compute_team_pythagorean_standings(season = season, method = method)
  
  if (nrow(standings) == 0) {
    log_warn("No standings generated for Pythagorean baseline", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }
  
  # Calculate baseline evaluation metrics across all 4 formulas
  rmse_pat  <- sqrt(mean((standings$wins - (standings$exp_pythagenpat * standings$games_played))^2))
  rmse_port <- sqrt(mean((standings$wins - (standings$exp_pythagenport * standings$games_played))^2))
  rmse_183  <- sqrt(mean((standings$wins - (standings$exp_fixed_183 * standings$games_played))^2))
  rmse_2    <- sqrt(mean((standings$wins - (standings$exp_fixed_2 * standings$games_played))^2))
  
  log_info(sprintf(
    "Pythagorean Win RMSE (wins) — Pythagenpat: %.3f | Pythagenport: %.3f | Fixed 1.83: %.3f | Fixed 2.0: %.3f",
    rmse_pat, rmse_port, rmse_183, rmse_2
  ), script = .LOG_SCRIPT)
  
  attr(standings, "rmse") <- list(
    pythagenpat  = rmse_pat,
    pythagenport = rmse_port,
    fixed_183    = rmse_183,
    fixed_2      = rmse_2
  )
  
  saveRDS(standings, cache_file)
  std_cache <- cache_path("pythag", "mlb_pythag_standings.rds")
  saveRDS(standings, std_cache)
  log_info(sprintf("Saved Pythagorean baseline for %d teams to %s and %s", nrow(standings), cache_file, std_cache),
           script = .LOG_SCRIPT)
  
  standings
}
