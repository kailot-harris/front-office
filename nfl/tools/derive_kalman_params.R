# ==============================================================================
# Kalman State-Space Model Hyperparameters - Empirical Derivation (Phase 5)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/derive_kalman_params.R
#
# Precedent: tools/derive_elo_k.R (single-parameter stats::optimize()), generalized to
# stats::optim() (method = "L-BFGS-B", box-constrained, not a grid search) for
# tools/kalman_state_space_model.R's four hyperparameters jointly: KALMAN_INITIAL_VARIANCE,
# KALMAN_PROCESS_VARIANCE, KALMAN_OBSERVATION_VARIANCE, KALMAN_SEASON_CARRYOVER. Minimizes
# walk-forward Brier score, same scoring convention as derive_elo_k.R (2002/MODERN_ERA_START_
# SEASON is the burn-in season, not scored; SCORE_SEASONS = 2003:(CURRENT_SEASON-1)).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_kalman_params.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_kalman_params.R"

if (!file.exists(CACHE_SCHEDULES)) stop("CACHE_SCHEDULES missing - run the ingest stage first.")

sch <- readRDS(CACHE_SCHEDULES) |> mutate(gameday = as.Date(gameday))
sch_completed <- sch |>
  filter(!is.na(home_score), !is.na(away_score),
         season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)

SCORE_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)

cat("==============================================================\n")
cat("Kalman state-space hyperparameter derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")
cat(sprintf("Simulating Kalman filter sequentially across %d games (seasons %d-%d, %d burn-in)...\n",
            nrow(sch_completed), MODERN_ERA_START_SEASON, CURRENT_SEASON - 1L, MODERN_ERA_START_SEASON))

# ------------------------------------------------------------------------------------------
# brier_for_params(): assigns the four KALMAN_* constants into the GLOBAL environment (matching
# derive_elo_k.R's pattern of relying on tools/elo_model.R reading its K argument as a function
# parameter - here the model file reads these as free global constants instead of function
# args, since there are four of them and the model's own file header documents them as
# config.R-level constants, not run_kalman_walkforward() arguments) before each simulation, then
# sources tools/kalman_state_space_model.R fresh isn't needed (function bodies read the globals
# at CALL time, not at define time) - source once outside the objective function for speed.
# ------------------------------------------------------------------------------------------
source("tools/kalman_state_space_model.R")

brier_for_params <- function(par) {
  # par[[i]] (not par[i]) - par is a NAMED numeric vector; par[i] would keep that name
  # attribute, and c(mu = 0, var = <a named scalar>) then mangles the "var" name into
  # "var.KALMAN_..." (R's c() name-combining behavior when the inner value is itself named) -
  # confirmed live (subscript-out-of-bounds on st_h[["var"]] before this fix).
  KALMAN_INITIAL_VARIANCE     <<- par[[1]]
  KALMAN_PROCESS_VARIANCE     <<- par[[2]]
  KALMAN_OBSERVATION_VARIANCE <<- par[[3]]
  KALMAN_SEASON_CARRYOVER     <<- par[[4]]

  res <- run_kalman_walkforward(sch_completed)
  scored <- res |> filter(season %in% SCORE_SEASONS)
  mean((scored$home_win_prob - scored$home_win)^2)
}

# Starting values: KALMAN_INITIAL_VARIANCE ~ a brand-new team's uncertainty should be comparable
# in scale to NFL_MARGIN_SIGMA^2 (the league's total unconditional margin variance) since a
# rookie state has essentially zero rating information; KALMAN_OBSERVATION_VARIANCE similarly
# starts near NFL_MARGIN_SIGMA^2 - NFL_HCA^2-ish (residual randomness after a real rating exists
# should be smaller than total unconditional variance, but not by an assumed amount - the
# optimizer is free to move it anywhere in its bounds); KALMAN_PROCESS_VARIANCE starts small
# (games are much more frequent than the timescale team strength meaningfully drifts at);
# KALMAN_SEASON_CARRYOVER starts at ELO_SEASON_CARRYOVER's literature value (2/3) as a
# reasonable prior, not because Elo's own re-derivation transfers directly.
start_par <- c(
  KALMAN_INITIAL_VARIANCE     = NFL_MARGIN_SIGMA^2,
  KALMAN_PROCESS_VARIANCE     = 5,
  KALMAN_OBSERVATION_VARIANCE = NFL_MARGIN_SIGMA^2 * 0.7,
  KALMAN_SEASON_CARRYOVER     = 2/3
)

cat("Optimizing via stats::optim(method = \"L-BFGS-B\")...\n")
cat("Starting parameters:\n"); print(start_par)

opt <- optim(
  par = start_par, fn = brier_for_params, method = "L-BFGS-B",
  lower = c(10, 0.01, 10, 0.01), upper = c(400, 100, 400, 0.99),
  control = list(factr = 1e9, maxit = 40)
)
gc()

cat("\nOptimizer result:\n")
print(opt$par)
cat(sprintf("Brier at optimum: %.6f\n", opt$value))

baseline_brier <- brier_for_params(start_par)
cat(sprintf("(Brier at literature-informed starting values, for comparison: %.6f)\n", baseline_brier))

cat("\n==============================================================\n")
cat("Paste these into config.R's Kalman State-Space section:\n")
cat("==============================================================\n")
cat(sprintf("KALMAN_INITIAL_VARIANCE     <- %.4f\n", opt$par[["KALMAN_INITIAL_VARIANCE"]]))
cat(sprintf("KALMAN_PROCESS_VARIANCE     <- %.4f\n", opt$par[["KALMAN_PROCESS_VARIANCE"]]))
cat(sprintf("KALMAN_OBSERVATION_VARIANCE <- %.4f\n", opt$par[["KALMAN_OBSERVATION_VARIANCE"]]))
cat(sprintf("KALMAN_SEASON_CARRYOVER     <- %.4f\n", opt$par[["KALMAN_SEASON_CARRYOVER"]]))
