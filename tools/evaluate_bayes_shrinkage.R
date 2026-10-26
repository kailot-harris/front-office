# ==============================================================================
# tools/evaluate_bayes_shrinkage.R — Verification & Evaluation of Bayes Shrinkage
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/tools/evaluate_bayes_shrinkage.R
#
# Issue #25 Verification Suite:
# Evaluates closed-form hierarchical empirical Bayes partial pooling,
# verifying that shrinkage is strictly monotonic with sample size and
# smaller sample sizes shrink more aggressively toward league average.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "evaluate_bayes_shrinkage.R"

#' Test Shrinkage Monotonicity
#'
#' Formally verifies Success Criterion 2:
#' Mathematical shrinkage is monotonic with sample size: smaller sample sizes
#' shrink more aggressively toward league average.
#'
#' @return Logical TRUE if all monotonicity assertions pass, halts with stop() otherwise
test_shrinkage_monotonicity <- function() {
  cat("==================================================================\n")
  cat(">>> EVALUATING BAYES SHRINKAGE MONOTONICITY (ISSUE #25)\n")
  cat("==================================================================\n\n")
  
  # ----------------------------------------------------------------------------
  # Test 1: Theoretical Formula Monotonicity (Closed-Form James-Stein / Normal-Normal)
  # Formula: B(n) = sigma_0^2 / (sigma_0^2 + sigma^2 / n)
  # Shrinkage(n) = 1 - B(n) = (sigma^2 / n) / (sigma_0^2 + sigma^2 / n)
  # ----------------------------------------------------------------------------
  cat("[TEST 1] Verifying Normal-Normal theoretical monotonicity...\n")
  
  sample_sizes <- c(10, 25, 50, 100, 200, 350, 500, 700)
  sigma0_sq    <- 0.00045   # True talent variance (between-player wOBA)
  sigma_sq     <- 0.38000   # Within-player sampling variance per PA
  mu_0         <- 0.31200   # League prior mean
  y_obs        <- 0.45000   # Extreme observed talent (e.g. Aaron Judge tier)
  
  # Compute B and shrinkage
  B_n        <- sigma0_sq / (sigma0_sq + sigma_sq / sample_sizes)
  shrink_n   <- 1.0 - B_n
  theta_hat  <- B_n * y_obs + (1.0 - B_n) * mu_0
  dist_to_mu <- abs(theta_hat - mu_0)
  
  # 1. B must be strictly increasing with sample size
  diff_B <- diff(B_n)
  if (!all(diff_B > 0)) {
    stop("FAILED: Shrinkage factor B is NOT strictly monotonically increasing with sample size!")
  }
  
  # 2. Shrinkage toward prior must be strictly decreasing with sample size
  diff_shrink <- diff(shrink_n)
  if (!all(diff_shrink < 0)) {
    stop("FAILED: Shrinkage toward prior mean is NOT strictly monotonically decreasing with sample size!")
  }
  
  # 3. Shrunk estimate distance from prior mean must grow monotonically toward observed value
  diff_dist <- diff(dist_to_mu)
  if (!all(diff_dist > 0)) {
    stop("FAILED: Distance to league mean does NOT increase monotonically with sample size!")
  }
  
  cat("  -> Normal-Normal closed-form formulas satisfy strict monotonicity (diff(B) > 0, diff(shrink) < 0).\n")
  for (j in seq_along(sample_sizes)) {
    cat(sprintf("     n=%3d | B=%.4f | Shrinkage=%.4f (%.1f%%) | Shrunk Val=%.4f\n",
                sample_sizes[j], B_n[j], shrink_n[j], shrink_n[j] * 100, theta_hat[j]))
  }
  cat("  [PASS] Test 1: Theoretical Normal-Normal Monotonicity passed.\n\n")

  # ----------------------------------------------------------------------------
  # Test 2: Theoretical Beta-Binomial Monotonicity
  # Formula: B(n) = n / (n + M_0), Shrinkage(n) = M_0 / (n + M_0)
  # ----------------------------------------------------------------------------
  cat("[TEST 2] Verifying Beta-Binomial theoretical monotonicity...\n")
  M_0          <- 45.0  # Prior effective sample size
  p_mu0        <- 0.225 # League mean rate (K%)
  p_obs        <- 0.350 # High strikeout rate
  
  B_beta       <- sample_sizes / (sample_sizes + M_0)
  shrink_beta  <- M_0 / (sample_sizes + M_0)
  p_hat        <- B_beta * p_obs + (1.0 - B_beta) * p_mu0
  
  if (!all(diff(B_beta) > 0)) {
    stop("FAILED: Beta-Binomial B is NOT strictly monotonically increasing with sample size!")
  }
  if (!all(diff(shrink_beta) < 0)) {
    stop("FAILED: Beta-Binomial shrinkage is NOT strictly monotonically decreasing with sample size!")
  }
  
  cat("  -> Beta-Binomial closed-form formulas satisfy strict monotonicity.\n")
  for (j in seq_along(sample_sizes)) {
    cat(sprintf("     n=%3d | B=%.4f | Shrinkage=%.4f (%.1f%%) | Shrunk Rate=%.4f\n",
                sample_sizes[j], B_beta[j], shrink_beta[j], shrink_beta[j] * 100, p_hat[j]))
  }
  cat("  [PASS] Test 2: Theoretical Beta-Binomial Monotonicity passed.\n\n")

  # ----------------------------------------------------------------------------
  # Test 3: Empirical Monotonicity on Cached Batters (bayes_pooled_batters.rds)
  # ----------------------------------------------------------------------------
  cat("[TEST 3] Verifying empirical monotonicity on bayes_pooled_batters.rds...\n")
  cache_bat_file <- cache_path("specialty", "bayes_pooled_batters.rds", create = FALSE)
  if (!file.exists(cache_bat_file)) {
    cat("  -> Cache missing. Running mlb_bayes_pooling.R to generate it...\n")
    source("mlb_bayes_pooling.R")
    run_bayes_pooling(seasons = 2024, force_refresh = TRUE)
  }
  
  b <- as.data.frame(readRDS(cache_bat_file))
  b <- b[!is.na(b$PA) & b$PA > 0, ]
  b_sorted <- b[order(b$PA), ]
  
  # Check sorted monotonicity for B_wOBA, B_ISO, B_K_pct, B_BB_pct
  if (is.unsorted(b_sorted$B_wOBA)) {
    stop("FAILED: b_sorted$B_wOBA is NOT monotonically non-decreasing with PA!")
  }
  if (is.unsorted(b_sorted$B_ISO)) {
    stop("FAILED: b_sorted$B_ISO is NOT monotonically non-decreasing with PA!")
  }
  if (is.unsorted(b_sorted$B_K_pct)) {
    stop("FAILED: b_sorted$B_K_pct is NOT monotonically non-decreasing with PA!")
  }
  if (is.unsorted(b_sorted$B_BB_pct)) {
    stop("FAILED: b_sorted$B_BB_pct is NOT monotonically non-decreasing with PA!")
  }
  
  # Check binned shrinkage behavior across sample sizes
  b_bins <- b %>%
    dplyr::mutate(pa_group = cut(PA, breaks = c(0, 100, 300, 500, Inf),
                                 labels = c("<100 PA", "100-299 PA", "300-499 PA", "500+ PA"))) %>%
    dplyr::group_by(pa_group) %>%
    dplyr::summarize(
      n_players   = dplyr::n(),
      mean_pa     = round(mean(PA), 1),
      mean_B_woba = round(mean(B_wOBA), 4),
      mean_shrink = round(mean(shrink_wOBA), 4),
      .groups     = "drop"
    )
  
  cat("  -> Batter wOBA Shrinkage by Sample Size Tier:\n")
  print(as.data.frame(b_bins))
  
  # Verify that mean shrinkage strictly decreases as PA tiers increase
  shrink_tiers <- b_bins$mean_shrink
  if (!all(diff(shrink_tiers) < 0)) {
    stop("FAILED: Mean batter shrinkage does NOT strictly decrease across sample size tiers!")
  }
  cat("  [PASS] Test 3: Empirical Batter Shrinkage Monotonicity passed.\n\n")

  # ----------------------------------------------------------------------------
  # Test 4: Empirical Monotonicity on Cached Pitchers (bayes_pooled_pitchers.rds)
  # ----------------------------------------------------------------------------
  cat("[TEST 4] Verifying empirical monotonicity on bayes_pooled_pitchers.rds...\n")
  cache_pitch_file <- cache_path("specialty", "bayes_pooled_pitchers.rds", create = FALSE)
  p <- as.data.frame(readRDS(cache_pitch_file))
  p <- p[!is.na(p$TBF) & p$TBF > 0, ]
  p_sorted <- p[order(p$TBF), ]
  
  if (is.unsorted(p_sorted$B_xFIP)) {
    stop("FAILED: p_sorted$B_xFIP is NOT monotonically non-decreasing with TBF!")
  }
  if (is.unsorted(p_sorted$B_K_pct)) {
    stop("FAILED: p_sorted$B_K_pct is NOT monotonically non-decreasing with TBF!")
  }
  if (is.unsorted(p_sorted$B_BB_pct)) {
    stop("FAILED: p_sorted$B_BB_pct is NOT monotonically non-decreasing with TBF!")
  }
  
  p_bins <- p %>%
    dplyr::mutate(tbf_group = cut(TBF, breaks = c(0, 100, 300, 500, Inf),
                                  labels = c("<100 TBF", "100-299 TBF", "300-499 TBF", "500+ TBF"))) %>%
    dplyr::group_by(tbf_group) %>%
    dplyr::summarize(
      n_players   = dplyr::n(),
      mean_tbf    = round(mean(TBF), 1),
      mean_B_xfip = round(mean(B_xFIP), 4),
      mean_shrink = round(mean(shrink_xFIP), 4),
      .groups     = "drop"
    )
  
  cat("  -> Pitcher xFIP Shrinkage by Sample Size Tier:\n")
  print(as.data.frame(p_bins))
  
  shrink_tiers_p <- p_bins$mean_shrink
  if (!all(diff(shrink_tiers_p) < 0)) {
    stop("FAILED: Mean pitcher shrinkage does NOT strictly decrease across sample size tiers!")
  }
  cat("  [PASS] Test 4: Empirical Pitcher Shrinkage Monotonicity passed.\n\n")

  # ----------------------------------------------------------------------------
  # Test 5: Verify Cache Files and Structure (Success Criterion 3)
  # ----------------------------------------------------------------------------
  cat("[TEST 5] Verifying output cache existence and required columns...\n")
  cache_bat <- cache_path("specialty", "bayes_pooled_batters.rds", create = FALSE)
  cache_pit <- cache_path("specialty", "bayes_pooled_pitchers.rds", create = FALSE)
  cache_tea <- cache_path("specialty", "bayes_team_talent.rds", create = FALSE)
  
  stopifnot(file.exists(cache_bat))
  stopifnot(file.exists(cache_pit))
  stopifnot(file.exists(cache_tea))
  
  bat_cols <- c("playerid", "PlayerName", "team_name", "PA", "wOBA_pooled", "ISO_pooled", "K_pct_pooled", "BB_pct_pooled", "park_factor")
  pit_cols <- c("playerid", "PlayerName", "team_name", "TBF", "xFIP_pooled", "K_pct_pooled", "BB_pct_pooled", "park_factor")
  tea_cols <- c("team_name", "team_wOBA_pooled", "team_xFIP_pooled", "net_talent_score", "talent_rank")
  
  stopifnot(all(bat_cols %in% names(b)))
  stopifnot(all(pit_cols %in% names(p)))
  stopifnot(all(tea_cols %in% names(readRDS(cache_tea))))
  
  cat(sprintf("  -> Batter cache validated: %d rows, all required columns present.\n", nrow(b)))
  cat(sprintf("  -> Pitcher cache validated: %d rows, all required columns present.\n", nrow(p)))
  cat(sprintf("  -> Team talent cache validated: %d franchises, all required columns present.\n", nrow(readRDS(cache_tea))))
  cat("  [PASS] Test 5: Cache validation passed.\n\n")

  cat("==================================================================\n")
  cat(">>> ALL BAYES SHRINKAGE MONOTONICITY & VERIFICATION TESTS PASSED!\n")
  cat("==================================================================\n")
  
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  test_shrinkage_monotonicity()
}
