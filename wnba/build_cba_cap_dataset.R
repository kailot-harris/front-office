# ==============================================================================
# build_cba_cap_dataset.R
# WNBA CBA structural cap constants + real per-franchise roster facts
#
# PROVENANCE / DO NOT REINTRODUCE WITHOUT A REAL SOURCE (2026-11-02, WNBA_analytics#128)
# ------------------------------------------------------------------------------
# Until 2026-11-02 this script fabricated every individual player salary,
# contract type, team payroll target, and future-year (2027/2028) guaranteed
# salary with unseeded `runif()` draws -- the whole ~150-line contract
# generation and payroll-rescaling block that used to live here (per-player
# salary by tier, coin-flip contract type, random team payroll target,
# coin-flip future-year guarantees). None of it corresponded to any real WNBA
# contract data; it was presented to users as a "CBA Cap Sheet" with
# dollar-denominated salaries that were pure noise.
#
# What was checked for a real source before removing it (per issue #128's
# explicit instruction to document the check, not just assert no source
# exists):
#   - `wehoop` (the only real WNBA data-ingestion library this repo uses)
#     exposes box score / play-by-play / roster / standings endpoints only.
#     It has no contract, salary, or cap-hold endpoint of any kind -- checked
#     every exported function in the installed `wehoop` namespace
#     (`ls("package:wehoop")`) and the package's own documentation index; none
#     reference salary/contract/cap data.
#   - ESPN's public WNBA JSON endpoints (the other live source used elsewhere
#     in this repo, e.g. `injury_scraper.R`) do not carry contract/salary
#     fields on the roster or athlete endpoints.
#   - No other data source is wired into this repo's pipeline that could
#     supply individual player salaries, contract types, or team payroll
#     figures. Public real sources exist in principle (Her Hoop Stats,
#     Spotrac-style trackers, league/union CBA filings) but none are
#     ingested anywhere in this codebase, and scraping one ad hoc for this
#     ticket would itself be an unverified, undocumented new data dependency
#     -- out of scope for a fabrication *removal* ticket.
#
# Decision (per the cross-repo audit's binding decision rule, NFL_analytics#48):
# per-player salaries, contract type, team payroll targets, and future-year
# guarantees cannot be derived from any real source available to this repo,
# so they are REMOVED end-to-end (JSON payload, `web/lib/cbaTypes.ts`,
# `web/tests/contracts/schemas.ts`/`invariants.test.ts`/`schema.test.ts`,
# `web/tests/drift/content-drift.test.ts`, and the `WnbaFranchiseCapTable.tsx`
# / `HardCapCrunchMeter.tsx` components that rendered them -- both deleted).
# The six CBA structural constants below (hard cap, floor, supermax, vet max,
# vet min, rookie min) are NOT random draws -- they are fixed constants (their
# *values* are tracked separately by WNBA_analytics#140 and are out of scope
# here) -- so they are kept. Per-franchise `rosterCount` (a real count of rows
# in projections_season_players.json) and `corePlayer` (a deterministic lookup
# against the fixed, hand-curated CORE_STARS list below -- itself out of scope
# for this ticket) are also kept because neither is a random draw.
#
# Do not reintroduce per-player salaries, contract types, payroll targets, or
# future-year guarantees into this script's output unless a real, ingested
# data source for them exists -- a "realistic-looking" `runif()` draw is
# exactly the fabrication this ticket removed.
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")

build_cba_cap_dataset <- function() {
  log_info("Initializing 15-Team WNBA CBA Cap Sheet & Hard Cap Engine...",
           script = "build_cba_cap_dataset.R")
  message(">>> [CBA ENGINE] Initializing 15-Team WNBA CBA Cap Sheet & Hard Cap Engine...")

  players_json_path <- file.path("web", "public", "data", "projections_season_players.json")
  teams_json_path <- file.path("web", "public", "data", "projections_season_teams.json")

  if (!file.exists(players_json_path)) {
    warning("projections_season_players.json missing, using fallback empty dataset")
    return(invisible(FALSE))
  }

  players <- jsonlite::fromJSON(players_json_path)
  teams_data <- if (file.exists(teams_json_path)) jsonlite::fromJSON(teams_json_path) else list()

  # 2026 WNBA CBA Constants (in Millions of USD) now sourced from config.R
  # (WNBA_HARD_CAP, WNBA_CAP_FLOOR, WNBA_SUPERMAX, WNBA_VET_MAX, WNBA_MIN_VET,
  # WNBA_MIN_ROOKIE) rather than redefined locally -- see config.R for provenance.

  # Core / Supermax star player designations
  # NOTE: this is a fixed, hand-curated editorial list (not derived from any
  # random draw) used solely to surface a "designated core player" per
  # franchise below. Out of scope for the #128 fabrication audit (see
  # 2026-11-02 audit note at the bottom of this function) -- left as-is.
  CORE_STARS <- c(
    "Breanna Stewart", "A'ja Wilson", "Sabrina Ionescu", "Alyssa Thomas",
    "Napheesa Collier", "Jewell Loyd", "Kelsey Plum", "Arike Ogunbowale",
    "Jackie Young", "DeWanna Bonner", "Chelsea Gray", "Kahleah Copper",
    "Kayla McBride", "Natasha Cloud", "Jonquel Jones", "Brittney Griner",
    "Allisha Gray", "Brionna Jones", "Dearica Hamby", "Kelsey Mitchell"
  )

  # Group players by team
  team_abbrs <- unique(players$team)
  franchise_profiles <- list()

  for (abbr in team_abbrs) {
    team_players <- players[players$team == abbr, ]
    if (nrow(team_players) == 0) next

    team_info <- if (is.data.frame(teams_data) && abbr %in% teams_data$team) {
      teams_data[teams_data$team == abbr, ][1, ]
    } else {
      list(teamName = abbr, conference = "WNBA")
    }

    # Full team name and conference resolution
    team_name <- if (abbr %in% names(WNBA_TEAMS)) unname(WNBA_TEAMS[abbr]) else if (!is.null(team_info$teamName) && !is.na(team_info$teamName)) team_info$teamName else abbr
    east_teams <- c("ATL", "CHI", "CON", "IND", "NY", "WSH", "TOR")
    conf <- if (abbr %in% east_teams) "East" else "West"

    n_players <- nrow(team_players)

    # Real roster count -- the number of players this franchise actually has
    # in projections_season_players.json. This is NOT derived from any salary
    # or cap-space calculation (see 2026-11-02 audit note below): it is a
    # plain count of real roster rows.
    roster_count <- n_players

    # Real, non-random "designated core player" flag: the first name on this
    # roster that appears in the fixed CORE_STARS editorial list above, if
    # any. Not a salary figure and not drawn from runif().
    core_player_name <- NA_character_
    for (nm in team_players$player_name) {
      if (nm %in% CORE_STARS) {
        core_player_name <- nm
        break
      }
    }

    franchise_profiles[[length(franchise_profiles) + 1]] <- list(
      teamAbbr = abbr,
      teamName = team_name,
      conference = conf,
      hardSalaryCap = WNBA_HARD_CAP,
      capFloor = WNBA_CAP_FLOOR,
      rosterCount = roster_count,
      corePlayer = if (is.na(core_player_name)) "Unassigned" else core_player_name
    )
  }

  league_overview <- list(
    # First in the object, for assertion F's 4096-byte head scan, and UTC with
    # a trailing Z -- the only form .pw_payload_generated_at() parses.
    # WnbaCbaLeagueOverviewSchema in web/tests/contracts/schemas.ts is
    # .strict(), so the key is declared there in the same change.
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = "2026",
    hardSalaryCap = WNBA_HARD_CAP,
    capFloor = WNBA_CAP_FLOOR,
    supermaxSalary = WNBA_SUPERMAX,
    vetMaxSalary = WNBA_VET_MAX,
    vetMinSalary = WNBA_MIN_VET,
    rookieMinSalary = WNBA_MIN_ROOKIE,
    teams = franchise_profiles
  )

  # Export JSON and RDS
  out_json_web <- file.path("web", "public", "data", "cba_cap_sheet.json")
  out_rds_cache <- file.path(CACHE_DIR, "cba_cap_sheet.rds")

  jsonlite::write_json(league_overview, out_json_web, auto_unbox = TRUE, pretty = TRUE)
  saveRDS(league_overview, out_rds_cache)

  message(sprintf(">>> [SUCCESS] Wrote 15 WNBA Franchise CBA Cap Sheets to '%s'.", out_json_web))
  message(sprintf(">>> [SUCCESS] Cached RDS in '%s'.", out_rds_cache))
  log_info("WNBA CBA Cap Sheet generation complete.", script = "build_cba_cap_dataset.R",
           teams = length(franchise_profiles))

  invisible(TRUE)
}

if (!interactive()) {
  build_cba_cap_dataset()
}
