# ==============================================================================
# Market-Blend Weight - Empirical Derivation (Phase 1)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/derive_market_blend_weight.R
#
# Precedent: tools/derive_nfl_constants.R / tools/derive_qb_injury_penalty.R (one-off,
# documented derivation scripts that print the final value for config.R). Derives
# MARKET_BLEND_WEIGHT: how much weight the EPA power-rating model's home_win_prob
# should give to devigged historical closing-line market probability when the two are
# blended (blended_prob = w*market_prob + (1-w)*model_prob), via stats::optimize()
# (golden-section search, not a grid search) minimizing walk-forward Brier score.
#
# Real historical closing moneylines only exist in CACHE_SCHEDULES from 2010 onward
# (verified empirically - see tools/backtest_shrinkage_optimizer.R's header), so this
# derivation is restricted to STAKING_SEASONS (2010-CURRENT_SEASON-1), unlike
# RATING_SHRINKAGE_GAMES_K's/QB_INJURY_RATING_PENALTY_PTS's full CALIBRATION_SEASONS
# window - document this window difference in config.R's constant comment, don't
# silently extend it.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_market_blend_weight.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_market_blend_weight.R"

source("team_ratings_engine.R")   # -> compute_power_rating_points()
source("market_odds_engine.R")    # -> american_to_prob()
source("tools/backtest_common.R") # -> build_walkforward_games()

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

STAKING_SEASONS <- 2010L:(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("Market-blend weight derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

cat("Building walk-forward game table (seasons", min(STAKING_SEASONS), "-", max(STAKING_SEASONS), ")...\n")
games <- build_walkforward_games(epa, completed, STAKING_SEASONS, avg_plays_per_game) |>
  filter(!is.na(home_ml), !is.na(away_ml))
cat(sprintf("Built %d walk-forward games with real historical moneylines.\n\n", nrow(games)))

k <- RATING_SHRINKAGE_GAMES_K
home_w <- games$home_gp / (games$home_gp + k)
away_w <- games$away_gp / (games$away_gp + k)
home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior
margin <- (home_rating - away_rating) + NFL_HCA
games$model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- imp_h / (imp_h + imp_a)

brier_for_weight <- function(w) {
  blended <- w * games$market_prob + (1 - w) * games$model_prob
  mean((blended - games$home_win)^2)
}

brier_model_only  <- brier_for_weight(0)
brier_market_only <- brier_for_weight(1)

cat("Optimizing MARKET_BLEND_WEIGHT via stats::optimize() (bounded [0, 1])...\n")
opt <- optimize(brier_for_weight, interval = c(0, 1), tol = 1e-4)

cat(sprintf("  Model only  (w=0): Brier = %.6f\n", brier_model_only))
cat(sprintf("  Market only (w=1): Brier = %.6f\n", brier_market_only))
cat(sprintf("  Optimizer result: w=%.3f -> Brier = %.6f\n", opt$minimum, opt$objective))
cat(sprintf("\nRECOMMENDATION for config.R: MARKET_BLEND_WEIGHT <- %.2f\n", round(opt$minimum, 2)))
cat(sprintf("(derived from %d walk-forward games, seasons %d-%d, real historical closing moneylines)\n",
            nrow(games), min(STAKING_SEASONS), max(STAKING_SEASONS)))

out <- list(
  run_at = Sys.time(),
  n_games = nrow(games),
  brier_model_only = brier_model_only, brier_market_only = brier_market_only,
  weight_optimal = opt$minimum, brier_optimal = opt$objective
)
saveRDS(out, file.path(CACHE_DIR, "market_blend_weight_derivation.rds"))
cat("\nSaved derivation output to cache/market_blend_weight_derivation.rds\n")
