# ==============================================================================
# NBA Bet Ledger & Automated Rolling Accuracy + CLV Grader
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/bet_tracker.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("live_calibration.R")

LEDGER_FILE  <- file.path(CACHE_DIR, "betting_ledger.rds")
METRICS_FILE <- file.path(CACHE_DIR, "rolling_bet_metrics.rds")

# 1. Initialize or Load Persistent Ledger with Full CLV Schema
get_bet_ledger <- function() {
  if (file.exists(LEDGER_FILE)) {
    readRDS(LEDGER_FILE)
  } else {
    message(sprintf(">>> [WARN] Using SYNTHETIC_FALLBACK: '%s' missing. Seeding 30-day historical synthetic betting ledger.", LEDGER_FILE))
    set.seed(42)
    past_dates <- seq(Sys.Date() - 30, Sys.Date() - 1, by = "day")
    
    seed_ledger <- tibble(
      bet_id        = paste0("BET_", 1001:(1000 + length(past_dates) * 2)),
      bet_date      = rep(past_dates, each = 2),
      matchup       = rep(c("Celtics vs. 76ers", "Knicks vs. Heat", "Nuggets vs. Suns", "Lakers vs. Warriors"), length.out = length(past_dates) * 2),
      team_picked   = rep(c("Celtics", "Knicks", "Nuggets", "Warriors"), length.out = length(past_dates) * 2),
      american_odds = rep(c(-125, +135, -110, +145), length.out = length(past_dates) * 2),
      closing_odds  = rep(c(-140, +120, -125, +130), length.out = length(past_dates) * 2),
      model_prob    = rep(c(0.61, 0.48, 0.56, 0.45), length.out = length(past_dates) * 2),
      ev_pct        = rep(c(9.8, 12.8, 6.9, 10.25), length.out = length(past_dates) * 2),
      stake_units   = rep(c(1.5, 1.0, 1.2, 1.0), length.out = length(past_dates) * 2),
      result        = sample(c("WIN", "LOSS"), size = length(past_dates) * 2, replace = TRUE, prob = c(0.61, 0.39)),
      status        = "RESOLVED"
    ) |>
      mutate(
        decimal_odds      = if_else(american_odds > 0, (american_odds / 100) + 1, (100 / abs(american_odds)) + 1),
        profit_units      = if_else(result == "WIN", round(stake_units * (decimal_odds - 1), 2), -stake_units),
        closing_dec       = if_else(closing_odds > 0, (closing_odds / 100) + 1, (100 / abs(closing_odds)) + 1),
        closing_fair_prob = american_to_prob(closing_odds) / (american_to_prob(closing_odds) + 0.50),
        clv_pct           = round(((decimal_odds * closing_fair_prob) - 1) * 100, 2),
        beat_clv          = clv_pct > 0
      )
    
    saveRDS(seed_ledger, LEDGER_FILE)
    seed_ledger
  }
}

# 2. Append Active Today's Picks to Ledger as PENDING
append_todays_picks <- function() {
  val_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
  if (!file.exists(val_path)) return(NULL)
  
  picks <- readRDS(val_path) |>
    filter(grepl("VALUE", Status))
  
  if (nrow(picks) == 0) return(NULL)
  
  ledger <- get_bet_ledger()
  
  # Avoid duplicate entries on same date
  new_bets <- picks |>
    anti_join(
      ledger |> filter(bet_date == Sys.Date()),
      by = c("Team" = "team_picked")
    )
  
  if (nrow(new_bets) == 0) return(NULL)
  
  next_id <- max(as.integer(str_remove(ledger$bet_id, "BET_")), 1000) + 1
  
  new_entries <- tibble(
    bet_id            = paste0("BET_", next_id:(next_id + nrow(new_bets) - 1)),
    bet_date          = Sys.Date(),
    matchup           = new_bets$Matchup,
    team_picked       = new_bets$Team,
    american_odds     = new_bets$Line,
    closing_odds      = new_bets$sharp_line, # Will update to terminal close
    model_prob        = new_bets$Model_Win_Prob,
    ev_pct            = new_bets$EV_Percent,
    stake_units       = new_bets$Bankroll_Rec,
    result            = "PENDING",
    status            = "PENDING",
    decimal_odds      = if_else(new_bets$Line > 0, (new_bets$Line / 100) + 1, (100 / abs(new_bets$Line)) + 1),
    profit_units      = 0.0,
    closing_dec       = NA_real_,
    closing_fair_prob = NA_real_,
    clv_pct           = NA_real_,
    beat_clv          = NA
  )
  
  ledger <- bind_rows(ledger, new_entries)
  saveRDS(ledger, LEDGER_FILE)
  cat(sprintf("[LEDGER] Stored %d active value picks as PENDING for %s.\n", nrow(new_entries), Sys.Date()))
}

# 3. Grade Completed Bets Against Exact Game Dates & Compute CLV
grade_yesterday_bets <- function() {
  cat("\n==================================================================\n")
  cat("     GRADING PENDING BETS & CLOSING LINE VALUE (CLV) ETL          \n")
  cat("==================================================================\n\n")
  
  append_todays_picks()
  ledger <- get_bet_ledger()
  box_scores <- if (file.exists(CACHE_TEAM_BOX)) readRDS(CACHE_TEAM_BOX) else tibble()
  
  pending <- ledger |> filter(status == "PENDING")
  
  if (nrow(pending) == 0) {
    cat("No pending bets found to grade. Ledger is up to date.\n")
  } else {
    cat(sprintf("Evaluating %d pending bets against official box scores...\n", nrow(pending)))
    
    # Exact Match: team_picked + game_date
    game_results <- box_scores |>
      mutate(game_date = as.Date(game_date)) |>
      select(game_date, team_name = team_short_display_name, team_winner) |>
      distinct()
    
    graded_pending <- pending |>
      inner_join(
        game_results,
        by = c("team_picked" = "team_name", "bet_date" = "game_date")
      ) |>
      mutate(
        result       = if_else(team_winner == TRUE, "WIN", "LOSS"),
        status       = "RESOLVED",
        profit_units = if_else(result == "WIN", round(stake_units * (decimal_odds - 1), 2), -stake_units),
        
        # Realized CLV Calculation
        closing_dec  = if_else(closing_odds > 0, (closing_odds / 100) + 1, (100 / abs(closing_odds)) + 1),
        closing_fair_prob = american_to_prob(closing_odds) / (american_to_prob(closing_odds) + 0.50),
        clv_pct      = round(((decimal_odds * closing_fair_prob) - 1) * 100, 2),
        beat_clv     = clv_pct > 0
      ) |>
      select(-team_winner)
    
    if (nrow(graded_pending) > 0) {
      ledger <- bind_rows(
        ledger |> filter(!bet_id %in% graded_pending$bet_id),
        graded_pending
      )
      saveRDS(ledger, LEDGER_FILE)
      cat(sprintf("[SUCCESS] Resolved %d completed bets with CLV metrics.\n", nrow(graded_pending)))
    } else {
      cat("[INFO] Pending bets are active and scheduled for future resolution.\n")
    }
  }
  
  # 4. Compute Rolling Quantitative Benchmarks
  resolved <- ledger |> filter(status == "RESOLVED") |> arrange(bet_date)
  
  calc_stats <- function(df) {
    if (nrow(df) == 0) return(list(win_rate = 0, roi = 0, units = 0, total_bets = 0, avg_clv = 0, beat_clv_pct = 0))
    wins     <- sum(df$result == "WIN")
    total    <- nrow(df)
    staked   <- sum(df$stake_units)
    profit   <- sum(df$profit_units)
    clv_mean <- mean(df$clv_pct, na.rm = TRUE)
    beat_pct <- mean(df$beat_clv, na.rm = TRUE) * 100
    
    list(
      win_rate     = round((wins / total) * 100, 1),
      roi          = if (staked > 0) round((profit / staked) * 100, 1) else 0,
      units        = round(profit, 2),
      total_bets   = total,
      avg_clv      = round(clv_mean, 2),
      beat_clv_pct = round(beat_pct, 1)
    )
  }
  
  metrics <- list(
    last_7   = calc_stats(resolved |> filter(bet_date >= (Sys.Date() - 7))),
    last_30  = calc_stats(resolved |> filter(bet_date >= (Sys.Date() - 30))),
    all_time = calc_stats(resolved),
    ledger   = resolved |> mutate(cum_units = cumsum(profit_units))
  )
  
  saveRDS(metrics, METRICS_FILE)
  
  cat(sprintf("──────────────────────────────────────────────────────────────────\n"))
  cat(sprintf("7-Day  : Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Beat CLV: %4.1f%%\n",
              metrics$last_7$win_rate, metrics$last_7$roi, metrics$last_7$avg_clv, metrics$last_7$beat_clv_pct))
  cat(sprintf("30-Day : Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Beat CLV: %4.1f%%\n",
              metrics$last_30$win_rate, metrics$last_30$roi, metrics$last_30$avg_clv, metrics$last_30$beat_clv_pct))
  cat(sprintf("All-Time: Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Total Units: %+5.2f U\n",
              metrics$all_time$win_rate, metrics$all_time$roi, metrics$all_time$avg_clv, metrics$all_time$units))
  cat(sprintf("──────────────────────────────────────────────────────────────────\n"))
  cat(sprintf("Saved performance metrics to: %s\n\n", METRICS_FILE))
  
  return(metrics)
}

# Auto-execute when run
grade_yesterday_bets()