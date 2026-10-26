# ==============================================================================
# tools/ml_feature_experiments.R
# ------------------------------------------------------------------------------
# Research/exploration pass for docs/ML_IMPROVEMENT_IDEAS.md "Part 2: Empirical
# Results". Does NOT modify ml_cv_benchmark.R, ML_BENCHMARK_REPORT.md, or
# roster_bottom_up_engine.R (or any other production file) — this is a
# standalone script that reuses the exact same feature pipeline / leave-one-
# season-out (LOSO) cross-validation / bootstrap-CI machinery as
# tools/ml_cv_benchmark.R (copied verbatim where it overlaps, not altered),
# so every number below is directly comparable to the published baseline:
#   Accuracy 0.639 [0.618, 0.661], ROC-AUC 0.675 [0.651, 0.699]
#   (docs/ML_BENCHMARK_REPORT.md, n = 1,902 real games, 8 real seasons).
#
# NOTE on window size: config.R's ROLLING_WINDOW_SIZE was re-swept from 13 to
# 12 on the same day ML_BENCHMARK_REPORT.md was written (see config.R's own
# comment on ROLLING_WINDOW_SIZE). To stay strictly comparable to the
# published 0.639/0.675 numbers (which were generated with window=13), this
# script pins window_size = 13 explicitly rather than reading the live
# (now-13->12-changed) config.R constant. A fresh baseline is re-fit inside
# this same script (identical pipeline, same seed) as the true apples-to-
# apples comparison point for every experiment below; the published 0.639 is
# reported alongside it only as an external sanity check.
#
# Three ideas tested (picked from docs/ML_IMPROVEMENT_IDEAS.md Part 1 as the
# most promising + cheapest to test given real data already in this repo):
#   1. Elo-style continuously-updated team rating differential (added feature,
#      derived purely from box_scores_cache.rds game-by-game results — no
#      new data source, zero look-ahead by construction).
#   2. RAPM-derived team-strength differential (added feature), using the
#      REAL possession-level RAPM data already computed by P2
#      (cache/wnba_pbp_cache.rds, 292,569 real possessions) — but RE-SOLVED
#      per LOSO fold using only the training seasons' possessions, because
#      the existing cache/rapm_ratings.rds is a single rating pooled across
#      ALL 8 seasons (including whichever season LOSO holds out), which would
#      leak future information into that fold if used as-is.
#   3. Recency-weighted (EWMA) rolling box-score averages, replacing the
#      existing flat-window rolling mean with an exponentially-weighted
#      moving average of the SAME underlying box-score stats (methodology
#      swap, not a new feature) — tests whether a continuously-updating
#      average suits WNBA's short ~40-44 game season better than a flat
#      window, directly per the brief's own research question.
#
# cache/travel_fatigue_metrics.rds (4 demo rows) and cache/team_shot_quality.rds
# (15 static snapshot rows, no reliable per-game join key back to
# box_scores_cache.rds — see docs/task_assignments_phase2.md's P2 Handoff
# Notes on the WNBA-Stats-API vs ESPN game_id namespace mismatch) were both
# considered and NOT tested empirically here for the same reason P4's report
# rejected travel_fatigue_metrics.rds: they cannot supply a real, non-
# fabricated per-game (or leakage-free per-season) feature without either
# inventing rows or accepting a same-season lookahead leak. Both are written
# up as ideas in docs/ML_IMPROVEMENT_IDEAS.md Part 1 with a concrete note on
# what real follow-up work would unblock them, rather than tested on shaky
# ground.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe tools/ml_feature_experiments.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(slider)
  library(Matrix)
})

set.seed(20260912)

# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("ml_feature_experiments.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
source("config.R")

WINDOW_SIZE_FOR_COMPARABILITY <- 13

cat("=====================================================================\n")
cat("STEP 0: Load real data\n")
cat("=====================================================================\n")
stopifnot(file.exists(CACHE_TEAM_BOX))
box_scores <- readRDS(CACHE_TEAM_BOX)
cat(sprintf("[data] box_scores_cache: %d real team-game rows, seasons %s\n",
            nrow(box_scores), paste(range(box_scores$season), collapse = "-")))

stopifnot(file.exists(file.path(CACHE_DIR, "wnba_pbp_cache.rds")))
pbp_cache <- readRDS(file.path(CACHE_DIR, "wnba_pbp_cache.rds"))
cat(sprintf("[data] wnba_pbp_cache: %d real possession rows, seasons %s (data_source: %s)\n",
            nrow(pbp_cache$possessions), paste(range(pbp_cache$possessions$season), collapse = "-"),
            pbp_cache$data_source))

# ------------------------------------------------------------------------------
# build_feature_df() -- copied VERBATIM from tools/ml_cv_benchmark.R (not
# altered in any way) so the box-score feature pipeline is byte-identical to
# the published baseline.
# ------------------------------------------------------------------------------
build_feature_df <- function(data, window_size = WINDOW_SIZE_FOR_COMPARABILITY, method = "reset") {
  if (method == "reset") {
    features <- data |>
      arrange(team_id, season, game_date) |>
      group_by(season, team_id) |>
      mutate(
        efg = (field_goals_made + 0.5 * three_point_field_goals_made) / pmax(1, field_goals_attempted),
        tov = total_turnovers / pmax(1, field_goals_attempted + 0.44 * free_throws_attempted + total_turnovers),
        ftr = free_throws_attempted / pmax(1, field_goals_attempted),
        ts  = team_score / pmax(1, 2 * (field_goals_attempted + 0.44 * free_throws_attempted)),

        roll_pts_scored = slide_dbl(team_score, mean, .before = window_size, .after = -1),
        roll_oreb       = slide_dbl(offensive_rebounds, mean, .before = window_size, .after = -1),
        roll_dreb       = slide_dbl(defensive_rebounds, mean, .before = window_size, .after = -1),
        roll_ast        = slide_dbl(assists, mean, .before = window_size, .after = -1),
        roll_stl        = slide_dbl(steals, mean, .before = window_size, .after = -1),
        roll_blk        = slide_dbl(blocks, mean, .before = window_size, .after = -1),
        # L-3: `total_turnovers` (not `turnovers`) is used for BOTH the four-factors `tov`
        # rate above and this rolling count. They are genuinely different cache columns
        # (total_turnovers ~= turnovers + team_turnovers; means 14.09 vs 13.17, not
        # identical), and previously this block mixed them for what reads as one concept.
        # `total_turnovers` wins deliberately: it is the column the paired four-factors
        # denominator already uses, and it is the full team-possession-ending count, so
        # diff_roll_tov and diff_roll_tovp now describe the same underlying quantity.
        # Kept byte-identical to tools/ml_cv_benchmark.R's copy of this block, as the
        # header above promises.
        roll_tov        = slide_dbl(total_turnovers, mean, .before = window_size, .after = -1),
        roll_efg        = slide_dbl(efg, mean, .before = window_size, .after = -1),
        roll_tovp       = slide_dbl(tov, mean, .before = window_size, .after = -1),
        roll_ftr        = slide_dbl(ftr, mean, .before = window_size, .after = -1),
        roll_ts         = slide_dbl(ts, mean, .before = window_size, .after = -1),
        days_rest       = pmin(REST_DAYS_CAP, coalesce(as.numeric(game_date - lag(game_date)), 3))
      ) |>
      ungroup()
  } else {
    stop("Only 'reset' is used by this benchmark (Rmd's real re-benchmark winner); other methods omitted here.")
  }

  features_selected <- features |>
    select(game_id, season, game_date, team_id, team_abbreviation, team_winner, team_home_away,
           roll_pts_scored, roll_oreb, roll_dreb, roll_ast, roll_stl, roll_blk,
           roll_tov, roll_efg, roll_tovp, roll_ftr, roll_ts, days_rest)

  home_df <- features_selected |>
    filter(team_home_away == "home") |>
    select(game_id, season, game_date, home_team = team_id, home_abbr = team_abbreviation,
           home_win = team_winner,
           home_roll_pts = roll_pts_scored, home_roll_oreb = roll_oreb, home_roll_dreb = roll_dreb,
           home_roll_ast = roll_ast, home_roll_stl = roll_stl, home_roll_blk = roll_blk,
           home_roll_tov = roll_tov, home_roll_efg = roll_efg, home_roll_tovp = roll_tovp,
           home_roll_ftr = roll_ftr, home_roll_ts = roll_ts, home_days_rest = days_rest)

  away_df <- features_selected |>
    filter(team_home_away == "away") |>
    select(game_id, away_team = team_id, away_abbr = team_abbreviation, away_win = team_winner,
           away_roll_pts = roll_pts_scored, away_roll_oreb = roll_oreb, away_roll_dreb = roll_dreb,
           away_roll_ast = roll_ast, away_roll_stl = roll_stl, away_roll_blk = roll_blk,
           away_roll_tov = roll_tov, away_roll_efg = roll_efg, away_roll_tovp = roll_tovp,
           away_roll_ftr = roll_ftr, away_roll_ts = roll_ts, away_days_rest = days_rest)

  model_df <- inner_join(home_df, away_df, by = "game_id") |>
    mutate(
      target_home_win = factor(if_else(home_win == TRUE, "Win", "Loss"), levels = c("Win", "Loss")),
      diff_roll_pts   = home_roll_pts - away_roll_pts,
      diff_roll_oreb  = home_roll_oreb - away_roll_oreb,
      diff_roll_dreb  = home_roll_dreb - away_roll_dreb,
      diff_roll_treb  = (home_roll_oreb + home_roll_dreb) - (away_roll_oreb + away_roll_dreb),
      diff_roll_ast   = home_roll_ast - away_roll_ast,
      diff_roll_stl   = home_roll_stl - away_roll_stl,
      diff_roll_blk   = home_roll_blk - away_roll_blk,
      diff_roll_tov   = home_roll_tov - away_roll_tov,
      diff_roll_efg   = home_roll_efg - away_roll_efg,
      diff_roll_tovp  = home_roll_tovp - away_roll_tovp,
      diff_roll_ftr   = home_roll_ftr - away_roll_ftr,
      diff_roll_ts    = home_roll_ts - away_roll_ts,
      diff_days_rest  = home_days_rest - away_days_rest
    ) |>
    drop_na()

  return(model_df)
}

# ------------------------------------------------------------------------------
# EXPERIMENT 3 ingredient: build_feature_df_ewma() -- identical to
# build_feature_df() above EXCEPT the rolling aggregator is an exponentially-
# weighted moving average (EWMA) of ALL prior in-season games (not a flat
# window), instead of slide_dbl's flat mean over the trailing `window_size`
# games. Same causal "no lookahead" guarantee (value at game t uses only
# games 1..t-1 of that team's season). alpha = 2/(N+1) with N = 13 to match
# ROLLING_WINDOW_SIZE's implied "span" for comparability (standard N-period
# EWMA <-> SMA span conversion).
# ------------------------------------------------------------------------------
ewma_prior <- function(x, alpha) {
  # Returns a vector the same length as x where element i is the EWMA of
  # x[1..(i-1)] (NA for i = 1, no prior history). Uses purrr::accumulate to
  # build the causal running EWMA, then shifts by one position.
  n <- length(x)
  if (n == 0) return(numeric(0))
  if (n == 1) return(NA_real_)
  cum <- purrr::accumulate(x, ~ alpha * .y + (1 - alpha) * .x)
  c(NA_real_, cum[-n])
}

build_feature_df_ewma <- function(data, alpha = 2 / (13 + 1), method = "reset") {
  if (method != "reset") stop("Only 'reset' supported here.")
  features <- data |>
    arrange(team_id, season, game_date) |>
    group_by(season, team_id) |>
    mutate(
      efg = (field_goals_made + 0.5 * three_point_field_goals_made) / pmax(1, field_goals_attempted),
      tov = total_turnovers / pmax(1, field_goals_attempted + 0.44 * free_throws_attempted + total_turnovers),
      ftr = free_throws_attempted / pmax(1, field_goals_attempted),
      ts  = team_score / pmax(1, 2 * (field_goals_attempted + 0.44 * free_throws_attempted)),

      roll_pts_scored = ewma_prior(team_score, alpha),
      roll_oreb       = ewma_prior(offensive_rebounds, alpha),
      roll_dreb       = ewma_prior(defensive_rebounds, alpha),
      roll_ast        = ewma_prior(assists, alpha),
      roll_stl        = ewma_prior(steals, alpha),
      roll_blk        = ewma_prior(blocks, alpha),
      # L-3: same deliberate `total_turnovers` choice as build_feature_df() above - this
      # EWMA variant is a methodology swap only, so it must aggregate the same column.
      roll_tov        = ewma_prior(total_turnovers, alpha),
      roll_efg        = ewma_prior(efg, alpha),
      roll_tovp       = ewma_prior(tov, alpha),
      roll_ftr        = ewma_prior(ftr, alpha),
      roll_ts         = ewma_prior(ts, alpha),
      days_rest       = pmin(REST_DAYS_CAP, coalesce(as.numeric(game_date - lag(game_date)), 3))
    ) |>
    ungroup()

  features_selected <- features |>
    select(game_id, season, game_date, team_id, team_abbreviation, team_winner, team_home_away,
           roll_pts_scored, roll_oreb, roll_dreb, roll_ast, roll_stl, roll_blk,
           roll_tov, roll_efg, roll_tovp, roll_ftr, roll_ts, days_rest)

  home_df <- features_selected |>
    filter(team_home_away == "home") |>
    select(game_id, season, game_date, home_team = team_id, home_abbr = team_abbreviation,
           home_win = team_winner,
           home_roll_pts = roll_pts_scored, home_roll_oreb = roll_oreb, home_roll_dreb = roll_dreb,
           home_roll_ast = roll_ast, home_roll_stl = roll_stl, home_roll_blk = roll_blk,
           home_roll_tov = roll_tov, home_roll_efg = roll_efg, home_roll_tovp = roll_tovp,
           home_roll_ftr = roll_ftr, home_roll_ts = roll_ts, home_days_rest = days_rest)

  away_df <- features_selected |>
    filter(team_home_away == "away") |>
    select(game_id, away_team = team_id, away_abbr = team_abbreviation, away_win = team_winner,
           away_roll_pts = roll_pts_scored, away_roll_oreb = roll_oreb, away_roll_dreb = roll_dreb,
           away_roll_ast = roll_ast, away_roll_stl = roll_stl, away_roll_blk = roll_blk,
           away_roll_tov = roll_tov, away_roll_efg = roll_efg, away_roll_tovp = roll_tovp,
           away_roll_ftr = roll_ftr, away_roll_ts = roll_ts, away_days_rest = days_rest)

  model_df <- inner_join(home_df, away_df, by = "game_id") |>
    mutate(
      target_home_win = factor(if_else(home_win == TRUE, "Win", "Loss"), levels = c("Win", "Loss")),
      diff_roll_pts   = home_roll_pts - away_roll_pts,
      diff_roll_oreb  = home_roll_oreb - away_roll_oreb,
      diff_roll_dreb  = home_roll_dreb - away_roll_dreb,
      diff_roll_treb  = (home_roll_oreb + home_roll_dreb) - (away_roll_oreb + away_roll_dreb),
      diff_roll_ast   = home_roll_ast - away_roll_ast,
      diff_roll_stl   = home_roll_stl - away_roll_stl,
      diff_roll_blk   = home_roll_blk - away_roll_blk,
      diff_roll_tov   = home_roll_tov - away_roll_tov,
      diff_roll_efg   = home_roll_efg - away_roll_efg,
      diff_roll_tovp  = home_roll_tovp - away_roll_tovp,
      diff_roll_ftr   = home_roll_ftr - away_roll_ftr,
      diff_roll_ts    = home_roll_ts - away_roll_ts,
      diff_days_rest  = home_days_rest - away_days_rest
    ) |>
    drop_na()

  return(model_df)
}

cat("\n=====================================================================\n")
cat("STEP 1: Fresh baseline (identical pipeline, window=13, method=reset)\n")
cat("=====================================================================\n")
model_df <- build_feature_df(box_scores, window_size = WINDOW_SIZE_FOR_COMPARABILITY, method = "reset")
cat(sprintf("[data] baseline model_df: %d real games, seasons %s\n",
            nrow(model_df), paste(range(model_df$season), collapse = "-")))
print(table(model_df$season))

# ------------------------------------------------------------------------------
# EXPERIMENT 1 ingredient: Elo-style continuously-updated team rating.
# Derived purely from box_scores_cache.rds's real game-by-game results (no
# new data source). Standard logistic Elo (K=20), no margin-of-victory
# multiplier (documented simplification -- see docs/ML_IMPROVEMENT_IDEAS.md
# for the 538-style MOV-adjusted Elo as a flagged future enhancement), no
# explicit home-court bump baked into the rating itself (mirrors how every
# other diff_ feature in this model has no explicit home-court term either --
# the downstream classifier can learn that from the overall base rate).
# Between-season carryover regresses 25% toward 1500 (standard practice,
# e.g. FiveThirtyEight's NBA Elo methodology: rating_new = 1505 + 0.75 *
# (rating_old - 1505); adapted here with 1500 as the neutral anchor).
# One elo_diff_pre value per unique game_id, computed causally (a team's
# rating going into game g reflects ONLY games strictly before g) --
# structurally zero look-ahead leakage, unlike a static/pooled rating.
# ------------------------------------------------------------------------------
cat("\n=====================================================================\n")
cat("STEP 2: Build Elo ratings (causal, game-by-game, K=20, 25% season regress)\n")
cat("=====================================================================\n")

games_chrono <- box_scores |>
  filter(team_home_away == "home") |>
  select(game_id, season, game_date, home_team = team_id, home_score = team_score,
         home_win = team_winner) |>
  inner_join(
    box_scores |> filter(team_home_away == "away") |>
      select(game_id, away_team = team_id, away_score = team_score),
    by = "game_id"
  ) |>
  arrange(game_date, game_id)

cat(sprintf("[elo] %d chronologically-ordered real games (%s to %s)\n",
            nrow(games_chrono), min(games_chrono$game_date), max(games_chrono$game_date)))

compute_elo <- function(games_chrono, k = 20, base = 1500, season_regress = 0.25) {
  team_ids <- unique(c(games_chrono$home_team, games_chrono$away_team))
  elo <- setNames(rep(base, length(team_ids)), as.character(team_ids))
  last_season <- setNames(rep(NA_integer_, length(team_ids)), as.character(team_ids))

  n <- nrow(games_chrono)
  elo_home_pre <- numeric(n)
  elo_away_pre <- numeric(n)

  for (i in seq_len(n)) {
    h <- as.character(games_chrono$home_team[i])
    a <- as.character(games_chrono$away_team[i])
    s <- games_chrono$season[i]

    # Between-season regression toward the mean, applied the first time a
    # team is seen in a new season (expansion teams simply start at `base`,
    # which is already the initial value, so no special-case needed).
    for (t in c(h, a)) {
      if (!is.na(last_season[[t]]) && last_season[[t]] != s) {
        elo[[t]] <- base + (1 - season_regress) * (elo[[t]] - base)
      }
      last_season[[t]] <- s
    }

    elo_home_pre[i] <- elo[[h]]
    elo_away_pre[i] <- elo[[a]]

    expected_home <- 1 / (1 + 10 ^ (-(elo[[h]] - elo[[a]]) / 400))
    actual_home <- if (isTRUE(games_chrono$home_win[i])) 1 else 0
    delta <- k * (actual_home - expected_home)
    elo[[h]] <- elo[[h]] + delta
    elo[[a]] <- elo[[a]] - delta
  }

  games_chrono |>
    mutate(elo_home_pre = elo_home_pre, elo_away_pre = elo_away_pre,
           diff_elo = elo_home_pre - elo_away_pre) |>
    select(game_id, diff_elo, elo_home_pre, elo_away_pre)
}

elo_table <- compute_elo(games_chrono)
cat(sprintf("[elo] built for %d games; diff_elo range [%.1f, %.1f], sd=%.1f\n",
            nrow(elo_table), min(elo_table$diff_elo), max(elo_table$diff_elo), sd(elo_table$diff_elo)))

model_df_elo <- model_df |>
  inner_join(elo_table, by = "game_id")
cat(sprintf("[elo] joined model_df: %d games (should equal baseline %d)\n",
            nrow(model_df_elo), nrow(model_df)))

# ------------------------------------------------------------------------------
# EXPERIMENT 2 ingredient: RAPM-derived team-strength differential,
# RE-SOLVED PER LOSO FOLD using only the fold's training-season possessions
# (cache/wnba_pbp_cache.rds, real data, already pulled by P2 -- no live
# network call here). This avoids the look-ahead leakage that would occur if
# the existing cache/rapm_ratings.rds (pooled across ALL 8 seasons, including
# whichever one LOSO holds out) were used directly as a static feature.
#
# solve_ridge_rapm() and the possession -> design-matrix construction are
# copied from rapm_engine.R's real (not synthetic) implementation, same
# lambda=900 (P2's grid-searched value, not re-tuned here to avoid
# introducing a second uncontrolled hyperparameter search on top of this
# experiment). Team-level rating = possession-count-weighted mean of
# `total_rapm` across a team's rostered players in that fold's training
# seasons (a team's "primary team" per player determined the same way
# rapm_engine.R does it: whichever team a player logged the most combined
# off/def possessions for, within the training-season subset only).
# ------------------------------------------------------------------------------
cat("\n=====================================================================\n")
cat("STEP 3: RAPM per-fold (leakage-free) team-strength ratings\n")
cat("=====================================================================\n")

TEAM_ID_MAP <- c(
  "1611661313" = "NY", "1611661317" = "PHX", "1611661319" = "LV", "1611661320" = "LA",
  "1611661321" = "DAL", "1611661322" = "WSH", "1611661323" = "CON", "1611661324" = "MIN",
  "1611661325" = "IND", "1611661327" = "POR", "1611661328" = "SEA", "1611661329" = "CHI",
  "1611661330" = "ATL", "1611661331" = "GS", "1611661332" = "TOR"
)

solve_ridge_rapm <- function(X, y, weights, lambda = 900) {
  W <- Diagonal(x = sqrt(weights))
  X_w <- W %*% X
  y_w <- W %*% y
  p_cols <- ncol(X)
  I_reg <- Diagonal(p_cols, lambda)
  XtX <- crossprod(X_w) + I_reg
  Xty <- crossprod(X_w, y_w)
  as.vector(solve(XtX, Xty))
}

compute_fold_team_rapm <- function(possessions_train, lambda = 900) {
  poss_clean <- possessions_train |>
    filter(
      !is.na(off_player_1), !is.na(off_player_2), !is.na(off_player_3),
      !is.na(off_player_4), !is.na(off_player_5),
      !is.na(def_player_1), !is.na(def_player_2), !is.na(def_player_3),
      !is.na(def_player_4), !is.na(def_player_5),
      !is.na(points), points >= 0, points <= 8
    )

  all_players <- sort(unique(c(
    poss_clean$off_player_1, poss_clean$off_player_2, poss_clean$off_player_3,
    poss_clean$off_player_4, poss_clean$off_player_5,
    poss_clean$def_player_1, poss_clean$def_player_2, poss_clean$def_player_3,
    poss_clean$def_player_4, poss_clean$def_player_5
  )))
  n_players <- length(all_players)
  player_idx <- setNames(seq_len(n_players), as.character(all_players))

  n_poss <- nrow(poss_clean)
  off_cols <- as.matrix(poss_clean |> select(off_player_1:off_player_5))
  def_cols <- as.matrix(poss_clean |> select(def_player_1:def_player_5))

  j_off <- matrix(player_idx[as.character(off_cols)], nrow = n_poss)
  j_def <- matrix(player_idx[as.character(def_cols)], nrow = n_poss) + n_players
  i_idx <- rep(seq_len(n_poss), 10)
  j_idx <- c(as.vector(j_off), as.vector(j_def))
  val_idx <- rep(1, n_poss * 10)

  X_sparse <- sparseMatrix(i = i_idx, j = j_idx, x = val_idx, dims = c(n_poss, 2 * n_players))

  # CENTRED RIDGE TARGET (GitHub issue #76). Mirrors the centring in
  # rapm_engine.R::build_possession_design_matrix(), which is the SOURCE OF TRUTH for the
  # design matrix and target: `league_ppp <- mean(poss_clean$points)` and
  # `y = poss_clean$points - league_ppp`. Without it the penalty parks league-average scoring
  # (~1.16 pts/possession over 10 players) inside every player coefficient, putting a shared
  # ~+7 pts/100 offset on both blocks. Kept in sync here by hand because this file deliberately
  # duplicates the fit to refit per CV train/test fold (same divergence #80 was about).
  # NO-OP FOR THIS SCRIPT'S OUTPUT: subtracting a constant from y shifts both blocks by the same
  # amount within a fold, and these fold ratings are consumed only as RELATIVE within-fold
  # features. Mirrored anyway so the two fits cannot silently diverge.
  league_ppp <- mean(poss_clean$points)
  coefs <- solve_ridge_rapm(X_sparse, poss_clean$points - league_ppp,
                            weights = rep(1, n_poss), lambda = lambda)

  # SIGN CONVENTION (GitHub issue #80). This file deliberately duplicates the ridge fit
  # rather than calling rapm_engine.R::fit_rapm_ratings(), because the CV experiment needs
  # to refit per train/test fold on a season subset. That duplication means the sign
  # convention has to be mirrored here by hand: negate the defensive coefficient block so
  # positive drapm == strong defender, and make total_rapm their SUM.
  # SOURCE OF TRUTH: rapm_engine.R::fit_rapm_ratings()'s "SIGN CONVENTION (GitHub issue
  # #79)" negation step — if that changes, change this with it. (No centring step here:
  # these fold ratings are consumed only as relative within-fold features by this script.)
  orapm <- coefs[1:n_players] * 100
  drapm <- -coefs[(n_players + 1):(2 * n_players)] * 100
  total_rapm <- orapm + drapm

  off_n <- as.integer(table(as.vector(off_cols))[as.character(all_players)])
  def_n <- as.integer(table(as.vector(def_cols))[as.character(all_players)])
  off_n[is.na(off_n)] <- 0L
  def_n[is.na(def_n)] <- 0L

  # Primary team per player (most combined off+def possessions for that team,
  # within this fold's training seasons only).
  off_votes <- poss_clean |>
    select(off_player_1:off_player_5, offense_team_id) |>
    pivot_longer(off_player_1:off_player_5, values_to = "player_id") |>
    count(player_id, offense_team_id, name = "n")
  def_votes <- poss_clean |>
    select(def_player_1:def_player_5, defense_team_id) |>
    pivot_longer(def_player_1:def_player_5, values_to = "player_id") |>
    count(player_id, defense_team_id, name = "n") |>
    rename(offense_team_id = defense_team_id)
  team_votes <- bind_rows(off_votes, def_votes) |>
    group_by(player_id, offense_team_id) |>
    summarise(n = sum(n), .groups = "drop") |>
    group_by(player_id) |>
    slice_max(n, n = 1, with_ties = FALSE) |>
    ungroup()

  primary_team_id <- setNames(team_votes$offense_team_id, as.character(team_votes$player_id))
  player_id_chr <- as.character(all_players)
  team_id_for_player <- unname(primary_team_id[player_id_chr])
  abbr <- unname(TEAM_ID_MAP[as.character(team_id_for_player)])

  player_tbl <- tibble(
    player_id = player_id_chr, total_rapm = total_rapm,
    n_poss = off_n + def_n, team_abbr = abbr
  ) |>
    filter(!is.na(team_abbr))

  # Team-level rating: possession-count-weighted mean of player total_rapm.
  player_tbl |>
    group_by(team_abbr) |>
    summarise(team_rapm = weighted.mean(total_rapm, w = pmax(1, n_poss)),
              n_players = n(), n_poss_total = sum(n_poss), .groups = "drop")
}

seasons_all <- sort(unique(model_df$season))
rapm_fold_ratings <- list()
for (s in seasons_all) {
  train_poss <- pbp_cache$possessions |> filter(season != s)
  rapm_fold_ratings[[as.character(s)]] <- compute_fold_team_rapm(train_poss) |>
    mutate(held_out_season = s)
  cat(sprintf("[rapm] fold held_out=%d: %d teams rated from %d training possessions\n",
              s, nrow(rapm_fold_ratings[[as.character(s)]]), nrow(train_poss)))
}
rapm_fold_table <- bind_rows(rapm_fold_ratings)
league_mean_rapm <- mean(rapm_fold_table$team_rapm)
cat(sprintf("[rapm] league-mean team_rapm across all folds (fallback value for unrated teams): %.3f\n", league_mean_rapm))

saveRDS(rapm_fold_table, file.path(CACHE_DIR, "rapm_fold_team_ratings.rds"))

# ------------------------------------------------------------------------------
# Model spec + drop_cols -- IDENTICAL to ml_cv_benchmark.R's winning
# architecture (RF/ranger, 250 trees), same recipe pattern (drop raw
# home_/away_ roll_ columns and raw days_rest, keep only diff_ columns +
# whatever new column(s) an experiment adds).
# ------------------------------------------------------------------------------
rf_spec <- rand_forest(trees = 250, mode = "classification") |>
  set_engine("ranger", importance = "impurity", num.threads = 4)

drop_cols_base <- c("game_id", "game_date", "season", "home_team", "away_team",
                     "home_abbr", "away_abbr", "home_win", "away_win",
                     "home_roll_ts", "home_roll_ftr", "home_roll_efg", "home_roll_pts", "home_roll_tovp",
                     "home_roll_oreb", "home_roll_dreb", "home_roll_ast", "home_roll_stl", "home_roll_blk", "home_roll_tov",
                     "away_roll_ts", "away_roll_ftr", "away_roll_efg", "away_roll_pts", "away_roll_tovp",
                     "away_roll_oreb", "away_roll_dreb", "away_roll_ast", "away_roll_stl", "away_roll_blk", "away_roll_tov",
                     "home_days_rest", "away_days_rest",
                     "elo_home_pre", "elo_away_pre")  # keep diff_elo, drop the raw pre-game levels

make_recipe <- function(train_data) {
  recipe(target_home_win ~ ., data = train_data) |>
    step_rm(all_of(intersect(drop_cols_base, names(train_data)))) |>
    step_normalize(all_numeric_predictors())
}

fit_and_eval_fold <- function(train_data, test_data) {
  rec <- make_recipe(train_data)
  wf <- workflow() |> add_recipe(rec) |> add_model(rf_spec)
  fit_m <- fit(wf, train_data)
  predict(fit_m, test_data) |>
    bind_cols(predict(fit_m, test_data, type = "prob")) |>
    bind_cols(test_data |> select(game_id, season, target_home_win))
}

metrics_for <- function(preds) {
  tibble(
    accuracy  = accuracy(preds, truth = target_home_win, estimate = .pred_class)$.estimate,
    precision = precision(preds, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
    recall    = recall(preds, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
    f1        = f_meas(preds, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
    roc_auc   = roc_auc(preds, truth = target_home_win, .pred_Win, event_level = "first")$.estimate
  )
}

# Generic LOSO runner for STATIC (precomputed once) feature sets -- used for
# baseline, +elo, and the EWMA methodology swap. Matches ml_cv_benchmark.R's
# run_loso() logic exactly.
run_loso <- function(df, label) {
  seasons <- sort(unique(df$season))
  fold_results <- list(); oof_preds <- list()
  for (s in seasons) {
    train_data <- df |> filter(season != s)
    test_data  <- df |> filter(season == s)
    if (nrow(test_data) < 10) { cat(sprintf("[%s] season %d: only %d rows, skipping\n", label, s, nrow(test_data))); next }
    preds <- fit_and_eval_fold(train_data, test_data)
    m <- metrics_for(preds)
    fold_results[[as.character(s)]] <- tibble(season = s, n = nrow(test_data)) |> bind_cols(m)
    oof_preds[[as.character(s)]] <- preds
    cat(sprintf("[%s] fold season=%d n=%d acc=%.4f auc=%.4f\n", label, s, nrow(test_data), m$accuracy, m$roc_auc))
  }
  list(fold_table = bind_rows(fold_results), oof_table = bind_rows(oof_preds))
}

# LOSO runner for the RAPM experiment -- team_rapm is re-solved per fold
# (train seasons only) so it must be joined in fold-by-fold, not once
# up-front. Unrated teams (e.g. an expansion team entirely absent from a
# fold's training seasons) fall back to the league-mean team_rapm across all
# folds, flagged via n_players_home/away == 0 -- a documented, non-fabricated
# fallback (same spirit as roster_bottom_up_engine.R's replacement-level
# default for unmatched players), not a silent drop of those games.
run_loso_rapm <- function(df, rapm_fold_table, league_mean) {
  seasons <- sort(unique(df$season))
  fold_results <- list(); oof_preds <- list()
  for (s in seasons) {
    ratings_s <- rapm_fold_table |> filter(held_out_season == s) |> select(team_abbr, team_rapm)
    df_s <- df |>
      left_join(ratings_s |> rename(home_abbr = team_abbr, home_team_rapm = team_rapm), by = "home_abbr") |>
      left_join(ratings_s |> rename(away_abbr = team_abbr, away_team_rapm = team_rapm), by = "away_abbr") |>
      mutate(
        home_team_rapm = coalesce(home_team_rapm, league_mean),
        away_team_rapm = coalesce(away_team_rapm, league_mean),
        diff_team_rapm = home_team_rapm - away_team_rapm
      ) |>
      select(-home_team_rapm, -away_team_rapm)

    train_data <- df_s |> filter(season != s)
    test_data  <- df_s |> filter(season == s)
    if (nrow(test_data) < 10) { cat(sprintf("[rapm] season %d: only %d rows, skipping\n", s, nrow(test_data))); next }
    preds <- fit_and_eval_fold(train_data, test_data)
    m <- metrics_for(preds)
    fold_results[[as.character(s)]] <- tibble(season = s, n = nrow(test_data)) |> bind_cols(m)
    oof_preds[[as.character(s)]] <- preds
    cat(sprintf("[rapm] fold season=%d n=%d acc=%.4f auc=%.4f\n", s, nrow(test_data), m$accuracy, m$roc_auc))
  }
  list(fold_table = bind_rows(fold_results), oof_table = bind_rows(oof_preds))
}

bootstrap_ci <- function(oof_table, n_boot = 2000, seed = 20260912) {
  set.seed(seed)
  n <- nrow(oof_table)
  point <- metrics_for(oof_table)
  boot_draws <- map_dfr(1:n_boot, function(i) metrics_for(oof_table[sample.int(n, n, replace = TRUE), ]))
  map_dfr(names(point), function(m) {
    vals <- boot_draws[[m]]
    tibble(metric = m, estimate = point[[m]], ci_lo = quantile(vals, 0.025, na.rm = TRUE), ci_hi = quantile(vals, 0.975, na.rm = TRUE))
  })
}

cat("\n=====================================================================\n")
cat("RUN: Fresh baseline LOSO CV\n")
cat("=====================================================================\n")
baseline_loso <- run_loso(model_df, "baseline")
baseline_ci <- bootstrap_ci(baseline_loso$oof_table)
cat("-- Baseline pooled CI --\n"); print(baseline_ci)

cat("\n=====================================================================\n")
cat("RUN: Experiment 1 -- + Elo differential\n")
cat("=====================================================================\n")
elo_loso <- run_loso(model_df_elo, "elo")
elo_ci <- bootstrap_ci(elo_loso$oof_table)
cat("-- +Elo pooled CI --\n"); print(elo_ci)

cat("\n=====================================================================\n")
cat("RUN: Experiment 2 -- + RAPM differential (per-fold, leakage-free)\n")
cat("=====================================================================\n")
rapm_loso <- run_loso_rapm(model_df, rapm_fold_table, league_mean_rapm)
rapm_ci <- bootstrap_ci(rapm_loso$oof_table)
cat("-- +RAPM pooled CI --\n"); print(rapm_ci)

cat("\n=====================================================================\n")
cat("RUN: Experiment 3 -- EWMA recency-weighted rolling averages (swap)\n")
cat("=====================================================================\n")
model_df_ewma <- build_feature_df_ewma(box_scores, alpha = 2 / (13 + 1), method = "reset")
cat(sprintf("[ewma] model_df: %d real games (baseline had %d)\n", nrow(model_df_ewma), nrow(model_df)))
print(table(model_df_ewma$season))
ewma_loso <- run_loso(model_df_ewma, "ewma")
ewma_ci <- bootstrap_ci(ewma_loso$oof_table)
cat("-- EWMA pooled CI --\n"); print(ewma_ci)

# ------------------------------------------------------------------------------
# Summary table + save
# ------------------------------------------------------------------------------
cat("\n=====================================================================\n")
cat("SUMMARY (pooled out-of-fold, bootstrap 95% CI, n_boot=2000)\n")
cat("=====================================================================\n")
summarize_run <- function(ci_table, label, n) {
  acc <- ci_table |> filter(metric == "accuracy")
  auc <- ci_table |> filter(metric == "roc_auc")
  cat(sprintf("%-30s n=%4d  Accuracy %.4f [%.4f, %.4f]   ROC-AUC %.4f [%.4f, %.4f]\n",
              label, n, acc$estimate, acc$ci_lo, acc$ci_hi, auc$estimate, auc$ci_lo, auc$ci_hi))
}
summarize_run(baseline_ci, "Baseline (fresh, window=13)", nrow(baseline_loso$oof_table))
summarize_run(elo_ci, "+ Elo differential", nrow(elo_loso$oof_table))
summarize_run(rapm_ci, "+ RAPM differential (fold-safe)", nrow(rapm_loso$oof_table))
summarize_run(ewma_ci, "EWMA rolling (vs flat window)", nrow(ewma_loso$oof_table))

saveRDS(list(
  baseline_fold_table = baseline_loso$fold_table, baseline_oof_table = baseline_loso$oof_table, baseline_ci = baseline_ci,
  elo_fold_table = elo_loso$fold_table, elo_oof_table = elo_loso$oof_table, elo_ci = elo_ci,
  rapm_fold_table_model = rapm_loso$fold_table, rapm_oof_table = rapm_loso$oof_table, rapm_ci = rapm_ci,
  ewma_fold_table = ewma_loso$fold_table, ewma_oof_table = ewma_loso$oof_table, ewma_ci = ewma_ci,
  rapm_team_ratings_by_fold = rapm_fold_table
), file.path(CACHE_DIR, "ml_feature_experiments_results.rds"))

cat("\n[done] Saved cache/ml_feature_experiments_results.rds\n")
