# ==============================================================================
# build_cba_cap_dataset.R
# Deterministic WNBA CBA & Salary Cap Structural Rules Exporter (Issue #150)
#
# SPIKE FINDINGS — WNBA Contract & Per-Player Salary Data Availability (#150)
# ==============================================================================
#
# 1. `wehoop` R Package Audit (v2.1+ / SportsDataverse):
#    Inspected all 214 exported functions in `ls("package:wehoop")` across the
#    `espn_wnba_*`, `load_wnba_*`, and `wnba_*` (stats.wnba.com) namespaces.
#    `wehoop` provides play-by-play, team/player box scores, schedules,
#    standings, rosters (`espn_wnba_team_roster`, `wnba_commonteamroster`),
#    draft boards (`wnba_drafthistory`, `wnba_draftboard`), and a basic free
#    agents status feed (`wnba_franchiseleaders`, `wnba_freeagents`). It exports
#    ZERO endpoints for player contract salaries, cap hits, contract lengths,
#    guaranteed money, or team salary cap ledgers. There is no WNBA equivalent
#    to `nflreadr::load_contracts()` or `hoopR` salary tables.
#
# 2. Public Web Trackers (Her Hoop Stats, Spotrac, Across the Timeline):
#    - Her Hoop Stats (herhoopstats.com/salary-cap-sheet): The canonical public
#      WNBA cap reference, but individual salary sheets and multi-year contract
#      breakdowns are gated behind a paid subscription paywall and governed by
#      restrictive Terms of Service prohibiting automated scraping/redistribution.
#    - Spotrac (spotrac.com/wnba): Renders team cap tables via client-side walls
#      and Cloudflare bot protection; HTML DOM structure changes frequently and
#      lacks a documented JSON/CSV feed.
#    - Across the Timeline (acrossthetimeline.com): Community tracker without a
#      versioned API or bulk export contract.
#    Per repo policy ("No silent fallbacks — if a live data source fails, fail
#    visibly; never substitute synthetic data"), relying on brittle HTML scraping
#    of paywalled or bot-protected pages in an automated weekly/daily GitHub
#    Actions pipeline is unmaintainable.
#
# 3. WNBA CBA Structural Constants (`config.R`):
#    League-wide CBA structural parameters ARE publicly ratified and stable for
#    the season (Hard Salary Cap ceiling, Cap Floor minimum spend, Supermax /
#    Core max salary, Veteran Max salary, Veteran Minimum, and Rookie Minimum).
#    These constants are centralized in `config.R` (`WNBA_HARD_CAP`,
#    `WNBA_CAP_FLOOR`, `WNBA_SUPERMAX`, `WNBA_VET_MAX`, `WNBA_MIN_VET`,
#    `WNBA_MIN_ROOKIE`).
#
# 4. Maintainability Verdict — Outcome B (No Viable Per-Player Salary Source):
#    Following the precedent established in `NFL_analytics#48` and `WNBA#128`,
#    this pipeline adopts Outcome B:
#    - Per-player `baseSalary`, `contractType`, `freeAgentYear`, team `totalSalary`,
#      and team `capSpace` are permanently excluded from `cba_cap_sheet.json`
#      rather than approximated or fabricated.
#    - `build_cba_cap_dataset.R` deterministically emits only the verified
#      league-wide CBA structural constants from `config.R` alongside real team
#      roster counts and metadata derived from `projections_season_players.json`
#      and `projections_season_teams.json`.
# ==============================================================================

source("config.R")
suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
})

build_cba_cap_dataset <- function(
  players_path = "web/public/data/projections_season_players.json",
  teams_path = "web/public/data/projections_season_teams.json",
  out_json_path = "web/public/data/cba_cap_sheet.json",
  out_rds_path = "cache/cba_cap_sheet.rds",
  persist = TRUE
) {
  message(">>> Building WNBA CBA & Salary Cap Structural Dataset (Outcome B)...")

  if (!file.exists(players_path) || !file.exists(teams_path)) {
    stop("Required projection files missing. Run export_web_datasets.R first.")
  }

  players <- fromJSON(players_path)
  teams <- fromJSON(teams_path)

  # Derive deterministic timestamp from upstream data state so repeated runs on
  # identical upstream inputs produce byte-identical JSON artifacts.
  baseline_state_path <- "cache/league_state_baseline.json"
  generated_at_ts <- if (file.exists(baseline_state_path)) {
    bs <- tryCatch(fromJSON(baseline_state_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(bs) && !is.null(bs$asOf)) as.character(bs$asOf) else "2026-11-07T00:00:00Z"
  } else {
    "2026-11-07T00:00:00Z"
  }

  teams_list <- list()

  for (i in seq_len(nrow(teams))) {
    t_row <- teams[i, ]
    t_abbr <- t_row$team

    t_players <- players %>%
      filter(team == t_abbr)

    full_name <- if (t_abbr %in% names(WNBA_TEAMS)) {
      unname(WNBA_TEAMS[t_abbr])
    } else if ("_row" %in% names(t_row) && !is.na(t_row$`_row`) && nzchar(t_row$`_row`)) {
      t_row$`_row`
    } else {
      t_row$team_name
    }

    teams_list[[i]] <- list(
      teamAbbr = t_abbr,
      teamName = full_name,
      conference = t_row$conference,
      hardSalaryCap = WNBA_HARD_CAP,
      capFloor = WNBA_CAP_FLOOR,
      rosterCount = nrow(t_players),
      corePlayer = "Unassigned"
    )
  }

  # Sort teams deterministically by teamAbbr
  team_abbrs <- vapply(teams_list, function(x) x$teamAbbr, character(1))
  teams_list <- teams_list[order(team_abbrs)]

  output_data <- list(
    generated_at = generated_at_ts,
    season = as.character(CURRENT_SEASON),
    hardSalaryCap = WNBA_HARD_CAP,
    capFloor = WNBA_CAP_FLOOR,
    supermaxSalary = WNBA_SUPERMAX,
    vetMaxSalary = WNBA_VET_MAX,
    vetMinSalary = WNBA_MIN_VET,
    rookieMinSalary = WNBA_MIN_ROOKIE,
    teams = teams_list
  )

  if (isTRUE(persist)) {
    dir.create(dirname(out_json_path), recursive = TRUE, showWarnings = FALSE)
    write_json(output_data, out_json_path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    message(">>> Successfully wrote CBA structural rules dataset to ", out_json_path)

    if (!is.null(out_rds_path) && nzchar(out_rds_path)) {
      dir.create(dirname(out_rds_path), recursive = TRUE, showWarnings = FALSE)
      saveRDS(output_data, out_rds_path)
    }
  }

  invisible(output_data)
}

if (sys.nframe() == 0L) {
  build_cba_cap_dataset()
}
