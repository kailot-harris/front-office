# ==============================================================================
# tools/compare_forecast_variants.R
# Walk-Forward Evaluation of the Four Candidate Forecast Variants (Section 5.1).
#
# Companion script to Section 5.1 of NFL_MATCHUP_GAME_DETAIL_PLAN.md and
# Section 2 of NFL_V2_BASELINE_AND_D2_FINDINGS.md, establishing the empirical
# basis for Owner Decision D2:
#
# Variants evaluated:
#   1. Margin-Avg (No Fatigue) [Decision D2 Selected Variant]:
#      pnorm((0.5 * ridge_margin + 0.5 * elo_margin) / NFL_MARGIN_SIGMA)
#   2. Margin-Avg (+ Fatigue):
#      pnorm((0.5 * ridge_margin + 0.5 * (elo_margin + fatigue_adj)) / NFL_MARGIN_SIGMA)
#   3. Prob-Avg (No Fatigue):
#      0.5 * pnorm(ridge_margin / NFL_MARGIN_SIGMA) + 0.5 * pnorm(elo_margin / NFL_MARGIN_SIGMA)
#   4. Prob-Avg (+ Fatigue):
#      0.5 * pnorm(ridge_margin / NFL_MARGIN_SIGMA) + 0.5 * pnorm((elo_margin + fatigue_adj) / NFL_MARGIN_SIGMA)
#
# Evaluated across:
#   - Historical out-of-sample window (2003-2025, N = 5,535 non-tied games)
#   - 2026 out-of-sample season-to-date (Weeks 1-10, N = 145 completed games)
#
# Strictly zero-betting compliant (no betting vocabulary or market data).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("team_ratings_engine.R")
source("tools/backtest_common.R")
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R")
source("tools/elo_model.R")
source("tools/forecast_engine.R")

evaluate_variants <- function(seasons = 2003:2026,
                              print_summary = TRUE,
                              print_calibration = FALSE) {
  epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
  sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
  completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
  fatigue <- readRDS(CACHE_FATIGUE_METRICS)

  avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

  # Build shared walk-forward game table
  games <- build_walkforward_games(epa, completed, seasons, avg_plays_per_game)

  # QB-backup flags (strictly as-of, no lookahead)
  starter_tbl <- get_qb_starter_table(MODERN_ERA_START_SEASON:max(seasons))
  qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
  games <- games |>
    left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
    left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

  # Elo walk-forward run sequentially across full history
  elo_full_history <- sch |>
    filter(!is.na(home_score), !is.na(away_score),
           season >= MODERN_ERA_START_SEASON, season <= max(seasons))
  elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
    select(game_id, elo_margin_pts, fatigue_adj)
  games <- games |> left_join(elo_results, by = "game_id")

  # Ridge-Massey walk-forward predictions
  games$ridge_margin_raw <- predict_ridge_massey_walkforward(games)

  # Quarterback injury penalty shift
  home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
  away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
  qb_shift <- -QB_INJURY_RATING_PENALTY_PTS * home_adj + QB_INJURY_RATING_PENALTY_PTS * away_adj

  ridge_m <- games$ridge_margin_raw + qb_shift
  elo_m   <- games$elo_margin_pts + qb_shift
  fat     <- games$fatigue_adj

  # Four variant predictions
  # 1. Margin-Avg (No Fatigue)
  p1 <- pnorm((0.5 * ridge_m + 0.5 * elo_m) / NFL_MARGIN_SIGMA)
  # 2. Margin-Avg (+ Fatigue)
  p2 <- pnorm((0.5 * ridge_m + 0.5 * (elo_m + fat)) / NFL_MARGIN_SIGMA)
  # 3. Prob-Avg (No Fatigue)
  p3 <- 0.5 * pnorm(ridge_m / NFL_MARGIN_SIGMA) + 0.5 * pnorm(elo_m / NFL_MARGIN_SIGMA)
  # 4. Prob-Avg (+ Fatigue)
  p4 <- 0.5 * pnorm(ridge_m / NFL_MARGIN_SIGMA) + 0.5 * pnorm((elo_m + fat) / NFL_MARGIN_SIGMA)

  probs <- list(p1 = p1, p2 = p2, p3 = p3, p4 = p4)
  variant_names <- c(
    "1. Margin-Avg (No Fatigue)",
    "2. Margin-Avg (+ Fatigue)",
    "3. Prob-Avg (No Fatigue)",
    "4. Prob-Avg (+ Fatigue)"
  )

  calc_metrics <- function(y, p) {
    p_clamped <- pmin(pmax(p, 1e-6), 1 - 1e-6)
    n <- length(y)
    correct <- sum((p > 0.5) == (y == 1))
    acc <- correct / n
    brier <- mean((p - y)^2)
    logloss <- -mean(y * log(p_clamped) + (1 - y) * log(1 - p_clamped))
    list(n = n, correct = correct, acc = acc, brier = brier, logloss = logloss)
  }

  calc_calibration <- function(y, p) {
    p_clamped <- pmin(pmax(p, 1e-6), 1 - 1e-6)
    bin <- cut(p_clamped, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
    tibble(p = p_clamped, y = y, bin = bin) |>
      group_by(bin) |>
      summarise(
        n = dplyr::n(),
        mean_pred = mean(p),
        realized_win_rate = mean(y),
        gap = abs(mean(p) - mean(y)),
        .groups = "drop"
      )
  }

  results <- list()

  # 1. Historical 2003-2025 non-tied games
  idx_hist <- which(games$season >= 2003 & games$season <= 2025 & games$home_margin != 0)
  hist_metrics <- vector("list", 4)
  for (v in 1:4) {
    hist_metrics[[v]] <- calc_metrics(games$home_win[idx_hist], probs[[v]][idx_hist])
  }
  results$historical_2003_2025 <- hist_metrics

  # 2. 2026 Completed games (all 145 games)
  idx_2026 <- which(games$season == 2026)
  curr_metrics <- vector("list", 4)
  for (v in 1:4) {
    curr_metrics[[v]] <- calc_metrics(games$home_win[idx_2026], probs[[v]][idx_2026])
  }
  results$current_2026 <- curr_metrics

  if (print_summary) {
    cat("========================================================================================\n")
    cat("Four-Variant Walk-Forward Evaluation (Decision D2, Plan Section 5.1)\n")
    cat("========================================================================================\n\n")

    cat("--- 1. Historical Out-of-Sample (2003-2025, Non-Tied Regular-Season Games) ---\n")
    cat(sprintf("%-30s | %6s | %10s | %10s | %10s\n", "Variant", "N", "Accuracy", "Brier", "Log Loss"))
    cat(paste(rep("-", 76), collapse = ""), "\n")
    for (v in 1:4) {
      m <- hist_metrics[[v]]
      cat(sprintf("%-30s | %6d | %9.3f%% | %10.6f | %10.6f\n",
                  variant_names[v], m$n, m$acc * 100, m$brier, m$logloss))
    }

    cat("\n--- 2. 2026 Out-of-Sample Season-to-Date (Weeks 1-10, N = 145 Completed Games) ---\n")
    cat(sprintf("%-30s | %6s | %8s | %10s | %10s | %10s\n", "Variant", "N", "Correct", "Accuracy", "Brier", "Log Loss"))
    cat(paste(rep("-", 87), collapse = ""), "\n")
    for (v in 1:4) {
      m <- curr_metrics[[v]]
      cat(sprintf("%-30s | %6d | %8d | %9.3f%% | %10.6f | %10.6f\n",
                  variant_names[v], m$n, m$correct, m$acc * 100, m$brier, m$logloss))
    }
    cat("========================================================================================\n\n")
  }

  if (print_calibration) {
    cat("\n--- 10-Bin Calibration Tables (2003-2025) ---\n")
    for (v in 1:4) {
      cat(sprintf("\nVariant %d: %s\n", v, variant_names[v]))
      print(calc_calibration(games$home_win[idx_hist], probs[[v]][idx_hist]))
    }
  }

  invisible(results)
}

if (!interactive() && identical(environment(), globalenv())) {
  evaluate_variants()
}
