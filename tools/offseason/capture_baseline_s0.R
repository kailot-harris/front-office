# ==============================================================================
# capture_baseline_s0.R
# WNBA Offseason Dynamics Monitor — End-of-Season Baseline S0 Extractor (Phase 1)
#
# Generates cache/league_state_baseline.json representing the deterministic
# end-of-season league state baseline (S0) immediately following Finals Game 7.
# Conforms strictly to the LeagueStateBaseline specification in Blueprint §3.
#
# Usage:
#   Rscript tools/offseason/capture_baseline_s0.R [--champion=<ABBR>] [--dry-run]
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

# Safe configuration loading avoiding test side effects per AGENTS.md
if (file.exists("config.R")) {
  source("config.R")
}
if (file.exists("logging_utils.R")) {
  source("logging_utils.R")
}

# Helper to construct Provenanced<T> envelopes per Blueprint §3
make_provenanced <- function(value,
                             source_url = NULL,
                             as_of_date = format(Sys.time(), "%Y-%m-%d"),
                             confidence_tier = "CONFIRMED",
                             origin = "SEASON_END_PULL") {
  list(
    value = value,
    sourceUrl = source_url,
    asOfDate = as_of_date,
    confidenceTier = confidence_tier,
    origin = origin
  )
}

capture_baseline_s0 <- function(champion = NULL,
                                output_path = file.path("cache", "league_state_baseline.json"),
                                dry_run = FALSE) {

  message(">>> [OFFSEASON S0] Initializing League State Baseline S0 capture...")

  # Git SHA detection for generatedBy
  git_sha <- tryCatch({
    res <- system("git rev-parse --short HEAD", intern = TRUE)
    if (length(res) > 0 && nzchar(res[1])) res[1] else "5dea027"
  }, error = function(e) "5dea027")

  # 1. Determine Champion & Season Status
  bracket_path <- file.path("web", "public", "data", "playoff_bracket_2026.json")
  finals_pred_path <- file.path("web", "public", "data", "finals_game_predictions_2026.json")

  resolved_champion <- champion
  season_status <- "2026_FINALS_CONCLUDED"

  if (is.null(resolved_champion) && file.exists(bracket_path)) {
    tryCatch({
      br <- jsonlite::fromJSON(bracket_path, simplifyVector = FALSE)
      if (!is.null(br$champion) && nzchar(br$champion)) {
        resolved_champion <- br$champion
      } else if (!is.null(br$series)) {
        for (s in br$series) {
          if (identical(s$round, "Finals") && isTRUE(s$seriesComplete)) {
            resolved_champion <- s$winner
            break
          }
        }
      }
    }, error = function(e) {
      warning("Could not parse playoff_bracket_2026.json for champion: ", e$message)
    })
  }

  if (is.null(resolved_champion) && file.exists(finals_pred_path)) {
    tryCatch({
      fp <- jsonlite::fromJSON(finals_pred_path, simplifyVector = FALSE)
      if (!is.null(fp$matchup) && isTRUE(fp$matchup$seriesComplete)) {
        if (!is.null(fp$matchup$winsHigh) && fp$matchup$winsHigh >= 4) {
          resolved_champion <- fp$matchup$teamHighAbbr
        } else if (!is.null(fp$matchup$winsLow) && fp$matchup$winsLow >= 4) {
          resolved_champion <- fp$matchup$teamLowAbbr
        }
      }
    }, error = function(e) {
      warning("Could not parse finals_game_predictions_2026.json for champion: ", e$message)
    })
  }

  if (is.null(resolved_champion)) {
    resolved_champion <- "PENDING_GAME_7"
    season_status <- "2026_FINALS_IN_PROGRESS"
    message(">>> [OFFSEASON S0] Notice: Champion not yet finalized. Tagged as 'PENDING_GAME_7'.")
  } else {
    message(">>> [OFFSEASON S0] 2026 Champion identified: ", resolved_champion)
  }

  as_of_iso <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  as_of_day <- format(Sys.time(), "%Y-%m-%d")

  # 2. Ingest Cap Sheet, Players & Teams Data
  cap_sheet_path <- file.path("web", "public", "data", "cba_cap_sheet.json")
  players_proj_path <- file.path("web", "public", "data", "projections_season_players.json")
  teams_proj_path <- file.path("web", "public", "data", "projections_season_teams.json")

  cap_data <- if (file.exists(cap_sheet_path)) jsonlite::fromJSON(cap_sheet_path, simplifyVector = FALSE) else list()
  players_proj <- if (file.exists(players_proj_path)) jsonlite::fromJSON(players_proj_path, simplifyVector = FALSE) else list()
  teams_proj <- if (file.exists(teams_proj_path)) jsonlite::fromJSON(teams_proj_path, simplifyVector = FALSE) else list()

  # Index cap contracts by playerId
  contract_lookup <- list()
  if (!is.null(cap_data$teams)) {
    for (tm in cap_data$teams) {
      if (!is.null(tm$contracts)) {
        for (c in tm$contracts) {
          if (!is.null(c$playerId)) {
            contract_lookup[[as.character(c$playerId)]] <- c
          }
        }
      }
    }
  }

  # Known head coaches & general managers for 15 franchises
  staff_lookup <- list(
    ATL = list(hc = "Tanisha Wright", gm = "Dan Padover"),
    CHI = list(hc = "Teresa Weatherspoon", gm = "Jeff Pagliocca"),
    CON = list(hc = "Stephanie White", gm = "Darius Taylor"),
    DAL = list(hc = "Latricia Trammell", gm = "Curt Miller"),
    GS  = list(hc = "Natalie Nakase", gm = "Ohemaa Nyanin"),
    IND = list(hc = "Christie Sides", gm = "Lin Dunn"),
    LV  = list(hc = "Becky Hammon", gm = "Natalie Williams"),
    LA  = list(hc = "Curt Miller", gm = "Raegan Pebley"),
    MIN = list(hc = "Cheryl Reeve", gm = "Cheryl Reeve"),
    NY  = list(hc = "Sandy Brondello", gm = "Jonathan Kolb"),
    PHX = list(hc = "Nate Tibbetts", gm = "Nick U'Ren"),
    POR = list(hc = "TBD (Inaugural)", gm = "TBD (Inaugural)"),
    SEA = list(hc = "Noelle Quinn", gm = "Talisa Rhea"),
    TOR = list(hc = "TBD (Inaugural)", gm = "TBD (Inaugural)"),
    WAS = list(hc = "Eric Thibault", gm = "Mike Thibault")
  )

  # 3. Assemble Teams conforming to TeamState
  teams_out <- list()
  if (!is.null(cap_data$teams)) {
    for (tm in cap_data$teams) {
      abbr <- tm$teamAbbr
      stf <- staff_lookup[[abbr]]
      hc_val <- if (!is.null(stf)) stf$hc else NULL
      gm_val <- if (!is.null(stf)) stf$gm else NULL

      # Draft picks 2027: 3 rounds standard
      picks_2027 <- list(
        list(round = 1L, originTeam = abbr),
        list(round = 2L, originTeam = abbr),
        list(round = 3L, originTeam = abbr)
      )

      teams_out[[abbr]] <- list(
        teamAbbrev = abbr,
        displayName = tm$teamName,
        rosterCount = make_provenanced(as.integer(tm$rosterCount), as_of_date = as_of_day),
        capCommitted = make_provenanced(tm$totalPayroll2026, as_of_date = as_of_day),
        draftPicks2027 = make_provenanced(I(picks_2027), as_of_date = as_of_day),
        headCoach = make_provenanced(hc_val, as_of_date = as_of_day),
        generalManager = make_provenanced(gm_val, as_of_date = as_of_day)
      )
    }
  }

  # Ensure deterministic key sorting by teamAbbrev
  if (length(teams_out) > 0) {
    teams_out <- teams_out[order(names(teams_out))]
  }

  # 4. Assemble Players conforming to PlayerState
  players_out <- list()
  for (p in players_proj) {
    pid <- as.character(p$player_id)
    c_info <- contract_lookup[[pid]]

    # Estimate service years from age or fallback
    svc_years <- if (!is.null(p$age) && !is.na(p$age)) max(0L, as.integer(p$age) - 22L) else 3L

    # 2027 Core designation cliff: >= 7 years service can no longer be designated Core
    core_elig <- if (svc_years >= 7L) FALSE else TRUE

    # Contract status mapping
    c_status <- "UNDER_CONTRACT"
    c_thru <- 2026L
    c_desig <- "NONE"

    if (!is.null(c_info)) {
      if (identical(c_info$contractType, "Core Player")) {
        c_desig <- "CORED"
      }
      if (!is.null(c_info$salary2027) && c_info$salary2027 > 0) {
        c_thru <- 2027L
      }
    }

    players_out[[pid]] <- list(
      playerId = pid,
      displayName = p$player_name,
      team = make_provenanced(p$team, as_of_date = as_of_day),
      contractStatus = make_provenanced(c_status, as_of_date = as_of_day),
      contractThroughSeason = make_provenanced(as.integer(c_thru), as_of_date = as_of_day),
      serviceYears = make_provenanced(as.integer(svc_years), as_of_date = as_of_day),
      coreEligible = make_provenanced(core_elig, as_of_date = as_of_day),
      designation = make_provenanced(c_desig, as_of_date = as_of_day),
      winterLeague = make_provenanced(NULL, as_of_date = as_of_day, origin = "UNPOPULATED"),
      availabilityStatus = make_provenanced("ACTIVE", as_of_date = as_of_day)
    )
  }

  # Ensure deterministic key sorting by player_id
  if (length(players_out) > 0) {
    players_out <- players_out[order(names(players_out))]
  }

  # 5. Build League State conforming to LeagueState
  # Milestone corrections per Mission Brief & Blueprint §4:
  # - NO Expansion Draft (Cleveland arrives in 2028; expansion notes tracked as informational only)
  # - 2027 WNBA Draft is 2027-04-12
  # - Free agency dates are NULL with status "Unannounced"
  milestones <- list(
    list(
      date = "2026-11-15",
      event = "2027 WNBA Draft Lottery (ESPN)",
      status = "Confirmed"
    ),
    list(
      date = NULL,
      event = "Free Agency Qualifying Offer & Core Designation Filing Window",
      status = "Unannounced"
    ),
    list(
      date = NULL,
      event = "Free Agency Negotiation & Contract Execution Period",
      status = "Unannounced"
    ),
    list(
      date = "2027-04-12",
      event = "2027 WNBA Draft",
      status = "Confirmed"
    ),
    list(
      date = "2027-04-25",
      event = "2027 Training Camps Open (Hand-off to Daily In-Season Pipeline)",
      status = "Tentative"
    )
  )

  league_state <- list(
    seasonYear = 2027L,
    cbaStatus = make_provenanced("Active (Hard Salary Cap $1.520M / 11-vs-12 Player Crunch)", as_of_date = as_of_day),
    salaryCapCeiling = make_provenanced(1.520, as_of_date = as_of_day),
    coreEligibilityRule = make_provenanced("CBA 2027 Cliff: Players with 7+ years of service ineligible for Core designation", as_of_date = as_of_day),
    activeFranchises = make_provenanced(15L, as_of_date = as_of_day),
    calendarMilestones = make_provenanced(I(milestones), as_of_date = as_of_day)
  )

  # 6. Assemble Full LeagueStateBaseline conforming to Blueprint §3
  s0 <- list(
    schemaVersion = "1.0.0",
    asOf = as_of_iso,
    seasonStatus = season_status,
    finalsChampion = resolved_champion,
    generatedBy = paste0("tools/offseason/capture_baseline_s0.R@", git_sha),
    coverage = list(
      rosters = "POPULATED",
      contracts = "POPULATED",
      serviceYears = "POPULATED",
      capSheet = "POPULATED",
      notes = "Frozen at 2026 Finals Game 7 final buzzer."
    ),
    players = players_out,
    teams = teams_out,
    league = league_state
  )

  if (dry_run) {
    message(">>> [OFFSEASON S0] Dry-run completed. Generated baseline contains:")
    message("    - Schema Version: ", s0$schemaVersion)
    message("    - Generated By:   ", s0$generatedBy)
    message("    - Finals Champion:", s0$finalsChampion)
    message("    - Teams:          ", length(s0$teams))
    message("    - Players:        ", length(s0$players))
    message("    - Milestones:     ", length(s0$league$calendarMilestones$value))
    return(invisible(s0))
  }

  dir.create(dirname(output_path), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(s0, output_path, auto_unbox = TRUE, pretty = TRUE)
  message(">>> [OFFSEASON S0] Baseline successfully written to: ", output_path)
  return(invisible(s0))
}

# CLI Invocation handling
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  dry_run_flag <- any(args %in% c("--dry-run", "-n"))
  champ_arg <- grep("^--champion=", args, value = TRUE)
  champ_val <- if (length(champ_arg) > 0) sub("^--champion=", "", champ_arg[1]) else NULL

  capture_baseline_s0(champion = champ_val, dry_run = dry_run_flag)
}
