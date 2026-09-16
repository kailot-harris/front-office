# ==============================================================================
# risk_management_engine.R (WNBA port)
# Phase 4 (T4) — Dynamic Bankroll Drawdown Monitor & Stop-Loss Engine
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/risk_management_engine.R
#
# Ported AS-IS per task_assignments.md's T4 brief item 5: bankroll/drawdown/
# Kelly-tier math is entirely sport-agnostic (bankroll units, not points or any
# WNBA/NBA-specific stat), so no logic changes beyond file paths/header comments.
# Per the agent's own risk-discipline instructions, the Kelly-tier thresholds
# (0.25 / 0.175 / 0.10 / 0.00 at 3/5/8-unit drawdown) are NOT loosened to
# "compensate" for WNBA's thinner betting markets — that thinness is a
# data-quality/dashboard-labeling concern (T5's job), not a reason to relax
# staking discipline here.
#
# FIXED (P3a, GAP_REMEDIATION_PLAN.md / agent9.md, wnba_bugfix_agent): this
# previously read the dead path "cache/bet_log.rds", which nothing in this repo
# ever wrote — every run silently fell back to the synthetic 120-bet seed
# ledger below. The real ledger bet_tracker.r actually writes/grades is
# "cache/betting_ledger.rds" (LEDGER_FILE in bet_tracker.r). That real ledger's
# schema differs from what this function's downstream math expects
# (bet_history$date/$pnl/$stake vs. the real ledger's $bet_date/$profit_units/
# $stake_units, plus PENDING rows with no realized outcome yet), so
# compute_risk_state() now reads the real path and adapts/renames columns
# in-place (see load_real_ledger() below) rather than changing bet_tracker.r's
# real ledger schema. The synthetic 120-bet fallback is KEPT for the cold-start
# case (fresh install, betting_ledger.rds not created yet) per Ground Rule 3 —
# it is simply no longer the only path ever taken.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
}
source("logging_utils.R")
.LOG_SCRIPT <- "risk_management_engine.R"

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [RISK] Initializing WNBA Bankroll Risk & Drawdown Management Engine...")

# Real-ledger adapter (P3a fix): bet_tracker.r's LEDGER_FILE
# ("cache/betting_ledger.rds") has columns bet_id/bet_date/matchup/team_picked/
# american_odds/closing_odds/model_prob/ev_pct/stake_units/result/status/
# decimal_odds/profit_units/closing_dec/closing_fair_prob/clv_pct/beat_clv
# (verified directly against bet_tracker.r's get_bet_ledger()/grade_yesterday_
# bets() — see this file's header comment). compute_risk_state()'s math below
# expects a bet_history tibble with $date, $pnl, $stake, $clv_pct, $beat_clv.
# clv_pct/beat_clv already match by name; date/pnl/stake need renaming from
# bet_date/profit_units/stake_units. Only RESOLVED bets are included — PENDING
# bets (profit_units == 0.0, clv_pct == NA by construction in bet_tracker.r)
# have no realized outcome yet and would understate drawdown/CLV if counted.
load_real_ledger <- function(path = "cache/betting_ledger.rds") {
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

compute_risk_state <- function(bet_history = NULL) {
  if (is.null(bet_history)) {
    if (file.exists("cache/betting_ledger.rds")) {
      bet_history <- tryCatch(load_real_ledger("cache/betting_ledger.rds"), error = function(e) {
        log_error("Falling back to synthetic seed ledger because the real ledger could not be read.",
                  condition = e, call = "compute_risk_state()")
        NULL
      })
      if (!is.null(bet_history) && nrow(bet_history) == 0) {
        log_warn("Real ledger exists but has zero RESOLVED bets; falling through to synthetic seed ledger.",
                 call = "compute_risk_state()")
        bet_history <- NULL  # no RESOLVED bets yet -> fall through to synthetic seed
      }
    } else {
      log_warn("cache/betting_ledger.rds does not exist yet; falling through to synthetic seed ledger.",
               call = "compute_risk_state()")
    }
    if (is.null(bet_history)) {
      # Build simulated historical ledger — clearly synthetic fallback, same
      # pattern/seed convention as the NBA original (bankroll units are
      # sport-agnostic, so no WNBA-specific recalibration is needed here).
      log_warn("Using SYNTHETIC_FALLBACK 120-bet seed ledger (no real RESOLVED bets available).",
               call = "compute_risk_state()", data_source = "SYNTHETIC_FALLBACK")
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

  # Dynamic Kelly Scaling Rules (unchanged from NBA — sport-agnostic bankroll
  # discipline, per the brief, NOT loosened for WNBA's thinner markets):
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
  log_info(sprintf("Risk state computed: %s | Kelly=%.3f | drawdown=-%.2f units (max -%.2f) | beat-CLV=%.1f%% | bets_audited=%d",
                    risk_status, active_kelly_mult, current_dd_units, max_dd_units, beat_clv_rate, nrow(bet_history)),
           call = "compute_risk_state()", risk_status = risk_status, bets_audited = nrow(bet_history),
           out_path = "cache/risk_state.rds")

  return(risk_report)
}

if (!interactive()) {
  invisible(compute_risk_state())
}
