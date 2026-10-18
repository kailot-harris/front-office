# ==============================================================================
# risk_management_engine.R
# Phase 4 Upgrade: Dynamic Bankroll Drawdown Monitor & Stop-Loss Engine
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [RISK] Initializing Bankroll Risk & Drawdown Management Engine...")

compute_risk_state <- function(bet_history = NULL) {
  if (is.null(bet_history)) {
    if (file.exists("cache/bet_log.rds")) {
      bet_history <- readRDS("cache/bet_log.rds")
    } else {
      # Build simulated historical ledger
      set.seed(101)
      n_bets <- 120
      dates <- seq.Date(Sys.Date() - 40, Sys.Date(), length.out = n_bets)
      pnl_units <- rnorm(n_bets, mean = 0.15, sd = 1.05)
      clv_diff  <- rnorm(n_bets, mean = 0.022, sd = 0.035)
      
      bet_history <- tibble(
        bet_id = paste0("BET_", 1:n_bets),
        date = dates,
        stake = round(runif(n_bets, 0.5, 1.8), 2),
        pnl = round(pnl_units, 2),
        clv_pct = round(clv_diff * 100, 2),
        beat_clv = clv_diff > 0
      )
    }
  }
  
  # Calculate cumulative bankroll path (Base 100 units)
  cum_pnl <- cumsum(bet_history$pnl)
  bankroll_path <- 100 + cum_pnl
  high_water_mark <- cummax(bankroll_path)
  drawdown_units <- high_water_mark - bankroll_path
  drawdown_pct   <- (drawdown_units / high_water_mark) * 100
  
  current_dd_units <- tail(drawdown_units, 1)
  current_dd_pct   <- tail(drawdown_pct, 1)
  max_dd_units     <- max(drawdown_units)
  max_dd_pct       <- max(drawdown_pct)
  
  # Dynamic Kelly Scaling Rules
  # Normal: 0.25 (Quarter-Kelly)
  # Level 1 Drawdown (>= 3.0 Units): 0.175
  # Level 2 Drawdown (>= 5.0 Units): 0.10 (Capital Preservation)
  # Level 3 Halt (>= 8.0 Units): 0.00 (Circuit Breaker / Stop-Loss)
  
  if (current_dd_units >= 8.0) {
    active_kelly_mult <- 0.00
    risk_status <- "TRADING_HALT"
    status_msg <- "CRITICAL STOP-LOSS REACHED: Trading halted for strategy re-evaluation."
  } else if (current_dd_units >= 5.0) {
    active_kelly_mult <- 0.10
    risk_status <- "CAPITAL_PRESERVATION"
    status_msg <- "SEVERE DRAWDOWN: Kelly scaled to 0.10 (Tenth-Kelly preservation mode)."
  } else if (current_dd_units >= 3.0) {
    active_kelly_mult <- 0.175
    risk_status <- "CAUTION"
    status_msg <- "MODERATE DRAWDOWN: Kelly scaled down to 0.175."
  } else {
    active_kelly_mult <- 0.25
    risk_status <- "OPTIMAL"
    status_msg <- "NORMAL OPERATION: Bankroll within 1-sigma bounds (0.25 Kelly)."
  }
  
  # Rolling CLV Metrics
  d7_cutoff <- Sys.Date() - 7
  d30_cutoff <- Sys.Date() - 30
  
  bets_7d  <- bet_history %>% filter(date >= d7_cutoff)
  bets_30d <- bet_history %>% filter(date >= d30_cutoff)
  
  rolling_7d_clv  <- ifelse(nrow(bets_7d) > 0, mean(bets_7d$clv_pct, na.rm = TRUE), 0.0)
  rolling_30d_clv <- ifelse(nrow(bets_30d) > 0, mean(bets_30d$clv_pct, na.rm = TRUE), 0.0)
  beat_clv_rate   <- mean(bet_history$beat_clv, na.rm = TRUE) * 100
  
  risk_report <- list(
    timestamp = Sys.time(),
    current_bankroll = round(tail(bankroll_path, 1), 2),
    current_dd_units = round(current_dd_units, 2),
    current_dd_pct = round(current_dd_pct, 2),
    max_dd_units = round(max_dd_units, 2),
    max_dd_pct = round(max_dd_pct, 2),
    active_kelly_multiplier = active_kelly_mult,
    risk_status = risk_status,
    status_message = status_msg,
    rolling_7d_clv_pct = round(rolling_7d_clv, 2),
    rolling_30d_clv_pct = round(rolling_30d_clv, 2),
    beat_clv_rate_pct = round(beat_clv_rate, 2),
    total_bets_audited = nrow(bet_history),
    ledger = bet_history %>% mutate(
      bankroll = round(bankroll_path, 2),
      drawdown = round(drawdown_units, 2)
    )
  )
  
  saveRDS(risk_report, "cache/risk_state.rds")
  message(sprintf(">>> [RISK] State: %s | Active Kelly: %.3f | Drawdown: -%.2f Units (Max: -%.2f) | Beat-CLV: %.1f%%",
                  risk_status, active_kelly_mult, current_dd_units, max_dd_units, beat_clv_rate))
  
  return(risk_report)
}

if (!interactive()) {
  invisible(compute_risk_state())
}