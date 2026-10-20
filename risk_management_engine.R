# ==============================================================================
# risk_management_engine.R (NFL port of WNBA Analytics' risk_management_engine.R)
# Phase 5, Task P5-A (docs/task_assignments_phase4.md)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/risk_management_engine.R
#
# Ported per that task doc's Overview: WNBA's engine is entirely sport-agnostic
# (bankroll drawdown monitor / dynamic Kelly-multiplier stop-loss operating on
# bankroll units, not points or any sport-specific stat) - its own header states
# it was "ported AS-IS" from an NBA original with zero sport-specific logic
# changes. Ported the same way here: no NFL-specific math changes, just
# path/header/naming updates for this repo's conventions.
#
# The Kelly-tier thresholds (0.25 Normal / 0.175 at >=3.0 unit drawdown / 0.10
# at >=5.0 / 0.00 halt at >=8.0) are NOT loosened or "recalibrated" for NFL -
# per the task doc's Constraints section, this is deliberately sport-agnostic
# bankroll discipline, not something to tune without real data.
#
# UPDATE (model-quality remediation, Known Issue #2, 2026-09-17): bet_tracker.r now exists and
# writes a real ledger at CACHE_BETTING_LEDGER (config.R) - the SYNTHETIC_FALLBACK cold-start
# path below is no longer dead code's only outcome; it now genuinely activates only when
# CACHE_BETTING_LEDGER doesn't exist yet or has zero RESOLVED bets (e.g. a fresh checkout, or
# every recorded pick is still PENDING because its game hasn't been played yet). load_real_
# ledger() below's transmute() already matches bet_tracker.r's real ledger schema (bet_id/
# bet_date/stake_units/profit_units/clv_pct/beat_clv/status) - built to satisfy this contract,
# not the other way around, so no adapter/renaming was needed here (unlike WNBA's own
# load_real_ledger(), which needed one - see that repo's version for the class of mismatch this
# NFL repo's ledger was deliberately built to avoid).
#
# Per this repo's CLAUDE.md ("Process / conventions") this script does NOT
# auto-run on source via a `sys.nframe() == 0` / `!interactive()` footer - the
# sole callable is run_risk_management(), invoked explicitly by
# run_full_pipeline.R's run_stage() via its call_fn mechanism (see
# team_ratings_engine.R / run_full_pipeline.R for the established pattern: the
# stage function returns TRUE/FALSE, not the risk_report list itself).
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "risk_management_engine.R"

# ------------------------------------------------------------------------------------------
# Real-ledger adapter (ported from WNBA's load_real_ledger()). No real ledger exists in this
# repo yet (see header) - this function is dead code today, kept only so a future agent wiring
# up bet_tracker.r's real ledger has the adapter shape ready, matching WNBA's own precedent
# (WNBA's version adapts bet_tracker.r's real LEDGER_FILE columns bet_id/bet_date/
# stake_units/profit_units/clv_pct/beat_clv/status into this engine's expected
# date/stake/pnl/clv_pct/beat_clv shape, filtering to status == "RESOLVED" only).
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
      bet_id  = bet_id,
      date    = as.Date(bet_date),
      stake   = stake_units,
      pnl     = profit_units,
      clv_pct = clv_pct,
      beat_clv = beat_clv
    )
  log_info(sprintf("Loaded real betting ledger: %d RESOLVED bets (of %d total rows).", nrow(out), nrow(raw)),
           call = "load_real_ledger()", resolved_rows = nrow(out), total_rows = nrow(raw), path = path)
  out
}

# ------------------------------------------------------------------------------------------
# run_risk_management()
# No required args. Looks for a real betting ledger at a placeholder path
# ("cache/betting_ledger.rds" - will become CACHE_BETTING_LEDGER in config.R once
# bet_tracker.r exists and actually writes it). That file does not exist yet in this repo, so
# the lookup below simply does not find it and falls through cleanly to the SYNTHETIC_FALLBACK
# seed ledger, exactly like WNBA's cold-start path. Computes bankroll path, drawdown
# units/pct, dynamic Kelly-tier multiplier, rolling 7d/30d CLV, beat-CLV rate. Writes
# CACHE_RISK_STATE (config.R). Returns TRUE/FALSE (this repo's run_stage() call_fn contract -
# see team_ratings_engine.R for the established pattern).
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
        log_warn(sprintf("%s does not exist yet (bet_tracker.r has not run in this environment yet); falling through to synthetic seed ledger.", real_ledger_path),
                 call = "run_risk_management()")
      }

      if (is.null(bet_history)) {
        # Build simulated historical ledger - clearly synthetic fallback, same pattern/seed
        # convention as the WNBA/NBA original (bankroll units are sport-agnostic, so no
        # NFL-specific recalibration is needed here).
        log_warn("Using SYNTHETIC_FALLBACK 120-bet seed ledger (no real RESOLVED bets available). This is simulated P&L, NOT real betting results.",
                 call = "run_risk_management()", data_source = "SYNTHETIC_FALLBACK")
        data_source <- "SYNTHETIC_FALLBACK"
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

    # Dynamic Kelly Scaling Rules (unchanged from WNBA/NBA - sport-agnostic bankroll
    # discipline, per the task doc's Constraints, NOT loosened/tightened for NFL):
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
      data_source = data_source,  # "SYNTHETIC_FALLBACK" | "REAL_LEDGER" | "CALLER_SUPPLIED" -
                                   # a future reader MUST check this before trusting any P&L
                                   # figure below as real.
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
