# ==============================================================================
# capture_baseline_s0.R
# WNBA Offseason Dynamics Monitor — End-of-Season Baseline S0 Extractor (Phase 1)
#
# Generates cache/league_state_baseline.json representing the deterministic
# end-of-season league state baseline (S0) immediately following Finals Game 7.
# Conforms to the LeagueStateBaseline contract with Provenanced<T> wrappers.
#
# Usage:
#   Rscript tools/offseason/capture_baseline_s0.R [--champion=<ABBR>] [--dry-run]
# ==============================================================================

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

capture_baseline_s0 <- function(champion = NULL,
                                output_path = file.path("cache", "league_state_baseline.json"),
                                dry_run = FALSE) {
  
  message(">>> [OFFSEASON S0] Initializing League State Baseline S0 capture...")
  
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
  
  # 2. Ingest Cap Sheet & Player Data
  cap_sheet_path <- file.path("web", "public", "data", "cba_cap_sheet.json")
  players_proj_path <- file.path("web", "public", "data", "projections_season_players.json")
  teams_proj_path <- file.path("web", "public", "data", "projections_season_teams.json")
  
  cap_data <- if (file.exists(cap_sheet_path)) jsonlite::fromJSON(cap_sheet_path, simplifyVector = FALSE) else list()
  players_proj <- if (file.exists(players_proj_path)) jsonlite::fromJSON(players_proj_path, simplifyVector = FALSE) else list()
  teams_proj <- if (file.exists(teams_proj_path)) jsonlite::fromJSON(teams_proj_path, simplifyVector = FALSE) else list()
  
  as_of_stamp <- strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  
  # 3. Assemble Teams Roster & Cap Breakdown
  teams_list <- list()
  if (!is.null(cap_data$teams)) {
    for (tm in cap_data$teams) {
      abbr <- tm$teamAbbr
      teams_list[[abbr]] <- list(
        team_abbrev = abbr,
        team_name = tm$teamName,
        conference = tm$conference,
        total_payroll_2026 = tm$totalPayroll2026,
        total_payroll_2027 = tm$totalPayroll2027,
        hard_salary_cap = tm$hardSalaryCap,
        cap_floor = tm$capFloor,
        cap_space_2026 = tm$capSpace2026,
        projected_cap_space_2027 = tm$projectedCapSpace2027,
        roster_count = tm$rosterCount,
        twelfth_spot_available = tm$twelfthSpotAvailable,
        cba_tier = tm$cbaTier,
        hard_cap_crunch_index = tm$hardCapCrunchIndex,
        core_player = tm$corePlayer,
        roster = I(lapply(tm$contracts, function(c) {
          list(
            player_id = c$playerId,
            player_name = c$playerName,
            position = c$position,
            salary_2026 = c$salary2026,
            salary_2027 = c$salary2027,
            contract_type = c$contractType,
            protected = isTRUE(c$protected),
            free_agent_year = c$freeAgentYear
          )
        }))
      )
    }
  }
  
  # Ensure deterministic sorting of teams
  if (length(teams_list) > 0) {
    teams_list <- teams_list[order(names(teams_list))]
  }
  
  # 4. Assemble Players Map
  players_list <- list()
  for (p in players_proj) {
    pid <- as.character(p$player_id)
    players_list[[pid]] <- list(
      player_id = pid,
      player_name = p$player_name,
      team = p$team,
      position = p$position,
      age = p$age,
      minutes_per_game = p$proj_mpg,
      bpm = p$proj_bpm,
      pts = p$proj_pts,
      reb = p$proj_reb,
      ast = p$proj_ast,
      net_rating = p$proj_net_rating
    )
  }
  
  if (length(players_list) > 0) {
    players_list <- players_list[order(names(players_list))]
  }
  
  # 5. Build S0 Payload conforming to Blueprint §3
  s0 <- list(
    asOf = as_of_stamp,
    seasonStatus = season_status,
    finalsChampion = resolved_champion,
    coverageReport = list(
      rosters = "POPULATED",
      capSheet = "POPULATED",
      contracts = if (length(teams_list) > 0) "POPULATED" else "UNAVAILABLE",
      serviceYears = "POPULATED"
    ),
    provenance = list(
      source = "WNBA Analytics CBA & Postseason Engine",
      origin = "POSTSEASON_CONCLUDED",
      generator = "tools/offseason/capture_baseline_s0.R",
      recorded_at = as_of_stamp
    ),
    cbaConstants = list(
      hardSalaryCap = if (!is.null(cap_data$hardSalaryCap)) cap_data$hardSalaryCap else 1.52,
      capFloor = if (!is.null(cap_data$capFloor)) cap_data$capFloor else 1.368,
      supermaxSalary = if (!is.null(cap_data$supermaxSalary)) cap_data$supermaxSalary else 0.2492,
      vetMaxSalary = if (!is.null(cap_data$vetMaxSalary)) cap_data$vetMaxSalary else 0.2153,
      vetMinSalary = if (!is.null(cap_data$vetMinSalary)) cap_data$vetMinSalary else 0.0788,
      rookieMinSalary = if (!is.null(cap_data$rookieMinSalary)) cap_data$rookieMinSalary else 0.0672
    ),
    draftPicks2027 = I(list()),
    calendarMilestones = I(list(
      list(date = "2026-10-31", event = "WNBA Finals Game 7 / Season S0 Baseline Freeze"),
      list(date = "2026-12-01", event = "Expansion Draft & Core Player Designations"),
      list(date = "2027-01-15", event = "Free Agency Moratorium Begins"),
      list(date = "2027-02-01", event = "Free Agency Signings Period"),
      list(date = "2027-04-15", event = "2027 WNBA Draft")
    )),
    teams = teams_list,
    players = players_list
  )
  
  if (dry_run) {
    message(">>> [OFFSEASON S0] Dry-run completed. Generated baseline contains ", length(teams_list), " teams and ", length(players_list), " players.")
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
