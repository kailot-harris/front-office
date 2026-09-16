# ==============================================================================
# backtest_margin_hyperparams.R
# Path: tools/backtest_margin_hyperparams.R
#
# Phase 2 of the model-robustness hyperparameter work (see
# docs/develop-a-plan-to-parallel-robin.md for Phase 1, and
# docs/HYPERPARAMETER_BACKTEST_PHASE2.md for the write-up this script produces
# evidence for). Phase 1's tools/optimize_hyperparams.R grid-searched `limit`,
# `dampening`, `star_weight` against cache/prediction_accuracy_log.rds's 100
# RESOLVED rows and found a boundary optimum (limit=5.0, dampening=0.1,
# star_weight=0.0) — a classic overfit-to-noise signature on a small, partly
# synthetic sample (some rows have off-season dates or a team playing itself).
#
# This script replaces that with a rigorous two-track backtest against the
# REAL testing set, data/box_scores_cache.rds (1,953 real completed games,
# 2019-2026), instead of the synthetic prediction log:
#
#   TRACK A — Leakage-free walk-forward LOSO CV, ALL 8 real seasons (limit,
#     dampening only). Net rating is proxied by each team's trailing rolling
#     point differential (ROLLING_WINDOW_SIZE games, "reset" per season —
#     identical convention to tools/ml_cv_benchmark.R's build_feature_df() and
#     config.R's own ROLLING_WINDOW_SIZE), so no future game ever leaks into a
#     prediction. For each held-out season, the grid is fit ONLY on the other
#     7 seasons and evaluated on the held-out season; out-of-fold (OOF)
#     predictions are pooled across all 8 folds for an honest, non-overfit MAE
#     estimate. star_weight is NOT testable here — there is no historical
#     per-game RAPM snapshot, only the current single cache/rapm_ratings.rds.
#
#   TRACK B — Cross-sectional backtest on the CURRENT real 2026 season only
#     (301 real games in box_scores_cache.rds), using the actual cached
#     standings/shot-quality/RAPM (the same caches the live pipeline reads),
#     exactly like Phase 1's method but against real final scores instead of
#     the synthetic log. This is the only track that can test star_weight, and
#     N=301 real games vs. Phase 1's 100 (partly synthetic) rows.
#
# Both tracks report pooled/point MAE, bootstrap 95% CIs, and a stability
# check (MAE of neighboring grid points) so a boundary hit can be told apart
# from a genuine, non-spiky improvement.
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(slider)
  library(stringr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "backtest_margin_hyperparams.R"

# FINDING M-6: local scalar `%||%` removed. The canonical hardened definition lives in
# logging_utils.R (sourced immediately above, before any use in this file).
set.seed(20260916)  # fixed seed, bootstrap resampling only

DEFAULT_LIMIT       <- 15.0   # NBA-original / pre-Phase-1 default
DEFAULT_DAMPENING   <- 0.5
DEFAULT_STAR_WEIGHT <- 0.2
PHASE1_LIMIT        <- 5.0    # Phase 1's (flagged-as-likely-overfit) grid optimum
PHASE1_DAMPENING    <- 0.1
PHASE1_STAR_WEIGHT  <- 0.0

# FINDING C-1: this line used to read `HCA_CONST <- 11.6`, described as
# "market_odds_engine.R's current live constant". That enshrined the defect as ground
# truth for the backtest: 11.6 was never the intended HCA, it was the NBA original's
# sigma-family constant pasted into the HCA slot. Read config.R::WNBA_HCA instead —
# the backtest must track whatever the engine actually uses, not a frozen copy.
HCA_CONST <- WNBA_HCA

apply_rating_limits_param <- function(rating, limit, dampening) {
  if (is.na(rating)) return(NA_real_)
  if (rating > limit) return(limit + dampening * (rating - limit))
  if (rating < -limit) return(-limit + dampening * (rating + limit))
  return(rating)
}

limit_grid       <- seq(5.0, 25.0, by = 2.5)
dampening_grid   <- seq(0.1, 0.9, by = 0.1)
star_weight_grid <- seq(0.0, 0.5, by = 0.05)

bootstrap_mae_ci <- function(residuals, n_boot = 2000) {
  n <- length(residuals)
  point <- mean(abs(residuals))
  boots <- vapply(1:n_boot, function(i) mean(abs(sample(residuals, n, replace = TRUE))), numeric(1))
  c(mae = point, ci_lo = quantile(boots, 0.025, names = FALSE), ci_hi = quantile(boots, 0.975, names = FALSE))
}

# ==============================================================================
# TRACK A — Walk-forward LOSO CV over all 8 real seasons (limit, dampening)
# ==============================================================================
run_track_a <- function(box_scores) {
  cat("\n==================================================================\n")
  cat(" TRACK A: WALK-FORWARD LOSO CV, REAL SEASONS 2019-2026 (N=1,953 games) \n")
  cat("==================================================================\n\n")

  # Leakage-free rolling point-differential per team, reset each season, same
  # convention as tools/ml_cv_benchmark.R's build_feature_df(method="reset").
  rolled <- box_scores |>
    arrange(team_id, season, game_date) |>
    group_by(season, team_id) |>
    mutate(
      margin = team_score - opponent_team_score,
      roll_margin = slide_dbl(margin, mean, .before = ROLLING_WINDOW_SIZE, .after = -1)
    ) |>
    ungroup()

  home_df <- rolled |> filter(team_home_away == "home") |>
    select(game_id, season, game_date, home_abbr = team_abbreviation,
           home_roll_margin = roll_margin, home_score = team_score, away_score = opponent_team_score)
  away_df <- rolled |> filter(team_home_away == "away") |>
    select(game_id, away_abbr = team_abbreviation, away_roll_margin = roll_margin)

  model_df <- inner_join(home_df, away_df, by = "game_id") |>
    mutate(actual_margin = home_score - away_score) |>
    filter(!is.na(home_roll_margin), !is.na(away_roll_margin))

  cat(sprintf("Rows with a full %d-game trailing rolling window (season 2019's first %d\n",
              ROLLING_WINDOW_SIZE, ROLLING_WINDOW_SIZE))
  cat(sprintf("games/team are necessarily excluded, no lookahead): N = %d / %d real games.\n\n",
              nrow(model_df), nrow(box_scores) / 2))
  print(model_df |> count(season))

  compute_preds <- function(df, limit, dampening) {
    h <- vapply(df$home_roll_margin, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    a <- vapply(df$away_roll_margin, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    (h - a) + HCA_CONST
  }
  compute_mae <- function(df, limit, dampening) {
    mean(abs(df$actual_margin - compute_preds(df, limit, dampening)))
  }

  seasons <- sort(unique(model_df$season))
  fold_results <- list()
  oof_rows <- list()

  grid <- expand.grid(limit = limit_grid, dampening = dampening_grid)

  for (s in seasons) {
    train_df <- model_df |> filter(season != s)
    test_df  <- model_df |> filter(season == s)
    if (nrow(test_df) < 10) {
      cat(sprintf("season %d: only %d rows, skipping fold\n", s, nrow(test_df)))
      next
    }
    grid$mae_train <- mapply(function(l, d) compute_mae(train_df, l, d), grid$limit, grid$dampening)
    best <- grid |> arrange(mae_train) |> slice(1)

    test_preds <- compute_preds(test_df, best$limit, best$dampening)
    fold_mae <- mean(abs(test_df$actual_margin - test_preds))

    fold_results[[as.character(s)]] <- tibble(
      season = s, n = nrow(test_df), fold_best_limit = best$limit,
      fold_best_dampening = best$dampening, fold_train_mae = best$mae_train, fold_test_mae = fold_mae
    )
    oof_rows[[as.character(s)]] <- test_df |> mutate(oof_residual = actual_margin - test_preds)

    cat(sprintf("[fold season=%d] n=%d  train-selected limit=%.1f dampening=%.1f  train MAE=%.3f  OOF test MAE=%.3f\n",
                s, nrow(test_df), best$limit, best$dampening, best$mae_train, fold_mae))
  }

  fold_table <- bind_rows(fold_results)
  oof_table  <- bind_rows(oof_rows)

  cat("\n--- Track A: per-fold selected hyperparameters ---\n")
  print(knitr::kable(fold_table, format = "simple", digits = 3))

  pooled_ci <- bootstrap_mae_ci(oof_table$oof_residual)
  cat(sprintf("\nPooled OOF MAE (honest, walk-forward, never trained on its own season): %.3f  [95%% CI %.3f - %.3f]  (N=%d)\n",
              pooled_ci["mae"], pooled_ci["ci_lo"], pooled_ci["ci_hi"], nrow(oof_table)))

  # Reference: same OOF pooled MAE under fixed defaults / Phase-1 values (no per-fold refitting,
  # since these aren't "selected" combos — just comparison points).
  base_oof_mae <- mean(abs(model_df$actual_margin - compute_preds(model_df, DEFAULT_LIMIT, DEFAULT_DAMPENING)))
  p1_oof_mae   <- mean(abs(model_df$actual_margin - compute_preds(model_df, PHASE1_LIMIT, PHASE1_DAMPENING)))
  cat(sprintf("For reference (fit-once-on-everything, NOT cross-validated):\n"))
  cat(sprintf("  Pre-Phase-1 defaults (limit=15.0, dampening=0.5): MAE = %.3f\n", base_oof_mae))
  cat(sprintf("  Phase 1's boundary optimum (limit=5.0, dampening=0.1): MAE = %.3f\n", p1_oof_mae))

  # Full-data (final) grid search for the single recommended combo, plus stability check.
  grid$mae_full <- mapply(function(l, d) compute_mae(model_df, l, d), grid$limit, grid$dampening)
  best_full <- grid |> arrange(mae_full) |> slice(1)
  neighbor_mask <- (abs(grid$limit - best_full$limit) <= 2.5 + 1e-9) & (abs(grid$dampening - best_full$dampening) <= 0.1 + 1e-9)
  neighbors <- grid[neighbor_mask, ]
  cat(sprintf("\nFull-data grid optimum: limit=%.1f dampening=%.1f  MAE=%.3f\n",
              best_full$limit, best_full$dampening, best_full$mae_full))
  cat(sprintf("Stability (neighbors, n=%d): mean MAE=%.3f sd=%.3f\n",
              nrow(neighbors) - 1, mean(neighbors$mae_full), sd(neighbors$mae_full)))
  is_boundary <- best_full$limit %in% range(limit_grid) || best_full$dampening %in% range(dampening_grid)
  cat(sprintf("Boundary hit: %s\n", is_boundary))

  list(fold_table = fold_table, oof_table = oof_table, pooled_ci = pooled_ci,
       base_oof_mae = base_oof_mae, p1_oof_mae = p1_oof_mae,
       best_full = best_full, is_boundary = is_boundary, grid = grid)
}

# ==============================================================================
# TRACK B — Cross-sectional backtest, real 2026 season (limit, dampening, star_weight)
# ==============================================================================
build_team_lookups <- function() {
  standings_path <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  sq_path        <- file.path(CACHE_DIR, "team_shot_quality.rds")
  rapm_path      <- file.path(CACHE_DIR, "rapm_ratings.rds")
  rost_path      <- file.path(CACHE_DIR, "active_rosters_cache.rds")

  required <- c(standings_path, sq_path, rapm_path, rost_path)
  missing  <- required[!file.exists(required)]
  if (length(missing) > 0) stop(sprintf("Missing required caches: %s", paste(missing, collapse = ", ")))

  standings <- readRDS(standings_path)
  sq_db     <- readRDS(sq_path)
  rapm      <- readRDS(rapm_path)
  rost      <- readRDS(rost_path)

  # ----------------------------------------------------------------------------
  # BUG FOUND during Phase 2 (see docs/HYPERPARAMETER_BACKTEST_PHASE2.md "Critical
  # Finding"): market_odds_engine.R's calculate_matchup_delta() joins rapm_ratings.rds
  # to active_rosters_cache.rds on `player_id`, but the two caches use INCOMPATIBLE ID
  # schemes (rapm's are stats-provider numeric IDs like 201496; rosters' are ESPN athlete
  # IDs like 869) AND incompatible name formats (rapm's player_name is last-name-only,
  # e.g. "Wilson"; rosters' is full "First Last"). The player_id join has ZERO overlap
  # and a naive full-name join also has ZERO overlap, so production's Star Power Delta
  # has been silently returning 0.0 for every single game — this is why Phase 1's
  # optimizer found star_weight=0.0 "optimal": it was never live in the first place, not
  # a genuine finding that the feature doesn't help.
  #
  # WORKAROUND (this script only, NOT applied to market_odds_engine.R): join on
  # (rost$team_name == rapm$team) + normalized last name. Verified safe: zero
  # team+last-name collisions across all 209 rostered players, and every one of the 15
  # teams has >=5 matched players (5-11, median 9) after the join. This recovers 121 of
  # 209 roster players (58%) mapped to a real RAPM rating — enough to meaningfully test
  # star_weight, but production code still needs a real player_id crosswalk (or a
  # last-name join with the same collision-safety check) before Star Power Delta does
  # anything at all live.
  # ----------------------------------------------------------------------------
  norm_last <- function(x) tolower(trimws(gsub("[^a-zA-Z ]", "", word(x, -1))))
  rost_x <- rost |> mutate(last_name = norm_last(player_name))
  rapm_x <- rapm |> mutate(last_name = tolower(trimws(gsub("[^a-zA-Z ]", "", player_name))))
  rapm_joined <- rost_x |>
    inner_join(rapm_x, by = c("team_name" = "team", "last_name"), suffix = c(".rost", ".rapm"))

  abbrs <- names(WNBA_TEAMS)
  raw_net  <- setNames(rep(NA_real_, length(abbrs)), abbrs)
  top_rapm <- setNames(rep(NA_real_, length(abbrs)), abbrs)

  for (abbr in abbrs) {
    full_name <- unname(WNBA_TEAMS[abbr])
    s_row <- standings |> filter(tolower(Team) == tolower(full_name))
    if (nrow(s_row) > 0) {
      net <- as.numeric(s_row$Net_Rating[1])
      luck <- sq_db$shooting_luck_pts[toupper(sq_db$team) == abbr][1] %||% 0.0
      raw_net[abbr] <- net - (0.50 * luck)
    }
    team_matches <- rapm_joined |> filter(team_abbreviation == abbr)
    if (nrow(team_matches) > 0) {
      top <- team_matches |> arrange(desc(total_rapm)) |> slice(1) |> pull(total_rapm)
      if (length(top) > 0) top_rapm[abbr] <- top
    }
  }
  list(raw_net = raw_net, top_rapm = top_rapm)
}

run_track_b <- function(box_scores) {
  cat("\n==================================================================\n")
  cat(" TRACK B: CROSS-SECTIONAL BACKTEST, REAL 2026 SEASON (N=301 games)  \n")
  cat("==================================================================\n\n")

  season_games <- box_scores |> filter(season == 2026, team_home_away == "home") |>
    select(game_id, home_abbr = team_abbreviation, home_score = team_score,
           away_abbr = opponent_team_abbreviation, away_score = opponent_team_score) |>
    distinct()

  lookups <- build_team_lookups()

  analysis_df <- season_games |>
    mutate(
      h_net_raw = lookups$raw_net[home_abbr],
      a_net_raw = lookups$raw_net[away_abbr],
      h_top     = lookups$top_rapm[home_abbr],
      a_top     = lookups$top_rapm[away_abbr],
      star_gap  = ifelse(is.na(h_top) | is.na(a_top), 0.0, h_top - a_top),
      actual_margin = home_score - away_score
    ) |>
    filter(!is.na(h_net_raw), !is.na(a_net_raw))

  cat(sprintf("N = %d real 2026 games matched to current standings/RAPM/shot-quality caches.\n\n", nrow(analysis_df)))

  compute_mae <- function(limit, dampening, star_weight) {
    h <- vapply(analysis_df$h_net_raw, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    a <- vapply(analysis_df$a_net_raw, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    preds <- (h - a) + HCA_CONST + star_weight * analysis_df$star_gap
    mean(abs(analysis_df$actual_margin - preds))
  }
  residuals_for <- function(limit, dampening, star_weight) {
    h <- vapply(analysis_df$h_net_raw, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    a <- vapply(analysis_df$a_net_raw, apply_rating_limits_param, numeric(1), limit = limit, dampening = dampening)
    preds <- (h - a) + HCA_CONST + star_weight * analysis_df$star_gap
    analysis_df$actual_margin - preds
  }

  grid <- expand.grid(limit = limit_grid, dampening = dampening_grid, star_weight = star_weight_grid)
  grid$mae <- mapply(compute_mae, grid$limit, grid$dampening, grid$star_weight)

  default_mae <- compute_mae(DEFAULT_LIMIT, DEFAULT_DAMPENING, DEFAULT_STAR_WEIGHT)
  p1_mae      <- compute_mae(PHASE1_LIMIT, PHASE1_DAMPENING, PHASE1_STAR_WEIGHT)
  best <- grid |> arrange(mae) |> slice(1)

  cat(sprintf("Pre-Phase-1 defaults  (limit=15.0 dampening=0.5 star_weight=0.20): MAE = %.3f\n", default_mae))
  cat(sprintf("Phase 1 boundary opt  (limit=5.0  dampening=0.1 star_weight=0.00): MAE = %.3f\n", p1_mae))
  cat(sprintf("Track B full-grid opt (limit=%.1f dampening=%.1f star_weight=%.2f): MAE = %.3f\n",
              best$limit, best$dampening, best$star_weight, best$mae))

  best_ci    <- bootstrap_mae_ci(residuals_for(best$limit, best$dampening, best$star_weight))
  default_ci <- bootstrap_mae_ci(residuals_for(DEFAULT_LIMIT, DEFAULT_DAMPENING, DEFAULT_STAR_WEIGHT))
  cat(sprintf("Bootstrap 95%% CI — defaults: [%.3f, %.3f]   Track B optimum: [%.3f, %.3f]\n",
              default_ci["ci_lo"], default_ci["ci_hi"], best_ci["ci_lo"], best_ci["ci_hi"]))

  neighbor_mask <- (abs(grid$limit - best$limit) <= 2.5 + 1e-9) &
    (abs(grid$dampening - best$dampening) <= 0.1 + 1e-9) &
    (abs(grid$star_weight - best$star_weight) <= 0.05 + 1e-9)
  neighbors <- grid[neighbor_mask, ]
  cat(sprintf("Stability (neighbors, n=%d): mean MAE=%.3f sd=%.3f\n",
              nrow(neighbors) - 1, mean(neighbors$mae), sd(neighbors$mae)))
  is_boundary <- best$limit %in% range(limit_grid) || best$dampening %in% range(dampening_grid) || best$star_weight %in% range(star_weight_grid)
  cat(sprintf("Boundary hit: %s\n", is_boundary))

  # Marginal sensitivity of star_weight, holding limit/dampening at Track A's recommendation
  # (filled in by the caller) is reported separately in the combined summary below.
  list(grid = grid, best = best, default_mae = default_mae, p1_mae = p1_mae,
       best_ci = best_ci, default_ci = default_ci, is_boundary = is_boundary,
       n = nrow(analysis_df), analysis_df = analysis_df)
}

# ==============================================================================
# Run both tracks, combine into a single recommendation
# ==============================================================================
main <- function() {
  stopifnot(file.exists(CACHE_TEAM_BOX))
  box_scores <- readRDS(CACHE_TEAM_BOX)
  cat(sprintf("[data] %s: %d real team-game rows (%d games), seasons %s\n",
              CACHE_TEAM_BOX, nrow(box_scores), nrow(box_scores) / 2,
              paste(range(box_scores$season), collapse = "-")))

  track_a <- run_track_a(box_scores)
  track_b <- run_track_b(box_scores)

  # Track B, marginal star_weight sweep holding limit/dampening fixed at Track A's
  # walk-forward-validated recommendation (isolates the star_weight effect from the
  # limit/dampening effect, since Track A can't see star_weight and Track B's joint
  # grid optimum can conflate the two).
  cat("\n==================================================================\n")
  cat(" COMBINED: star_weight sweep at Track A's recommended limit/dampening \n")
  cat("==================================================================\n\n")
  fixed_limit <- track_a$best_full$limit
  fixed_damp  <- track_a$best_full$dampening
  sw_sweep <- track_b$grid |>
    filter(limit == fixed_limit, dampening == fixed_damp) |>
    arrange(star_weight)
  print(knitr::kable(sw_sweep |> select(star_weight, mae), format = "simple", digits = 3))
  best_sw <- sw_sweep |> arrange(mae) |> slice(1)

  cat("\n==================================================================\n")
  cat(" FINAL PHASE 2 RECOMMENDATION \n")
  cat("==================================================================\n\n")
  cat(sprintf("limit       = %.1f  (Track A walk-forward LOSO OOF MAE=%.3f, boundary=%s; Track B full-grid agrees=%s)\n",
              fixed_limit, track_a$pooled_ci["mae"], track_a$is_boundary, fixed_limit == track_b$best$limit))
  cat(sprintf("dampening   = %.1f  (same evidence as above)\n", fixed_damp))
  cat(sprintf("star_weight = %.2f  (Track B marginal sweep at Track A's limit/dampening, MAE=%.3f, boundary=%s)\n",
              best_sw$star_weight, best_sw$mae, best_sw$star_weight %in% range(star_weight_grid)))

  saveRDS(list(
    track_a = track_a, track_b = track_b, sw_sweep = sw_sweep,
    recommendation = list(limit = fixed_limit, dampening = fixed_damp, star_weight = best_sw$star_weight)
  ), file.path(CACHE_DIR, "hyperparam_backtest_phase2_results.rds"))
  cat(sprintf("\n[done] Saved %s\n", file.path(CACHE_DIR, "hyperparam_backtest_phase2_results.rds")))

  invisible(list(track_a = track_a, track_b = track_b, recommendation = list(
    limit = fixed_limit, dampening = fixed_damp, star_weight = best_sw$star_weight
  )))
}

if (sys.nframe() == 0) {
  main()
}
