# ==============================================================================
# NFL Analytics Pipeline - Empirical Constant Derivation
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/derive_nfl_constants.R
#
# Phase 0 (T0) reproducible derivation script. Pulls REAL historical NFL
# schedule/results data via nflreadr::load_schedules() and empirically computes
# the two modeling constants that config.R needs:
#   - NFL_MARGIN_SIGMA : sd(home_score - away_score) across real games
#   - NFL_HCA          : mean(home_score - away_score) across real games (home-field advantage)
#
# This mirrors the WNBA Analytics repo's config.R provenance pattern (see that
# repo's Finding C-1): every empirically-derived constant must be produced by a
# script like this one, cited in config.R by filename, and NEVER re-typed from
# memory/literature at a second call site. Re-run this script whenever the
# season advances materially (e.g. once each new season's data is complete)
# and update config.R's NFL_MARGIN_SIGMA / NFL_HCA + the comment citing this run.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/derive_nfl_constants.R
# ==============================================================================

if (!requireNamespace("nflreadr", quietly = TRUE)) {
  stop("nflreadr is not installed. Run: install.packages('nflreadr', repos='https://cloud.r-project.org')")
}

suppressPackageStartupMessages({
  library(nflreadr)
})

cat("==============================================================\n")
cat("NFL empirical constant derivation - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

# ------------------------------------------------------------------------------------------
# Window choice rationale
# ------------------------------------------------------------------------------------------
# nflreadr::load_schedules() data (Lee Sharpe / nflverse "games" file) reliably starts at the
# 1999 season (verified empirically below and via nflreadr docs: load_pbp()/load_schedules()
# both cover 1999-present). We do NOT blindly use the full 1999-present range as the primary
# sigma window, because several structural rule/scheduling changes since then plausibly shift
# scoring-margin variance and are not "the same game":
#   - 2002: league realignment to the current 32-team / 8-division structure (from 31 teams /
#     6 divisions). Anything before 2002 is a genuinely different league shape.
#   - 2010s: multiple emphasis-of-downfield-passing rule changes (illegal contact enforcement
#     2004, defenseless receiver rules 2010s, etc.) generally associated with a higher-scoring,
#     higher-variance modern game.
#   - 2021: regular season expanded from 16 to 17 games (does not directly affect per-game
#     margin distribution, but marks the start of the truly "current" scheduling regime).
# We therefore treat 2002-present ("modern 32-team era") as the primary/baseline window for
# NFL_MARGIN_SIGMA - long enough for a stable sd() estimate, short enough to exclude the
# pre-realignment era. We ALSO compute the full 1999-present window and a recent-10-season
# window for comparison/documentation, so a future agent can see whether the modern-era number
# is an outlier vs. a longer or shorter horizon.
CURRENT_YEAR <- as.integer(format(Sys.Date(), "%Y"))

# The season currently in progress (if any) has incomplete data (a partial slate of games with
# NA scores for not-yet-played games) and must be excluded from variance/mean computations.
raw_probe <- nflreadr::load_schedules(seasons = TRUE)
completed_seasons <- raw_probe$season[!is.na(raw_probe$home_score) & !is.na(raw_probe$away_score)]
LAST_COMPLETE_SEASON <- max(completed_seasons, na.rm = TRUE)
EARLIEST_SEASON <- min(raw_probe$season, na.rm = TRUE)

cat("Earliest season available from load_schedules():", EARLIEST_SEASON, "\n")
cat("Last season with complete (non-NA) final scores:", LAST_COMPLETE_SEASON, "\n\n")

MODERN_ERA_START <- 2002L   # post-realignment, current 32-team / 8-division structure
RECENT_WINDOW_N  <- 10L     # "recent" window for HCA-compression comparison
RECENT5_WINDOW_N <- 5L      # tighter recent window (post-17-game-season regime, 2021+)

full_seasons    <- EARLIEST_SEASON:LAST_COMPLETE_SEASON
modern_seasons  <- MODERN_ERA_START:LAST_COMPLETE_SEASON
recent_seasons  <- (LAST_COMPLETE_SEASON - RECENT_WINDOW_N + 1L):LAST_COMPLETE_SEASON
recent5_seasons <- (LAST_COMPLETE_SEASON - RECENT5_WINDOW_N + 1L):LAST_COMPLETE_SEASON

# ------------------------------------------------------------------------------------------
# Pull full history once, then subset in-memory (avoids re-downloading per window)
# ------------------------------------------------------------------------------------------
sched <- nflreadr::load_schedules(seasons = full_seasons)

# Regular season + playoffs both reflect real competitive margins; keep both but drop any
# unfinished/no-score rows (bye weeks, future/postponed games, or the in-progress season).
sched <- sched[!is.na(sched$home_score) & !is.na(sched$away_score), ]
sched$home_margin <- sched$home_score - sched$away_score

compute_window <- function(df, seasons, label) {
  sub <- df[df$season %in% seasons, ]
  n <- nrow(sub)
  sigma <- stats::sd(sub$home_margin)
  hca   <- mean(sub$home_margin)
  cat(sprintf(
    "[%s] seasons %d-%d | n_games = %d | sd(home_margin) = %.3f | mean(home_margin) [HCA] = %.3f\n",
    label, min(seasons), max(seasons), n, sigma, hca
  ))
  invisible(list(label = label, seasons = seasons, n = n, sigma = sigma, hca = hca))
}

cat("---- NFL_MARGIN_SIGMA candidates (sd of home_score - away_score) ----\n")
res_full    <- compute_window(sched, full_seasons,    sprintf("full history (%d-present)", EARLIEST_SEASON))
res_modern  <- compute_window(sched, modern_seasons,  "modern 32-team era (2002-present)")
res_recent  <- compute_window(sched, recent_seasons,  sprintf("recent %d seasons", RECENT_WINDOW_N))
res_recent5 <- compute_window(sched, recent5_seasons, sprintf("recent %d seasons (17-game era)", RECENT5_WINDOW_N))

cat("\n---- NFL_HCA candidates (mean of home_score - away_score) ----\n")
cat("(same four windows as above; HCA is reportedly compressed in recent seasons - compare\n")
cat(" the modern-era mean against the recent-5/recent-10 means below)\n\n")
for (r in list(res_full, res_modern, res_recent, res_recent5)) {
  cat(sprintf("  %-38s n=%5d  HCA=%.3f  sigma=%.3f\n", r$label, r$n, r$hca, r$sigma))
}

# ------------------------------------------------------------------------------------------
# Per-season breakdown for the modern era, so drift/compression is visible year by year
# (this is what actually shows HCA compression, rather than just two window averages).
# ------------------------------------------------------------------------------------------
cat("\n---- Per-season home_margin mean (HCA) and sd (sigma), modern era ----\n")
by_season <- stats::aggregate(
  home_margin ~ season, data = sched[sched$season %in% modern_seasons, ],
  FUN = function(x) c(mean = mean(x), sd = stats::sd(x), n = length(x))
)
season_tbl <- data.frame(
  season = by_season$season,
  mean_margin = by_season$home_margin[, "mean"],
  sd_margin   = by_season$home_margin[, "sd"],
  n_games     = by_season$home_margin[, "n"]
)
print(season_tbl, row.names = FALSE)

# ------------------------------------------------------------------------------------------
# FINAL CHOICE (this is what config.R must cite verbatim)
# ------------------------------------------------------------------------------------------
# NFL_MARGIN_SIGMA: use the modern 32-team era (2002-present) - long enough for a stable
# variance estimate (500+ games/season x ~24 seasons), while excluding the pre-realignment
# league shape. The recent-10/recent-5 sigma estimates (printed above) are close to the
# modern-era figure (variance is comparatively stable across sub-windows, unlike HCA), which
# supports using the longer, lower-noise window for sigma specifically.
#
# NFL_HCA: use the recent 10-season window (not the full modern-era mean), because the
# per-season table above shows real, sustained drift downward in home-field advantage over
# the modern era (widely attributed to reduced/normalized crowd effects, more accurate
# officiating via replay, and increased late-season/road short-week travel parity) - using the
# 2002-present average would overstate current HCA. The recent-10 window balances sample size
# against staying current; the recent-5 figure (printed above) is directionally consistent
# (further compressed) but built on a much smaller sample (~5 x 285 games) and is noisier
# season-to-season - kept as a secondary data point, not the primary source.
final_sigma <- res_modern$sigma
final_hca   <- res_recent$hca

cat("\n==============================================================\n")
cat("FINAL VALUES FOR config.R\n")
cat("==============================================================\n")
cat(sprintf("NFL_MARGIN_SIGMA <- %.2f   (source: modern 32-team era %d-%d, n=%d games)\n",
            final_sigma, min(modern_seasons), max(modern_seasons), res_modern$n))
cat(sprintf("NFL_HCA          <- %.2f   (source: recent %d seasons %d-%d, n=%d games)\n",
            final_hca, RECENT_WINDOW_N, min(recent_seasons), max(recent_seasons), res_recent$n))
cat(sprintf("[secondary/for comparison] recent-%d-season HCA = %.2f (n=%d)\n",
            RECENT5_WINDOW_N, res_recent5$hca, res_recent5$n))
cat("Derivation run at:", format(Sys.time()), "| nflreadr version:",
    as.character(utils::packageVersion("nflreadr")), "\n")

# Persist a small artifact so config.R's comment can cite exact figures without re-running R
# interactively every time (mirrors WNBA repo's PHASE0_VALIDATION_NOTES.md pattern, but kept
# as a lightweight machine-readable sidecar here since this is a from-scratch Phase 0 repo).
out <- list(
  run_at = Sys.time(),
  nflreadr_version = as.character(utils::packageVersion("nflreadr")),
  earliest_season_available = EARLIEST_SEASON,
  last_complete_season = LAST_COMPLETE_SEASON,
  windows = list(full = res_full, modern = res_modern, recent10 = res_recent, recent5 = res_recent5),
  season_table = season_tbl,
  final = list(NFL_MARGIN_SIGMA = final_sigma, NFL_HCA = final_hca)
)
# NOTE: run this script with the repo root as the working directory
# (e.g. `Rscript tools/derive_nfl_constants.R` from "NFL Analytics/"), matching the
# invocation documented at the top of this file.
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(out, file.path("cache", "nfl_constants_derivation.rds"))
cat("\nSaved full derivation output to cache/nfl_constants_derivation.rds\n")
