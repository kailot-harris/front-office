# ==============================================================================
# prediction_accuracy_logger.R (WNBA — NEW FILE, standalone feature build)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/prediction_accuracy_logger.R
#
# Daily, structured, append-only log of the model's OWN pre-game win-probability
# predictions vs. real outcomes — distinct from bet_tracker.r's betting ledger
# (which only tracks games that passed the EV/CLV +EV filter, a biased subset).
# Captures every real game the model priced, whether or not it became a bet, to
# support future accuracy/calibration/drift analysis. Full rationale, schema, and
# phased plan: docs/PREDICTION_LOGGING_PLAN.md — this file follows that plan
# precisely; any deviation is called out inline below and in
# docs/task_assignments_phase2.md's dated section for this task.
#
# Mirrors bet_tracker.r's proven PENDING -> RESOLVED two-phase pattern
# (append_todays_picks() / grade_yesterday_bets()) rather than inventing a new
# structure. Reuses market_odds_engine.R::evaluate_betting_slate()'s real same-day
# output (cache/latest_value_bets.rds, Model_Win_Prob column) as the source of
# "today's real games + today's model prediction", instead of recomputing
# predictions independently, so the logged prediction matches exactly what the
# rest of the pipeline (EV, notify_bets) acted on that day.
#
# DEVIATION #1 (name resolution): market_odds_engine.R's resolve_team_name()/
# abbr_for() helpers are NOT sourced here, because market_odds_engine.R has an
# UNCONDITIONAL top-level call at its own tail (evaluate_betting_slate(), no
# sys.nframe() guard, unlike daily_ingest.R) — sourcing that file would silently
# re-trigger a live odds pull / rewrite cache/latest_value_bets.rds as a side
# effect of just wanting two helper functions. Instead, a small local .team_abbr()
# below does the same WNBA_TEAMS-based canonicalization directly.
#
# DEVIATION #2 (game_id is NOT joinable across sources — confirmed empirically
# this session, not assumed): cache/latest_value_bets.rds's game_id is The Odds
# API's hex event ID (e.g. "e1345bc3242e9236f8524205bb759ad3"); data/box_scores_
# cache.rds's game_id is ESPN's integer game ID. These are two different ID
# spaces. Per the plan's explicit fallback instruction, reconcile_predictions()
# joins on (team, game_date) instead — same JOIN SHAPE as bet_tracker.r's
# grade_yesterday_bets(), but with team identity normalized to box_scores_cache's
# actual short-nickname format (see reconcile_predictions() comments below). Note:
# a literal byte-for-byte copy of bet_tracker.r's join (team_picked full name ==
# team_short_display_name short nickname) would silently match zero rows, since
# those two columns use different name representations — flagged in Handoff Notes
# as a related pre-existing issue in bet_tracker.r, out of scope to fix per this
# task's Constraints.
#
# DEVIATION #3 (run_stage() call_fn parameter): run_stage() in run_full_pipeline.R
# sources a script and expects it to auto-execute at the top level (like bet_
# tracker.r's trailing grade_yesterday_bets() call). This file deliberately does
# NOT auto-run either function unconditionally on source, because the plan needs
# TWO separate run_stage() calls against the SAME file at two different DAG
# points (reconciliation early, prediction-logging later), each invoking a
# DIFFERENT one of this file's two functions. run_stage() was extended with a
# minimal, backward-compatible optional `call_fn` parameter (default NULL, so all
# 13 pre-existing run_stage() calls are byte-for-byte unaffected) that invokes a
# named function after sourcing — see run_full_pipeline.R for the two new call
# sites. When this file is Rscript'd directly (sys.nframe() == 0 at the bottom
# guard — verified empirically this session: source()'d code never sees nframe
# 0, so this block is dormant under run_stage()), both functions run once each,
# reconcile-then-log, for convenient standalone/manual use.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "prediction_accuracy_logger.R"

# Defines daily_box_ingest() WITHOUT auto-running it (verified empirically this
# session: sys.nframe() inside a source()'d file is never 0, so daily_ingest.R's
# own `if (sys.nframe() == 0) daily_box_ingest()` guard stays dormant here). This
# guarantees reconcile_predictions() can call daily_box_ingest() itself to force
# a fresh box_scores_cache.rds, defending against the real pre-existing gap that
# daily_ingest.R is not itself a stage in run_full_pipeline.R's DAG (see plan).
if (file.exists("daily_ingest.R")) {
  source("daily_ingest.R")
} else if (file.exists(file.path(PROJECT_DIR, "daily_ingest.R"))) {
  source(file.path(PROJECT_DIR, "daily_ingest.R"))
}
# daily_ingest.R sets its own .LOG_SCRIPT <- "daily_ingest.R" at its top level when
# sourced, which would otherwise silently mis-attribute every log_info()/log_warn()/
# log_error() call below (found and fixed during this session's Phase 4 verification —
# a real run showed log lines tagged [daily_ingest.R] for reconcile_predictions()/
# log_todays_predictions() calls). Reassert this file's own tag afterward.
.LOG_SCRIPT <- "prediction_accuracy_logger.R"

PRED_LOG_RDS            <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
PRED_LOG_CSV            <- file.path(CACHE_DIR, "prediction_accuracy_log.csv")
PRED_LOG_SCHEMA_VERSION <- 1L

# ------------------------------------------------------------------------------
# Canonical empty schema (schema_version column from day one — Best Practice #8)
# so saveRDS()/bind_rows() always produce a stable, typed column set even before
# any real row has ever been written.
# ------------------------------------------------------------------------------
.empty_prediction_log <- function() {
  tibble(
    schema_version            = integer(),
    game_id                   = character(),
    game_date                 = as.Date(character()),
    season                    = integer(),
    home_team                 = character(),
    away_team                 = character(),
    prediction_timestamp      = as.POSIXct(numeric(), origin = "1970-01-01"),
    predicted_home_win_prob   = double(),
    predicted_winner          = character(),
    model_rolling_window_size = integer(),
    model_margin_sigma        = double(),
    model_rotation_size       = integer(),
    model_offseason_method    = character(),
    injury_data_source        = character(),
    shot_quality_data_source  = character(),
    predicted_margin           = double(),
    contrib_net_diff           = double(),
    contrib_hca                = double(),
    contrib_fatigue            = double(),
    status                    = character(),
    actual_winner             = character(),
    correct                   = logical(),
    brier_component           = double(),
    log_loss_component        = double(),
    resolved_timestamp        = as.POSIXct(numeric(), origin = "1970-01-01")
  )
}

get_prediction_log <- function() {
  if (file.exists(PRED_LOG_RDS)) readRDS(PRED_LOG_RDS) else .empty_prediction_log()
}

save_prediction_log <- function(df) {
  saveRDS(df, PRED_LOG_RDS)
  utils::write.csv(df, PRED_LOG_CSV, row.names = FALSE, na = "")
  invisible(df)
}

# Full WNBA_TEAMS franchise name -> abbreviation. Local, deliberately NOT sourced
# from market_odds_engine.R (see DEVIATION #1 above).
.team_abbr <- function(full_name) {
  idx <- match(full_name, WNBA_TEAMS)
  if (!is.na(idx)) return(names(WNBA_TEAMS)[idx])
  s <- tolower(as.character(full_name))
  hit <- which(vapply(tolower(WNBA_TEAMS), function(fn) grepl(fn, s, fixed = TRUE) || grepl(s, fn, fixed = TRUE), logical(1)))
  if (length(hit) >= 1) return(names(WNBA_TEAMS)[hit[1]])
  NA_character_
}

# Snapshot of injury/shot-quality data provenance active right now (Best Practice
# #5 — config/provenance snapshotting), collapsed to one value per log call since
# both source caches are refreshed once per pipeline run, not per game.
.current_injury_data_source <- function() {
  if (!file.exists(CACHE_INJURY_DATA)) return("NO_DATA")
  inj <- tryCatch(readRDS(CACHE_INJURY_DATA), error = function(e) tibble())
  if (nrow(inj) > 0 && "data_source" %in% names(inj)) {
    paste(sort(unique(inj$data_source)), collapse = "+")
  } else {
    "NO_DATA"
  }
}

.current_shot_quality_data_source <- function() {
  sq_path <- file.path(CACHE_DIR, "team_shot_quality.rds")
  if (!file.exists(sq_path)) return("NO_DATA")
  sq <- tryCatch(readRDS(sq_path), error = function(e) tibble())
  if (nrow(sq) > 0 && "data_source" %in% names(sq)) {
    paste(sort(unique(sq$data_source)), collapse = "+")
  } else {
    "NO_DATA"
  }
}

# ------------------------------------------------------------------------------
# Phase 1, step 1: log_todays_predictions()
#
# Source of "today's real games + today's model prediction": cache/
# latest_value_bets.rds, written by market_odds_engine.R::evaluate_betting_slate()
# (Model_Win_Prob column) — the SAME cache bet_tracker.r::append_todays_picks()
# already reads, so this reuses the exact live computation the rest of the
# pipeline acted on, per the plan's Best Practice #3 (point-in-time correctness).
#
# Model_Win_Prob is the probability of whichever side (home or away) had the
# better EV that day (`team_picked`), NOT always the home team's probability.
# home_team/away_team are not retained as separate columns in latest_value_bets.
# rds's final output_table, but Matchup is always formatted "{away} vs. {home}"
# (verified against both market_odds_engine.R::fetch_market_odds()'s fixture
# fallback AND parse_multi_book_feed()'s live-API formatting, AND against a real
# cache pull inspected this session) — so home/away are recovered by splitting
# Matchup, then predicted_home_win_prob is derived: Model_Win_Prob if the picked
# Team is the home side, else 1 - Model_Win_Prob.
# ------------------------------------------------------------------------------
log_todays_predictions <- function() {
  tryCatch({
    val_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
    if (!file.exists(val_path)) {
      log_info("cache/latest_value_bets.rds not found (market_odds_engine.R has not produced a slate yet this session); skipping prediction logging.",
               call = "log_todays_predictions()")
      return(invisible(NULL))
    }

    slate <- readRDS(val_path)
    if (nrow(slate) == 0) {
      log_info("0 real games in latest_value_bets.rds (e.g. WNBA off-season or an empty slate); skipping prediction logging (Best Practice #6, trigger-gated).",
               call = "log_todays_predictions()")
      return(invisible(NULL))
    }

    parsed    <- str_split_fixed(slate$Matchup, " vs\\. ", 2)
    away_full <- parsed[, 1]
    home_full <- parsed[, 2]

    valid_idx <- nchar(away_full) > 0 & nchar(home_full) > 0
    if (any(!valid_idx)) {
      log_warn(sprintf("%d slate row(s) had an unparseable Matchup string; skipped.", sum(!valid_idx)),
               call = "log_todays_predictions()")
    }
    slate     <- slate[valid_idx, , drop = FALSE]
    away_full <- away_full[valid_idx]
    home_full <- home_full[valid_idx]

    if (nrow(slate) == 0) {
      log_warn("All slate rows had unparseable Matchup strings; nothing to log.", call = "log_todays_predictions()")
      return(invisible(NULL))
    }

    home_abbr <- vapply(home_full, .team_abbr, character(1), USE.NAMES = FALSE)
    away_abbr <- vapply(away_full, .team_abbr, character(1), USE.NAMES = FALSE)

    abbr_ok <- !is.na(home_abbr) & !is.na(away_abbr)
    if (any(!abbr_ok)) {
      log_warn(sprintf("%d slate row(s) had a team name that did not resolve to a WNBA_TEAMS abbreviation; skipped.", sum(!abbr_ok)),
               call = "log_todays_predictions()")
    }
    slate     <- slate[abbr_ok, , drop = FALSE]
    home_full <- home_full[abbr_ok]
    home_abbr <- home_abbr[abbr_ok]
    away_abbr <- away_abbr[abbr_ok]

    if (nrow(slate) == 0) {
      log_warn("No slate rows had resolvable team names; nothing to log.", call = "log_todays_predictions()")
      return(invisible(NULL))
    }

    predicted_home_win_prob <- if_else(slate$Team == home_full, slate$Model_Win_Prob, 1 - slate$Model_Win_Prob)

    now_ts <- Sys.time()

    new_rows <- tibble(
      schema_version            = PRED_LOG_SCHEMA_VERSION,
      game_id                   = as.character(slate$game_id),
      game_date                 = as.Date(slate$game_date),
      season                    = as.integer(CURRENT_SEASON),
      home_team                 = home_abbr,
      away_team                 = away_abbr,
      prediction_timestamp      = now_ts,
      predicted_home_win_prob   = as.double(predicted_home_win_prob),
      predicted_winner          = if_else(predicted_home_win_prob >= 0.5, home_abbr, away_abbr),
      predicted_margin           = as.double(slate$predicted_margin),
      contrib_net_diff           = as.double(slate$contrib_net_diff),
      contrib_hca                = as.double(slate$contrib_hca),
      contrib_fatigue            = as.double(slate$contrib_fatigue),
      model_rolling_window_size = as.integer(ROLLING_WINDOW_SIZE),
      model_margin_sigma        = as.double(WNBA_MARGIN_SIGMA),
      model_rotation_size       = as.integer(WNBA_ROTATION_SIZE),
      model_offseason_method    = as.character(OFFSEASON_METHOD),
      injury_data_source        = .current_injury_data_source(),
      shot_quality_data_source  = .current_shot_quality_data_source(),
      status                    = "PENDING",
      actual_winner             = NA_character_,
      correct                   = NA,
      brier_component           = NA_real_,
      log_loss_component        = NA_real_,
      resolved_timestamp        = as.POSIXct(NA)
    )

    existing_log <- get_prediction_log()

    # Idempotency (Best Practice #1): dedupe on game_id before inserting, exact
    # same discipline as bet_tracker.r::append_todays_picks(). Append-only (Best
    # Practice #2): a game_id already present (PENDING or RESOLVED) is never
    # re-inserted or overwritten here.
    dedup_rows <- new_rows |> anti_join(existing_log, by = "game_id")

    if (nrow(dedup_rows) == 0) {
      log_info("All of this slate's game_ids are already present in the prediction log; nothing new to append.",
               call = "log_todays_predictions()", slate_rows = nrow(new_rows))
      return(invisible(existing_log))
    }

    updated_log <- bind_rows(existing_log, dedup_rows)
    save_prediction_log(updated_log)

    log_info(sprintf("Logged %d new PENDING predictions.", nrow(dedup_rows)),
             call = "log_todays_predictions()", rows = nrow(dedup_rows), out_path = PRED_LOG_RDS)
    cat(sprintf("[PREDICTION LOG] Logged %d new PENDING predictions to %s.\n", nrow(dedup_rows), PRED_LOG_RDS))

    invisible(updated_log)
  }, error = function(e) {
    log_error("log_todays_predictions() failed.", condition = e, call = "log_todays_predictions()")
    warning(sprintf(">>> [PREDICTION LOG FAILED] log_todays_predictions(): %s", e$message))
    invisible(NULL)
  })
}

# ------------------------------------------------------------------------------
# Phase 1, step 2: reconcile_predictions()
#
# Defensively refreshes box scores via daily_box_ingest() first (defends against
# the real pre-existing gap that daily_ingest.R is not itself in run_full_
# pipeline.R's DAG — see plan). Joins PENDING rows against completed games. Per
# DEVIATION #2 above, game_id is NOT a valid join key across these two caches, so
# this falls back to bet_tracker.r's (team, game_date) join SHAPE — but with team
# identity normalized to box_scores_cache.rds's actual short-nickname format
# (team_short_display_name holds values like "Aces"/"Mystics", not full franchise
# names), since a literal copy of bet_tracker.r's full-name value would silently
# match zero rows.
# ------------------------------------------------------------------------------
reconcile_predictions <- function() {
  tryCatch({
    existing_log <- get_prediction_log()
    pending <- existing_log |> filter(status == "PENDING")

    if (nrow(pending) == 0) {
      log_info("No PENDING rows to reconcile.", call = "reconcile_predictions()")
      return(invisible(existing_log))
    }

    box_scores <- tryCatch({
      if (exists("daily_box_ingest", mode = "function")) {
        daily_box_ingest()
      } else if (file.exists(CACHE_TEAM_BOX)) {
        readRDS(CACHE_TEAM_BOX)
      } else {
        tibble()
      }
    }, error = function(e) {
      log_error("daily_box_ingest() failed during reconciliation; falling back to box_scores_cache.rds as-is on disk.",
                condition = e, call = "reconcile_predictions()")
      if (file.exists(CACHE_TEAM_BOX)) readRDS(CACHE_TEAM_BOX) else tibble()
    })

    if (is.null(box_scores) || nrow(box_scores) == 0) {
      log_info("box_scores_cache.rds unavailable/empty; nothing to reconcile against yet.",
               call = "reconcile_predictions()", pending_rows = nrow(pending))
      return(invisible(existing_log))
    }

    home_results <- box_scores |>
      filter(team_home_away == "home") |>
      mutate(game_date = as.Date(game_date)) |>
      select(game_date, home_team_short = team_short_display_name, home_winner = team_winner) |>
      distinct()

    # WNBA_TEAMS full-name -> single-word nickname (e.g. "Las Vegas Aces" -> "Aces"),
    # matching box_scores_cache.rds's team_short_display_name format exactly.
    pending2 <- pending |>
      mutate(.home_short = word(unname(WNBA_TEAMS[home_team]), -1))

    joined <- pending2 |>
      inner_join(home_results, by = c("game_date" = "game_date", ".home_short" = "home_team_short"))

    if (nrow(joined) == 0) {
      log_info("No PENDING rows matched a completed game in box_scores_cache.rds yet.",
               call = "reconcile_predictions()", pending_rows = nrow(pending))
      return(invisible(existing_log))
    }

    resolved <- joined |>
      mutate(
        .actual_home_win    = as.integer(home_winner),
        actual_winner       = if_else(home_winner, home_team, away_team),
        correct              = (predicted_winner == actual_winner),
        brier_component      = (predicted_home_win_prob - .actual_home_win)^2,
        .p_clamped           = pmin(pmax(predicted_home_win_prob, 1e-6), 1 - 1e-6),
        log_loss_component   = -(.actual_home_win * log(.p_clamped) + (1 - .actual_home_win) * log(1 - .p_clamped)),
        status               = "RESOLVED",
        resolved_timestamp   = Sys.time()
      ) |>
      select(-.home_short, -home_winner, -.actual_home_win, -.p_clamped)

    updated_log <- bind_rows(
      existing_log |> filter(!game_id %in% resolved$game_id),
      resolved
    ) |>
      select(all_of(names(existing_log)))

    save_prediction_log(updated_log)

    log_info(sprintf("Reconciled %d predictions against real completed-game outcomes.", nrow(resolved)),
             call = "reconcile_predictions()", rows = nrow(resolved), out_path = PRED_LOG_RDS)
    cat(sprintf("[PREDICTION LOG] Reconciled %d predictions.\n", nrow(resolved)))

    invisible(updated_log)
  }, error = function(e) {
    log_error("reconcile_predictions() failed.", condition = e, call = "reconcile_predictions()")
    warning(sprintf(">>> [PREDICTION LOG FAILED] reconcile_predictions(): %s", e$message))
    invisible(NULL)
  })
}

# ------------------------------------------------------------------------------
# Phase 3: summarize_prediction_accuracy() — thin, real analysis helper over
# RESOLVED rows. Not a dashboard tab (explicitly out of scope for this task —
# see Handoff Notes' follow-up note).
# ------------------------------------------------------------------------------
summarize_prediction_accuracy <- function(window = c("7d", "30d", "season", "all")) {
  window <- match.arg(window)
  resolved <- get_prediction_log() |> filter(status == "RESOLVED")

  empty_summary <- tibble(window = window, n = 0L, accuracy = NA_real_, brier_score = NA_real_, log_loss = NA_real_)
  if (nrow(resolved) == 0) return(empty_summary)

  filtered <- switch(window,
    "7d"     = resolved |> filter(game_date >= (Sys.Date() - 7)),
    "30d"    = resolved |> filter(game_date >= (Sys.Date() - 30)),
    "season" = resolved |> filter(season == CURRENT_SEASON),
    "all"    = resolved
  )

  if (nrow(filtered) == 0) return(empty_summary)

  tibble(
    window      = window,
    n           = nrow(filtered),
    accuracy    = round(mean(filtered$correct, na.rm = TRUE), 4),
    brier_score = round(mean(filtered$brier_component, na.rm = TRUE), 4),
    log_loss    = round(mean(filtered$log_loss_component, na.rm = TRUE), 4)
  )
}

# ------------------------------------------------------------------------------
# Standalone convenience auto-run (see DEVIATION #3 above): only fires when this
# file is Rscript'd directly (sys.nframe() == 0), never when source()'d by
# run_full_pipeline.R's run_stage() (verified empirically this session). Under
# run_stage(), the two new call sites in run_full_pipeline.R invoke exactly one
# of these two functions each, via run_stage()'s new optional `call_fn` param.
# ------------------------------------------------------------------------------
if (sys.nframe() == 0) {
  reconcile_predictions()
  log_todays_predictions()
}
