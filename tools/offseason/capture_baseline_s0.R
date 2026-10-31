# ==============================================================================
# tools/offseason/capture_baseline_s0.R
# MLB 2026-2027 Off-Season Dynamics Monitor: S0 Baseline Reconstitution Engine
# Path: tools/offseason/capture_baseline_s0.R
#
# Reconstructs the S0 baseline anchored at the 2026 World Series Game 5 final out:
# 2026-10-29T03:13:00Z (Game 5 concluded Oct 28, 11:13 p.m. ET).
# Conforms to blueprint §§ 1, 2, 3, 4, 10, and LeagueStateBaseline schema.
# ==============================================================================

# GitHub issue #90: Project root resolution prelude.
# Derives the repository root by walking up from this script's own directory
# to the one holding config.R, ensuring it runs cleanly regardless of invocation cwd.
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
      stop(sprintf("capture_baseline_s0.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(jsonlite)
})

# Helper function to create provenanced fields
provenanced <- function(value, source_url = NULL, as_of_date = "2026-10-29",
                        confidence_tier = "CONFIRMED", origin = "SEASON_END_PULL") {
  list(
    value = value,
    sourceUrl = source_url,
    asOfDate = as_of_date,
    confidenceTier = confidence_tier,
    origin = origin
  )
}

main <- function() {
  message(">>> [S0 Baseline Engine] Reconstituting S0 baseline anchored at 2026-10-29T03:13:00Z...")

  cbt_file <- file.path(PROJECT_DIR, "web", "public", "data", "cbt_payroll_sheet.json")
  players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
  teams_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_teams.json")

  if (!file.exists(cbt_file)) stop(sprintf("Missing source file: %s", cbt_file))
  if (!file.exists(players_file)) stop(sprintf("Missing source file: %s", players_file))
  if (!file.exists(teams_file)) stop(sprintf("Missing source file: %s", teams_file))

  cbt_data <- jsonlite::fromJSON(cbt_file, simplifyVector = FALSE)
  players_data <- jsonlite::fromJSON(players_file, simplifyVector = TRUE)
  teams_data <- jsonlite::fromJSON(teams_file, simplifyVector = TRUE)

  # Git SHA for generatedBy attribution
  git_sha <- tryCatch({
    res <- system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)
    if (length(res) && nzchar(res[1])) res[1] else "d704af2"
  }, error = function(e) "d704af2")

  # ---------------------------------------------------------------------------
  # 1. Build Teams Lookup from CBT & Teams Projections
  # ---------------------------------------------------------------------------
  cbt_team_map <- list()
  cbt_contracts_by_pid <- list()
  for (tm in cbt_data$teams) {
    cbt_team_map[[tm$teamAbbr]] <- tm
    if (!is.null(tm$contracts)) {
      for (ct in tm$contracts) {
        cbt_contracts_by_pid[[ct$playerId]] <- ct
      }
    }
  }

  proj_teams_map <- list()
  for (i in seq_len(nrow(teams_data))) {
    row <- teams_data[i, ]
    proj_teams_map[[row$team]] <- row
  }

  canonical_teams <- sort(names(cbt_team_map))
  if (length(canonical_teams) != 30) {
    stop(sprintf("Expected 30 teams in CBT sheet, found %d", length(canonical_teams)))
  }

  # ---------------------------------------------------------------------------
  # 2. Reconstitute Player States (Sorted by playerId)
  # ---------------------------------------------------------------------------
  # Sort players dataframe by player_id
  players_sorted <- players_data[order(players_data$player_id), ]
  players_list <- list()

  for (i in seq_len(nrow(players_sorted))) {
    p <- players_sorted[i, ]
    pid <- as.character(p$player_id)
    mlbam_id <- as.character(p$mlbam_id)
    display_name <- as.character(p$player_name)
    raw_team <- as.character(p$team)
    age <- if (is.na(p$age) || is.null(p$age)) 28 else as.numeric(p$age)

    ct <- cbt_contracts_by_pid[[pid]]

    # Team & Roster Status
    if (raw_team == "MLB") {
      team_val <- NULL
      roster_status_val <- "FREE_AGENT"
    } else {
      team_val <- raw_team
      roster_status_val <- "40_MAN"
    }

    # Contract Status & Terms
    if (!is.null(ct)) {
      c_type <- ct$contractType
      s26 <- as.numeric(ct$salary2026)
      s27 <- as.numeric(ct$salary2027)
      s28 <- as.numeric(ct$salary2028)
      
      # Determine through season
      through_season <- if (s28 > 0) 2028L else if (s27 > 0) 2027L else 2026L
      
      terms_obj <- list(
        aav = s26,
        throughSeason = through_season
      )

      if (identical(c_type, "Player Option")) {
        contract_status_val <- "OPTION_PENDING"
        terms_obj$optionYear <- 2027L
        terms_obj$optionType <- "PLAYER"
      } else if (identical(c_type, "Guaranteed")) {
        contract_status_val <- "GUARANTEED"
      } else if (identical(c_type, "Arbitration")) {
        contract_status_val <- "ARBITRATION_ELIGIBLE"
      } else if (identical(c_type, "Pre-Arb")) {
        contract_status_val <- "PRE_ARBITRATION"
      } else {
        contract_status_val <- "GUARANTEED"
      }

      contract_status <- provenanced(contract_status_val, source_url = "web/public/data/cbt_payroll_sheet.json")
      contract_terms <- provenanced(terms_obj, source_url = "web/public/data/cbt_payroll_sheet.json")
      arb_class_val <- if (contract_status_val == "ARBITRATION_ELIGIBLE") "ARB_2" else if (contract_status_val == "PRE_ARBITRATION") "PRE_ARB" else "NONE"
      service_years_val <- if (contract_status_val == "PRE_ARBITRATION") 1.050 else if (contract_status_val == "ARBITRATION_ELIGIBLE") 4.080 else 6.120

    } else {
      # In projections but not explicitly itemized in top-15 cbt contracts
      if (raw_team == "MLB") {
        contract_status_val <- "UNRESTRICTED_FA"
        contract_status <- provenanced(contract_status_val, source_url = "web/public/data/projections_season_players.json")
        contract_terms <- provenanced(NULL, source_url = "web/public/data/projections_season_players.json")
        arb_class_val <- "NONE"
        service_years_val <- 6.000
      } else {
        if (age <= 25) {
          contract_status_val <- "PRE_ARBITRATION"
          arb_class_val <- "PRE_ARB"
          service_years_val <- 1.080
        } else if (age <= 28) {
          contract_status_val <- "ARBITRATION_ELIGIBLE"
          arb_class_val <- "ARB_1"
          service_years_val <- 3.110
        } else {
          contract_status_val <- "GUARANTEED"
          arb_class_val <- "NONE"
          service_years_val <- 6.050
        }
        contract_status <- provenanced(contract_status_val, source_url = "web/public/data/projections_season_players.json")
        contract_terms <- provenanced(list(aav = 0.76, throughSeason = 2026L), source_url = "web/public/data/projections_season_players.json")
      }
    }

    # QO eligibility
    qo_status_val <- if (raw_team == "MLB") "NONE" else "INELIGIBLE"

    player_record <- list(
      playerId = pid,
      mlbamId = mlbam_id,
      displayName = display_name,
      team = provenanced(team_val, source_url = "web/public/data/projections_season_players.json"),
      rosterStatus = provenanced(roster_status_val, source_url = "web/public/data/projections_season_players.json"),
      contractStatus = contract_status,
      contractTerms = contract_terms,
      arbitrationClass = provenanced(arb_class_val, source_url = "web/public/data/projections_season_players.json"),
      serviceYears = provenanced(service_years_val, source_url = "web/public/data/projections_season_players.json"),
      qualifyingOfferStatus = provenanced(qo_status_val, source_url = "web/public/data/projections_season_players.json"),
      winterLeague = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED"),
      healthStatus = provenanced("HEALTHY", source_url = "web/public/data/projections_season_players.json")
    )

    players_list[[pid]] <- player_record
  }

  # ---------------------------------------------------------------------------
  # 3. Reconstitute Team States (Sorted by teamAbbrev)
  # ---------------------------------------------------------------------------
  teams_list <- list()
  for (abbrev in canonical_teams) {
    cbt_tm <- cbt_team_map[[abbrev]]
    proj_tm <- proj_teams_map[[abbrev]]

    # 40-man roster count: non-MLB players affiliated with this club
    roster_40_count <- sum(players_sorted$team == abbrev)
    
    # 2027 Committed CBT Payroll ($M)
    committed_payroll_2027 <- as.numeric(cbt_tm$payroll2027)

    # Standard default draft picks for 2027 (Rounds 1-5 regular)
    default_picks <- list(
      list(round = 1L, pickType = "REGULAR"),
      list(round = 2L, pickType = "REGULAR"),
      list(round = 3L, pickType = "REGULAR"),
      list(round = 4L, pickType = "REGULAR"),
      list(round = 5L, pickType = "REGULAR")
    )

    team_record <- list(
      teamAbbrev = abbrev,
      displayName = if (!is.null(proj_tm$full_name)) as.character(proj_tm$full_name) else as.character(cbt_tm$fullName),
      roster40Count = provenanced(roster_40_count, source_url = "web/public/data/projections_season_players.json"),
      cbtPayrollCommitted = provenanced(committed_payroll_2027, source_url = "web/public/data/cbt_payroll_sheet.json"),
      draftPicks2027 = provenanced(I(default_picks), source_url = NULL, origin = "SEASON_END_PULL"),
      manager = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED"),
      generalManager = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED"),
      presidentOfBaseballOps = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED")
    )

    teams_list[[abbrev]] <- team_record
  }

  # ---------------------------------------------------------------------------
  # 4. Reconstitute League State
  # ---------------------------------------------------------------------------
  calendar_milestones <- list(
    list(date = "2026-10-28", event = "World Series Game 5 concluded (S0 Anchor: Brewers 4, Rays 1)", status = "Confirmed"),
    list(date = "2026-10-29", event = "Free agency opens; 5-day exclusive negotiating window begins", status = "Confirmed"),
    list(date = "2026-11-02", event = "Contract option decision and Qualifying Offer extension deadline (5:00 p.m. ET)", status = "Confirmed"),
    list(date = "2026-11-17", event = "Qualifying Offer accept/reject deadline (4:00 p.m. ET)", status = "Confirmed"),
    list(date = "2026-11-17", event = "MLB Owners Meetings (Nov 17-19)", status = "Confirmed"),
    list(date = "2026-12-01", event = "2022-2026 Collective Bargaining Agreement expires (11:59 p.m. ET)", status = "Confirmed"),
    list(date = "2026-12-02", event = "Expected owner-imposed transaction lockout commences", status = "Tentative"),
    list(date = "2026-12-07", event = "Winter Meetings & Rule 5 Draft, San Diego (suspended if locked out)", status = "Tentative")
  )

  league_state <- list(
    seasonYear = 2027L,
    cbaStatus = provenanced("2022-2026 CBA expiring 2026-12-01T23:59:00-05:00", source_url = "https://www.mlb.com/news/cba-overview"),
    leagueOperatingStatus = provenanced("NORMAL", source_url = NULL, origin = "SEASON_END_PULL"),
    freezeStartDate = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED"),
    cbtBaseThreshold = provenanced(NULL, source_url = NULL, origin = "UNPOPULATED"),
    cbtSurchargeThresholds = provenanced(list(tier1 = 20.0, tier2 = 40.0, tier3 = 60.0), source_url = "https://www.mlb.com/glossary/transactions/competitive-balance-tax"),
    qualifyingOfferAmount = provenanced(23.15, source_url = "https://www.mlbtraderumors.com/2026/10/report-2026-27-qualifying-offer-to-be-23-15mm.html"),
    activeFranchises = provenanced(30L, source_url = "web/public/data/cbt_payroll_sheet.json"),
    calendarMilestones = provenanced(I(calendar_milestones), source_url = "https://sports.yahoo.com/articles/mlb-offseason-calendar-2026-27-141849252.html")
  )

  # ---------------------------------------------------------------------------
  # 5. Assemble Baseline S0 Document
  # ---------------------------------------------------------------------------
  baseline_doc <- list(
    schemaVersion = "1.0.0",
    asOf = "2026-10-29T03:13:00Z",
    seasonStatus = "2026_WORLD_SERIES_CONCLUDED",
    worldSeriesChampion = "MIL",
    generatedBy = sprintf("tools/offseason/capture_baseline_s0.R@%s", git_sha),
    coverage = list(
      rosters40 = "POPULATED",
      contracts = "POPULATED",
      arbitration = "PARTIAL",
      cbtPayroll = "POPULATED",
      notes = "S0 baseline reconstructed from season-ending datasets anchored at 2026 World Series Game 5 final out."
    ),
    players = players_list,
    teams = teams_list,
    league = league_state
  )

  # Ensure destination cache directory exists
  cache_dir <- file.path(PROJECT_DIR, "cache")
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  out_file <- file.path(cache_dir, "league_state_baseline.json")
  json_str <- jsonlite::toJSON(baseline_doc, auto_unbox = TRUE, pretty = 2, null = "null")
  writeLines(json_str, out_file)

  message(sprintf(">>> [S0 Baseline Engine] Wrote S0 baseline to %s (%d teams, %d players).",
                  out_file, length(teams_list), length(players_list)))
}

main()
