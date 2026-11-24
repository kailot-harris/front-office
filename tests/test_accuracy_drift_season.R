# ==============================================================================
# tests/test_accuracy_drift_season.R
# Regression tests for NBA_analytics#225:
#   - 2026-27 LOGGED_PREGAME forecasts carry consistent season = 2027L
#   - accuracy_governance.R .diag_block normalizes mixed 2026/2027 season labels
#     for 2026-10-20+ into a single 2027 tile without dropping rows
#   - normalize_prediction_log_seasons() repairs existing mixed-label rows
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

REPO_ROOT <- normalizePath(".", winslash = "/", mustWork = TRUE)

checks   <- 0L
failures <- 0L
ok <- function(desc, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", desc))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", desc))
  }
}

Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")

cfg_env <- new.env(parent = .GlobalEnv)
source(file.path(REPO_ROOT, "config.R"), local = cfg_env)

gov_env <- new.env(parent = .GlobalEnv)
source(file.path(REPO_ROOT, "accuracy_governance.R"), local = gov_env)

logger_env <- new.env(parent = .GlobalEnv)
source(file.path(REPO_ROOT, "prediction_accuracy_logger.R"), local = logger_env)

pwp_env <- new.env(parent = .GlobalEnv)
source(file.path(REPO_ROOT, "tools", "project_week_predictions.R"), local = pwp_env)

# 1. nba_season_end_year() helper
ok("nba_season_end_year maps 2025-26 dates to 2026L",
   identical(cfg_env$nba_season_end_year(c("2025-10-21", "2026-04-12", "2026-06-20")),
             c(2026L, 2026L, 2026L)))

ok("nba_season_end_year maps 2026-27 dates to 2027L",
   identical(cfg_env$nba_season_end_year(c("2026-10-20", "2026-10-23", "2026-11-24", "2027-04-11")),
             c(2027L, 2027L, 2027L, 2027L)))

ok("nba_season_end_year falls back on NA dates",
   identical(cfg_env$nba_season_end_year(c(NA, "2026-10-20"), fallback_season = 2025L),
             c(2025L, 2027L)))

# 2. Writer consistency: project_week_predictions.R vs prediction_accuracy_logger.R
synth_ratings <- list(
  rating       = c(Celtics = 4.0, Heat = 1.0, BOS = 4.0, MIA = 1.0),
  sd           = c(Celtics = 1.0, Heat = 1.0, BOS = 1.0, MIA = 1.0),
  bottom_up    = c(Celtics = 4.0, Heat = 1.0, BOS = 4.0, MIA = 1.0),
  rapm         = c(Celtics = 4.0, Heat = 1.0, BOS = 4.0, MIA = 1.0),
  shot_fatigue = c(Celtics = 4.0, Heat = 1.0, BOS = 4.0, MIA = 1.0),
  embeddings   = c(Celtics = 4.0, Heat = 1.0, BOS = 4.0, MIA = 1.0),
  abbr         = c(Celtics = "BOS", Heat = "MIA", BOS = "BOS", MIA = "MIA"),
  n            = 2L
)
synth_spine <- tibble(
  game_id                 = c("G1", "G2"),
  game_date               = as.Date(c("2026-10-20", "2026-10-24")),
  home_short_display_name = c("Celtics", "Heat"),
  away_short_display_name = c("Heat", "Celtics")
)
pwp_rows <- pwp_env$.pwp_build_week_projections(
  wk = synth_spine,
  full_spine = synth_spine,
  r = synth_ratings,
  prediction_timestamp = as.POSIXct("2026-10-19 10:00:00", tz = "UTC")
)
ok("project_week_predictions.R writes season = 2027L for 2026-10-20+ LOGGED_PREGAME rows",
   identical(as.integer(pwp_rows$season), c(2027L, 2027L)) &&
     all(pwp_rows$log_source == "LOGGED_PREGAME"))

slate_rows <- logger_env$.build_slate_rows(tibble(
  game_id        = "G3",
  game_date      = as.Date("2026-10-25"),
  Matchup        = "Heat vs. Celtics",
  Team           = "Celtics",
  Model_Win_Prob = 0.65
))
ok(".build_slate_rows() also writes season = 2027L for 2026-10-25",
   identical(as.integer(slate_rows$season), 2027L))

# 3. normalize_prediction_log_seasons() repairs mixed 2026/2027 rows
mixed_log <- tibble(
  game_id                 = c("H1", "P1", "P2", "P3"),
  game_date               = as.Date(c("2026-03-10", "2026-10-20", "2026-10-24", "2026-11-05")),
  season                  = c(2026L, 2026L, 2027L, 2026L),
  home_team               = c("Celtics", "Celtics", "Heat", "Celtics"),
  away_team               = c("Heat", "Heat", "Celtics", "Heat"),
  predicted_home_win_prob = c(0.7, 0.8, 0.6, 0.75),
  actual_winner           = c("Celtics", "Celtics", "Celtics", "Celtics"),
  status                  = rep("RESOLVED", 4L),
  log_source              = c("BACKTEST_SEEDED", "LOGGED_PREGAME", "LOGGED_PREGAME", "LOGGED_PREGAME")
)
repaired_log <- logger_env$normalize_prediction_log_seasons(mixed_log, persist = FALSE)
ok("normalize_prediction_log_seasons() keeps 2025-26 at 2026L and repairs 2026-27 to 2027L",
   identical(as.integer(repaired_log$season), c(2026L, 2027L, 2027L, 2027L)) &&
     identical(repaired_log$predicted_home_win_prob, mixed_log$predicted_home_win_prob))

# 4. accuracy_governance.R .diag_block merges mixed 2026/2027 2026-27 LOGGED_PREGAME rows
gov_fixture <- tibble(
  game_id                 = paste0("G", 1:6),
  game_date               = as.Date(c("2026-10-20", "2026-10-21", "2026-10-23",
                                      "2026-10-24", "2026-10-25", "2026-11-01")),
  season                  = c(2026L, 2026L, 2027L, 2027L, 2027L, 2026L),
  home_team               = rep("Celtics", 6L),
  away_team               = rep("Heat", 6L),
  prediction_timestamp    = as.POSIXct("2026-10-19 08:00:00", tz = "UTC"),
  predicted_home_win_prob = c(0.8, 0.8, 0.6, 0.6, 0.4, 0.8),
  actual_winner           = c("Celtics", "Celtics", "Celtics", "Heat", "Heat", "Celtics"),
  status                  = rep("RESOLVED", 6L),
  log_source              = rep("LOGGED_PREGAME", 6L)
)
tmp_dir <- tempfile("gov_drift_")
dir.create(tmp_dir, recursive = TRUE)
gov_res <- gov_env$run_nba_accuracy_governance(
  log_df       = gov_fixture,
  out_rds      = file.path(tmp_dir, "accuracy_governance.rds"),
  web_data_dir = tmp_dir,
  persist      = TRUE
)
diag <- jsonlite::fromJSON(file.path(tmp_dir, "projections_diagnostics.json"), simplifyVector = TRUE)
unlink(tmp_dir, recursive = TRUE)

ok("accuracy_governance.R merges mixed 2026/2027 rows for 2026-10-20+ into single 2027 drift tile",
   identical(nrow(diag$accuracyDrift), 1L) &&
     identical(as.character(diag$accuracyDrift$season), "2027") &&
     identical(as.integer(diag$accuracyDrift$games), 6L) &&
     identical(as.integer(diag$genuineForecast$accuracyDrift$games), 6L) &&
     identical(as.integer(gov_res$total_games), 6L))

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
