# ==============================================================================
# check_preseason_trigger.R
# WNBA Offseason Dynamics Monitor — Preseason Hand-Off Trigger (Phase 7 / Issue #124)
#
# Implements the dual-trigger preseason detection mechanism:
#   1. Condition 1 (Schedule Feed with Franchise Code Guard):
#      Inspects schedule feed (cache/wnba_schedule_cache.rds or live/mock schedule).
#      Fires IF AND ONLY IF both home_team and away_team are valid franchise keys
#      in names(WNBA_TEAMS). Strictly suppresses triggers on exhibition/international
#      opponent codes (e.g. DEL, WIL, USA).
#   2. Condition 2 (Calendar Ceiling Fallback):
#      Triggers hand-off once calendar reaches cutoff date ("2027-04-26") even if
#      no schedule records have appeared in early feeds.
#
# Usage:
#   Rscript tools/offseason/check_preseason_trigger.R [--dry-run] [--force-hand-off]
#                                                    [--as-of-date=YYYY-MM-DD]
#                                                    [--schedule-path=<PATH>]
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

# Safe configuration loading avoiding test side effects per AGENTS.md
if (file.exists("config.R")) source("config.R")
if (file.exists("logging_utils.R")) source("logging_utils.R")

DEFAULT_CALENDAR_CEILING <- "2027-04-26"
DEFAULT_BASELINE_PATH    <- file.path("cache", "league_state_baseline.json")
DEFAULT_SCHEDULE_PATH    <- if (exists("CACHE_WNBA_SCHEDULE")) CACHE_WNBA_SCHEDULE else file.path("cache", "wnba_schedule_cache.rds")
DEFAULT_MONITOR_PATH     <- if (exists("WEB_JSON_OFFSEASON_MONITOR")) WEB_JSON_OFFSEASON_MONITOR else file.path("web", "public", "data", "offseason_monitor.json")
DEFAULT_ARCHIVE_PATH     <- file.path("web", "public", "data", "archive", "2026_2027_offseason.json")

# ------------------------------------------------------------------------------
# Core Evaluation Function (Injectable for Pure Unit Testing)
# ------------------------------------------------------------------------------
evaluate_preseason_trigger <- function(schedule_data = NULL,
                                       schedule_path = DEFAULT_SCHEDULE_PATH,
                                       as_of_date = Sys.Date(),
                                       calendar_ceiling = DEFAULT_CALENDAR_CEILING,
                                       valid_franchises = names(WNBA_TEAMS)) {
  current_date <- as.Date(as_of_date)
  ceiling_date <- as.Date(calendar_ceiling)
  
  # Condition 2: Calendar Ceiling Fallback
  calendar_triggered <- (current_date >= ceiling_date)
  
  # Load schedule if not supplied directly
  sched <- schedule_data
  if (is.null(sched) && !is.null(schedule_path) && file.exists(schedule_path)) {
    tryCatch({
      sched <- readRDS(schedule_path)
    }, error = function(e) {
      sched <- NULL
    })
  }
  
  schedule_triggered <- FALSE
  triggering_games <- list()
  ignored_exhibitions <- list()
  
  if (!is.null(sched) && is.data.frame(sched) && nrow(sched) > 0) {
    # Normalize team columns
    # WeHoop or ESPN feed representations
    home_col <- if ("home_team" %in% names(sched)) "home_team" else if ("team_abbreviation" %in% names(sched)) "team_abbreviation" else NA_character_
    away_col <- if ("away_team" %in% names(sched)) "away_team" else if ("opponent_team_abbreviation" %in% names(sched)) "opponent_team_abbreviation" else NA_character_
    date_col <- if ("game_date" %in% names(sched)) "game_date" else if ("date" %in% names(sched)) "date" else NA_character_
    
    if (!is.na(home_col) && !is.na(away_col)) {
      # Filter for upcoming / future games relative to 2026 season end or as_of_date
      # Preseason / 2027 season games will have date >= 2027-01-01 or season >= 2027
      is_candidate_game <- rep(TRUE, nrow(sched))
      if (!is.na(date_col)) {
        game_dates <- as.Date(sched[[date_col]])
        is_candidate_game <- !is.na(game_dates) & (game_dates >= as.Date("2027-01-01"))
      }
      if ("season" %in% names(sched)) {
        is_candidate_game <- is_candidate_game | (sched$season >= 2027)
      }
      
      candidate_rows <- which(is_candidate_game)
      for (idx in candidate_rows) {
        h <- as.character(sched[[home_col]][idx])
        a <- as.character(sched[[away_col]][idx])
        g_date <- if (!is.na(date_col)) as.character(sched[[date_col]][idx]) else "UNKNOWN"
        g_id <- if ("game_id" %in% names(sched)) as.character(sched$game_id[idx]) else as.character(idx)
        
        h_valid <- h %in% valid_franchises
        a_valid <- a %in% valid_franchises
        
        if (h_valid && a_valid) {
          schedule_triggered <- TRUE
          triggering_games[[length(triggering_games) + 1]] <- list(
            game_id = g_id,
            game_date = g_date,
            home_team = h,
            away_team = a,
            type = "FRANCHISE_MATCHUP"
          )
        } else {
          ignored_exhibitions[[length(ignored_exhibitions) + 1]] <- list(
            game_id = g_id,
            game_date = g_date,
            home_team = h,
            away_team = a,
            reason = "NON_FRANCHISE_OPPONENT_GUARD"
          )
        }
      }
    }
  }
  
  overall_triggered <- schedule_triggered || calendar_triggered
  
  trigger_reason <- if (schedule_triggered && calendar_triggered) {
    "BOTH_CONDITIONS_MET (Valid franchise schedule detected AND calendar ceiling reached)"
  } else if (schedule_triggered) {
    "CONDITION_1_MET (Valid franchise matchup detected in schedule feed)"
  } else if (calendar_triggered) {
    "CONDITION_2_MET (Calendar ceiling cutoff date reached)"
  } else {
    "NONE (Platform remains in Off-Season mode)"
  }
  
  list(
    triggered = overall_triggered,
    trigger_reason = trigger_reason,
    schedule_triggered = schedule_triggered,
    calendar_triggered = calendar_triggered,
    as_of_date = format(current_date, "%Y-%m-%d"),
    calendar_ceiling = format(ceiling_date, "%Y-%m-%d"),
    triggering_games = triggering_games,
    ignored_exhibitions = ignored_exhibitions
  )
}

# ------------------------------------------------------------------------------
# Orchestrator / Transition Execution
# ------------------------------------------------------------------------------
execute_preseason_hand_off <- function(eval_result,
                                       dry_run = FALSE,
                                       force = FALSE,
                                       baseline_path = DEFAULT_BASELINE_PATH,
                                       monitor_path = DEFAULT_MONITOR_PATH,
                                       archive_path = DEFAULT_ARCHIVE_PATH) {
  should_execute <- (eval_result$triggered || force)
  
  cat("==============================================================================\n")
  cat("WNBA Analytics — Spring 2027 Preseason Hand-Off Orchestrator\n")
  cat("==============================================================================\n")
  cat(sprintf("As of Date:         %s\n", eval_result$as_of_date))
  cat(sprintf("Calendar Ceiling:   %s\n", eval_result$calendar_ceiling))
  cat(sprintf("Schedule Trigger:   %s (Triggering games: %d, Ignored exhibitions: %d)\n",
              eval_result$schedule_triggered, length(eval_result$triggering_games), length(eval_result$ignored_exhibitions)))
  cat(sprintf("Calendar Trigger:   %s\n", eval_result$calendar_triggered))
  cat(sprintf("Overall Triggered:  %s\n", eval_result$triggered))
  cat(sprintf("Decision Reason:    %s\n", eval_result$trigger_reason))
  cat(sprintf("Execution Mode:     %s\n", if (dry_run) "DRY-RUN (No changes applied)" else if (force) "FORCE HAND-OFF" else "LIVE EXECUTION"))
  cat("------------------------------------------------------------------------------\n")
  
  if (!should_execute) {
    cat("[STATUS] Preseason hand-off criteria NOT met. WNBA Analytics remains in off-season mode.\n")
    return(invisible(list(status = "NOOP", eval_result = eval_result)))
  }
  
  cat("[ACTION REQUIRED] Hand-off conditions met! Transitioning platform to Spring 2027 in-season modeling...\n\n")
  
  if (dry_run) {
    cat("[DRY-RUN] The following transition steps would be executed:\n")
    cat(sprintf("  1. Archive %s -> %s\n", monitor_path, archive_path))
    cat(sprintf("  2. Update %s: set seasonStatus = '2027_CAMP_OPEN'\n", baseline_path))
    cat("  3. Schedule restoration instruction:\n")
    cat("     schtasks /change /tn \"WNBA Analytics Schedule Daily\" /enable\n")
    return(invisible(list(status = "DRY_RUN_SUCCESS", eval_result = eval_result)))
  }
  
  # 1. Archive offseason monitor JSON
  if (file.exists(monitor_path)) {
    archive_dir <- dirname(archive_path)
    if (!dir.exists(archive_dir)) {
      dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
    }
    file.copy(monitor_path, archive_path, overwrite = TRUE)
    cat(sprintf("[SUCCESS] Archived offseason monitor to %s\n", archive_path))
  } else {
    cat(sprintf("[WARNING] Monitor file %s does not exist; skipping archival.\n", monitor_path))
  }
  
  # 2. Update baseline seasonStatus
  if (file.exists(baseline_path)) {
    baseline_data <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
    baseline_data$seasonStatus <- "2027_CAMP_OPEN"
    baseline_data$updatedAt <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    jsonlite::write_json(baseline_data, baseline_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[SUCCESS] Updated %s: seasonStatus = '2027_CAMP_OPEN'\n", baseline_path))
  } else {
    cat(sprintf("[WARNING] Baseline file %s does not exist; skipping baseline update.\n", baseline_path))
  }
  
  # 3. Actionable Task Scheduler instructions
  cat("\n==============================================================================\n")
  cat("[HAND-OFF COMPLETE] Actionable Post-Transition Ops Instructions:\n")
  cat("  1. Enable in-season daily Task Scheduler job:\n")
  cat("     schtasks /change /tn \"WNBA Analytics Schedule Daily\" /enable\n")
  cat("  2. Disable weekly offseason Task Scheduler job:\n")
  cat("     schtasks /change /tn \"WNBA Analytics Schedule Weekly Offseason\" /disable\n")
  cat("  3. Restore Sidebar.tsx navigation to 2027 in-season tabs.\n")
  cat("==============================================================================\n")
  
  invisible(list(status = "TRANSITION_APPLIED", eval_result = eval_result))
}

# ------------------------------------------------------------------------------
# CLI Entry Point
# ------------------------------------------------------------------------------
if (!interactive()) {
  cmd_args <- commandArgs(trailingOnly = TRUE)
  dry_run_flag <- "--dry-run" %in% cmd_args
  force_flag   <- "--force-hand-off" %in% cmd_args
  
  date_arg <- grep("^--as-of-date=", cmd_args, value = TRUE)
  as_of_val <- if (length(date_arg) > 0) sub("^--as-of-date=", "", date_arg[1]) else Sys.Date()
  
  sched_arg <- grep("^--schedule-path=", cmd_args, value = TRUE)
  sched_path_val <- if (length(sched_arg) > 0) sub("^--schedule-path=", "", sched_arg[1]) else DEFAULT_SCHEDULE_PATH
  
  eval_res <- evaluate_preseason_trigger(
    schedule_path = sched_path_val,
    as_of_date = as_of_val
  )
  
  execute_preseason_hand_off(
    eval_result = eval_res,
    dry_run = dry_run_flag,
    force = force_flag
  )
}
