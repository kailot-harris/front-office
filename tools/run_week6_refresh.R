# Ad-hoc refresh: regenerate projections through team_ratings_engine.R only (stages 1-5 of
# run_full_pipeline.R), skipping fatigue/playoff/market/bet/discord stages since this run's sole
# purpose is to regenerate CACHE_PROJECTED_MATCHUPS for a week 6 prediction visualization, not a
# full pipeline execution with live Discord/Odds-API side effects.
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
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
