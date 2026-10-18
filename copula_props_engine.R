# ==============================================================================
# copula_props_engine.R
# Phase 5: Multivariate Gaussian Copula Engine for PRA Combination & SGPs
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(mvtnorm) # Multivariate Gaussian distribution
})

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [COPULA] Initializing Joint Multivariate Copula Engine...")

# Inverse CDF of ZINB to transform uniform copula marginals back to discrete stats
qzinb_approx <- function(u, mu, theta, pi_0 = 0.02) {
  # Map uniform [0, 1] into ZINB counts
  u_adj <- (u - pi_0) / (1 - pi_0)
  u_adj <- pmax(0, u_adj)
  qnbinom(u_adj, size = theta, mu = mu)
}

# ------------------------------------------------------------------------------
# Simulate Correlated Joint Player Distributions (100,000 Iterations)
# ------------------------------------------------------------------------------
simulate_joint_player_props <- function(player_name, mu_pts, mu_reb, mu_ast,
                                        line_pra, n_draws = 50000) {
  
  # Empirical correlation matrix between PTS, REB, and AST in primary creators:
  # PTS & AST: weakly positive (+0.18)
  # PTS & REB: weakly positive (+0.12)
  # REB & AST: moderate negative to zero (-0.08) depending on role
  sigma_mat <- matrix(c(
    1.00,  0.12,  0.18,
    0.12,  1.00, -0.08,
    0.18, -0.08,  1.00
  ), nrow = 3, ncol = 3)
  
  # 1. Sample from 3D Multivariate Normal
  mvn_samples <- rmvnorm(n_draws, mean = c(0, 0, 0), sigma = sigma_mat)
  
  # 2. Transform through Normal CDF to obtain uniform marginals in [0, 1]
  u_pts <- pnorm(mvn_samples[, 1])
  u_reb <- pnorm(mvn_samples[, 2])
  u_ast <- pnorm(mvn_samples[, 3])
  
  # 3. Transform through Inverse ZINB Marginals
  sim_pts <- qzinb_approx(u_pts, mu = mu_pts, theta = 12.5, pi_0 = 0.001)
  sim_reb <- qzinb_approx(u_reb, mu = mu_reb, theta = 6.0,  pi_0 = 0.010)
  sim_ast <- qzinb_approx(u_ast, mu = mu_ast, theta = 4.5,  pi_0 = 0.035)
  
  sim_pra <- sim_pts + sim_reb + sim_ast
  
  # Compute Combination PRA Fair Over/Under Probabilities
  p_over_pra  <- mean(sim_pra > line_pra)
  p_under_pra <- 1 - p_over_pra
  
  # Probability of a Triple-Double (PTS >= 10, REB >= 10, AST >= 10)
  p_triple_double <- mean(sim_pts >= 10 & sim_reb >= 10 & sim_ast >= 10)
  
  # Probability of Double-Double
  p_double_double <- mean(
    (sim_pts >= 10 & sim_reb >= 10) |
      (sim_pts >= 10 & sim_ast >= 10) |
      (sim_reb >= 10 & sim_ast >= 10)
  )
  
  # Compare Copula PRA with naive independent convolution (demonstrating copula edge)
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

# Run Marquee Test: Nikola Jokic PRA Combination
run_copula_suite <- function() {
  jokic_pra <- simulate_joint_player_props(
    player_name = "Nikola Jokic",
    mu_pts = 26.4,
    mu_reb = 12.3,
    mu_ast = 9.2,
    line_pra = 47.5
  )
  
  saveRDS(jokic_pra, "cache/copula_jokic_pra.rds")
  message(sprintf(">>> [COPULA] %s PRA Line %.1f | Copula Over Prob: %.1f%% (Fair ML: %+d) | Triple-Double Prob: %.1f%%",
                  jokic_pra$player, jokic_pra$line_pra, jokic_pra$copula_p_over * 100, 
                  jokic_pra$fair_odds_over, jokic_pra$p_triple_double))
  return(jokic_pra)
}

if (!interactive()) {
  invisible(run_copula_suite())
}