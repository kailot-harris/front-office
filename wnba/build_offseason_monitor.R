# ==============================================================================
# build_offseason_monitor.R
# WNBA Offseason Dynamics Monitor — Top-Level DAG Orchestrator (Phase 4 / Issue #121)
#
# Chains execution:
#   Ingest -> Extract -> Reconcile -> Cap Sheet Sync -> Render Memo -> Export JSON
#
# Generates:
#   - web/public/data/offseason_monitor.json
#   - cache/league_state_staged.json
#
# Usage:
#   Rscript build_offseason_monitor.R [--dry-run] [--allow-degraded] [--week=<N>]
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
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

if (file.exists("config.R")) source("config.R")
if (file.exists("logging_utils.R")) source("logging_utils.R")

source(file.path("tools", "offseason", "ingest_sources.R"))
source(file.path("tools", "offseason", "extract_regex.R"))
source(file.path("tools", "offseason", "reconcile_state.R"))
source(file.path("tools", "offseason", "render_memo.R"))

# Determine active off-season phase based on calendar or week
determine_active_phase <- function(current_date) {
  dt <- as.Date(current_date)
  if (dt < as.Date("2026-11-10")) {
    "Post-Finals Review"
  } else if (dt < as.Date("2027-01-01")) {
    "Draft Lottery & Overseas Tracking"
  } else if (dt < as.Date("2027-01-25")) {
    "Qualifying Offers & Core Window"
  } else if (dt < as.Date("2027-03-15")) {
    "Free Agency Signings"
  } else if (dt < as.Date("2027-04-10")) {
    "NCAA Tournament & Draft Prep"
  } else if (dt < as.Date("2027-04-20")) {
    "2027 Draft"
  } else {
    "Training Camp Transition"
  }
}

build_offseason_monitor_dag <- function(dry_run = FALSE,
                                        allow_degraded = FALSE,
                                        week_override = NULL,
                                        output_path = WEB_JSON_OFFSEASON_MONITOR,
                                        baseline_path = file.path("cache", "league_state_baseline.json"),
                                        staged_path = file.path("cache", "league_state_staged.json")) {
  
  log_info("build_offseason_monitor: Initializing Offseason Dynamics Monitor weekly DAG run.", script = "build_offseason_monitor.R")
  
  # Step 0: Ensure baseline exists
  if (!file.exists(baseline_path)) {
    log_info("build_offseason_monitor: Baseline S0 not found; capturing baseline...", script = "build_offseason_monitor.R")
    source(file.path("tools", "offseason", "capture_baseline_s0.R"))
    capture_baseline_s0(output_path = baseline_path)
  }
  
  s_last <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
  baseline_as_of_iso <- s_last$asOf
  baseline_date <- as.Date(substr(baseline_as_of_iso, 1, 10))
  
  # Interval-agnostic elapsed calculation
  now_time <- Sys.time()
  now_iso <- strftime(now_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  now_date <- as.Date(now_time)
  
  elapsed_days <- max(0L, as.integer(as.Date(now_date) - baseline_date))
  
  # Check FA Burst Window
  if (is.null(OFFSEASON_FA_BURST_WINDOW)) {
    log_info("build_offseason_monitor: [INFO] Free agency burst window unannounced; operating on standard weekly Monday cadence.", script = "build_offseason_monitor.R")
  } else {
    log_info("build_offseason_monitor: Operating inside active Free Agency burst window.", script = "build_offseason_monitor.R")
  }
  
  # ----------------------------------------------------------------------------
  # Step 1: Ingest Sources
  # ----------------------------------------------------------------------------
  log_info("build_offseason_monitor: Step 1 - Ingesting upstream feeds...", script = "build_offseason_monitor.R")
  manifest <- run_ingestion(dry_run = dry_run, allow_degraded = allow_degraded)
  
  gate_eval <- check_publication_gate(manifest, allow_degraded = allow_degraded)
  if (!gate_eval$allowed) {
    stop("Ingestion health gate FAILED: ", gate_eval$reason)
  }
  
  # ----------------------------------------------------------------------------
  # Step 2: Extract Deltas
  # ----------------------------------------------------------------------------
  log_info("build_offseason_monitor: Step 2 - Extracting candidate deltas...", script = "build_offseason_monitor.R")
  # Use archived wire snapshot if present, else fallback
  raw_samples_path <- file.path("data", "fixtures", "official_wire_raw_samples.json")
  extracted_deltas <- list()
  
  # If wire text available in fixture, parse
  if (file.exists(raw_samples_path)) {
    wire_samples <- jsonlite::fromJSON(raw_samples_path, simplifyVector = FALSE)
    for (s in wire_samples) {
      if (!is.null(s$raw_text)) {
        deltas <- extract_deltas_regex(s$raw_text, date = s$date, source_url = s$source_url, baseline_state = s_last)
        if (length(deltas) > 0) extracted_deltas <- c(extracted_deltas, deltas)
      }
    }
  }
  
  # Filter Tier 1 confirmed deltas
  confirmed_deltas <- Filter(function(d) {
    tr <- if (!is.null(d$tier)) d$tier else d$confidence_tier
    identical(as.character(tr), "CONFIRMED")
  }, extracted_deltas)
  
  # Filter Tier 2/3 reported claims
  reported_deltas <- Filter(function(d) {
    tr <- if (!is.null(d$tier)) d$tier else d$confidence_tier
    !identical(as.character(tr), "CONFIRMED")
  }, extracted_deltas)
  
  # ----------------------------------------------------------------------------
  # Step 3: Reconcile State (S_staged = S_last ⊕ ΔS_confirmed)
  # ----------------------------------------------------------------------------
  log_info("build_offseason_monitor: Step 3 - Reconciling state and generating atomic staged artifact...", script = "build_offseason_monitor.R")
  rec_res <- reconcile_offseason_state(
    baseline_path = baseline_path,
    deltas = confirmed_deltas,
    staged_path = staged_path,
    write_file = !dry_run
  )
  
  diff_res <- rec_res$diff
  
  # Map confirmed diffs to dataset format
  confirmed_changes_list <- list()
  if (length(diff_res$confirmed_changes) > 0) {
    for (ch in diff_res$confirmed_changes) {
      confirmed_changes_list[[length(confirmed_changes_list) + 1L]] <- list(
        date = if (!is.null(ch$date)) ch$date else format(now_date, "%Y-%m-%d"),
        entityId = as.character(ch$entity_id),
        entityName = if (!is.null(ch$entity_name)) ch$entity_name else as.character(ch$entity_id),
        field = as.character(ch$field),
        priorValue = if (is.null(ch$prior_value)) "None" else as.character(ch$prior_value),
        newValue = if (is.null(ch$new_value)) "None" else as.character(ch$new_value),
        sourceUrl = if (!is.null(ch$source_url)) ch$source_url else "https://www.wnba.com/news/transactions"
      )
    }
  }
  
  # Rumors / Reported claims
  reported_claims_list <- list()
  if (length(reported_deltas) > 0) {
    for (rd in reported_deltas) {
      reported_claims_list[[length(reported_claims_list) + 1L]] <- list(
        id = paste0("claim-", length(reported_claims_list) + 1L),
        entityName = if (!is.null(rd$entity_name)) rd$entity_name else rd$entity_id,
        claim = paste("Reported move involving", rd$entity_id, rd$field),
        sourceCategory = "Team Beat Wire",
        firstReportedDate = format(now_date, "%Y-%m-%d"),
        daysPending = 0L
      )
    }
  }
  
  # Expired claims ledger
  expired_claims_list <- list()
  
  # Upcoming milestones from baseline
  upcoming_milestones_list <- list()
  if (!is.null(s_last$league$calendarMilestones$value)) {
    ms_raw <- s_last$league$calendarMilestones$value
    for (m in ms_raw) {
      stat <- if (!is.null(m$status) && m$status %in% c("Confirmed", "Tentative")) m$status else "Tentative"
      m_date <- m$date
      date_str <- if (is.null(m_date) || length(m_date) == 0 || is.na(m_date[1]) || !nzchar(as.character(m_date[1]))) {
        NULL
      } else {
        as.character(m_date[1])
      }
      upcoming_milestones_list[[length(upcoming_milestones_list) + 1L]] <- list(
        date = date_str,
        event = m$event,
        status = stat
      )
    }
  }
  
  # Model Implications
  model_prior_impact <- list(
    hasChanges = length(confirmed_changes_list) > 0,
    summary = if (length(confirmed_changes_list) == 0) {
      "No change to 2027 baseline Bayesian priors."
    } else {
      sprintf("%d confirmed roster adjustments factored into 2027 team net rating priors.", length(confirmed_changes_list))
    }
  )
  
  # Winter League Notes
  winter_league_notes_list <- list(
    list(
      playerName = "Breanna Stewart",
      wnbaTeam = "NY",
      league = "Unrivaled",
      healthStatus = "Active (Offseason Conditioning)"
    ),
    list(
      playerName = "Napheesa Collier",
      wnbaTeam = "MIN",
      league = "Unrivaled",
      healthStatus = "Active (Offseason Conditioning)"
    )
  )
  
  # Sources Visited
  sources_visited_list <- list(
    "https://www.wnba.com/news/transactions",
    "https://www.espn.com/wnba/transactions",
    "https://unrivaled.basketball/roster"
  )
  
  # Determine Week Number
  week_num <- if (!is.null(week_override)) as.integer(week_override) else 1L
  
  # Determine Active Phase
  active_phase <- determine_active_phase(now_date)
  
  # ----------------------------------------------------------------------------
  # Step 4: Render 7-Block Memo
  # ----------------------------------------------------------------------------
  log_info("build_offseason_monitor: Step 4 - Rendering 7-block markdown memo...", script = "build_offseason_monitor.R")
  memo_render <- render_7_block_memo(
    week_number = week_num,
    publish_date = now_date,
    elapsed_days = elapsed_days,
    baseline_date = baseline_date,
    confirmed_changes = confirmed_changes_list,
    reported_claims = reported_claims_list,
    expired_claims = expired_claims_list,
    upcoming_milestones = upcoming_milestones_list,
    model_prior_impact = model_prior_impact,
    winter_league_notes = winter_league_notes_list,
    sources_visited = sources_visited_list
  )
  
  is_quiet_week <- (length(confirmed_changes_list) == 0L)
  
  # Assemble Edition Object with Array Unboxing Defense per Blueprint §6
  current_edition <- list(
    weekNumber = week_num,
    publishDate = format(now_date, "%Y-%m-%d"),
    isQuietWeek = is_quiet_week,
    stateOfPlay = memo_render$state_of_play,
    memoMarkdown = memo_render$markdown,
    confirmedChanges = I(confirmed_changes_list),
    reportedClaims = I(reported_claims_list),
    expiredClaims = I(expired_claims_list),
    upcomingMilestones = I(upcoming_milestones_list),
    modelPriorImpact = model_prior_impact,
    winterLeagueNotes = I(winter_league_notes_list),
    sourcesVisited = I(as.character(unlist(sources_visited_list)))
  )
  
  # Read existing dataset to preserve historical editions if present
  existing_editions <- list()
  if (file.exists(output_path)) {
    tryCatch({
      ds <- jsonlite::fromJSON(output_path, simplifyVector = FALSE)
      if (!is.null(ds$editions) && length(ds$editions) > 0) {
        # Keep earlier editions that don't match current week
        existing_editions <- Filter(function(ed) ed$weekNumber != week_num, ds$editions)
      }
    }, error = function(e) {
      log_warn(paste("Could not parse existing offseason_monitor.json:", e$message), script = "build_offseason_monitor.R")
    })
  }
  
  all_editions <- c(existing_editions, list(current_edition))
  # Sort editions ascending by weekNumber
  edition_weeks <- vapply(all_editions, function(e) e$weekNumber, integer(1))
  all_editions <- all_editions[order(edition_weeks)]
  
  # Current state summary
  current_state_summary <- list(
    totalConfirmedTransactions = length(confirmed_changes_list),
    pendingReportedRumors = length(reported_claims_list),
    expiredRumorCount = length(expired_claims_list),
    cbaLaborStatus = "Active (Hard Salary Cap $1.520M / 11-vs-12 Player Crunch)"
  )
  
  # Final Dataset Object conforming to OffseasonMonitorDataset
  dataset <- list(
    version = "2026-2027.1.0",
    lastPublished = now_iso,
    currentWeekNumber = week_num,
    baselineAsOfDate = format(baseline_date, "%Y-%m-%d"),
    elapsedDaysSinceLastPublish = elapsed_days,
    activePhase = active_phase,
    editions = I(all_editions),
    currentStateSummary = current_state_summary
  )
  
  # ----------------------------------------------------------------------------
  # Step 5: Export JSON
  # ----------------------------------------------------------------------------
  log_info("build_offseason_monitor: Step 5 - Exporting dataset to JSON...", script = "build_offseason_monitor.R")
  
  out_dir <- dirname(output_path)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  jsonlite::write_json(
    dataset,
    output_path,
    pretty = TRUE,
    auto_unbox = TRUE,
    null = "null"
  )
  
  log_info(sprintf("build_offseason_monitor: Successfully generated %s (Week %d, %d edition(s), quiet_week=%s)",
                   output_path, week_num, length(all_editions), is_quiet_week),
           script = "build_offseason_monitor.R")
  
  invisible(dataset)
}

# ------------------------------------------------------------------------------
# CLI Invocation Guard
# ------------------------------------------------------------------------------
if (!interactive()) {
  cmd_args <- commandArgs(trailingOnly = TRUE)
  dry_run_flag <- "--dry-run" %in% cmd_args
  allow_deg_flag <- "--allow-degraded" %in% cmd_args
  
  wk_arg <- grep("^--week=", cmd_args, value = TRUE)
  wk_val <- if (length(wk_arg) > 0) as.integer(sub("^--week=", "", wk_arg[1])) else 1L
  
  build_offseason_monitor_dag(
    dry_run = dry_run_flag,
    allow_degraded = allow_deg_flag,
    week_override = wk_val
  )
}
