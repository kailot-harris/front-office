# ==============================================================================
# Verification: is the home-backup-QB market bias a real, walk-forward-exploitable edge?
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/verify_qb_backup_market_bias.R
#
# tools/market_disagreement_features.R's exploratory diagnostic found one bucket, among ~8
# scanned, whose 95% CI clearly excludes zero: games where the HOME team started a backup QB
# and the away team did not (n=430) showed mean market_residual = -0.0615 (95% CI
# [-0.1055, -0.0175]) - the home team underperformed the market's own price by ~6 points of
# win probability on average. Mechanistically plausible root cause: QB_INJURY_RATING_PENALTY_
# PTS (tools/derive_qb_injury_penalty.R) was derived as a SINGLE value applied symmetrically to
# home and away backup starts, optimized against Brier, never checked for a home/away asymmetry
# or against Sharpe - exactly the class of thing this project exists to catch.
#
# A descriptive in-sample residual is not yet a validated edge (same lesson as
# investigate_participation_sharpe.R). This script asks the real question: using ONLY prior-
# season data to estimate the bias (genuine walk-forward, no lookahead), would betting the away
# team whenever the home team alone starts a backup QB have been profitable?
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/verify_qb_backup_market_bias.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/verify_qb_backup_market_bias.R"
source("market_odds_engine.R")  # -> american_to_decimal(), calculate_kelly()

cached <- readRDS(file.path(CACHE_DIR, "market_disagreement_features.rds"))
games <- cached$games |> filter(qb_situation == "home_backup_only") |> arrange(season, week)
cat(sprintf("home_backup_only games: %d (seasons %d-%d)\n", nrow(games), min(games$season), max(games$season)))

# ------------------------------------------------------------------------------------------
# Walk-forward bias estimate: for each season s, the mean market_residual among
# home_backup_only games STRICTLY BEFORE season s (pooled across all prior seasons - the
# subgroup is too thin for a per-season estimate). Requires >= 20 prior games, else that
# season is skipped (not enough history yet for a stable estimate).
# ------------------------------------------------------------------------------------------
MIN_PRIOR_GAMES <- 20
seasons <- sort(unique(games$season))
bet_rows <- list()

for (s in seasons) {
  prior <- games |> filter(season < s)
  if (nrow(prior) < MIN_PRIOR_GAMES) next
  bias <- mean(prior$market_residual)  # negative = home overpriced by the market

  cur <- games |> filter(season == s)
  for (i in seq_len(nrow(cur))) {
    g <- cur[i, ]
    adj_home_prob <- min(max(g$market_prob + bias, 1e-4), 1 - 1e-4)
    adj_away_prob <- 1 - adj_home_prob
    away_dec <- american_to_decimal(g$away_ml)
    away_ev <- adj_away_prob * away_dec - 1
    if (away_ev <= 0) next  # walk-forward bias didn't imply a positive-EV bet this game
    kelly_pct <- calculate_kelly(adj_away_prob, away_dec, fraction = 0.25, max_cap_pct = 3.0)
    if (kelly_pct <= 0) next
    won <- g$home_win == 0L
    bet_return_pct <- if (won) kelly_pct / 100 * (away_dec - 1) else -kelly_pct / 100
    bet_rows[[length(bet_rows) + 1]] <- data.frame(
      season = s, week = g$week, game_id = g$game_id, home_team = g$home_team, away_team = g$away_team,
      prior_bias_used = bias, market_prob = g$market_prob, adj_away_prob = adj_away_prob,
      away_dec = away_dec, kelly_pct = kelly_pct, won = won, bet_return_pct = bet_return_pct
    )
  }
}

bets <- bind_rows(bet_rows)
cat(sprintf("\nWalk-forward-eligible bets (bias estimated from >= %d prior-season home_backup_only games, positive EV, positive Kelly): %d\n",
            MIN_PRIOR_GAMES, nrow(bets)))

if (nrow(bets) < 5) {
  cat("Too few bets to evaluate meaningfully - stopping here.\n")
  quit(save = "no")
}

sharpe <- mean(bets$bet_return_pct) / sd(bets$bet_return_pct)
cat(sprintf("\nObserved: n=%d, win rate=%.1f%%, Sharpe=%.4f, cumulative return=%.2f%%\n",
            nrow(bets), 100 * mean(bets$won), sharpe, sum(bets$bet_return_pct) * 100))

cat("\nPer-season breakdown (robustness check - is this concentrated in one season?):\n")
print(bets |> group_by(season) |> summarise(n = dplyr::n(), win_rate = mean(won), cum_ret_pct = sum(bet_return_pct) * 100, .groups = "drop"))

cat("\nBootstrap 95% CI on Sharpe (10,000 resamples)...\n")
set.seed(20260917)
boot_sharpes <- vapply(seq_len(10000), function(i) {
  s <- sample(bets$bet_return_pct, size = nrow(bets), replace = TRUE)
  if (sd(s) == 0) return(NA_real_)
  mean(s) / sd(s)
}, numeric(1))
boot_sharpes <- boot_sharpes[!is.na(boot_sharpes)]
ci <- quantile(boot_sharpes, c(0.025, 0.5, 0.975))
cat(sprintf("Bootstrap 95%% CI: [%.4f, %.4f], median %.4f\n", ci[1], ci[3], ci[2]))
cat(sprintf("Fraction of resamples with Sharpe > 0: %.1f%%\n", mean(boot_sharpes > 0) * 100))

saveRDS(list(run_at = Sys.time(), bets = bets, observed_sharpe = sharpe, bootstrap_ci = ci, boot_sharpes = boot_sharpes),
        file.path(CACHE_DIR, "qb_backup_market_bias_verification.rds"))
cat("\nSaved to cache/qb_backup_market_bias_verification.rds\n")
