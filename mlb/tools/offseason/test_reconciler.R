# ==============================================================================
# tools/offseason/test_reconciler.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Deterministic Reconciler Test Suite
# Path: tools/offseason/test_reconciler.R
#
# Validates all 6 diff rules:
#   Rule 1: Diffs compare .value at identical key paths. Provenance changes never generate events.
#   Rule 2: 40-man roster additions/removals handled as 40-man transactions.
#   Rule 3: Transition from origin: 'UNPOPULATED' to populated is backfill, excluded from reported transitions.
#   Rule 4: Derived figures (cbtTaxEstimated, cbtSpaceRemaining) computed on read, never stored/diffed (1 signing produces 1 event, not 4 phantom diffs).
#   Rule 5: Keys sorted (players by playerId, teams by teamAbbrev).
#   Rule 6: Wrap draftPicks2027 and calendarMilestones in I() when serializing.
#
# Conforms to blueprint §§ 2, 3, 10 and Issue #45.
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
      stop(sprintf("test_reconciler.R: cannot locate repo root (no config.R at or above '%s')", start))
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

source("tools/offseason/reconcile_state.R")

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Running Deterministic State Reconciler & 6 Diff Rules Test Suite\n")
  cat("=====================================================================\n")
  
  baseline_path <- "cache/league_state_baseline.json"
  if (!file.exists(baseline_path)) {
    stop("test_reconciler.R: baseline not found at cache/league_state_baseline.json")
  }
  baseline <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
  
  # ---------------------------------------------------------------------------
  # Test Rule 1: Diffs compare .value. Provenance changes never generate events.
  # ---------------------------------------------------------------------------
  cat("Test Rule 1: Provenance changes do not generate events...\n")
  # Delta where value is unchanged ("GUARANTEED"), but sourceUrl or asOfDate changed
  delta_rule1 <- list(
    list(
      entity_id = "B_10155",
      field = "contractStatus",
      prior_val = "GUARANTEED",
      new_val = "GUARANTEED",
      tier = "CONFIRMED",
      date = "2026-11-01",
      source_url = "https://newsource.com/updated"
    )
  )
  res1 <- reconcile_state(baseline, delta_rule1)
  if (length(res1$confirmed_events) != 0) {
    stop(sprintf("Rule 1 failed: expected 0 events for identical value provenance update, got %d",
                 length(res1$confirmed_events)))
  }
  # But staged state should reflect the new provenance
  if (res1$staged_state$players$B_10155$contractStatus$sourceUrl != "https://newsource.com/updated") {
    stop("Rule 1 failed: staged state did not update provenance sourceUrl")
  }
  cat("  [PASS] Provenance-only update mutated state with 0 reported diff events.\n")
  
  # ---------------------------------------------------------------------------
  # Test Rule 2: 40-man roster additions/removals handled as 40-man transactions.
  # ---------------------------------------------------------------------------
  cat("Test Rule 2: 40-man roster additions/removals update team 40-man count...\n")
  initial_laa_count <- baseline$teams$LAA$roster40Count$value
  # Mike Trout removed from 40-man to FREE_AGENT
  delta_rule2 <- list(
    list(
      entity_id = "B_10155",
      field = "rosterStatus",
      prior_val = "40_MAN",
      new_val = "FREE_AGENT",
      tier = "CONFIRMED",
      date = "2026-11-01",
      source_url = "https://statsapi.mlb.com/api/v1/transactions"
    )
  )
  res2 <- reconcile_state(baseline, delta_rule2)
  new_laa_count <- res2$staged_state$teams$LAA$roster40Count$value
  if (new_laa_count != (initial_laa_count - 1)) {
    stop(sprintf("Rule 2 failed: expected LAA 40-man count %d, got %d",
                 initial_laa_count - 1, new_laa_count))
  }
  cat(sprintf("  [PASS] 40-man removal correctly adjusted LAA roster40Count from %d to %d.\n",
              initial_laa_count, new_laa_count))
  
  # ---------------------------------------------------------------------------
  # Test Rule 3: Transition from origin 'UNPOPULATED' is backfill, excluded from diffs.
  # ---------------------------------------------------------------------------
  cat("Test Rule 3: Origin UNPOPULATED transition is backfill (0 events)...\n")
  # winterLeague on B_10155 has origin UNPOPULATED
  if (baseline$players$B_10155$winterLeague$origin != "UNPOPULATED") {
    stop("Rule 3 test setup error: baseline winterLeague origin is not UNPOPULATED")
  }
  delta_rule3 <- list(
    list(
      entity_id = "B_10155",
      field = "winterLeague",
      prior_val = NULL,
      new_val = list(league = "AFL", team = "Salt River Rafters"),
      tier = "CONFIRMED",
      date = "2026-11-01",
      source_url = "https://mlb.com/winter-leagues"
    )
  )
  res3 <- reconcile_state(baseline, delta_rule3)
  if (length(res3$confirmed_events) != 0) {
    stop(sprintf("Rule 3 failed: expected 0 events for UNPOPULATED backfill, got %d",
                 length(res3$confirmed_events)))
  }
  if (res3$staged_state$players$B_10155$winterLeague$origin != "BACKFILL") {
    stop("Rule 3 failed: backfilled item did not receive origin 'BACKFILL'")
  }
  cat("  [PASS] Backfill from UNPOPULATED populated state with origin BACKFILL and 0 diff events.\n")
  
  # ---------------------------------------------------------------------------
  # Test Rule 4: Signing a player produces 1 confirmed event and 0 phantom CBT diffs.
  # Derived figures computed on read, never stored or diffed.
  # ---------------------------------------------------------------------------
  cat("Test Rule 4: Signing a player produces 1 confirmed event & 0 phantom CBT diffs...\n")
  initial_nym_payroll <- baseline$teams$NYM$cbtPayrollCommitted$value
  
  # Simulate signing Pete Alonso to NYM:
  # 1 transaction delta: team moves to NYM (or contractTerms set)
  delta_signing <- list(
    list(
      entity_id = "B_19251",
      field = "team",
      prior_val = baseline$players$B_19251$team$value,
      new_val = "NYM",
      tier = "CONFIRMED",
      date = "2026-11-03",
      source_url = "https://statsapi.mlb.com/api/v1/transactions"
    )
  )
  res4 <- reconcile_state(baseline, delta_signing)
  
  # Assert exactly 1 confirmed event produced
  if (length(res4$confirmed_events) != 1) {
    stop(sprintf("Rule 4 failed: expected exactly 1 confirmed event for signing, got %d",
                 length(res4$confirmed_events)))
  }
  
  # Verify that neither cbtTaxEstimated nor cbtSpaceRemaining exist as stored fields on teams
  if (!is.null(res4$staged_state$teams$NYM$cbtTaxEstimated) ||
      !is.null(res4$staged_state$teams$NYM$cbtSpaceRemaining)) {
    stop("Rule 4 failed: derived CBT fields are stored on staged team state!")
  }
  
  # Verify compute_derived_cbt computes derived figures on read
  derived_read <- compute_derived_cbt(cbt_payroll_committed = 280, cbt_base_threshold = 241)
  if (derived_read$cbtSpaceRemaining != (241 - 280) || derived_read$cbtTaxEstimated <= 0) {
    stop("Rule 4 failed: compute_derived_cbt did not calculate read-time metrics correctly")
  }
  cat("  [PASS] Signing produced exactly 1 event and 0 phantom derived CBT diffs.\n")
  cat(sprintf("  [PASS] On-read derived CBT computed: spaceRemaining=$%.1fM, taxEstimated=$%.2fM.\n",
              derived_read$cbtSpaceRemaining, derived_read$cbtTaxEstimated))
  
  # ---------------------------------------------------------------------------
  # Test Rule 5: Keys sorted (players by playerId, teams by teamAbbrev).
  # ---------------------------------------------------------------------------
  cat("Test Rule 5: State keys sorted strictly...\n")
  player_keys <- names(res4$staged_state$players)
  team_keys <- names(res4$staged_state$teams)
  if (!identical(player_keys, sort(player_keys))) {
    stop("Rule 5 failed: staged players keys are not sorted!")
  }
  if (!identical(team_keys, sort(team_keys))) {
    stop("Rule 5 failed: staged teams keys are not sorted!")
  }
  cat("  [PASS] 100% of player and team keys are sorted lexicographically.\n")
  
  # ---------------------------------------------------------------------------
  # Test Rule 6: Wrap draftPicks2027 and calendarMilestones in I() when serializing.
  # ---------------------------------------------------------------------------
  cat("Test Rule 6: Serialization protects arrays with I()...\n")
  test_staged_path <- "cache/test_staged_rule6.json"
  save_staged_state(res4$staged_state, test_staged_path)
  
  # Read back with raw json parser to verify array structure
  json_txt <- readLines(test_staged_path, warn = FALSE)
  parsed_test <- fromJSON(test_staged_path, simplifyVector = FALSE)
  
  if (!is.list(parsed_test$league$calendarMilestones$value) ||
      length(parsed_test$league$calendarMilestones$value) == 0) {
    stop("Rule 6 failed: calendarMilestones is not an array!")
  }
  if (!is.list(parsed_test$teams$LAD$draftPicks2027$value) ||
      length(parsed_test$teams$LAD$draftPicks2027$value) == 0) {
    stop("Rule 6 failed: draftPicks2027 is not an array!")
  }
  unlink(test_staged_path)
  cat("  [PASS] draftPicks2027 and calendarMilestones serialized as arrays.\n")
  
  # ---------------------------------------------------------------------------
  # Regression test: Kyren Paris is a waiver claim, not a trade.
  # A "team" field delta carrying transaction_type = "WAIVER_CLAIM" (as the
  # extractor now tags waiver-claim text) must be classified as WAIVER_CLAIM
  # in the resulting confirmedChanges event, not defaulted to TRADE.
  # ---------------------------------------------------------------------------
  cat("Regression test: waiver-claim delta is classified WAIVER_CLAIM...\n")
  delta_paris <- list(
    list(
      entity_id = "B_26420",
      field = "team",
      prior_val = baseline$players$B_26420$team$value,
      new_val = "NYM",
      tier = "CONFIRMED",
      date = "2026-10-29",
      source_url = "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=947444",
      transaction_type = "WAIVER_CLAIM"
    )
  )
  res_paris <- reconcile_state(baseline, delta_paris)
  if (length(res_paris$confirmed_events) != 1) {
    stop(sprintf("Waiver-claim regression failed: expected exactly 1 event, got %d",
                 length(res_paris$confirmed_events)))
  }
  if (res_paris$confirmed_events[[1]]$transactionType != "WAIVER_CLAIM") {
    stop(sprintf("Waiver-claim regression failed: expected transactionType WAIVER_CLAIM, got %s",
                 res_paris$confirmed_events[[1]]$transactionType))
  }
  cat("  [PASS] Waiver-claim delta correctly classified as WAIVER_CLAIM (not TRADE).\n")

  # ---------------------------------------------------------------------------
  # Regression test: Pete Alonso free-agency declaration collapses to exactly
  # 1 confirmedChanges row (not 3), with no phantom team: "FA" / TRADE / "None"
  # row. The contractStatus and team side-effect deltas must be tagged
  # suppress_event = TRUE by the extractor and skipped by the reconciler.
  # ---------------------------------------------------------------------------
  cat("Regression test: Alonso free-agency declaration dedupes to 1 event...\n")
  prior_team_alonso <- baseline$players$B_19251$team$value
  delta_alonso <- list(
    list(
      entity_id = "B_19251",
      field = "rosterStatus",
      prior_val = baseline$players$B_19251$rosterStatus$value,
      new_val = "FREE_AGENT",
      tier = "CONFIRMED",
      date = "2026-10-29",
      source_url = "https://statsapi.mlb.com/api/v1/transactions?teamId=110&startDate=2026-10-29&endDate=2026-10-29",
      transaction_type = "FREE_AGENCY"
    ),
    list(
      entity_id = "B_19251",
      field = "contractStatus",
      prior_val = baseline$players$B_19251$contractStatus$value,
      new_val = "UNRESTRICTED_FA",
      tier = "CONFIRMED",
      date = "2026-10-29",
      source_url = "https://statsapi.mlb.com/api/v1/transactions?teamId=110&startDate=2026-10-29&endDate=2026-10-29",
      transaction_type = "FREE_AGENCY",
      suppress_event = TRUE
    ),
    list(
      entity_id = "B_19251",
      field = "team",
      prior_val = prior_team_alonso,
      new_val = NULL,
      tier = "CONFIRMED",
      date = "2026-10-29",
      source_url = "https://statsapi.mlb.com/api/v1/transactions?teamId=110&startDate=2026-10-29&endDate=2026-10-29",
      transaction_type = "FREE_AGENCY",
      suppress_event = TRUE
    )
  )
  res_alonso <- reconcile_state(baseline, delta_alonso)
  if (length(res_alonso$confirmed_events) != 1) {
    stop(sprintf("Alonso dedup regression failed: expected exactly 1 confirmed event, got %d",
                 length(res_alonso$confirmed_events)))
  }
  alonso_event <- res_alonso$confirmed_events[[1]]
  if (alonso_event$transactionType != "FREE_AGENCY") {
    stop(sprintf("Alonso dedup regression failed: expected transactionType FREE_AGENCY, got %s",
                 alonso_event$transactionType))
  }
  if (alonso_event$team != prior_team_alonso || alonso_event$newValue == "None") {
    stop("Alonso dedup regression failed: expected the real prior team (not 'FA') and no phantom newValue 'None'")
  }
  cat(sprintf("  [PASS] Alonso free-agency declaration produced exactly 1 event (team=%s, no phantom rows).\n",
              alonso_event$team))

  cat("\n=====================================================================\n")
  cat(">>> ALL 6 DIFF RULES + REGRESSION TESTS VERIFIED CLEANLY\n")
  cat("=====================================================================\n")
}

if (!interactive()) {
  main()
}
