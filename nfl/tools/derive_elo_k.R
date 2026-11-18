# ==============================================================================
# Elo K-Factor - Empirical Derivation (Phase 3)
# Path: tools/derive_elo_k.R
#
# Precedent: tools/derive_market_blend_weight.R / tools/derive_qb_injury_penalty.R.
# Derives ELO_K_FACTOR (tools/elo_model.R's rating-update sensitivity) via
# stats::optimize() (golden-section search, not a grid search) minimizing walk-forward
# Brier score. ELO_HCA_POINTS/ELO_MOV_C/ELO_POINTS_PER_MARGIN_PT are NOT derived here -
# see tools/elo_model.R's header for why those three stay literature-reference values
# (a documented deviation from this repo's usual derive-everything discipline, not an
# oversight).
#
# 2002 (MODERN_ERA_START_SEASON) is used as Elo's own "burn-in" season - every team
# starts at ELO_INITIAL_RATING with zero real history, so 2002's predictions are not
# scored (same role 2002 already plays for RATING_SHRINKAGE_GAMES_K's prior-season
# fallback). Scoring window: 2003-CURRENT_SEASON-1.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_elo_k.R
# ==============================================================================

PROJECT_DIR <- local({
  # Repo root: NFL_PROJECT_DIR if set, else this script's parent directory (it lives in
  # tools/), else the working directory if it holds config.R. No hard-coded fallback.
  env_root <- Sys.getenv("NFL_PROJECT_DIR", "")
  f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  f <- gsub("~+~", " ", f, fixed = TRUE)
  script_root <- if (length(f) == 1L) {
    dirname(dirname(normalizePath(f, winslash = "/", mustWork = FALSE)))
  } else ""
  root <- if (nzchar(env_root)) {
    env_root
  } else if (nzchar(script_root) && file.exists(file.path(script_root, "config.R"))) {
    script_root
  } else if (file.exists("config.R")) {
    getwd()
  } else {
    stop("Cannot locate the NFL Analytics project root: set NFL_PROJECT_DIR or run from the repo root.")
  }
  normalizePath(root, winslash = "/", mustWork = FALSE)
})
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/derive_elo_k.R"

source("tools/elo_model.R")

if (!file.exists(CACHE_SCHEDULES) || !file.exists(CACHE_FATIGUE_METRICS)) {
  stop("CACHE_SCHEDULES / CACHE_FATIGUE_METRICS missing - run the ingest and fatigue stages first.")
}

sch <- readRDS(CACHE_SCHEDULES) |> mutate(gameday = as.Date(gameday))
fatigue <- readRDS(CACHE_FATIGUE_METRICS)

sch_completed <- sch |>
  filter(!is.na(home_score), !is.na(away_score),
         season >= MODERN_ERA_START_SEASON, season <= CURRENT_SEASON - 1L)

SCORE_SEASONS <- (MODERN_ERA_START_SEASON + 1L):(CURRENT_SEASON - 1L)

cat("==============================================================\n")
cat("Elo K-factor derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")
cat(sprintf("Simulating Elo sequentially across %d games (seasons %d-%d, %d burn-in)...\n",
            nrow(sch_completed), MODERN_ERA_START_SEASON, CURRENT_SEASON - 1L, MODERN_ERA_START_SEASON))

brier_for_k <- function(k) {
  res <- run_elo_walkforward(sch_completed, fatigue, k)
  scored <- res |> filter(season %in% SCORE_SEASONS)
  mean((scored$home_win_prob - scored$home_win)^2)
}

cat("Optimizing ELO_K_FACTOR via stats::optimize() (bounded [2, 60])...\n")
opt <- optimize(brier_for_k, interval = c(2, 60), tol = 0.5)

cat(sprintf("  Optimizer result: K=%.2f -> Brier = %.6f\n", opt$minimum, opt$objective))
cat(sprintf("\nRECOMMENDATION for config.R: ELO_K_FACTOR <- %.0f\n", round(opt$minimum)))

out <- list(run_at = Sys.time(), n_games_scored = sum(sch_completed$season %in% SCORE_SEASONS),
            k_optimal = opt$minimum, brier_optimal = opt$objective)
saveRDS(out, file.path(CACHE_DIR, "elo_k_derivation.rds"))
cat("\nSaved derivation output to cache/elo_k_derivation.rds\n")
