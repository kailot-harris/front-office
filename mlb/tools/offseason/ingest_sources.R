# ==============================================================================
# tools/offseason/ingest_sources.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Multi-Source Ingestion Subsystem
# Path: tools/offseason/ingest_sources.R
#
# Implements 3 isolated feed adapters:
#   1. league_wire: MLB Stats API transactions wire
#   2. team_releases: 30 MLB team transaction feeds
#   3. beat_feeds: National & team beat news / rumor RSS feeds
#
# CLI usage:
#   Rscript --vanilla tools/offseason/ingest_sources.R [options]
#   Options:
#     --start-date=YYYY-MM-DD   Override start date (default derived from baseline asOf)
#     --end-date=YYYY-MM-DD     Override end date (default Sys.Date())
#     --allow-degraded          Allow execution past feed failures without fatal exit
#     --replay-snapshot=<path>  Explicit snapshot replay (reports status DEGRADED)
#
# Generates cache/offseason_wire_items.json with contract-validated normalized
# wire transactions, and cache/ingestion_manifest.json with multilateral health
# checks. Enforces block-vs-degrade governance and quiet-week preconditions,
# snapshots raw ingest into cache/raw_ingest_archive/YYYYMMDD/,
# and implements minor-league vs major-league discrimination (rosterTier).
#
# Conforms to docs/contracts/offseason_wire_items_contract.md and Zero-Betting Policy.
# ==============================================================================

# GitHub issue #90: Project root resolution prelude.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("ingest_sources.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

# Ensure renv / user library path includes installed packages
if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
  library(httr)
  library(xml2)
})

# Source contract schema validator and URL derivation helper
source(file.path(PROJECT_DIR, "tools", "offseason", "wire_items_schema.R"))
source(file.path(PROJECT_DIR, "tools", "offseason", "extract_regex.R"))

# Derives the default start date dynamically from baseline asOf state
# (cache/league_state_baseline.json -> asOf, e.g. "2026-10-31T18:29:51Z").
# Re-fetch overlap: truncating the timestamp to its calendar date (2026-10-31)
# provides an intraday overlap of ~18.5 hours of transactions prior to baseline
# reconciliation to capture any back-dated wire items, while downstream reconcilers dedup.
derive_default_start_date <- function(baseline_path = file.path(PROJECT_DIR, "cache", "league_state_baseline.json"),
                                      overlap_days = 0L) {
  if (file.exists(baseline_path)) {
    tryCatch({
      baseline <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
      if (!is.null(baseline$asOf) && nzchar(baseline$asOf)) {
        base_date <- as.Date(substr(baseline$asOf, 1, 10))
        return(format(base_date - as.integer(overlap_days), "%Y-%m-%d"))
      }
    }, error = function(e) NULL)
  }
  format(Sys.Date() - 7L, "%Y-%m-%d")
}

# Zero-betting policy guard check
FORBIDDEN_BETTING_TERMS <- c("sportsbook", "betmgm", "draftkings", "fanduel",
                             "caesars sportsbook", "pointsbet", "bovada", "bet365",
                             "moneyline", "runline", "over/under", "parlay",
                             "\\bvig\\b", "\\bjuice\\b", "\\bprop bet\\b")

validate_zero_betting <- function(text_vector) {
  for (pattern in FORBIDDEN_BETTING_TERMS) {
    matches <- grepl(pattern, text_vector, ignore.case = TRUE)
    if (any(matches)) {
      stop(sprintf("[Zero-Betting Guard] Violation detected matching pattern '%s'", pattern))
    }
  }
  TRUE
}

# 30 MLB Teams Table
MLB_TEAMS_30 <- data.frame(
  id = c(133, 144, 109, 110, 111, 112, 113, 114, 115, 145, 116, 117, 118, 108, 119, 146, 158, 142, 121, 147, 143, 134, 135, 136, 137, 138, 139, 140, 141, 120),
  name = c("Athletics", "Atlanta Braves", "Arizona Diamondbacks", "Baltimore Orioles", "Boston Red Sox",
           "Chicago Cubs", "Cincinnati Reds", "Cleveland Guardians", "Colorado Rockies", "Chicago White Sox",
           "Detroit Tigers", "Houston Astros", "Kansas City Royals", "Los Angeles Angels", "Los Angeles Dodgers",
           "Miami Marlins", "Milwaukee Brewers", "Minnesota Twins", "New York Mets", "New York Yankees",
           "Philadelphia Phillies", "Pittsburgh Pirates", "San Diego Padres", "Seattle Mariners", "San Francisco Giants",
           "St. Louis Cardinals", "Tampa Bay Rays", "Texas Rangers", "Toronto Blue Jays", "Washington Nationals"),
  abbrev = c("ATH", "ATL", "ARI", "BAL", "BOS",
             "CHC", "CIN", "CLE", "COL", "CHW",
             "DET", "HOU", "KC", "LAA", "LAD",
             "MIA", "MIL", "MIN", "NYM", "NYY",
             "PHI", "PIT", "SD", "SEA", "SF",
             "STL", "TB", "TEX", "TOR", "WSH"),
  stringsAsFactors = FALSE
)

# ------------------------------------------------------------------------------
# Adapter 1: League Transaction Wire (MLB Stats API)
# ------------------------------------------------------------------------------
fetch_league_wire <- function(start_date = derive_default_start_date(), end_date = Sys.Date(),
                              mock_fail = FALSE, timeout_secs = 10,
                              replay_snapshot = NULL) {
  # Explicit snapshot replay opt-in: reports status DEGRADED, http_code 0L,
  # never auto-selected, and never claims HEALTHY or http_code 200.
  if (!is.null(replay_snapshot)) {
    if (file.exists(replay_snapshot)) {
      raw_txt <- readLines(replay_snapshot, warn = FALSE, encoding = "UTF-8")
      combined_txt <- paste(raw_txt, collapse = "\n")
      parsed <- jsonlite::fromJSON(combined_txt)
      tx_count <- if (!is.null(parsed$transactions)) nrow(parsed$transactions) else 0L
      return(list(
        status = "DEGRADED",
        http_code = 0L,
        items_found = as.integer(tx_count),
        bytes_captured = nchar(combined_txt),
        raw_json = parsed,
        raw_text = combined_txt,
        error = "Snapshot replay mode explicitly requested"
      ))
    } else {
      return(list(
        status = "FAILED",
        http_code = 0L,
        items_found = 0L,
        bytes_captured = 0L,
        raw_json = NULL,
        raw_text = NULL,
        error = sprintf("Replay snapshot file not found: %s", replay_snapshot)
      ))
    }
  }

  if (mock_fail) {
    return(list(
      status = "FAILED",
      http_code = 500L,
      items_found = 0L,
      bytes_captured = 0L,
      raw_json = NULL,
      raw_text = NULL,
      error = "Simulated network failure"
    ))
  }
  
  url <- sprintf("https://statsapi.mlb.com/api/v1/transactions?startDate=%s&endDate=%s", start_date, end_date)
  
  res <- tryCatch({
    httr::GET(url, httr::user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"), httr::timeout(timeout_secs))
  }, error = function(e) {
    NULL
  })
  
  # Fail closed: network failure or non-200 yields FAILED with true http_code
  # (0L when no response received). Stale snapshot laundering fallback removed.
  if (is.null(res) || httr::status_code(res) != 200L) {
    code <- if (!is.null(res)) as.integer(httr::status_code(res)) else 0L
    return(list(
      status = "FAILED",
      http_code = code,
      items_found = 0L,
      bytes_captured = 0L,
      raw_json = NULL,
      raw_text = NULL,
      error = if (is.null(res)) "Network unreachable or request timed out" else sprintf("HTTP %d from statsapi", code)
    ))
  }
  
  raw_txt <- httr::content(res, as = "text", encoding = "UTF-8")
  parsed <- tryCatch({
    jsonlite::fromJSON(raw_txt)
  }, error = function(e) NULL)
  
  if (is.null(parsed) || is.null(parsed$transactions)) {
    return(list(
      status = "FAILED",
      http_code = as.integer(httr::status_code(res)),
      items_found = 0L,
      bytes_captured = nchar(raw_txt),
      raw_json = NULL,
      raw_text = NULL,
      error = "Failed to parse API response as JSON transactions"
    ))
  }
  
  tx_count <- nrow(parsed$transactions)
  list(
    status = "HEALTHY",
    http_code = as.integer(httr::status_code(res)),
    items_found = as.integer(tx_count),
    bytes_captured = nchar(raw_txt),
    raw_json = parsed,
    raw_text = raw_txt
  )
}

# ------------------------------------------------------------------------------
# Adapter 2: Team Press Releases / Announcement Feeds (30 Clubs)
# ------------------------------------------------------------------------------
fetch_team_releases <- function(start_date = derive_default_start_date(), end_date = Sys.Date(),
                                mock_fail = FALSE, timeout_secs = 5) {
  if (mock_fail) {
    return(list(
      status = "DEGRADED",
      feeds_polled = 30L,
      feeds_succeeded = 0L,
      items_found = 0L,
      team_records = list()
    ))
  }
  
  feeds_polled <- as.integer(nrow(MLB_TEAMS_30))
  feeds_succeeded <- 0L
  items_found <- 0L
  team_records <- list()
  
  for (i in seq_len(feeds_polled)) {
    tm <- MLB_TEAMS_30[i, ]
    url <- sprintf("https://statsapi.mlb.com/api/v1/transactions?teamId=%d&startDate=%s&endDate=%s", tm$id, start_date, end_date)
    
    t_res <- tryCatch({
      httr::GET(url, httr::user_agent("Mozilla/5.0"), httr::timeout(timeout_secs))
    }, error = function(e) NULL)
    
    if (!is.null(t_res) && httr::status_code(t_res) == 200) {
      t_txt <- httr::content(t_res, as = "text", encoding = "UTF-8")
      t_parsed <- tryCatch(jsonlite::fromJSON(t_txt), error = function(e) NULL)
      if (!is.null(t_parsed) && !is.null(t_parsed$transactions)) {
        feeds_succeeded <- feeds_succeeded + 1L
        n_tx <- if (is.data.frame(t_parsed$transactions)) {
          nrow(t_parsed$transactions)
        } else if (is.list(t_parsed$transactions)) {
          length(t_parsed$transactions)
        } else {
          0L
        }
        items_found <- items_found + as.integer(n_tx)
        team_records[[tm$abbrev]] <- list(team = tm$abbrev, id = tm$id, name = tm$name, tx_count = as.integer(n_tx))
        next
      }
    }
    
    # If network call failed, mark team
    team_records[[tm$abbrev]] <- list(team = tm$abbrev, id = tm$id, name = tm$name, tx_count = 0L)
  }
  
  # Status: HEALTHY if >= 25; DEGRADED if 1..24; FAILED if 0. Stale snapshot fallback removed.
  status <- if (feeds_succeeded >= 25) {
    "HEALTHY"
  } else if (feeds_succeeded > 0) {
    "DEGRADED"
  } else {
    "FAILED"
  }
  
  list(
    status = status,
    feeds_polled = feeds_polled,
    feeds_succeeded = feeds_succeeded,
    items_found = items_found,
    team_records = team_records
  )
}

# ------------------------------------------------------------------------------
# Adapter 3: National Beat News / Rumor RSS Feeds
# ------------------------------------------------------------------------------
BEAT_FEED_SOURCES <- list(
  list(name = "MLB Trade Rumors", url = "https://www.mlbtraderumors.com/feed", category = "Trade Speculation"),
  list(name = "ESPN MLB News", url = "https://www.espn.com/espn/rss/mlb/news", category = "National Beat"),
  list(name = "CBS Sports MLB", url = "https://www.cbssports.com/rss/headlines/mlb/", category = "National Beat"),
  list(name = "Yahoo Sports MLB", url = "https://sports.yahoo.com/mlb/rss/", category = "National Beat"),
  list(name = "MLB.com Official News", url = "https://www.mlb.com/feeds/news/rss.xml", category = "National Beat"),
  list(name = "FanGraphs Baseball", url = "https://blogs.fangraphs.com/feed/", category = "Trade Speculation"),
  list(name = "RotoWire Baseball", url = "https://www.rotowire.com/rss/news.php?sport=mlb", category = "National Beat"),
  list(name = "Sporting News MLB", url = "https://www.sportingnews.com/us/rss/mlb", category = "National Beat")
)

fetch_beat_feeds <- function(sources = BEAT_FEED_SOURCES, mock_fail = FALSE, timeout_secs = 5) {
  if (mock_fail) {
    return(list(
      status = "DEGRADED",
      sources_polled = length(sources),
      sources_succeeded = 0,
      claims_found = 0,
      items = list()
    ))
  }
  
  sources_polled <- length(sources)
  sources_succeeded <- 0
  claims_found <- 0
  items_list <- list()
  
  for (src in sources) {
    res <- tryCatch({
      httr::GET(src$url, httr::user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"), httr::timeout(timeout_secs))
    }, error = function(e) NULL)
    
    if (!is.null(res) && httr::status_code(res) == 200) {
      xml_content <- tryCatch({
        xml2::read_xml(httr::content(res, as = "raw"))
      }, error = function(e) NULL)
      
      if (!is.null(xml_content)) {
        entries <- xml2::xml_find_all(xml_content, ".//item")
        n_entries <- length(entries)
        sources_succeeded <- sources_succeeded + 1
        claims_found <- claims_found + n_entries
        
        # Sample items
        if (n_entries > 0) {
          for (k in seq_len(min(n_entries, 5))) {
            it <- entries[[k]]
            title_node <- xml2::xml_find_first(it, "./title")
            link_node <- xml2::xml_find_first(it, "./link")
            desc_node <- xml2::xml_find_first(it, "./description")
            
            title <- if (!is.na(title_node)) xml2::xml_text(title_node) else ""
            link <- if (!is.na(link_node)) xml2::xml_text(link_node) else ""
            desc <- if (!is.na(desc_node)) xml2::xml_text(desc_node) else ""
            
            # Validate zero betting
            validate_zero_betting(c(title, desc))
            
            items_list[[length(items_list) + 1]] <- list(
              title = title,
              link = link,
              source = src$name,
              category = src$category
            )
          }
        }
      }
    }
  }
  
  status <- if (sources_succeeded >= 5) {
    "HEALTHY"
  } else if (sources_succeeded > 0) {
    "DEGRADED"
  } else {
    "FAILED"
  }
  
  list(
    status = status,
    sources_polled = sources_polled,
    sources_succeeded = sources_succeeded,
    claims_found = claims_found,
    items = items_list
  )
}

# ------------------------------------------------------------------------------
# Minor-League vs Major-League Discrimination
# ------------------------------------------------------------------------------
discriminate_roster_tier <- function(tx_row, mlb_team_names, baseline_40_mlbam_ids) {
  to_name <- if (!is.null(tx_row$toTeam) && !is.null(tx_row$toTeam$name)) tx_row$toTeam$name else ""
  from_name <- if (!is.null(tx_row$fromTeam) && !is.null(tx_row$fromTeam$name)) tx_row$fromTeam$name else ""
  desc <- if (!is.null(tx_row$description)) tx_row$description else ""
  ttype <- if (!is.null(tx_row$typeDesc)) tx_row$typeDesc else ""
  pid <- if (!is.null(tx_row$person) && !is.null(tx_row$person$id)) as.character(tx_row$person$id) else ""
  
  desc_lower <- tolower(desc)
  
  # 1. Outrighted to minor league affiliate
  if (grepl("outright", desc_lower) || identical(ttype, "Outrighted")) {
    return("MINOR_LEAGUE")
  }
  
  # 2. Reserve list / winter league / international placements
  if (grepl("reserve list", desc_lower)) {
    return("MINOR_LEAGUE")
  }
  
  # 3. Selected contract from minor league affiliate to MLB Team
  if (grepl("selected", desc_lower) || identical(ttype, "Selected")) {
    return("MAJOR_40_MAN")
  }
  
  # 4. If destination team is explicitly specified and is NOT an MLB team:
  if (nzchar(to_name) && !(to_name %in% mlb_team_names)) {
    return("MINOR_LEAGUE")
  }
  
  # 5. Assigned to minor league affiliate or foreign/winter league team
  if (grepl("assigned", desc_lower) || identical(ttype, "Assigned")) {
    if (nzchar(to_name) && !(to_name %in% mlb_team_names)) {
      return("MINOR_LEAGUE")
    }
  }
  
  # 6. Minor league contract indicator in text
  if (grepl("minor league", desc_lower)) {
    return("MINOR_LEAGUE")
  }
  
  # 7. Released from non-MLB affiliate or player never on 40-man roster
  if (identical(ttype, "Released") || grepl("released", desc_lower)) {
    if ((nzchar(from_name) && !(from_name %in% mlb_team_names)) ||
        (nzchar(to_name) && !(to_name %in% mlb_team_names)) ||
        (!(pid %in% baseline_40_mlbam_ids))) {
      return("MINOR_LEAGUE")
    }
  }
  
  # Default for major league operations (DFA, Declared Free Agency from MLB club, Trades, Waivers)
  "MAJOR_40_MAN"
}

# ------------------------------------------------------------------------------
# Core Ingestion Orchestrator
# ------------------------------------------------------------------------------
ingest_all <- function(start_date = derive_default_start_date(), end_date = Sys.Date(),
                       allow_degraded = FALSE,
                       replay_snapshot = NULL,
                       mock_wire_fail = FALSE,
                       mock_teams_fail = FALSE,
                       mock_beat_fail = FALSE) {
  message(sprintf(">>> [Ingestion Subsystem] Starting multi-source ingestion run for window %s to %s...",
                  start_date, end_date))
  
  # 1. Fetch 3 feeds
  wire_res <- fetch_league_wire(start_date = start_date, end_date = end_date,
                                mock_fail = mock_wire_fail, replay_snapshot = replay_snapshot)
  teams_res <- fetch_team_releases(start_date = start_date, end_date = end_date, mock_fail = mock_teams_fail)
  beat_res <- fetch_beat_feeds(mock_fail = mock_beat_fail)
  
  # 2. Compute composite health & block-vs-degrade policy
  composite_health <- if (wire_res$status == "FAILED") {
    "FAILED"
  } else if (wire_res$status == "DEGRADED" || teams_res$status == "DEGRADED" || beat_res$status == "DEGRADED") {
    "DEGRADED"
  } else if (wire_res$status == "HEALTHY" && teams_res$status == "HEALTHY" && beat_res$status == "HEALTHY") {
    "HEALTHY"
  } else {
    "DEGRADED"
  }
  
  # Enforce block-vs-degrade governance:
  # league_wire FAILED => fatal publish gate block unless allow_degraded is TRUE
  if (wire_res$status == "FAILED" && !allow_degraded) {
    warning(">>> [Publish Gate Block] league_wire status is FAILED. Fatal block enforced unless --allow-degraded is passed.")
  }
  
  # 3. Load baseline for player 40-man discrimination
  baseline_file <- file.path(PROJECT_DIR, "cache", "league_state_baseline.json")
  p_40_mlbam_ids <- character(0)
  if (file.exists(baseline_file)) {
    baseline <- jsonlite::fromJSON(baseline_file, simplifyVector = FALSE)
    if (!is.null(baseline$players)) {
      for (p in baseline$players) {
        if (!is.null(p$rosterStatus) && identical(p$rosterStatus$value, "40_MAN") && !is.null(p$mlbamId)) {
          p_40_mlbam_ids <- c(p_40_mlbam_ids, as.character(p$mlbamId))
        }
      }
    }
  }
  
  # 4. Process raw items: dedup mirrored trades, assign rosterTier, and map to contract shape
  raw_items <- list()
  normalized_items <- list()
  
  if (!is.null(wire_res$raw_json) && !is.null(wire_res$raw_json$transactions)) {
    tx_df <- wire_res$raw_json$transactions
    mlb_team_names <- MLB_TEAMS_30$name
    
    # Contract §4: Exactly one record per wire transaction. statsapi emits mirrored rows
    # for trades (the same transaction id once per club with fromTeam/toTeam swapped).
    # Collapse them, keeping the first occurrence in feed order.
    keep_mask <- !duplicated(tx_df$id)
    tx_dedup <- tx_df[keep_mask, ]
    
    # Filter out unpopulated/corrupted transaction stubs (e.g. empty trade stubs without description or team)
    valid_mask <- !is.na(tx_dedup$description) & nzchar(trimws(as.character(tx_dedup$description))) &
                  !is.na(tx_dedup$toTeam$id) & as.integer(tx_dedup$toTeam$id) > 0
    if (any(!valid_mask)) {
      dropped_ids <- tx_dedup$id[!valid_mask]
      message(sprintf(">>> [Ingestion Subsystem] Dropping %d malformed wire transaction(s) lacking description/team: %s",
                      length(dropped_ids), paste(dropped_ids, collapse = ", ")))
      tx_dedup <- tx_dedup[valid_mask, ]
    }
    
    n_records <- nrow(tx_dedup)
    tier_list <- character(n_records)
    normalized_items <- vector("list", n_records)
    
    for (idx in seq_len(n_records)) {
      row <- tx_dedup[idx, ]
      tier <- discriminate_roster_tier(row, mlb_team_names, p_40_mlbam_ids)
      tier_list[idx] <- tier
      
      # Contract §2 & §3 mapping block:
      item <- list(
        transaction_id = as.integer(row$id),
        raw_text = as.character(row$description),
        date = as.character(row$date),
        source_url = build_wire_source_url("https://statsapi.mlb.com/api/v1/transactions"),
        team_id = as.integer(row$toTeam$id)
      )
      
      # Contract §3: Optional from_team_id
      if (!is.null(row$fromTeam) && !is.null(row$fromTeam$id)) {
        fid <- row$fromTeam$id
        if (!is.na(fid) && as.integer(fid) > 0) {
          item$from_team_id <- as.integer(fid)
        }
      }
      
      # Contract §7: Optional mlbam_id & player_name co-requirement
      # Neither present passes; both present passes; exactly one present fails.
      # Only emit when both id and non-empty fullName exist in the upstream record.
      has_pid <- !is.null(row$person) && !is.null(row$person$id) && !is.na(row$person$id) && as.integer(row$person$id) > 0
      has_pname <- !is.null(row$person) && !is.null(row$person$fullName) && !is.na(row$person$fullName) &&
                   nzchar(trimws(as.character(row$person$fullName)))
      
      if (has_pid && has_pname) {
        item$mlbam_id <- as.integer(row$person$id)
        item$player_name <- as.character(row$person$fullName)
      } else if (has_pid || has_pname) {
        # Upstream provided incomplete person object; leave neither key present per §7
      }
      
      item$type_code <- as.character(row$typeCode)
      item$type_desc <- as.character(row$typeDesc)
      item$roster_tier <- as.character(tier)
      
      normalized_items[[idx]] <- item
    }
    
    tx_dedup$rosterTier <- tier_list
    raw_items <- tx_dedup
  }
  
  # 5. Contract validation & persistence (cache/offseason_wire_items.json)
  # Validate in-memory items BEFORE writing to disk; abort ingest stage on failure.
  items_written <- length(normalized_items)
  if (wire_res$status %in% c("HEALTHY", "DEGRADED") && items_written > 0) {
    val_res <- validate_wire_items(normalized_items,
                                   require_unique_transaction_ids = TRUE,
                                   allow_unknown_fields = FALSE)
    if (!val_res$pass) {
      error_msg <- sprintf("Contract validation FAILED for wire items (%d errors):\n%s",
                           val_res$n_errors, paste(head(val_res$messages, 10), collapse = "\n"))
      stop(error_msg)
    }
    message(sprintf(">>> [Wire Items Validation] %s", val_res$summary))
    
    wire_items_path <- file.path(PROJECT_DIR, "cache", "offseason_wire_items.json")
    con <- file(wire_items_path, open = "wt", encoding = "UTF-8")
    writeLines(jsonlite::toJSON(normalized_items, auto_unbox = TRUE, pretty = TRUE), con, useBytes = FALSE)
    close(con)
    message(sprintf(">>> Persisted %d normalized wire item(s) to %s", items_written, wire_items_path))
  }
  
  # 6. Snapshot raw captures to cache/raw_ingest_archive/YYYYMMDD/
  today_yyyymmdd <- format(Sys.Date(), "%Y%m%d")
  archive_dir <- file.path(PROJECT_DIR, "cache", "raw_ingest_archive", today_yyyymmdd)
  if (!dir.exists(archive_dir)) {
    dir.create(archive_dir, recursive = TRUE)
  }
  
  if (!is.null(wire_res$raw_text)) {
    writeLines(wire_res$raw_text, file.path(archive_dir, "mlb_transactions_feed.json"))
  }
  
  # 7. Write cache/ingestion_manifest.json with honest volume telemetry
  manifest <- list(
    ingest_timestamp = format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
    composite_health = composite_health,
    start_date = as.character(start_date),
    end_date = as.character(end_date),
    adapters = list(
      league_wire = list(
        status = wire_res$status,
        http_code = wire_res$http_code,
        items_found = as.integer(items_written),
        bytes_captured = wire_res$bytes_captured
      ),
      team_releases = list(
        status = teams_res$status,
        feeds_polled = teams_res$feeds_polled,
        feeds_succeeded = teams_res$feeds_succeeded,
        items_found = teams_res$items_found
      ),
      beat_feeds = list(
        status = beat_res$status,
        sources_polled = beat_res$sources_polled,
        sources_succeeded = beat_res$sources_succeeded,
        claims_found = beat_res$claims_found
      )
    )
  )
  
  manifest_path <- file.path(PROJECT_DIR, "cache", "ingestion_manifest.json")
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  message(sprintf(">>> Manifest written to %s (Composite: %s, Items: %d)",
                  manifest_path, composite_health, items_written))
  
  list(
    manifest = manifest,
    raw_items = raw_items,
    normalized_items = normalized_items,
    composite_health = composite_health,
    can_assert_quiet_week = (composite_health == "HEALTHY" && items_written > 0)
  )
}

# CLI entry point
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  all_args <- commandArgs(trailingOnly = FALSE)
  is_direct <- any(grepl("^--file=.*ingest_sources\\.R$", all_args))
  if (is_direct) {
    allow_deg <- "--allow-degraded" %in% args
    start_arg <- grep("^--start-date=", args, value = TRUE)
    start_override <- if (length(start_arg) > 0) sub("^--start-date=", "", start_arg[1]) else NULL
    end_arg <- grep("^--end-date=", args, value = TRUE)
    end_override <- if (length(end_arg) > 0) sub("^--end-date=", "", end_arg[1]) else Sys.Date()
    replay_arg <- grep("^--replay-snapshot=", args, value = TRUE)
    replay_path <- if (length(replay_arg) > 0) sub("^--replay-snapshot=", "", replay_arg[1]) else NULL

    res <- ingest_all(
      start_date = if (!is.null(start_override)) start_override else derive_default_start_date(),
      end_date = end_override,
      allow_degraded = allow_deg,
      replay_snapshot = replay_path
    )
    if (res$composite_health == "FAILED" && !allow_deg) {
      message("FATAL: Ingestion composite health is FAILED. Publish gate blocked.")
      quit(status = 1)
    }
    quit(status = 0)
  }
}
