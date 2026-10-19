# ==============================================================================
# mlb_risk_management_engine.R (MLB port of NFL / WNBA risk_management_engine.R)
# Phase 5, Issue #20: Bankroll Drawdown Monitor & Dynamic Kelly Stop-Loss Engine
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_risk_management_engine.R
#
# Ported AS-IS per docs/MLB_IMPLEMENTATION_PLAN.md Phase 5 and Issue #20:
# The risk management engine is entirely sport-agnostic (bankroll drawdown monitor
# and dynamic Kelly-multiplier stop-loss operating on bankroll units, not points,
# runs, or any sport-specific stat). It matches the sibling NFL/WNBA implementations
# with zero math changes, updating only path/header/naming conventions.
#
# The Kelly-tier thresholds:
#   - Normal (current_dd < 3.0 units): 0.25 (Quarter-Kelly, OPTIMAL)
#   - Level 1 Drawdown (>= 3.0 units): 0.175 (CAUTION)
#   - Level 2 Drawdown (>= 5.0 units): 0.10 (Tenth-Kelly, CAPITAL_PRESERVATION)
#   - Level 3 Halt (>= 8.0 units): 0.00 (Circuit Breaker / Stop-Loss, TRADING_HALT)
# These rules are sport-agnostic bankroll discipline, not tuned or loosened.
#
# Data Ingestion & Cold-Start Fallback:
# Checks for real betting ledger at CACHE_BETTING_LEDGER (config.R). If missing or
# containing 0 resolved bets, seamlessly activates SYNTHETIC_FALLBACK (reproducible
# seed 101, 120 synthetic bets), matching the sibling pattern.
#
# Per repo conventions, this script does NOT auto-run on source via sys.nframe() == 0.
# The sole callable is run_risk_management(), invoked explicitly by
# run_full_pipeline.R's run_stage() via its call_fn mechanism, returning TRUE/FALSE.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_risk_management_engine.R"

# ------------------------------------------------------------------------------------------
# Real-ledger adapter (ported from sibling repos' load_real_ledger()).
# Adapts real betting ledger rows (bet_id, bet_date, stake_units, profit_units,
# clv_pct, beat_clv, status) into this engine's expected shape, filtering to
# status == "RESOLVED" only.
# ------------------------------------------------------------------------------------------
load_real_ledger <- function(path) {
  raw <- tryCatch(readRDS(path), error = function(e) {
    log_error(sprintf("Real ledger at %s is missing/corrupted; readRDS() failed.", path),
              condition = e, call = "load_real_ledger()", path = path)
    stop(e)
  })
  out <- raw %>%
    filter(status == "RESOLVED") %>%
    arrange(bet_date) %>%
    transmute(
      bet_id   = bet_id,
      date     = as.Date(bet_date),
      stake    = stake_units,
      pnl      = profit_units,
      clv_pct  = clv_pct,
      beat_clv = beat_clv
    )
  log_info(sprintf("Loaded real betting ledger: %d RESOLVED bets (of %d total rows).", nrow(out), nrow(raw)),
           call = "load_real_ledger()", resolved_rows = nrow(out), total_rows = nrow(raw), path = path)
  out
}

# ------------------------------------------------------------------------------------------
# run_risk_management()
# Checks for a real betting ledger at CACHE_BETTING_LEDGER. If missing or empty,
# falls through cleanly to the SYNTHETIC_FALLBACK seed ledger (seed 101, 120 bets).
# Computes bankroll path, drawdown units/pct, dynamic Kelly-tier multiplier,
# rolling 7d/30d CLV, beat-CLV rate. Writes CACHE_RISK_STATE (config.R).
# Returns TRUE on success, FALSE on failure.
# ------------------------------------------------------------------------------------------
run_risk_management <- function(bet_history = NULL) {
  log_info("Starting risk management engine (bankroll drawdown / Kelly-tier stop-loss)...",
           call = "run_risk_management()")

  tryCatch({
    real_ledger_path <- CACHE_BETTING_LEDGER
    data_source <- NA_character_

    if (is.null(bet_history)) {
      if (file.exists(real_ledger_path)) {
        bet_history <- tryCatch(load_real_ledger(real_ledger_path), error = function(e) {
          log_error("Falling back to synthetic seed ledger because the real ledger could not be read.",
                    condition = e, call = "run_risk_management()")
          NULL
        })
        if (!is.null(bet_history) && nrow(bet_history) == 0) {
          log_warn("Real ledger exists but has zero RESOLVED bets; falling through to synthetic seed ledger.",
                   call = "run_risk_management()")
          bet_history <- NULL  # no RESOLVED bets yet -> fall through to synthetic seed
        }
        if (!is.null(bet_history)) data_source <- "REAL_LEDGER"
      } else {
        log_warn(sprintf("%s does not exist yet; falling through to synthetic seed ledger.", real_ledger_path),
                 call = "run_risk_management()")
      }

      if (is.null(bet_history)) {
        # Build simulated historical ledger - clearly synthetic fallback, same pattern/seed
        # convention as sibling repos (bankroll units are sport-agnostic).
        log_warn("Using SYNTHETIC_FALLBACK 120-bet seed ledger (no real RESOLVED bets available). This is simulated P&L, NOT real betting results.",
                 call = "run_risk_management()", data_source = "SYNTHETIC_FALLBACK")
        data_source <- "SYNTHETIC_FALLBACK"
        set.seed(101)
        n_bets <- 120
        dates <- seq.Date(Sys.Date() - 40, Sys.Date(), length.out = n_bets)
        pnl_units <- rnorm(n_bets, mean = 0.15, sd = 1.05)
        clv_diff  <- rnorm(n_bets, mean = 0.022, sd = 0.035)

        bet_history <- tibble(
          bet_id   = paste0("BET_", 1:n_bets),
          date     = dates,
          stake    = round(runif(n_bets, 0.5, 1.8), 2),
          pnl      = round(pnl_units, 2),
          clv_pct  = round(clv_diff * 100, 2),
          beat_clv = clv_diff > 0
        )
      }
    } else {
      data_source <- "CALLER_SUPPLIED"
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

    # Dynamic Kelly Scaling Rules (unchanged from WNBA/NBA/NFL - sport-agnostic bankroll
    # discipline, per the task doc's Constraints, NOT loosened/tightened for MLB):
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
      data_source = data_source,  # "SYNTHETIC_FALLBACK" | "REAL_LEDGER" | "CALLER_SUPPLIED"
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

    saveRDS(risk_report, CACHE_RISK_STATE)

    log_info(sprintf("Risk state computed [data_source=%s]: %s | Kelly=%.3f | drawdown=-%.2f units (max -%.2f) | beat-CLV=%.1f%% | bets_audited=%d",
                      data_source, risk_status, active_kelly_mult, current_dd_units, max_dd_units, beat_clv_rate, nrow(bet_history)),
             call = "run_risk_management()", data_source = data_source, risk_status = risk_status,
             bets_audited = nrow(bet_history), out_path = CACHE_RISK_STATE)

    TRUE
  }, error = function(e) {
    log_error("Risk management engine failed.", condition = e, call = "run_risk_management()")
    FALSE
  })
}
