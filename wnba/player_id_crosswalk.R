# ==============================================================================
# player_id_crosswalk.R (WNBA)
# Cross-Source WNBA Player-ID Crosswalk
# Path: c:/Users/kailo/kayceeslices/front-office/WNBA Analytics/player_id_crosswalk.R
#
# Connects ESPN athlete IDs (used in active_rosters_cache.rds) to WNBA.com / Stats API
# person_id values (used in rapm_ratings.rds as `player_id`).
#
# Addresses GitHub issue #91: allows join_rapm_to_roster() to join by exact player ID
# rather than fragile (team, surname) pairs that fail on trades or ambiguous surnames.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(wehoop)
})

source("config.R")
if (file.exists("logging_utils.R")) source("logging_utils.R")

if (!exists("CACHE_PLAYER_ID_CROSSWALK")) {
  CACHE_PLAYER_ID_CROSSWALK <- file.path(CACHE_DIR, "player_id_crosswalk.rds")
}

#' Load and cache cross-source player ID crosswalk from wehoop.
#'
#' @param force_refresh If TRUE, re-fetch from wehoop even if cached locally.
#' @return A data frame containing espn_athlete_id, wnba_player_id, player_name, and metadata.
load_player_id_crosswalk <- function(force_refresh = FALSE) {
  if (!force_refresh && file.exists(CACHE_PLAYER_ID_CROSSWALK)) {
    return(readRDS(CACHE_PLAYER_ID_CROSSWALK))
  }

  raw <- tryCatch({
    wehoop::load_wnba_player_crosswalk()
  }, error = function(e) {
    if (exists("log_warn")) {
      log_warn(sprintf("load_player_id_crosswalk(): wehoop fetch failed: %s", conditionMessage(e)),
               call = "load_player_id_crosswalk()")
    }
    NULL
  })

  if (is.null(raw) || nrow(raw) == 0) {
    if (file.exists(CACHE_PLAYER_ID_CROSSWALK)) {
      message(">>> [CROSSWALK] Remote fetch failed; falling back to existing cache.")
      return(readRDS(CACHE_PLAYER_ID_CROSSWALK))
    }
    warning("load_player_id_crosswalk(): unable to fetch or load crosswalk.")
    return(tibble(espn_athlete_id = character(0), wnba_player_id = character(0)))
  }

  # Clean and deduplicate: keep unique mapping between espn_athlete_id and wnba_player_id
  clean <- raw %>%
    filter(!is.na(espn_athlete_id), !is.na(wnba_player_id),
           espn_athlete_id != "", wnba_player_id != "") %>%
    mutate(
      espn_athlete_id = as.character(espn_athlete_id),
      wnba_player_id  = as.character(wnba_player_id)
    )

  # Check for ambiguous IDs (1 espn ID mapping to multiple distinct wnba IDs)
  dupe_espn <- clean %>%
    group_by(espn_athlete_id) %>%
    filter(n_distinct(wnba_player_id) > 1) %>%
    ungroup()

  if (nrow(dupe_espn) > 0) {
    bad_ids <- unique(dupe_espn$espn_athlete_id)
    if (exists("log_warn")) {
      log_warn(sprintf("load_player_id_crosswalk(): %d ambiguous espn_athlete_id(s) map to multiple WNBA IDs - dropping.", length(bad_ids)),
               call = "load_player_id_crosswalk()")
    }
    clean <- clean %>% filter(!espn_athlete_id %in% bad_ids)
  }

  clean <- clean %>%
    distinct(espn_athlete_id, .keep_all = TRUE)

  saveRDS(clean, CACHE_PLAYER_ID_CROSSWALK)
  if (exists("log_info")) {
    log_info(sprintf("load_player_id_crosswalk(): cached %d unique mappings to %s", nrow(clean), CACHE_PLAYER_ID_CROSSWALK),
             call = "load_player_id_crosswalk()", rows = nrow(clean))
  }
  message(sprintf(">>> [CROSSWALK] Cached %d player ID mappings to %s", nrow(clean), CACHE_PLAYER_ID_CROSSWALK))
  clean
}

if (!interactive()) {
  load_player_id_crosswalk()
}
