# ==============================================================================
# tools/offseason/extract_regex.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Layer A Deterministic Regex Extractor
# Path: tools/offseason/extract_regex.R
#
# Extracts deterministic state deltas from official wire transaction text.
# Evaluates tuples: (entity_type, entity_id, field, prior_val, new_val, tier)
# Runs offline, <100ms, zero network calls.
#
# GitHub issue #60:
#   - Classifies all 12 live transaction classes across ~1,970 post-WS items:
#     1. Status Change (SC)               -> Deliberate NO-OP
#     2. Declared Free Agency (DFA)       -> State mutation (FREE_AGENCY)
#     3. Assigned (ASG)                   -> Deliberate NO-OP if non-MLB
#     4. Released (REL)                   -> State mutation (RELEASE) if 40-man, else NO-OP
#     5. Outrighted (OUT)                 -> State mutation (OUTRIGHT) if 40-man, else NO-OP
#     6. Claimed Off Waivers (CLW)        -> State mutation (WAIVER_CLAIM)
#     7. Trade (TR)                       -> State mutation (TRADE), with or without 'for' clause
#     8. Designated for Assignment (DES)  -> State mutation (DFA)
#     9. Selected (SE)                    -> State mutation (CONTRACT_SELECTED)
#    10. Signed as Free Agent (SFA)       -> State mutation (FREE_AGENT_SIGNING) if major, else NO-OP
#    11. Loan (LON)                       -> Deliberate NO-OP
#    12. Returned (RTN)                   -> Deliberate NO-OP (Rule 5 / minor league on non-40-man)
#   - Eliminates silent fall-through: explicit UNCLASSIFIED fallback.
#   - Resolves players primarily by mlbamId (O(1) table lookup) with name fallback.
#   - Explicit UTF-8 decoding for accented names under cp1252 Windows locales.
#   - Conforms to blueprint §§ 2, 3, 10 and Zero-Betting Policy.
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

TEAM_ID_TO_ABBREV <- c(
  "133" = "ATH", "144" = "ATL", "109" = "ARI", "110" = "BAL", "111" = "BOS",
  "112" = "CHC", "113" = "CIN", "114" = "CLE", "115" = "COL", "145" = "CHW",
  "116" = "DET", "117" = "HOU", "118" = "KC",  "108" = "LAA", "119" = "LAD",
  "146" = "MIA", "158" = "MIL", "142" = "MIN", "121" = "NYM", "147" = "NYY",
  "143" = "PHI", "134" = "PIT", "135" = "SD",  "136" = "SEA", "137" = "SF",
  "138" = "STL", "139" = "TB",  "140" = "TEX", "141" = "TOR", "120" = "WSH"
)

resolve_team_abbr <- function(name_or_id) {
  if (is.null(name_or_id)) return(NULL)
  clean <- trimws(as.character(name_or_id))
  if (clean %in% names(TEAM_ID_TO_ABBREV)) {
    return(TEAM_ID_TO_ABBREV[[clean]])
  }
  if (clean %in% names(TEAM_NAME_TO_ABBREV)) {
    return(TEAM_NAME_TO_ABBREV[[clean]])
  }
  if (clean %in% unname(TEAM_NAME_TO_ABBREV)) {
    return(clean)
  }
  for (nm in names(TEAM_NAME_TO_ABBREV)) {
    if (grepl(paste0("\\b", nm, "$"), clean, ignore.case = TRUE) ||
        grepl(paste0("^", nm, "\\b"), clean, ignore.case = TRUE)) {
      return(TEAM_NAME_TO_ABBREV[[nm]])
    }
  }
  clean
}

# Build an indexed lookup environment for <1ms matching (GitHub issue #60):
# Indexes by:
#   1. MLBAM ID string (e.g. "553993") -> O(1) table lookup
#   2. Lowercase UTF-8 displayName (e.g. "eugenio suárez")
#   3. Transliterated ASCII lowercase displayName (e.g. "eugenio suarez") for cp1252 compatibility
build_player_index <- function(baseline_players) {
  env <- new.env(parent = emptyenv(), hash = TRUE)
  for (pid in names(baseline_players)) {
    p <- baseline_players[[pid]]
    dname <- p$displayName
    if (!is.null(dname) && nzchar(dname)) {
      u_name <- enc2utf8(tolower(trimws(dname)))
      env[[u_name]] <- p
      a_name <- iconv(u_name, to = "ASCII//TRANSLIT")
      if (!is.na(a_name) && nzchar(a_name) && !identical(a_name, u_name)) {
        if (!exists(a_name, envir = env, inherits = FALSE)) {
          env[[a_name]] <- p
        }
      }
    }
    mid <- p$mlbamId
    if (!is.null(mid) && !is.na(mid)) {
      id_str <- as.character(mid)
      env[[id_str]] <- p
    }
  }
  env
}

# Strip positions like 1B, RHP, SS, LF, etc.
strip_position <- function(str) {
  clean <- sub("^(?:[123]B|SS|LF|CF|RF|DH|OF|IF|LHP|RHP|C|P)\\s+", "", trimws(str))
  sub("\\.+$", "", trimws(clean))
}

# Resolves player primarily by mlbam_id (O(1) table lookup),
# falling back to name search only when mlbam_id is absent (GitHub issue #60).
resolve_player <- function(mlbam_id = NULL, snippet = NULL, baseline_players = NULL, player_index = NULL) {
  # 1. Primary path: O(1) lookup by mlbamId
  if (!is.null(mlbam_id) && !is.na(mlbam_id)) {
    id_str <- as.character(mlbam_id)
    if (!is.null(player_index)) {
      if (exists(id_str, envir = player_index, inherits = FALSE)) {
        return(get(id_str, envir = player_index))
      }
    } else if (!is.null(baseline_players)) {
      for (pid in names(baseline_players)) {
        p_mid <- baseline_players[[pid]]$mlbamId
        if (!is.null(p_mid) && identical(as.character(p_mid), id_str)) {
          return(baseline_players[[pid]])
        }
      }
    }
  }

  # 2. Fallback path: Name search in snippet
  if (!is.null(snippet) && nzchar(trimws(snippet))) {
    return(find_player_in_snippet(snippet, baseline_players, player_index))
  }

  NULL
}

# Fast player lookup in text using exact word tokens and UTF-8 / transliterated matching
find_player_in_snippet <- function(snippet, baseline_players, player_index = NULL) {
  if (is.null(snippet) || !nzchar(trimws(snippet))) return(NULL)
  snip_clean <- strip_position(snippet)
  snip_utf8 <- enc2utf8(snip_clean)

  if (!is.null(player_index)) {
    # Check whole snippet
    clean_lower <- tolower(snip_utf8)
    if (exists(clean_lower, envir = player_index, inherits = FALSE)) {
      return(get(clean_lower, envir = player_index))
    }
    clean_translit <- iconv(clean_lower, to = "ASCII//TRANSLIT")
    if (!is.na(clean_translit) && exists(clean_translit, envir = player_index, inherits = FALSE)) {
      return(get(clean_translit, envir = player_index))
    }

    # Check n-grams (2 words or 3 words)
    words <- unlist(strsplit(snip_utf8, "\\s+"))
    n_w <- length(words)
    if (n_w >= 2) {
      for (j in 1:(n_w - 1)) {
        w2 <- tolower(paste(words[j], words[j+1]))
        if (exists(w2, envir = player_index, inherits = FALSE)) {
          return(get(w2, envir = player_index))
        }
        w2_tr <- iconv(w2, to = "ASCII//TRANSLIT")
        if (!is.na(w2_tr) && exists(w2_tr, envir = player_index, inherits = FALSE)) {
          return(get(w2_tr, envir = player_index))
        }
      }
    }
    if (n_w >= 3) {
      for (j in 1:(n_w - 2)) {
        w3 <- tolower(paste(words[j], words[j+1], words[j+2]))
        if (exists(w3, envir = player_index, inherits = FALSE)) {
          return(get(w3, envir = player_index))
        }
        w3_tr <- iconv(w3, to = "ASCII//TRANSLIT")
        if (!is.na(w3_tr) && exists(w3_tr, envir = player_index, inherits = FALSE)) {
          return(get(w3_tr, envir = player_index))
        }
      }
    }
  } else {
    for (pid in names(baseline_players)) {
      dname <- baseline_players[[pid]]$displayName
      if (!is.null(dname) && nchar(dname) > 4 && grepl(enc2utf8(dname), snip_utf8, fixed = TRUE)) {
        return(baseline_players[[pid]])
      }
    }
  }
  NULL
}

# Builds a wire sourceUrl that identifies the specific transaction when a
# teamId + transactionId are known.
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

# In-memory index of wire items for O(1) enrichment by transaction_id
WIRE_ITEMS_CACHE <- new.env(parent = emptyenv(), hash = TRUE)

load_wire_items_cache <- function(path = "cache/offseason_wire_items.json") {
  if (file.exists(path)) {
    items <- tryCatch(
      jsonlite::fromJSON(path, simplifyVector = FALSE, encoding = "UTF-8"),
      error = function(e) NULL
    )
    if (is.list(items)) {
      for (it in items) {
        if (!is.null(it$transaction_id)) {
          tid <- as.character(it$transaction_id)
          WIRE_ITEMS_CACHE[[tid]] <- it
        }
      }
    }
  }
  WIRE_ITEMS_CACHE[[".loaded"]] <- TRUE
}

# Core Layer A regex extraction function
# Evaluates structured wire fields (type_code, type_desc, mlbam_id, team_id, from_team_id)
# when available, falling back to natural-language regex on raw_text.
extract_regex_from_text <- function(raw_text, baseline, as_of_date = "2026-10-31", source_url = NULL,
                                    player_index = NULL, team_id = NULL, transaction_id = NULL,
                                    from_team_id = NULL, mlbam_id = NULL, player_name = NULL,
                                    type_code = NULL, type_desc = NULL, roster_tier = NULL, ...) {
  # Accept wire-item list object directly if passed as first argument
  if (is.list(raw_text)) {
    item <- raw_text
    raw_text <- item$raw_text
    if (is.null(as_of_date) || identical(as_of_date, "2026-10-31")) as_of_date <- if (!is.null(item$date)) item$date else as_of_date
    if (is.null(source_url)) source_url <- item$source_url
    if (is.null(team_id)) team_id <- item$team_id
    if (is.null(transaction_id)) transaction_id <- item$transaction_id
    if (is.null(from_team_id)) from_team_id <- item$from_team_id
    if (is.null(mlbam_id)) mlbam_id <- item$mlbam_id
    if (is.null(player_name)) player_name <- item$player_name
    if (is.null(type_code)) type_code <- item$type_code
    if (is.null(type_desc)) type_desc <- item$type_desc
    if (is.null(roster_tier)) roster_tier <- item$roster_tier
  }

  # If transaction_id is present and structured fields were not supplied,
  # look up structured metadata from the wire items cache
  if (!is.null(transaction_id) && is.null(type_code)) {
    tid_str <- as.character(transaction_id)
    if (!exists(".loaded", envir = WIRE_ITEMS_CACHE, inherits = FALSE)) {
      if (file.exists("cache/offseason_wire_items.json")) {
        load_wire_items_cache("cache/offseason_wire_items.json")
      } else {
        WIRE_ITEMS_CACHE[[".loaded"]] <- TRUE
      }
    }
    if (exists(tid_str, envir = WIRE_ITEMS_CACHE, inherits = FALSE)) {
      wi <- get(tid_str, envir = WIRE_ITEMS_CACHE)
      if (is.null(from_team_id)) from_team_id <- wi$from_team_id
      if (is.null(mlbam_id)) mlbam_id <- wi$mlbam_id
      if (is.null(player_name)) player_name <- wi$player_name
      if (is.null(type_code)) type_code <- wi$type_code
      if (is.null(type_desc)) type_desc <- wi$type_desc
      if (is.null(roster_tier)) roster_tier <- wi$roster_tier
      if (is.null(team_id)) team_id <- wi$team_id
    }
  }

  raw_text <- enc2utf8(as.character(raw_text))
  validate_zero_betting(raw_text)
  deltas <- list()
  resolved_source_url <- build_wire_source_url(source_url, team_id, transaction_id, as_of_date)

  if (is.null(player_index) && !is.null(baseline$players)) {
    player_index <- if (is.null(baseline$.player_index)) build_player_index(baseline$players) else baseline$.player_index
  }

  # ----------------------------------------------------------------------------
  # Class 1: Status Change (SC) — Minor league / IL moves (Documented NO-OP)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "SC") || identical(type_desc, "Status Change") ||
      grepl("\\b(?:placed|activated)\\b.+\\breserve list\\b", raw_text, ignore.case = TRUE)) {
    attr(deltas, "classification") <- list(
      status = "NO_OP",
      class = "Status Change",
      type_code = if (!is.null(type_code)) type_code else "SC",
      type_desc = if (!is.null(type_desc)) type_desc else "Status Change",
      rationale = "Minor league / IL move; does not mutate 40-man roster"
    )
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 2: Assigned (ASG) — Minor-league assignments (Documented NO-OP)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "ASG") || identical(type_desc, "Assigned") ||
      grepl("\\bassigned to\\b", raw_text, ignore.case = TRUE)) {
    attr(deltas, "classification") <- list(
      status = "NO_OP",
      class = "Assigned",
      type_code = if (!is.null(type_code)) type_code else "ASG",
      type_desc = if (!is.null(type_desc)) type_desc else "Assigned",
      rationale = "Minor-league assignment; does not mutate 40-man roster"
    )
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 3: Loan (LON) — Winter league / international loan (Documented NO-OP)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "LON") || identical(type_desc, "Loan") ||
      grepl("\\bloaned to\\b", raw_text, ignore.case = TRUE)) {
    attr(deltas, "classification") <- list(
      status = "NO_OP",
      class = "Loan",
      type_code = if (!is.null(type_code)) type_code else "LON",
      type_desc = if (!is.null(type_desc)) type_desc else "Loan",
      rationale = "Winter league / international loan; does not mutate 40-man roster"
    )
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 4: Returned (RTN) — Rule 5 / minor return on non-40-man (Documented NO-OP)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "RTN") || identical(type_desc, "Returned") ||
      grepl("\\breturned to\\b.+\\bfrom\\b", raw_text, ignore.case = TRUE)) {
    attr(deltas, "classification") <- list(
      status = "NO_OP",
      class = "Returned",
      type_code = if (!is.null(type_code)) type_code else "RTN",
      type_desc = if (!is.null(type_desc)) type_desc else "Returned",
      rationale = "Rule 5 / minor league return on non-40-man player; does not mutate 40-man roster"
    )
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 5: Declared Free Agency (DFA)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "DFA") || identical(type_desc, "Declared Free Agency") ||
      grepl("(?:declared|elected)\\s+free\\s+agency\\.?$", raw_text, ignore.case = TRUE)) {
    prefix <- sub("\\s+(?:declared|elected)\\s+free\\s+agency\\.?$", "", raw_text, ignore.case = TRUE)
    p <- resolve_player(mlbam_id, prefix, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (!identical(prior_roster, "FREE_AGENT")) {
        deltas[[length(deltas) + 1L]] <- list(
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

      prior_contract <- p$contractStatus$value
      deltas[[length(deltas) + 1L]] <- list(
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
        deltas[[length(deltas) + 1L]] <- list(
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
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Declared Free Agency",
        type_code = "DFA",
        type_desc = "Declared Free Agency",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Declared Free Agency",
        type_code = "DFA",
        type_desc = "Declared Free Agency",
        rationale = "Player not found in baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 6: Contract option exercised / declined
  # ----------------------------------------------------------------------------
  if (grepl("(exercised|declined)\\s+(?:his\\s+)?(?:[0-9]{4}\\s+)?contract option\\.?$", raw_text, ignore.case = TRUE)) {
    action <- if (grepl("exercised", raw_text, ignore.case = TRUE)) "exercised" else "declined"
    prefix <- sub("\\s+(exercised|declined)\\s+(?:his\\s+)?(?:[0-9]{4}\\s+)?contract option\\.?$", "", raw_text, ignore.case = TRUE)
    p <- resolve_player(mlbam_id, prefix, baseline$players, player_index)
    if (!is.null(p)) {
      prior_contract <- p$contractStatus$value
      new_contract <- if (action == "exercised") "GUARANTEED" else "UNRESTRICTED_FA"
      deltas[[length(deltas) + 1L]] <- list(
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
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Contract Option",
        type_code = "OPT",
        type_desc = "Contract Option",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Contract Option",
        type_code = "OPT",
        type_desc = "Contract Option",
        rationale = "Player not found in baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 7: Claimed Off Waivers (CLW)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "CLW") || identical(type_desc, "Claimed Off Waivers") ||
      grepl("\\bclaimed\\b.+\\boff waivers from\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+claimed\\s+(.+?)\\s+off waivers from\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    to_team <- if (!is.null(team_id)) resolve_team_abbr(team_id) else if (length(parts) >= 2) resolve_team_abbr(parts[2]) else NULL
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p)) {
      prior_team <- p$team$value
      deltas[[length(deltas) + 1L]] <- list(
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
      if (identical(p$rosterStatus$value, "DFA")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = "DFA",
          new_val = "40_MAN",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "WAIVER_CLAIM",
          suppress_event = TRUE
        )
      }
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Claimed Off Waivers",
        type_code = "CLW",
        type_desc = "Claimed Off Waivers",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Claimed Off Waivers",
        type_code = "CLW",
        type_desc = "Claimed Off Waivers",
        rationale = "Claimed player not in baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 8: Trade (TR) — with or without 'for' clause (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "TR") || identical(type_desc, "Trade") ||
      grepl("\\btraded\\b.+\\bto\\b", raw_text, ignore.case = TRUE)) {
    # Optional 'for' clause regex pattern: (?:\\s+for\\s+(.+?))?\\.?$
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+traded\\s+(.+?)\\s+to\\s+(.+?)(?:\\s+for\\s+(.+?))?\\.?$", raw_text, ignore.case = TRUE))[[1]]
    if (length(parts) >= 4) {
      from_str <- sub("\\.+$", "", trimws(parts[2]))
      to_str <- sub("\\.+$", "", trimws(parts[4]))
      from_team <- if (!is.null(from_team_id)) resolve_team_abbr(from_team_id) else resolve_team_abbr(from_str)
      p1_snippet <- sub("\\.+$", "", trimws(parts[3]))
      to_team <- if (!is.null(team_id)) resolve_team_abbr(team_id) else resolve_team_abbr(to_str)
      return_pkg <- if (length(parts) >= 5 && nzchar(trimws(parts[5]))) sub("\\.+$", "", trimws(parts[5])) else NULL

      p1 <- resolve_player(mlbam_id, p1_snippet, baseline$players, player_index)
      if (!is.null(p1)) {
        deltas[[length(deltas) + 1L]] <- list(
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

      if (!is.null(return_pkg) && !grepl("^(?:cash|a player to be named later|future considerations|PTBNL)\\.?$", return_pkg, ignore.case = TRUE)) {
        p2 <- find_player_in_snippet(return_pkg, baseline$players, player_index)
        if (!is.null(p2)) {
          deltas[[length(deltas) + 1L]] <- list(
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
      if (length(deltas) > 0) {
        attr(deltas, "classification") <- list(
          status = "DELTA",
          class = "Trade",
          type_code = "TR",
          type_desc = "Trade",
          deltas_count = length(deltas)
        )
      } else {
        attr(deltas, "classification") <- list(
          status = "NO_OP",
          class = "Trade",
          type_code = "TR",
          type_desc = "Trade",
          rationale = "Trade involved non-40-man players or non-MLB clubs; no 40-man baseline mutation"
        )
      }
      return(deltas)
    }
  }

  # ----------------------------------------------------------------------------
  # Class 9: Designated for Assignment (DES) (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "DES") || identical(type_desc, "Designated for Assignment") ||
      grepl("\\bdesignated\\b.+\\bfor assignment\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+designated\\s+(.+?)\\s+for\\s+assignment\\.?$", raw_text, ignore.case = TRUE))[[1]]
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (!identical(prior_roster, "DFA")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = prior_roster,
          new_val = "DFA",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "DFA"
        )
      }
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Designated for Assignment",
        type_code = "DES",
        type_desc = "Designated for Assignment",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Designated for Assignment",
        type_code = "DES",
        type_desc = "Designated for Assignment",
        rationale = "DFA player not in baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 10: Outrighted (OUT) (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "OUT") || identical(type_desc, "Outrighted") ||
      grepl("\\bsent\\b.+\\boutright to\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+sent\\s+(.+?)\\s+outright\\s+to\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (identical(prior_roster, "40_MAN")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = prior_roster,
          new_val = "MINOR_LEAGUE",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "OUTRIGHT"
        )
        attr(deltas, "classification") <- list(
          status = "DELTA",
          class = "Outrighted",
          type_code = "OUT",
          type_desc = "Outrighted",
          deltas_count = length(deltas)
        )
      } else {
        attr(deltas, "classification") <- list(
          status = "NO_OP",
          class = "Outrighted",
          type_code = "OUT",
          type_desc = "Outrighted",
          rationale = "Outrighted player already not on 40-man roster"
        )
      }
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Outrighted",
        type_code = "OUT",
        type_desc = "Outrighted",
        rationale = "Outrighted player not in 40-man baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 11: Released (REL) (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "REL") || identical(type_desc, "Released") ||
      grepl("\\breleased\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+released\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p) && identical(p$rosterStatus$value, "40_MAN")) {
      prior_roster <- p$rosterStatus$value
      deltas[[length(deltas) + 1L]] <- list(
        entity_type = "player",
        entity_id = p$playerId,
        field = "rosterStatus",
        prior_val = prior_roster,
        new_val = "FREE_AGENT",
        tier = "CONFIRMED",
        date = as_of_date,
        source_url = resolved_source_url,
        transaction_type = "RELEASE"
      )
      deltas[[length(deltas) + 1L]] <- list(
        entity_type = "player",
        entity_id = p$playerId,
        field = "contractStatus",
        prior_val = p$contractStatus$value,
        new_val = "UNRESTRICTED_FA",
        tier = "CONFIRMED",
        date = as_of_date,
        source_url = resolved_source_url,
        transaction_type = "RELEASE",
        suppress_event = TRUE
      )
      if (!is.null(p$team$value)) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "team",
          prior_val = p$team$value,
          new_val = NULL,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "RELEASE",
          suppress_event = TRUE
        )
      }
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Released",
        type_code = "REL",
        type_desc = "Released",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Released",
        type_code = "REL",
        type_desc = "Released",
        rationale = "Released player not on 40-man roster; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 12: Selected (SE) — Contract selected onto 40-man (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "SE") || identical(type_desc, "Selected") ||
      grepl("\\bselected the contract of\\b", raw_text, ignore.case = TRUE)) {
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+selected\\s+the\\s+contract\\s+of\\s+(.+?)\\s+from\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
    to_team <- if (!is.null(team_id)) resolve_team_abbr(team_id) else if (length(parts) >= 2) resolve_team_abbr(parts[2]) else NULL
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (!identical(prior_roster, "40_MAN")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = prior_roster,
          new_val = "40_MAN",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "CONTRACT_SELECTED"
        )
      }
      if (!is.null(to_team) && !identical(p$team$value, to_team)) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "team",
          prior_val = p$team$value,
          new_val = to_team,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "CONTRACT_SELECTED",
          suppress_event = TRUE
        )
      }
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Selected",
        type_code = "SE",
        type_desc = "Selected",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Selected",
        type_code = "SE",
        type_desc = "Selected",
        rationale = "Selected player not in baseline; no baseline mutation"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Class 13: Signed as Free Agent (SFA) (GitHub issue #60)
  # ----------------------------------------------------------------------------
  if (identical(type_code, "SFA") || identical(type_desc, "Signed as Free Agent") ||
      grepl("\\bsigned free agent\\b", raw_text, ignore.case = TRUE)) {
    is_minor <- grepl("minor league", raw_text, ignore.case = TRUE) || identical(roster_tier, "MINOR_LEAGUE")
    if (is_minor) {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Signed as Free Agent",
        type_code = "SFA",
        type_desc = "Signed as Free Agent",
        rationale = "Minor league free agent signing; does not mutate 40-man roster"
      )
      return(deltas)
    }
    parts <- regmatches(raw_text, regexec("^(.+?)\\s+signed\\s+free\\s+agent\\s+(.+?)(?:\\s+to\\s+a\\s+minor\\s+league\\s+contract)?\\.?$", raw_text, ignore.case = TRUE))[[1]]
    to_team <- if (!is.null(team_id)) resolve_team_abbr(team_id) else if (length(parts) >= 2) resolve_team_abbr(parts[2]) else NULL
    p_snip <- if (length(parts) >= 3) parts[3] else NULL
    p <- resolve_player(mlbam_id, p_snip, baseline$players, player_index)
    if (!is.null(p)) {
      prior_roster <- p$rosterStatus$value
      if (!identical(prior_roster, "40_MAN")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "rosterStatus",
          prior_val = prior_roster,
          new_val = "40_MAN",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "FREE_AGENT_SIGNING"
        )
      }
      if (!is.null(to_team) && !identical(p$team$value, to_team)) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "team",
          prior_val = p$team$value,
          new_val = to_team,
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "FREE_AGENT_SIGNING",
          suppress_event = TRUE
        )
      }
      prior_contract <- p$contractStatus$value
      if (!identical(prior_contract, "GUARANTEED")) {
        deltas[[length(deltas) + 1L]] <- list(
          entity_type = "player",
          entity_id = p$playerId,
          field = "contractStatus",
          prior_val = prior_contract,
          new_val = "GUARANTEED",
          tier = "CONFIRMED",
          date = as_of_date,
          source_url = resolved_source_url,
          transaction_type = "FREE_AGENT_SIGNING",
          suppress_event = TRUE
        )
      }
      attr(deltas, "classification") <- list(
        status = "DELTA",
        class = "Signed as Free Agent",
        type_code = "SFA",
        type_desc = "Signed as Free Agent",
        deltas_count = length(deltas)
      )
    } else {
      attr(deltas, "classification") <- list(
        status = "NO_OP",
        class = "Signed as Free Agent",
        type_code = "SFA",
        type_desc = "Signed as Free Agent",
        rationale = "Free agent signing player not in baseline"
      )
    }
    return(deltas)
  }

  # ----------------------------------------------------------------------------
  # Fall-through: Explicit UNCLASSIFIED (eliminating silent fall-through)
  # ----------------------------------------------------------------------------
  attr(deltas, "classification") <- list(
    status = "UNCLASSIFIED",
    type_code = if (!is.null(type_code)) type_code else "UNKNOWN",
    type_desc = if (!is.null(type_desc)) type_desc else "Unknown",
    raw_text = raw_text,
    reason = "No handler matched"
  )
  deltas
}
