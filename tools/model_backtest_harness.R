# ==============================================================================
# General-Purpose Model-Comparison Backtest Harness (Phase A, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/model_backtest_harness.R
#
# Generalizes tools/backtest_shrinkage_optimizer.R's walk-forward, no-lookahead discipline
# into a REUSABLE comparison across multiple candidate rating models, not just the two
# Phase-8 constants. Shares the exact same game-table builder (tools/backtest_common.R) -
# backtest_shrinkage_optimizer.R itself is untouched in behavior (see its own header/commit
# message for the regression check proving this).
#
# PLUGGABLE INTERFACE (deliberately minimal - see docs/HANDOFF.md's plan for why a bigger
# "framework" was rejected): a candidate is a plain named list:
#   list(name = "...", predict_fn = function(games, params) -> home_win_prob vector, params = list(...))
# `predict_fn` receives the FULL walk-forward game table (see column list below) and must
# return one home_win_prob per row, using only columns already present (no candidate may
# reach back into CACHE_EPA_METRICS/CACHE_SCHEDULES itself - keeps every candidate provably
# walk-forward/no-lookahead by construction, since the table itself was built that way once).
# This is a simpler contract than a general fit/predict split - sufficient for every candidate
# in this repo's current roadmap (all are direct formula transforms of the same snapshot
# columns), and avoids building unused generality (CLAUDE.md's anti-premature-abstraction
# convention).
#
# Game table columns (from build_walkforward_games(), see tools/backtest_common.R, plus this
# script's own additions below): season, week, game_id, gameday, home_team, away_team,
# home_raw, away_raw, home_prior, away_prior, home_gp, away_gp, home_win, home_margin,
# home_ml, away_ml, home_qb_backup, away_qb_backup (NA where unknown), market_prob (ALWAYS NA now -
# market_odds_engine.R, which used to compute this, is deleted; see "MARKET DEPENDENCY REMOVED"
# below).
#
# METRICS (compute_backtest_metrics()): Brier score, log-loss, and a calibration/reliability
# table are PRIMARY (threshold-free). Accuracy/precision/recall/F1 (threshold=0.5, positive
# class="home team wins" - stated explicitly here, not left implicit) and AUC are SECONDARY/
# diagnostic, reported because the user asked for them, but never the sole basis for judging a
# candidate given they're sensitive to an arbitrary threshold/class choice for a problem with
# no natural positive class. There is NO market-relative Sharpe/ROI staking check any more - see
# the "MARKET DEPENDENCY REMOVED" note below for why (that diagnostic required market_odds_
# engine.R, which is deleted and staying deleted per the zero-betting-data policy).
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/model_backtest_harness.R
#
# MARKET DEPENDENCY REMOVED (2026-11-11, Issue #137 follow-up - see docs/internal/
# handoff_history.md's entry of this date for the full writeup): this script used to
# source("market_odds_engine.R") for american_to_decimal()/american_to_prob()/calculate_kelly(),
# blend every candidate's model probability with devigged historical market odds via
# MARKET_BLEND_WEIGHT, and run a quarter-Kelly staking/Sharpe simulation against real closing
# moneylines. market_odds_engine.R was deleted under the zero-betting-data policy (#137/#13) and
# MARKET_BLEND_WEIGHT no longer has a live assignment in config.R (see config.R's own comment at
# the old constant's former location). This script now has NO market/odds input anywhere -
# blend_with_market() below is kept only as a documented no-op pass-through (never resurrecting
# market_odds_engine.R) so candidate code that historically called it still reads the same, and
# the Kelly/Sharpe staking diagnostic has been removed outright from compute_backtest_metrics()
# rather than faked with no real odds data behind it.
# ==============================================================================

# PROJECT_DIR: previously hardcoded to the author's main checkout (stale pattern predating
# config.R's own worktree-safe fix for GitHub issue #43 - see config.R's PROJECT_DIR comment
# block for the full history). This script is invoked via `Rscript tools/model_backtest_harness.R`
# from the repo root, same convention every other pipeline entry point uses, so no setwd() of its
# own is needed - config.R itself derives PROJECT_DIR from getwd() (or NFL_PROJECT_DIR if set),
# which makes this script correctly worktree-isolated instead of silently reading/writing the
# main checkout's cache/ from inside a worktree.

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/model_backtest_harness.R"

source("team_ratings_engine.R")   # -> compute_power_rating_points()
source("tools/backtest_common.R") # -> build_walkforward_games()
source("tools/qb_injury_features.R")
source("tools/ridge_massey_model.R") # -> predict_ridge_massey_walkforward() (Phase 2)
source("tools/elo_model.R")          # -> run_elo_walkforward() (Phase 3)
source("tools/gbm_model.R")          # -> predict_gbm_walkforward() (Phase 4)
source("tools/ridge_situational_model.R") # -> predict_ridge_situational_walkforward() (Phase 4, situational features)
source("tools/kalman_state_space_model.R") # -> run_kalman_walkforward() (Phase 5, state-space)
source("tools/ridge_participation_model.R") # -> predict_ridge_participation_walkforward() (Known Issue #7 pickup)

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

CALIBRATION_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("NFL model-comparison backtest harness - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

# ------------------------------------------------------------------------------------------
# Build the shared game table ONCE, then attach every candidate's extra feature columns to it
# (QB-backup flags, historical devigged market probability) so every predict_fn() below draws
# from the same, single, provably-no-lookahead table.
# ------------------------------------------------------------------------------------------
cat("Building walk-forward game table...\n")
games <- build_walkforward_games(epa, completed, CALIBRATION_SEASONS, avg_plays_per_game)
cat(sprintf("Built %d walk-forward games (seasons %d-%d).\n", nrow(games),
            min(CALIBRATION_SEASONS), max(CALIBRATION_SEASONS)))

starter_tbl <- get_qb_starter_table((MODERN_ERA_START_SEASON):(CURRENT_SEASON - 1L))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

# Devigged market odds removed per the zero-betting-data policy (#137/#13) - market_odds_
# engine.R's american_to_prob() is gone, so there is no real market-implied probability to
# compute here. Keep the column (NA throughout) so blend_with_market()'s existing NA fallback
# path is exercised identically to tools/backtest_common.R's grade_walkforward_games(), which
# already does the same thing for the same reason.
games$market_prob <- NA_real_

cat(sprintf("Games with a known QB-backup flag: %d/%d. No market-odds input in this harness (Issue #137 - market_odds_engine.R deleted).\n\n",
            sum(!is.na(games$home_qb_backup) & !is.na(games$away_qb_backup)), nrow(games)))

# ------------------------------------------------------------------------------------------
# Phase 3: Elo simulation. Run ONCE across the FULL history (MODERN_ERA_START_SEASON onward,
# not just CALIBRATION_SEASONS) so the sequential rating state is properly warmed up before
# CALIBRATION_SEASONS begins (2002 is Elo's own burn-in season - see tools/derive_elo_k.R),
# then join elo_margin_pts/fatigue_adj back onto the shared `games` table by game_id so Elo's
# candidates can be combined with the same QB-injury/market-blend stack as every other
# candidate, exactly like Phases 1-2's candidates are.
# ------------------------------------------------------------------------------------------
cat("Simulating Elo sequentially across full history (one-time cost)...\n")
elo_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score), season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)
elo_results <- run_elo_walkforward(elo_full_history, fatigue, ELO_K_FACTOR) |>
  select(game_id, elo_margin_pts, fatigue_adj)
games <- games |> left_join(elo_results, by = "game_id")
cat(sprintf("Elo coverage in the scored window: %d/%d games.\n\n", sum(!is.na(games$elo_margin_pts)), nrow(games)))

# ------------------------------------------------------------------------------------------
# Phase 5: Kalman state-space simulation. Run ONCE across the FULL history for the same
# burn-in-then-join-by-game_id reason Elo's block above does. kalman_pred_var is that game's
# OWN combined (home_var + away_var + KALMAN_OBSERVATION_VARIANCE) uncertainty - unlike every
# other candidate here, this one does NOT convert margin to probability via a fixed
# NFL_MARGIN_SIGMA; kalman_margin_pts/kalman_pred_var are joined in raw and each candidate below
# does its own pnorm(margin / sqrt(pred_var)).
# ------------------------------------------------------------------------------------------
cat("Simulating Kalman state-space filter sequentially across full history (one-time cost)...\n")
kalman_full_history <- sch |>
  filter(!is.na(home_score), !is.na(away_score), season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)
kalman_results <- run_kalman_walkforward(kalman_full_history) |>
  select(game_id, kalman_margin_pts, kalman_pred_var)
games <- games |> left_join(kalman_results, by = "game_id")
cat(sprintf("Kalman coverage in the scored window: %d/%d games.\n\n", sum(!is.na(games$kalman_margin_pts)), nrow(games)))

# ------------------------------------------------------------------------------------------
# Known Issue #7 pickup: participation/personnel features. CACHE_PARTICIPATION_FEATURES only
# covers PARTICIPATION_MIN_SEASON (2016) onward (see tools/participation_features.R's header
# for why) - attach_participation_asof() leaves home_/away_ participation columns NA for any
# game before that team has real participation history, exactly like every other as-of
# attach in this harness.
# ------------------------------------------------------------------------------------------
if (file.exists(CACHE_PARTICIPATION_FEATURES)) {
  cat("Attaching participation/personnel features (as-of, no lookahead)...\n")
  part_features <- readRDS(CACHE_PARTICIPATION_FEATURES) |> mutate(game_date = as.Date(game_date))
  games <- attach_participation_asof(games, part_features)
  cat(sprintf("Games with real participation history for BOTH teams: %d/%d.\n\n",
              sum(!is.na(games$home_off_personnel_11_rate_roll) & !is.na(games$away_off_personnel_11_rate_roll)),
              nrow(games)))
} else {
  cat("CACHE_PARTICIPATION_FEATURES not found - run tools/participation_features.R first. Skipping participation candidates' real coverage (diffs will impute to 0 for every game).\n\n")
  for (cn in PARTICIPATION_ROLL_COLS) {
    games[[paste0("home_", cn)]] <- NA_real_
    games[[paste0("away_", cn)]] <- NA_real_
  }
}

# ------------------------------------------------------------------------------------------
# Shared building block every candidate's predict_fn() calls - the exact production blend
# formula (K-shrinkage + HCA + pnorm), never a second copy.
# ------------------------------------------------------------------------------------------
baseline_margin <- function(games, k = RATING_SHRINKAGE_GAMES_K) {
  home_w <- games$home_gp / (games$home_gp + k)
  away_w <- games$away_gp / (games$away_gp + k)
  home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
  away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior
  (home_rating - away_rating) + NFL_HCA
}

# NO-OP (Issue #137 follow-up, 2026-11-11): this used to blend a model probability with
# historical market probability (weight * market_prob + (1 - weight) * model_prob), falling back
# to model_prob where market data was unavailable. market_odds_engine.R is deleted and
# MARKET_BLEND_WEIGHT no longer has a live assignment (zero-betting-data policy, #137/#13) - every
# caller below now always passes market_prob = NA (see games$market_prob above), so this always
# takes the fallback branch. Kept as a named pass-through, rather than inlining model_prob at
# every call site, so the diff against the pre-#137 candidate bodies stays minimal and legible.
blend_with_market <- function(model_prob, market_prob = NA_real_, weight = 0) {
  model_prob
}

# ------------------------------------------------------------------------------------------
# Candidates - Phase A's baseline plus Phase 1's two feature additions, individually AND
# combined (per the plan's requirement that each sub-component be independently toggleable,
# since the research flagged that a market-blend alone shows diminishing returns once market
# info is present - only checking the combination would hide that).
# ------------------------------------------------------------------------------------------
candidates <- list(
  list(name = "baseline_k3.6", params = list(), predict_fn = function(games, params) {
    pnorm(baseline_margin(games) / NFL_MARGIN_SIGMA)
  }),
  list(name = "market_blend_only", params = list(weight = 0), predict_fn = function(games, params) {
    model_prob <- pnorm(baseline_margin(games) / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  list(name = "qb_injury_only", params = list(penalty = QB_INJURY_RATING_PENALTY_PTS), predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- baseline_margin(games) - params$penalty * home_adj + params$penalty * away_adj
    pnorm(margin / NFL_MARGIN_SIGMA)
  }),
  list(name = "phase1_combined", params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- baseline_margin(games) - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  # Phase 2: ridge-regularized Massey rating (tools/ridge_massey_model.R), replacing the
  # hand-tuned K-blend with a learned, per-season-refit ridge regression. "ridge_only" is the
  # fair comparison against baseline_k3.6 (does ridge alone beat the original hand-coded
  # formula?); "ridge_phase1_combined" swaps ridge's margin in for baseline_margin() inside the
  # SAME QB-injury + market-blend stack production already uses, to test whether ridge is worth
  # promoting on top of what's actually deployed.
  list(name = "ridge_only", params = list(), predict_fn = function(games, params) {
    pnorm(predict_ridge_massey_walkforward(games) / NFL_MARGIN_SIGMA)
  }),
  list(name = "ridge_phase1_combined", params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- predict_ridge_massey_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  # Phase 3: MOV-weighted Elo (tools/elo_model.R), a structurally different candidate from the
  # EPA-differential/ridge lineage above - a classic sequential Elo rating with real fatigue
  # already folded in as an additive margin term (see that file's header). elo_margin_pts is
  # Elo's OWN margin (fatigue_adj is added separately below, matching tools/elo_model.R's own
  # construction of its home_win_prob column, so "elo_mov" here reproduces that column exactly).
  # "elo_phase1_combined" swaps Elo's margin in for baseline_margin()/ridge's margin inside the
  # SAME QB-injury + market-blend stack, to see whether Elo is worth promoting on top of what's
  # actually deployed (ridge_phase1_combined, as of Phase 2).
  list(name = "elo_mov", params = list(), predict_fn = function(games, params) {
    pnorm((games$elo_margin_pts + games$fatigue_adj) / NFL_MARGIN_SIGMA)
  }),
  list(name = "elo_phase1_combined", params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- games$elo_margin_pts + games$fatigue_adj - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  # Exploratory: simple 50/50 probability ensemble of ridge_phase1_combined and
  # elo_phase1_combined - checks whether averaging the two structurally-different Phase 2/
  # Phase 3 candidates combines ridge's better Sharpe profile with Elo's better calibration,
  # rather than picking just one. Not in the original phase roadmap - added because Phase 3's
  # elo_phase1_combined showed a real calibration win (Brier/log-loss/AUC) alongside a real
  # Sharpe REGRESSION (not just "still negative" like Phases 1-2, but meaningfully worse) - see
  # docs/HANDOFF.md for the full comparison and why this candidate was worth checking before
  # deciding what (if anything) replaces ridge in the live pipeline.
  list(name = "ensemble_ridge_elo", params = list(weight = 0,  # dead param (Issue #137) - blend_with_market() ignores this now
                                                   penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    ridge_margin <- predict_ridge_massey_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    elo_margin   <- games$elo_margin_pts + games$fatigue_adj - params$penalty * home_adj + params$penalty * away_adj
    ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    0.5 * ridge_prob + 0.5 * elo_prob
  }),
  # TRUE CURRENT PRODUCTION FORMULA (added 2026-11-11 - see docs/internal/handoff_history.md's
  # entry of this date, and VariantsClient.tsx's "2-Model Baseline (Production)" row, which this
  # candidate's output is meant to back). "ensemble_ridge_elo" directly above is NOT the same
  # formula as what team_ratings_engine.R actually deploys for projected matchups, in two ways
  # verified by reading team_ratings_engine.R's run_team_ratings() (~lines 436-548) directly:
  #   1) Production averages MARGINS once then takes a single pnorm() (projected_margin <-
  #      0.5 * ridge_margin + 0.5 * elo_margin; home_win_prob <- pnorm(projected_margin /
  #      NFL_MARGIN_SIGMA), team_ratings_engine.R:542-544) - NOT an average of two independently-
  #      pnorm'd probabilities like "ensemble_ridge_elo" computes.
  #   2) Production's live Elo margin for an upcoming game does NOT add fatigue_adj - the
  #      run_elo_walkforward() call inside run_team_ratings() (team_ratings_engine.R:450-463) is
  #      used ONLY to warm up Elo's sequential state (see that function's own comment: "only used
  #      for warming up Elo's historical state, not for this run's live prediction"); the actual
  #      per-game elo_margin comes from get_team_elo()/project_elo_rating() + qb_shift only
  #      (team_ratings_engine.R:531-539). Fatigue was originally meant to be applied once,
  #      downstream, inside market_odds_engine.R (team_ratings_engine.R:446's own comment) - that
  #      file is deleted (#137/#13) and nothing else re-applies fatigue to projected_matchups, so
  #      the live production formula today has NO fatigue term in it at all.
  # This candidate reproduces that exact formula: no market blend (none exists), QB-injury
  # shift applied to both margins before averaging, no fatigue_adj, margins averaged once, one
  # pnorm() at the end - matching grade_walkforward_games()'s formula-parity comment too
  # (tools/backtest_common.R:278-285), modulo that function's probability-averaging form which
  # pre-dates this correction and is itself NOT bit-for-bit identical to run_team_ratings()'s
  # margin-averaging form either (a separate, pre-existing discrepancy between the grading helper
  # and the live ensemble, out of scope for this candidate - noted here for a future session).
  list(name = "prod_ridge_elo_2model", params = list(penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    qb_shift <- -params$penalty * home_adj + params$penalty * away_adj
    ridge_margin <- predict_ridge_massey_walkforward(games) + qb_shift
    elo_margin   <- games$elo_margin_pts + qb_shift   # NOTE: no fatigue_adj - matches live production
    projected_margin <- 0.5 * ridge_margin + 0.5 * elo_margin
    pnorm(projected_margin / NFL_MARGIN_SIGMA)
  }),
  # Phase 4: gradient-boosted trees (tools/gbm_model.R) as a STACKING model over Phase 2/3's
  # ridge and Elo margins (raw, unadjusted for QB/market - those are fed in as their own
  # features so the tree ensemble learns their effect itself, rather than double-applying a
  # hand-picked adjustment on top of tree output). Nested walk-forward hyperparameter tuning
  # (nrounds via early stopping on a held-out prior season) happens inside
  # predict_gbm_walkforward() itself - see that file's header.
  list(name = "gbm_stack", params = list(), predict_fn = function(games, params) {
    ridge_margin_raw <- predict_ridge_massey_walkforward(games)
    elo_margin_raw   <- games$elo_margin_pts
    predict_gbm_walkforward(games, ridge_margin_raw, elo_margin_raw)
  }),
  # Phase 4 (situational-feature engineering): ridge_massey_model.R's same ridge/Massey approach,
  # but with 14 extra situational-EPA-diff regressors (config.R's SITUATIONAL_EPA_ROLL_COLS -
  # early-down/money-down EPA/success, red-zone success rate, explosive-play rate, PROE) added on
  # top of diff_raw/diff_prior/their games-played interactions - see tools/ridge_situational_
  # model.R's header for the full feature list and why this is a separate file/candidate rather
  # than an edit to ridge_massey_model.R itself. "ridge_situational_only" is the fair comparison
  # against "ridge_only" (do situational splits help the SAME ridge approach beat aggregate-EPA-
  # only ridge?); "ridge_situational_phase1_combined" swaps it into the same QB-injury + market-
  # blend stack ensemble_ridge_elo is built from, to see whether it's worth promoting on top of
  # what's actually deployed.
  list(name = "ridge_situational_only", params = list(), predict_fn = function(games, params) {
    pnorm(predict_ridge_situational_walkforward(games) / NFL_MARGIN_SIGMA)
  }),
  list(name = "ridge_situational_phase1_combined",
       params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- predict_ridge_situational_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  # Ensemble analog of "ensemble_ridge_elo" but with the situational ridge candidate swapped in
  # for the plain ridge candidate - checks whether situational features help THROUGH the
  # currently-deployed ensemble shape, not just standalone.
  list(name = "ensemble_ridge_situational_elo",
       params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    ridge_margin <- predict_ridge_situational_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    elo_margin   <- games$elo_margin_pts + games$fatigue_adj - params$penalty * home_adj + params$penalty * away_adj
    ridge_prob <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    elo_prob   <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    0.5 * ridge_prob + 0.5 * elo_prob
  }),
  # Phase 5: Kalman state-space filter (tools/kalman_state_space_model.R) - a third,
  # structurally different candidate from the ridge/Elo lineage (genuine Bayesian filtering,
  # per-game-specific uncertainty rather than a single fixed NFL_MARGIN_SIGMA). "kalman_pure" is
  # the fair standalone comparison (pnorm() uses THIS candidate's own kalman_pred_var, not
  # NFL_MARGIN_SIGMA - the whole point of tracking per-team variance explicitly);
  # "kalman_phase1_combined" adds the QB-injury margin shift (kept in the same additive-margin
  # form every other candidate uses) then blends with market, still against kalman_pred_var.
  list(name = "kalman_pure", params = list(), predict_fn = function(games, params) {
    pnorm(games$kalman_margin_pts / sqrt(games$kalman_pred_var))
  }),
  list(name = "kalman_phase1_combined",
       params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- games$kalman_margin_pts - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / sqrt(games$kalman_pred_var))
    blend_with_market(model_prob, games$market_prob, params$weight)
  }),
  # Three-way ensemble: ridge + Elo + Kalman, each already market-blended/QB-adjusted in their
  # own established form, simple unweighted average (same "just average the probabilities"
  # philosophy as ensemble_ridge_elo, extended to a third structurally different candidate rather
  # than re-deriving new ensemble weights this session).
  list(name = "ensemble_ridge_elo_kalman",
       params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    ridge_margin  <- predict_ridge_massey_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    elo_margin    <- games$elo_margin_pts + games$fatigue_adj - params$penalty * home_adj + params$penalty * away_adj
    kalman_margin <- games$kalman_margin_pts - params$penalty * home_adj + params$penalty * away_adj
    ridge_prob  <- blend_with_market(pnorm(ridge_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    elo_prob    <- blend_with_market(pnorm(elo_margin / NFL_MARGIN_SIGMA), games$market_prob, params$weight)
    kalman_prob <- blend_with_market(pnorm(kalman_margin / sqrt(games$kalman_pred_var)), games$market_prob, params$weight)
    (ridge_prob + elo_prob + kalman_prob) / 3
  }),
  # Known Issue #7 pickup: ridge + participation/personnel features (tools/participation_
  # features.R / tools/ridge_participation_model.R) - personnel-grouping tendency, box counts,
  # pressure rates. Only real coverage 2016+ (participation's own hard floor - see that file's
  # header); earlier seasons impute all-zero diffs (no signal), same convention
  # ridge_situational_model.R already established for its own coverage gap.
  list(name = "ridge_participation_only", params = list(), predict_fn = function(games, params) {
    pnorm(predict_ridge_participation_walkforward(games) / NFL_MARGIN_SIGMA)
  }),
  list(name = "ridge_participation_phase1_combined",
       params = list(weight = 0, penalty = QB_INJURY_RATING_PENALTY_PTS),
       predict_fn = function(games, params) {
    home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
    away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))
    margin <- predict_ridge_participation_walkforward(games) - params$penalty * home_adj + params$penalty * away_adj
    model_prob <- pnorm(margin / NFL_MARGIN_SIGMA)
    blend_with_market(model_prob, games$market_prob, params$weight)
  })
)

# ------------------------------------------------------------------------------------------
# compute_backtest_metrics(): the full metric set for one candidate's prob vector.
# ------------------------------------------------------------------------------------------
compute_backtest_metrics <- function(games, prob, tau_grid_max = 12) {
  y <- games$home_win
  p <- pmin(pmax(prob, 1e-6), 1 - 1e-6)

  brier <- mean((p - y)^2)
  logloss <- -mean(y * log(p) + (1 - y) * log(1 - p))

  # Calibration/reliability table - fixed-width decile bins (not rank-based deciles), so bins
  # are directly comparable across candidates whose probability distributions differ in shape.
  bin <- cut(p, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
  calib <- tibble(p = p, y = y, bin = bin) |>
    group_by(bin) |>
    summarise(n = dplyr::n(), mean_predicted = mean(p), mean_actual = mean(y), .groups = "drop")

  # Secondary, threshold-based metrics. Convention (stated explicitly, per this repo's honesty
  # discipline): positive class = "home team wins", threshold = 0.5.
  pred_class <- as.integer(p > 0.5)
  tp <- sum(pred_class == 1 & y == 1); fp <- sum(pred_class == 1 & y == 0)
  fn <- sum(pred_class == 0 & y == 1); tn <- sum(pred_class == 0 & y == 0)
  accuracy  <- (tp + tn) / length(y)
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall    <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  f1        <- if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0) {
    2 * precision * recall / (precision + recall)
  } else NA_real_

  # Rank-based AUC (Mann-Whitney U / (n_pos*n_neg)) - no new package dependency.
  n_pos <- sum(y == 1); n_neg <- sum(y == 0)
  auc <- if (n_pos > 0 && n_neg > 0) {
    r <- rank(p, ties.method = "average")
    (sum(r[y == 1]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
  } else NA_real_

  # Market-relative Sharpe/ROI staking simulation REMOVED (2026-11-11, Issue #137 follow-up).
  # This used to run a quarter-Kelly staking simulation against real historical closing
  # moneylines, reusing calculate_kelly()/american_to_decimal() verbatim from market_odds_
  # engine.R. That file is deleted under the zero-betting-data policy (#137/#13) and is staying
  # deleted - rather than faking a staking diagnostic with no real odds/staking engine behind it,
  # this metric set is now threshold-free calibration (Brier/log-loss) plus the secondary
  # accuracy/precision/recall/F1/AUC diagnostics only. tau_grid_max is accordingly unused; kept
  # as a no-op parameter rather than touching every call site, since removing it carries no
  # benefit and this function's signature is not part of any other script's contract.

  list(
    brier = brier, logloss = logloss, accuracy = accuracy, precision = precision,
    recall = recall, f1 = f1, auc = auc,
    calibration_table = calib
  )
}

# ------------------------------------------------------------------------------------------
# Run every candidate, print + save the comparison table.
# ------------------------------------------------------------------------------------------
results <- list()
calib_tables <- list()

for (cand in candidates) {
  cat(sprintf("Evaluating candidate: %s...\n", cand$name))
  prob <- cand$predict_fn(games, cand$params)
  m <- compute_backtest_metrics(games, prob)
  calib_tables[[cand$name]] <- m$calibration_table
  results[[cand$name]] <- tibble(
    candidate = cand$name, brier = m$brier, logloss = m$logloss,
    accuracy = m$accuracy, precision = m$precision, recall = m$recall, f1 = m$f1, auc = m$auc,
    n_games = nrow(games)
  )
}

comparison <- bind_rows(results)

cat("\n==============================================================\n")
cat("COMPARISON TABLE (positive class = home win, threshold = 0.5)\n")
cat("==============================================================\n")
print(as.data.frame(comparison), row.names = FALSE)

cat("\n==============================================================\n")
cat("CALIBRATION TABLES (predicted-probability decile vs. actual home-win rate)\n")
cat("==============================================================\n")
for (nm in names(calib_tables)) {
  cat(sprintf("\n-- %s --\n", nm))
  print(as.data.frame(calib_tables[[nm]]), row.names = FALSE)
}

saveRDS(list(comparison = comparison, calibration_tables = calib_tables, run_at = Sys.time()),
        file.path(CACHE_DIR, "model_comparison_backtest.rds"))
cat("\nSaved full comparison output to cache/model_comparison_backtest.rds\n")
