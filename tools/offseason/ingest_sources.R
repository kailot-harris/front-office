# ==============================================================================
# ingest_sources.R
# WNBA Offseason Dynamics Monitor — Ingestion Subsystem & Health Gate (Phase 2)
#
# Implements multi-source weekly ingestion across isolated adapters:
#   1. league_wire: Official WNBA transaction wire & ESPN wire (paginated)
#   2. team_releases: Retired per #160 spike (15 franchise feeds non-existent)
#   3. beat_feeds: Beat feeds & reporter wire (6 active feeds per #160)
#
# Emits:
#   - Validated wire items conforming to canonical contract (Issue #159)
#   - cache/ingestion_manifest.json
#   - cache/raw_ingest_archive/YYYYMMDD/<adapter>_<timestamp>.(html|json|xml|txt)
#   - cache/raw_ingest_archive/YYYYMMDD/wire_items_normalized.json
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
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

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

# Source canonical wire items contract schema (Issue #159)
schema_path <- file.path("tools", "offseason", "wire_items_schema.R")
if (file.exists(schema_path)) {
  source(schema_path)
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

# Canonical beat sources (6 beat feeds per Blueprint §2 & Issue #160 spike)
# athletic_wnba replaced with just_womens_sports due to NYT migration (404)
DEFAULT_BEAT_SOURCES <- list(
  list(id = "the_next_hoops", name = "The Next Hoops", url = "https://thenexthoops.com/feed/"),
  list(id = "winsidr", name = "Winsidr", url = "https://winsidr.com/feed/"),
  list(id = "her_hoop_stats", name = "Her Hoop Stats", url = "https://herhoopstats.substack.com/feed"),
  list(id = "espn_wnba_beat", name = "ESPN Women's Hoops Desk", url = "https://www.espn.com/espn/rss/wnba/news"),
  list(id = "just_womens_sports", name = "Just Women's Sports", url = "https://justwomenssports.com/feed/"),
  list(id = "swish_appeal", name = "Swish Appeal", url = "https://www.swishappeal.com/rss/index.xml")
)

# ------------------------------------------------------------------------------
# HTTP Snapshot Helper (with dry-run quarantine)
# ------------------------------------------------------------------------------
snapshot_raw_response <- function(content, adapter_name, source_id, ext = "txt", archive_dir = NULL, dry_run = FALSE) {
  if (is.null(archive_dir)) {
    date_str <- format(Sys.time(), "%Y%m%d")
    if (isTRUE(dry_run)) {
      archive_dir <- file.path("cache", "dry_run_archive", date_str)
    } else {
      archive_dir <- file.path("cache", "raw_ingest_archive", date_str)
    }
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
# League Wire JSON Payload Parser
# Resolves Defect 2: uses transaction count (not column count), fails closed on parse errors
# ------------------------------------------------------------------------------
parse_league_wire_payload <- function(raw_content,
                                      observed_at = NULL,
                                      base_url = "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/transactions",
                                      start_index = 1L) {
  if (is.null(observed_at)) {
    observed_at <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
  
  txt <- if (is.raw(raw_content)) rawToChar(raw_content) else as.character(raw_content)
  parsed <- tryCatch({
    jsonlite::fromJSON(txt, simplifyVector = FALSE)
  }, error = function(e) {
    warning("JSON parse error in league wire payload: ", e$message)
    NULL
  })
  
  if (is.null(parsed) || !is.list(parsed)) {
    return(list(
      valid = FALSE,
      items_found = 0L,
      page_count = 0L,
      items = list(),
      error = "JSON parse failed"
    ))
  }
  
  tx_list <- parsed$transactions %||% list()
  page_count <- as.integer(parsed$pageCount %||% 1)
  if (is.na(page_count) || page_count < 1) page_count <- 1
  
  items <- list()
  for (i in seq_along(tx_list)) {
    tx <- tx_list[[i]]
    raw_desc <- trimws(as.character(tx$description %||% ""))
    if (!nzchar(raw_desc)) next
    
    tx_date <- as.character(tx$date %||% format(Sys.Date(), "%Y-%m-%d"))
    team_abbr <- NA_character_
    source_url <- NULL
    
    if (is.list(tx$team)) {
      if (!is.null(tx$team$abbreviation) && nzchar(tx$team$abbreviation)) {
        team_abbr <- as.character(tx$team$abbreviation)
      }
      if (!is.null(tx$team$links)) {
        links <- tx$team$links
        if (is.character(links) && length(links) > 0 && nzchar(links[1])) {
          source_url <- links[1]
        } else if (is.data.frame(links) && "href" %in% names(links) && length(links$href) > 0) {
          source_url <- as.character(links$href[1])
        } else if (is.list(links)) {
          if (!is.null(links$href)) {
            source_url <- as.character(links$href)
          } else if (length(links) > 0 && is.list(links[[1]]) && !is.null(links[[1]]$href)) {
            source_url <- as.character(links[[1]]$href)
          }
        }
      }
    }
    
    date_clean <- gsub("[^0-9]", "", substr(tx_date, 1, 10))
    abbr_clean <- tolower(if (!is.na(team_abbr) && nzchar(team_abbr)) team_abbr else "league")
    item_id <- sprintf("espn_wire_%s_%s_%03d", date_clean, abbr_clean, start_index + i - 1L)
    
    item <- create_wire_item(
      item_id = item_id,
      source_family = "league_wire",
      source_id = "espn",
      source_url = source_url %||% base_url,
      observed_at = observed_at,
      event_date = tx_date,
      raw_text = raw_desc,
      team_abbr = team_abbr
    )
    items[[length(items) + 1L]] <- item
  }
  
  list(
    valid = TRUE,
    items_found = length(items),
    page_count = page_count,
    items = items,
    error = NULL
  )
}

# ------------------------------------------------------------------------------
# Adapter 1: League Transaction Wire (Paginated across all pages up to pageCount)
# ------------------------------------------------------------------------------
poll_league_wire <- function(dry_run = FALSE,
                             archive_dir = NULL,
                             mock_response = NULL,
                             fetch_fn = curl::curl_fetch_memory,
                             base_url = "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/transactions",
                             max_pages = NULL) {
  message(">>> [INGEST] Polling League Transaction Wire adapter...")
  ingest_ts <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  if (!is.null(mock_response)) {
    status <- mock_response$status %||% "HEALTHY"
    http_code <- mock_response$http_code %||% 200
    items <- mock_response$items %||% list()
    bytes_captured <- mock_response$bytes_captured %||% 0
    items_found <- mock_response$items_found %||% length(items)
    
    if (bytes_captured > 0 && !is.null(archive_dir)) {
      snapshot_raw_response(
        mock_response$content %||% "MOCK_WIRE_CONTENT",
        "league_wire", "primary_wire", "json", archive_dir, dry_run = dry_run
      )
    }
    
    return(list(
      status = status,
      http_code = http_code,
      items_found = items_found,
      bytes_captured = bytes_captured,
      items = items
    ))
  }
  
  if (isTRUE(dry_run)) {
    # In dry-run mode, simulate validated wire items and snapshot to dry-run path
    sim_items <- list(
      create_wire_item(
        item_id = "espn_wire_20261031_ny_001",
        source_family = "league_wire",
        source_id = "espn_simulated",
        source_url = "https://www.espn.com/wnba/team/_/name/ny/new-york-liberty",
        observed_at = ingest_ts,
        event_date = "2026-10-31",
        raw_text = "Signed free agent guard to extension.",
        team_abbr = "NY"
      ),
      create_wire_item(
        item_id = "espn_wire_20261031_lv_002",
        source_family = "league_wire",
        source_id = "espn_simulated",
        source_url = "https://www.espn.com/wnba/team/_/name/lv/las-vegas-aces",
        observed_at = ingest_ts,
        event_date = "2026-10-31",
        raw_text = "Exercised fourth-year team option.",
        team_abbr = "LV"
      ),
      create_wire_item(
        item_id = "espn_wire_20261031_con_003",
        source_family = "league_wire",
        source_id = "espn_simulated",
        source_url = "https://www.espn.com/wnba/team/_/name/con/connecticut-sun",
        observed_at = ingest_ts,
        event_date = "2026-10-31",
        raw_text = "Cored forward for 2027 season.",
        team_abbr = "CON"
      )
    )
    sim_data <- list(
      transactions = lapply(sim_items, function(it) {
        list(date = it$event_date, team = it$team_abbr, text = it$raw_text)
      })
    )
    json_bytes <- jsonlite::toJSON(sim_data, auto_unbox = TRUE, pretty = TRUE)
    snapshot_raw_response(json_bytes, "league_wire", "simulated", "json", archive_dir, dry_run = TRUE)
    
    return(list(
      status = "HEALTHY",
      http_code = 200,
      items_found = length(sim_items),
      bytes_captured = nchar(as.character(json_bytes)),
      items = sim_items
    ))
  }
  
  # Live poll: ESPN WNBA transactions endpoint with pagination loop
  total_bytes <- 0
  all_items <- list()
  http_code <- 0
  adapter_status <- "FAILED"
  
  # Fetch Page 1
  res1 <- tryCatch({
    fetch_fn(base_url)
  }, error = function(e) {
    warning("Error fetching wire from ", base_url, ": ", e$message)
    NULL
  })
  
  if (!is.null(res1)) {
    http_code <- res1$status_code
    if (res1$status_code >= 200 && res1$status_code < 300) {
      body_len <- length(res1$content)
      total_bytes <- total_bytes + body_len
      snapshot_raw_response(res1$content, "league_wire", "espn_p1", "json", archive_dir, dry_run = FALSE)
      
      p1_parsed <- parse_league_wire_payload(res1$content, observed_at = ingest_ts, base_url = base_url, start_index = 1L)
      
      if (!p1_parsed$valid) {
        # Parse error: report FAILED, never increment items + 1
        warning("Failed to parse league wire JSON from primary endpoint.")
        return(list(
          status = "FAILED",
          http_code = http_code,
          items_found = 0L,
          bytes_captured = total_bytes,
          items = list()
        ))
      }
      
      all_items <- p1_parsed$items
      page_count <- p1_parsed$page_count
      if (!is.null(max_pages) && max_pages < page_count) {
        page_count <- max_pages
      }
      
      # Paginate to exhaustion across remaining pages (up to pageCount)
      if (page_count > 1) {
        for (p in 2:page_count) {
          page_url <- if (grepl("\\?", base_url)) {
            sprintf("%s&page=%d", base_url, p)
          } else {
            sprintf("%s?page=%d", base_url, p)
          }
          
          res_p <- tryCatch({
            fetch_fn(page_url)
          }, error = function(e) {
            warning("Error fetching league wire page ", p, " from ", page_url, ": ", e$message)
            NULL
          })
          
          if (!is.null(res_p) && res_p$status_code >= 200 && res_p$status_code < 300) {
            total_bytes <- total_bytes + length(res_p$content)
            snapshot_raw_response(res_p$content, "league_wire", sprintf("espn_p%d", p), "json", archive_dir, dry_run = FALSE)
            p_parsed <- parse_league_wire_payload(
              res_p$content,
              observed_at = ingest_ts,
              base_url = base_url,
              start_index = length(all_items) + 1L
            )
            if (p_parsed$valid && length(p_parsed$items) > 0) {
              all_items <- c(all_items, p_parsed$items)
            }
          } else {
            warning("Failed to retrieve league wire page ", p, " (status: ", if (is.null(res_p)) "error" else res_p$status_code, ")")
          }
        }
      }
      
      adapter_status <- "HEALTHY"
      return(list(
        status = adapter_status,
        http_code = http_code,
        items_found = length(all_items),
        bytes_captured = total_bytes,
        items = all_items
      ))
    }
  }
  
  # Secondary fallback endpoint: WNBA transactions portal
  fallback_url <- "https://www.wnba.com/transactions"
  res_fb <- tryCatch({
    fetch_fn(fallback_url)
  }, error = function(e) {
    warning("Error fetching fallback wire from ", fallback_url, ": ", e$message)
    NULL
  })
  
  if (!is.null(res_fb) && res_fb$status_code >= 200 && res_fb$status_code < 300) {
    http_code <- res_fb$status_code
    total_bytes <- total_bytes + length(res_fb$content)
    snapshot_raw_response(res_fb$content, "league_wire", "wnba_com", "html", archive_dir, dry_run = FALSE)
    
    html_text <- rawToChar(res_fb$content)
    matches <- gregexpr("<tr|<li class=[\"'][^\"']*transaction", html_text, ignore.case = TRUE)[[1]]
    if (matches[1] != -1) {
      items_count <- length(matches)
      adapter_status <- "HEALTHY"
    } else {
      # Parse failure / no transactions parsed: do NOT increment items + 1
      items_count <- 0L
      adapter_status <- "FAILED"
    }
    
    return(list(
      status = adapter_status,
      http_code = http_code,
      items_found = items_count,
      bytes_captured = total_bytes,
      items = list()
    ))
  }
  
  list(
    status = "FAILED",
    http_code = http_code,
    items_found = 0L,
    bytes_captured = total_bytes,
    items = list()
  )
}

# ------------------------------------------------------------------------------
# Adapter 2: Team Press Releases & News Portals (Retired per Issue #160 Spike)
# ------------------------------------------------------------------------------
poll_team_releases <- function(teams = NULL, dry_run = FALSE, archive_dir = NULL, mock_response = NULL) {
  # Retired per Issue #160 Feed Inventory Spike:
  # All 15 franchise URLs return 404/403 with no public RSS/XML feeds.
  # This adapter is permanently retired from active polling and composite health gating.
  message(">>> [INGEST] Team Press Release adapter retired per #160 feed inventory spike.")
  
  if (!is.null(mock_response)) {
    return(mock_response)
  }
  
  list(
    status = "RETIRED",
    feeds_polled = 0L,
    feeds_succeeded = 0L,
    items_found = 0L,
    items = list(),
    retired = TRUE,
    reason = "No public RSS feeds exist across 15 franchise portals per #160 spike."
  )
}

# ------------------------------------------------------------------------------
# Adapter 3: National & Team Beat Feeds
# ------------------------------------------------------------------------------
poll_beat_feeds <- function(beat_sources = NULL, dry_run = FALSE, archive_dir = NULL, mock_response = NULL) {
  message(">>> [INGEST] Polling Beat Feeds adapter...")
  ingest_ts <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  if (is.null(beat_sources)) {
    beat_sources <- DEFAULT_BEAT_SOURCES
  }
  
  if (!is.null(mock_response)) {
    status <- mock_response$status %||% "HEALTHY"
    sources_polled <- mock_response$sources_polled %||% length(beat_sources)
    sources_succeeded <- mock_response$sources_succeeded %||% length(beat_sources)
    claims_found <- mock_response$claims_found %||% 0
    items <- mock_response$items %||% list()
    
    if (claims_found > 0 && !is.null(archive_dir)) {
      snapshot_raw_response(
        mock_response$content %||% "MOCK_BEAT_CONTENT",
        "beat_feeds", "mock_beat", "txt", archive_dir, dry_run = dry_run
      )
    }
    
    return(list(
      status = status,
      sources_polled = sources_polled,
      sources_succeeded = sources_succeeded,
      claims_found = claims_found,
      items = items
    ))
  }
  
  if (isTRUE(dry_run)) {
    for (src in beat_sources) {
      sim_text <- sprintf("Beat reporting from %s: pending rumors and scouting observations.", src$name)
      snapshot_raw_response(sim_text, "beat_feeds", src$id, "txt", archive_dir, dry_run = TRUE)
    }
    return(list(
      status = "HEALTHY",
      sources_polled = length(beat_sources),
      sources_succeeded = length(beat_sources),
      claims_found = 8L,
      items = list()
    ))
  }
  
  sources_polled <- length(beat_sources)
  sources_succeeded <- 0L
  claims_found <- 0L
  beat_items <- list()
  
  for (src in beat_sources) {
    res <- tryCatch({
      curl::curl_fetch_memory(src$url)
    }, error = function(e) {
      warning("Warning polling beat feed ", src$name, " (", src$url, "): ", e$message)
      NULL
    })
    
    if (!is.null(res) && res$status_code >= 200 && res$status_code < 400) {
      sources_succeeded <- sources_succeeded + 1L
      snapshot_raw_response(res$content, "beat_feeds", src$id, "xml", archive_dir, dry_run = FALSE)
      
      feed_parsed_items <- list()
      if (requireNamespace("xml2", quietly = TRUE)) {
        doc <- tryCatch(xml2::read_xml(res$content), error = function(e) NULL)
        if (!is.null(doc)) {
          nodes <- xml2::xml_find_all(doc, "//item | //entry")
          for (idx in seq_along(nodes)) {
            node <- nodes[[idx]]
            title <- xml2::xml_text(xml2::xml_find_first(node, "title"))
            desc <- xml2::xml_text(xml2::xml_find_first(node, "description | summary | content"))
            link_node <- xml2::xml_find_first(node, "link | link/@href")
            link <- if (!is.na(link_node)) xml2::xml_text(link_node) else src$url
            pub_date <- xml2::xml_text(xml2::xml_find_first(node, "pubDate | published | updated | dc:date"))
            
            event_date <- tryCatch({
              dt <- as.POSIXct(pub_date, format = "%a, %d %b %Y %H:%M:%S", tz = "GMT")
              if (is.na(dt)) dt <- as.POSIXct(pub_date, tz = "UTC")
              if (is.na(dt)) format(Sys.Date(), "%Y-%m-%d") else strftime(dt, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
            }, error = function(e) format(Sys.Date(), "%Y-%m-%d"))
            
            raw_text <- trimws(paste(c(title, desc), collapse = " - "))
            if (!nzchar(raw_text)) next
            
            item_id <- sprintf("beat_%s_%03d", src$id, length(beat_items) + length(feed_parsed_items) + 1L)
            item <- create_wire_item(
              item_id = item_id,
              source_family = "beat_feeds",
              source_id = src$id,
              source_url = if (nzchar(link)) link else src$url,
              observed_at = ingest_ts,
              event_date = event_date,
              raw_text = raw_text,
              team_abbr = NA_character_
            )
            feed_parsed_items[[length(feed_parsed_items) + 1L]] <- item
          }
        }
      }
      
      if (length(feed_parsed_items) > 0) {
        claims_found <- claims_found + length(feed_parsed_items)
        beat_items <- c(beat_items, feed_parsed_items)
      } else {
        # Fallback regex count if xml2 parsing produced 0 or was unavailable
        raw_str <- rawToChar(res$content)
        item_matches <- gregexpr("<item|<entry", raw_str, ignore.case = TRUE)[[1]]
        if (item_matches[1] != -1) {
          claims_found <- claims_found + length(item_matches)
        }
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
    claims_found = claims_found,
    items = beat_items
  )
}

# ------------------------------------------------------------------------------
# Composite Health & Governance Policy
# team_releases is retired per #160 and does not block or downgrade composite health
# ------------------------------------------------------------------------------
compute_composite_health <- function(wire_res, releases_res = NULL, beat_res = NULL) {
  # Support both 2-arg compute_composite_health(wire, beat)
  # and 3-arg compute_composite_health(wire, releases, beat).
  # team_releases is retired per #160 spike and does not block or downgrade composite health.
  if (is.null(beat_res) && !is.null(releases_res)) {
    # 2-arg invocation where releases_res was actually beat_res
    beat_res <- releases_res
    releases_res <- NULL
  }
  
  wire_status <- wire_res$status %||% "UNKNOWN"
  beat_status <- if (!is.null(beat_res)) (beat_res$status %||% "UNKNOWN") else "HEALTHY"
  
  # Wire failure is critical: blocks composite health
  if (identical(wire_status, "FAILED")) {
    return("FAILED")
  }
  
  # Wire healthy + Beat feeds healthy -> HEALTHY
  if (identical(wire_status, "HEALTHY") && identical(beat_status, "HEALTHY")) {
    return("HEALTHY")
  }
  
  # Wire healthy + Beat feeds degraded or failed -> DEGRADED (advisory banner, non-blocking)
  if (identical(wire_status, "HEALTHY") && (identical(beat_status, "DEGRADED") || identical(beat_status, "FAILED"))) {
    return("DEGRADED")
  }
  
  "DEGRADED"
}

# Evaluates whether quiet week can be asserted
can_assert_quiet_week <- function(manifest) {
  if (is.list(manifest) && "manifest" %in% names(manifest) && !("composite_health" %in% names(manifest))) {
    manifest <- manifest$manifest
  }
  isTRUE(manifest$composite_health == "HEALTHY")
}

# Evaluates publication gate rule per Blueprint §2 & §10
check_publication_gate <- function(manifest, allow_degraded = FALSE) {
  if (is.list(manifest) && "manifest" %in% names(manifest) && !("adapters" %in% names(manifest))) {
    manifest <- manifest$manifest
  }
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
# Emits both manifest and validated canonical wire items per Issue #159 contract
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
    if (isTRUE(dry_run)) {
      archive_dir <- file.path("cache", "dry_run_archive", date_str)
    } else {
      archive_dir <- file.path("cache", "raw_ingest_archive", date_str)
    }
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
  
  # Collect and validate all produced wire items
  all_items <- c(
    wire_res$items %||% list(),
    beat_res$items %||% list(),
    releases_res$items %||% list()
  )
  
  if (exists("validate_wire_items", mode = "function")) {
    val_res <- validate_wire_items(all_items, stop_on_error = FALSE, detailed = TRUE, allow_empty = TRUE)
    if (!val_res$valid) {
      warning("Wire items validation warnings (", length(val_res$errors), " errors):\n",
              paste(paste0("  - ", head(val_res$errors, 10)), collapse = "\n"))
    }
  }
  
  # Snapshot normalized wire items to archive directory
  if (length(all_items) > 0 && exists("write_wire_items", mode = "function")) {
    norm_path <- file.path(archive_dir, "wire_items_normalized.json")
    tryCatch({
      write_wire_items(all_items, norm_path, validate = FALSE)
    }, error = function(e) {
      warning("Failed to write wire_items_normalized.json: ", e$message)
    })
  }
  
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
  
  invisible(list(
    manifest = manifest,
    items = all_items,
    composite_health = manifest$composite_health,
    adapters = manifest$adapters
  ))
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
  
  res <- run_ingestion(
    dry_run = dry_run,
    allow_degraded = allow_degraded,
    output_manifest = out_path
  )
  
  gate_eval <- check_publication_gate(res$manifest, allow_degraded = allow_degraded)
  if (!gate_eval$allowed) {
    quit(status = 1)
  }
}
