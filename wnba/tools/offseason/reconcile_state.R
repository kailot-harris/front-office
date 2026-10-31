# ==============================================================================
# reconcile_state.R
# WNBA Offseason Dynamics Monitor — Deterministic State Reconciler (Phase 3)
#
# Implements:
#   S_staged = S_last ⊕ ΔS_confirmed
#   ΔS = S_staged ⊖ S_last
#
# Enforces the 6 Blueprint diff rules:
#   1. Diff compares .value at identical key paths; provenance changes do not
#      generate reportable events.
#   2. Roster add/removal detected via player/team key presence changes.
#   3. Fields transitioning from origin: 'UNPOPULATED' to populated are tagged
#      as BACKFILL and excluded from reportable state transitions.
#   4. Derived attributes (coreEligible under the 7-year cliff) are recomputed
#      post-application, not diffed.
#   5. Strict key sorting (players by player_id, teams by team_abbrev).
#   6. Safe array serialization using I() for draftPicks2027 and calendarMilestones.
#
# Atomic staging target: cache/league_state_staged.json
#
# Usage:
#   Rscript tools/offseason/reconcile_state.R [--baseline=<file>] [--deltas=<file>]
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

# Safe provenance envelope helper
make_provenanced_field <- function(value,
                                   source_url = NULL,
                                   as_of_date = format(Sys.time(), "%Y-%m-%d"),
                                   confidence_tier = "CONFIRMED",
                                   origin = "TRANSACTION_WIRE") {
  list(
    value = value,
    sourceUrl = source_url,
    asOfDate = as_of_date,
    confidenceTier = confidence_tier,
    origin = origin
  )
}

# Rule 4: Recompute derived attributes post-application
recompute_derived_attributes <- function(state) {
  if (is.null(state$players)) return(state)
  
  for (pid in names(state$players)) {
    p <- state$players[[pid]]
    # 2027 Core designation cliff: players with >= 7 years of service are ineligible for Core
    svc <- p$serviceYears$value
    if (!is.null(svc) && !is.na(svc) && is.numeric(svc)) {
      is_eligible <- (as.integer(svc) < 7L)
      # Update coreEligible derived flag
      p$coreEligible$value <- is_eligible
      p$coreEligible$asOfDate <- format(Sys.time(), "%Y-%m-%d")
      state$players[[pid]] <- p
    }
  }
  
  state
}

# Ensure safe array wrapping per Rule 6
wrap_safe_arrays <- function(state) {
  # Wrap draftPicks2027 arrays for teams
  if (!is.null(state$teams)) {
    for (tm in names(state$teams)) {
      if (!is.null(state$teams[[tm]]$draftPicks2027$value)) {
        state$teams[[tm]]$draftPicks2027$value <- I(state$teams[[tm]]$draftPicks2027$value)
      }
    }
  }
  
  # Wrap calendarMilestones array for league
  if (!is.null(state$league$calendarMilestones$value)) {
    state$league$calendarMilestones$value <- I(state$league$calendarMilestones$value)
  }
  
  state
}

#' Apply confirmed deltas to state baseline: S_staged = S_last ⊕ ΔS_confirmed
apply_deltas_to_state <- function(baseline_state, confirmed_deltas) {
  staged <- baseline_state
  staged$asOf <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  for (delta in confirmed_deltas) {
    # Only apply Tier 1 confirmed deltas to state baseline
    tier <- if (!is.null(delta$tier)) delta$tier else delta$confidence_tier
    if (!identical(as.character(tier), "CONFIRMED")) next
    
    ent_type <- delta$entity_type
    ent_id <- as.character(delta$entity_id)
    field <- delta$field
    new_val <- delta$new_val
    src_url <- delta$source_url
    ev_date <- if (!is.null(delta$date)) delta$date else format(Sys.time(), "%Y-%m-%d")
    
    if (identical(ent_type, "player")) {
      if (!is.null(staged$players[[ent_id]])) {
        if (!is.null(staged$players[[ent_id]][[field]])) {
          prior_origin <- staged$players[[ent_id]][[field]]$origin
          # Rule 3: Detect if transitioning from UNPOPULATED to populated
          new_origin <- if (identical(prior_origin, "UNPOPULATED")) "BACKFILL" else "TRANSACTION_WIRE"
          
          staged$players[[ent_id]][[field]]$value <- new_val
          staged$players[[ent_id]][[field]]$sourceUrl <- src_url
          staged$players[[ent_id]][[field]]$asOfDate <- ev_date
          staged$players[[ent_id]][[field]]$confidenceTier <- "CONFIRMED"
          staged$players[[ent_id]][[field]]$origin <- new_origin
        } else {
          # Field didn't exist in envelope
          staged$players[[ent_id]][[field]] <- make_provenanced_field(
            value = new_val,
            source_url = src_url,
            as_of_date = ev_date,
            confidence_tier = "CONFIRMED",
            origin = "TRANSACTION_WIRE"
          )
        }
      } else {
        # Rule 2: Brand new player entry (roster add)
        staged$players[[ent_id]] <- list(
          playerId = ent_id,
          displayName = if (!is.null(delta$entity_name)) delta$entity_name else paste("Player", ent_id),
          team = make_provenanced_field(if (field == "team") new_val else NULL, source_url = src_url, as_of_date = ev_date),
          contractStatus = make_provenanced_field(if (field == "contractStatus") new_val else "UNDER_CONTRACT", source_url = src_url, as_of_date = ev_date),
          contractThroughSeason = make_provenanced_field(if (field == "contractThroughSeason") as.integer(new_val) else 2027L, source_url = src_url, as_of_date = ev_date),
          serviceYears = make_provenanced_field(if (field == "serviceYears") as.integer(new_val) else 0L, source_url = src_url, as_of_date = ev_date),
          coreEligible = make_provenanced_field(TRUE, source_url = src_url, as_of_date = ev_date),
          designation = make_provenanced_field(if (field == "designation") new_val else "NONE", source_url = src_url, as_of_date = ev_date),
          winterLeague = make_provenanced_field(NULL, source_url = src_url, as_of_date = ev_date, origin = "UNPOPULATED"),
          availabilityStatus = make_provenanced_field("ACTIVE", source_url = src_url, as_of_date = ev_date)
        )
      }
    } else if (identical(ent_type, "team")) {
      if (!is.null(staged$teams[[ent_id]])) {
        if (!is.null(staged$teams[[ent_id]][[field]])) {
          prior_origin <- staged$teams[[ent_id]][[field]]$origin
          new_origin <- if (identical(prior_origin, "UNPOPULATED")) "BACKFILL" else "TRANSACTION_WIRE"
          
          staged$teams[[ent_id]][[field]]$value <- new_val
          staged$teams[[ent_id]][[field]]$sourceUrl <- src_url
          staged$teams[[ent_id]][[field]]$asOfDate <- ev_date
          staged$teams[[ent_id]][[field]]$confidenceTier <- "CONFIRMED"
          staged$teams[[ent_id]][[field]]$origin <- new_origin
        } else {
          staged$teams[[ent_id]][[field]] <- make_provenanced_field(
            value = new_val,
            source_url = src_url,
            as_of_date = ev_date,
            confidence_tier = "CONFIRMED",
            origin = "TRANSACTION_WIRE"
          )
        }
      }
    }
  }
  
  # Rule 4: Recompute derived attributes (coreEligible)
  staged <- recompute_derived_attributes(staged)
  
  # Rule 5: Strict key sorting
  if (!is.null(staged$players) && length(staged$players) > 0) {
    staged$players <- staged$players[order(names(staged$players))]
  }
  if (!is.null(staged$teams) && length(staged$teams) > 0) {
    staged$teams <- staged$teams[order(names(staged$teams))]
  }
  
  staged
}

#' Compute deterministic diff: ΔS = S_staged ⊖ S_last
compute_state_diff <- function(baseline_state, staged_state) {
  confirmed_changes <- list()
  backfill_changes <- list()
  roster_additions <- list()
  roster_removals <- list()
  
  # Rule 2: Player presence changes (Roster adds / removals)
  base_pids <- names(baseline_state$players)
  staged_pids <- names(staged_state$players)
  
  added_pids <- setdiff(staged_pids, base_pids)
  removed_pids <- setdiff(base_pids, staged_pids)
  
  for (pid in added_pids) {
    p <- staged_state$players[[pid]]
    roster_additions[[length(roster_additions) + 1]] <- list(
      entity_type = "player",
      entity_id = pid,
      entity_name = p$displayName,
      action = "ROSTER_ADD",
      as_of_date = p$team$asOfDate
    )
  }
  
  for (pid in removed_pids) {
    p <- baseline_state$players[[pid]]
    roster_removals[[length(roster_removals) + 1]] <- list(
      entity_type = "player",
      entity_id = pid,
      entity_name = p$displayName,
      action = "ROSTER_REMOVAL",
      as_of_date = format(Sys.time(), "%Y-%m-%d")
    )
  }
  
  # Rule 1, 3, 4: Compare field values across common player entities
  common_pids <- intersect(base_pids, staged_pids)
  tracked_player_fields <- c("team", "contractStatus", "contractThroughSeason", "serviceYears", "designation", "winterLeague", "availabilityStatus")
  # Note: coreEligible is intentionally excluded from reportable diff per Rule 4
  
  for (pid in common_pids) {
    p_base <- baseline_state$players[[pid]]
    p_staged <- staged_state$players[[pid]]
    
    for (fld in tracked_player_fields) {
      base_env <- p_base[[fld]]
      staged_env <- p_staged[[fld]]
      
      if (is.null(base_env) || is.null(staged_env)) next
      
      val_base <- base_env$value
      val_staged <- staged_env$value
      
      # Treat empty list as NULL
      if (is.list(val_base) && length(val_base) == 0) val_base <- NULL
      if (is.list(val_staged) && length(val_staged) == 0) val_staged <- NULL
      
      # Rule 1: Compare .value only. Check if value actually changed
      val_changed <- !identical(val_base, val_staged)
      
      if (val_changed) {
        # Rule 3: Check for BACKFILL from UNPOPULATED
        if (identical(base_env$origin, "UNPOPULATED") || identical(staged_env$origin, "BACKFILL")) {
          backfill_changes[[length(backfill_changes) + 1]] <- list(
            entity_type = "player",
            entity_id = pid,
            entity_name = p_staged$displayName,
            field = fld,
            prior_value = val_base,
            new_value = val_staged,
            origin = "BACKFILL"
          )
        } else {
          # Reportable confirmed state transition
          confirmed_changes[[length(confirmed_changes) + 1]] <- list(
            entity_type = "player",
            entity_id = pid,
            entity_name = p_staged$displayName,
            field = fld,
            prior_value = val_base,
            new_value = val_staged,
            source_url = staged_env$sourceUrl,
            date = staged_env$asOfDate
          )
        }
      }
    }
  }
  
  # Team changes
  common_teams <- intersect(names(baseline_state$teams), names(staged_state$teams))
  tracked_team_fields <- c("rosterCount", "capCommitted", "headCoach", "generalManager")
  
  for (tm in common_teams) {
    t_base <- baseline_state$teams[[tm]]
    t_staged <- staged_state$teams[[tm]]
    
    for (fld in tracked_team_fields) {
      base_env <- t_base[[fld]]
      staged_env <- t_staged[[fld]]
      
      if (is.null(base_env) || is.null(staged_env)) next
      
      val_base <- base_env$value
      val_staged <- staged_env$value
      if (is.list(val_base) && length(val_base) == 0) val_base <- NULL
      if (is.list(val_staged) && length(val_staged) == 0) val_staged <- NULL
      
      if (!identical(val_base, val_staged)) {
        if (identical(base_env$origin, "UNPOPULATED") || identical(staged_env$origin, "BACKFILL")) {
          backfill_changes[[length(backfill_changes) + 1]] <- list(
            entity_type = "team",
            entity_id = tm,
            entity_name = t_staged$displayName,
            field = fld,
            prior_value = val_base,
            new_value = val_staged,
            origin = "BACKFILL"
          )
        } else {
          confirmed_changes[[length(confirmed_changes) + 1]] <- list(
            entity_type = "team",
            entity_id = tm,
            entity_name = t_staged$displayName,
            field = fld,
            prior_value = val_base,
            new_value = val_staged,
            source_url = staged_env$sourceUrl,
            date = staged_env$asOfDate
          )
        }
      }
    }
  }
  
  list(
    confirmed_changes = confirmed_changes,
    backfill_changes = backfill_changes,
    roster_additions = roster_additions,
    roster_removals = roster_removals
  )
}

#' Reconcile state and write atomic staged output
reconcile_offseason_state <- function(baseline_path = file.path("cache", "league_state_baseline.json"),
                                      deltas = list(),
                                      staged_path = file.path("cache", "league_state_staged.json"),
                                      write_file = TRUE) {
  if (!file.exists(baseline_path)) {
    stop("Baseline state file not found: ", baseline_path)
  }
  
  baseline_state <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
  staged_state <- apply_deltas_to_state(baseline_state, deltas)
  
  # Rule 6: safe array serialization wrapping
  staged_for_write <- wrap_safe_arrays(staged_state)
  
  if (write_file) {
    out_dir <- dirname(staged_path)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    
    jsonlite::write_json(
      staged_for_write,
      staged_path,
      pretty = TRUE,
      auto_unbox = TRUE,
      null = "null"
    )
    message(">>> [RECONCILER] Successfully wrote staged state: ", staged_path)
  }
  
  diff_res <- compute_state_diff(baseline_state, staged_state)
  
  invisible(list(
    baseline = baseline_state,
    staged = staged_state,
    diff = diff_res
  ))
}

if (!interactive()) {
  # Default command line execution
  reconcile_offseason_state()
}
