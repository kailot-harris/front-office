# ==============================================================================
# tools/offseason/extract_regex.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Layer A Deterministic Regex Extractor
# Path: tools/offseason/extract_regex.R
#
# Extracts deterministic state deltas from official wire transaction text.
# Evaluates tuples: (entity_type, entity_id, field, prior_val, new_val, tier)
# Runs offline, <100ms, zero network calls.
#
# Conforms to blueprint §§ 2, 3, 10 and Zero-Betting Policy.
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
      stop(sprintf("extract_regex.R: cannot locate repo root (no config.R at or above '%s')", start))
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

# Zero-betting policy guard check
FORBIDDEN_BETTING_TERMS <- c("sportsbook", "betmgm", "draftkings", "fanduel",
                             "caesars sportsbook", "pointsbet", "bovada", "bet365",
                             "moneyline", "runline", "over/under", "parlay",
                             "\\bvig\\b", "\\bjuice\\b", "\\bprop bet\\b")

validate_zero_betting <- function(text_vector) {
  for (pattern in FORBIDDEN_BETTING_TERMS) {
    matches <- grepl(pattern, text_vector, ignore.case = TRUE)
    if (any(matches)) {
      stop(sprintf("Zero-betting policy violation: found '%s' in extraction text", pattern))
    }
  }
}

# Team mapping helper
TEAM_NAME_TO_ABBREV <- c(
  "Arizona Diamondbacks" = "ARI", "Diamondbacks" = "ARI", "D-backs" = "ARI",
  "Athletics" = "ATH", "Oakland Athletics" = "ATH",
  "Atlanta Braves" = "ATL", "Braves" = "ATL",
  "Baltimore Orioles" = "BAL", "Orioles" = "BAL",
  "Boston Red Sox" = "BOS", "Red Sox" = "BOS",
  "Chicago Cubs" = "CHC", "Cubs" = "CHC",
  "Chicago White Sox" = "CHW", "White Sox" = "CHW",
  "Cincinnati Reds" = "CIN", "Reds" = "CIN",
  "Cleveland Guardians" = "CLE", "Guardians" = "CLE",
  "Colorado Rockies" = "COL", "Rockies" = "COL",
  "Detroit Tigers" = "DET", "Tigers" = "DET",
  "Houston Astros" = "HOU", "Astros" = "HOU",
  "Kansas City Royals" = "KC", "Royals" = "KC",
  "Los Angeles Angels" = "LAA", "Angels" = "LAA",
  "Los Angeles Dodgers" = "LAD", "Dodgers" = "LAD",
  "Miami Marlins" = "MIA", "Marlins" = "MIA",
  "Milwaukee Brewers" = "MIL", "Brewers" = "MIL",
  "Minnesota Twins" = "MIN", "Twins" = "MIN",
  "New York Mets" = "NYM", "Mets" = "NYM",
  "New York Yankees" = "NYY", "Yankees" = "NYY",
  "Philadelphia Phillies" = "PHI", "Phillies" = "PHI",
  "Pittsburgh Pirates" = "PIT", "Pirates" = "PIT",
  "San Diego Padres" = "SD", "Padres" = "SD",
  "San Francisco Giants" = "SF", "Giants" = "SF",
  "Seattle Mariners" = "SEA", "Mariners" = "SEA",
  "St. Louis Cardinals" = "STL", "Cardinals" = "STL",
  "Tampa Bay Rays" = "TB", "Rays" = "TB",
  "Texas Rangers" = "TEX", "Rangers" = "TEX",
  "Toronto Blue Jays" = "TOR", "Blue Jays" = "TOR",
  "Washington Nationals" = "WSH", "Nationals" = "WSH"
)

resolve_team_abbr <- function(name) {
  clean <- trimws(name)
  if (clean %in% names(TEAM_NAME_TO_ABBREV)) {
    return(TEAM_NAME_TO_ABBREV[[clean]])
  }
  for (nm in names(TEAM_NAME_TO_ABBREV)) {
    if (grepl(paste0("\\b", nm, "$"), clean, ignore.case = TRUE) ||
        grepl(paste0("^", nm, "\\b"), clean, ignore.case = TRUE)) {
      return(TEAM_NAME_TO_ABBREV[[nm]])
    }
  }
  clean
}

# Build an indexed displayName -> playerId lookup environment for <1ms matching
build_player_index <- function(baseline_players) {
  env <- new.env(parent = emptyenv(), hash = TRUE)
  for (pid in names(baseline_players)) {
    dname <- baseline_players[[pid]]$displayName
    if (!is.null(dname) && nzchar(dname)) {
      env[[tolower(trimws(dname))]] <- baseline_players[[pid]]
    }
  }
  env
}

# Strip positions like 1B, RHP, SS, LF, etc.
strip_position <- function(str) {
  sub("^(?:[123]B|SS|LF|CF|RF|DH|OF|IF|LHP|RHP|C|P)\\s+", "", trimws(str))
}

# Fast player lookup in text using exact word tokens
find_player_in_snippet <- function(snippet, baseline_players, player_index = NULL) {
  snip_clean <- strip_position(snippet)
  
  if (!is.null(player_index)) {
    # Check whole snippet
    clean_lower <- tolower(snip_clean)
    if (exists(clean_lower, envir = player_index, inherits = FALSE)) {
      return(get(clean_lower, envir = player_index))
    }
    # Check n-grams (2 words or 3 words)
    words <- unlist(strsplit(snip_clean, "\\s+"))
    n_w <- length(words)
    if (n_w >= 2) {
      for (j in 1:(n_w - 1)) {
        w2 <- tolower(paste(words[j], words[j+1]))
        if (exists(w2, envir = player_index, inherits = FALSE)) {
          return(get(w2, envir = player_index))
        }
      }
    }
    if (n_w >= 3) {
      for (j in 1:(n_w - 2)) {
        w3 <- tolower(paste(words[j], words[j+1], words[j+2]))
        if (exists(w3, envir = player_index, inherits = FALSE)) {
          return(get(w3, envir = player_index))
        }
      }
    }
  } else {
    for (pid in names(baseline_players)) {
      dname <- baseline_players[[pid]]$displayName
      if (!is.null(dname) && nchar(dname) > 4 && grepl(dname, snippet, fixed = TRUE)) {
        return(baseline_players[[pid]])
      }
    }
  }
  NULL
}

# Builds a wire sourceUrl that identifies the specific transaction when a
# teamId + transactionId are known, so links are no longer the bare,
# query-less transactions endpoint. Falls back to a team-scoped link with
# the as-of date when only the teamId is known, and finally to the raw
# default_url (e.g. the bare endpoint from a fixture) when neither is known.
build_wire_source_url <- function(default_url, team_id = NULL, transaction_id = NULL, as_of_date = NULL) {
  base <- "https://statsapi.mlb.com/api/v1/transactions"
  if (!is.null(team_id) && !is.null(transaction_id)) {
    return(sprintf("%s?teamId=%s&transactionIds=%s", base, team_id, transaction_id))
  }
  if (!is.null(team_id)) {
    if (!is.null(as_of_date)) {
      return(sprintf("%s?teamId=%s&startDate=%s&endDate=%s", base, team_id, as_of_date, as_of_date))
    }
    return(sprintf("%s?teamId=%s", base, team_id))
  }
  default_url
}

# Core Layer A regex extraction function
# team_id / transaction_id (when known from the raw ingest payload) are used
# to build a sourceUrl that identifies the specific transaction instead of
# the bare transactions endpoint.
extract_regex_from_text <- function(raw_text, baseline, as_of_date = "2026-10-31", source_url = NULL,
                                     player_index = NULL, team_id = NULL, transaction_id = NULL) {
  validate_zero_betting(raw_text)
  deltas <- list()
  resolved_source_url <- build_wire_source_url(source_url, team_id, transaction_id, as_of_date)
  
  if (is.null(player_index) && !is.null(baseline$players)) {
    if (is.null(baseline$.player_index)) {
      player_index <- build_player_index(baseline$players)
    } else {
      player_index <- baseline$.player_index
    }
  }
  
  # Pattern 1: Free agency declaration / election
  if (grepl("(?:declared|elected) free agency\\.?$", raw_text, ignore.case = TRUE)) {
    prefix <- sub("\\s+(?:declared|elected) free agency\\.?$", "", raw_text, ignore.case = TRUE)
    p <- find_player_in_snippet(prefix, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (!identical(prior_roster, "FREE_AGENT")) {
        deltas[[length(deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = prior_roster,
          new_val = "FREE_AGENT",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "FREE_AGENCY"
        )
      }

      # contractStatus and team are the same underlying free-agency transaction
      # as rosterStatus above; they still mutate the baseline (so downstream
      # state is correct) but must not each spawn their own confirmedChanges
      # row (that produced the Pete Alonso duplicate/phantom rows: 1 signing
      # must produce exactly 1 reported event, not 3).
      prior_contract <- p$contractStatus$value
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = p$playerId,
        field = "contractStatus",
        prior_val = prior_contract,
        new_val = "UNRESTRICTED_FA",
        tier = "CONFIRMED",
        date = as_of_date,
        source_url = resolved_source_url,
        transaction_type = "FREE_AGENCY",
        suppress_event = TRUE
      )

      prior_team <- p$team$value
      if (!is.null(prior_team)) {
        deltas[[length(deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "team",
          prior_val = prior_team,
          new_val = NULL,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "FREE_AGENCY",
          suppress_event = TRUE
        )
      }
    }
    return(deltas)
  }

  # Pattern 2: Option exercised / declined
  if (grepl("(exercised|declined)\\s+(?:his\\s+)?(?:[0-9]{4}\\s+)?contract option\\.?$", raw_text, ignore.case = TRUE)) {
    action <- if (grepl("exercised", raw_text, ignore.case = TRUE)) "exercised" else "declined"
    prefix <- sub("\\s+(exercised|declined)\\s+(?:his\\s+)?(?:[0-9]{4}\\s+)?contract option\\.?$", "", raw_text, ignore.case = TRUE)
    p <- find_player_in_snippet(prefix, baseline$players, player_index)
    if (!is.null(p)) {
      prior_contract <- p$contractStatus$value
      new_contract <- if (action == "exercised") "GUARANTEED" else "UNRESTRICTED_FA"
      deltas[[length(deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = p$playerId,
        field = "contractStatus",
        prior_val = prior_contract,
        new_val = new_contract,
        tier = "CONFIRMED",
        date = as_of_date,
        source_url = resolved_source_url,
        transaction_type = if (action == "exercised") "OPTION_EXERCISED" else "OPTION_DECLINED"
      )
    }
    return(deltas)
  }

  # Pattern 3: Waiver claim
  if (grepl("claimed.+off waivers from", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+claimed\\s+(.+?)\\s+off waivers from\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    if (length(parts) >= 4) {
      to_team <- resolve_team_abbr(parts[2])
      p_snippet <- parts[3]
      from_team <- resolve_team_abbr(parts[4])
      p <- find_player_in_snippet(p_snippet, baseline$players, player_index)
      if (!is.null(p)) {
        prior_team <- p$team$value
        deltas[[length(deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "team",
          prior_val = prior_team,
          new_val = to_team,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "WAIVER_CLAIM"
        )
      }
    }
    return(deltas)
  }

  # Pattern 4: Trade
  if (grepl("\\btraded\\b.+\\bto\\b.+\\bfor\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+traded\\s+(.+?)\\s+to\\s+(.+?)\\s+for\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    if (length(parts) >= 5) {
      from_team <- resolve_team_abbr(parts[2])
      p1_snippet <- parts[3]
      to_team <- resolve_team_abbr(parts[4])
      return_pkg <- parts[5]
      
      p1 <- find_player_in_snippet(p1_snippet, baseline$players, player_index)
      if (!is.null(p1)) {
        deltas[[length(deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = p1$playerId,
          field = "team",
          prior_val = p1$team$value,
          new_val = to_team,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "TRADE"
        )
      }

      p2 <- find_player_in_snippet(return_pkg, baseline$players, player_index)
      if (!is.null(p2)) {
        deltas[[length(deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = p2$playerId,
          field = "team",
          prior_val = p2$team$value,
          new_val = from_team,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "TRADE"
        )
      }
    }
    return(deltas)
  }

  deltas
}
