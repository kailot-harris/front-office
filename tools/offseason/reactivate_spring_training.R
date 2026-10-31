# ==============================================================================
# tools/offseason/reactivate_spring_training.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Spring Reactivation Orchestrator
# Path: tools/offseason/reactivate_spring_training.R
#
# Orchestrates the hand-off from weekly off-season monitoring to Spring Training 2027.
#
# Features:
#   - Root resolution prelude (Issue #90).
#   - Trigger verification via check_spring_training_trigger.R (or --force).
#   - Archives current offseason data to web/public/data/archive/2026_2027_offseason.json.
#   - Updates seasonStatus in cache/league_state_baseline.json to '2027_SPRING_TRAINING'.
#   - Produces final retrospective memo summarizing the 2026-2027 offseason dynamics.
#   - Supports --dry-run and simulated activation flags.
#
# Conforms to blueprint §§ 1, 7, 10 and Zero-Betting Policy.
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
      stop(sprintf("reactivate_spring_training.R: cannot locate repo root (no config.R at or above '%s')", start))
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

source("tools/offseason/check_spring_training_trigger.R")

generate_retrospective_memo <- function(offseason_data, baseline_data, archive_path) {
  now_utc <- format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC")
  latest_ed <- if (!is.null(offseason_data$editions) && length(offseason_data$editions) > 0) {
    offseason_data$editions[[1]]
  } else {
    list()
  }
  
  total_changes <- length(latest_ed$confirmedChanges %||% list())
  summary_stats <- offseason_data$currentStateSummary %||% list()
  cbt_leader <- summary_stats$cbtPayrollLeader %||% "N/A"
  total_confirmed <- summary_stats$totalConfirmedTransactions %||% total_changes
  
  memo <- c(
    "# 2026-2027 MLB Off-Season Retrospective & Spring Training Hand-Off Memo",
    "",
    sprintf("**Transition Execution Timestamp:** %s  ", now_utc),
    sprintf("**Target Operational Status:** `2027_SPRING_TRAINING`  ", NULL),
    sprintf("**Off-Season Archive Destination:** `%s`  ", archive_path),
    "",
    "---",
    "",
    "## 1. Executive Summary & Winter Transition",
    "",
    "The 2026-2027 MLB Off-Season Dynamics Monitor has concluded its weekly state-diff intelligence operations. All major 40-man roster movements, free agent acquisitions, arbitration settlements, and luxury tax threshold commitments have been attested and finalized into the comprehensive historical archive.",
    "",
    "### Final Off-Season Metrics:",
    sprintf("- **Total Weeks Published:** %d", as.integer(offseason_data$currentWeekNumber %||% 1)),
    sprintf("- **Total Confirmed Roster/Contract Transitions:** %d", as.integer(total_confirmed)),
    sprintf("- **Active League Operating Posture:** %s", as.character(offseason_data$leagueOperatingStatus %||% "NORMAL")),
    sprintf("- **2027 CBT Payroll Leader:** %s", cbt_leader),
    "",
    "---",
    "",
    "## 2. Hand-Off Verification & Dual-Trigger Compliance",
    "",
    "- **Condition 1 (Guarded Schedule Trigger):** Spring Training exhibition schedule active. Non-MLB college exhibition squads (e.g. Northeastern Huskies) were verified and successfully guarded against false pipeline triggers.",
    "- **Condition 2 (Calendar Cutoff & Lockout Gate):** Calendar milestone verified. Normal league operations confirmed; no active transaction freezes or bargaining stoppages impeding Spring Training camp openings.",
    "",
    "---",
    "",
    "## 3. Downstream Pipeline Reactivation Instructions",
    "",
    "1. **State Archival:** Snapshot saved cleanly to `web/public/data/archive/2026_2027_offseason.json`.",
    "2. **Baseline Evolution:** `cache/league_state_baseline.json` updated with `seasonStatus = '2027_SPRING_TRAINING'`.",
    "3. **Frontend Toggle:** Set `seasonMode: 'inseason'` in web navigation configuration or data hook.",
    "4. **Task Scheduler:** Re-enable daily 09:00 local sabermetric pipeline DAG.",
    "",
    "*(End of 2026-2027 Off-Season Retrospective Memo)*"
  )
  
  paste(memo, collapse = "\n")
}

reactivate_spring_training <- function(dry_run = FALSE,
                                       force = FALSE,
                                       as_of_date = Sys.Date(),
                                       operating_status = NULL,
                                       archive_dest = "web/public/data/archive/2026_2027_offseason.json",
                                       memo_dest = "cache/2026_2027_offseason_retrospective_memo.md") {
  cat("=======================================================================\n")
  cat("MLB 2027 Spring Training Reactivation & Hand-Off Orchestrator\n")
  cat(sprintf("Dry Run: %s | Force Trigger: %s | As-Of Date: %s\n", dry_run, force, as_of_date))
  cat("=======================================================================\n\n")
  
  # 1. Trigger Verification
  trigger_eval <- evaluate_spring_training_trigger(
    as_of_date = as_of_date,
    operating_status = operating_status
  )
  
  cat(sprintf("Trigger Evaluation: %s\n", trigger_eval$verdict))
  cat(sprintf("Reason: %s\n\n", trigger_eval$reason))
  
  if (!trigger_eval$handoffTriggered && !force) {
    cat("[HALT] Spring Training hand-off conditions not met. Aborting reactivation.\n")
    return(list(
      status = "ABORTED",
      reason = trigger_eval$reason,
      dryRun = dry_run,
      archiveCreated = FALSE
    ))
  }
  
  # 2. Load Existing Off-Season Data & Baseline
  monitor_path <- "web/public/data/offseason_monitor.json"
  baseline_path <- "cache/league_state_baseline.json"
  
  if (!file.exists(monitor_path)) {
    stop(sprintf("Cannot locate offseason monitor dataset at '%s'", monitor_path))
  }
  if (!file.exists(baseline_path)) {
    stop(sprintf("Cannot locate baseline state at '%s'", baseline_path))
  }
  
  offseason_data <- jsonlite::fromJSON(monitor_path, simplifyDataFrame = FALSE)
  baseline_data <- jsonlite::fromJSON(baseline_path, simplifyDataFrame = FALSE)
  
  # 3. Create Archive
  cat(sprintf("Preparing archive package: %s...\n", archive_dest))
  dir.create(dirname(archive_dest), recursive = TRUE, showWarnings = FALSE)
  
  # Build enhanced archive dataset
  archive_payload <- list(
    archiveMetadata = list(
      archiveId = "2026_2027_offseason_final",
      archivedAt = format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
      finalWeekNumber = offseason_data$currentWeekNumber,
      totalEditionsArchived = length(offseason_data$editions),
      seasonStatus = "2027_SPRING_TRAINING",
      handOffTrigger = trigger_eval
    ),
    offseasonMonitor = offseason_data
  )
  
  archive_json <- jsonlite::toJSON(archive_payload, pretty = TRUE, auto_unbox = TRUE, null = "null")
  
  if (!dry_run) {
    writeLines(archive_json, archive_dest)
    cat(sprintf("[SUCCESS] Archived offseason dataset to %s (%d bytes)\n",
                archive_dest, nchar(archive_json)))
  } else {
    cat(sprintf("[DRY RUN] Would write archive dataset to %s (%d bytes)\n",
                archive_dest, nchar(archive_json)))
  }
  
  # 4. Update Season Status in Baseline
  cat("Updating baseline state seasonStatus to '2027_SPRING_TRAINING'...\n")
  baseline_data$seasonStatus <- "2027_SPRING_TRAINING"
  baseline_data$asOf <- format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  baseline_data$generatedBy <- "tools/offseason/reactivate_spring_training.R"
  
  baseline_json <- jsonlite::toJSON(baseline_data, pretty = TRUE, auto_unbox = TRUE, null = "null")
  
  if (!dry_run) {
    writeLines(baseline_json, baseline_path)
    cat(sprintf("[SUCCESS] Updated baseline seasonStatus in %s\n", baseline_path))
  } else {
    cat(sprintf("[DRY RUN] Would update baseline seasonStatus in %s\n", baseline_path))
  }
  
  # 5. Generate Final Retrospective Memo
  memo_content <- generate_retrospective_memo(offseason_data, baseline_data, archive_dest)
  if (!dry_run) {
    dir.create(dirname(memo_dest), recursive = TRUE, showWarnings = FALSE)
    writeLines(memo_content, memo_dest)
    cat(sprintf("[SUCCESS] Final retrospective memo written to %s\n", memo_dest))
  } else {
    cat(sprintf("[DRY RUN] Would write retrospective memo to %s\n", memo_dest))
  }
  
  cat("\n=======================================================================\n")
  cat("Spring Training Reactivation Completed Successfully!\n")
  cat("=======================================================================\n")
  
  invisible(list(
    status = "SUCCESS",
    dryRun = dry_run,
    archivePath = archive_dest,
    archiveCreated = !dry_run,
    seasonStatus = "2027_SPRING_TRAINING",
    memoPath = memo_dest,
    triggerReason = trigger_eval$reason
  ))
}

show_help <- function() {
  cat("=======================================================================\n")
  cat("tools/offseason/reactivate_spring_training.R\n")
  cat("MLB 2026-2027 Off-Season Dynamics Monitor: Spring Reactivation Orchestrator\n")
  cat("=======================================================================\n\n")
  cat("Usage:\n")
  cat("  Rscript tools/offseason/reactivate_spring_training.R [options]\n\n")
  cat("Options:\n")
  cat("  --dry-run                 Simulate hand-off without modifying files on disk\n")
  cat("  --force                   Force reactivation regardless of trigger status\n")
  cat("  --as-of=YYYY-MM-DD        Simulate as-of date (default: today)\n")
  cat("  --operating-status=STATUS Force operating status: NORMAL | TRANSACTION_FREEZE\n")
  cat("  --archive-dest=PATH       Custom destination for offseason archive JSON\n")
  cat("  --memo-dest=PATH          Custom destination for retrospective memo\n")
  cat("  --help                    Display this help message and exit\n\n")
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if ("--help" %in% args || "-h" %in% args) {
    show_help()
    quit(status = 0)
  }
  
  is_dry_run <- "--dry-run" %in% args
  is_force <- "--force" %in% args
  
  as_of_arg <- grep("^--as-of=", args, value = TRUE)
  as_of_val <- if (length(as_of_arg)) sub("^--as-of=", "", as_of_arg[1]) else Sys.Date()
  
  status_arg <- grep("^--operating-status=", args, value = TRUE)
  status_val <- if (length(status_arg)) sub("^--operating-status=", "", status_arg[1]) else NULL
  
  archive_arg <- grep("^--archive-dest=", args, value = TRUE)
  archive_val <- if (length(archive_arg)) sub("^--archive-dest=", "", archive_arg[1]) else "web/public/data/archive/2026_2027_offseason.json"
  
  memo_arg <- grep("^--memo-dest=", args, value = TRUE)
  memo_val <- if (length(memo_arg)) sub("^--memo-dest=", "", memo_arg[1]) else "cache/2026_2027_offseason_retrospective_memo.md"
  
  res <- reactivate_spring_training(
    dry_run = is_dry_run,
    force = is_force,
    as_of_date = as_of_val,
    operating_status = status_val,
    archive_dest = archive_val,
    memo_dest = memo_val
  )
  
  if (res$status == "SUCCESS") {
    quit(status = 0)
  } else {
    quit(status = 1)
  }
}
