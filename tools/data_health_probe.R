# ==============================================================================
# Data Health Probe (WNBA)
# Path: tools/data_health_probe.R
#
# Utility to verify the integrity of the pipeline's core caches.
# Checks for existence, non-zero size, expected schemas, and team completeness.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "data_health_probe.R"

# Expected columns for key caches
EXPECTED_COLS <- list(
  CACHE_TEAM_BOX     = c("game_id", "team_id", "team_abbreviation", "season", "game_date"),
  CACHE_INJURY_DATA  = c("game_date", "team_name", "player_name", "player_id", "status"),
  # Standings path is dynamic in market_odds_engine, we use the canonical one here
  "cache/projected_wnba_standings.rds" = c("Team")
)

check_cache_health <- function() {
  cat("\n==================================================================\n")
  cat("                WNBA PIPELINE DATA HEALTH PROBE                    \n")
  cat("==================================================================\n\n")

  all_passed <- TRUE
  warnings <- list()

  # 1. Define all critical caches to check
  caches_to_check <- c(
    CACHE_TEAM_BOX,
    CACHE_PLAYER_BOX,
    CACHE_FEATURES,
    CACHE_INJURY_DATA,
    CACHE_PLAYER_PROPS,
    file.path(CACHE_DIR, "projected_wnba_standings.rds")
  )

  for (path in caches_to_check) {
    cat(sprintf("Checking %s... ", basename(path)))

    # Existence check
    if (!file.exists(path)) {
      cat("MISSING\n")
      log_warn(sprintf("Cache file missing: %s", path), call = "check_cache_health()")
      all_passed <- FALSE
      next
    }

    # Size check
    if (file.info(path)$size == 0) {
      cat("EMPTY\n")
      log_warn(sprintf("Cache file is empty: %s", path), call = "check_cache_health()")
      all_passed <- FALSE
      next
    }

    # Schema check (if we have expected columns defined)
    # Note: we match the path by looking it up in the EXPECTED_COLS list (using basename or full path)
    expected <- NULL
    for (exp_path in names(EXPECTED_COLS)) {
      if (exp_path == path || exp_path == basename(path)) {
        expected <- EXPECTED_COLS[[exp_path]]
        break
      }
    }

    if (!is.null(expected)) {
      data <- tryCatch(readRDS(path), error = function(e) NULL)
      if (is.null(data)) {
        cat("CORRUPT\n")
        log_error(sprintf("Failed to read RDS: %s", path), call = "check_cache_health()")
        all_passed <- FALSE
      } else if (!all(expected %in% names(data))) {
        missing <- setdiff(expected, names(data))
        cat(sprintf("SCHEMA FAIL (Missing: %s)\n", paste(missing, collapse = ", ")))
        log_warn(sprintf("Cache %s missing expected columns: %s", path, paste(missing, collapse = ", ")), call = "check_cache_health()")
        all_passed <- FALSE
      } else {
        cat("OK\n")
      }
    } else {
      cat("OK (No schema defined)\n")
    }
  }

  # 2. Deep check: Team Completeness in Box Scores
  if (file.exists(CACHE_TEAM_BOX)) {
    cat("\nChecking team completeness in team box cache...\n")
    box_data <- readRDS(CACHE_TEAM_BOX)

    # Normalize abbreviations to handle CONN -> CON
    # (Matching the logic in daily_ingest.R)
    present_teams <- unique(box_data$team_abbreviation)
    present_teams <- if_else(present_teams == "CONN", "CON", present_teams)

    missing_teams <- setdiff(names(WNBA_TEAMS), present_teams)

    if (length(missing_teams) > 0) {
      cat(sprintf("WARNING: %d teams missing from cache: %s\n",
                  length(missing_teams), paste(missing_teams, collapse = ", ")))
      log_warn(sprintf("Teams missing from %s: %s", CACHE_TEAM_BOX, paste(missing_teams, collapse = ", ")),
               call = "check_cache_health()")
      # We don't mark all_passed = FALSE here because it might be early season,
      # but it's a warning.
    } else {
      cat("All franchise teams present.\n")
    }
  }

  cat("\n------------------------------------------------------------------\n")
  if (all_passed) {
    cat("OVERALL HEALTH: PASSED\n")
    log_info("Data health probe passed successfully.", call = "check_cache_health()")
  } else {
    cat("OVERALL HEALTH: FAILED (Check logs for details)\n")
    log_error("Data health probe failed one or more checks.", call = "check_cache_health()")
  }
  cat("==================================================================\n")

  return(all_passed)
}

if (sys.nframe() == 0) {
  check_cache_health()
}
