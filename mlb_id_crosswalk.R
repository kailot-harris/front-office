# ==============================================================================
# mlb_id_crosswalk.R — Cross-Vendor MLB Player-ID Crosswalk
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_id_crosswalk.R
#
# Builds and persists a canonical join table across the 5 primary player ID schemes:
#   1. MLB Stats API person ID (`mlb_id` / `mlbam_id`)
#   2. FanGraphs ID (`fangraphs_id` / `fg_id`)
#   3. Baseball-Reference ID (`bref_id` / `bbref_id`)
#   4. Retrosheet ID (`retro_id` / `retrosheet_id`)
#   5. ESPN athlete ID (`espn_id` / `espn_athlete_id`)
#
# Background (docs/MLB_REPLICATION_PLAN.md §6 & Summary Judgment):
#   Baseball has four major historical ID schemes plus ESPN's site-specific IDs,
#   with no bundled crosswalk like NFL's nflreadr::load_ff_playerids().
#   This file provides that infrastructure using the Chadwick Bureau register
#   (via baseballr::chadwick_player_lu()) joined with live ESPN athlete mappings.
#
# Deduplication rule (inherited from sibling repos):
#   Drop ambiguous ID values that map to 2+ distinct players in any scheme,
#   rather than guessing which player is correct.
#
# Interface contract (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 / Issue #13):
#   - Callable top-level function: run_id_crosswalk(force_refresh = FALSE)
#   - Helper query function: query_id_crosswalk(id_scheme, id_value, crosswalk = NULL)
#   - Writes to cache_path("id_crosswalk", "mlb_id_crosswalk.rds")
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_id_crosswalk.R"

ESPN_ROSTER_BASE_URL <- "https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/%d/roster"

#' Fetch current ESPN MLB rosters across all 30 teams to extract ESPN athlete IDs and names
#'
#' @return A tibble with espn_id, espn_name, first_name, last_name, position, team_id
.fetch_espn_roster_athletes <- function() {
  log_info("Fetching ESPN rosters across 30 teams for ESPN athlete IDs", script = .LOG_SCRIPT)
  
  roster_rows <- list()
  for (tid in 1:30) {
    url <- sprintf(ESPN_ROSTER_BASE_URL, tid)
    res <- tryCatch({
      fromJSON(url, simplifyVector = FALSE)
    }, error = function(e) NULL)
    
    if (is.null(res) || is.null(res$athletes)) next
    
    for (pos_grp in res$athletes) {
      items <- pos_grp$items %||% list()
      for (a in items) {
        if (!is.null(a$id)) {
          roster_rows[[length(roster_rows) + 1]] <- tibble::tibble(
            espn_id    = as.character(a$id),
            espn_name  = as.character(a$displayName %||% a$fullName %||% ""),
            first_name = as.character(a$firstName %||% ""),
            last_name  = as.character(a$lastName %||% ""),
            position   = as.character(a$position$abbreviation %||% ""),
            team_id    = as.character(tid)
          )
        }
      }
    }
  }
  
  if (length(roster_rows) == 0) {
    log_warn("No ESPN athletes retrieved from team rosters", script = .LOG_SCRIPT)
    return(tibble::tibble(
      espn_id = character(), espn_name = character(),
      first_name = character(), last_name = character(),
      position = character(), team_id = character()
    ))
  }
  
  df <- dplyr::bind_rows(roster_rows) %>%
    dplyr::filter(!is.na(espn_id) & nzchar(espn_id)) %>%
    dplyr::distinct(espn_id, .keep_all = TRUE)
  
  log_info(sprintf("Retrieved %d distinct active ESPN athletes from rosters", nrow(df)),
           script = .LOG_SCRIPT)
  df
}

#' Run ID crosswalk builder and cache results
#'
#' @param force_refresh If TRUE, re-generates crosswalk even if cached. Default FALSE.
#' @return A tibble representing the unified crosswalk
run_id_crosswalk <- function(force_refresh = FALSE) {
  cache_file <- cache_path("id_crosswalk", "mlb_id_crosswalk.rds")
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info("Loading cached MLB player-ID crosswalk from disk", script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  log_info("Building unified MLB player-ID crosswalk", script = .LOG_SCRIPT)
  
  # 1. Fetch or load Chadwick register via baseballr
  chadwick_raw <- tryCatch({
    if (.mlb_has_baseballr) {
      baseballr::chadwick_player_lu()
    } else {
      stop("baseballr is required to load the Chadwick register")
    }
  }, error = function(e) {
    log_error("Failed to load Chadwick register from baseballr", condition = e, script = .LOG_SCRIPT)
    NULL
  })
  
  if (is.null(chadwick_raw) || nrow(chadwick_raw) == 0) {
    if (file.exists(cache_file)) {
      log_warn("Using existing crosswalk cache as fallback", script = .LOG_SCRIPT)
      return(readRDS(cache_file))
    }
    stop("Cannot build player ID crosswalk without Chadwick register")
  }
  
  # Standardize column types and names
  clean_cw <- chadwick_raw %>%
    dplyr::transmute(
      mlb_id        = as.character(key_mlbam),
      fangraphs_id  = as.character(key_fangraphs),
      bref_id       = as.character(key_bbref),
      retro_id      = as.character(key_retro),
      first_name    = as.character(name_first),
      last_name     = as.character(name_last),
      full_name     = trimws(paste(name_first %||% "", name_last %||% "")),
      birth_year    = as.integer(birth_year),
      mlb_played_first = as.integer(mlb_played_first),
      mlb_played_last  = as.integer(mlb_played_last)
    )
  
  # Clean NA representations (empty strings or "NA")
  clean_cw <- clean_cw %>%
    dplyr::mutate(
      mlb_id       = ifelse(is.na(mlb_id) | mlb_id %in% c("", "NA", "0"), NA_character_, mlb_id),
      fangraphs_id = ifelse(is.na(fangraphs_id) | fangraphs_id %in% c("", "NA", "0"), NA_character_, fangraphs_id),
      bref_id      = ifelse(is.na(bref_id) | bref_id %in% c("", "NA"), NA_character_, bref_id),
      retro_id     = ifelse(is.na(retro_id) | retro_id %in% c("", "NA"), NA_character_, retro_id)
    )
  
  # Filter out rows where all 4 IDs are NA
  clean_cw <- clean_cw %>%
    dplyr::filter(!is.na(mlb_id) | !is.na(fangraphs_id) | !is.na(bref_id) | !is.na(retro_id))
  
  # 2. Fetch active ESPN roster athletes to crosswalk ESPN IDs
  espn_athletes <- .fetch_espn_roster_athletes()
  
  # Join ESPN athletes: first match by exact full_name and last_name
  # For active players (mlb_played_last >= 2020 or NA)
  active_candidates <- clean_cw %>%
    dplyr::filter(is.na(mlb_played_last) | mlb_played_last >= 2020)
  
  # Build normalized name key for matching: lowercase alphanumeric only
  norm_name <- function(x) tolower(gsub("[^A-Za-z0-9]", "", x %||% ""))
  
  espn_athletes$norm_name <- norm_name(espn_athletes$espn_name)
  active_candidates$norm_name <- norm_name(active_candidates$full_name)
  
  # Find unique matches on norm_name
  espn_matches <- espn_athletes %>%
    dplyr::inner_join(
      active_candidates %>% dplyr::select(norm_name, mlb_id),
      by = "norm_name",
      relationship = "many-to-many"
    ) %>%
    dplyr::group_by(mlb_id) %>%
    dplyr::filter(dplyr::n() == 1) %>% # Discard ambiguous matches
    dplyr::ungroup() %>%
    dplyr::group_by(espn_id) %>%
    dplyr::filter(dplyr::n() == 1) %>%
    dplyr::ungroup() %>%
    dplyr::select(mlb_id, espn_id)
  
  clean_cw <- clean_cw %>%
    dplyr::left_join(espn_matches, by = "mlb_id")
  
  # 3. Deduplicate ambiguous IDs per key scheme (drop duplicate assignments)
  dedupe_schemes <- c("mlb_id", "fangraphs_id", "bref_id", "retro_id", "espn_id")
  for (scheme in dedupe_schemes) {
    vals <- clean_cw[[scheme]]
    non_na <- vals[!is.na(vals)]
    dupes <- unique(non_na[duplicated(non_na)])
    if (length(dupes) > 0) {
      log_warn(sprintf("mlb_id_crosswalk: %d ambiguous %s values map to 2+ records; setting to NA",
                       length(dupes), scheme),
               script = .LOG_SCRIPT)
      clean_cw[[scheme]][clean_cw[[scheme]] %in% dupes] <- NA_character_
    }
  }
  
  # Re-filter in case any became entirely empty
  clean_cw <- clean_cw %>%
    dplyr::filter(!is.na(mlb_id) | !is.na(fangraphs_id) | !is.na(bref_id) | !is.na(retro_id) | !is.na(espn_id))
  
  saveRDS(clean_cw, cache_file)
  log_info(sprintf("Saved MLB player-ID crosswalk with %d total records (%d with ESPN ID)",
                   nrow(clean_cw), sum(!is.na(clean_cw$espn_id))),
           script = .LOG_SCRIPT, cache_file = cache_file)
  
  clean_cw
}

#' Query the MLB Player-ID Crosswalk by any supported ID scheme
#'
#' @param id_scheme One of 'mlb_id', 'fangraphs_id', 'bref_id', 'retro_id', 'espn_id'
#' @param id_value Character or numeric ID value to search
#' @param crosswalk Optional pre-loaded crosswalk tibble. If NULL, loads from cache/builder.
#' @return Matching row(s) as a tibble, or empty tibble if not found.
query_id_crosswalk <- function(id_scheme, id_value, crosswalk = NULL) {
  valid_schemes <- c("mlb_id", "fangraphs_id", "bref_id", "retro_id", "espn_id")
  if (!id_scheme %in% valid_schemes) {
    stop(sprintf("Invalid id_scheme '%s'. Must be one of: %s",
                 id_scheme, paste(valid_schemes, collapse = ", ")))
  }
  
  cw <- if (is.null(crosswalk)) run_id_crosswalk() else crosswalk
  val_str <- as.character(id_value)
  
  cw %>% dplyr::filter(.data[[id_scheme]] == val_str)
}
