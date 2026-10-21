# ==============================================================================
# prediction_accuracy_logger.R
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/prediction_accuracy_logger.R
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

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("live_calibration.R")

PRED_LOG_RDS <- if (exists("CACHE_PREDICTION_LOG")) CACHE_PREDICTION_LOG else file.path(CACHE_DIR, "prediction_accuracy_log.rds")
PRED_LOG_CSV <- file.path(CACHE_DIR, "prediction_accuracy_log.csv")
PRED_LOG_UNRESOLVABLE_AFTER_DAYS <- 7L

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

# Canonical team resolver to short franchise nickname (matching box_scores_cache.rds)
.resolve_team_name <- function(tm_raw) {
  s <- tolower(as.character(tm_raw))
  case_when(
    grepl("celtic|bos", s)                      ~ "Celtics",
    grepl("thunder|okc|oklahoma", s)            ~ "Thunder",
    grepl("cavalier|cle|cleveland", s)          ~ "Cavaliers",
    grepl("spur|sas|san antonio", s)            ~ "Spurs",
    grepl("warrior|gsw|golden state", s)        ~ "Warriors",
    grepl("rocket|hou|houston", s)              ~ "Rockets",
    grepl("knick|nyk|new york", s)              ~ "Knicks",
    grepl("piston|det|detroit", s)              ~ "Pistons",
    grepl("nugget|den|denver", s)               ~ "Nuggets",
    grepl("heat|mia|miami", s)                  ~ "Heat",
    grepl("76er|sixer|phi|philadelphia", s)     ~ "76ers",
    grepl("pacer|ind|indiana", s)               ~ "Pacers",
    grepl("blazer|por|portland", s)             ~ "Trail Blazers",
    grepl("timberwolv|min|minnesota|wolves", s) ~ "Timberwolves",
    grepl("magic|orl|orlando", s)               ~ "Magic",
    grepl("grizzl|mem|memphis", s)              ~ "Grizzlies",
    grepl("laker|lal|los angeles lakers", s)    ~ "Lakers",
    grepl("raptor|tor|toronto", s)              ~ "Raptors",
    grepl("hawk|atl|atlanta", s)                ~ "Hawks",
    grepl("maverick|dal|dallas|mavs", s)        ~ "Mavericks",
    grepl("clipper|lac|los angeles clippers", s)~ "Clippers",
    grepl("buck|mil|milwaukee", s)              ~ "Bucks",
    grepl("sun|phx|phoenix", s)                 ~ "Suns",
    grepl("jazz|uta|utah", s)                   ~ "Jazz",
    grepl("hornet|cha|charlotte", s)            ~ "Hornets",
    grepl("net|bkn|brooklyn", s)                ~ "Nets",
    grepl("bull|chi|chicago", s)                ~ "Bulls",
    grepl("pelican|nop|new orleans", s)         ~ "Pelicans",
    grepl("wizard|was|washington", s)           ~ "Wizards",
    grepl("king|sac|sacramento", s)             ~ "Kings",
    TRUE                                        ~ as.character(tm_raw)
  )
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
log_todays_predictions <- function() {
  val_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
  if (!file.exists(val_path)) {
    cat("[PREDICTION LOG] latest_value_bets.rds not found; skipping prediction logging.\n")
    return(invisible(NULL))
  }

  slate <- readRDS(val_path)
  if (nrow(slate) == 0) {
    cat("[PREDICTION LOG] 0 games in latest_value_bets.rds; skipping prediction logging.\n")
    return(invisible(NULL))
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
    return(invisible(NULL))
  }

  home_short <- vapply(home_full, .resolve_team_name, character(1), USE.NAMES = FALSE)
  away_short <- vapply(away_full, .resolve_team_name, character(1), USE.NAMES = FALSE)
  team_short <- vapply(slate$Team, .resolve_team_name, character(1), USE.NAMES = FALSE)

  # Derive home win probability based on whether slate$Team is the home or away side
  pred_home_prob <- if_else(
    team_short == home_short,
    as.double(slate$Model_Win_Prob),
    1.0 - as.double(slate$Model_Win_Prob)
  )

  new_rows <- tibble(
    game_id                 = as.character(slate$game_id),
    game_date               = as.Date(slate$game_date),
    season                  = as.integer(CURRENT_SEASON),
    home_team               = home_short,
    away_team               = away_short,
    prediction_timestamp    = Sys.time(),
    predicted_home_win_prob = round(as.double(pred_home_prob), 4),
    .pred_Win               = round(as.double(pred_home_prob), 4),
    predicted_winner        = if_else(pred_home_prob >= 0.50, home_short, away_short),
    predicted_margin        = NA_real_,
    target_home_win         = NA_character_,
    actual_winner           = NA_character_,
    correct                 = NA,
    brier_component         = NA_real_,
    log_loss_component      = NA_real_,
    status                  = "PENDING",
    resolved_timestamp      = as.POSIXct(NA)
  )

  existing_log <- get_prediction_log()

  # Idempotent deduplication on game_id
  dedup_rows <- new_rows |> anti_join(existing_log, by = "game_id")

  if (nrow(dedup_rows) == 0) {
    cat("[PREDICTION LOG] All active slate predictions are already logged.\n")
    return(invisible(existing_log))
  }

  updated_log <- bind_rows(existing_log, dedup_rows)
  saveRDS(updated_log, PRED_LOG_RDS)
  utils::write.csv(updated_log, PRED_LOG_CSV, row.names = FALSE, na = "")

  cat(sprintf("[PREDICTION LOG] Logged %d new PENDING predictions to %s.\n", nrow(dedup_rows), PRED_LOG_RDS))
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

  # Re-persist to guarantee fresh mtime for run_full_pipeline's staleness check
  saveRDS(final_log, PRED_LOG_RDS)
  utils::write.csv(final_log, PRED_LOG_CSV, row.names = FALSE, na = "")

  invisible(final_log)
}

# Auto-execute when run standalone or sourced by run_stage()
run_prediction_accuracy_logger()
