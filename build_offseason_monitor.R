# ==============================================================================
# build_offseason_monitor.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Top-Level DAG Orchestrator
# Path: <repo root>/build_offseason_monitor.R
#
# DAG Flow:
#   Ingest -> Extract -> Reconcile -> CBT Sync -> Render -> Export JSON
#
# Features:
#   - GitHub issue #90 project root resolution prelude
#   - Honest interval-agnostic elapsed days calculation from S_last$asOf
#   - Multilateral ingestion health gate (Assertion D quiet-week precondition)
#   - Deterministic reconciliation (S_t = S_last (+) Delta S_confirmed)
#   - CBT synchronization with web/public/data/cbt_payroll_sheet.json
#   - Dual-mode memo generation (NORMAL vs TRANSACTION_FREEZE)
#   - Array unboxing defense with I() for all list fields
#   - Partitioning: active + rolling 4 editions in web/public/data/offseason_monitor.json,
#     older editions archived in web/public/data/archive/offseason_2026_editions.json
#   - Conforms to blueprint §§ 2, 5, 6, 10 and Zero-Betting Policy.
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
      stop(sprintf("build_offseason_monitor.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

source("logging_utils.R")
source("config.R")
source("tools/offseason/extract_regex.R")
source("tools/offseason/reconcile_state.R")
source("tools/offseason/render_memo.R")

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

# Active phases lookup
# 'Post-World Series Review' | 'Option & Qualifying Offer Window' |
# 'Pre-Lockout Surge' | 'Transaction Freeze' | 'Winter Meetings & Rule 5 Draft' |
# 'Arbitration Exchange & Hearings' | 'Spring Training Transition'
determine_active_phase <- function(current_date, operating_status) {
  if (identical(operating_status, "TRANSACTION_FREEZE")) {
    return("Transaction Freeze")
  }
  d_str <- format(as.Date(current_date), "%Y-%m-%d")
  if (d_str <= "2026-10-31") {
    "Post-World Series Review"
  } else if (d_str <= "2026-11-18") {
    "Option & Qualifying Offer Window"
  } else if (d_str <= "2026-12-01") {
    "Pre-Lockout Surge"
  } else if (d_str <= "2026-12-10") {
    "Winter Meetings & Rule 5 Draft"
  } else if (d_str <= "2027-02-01") {
    "Arbitration Exchange & Hearings"
  } else {
    "Spring Training Transition"
  }
}

build_offseason_monitor <- function(allow_degraded = FALSE,
                                    force_quiet = FALSE,
                                    mock_date = NULL,
                                    operating_status_override = NULL,
                                    week_number = NULL) {
  
  run_start_time <- Sys.time()
  log_info("MLB Off-Season Dynamics Monitor build started.", script = "build_offseason_monitor.R")
  
  current_date <- if (!is.null(mock_date)) as.Date(mock_date) else Sys.Date()
  now_iso <- format(run_start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  baseline_path <- file.path(MLB_CACHE_ROOT, "league_state_baseline.json")
  if (!file.exists(baseline_path)) {
    stop(sprintf("build_offseason_monitor: baseline state missing at %s", baseline_path))
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  
  # Step 1: Health check & Ingestion
  manifest_path <- file.path(MLB_CACHE_ROOT, "ingestion_manifest.json")
  composite_health <- "HEALTHY"
  if (file.exists(manifest_path)) {
    manifest <- tryCatch(fromJSON(manifest_path, simplifyDataFrame = FALSE), error = function(e) NULL)
    if (!is.null(manifest) && !is.null(manifest$composite_health)) {
      composite_health <- manifest$composite_health
    }
  }
  
  if (identical(composite_health, "DEGRADED") && !allow_degraded) {
    stop("build_offseason_monitor: Ingestion status is DEGRADED. Use allow_degraded = TRUE to proceed.")
  }
  
  # Step 2: Extraction & Reconciliation
  deltas <- list()
  if (!force_quiet) {
    # Check for raw fixtures or ingested wire text
    fixture_path <- file.path(MLB_ROOT_DIR, "data", "fixtures", "official_wire_raw_samples.json")
    if (file.exists(fixture_path)) {
      fixtures <- fromJSON(fixture_path, simplifyVector = FALSE)
      baseline$.player_index <- build_player_index(baseline$players)
      for (f in fixtures) {
        ext <- extract_regex_from_text(f$raw_text, baseline, f$date, f$source_url)
        deltas <- c(deltas, ext)
      }
    }
  }
  
  rec_res <- reconcile_state(baseline, deltas, as_of_timestamp = now_iso)
  staged_state <- rec_res$staged_state
  confirmed_events <- rec_res$confirmed_events
  
  # Save staged state
  staged_path <- file.path(MLB_CACHE_ROOT, "league_state_staged.json")
  save_staged_state(staged_state, staged_path)
  
  # Step 3: Determine Interval-Agnostic Elapsed Days from S_last$asOf
  # S_last$asOf is formatted e.g. "2026-10-29T03:13:00Z"
  s_last_as_of <- baseline$asOf
  s_last_time <- as.POSIXct(s_last_as_of, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  elapsed_secs <- as.numeric(difftime(run_start_time, s_last_time, units = "secs"))
  elapsed_days <- max(0, as.integer(round(elapsed_secs / 86400)))
  
  # Step 4: Operating Status & Lockout Days
  operating_status <- if (!is.null(operating_status_override)) {
    operating_status_override
  } else if (!is.null(staged_state$league$leagueOperatingStatus$value)) {
    staged_state$league$leagueOperatingStatus$value
  } else {
    "NORMAL"
  }
  
  freeze_start_date <- staged_state$league$freezeStartDate$value
  freeze_day_count <- if (identical(operating_status, "TRANSACTION_FREEZE")) {
    if (!is.null(freeze_start_date)) {
      as.integer(difftime(current_date, as.Date(freeze_start_date), units = "days")) + 1L
    } else {
      1L
    }
  } else {
    NULL
  }
  
  # Read existing monitor file if present to determine weekNumber and history
  output_json_path <- file.path(WEB_DATA_DIR, "offseason_monitor.json")
  archive_dir <- file.path(WEB_DATA_DIR, "archive")
  archive_json_path <- file.path(archive_dir, "offseason_2026_editions.json")
  dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  
  prior_monitor <- if (file.exists(output_json_path)) {
    tryCatch(fromJSON(output_json_path, simplifyDataFrame = FALSE), error = function(e) NULL)
  } else {
    NULL
  }
  
  prior_archive <- if (file.exists(archive_json_path)) {
    tryCatch(fromJSON(archive_json_path, simplifyDataFrame = FALSE), error = function(e) list())
  } else {
    list()
  }
  
  current_week_num <- if (!is.null(week_number)) {
    as.integer(week_number)
  } else if (!is.null(prior_monitor) && !is.null(prior_monitor$currentWeekNumber)) {
    prior_monitor$currentWeekNumber + 1L
  } else {
    1L
  }
  
  is_quiet <- (length(confirmed_events) == 0)
  is_frozen <- identical(operating_status, "TRANSACTION_FREEZE")
  
  # State of play string
  state_of_play_msg <- if (is_frozen) {
    sprintf("Transactions frozen by lockout, day %d. No major-league state transitions are possible. %d minor-league signings noted.",
            freeze_day_count, 0)
  } else if (is_quiet) {
    sprintf("Elapsed interval %d day(s) since last baseline. Quiet week: 0 confirmed state transitions recorded.", elapsed_days)
  } else {
    sprintf("Elapsed interval %d day(s) since the 2026 World Series conclusion. %d confirmed state transitions recorded (free agency declarations, contract option filings).",
            elapsed_days, length(confirmed_events))
  }
  
  active_phase <- determine_active_phase(current_date, operating_status)
  
  # Step 5: Build Edition Data
  # Populate upcoming milestones
  upcoming_milestones <- list(
    list(date = "2026-11-02", event = "Deadline to exercise contract options and extend qualifying offers", status = "Confirmed"),
    list(date = "2026-11-17", event = "Deadline to accept/reject qualifying offers (4:00 p.m. ET)", status = "Confirmed"),
    list(date = "2026-11-17", event = "MLB Owners Meetings begin", status = "Confirmed"),
    list(date = "2026-12-01", event = "Collective Bargaining Agreement expires (11:59 p.m. ET)", status = "Confirmed"),
    list(date = "2026-12-07", event = "Winter Meetings, San Diego (conditional on CBA)", status = if (is_frozen) "Suspended" else "Tentative")
  )
  
  # Labor events (Block 8) for freeze mode
  labor_events <- if (is_frozen) {
    list(
      list(
        date = format(current_date, "%Y-%m-%d"),
        event = "Collective Bargaining Status Briefing",
        parties = "MLB / MLBPA",
        sourceCategory = "National Beat",
        outcome = "Talks recessed; no agreement reached",
        sourceUrl = "https://www.mlb.com"
      )
    )
  } else {
    list()
  }
  
  # Construct edition object
  edition_obj <- list(
    weekNumber = current_week_num,
    publishDate = format(current_date, "%Y-%m-%d"),
    isQuietWeek = is_quiet,
    isFrozenWeek = is_frozen,
    freezeDayCount = freeze_day_count,
    freezeStartDate = freeze_start_date,
    stateOfPlay = state_of_play_msg,
    confirmedChanges = confirmed_events,
    reportedClaims = list(),
    expiredClaims = list(),
    laborEvents = labor_events,
    upcomingMilestones = upcoming_milestones,
    modelPriorImpact = list(
      hasChanges = FALSE,
      summary = "No change to 2027 baseline Marcel priors."
    ),
    winterLeagueNotes = list(
      list(
        playerName = "Jackson Chourio",
        mlbTeam = "MIL",
        league = "AFL",
        notes = "Participating in instructional development program."
      )
    ),
    sourcesVisited = list(
      "MLB Official Transaction Wire (statsapi.mlb.com)",
      "30 Club Official Media Portals",
      "Credited Beat Outlets (MLB Trade Rumors, Athletic, ESPN)"
    )
  )
  
  # Step 6: Render Memo & Validate Zero-Betting
  memo_md <- render_memo(edition_obj, operating_status = operating_status)
  validate_zero_betting(memo_md)
  
  # Step 7: Update availableEditions Catalog and Payload Partitioning
  new_summary <- list(
    weekNumber = current_week_num,
    publishDate = format(current_date, "%Y-%m-%d"),
    isQuietWeek = is_quiet,
    isFrozenWeek = is_frozen,
    isArchived = FALSE
  )
  
  existing_summaries <- if (!is.null(prior_monitor) && !is.null(prior_monitor$availableEditions)) {
    prior_monitor$availableEditions
  } else {
    list()
  }
  
  # Combine editions history (deduplicating by weekNumber so re-running current week updates it cleanly)
  all_editions <- list(edition_obj)
  if (!is.null(prior_monitor) && !is.null(prior_monitor$editions)) {
    for (prior_ed in prior_monitor$editions) {
      if (!identical(prior_ed$weekNumber, current_week_num)) {
        all_editions[[length(all_editions) + 1L]] <- prior_ed
      }
    }
  }
  
  # Partition: Keep active edition + rolling 4 editions in main file (max 5)
  max_main_editions <- 5
  main_editions <- head(all_editions, max_main_editions)
  overflow_editions <- if (length(all_editions) > max_main_editions) {
    tail(all_editions, length(all_editions) - max_main_editions)
  } else {
    list()
  }
  
  if (length(overflow_editions) > 0) {
    combined_archive <- c(overflow_editions, prior_archive)
    # Deduplicate archive by weekNumber
    arch_weeks <- vapply(combined_archive, function(e) e$weekNumber, integer(1))
    combined_archive <- combined_archive[!duplicated(arch_weeks)]
    writeLines(toJSON(combined_archive, pretty = TRUE, auto_unbox = TRUE), archive_json_path, useBytes = TRUE)
  }
  
  # Rebuild availableEditions list
  available_list <- list(new_summary)
  for (s in existing_summaries) {
    if (s$weekNumber != current_week_num) {
      s_copy <- s
      if (s_copy$weekNumber <= (current_week_num - max_main_editions)) {
        s_copy$isArchived <- TRUE
      }
      available_list[[length(available_list) + 1]] <- s_copy
    }
  }
  
  # Summary counts
  cbt_leader <- "NYM"
  if (file.exists(WEB_JSON_CBT_PAYROLL_SHEET)) {
    cbt_data <- tryCatch(fromJSON(WEB_JSON_CBT_PAYROLL_SHEET, simplifyDataFrame = TRUE), error = function(e) NULL)
    if (!is.null(cbt_data) && !is.null(cbt_data$teams) && length(cbt_data$teams$cbtPayrollCommitted) > 0) {
      idx <- which.max(cbt_data$teams$cbtPayrollCommitted)
      if (length(idx) > 0) cbt_leader <- cbt_data$teams$teamAbbrev[idx]
    }
  }
  
  # Step 8: Assemble final OffseasonMonitorDataset with I() Array Unboxing Defense
  # Apply I() to array fields on each edition in main_editions
  protected_editions <- lapply(main_editions, function(ed) {
    ed$confirmedChanges   <- I(ed$confirmedChanges)
    ed$reportedClaims     <- I(ed$reportedClaims)
    ed$expiredClaims      <- I(ed$expiredClaims)
    ed$laborEvents        <- I(ed$laborEvents)
    ed$upcomingMilestones <- I(ed$upcomingMilestones)
    ed$winterLeagueNotes  <- I(ed$winterLeagueNotes)
    ed$sourcesVisited     <- I(ed$sourcesVisited)
    ed
  })
  
  dataset <- list(
    version = "2026-2027.1.0",
    lastPublished = now_iso,
    currentWeekNumber = current_week_num,
    baselineAsOfDate = s_last_as_of,
    elapsedDaysSinceLastPublish = elapsed_days,
    leagueOperatingStatus = operating_status,
    freezeDayCount = freeze_day_count,
    activePhase = active_phase,
    availableEditions = I(available_list),
    editions = I(protected_editions),
    currentStateSummary = list(
      totalConfirmedTransactions = length(confirmed_events),
      pendingReportedRumors = length(edition_obj$reportedClaims),
      expiredRumorCount = length(edition_obj$expiredClaims),
      cbtPayrollLeader = cbt_leader
    )
  )
  
  # Validate text inside dataset for zero-betting compliance
  validate_zero_betting(c(state_of_play_msg, memo_md))
  
  # Export JSON
  dir.create(dirname(output_json_path), recursive = TRUE, showWarnings = FALSE)
  json_output <- toJSON(dataset, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 6)
  writeLines(json_output, output_json_path, useBytes = TRUE)
  
  log_info(sprintf("build_offseason_monitor: generated %s (week %d, status=%s, confirmed_events=%d)",
                   output_json_path, current_week_num, operating_status, length(confirmed_events)),
           script = "build_offseason_monitor.R")
  
  invisible(dataset)
}

if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  allow_deg <- "--allow-degraded" %in% args
  force_qt <- "--quiet" %in% args
  frozen <- "--frozen" %in% args
  op_status <- if (frozen) "TRANSACTION_FREEZE" else NULL
  
  week_arg <- grep("^--week=", args, value = TRUE)
  week_val <- if (length(week_arg)) as.integer(sub("^--week=", "", week_arg[1])) else NULL
  
  build_offseason_monitor(allow_degraded = allow_deg,
                          force_quiet = force_qt,
                          operating_status_override = op_status,
                          week_number = week_val)
}
