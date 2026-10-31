# ==============================================================================
# extract_regex.R
# WNBA Offseason Dynamics Monitor — Deterministic Regex Extractor (Phase 3)
#
# Parses official transaction wire text snapshots using deterministic regex patterns.
# Returns candidate structured delta tuples:
#   (entity_type, entity_id, field, prior_val, new_val, tier, date, source_url)
#
# Usage:
#   Rscript tools/offseason/extract_regex.R [--input=<file>] [--output=<file>]
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

# Canonical team dictionary (Names & Nicknames to Abbrev)
TEAM_NAME_MAP <- list(
  "Atlanta Dream" = "ATL", "Dream" = "ATL",
  "Chicago Sky" = "CHI", "Sky" = "CHI",
  "Connecticut Sun" = "CON", "Sun" = "CON",
  "Dallas Wings" = "DAL", "Wings" = "DAL",
  "Golden State Valkyries" = "GS", "Valkyries" = "GS",
  "Indiana Fever" = "IND", "Fever" = "IND",
  "Las Vegas Aces" = "LV", "Aces" = "LV",
  "Los Angeles Sparks" = "LA", "Sparks" = "LA",
  "Minnesota Lynx" = "MIN", "Lynx" = "MIN",
  "New York Liberty" = "NY", "Liberty" = "NY",
  "Phoenix Mercury" = "PHX", "Mercury" = "PHX",
  "Portland Fire" = "POR", "Fire" = "POR",
  "Seattle Storm" = "SEA", "Storm" = "SEA",
  "Toronto Tempo" = "TOR", "Tempo" = "TOR",
  "Washington Mystics" = "WSH", "Mystics" = "WSH"
)

# Unpack baseline JSON value cleanly (converts empty list / list() from jsonlite into NULL)
clean_baseline_val <- function(val) {
  if (is.null(val)) return(NULL)
  if (is.list(val) && length(val) == 0) return(NULL)
  if (length(val) == 1 && is.character(val) && !nzchar(val)) return(NULL)
  val
}

# Known player lookup helper
find_player_by_name <- function(player_name, baseline_state = NULL) {
  if (is.null(baseline_state)) {
    baseline_path <- file.path("cache", "league_state_baseline.json")
    if (file.exists(baseline_path)) {
      baseline_state <- jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
    }
  }
  
  if (!is.null(baseline_state) && !is.null(baseline_state$players)) {
    for (pid in names(baseline_state$players)) {
      p <- baseline_state$players[[pid]]
      if (identical(tolower(p$displayName), tolower(player_name))) {
        return(list(
          id = pid,
          name = p$displayName,
          team = clean_baseline_val(p$team$value),
          contractStatus = clean_baseline_val(p$contractStatus$value),
          designation = clean_baseline_val(p$designation$value),
          contractThroughSeason = clean_baseline_val(p$contractThroughSeason$value),
          serviceYears = clean_baseline_val(p$serviceYears$value)
        ))
      }
    }
  }
  
  # Fallback manual index for fixtures if baseline not available
  known_marq <- list(
    "Nneka Ogwumike" = list(id = "1068", name = "Nneka Ogwumike", team = "LA", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2027L, serviceYears = 3L),
    "Ezi Magbegor" = list(id = "4420318", name = "Ezi Magbegor", team = "SEA", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L),
    "Satou Sabally" = list(id = "4281929", name = "Satou Sabally", team = "NY", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L),
    "DiJonai Carrington" = list(id = "4066548", name = "DiJonai Carrington", team = "CHI", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L)
  )
  for (nm in names(known_marq)) {
    if (identical(tolower(nm), tolower(player_name))) {
      return(known_marq[[nm]])
    }
  }
  
  NULL
}

# Resolve team abbreviation from text mention
resolve_team_abbr <- function(text) {
  for (nm in names(TEAM_NAME_MAP)) {
    pattern <- paste0("\\b", nm, "\\b")
    if (grepl(pattern, text, ignore.case = TRUE)) {
      return(TEAM_NAME_MAP[[nm]])
    }
  }
  NULL
}

#' Extract deltas from raw wire text snapshot
#'
#' @param raw_text string containing the wire update
#' @param date event date 'YYYY-MM-DD'
#' @param source_url origin URL
#' @param baseline_state optional baseline object for resolving prior values
#' @return list of extracted delta objects
extract_deltas_regex <- function(raw_text, date = NULL, source_url = NULL, baseline_state = NULL) {
  deltas <- list()
  
  # ----------------------------------------------------------------------------
  # Pattern 1: Free Agency / Multi-year contract signings
  # Example: "Seattle Storm sign forward Nneka Ogwumike to a multi-year contract as an unrestricted free agent."
  # ----------------------------------------------------------------------------
  p1 <- "^(.*?) sign(?:s)? (?:forward|guard|center)?\\s*([A-Z][a-z]+ [A-Z][a-z]+) to a (?:multi-year|contract|one-year|two-year)"
  m1 <- regexec(p1, raw_text, ignore.case = TRUE)
  reg1 <- regmatches(raw_text, m1)[[1]]
  if (length(reg1) >= 3) {
    team_chunk <- reg1[2]
    player_name <- trimws(reg1[3])
    
    new_team <- resolve_team_abbr(team_chunk)
    player_info <- find_player_by_name(player_name, baseline_state)
    
    if (!is.null(new_team) && !is.null(player_info)) {
      # 1. Team change delta
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = player_info$id,
        entity_name = player_info$name,
        field = "team",
        prior_val = player_info$team,
        new_val = new_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
      
      # 2. Contract status delta
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = player_info$id,
        entity_name = player_info$name,
        field = "contractStatus",
        prior_val = if (!is.null(player_info$contractStatus)) player_info$contractStatus else "UNDER_CONTRACT",
        new_val = "UNDER_CONTRACT",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  # ----------------------------------------------------------------------------
  # Pattern 2: Core Player Designation
  # Example: "Seattle Storm designate center Ezi Magbegor as Core Player."
  # ----------------------------------------------------------------------------
  p2 <- "^(.*?) designate(?:s)? (?:forward|guard|center)?\\s*([A-Z][a-z]+ [A-Z][a-z]+) as Core Player"
  m2 <- regexec(p2, raw_text, ignore.case = TRUE)
  reg2 <- regmatches(raw_text, m2)[[1]]
  if (length(reg2) >= 3) {
    player_name <- trimws(reg2[3])
    player_info <- find_player_by_name(player_name, baseline_state)
    
    if (!is.null(player_info)) {
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = player_info$id,
        entity_name = player_info$name,
        field = "designation",
        prior_val = if (!is.null(player_info$designation)) player_info$designation else "NONE",
        new_val = "CORED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  # ----------------------------------------------------------------------------
  # Pattern 3: Trades & Sign-and-trades
  # Example: "New York Liberty complete sign-and-trade transaction sending forward Satou Sabally to Dallas Wings in exchange for 2027 draft assets."
  # ----------------------------------------------------------------------------
  p3 <- "sending (?:forward|guard|center)?\\s*([A-Z][a-z]+ [A-Z][a-z]+) to (.*?) in exchange"
  m3 <- regexec(p3, raw_text, ignore.case = TRUE)
  reg3 <- regmatches(raw_text, m3)[[1]]
  if (length(reg3) >= 3) {
    player_name <- trimws(reg3[2])
    dest_chunk <- reg3[3]
    
    new_team <- resolve_team_abbr(dest_chunk)
    player_info <- find_player_by_name(player_name, baseline_state)
    
    if (!is.null(new_team) && !is.null(player_info)) {
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = player_info$id,
        entity_name = player_info$name,
        field = "team",
        prior_val = player_info$team,
        new_val = new_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  # ----------------------------------------------------------------------------
  # Pattern 4: Coaching & GM Hires / Names
  # Example A: "Washington Mystics name Teresa Weatherspoon head coach."
  # Example B: "Washington Mystics hire Curt Miller as general manager."
  # ----------------------------------------------------------------------------
  p4_hc <- "^(.*?) (?:name(?:s)?|hire(?:s)?)\\s*([A-Z][a-z]+ [A-Z][a-z]+) (?:as )?head coach"
  m4_hc <- regexec(p4_hc, raw_text, ignore.case = TRUE)
  reg4_hc <- regmatches(raw_text, m4_hc)[[1]]
  if (length(reg4_hc) >= 3) {
    team_chunk <- reg4_hc[2]
    coach_name <- trimws(reg4_hc[3])
    team_abbr <- resolve_team_abbr(team_chunk)
    if (!is.null(team_abbr)) {
      prior_coach <- NULL
      if (!is.null(baseline_state) && !is.null(baseline_state$teams[[team_abbr]])) {
        prior_coach <- clean_baseline_val(baseline_state$teams[[team_abbr]]$headCoach$value)
      }
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "team",
        entity_id = team_abbr,
        entity_name = team_abbr,
        field = "headCoach",
        prior_val = prior_coach,
        new_val = coach_name,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  p4_gm <- "^(.*?) (?:name(?:s)?|hire(?:s)?)\\s*([A-Z][a-z]+ [A-Z][a-z]+) (?:as )?general manager"
  m4_gm <- regexec(p4_gm, raw_text, ignore.case = TRUE)
  reg4_gm <- regmatches(raw_text, m4_gm)[[1]]
  if (length(reg4_gm) >= 3) {
    team_chunk <- reg4_gm[2]
    gm_name <- trimws(reg4_gm[3])
    team_abbr <- resolve_team_abbr(team_chunk)
    if (!is.null(team_abbr)) {
      prior_gm <- NULL
      if (!is.null(baseline_state) && !is.null(baseline_state$teams[[team_abbr]])) {
        prior_gm <- clean_baseline_val(baseline_state$teams[[team_abbr]]$generalManager$value)
      }
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "team",
        entity_id = team_abbr,
        entity_name = team_abbr,
        field = "generalManager",
        prior_val = prior_gm,
        new_val = gm_name,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  # ----------------------------------------------------------------------------
  # Pattern 5: Contract Option Exercised
  # Example: "Chicago Sky exercise contract option on guard DiJonai Carrington through 2027 season."
  # ----------------------------------------------------------------------------
  p5 <- "exercise(?:s)? contract option on (?:forward|guard|center)?\\s*([A-Z][a-z]+ [A-Z][a-z]+) through ([0-9]{4})"
  m5 <- regexec(p5, raw_text, ignore.case = TRUE)
  reg5 <- regmatches(raw_text, m5)[[1]]
  if (length(reg5) >= 3) {
    player_name <- trimws(reg5[2])
    through_year <- as.integer(reg5[3])
    player_info <- find_player_by_name(player_name, baseline_state)
    
    if (!is.null(player_info)) {
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = player_info$id,
        entity_name = player_info$name,
        field = "contractThroughSeason",
        prior_val = player_info$contractThroughSeason,
        new_val = through_year,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url
      )
    }
    return(deltas)
  }
  
  deltas
}
