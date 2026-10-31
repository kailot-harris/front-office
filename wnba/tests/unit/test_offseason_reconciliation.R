# ==============================================================================
# test_offseason_reconciliation.R
# Unit Tests for Deterministic Offseason State Reconciler (Phase 3 / Issue #120)
#
# Verifies the 6 Blueprint diff rules:
#   1. Diff compares .value at identical key paths; provenance changes do not generate reportable events.
#   2. Roster add/removal detected via player/team key presence changes.
#   3. UNPOPULATED -> populated transition is tagged as BACKFILL and excluded from confirmed changes.
#   4. Derived attributes (coreEligible 7-year cliff) recomputed post-application, not diffed.
#   5. Strict key sorting (players by player_id, teams by team_abbrev).
#   6. Safe array serialization using I() for draftPicks2027 and calendarMilestones.
#   7. Atomic staging write to cache/league_state_staged.json.
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
  library(testthat)
  library(jsonlite)
})

# Source state reconciler
source(file.path("tools", "offseason", "reconcile_state.R"))

test_dir <- tempfile("test_reconciler_")
dir.create(test_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(test_dir, recursive = TRUE), add = TRUE)

baseline_path <- file.path("cache", "league_state_baseline.json")
if (!file.exists(baseline_path)) {
  # If baseline doesn't exist, generate it for unit test
  source(file.path("tools", "offseason", "capture_baseline_s0.R"))
  capture_baseline_s0(output_path = baseline_path)
}

baseline_data <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)

test_that("Rule 1: Provenance changes do not generate reportable state events", {
  # Create a staged copy with identical values but updated provenance
  staged_mod <- baseline_data
  staged_mod$players[["1068"]]$team$asOfDate <- "2027-02-15"
  staged_mod$players[["1068"]]$team$sourceUrl <- "https://test.com/new_source"
  
  diff_res <- compute_state_diff(baseline_data, staged_mod)
  expect_equal(length(diff_res$confirmed_changes), 0)
  expect_equal(length(diff_res$backfill_changes), 0)
})

test_that("Rule 2: Roster additions and removals detected via key presence changes", {
  staged_mod <- baseline_data
  # Add new synthetic player
  staged_mod$players[["9999999"]] <- list(
    playerId = "9999999",
    displayName = "Test Rookie",
    team = list(value = "GS", sourceUrl = NULL, asOfDate = "2027-04-15", confidenceTier = "CONFIRMED", origin = "TRANSACTION_WIRE")
  )
  
  # Remove an existing player
  staged_mod$players[["1054"]] <- NULL
  
  diff_res <- compute_state_diff(baseline_data, staged_mod)
  expect_equal(length(diff_res$roster_additions), 1)
  expect_equal(diff_res$roster_additions[[1]]$entity_id, "9999999")
  expect_equal(length(diff_res$roster_removals), 1)
  expect_equal(diff_res$roster_removals[[1]]$entity_id, "1054")
})

test_that("Rule 3: Transitions from origin: 'UNPOPULATED' are tagged as BACKFILL and excluded from confirmed changes", {
  # In baseline, winterLeague is UNPOPULATED
  test_deltas <- list(
    list(
      entity_type = "player",
      entity_id = "1068",
      field = "winterLeague",
      prior_val = NULL,
      new_val = list(league = "Unrivaled", team = "Mist BC"),
      tier = "CONFIRMED",
      source_url = "https://unrivaled.basketball/roster"
    )
  )
  
  staged_state <- apply_deltas_to_state(baseline_data, test_deltas)
  expect_equal(staged_state$players[["1068"]]$winterLeague$origin, "BACKFILL")
  
  diff_res <- compute_state_diff(baseline_data, staged_state)
  expect_equal(length(diff_res$confirmed_changes), 0)
  expect_equal(length(diff_res$backfill_changes), 1)
  expect_equal(diff_res$backfill_changes[[1]]$field, "winterLeague")
  expect_equal(diff_res$backfill_changes[[1]]$origin, "BACKFILL")
})

test_that("Rule 4: Derived coreEligible is recomputed post-application under the 7-year cliff and excluded from diffs", {
  # Player with serviceYears updated from 3 to 7
  test_deltas <- list(
    list(
      entity_type = "player",
      entity_id = "1068",
      field = "serviceYears",
      prior_val = 3L,
      new_val = 7L,
      tier = "CONFIRMED",
      source_url = "https://wnba.com/cba/audit"
    )
  )
  
  staged_state <- apply_deltas_to_state(baseline_data, test_deltas)
  # 7 service years -> coreEligible must be FALSE under 2027 cliff
  expect_equal(staged_state$players[["1068"]]$coreEligible$value, FALSE)
  
  # Diff engine should report serviceYears change, but NOT coreEligible as a separate transition
  diff_res <- compute_state_diff(baseline_data, staged_state)
  expect_equal(length(diff_res$confirmed_changes), 1)
  expect_equal(diff_res$confirmed_changes[[1]]$field, "serviceYears")
  expect_equal(diff_res$confirmed_changes[[1]]$new_value, 7L)
  
  # Verify coreEligible is not in confirmed_changes
  fields_reported <- sapply(diff_res$confirmed_changes, function(x) x$field)
  expect_false("coreEligible" %in% fields_reported)
})

test_that("Rule 5 & 6 & 7: Strict key sorting, safe array serialization, and atomic staging file write", {
  staged_temp_path <- file.path(test_dir, "league_state_staged.json")
  
  res <- reconcile_offseason_state(
    baseline_path = baseline_path,
    deltas = list(),
    staged_path = staged_temp_path,
    write_file = TRUE
  )
  
  expect_true(file.exists(staged_temp_path))
  
  # Read back raw JSON text to verify array serialization
  raw_json <- readLines(staged_temp_path, warn = FALSE)
  json_text <- paste(raw_json, collapse = " ")
  
  # Verify draftPicks2027 serializes as a JSON array "[ ... ]"
  expect_true(grepl('"draftPicks2027":\\s*\\{\\s*"value":\\s*\\[', json_text))
  
  # Verify calendarMilestones serializes as a JSON array "[ ... ]"
  expect_true(grepl('"calendarMilestones":\\s*\\{\\s*"value":\\s*\\[', json_text))
  
  # Verify key sorting in staged object
  staged_parsed <- jsonlite::fromJSON(staged_temp_path, simplifyVector = FALSE)
  player_keys <- names(staged_parsed$players)
  team_keys <- names(staged_parsed$teams)
  
  expect_equal(player_keys, sort(player_keys))
  expect_equal(team_keys, sort(team_keys))
})

test_that("Production staged file write creates cache/league_state_staged.json", {
  prod_staged <- file.path("cache", "league_state_staged.json")
  reconcile_offseason_state(
    baseline_path = baseline_path,
    deltas = list(),
    staged_path = prod_staged,
    write_file = TRUE
  )
  expect_true(file.exists(prod_staged))
})
