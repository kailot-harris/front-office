# ==============================================================================
# build_cba_cap_dataset.R
# 2026-2027 NBA Season Salary Cap, Apron & Luxury Tax Architect Dataset
#
# League-wide thresholds are the NBA's own officially announced figures for
# 2026-27 (pr.nba.com, July 2026):
# - Salary Cap: $165.0M ($164,961,000)
# - Minimum Team Salary: $148.5M ($148,465,000)
# - Luxury Tax Line: $200.4M ($200,428,000)
# - First Apron: $209.0M ($209,015,000)
# - Second Apron: $221.7M ($221,686,000)
# These four thresholds remain MANUALLY-UPDATED CONSTANTS (SALARY_CAP /
# LUXURY_TAX / FIRST_APRON / SECOND_APRON below) -- a deliberate sourcing
# decision, not an oversight. Per #100/#101's cap_data_phase3_findings.md: no
# Basketball-Reference page carries these figures (its salary-cap-history
# table has only Year / Salary Cap / 2025 Dollars columns), they change once
# a season via a single official NBA announcement, and the realistic scrape
# alternative (Spotrac) is the same anti-bot source #97 already ruled out. A
# human updates these four numbers from the NBA's own press release.
#
# `team_payrolls` (#101, Phase 4 of the Basketball-Reference cap-data
# automation effort) is now AUTOMATED: built each run from
# cache/bbref_team_payroll_active_roster.rds (tools/derive_team_payroll_from_bbref.R,
# #100), which sums Basketball-Reference's /contracts/players.html
# current-season salary (`salary_y1`) per team. `verified_contracts` is
# likewise built from the raw per-player rows in
# cache/bbref_player_contracts.rds (tools/fetch_bbref_player_contracts.R,
# #98) instead of the one-off manual list #75 added, so both now refresh on
# the daily schedule instead of going stale the moment they're written.
#
# ACTIVE-ROSTER-ONLY CAVEAT (read before touching the loader below): BBRef's
# contracts table lists ACTIVE ROSTER SALARIES ONLY -- no dead cap, no cap
# holds, no non-guaranteed partial-season proration. `team_payrolls` below is
# therefore BBRef's `active_roster_salary_total`, NOT the Spotrac "Total Cap
# Allocations" figure #75's interim fix used (which does include those). The
# two are different quantities and will not match team-for-team -- see
# cap_data_phase3_findings.md for a quantified, by-team comparison of the
# gap. `cbaThresholdSources` below states this caveat plainly; never let a
# downstream consumer imply parity with the old Spotrac methodology.
#
# UNAVAILABLE / MISSING CACHE BEHAVIOR: if cache/bbref_team_payroll_active_roster.rds
# and/or cache/bbref_player_contracts.rds are missing, unreadable, or malformed
# (e.g. an upstream fetch stage failed), this script does NOT crash and does
# NOT fall back to hardcoded Spotrac snapshots or proportional-fill salary
# estimates (#75). Instead, it logs a clear [CBA_BBREF_UNAVAILABLE] message and
# emits explicit NA (JSON null) / empty contracts ([]) with the unavailable
# reason recorded in `cbaThresholdSources`.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------
# BBRef cache paths (#98/#100's outputs) and the BBRef -> this-repo team
# abbreviation remap. Basketball-Reference uses three team abbreviations that
# differ from the ones used throughout this repo (cap_data_phase3_findings.md
# §3): PHO (Suns) -> PHX, CHO (Hornets) -> CHA, BRK (Nets) -> BKN. Applied
# uniformly to every BBRef team code before use so it matches this repo's own
# abbreviations (used in repeater_teams, handcuffs, charts, etc.).
# ------------------------------------------------------------------------------
CACHE_BBREF_PLAYER_CONTRACTS    <- file.path(CACHE_DIR, "bbref_player_contracts.rds")
CACHE_BBREF_TEAM_PAYROLL_ACTIVE <- file.path(CACHE_DIR, "bbref_team_payroll_active_roster.rds")

BBREF_TEAM_ABBR_REMAP <- c(PHO = "PHX", CHO = "CHA", BRK = "BKN")

remap_bbref_team_abbr <- function(team_abbr) {
  hit <- BBREF_TEAM_ABBR_REMAP[team_abbr]
  ifelse(is.na(hit), team_abbr, hit)
}

message(">>> [CBA ARCHITECT] Initializing Calibrated 2026-2027 CBA Salary Cap & Apron Analytics Engine...")

# CBA Financial Thresholds for 2026-2027 Season ($M)
SALARY_CAP       <- 165.0
LUXURY_TAX       <- 200.4
FIRST_APRON      <- 209.0
SECOND_APRON     <- 221.7
CAP_PROJ_2027    <- 181.5
CAP_PROJ_2028    <- 199.6

# ------------------------------------------------------------------------------
# Luxury Tax Calculation Function (Progressive Brackets + Repeater Penalties)
# ------------------------------------------------------------------------------
#' #117: the rates below were the pre-2023-CBA schedule (1.50/1.75/2.50/3.25
#' standard, 2.50/2.75/3.50/4.25 repeater) -- stale for the 2026-27 season this
#' dataset represents. Verified against the 2023 CBA's tax-rate schedule for
#' 2025-26-and-later (Article VII; the rate *multipliers* are fixed from
#' 2025-26 onward, only the dollar bracket widths grow with the cap each
#' year) via the Hoops Rumors CBA glossary, which cites the CBA directly:
#' https://www.hoopsrumors.com/2024/11/hoops-rumors-glossary-luxury-tax-penalties-4.html
#' Standard: $1.00 / $1.25 / $3.50 / $4.75 per dollar in brackets 1-4, +$0.50
#' per bracket thereafter. Repeater: $3.00 / $3.25 / $5.50 / $6.75, +$0.50 per
#' bracket thereafter (always $2.00 above the standard rate here).
#' Bracket *width* in the live CBA scales with the salary cap rather than
#' being a fixed $5M; this dataset's cap/threshold constants above are
#' already stylized round numbers rather than the officially reported
#' figures, so the fixed $5M-wide brackets below are kept as the existing
#' structural approach -- only the per-dollar rates were wrong and are fixed
#' here. Revisiting bracket width to scale with SALARY_CAP is a larger,
#' separate change and is left out of this fix.
compute_luxury_tax <- function(payroll, is_repeater = FALSE) {
  # #125 (supersedes the narrower #117 fix below): rewritten with
  # pmin()/pmax() so the function vectorises directly over `payroll`
  # instead of using scalar `if()`, which used to raise "missing value
  # where TRUE/FALSE needed" on a single NA and "the condition has length
  # > 1" on any vector input.
  #   - NULL / length-0 payroll: nothing to compute -> NA_real_.
  #   - NA/NaN payroll (scalar or any element of a vector): pmin()/pmax()
  #     propagate NA/NaN through arithmetic without erroring, so that
  #     element's tax bill is NA_real_ instead of crashing the whole call.
  #   - Inf payroll: an infinite overage correctly yields an infinite (not
  #     NaN, not an error) tax bill -- the dollar amount owed on unbounded
  #     overage is itself unbounded, so Inf is the sensible result here.
  #   - NA repeater flag: treated as FALSE (standard rate) with a logged
  #     warning, rather than guessing silently or erroring.
  payroll <- as.numeric(payroll)
  if (length(payroll) == 0L) return(NA_real_)
  # Normalise NaN to NA_real_ up front so NaN and NA payroll both yield the
  # same NA_real_ result (both satisfy is.na(), but are distinct bit
  # patterns in R and would otherwise print differently downstream).
  payroll[is.nan(payroll)] <- NA_real_

  is_repeater <- as.logical(is_repeater)
  if (length(is_repeater) == 0L) is_repeater <- FALSE
  if (anyNA(is_repeater)) {
    warning(
      "compute_luxury_tax(): NA repeater flag encountered; treating as FALSE (standard rate)",
      call. = FALSE
    )
    is_repeater[is.na(is_repeater)] <- FALSE
  }
  is_repeater <- rep_len(is_repeater, length(payroll))

  overage <- pmax(payroll - LUXURY_TAX, 0)

  # Standard vs Repeater rates per bracket ($0-5M, $5-10M, $10-15M, $15-20M, >$20M)
  std_rates <- c(1.00, 1.25, 3.50, 4.75, 5.25)
  rep_rates <- c(3.00, 3.25, 5.50, 6.75, 7.25)

  # Bracket widths: $5M each for brackets 1-4, uncapped (whatever remains)
  # for bracket 5. Equivalent to the original scalar bracket-by-bracket
  # `if` chain, just computed for every element at once.
  b1 <- pmin(overage, 5.0)
  b2 <- pmin(pmax(overage - 5.0, 0), 5.0)
  b3 <- pmin(pmax(overage - 10.0, 0), 5.0)
  b4 <- pmin(pmax(overage - 15.0, 0), 5.0)
  b5 <- pmax(overage - 20.0, 0)

  bracket_bill <- function(rates) {
    b1 * rates[1] + b2 * rates[2] + b3 * rates[3] + b4 * rates[4] + b5 * rates[5]
  }

  tax_bill <- ifelse(is_repeater, bracket_bill(rep_rates), bracket_bill(std_rates))

  round(tax_bill, 1)
}

# ------------------------------------------------------------------------------
# Static 30-team NBA franchise reference (abbreviation, name, conference) and
# repeater tax status. Contains NO salary/payroll dollar figures (#75 removed
# hardcoded Spotrac payroll and contract fallbacks).
# ------------------------------------------------------------------------------
repeater_teams <- c("GSW", "BOS", "PHX", "DEN", "MIL", "LAC")

NBA_TEAMS_REF <- tribble(
  ~team_abbr, ~team_name, ~conf,
  "GSW", "Warriors", "West",
  "MIN", "Timberwolves", "West",
  "WAS", "Wizards", "East",
  "PHX", "Suns", "West",
  "DEN", "Nuggets", "West",
  "SAS", "Spurs", "West",
  "ATL", "Hawks", "East",
  "CLE", "Cavaliers", "East",
  "NYK", "Knicks", "East",
  "ORL", "Magic", "East",
  "OKC", "Thunder", "West",
  "PHI", "76ers", "East",
  "MIA", "Heat", "East",
  "TOR", "Raptors", "East",
  "SAC", "Kings", "West",
  "HOU", "Rockets", "West",
  "NOP", "Pelicans", "West",
  "IND", "Pacers", "East",
  "BOS", "Celtics", "East",
  "DAL", "Mavericks", "West",
  "DET", "Pistons", "East",
  "POR", "Trail Blazers", "West",
  "LAL", "Lakers", "West",
  "LAC", "Clippers", "West",
  "MIL", "Bucks", "East",
  "UTA", "Jazz", "West",
  "CHA", "Hornets", "East",
  "CHI", "Bulls", "East",
  "MEM", "Grizzlies", "West",
  "BKN", "Nets", "East"
)

# ------------------------------------------------------------------------------
# Automated BBRef sourcing (#101, Phase 4; #75 removes Spotrac/proportional
# fallbacks). Builds `team_payrolls` from
# cache/bbref_team_payroll_active_roster.rds (#100) and `verified_contracts`
# from cache/bbref_player_contracts.rds (#98). If either cache is missing,
# unreadable, or doesn't have the columns these loaders expect, logs
# [CBA_BBREF_UNAVAILABLE] and returns NULL data with the reason so the export
# emits explicit NA (JSON null) / empty contracts ([]) instead of synthetic or
# stale Spotrac numbers.
# ------------------------------------------------------------------------------
bbref_cba_unavailable <- function(reason) {
  message(sprintf(
    "[CBA_BBREF_UNAVAILABLE] build_cba_cap_dataset.R: %s Emitting NA/empty unavailable values with reason (no Spotrac or proportional-fill fallback).",
    reason
  ))
  reason
}

#' Build `team_payrolls` (team_abbr, team_name, conf, payroll_2026,
#' payroll_2027, payroll_2028) from the BBRef active-roster aggregate. BBRef
#' only carries the CURRENT season's active-roster salary -- there is no
#' forward-looking 2027-28/2028-29 figure to read, automated or otherwise.
#' 2027/2028 are therefore projected from the current total using the same
#' league-wide cap growth rates (CAP_PROJ_2027/SALARY_CAP, CAP_PROJ_2028/SALARY_CAP)
#' already used elsewhere in this file for projectedCapSpace -- an explicit
#' modeling assumption (team payroll grows with the league cap), not a
#' second sourced figure. team_name/conf are looked up from NBA_TEAMS_REF.
build_team_payrolls_from_bbref <- function() {
  if (!file.exists(CACHE_BBREF_TEAM_PAYROLL_ACTIVE)) {
    reason <- bbref_cba_unavailable(sprintf("%s does not exist.", CACHE_BBREF_TEAM_PAYROLL_ACTIVE))
    return(list(data = NULL, reason = reason))
  }
  bbref_payroll <- tryCatch(readRDS(CACHE_BBREF_TEAM_PAYROLL_ACTIVE), error = function(e) NULL)
  required_cols <- c("team_abbr", "active_roster_salary_total")
  if (is.null(bbref_payroll) || !all(required_cols %in% names(bbref_payroll)) || nrow(bbref_payroll) == 0) {
    reason <- bbref_cba_unavailable(sprintf("%s was unreadable, empty, or missing expected column(s).", CACHE_BBREF_TEAM_PAYROLL_ACTIVE))
    return(list(data = NULL, reason = reason))
  }

  bbref_payroll$team_abbr <- remap_bbref_team_abbr(bbref_payroll$team_abbr)
  team_ref <- NBA_TEAMS_REF

  built <- bbref_payroll %>%
    transmute(team_abbr, payroll_2026 = round(active_roster_salary_total / 1e6, 1)) %>%
    inner_join(team_ref, by = "team_abbr") %>%
    mutate(
      payroll_2027 = round(payroll_2026 * (CAP_PROJ_2027 / SALARY_CAP), 1),
      payroll_2028 = round(payroll_2026 * (CAP_PROJ_2028 / SALARY_CAP), 1)
    ) %>%
    select(team_abbr, team_name, conf, payroll_2026, payroll_2027, payroll_2028)

  if (nrow(built) < nrow(team_ref)) {
    reason <- bbref_cba_unavailable(sprintf(
      "Only %d of %d known teams matched after the BBRef team-abbreviation remap.",
      nrow(built), nrow(team_ref)
    ))
    return(list(data = NULL, reason = reason))
  }

  list(data = built, reason = NULL)
}

#' Build `verified_contracts` (named list, one element per team, each a list
#' of per-player rows) from the raw BBRef contracts cache.
#'
#' BBRef's contracts table carries no playerId, position, or contractType --
#' those are JSON-schema-required, non-nullable fields downstream
#' (web/tests/contracts/schemas.ts's PlayerContractSchema is .strict() with
#' playerId/position/contractType all required; NA would serialize to a JSON
#' null and fail that contract test / risk a render crash, per #113's
#' regression guard in web/tests/components/CapSheetNullFields.test.tsx,
#' which only tolerates null on the numeric salary fields). So:
#'   - playerId: a synthetic but stable "bbref-<team>-<rank>" string (BBRef
#'     has no numeric player id on this page at all).
#'   - position: looked up by name from the projections player catalog
#'     (projections_season_players.json), falling back to "F" when no match is
#'     found -- noted explicitly, never silently guessed without saying so.
#'   - contractType: BBRef's table has no option/guaranteed flag, so this
#'     defaults to "Guaranteed" (the modal case league-wide), and is disclosed
#'     in `notes` on every row rather than presented as sourced.
build_verified_contracts_from_bbref <- function() {
  if (!file.exists(CACHE_BBREF_PLAYER_CONTRACTS)) {
    reason <- bbref_cba_unavailable(sprintf("%s does not exist.", CACHE_BBREF_PLAYER_CONTRACTS))
    return(list(data = NULL, reason = reason))
  }
  contracts <- tryCatch(readRDS(CACHE_BBREF_PLAYER_CONTRACTS), error = function(e) NULL)
  required_cols <- c("player", "team", "salary_y1")
  if (is.null(contracts) || !all(required_cols %in% names(contracts)) || nrow(contracts) == 0) {
    reason <- bbref_cba_unavailable(sprintf("%s was unreadable, empty, or missing expected column(s).", CACHE_BBREF_PLAYER_CONTRACTS))
    return(list(data = NULL, reason = reason))
  }

  contracts$team <- remap_bbref_team_abbr(contracts$team)
  contracts <- contracts[!is.na(contracts$team) & trimws(contracts$team) != "", , drop = FALSE]
  contracts <- contracts[!is.na(contracts$player) & trimws(contracts$player) != "", , drop = FALSE]
  to_m <- function(x) ifelse(is.na(x), 0.0, round(x / 1e6, 1))

  position_lookup_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
  position_lookup <- NULL
  if (file.exists(position_lookup_file)) {
    position_lookup <- tryCatch(fromJSON(position_lookup_file), error = function(e) NULL)
  }
  lookup_position <- function(player_name, team_code) {
    if (is.null(position_lookup)) return(NA_character_)
    hit <- position_lookup[
      !is.na(position_lookup$player_name) &
        tolower(trimws(position_lookup$player_name)) == tolower(trimws(player_name)) &
        !is.na(position_lookup$team) & position_lookup$team == team_code,
    ]
    if (nrow(hit) == 0) return(NA_character_)
    hit$position[1]
  }

  out <- list()
  for (code in unique(contracts$team)) {
    rows <- contracts[contracts$team == code, , drop = FALSE]
    rows <- rows[order(-ifelse(is.na(rows$salary_y1), 0, rows$salary_y1)), , drop = FALSE]
    out[[code]] <- lapply(seq_len(nrow(rows)), function(j) {
      r <- rows[j, ]
      pos <- lookup_position(r$player, code)
      pos_sourced <- !is.na(pos) && nzchar(pos)
      if (!pos_sourced) pos <- "F"
      list(
        playerId = sprintf("bbref-%s-%03d", code, j),
        playerName = r$player,
        position = pos,
        salary2026 = to_m(r$salary_y1),
        salary2027 = to_m(r$salary_y2),
        salary2028 = to_m(r$salary_y3),
        contractType = "Guaranteed",
        notes = paste(
          "Basketball-Reference /contracts/players.html (active roster; current-season salary_y1).",
          if (pos_sourced) {
            "Position from the projections player catalog."
          } else {
            "Position not found in the projections player catalog; defaulted to 'F', not sourced."
          },
          "contractType is not available from BBRef and defaults to 'Guaranteed'; not individually verified."
        )
      )
    })
  }
  list(data = out, reason = NULL)
}

payroll_res <- build_team_payrolls_from_bbref()
team_payrolls_sourced_from_bbref <- !is.null(payroll_res$data)
team_payrolls_unavailable_reason <- payroll_res$reason
team_payrolls <- if (team_payrolls_sourced_from_bbref) {
  payroll_res$data
} else {
  NBA_TEAMS_REF %>%
    mutate(
      payroll_2026 = NA_real_,
      payroll_2027 = NA_real_,
      payroll_2028 = NA_real_
    )
}

contracts_res <- build_verified_contracts_from_bbref()
verified_contracts <- contracts_res$data
verified_contracts_sourced_from_bbref <- !is.null(verified_contracts)
verified_contracts_unavailable_reason <- contracts_res$reason

# Build franchise CBA profiles
franchise_profiles <- list()

for (i in 1:nrow(team_payrolls)) {
  tm <- team_payrolls[i, ]
  code <- tm$team_abbr
  payroll <- tm$payroll_2026
  payroll_27 <- tm$payroll_2027
  payroll_28 <- tm$payroll_2028
  has_payroll <- !is.na(payroll)

  is_rep <- code %in% repeater_teams
  tax_bill <- compute_luxury_tax(payroll, is_rep)
  total_commitment <- if (has_payroll && !is.na(tax_bill)) round(payroll + tax_bill, 1) else NA_real_

  # CBA Tier Classification
  tier <- if (!has_payroll) {
    NA_character_
  } else if (payroll > SECOND_APRON) {
    "Second Apron Restricted"
  } else if (payroll > FIRST_APRON) {
    "First Apron Team"
  } else if (payroll > LUXURY_TAX) {
    "Taxpayer (Below Apron 1)"
  } else if (payroll > SALARY_CAP) {
    "Over Cap (Non-Taxpayer)"
  } else {
    "Under Cap Room"
  }

  # Space calculations ($M)
  cap_sp <- if (has_payroll) round(max(0, SALARY_CAP - payroll), 1) else NA_real_
  tax_sp <- if (has_payroll) round(LUXURY_TAX - payroll, 1) else NA_real_
  a1_sp  <- if (has_payroll) round(FIRST_APRON - payroll, 1) else NA_real_
  a2_sp  <- if (has_payroll) round(SECOND_APRON - payroll, 1) else NA_real_

  # Multi-year projected cap room
  cap_sp_27 <- if (!is.na(payroll_27)) round(max(0, CAP_PROJ_2027 - payroll_27), 1) else NA_real_
  cap_sp_28 <- if (!is.na(payroll_28)) round(max(0, CAP_PROJ_2028 - payroll_28), 1) else NA_real_

  # CBA Handcuffs state machine
  is_a1 <- has_payroll && payroll > FIRST_APRON
  is_a2 <- has_payroll && payroll > SECOND_APRON

  handcuffs <- if (has_payroll) {
    list(
      frozenPick7Years = is_a2,
      noSalaryAggregation = is_a2,
      noCashInTrades = is_a2,
      noTpmle = is_a2,
      tradeSalaryMatchingPct = if (is_a1) 100 else if (payroll > SALARY_CAP) 125 else 200,
      signAndTradeHardCapped = is_a1
    )
  } else {
    list(
      frozenPick7Years = NA,
      noSalaryAggregation = NA,
      noCashInTrades = NA,
      noTpmle = NA,
      tradeSalaryMatchingPct = NA_real_,
      signAndTradeHardCapped = NA
    )
  }

  # Select contracts: BBRef verified contracts only; never synthesize
  # proportional-fill or Spotrac fallback rows when missing (#75).
  tm_contracts <- if (verified_contracts_sourced_from_bbref && code %in% names(verified_contracts)) {
    verified_contracts[[code]]
  } else {
    list()
  }

  franchise_profiles[[i]] <- list(
    teamAbbr = code,
    teamName = tm$team_name,
    conference = tm$conf,
    totalPayroll2026 = payroll,
    totalPayroll2027 = payroll_27,
    totalPayroll2028 = payroll_28,
    salaryCap = SALARY_CAP,
    luxuryTaxThreshold = LUXURY_TAX,
    firstApron = FIRST_APRON,
    secondApron = SECOND_APRON,
    capSpace2026 = cap_sp,
    taxSpace2026 = tax_sp,
    firstApronSpace2026 = a1_sp,
    secondApronSpace2026 = a2_sp,
    cbaTier = tier,
    isRepeaterTax = is_rep,
    luxuryTaxBill = tax_bill,
    totalFinancialCommitment = total_commitment,
    projectedCapSpace2027 = cap_sp_27,
    projectedCapSpace2028 = cap_sp_28,
    handcuffs = handcuffs,
    contracts = tm_contracts
  )
}

# League Aggregate Statistics
payrolls_2026 <- sapply(franchise_profiles, function(x) x$totalPayroll2026)
tax_bills_2026 <- sapply(franchise_profiles, function(x) x$luxuryTaxBill)
cap_spaces_2026 <- sapply(franchise_profiles, function(x) x$capSpace2026)

if (any(!is.na(payrolls_2026))) {
  total_tax_revenue <- round(sum(tax_bills_2026, na.rm = TRUE), 1)
  avg_payroll <- round(mean(payrolls_2026, na.rm = TRUE), 1)
  sec_apron_count <- sum(!is.na(payrolls_2026) & payrolls_2026 > SECOND_APRON)
  first_apron_count <- sum(!is.na(payrolls_2026) & payrolls_2026 > FIRST_APRON & payrolls_2026 <= SECOND_APRON)
  tax_count <- sum(!is.na(payrolls_2026) & payrolls_2026 > LUXURY_TAX)
  cap_room_count <- sum(!is.na(cap_spaces_2026) & cap_spaces_2026 > 0)
} else {
  total_tax_revenue <- NA_real_
  avg_payroll <- NA_real_
  sec_apron_count <- NA_integer_
  first_apron_count <- NA_integer_
  tax_count <- NA_integer_
  cap_room_count <- NA_integer_
}

cap_sheet_export <- list(
  # First in the object, for assertion F's 4096-byte head scan, and UTC with a
  # trailing Z because that is the only form .pw_payload_generated_at() parses.
  # web/tests/contracts/schemas.ts's CbaLeagueOverviewSchema is .strict(), so
  # this key had to be added there in the same change or the contract suite --
  # and therefore assertion G, which is fatal -- would reject the payload.
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  season = "2026-2027",
  cbaThresholdSources = paste(
    "Cap/tax/apron/minimum thresholds (salaryCap/luxuryTaxThreshold/firstApron/secondApron):",
    "manually-updated constants, sourced from the NBA's own official release",
    "(pr.nba.com), July 2026 -- no Basketball-Reference page carries these figures",
    "(see cap_data_phase3_findings.md), and they change only once per season.",
    if (team_payrolls_sourced_from_bbref) {
      paste(
        "Team payroll totals (payroll_2026): automated, from Basketball-Reference's",
        "/contracts/players.html active-roster current-season salaries, aggregated",
        "per team by tools/derive_team_payroll_from_bbref.R.",
        "ACTIVE-ROSTER SALARY ONLY -- excludes dead cap, cap holds, and",
        "non-guaranteed partial-season proration, so it is NOT the same quantity as",
        "a 'Total Cap Allocations' figure (e.g. Spotrac's) and will not match one",
        "team-for-team; see cap_data_phase3_findings.md for the quantified gap.",
        "payroll_2027/payroll_2028 are not BBRef figures -- they are this season's",
        "BBRef total projected forward using the league-wide cap growth rate",
        "(CAP_PROJ_2027/2028 vs. SALARY_CAP), an explicit modeling assumption."
      )
    } else {
      sprintf(
        paste(
          "Team payroll totals (payroll_2026/2027/2028): UNAVAILABLE this run (%s) --",
          "emitted as null with no Spotrac or estimated fallback."
        ),
        team_payrolls_unavailable_reason
      )
    },
    if (verified_contracts_sourced_from_bbref) {
      paste(
        "Per-player contract rows shown for the teams listed in verified_contracts:",
        "automated, read directly from Basketball-Reference's /contracts/players.html",
        "(tools/fetch_bbref_player_contracts.R); playerName/salary figures are",
        "sourced from BBRef, current-season salary only. playerId is a synthetic",
        "'bbref-<team>-<rank>' string (BBRef has no player id on this page);",
        "position is looked up from the projections player catalog where possible,",
        "else defaulted to 'F'; contractType defaults to 'Guaranteed' -- BBRef's",
        "table carries no option/guaranteed flag. All three are disclosed per-row",
        "in each contract's own `notes` field. Any team absent from the BBRef",
        "contracts cache has an empty contracts array (no proportional-fill estimate)."
      )
    } else {
      sprintf(
        paste(
          "Per-player contract rows: UNAVAILABLE this run (%s) --",
          "omitted (empty contracts array) with no Spotrac or proportional-fill fallback."
        ),
        verified_contracts_unavailable_reason
      )
    }
  ),
  salaryCap = SALARY_CAP,
  luxuryTaxThreshold = LUXURY_TAX,
  firstApron = FIRST_APRON,
  secondApron = SECOND_APRON,
  averagePayroll = avg_payroll,
  totalLeagueTaxRevenue = total_tax_revenue,
  secondApronTeamCount = sec_apron_count,
  firstApronTeamCount = first_apron_count,
  taxTeamCount = tax_count,
  capRoomTeamCount = cap_room_count,
  teams = franchise_profiles
)

# Export to Web JSON (na = "null" so unavailable NA values serialize as JSON null, not "NA")
output_json <- WEB_JSON_CBA_CAP_SHEET  # config.R
write_json(cap_sheet_export, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
message(sprintf(">>> [SUCCESS] Calibrated 2026-27 CBA Cap Sheet dataset exported to: %s", output_json))

# Cache RDS
saveRDS(cap_sheet_export, file.path(CACHE_DIR, "cba_cap_sheet.rds"))
message(">>> [SUCCESS] Cached RDS in: cache/cba_cap_sheet.rds")
