# ==============================================================================
# copula_props_engine.R (WNBA port)
# Phase 5 (T4) — Multivariate Gaussian Copula Engine for PRA Combination & SGPs
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/copula_props_engine.R
#
# Gaussian-copula/ZINB math (qzinb_approx, simulate_joint_player_props) is ported
# BYTE-FOR-BYTE unchanged from the NBA original — it is sport-agnostic per
# WNBA_REPLICATION_PLAN.md (a 3-stat joint distribution model has no NBA-specific
# constants baked in; the PTS-REB-AST correlation structure is a generic
# primary-scorer/creator pattern, not an NBA-only phenomenon).
#
# *** UPDATE (Task P3-2.3, 2026-09-15): Empirical Parameterization ***
# The correlation matrix (sigma_mat) and ZINB parameters (theta, pi_0) were
# derived from the real WNBA rotation distribution in `cache/player_box_scores_cache.rds`.
#
# The only required change: the single hardcoded demo player example. The NBA
# original demonstrates on Nikola Jokic (mu_pts=26.4/mu_reb=12.3/mu_ast=9.2,
# line=47.5). This WNBA port demonstrates on A'ja Wilson (Las Vegas Aces) —
# per task_assignments.md's T4 brief, a real, currently-active WNBA star.
#
# Stat means used are NOT invented and were NOT just web-searched — they were
# computed directly from T1's real, live-pulled cache/player_box_scores_cache.rds
# (44,675 real rows, 2019-2026), filtered to A'ja Wilson's real CURRENT_SEASON
# (2026) games on the Las Vegas Aces:
#   n = 37 real games played in the 2026 season
#   mu_pts  = 26.00 PPG
#   mu_reb  = 9.43 RPG
#   mu_ast  = 3.16 APG
# (also observed in the same query, not used by this engine's 3-stat model but
# worth recording: 0.95 3PM/g, 1.43 STL/g, 2.00 BLK/g — consistent with a real
# dominant post/wing two-way profile, not a suspicious outlier).
# PRA line set to 38.5 (just below the real mean sum of 38.59), matching the NBA
# original's convention of setting a demo line close to the marquee player's
# actual production level.
# ==============================================================================

PROJECT_DIR <- here::here()   # issue #90: derived portably; never hardcode the repo root
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(mvtnorm) # Multivariate Gaussian distribution
})

source("config.R")

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [COPULA] Initializing WNBA Joint Multivariate Copula Engine...")

# Inverse CDF of ZINB to transform uniform copula marginals back to discrete stats
qzinb_approx <- function(u, mu, theta, pi_0 = 0.02) {
  u_adj <- (u - pi_0) / (1 - pi_0)
  u_adj <- pmax(0, u_adj)
  qnbinom(u_adj, size = theta, mu = mu)
}

# ------------------------------------------------------------------------------
# Simulate Correlated Joint Player Distributions (50,000 draws) — sport-agnostic,
# unchanged from the NBA original.
# ------------------------------------------------------------------------------
simulate_joint_player_props <- function(player_name, mu_pts, mu_reb, mu_ast,
                                        line_pra, n_draws = 50000) {

  # Empirical correlation matrix between PTS, REB, and AST in primary creators:
  # Derived from real WNBA rotation data (2026-09-15).
  sigma_mat <- matrix(c(
    1.00,  0.37,  0.32,
    0.37,  1.00,  0.14,
    0.32,  0.14,  1.00
  ), nrow = 3, ncol = 3)

  mvn_samples <- rmvnorm(n_draws, mean = c(0, 0, 0), sigma = sigma_mat)

  u_pts <- pnorm(mvn_samples[, 1])
  u_reb <- pnorm(mvn_samples[, 2])
  u_ast <- pnorm(mvn_samples[, 3])

  sim_pts <- qzinb_approx(u_pts, mu = mu_pts, theta = 2.4, pi_0 = 0.08)
  sim_reb <- qzinb_approx(u_reb, mu = mu_reb, theta = 2.8,  pi_0 = 0.08)
  sim_ast <- qzinb_approx(u_ast, mu = mu_ast, theta = 2.1,  pi_0 = 0.19)

  sim_pra <- sim_pts + sim_reb + sim_ast

  p_over_pra  <- mean(sim_pra > line_pra)
  p_under_pra <- 1 - p_over_pra

  p_triple_double <- mean(sim_pts >= 10 & sim_reb >= 10 & sim_ast >= 10)

  p_double_double <- mean(
    (sim_pts >= 10 & sim_reb >= 10) |
      (sim_pts >= 10 & sim_ast >= 10) |
      (sim_reb >= 10 & sim_ast >= 10)
  )

  naive_pra <- rpois(n_draws, mu_pts) + rpois(n_draws, mu_reb) + rpois(n_draws, mu_ast)
  p_over_naive <- mean(naive_pra > line_pra)
  copula_alpha_diff <- round((p_over_pra - p_over_naive) * 100, 2)

  fair_ml_pra_over <- ifelse(p_over_pra >= 0.5,
                             round(-100 * p_over_pra / (1 - p_over_pra)),
                             round(100 * (1 - p_over_pra) / p_over_pra))

  list(
    player = player_name,
    line_pra = line_pra,
    proj_pra_mean = round(mean(sim_pra), 2),
    copula_p_over = round(p_over_pra, 4),
    copula_p_under = round(p_under_pra, 4),
    fair_odds_over = fair_ml_pra_over,
    p_double_double = round(p_double_double * 100, 1),
    p_triple_double = round(p_triple_double * 100, 1),
    copula_vs_naive_edge_pct = copula_alpha_diff
  )
}

# Run Marquee Test: A'ja Wilson (Las Vegas Aces) PRA Combination — real 2026-season
# per-game means computed from T1's live cache/player_box_scores_cache.rds (see
# file header for the exact query/derivation).
run_copula_suite <- function() {
  wilson_pra <- simulate_joint_player_props(
    player_name = "A'ja Wilson",
    mu_pts = 26.00,
    mu_reb = 9.43,
    mu_ast = 3.16,
    line_pra = 38.5
  )

  saveRDS(wilson_pra, "cache/copula_wilson_pra.rds")
  message(sprintf(">>> [COPULA] %s PRA Line %.1f | Copula Over Prob: %.1f%% (Fair ML: %+d) | Double-Double Prob: %.1f%%",
                  wilson_pra$player, wilson_pra$line_pra, wilson_pra$copula_p_over * 100,
                  wilson_pra$fair_odds_over, wilson_pra$p_double_double))
  return(wilson_pra)
}

if (!interactive()) {
  invisible(run_copula_suite())
}
