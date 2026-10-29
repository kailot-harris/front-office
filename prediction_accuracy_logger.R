# ==============================================================================
# prediction_accuracy_logger.R
#
# Daily, structured, append-only log of the model's pre-game win-probability
# predictions vs. realized game outcomes — distinct from bet_tracker.r's betting
# ledger (which only tracks games passing the EV/CLV filter).
#
# Reconciles PENDING predictions against official completed box scores in
# box_scores_cache.rds, computing Brier score components, log-loss, and calibration
# diagnostics for wiring into Tab 6 of the terminal dashboard.
# Follows the proven sibling design from WNBA Analytics & NFL Analytics.
# ==============================================================================

# This file's own directory, derived rather than hardcoded. It used to be
# `PROJECT_DIR <- "c:/Users/..."` followed by `setwd(PROJECT_DIR)`, which ran
# before config.R got a say and so defeated the worktree-safe derivation in
# config.R: from a git worktree on the authoring machine the hardcoded path
# still exists, so setwd() silently relocated execution into the main checkout
# and this stage read that checkout's config and caches. Every path below is
# absolute (CACHE_DIR / PROJECT_DIR), so nothing needs the working directory.
# Bootstrap has to live in each entrypoint - it is what finds config.R - but it
# is the same two cases config.R handles: `Rscript this_file.R` (--file=) and
# `source("this_file.R")` (the `ofile` of an enclosing source() frame).
.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages({
  library(tidyverse)
})

# Sourced by absolute path: config.R defines PROJECT_DIR and CACHE_DIR from its
# own location, so it resolves to this checkout, worktree or not. `local = TRUE`
# puts those definitions in whatever environment this file is being loaded into
# rather than always the global one - identical under run_stage() (which sources
# this file into the global environment anyway) and what lets a test load the
# whole stage into a throwaway environment.
source(file.path(.THIS_DIR, "config.R"), local = TRUE)
source(file.path(.THIS_DIR, "live_calibration.R"), local = TRUE)
# `resolve_team_name()` - the single shared 30-branch nickname resolver. This
# file used to carry its own byte-identical copy as `.resolve_team_name`
# (issue 24); two copies of a 30-branch lookup table drift.
source(file.path(.THIS_DIR, "team_name_resolver.R"), local = TRUE)

PRED_LOG_RDS <- if (exists("CACHE_PREDICTION_LOG")) CACHE_PREDICTION_LOG else file.path(CACHE_DIR, "prediction_accuracy_log.rds")
PRED_LOG_CSV <- file.path(CACHE_DIR, "prediction_accuracy_log.csv")
PRED_LOG_UNRESOLVABLE_AFTER_DAYS <- 7L

# --- SCHEDULE SPINE CONTRACT (issue 24) -------------------------------------
# The active slate is parsed out of bookmaker feeds (market_odds_engine.R). A
# bookmaker feed can mis-pair teams: issue 24 logged four rows whose
# (date, home, away) triple was NOT a scheduled game at all - one of the two
# teams had been swapped for a team from a DIFFERENT game that night. Nothing
# checked the triple, so the fabricated pairing was written to the log, and
# build_matchups_dataset.R then hard-failed its join-rate contract.
#
# Every slate row must therefore be checked against the authoritative ESPN
# schedule spine (the SAME artifact build_matchups_dataset.R joins against)
# before it is written.
#
# NOTE: the orientation check is DELIBERATELY strict - home must be home and
# away must be away. A "bidirectional" join that also accepts the reversed
# orientation was proposed on issue 24 and is actively wrong: it would not have
# matched any of the four bad rows (the pairings were fabricated, not inverted)
# and it would let a genuinely home/away-inverted row match the spine, silently
# publishing a prediction with home-court advantage applied to the wrong side.

# hoopR end-year season numbering, matching build_matchups_dataset.R's
# MATCHUPS_HOOPR_SEASON. Overridable by the same env var so the two stages
# cannot be pointed at different seasons.
PRED_LOG_SPINE_SEASON <- {
  env <- Sys.getenv("NBA_MATCHUPS_SEASON", unset = "")
  if (nzchar(env)) as.integer(env) else 2027L
}

# Columns the spine must supply. See build_matchups_dataset.R:238-247, which
# reads exactly these.
PRED_LOG_SPINE_COLUMNS <- c("game_id", "game_date",
                            "home_short_display_name", "away_short_display_name")

# ESPN ships unseeded NBA Cup knockout slots as TBD vs TBD. They are not games.
PRED_LOG_SPINE_PLACEHOLDER <- "TBD"

# FALSE: a slate row absent from the spine is dropped and reported loudly, so a
# bad pairing can never reach the log while the rest of the slate still
# publishes. build_matchups_dataset.R:311-335 remains the hard backstop for
# anything that is already in the log.
# TRUE: abort the run on the first rejection instead.
PRED_LOG_SPINE_STRICT <- FALSE

# predicted_winner is derived as if_else(prob >= PRED_LOG_WINNER_PROB_CUTOFF,
# home, away). Anything else in that column is corruption.
PRED_LOG_WINNER_PROB_CUTOFF <- 0.50

# Canonical empty schema for prediction log
.empty_prediction_log <- function() {
  tibble(
    game_id                 = character(),
    game_date               = as.Date(character()),
    season                  = integer(),
    home_team               = character(),
    away_team               = character(),
    prediction_timestamp    = as.POSIXct(numeric(), origin = "1970-01-01"),
    predicted_home_win_prob = double(),
    .pred_Win               = double(),
    predicted_winner        = character(),
    predicted_margin        = double(),
    target_home_win         = character(),
    actual_winner           = character(),
    correct                 = logical(),
    brier_component         = double(),
    log_loss_component      = double(),
    status                  = character(),
    resolved_timestamp      = as.POSIXct(numeric(), origin = "1970-01-01")
  )
}

# ------------------------------------------------------------------------------
# Schedule spine validation (issue 24)
# ------------------------------------------------------------------------------

# Normalize a raw hoopR/ESPN schedule pull into the minimal
# (game_id, game_date, home_team, away_team) spine this module checks against,
# with team names pushed through the shared resolver so spine and slate are
# compared in the same vocabulary.
#
# `spine` is a data frame, NOT a path: the caller injects it. That is what makes
# this testable with an in-memory fixture - `cache/` is gitignored, so no
# checkout is guaranteed to have the real artifact.
.normalize_schedule_spine <- function(spine) {
  if (is.null(spine) || !is.data.frame(spine) || nrow(spine) == 0) {
    return(tibble(game_id = character(), game_date = as.Date(character()),
                  home_team = character(), away_team = character()))
  }

  missing_cols <- setdiff(PRED_LOG_SPINE_COLUMNS, names(spine))
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "Schedule spine is missing required column(s): %s. Expected: %s.",
      paste(missing_cols, collapse = ", "),
      paste(PRED_LOG_SPINE_COLUMNS, collapse = ", ")))
  }

  out <- tibble(
    game_id   = as.character(spine[["game_id"]]),
    game_date = as.Date(spine[["game_date"]]),
    home_team = resolve_team_name(spine[["home_short_display_name"]]),
    away_team = resolve_team_name(spine[["away_short_display_name"]])
  )

  placeholder <- out$home_team == PRED_LOG_SPINE_PLACEHOLDER |
                 out$away_team == PRED_LOG_SPINE_PLACEHOLDER
  out <- out[!is.na(out$game_date) & !(placeholder %in% TRUE), , drop = FALSE]
  distinct(out)
}

# Read the real spine from cache. Returns NULL when the artifact is absent, so
# a fresh checkout without `cache/` degrades to a loud warning instead of an
# error. Exists purely as the seam that supplies the default `spine` argument.
.load_schedule_spine <- function(season = PRED_LOG_SPINE_SEASON) {
  path <- if (exists("CACHE_MATCHUPS_SCHEDULE")) {
    CACHE_MATCHUPS_SCHEDULE(season)
  } else {
    file.path(CACHE_DIR, sprintf("matchups_schedule_%d.rds", season))
  }
  if (!file.exists(path)) {
    cat(sprintf("[PREDICTION LOG] Schedule spine not found at %s.\n", path))
    return(NULL)
  }
  readRDS(path)
}

# Split candidate prediction rows into those whose (game_date, home_team,
# away_team) triple IS a scheduled game and those whose triple is not.
#
# Returns list(accepted, rejected, spine_available). When no spine is available
# nothing can be checked, so everything is accepted and the caller reports it.
.validate_slate_against_spine <- function(candidate_rows, spine) {
  empty <- candidate_rows[0, , drop = FALSE]

  if (is.null(candidate_rows) || nrow(candidate_rows) == 0) {
    return(list(accepted = candidate_rows, rejected = empty, spine_available = FALSE))
  }

  sp <- .normalize_schedule_spine(spine)
  if (nrow(sp) == 0) {
    return(list(accepted = candidate_rows, rejected = empty, spine_available = FALSE))
  }

  spine_keys <- paste(format(sp$game_date), sp$home_team, sp$away_team)
  cand_keys  <- paste(format(as.Date(candidate_rows$game_date)),
                      candidate_rows$home_team, candidate_rows$away_team)
  ok <- cand_keys %in% spine_keys

  list(accepted        = candidate_rows[ok, , drop = FALSE],
       rejected        = candidate_rows[!ok, , drop = FALSE],
       spine_available = TRUE)
}

# Loudly report rows the spine rejected, and (in strict mode) refuse to go on.
.report_spine_rejections <- function(rejected, strict = PRED_LOG_SPINE_STRICT) {
  if (is.null(rejected) || nrow(rejected) == 0) return(invisible(0L))

  keys <- paste(format(as.Date(rejected$game_date)),
                "home", rejected$home_team, "away", rejected$away_team)

  cat(sprintf(paste0(
    "[PREDICTION LOG] SPINE CONTRACT VIOLATION: %d parsed slate row(s) are not a ",
    "scheduled game and were NOT written:\n"), nrow(rejected)))
  for (i in seq_along(keys)) {
    cat(sprintf("[PREDICTION LOG]   REJECTED  game_id %s  %s\n",
                rejected$game_id[i], keys[i]))
  }
  cat(paste0("[PREDICTION LOG]   Cause is upstream in market_odds_engine.R: the ",
             "bookmaker matchup string paired teams that are not playing each ",
             "other. Do NOT 'fix' this with a reversed home/away join.\n"))

  if (isTRUE(strict)) {
    stop(sprintf(paste0(
      "%d parsed slate row(s) failed the schedule spine contract on ",
      "(game_date, home_team, away_team): %s. Refusing to write a prediction ",
      "for a game that is not on the schedule."),
      nrow(rejected), paste(keys, collapse = "; ")))
  }

  invisible(nrow(rejected))
}

# ------------------------------------------------------------------------------
# Derived-column self-consistency guard (issue 24)
# ------------------------------------------------------------------------------
# predicted_winner is derived from predicted_home_win_prob and the two team
# slots, so it can only ever be home_team or away_team, on the correct side of
# PRED_LOG_WINNER_PROB_CUTOFF. A row that breaks that was written (or hand-
# repaired) incorrectly. Issue 24 left exactly one such row live:
#   game_id 7469a7f48dbb77001b3148829f80c97b, 2026-10-23, home Jazz,
#   away Pelicans, prob 0.339, predicted_winner "Magic"
# - a team in neither slot. Nothing in the code would have caught it.
#
# Returns the offending rows (zero-row tibble when clean). `strict = TRUE`
# aborts; that is for rows this process is about to write, where an
# inconsistency is a code bug. The stored log is reported, not rewritten.
.check_predicted_winner_consistency <- function(df, label = "prediction log",
                                                strict = FALSE) {
  needed <- c("game_id", "home_team", "away_team",
              "predicted_home_win_prob", "predicted_winner")
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0 ||
      !all(needed %in% names(df))) {
    return(df[0, , drop = FALSE])
  }

  prob   <- suppressWarnings(as.numeric(df$predicted_home_win_prob))
  winner <- as.character(df$predicted_winner)
  home   <- as.character(df$home_team)
  away   <- as.character(df$away_team)

  not_a_slot  <- !is.na(winner) & winner != home & winner != away
  expected    <- if_else(prob >= PRED_LOG_WINNER_PROB_CUTOFF, home, away)
  wrong_side  <- !is.na(winner) & !is.na(prob) & !not_a_slot & winner != expected

  bad <- not_a_slot | wrong_side
  bad[is.na(bad)] <- FALSE
  if (!any(bad)) return(df[0, , drop = FALSE])

  cat(sprintf(paste0(
    "[PREDICTION LOG] WINNER CONSISTENCY VIOLATION: %d row(s) in the %s have a ",
    "predicted_winner that is not derivable from their own teams and ",
    "probability:\n"), sum(bad), label))
  for (i in which(bad)) {
    cat(sprintf(paste0(
      "[PREDICTION LOG]   game_id %s  home %s  away %s  prob %.3f  ",
      "predicted_winner %s  (expected %s)%s\n"),
      df$game_id[i], home[i], away[i], prob[i], winner[i], expected[i],
      if (not_a_slot[i]) "  [winner is in NEITHER team slot]" else "  [wrong side of cutoff]"))
  }

  if (isTRUE(strict)) {
    stop(sprintf(paste0(
      "%d row(s) in the %s have a predicted_winner inconsistent with their ",
      "home_team / away_team and predicted_home_win_prob. Refusing to publish."),
      sum(bad), label))
  }

  df[bad, , drop = FALSE]
}

# ------------------------------------------------------------------------------
# Correcting upsert (issue 24)
# ------------------------------------------------------------------------------
# The old insertion path deduplicated with
#   new_rows |> anti_join(existing_log, by = "game_id")
# which made corruption PERMANENT: once a row existed for a game_id, a later run
# carrying the CORRECTED teams for that same game_id was dropped as a duplicate.
# That is why issue 24's four bad rows survived many daily runs.
#
# Insertion now upserts: a still-PENDING stored row whose teams disagree with a
# spine-validated slate row for the same game_id is REPLACED. RESOLVED /
# UNRESOLVABLE rows carry grading and are never overwritten - a disagreement
# there is reported instead.
#
# Returns list(log, n_inserted, n_corrected, n_unchanged, n_locked).
.upsert_predictions <- function(existing_log, new_rows) {
  if (is.null(new_rows) || nrow(new_rows) == 0) {
    return(list(log = existing_log, n_inserted = 0L, n_corrected = 0L,
                n_unchanged = 0L, n_locked = 0L))
  }
  if (is.null(existing_log) || nrow(existing_log) == 0) {
    return(list(log = new_rows, n_inserted = nrow(new_rows), n_corrected = 0L,
                n_unchanged = 0L, n_locked = 0L))
  }

  existing_ids <- as.character(existing_log$game_id)
  new_ids      <- as.character(new_rows$game_id)

  is_new <- !(new_ids %in% existing_ids)

  # For each already-logged slate row, decide: correctable, locked, unchanged.
  correct_idx <- integer(0)
  locked_idx  <- integer(0)
  for (i in which(!is_new)) {
    j <- match(new_ids[i], existing_ids)
    teams_differ <-
      !identical(as.character(existing_log$home_team[j]), as.character(new_rows$home_team[i])) ||
      !identical(as.character(existing_log$away_team[j]), as.character(new_rows$away_team[i]))
    if (!teams_differ) next
    stored_status <- as.character(existing_log$status[j])
    if (!is.na(stored_status) && stored_status == "PENDING") {
      cat(sprintf(paste0(
        "[PREDICTION LOG] CORRECTING game_id %s: stored home %s / away %s -> ",
        "spine-validated home %s / away %s\n"),
        new_ids[i], existing_log$home_team[j], existing_log$away_team[j],
        new_rows$home_team[i], new_rows$away_team[i]))
      correct_idx <- c(correct_idx, i)
    } else {
      cat(sprintf(paste0(
        "[PREDICTION LOG] NOT correcting game_id %s: stored row is %s (graded) ",
        "with home %s / away %s but the slate says home %s / away %s. Needs a ",
        "manual repair.\n"),
        new_ids[i], stored_status,
        existing_log$home_team[j], existing_log$away_team[j],
        new_rows$home_team[i], new_rows$away_team[i]))
      locked_idx <- c(locked_idx, i)
    }
  }

  write_idx    <- sort(c(which(is_new), correct_idx))
  replaced_ids <- new_ids[correct_idx]

  updated <- bind_rows(
    existing_log[!(existing_ids %in% replaced_ids), , drop = FALSE],
    new_rows[write_idx, , drop = FALSE]
  ) |>
    arrange(game_date, game_id)

  list(log         = updated,
       n_inserted  = length(which(is_new)),
       n_corrected = length(correct_idx),
       n_unchanged = sum(!is_new) - length(correct_idx) - length(locked_idx),
       n_locked    = length(locked_idx))
}



# Sweep stale PENDING rows older than PRED_LOG_UNRESOLVABLE_AFTER_DAYS to UNRESOLVABLE
.sweep_unresolvable <- function(df, persist = TRUE) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) return(df)
  if (!all(c("status", "game_date") %in% names(df))) return(df)

  cutoff <- Sys.Date() - PRED_LOG_UNRESOLVABLE_AFTER_DAYS
  stale  <- !is.na(df$status) & df$status == "PENDING" &
            !is.na(df$game_date) & as.Date(df$game_date) < cutoff

  if (!any(stale)) return(df)

  df$status[stale] <- "UNRESOLVABLE"
  if ("resolved_timestamp" %in% names(df)) df$resolved_timestamp[stale] <- Sys.time()

  cat(sprintf("[PREDICTION LOG] Swept %d stale PENDING row(s) older than %s to UNRESOLVABLE.\n",
              sum(stale), as.character(cutoff)))

  if (isTRUE(persist)) {
    saveRDS(df, PRED_LOG_RDS)
    utils::write.csv(df, PRED_LOG_CSV, row.names = FALSE, na = "")
  }
  df
}

# ------------------------------------------------------------------------------
# 1. Seeding Function: Populate Historical Resolved Predictions from Box Scores
# ------------------------------------------------------------------------------
seed_prediction_log <- function() {
  box_path <- if (exists("CACHE_TEAM_BOX")) CACHE_TEAM_BOX else file.path(PROJECT_DIR, "box_scores_cache.rds")
  if (!file.exists(box_path)) {
    cat("[PREDICTION LOG] box_scores_cache.rds not found. Starting with empty log.\n")
    empty_df <- .empty_prediction_log()
    saveRDS(empty_df, PRED_LOG_RDS)
    return(empty_df)
  }

  box_scores <- readRDS(box_path)

  # Seasons the log covers: the current one plus the one before it. Derived from
  # CURRENT_SEASON (config.R) rather than hardcoded, so a season rollover does not
  # silently leave this filter a year behind and stop every new game from grading.
  recent_seasons <- if (exists("CURRENT_SEASON")) {
    c(CURRENT_SEASON - 1L, CURRENT_SEASON)
  } else {
    c(2026L, 2027L)
  }

  # Filter completed home games for the current and previous seasons
  games <- box_scores |>
    filter(
      season %in% recent_seasons,
      team_home_away == "home",
      season_type %in% c(2, 3)
    )

  if (nrow(games) == 0) {
    empty_df <- .empty_prediction_log()
    saveRDS(empty_df, PRED_LOG_RDS)
    return(empty_df)
  }

  # Team ratings: use projected standings or empirical net points from box scores
  std_path <- file.path(CACHE_DIR, "projected_30_team_standings.rds")
  if (file.exists(std_path)) {
    std <- readRDS(std_path)
    ratings <- setNames(std$Net_Rating, std$Team)
  } else {
    team_diffs <- box_scores |>
      filter(season %in% recent_seasons) |>
      group_by(team_short_display_name) |>
      summarise(net = mean(team_score - opponent_team_score, na.rm = TRUE), .groups = "drop")
    ratings <- setNames(team_diffs$net, team_diffs$team_short_display_name)
  }

  # Ensure games involve valid rated NBA franchises
  valid_mask <- games$team_short_display_name %in% names(ratings) &
                games$opponent_team_short_display_name %in% names(ratings)
  games <- games[valid_mask, , drop = FALSE]

  home_teams <- games$team_short_display_name
  away_teams <- games$opponent_team_short_display_name

  h_rtg <- ratings[home_teams]
  a_rtg <- ratings[away_teams]
  hca   <- 2.40  # Standard NBA Home Court Advantage points

  pred_margin <- (h_rtg - a_rtg) + hca
  sigma       <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8
  pred_prob   <- pnorm(pred_margin / sigma)
  pred_winner <- if_else(pred_prob >= 0.50, home_teams, away_teams)

  home_won    <- games$team_winner == TRUE
  actual_win  <- if_else(home_won, home_teams, away_teams)
  target_win  <- if_else(home_won, "Win", "Loss")
  is_correct  <- (pred_winner == actual_win)

  brier_comp  <- (pred_prob - if_else(home_won, 1.0, 0.0))^2
  p_clamp     <- pmin(pmax(pred_prob, 1e-6), 1 - 1e-6)
  actual_num  <- if_else(home_won, 1.0, 0.0)
  logloss_comp <- -(actual_num * log(p_clamp) + (1.0 - actual_num) * log(1.0 - p_clamp))

  seed_df <- tibble(
    game_id                 = as.character(games$game_id),
    game_date               = as.Date(games$game_date),
    season                  = as.integer(games$season),
    home_team               = home_teams,
    away_team               = away_teams,
    prediction_timestamp    = as.POSIXct(paste(games$game_date, "12:00:00")),
    predicted_home_win_prob = round(as.double(pred_prob), 4),
    .pred_Win               = round(as.double(pred_prob), 4),
    predicted_winner        = pred_winner,
    predicted_margin        = round(as.double(pred_margin), 2),
    target_home_win         = target_win,
    actual_winner           = actual_win,
    correct                 = is_correct,
    brier_component         = round(as.double(brier_comp), 6),
    log_loss_component      = round(as.double(logloss_comp), 6),
    status                  = "RESOLVED",
    resolved_timestamp      = as.POSIXct(paste(games$game_date, "23:59:59"))
  ) |>
    arrange(game_date, game_id)

  saveRDS(seed_df, PRED_LOG_RDS)
  utils::write.csv(seed_df, PRED_LOG_CSV, row.names = FALSE, na = "")
  cat(sprintf("[PREDICTION LOG] Seeded %d historical resolved predictions for 2025-2026 seasons.\n", nrow(seed_df)))

  seed_df
}

# ------------------------------------------------------------------------------
# 2. Load or Get Prediction Log
# ------------------------------------------------------------------------------
get_prediction_log <- function() {
  if (file.exists(PRED_LOG_RDS)) {
    readRDS(PRED_LOG_RDS)
  } else {
    seed_prediction_log()
  }
}

# ------------------------------------------------------------------------------
# 3. Log Today's Predictions from Active Slate
# ------------------------------------------------------------------------------

# Parse a `latest_value_bets.rds` slate into candidate prediction-log rows.
# Pure: no file IO, no spine check, no dedup - so it can be unit-tested with an
# in-memory slate. Returns a zero-row log-schema tibble when nothing parses.
.build_slate_rows <- function(slate) {
  if (is.null(slate) || !is.data.frame(slate) || nrow(slate) == 0) {
    return(.empty_prediction_log())
  }

  parsed    <- str_split_fixed(slate$Matchup, " vs\\. ", 2)
  away_full <- parsed[, 1]
  home_full <- parsed[, 2]

  valid_idx <- nchar(away_full) > 0 & nchar(home_full) > 0
  if (any(!valid_idx)) {
    slate     <- slate[valid_idx, , drop = FALSE]
    away_full <- away_full[valid_idx]
    home_full <- home_full[valid_idx]
  }

  if (nrow(slate) == 0) {
    cat("[PREDICTION LOG] No valid Matchup strings found in slate.\n")
    return(.empty_prediction_log())
  }

  home_short <- resolve_team_name(home_full)
  away_short <- resolve_team_name(away_full)
  team_short <- resolve_team_name(slate$Team)

  # Derive home win probability based on whether slate$Team is the home or away side
  pred_home_prob <- if_else(
    team_short == home_short,
    as.double(slate$Model_Win_Prob),
    1.0 - as.double(slate$Model_Win_Prob)
  )

  tibble(
    game_id                 = as.character(slate$game_id),
    game_date               = as.Date(slate$game_date),
    season                  = as.integer(CURRENT_SEASON),
    home_team               = home_short,
    away_team               = away_short,
    prediction_timestamp    = Sys.time(),
    predicted_home_win_prob = round(as.double(pred_home_prob), 4),
    .pred_Win               = round(as.double(pred_home_prob), 4),
    predicted_winner        = if_else(pred_home_prob >= PRED_LOG_WINNER_PROB_CUTOFF,
                                      home_short, away_short),
    predicted_margin        = NA_real_,
    target_home_win         = NA_character_,
    actual_winner           = NA_character_,
    correct                 = NA,
    brier_component         = NA_real_,
    log_loss_component      = NA_real_,
    status                  = "PENDING",
    resolved_timestamp      = as.POSIXct(NA)
  )
}

# `slate`, `spine` and `existing_log` default to NULL.
# When `slate` is injected (e.g. in tests), it is parsed and validated directly.
# When `slate` is NULL (scheduled pipeline execution), predictions are projected
# from the ESPN schedule spine on a Tuesday cadence (Issue #33) via
# tools/project_week_predictions.R without reading betting caches or calling Odds APIs.
log_todays_predictions <- function(slate = NULL, spine = NULL,
                                   existing_log = NULL, persist = TRUE) {
  if (is.null(slate)) {
    today <- Sys.Date()
    is_tuesday <- identical(weekdays(today), "Tuesday")
    force_run <- nzchar(Sys.getenv("NBA_FORCE_PROJECT_WEEK"))

    if (!is_tuesday && !force_run) {
      cat(sprintf("[PREDICTION LOG] Non-Tuesday cadence (%s); weekly schedule projection skipped (runs on Tuesdays).\n",
                  format(today, "%A")))
      return(invisible(if (is.null(existing_log)) get_prediction_log() else existing_log))
    }

    pwp_path <- file.path(PROJECT_DIR, "tools", "project_week_predictions.R")
    if (!file.exists(pwp_path)) {
      cat(sprintf("[PREDICTION LOG] %s not found; skipping weekly projection.\n", pwp_path))
      return(invisible(if (is.null(existing_log)) get_prediction_log() else existing_log))
    }

    cat(sprintf("[PREDICTION LOG] Running weekly prediction projector (%s cadence)...\n",
                format(today, "%A")))
    pwp_env <- new.env(parent = .GlobalEnv)
    sys.source(pwp_path, envir = pwp_env)
    if (exists("main", envir = pwp_env, mode = "function")) {
      pwp_env$main(do_write = isTRUE(persist))
    }
    return(invisible(get_prediction_log()))
  }

  if (nrow(slate) == 0) {
    cat("[PREDICTION LOG] 0 games in slate; skipping prediction logging.\n")
    return(invisible(NULL))
  }

  new_rows <- .build_slate_rows(slate)
  if (nrow(new_rows) == 0) return(invisible(NULL))

  # GUARD 1: predicted_winner must be derivable from this row's own teams and
  # probability. These rows were just computed here, so a violation is a code
  # bug and must not be published.
  .check_predicted_winner_consistency(new_rows, label = "parsed active slate",
                                      strict = TRUE)

  # GUARD 2: the (game_date, home_team, away_team) triple must be a real
  # scheduled game. See the SCHEDULE SPINE CONTRACT note at the top of this file.
  if (is.null(spine)) spine <- .load_schedule_spine()
  checked <- .validate_slate_against_spine(new_rows, spine)
  if (!isTRUE(checked$spine_available)) {
    cat(paste0("[PREDICTION LOG] WARNING: no schedule spine available - slate ",
               "rows written WITHOUT the (date, home, away) contract check.\n"))
  }
  .report_spine_rejections(checked$rejected)
  new_rows <- checked$accepted

  if (nrow(new_rows) > 0) {
    cat(sprintf("[PREDICTION LOG] %d slate row(s) validated against the schedule spine.\n",
                nrow(new_rows)))
  }
  if (nrow(new_rows) == 0) {
    cat("[PREDICTION LOG] No slate rows survived the schedule spine contract; nothing logged.\n")
    return(invisible(existing_log))
  }

  if (is.null(existing_log)) existing_log <- get_prediction_log()

  # Correcting upsert, NOT anti_join(by = "game_id"): a stored PENDING row with
  # the wrong teams has to be repairable on the next run (issue 24).
  res         <- .upsert_predictions(existing_log, new_rows)
  updated_log <- res$log

  if (res$n_inserted == 0L && res$n_corrected == 0L) {
    cat("[PREDICTION LOG] All active slate predictions are already logged.\n")
    return(invisible(existing_log))
  }

  if (isTRUE(persist)) {
    saveRDS(updated_log, PRED_LOG_RDS)
    utils::write.csv(updated_log, PRED_LOG_CSV, row.names = FALSE, na = "")
  }

  cat(sprintf(paste0(
    "[PREDICTION LOG] Logged %d new PENDING prediction(s), corrected %d stored ",
    "row(s), left %d unchanged%s.\n"),
    res$n_inserted, res$n_corrected, res$n_unchanged,
    if (res$n_locked > 0) sprintf(", %d graded row(s) need manual repair", res$n_locked) else ""))
  invisible(updated_log)
}

# ------------------------------------------------------------------------------
# 4. Reconcile Completed Predictions against Official Box Scores
# ------------------------------------------------------------------------------
reconcile_predictions <- function() {
  existing_log <- get_prediction_log()
  pending      <- existing_log |> filter(status == "PENDING")

  if (nrow(pending) == 0) {
    cat("[PREDICTION LOG] No PENDING predictions to reconcile.\n")
    return(invisible(.sweep_unresolvable(existing_log)))
  }

  box_path <- if (exists("CACHE_TEAM_BOX")) CACHE_TEAM_BOX else file.path(PROJECT_DIR, "box_scores_cache.rds")
  if (!file.exists(box_path)) {
    cat("[PREDICTION LOG] box_scores_cache.rds not found; skipping reconciliation.\n")
    return(invisible(.sweep_unresolvable(existing_log)))
  }

  box_scores <- readRDS(box_path)

  home_results <- box_scores |>
    filter(team_home_away == "home") |>
    mutate(game_date = as.Date(game_date)) |>
    select(
      game_date,
      home_team_short = team_short_display_name,
      home_winner     = team_winner
    ) |>
    distinct()

  joined <- pending |>
    inner_join(
      home_results,
      by = c("game_date" = "game_date", "home_team" = "home_team_short")
    )

  if (nrow(joined) == 0) {
    cat("[PREDICTION LOG] No PENDING predictions matched completed box scores yet.\n")
    return(invisible(.sweep_unresolvable(existing_log)))
  }

  resolved <- joined |>
    mutate(
      home_won           = home_winner == TRUE,
      target_home_win    = if_else(home_won, "Win", "Loss"),
      actual_winner      = if_else(home_won, home_team, away_team),
      correct            = (predicted_winner == actual_winner),
      brier_component    = round((predicted_home_win_prob - if_else(home_won, 1.0, 0.0))^2, 6),
      .p_clamp           = pmin(pmax(predicted_home_win_prob, 1e-6), 1 - 1e-6),
      .actual_num        = if_else(home_won, 1.0, 0.0),
      log_loss_component = round(-(.actual_num * log(.p_clamp) + (1.0 - .actual_num) * log(1.0 - .p_clamp)), 6),
      status             = "RESOLVED",
      resolved_timestamp = Sys.time()
    ) |>
    select(-home_winner, -home_won, -.p_clamp, -.actual_num)

  updated_log <- bind_rows(
    existing_log |> filter(!game_id %in% resolved$game_id),
    resolved
  ) |>
    arrange(game_date, game_id)

  saveRDS(updated_log, PRED_LOG_RDS)
  utils::write.csv(updated_log, PRED_LOG_CSV, row.names = FALSE, na = "")

  cat(sprintf("[PREDICTION LOG] Reconciled %d predictions against official box scores.\n", nrow(resolved)))
  invisible(.sweep_unresolvable(updated_log))
}

# ------------------------------------------------------------------------------
# 5. Master Pipeline Execution Wrapper
# ------------------------------------------------------------------------------
run_prediction_accuracy_logger <- function() {
  cat("\n==================================================================\n")
  cat("     RECONCILING OUTCOMES & LOGGING MODEL PREDICTIONS            \n")
  cat("==================================================================\n\n")

  log_df <- get_prediction_log()
  reconcile_predictions()
  log_todays_predictions()

  final_log  <- get_prediction_log()
  n_resolved <- sum(final_log$status == "RESOLVED", na.rm = TRUE)
  n_pending  <- sum(final_log$status == "PENDING", na.rm = TRUE)

  cat(sprintf("[PREDICTION LOG] Total records: %d (Resolved: %d, Pending: %d)\n",
              nrow(final_log), n_resolved, n_pending))

  # Audit the STORED log, report-only: the hand-repair that fixed issue 24's four
  # bad pairings edited home_team / away_team without recomputing
  # predicted_winner, and nothing would have surfaced the leftover. Rewriting a
  # cached artifact the pipeline owns is deliberately not done here.
  bad_winner <- .check_predicted_winner_consistency(final_log,
                                                    label = "stored prediction log")
  if (nrow(bad_winner) > 0) {
    cat(sprintf(paste0(
      "[PREDICTION LOG] %d stored row(s) need a manual repair of ",
      "predicted_winner (not rewritten automatically).\n"), nrow(bad_winner)))
  }

  # Re-persist to guarantee fresh mtime for run_full_pipeline's staleness check
  saveRDS(final_log, PRED_LOG_RDS)
  utils::write.csv(final_log, PRED_LOG_CSV, row.names = FALSE, na = "")

  invisible(final_log)
}

# Auto-execute when run standalone or sourced by run_stage(), which relies on
# this call (run_full_pipeline.R passes no `call_fn` for this stage and its
# `.check_stage_output` staleness check would catch a guard that silently
# no-ops). Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions
# alone - that is what tests/test_prediction_log_spine_validation.R does, so it
# exercises the real bootstrap above instead of stepping over it.
if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  run_prediction_accuracy_logger()
}
