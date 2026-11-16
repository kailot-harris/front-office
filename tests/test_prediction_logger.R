# ==============================================================================
# tests/test_prediction_logger.R
# Test Suite for Game Forecast Accuracy Logger (Issue #111 / Issue 2-2)
#
# Validates:
#   1. Configuration: CACHE_PREDICTION_ACCURACY_LOG declared and points to cache.
#   2. Initial logging: unplayed games recorded with log_source = "LOGGED_PREGAME".
#   3. IMMUTABILITY GATE: consecutive logger runs preserve existing rows without
#      any modification or overwriting of pre-game columns.
#   4. WATERFALL STEP INTEGRITY: five steps sum to projected margin with
#      rounding term <= 0.02.
#   5. Result realization: completed games update realization fields without
#      altering pregame forecast columns.
#   6. Fallback when Elo is absent: step_elo_diff == 0 and Ridge gets 100% weight.
#   7. Neutral site handling: step_home_field == 0 for neutral location games.
#   8. Zero-betting policy: zero forbidden terms across logger and tests.
#
# Runs via:
#   Rscript tests/test_prediction_logger.R
# ==============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("testthat", quietly = TRUE)) {
    library(testthat)
  }
  library(dplyr)
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}

source(file.path(root_dir, "config.R"))
source(file.path(root_dir, "tools", "forecast_engine.R"))
source(file.path(root_dir, "prediction_accuracy_logger.R"))

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

tol <- 1e-9

# Helper to assert numeric equality within tolerance
within_tol <- function(a, b, epsilon = 1e-9) {
  all(abs(a - b) <= epsilon, na.rm = FALSE)
}

# ------------------------------------------------------------------------------
# Test 1: CACHE_PREDICTION_ACCURACY_LOG defined in config.R
# ------------------------------------------------------------------------------
test_that("PAL-1 CACHE_PREDICTION_ACCURACY_LOG constant declared in config.R", {
  cond_exists <- exists("CACHE_PREDICTION_ACCURACY_LOG", mode = "character")
  expected_suffix <- file.path("cache", "prediction_accuracy_log.rds")
  cond_path <- grepl("prediction_accuracy_log\\.rds$", CACHE_PREDICTION_ACCURACY_LOG)

  ok("PAL-1 CACHE_PREDICTION_ACCURACY_LOG defined and points to prediction_accuracy_log.rds",
     cond_exists && cond_path,
     paste("Path:", CACHE_PREDICTION_ACCURACY_LOG))

  expect_true(cond_exists)
  expect_true(cond_path)
})

# ------------------------------------------------------------------------------
# Test 2: Waterfall Steps computation and Rounding term <= 0.02
# ------------------------------------------------------------------------------
test_that("PAL-2 compute_waterfall_steps sums to projected margin with rounding <= 0.02", {
  # Synthetic matchup with known Ridge coefficients
  test_coefs <- list(
    ridge_b_intercept = 2.2427706,
    ridge_b_raw       = 0.1911252,
    ridge_b_prior     = 0.0909437,
    ridge_b_raw_gp    = 0.0101408,
    ridge_b_prior_gp  = 0.0003518
  )

  # Home favored by EPA and Elo
  h_raw   <- 15.5
  a_raw   <- 5.2
  h_prior <- 12.0
  a_prior <- 8.0
  h_gp    <- 9L
  a_gp    <- 9L
  h_elo   <- 1620.0
  a_elo   <- 1480.0
  avg_gp  <- 9.0

  # Step 1: 0.5 * (b_raw + b_raw_gp * avg_gp) * (h_raw - a_raw)
  exp_s1 <- 0.5 * (test_coefs$ridge_b_raw + test_coefs$ridge_b_raw_gp * avg_gp) * (h_raw - a_raw)
  # Step 2: 0.5 * (b_prior + b_prior_gp * avg_gp) * (h_prior - a_prior)
  exp_s2 <- 0.5 * (test_coefs$ridge_b_prior + test_coefs$ridge_b_prior_gp * avg_gp) * (h_prior - a_prior)
  # Step 3: 0.5 * (h_elo - a_elo) / 25
  exp_s3 <- 0.5 * (h_elo - a_elo) / 25.0
  # Step 4: 0.5 * ridge_intercept + 0.5 * 48 / 25
  exp_s4 <- 0.5 * test_coefs$ridge_b_intercept + 0.5 * (48.0 / 25.0)
  # Step 5: 1.60 * (away_backup - home_backup) = 1.60 * (1 - 0) = 1.60
  exp_s5 <- 1.60 * (1L - 0L)

  expected_proj_margin <- exp_s1 + exp_s2 + exp_s3 + exp_s4 + exp_s5

  wf <- compute_waterfall_steps(
    home_raw           = h_raw,
    away_raw           = a_raw,
    home_prior         = h_prior,
    away_prior         = a_prior,
    home_gp            = h_gp,
    away_gp            = a_gp,
    home_elo           = h_elo,
    away_elo           = a_elo,
    elo_available      = TRUE,
    neutral            = FALSE,
    home_qb_backup     = FALSE,
    away_qb_backup     = TRUE,
    ridge_coefs        = test_coefs,
    projected_margin   = expected_proj_margin
  )

  sum_five <- wf$step_current_epa + wf$step_prior_epa + wf$step_elo_diff + wf$step_home_field + wf$step_qb_adjustment
  rounding <- wf$step_rounding

  cond_s1 <- within_tol(wf$step_current_epa, exp_s1, tol)
  cond_s2 <- within_tol(wf$step_prior_epa, exp_s2, tol)
  cond_s3 <- within_tol(wf$step_elo_diff, exp_s3, tol)
  cond_s4 <- within_tol(wf$step_home_field, exp_s4, tol)
  cond_s5 <- within_tol(wf$step_qb_adjustment, exp_s5, tol)
  cond_sum <- within_tol(sum_five + rounding, expected_proj_margin, tol)
  cond_round <- abs(rounding) <= 0.02

  ok("PAL-2 Waterfall step decomposition exact to within 1e-9 and rounding <= 0.02",
     cond_s1 && cond_s2 && cond_s3 && cond_s4 && cond_s5 && cond_sum && cond_round,
     sprintf("rounding = %.2e", rounding))

  expect_true(cond_s1)
  expect_true(cond_s2)
  expect_true(cond_s3)
  expect_true(cond_s4)
  expect_true(cond_s5)
  expect_true(cond_sum)
  expect_true(cond_round)
})

# ------------------------------------------------------------------------------
# Test 3: Fallback to 100% Ridge weight when Elo is absent
# ------------------------------------------------------------------------------
test_that("PAL-3 Waterfall fallback when Elo is NA or unavailable", {
  test_coefs <- list(
    ridge_b_intercept = 2.0,
    ridge_b_raw       = 0.20,
    ridge_b_prior     = 0.10,
    ridge_b_raw_gp    = 0.01,
    ridge_b_prior_gp  = 0.001
  )

  wf_no_elo <- compute_waterfall_steps(
    home_raw           = 10.0,
    away_raw           = 0.0,
    home_prior         = 5.0,
    away_prior         = 5.0,
    home_gp            = 4L,
    away_gp            = 4L,
    home_elo           = NA_real_,
    away_elo           = NA_real_,
    elo_available      = FALSE,
    neutral            = FALSE,
    home_qb_backup     = FALSE,
    away_qb_backup     = FALSE,
    ridge_coefs        = test_coefs
  )

  # When Elo is absent:
  # step_elo_diff must be 0
  # step_current_epa has 1.0 weight: 1.0 * (0.20 + 0.01 * 4) * 10 = 2.40
  # step_home_field has 1.0 weight: 1.0 * 2.0 = 2.0
  cond_elo_zero <- wf_no_elo$step_elo_diff == 0.0
  cond_raw_100  <- within_tol(wf_no_elo$step_current_epa, 1.0 * (0.20 + 0.01 * 4.0) * 10.0, tol)
  cond_hca_100  <- within_tol(wf_no_elo$step_home_field, 2.0, tol)

  ok("PAL-3 Fallback when Elo is absent sets step_elo_diff = 0 and Ridge weight = 1.0",
     cond_elo_zero && cond_raw_100 && cond_hca_100,
     sprintf("step_elo_diff=%.1f, step_current_epa=%.2f, step_home_field=%.2f",
             wf_no_elo$step_elo_diff, wf_no_elo$step_current_epa, wf_no_elo$step_home_field))

  expect_true(cond_elo_zero)
  expect_true(cond_raw_100)
  expect_true(cond_hca_100)
})

# ------------------------------------------------------------------------------
# Test 4: Neutral site zeroes home field step
# ------------------------------------------------------------------------------
test_that("PAL-4 Neutral site zeroes home field step in waterfall", {
  wf_neutral <- compute_waterfall_steps(
    home_raw       = 5.0,
    away_raw       = 5.0,
    home_prior     = 0.0,
    away_prior     = 0.0,
    home_gp        = 5L,
    away_gp        = 5L,
    home_elo       = 1500.0,
    away_elo       = 1500.0,
    neutral        = TRUE,
    b_intercept    = 2.25
  )

  cond_zero_hca <- wf_neutral$step_home_field == 0.0
  ok("PAL-4 Neutral site sets step_home_field = 0",
     cond_zero_hca,
     sprintf("step_home_field = %.1f", wf_neutral$step_home_field))

  expect_true(cond_zero_hca)
})

# ------------------------------------------------------------------------------
# Test 5: IMMUTABILITY GATE — consecutive logger runs preserve existing rows
# ------------------------------------------------------------------------------
test_that("PAL-5 Immutability Gate: consecutive runs preserve existing rows without modification", {
  temp_dir <- tempfile("test_pred_logger_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  # Create initial schedule with 2 unplayed games
  sch_df <- data.frame(
    game_id    = c("2026_11_KC_BUF", "2026_11_BAL_PIT"),
    season     = c(2026L, 2026L),
    week       = c(11L, 11L),
    gameday    = c("2026-11-22", "2026-11-22"),
    weekday    = c("Sunday", "Sunday"),
    gametime   = c("16:25", "13:00"),
    home_team  = c("BUF", "PIT"),
    away_team  = c("KC", "BAL"),
    home_score = c(NA_integer_, NA_integer_),
    away_score = c(NA_integer_, NA_integer_),
    location   = c("Home", "Home"),
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  # Team ratings lookup
  tr_df <- data.frame(
    team                = c("BUF", "KC", "PIT", "BAL", "NE", "MIA"),
    current_raw_rating  = c(18.0, 14.0, 6.0, 10.0, 2.0, 8.0),
    prior_season_rating = c(16.0, 15.0, 8.0, 12.0, 3.0, 7.0),
    power_rating        = c(17.5, 14.5, 6.5, 10.5, 2.2, 7.8),
    games_played        = c(9L, 9L, 9L, 9L, 9L, 9L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  test_coefs <- list(
    ridge_b_intercept = 2.2427706,
    ridge_b_raw       = 0.1911252,
    ridge_b_prior     = 0.0909437,
    ridge_b_raw_gp    = 0.0101408,
    ridge_b_prior_gp  = 0.0003518
  )

  # Compute exact projected margins for test games using waterfall formula
  # Game 1: BUF (home) vs KC (away), diff_raw=4, diff_prior=1, gp=9
  m1 <- 1.0 * (test_coefs$ridge_b_raw + test_coefs$ridge_b_raw_gp * 9) * 4 +
        1.0 * (test_coefs$ridge_b_prior + test_coefs$ridge_b_prior_gp * 9) * 1 +
        test_coefs$ridge_b_intercept
  # Game 2: PIT (home) vs BAL (away), diff_raw=-4, diff_prior=-4, gp=9
  m2 <- 1.0 * (test_coefs$ridge_b_raw + test_coefs$ridge_b_raw_gp * 9) * (-4) +
        1.0 * (test_coefs$ridge_b_prior + test_coefs$ridge_b_prior_gp * 9) * (-4) +
        test_coefs$ridge_b_intercept

  # Projected matchups for week 11
  pm_df <- data.frame(
    game_id           = c("2026_11_KC_BUF", "2026_11_BAL_PIT"),
    season            = c(2026L, 2026L),
    week              = c(11L, 11L),
    home_team         = c("BUF", "PIT"),
    away_team         = c("KC", "BAL"),
    home_power_rating = c(17.5, 6.5),
    away_power_rating = c(14.5, 10.5),
    home_games_played = c(9L, 9L),
    away_games_played = c(9L, 9L),
    projected_margin  = c(m1, m2),
    home_win_prob     = c(pnorm(m1 / 14.60), pnorm(m2 / 14.60)),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # RUN 1: Initial logging
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list()
  )

  log_run1 <- readRDS(test_log_path)
  cond_count1 <- nrow(log_run1) == 2L
  cond_source1 <- all(log_run1$log_source == "LOGGED_PREGAME")

  # Snapshot all pre-game values from run 1
  snapshot_cols <- c(
    "game_id", "season", "week", "home_team", "away_team", "log_source",
    "home_power_rating", "away_power_rating", "projected_margin", "home_win_prob",
    "step_current_epa", "step_prior_epa", "step_elo_diff", "step_home_field",
    "step_qb_adjustment", "step_rounding", "ridge_b_intercept", "ridge_b_raw"
  )
  snap1 <- log_run1[, snapshot_cols]

  # Modify projected matchups and team ratings as if a subsequent pipeline run
  # had newer ratings for future games or changed underlying ratings
  pm_df_modified <- pm_df
  pm_df_modified$projected_margin[1] <- 99.9  # drastically changed projection
  pm_df_modified$home_win_prob[1]    <- 0.99
  # Also add a new 3rd game with exact margin
  m3 <- 1.0 * (test_coefs$ridge_b_raw + test_coefs$ridge_b_raw_gp * 9) * (-6) +
        1.0 * (test_coefs$ridge_b_prior + test_coefs$ridge_b_prior_gp * 9) * (-4) +
        test_coefs$ridge_b_intercept
  pm_df_modified <- bind_rows(pm_df_modified, data.frame(
    game_id           = "2026_11_MIA_NE",
    season            = 2026L,
    week              = 11L,
    home_team         = "NE",
    away_team         = "MIA",
    home_power_rating = 2.0,
    away_power_rating = 8.0,
    home_games_played = 9L,
    away_games_played = 9L,
    projected_margin  = m3,
    home_win_prob     = pnorm(m3 / 14.60),
    stringsAsFactors  = FALSE
  ))
  saveRDS(pm_df_modified, test_pm_path)

  # RUN 2: Subsequent run
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list()
  )

  log_run2 <- readRDS(test_log_path)
  cond_count2 <- nrow(log_run2) == 3L  # 2 original + 1 new

  # Filter down to the 2 original games in run 2
  snap2 <- log_run2[log_run2$game_id %in% snap1$game_id, snapshot_cols]
  snap2 <- snap2[order(snap2$game_id), ]
  snap1_ordered <- snap1[order(snap1$game_id), ]

  # IMMUTABILITY GATE ASSERTION:
  # Values for the 2 original games must be 100% IDENTICAL to run 1 snapshot
  cond_immutable <- isTRUE(all.equal(snap1_ordered, snap2))
  # In particular, projected_margin[1] must NOT be 99.9!
  cond_not_overwritten <- log_run2$projected_margin[log_run2$game_id == "2026_11_KC_BUF"] == m1

  ok("PAL-5 Immutability gate: existing logged games are NEVER overwritten on subsequent runs",
     cond_count1 && cond_source1 && cond_count2 && cond_immutable && cond_not_overwritten,
     sprintf("Run 1 rows: %d, Run 2 rows: %d, Immutability preserved: %s",
             nrow(log_run1), nrow(log_run2), cond_immutable))

  expect_true(cond_count1)
  expect_true(cond_source1)
  expect_true(cond_count2)
  expect_true(cond_immutable)
  expect_true(cond_not_overwritten)
})

# ------------------------------------------------------------------------------
# Test 6: Game Completion updates results without altering pregame columns
# ------------------------------------------------------------------------------
test_that("PAL-6 Game completion updates result fields while preserving pregame columns", {
  temp_dir <- tempfile("test_pred_logger_finish_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_log.rds")
  test_sch_path <- file.path(temp_dir, "test_sch.rds")
  test_pm_path  <- file.path(temp_dir, "test_pm.rds")
  test_tr_path  <- file.path(temp_dir, "test_tr.rds")

  sch_df <- data.frame(
    game_id    = "2026_10_LA_ARI",
    season     = 2026L,
    week       = 10L,
    gameday    = "2026-11-15",
    weekday    = "Sunday",
    gametime   = "16:05",
    home_team  = "ARI",
    away_team  = "LA",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("ARI", "LA"),
    current_raw_rating  = c(-9.2, 8.0),
    prior_season_rating = c(-8.0, 7.0),
    power_rating        = c(-8.8, 7.5),
    games_played        = c(9L, 9L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  test_coefs <- list(
    ridge_b_intercept = 2.2427706,
    ridge_b_raw       = 0.1911252,
    ridge_b_prior     = 0.0909437,
    ridge_b_raw_gp    = 0.0101408,
    ridge_b_prior_gp  = 0.0003518
  )

  m_ari <- 1.0 * (test_coefs$ridge_b_raw + test_coefs$ridge_b_raw_gp * 9) * (-17.2) +
           1.0 * (test_coefs$ridge_b_prior + test_coefs$ridge_b_prior_gp * 9) * (-15.0) +
           test_coefs$ridge_b_intercept - 1.60
  p_ari <- pnorm(m_ari / 14.60)

  pm_df <- data.frame(
    game_id           = "2026_10_LA_ARI",
    season            = 2026L,
    week              = 10L,
    home_team         = "ARI",
    away_team         = "LA",
    home_power_rating = -8.8,
    away_power_rating = 7.5,
    home_games_played = 9L,
    away_games_played = 9L,
    projected_margin  = m_ari,
    home_win_prob     = p_ari,
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # Pre-game run
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(ARI = TRUE)
  )

  pre_log <- readRDS(test_log_path)
  cond_pre_na <- is.na(pre_log$home_score[1]) && is.na(pre_log$actual_margin[1])

  # Now game finishes: ARI 24, LA 20 (Upset: ARI wins by +4)
  sch_df$home_score[1] <- 24L
  sch_df$away_score[1] <- 20L
  saveRDS(sch_df, test_sch_path)

  # Run logger after game finish
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(ARI = TRUE)
  )

  post_log <- readRDS(test_log_path)

  # Result fields must now be populated
  cond_home_score <- post_log$home_score[1] == 24L
  cond_away_score <- post_log$away_score[1] == 20L
  cond_margin     <- post_log$actual_margin[1] == 4.0
  cond_winner     <- post_log$actual_winner[1] == "ARI"
  # Model predicted LA (projected_margin was negative), ARI won -> prediction_correct is FALSE
  cond_correct    <- post_log$prediction_correct[1] == FALSE
  # Brier score: ARI won (outcome 1), home_win_prob = p_ari -> (1 - p_ari)^2
  expected_brier  <- (1.0 - p_ari)^2
  cond_brier      <- within_tol(post_log$brier_score[1], expected_brier, 1e-4)

  # Pre-game forecast columns must remain identical
  cond_pre_margin <- post_log$projected_margin[1] == pre_log$projected_margin[1]
  cond_pre_prob   <- post_log$home_win_prob[1] == pre_log$home_win_prob[1]
  cond_pre_step1  <- post_log$step_current_epa[1] == pre_log$step_current_epa[1]
  cond_pre_source <- post_log$log_source[1] == "LOGGED_PREGAME"

  cond_all <- cond_pre_na && cond_home_score && cond_away_score && cond_margin &&
              cond_winner && cond_correct && cond_brier && cond_pre_margin &&
              cond_pre_prob && cond_pre_step1 && cond_pre_source

  ok("PAL-6 Realized scores updated for finished game without altering pre-game forecasts",
     cond_all,
     sprintf("Actual margin: %.1f, winner: %s, correct: %s, brier: %.4f",
             post_log$actual_margin[1], post_log$actual_winner[1],
             post_log$prediction_correct[1], post_log$brier_score[1]))

  expect_true(cond_all)
})

# ------------------------------------------------------------------------------
# Test 7: Production cache end-to-end run verification
# ------------------------------------------------------------------------------
test_that("PAL-7 Logger runs against real repository cache and verifies waterfall sum <= 0.02", {
  if (file.exists(CACHE_PROJECTED_MATCHUPS) && file.exists(CACHE_SCHEDULES)) {
    temp_dir <- tempfile("test_pred_logger_prod_")
    dir.create(temp_dir, recursive = TRUE)
    on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)
    prod_test_log <- file.path(temp_dir, "prediction_accuracy_log.rds")

    prod_coefs <- list(
      ridge_b_intercept = 2.2427706,
      ridge_b_raw       = 0.1911252,
      ridge_b_prior     = 0.0909437,
      ridge_b_raw_gp    = 0.0101408,
      ridge_b_prior_gp  = 0.0003518
    )

    # Run logger with production caches and fitted ridge coefficients
    run_prediction_accuracy_logger(log_path = prod_test_log, ridge_coefs = prod_coefs)

    log_df <- readRDS(prod_test_log)
    cond_rows <- nrow(log_df) > 0

    # Verify waterfall steps sum to projected margin within 0.02 for all logged rows
    steps_sum <- log_df$step_current_epa + log_df$step_prior_epa +
                 log_df$step_elo_diff + log_df$step_home_field +
                 log_df$step_qb_adjustment
    reconstructed_margin <- steps_sum + log_df$step_rounding
    diff_from_margin <- abs(reconstructed_margin - log_df$projected_margin)
    max_diff <- max(diff_from_margin, na.rm = TRUE)
    max_rounding <- max(abs(log_df$step_rounding), na.rm = TRUE)

    cond_exact_reconstruct <- max_diff <= 1e-6
    cond_rounding_threshold <- max_rounding <= 0.02

    ok("PAL-7 Real cache end-to-end: all waterfall steps reconstruct projected margin and rounding <= 0.02",
       cond_rows && cond_exact_reconstruct && cond_rounding_threshold,
       sprintf("N=%d games, max margin reconstruction diff: %.2e, max rounding: %.2e",
               nrow(log_df), max_diff, max_rounding))

    expect_true(cond_rows)
    expect_true(cond_exact_reconstruct)
    expect_true(cond_rounding_threshold)
  } else {
    ok("PAL-7 Skipped production cache test (caches not present in testing environment)", TRUE)
  }
})

# ------------------------------------------------------------------------------
# Test 8: Zero-Betting Policy Guard
# ------------------------------------------------------------------------------
test_that("PAL-8 Zero-Betting Policy: zero forbidden terms across files", {
  files_to_check <- c(
    file.path(root_dir, "prediction_accuracy_logger.R"),
    file.path(root_dir, "tools", "forecast_engine.R"),
    file.path(root_dir, "tests", "test_prediction_logger.R")
  )

  banned_patterns <- c(
    "\\bspread\\b",
    "\\bspreads\\b",
    "\\btotal\\b",
    "\\btotals\\b",
    "\\bmoneyline\\b",
    "\\bmoneylines\\b",
    "\\bsportsbook\\b",
    "\\bsportsbooks\\b",
    "\\bwager\\b",
    "\\bwagers\\b",
    "\\bclosing line\\b",
    "\\bsharp_book\\b",
    "\\bThe Odds API\\b"
  )

  violations <- character(0)
  for (f in files_to_check) {
    if (file.exists(f)) {
      lines <- readLines(f, warn = FALSE)
      for (pat in banned_patterns) {
        matches <- grep(pat, lines, ignore.case = TRUE, value = TRUE)
        if (length(matches) > 0) {
          violations <- c(violations, sprintf("%s [%s]: %s", basename(f), pat, matches[1]))
        }
      }
    }
  }

  cond_clean <- length(violations) == 0L
  ok("PAL-8 Zero-betting policy: zero forbidden terms in logger, forecast engine, and tests",
     cond_clean,
     if (cond_clean) "clean" else paste(violations, collapse = "; "))

  expect_true(cond_clean)
})

# Summary
cat(sprintf("\n=== Prediction Logger Test Summary: %d failures ===\n", failures))
if (failures > 0L) quit(status = 1L)
