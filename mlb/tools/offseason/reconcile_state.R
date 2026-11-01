# ==============================================================================
# tools/offseason/reconcile_state.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Deterministic State Reconciler
# Path: tools/offseason/reconcile_state.R
#
# Computes S_staged = S_last (+) Delta S_confirmed and emits diff events:
#   ReportDiff = S_staged (-) S_last
#
# Strictly enforces the 6 diff rules:
#   1. Diffs compare .value at identical key paths. Provenance changes never generate events.
#   2. 40-man roster additions/removals handled as 40-man transactions.
#   3. Transition from origin: 'UNPOPULATED' to populated is backfill, excluded from reported transitions.
#   4. Derived figures (cbtTaxEstimated, cbtSpaceRemaining) computed on read, never stored/diffed (1 signing produces 1 event, not 4 phantom diffs).
#   5. Keys sorted (players by playerId, teams by teamAbbrev).
#   6. Wrap draftPicks2027 and calendarMilestones in I() when serializing.
#
# Outputs cache/league_state_staged.json conforming to LeagueStateBaseline schema.
# Conforms to blueprint §§ 2, 3, 10 and Zero-Betting Policy.
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
      stop(sprintf("reconcile_state.R: cannot locate repo root (no config.R at or above '%s')", start))
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

# Zero-betting policy guard check
FORBIDDEN_BETTING_TERMS <- c("sportsbook", "betmgm", "draftkings", "fanduel",
                             "caesars sportsbook", "pointsbet", "bovada", "bet365",
                             "moneyline", "runline", "over/under", "parlay",
                             "\\bvig\\b", "\\bjuice\\b", "\\bprop bet\\b")

validate_zero_betting <- function(text_vector) {
  for (pattern in FORBIDDEN_BETTING_TERMS) {
    matches <- grepl(pattern, text_vector, ignore.case = TRUE)
    if (any(matches)) {
      stop(sprintf("Zero-betting policy violation: found '%s' in state text", pattern))
    }
  }
}

# Helper to create a provenanced object
provenanced_item <- function(value, source_url = NULL, as_of_date = format(Sys.Date(), "%Y-%m-%d"),
                             confidence_tier = "CONFIRMED", origin = "TRANSACTION_WIRE") {
  list(
    value = value,
    sourceUrl = source_url,
    asOfDate = as_of_date,
    confidenceTier = confidence_tier,
    origin = origin
  )
}

# Compute derived CBT metrics on read (Rule 4)
# NEVER stored or diffed on the state baseline!
compute_derived_cbt <- function(cbt_payroll_committed, cbt_base_threshold = 241, surcharge_thresholds = list(tier1 = 20, tier2 = 40, tier3 = 60)) {
  if (is.null(cbt_base_threshold) || is.na(cbt_base_threshold)) {
    return(list(
      cbtSpaceRemaining = NA_real_,
      cbtTaxEstimated = 0
    ))
  }
  space_remaining <- cbt_base_threshold - cbt_payroll_committed
  tax <- 0
  if (cbt_payroll_committed > cbt_base_threshold) {
    overage <- cbt_payroll_committed - cbt_base_threshold
    # Standard 20% first tier rate
    tax <- overage * 0.20
  }
  list(
    cbtSpaceRemaining = space_remaining,
    cbtTaxEstimated = tax
  )
}

# Reconcile state deltas onto baseline state
# S_staged = S_last (+) Delta S_confirmed
# Emits list(staged_state = S_staged, confirmed_events = events)
reconcile_state <- function(baseline_state, confirmed_deltas, as_of_timestamp = NULL) {
  # Clone baseline
  staged <- baseline_state
  
  if (is.null(as_of_timestamp)) {
    as_of_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
  staged$asOf <- as_of_timestamp
  
  confirmed_events <- list()
  
  # Track 40-man roster counts if players are added/removed (Rule 2)
  roster_40_changes <- list()
  
  for (delta in confirmed_deltas) {
    # Strictly filter confidence tier: only CONFIRMED mutates baseline
    tier <- if (!is.null(delta$tier)) delta$tier else delta$confidenceTier
    if (!identical(tier, "CONFIRMED")) {
      next
    }
    
    entity_type <- if (!is.null(delta$entity_type)) delta$entity_type else {
      if (grepl("^[BP]_[0-9]+", delta$entity_id)) "player" else "team"
    }
    entity_id <- delta$entity_id
    field <- delta$field
    new_val <- delta$new_val
    as_of_date <- if (!is.null(delta$date)) delta$date else format(Sys.Date(), "%Y-%m-%d")
    source_url <- delta$source_url
    
    if (identical(entity_type, "player")) {
      if (is.null(staged$players[[entity_id]])) {
        # Unknown player, skip or create stub
        next
      }
      
      prior_item <- staged$players[[entity_id]][[field]]
      prior_val <- prior_item$value
      prior_origin <- prior_item$origin
      
      # Rule 3: Transition from UNPOPULATED is backfill, excluded from reported transitions
      is_backfill <- identical(prior_origin, "UNPOPULATED")
      
      # Rule 1: Diffs compare .value at identical key paths. Provenance changes never generate events.
      value_changed <- !identical(prior_val, new_val)
      
      # Apply update to staged state
      origin_type <- if (is_backfill) "BACKFILL" else "TRANSACTION_WIRE"
      staged$players[[entity_id]][[field]] <- provenanced_item(
        value = new_val,
        source_url = source_url,
        as_of_date = as_of_date,
        confidence_tier = "CONFIRMED",
        origin = origin_type
      )
      
      # Rule 2: 40-man roster additions/removals
      if (identical(field, "rosterStatus")) {
        old_is_40 <- identical(prior_val, "40_MAN")
        new_is_40 <- identical(new_val, "40_MAN")
        p_team <- staged$players[[entity_id]]$team$value
        if (!is.null(p_team) && !is.null(staged$teams[[p_team]])) {
          if (old_is_40 && !new_is_40) {
            # Removed from 40-man
            roster_40_changes[[p_team]] <- (if (is.null(roster_40_changes[[p_team]])) 0 else roster_40_changes[[p_team]]) - 1
          } else if (!old_is_40 && new_is_40) {
            # Added to 40-man
            roster_40_changes[[p_team]] <- (if (is.null(roster_40_changes[[p_team]])) 0 else roster_40_changes[[p_team]]) + 1
          }
        }
      }
      
      # Record confirmed event if value changed and not backfill.
      # A delta tagged suppress_event (e.g. the contractStatus/team
      # side-effects of a single free-agency declaration) still mutates the
      # baseline above, but must not spawn its own confirmedChanges row --
      # otherwise 1 transaction produces several duplicate/phantom rows
      # (the Pete Alonso bug: 3 rows, including a bogus team: "FA" row,
      # for what is really 1 FREE_AGENCY transaction).
      if (value_changed && !is_backfill && !isTRUE(delta$suppress_event)) {
        player_name <- staged$players[[entity_id]]$displayName
        # Attribute the event to the club the transaction is filed under, so
        # that `team` agrees with the teamId carried in sourceUrl and the web
        # UI's team filter surfaces the row under the acquiring club.
        #
        # For a "team" field change that lands somewhere (TRADE, WAIVER_CLAIM)
        # that is the post-mutation value: Kyren Paris claimed by NYM off LAA
        # waivers is NYM's transaction (sourceUrl teamId=121), and the origin
        # club stays visible in priorValue.
        #
        # When the new value is empty the player is leaving the league rather
        # than joining a club (a free-agency declaration), so fall back to the
        # pre-mutation value -- otherwise the row would report team "FA".
        p_team <- if (identical(field, "team")) {
          if (!is.null(new_val) && nzchar(as.character(new_val))) new_val else prior_val
        } else {
          staged$players[[entity_id]]$team$value
        }

        # Determine transactionType. Prefer an explicit transaction_type
        # carried on the delta (set by the extractor, which knows whether a
        # "team" field change is a TRADE or a WAIVER_CLAIM, etc.) and fall
        # back to the old field-based heuristic only when none was supplied.
        tx_type <- if (!is.null(delta$transaction_type)) {
          delta$transaction_type
        } else if (identical(field, "rosterStatus") && identical(new_val, "FREE_AGENT")) {
          "FREE_AGENCY"
        } else if (identical(field, "team")) {
          "TRADE"
        } else if (identical(field, "contractStatus") && identical(new_val, "GUARANTEED")) {
          "OPTION_EXERCISED"
        } else if (identical(field, "contractStatus") && identical(new_val, "UNRESTRICTED_FA")) {
          "FREE_AGENCY"
        } else {
          "MAJOR_40_MAN"
        }

        confirmed_events[[length(confirmed_events) + 1]] <- list(
          date = as_of_date,
          team = if (!is.null(p_team)) p_team else "FA",
          playerName = player_name,
          playerId = entity_id,
          rosterTier = "MAJOR_40_MAN",
          transactionType = tx_type,
          priorValue = as.character(if (is.null(prior_val)) "None" else prior_val),
          newValue = as.character(if (is.null(new_val)) "None" else new_val),
          sourceUrl = if (!is.null(source_url)) source_url else ""
        )
      }
      
    } else if (identical(entity_type, "team")) {
      if (is.null(staged$teams[[entity_id]])) {
        next
      }
      
      prior_item <- staged$teams[[entity_id]][[field]]
      prior_val <- prior_item$value
      prior_origin <- prior_item$origin
      
      is_backfill <- identical(prior_origin, "UNPOPULATED")
      value_changed <- !identical(prior_val, new_val)
      
      # Rule 4 check: Derived figures (cbtTaxEstimated, cbtSpaceRemaining) are never stored or diffed!
      if (field %in% c("cbtTaxEstimated", "cbtSpaceRemaining")) {
        warning(sprintf("Rule 4 violation prevented: attempted to store derived field '%s' on team %s", field, entity_id))
        next
      }
      
      origin_type <- if (is_backfill) "BACKFILL" else "TRANSACTION_WIRE"
      staged$teams[[entity_id]][[field]] <- provenanced_item(
        value = new_val,
        source_url = source_url,
        as_of_date = as_of_date,
        confidence_tier = "CONFIRMED",
        origin = origin_type
      )
      
      if (value_changed && !is_backfill) {
        confirmed_events[[length(confirmed_events) + 1]] <- list(
          date = as_of_date,
          team = entity_id,
          playerName = "Team Attribute Update",
          playerId = entity_id,
          rosterTier = "MAJOR_40_MAN",
          transactionType = "MAJOR_40_MAN",
          priorValue = as.character(if (is.null(prior_val)) "None" else prior_val),
          newValue = as.character(if (is.null(new_val)) "None" else new_val),
          sourceUrl = if (!is.null(source_url)) source_url else ""
        )
      }
    }
  }
  
  # Apply 40-man roster adjustments (Rule 2)
  for (t_abbr in names(roster_40_changes)) {
    net_diff <- roster_40_changes[[t_abbr]]
    if (net_diff != 0 && !is.null(staged$teams[[t_abbr]])) {
      current_count <- staged$teams[[t_abbr]]$roster40Count$value
      staged$teams[[t_abbr]]$roster40Count <- provenanced_item(
        value = max(0, min(40, current_count + net_diff)),
        source_url = "https://statsapi.mlb.com/api/v1/transactions",
        as_of_date = format(Sys.Date(), "%Y-%m-%d"),
        confidence_tier = "CONFIRMED",
        origin = "TRANSACTION_WIRE"
      )
    }
  }
  
  # Rule 5: Keys sorted (players by playerId, teams by teamAbbrev)
  sorted_player_keys <- sort(names(staged$players))
  staged$players <- staged$players[sorted_player_keys]
  
  sorted_team_keys <- sort(names(staged$teams))
  staged$teams <- staged$teams[sorted_team_keys]
  
  list(
    staged_state = staged,
    confirmed_events = confirmed_events
  )
}

# Serialize staged state with Rule 6 array protection:
# Wrap draftPicks2027 and calendarMilestones in I()
save_staged_state <- function(staged_state, output_path = "cache/league_state_staged.json") {
  # Deep copy state for serialization
  export_obj <- staged_state
  
  # Rule 6: Wrap draftPicks2027 in each team
  for (t_abbr in names(export_obj$teams)) {
    if (!is.null(export_obj$teams[[t_abbr]]$draftPicks2027$value)) {
      export_obj$teams[[t_abbr]]$draftPicks2027$value <- I(export_obj$teams[[t_abbr]]$draftPicks2027$value)
    }
  }
  
  # Rule 6: Wrap calendarMilestones in league
  if (!is.null(export_obj$league$calendarMilestones$value)) {
    export_obj$league$calendarMilestones$value <- I(export_obj$league$calendarMilestones$value)
  }
  
  # Remove temporary indexing properties if present
  export_obj$.player_index <- NULL
  
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  json_data <- toJSON(export_obj, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 6)
  writeLines(json_data, output_path, useBytes = TRUE)
  invisible(output_path)
}

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Executing Deterministic State Reconciler\n")
  cat("=====================================================================\n")
  
  baseline_path <- "cache/league_state_baseline.json"
  if (!file.exists(baseline_path)) {
    stop("reconcile_state.R: baseline not found at cache/league_state_baseline.json")
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  
  # Ingest sample confirmed deltas from Layer A test fixtures
  fixture_path <- "data/fixtures/official_wire_raw_samples.json"
  deltas <- list()
  if (file.exists(fixture_path)) {
    fixtures <- fromJSON(fixture_path, simplifyVector = FALSE)
    source("tools/offseason/extract_regex.R")
    baseline$.player_index <- build_player_index(baseline$players)
    for (f in fixtures) {
      ext <- extract_regex_from_text(f$raw_text, baseline, f$date, f$source_url,
                                      team_id = f$team_id, transaction_id = f$transaction_id)
      deltas <- c(deltas, ext)
    }
  }
  
  cat(sprintf("Reconciling %d confirmed state deltas onto S0 baseline...\n", length(deltas)))
  res <- reconcile_state(baseline, deltas)
  
  staged_path <- "cache/league_state_staged.json"
  save_staged_state(res$staged_state, staged_path)
  
  cat(sprintf(">>> State reconciled successfully. Wrote staged state to %s\n", staged_path))
  cat(sprintf("Total confirmed diff events generated: %d\n", length(res$confirmed_events)))
  cat("=====================================================================\n")
}

if (!interactive()) {
  main()
}
