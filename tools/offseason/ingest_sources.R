# ==============================================================================
# ingest_sources.R
# WNBA Offseason Dynamics Monitor — Ingestion Subsystem & Health Gate (Phase 2)
#
# Implements multi-source weekly ingestion across 3 isolated adapters:
#   1. league_wire: Official WNBA transaction wire & ESPN wire
#   2. team_releases: Team press release feeds / news portals for 15 franchises
#   3. beat_feeds: Beat feeds & reporter wire
#
# Generates:
#   - cache/ingestion_manifest.json
#   - cache/raw_ingest_archive/YYYYMMDD/<adapter>_<timestamp>.(html|json|xml|txt)
#
# Usage:
#   Rscript tools/offseason/ingest_sources.R [--dry-run] [--allow-degraded] [--output-manifest=<path>]
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# Guarantees the script resolves repo root regardless of invocation working dir
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}

suppressPackageStartupMessages({
  library(jsonlite)
})

# Safe configuration loading
if (file.exists("config.R")) {
  source("config.R")
}
if (file.exists("logging_utils.R")) {
  source("logging_utils.R")
}

# Define the 15 canonical WNBA franchises
DEFAULT_WNBA_TEAMS <- c(
  ATL = "Atlanta Dream",
  CHI = "Chicago Sky",
  CON = "Connecticut Sun",
  DAL = "Dallas Wings",
  GS  = "Golden State Valkyries",
  IND = "Indiana Fever",
  LV  = "Las Vegas Aces",
  LA  = "Los Angeles Sparks",
  MIN = "Minnesota Lynx",
  NY  = "New York Liberty",
  PHX = "Phoenix Mercury",
  POR = "Portland Fire",
  SEA = "Seattle Storm",
  TOR = "Toronto Tempo",
  WSH = "Washington Mystics"
)

# Canonical beat sources (6 beat feeds per Blueprint §2)
DEFAULT_BEAT_SOURCES <- list(
  list(id = "the_next_hoops", name = "The Next Hoops", url = "https://thenexthoops.com/feed/"),
  list(id = "winsidr", name = "Winsidr", url = "https://winsidr.com/feed/"),
  list(id = "her_hoop_stats", name = "Her Hoop Stats", url = "https://herhoopstats.substack.com/feed"),
  list(id = "espn_wnba_beat", name = "ESPN Women's Hoops Desk", url = "https://www.espn.com/espn/rss/wnba/news"),
  list(id = "athletic_wnba", name = "The Athletic WNBA Wire", url = "https://theathletic.com/wnba/feed/"),
  list(id = "swish_appeal", name = "Swish Appeal", url = "https://www.swishappeal.com/rss/index.xml")
)

# ------------------------------------------------------------------------------
# HTTP Snapshot Helper
# ------------------------------------------------------------------------------
snapshot_raw_response <- function(content, adapter_name, source_id, ext = "txt", archive_dir = NULL) {
  if (is.null(archive_dir)) {
    date_str <- format(Sys.time(), "%Y%m%d")
    archive_dir <- file.path("cache", "raw_ingest_archive", date_str)
  }
  if (!dir.exists(archive_dir)) {
    dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  ts <- format(Sys.time(), "%H%M%S")
  filename <- sprintf("%s_%s_%s.%s", adapter_name, source_id, ts, ext)
  target_path <- file.path(archive_dir, filename)
  
  tryCatch({
    if (is.raw(content)) {
      writeBin(content, target_path)
    } else {
      writeLines(as.character(content), target_path, useBytes = TRUE)
    }
    target_path
  }, error = function(e) {
    warning("Failed to snapshot raw response for ", adapter_name, ": ", e$message)
    NULL
  })
}

# ------------------------------------------------------------------------------
# Adapter 1: League Transaction Wire
# ------------------------------------------------------------------------------
poll_league_wire <- function(dry_run = FALSE, archive_dir = NULL, mock_response = NULL) {
  message(">>> [INGEST] Polling League Transaction Wire adapter...")
  
  if (!is.null(mock_response)) {
    status <- mock_response$status %||% "HEALTHY"
    http_code <- mock_response$http_code %||% 200
    items_found <- mock_response$items_found %||% 0
    bytes_captured <- mock_response$bytes_captured %||% 0
    
    if (bytes_captured > 0) {
      snapshot_raw_response(
        mock_response$content %||% "MOCK_WIRE_CONTENT",
        "league_wire", "primary_wire", "json", archive_dir
      )
    }
    
    return(list(
      status = status,
      http_code = http_code,
      items_found = items_found,
      bytes_captured = bytes_captured
    ))
  }
  
  if (isTRUE(dry_run)) {
    # In dry-run mode, simulate a successful pull
    sim_data <- list(
      transactions = list(
        list(date = "2026-10-31", team = "NY", text = "Signed free agent guard to extension.", type = "extension"),
        list(date = "2026-10-31", team = "LV", text = "Exercised fourth-year team option.", type = "option"),
        list(date = "2026-10-31", team = "CON", text = "Cored forward for 2027 season.", type = "cored")
      )
    )
    json_bytes <- jsonlite::toJSON(sim_data, auto_unbox = TRUE, pretty = TRUE)
    snapshot_raw_response(json_bytes, "league_wire", "simulated", "json", archive_dir)
    
    return(list(
      status = "HEALTHY",
      http_code = 200,
      items_found = length(sim_data$transactions),
      bytes_captured = nchar(as.character(json_bytes))
    ))
  }
  
  # Live poll: ESPN WNBA transactions endpoint + WNBA transactions portal
  urls <- c(
    "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/transactions",
    "https://www.wnba.com/transactions"
  )
  
  total_bytes <- 0
  items <- 0
  http_code <- 0
  adapter_status <- "FAILED"
  
  for (u in urls) {
    res <- tryCatch({
      h <- curl::curl_fetch_memory(u)
      h
    }, error = function(e) {
      warning("Error fetching wire from ", u, ": ", e$message)
      NULL
    })
    
    if (!is.null(res)) {
      http_code <- res$status_code
      if (res$status_code >= 200 && res$status_code < 300) {
        body_len <- length(res$content)
        total_bytes <- total_bytes + body_len
        adapter_status <- "HEALTHY"
        ext <- if (grepl("json", res$type %||% "")) "json" else "html"
        snapshot_raw_response(res$content, "league_wire", ifelse(grepl("espn", u), "espn", "wnba_com"), ext, archive_dir)
        
        # Parse items if possible
        if (ext == "json") {
          parsed <- tryCatch(jsonlite::fromJSON(rawToChar(res$content)), error = function(e) NULL)
          if (!is.null(parsed$transactions)) items <- items + length(parsed$transactions)
          else if (!is.null(parsed$items)) items <- items + length(parsed$items)
          else items <- items + 1
        } else {
          # HTML regex count of transaction items/rows
          html_text <- rawToChar(res$content)
          matches <- gregexpr("<tr|<li class=[\"'][^\"']*transaction", html_text, ignore.case = TRUE)[[1]]
          if (matches[1] != -1) items <- items + length(matches) else items <- items + 1
        }
        break # Successfully fetched primary or secondary wire
      }
    }
  }
  
  list(
    status = adapter_status,
    http_code = http_code,
    items_found = items,
    bytes_captured = total_bytes
  )
}

# ------------------------------------------------------------------------------
# Adapter 2: Team Press Releases & News Portals (15 Franchises)
# ------------------------------------------------------------------------------
poll_team_releases <- function(teams = NULL, dry_run = FALSE, archive_dir = NULL, mock_response = NULL) {
  message(">>> [INGEST] Polling Team Press Release adapter (15 franchises)...")
  
  if (is.null(teams)) {
    teams <- if (exists("WNBA_TEAMS")) WNBA_TEAMS else DEFAULT_WNBA_TEAMS
  }
  
  if (!is.null(mock_response)) {
    status <- mock_response$status %||% "HEALTHY"
    feeds_polled <- mock_response$feeds_polled %||% length(teams)
    feeds_succeeded <- mock_response$feeds_succeeded %||% length(teams)
    items_found <- mock_response$items_found %||% 0
    
    if (items_found > 0) {
      snapshot_raw_response(
        mock_response$content %||% "MOCK_TEAM_CONTENT",
        "team_releases", "mock_teams", "txt", archive_dir
      )
    }
    
    return(list(
      status = status,
      feeds_polled = feeds_polled,
      feeds_succeeded = feeds_succeeded,
      items_found = items_found
    ))
  }
  
  if (isTRUE(dry_run)) {
    # Simulate dry run
    for (abbr in names(teams)) {
      sim_text <- sprintf("Press release for %s: Roster updates and staff announcement.", teams[[abbr]])
      snapshot_raw_response(sim_text, "team_releases", abbr, "txt", archive_dir)
    }
    return(list(
      status = "HEALTHY",
      feeds_polled = length(teams),
      feeds_succeeded = length(teams),
      items_found = 5
    ))
  }
  
  feeds_polled <- length(teams)
  feeds_succeeded <- 0
  items_found <- 0
  
  for (abbr in names(teams)) {
    team_name <- teams[[abbr]]
    feed_url <- sprintf("https://www.wnba.com/%s/news/rss", tolower(abbr))
    
    res <- tryCatch({
      h <- curl::curl_fetch_memory(feed_url)
      h
    }, error = function(e) {
      # Isolated exception: log warning without crashing DAG
      warning("Warning polling feed for ", abbr, " (", team_name, "): ", e$message)
      NULL
    })
    
    if (!is.null(res) && res$status_code >= 200 && res$status_code < 400) {
      feeds_succeeded <- feeds_succeeded + 1
      snapshot_raw_response(res$content, "team_releases", abbr, "xml", archive_dir)
      
      # Isolated parse
      xml_str <- rawToChar(res$content)
      item_matches <- gregexpr("<item|<entry", xml_str, ignore.case = TRUE)[[1]]
      if (item_matches[1] != -1) {
        items_found <- items_found + length(item_matches)
      }
    }
  }
  
  status <- if (feeds_succeeded == feeds_polled) {
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
    items_found = items_found
  )
}

# ------------------------------------------------------------------------------
# Adapter 3: National & Team Beat Feeds
# ------------------------------------------------------------------------------
poll_beat_feeds <- function(beat_sources = NULL, dry_run = FALSE, archive_dir = NULL, mock_response = NULL) {
  message(">>> [INGEST] Polling Beat Feeds adapter...")
  
  if (is.null(beat_sources)) {
    beat_sources <- DEFAULT_BEAT_SOURCES
  }
  
  if (!is.null(mock_response)) {
    status <- mock_response$status %||% "HEALTHY"
    sources_polled <- mock_response$sources_polled %||% length(beat_sources)
    sources_succeeded <- mock_response$sources_succeeded %||% length(beat_sources)
    claims_found <- mock_response$claims_found %||% 0
    
    if (claims_found > 0) {
      snapshot_raw_response(
        mock_response$content %||% "MOCK_BEAT_CONTENT",
        "beat_feeds", "mock_beat", "txt", archive_dir
      )
    }
    
    return(list(
      status = status,
      sources_polled = sources_polled,
      sources_succeeded = sources_succeeded,
      claims_found = claims_found
    ))
  }
  
  if (isTRUE(dry_run)) {
    for (src in beat_sources) {
      sim_text <- sprintf("Beat reporting from %s: pending rumors and scouting observations.", src$name)
      snapshot_raw_response(sim_text, "beat_feeds", src$id, "txt", archive_dir)
    }
    return(list(
      status = "HEALTHY",
      sources_polled = length(beat_sources),
      sources_succeeded = length(beat_sources),
      claims_found = 8
    ))
  }
  
  sources_polled <- length(beat_sources)
  sources_succeeded <- 0
  claims_found <- 0
  
  for (src in beat_sources) {
    res <- tryCatch({
      h <- curl::curl_fetch_memory(src$url)
      h
    }, error = function(e) {
      warning("Warning polling beat feed ", src$name, " (", src$url, "): ", e$message)
      NULL
    })
    
    if (!is.null(res) && res$status_code >= 200 && res$status_code < 400) {
      sources_succeeded <- sources_succeeded + 1
      snapshot_raw_response(res$content, "beat_feeds", src$id, "xml", archive_dir)
      
      # Parse items count
      raw_str <- rawToChar(res$content)
      item_matches <- gregexpr("<item|<entry", raw_str, ignore.case = TRUE)[[1]]
      if (item_matches[1] != -1) {
        claims_found <- claims_found + length(item_matches)
      }
    }
  }
  
  status <- if (sources_succeeded == sources_polled) {
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
    claims_found = claims_found
  )
}

# ------------------------------------------------------------------------------
# Composite Health & Governance Policy
# ------------------------------------------------------------------------------
compute_composite_health <- function(wire_res, releases_res, beat_res) {
  # Composite is HEALTHY only if all adapters are HEALTHY
  if (identical(wire_res$status, "HEALTHY") &&
      identical(releases_res$status, "HEALTHY") &&
      identical(beat_res$status, "HEALTHY")) {
    return("HEALTHY")
  }
  
  if (identical(wire_res$status, "FAILED") ||
      (identical(releases_res$status, "FAILED") && identical(beat_res$status, "FAILED"))) {
    return("FAILED")
  }
  
  "DEGRADED"
}

# Evaluates whether quiet week can be asserted
can_assert_quiet_week <- function(manifest) {
  isTRUE(manifest$composite_health == "HEALTHY")
}

# Evaluates publication gate rule per Blueprint §2 & §10
check_publication_gate <- function(manifest, allow_degraded = FALSE) {
  wire_failed <- identical(manifest$adapters$league_wire$status, "FAILED")
  
  if (wire_failed && !allow_degraded) {
    return(list(
      allowed = FALSE,
      reason = "Publication blocked: league_wire status is FAILED. Operator override required via --allow-degraded."
    ))
  }
  
  if (wire_failed && allow_degraded) {
    return(list(
      allowed = TRUE,
      advisory = TRUE,
      promotion_frozen = TRUE,
      reason = "Publication allowed under --allow-degraded. Advisory banner required; baseline promotion PROHIBITED."
    ))
  }
  
  list(
    allowed = TRUE,
    advisory = (manifest$composite_health != "HEALTHY"),
    promotion_frozen = FALSE,
    reason = "Publication allowed."
  )
}

# ------------------------------------------------------------------------------
# Main Ingestion Orchestrator
# ------------------------------------------------------------------------------
run_ingestion <- function(dry_run = FALSE,
                          allow_degraded = FALSE,
                          output_manifest = file.path("cache", "ingestion_manifest.json"),
                          archive_dir = NULL,
                          mock_wire = NULL,
                          mock_releases = NULL,
                          mock_beat = NULL) {
  
  if (is.null(archive_dir)) {
    date_str <- format(Sys.time(), "%Y%m%d")
    archive_dir <- file.path("cache", "raw_ingest_archive", date_str)
  }
  if (!dir.exists(archive_dir)) {
    dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  ingest_ts <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  # Run isolated adapters
  wire_res <- poll_league_wire(dry_run = dry_run, archive_dir = archive_dir, mock_response = mock_wire)
  releases_res <- poll_team_releases(dry_run = dry_run, archive_dir = archive_dir, mock_response = mock_releases)
  beat_res <- poll_beat_feeds(dry_run = dry_run, archive_dir = archive_dir, mock_response = mock_beat)
  
  comp_health <- compute_composite_health(wire_res, releases_res, beat_res)
  
  manifest <- list(
    ingest_timestamp = ingest_ts,
    composite_health = comp_health,
    adapters = list(
      league_wire = list(
        status = wire_res$status,
        http_code = wire_res$http_code,
        items_found = wire_res$items_found,
        bytes_captured = wire_res$bytes_captured
      ),
      team_releases = list(
        status = releases_res$status,
        feeds_polled = releases_res$feeds_polled,
        feeds_succeeded = releases_res$feeds_succeeded,
        items_found = releases_res$items_found
      ),
      beat_feeds = list(
        status = beat_res$status,
        sources_polled = beat_res$sources_polled,
        sources_succeeded = beat_res$sources_succeeded,
        claims_found = beat_res$claims_found
      )
    )
  )
  
  # Write manifest
  if (!is.null(output_manifest)) {
    manifest_dir <- dirname(output_manifest)
    if (!dir.exists(manifest_dir)) {
      dir.create(manifest_dir, recursive = TRUE, showWarnings = FALSE)
    }
    jsonlite::write_json(manifest, output_manifest, auto_unbox = TRUE, pretty = TRUE)
    message(">>> [INGEST] Ingestion manifest written to ", output_manifest)
  }
  
  # Check publication gate
  gate_eval <- check_publication_gate(manifest, allow_degraded = allow_degraded)
  if (!gate_eval$allowed) {
    message(">>> [GATE ALERT] ", gate_eval$reason)
  } else if (isTRUE(gate_eval$advisory)) {
    message(">>> [GATE ADVISORY] ", gate_eval$reason)
  } else {
    message(">>> [GATE OK] ", gate_eval$reason)
  }
  
  invisible(manifest)
}

# ------------------------------------------------------------------------------
# CLI Invocation Guard
# ------------------------------------------------------------------------------
if (sys.nframe() == 0) {
  cmd_args <- commandArgs(trailingOnly = TRUE)
  dry_run <- "--dry-run" %in% cmd_args
  allow_degraded <- "--allow-degraded" %in% cmd_args
  
  out_arg <- grep("^--output-manifest=", cmd_args, value = TRUE)
  out_path <- if (length(out_arg) > 0) sub("^--output-manifest=", "", out_arg[1]) else file.path("cache", "ingestion_manifest.json")
  
  manifest <- run_ingestion(
    dry_run = dry_run,
    allow_degraded = allow_degraded,
    output_manifest = out_path
  )
  
  gate_eval <- check_publication_gate(manifest, allow_degraded = allow_degraded)
  if (!gate_eval$allowed) {
    quit(status = 1)
  }
}
