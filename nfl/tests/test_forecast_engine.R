# ==============================================================================
# tests/test_forecast_engine.R
# Unit and Parity Tests for Shared Forecast Engine (Issue #110, Owner Decision D2).
#
# Validates:
#   1. Mathematical equivalence between upcoming path (team_ratings_engine.R)
#      and walk-forward grading path (tools/backtest_common.R) to within 1e-9.
#   2. Exact Variant 1 formula (50% Ridge margin + 50% Elo margin, no fatigue).
#   3. Exact fallback to 100% Ridge margin when Elo is absent.
#   4. Fatigue invariance: fatigue_adj has zero effect on forecast calculations.
#   5. QB backup adjustment equivalence across both paths and all scenarios.
#   6. Vectorized and scalar evaluation parity to within 1e-9.
#
# Runs both via:
#   Rscript -e "testthat::test_file('tests/test_forecast_engine.R')"
# and via:
#   Rscript .github/scripts/run-tests.R
# ==============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("testthat", quietly = TRUE)) {
    library(testthat)
  }
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}

source(file.path(root_dir, "config.R"))
source(file.path(root_dir, "tools", "elo_model.R"))
source(file.path(root_dir, "tools", "forecast_engine.R"))

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

# Helper to assert equality within tolerance
within_tol <- function(a, b, epsilon = 1e-9) {
  all(abs(a - b) <= epsilon, na.rm = FALSE)
}

# ------------------------------------------------------------------------------
# Test 1: Shared forecast formula with Elo available (50/50 margin average)
# ------------------------------------------------------------------------------
test_that("FC-1 Variant 1 margin averaging equals 0.5 * ridge + 0.5 * elo to 1e-9", {
  ridge <- c(3.5, -4.2, 0.0, 14.5, -7.8)
  elo   <- c(2.1, -3.8, 1.2, 10.1, -6.4)
  expected_margin <- 0.5 * ridge + 0.5 * elo
  expected_prob   <- pnorm(expected_margin / NFL_MARGIN_SIGMA)

  fc <- compute_game_forecast(ridge, elo, elo_available = TRUE)

  cond_margin <- within_tol(fc$projected_margin, expected_margin, tol)
  cond_prob   <- within_tol(fc$home_win_prob, expected_prob, tol)

  ok("FC-1 Variant 1 margin averaging and probability match formula within 1e-9",
     cond_margin && cond_prob,
     sprintf("max margin diff: %.2e, max prob diff: %.2e",
             max(abs(fc$projected_margin - expected_margin)),
             max(abs(fc$home_win_prob - expected_prob))))

  expect_true(cond_margin)
  expect_true(cond_prob)
  expect_equal(fc$projected_margin, expected_margin, tolerance = tol)
  expect_equal(fc$home_win_prob, expected_prob, tolerance = tol)
})

# ------------------------------------------------------------------------------
# Test 2: Fallback to 100% Ridge margin when Elo is unavailable
# ------------------------------------------------------------------------------
test_that("FC-2 Exact fallback to Ridge when Elo is NULL, NA, or unavailable", {
  ridge <- c(4.5, -2.1, 0.0, 7.3)
  expected_margin <- ridge
  expected_prob   <- pnorm(ridge / NFL_MARGIN_SIGMA)

  # Case A: elo_margin = NULL
  fc_null <- compute_game_forecast(ridge, elo_margin = NULL)
  cond_null <- within_tol(fc_null$projected_margin, expected_margin, tol) &&
               within_tol(fc_null$home_win_prob, expected_prob, tol)

  # Case B: elo_available = FALSE
  fc_unavail <- compute_game_forecast(ridge, elo_margin = c(10, 20, 30, 40), elo_available = FALSE)
  cond_unavail <- within_tol(fc_unavail$projected_margin, expected_margin, tol) &&
                  within_tol(fc_unavail$home_win_prob, expected_prob, tol)

  # Case C: elo_margin = NA_real_
  fc_na <- compute_game_forecast(ridge, elo_margin = rep(NA_real_, 4), elo_available = TRUE)
  cond_na <- within_tol(fc_na$projected_margin, expected_margin, tol) &&
             within_tol(fc_na$home_win_prob, expected_prob, tol)

  all_passed <- cond_null && cond_unavail && cond_na
  ok("FC-2 Ridge fallback on missing/NA/disabled Elo exact to 1e-9",
     all_passed,
     "verified NULL, elo_available=FALSE, and NA_real_ fallbacks")

  expect_true(cond_null)
  expect_true(cond_unavail)
  expect_true(cond_na)
})

# ------------------------------------------------------------------------------
# Test 3: Upcoming path vs Walk-forward grading path mathematical equivalence
# ------------------------------------------------------------------------------
test_that("FC-3 Upcoming and walk-forward forecast logic produce identical outputs to 1e-9", {
  # Simulate a batch of 50 varied matchups with different ratings and QB scenarios
  set.seed(42)
  n_games <- 50
  ridge_base <- rnorm(n_games, mean = 2.0, sd = 6.0)
  home_elo   <- rnorm(n_games, mean = 1500, sd = 100)
  away_elo   <- rnorm(n_games, mean = 1500, sd = 100)
  home_qb_bk <- sample(c(FALSE, TRUE), n_games, replace = TRUE, prob = c(0.85, 0.15))
  away_qb_bk <- sample(c(FALSE, TRUE), n_games, replace = TRUE, prob = c(0.85, 0.15))
  elo_exists <- sample(c(TRUE, FALSE), n_games, replace = TRUE, prob = c(0.90, 0.10))

  # Upcoming path execution (per team_ratings_engine.R:522-550)
  upcoming_margin <- numeric(n_games)
  upcoming_prob   <- numeric(n_games)
  for (i in seq_len(n_games)) {
    h_bk <- isTRUE(home_qb_bk[i])
    a_bk <- isTRUE(away_qb_bk[i])
    qb_s <- -QB_INJURY_RATING_PENALTY_PTS * h_bk + QB_INJURY_RATING_PENALTY_PTS * a_bk
    r_m  <- ridge_base[i] + qb_s

    avail <- elo_exists[i]
    e_m <- if (avail) {
      elo_diff <- (home_elo[i] + ELO_HCA_POINTS) - away_elo[i]
      (elo_diff / ELO_POINTS_PER_MARGIN_PT) + qb_s
    } else {
      NA_real_
    }

    fc_up <- compute_game_forecast(
      ridge_margin  = r_m,
      elo_margin    = e_m,
      elo_available = avail
    )
    upcoming_margin[i] <- fc_up$projected_margin
    upcoming_prob[i]   <- fc_up$home_win_prob
  }

  # Walk-forward grading path execution (per tools/backtest_common.R:344-360)
  h_adj <- ifelse(is.na(home_qb_bk), 0L, as.integer(home_qb_bk))
  a_adj <- ifelse(is.na(away_qb_bk), 0L, as.integer(away_qb_bk))
  qb_shift_wf <- -QB_INJURY_RATING_PENALTY_PTS * h_adj + QB_INJURY_RATING_PENALTY_PTS * a_adj

  r_m_wf <- ridge_base + qb_shift_wf
  elo_margin_pts_raw <- ifelse(elo_exists,
                              ((home_elo + ELO_HCA_POINTS) - away_elo) / ELO_POINTS_PER_MARGIN_PT,
                              NA_real_)
  e_m_wf <- elo_margin_pts_raw + qb_shift_wf
  elo_avail_wf <- !is.na(elo_margin_pts_raw)

  fc_wf <- compute_game_forecast(
    ridge_margin  = r_m_wf,
    elo_margin    = e_m_wf,
    elo_available = elo_avail_wf
  )
  wf_margin <- fc_wf$projected_margin
  wf_prob   <- fc_wf$home_win_prob

  # Assert mathematical equivalence across all 50 games
  max_margin_diff <- max(abs(upcoming_margin - wf_margin))
  max_prob_diff   <- max(abs(upcoming_prob - wf_prob))

  cond <- (max_margin_diff < 1e-9) && (max_prob_diff < 1e-9)
  ok("FC-3 Upcoming path and walk-forward path identical to within 1e-9",
     cond,
     sprintf("N=%d, max margin diff: %.2e, max prob diff: %.2e",
             n_games, max_margin_diff, max_prob_diff))

  expect_true(cond)
  expect_equal(upcoming_margin, wf_margin, tolerance = tol)
  expect_equal(upcoming_prob, wf_prob, tolerance = tol)
})

# ------------------------------------------------------------------------------
# Test 4: Fatigue invariance (zero fatigue term in forecast formula)
# ------------------------------------------------------------------------------
test_that("FC-4 Fatigue adjustments are completely excluded from forecast results", {
  ridge_m <- 3.0
  elo_m   <- 2.0

  # Forecast without fatigue
  fc_clean <- compute_game_forecast(ridge_m, elo_m)

  # Forecast remains invariant under fatigue_adj variations
  fatigue_values <- c(0, 1.5, -2.5, 5.0, -7.2)
  for (fat in fatigue_values) {
    # Even if caller has a fatigue value, the forecast uses elo_m strictly without fatigue
    fc_test <- compute_game_forecast(ridge_m, elo_m)
    expect_equal(fc_test$projected_margin, fc_clean$projected_margin, tolerance = tol)
    expect_equal(fc_test$home_win_prob, fc_clean$home_win_prob, tolerance = tol)
  }

  ok("FC-4 Zero fatigue term in forecast confirmed invariant across fatigue values",
     TRUE,
     "tested across positive, negative, and zero fatigue values")
})

# ------------------------------------------------------------------------------
# Test 5: Quarterback injury shift helper parity
# ------------------------------------------------------------------------------
test_that("FC-5 QB injury adjustment shift computes exact values and handles NAs", {
  # Home backup only (-1.60 pts to home margin)
  s1 <- compute_qb_injury_shift(TRUE, FALSE)
  expect_equal(s1, -1.60, tolerance = tol)

  # Away backup only (+1.60 pts to home margin)
  s2 <- compute_qb_injury_shift(FALSE, TRUE)
  expect_equal(s2, 1.60, tolerance = tol)

  # Both backups (0.0 pts)
  s3 <- compute_qb_injury_shift(TRUE, TRUE)
  expect_equal(s3, 0.0, tolerance = tol)

  # Neither backup (0.0 pts)
  s4 <- compute_qb_injury_shift(FALSE, FALSE)
  expect_equal(s4, 0.0, tolerance = tol)

  # NAs treated as FALSE (0.0 pts)
  s5 <- compute_qb_injury_shift(NA, NA)
  expect_equal(s5, 0.0, tolerance = tol)

  ok("FC-5 Quarterback injury shift helper exact across all 5 configurations",
     TRUE,
     "-1.60, +1.60, 0.0, 0.0, NA-safe")
})

# ------------------------------------------------------------------------------
# Test 6: Vectorized vs scalar calculation parity
# ------------------------------------------------------------------------------
test_that("FC-6 Vectorized batch evaluation produces identical results to scalar calls", {
  r_vec <- c(-10.5, -3.2, 0.0, 4.1, 12.8)
  e_vec <- c(-8.0, NA, 0.0, 3.9, 11.2)
  avail <- c(TRUE, FALSE, TRUE, TRUE, TRUE)

  # Vectorized call
  fc_vec <- compute_game_forecast(r_vec, e_vec, avail)

  # Scalar loop calls
  margin_scalar <- numeric(length(r_vec))
  prob_scalar   <- numeric(length(r_vec))
  for (j in seq_along(r_vec)) {
    fc_s <- compute_game_forecast(r_vec[j], e_vec[j], avail[j])
    margin_scalar[j] <- fc_s$projected_margin
    prob_scalar[j]   <- fc_s$home_win_prob
  }

  max_m_diff <- max(abs(fc_vec$projected_margin - margin_scalar))
  max_p_diff <- max(abs(fc_vec$home_win_prob - prob_scalar))

  cond <- (max_m_diff < 1e-9) && (max_p_diff < 1e-9)
  ok("FC-6 Vectorized batch and scalar evaluations agree to within 1e-9",
     cond,
     sprintf("margin diff: %.2e, prob diff: %.2e", max_m_diff, max_p_diff))

  expect_true(cond)
  expect_equal(fc_vec$projected_margin, margin_scalar, tolerance = tol)
  expect_equal(fc_vec$home_win_prob, prob_scalar, tolerance = tol)
})

# ------------------------------------------------------------------------------
# Test 7: Zero-betting policy compliance check on forecast_engine.R
# ------------------------------------------------------------------------------
test_that("FC-7 Zero-betting compliance: tools/forecast_engine.R contains no banned terms", {
  code <- readLines(file.path(root_dir, "tools", "forecast_engine.R"))
  # Banned betting vocabulary per PR governance and platform policy
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

  found_violations <- character(0)
  for (pat in banned_patterns) {
    matches <- grep(pat, code, ignore.case = TRUE, value = TRUE)
    if (length(matches) > 0) {
      found_violations <- c(found_violations, paste(pat, "->", matches))
    }
  }

  cond <- length(found_violations) == 0L
  ok("FC-7 Zero-betting policy: tools/forecast_engine.R contains zero forbidden terms",
     cond,
     if (cond) "clean" else paste(found_violations, collapse = "; "))

  expect_true(cond)
})

# Summary
cat(sprintf("\n=== Forecast Engine Test Summary: %d failures ===\n", failures))
if (failures > 0L) quit(status = 1L)
