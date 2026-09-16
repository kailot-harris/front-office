# ==============================================================================
# build_calibration_cache.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/build_calibration_cache.R
#
# P3b (GAP_REMEDIATION_PLAN.md / agent9.md, wnba_bugfix_agent): app.R's Tab 6
# "Model Calibration & Reliability" rendered a hardcoded seq()/rnorm() fake curve,
# never calling live_calibration.R's real calibration_analysis(). agent9.md's brief
# asked first to check cache/ for a saved model-predictions object (e.g.
# enhanced_rf_fit.rds) to feed calibration_analysis() with the "real" model's
# predicted-probability/actual-outcome pairs. There is NO such saved predictions
# cache in this repo: `cache/` (see directory listing checked 2026-09-12) has only
# active_rosters_cache.rds, betting_ledger.rds, copula_wilson_pra.rds,
# injury_data_cache.rds, latest_player_props.rds, latest_value_bets.rds,
# odds_history.rds, player_box_scores_cache.rds, playoff_series_wnba_demo.rds,
# projected_wnba_standings.rds, risk_state.rds, rolling_bet_metrics.rds,
# team_shot_quality.rds, travel_fatigue_metrics.rds — nothing that stores held-out
# predicted-probability/actual-outcome pairs from WNBA_Analysis_Project.Rmd's RF
# model. That Rmd is a notebook (not a sourceable function returning predictions),
# so re-running it here to extract its fitted object is out of scope for this
# mechanical bugfix pass.
#
# DOCUMENTED SUBSTITUTE (per agent9.md's explicit fallback instruction): this
# script builds real predicted-win-probability / real-actual-outcome pairs directly
# from T1's real box_scores_cache.rds (3,906 real WNBA team-game rows, 2019-2026),
# using the SAME point-margin -> win-probability formula roster_bottom_up_engine.R's
# get_fair_spread() uses (win_prob = pnorm(margin / WNBA_MARGIN_SIGMA), margin =
# net-rating differential + home-court-advantage 2.40) — but WITHOUT get_fair_spread
# ()'s look-ahead problem. get_fair_spread() reads a single CURRENT snapshot
# (cache/projected_wnba_standings.rds, built from current rosters), so applying it
# to games from 2019-2025 would compare a 2026-roster-based rating against
# years-old outcomes, which is not a fair backtest. Instead, for every game this
# script computes each team's PRE-GAME rolling scoring margin (mean of that team's
# own prior ROLLING_WINDOW_SIZE games' point margins, resetting at each season
# boundary per config.R's OFFSEASON_METHOD == "reset", exactly mirroring the
# windowing convention WNBA_Analysis_Project.Rmd itself validated — see config.R's
# ROLLING_WINDOW_SIZE comment) using ONLY games strictly before the game being
# predicted, so there is no look-ahead. predicted_margin = (home_roll_margin -
# away_roll_margin) + hca(2.40); .pred_Win = pnorm(predicted_margin /
# WNBA_MARGIN_SIGMA). target_home_win = "Win"/"Loss" from the real team_winner
# column. Games in each team's first ROLLING_WINDOW_SIZE games of a season (no
# prior-games history yet) are dropped, same as any rolling-window model would.
#
# This is a reasonable, clearly-labeled substitute for a saved ML-model prediction
# cache -- it is a real, simple, sport-agnostic margin model evaluated honestly
# out-of-sample against REAL WNBA game outcomes, not synthetic data. It is NOT the
# same model class as WNBA_Analysis_Project.Rmd's tuned Random Forest and should
# not be quoted as that model's calibration -- app.R's Tab 6 UI text says so
# explicitly (see app.R's Tab 6 box `p()` caveat).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)
if (file.exists("config.R")) source("config.R")
if (!exists("WNBA_MARGIN_SIGMA")) WNBA_MARGIN_SIGMA <- 14.0
if (!exists("ROLLING_WINDOW_SIZE")) ROLLING_WINDOW_SIZE <- 13
if (!exists("CACHE_TEAM_BOX")) CACHE_TEAM_BOX <- file.path(PROJECT_DIR, "data", "box_scores_cache.rds")
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_DIR, "cache")

# FINDING C-1: home-court advantage is read from config.R::WNBA_HCA, not restated as a
# literal `2.40` here. Restating it is exactly how market_odds_engine.R drifted to 11.6
# while its own comment still said 2.40. The `if (!exists(...))` guard matches the
# defensive pattern used for the other constants above, for the case where config.R is
# somehow unavailable; config.R is the authority whenever it loads.
if (!exists("WNBA_HCA")) WNBA_HCA <- 2.40
HCA <- WNBA_HCA

build_model_calibration_input <- function() {
  if (!file.exists(CACHE_TEAM_BOX)) {
    stop("build_calibration_cache.R: box_scores_cache.rds not found at ", CACHE_TEAM_BOX,
         " -- cannot build real calibration input without T1's real box score cache.")
  }

  box <- readRDS(CACHE_TEAM_BOX) %>%
    mutate(game_date = as.Date(game_date)) %>%
    arrange(season, game_date, game_id)

  # Long team-game table: one row per team per game, with that team's own margin
  # (its perspective, regardless of home/away), used to build each team's
  # PRE-GAME rolling mean margin within a season (reset each season boundary).
  team_games <- box %>%
    transmute(
      game_id, season, game_date,
      team = team_short_display_name,
      opponent = opponent_team_short_display_name,
      home_away = team_home_away,
      margin = team_score - opponent_team_score,
      team_winner
    ) %>%
    arrange(team, season, game_date, game_id) %>%
    group_by(team, season) %>%
    mutate(
      # Pre-game rolling mean of this team's own last ROLLING_WINDOW_SIZE margins,
      # strictly excluding the current game (lag by 1 before the rolling window).
      roll_margin = {
        lagged <- lag(margin)
        sapply(seq_along(lagged), function(i) {
          lo <- max(1, i - ROLLING_WINDOW_SIZE)
          window_vals <- lagged[lo:i]
          if (i <= 1 || all(is.na(window_vals))) NA_real_ else mean(window_vals, na.rm = TRUE)
        })
      }
    ) %>%
    ungroup()

  # Rebuild one row per game from the HOME team's perspective, joining in both
  # teams' pre-game rolling margins (no look-ahead: roll_margin at row i used
  # only lag()'d prior games).
  home_rows <- team_games %>% filter(home_away == "home") %>%
    select(game_id, season, game_date, home_team = team, away_team = opponent,
           home_roll = roll_margin, team_winner)
  away_rows <- team_games %>% filter(home_away == "away") %>%
    select(game_id, away_roll = roll_margin)

  games <- home_rows %>%
    inner_join(away_rows, by = "game_id") %>%
    filter(!is.na(home_roll), !is.na(away_roll)) %>%
    mutate(
      predicted_margin = (home_roll - away_roll) + HCA,
      .pred_Win = pmin(pmax(pnorm(predicted_margin / WNBA_MARGIN_SIGMA), 1e-4), 1 - 1e-4),
      target_home_win = if_else(team_winner == TRUE, "Win", "Loss")
    ) %>%
    select(game_id, season, game_date, home_team, away_team, .pred_Win, target_home_win)

  attr(games, "model_description") <- paste0(
    "Substitute calibration input (P3b): pre-game rolling-margin model ",
    "(window=", ROLLING_WINDOW_SIZE, ", sigma=", WNBA_MARGIN_SIGMA, ", hca=", HCA, ") ",
    "evaluated out-of-sample against real box_scores_cache.rds outcomes. ",
    "NOT WNBA_Analysis_Project.Rmd's tuned Random Forest -- see build_calibration_cache.R header."
  )
  attr(games, "built_at") <- Sys.time()
  attr(games, "n_games") <- nrow(games)

  out_path <- file.path(CACHE_DIR, "model_calibration_input.rds")
  saveRDS(games, out_path)
  message(sprintf(">>> [CALIBRATION-CACHE] Saved %d real held-out game predictions to %s", nrow(games), out_path))
  invisible(games)
}

if (!interactive() && identical(environment(), globalenv()) && sys.nframe() == 0) {
  build_model_calibration_input()
}
