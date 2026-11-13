# ==============================================================================
# tools/derive_team_payroll_from_bbref.R
#
# Phase 3 of the Basketball-Reference cap-data automation effort (issue #100).
# Aggregates cache/bbref_player_contracts.rds (produced by #98's
# tools/fetch_bbref_player_contracts.R) into per-team, current-season payroll
# totals.
#
# IMPORTANT LABELING CAVEAT (carried forward from #97/#98/#99/#100's issue
# text -- read this before touching the output field name):
# Basketball-Reference's /contracts/players.html page lists ACTIVE ROSTER
# SALARIES ONLY. It has no dead cap, no cap holds, and no non-guaranteed
# partial-season adjustments. build_cba_cap_dataset.R's `team_payrolls`
# table, by contrast, is sourced from Spotrac's "Total Cap Allocations",
# which DOES include those. The two are NOT the same quantity and will not
# match team-for-team. The output column here is therefore named
# `active_roster_salary_total` -- never `total_cap_allocation` or any name
# implying parity with build_cba_cap_dataset.R's figures. See
# docs/cap_data_phase3_findings.md for the quantified gap, by team, and why
# it exists.
#
# Run standalone: Rscript tools/derive_team_payroll_from_bbref.R
# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone
# without running the aggregation (matches this repo's other tools/fetch_*
# style scripts).
# ==============================================================================

.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

source(file.path(.THIS_DIR, "..", "config.R"), local = TRUE)

CACHE_BBREF_PLAYER_CONTRACTS <- file.path(CACHE_DIR, "bbref_player_contracts.rds")
CACHE_TEAM_PAYROLL_ACTIVE_ROSTER <- file.path(CACHE_DIR, "bbref_team_payroll_active_roster.rds")

derive_payroll_stop <- function(reason) {
  stop(sprintf(
    "[BBREF_TEAM_PAYROLL_DERIVE_FAILED] tools/derive_team_payroll_from_bbref.R: %s",
    reason
  ), call. = FALSE)
}

#' Aggregate the per-player BBRef contracts cache into one row per team: the
#' sum of current-season active-roster salary (`salary_y1`, the first
#' forward-looking salary column BBRef's table carries -- see #98's
#' bbref_parse_contracts_table() for column provenance). NA salaries (players
#' with no current-season figure listed, e.g. two-way/partial rows) are
#' treated as 0 for the purposes of the team sum, since a missing row should
#' not silently exclude a team from the aggregation -- but the player count
#' actually summed is reported alongside, so a team with many NA rows is
#' visibly distinguishable from one with none.
derive_team_payroll_from_bbref <- function(contracts = NULL) {
  if (is.null(contracts)) {
    if (!file.exists(CACHE_BBREF_PLAYER_CONTRACTS)) {
      derive_payroll_stop(sprintf(
        "%s does not exist. Run tools/fetch_bbref_player_contracts.R first.",
        CACHE_BBREF_PLAYER_CONTRACTS
      ))
    }
    contracts <- readRDS(CACHE_BBREF_PLAYER_CONTRACTS)
  }

  required_cols <- c("player", "team", "salary_y1")
  missing_cols <- setdiff(required_cols, names(contracts))
  if (length(missing_cols) > 0) {
    derive_payroll_stop(sprintf(
      "Input is missing expected column(s): %s. BBRef's contracts cache schema may have changed.",
      paste(missing_cols, collapse = ", ")
    ))
  }

  contracts <- contracts[!is.na(contracts$team) & trimws(contracts$team) != "", , drop = FALSE]
  if (nrow(contracts) == 0) {
    derive_payroll_stop("No rows with a non-missing team abbreviation were found to aggregate.")
  }

  salary <- contracts$salary_y1
  salary_for_sum <- ifelse(is.na(salary), 0, salary)

  agg <- data.frame(
    team_abbr = contracts$team,
    salary_for_sum = salary_for_sum,
    has_salary = as.integer(!is.na(salary)),
    stringsAsFactors = FALSE
  )

  totals <- aggregate(
    cbind(active_roster_salary_total = salary_for_sum, players_with_salary = has_salary) ~ team_abbr,
    data = agg,
    FUN = sum
  )
  player_counts <- as.data.frame(table(team_abbr = agg$team_abbr), stringsAsFactors = FALSE)
  names(player_counts) <- c("team_abbr", "player_count")

  out <- merge(totals, player_counts, by = "team_abbr")
  out <- out[order(-out$active_roster_salary_total), , drop = FALSE]
  rownames(out) <- NULL

  out
}

#' Top-level entrypoint: load the cache, aggregate, write the derived cache.
#' Output column is explicitly `active_roster_salary_total` (see the file
#' header caveat) -- this is intentionally NOT comparable 1:1 to
#' build_cba_cap_dataset.R's `team_payrolls$payroll_2026` (Spotrac "Total Cap
#' Allocations"), which includes dead cap / cap holds this figure omits.
run_derive_team_payroll_from_bbref <- function() {
  cat("[BBREF_TEAM_PAYROLL] Loading", CACHE_BBREF_PLAYER_CONTRACTS, "...\n")
  contracts <- readRDS(CACHE_BBREF_PLAYER_CONTRACTS)

  cat("[BBREF_TEAM_PAYROLL] Aggregating by team (active-roster salary only; see file header caveat)...\n")
  team_payroll <- derive_team_payroll_from_bbref(contracts)

  attr(team_payroll, "derived_at") <- Sys.time()
  attr(team_payroll, "source_cache") <- CACHE_BBREF_PLAYER_CONTRACTS
  attr(team_payroll, "methodology") <- paste(
    "active_roster_salary_total = sum of Basketball-Reference's current-season",
    "(salary_y1) active-roster salary figures per team. Excludes dead cap, cap",
    "holds, and non-guaranteed partial-season adjustments. NOT equivalent to",
    "Spotrac-style 'Total Cap Allocations' (see build_cba_cap_dataset.R's",
    "team_payrolls table and docs/cap_data_phase3_findings.md)."
  )

  saveRDS(team_payroll, CACHE_TEAM_PAYROLL_ACTIVE_ROSTER)
  cat(sprintf(
    "[BBREF_TEAM_PAYROLL] Cached %d team rows to %s.\n",
    nrow(team_payroll), CACHE_TEAM_PAYROLL_ACTIVE_ROSTER
  ))

  team_payroll
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  run_derive_team_payroll_from_bbref()
}
