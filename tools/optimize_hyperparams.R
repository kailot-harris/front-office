# ==============================================================================
# optimize_hyperparams.R
# Path: tools/optimize_hyperparams.R
#
# Grid-search optimizer for the three "Model Robustness" hyperparameters
# introduced alongside the Ceiling/Floor rating adjustment and the Star Power
# Delta in market_odds_engine.R:
#   1. limit       — apply_rating_limits() rating threshold (default 15.0)
#   2. dampening   — apply_rating_limits() multiplier beyond the threshold (default 0.5)
#   3. star_weight — calculate_matchup_delta() multiplier on the top-player
#                    RAPM gap (default 0.2)
#
# Per docs/develop-a-plan-to-parallel-robin.md: minimizes MAE(actual_margin,
# predicted_margin) over resolved games in prediction_accuracy_log.rds.
#
# NOTE ON METHOD: apply_rating_limits() is applied PER TEAM (not to the home/
# away net-rating diff), so the logged `contrib_net_diff` column (already
# damped with the *old* limit/dampening) cannot be algebraically un-damped to
# test new values. Instead this script recomputes each resolved game's
# pre-damping home/away net ratings (standings Net_Rating minus half the
# shot-quality shooting-luck points, same as market_odds_engine.R's
# get_model_slate_probabilities()) and each team's top-RAPM value fresh from
# the current caches, then re-derives predicted_margin under each candidate
# (limit, dampening, star_weight) combination. This mirrors optimize_hca.R's
# existing simplification of using current cached ratings as a stand-in for
# point-in-time historical ratings (there is no per-game historical snapshot
# of standings/RAPM in this repo) — contrib_hca and contrib_fatigue are left
# exactly as logged since this script isn't optimizing those.
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "optimize_hyperparams.R"

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

# Current defaults (market_odds_engine.R lines 67-68 and 95)
DEFAULT_LIMIT       <- 15.0
DEFAULT_DAMPENING   <- 0.5
DEFAULT_STAR_WEIGHT <- 0.2

apply_rating_limits_param <- function(rating, limit, dampening) {
  if (is.na(rating)) return(NA_real_)
  if (rating > limit) return(limit + dampening * (rating - limit))
  if (rating < -limit) return(-limit + dampening * (rating + limit))
  return(rating)
}

# ------------------------------------------------------------------------------
# Build per-team-abbreviation lookups (raw net rating pre-damping, and top RAPM)
# from the same caches market_odds_engine.R reads, keyed by WNBA_TEAMS abbrs.
# ------------------------------------------------------------------------------
build_team_lookups <- function() {
  standings_path <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  sq_path        <- file.path(CACHE_DIR, "team_shot_quality.rds")
  rapm_path      <- file.path(CACHE_DIR, "rapm_ratings.rds")
  rost_path      <- file.path(CACHE_DIR, "active_rosters_cache.rds")

  required <- c(standings_path, sq_path, rapm_path, rost_path)
  missing  <- required[!file.exists(required)]
  if (length(missing) > 0) {
    stop(sprintf("Missing required caches: %s", paste(missing, collapse = ", ")))
  }

  standings <- readRDS(standings_path)
  sq_db     <- readRDS(sq_path)
  rapm      <- readRDS(rapm_path)
  rost      <- readRDS(rost_path)

  abbrs <- names(WNBA_TEAMS)

  raw_net <- setNames(rep(NA_real_, length(abbrs)), abbrs)
  top_rapm <- setNames(rep(NA_real_, length(abbrs)), abbrs)

  for (abbr in abbrs) {
    full_name <- unname(WNBA_TEAMS[abbr])
    s_row <- standings |> filter(tolower(Team) == tolower(full_name))
    if (nrow(s_row) > 0) {
      net <- as.numeric(s_row$Net_Rating[1])
      luck <- sq_db$shooting_luck_pts[toupper(sq_db$team) == abbr][1] %||% 0.0
      raw_net[abbr] <- net - (0.50 * luck)
    }

    players <- rost |> filter(team_abbreviation == abbr) |> pull(player_id)
    if (length(players) > 0) {
      top <- rapm |> filter(player_id %in% players) |> arrange(desc(total_rapm)) |> slice(1) |> pull(total_rapm)
      if (length(top) > 0) top_rapm[abbr] <- top
    }
  }

  list(raw_net = raw_net, top_rapm = top_rapm)
}

# ------------------------------------------------------------------------------
# Core Optimization
# ------------------------------------------------------------------------------
run_hyperparam_optimization <- function() {
  cat("\n==================================================================\n")
  cat("       WNBA MODEL ROBUSTNESS HYPERPARAMETER GRID SEARCH         \n")
  cat("==================================================================\n\n")

  log_path <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
  if (!file.exists(log_path)) stop("Missing prediction_accuracy_log.rds cache.")

  pred_log <- readRDS(log_path)
  resolved <- pred_log |> filter(status == "RESOLVED", !is.na(actual_margin))
  if (nrow(resolved) == 0) stop("No RESOLVED predictions found to optimize against.")

  lookups <- build_team_lookups()

  analysis_df <- resolved |>
    mutate(
      h_net_raw = lookups$raw_net[home_team],
      a_net_raw = lookups$raw_net[away_team],
      h_top     = lookups$top_rapm[home_team],
      a_top     = lookups$top_rapm[away_team],
      star_gap  = ifelse(is.na(h_top) | is.na(a_top), 0.0, h_top - a_top),
      base_fixed = coalesce(contrib_hca, 0.0) + coalesce(contrib_fatigue, 0.0)
    ) |>
    filter(!is.na(h_net_raw), !is.na(a_net_raw))

  if (nrow(analysis_df) == 0) stop("No resolved games matched current team caches.")

  cat(sprintf("Optimizing over N = %d resolved games...\n\n", nrow(analysis_df)))

  # ----------------------------------------------------------------------------
  # Grid definition (per docs/develop-a-plan-to-parallel-robin.md)
  # ----------------------------------------------------------------------------
  limit_grid       <- seq(5.0, 25.0, by = 2.5)
  dampening_grid   <- seq(0.1, 0.9, by = 0.1)
  star_weight_grid <- seq(0.0, 0.5, by = 0.05)

  grid <- expand.grid(
    limit       = limit_grid,
    dampening   = dampening_grid,
    star_weight = star_weight_grid
  )

  compute_mae <- function(limit, dampening, star_weight) {
    h_damped <- vapply(analysis_df$h_net_raw, apply_rating_limits_param, numeric(1),
                        limit = limit, dampening = dampening)
    a_damped <- vapply(analysis_df$a_net_raw, apply_rating_limits_param, numeric(1),
                        limit = limit, dampening = dampening)
    preds <- (h_damped - a_damped) + analysis_df$base_fixed + star_weight * analysis_df$star_gap
    mean(abs(analysis_df$actual_margin - preds), na.rm = TRUE)
  }

  cat(sprintf("Grid size: %d combinations...\n", nrow(grid)))
  grid$mae <- mapply(compute_mae, grid$limit, grid$dampening, grid$star_weight)

  baseline_mae <- compute_mae(DEFAULT_LIMIT, DEFAULT_DAMPENING, DEFAULT_STAR_WEIGHT)

  best <- grid |> arrange(mae) |> slice(1)

  cat("\n--- Optimization Results ---\n")
  cat(sprintf("Current defaults: limit=%.1f dampening=%.1f star_weight=%.2f => MAE: %.3f\n",
              DEFAULT_LIMIT, DEFAULT_DAMPENING, DEFAULT_STAR_WEIGHT, baseline_mae))
  cat(sprintf("Best combination: limit=%.1f dampening=%.1f star_weight=%.2f => MAE: %.3f\n",
              best$limit, best$dampening, best$star_weight, best$mae))
  cat(sprintf("MAE Improvement: %.3f points (%.1f%% reduction)\n",
              baseline_mae - best$mae, 100 * (baseline_mae - best$mae) / baseline_mae))

  # ----------------------------------------------------------------------------
  # Stability check: is the optimum part of a broad valley, or an isolated spike?
  # Compare against the mean MAE of its immediate grid neighbors (one step out
  # in each dimension, clipped to grid bounds).
  # ----------------------------------------------------------------------------
  neighbor_mask <- (abs(grid$limit - best$limit) <= 2.5 + 1e-9) &
    (abs(grid$dampening - best$dampening) <= 0.1 + 1e-9) &
    (abs(grid$star_weight - best$star_weight) <= 0.05 + 1e-9)
  neighbors <- grid[neighbor_mask, ]

  cat(sprintf("\n--- Stability Check (%d neighboring combinations) ---\n", nrow(neighbors) - 1))
  cat(sprintf("Neighborhood mean MAE: %.3f | sd: %.3f\n", mean(neighbors$mae), sd(neighbors$mae)))
  if (sd(neighbors$mae) < 0.5 * abs(baseline_mae - best$mae) || nrow(neighbors) <= 1) {
    cat("Optimum sits in a broad, stable valley (not an isolated spike).\n")
  } else {
    cat("WARNING: high variance among neighbors — optimum may be overfit to this sample.\n")
  }

  invisible(list(
    best_limit       = best$limit,
    best_dampening   = best$dampening,
    best_star_weight = best$star_weight,
    best_mae         = best$mae,
    baseline_mae     = baseline_mae,
    grid             = grid
  ))
}

if (sys.nframe() == 0) {
  run_hyperparam_optimization()
}
