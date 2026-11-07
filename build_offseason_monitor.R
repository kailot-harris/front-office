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
#   - GitHub issue #58: the DAG's Ingest edge is real. Step 1 calls
#     ingest_all() and gates on the manifest *this* run produced, via
#     assert_ingest_freshness() (issue #59) as well as composite_health.
#     Step 2 extracts from the live wire-items artifact
#     cache/offseason_wire_items.json, whose shape is fixed by the issue #56
#     contract in docs/internal/offseason_wire_items_contract.md and is
#     validated by validate_wire_items() before extraction.
#   - GitHub issue #58: data/fixtures/official_wire_raw_samples.json is DEMOTED
#     to a test-only input behind fixture_mode / --fixture-mode. It is a
#     6-record benchmark fixture authored for issue #45 and frozen at
#     2026-10-29/30 -- not a feed. Its 6 deltas were promoted into the baseline
#     on 2026-10-31, so every run afterwards re-extracted the same 6, the
#     reconciler correctly deduped them as already-applied, confirmed_events
#     collapsed to 0, and the monitor published "Quiet week: 0 confirmed state
#     transitions recorded." for six days while the live wire carried 1,970
#     transactions (1,401 on 2026-11-02 alone). Reading it implicitly made the
#     monitor structurally incapable of reporting a non-quiet week. It is kept
#     only for benchmark continuity with #45. See issues #58 and #64.
#   - Multilateral ingestion health gate (Assertion D quiet-week precondition)
#   - Fail-closed quiet-week precondition: a zero confirmed-event count may only
#     publish as a quiet week when ingestion was fresh, healthy and actually
#     returned records (ingest_all()$can_assert_quiet_week). Zero deltas from
#     zero fetched items is a blind run, which blocks (issue #58, tracker #64).
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
                                    week_number = NULL,
                                    fixture_mode = FALSE) {
  
  run_start_time <- Sys.time()
  log_info("MLB Off-Season Dynamics Monitor build started.", script = "build_offseason_monitor.R")
  
  current_date <- if (!is.null(mock_date)) as.Date(mock_date) else Sys.Date()
  now_iso <- format(run_start_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  baseline_path <- file.path(MLB_CACHE_ROOT, "league_state_baseline.json")
  if (!file.exists(baseline_path)) {
    stop(sprintf("build_offseason_monitor: baseline state missing at %s", baseline_path))
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  
  # ---------------------------------------------------------------------------
  # Step 1: Ingestion -> freshness gate -> health gate       (GitHub issue #58)
  # ---------------------------------------------------------------------------
  # This is the DAG's Ingest edge. Before #58 it did not exist: this step opened
  # whatever cache/ingestion_manifest.json a previous manual run had left
  # behind, lifted composite_health, and fetched nothing. ingest_all() is now
  # invoked here, so the manifest gated on is the one this run just produced
  # rather than a leftover.
  manifest_path <- file.path(MLB_CACHE_ROOT, "ingestion_manifest.json")
  manifest <- NULL
  ingest_can_assert_quiet_week <- FALSE

  if (fixture_mode) {
    # Benchmark replay (issue #45). No fetch, and therefore no authority to
    # assert a quiet week: ingest_can_assert_quiet_week stays FALSE.
    log_info("build_offseason_monitor: fixture_mode is ON -- ingestion stage skipped; extraction replays the issue #45 benchmark fixture. Not a publishable edition.",
             script = "build_offseason_monitor.R")
  } else {
    # Producer side is owned by issue #57; we only call its entry point.
    if (!exists("ingest_all", mode = "function")) {
      source(file.path(MLB_ROOT_DIR, "tools", "offseason", "ingest_sources.R"))
    }
    if (!exists("ingest_all", mode = "function")) {
      stop("build_offseason_monitor: tools/offseason/ingest_sources.R did not define ingest_all(); the DAG's Ingest edge cannot run (issue #57).")
    }
    log_info(sprintf("build_offseason_monitor: Step 1 invoking ingest_all(allow_degraded = %s) -- live wire fetch before extraction.", allow_degraded),
             script = "build_offseason_monitor.R")
    ingest_res <- ingest_all(allow_degraded = allow_degraded)

    # Prefer the manifest ingest_all() just returned; fall back to the file it
    # just wrote. Never fall back to a healthy default -- see rule "fail closed".
    manifest <- ingest_res$manifest
    if (is.null(manifest) && file.exists(manifest_path)) {
      manifest <- tryCatch(fromJSON(manifest_path, simplifyDataFrame = FALSE), error = function(e) NULL)
    }
    if (is.null(manifest)) {
      stop("build_offseason_monitor: ingestion produced no readable manifest. Failing closed -- an absent or unparseable manifest must never be treated as a healthy one (issue #58).")
    }

    # --- Freshness gate (implementation owned by issue #59) ------------------
    # composite_health alone cannot see staleness: a manifest frozen days ago
    # still certifies HEALTHY. Signature is fixed by the #56 contract.
    freshness_path <- file.path(MLB_ROOT_DIR, "tools", "offseason", "ingest_freshness.R")
    if (file.exists(freshness_path)) {
      source(freshness_path)
    }
    # Local fallback stub conforming to contract section 6 if issue #59 has not yet merged
    if (!exists("assert_ingest_freshness", mode = "function")) {
      assert_ingest_freshness <- function(manifest, now = Sys.time(), max_age_hours = 26, allow_stale = FALSE) {
        if (is.null(manifest) || is.null(manifest$ingest_timestamp)) {
          res <- list(status = "MISSING", age_hours = NA_real_, max_age_hours = max_age_hours,
                      reason = "Manifest or ingest_timestamp is missing.")
          if (!allow_stale) stop(res$reason)
          return(res)
        }
        ts <- tryCatch(as.POSIXct(manifest$ingest_timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                       error = function(e) NA)
        if (is.na(ts)) {
          res <- list(status = "MISSING", age_hours = NA_real_, max_age_hours = max_age_hours,
                      reason = "Manifest ingest_timestamp could not be parsed.")
          if (!allow_stale) stop(res$reason)
          return(res)
        }
        age <- as.numeric(difftime(now, ts, units = "hours"))
        if (age > max_age_hours) {
          res <- list(status = "STALE", age_hours = age, max_age_hours = max_age_hours,
                      reason = sprintf("Manifest is STALE (age %.1f hours > max %.1f hours).", age, max_age_hours))
          if (!allow_stale) stop(res$reason)
          return(res)
        }
        list(status = "FRESH", age_hours = age, max_age_hours = max_age_hours,
             reason = sprintf("Manifest is FRESH (age %.1f hours <= max %.1f hours).", age, max_age_hours))
      }
    }
    now_clock <- if (!is.null(mock_date)) as.POSIXct(paste(mock_date, '12:00:00'), tz = 'UTC') else Sys.time()
    freshness <- assert_ingest_freshness(manifest,
                                         now = now_clock,
                                         max_age_hours = 26,
                                         allow_stale = allow_degraded)
    log_info(sprintf("build_offseason_monitor: ingest freshness %s (age=%s h, max=%s h): %s",
                     as.character(freshness$status),
                     format(freshness$age_hours), format(freshness$max_age_hours),
                     as.character(freshness$reason)),
             script = "build_offseason_monitor.R")

    # --- Blind-run gate: zero fetched items is a fault, not a quiet week -----
    wire_items_found <- suppressWarnings(as.integer(manifest$adapters$league_wire$items_found))
    if (length(wire_items_found) != 1L || is.na(wire_items_found)) {
      stop("build_offseason_monitor: manifest does not report adapters$league_wire$items_found. Failing closed -- an unknown fetch volume cannot be certified as a quiet week (issue #58).")
    }
    if (wire_items_found <= 0L) {
      stop(sprintf("build_offseason_monitor: BLIND RUN -- ingestion fetched 0 wire items (adapters$league_wire$items_found = %d, composite_health = %s). This is a fault, not a quiet week: zero fetched items is indistinguishable from a feed outage, so the build blocks instead of publishing a quiet-week edition (issue #58, tracker #64).",
                   wire_items_found, as.character(manifest$composite_health)))
    }

    # can_assert_quiet_week was previously discarded. It is the precondition on
    # publishing a zero confirmed-event count as a quiet week, enforced below.
    ingest_can_assert_quiet_week <- isTRUE(ingest_res$can_assert_quiet_week)
    log_info(sprintf("build_offseason_monitor: ingestion complete -- items_found=%d, composite_health=%s, can_assert_quiet_week=%s.",
                     wire_items_found, as.character(manifest$composite_health), ingest_can_assert_quiet_week),
             script = "build_offseason_monitor.R")
  }

  # Health gate. DEGRADED block semantics preserved verbatim from pre-#58.
  composite_health <- if (!is.null(manifest) && !is.null(manifest$composite_health)) {
    manifest$composite_health
  } else if (fixture_mode) {
    "HEALTHY"
  } else {
    stop("build_offseason_monitor: manifest carries no composite_health. Failing closed (issue #58).")
  }

  if (identical(composite_health, "DEGRADED") && !allow_degraded) {
    stop("build_offseason_monitor: Ingestion status is DEGRADED. Use allow_degraded = TRUE to proceed.")
  }
  if (identical(composite_health, "FAILED") && !allow_degraded) {
    stop("build_offseason_monitor: Ingestion status is FAILED. Use allow_degraded = TRUE to proceed.")
  }
  # ---------------------------------------------------------------------------
  # Step 2: Extraction & Reconciliation                      (GitHub issue #58)
  # ---------------------------------------------------------------------------
  # Extraction reads the live wire-items artifact that Step 1's ingest run
  # persisted: cache/offseason_wire_items.json, shape fixed by the issue #56
  # contract (docs/internal/offseason_wire_items_contract.md), produced by
  # issue #57's ingest_all(). It is validated by validate_wire_items() BEFORE
  # extraction so schema drift fails loudly here instead of degrading into
  # "zero deltas extracted" downstream.
  #
  # data/fixtures/official_wire_raw_samples.json is NOT read on a default or
  # scheduled run any more -- only under the explicit fixture_mode opt-in. See
  # the DEMOTED note in the file header for why (issues #58, #64).
  #
  # Contract note (#56 contract, section 7): mlbam_id and player_name are
  # optional and co-required; never dereference mlbam_id without a presence
  # check. The extraction call below passes only contract-required fields, so no
  # optional field is dereferenced here.
  deltas <- list()
  wire_item_count <- 0L
  if (!force_quiet) {
    if (fixture_mode) {
      # --- Benchmark replay path (issue #45 continuity) -- test-only. --------
      fixture_path <- file.path(MLB_ROOT_DIR, "data", "fixtures", "official_wire_raw_samples.json")
      if (!file.exists(fixture_path)) {
        stop(sprintf("build_offseason_monitor: fixture_mode requested but the issue #45 benchmark fixture is missing at %s", fixture_path))
      }
      log_info(sprintf("build_offseason_monitor: fixture_mode reading benchmark fixture %s (issue #45 benchmark continuity only).", fixture_path),
               script = "build_offseason_monitor.R")
      fixtures <- fromJSON(fixture_path, simplifyVector = FALSE)
      wire_item_count <- length(fixtures)
      baseline$.player_index <- build_player_index(baseline$players)
      for (f in fixtures) {
        ext <- extract_regex_from_text(f$raw_text, baseline, f$date, f$source_url,
                                        team_id = f$team_id, transaction_id = f$transaction_id)
        deltas <- c(deltas, ext)
      }
    } else {
      # --- Live wire-items path ---------------------------------------------
      wire_items_path <- file.path(MLB_CACHE_ROOT, "offseason_wire_items.json")
      if (!file.exists(wire_items_path)) {
        stop(sprintf("build_offseason_monitor: wire-items artifact missing at %s. Failing closed -- the ingest stage reported items but persisted no artifact, so extraction has nothing to read and an empty delta list must never stand in for it (issues #57, #58).",
                     wire_items_path))
      }
      wire_items <- tryCatch(
        fromJSON(wire_items_path, simplifyVector = FALSE, encoding = "UTF-8"),
        error = function(e) stop(sprintf("build_offseason_monitor: wire-items artifact at %s is unparseable JSON: %s. Failing closed (issue #58).",
                                         wire_items_path, conditionMessage(e)))
      )

      source(file.path(MLB_ROOT_DIR, "tools", "offseason", "wire_items_schema.R"))
      wire_validation <- validate_wire_items(wire_items,
                                             require_unique_transaction_ids = TRUE,
                                             allow_unknown_fields = FALSE)
      if (!isTRUE(wire_validation$pass)) {
        shown <- utils::head(wire_validation$messages, 20L)
        stop(sprintf("build_offseason_monitor: wire-items contract validation FAILED for %s -- %s\n%s%s\nFailing closed: a schema-invalid artifact must stop the build, not fall through to an empty delta list (an empty list is indistinguishable from a genuine quiet week). See the issue #56 contract.",
                     wire_items_path,
                     wire_validation$summary,
                     paste0("  - ", shown, collapse = "\n"),
                     if (length(wire_validation$messages) > length(shown))
                       sprintf("\n  ... and %d further error(s)", length(wire_validation$messages) - length(shown)) else ""))
      }
      wire_item_count <- wire_validation$n_records
      log_info(sprintf("build_offseason_monitor: Step 2 extracting from %s -- %s", wire_items_path, wire_validation$summary),
               script = "build_offseason_monitor.R")

      baseline$.player_index <- build_player_index(baseline$players)
      for (f in wire_items) {
        ext <- extract_regex_from_text(f$raw_text, baseline, f$date, f$source_url,
                                        team_id = f$team_id, transaction_id = f$transaction_id)
        deltas <- c(deltas, ext)
      }
    }
    log_info(sprintf("build_offseason_monitor: extracted %d candidate delta(s) from %d wire item(s).",
                     length(deltas), wire_item_count),
             script = "build_offseason_monitor.R")
  }

  rec_res <- reconcile_state(baseline, deltas, as_of_timestamp = now_iso)
  staged_state <- rec_res$staged_state
  confirmed_events <- rec_res$confirmed_events

  # --- Earned-quiet-week gate (issue #58; tracker #64 rule \"a zero is a claim\")
  # length(confirmed_events) == 0 is correct arithmetic, but it is only a
  # publishable *claim about the world* when ingestion was fresh, healthy and
  # actually returned records. force_quiet remains an explicit operator
  # override; everything else must earn the zero.
  if (length(confirmed_events) == 0L && !force_quiet && !fixture_mode &&
      !isTRUE(ingest_can_assert_quiet_week)) {
    stop(sprintf("build_offseason_monitor: BLIND RUN -- 0 confirmed state transitions from %d wire item(s), but ingestion cannot vouch for that zero (composite_health = %s, can_assert_quiet_week = FALSE). Zero-because-we-did-not-look must never publish as zero-because-nothing-happened, so the build blocks instead of emitting a quiet-week edition (issue #58, tracker #64).",
                 wire_item_count, as.character(composite_health)))
  }
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
  # Issue #58: explicit opt-in to replay the demoted issue #45 benchmark
  # fixture instead of the live wire-items artifact. Test-only.
  fixture_md <- "--fixture-mode" %in% args
  op_status <- if (frozen) "TRANSACTION_FREEZE" else NULL
  
  week_arg <- grep("^--week=", args, value = TRUE)
  week_val <- if (length(week_arg)) as.integer(sub("^--week=", "", week_arg[1])) else NULL
  
  build_offseason_monitor(allow_degraded = allow_deg,
                          force_quiet = force_qt,
                          operating_status_override = op_status,
                          week_number = week_val,
                          fixture_mode = fixture_md)
}
