# ==============================================================================
# Train/Test Derivation of MIN_SAMPLE_GAMES_FOR_STAKE via Calibration Responsiveness
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/derive_min_sample_games_for_stake.R
#
# Answers a DIFFERENT question than tools/backtest_shrinkage_optimizer.R's existing
# MIN_SAMPLE_GAMES_FOR_STAKE derivation (config.R:228-261, tau=9, 2026-09-17). That
# earlier effort optimized STAKING SHARPE in-sample over the full 2010-2025 window (no
# train/test split) and found Sharpe negative at every threshold tested - tau=9 was
# chosen as best-available LOSS MITIGATION, not a validated edge.
#
# This script instead asks: at what point does the deployed model (ensemble_ridge_elo,
# market-blended - tools/model_backtest_harness.R's "ensemble_ridge_elo" candidate,
# reproduced verbatim here, never re-derived) produce genuinely CALIBRATED/RESPONSIVE
# predictions, independent of whether that's currently profitable against the closing
# line - using a real chronological TRAIN (2010-2017) / TEST (2018-2019) split, both
# walk-forward/no-lookahead via tools/backtest_common.R's existing build_walkforward_
# games() (reused, not re-derived - same discipline tools/weekly_accuracy_report.R
# followed reusing tools/model_backtest_harness.R's candidate).
#
# Real historical closing moneylines exist in CACHE_SCHEDULES only from 2010 onward
# (config.R:244/276 - hard data-availability wall, not a choice) - hence TRAIN =
# 2010-2017 (8 seasons), TEST = 2018-2019 (2 seasons), exactly as specified.
#
# Threshold g is CUMULATIVE (min(home_gp, away_gp) >= g), matching the semantics of the
# actual MIN_SAMPLE_GAMES_FOR_STAKE gate itself (market_odds_engine.R forces Bankroll_Rec
# to 0 when EITHER team has played fewer than the threshold) and matching backtest_
# shrinkage_optimizer.R's own tau convention - not a re-derived, differently-shaped
# bucketing rule.
#
# METHOD for candidate g* (TRAIN only): at each g in 0:16, compute the model's Brier
# score on games with min_gp >= g, and compare it to a NAIVE baseline (constant
# probability = the TRAIN-set overall home-win rate - a "no information beyond
# home-field" baseline, deliberately not the market itself, since the market's own
# blend weight (0.97) already dominates the model at every g and would trivially "pass"
# a market-relative baseline everywhere). g* = the smallest g at which the model beats
# the naive baseline's Brier score AND a game-level paired bootstrap CI (2000 resamples,
# set.seed(20260917) per CLAUDE.md's glmnet/randomized-procedure convention) of
# (naive_brier - model_brier) excludes zero on the low side (i.e. the improvement is
# statistically distinguishable from noise, not just numerically positive).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_min_sample_games_for_stake.R
# ==============================================================================

# NOTE: this agent's work is isolated to the git worktree at WORKTREE_DIR below (per this
# task's dispatch instructions), unlike every sibling tools/*.R script's hardcoded PROJECT_DIR,
# which points at the main repo checkout. source("config.R") below re-hardcodes its own
# PROJECT_DIR/CACHE_DIR to the main repo path (config.R:20-21) regardless of our setwd() -
# WORKTREE_CACHE_DIR is therefore tracked separately so this script's own output artifact
# lands inside the worktree (not silently written into the main repo's cache/), while every
# READ of an existing CACHE_* path still correctly resolves to config.R's main-repo path
# (those input caches are shared, read-only, real data - not something this task regenerates).
WORKTREE_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics/.claude/worktrees/agent-a648d39a05886e7cb"
WORKTREE_CACHE_DIR <- file.path(WORKTREE_DIR, "cache")
if (!dir.exists(WORKTREE_CACHE_DIR)) dir.create(WORKTREE_CACHE_DIR, recursive = TRUE)
setwd(WORKTREE_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_min_sample_games_for_stake.R"

source("team_ratings_engine.R")     # -> compute_power_rating_points()
source("market_odds_engine.R")      # -> american_to_decimal(), american_to_prob(), calculate_kelly()
source("tools/backtest_common.R")   # -> build_walkforward_games()
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R") # -> predict_ridge_massey_walkforward()
source("tools/elo_model.R")          # -> run_elo_walkforward()

if (!file.exists(CACHE_EPA_METRICS) || !file.exists(CACHE_SCHEDULES) || !file.exists(CACHE_FATIGUE_METRICS)) {
  stop("CACHE_EPA_METRICS / CACHE_SCHEDULES / CACHE_FATIGUE_METRICS missing - run the pipeline stages first.")
}

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

TRAIN_SEASONS <- 2010L:2017L
TEST_SEASONS  <- 2018L:2019L
ALL_SEASONS   <- c(TRAIN_SEASONS, TEST_SEASONS)

avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("MIN_SAMPLE_GAMES_FOR_STAKE calibration-responsiveness derivation - run at",
    format(Sys.time()), "\n")
cat("==============================================================\n\n")
cat(sprintf("TRAIN seasons: %d-%d (n_seasons=%d)\n", min(TRAIN_SEASONS), max(TRAIN_SEASONS), length(TRAIN_SEASONS)))
cat(sprintf("TEST  seasons: %d-%d (n_seasons=%d)\n\n", min(TEST_SEASONS), max(TEST_SEASONS), length(TEST_SEASONS)))

# ------------------------------------------------------------------------------------------
# Build the shared walk-forward game table ONCE across TRAIN+TEST (no-lookahead by
# construction - see tools/backtest_common.R header), then split by season.
# ------------------------------------------------------------------------------------------
cat("Building walk-forward game table (2010-2019)...\n")
games <- build_walkforward_games(epa, completed, ALL_SEASONS, avg_plays_per_game)
cat(sprintf("Built %d walk-forward games.\n\n", nrow(games)))

starter_tbl <- get_qb_starter_table(MODERN_ERA_START_SEASON:max(TEST_SEASONS))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- ifelse(is.na(games$home_ml) | is.na(games$away_ml), NA_real_, imp_h / (imp_h + imp_a))

# Elo needs sequential simulation across full history for proper warm-up (matches
# tools/model_backtest_harness.R's own approach) - run once from MODERN_ERA_START_SEASON
# through the end of TEST, then join by game_id.
cat("Simulating Elo sequentially across full history (one-time cost)...\n")
elo_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score),
         season >= MODERN_ERA_START_SEASON, season <= max(TEST_SEASONS))
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
  select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")
cat(sprintf("Elo coverage in the scored window: %d/%d games.\n\n", sum(!is.na(games$elo_margin_pts)), nrow(games)))

# ------------------------------------------------------------------------------------------
# ensemble_ridge_elo predict_fn, reproduced VERBATIM from tools/model_backtest_harness.R
# (never a second, independently-typed copy of the deployed candidate's math - see CLAUDE.md).
# ------------------------------------------------------------------------------------------
baseline_margin <- function(games, k = RATING_SHRINKAGE_GAMES_K) {
  home_w <- games$home_gp / (games$home_gp + k)
  away_w <- games$away_gp / (games$away_gp + k)
  home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
  away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior
  (home_rating - away_rating) + NFL_HCA
}

blend_with_market <- function(model_prob, market_prob, weight) {
  ifelse(is.na(market_prob), model_prob, weight * market_prob + (1 - weight) * model_prob)
}

predict_ensemble_ridge_elo <- function(games, weight = MARKET_BLEND_WEIGHT, penalty = QB_INJURY_RATING_PENALTY_PTS) {
  home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
  away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
  ridge_margin <- predict_ridge_massey_walkforward(games) - penalty * home_adj + penalty * away_adj
  elo_margin   <- games$elo_margin_pts + games$fatigue_adj - penalty * home_adj + penalty * away_adj
  ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, weight)
  elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, weight)
  0.5 * ridge_prob + 0.5 * elo_prob
}

games$model_prob <- predict_ensemble_ridge_elo(games)
games$min_gp <- pmin(games$home_gp, games$away_gp)

train_games <- games |> filter(season %in% TRAIN_SEASONS)
test_games  <- games |> filter(season %in% TEST_SEASONS)
cat(sprintf("TRAIN games: %d   TEST games: %d\n\n", nrow(train_games), nrow(test_games)))

# ------------------------------------------------------------------------------------------
# Naive baseline: constant probability = TRAIN-set overall home-win rate. Deliberately NOT
# the market (market_prob already dominates the blend at weight=0.97 and would trivially
# "beat" the model everywhere, telling us nothing about the model's OWN responsiveness to
# sample size) and NOT a flat 0.5 (home field advantage is real and well-established - a
# fair naive baseline should already capture it).
# ------------------------------------------------------------------------------------------
naive_prob_train <- mean(train_games$home_win)
cat(sprintf("Naive baseline probability (TRAIN home-win rate): %.4f\n\n", naive_prob_train))

brier <- function(p, y) mean((p - y)^2)
logloss <- function(p, y) {
  p <- pmin(pmax(p, 1e-6), 1 - 1e-6)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

# ------------------------------------------------------------------------------------------
# Bootstrap CI (paired, game-level resampling) of (naive_brier - model_brier) at threshold g,
# on a given dataset. Positive = model beats naive. CI excludes zero on the low side => the
# improvement is not just noise. set.seed(20260917) per CLAUDE.md's randomized-procedure
# convention (reused from team_ratings_engine.R's ridge fit).
# ------------------------------------------------------------------------------------------
N_BOOT <- 2000L

bootstrap_ci_brier_diff <- function(p_model, p_naive, y, n_boot = N_BOOT) {
  n <- length(y)
  if (n < 5) return(c(lo = NA_real_, hi = NA_real_, mean = NA_real_))
  set.seed(20260917)
  diffs <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    diffs[b] <- brier(p_naive[idx], y[idx]) - brier(p_model[idx], y[idx])
  }
  c(lo = unname(quantile(diffs, 0.025)), hi = unname(quantile(diffs, 0.975)), mean = mean(diffs))
}

# ------------------------------------------------------------------------------------------
# Sharpe at threshold g (cumulative min_gp >= g), reused formula from
# tools/backtest_shrinkage_optimizer.R / tools/model_backtest_harness.R (quarter-Kelly,
# real historical moneylines, never re-derived independently).
# ------------------------------------------------------------------------------------------
sharpe_for_tau <- function(df, tau) {
  staking <- df |>
    filter(min_gp >= tau, !is.na(home_ml), !is.na(away_ml)) |>
    mutate(
      model_away_prob = 1 - model_prob,
      home_dec = american_to_decimal(home_ml), away_dec = american_to_decimal(away_ml),
      home_ev = model_prob * home_dec - 1, away_ev = model_away_prob * away_dec - 1,
      pick_home = home_ev > away_ev,
      best_prob = if_else(pick_home, model_prob, model_away_prob),
      best_dec  = if_else(pick_home, home_dec, away_dec),
      won       = if_else(pick_home, home_win == 1L, home_win == 0L),
      kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
      bet_return_pct = if_else(won, kelly_pct / 100 * (best_dec - 1), -kelly_pct / 100)
    ) |>
    filter(kelly_pct > 0)
  n <- nrow(staking)
  if (n < 2) return(list(sharpe = NA_real_, n = n, cumret_pct = NA_real_))
  list(sharpe = mean(staking$bet_return_pct) / sd(staking$bet_return_pct), n = n,
       cumret_pct = sum(staking$bet_return_pct) * 100)
}

# ------------------------------------------------------------------------------------------
# g in 0:16 - compute Brier/log-loss/naive-comparison/bootstrap CI on TRAIN, and Brier/
# log-loss/Sharpe on both TRAIN and TEST at every g for direct comparison.
# ------------------------------------------------------------------------------------------
G_GRID <- 0:16

compute_row <- function(df, g, naive_p) {
  sub <- df |> filter(min_gp >= g)
  n <- nrow(sub)
  if (n == 0) {
    return(data.frame(g = g, n = 0, brier_model = NA_real_, brier_naive = NA_real_,
                       logloss_model = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_, ci_mean = NA_real_))
  }
  bm <- brier(sub$model_prob, sub$home_win)
  bn <- brier(rep(naive_p, n), sub$home_win)
  ll <- logloss(sub$model_prob, sub$home_win)
  ci <- bootstrap_ci_brier_diff(sub$model_prob, rep(naive_p, n), sub$home_win)
  data.frame(g = g, n = n, brier_model = bm, brier_naive = bn, logloss_model = ll,
             ci_lo = ci["lo"], ci_hi = ci["hi"], ci_mean = ci["mean"], row.names = NULL)
}

cat("Computing TRAIN-set calibration curve (Brier/log-loss/naive-comparison/bootstrap CI) by threshold g...\n")
train_curve <- bind_rows(lapply(G_GRID, function(g) compute_row(train_games, g, naive_prob_train)))
cat("\n-- TRAIN curve (2010-2017) --\n")
print(train_curve, row.names = FALSE)

# g* = smallest g where model beats naive (brier_model < brier_naive) AND bootstrap CI of
# (naive - model) excludes zero on the low side (ci_lo > 0).
candidate_rows <- train_curve |>
  filter(!is.na(brier_model), brier_model < brier_naive, !is.na(ci_lo), ci_lo > 0)
g_star <- if (nrow(candidate_rows) > 0) min(candidate_rows$g) else NA_integer_

cat(sprintf("\nCandidate g* (smallest g with model_brier < naive_brier AND bootstrap 95%% CI of\n"))
cat(sprintf("(naive_brier - model_brier) excluding zero on the low side): %s\n\n",
            ifelse(is.na(g_star), "NONE FOUND in 0:16", g_star)))

# ------------------------------------------------------------------------------------------
# Validate g* (and neighbors) out-of-sample on TEST.
# ------------------------------------------------------------------------------------------
cat("Computing TEST-set calibration curve (same naive baseline, TRAIN-derived) by threshold g...\n")
test_curve <- bind_rows(lapply(G_GRID, function(g) compute_row(test_games, g, naive_prob_train)))
cat("\n-- TEST curve (2018-2019) --\n")
print(test_curve, row.names = FALSE)

# ------------------------------------------------------------------------------------------
# Sharpe at g* (and at current config.R tau=9) on both TRAIN and TEST, reconciled against
# config.R's existing Sharpe-negative-everywhere finding.
# ------------------------------------------------------------------------------------------
g_eval <- if (!is.na(g_star)) g_star else MIN_SAMPLE_GAMES_FOR_STAKE

sharpe_train_gstar <- sharpe_for_tau(train_games, g_eval)
sharpe_test_gstar  <- sharpe_for_tau(test_games, g_eval)
sharpe_train_tau9  <- sharpe_for_tau(train_games, MIN_SAMPLE_GAMES_FOR_STAKE)
sharpe_test_tau9   <- sharpe_for_tau(test_games, MIN_SAMPLE_GAMES_FOR_STAKE)

cat("\n==============================================================\n")
cat("SHARPE AT g* / current tau=9 (TRAIN 2010-2017, TEST 2018-2019 subwindows only -\n")
cat("NOT directly comparable in magnitude to config.R's full 2010-2025 in-sample Sharpe figures,\n")
cat("but same sign/direction check)\n")
cat("==============================================================\n")
cat(sprintf("g* = %s:  TRAIN sharpe=%s (n=%s, cumret=%s%%)   TEST sharpe=%s (n=%s, cumret=%s%%)\n",
            g_eval,
            ifelse(is.na(sharpe_train_gstar$sharpe), "NA", sprintf("%.4f", sharpe_train_gstar$sharpe)),
            sharpe_train_gstar$n,
            ifelse(is.na(sharpe_train_gstar$cumret_pct), "NA", sprintf("%.1f", sharpe_train_gstar$cumret_pct)),
            ifelse(is.na(sharpe_test_gstar$sharpe), "NA", sprintf("%.4f", sharpe_test_gstar$sharpe)),
            sharpe_test_gstar$n,
            ifelse(is.na(sharpe_test_gstar$cumret_pct), "NA", sprintf("%.1f", sharpe_test_gstar$cumret_pct))))
cat(sprintf("tau=9:  TRAIN sharpe=%s (n=%s, cumret=%s%%)   TEST sharpe=%s (n=%s, cumret=%s%%)\n",
            ifelse(is.na(sharpe_train_tau9$sharpe), "NA", sprintf("%.4f", sharpe_train_tau9$sharpe)),
            sharpe_train_tau9$n,
            ifelse(is.na(sharpe_train_tau9$cumret_pct), "NA", sprintf("%.1f", sharpe_train_tau9$cumret_pct)),
            ifelse(is.na(sharpe_test_tau9$sharpe), "NA", sprintf("%.4f", sharpe_test_tau9$sharpe)),
            sharpe_test_tau9$n,
            ifelse(is.na(sharpe_test_tau9$cumret_pct), "NA", sprintf("%.1f", sharpe_test_tau9$cumret_pct))))

cat("\nRECONCILIATION: this script's Sharpe figures are NOT a new profitability claim - both are\n")
cat("consistent with config.R:247's existing finding (Sharpe negative at every threshold tested,\n")
cat("2010-2025 in-sample). This script's TRAIN/TEST Sharpe figures at g* are reported here purely\n")
cat("for honesty/completeness (per this task's Scope/Out-of-scope instructions), not as evidence\n")
cat("of a validated edge. The calibration finding (Brier-score responsiveness to sample size) and\n")
cat("the staking-profitability finding (Sharpe) are two DIFFERENT questions about the same model -\n")
cat("a model can become better-calibrated with more current-season data while still losing money\n")
cat("against the closing line at every threshold, if the underlying rating signal itself does not\n")
cat("beat the market (which config.R's market-blend-weight derivation, w=0.97, already suggests -\n")
cat("see config.R:288-296).\n")

# ------------------------------------------------------------------------------------------
# Save + recommendation
# ------------------------------------------------------------------------------------------
out <- list(
  run_at = Sys.time(),
  train_seasons = TRAIN_SEASONS,
  test_seasons = TEST_SEASONS,
  n_train_games = nrow(train_games),
  n_test_games = nrow(test_games),
  naive_prob_train = naive_prob_train,
  train_curve = train_curve,
  test_curve = test_curve,
  g_star = g_star,
  sharpe_train_gstar = sharpe_train_gstar,
  sharpe_test_gstar = sharpe_test_gstar,
  sharpe_train_tau9 = sharpe_train_tau9,
  sharpe_test_tau9 = sharpe_test_tau9,
  current_config_tau = MIN_SAMPLE_GAMES_FOR_STAKE
)
saveRDS(out, file.path(WORKTREE_CACHE_DIR, "min_sample_games_for_stake_derivation.rds"))
cat("\nSaved full derivation output to (worktree) cache/min_sample_games_for_stake_derivation.rds\n")

cat("\n==============================================================\n")
cat("RECOMMENDATION\n")
cat("==============================================================\n")
cat(sprintf("Candidate g* from TRAIN (calibration-responsiveness method): %s\n", ifelse(is.na(g_star), "NONE", g_star)))
cat(sprintf("Current config.R MIN_SAMPLE_GAMES_FOR_STAKE: %d\n", MIN_SAMPLE_GAMES_FOR_STAKE))
cat("See this run's stdout/cache/min_sample_games_for_stake_derivation.rds for the full TRAIN/TEST\n")
cat("curves this recommendation is based on. Final written recommendation is in this task's report,\n")
cat("not auto-applied to config.R (out of scope for this script/task).\n")
