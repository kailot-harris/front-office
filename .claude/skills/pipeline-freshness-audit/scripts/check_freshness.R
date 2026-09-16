# Pipeline Freshness Audit
#
# Mechanical half of the pipeline-freshness-audit skill. Checks that every stage's declared
# output cache in run_full_pipeline.R actually advanced its mtime past a given run-start
# timestamp -- the check that would have caught the silent no-op stages (sys.nframe() == 0 guard
# bug) immediately instead of relying on someone noticing an anomalously fast stage.
#
# Usage: Rscript.exe check_freshness.R "2026-09-16 16:00:00"

PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_ROOT)
source("config.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript.exe check_freshness.R \"YYYY-MM-DD HH:MM:SS\"")
}
run_start <- as.POSIXct(args[1], tz = Sys.timezone())
if (is.na(run_start)) stop("Could not parse run-start timestamp: ", args[1])

# Keep this manifest in sync with run_full_pipeline.R's `output = ` arguments. See SKILL.md's
# table for the authoritative source-of-truth cross-reference.
manifest <- list(
  list(stage = "sync_rosters.R",           outputs = file.path(CACHE_DIR, "active_rosters_cache.rds")),
  list(stage = "injury_scraper.R",         outputs = CACHE_INJURY_DATA),
  list(stage = "team_embeddings.py",       outputs = "logs/analytics.duckdb"),
  list(stage = "shot_quality_engine.R",    outputs = "cache/team_shot_quality.rds"),
  list(stage = "fatigue_travel_engine.R",  outputs = "cache/travel_fatigue_metrics.rds"),
  list(stage = "rapm_engine.R",            outputs = "cache/rapm_ratings.rds"),
  list(stage = "roster_bottom_up_engine.R",outputs = "cache/projected_wnba_standings.rds"),
  list(stage = "market_odds_engine.R",     outputs = file.path(CACHE_DIR, c("latest_value_bets.rds", "odds_history.rds"))),
  list(stage = "player_props_engine.R",    outputs = CACHE_PLAYER_PROPS),
  list(stage = "copula_props_engine.R",    outputs = "cache/copula_wilson_pra.rds"),
  list(stage = "playoff_simulator.R",      outputs = "cache/playoff_series_wnba_demo.rds"),
  list(stage = "risk_management_engine.R", outputs = "cache/risk_state.rds"),
  list(stage = "bet_tracker.r",            outputs = file.path(CACHE_DIR, "rolling_bet_metrics.rds"))
)

cat(sprintf("Freshness audit: run start = %s\n\n", format(run_start)))

n_fresh <- 0L
n_stale <- 0L
n_missing <- 0L

for (m in manifest) {
  for (path in m$outputs) {
    if (!file.exists(path)) {
      cat(sprintf("[MISSING] %-28s %s\n", m$stage, path))
      n_missing <- n_missing + 1L
      next
    }
    mt <- file.info(path)$mtime
    if (mt >= run_start) {
      cat(sprintf("[FRESH]   %-28s %s (mtime %s)\n", m$stage, path, format(mt)))
      n_fresh <- n_fresh + 1L
    } else {
      cat(sprintf("[STALE]   %-28s %s (mtime %s, before run start)\n", m$stage, path, format(mt)))
      n_stale <- n_stale + 1L
    }
  }
}

cat(sprintf("\n%d fresh, %d stale, %d missing.\n", n_fresh, n_stale, n_missing))
if (n_stale > 0 || n_missing > 0) {
  cat(paste(
    "\nVERDICT: one or more stages did not demonstrably regenerate their output during this run.",
    "Do not trust downstream numbers from a stale/missing stage until investigated -- check",
    "whether the stage legitimately had nothing new to do (e.g. incremental ingestion) versus",
    "silently failing to execute (e.g. an invocation-guard bug).\n"
  ))
} else {
  cat("\nVERDICT: all declared stage outputs advanced during this run.\n")
}
