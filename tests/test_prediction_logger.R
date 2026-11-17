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
# Test 5: KICKOFF FREEZE & TIMESTAMPS MATRIX (Issue #149)
# ------------------------------------------------------------------------------
test_that("PAL-5a Pre-kickoff refresh updates forecast, waterfall, and refreshed_at, keeping logged_at unchanged", {
  temp_dir <- tempfile("test_pred_logger_5a_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  sch_df <- data.frame(
    game_id    = "2026_12_KC_BUF",
    season     = 2026L,
    week       = 12L,
    gameday    = "2026-11-29",
    weekday    = "Sunday",
    gametime   = "16:25",
    home_team  = "BUF",
    away_team  = "KC",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("BUF", "KC"),
    current_raw_rating  = c(18.0, 14.0),
    prior_season_rating = c(16.0, 15.0),
    power_rating        = c(17.5, 14.5),
    games_played        = c(10L, 10L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  test_coefs <- list(
    ridge_b_intercept = 2.0,
    ridge_b_raw       = 0.20,
    ridge_b_prior     = 0.10,
    ridge_b_raw_gp    = 0.01,
    ridge_b_prior_gp  = 0.001
  )

  # Exact margin: 2.0 + (0.2 + 0.1)*4 + (0.1 + 0.01)*1 = 2.0 + 1.2 + 0.11 = 3.31
  m1 <- 3.31
  pm_df1 <- data.frame(
    game_id           = "2026_12_KC_BUF",
    season            = 2026L,
    week              = 12L,
    home_team         = "BUF",
    away_team         = "KC",
    home_power_rating = 17.5,
    away_power_rating = 14.5,
    home_games_played = 10L,
    away_games_played = 10L,
    projected_margin  = m1,
    home_win_prob     = pnorm(m1 / 14.60),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df1, test_pm_path)

  # Initial run on Wednesday Nov 25 at 10:00 Eastern
  t1 <- as.POSIXct("2026-11-25 10:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(),
    as_of                   = t1
  )

  log1 <- readRDS(test_log_path)
  cond_init_margin <- abs(log1$projected_margin[1] - m1) < 1e-6
  cond_init_logged <- log1$logged_at[1] == t1
  cond_init_refreshed <- log1$refreshed_at[1] == t1

  # BUF raw rating updates to 19.0 (diff_raw = 5.0) -> exact margin: 2.0 + 1.5 + 0.11 = 3.61
  tr_df$current_raw_rating[tr_df$team == "BUF"] <- 19.0
  saveRDS(tr_df, test_tr_path)

  m2 <- 3.61
  pm_df2 <- pm_df1
  pm_df2$projected_margin <- m2
  pm_df2$home_win_prob <- pnorm(m2 / 14.60)
  saveRDS(pm_df2, test_pm_path)

  t2 <- as.POSIXct("2026-11-28 14:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(),
    as_of                   = t2
  )

  log2 <- readRDS(test_log_path)
  cond_updated_margin <- abs(log2$projected_margin[1] - m2) < 1e-6
  cond_logged_unchanged <- log2$logged_at[1] == t1
  cond_refreshed_updated <- log2$refreshed_at[1] == t2
  cond_wf_sums <- abs((log2$step_current_epa[1] + log2$step_prior_epa[1] +
                       log2$step_elo_diff[1] + log2$step_home_field[1] +
                       log2$step_qb_adjustment[1] + log2$step_rounding[1]) - m2) < 1e-6

  cond_all <- cond_init_margin && cond_init_logged && cond_init_refreshed &&
              cond_updated_margin && cond_logged_unchanged && cond_refreshed_updated && cond_wf_sums

  ok("PAL-5a Pre-kickoff refresh updates forecast, waterfall, and refreshed_at, keeping logged_at unchanged",
     cond_all,
     sprintf("Initial margin: %.2f, refreshed margin: %.2f, logged_at: %s, refreshed_at: %s",
             log1$projected_margin[1], log2$projected_margin[1],
             as.character(log2$logged_at[1]), as.character(log2$refreshed_at[1])))

  expect_true(cond_all)
})

test_that("PAL-5b Post-kickoff run (as_of >= kickoff_time) leaves forecast completely frozen", {
  temp_dir <- tempfile("test_pred_logger_5b_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  # Kickoff is 2026-11-29 16:25:00 Eastern
  sch_df <- data.frame(
    game_id    = "2026_12_KC_BUF",
    season     = 2026L,
    week       = 12L,
    gameday    = "2026-11-29",
    weekday    = "Sunday",
    gametime   = "16:25",
    home_team  = "BUF",
    away_team  = "KC",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("BUF", "KC"),
    current_raw_rating  = c(18.0, 14.0),
    prior_season_rating = c(16.0, 15.0),
    power_rating        = c(17.5, 14.5),
    games_played        = c(10L, 10L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  m_pre <- 3.31
  pm_df <- data.frame(
    game_id           = "2026_12_KC_BUF",
    season            = 2026L,
    week              = 12L,
    home_team         = "BUF",
    away_team         = "KC",
    home_power_rating = 17.5,
    away_power_rating = 14.5,
    home_games_played = 10L,
    away_games_played = 10L,
    projected_margin  = m_pre,
    home_win_prob     = pnorm(m_pre / 14.60),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # Initial log prior to kickoff
  t_pre <- as.POSIXct("2026-11-29 12:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_pre
  )

  # Projected matchups changes significantly after kickoff
  pm_df$projected_margin <- 99.9
  pm_df$home_win_prob <- 0.99
  saveRDS(pm_df, test_pm_path)

  # 1. Post-kickoff run at 16:30 Eastern (kickoff was 16:25)
  t_post <- as.POSIXct("2026-11-29 16:30:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_post
  )

  log_post <- readRDS(test_log_path)
  cond_frozen_margin <- abs(log_post$projected_margin[1] - m_pre) < 1e-6
  cond_refreshed_not_changed <- log_post$refreshed_at[1] == t_pre

  # 2. Mid-run safety: run started at 16:20 (before kickoff) but evaluated at 16:26 (after kickoff)
  t_mid_start <- as.POSIXct("2026-11-29 16:20:00", tz = "America/New_York")
  t_mid_eval  <- as.POSIXct("2026-11-29 16:26:00", tz = "America/New_York")
  pm_df$projected_margin <- -50.0
  saveRDS(pm_df, test_pm_path)

  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_mid_start,
    eval_time               = t_mid_eval
  )

  log_mid <- readRDS(test_log_path)
  cond_mid_frozen <- abs(log_mid$projected_margin[1] - m_pre) < 1e-6

  cond_all <- cond_frozen_margin && cond_refreshed_not_changed && cond_mid_frozen

  ok("PAL-5b Post-kickoff run and mid-run kickoff evaluation leave forecast completely frozen",
     cond_all,
     sprintf("Margin remained %.2f (not 99.9 or -50.0), refreshed_at: %s", m_pre, as.character(log_mid$refreshed_at[1])))

  expect_true(cond_all)
})

test_that("PAL-5c Missing kickoff time (gametime = NA) freezes at start of the day in Eastern time", {
  temp_dir <- tempfile("test_pred_logger_5c_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  # Game on 2026-11-29 with gametime = NA (missing kickoff time)
  sch_df <- data.frame(
    game_id    = "2026_12_KC_BUF",
    season     = 2026L,
    week       = 12L,
    gameday    = "2026-11-29",
    weekday    = "Sunday",
    gametime   = NA_character_,
    home_team  = "BUF",
    away_team  = "KC",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("BUF", "KC"),
    current_raw_rating  = c(18.0, 14.0),
    prior_season_rating = c(16.0, 15.0),
    power_rating        = c(17.5, 14.5),
    games_played        = c(10L, 10L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  m_val <- 3.31
  pm_df <- data.frame(
    game_id           = "2026_12_KC_BUF",
    season            = 2026L,
    week              = 12L,
    home_team         = "BUF",
    away_team         = "KC",
    home_power_rating = 17.5,
    away_power_rating = 14.5,
    home_games_played = 10L,
    away_games_played = 10L,
    projected_margin  = m_val,
    home_win_prob     = pnorm(m_val / 14.60),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # Initial log on Saturday Nov 28 at 20:00 Eastern (before midnight date start)
  t_prev_day <- as.POSIXct("2026-11-28 20:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_prev_day
  )

  log1 <- readRDS(test_log_path)
  expected_freeze_ko <- as.POSIXct("2026-11-29 00:00:00", tz = "America/New_York")
  cond_ko_time <- log1$kickoff_time[1] == expected_freeze_ko
  cond_ko_fb   <- isTRUE(log1$kickoff_fallback[1])

  # Now run on Sunday Nov 29 at 08:00 Eastern (after midnight date start, but morning)
  t_gameday_morning <- as.POSIXct("2026-11-29 08:00:00", tz = "America/New_York")
  pm_df$projected_margin <- 99.9
  saveRDS(pm_df, test_pm_path)

  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_gameday_morning
  )

  log2 <- readRDS(test_log_path)
  cond_frozen <- abs(log2$projected_margin[1] - m_val) < 1e-6  # Frozen at midnight, not refreshed to 99.9!

  cond_all <- cond_ko_time && cond_ko_fb && cond_frozen

  ok("PAL-5c Missing kickoff time freezes at start of the day (00:00:00 Eastern) with kickoff_fallback = TRUE",
     cond_all,
     sprintf("Kickoff time: %s, fallback flag: %s, frozen margin: %.2f",
             as.character(log2$kickoff_time[1]), log2$kickoff_fallback[1], log2$projected_margin[1]))

  expect_true(cond_all)
})

test_that("PAL-5d Unlogged game past kickoff is NOT created as LOGGED_PREGAME", {
  temp_dir <- tempfile("test_pred_logger_5d_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  sch_df <- data.frame(
    game_id    = "2026_12_DAL_WAS",
    season     = 2026L,
    week       = 12L,
    gameday    = "2026-11-29",
    weekday    = "Sunday",
    gametime   = "13:00",
    home_team  = "WAS",
    away_team  = "DAL",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("WAS", "DAL"),
    current_raw_rating  = c(10.0, 8.0),
    prior_season_rating = c(9.0, 7.0),
    power_rating        = c(9.5, 7.5),
    games_played        = c(10L, 10L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  pm_df <- data.frame(
    game_id           = "2026_12_DAL_WAS",
    season            = 2026L,
    week              = 12L,
    home_team         = "WAS",
    away_team         = "DAL",
    home_power_rating = 9.5,
    away_power_rating = 7.5,
    home_games_played = 10L,
    away_games_played = 10L,
    projected_margin  = 2.0,
    home_win_prob     = pnorm(2.0 / 14.60),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # Logger runs at 14:00 Eastern (1 hour after kickoff 13:00) with empty prior log
  t_post_ko <- as.POSIXct("2026-11-29 14:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = list(ridge_b_intercept = 2, ridge_b_raw = 0.2, ridge_b_prior = 0.1, ridge_b_raw_gp = 0.01, ridge_b_prior_gp = 0.001),
    qb_lookup               = list(),
    as_of                   = t_post_ko
  )

  # Log must NOT exist or have 0 rows
  cond_no_row <- !file.exists(test_log_path) || nrow(readRDS(test_log_path)) == 0L

  ok("PAL-5d No pre-game row created for game after kickoff",
     cond_no_row,
     if (cond_no_row) "Game correctly excluded from LOGGED_PREGAME" else "FAIL: Row was created post-kickoff")

  expect_true(cond_no_row)
})

test_that("PAL-5e Rescheduled game follows its new kickoff time", {
  temp_dir <- tempfile("test_pred_logger_5e_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  test_log_path <- file.path(temp_dir, "test_prediction_log.rds")
  test_sch_path <- file.path(temp_dir, "test_schedules.rds")
  test_pm_path  <- file.path(temp_dir, "test_projected_matchups.rds")
  test_tr_path  <- file.path(temp_dir, "test_team_ratings.rds")

  # Game originally scheduled for Sunday 13:00
  sch_df <- data.frame(
    game_id    = "2026_12_BAL_CLE",
    season     = 2026L,
    week       = 12L,
    gameday    = "2026-11-29",
    weekday    = "Sunday",
    gametime   = "13:00",
    home_team  = "CLE",
    away_team  = "BAL",
    home_score = NA_integer_,
    away_score = NA_integer_,
    location   = "Home",
    stringsAsFactors = FALSE
  )
  saveRDS(sch_df, test_sch_path)

  tr_df <- data.frame(
    team                = c("CLE", "BAL"),
    current_raw_rating  = c(2.0, 12.0),
    prior_season_rating = c(3.0, 11.0),
    power_rating        = c(2.5, 11.5),
    games_played        = c(10L, 10L),
    stringsAsFactors    = FALSE
  )
  saveRDS(tr_df, test_tr_path)

  test_coefs <- list(
    ridge_b_intercept = 2.0,
    ridge_b_raw       = 0.20,
    ridge_b_prior     = 0.10,
    ridge_b_raw_gp    = 0.01,
    ridge_b_prior_gp  = 0.001
  )

  # Exact margin: 2.0 + 0.3*(-10) + 0.11*(-8) = 2.0 - 3.0 - 0.88 = -1.88
  m1 <- -1.88
  pm_df <- data.frame(
    game_id           = "2026_12_BAL_CLE",
    season            = 2026L,
    week              = 12L,
    home_team         = "CLE",
    away_team         = "BAL",
    home_power_rating = 2.5,
    away_power_rating = 11.5,
    home_games_played = 10L,
    away_games_played = 10L,
    projected_margin  = m1,
    home_win_prob     = pnorm(m1 / 14.60),
    stringsAsFactors  = FALSE
  )
  saveRDS(pm_df, test_pm_path)

  # Initial log on Wednesday Nov 25
  t_init <- as.POSIXct("2026-11-25 10:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(),
    as_of                   = t_init
  )

  # NFL flexes game to Monday Night 20:15
  sch_df$gameday  <- "2026-11-30"
  sch_df$weekday  <- "Monday"
  sch_df$gametime <- "20:15"
  saveRDS(sch_df, test_sch_path)

  # On Sunday Nov 29 at 15:00 Eastern (after the old 13:00 kickoff, but before new Monday 20:15 kickoff)
  # CLE raw drops to 0.0 (diff_raw = -12.0) -> margin: 2.0 - 3.60 - 0.88 = -2.48
  tr_df$current_raw_rating[tr_df$team == "CLE"] <- 0.0
  saveRDS(tr_df, test_tr_path)

  m2 <- -2.48
  pm_df$projected_margin <- m2
  pm_df$home_win_prob <- pnorm(m2 / 14.60)
  saveRDS(pm_df, test_pm_path)

  t_resched <- as.POSIXct("2026-11-29 15:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(),
    as_of                   = t_resched
  )

  log_resched <- readRDS(test_log_path)
  expected_new_ko <- as.POSIXct("2026-11-30 20:15:00", tz = "America/New_York")
  cond_ko_updated <- log_resched$kickoff_time[1] == expected_new_ko
  cond_refreshed  <- log_resched$refreshed_at[1] == t_resched
  cond_margin_updated <- abs(log_resched$projected_margin[1] - m2) < 1e-6

  cond_all <- cond_ko_updated && cond_refreshed && cond_margin_updated

  ok("PAL-5e Rescheduled game follows new kickoff time and refreshes until new freeze",
     cond_all,
     sprintf("Updated kickoff: %s, refreshed margin: %.2f, refreshed_at: %s",
             as.character(log_resched$kickoff_time[1]), log_resched$projected_margin[1],
             as.character(log_resched$refreshed_at[1])))

  expect_true(cond_all)
})

test_that("PAL-5f Dual timestamps and kickoff audit columns verified non-null across log", {
  fixture_path <- file.path(root_dir, "tests", "fixtures", "prediction_accuracy_log_fixture.rds")
  if (file.exists(fixture_path)) {
    log_df <- readRDS(fixture_path)
    cond_logged_not_na    <- all(!is.na(log_df$logged_at))
    cond_refreshed_not_na <- all(!is.na(log_df$refreshed_at))
    cond_ko_not_na        <- all(!is.na(log_df$kickoff_time))
    cond_fb_not_na        <- all(!is.na(log_df$kickoff_fallback))
    cond_refreshed_gte    <- all(log_df$refreshed_at >= log_df$logged_at)

    cond_all <- cond_logged_not_na && cond_refreshed_not_na &&
                cond_ko_not_na && cond_fb_not_na && cond_refreshed_gte

    ok("PAL-5f Dual timestamps (logged_at, refreshed_at) and audit columns (kickoff_time, kickoff_fallback) non-null",
       cond_all,
       sprintf("N=%d rows, all timestamps valid, refreshed >= logged: %s", nrow(log_df), cond_refreshed_gte))

    expect_true(cond_all)
  } else {
    ok("PAL-5f Skipped (fixture not found)", TRUE)
  }
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

  # Pre-game run before kickoff on Sunday Nov 15
  t_pre <- as.POSIXct("2026-11-15 12:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(ARI = TRUE),
    as_of                   = t_pre
  )

  pre_log <- readRDS(test_log_path)
  cond_pre_na <- is.na(pre_log$home_score[1]) && is.na(pre_log$actual_margin[1])

  # Now game finishes: ARI 24, LA 20 (Upset: ARI wins by +4)
  sch_df$home_score[1] <- 24L
  sch_df$away_score[1] <- 20L
  saveRDS(sch_df, test_sch_path)

  # Run logger after game finish
  t_post <- as.POSIXct("2026-11-15 20:00:00", tz = "America/New_York")
  run_prediction_accuracy_logger(
    log_path                = test_log_path,
    schedules_path          = test_sch_path,
    projected_matchups_path = test_pm_path,
    team_ratings_path       = test_tr_path,
    ridge_coefs             = test_coefs,
    qb_lookup               = list(ARI = TRUE),
    as_of                   = t_post
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
    expect_true(TRUE)
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
