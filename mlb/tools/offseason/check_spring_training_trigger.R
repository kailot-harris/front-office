# ==============================================================================
# tools/offseason/check_spring_training_trigger.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Dual-Trigger Spring Training Detector
# Path: tools/offseason/check_spring_training_trigger.R
#
# Detects whether the transition threshold to Spring Training 2027 has been met.
#
# Dual-Trigger Rules (Blueprint §§ 1, 7, 10; Issue #49):
#   Condition 1: Franchise-code guarded spring schedule feed.
#     - Ingests spring/exhibition games from MLB Stats API / baseballr feed.
#     - STRICTLY GUARDS both teams to confirmed MLB franchise codes (names(MLB_TEAMS)
#       or active MLB clubs in MLB_TEAMS_30 / MLB_TEAMS).
#     - Prevents false triggers on college exhibition games (e.g. Northeastern Huskies,
#       Minnesota Golden Gophers) or WBC / international exhibition teams.
#   Condition 2: Hard calendar cutoff (~February 22, 2027).
#     - STRICTLY GATED on leagueOperatingStatus == 'NORMAL'.
#     - If the league is locked out (leagueOperatingStatus == 'TRANSACTION_FREEZE'),
#       the calendar ceiling is ignored and handoff does NOT fire.
#
# Outputs JSON trigger evaluation result to stdout or optional --output path.
# Conforms to blueprint §§ 1, 7, 10 and Zero-Betting Policy.
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
      stop(sprintf("check_spring_training_trigger.R: cannot locate repo root (no config.R at or above '%s')", start))
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

# Canonical MLB 30 franchise definitions
CANONICAL_MLB_ABBREVS <- c(
  "ARI", "ATH", "ATL", "BAL", "BOS", "CHC", "CHW", "CIN", "CLE", "COL",
  "DET", "HOU", "KC",  "LAA", "LAD", "MIA", "MIL", "MIN", "NYM", "NYY",
  "PHI", "PIT", "SD",  "SEA", "SF",  "STL", "TB",  "TEX", "TOR", "WSH"
)

CANONICAL_MLB_TEAM_IDS <- c(
  108, 109, 110, 111, 112, 113, 114, 115, 116, 117,
  118, 119, 120, 121, 133, 134, 135, 136, 137, 138,
  139, 140, 141, 142, 143, 144, 145, 146, 147, 158
)

# Standard alias map for non-standard abbreviations in feeds
CANONICAL_ABBREV_ALIASES <- c(
  "AZ" = "ARI", "OAK" = "ATH", "CWS" = "CHW", "KCA" = "KC",
  "LAN" = "LAD", "NYN" = "NYM", "SDN" = "SD", "SFN" = "SF",
  "SLN" = "STL", "TBA" = "TB", "WAS" = "WSH"
)

#' Normalize team code or abbreviation
normalize_team_code <- function(code) {
  if (is.null(code) || is.na(code)) return(NA_character_)
  code_clean <- toupper(trimws(as.character(code)))
  if (code_clean %in% names(CANONICAL_ABBREV_ALIASES)) {
    code_clean <- CANONICAL_ABBREV_ALIASES[[code_clean]]
  }
  code_clean
}

#' Check if team identifier represents a valid MLB franchise
is_mlb_franchise <- function(team_id = NULL, team_code = NULL) {
  if (!is.null(team_id) && !is.na(team_id)) {
    id_num <- suppressWarnings(as.integer(team_id))
    if (!is.na(id_num) && id_num %in% CANONICAL_MLB_TEAM_IDS) {
      return(TRUE)
    }
  }
  if (!is.null(team_code) && !is.na(team_code)) {
    norm <- normalize_team_code(team_code)
    if (!is.na(norm) && norm %in% CANONICAL_MLB_ABBREVS) {
      return(TRUE)
    }
  }
  FALSE
}

#' Get current league operating status from baseline or staged state
get_league_operating_status <- function(state_path = NULL) {
  path_to_check <- if (!is.null(state_path)) {
    state_path
  } else if (file.exists("cache/league_state_staged.json")) {
    "cache/league_state_staged.json"
  } else if (file.exists("cache/league_state_baseline.json")) {
    "cache/league_state_baseline.json"
  } else if (file.exists("web/public/data/offseason_monitor.json")) {
    "web/public/data/offseason_monitor.json"
  } else {
    NULL
  }
  
  if (is.null(path_to_check) || !file.exists(path_to_check)) {
    return("NORMAL")
  }
  
  obj <- tryCatch(jsonlite::fromJSON(path_to_check, simplifyDataFrame = FALSE), error = function(e) NULL)
  if (is.null(obj)) return("NORMAL")
  
  # Check league$leagueOperatingStatus$value (LeagueStateBaseline format)
  if (!is.null(obj$league$leagueOperatingStatus$value)) {
    return(as.character(obj$league$leagueOperatingStatus$value))
  }
  # Check top-level leagueOperatingStatus (offseason_monitor.json format)
  if (!is.null(obj$leagueOperatingStatus)) {
    return(as.character(obj$leagueOperatingStatus))
  }
  
  "NORMAL"
}

#' Evaluate Spring Training Trigger
#'
#' @param as_of_date Character date 'YYYY-MM-DD' or Date object. Defaults to Sys.Date().
#' @param operating_status Character 'NORMAL' or 'TRANSACTION_FREEZE'. If NULL, read from state.
#' @param schedule_data Optional data.frame or list of games to evaluate.
#' @param calendar_cutoff Character 'YYYY-MM-DD'. Default is '2027-02-22'.
#' @param season Integer season year. Default is 2027.
#' @return List conforming to trigger evaluation specification.
evaluate_spring_training_trigger <- function(as_of_date = Sys.Date(),
                                            operating_status = NULL,
                                            schedule_data = NULL,
                                            calendar_cutoff = "2027-02-22",
                                            season = 2027) {
  as_of <- as.Date(as_of_date)
  cutoff <- as.Date(calendar_cutoff)
  
  if (is.null(operating_status)) {
    operating_status <- get_league_operating_status()
  }
  
  # Condition 1: Franchise-code guarded spring schedule feed
  # Ingest spring training schedule if not provided
  cond1_triggered <- FALSE
  confirmed_spring_games <- list()
  rejected_exhibition_games <- list()
  
  games_to_inspect <- schedule_data
  if (is.null(games_to_inspect)) {
    # Attempt to fetch schedule feed for season
    games_to_inspect <- tryCatch({
      if (requireNamespace("baseballr", quietly = TRUE)) {
        df <- baseballr::mlb_schedule(season = season)
        if (!is.null(df) && nrow(df) > 0) df else NULL
      } else {
        NULL
      }
    }, error = function(e) NULL)
  }
  
  if (!is.null(games_to_inspect) && (is.data.frame(games_to_inspect) || is.list(games_to_inspect))) {
    # Normalize to row list if data frame
    rows <- if (is.data.frame(games_to_inspect)) {
      lapply(seq_len(nrow(games_to_inspect)), function(i) as.list(games_to_inspect[i, , drop = FALSE]))
    } else if (is.list(games_to_inspect) && length(games_to_inspect) > 0 && is.list(games_to_inspect[[1]])) {
      games_to_inspect
    } else {
      list()
    }
    
    for (gm in rows) {
      # Extract fields
      s_desc <- as.character(gm$series_description %||% gm[["series_description"]] %||% "")
      g_type <- as.character(gm$game_type %||% gm[["game_type"]] %||% "")
      
      is_spring_context <- grepl("Spring", s_desc, ignore.case = TRUE) ||
                           grepl("Exhibition", s_desc, ignore.case = TRUE) ||
                           g_type %in% c("S", "E")
      
      if (!is_spring_context) next
      
      away_id <- gm$teams_away_team_id %||% gm$away_team_id %||% gm[["teams_away_team_id"]] %||% gm[["away_team_id"]]
      home_id <- gm$teams_home_team_id %||% gm$home_team_id %||% gm[["teams_home_team_id"]] %||% gm[["home_team_id"]]
      away_code <- gm$away_team_code %||% gm$teams_away_team_abbreviation %||% gm[["away_code"]]
      home_code <- gm$home_team_code %||% gm$teams_home_team_abbreviation %||% gm[["home_code"]]
      away_name <- as.character(gm$teams_away_team_name %||% gm$away_team_name %||% away_code %||% away_id %||% "Unknown")
      home_name <- as.character(gm$teams_home_team_name %||% gm$home_team_name %||% home_code %||% home_id %||% "Unknown")
      g_date <- as.character(gm$game_date %||% gm$official_date %||% gm$date %||% "")
      
      away_valid <- is_mlb_franchise(away_id, away_code)
      home_valid <- is_mlb_franchise(home_id, home_code)
      
      game_summary <- list(
        date = g_date,
        awayTeam = away_name,
        awayId = away_id,
        awayIsMlb = away_valid,
        homeTeam = home_name,
        homeId = home_id,
        homeIsMlb = home_valid,
        gameType = g_type,
        seriesDescription = s_desc
      )
      
      if (away_valid && home_valid) {
        confirmed_spring_games[[length(confirmed_spring_games) + 1L]] <- game_summary
      } else {
        rejected_exhibition_games[[length(rejected_exhibition_games) + 1L]] <- game_summary
      }
    }
  }
  
  if (length(confirmed_spring_games) > 0) {
    cond1_triggered <- TRUE
  }
  
  # Condition 2: Hard calendar cutoff gated STRICTLY on leagueOperatingStatus == 'NORMAL'
  calendar_cutoff_reached <- (as_of >= cutoff)
  is_normal_status <- identical(operating_status, "NORMAL")
  cond2_triggered <- (calendar_cutoff_reached && is_normal_status)
  
  # Dual-trigger conclusion: fires if EITHER condition 1 OR condition 2 is satisfied
  handoff_triggered <- cond1_triggered || cond2_triggered
  
  trigger_reason <- if (handoff_triggered) {
    if (cond1_triggered && cond2_triggered) {
      sprintf("Dual trigger satisfied: Confirmed MLB franchise spring games detected (%d game(s)) AND calendar ceiling reached (%s) under NORMAL status",
              length(confirmed_spring_games), format(cutoff, "%Y-%m-%d"))
    } else if (cond1_triggered) {
      sprintf("Condition 1 satisfied: Confirmed MLB franchise spring games detected (%d game(s)); non-MLB exhibitions rejected (%d game(s))",
              length(confirmed_spring_games), length(rejected_exhibition_games))
    } else {
      sprintf("Condition 2 satisfied: Calendar cutoff reached (%s >= %s) under NORMAL operating status",
              format(as_of, "%Y-%m-%d"), format(cutoff, "%Y-%m-%d"))
    }
  } else {
    if (calendar_cutoff_reached && !is_normal_status) {
      sprintf("Handoff BLOCKED: Calendar cutoff reached (%s >= %s) but leagueOperatingStatus is '%s' (Lockout calendar freeze in effect)",
              format(as_of, "%Y-%m-%d"), format(cutoff, "%Y-%m-%d"), operating_status)
    } else {
      sprintf("Handoff dormant: No confirmed MLB spring games (%d rejected exhibitions) and calendar cutoff not reached (%s < %s)",
              length(rejected_exhibition_games), format(as_of, "%Y-%m-%d"), format(cutoff, "%Y-%m-%d"))
    }
  }
  
  list(
    handoffTriggered = handoff_triggered,
    asOfDate = format(as_of, "%Y-%m-%d"),
    operatingStatus = operating_status,
    calendarCutoffDate = format(cutoff, "%Y-%m-%d"),
    condition1 = list(
      triggered = cond1_triggered,
      confirmedMlbSpringGamesCount = length(confirmed_spring_games),
      rejectedExhibitionGamesCount = length(rejected_exhibition_games),
      confirmedGames = confirmed_spring_games,
      rejectedGames = rejected_exhibition_games
    ),
    condition2 = list(
      triggered = cond2_triggered,
      calendarCutoffReached = calendar_cutoff_reached,
      isNormalOperatingStatus = is_normal_status,
      lockoutBlockActive = (calendar_cutoff_reached && !is_normal_status)
    ),
    verdict = if (handoff_triggered) "TRIGGER_SPRING_REACTIVATION" else "MAINTAIN_OFFSEASON_MONITOR",
    reason = trigger_reason
  )
}

# Helper operator
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
}

show_help <- function() {
  cat("=======================================================================\n")
  cat("tools/offseason/check_spring_training_trigger.R\n")
  cat("MLB 2026-2027 Off-Season Dynamics Monitor: Dual-Trigger Spring Detector\n")
  cat("=======================================================================\n\n")
  cat("Usage:\n")
  cat("  Rscript tools/offseason/check_spring_training_trigger.R [options]\n\n")
  cat("Options:\n")
  cat("  --as-of=YYYY-MM-DD        Simulate as-of date (default: today)\n")
  cat("  --operating-status=STATUS Force operating status: NORMAL | TRANSACTION_FREEZE\n")
  cat("  --cutoff=YYYY-MM-DD       Override calendar cutoff date (default: 2027-02-22)\n")
  cat("  --output=PATH             Optional path to save JSON result\n")
  cat("  --help                    Display this help message and exit\n\n")
  cat("Dual Trigger Logic:\n")
  cat("  Condition 1: Detects upcoming spring training games where BOTH teams are\n")
  cat("               confirmed MLB franchises (names(MLB_TEAMS)), rejecting college\n")
  cat("               exhibitions and non-MLB squads.\n")
  cat("  Condition 2: Calendar cutoff (2027-02-22), STRICTLY GATED on\n")
  cat("               leagueOperatingStatus == 'NORMAL'. Lockout ignores calendar.\n\n")
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  
  if ("--help" %in% args || "-h" %in% args) {
    show_help()
    quit(status = 0)
  }
  
  as_of_arg <- grep("^--as-of=", args, value = TRUE)
  as_of_val <- if (length(as_of_arg)) sub("^--as-of=", "", as_of_arg[1]) else Sys.Date()
  
  status_arg <- grep("^--operating-status=", args, value = TRUE)
  status_val <- if (length(status_arg)) sub("^--operating-status=", "", status_arg[1]) else NULL
  
  cutoff_arg <- grep("^--cutoff=", args, value = TRUE)
  cutoff_val <- if (length(cutoff_arg)) sub("^--cutoff=", "", cutoff_arg[1]) else "2027-02-22"
  
  output_arg <- grep("^--output=", args, value = TRUE)
  output_val <- if (length(output_arg)) sub("^--output=", "", output_arg[1]) else NULL
  
  result <- evaluate_spring_training_trigger(
    as_of_date = as_of_val,
    operating_status = status_val,
    calendar_cutoff = cutoff_val
  )
  
  json_res <- jsonlite::toJSON(result, pretty = TRUE, auto_unbox = TRUE)
  
  if (!is.null(output_val)) {
    dir.create(dirname(output_val), recursive = TRUE, showWarnings = FALSE)
    writeLines(json_res, output_val)
    cat(sprintf("Result saved to: %s\n", output_val))
  }
  
  cat(json_res, "\n")
  
  # Exit code 0 on normal completion
  quit(status = 0)
}
