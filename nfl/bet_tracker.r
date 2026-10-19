# ==============================================================================
# bet_tracker.r (NFL port of WNBA Analytics' bet_tracker.r - lowercase .r extension kept
# to match that repo's naming, which itself carried it from an NBA original; not "fixed"
# here in case a future orchestrator/.bat convention is sensitive to the exact filename.)
# NFL Bet Ledger & Automated Rolling Accuracy + CLV Grader
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/bet_tracker.r
#
# Built to close docs/HANDOFF.md Known Issue #2 ("risk_management_engine.R has no real
# ledger"): risk_management_engine.R's load_real_ledger()/run_risk_management() already
# had a documented, dormant "REAL_LEDGER" code path (CACHE_BETTING_LEDGER, config.R) that
# has never had a writer until this file. Once this script has been run at least once and
# accumulated real RESOLVED bets, run_risk_management() will use them instead of its
# SYNTHETIC_FALLBACK seed ledger automatically - no changes needed there beyond reading
# the now-real CACHE_BETTING_LEDGER constant (see that file's own header for the exact
# schema contract this ledger satisfies: bet_id, bet_date, stake_units, profit_units,
# clv_pct, beat_clv, status).
#
# DELIBERATE DEVIATIONS from the WNBA original, both driven by this repo's stricter
# provenance/honesty conventions (SYNTHETIC_FALLBACK/market_data_source tagging - see
# CLAUDE.md and market_odds_engine.R's own Finding M-5 comments):
#   1. NO fabricated seed ledger. WNBA's get_bet_ledger() cold-starts with 60 fake
#      WIN/LOSS rows tagged status="RESOLVED" - i.e. fabricated results are indistinguishable
#      from real ones once mixed into a ledger risk_management_engine.R will read as
#      "REAL_LEDGER". That is exactly the class of silent-provenance-loss bug this repo's
#      SYNTHETIC_FALLBACK/market_data_source markers exist to prevent elsewhere (M-5, H-1,
#      the risk report's own data_source field). This ledger cold-starts EMPTY instead
#      (0 rows) - risk_management_engine.R's existing "real ledger exists but has zero
#      RESOLVED bets; falling through to synthetic seed ledger" branch (already written,
#      previously unreachable dead code) handles that cleanly and correctly, with the
#      SYNTHETIC_FALLBACK tag staying honest until real graded bets exist.
#   2. Only records picks whose market_data_source == "LIVE_ODDS_API" (config.R's
#      NFL_TEAMS-based Status/EV/Bankroll_Rec columns from CACHE_LATEST_VALUE_BETS). A
#      SYNTHETIC_FALLBACK fixture slate's fabricated matchups/odds/dates (see
#      market_odds_engine.R's fetch_market_odds() header) must never be recorded into a
#      ledger meant to represent real bets - this repo has no equivalent gap to WNBA's
#      version, which didn't have a synthetic-fixture-slate concept to guard against.
#   3. Grading joins by (team_picked, bet_date) against CACHE_SCHEDULES (nflreadr's
#      real game results), not WNBA's CACHE_TEAM_BOX box-score table - NFL has no
#      per-team box-score cache in this repo's DAG; CACHE_SCHEDULES already carries
#      home_score/away_score per game_id, pivoted to long (one row per team per game)
#      below. team_picked is an NFL_TEAMS ABBREVIATION (market_odds_engine.R's
#      resolve_team_name() returns the abbreviation, not the full name, unlike WNBA's
#      version - see that file's header point 3) and CACHE_SCHEDULES$home_team/away_team
#      already use the same abbreviation convention, so no translation is needed.
#
# KNOWN LIMITATION (carried over from WNBA, not newly introduced here): `closing_odds`
# is recorded as the ODDS SNAPSHOT'S consensus/sharp line at BET TIME (CACHE_LATEST_
# VALUE_BETS$sharp_line), not the game's true closing line at kickoff - this repo has no
# separate "poll again right before kickoff" job yet. CLV computed from it is therefore an
# approximation (closer to "edge vs. the market's current consensus" than true CLV) -
# documented here rather than silently mislabeled as true closing-line value.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
})

source("config.R")
source("logging_utils.R")
source("market_odds_engine.R")  # -> american_to_decimal(), american_to_prob()
# NOTE: must be set AFTER sourcing market_odds_engine.R, which sets its own .LOG_SCRIPT at its
# top level via source(..., local = FALSE) - setting this before that line would be silently
# clobbered.
.LOG_SCRIPT <- "bet_tracker.r"

METRICS_FILE <- file.path(CACHE_DIR, "rolling_bet_metrics.rds")

# ------------------------------------------------------------------------------------------
# 1. Initialize or Load Persistent Ledger
# Cold-starts EMPTY (see header point 1) - no fabricated seed rows. Schema matches
# risk_management_engine.R::load_real_ledger()'s transmute() contract exactly.
# ------------------------------------------------------------------------------------------
get_bet_ledger <- function() {
  if (file.exists(CACHE_BETTING_LEDGER)) {
    readRDS(CACHE_BETTING_LEDGER)
  } else {
    log_info("No betting ledger found; cold-starting an EMPTY real ledger (no fabricated seed rows - see file header).",
             call = "get_bet_ledger()", path = CACHE_BETTING_LEDGER)
    empty_ledger <- tibble(
      bet_id            = character(0), bet_date = as.Date(character(0)),
      matchup           = character(0), team_picked = character(0),
      american_odds     = numeric(0), closing_odds = numeric(0),
      model_prob        = numeric(0), ev_pct = numeric(0),
      stake_units       = numeric(0), result = character(0), status = character(0),
      decimal_odds      = numeric(0), profit_units = numeric(0),
      closing_dec       = numeric(0), closing_fair_prob = numeric(0),
      clv_pct           = numeric(0), beat_clv = logical(0)
    )
    saveRDS(empty_ledger, CACHE_BETTING_LEDGER)
    empty_ledger
  }
}

# ------------------------------------------------------------------------------------------
# 2. Append Today's Real Value Picks to the Ledger as PENDING
# Only records real LIVE_ODDS_API picks with an actual recommended stake (see header
# point 2) - never a SYNTHETIC_FALLBACK fixture row, and never a $0-stake row that was
# gated out by MIN_SAMPLE_GAMES_FOR_STAKE or LONGSHOT_DECIMAL_ODDS_CAP upstream (those
# rows carry a real edge_flag but Bankroll_Rec == 0 by construction - not a bet anyone
# would actually place).
# ------------------------------------------------------------------------------------------
append_todays_picks <- function() {
  if (!file.exists(CACHE_LATEST_VALUE_BETS)) {
    log_warn("No cache/latest_value_bets.rds found; nothing to append.", call = "append_todays_picks()")
    return(invisible(NULL))
  }

  picks <- readRDS(CACHE_LATEST_VALUE_BETS) |>
    filter(grepl("VALUE|SHARP", Status), Bankroll_Rec > 0, market_data_source == "LIVE_ODDS_API")

  if (nrow(picks) == 0) {
    log_info("No real, staked value picks in the latest slate; nothing to append.", call = "append_todays_picks()")
    return(invisible(NULL))
  }

  ledger <- get_bet_ledger()

  # Avoid duplicate entries for the same team on the same bet date (re-running
  # market_odds_engine.R/bet_tracker.r same-day should not double-record a pick).
  already_recorded <- ledger |> filter(bet_date == as.Date(picks$game_date[1]))
  new_bets <- picks |> anti_join(already_recorded, by = c("Team" = "team_picked"))

  if (nrow(new_bets) == 0) {
    log_info("All of today's real value picks are already recorded; nothing new to append.",
             call = "append_todays_picks()")
    return(invisible(NULL))
  }

  existing_ids <- suppressWarnings(as.integer(str_remove(ledger$bet_id, "BET_")))
  next_id <- max(existing_ids, 1000, na.rm = TRUE) + 1

  new_entries <- tibble(
    bet_id            = paste0("BET_", next_id:(next_id + nrow(new_bets) - 1)),
    bet_date          = as.Date(new_bets$game_date),
    matchup           = new_bets$Matchup,
    team_picked       = new_bets$Team,
    american_odds     = new_bets$Line,
    closing_odds      = new_bets$sharp_line,  # bet-time consensus snapshot - see header's Known Limitation
    model_prob        = new_bets$Model_Win_Prob,
    ev_pct            = new_bets$EV_Percent,
    stake_units       = new_bets$Bankroll_Rec,
    result            = "PENDING",
    status            = "PENDING",
    decimal_odds      = american_to_decimal(new_bets$Line),
    profit_units      = 0.0,
    closing_dec       = NA_real_,
    closing_fair_prob = NA_real_,
    clv_pct           = NA_real_,
    beat_clv          = NA
  )

  ledger <- bind_rows(ledger, new_entries)
  saveRDS(ledger, CACHE_BETTING_LEDGER)
  log_info(sprintf("Stored %d real value picks as PENDING for %s.", nrow(new_entries), new_bets$game_date[1]),
           call = "append_todays_picks()", n = nrow(new_entries))
  cat(sprintf("[LEDGER] Stored %d real value picks as PENDING for %s.\n", nrow(new_entries), new_bets$game_date[1]))
  invisible(new_entries)
}

# ------------------------------------------------------------------------------------------
# 3. Grade Completed Bets Against Real CACHE_SCHEDULES Results & Compute Approximate CLV
# CACHE_SCHEDULES is wide (one row per game, home_team/home_score/away_team/away_score) -
# pivoted to long (one row per team per game) below so a PENDING bet's team_picked can be
# matched directly, mirroring WNBA's box-score join shape (see header point 3).
# ------------------------------------------------------------------------------------------
grade_pending_bets <- function() {
  cat("\n==================================================================\n")
  cat("       NFL BET LEDGER: GRADING PENDING BETS & CLV ETL              \n")
  cat("==================================================================\n\n")

  append_todays_picks()
  ledger <- get_bet_ledger()

  if (!file.exists(CACHE_SCHEDULES)) {
    log_warn("cache/schedules_cache.rds not found; cannot grade pending bets this run.",
             call = "grade_pending_bets()")
    return(invisible(ledger))
  }

  sch <- readRDS(CACHE_SCHEDULES) |>
    filter(!is.na(home_score), !is.na(away_score)) |>
    mutate(gameday = as.Date(gameday))

  game_results <- bind_rows(
    sch |> transmute(team = home_team, game_date = gameday, won = home_score > away_score),
    sch |> transmute(team = away_team, game_date = gameday, won = away_score > home_score)
  ) |> distinct()

  pending <- ledger |> filter(status == "PENDING")

  if (nrow(pending) == 0) {
    cat("No pending bets found to grade. Ledger is up to date.\n")
  } else {
    cat(sprintf("Evaluating %d pending bets against real game results...\n", nrow(pending)))

    graded_pending <- pending |>
      inner_join(game_results, by = c("team_picked" = "team", "bet_date" = "game_date")) |>
      mutate(
        result       = if_else(won, "WIN", "LOSS"),
        status       = "RESOLVED",
        profit_units = if_else(won, round(stake_units * (decimal_odds - 1), 2), -stake_units),

        closing_dec  = american_to_decimal(closing_odds),
        closing_fair_prob = {
          imp <- american_to_prob(closing_odds)
          imp / (imp + 0.50)
        },
        clv_pct  = round(((decimal_odds * closing_fair_prob) - 1) * 100, 2),
        beat_clv = clv_pct > 0
      ) |>
      select(-won)

    if (nrow(graded_pending) > 0) {
      ledger <- bind_rows(
        ledger |> filter(!bet_id %in% graded_pending$bet_id),
        graded_pending
      )
      saveRDS(ledger, CACHE_BETTING_LEDGER)
      log_info(sprintf("Resolved %d completed bets with CLV metrics.", nrow(graded_pending)),
               call = "grade_pending_bets()", n = nrow(graded_pending))
      cat(sprintf("[SUCCESS] Resolved %d completed bets with CLV metrics.\n", nrow(graded_pending)))
    } else {
      cat("[INFO] Pending bets' games have not been played yet; nothing to grade this run.\n")
    }
  }

  resolved <- ledger |> filter(status == "RESOLVED") |> arrange(bet_date)

  calc_stats <- function(df) {
    if (nrow(df) == 0) return(list(win_rate = 0, roi = 0, units = 0, total_bets = 0, avg_clv = 0, beat_clv_pct = 0))
    wins   <- sum(df$result == "WIN")
    total  <- nrow(df)
    staked <- sum(df$stake_units)
    profit <- sum(df$profit_units)
    list(
      win_rate     = round((wins / total) * 100, 1),
      roi          = if (staked > 0) round((profit / staked) * 100, 1) else 0,
      units        = round(profit, 2),
      total_bets   = total,
      avg_clv      = round(mean(df$clv_pct, na.rm = TRUE), 2),
      beat_clv_pct = round(mean(df$beat_clv, na.rm = TRUE) * 100, 1)
    )
  }

  metrics <- list(
    last_7   = calc_stats(resolved |> filter(bet_date >= (Sys.Date() - 7))),
    last_30  = calc_stats(resolved |> filter(bet_date >= (Sys.Date() - 30))),
    all_time = calc_stats(resolved),
    ledger   = resolved |> mutate(cum_units = cumsum(profit_units))
  )
  saveRDS(metrics, METRICS_FILE)

  cat(sprintf("7-Day   : Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Beat CLV: %4.1f%% | n=%d\n",
              metrics$last_7$win_rate, metrics$last_7$roi, metrics$last_7$avg_clv, metrics$last_7$beat_clv_pct, metrics$last_7$total_bets))
  cat(sprintf("30-Day  : Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Beat CLV: %4.1f%% | n=%d\n",
              metrics$last_30$win_rate, metrics$last_30$roi, metrics$last_30$avg_clv, metrics$last_30$beat_clv_pct, metrics$last_30$total_bets))
  cat(sprintf("All-Time: Win Rate: %5.1f%% | ROI: %+5.1f%% | Avg CLV: %+4.2f%% | Total Units: %+5.2fU | n=%d\n",
              metrics$all_time$win_rate, metrics$all_time$roi, metrics$all_time$avg_clv, metrics$all_time$units, metrics$all_time$total_bets))
  cat(sprintf("\nSaved performance metrics to: %s\n\n", METRICS_FILE))

  metrics
}

# ------------------------------------------------------------------------------------------
# Exposed entry point, matching this repo's run_stage() call_fn convention (see
# team_ratings_engine.R/market_odds_engine.R): no required args, returns TRUE/FALSE. No
# sys.nframe()/!interactive() auto-run guard - explicit invocation only.
# ------------------------------------------------------------------------------------------
run_bet_tracker <- function() {
  result <- tryCatch({
    grade_pending_bets()
  }, error = function(e) {
    log_error("run_bet_tracker() failed.", condition = e, call = "run_bet_tracker()")
    NULL
  })
  !is.null(result)
}
