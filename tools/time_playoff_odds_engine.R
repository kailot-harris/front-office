# ==============================================================================
# One-off timing/stability harness for GitHub issue #16 ("Playoff Odds 6: Time
# and tune N_SEASON_SIMULATIONS against real data").
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/time_playoff_odds_engine.R
#
# NOT part of run_full_pipeline.R's DAG (per tools/ convention in CLAUDE.md) and not
# required to be kept as a permanent script per issue #16's own "Testable independently"
# section - kept here as a verifiable reference for how the config.R N_SEASON_SIMULATIONS
# comment's timing table / stability numbers were produced, re-runnable if a future agent
# wants to re-verify after a machine change or a change to .simulate_one_season()'s cost.
#
# What this does:
#   1. Directly times a small number of .simulate_one_season() trials (the same function
#      run_playoff_odds_engine() loops N_SEASON_SIMULATIONS times) to get a real per-trial
#      wall-clock cost on THIS machine, against the REAL CACHE_SCHEDULES/CACHE_TEAM_RATINGS
#      snapshot already in cache/ - not a synthetic benchmark.
#   2. Extrapolates that per-trial cost linearly to larger candidate trial counts (200, 500,
#      1000, 2000) - valid because each .simulate_one_season() call is a fresh, independent
#      computation with no shared state/memoization across trials (confirmed by reading the
#      function: it re-reads both caches from disk every call and has no global accumulator).
#   3. Runs the REAL run_playoff_odds_engine() end-to-end twice at a chosen trial count and
#      diffs the resulting playoff_prob column for stability.
#
# setwd() to the absolute project root first, per tools/ convention, so source() calls work
# regardless of invocation directory.
# ==============================================================================

setwd("c:/Users/kailo/kayceeslices/front-office/nfl analytics/.claude/worktrees/agent-a29965b4a3135a707")
source("config.R")
source("playoff_odds_engine.R")

cat("=== Step 1: direct per-trial timing (small N, real .simulate_one_season() calls) ===\n")

time_n_trials <- function(n) {
  t0 <- Sys.time()
  for (i in seq_len(n)) {
    f <- .simulate_one_season()
    if (is.null(f)) stop("`.simulate_one_season()` returned NULL - required cache missing.")
  }
  as.numeric(difftime(Sys.time(), t0, units = "secs"))
}

set.seed(16001)
small_n <- 30
small_secs <- time_n_trials(small_n)
per_trial <- small_secs / small_n
cat(sprintf("Measured: %d trials took %.2f sec (%.4f sec/trial)\n", small_n, small_secs, per_trial))

# Second small-N measurement at a different N, to sanity-check the per-trial cost is roughly
# constant (not a fluke of one run) before trusting the linear extrapolation.
set.seed(16002)
small_n2 <- 50
small_secs2 <- time_n_trials(small_n2)
per_trial2 <- small_secs2 / small_n2
cat(sprintf("Measured: %d trials took %.2f sec (%.4f sec/trial)\n", small_n2, small_secs2, per_trial2))

candidates <- c(200, 500, 1000, 2000)
avg_per_trial <- mean(c(per_trial, per_trial2))
cat(sprintf("\nAverage measured per-trial cost: %.4f sec/trial\n", avg_per_trial))
cat("Linear extrapolation to candidate N_SEASON_SIMULATIONS values:\n")
for (n in candidates) {
  cat(sprintf("  n=%d -> extrapolated %.1f sec (%.2f min)\n", n, avg_per_trial * n, avg_per_trial * n / 60))
}

cat("\n=== Step 2: real end-to-end run_playoff_odds_engine() runs for stability check ===\n")

run_and_capture <- function(label) {
  t0 <- Sys.time()
  ok <- run_playoff_odds_engine()
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (!isTRUE(ok)) stop("run_playoff_odds_engine() returned FALSE")
  res <- readRDS(CACHE_PLAYOFF_ODDS)
  cat(sprintf("[%s] run_playoff_odds_engine() at N_SEASON_SIMULATIONS=%d took %.2f sec\n",
              label, N_SEASON_SIMULATIONS, secs))
  res$field
}

run_a <- run_and_capture("run A")
run_b <- run_and_capture("run B")

merged <- merge(run_a[, c("team", "playoff_prob")], run_b[, c("team", "playoff_prob")],
                 by = "team", suffixes = c("_A", "_B"))
merged$abs_diff <- abs(merged$playoff_prob_A - merged$playoff_prob_B)
merged <- merged[order(-merged$abs_diff), ]

cat("\nPer-team playoff_prob, run A vs run B (sorted by abs diff, largest first):\n")
print(merged, row.names = FALSE)

cat(sprintf("\nMax abs diff across all 32 teams: %.4f\n", max(merged$abs_diff)))
cat(sprintf("Mean abs diff across all 32 teams: %.4f\n", mean(merged$abs_diff)))
