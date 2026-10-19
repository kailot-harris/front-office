# ==============================================================================
# QB-Injury/Backup-Starter Rating Penalty - Empirical Derivation (Phase 1)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/derive_qb_injury_penalty.R
#
# Precedent: tools/derive_nfl_constants.R (one-off, documented derivation script that
# prints the final value(s) for config.R rather than writing config.R itself). This
# script derives QB_INJURY_RATING_PENALTY_PTS: how many rating points (same point-
# margin scale as compute_power_rating_points()'s output) to subtract from a team's
# power rating when its "primary" QB (per tools/qb_injury_features.R's depth-chart-
# based, no-lookahead definition) is NOT the QB who actually started that week.
#
# METHOD: walk-forward, out-of-sample, optimizer-driven (stats::optimize(), not a
# grid search) - same discipline as tools/backtest_shrinkage_optimizer.R. For each
# candidate penalty value P, adjust every walk-forward game's baseline projected
# margin by -P for the home team's own backup-QB games and +P for the away team's
# backup-QB games (a backup-starting team is worse, which helps its opponent's
# relative margin), then score Brier vs. real outcomes. Games with an unknown
# backup-QB flag (e.g. depth-chart data gaps) get zero adjustment, not a guessed
# default - they simply don't move the optimizer's objective for that game.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_qb_injury_penalty.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(nflreadr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_qb_injury_penalty.R"

source("team_ratings_engine.R")   # -> compute_power_rating_points()
source("tools/backtest_common.R") # -> build_walkforward_games()
source("tools/qb_injury_features.R")

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

CALIBRATION_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("QB-injury/backup-starter rating penalty derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

cat("Building walk-forward game table (seasons", min(CALIBRATION_SEASONS), "-", max(CALIBRATION_SEASONS), ")...\n")
games <- build_walkforward_games(epa, completed, CALIBRATION_SEASONS, avg_plays_per_game)
cat(sprintf("Built %d walk-forward games.\n", nrow(games)))

cat("Fetching real depth-chart data (nflreadr::load_depth_charts) - includes one extra prior\n")
cat("season for the primary-QB fallback window (see tools/qb_injury_features.R)...\n")
starter_tbl <- get_qb_starter_table((MODERN_ERA_START_SEASON):(CURRENT_SEASON - 1L))
flags <- compute_qb_backup_flags(starter_tbl) |>
  select(season, week, team, qb_backup_started)

games <- games |>
  left_join(flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team"))

n_home_backup <- sum(games$home_qb_backup, na.rm = TRUE)
n_away_backup <- sum(games$away_qb_backup, na.rm = TRUE)
n_unknown <- sum(is.na(games$home_qb_backup) | is.na(games$away_qb_backup))
cat(sprintf("Backup-QB games: home=%d, away=%d (of %d total; %d games have an unknown flag and get zero adjustment).\n\n",
            n_home_backup, n_away_backup, nrow(games), n_unknown))

# ------------------------------------------------------------------------------------------
# Baseline projected margin at the production K (RATING_SHRINKAGE_GAMES_K) - identical blend
# formula to team_ratings_engine.R/backtest_shrinkage_optimizer.R, never a second copy.
# ------------------------------------------------------------------------------------------
k <- RATING_SHRINKAGE_GAMES_K
home_w <- games$home_gp / (games$home_gp + k)
away_w <- games$away_gp / (games$away_gp + k)
home_rating <- home_w * games$home_raw + (1 - home_w) * games$home_prior
away_rating <- away_w * games$away_raw + (1 - away_w) * games$away_prior
games$baseline_margin <- (home_rating - away_rating) + NFL_HCA

home_adj <- ifelse(is.na(games$home_qb_backup), 0, as.integer(games$home_qb_backup))
away_adj <- ifelse(is.na(games$away_qb_backup), 0, as.integer(games$away_qb_backup))

brier_for_penalty <- function(pen) {
  margin <- games$baseline_margin - pen * home_adj + pen * away_adj
  prob   <- pnorm(margin / NFL_MARGIN_SIGMA)
  mean((prob - games$home_win)^2)
}

brier_baseline <- brier_for_penalty(0)
cat("Optimizing QB_INJURY_RATING_PENALTY_PTS via stats::optimize() (bounded [0, 15])...\n")
opt <- optimize(brier_for_penalty, interval = c(0, 15), tol = 1e-3)

cat(sprintf("  No adjustment (penalty=0):        Brier = %.6f\n", brier_baseline))
cat(sprintf("  Optimizer result: penalty=%.2f pts -> Brier = %.6f\n", opt$minimum, opt$objective))
cat(sprintf("\nRECOMMENDATION for config.R: QB_INJURY_RATING_PENALTY_PTS <- %.1f\n", round(opt$minimum, 1)))
cat(sprintf("(derived from %d walk-forward games, seasons %d-%d, %d/%d with a known backup-QB flag)\n",
            nrow(games), min(CALIBRATION_SEASONS), max(CALIBRATION_SEASONS), nrow(games) - n_unknown, nrow(games)))

out <- list(
  run_at = Sys.time(),
  n_games = nrow(games),
  n_home_backup = n_home_backup, n_away_backup = n_away_backup, n_unknown = n_unknown,
  brier_baseline = brier_baseline,
  penalty_optimal = opt$minimum, brier_optimal = opt$objective
)
saveRDS(out, file.path(CACHE_DIR, "qb_injury_penalty_derivation.rds"))
cat("\nSaved derivation output to cache/qb_injury_penalty_derivation.rds\n")
