# Ad-hoc refresh: regenerate projections through team_ratings_engine.R only (stages 1-5 of
# run_full_pipeline.R), skipping fatigue/playoff/market/bet/discord stages since this run's sole
# purpose is to regenerate CACHE_PROJECTED_MATCHUPS for a week 5 prediction visualization, not a
# full pipeline execution with live Discord/Odds-API side effects.
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
source("logging_utils.R")
source("config.R")

message(">>> Stage 1: daily_ingest.R")
source("daily_ingest.R", local = FALSE)
run_daily_ingest()

message(">>> Stage 2: sync_rosters.R")
source("sync_rosters.R", local = FALSE)
run_sync_rosters()

message(">>> Stage 3: injury_scraper.R")
source("injury_scraper.R", local = FALSE)
run_injury_scraper()

message(">>> Stage 4: epa_metrics_engine.R")
source("epa_metrics_engine.R", local = FALSE)
run_epa_metrics()

message(">>> Stage 5: team_ratings_engine.R")
source("team_ratings_engine.R", local = FALSE)
run_team_ratings()

message(">>> Done. CACHE_PROJECTED_MATCHUPS rewritten.")
