# ==============================================================================
# mlb_injury_scraper.R — ESPN MLB injury feed scraper with Player-Card ID parsing
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_injury_scraper.R
#
# Scrapes active MLB injuries from ESPN's public site-API feed:
#   https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/injuries
#
# Reuses the proven ESPN athlete ID-parsing workaround from sibling repos
# (WNBA Analytics / NFL Analytics) verified in docs/research/phase0a-vendor-api.md:
#   The `athlete` object has NO top-level `id` field. The numeric ESPN athlete ID
#   is parsed from the athlete$links hrefs (e.g. ".../player/_/id/39878/corbin-burnes").
#
# Interface contract (docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 / Issue #13):
#   - Exposes exactly one callable top-level function: run_injury_scraper(force_refresh = FALSE)
#   - Writes output to cache_path("injury", "mlb_injuries.rds")
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_injury_scraper.R"

ESPN_MLB_INJURIES_URL <- "https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/injuries"

#' Extract numeric ESPN athlete ID from an athlete's links list
#'
#' @param links_list List of link objects from ESPN athlete JSON
#' @return Character string containing numeric athlete ID, or NA_character_ if not found
.extract_espn_athlete_id <- function(links_list) {
  if (is.null(links_list) || length(links_list) == 0) return(NA_character_)
  
  # Try to find a link with 'playercard' in rel
  for (link in links_list) {
    href <- link$href %||% ""
    rels <- unlist(link$rel %||% list())
    if ("playercard" %in% rels && grepl("/id/([0-9]+)", href)) {
      m <- regmatches(href, regexec("/id/([0-9]+)", href))[[1]]
      if (length(m) >= 2) return(m[2])
    }
  }
  
  # Fallback: check any href containing /id/<digits>
  for (link in links_list) {
    href <- link$href %||% ""
    if (grepl("/id/([0-9]+)", href)) {
      m <- regmatches(href, regexec("/id/([0-9]+)", href))[[1]]
      if (length(m) >= 2) return(m[2])
    }
  }
  
  NA_character_
}

#' Run ESPN MLB injury scraper and persist cached results
#'
#' @param force_refresh If TRUE, re-fetches from API even if cache exists. Default FALSE.
#' @return A tibble with current MLB injuries, or empty tibble on failure.
run_injury_scraper <- function(force_refresh = FALSE) {
  cache_file <- cache_path("injury", "mlb_injuries.rds")
  
  if (!force_refresh && file.exists(cache_file)) {
    log_info("Loading cached injuries from disk", script = .LOG_SCRIPT, cache_file = cache_file)
    return(readRDS(cache_file))
  }
  
  log_info("Fetching live ESPN MLB injuries feed", script = .LOG_SCRIPT, url = ESPN_MLB_INJURIES_URL)
  
  raw_data <- tryCatch({
    fromJSON(ESPN_MLB_INJURIES_URL, simplifyVector = FALSE)
  }, error = function(e) {
    log_error("Failed to fetch or parse ESPN MLB injuries feed", condition = e, script = .LOG_SCRIPT)
    NULL
  })
  
  if (is.null(raw_data) || is.null(raw_data$injuries)) {
    log_warn("Empty response or missing injuries element from ESPN API", script = .LOG_SCRIPT)
    if (file.exists(cache_file)) {
      log_warn("Falling back to existing cache", script = .LOG_SCRIPT)
      return(readRDS(cache_file))
    }
    return(tibble::tibble())
  }
  
  records <- list()
  feed_timestamp <- raw_data$timestamp %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
  
  for (team_block in raw_data$injuries) {
    team_name <- team_block$displayName %||% NA_character_
    team_id   <- as.character(team_block$id %||% NA_character_)
    injuries  <- team_block$injuries %||% list()
    
    for (inj in injuries) {
      athlete <- inj$athlete %||% list()
      espn_id <- .extract_espn_athlete_id(athlete$links)
      
      details <- inj$details %||% list()
      fantasy_status <- if (!is.null(details$fantasyStatus)) {
        details$fantasyStatus$description %||% details$fantasyStatus$abbreviation %||% NA_character_
      } else {
        NA_character_
      }
      
      pos <- if (!is.null(athlete$position)) {
        athlete$position$abbreviation %||% athlete$position$name %||% NA_character_
      } else {
        NA_character_
      }
      
      rec <- tibble::tibble(
        espn_athlete_id = as.character(espn_id),
        athlete_name    = as.character(athlete$displayName %||% athlete$fullName %||% NA_character_),
        first_name      = as.character(athlete$firstName %||% NA_character_),
        last_name       = as.character(athlete$lastName %||% NA_character_),
        position        = as.character(pos),
        team_id         = as.character(team_id),
        team_name       = as.character(team_name),
        status          = as.character(inj$status %||% NA_character_),
        injury_type     = as.character(details$type %||% NA_character_),
        injury_detail   = as.character(details$detail %||% NA_character_),
        side            = as.character(details$side %||% NA_character_),
        fantasy_status  = as.character(fantasy_status),
        return_date     = as.character(details$returnDate %||% NA_character_),
        report_date     = as.character(inj$date %||% NA_character_),
        short_comment   = as.character(inj$shortComment %||% NA_character_),
        long_comment    = as.character(inj$longComment %||% NA_character_),
        feed_timestamp  = as.character(feed_timestamp),
        scraped_at      = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
      records[[length(records) + 1]] <- rec
    }
  }
  
  if (length(records) == 0) {
    log_warn("No injury records found in feed", script = .LOG_SCRIPT)
    res <- tibble::tibble()
  } else {
    res <- dplyr::bind_rows(records)
    log_info(sprintf("Parsed %d injury records across %d teams", nrow(res), length(raw_data$injuries)),
             script = .LOG_SCRIPT,
             players_with_espn_id = sum(!is.na(res$espn_athlete_id)))
  }
  
  saveRDS(res, cache_file)
  log_info("Saved injury data to cache", script = .LOG_SCRIPT, cache_file = cache_file)
  
  res
}
