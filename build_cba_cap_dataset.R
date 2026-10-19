# ==============================================================================
# build_cba_cap_dataset.R
# WNBA Hard Salary Cap, Rookie Scale & 11-vs-12 Player Roster Crunch Engine
#
# Generates realistic CBA cap sheets for all 15 WNBA franchises (2026 season)
# incorporating the hard salary cap ($1.520M), 90% floor ($1.368M), supermax tags,
# rookie scale wage ladders, and the 11 vs 12 player roster crunch.
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

  # 2026 WNBA CBA Constants (in Millions of USD)
  WNBA_HARD_CAP <- 1.520       # $1,520,000 Hard Cap
  WNBA_CAP_FLOOR <- 1.368      # $1,368,000 Minimum Floor (90%)
  WNBA_SUPERMAX <- 0.2492      # $249,244 Supermax
  WNBA_VET_MAX <- 0.2153       # $215,340 Regular Veteran Max
  WNBA_MIN_VET <- 0.0788       # $78,831 3+ Year Vet Minimum / 12th Spot Threshold
  WNBA_MIN_ROOKIE <- 0.0672    # $67,249 0-2 Year Minimum

  # Core / Supermax star player designations
  CORE_STARS <- c(
    "Breanna Stewart", "A'ja Wilson", "Sabrina Ionescu", "Alyssa Thomas",
    "Napheesa Collier", "Jewell Loyd", "Kelsey Plum", "Arike Ogunbowale",
    "Jackie Young", "DeWanna Bonner", "Chelsea Gray", "Kahleah Copper",
    "Kayla McBride", "Natasha Cloud", "Jonquel Jones", "Brittney Griner",
    "Allisha Gray", "Brionna Jones", "Dearica Hamby", "Kelsey Mitchell"
  )

  # Top rookie scale phenoms
  ROOKIE_SCALE_STARS <- c(
    "Caitlin Clark", "Angel Reese", "Cameron Brink", "Paige Bueckers",
    "Kamilla Cardoso", "Rickea Jackson", "Aaliyah Edwards", "Jacy Sheldon"
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

    pts <- if ("proj_pts" %in% names(team_players)) team_players$proj_pts else 0
    reb <- if ("proj_reb" %in% names(team_players)) team_players$proj_reb else 0
    ast <- if ("proj_ast" %in% names(team_players)) team_players$proj_ast else 0
    team_players$proj_pra <- ifelse(is.na(pts), 0, pts) + ifelse(is.na(reb), 0, reb) + ifelse(is.na(ast), 0, ast)
    team_players <- team_players[order(team_players$proj_pra, decreasing = TRUE), ]
    n_players <- nrow(team_players)

    # Generate realistic contract breakdown
    contracts <- list()
    core_player_name <- NA_character_

    for (i in seq_len(n_players)) {
      p <- team_players[i, ]
      p_name <- p$player_name
      p_id <- as.character(p$player_id)
      p_pos <- p$position

      # Determine salary based on status
      sal_2026 <- WNBA_MIN_VET
      c_type <- "Guaranteed"
      notes <- "Standard Contract"

      if (p_name %in% CORE_STARS) {
        if (is.na(core_player_name)) {
          core_player_name <- p_name
          c_type <- "Core Player"
          sal_2026 <- round(runif(1, 0.240, WNBA_SUPERMAX), 4)
          notes <- "Designated Core Franchise Player"
        } else {
          c_type <- "Veteran Max"
          sal_2026 <- round(runif(1, 0.205, WNBA_VET_MAX), 4)
          notes <- "Protected Veteran Maximum"
        }
      } else if (p_name %in% ROOKIE_SCALE_STARS) {
        c_type <- "Rookie Scale"
        sal_2026 <- round(runif(1, 0.078, 0.082), 4)
        notes <- "First-Round Rookie Scale Ladder"
      } else if (i <= 3) {
        c_type <- "Veteran Starter"
        sal_2026 <- round(runif(1, 0.125, 0.170), 4)
        notes <- "Multi-Year Guaranteed Starter"
      } else if (i <= 6) {
        c_type <- "Rotation Core"
        sal_2026 <- round(runif(1, 0.085, 0.115), 4)
        notes <- "Rotation Player Agreement"
      } else if (i >= 10) {
        c_type <- if (runif(1) > 0.5) "Team Option" else "Minimum"
        sal_2026 <- round(runif(1, WNBA_MIN_ROOKIE, WNBA_MIN_VET), 4)
        notes <- "Depth / Minimum Salary Exception"
      } else {
        c_type <- "Guaranteed"
        sal_2026 <- round(runif(1, WNBA_MIN_VET, 0.092), 4)
        notes <- "Standard Protected Agreement"
      }

      contracts[[length(contracts) + 1]] <- list(
        playerId = p_id,
        playerName = p_name,
        position = p_pos,
        salary2026 = sal_2026,
        salary2027 = 0,
        salary2028 = 0,
        contractType = c_type,
        notes = notes
      )
    }

    # Strict Hard Cap Normalization:
    # Target payroll must strictly fall between Floor ($1.368M) and Hard Cap ($1.520M - $0.003M)
    raw_sum <- sum(sapply(contracts, function(c) c$salary2026))
    target_payroll <- round(runif(1, WNBA_CAP_FLOOR + 0.020, WNBA_HARD_CAP - 0.003), 4)
    # Give some rebuilding/expansion teams lower payroll for cap space variety
    if (abbr %in% c("GS", "POR", "TOR", "WAS", "CHI") && runif(1) > 0.4) {
      target_payroll <- round(runif(1, WNBA_CAP_FLOOR + 0.005, 1.430), 4)
    }

    scale_factor <- target_payroll / raw_sum
    total_payroll_2026 <- 0
    total_payroll_2027 <- 0
    total_payroll_2028 <- 0

    for (k in seq_along(contracts)) {
      c_sal <- round(contracts[[k]]$salary2026 * scale_factor, 4)
      # enforce minimum bounds
      c_sal <- max(WNBA_MIN_ROOKIE, min(WNBA_SUPERMAX, c_sal))
      contracts[[k]]$salary2026 <- c_sal

      c_type <- contracts[[k]]$contractType
      if (c_type %in% c("Core Player", "Veteran Max")) {
        contracts[[k]]$salary2027 <- round(c_sal * 1.03, 4)
        contracts[[k]]$salary2028 <- round(c_sal * 1.06, 4)
      } else if (c_type == "Rookie Scale") {
        contracts[[k]]$salary2027 <- round(c_sal * 1.08, 4)
        contracts[[k]]$salary2028 <- round(c_sal * 1.15, 4)
      } else if (c_type == "Veteran Starter") {
        contracts[[k]]$salary2027 <- round(c_sal * 1.03, 4)
        contracts[[k]]$salary2028 <- if (runif(1) > 0.5) round(c_sal * 1.03, 4) else 0
      } else if (c_type == "Team Option") {
        contracts[[k]]$salary2027 <- round(c_sal * 1.04, 4)
        contracts[[k]]$salary2028 <- 0
      } else {
        contracts[[k]]$salary2027 <- if (runif(1) > 0.6) round(c_sal, 4) else 0
        contracts[[k]]$salary2028 <- 0
      }

      total_payroll_2026 <- total_payroll_2026 + contracts[[k]]$salary2026
      total_payroll_2027 <- total_payroll_2027 + contracts[[k]]$salary2027
      total_payroll_2028 <- total_payroll_2028 + contracts[[k]]$salary2028
    }

    # Ensure hard cap ceiling is strictly respected
    if (total_payroll_2026 > WNBA_HARD_CAP - 0.002) {
      overage <- total_payroll_2026 - (WNBA_HARD_CAP - 0.005)
      contracts[[length(contracts)]]$salary2026 <- round(contracts[[length(contracts)]]$salary2026 - overage, 4)
      total_payroll_2026 <- sum(sapply(contracts, function(c) c$salary2026))
    }

    cap_space_2026 <- round(max(0.001, WNBA_HARD_CAP - total_payroll_2026), 4)
    twelfth_spot_available <- cap_space_2026 >= WNBA_MIN_VET
    roster_count <- if (twelfth_spot_available && n_players >= 12) 12 else min(11, n_players)

    # Determine WNBA CBA Tier
    cba_tier <- if (cap_space_2026 < WNBA_MIN_VET && roster_count == 11) {
      "Hard Cap Squeeze (11 Roster)"
    } else if (cap_space_2026 < 0.060) {
      "Cap Compliant (12 Roster)"
    } else if (cap_space_2026 < 0.120) {
      "Flexible Cap Room"
    } else {
      "Maximum Cap Space"
    }

    projected_cap_space_2027 <- round(max(0, (WNBA_HARD_CAP * 1.05) - total_payroll_2027), 4)
    projected_cap_space_2028 <- round(max(0, (WNBA_HARD_CAP * 1.10) - total_payroll_2028), 4)

    franchise_profiles[[length(franchise_profiles) + 1]] <- list(
      teamAbbr = abbr,
      teamName = team_name,
      conference = conf,
      totalPayroll2026 = round(total_payroll_2026, 4),
      totalPayroll2027 = round(total_payroll_2027, 4),
      totalPayroll2028 = round(total_payroll_2028, 4),
      hardSalaryCap = WNBA_HARD_CAP,
      capFloor = WNBA_CAP_FLOOR,
      capSpace2026 = cap_space_2026,
      rosterCount = roster_count,
      twelfthSpotAvailable = twelfth_spot_available,
      cbaTier = cba_tier,
      corePlayer = if (is.na(core_player_name)) "Unassigned" else core_player_name,
      projectedCapSpace2027 = projected_cap_space_2027,
      projectedCapSpace2028 = projected_cap_space_2028,
      hardCapCrunchIndex = round((total_payroll_2026 / WNBA_HARD_CAP) * 100, 1),
      contracts = contracts
    )
  }

  # Build league summary
  avg_payroll <- round(mean(sapply(franchise_profiles, function(f) f$totalPayroll2026)), 4)
  squeeze_count <- sum(sapply(franchise_profiles, function(f) f$cbaTier == "Hard Cap Squeeze (11 Roster)"))
  full_roster_count <- sum(sapply(franchise_profiles, function(f) f$rosterCount == 12))
  max_space_count <- sum(sapply(franchise_profiles, function(f) f$cbaTier == "Maximum Cap Space"))

  league_overview <- list(
    season = "2026",
    hardSalaryCap = WNBA_HARD_CAP,
    capFloor = WNBA_CAP_FLOOR,
    supermaxSalary = WNBA_SUPERMAX,
    vetMaxSalary = WNBA_VET_MAX,
    vetMinSalary = WNBA_MIN_VET,
    rookieMinSalary = WNBA_MIN_ROOKIE,
    averagePayroll = avg_payroll,
    hardCapSqueezeTeamCount = squeeze_count,
    twelvePlayerTeamCount = full_roster_count,
    maxCapSpaceTeamCount = max_space_count,
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
           teams = length(franchise_profiles), squeeze_count = squeeze_count)

  invisible(TRUE)
}

if (!interactive()) {
  build_cba_cap_dataset()
}
