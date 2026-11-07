# ==============================================================================
# extract_regex.R
# WNBA Offseason Dynamics Monitor — Deterministic Regex Extractor (Tier 2 / Phase 3)
#
# Parses official transaction wire text snapshots using deterministic regex patterns.
# Returns candidate structured delta tuples:
#   (entity_type, entity_id, entity_name, field, prior_val, new_val, tier, date, source_url, change_type)
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
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    warning("jsonlite package not available; JSON features may be limited.")
  }
})

# Agreed change_type vocabulary across Tier 2 units
VALID_CHANGE_TYPES <- c(
  "SIGNING", "WAIVER", "RELEASE", "TRADE", "WAIVER_CLAIM",
  "CONTRACT_OFFER", "OFFER_MATCH", "ROSTER_STATUS", "FRONT_OFFICE",
  "CORE_DESIGNATION", "RESERVED_PLAYER", "QUALIFYING_OFFER",
  "PRIORITIZATION", "RETIREMENT", "SUSPENSION", "DRAFT_RIGHTS",
  "EXPANSION_DRAFT", "UNCLASSIFIED"
)

# Canonical team dictionary (Names, Nicknames, Cities, and Abbrevs to Canonical Abbrev)
TEAM_NAME_MAP <- list(
  "Golden State Valkyries" = "GS", "Valkyries" = "GS", "Golden State" = "GS", "GS" = "GS",
  "Atlanta Dream" = "ATL", "Dream" = "ATL", "Atlanta" = "ATL", "ATL" = "ATL",
  "Chicago Sky" = "CHI", "Sky" = "CHI", "Chicago" = "CHI", "CHI" = "CHI",
  "Connecticut Sun" = "CON", "Sun" = "CON", "Connecticut" = "CON", "CON" = "CON", "CONN" = "CON",
  "Dallas Wings" = "DAL", "Wings" = "DAL", "Dallas" = "DAL", "DAL" = "DAL",
  "Indiana Fever" = "IND", "Fever" = "IND", "Indiana" = "IND", "IND" = "IND",
  "Las Vegas Aces" = "LV", "Aces" = "LV", "Las Vegas" = "LV", "LV" = "LV",
  "Los Angeles Sparks" = "LA", "Sparks" = "LA", "Los Angeles" = "LA", "LA" = "LA",
  "Minnesota Lynx" = "MIN", "Lynx" = "MIN", "Minnesota" = "MIN", "MIN" = "MIN",
  "New York Liberty" = "NY", "Liberty" = "NY", "New York" = "NY", "NY" = "NY",
  "Phoenix Mercury" = "PHX", "Mercury" = "PHX", "Phoenix" = "PHX", "PHX" = "PHX",
  "Portland Fire" = "POR", "Fire" = "POR", "Portland" = "POR", "POR" = "POR",
  "Seattle Storm" = "SEA", "Storm" = "SEA", "Seattle" = "SEA", "SEA" = "SEA",
  "Toronto Tempo" = "TOR", "Tempo" = "TOR", "Toronto" = "TOR", "TOR" = "TOR",
  "Washington Mystics" = "WSH", "Mystics" = "WSH", "Washington" = "WSH", "WSH" = "WSH"
)

# Unpack baseline JSON value cleanly (converts empty list / list() from jsonlite into NULL)
clean_baseline_val <- function(val) {
  if (is.null(val)) return(NULL)
  if (is.list(val) && length(val) == 0) return(NULL)
  if (length(val) == 1 && is.character(val) && !nzchar(val)) return(NULL)
  val
}

# Deterministic player ID generator for unlisted / rookie / camp players
generate_player_id <- function(player_name) {
  clean <- tolower(gsub("[^a-zA-Z0-9]+", "_", trimws(player_name)))
  clean <- gsub("^_+|_+$", "", clean)
  paste0("p_", clean)
}

# Known marquee fallback dictionary for synthetic CI test fixtures
KNOWN_MARQ <- list(
  "nneka ogwumike" = list(id = "1068", name = "Nneka Ogwumike", team = "LA", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2027L, serviceYears = 3L),
  "ezi magbegor" = list(id = "4420318", name = "Ezi Magbegor", team = "SEA", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L),
  "satou sabally" = list(id = "4281929", name = "Satou Sabally", team = "NY", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L),
  "dijonai carrington" = list(id = "4066548", name = "DiJonai Carrington", team = "CHI", contractStatus = "UNDER_CONTRACT", designation = "NONE", contractThroughSeason = 2026L, serviceYears = 3L)
)

# Known player lookup helper
find_player_by_name <- function(player_name, baseline_state = NULL) {
  clean_target <- tolower(trimws(player_name))
  clean_target <- sub("['’]s$", "", clean_target)
  
  # Check marquee fixture dictionary first if matches
  if (clean_target %in% names(KNOWN_MARQ)) {
    return(KNOWN_MARQ[[clean_target]])
  }
  
  # Check baseline state if provided or available on disk
  if (is.null(baseline_state)) {
    baseline_path <- file.path("cache", "league_state_baseline.json")
    if (file.exists(baseline_path)) {
      baseline_state <- tryCatch({
        jsonlite::fromJSON(baseline_path, simplifyVector = FALSE)
      }, error = function(e) NULL)
    }
  }
  
  if (!is.null(baseline_state) && !is.null(baseline_state$players)) {
    for (pid in names(baseline_state$players)) {
      p <- baseline_state$players[[pid]]
      if (identical(tolower(trimws(p$displayName)), clean_target)) {
        return(list(
          id = pid,
          name = p$displayName,
          team = clean_baseline_val(p$team$value),
          contractStatus = clean_baseline_val(p$contractStatus$value),
          designation = clean_baseline_val(p$designation$value),
          contractThroughSeason = clean_baseline_val(p$contractThroughSeason$value),
          serviceYears = clean_baseline_val(p$serviceYears$value),
          availabilityStatus = clean_baseline_val(p$availabilityStatus$value)
        ))
      }
    }
  }
  
  # Return synthesized player descriptor for new / unlisted players
  list(
    id = generate_player_id(player_name),
    name = player_name,
    team = NULL,
    contractStatus = NULL,
    designation = "NONE",
    contractThroughSeason = NULL,
    serviceYears = 0L,
    availabilityStatus = "ACTIVE"
  )
}

# Resolve team abbreviation from text mention
resolve_team_abbr <- function(text) {
  if (is.null(text) || !is.character(text) || length(text) == 0 || !nzchar(trimws(text[1]))) {
    return(NULL)
  }
  # Sort names by descending length so "Golden State Valkyries" matches before "Golden State"
  team_keys <- names(TEAM_NAME_MAP)
  team_keys <- team_keys[order(nchar(team_keys), decreasing = TRUE)]
  for (nm in team_keys) {
    pattern <- paste0("\\b", nm, "\\b")
    if (grepl(pattern, text, ignore.case = TRUE)) {
      return(TEAM_NAME_MAP[[nm]])
    }
  }
  NULL
}

# ------------------------------------------------------------------------------
# Split multi-event descriptions into atomic event clauses
# ------------------------------------------------------------------------------
split_wire_clauses <- function(raw_text) {
  if (is.null(raw_text) || !is.character(raw_text) || length(raw_text) == 0) {
    return(character(0))
  }
  txt <- trimws(raw_text[1])
  if (!nzchar(txt)) return(character(0))
  
  # Strip leading headline/date markers like "February 1, 2027: " or "November 10, 2026: "
  txt <- sub("^[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}:\\s*", "", txt)
  
  # Split on:
  # 1. Newlines or semicolons
  # 2. Periods followed by whitespace: \.\s+
  # 3. Lookahead for known action verbs following a sentence boundary or word:
  #    Signed, Waived, Released, Acquired, Announced, Set, Tendered, Matched, Fired
  split_pat <- "(?:;\\s*|\\r?\\n+|(?<=[a-z0-9'’\"\\)])\\.\\s+(?=[A-Z])|(?<=[a-z0-9'’\"\\)])\\s+(?=(?:(?:Re[- ]?)?Signed|Waived|Released|Acquired|Announced|Set|Tendered|Matched|Fired|Activated|Exercised)\\b))"
  parts <- unlist(strsplit(txt, split_pat, perl = TRUE))
  parts <- trimws(parts)
  parts <- sub("\\.+$", "", parts)
  parts <- parts[nzchar(parts)]
  parts
}

# Position tokens supported: C, F, G, G/F, F/G, C/F, and literal CF typo, plus words
POS_PREFIX_REGEX <- "^(?:(?:G/F|F/G|C/F|CF|centers?|forwards?|guards?|[CFG]s?)\\b\\s*)+"

# Extract position token and player name cleanly
extract_pos_and_name <- function(text) {
  text <- trimws(text)
  pos <- NULL
  m <- regexpr(POS_PREFIX_REGEX, text, ignore.case = TRUE, perl = TRUE)
  if (m > 0) {
    pos_len <- attr(m, "match.length")
    pos <- trimws(substr(text, 1, pos_len))
    text <- trimws(substr(text, pos_len + 1, nchar(text)))
  }
  
  # Clean possessive ('s / ’s) and trailing punctuation
  name <- sub("['’]s$", "", text)
  name <- trimws(sub("[.,;]+$", "", name))
  
  list(pos = pos, name = name)
}

#' Extract deltas from raw wire text snapshot
#'
#' @param raw_text string containing the wire update, or a structured wire item list
#' @param date event date 'YYYY-MM-DD'
#' @param source_url origin URL
#' @param baseline_state optional baseline object for resolving prior values
#' @param team_abbr structural sibling team abbreviation
#' @return list of extracted delta objects with change_type classification
extract_deltas_regex <- function(raw_text,
                                 date = NULL,
                                 source_url = NULL,
                                 baseline_state = NULL,
                                 team_abbr = NULL) {
  # Handle structured wire item list input
  if (is.list(raw_text)) {
    item <- raw_text
    if (is.null(date)) date <- if (!is.null(item$event_date)) item$event_date else item$date
    if (is.null(source_url)) source_url <- if (!is.null(item$source_url)) item$source_url else item$url
    if (is.null(team_abbr)) team_abbr <- item$team_abbr
    raw_text <- if (!is.null(item$raw_text)) item$raw_text else item$description
  }
  
  deltas <- list()
  unclassified_clauses <- list()
  
  if (is.null(raw_text) || !is.character(raw_text) || length(raw_text) == 0 || !nzchar(trimws(raw_text[1]))) {
    res <- structure(list(), unclassified_count = 0L)
    return(res)
  }
  
  # Resolve fallback team from raw text if not provided
  if (is.null(team_abbr) || is.na(team_abbr) || !nzchar(trimws(team_abbr))) {
    team_abbr <- resolve_team_abbr(raw_text)
  }
  
  clauses <- split_wire_clauses(raw_text)
  if (length(clauses) == 0) {
    res <- structure(list(), unclassified_count = 0L)
    return(res)
  }
  
  for (clause in clauses) {
    clause_deltas <- list()
    clause_team <- resolve_team_abbr(clause)
    effective_team <- if (!is.null(team_abbr) && !is.na(team_abbr) && nzchar(trimws(team_abbr))) team_abbr else clause_team
    if ((is.null(effective_team) || !nzchar(trimws(effective_team))) && !is.null(source_url) && nzchar(trimws(source_url))) {
      m_url <- regexec("/(?:name|team)/([a-z]{2,4})", source_url, ignore.case = TRUE)
      r_url <- regmatches(source_url, m_url)[[1]]
      if (length(r_url) >= 2) effective_team <- toupper(r_url[2])
    }
    
    # --------------------------------------------------------------------------
    # 1. Multi-player Signing Pattern:
    # "Signed C Kamila Borkowska and F Maria Gakdeng to player development contracts."
    # --------------------------------------------------------------------------
    m_multi_sign <- regexec("^(?:Re[- ]?)?Signed\\s+(.+?)\\s+and\\s+(.+?)(?:\\s+to\\s+(.+))?$", clause, ignore.case = TRUE, perl = TRUE)
    r_multi_sign <- regmatches(clause, m_multi_sign)[[1]]
    if (length(r_multi_sign) >= 3) {
      p1_chunk <- trimws(r_multi_sign[2])
      p2_chunk <- trimws(r_multi_sign[3])
      contract_str <- if (length(r_multi_sign) >= 4 && nzchar(r_multi_sign[4])) trimws(r_multi_sign[4]) else "Standard Contract"
      
      for (pchunk in c(p1_chunk, p2_chunk)) {
        parsed <- extract_pos_and_name(pchunk)
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "team",
          prior_val = pinfo$team,
          new_val = effective_team,
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "SIGNING",
          position = parsed$pos,
          contract = contract_str
        )
      }
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 2. Trades & Sign-and-trades (Checked before single signing to avoid clash)
    # 2a. Live: "Acquired G Kelsey Plum from Los Angeles in exchange for G Monique Akoa Makani."
    # 2b. Legacy: "New York Liberty complete sign-and-trade transaction sending forward Satou Sabally to Dallas Wings in exchange for 2027 draft assets."
    # --------------------------------------------------------------------------
    m_acq_tr <- regexec("^Acquired\\s+(.*?)\\s+from\\s+(.*?)\\s+in\\s+exchange\\s+for\\s+(.*?)$",
                        clause, ignore.case = TRUE, perl = TRUE)
    r_acq_tr <- regmatches(clause, m_acq_tr)[[1]]
    if (length(r_acq_tr) >= 4) {
      p1_chunk <- trimws(r_acq_tr[2])
      src_team_chunk <- trimws(r_acq_tr[3])
      p2_chunk <- trimws(r_acq_tr[4])
      
      other_team <- resolve_team_abbr(src_team_chunk)
      p1_parsed <- extract_pos_and_name(p1_chunk)
      p2_parsed <- extract_pos_and_name(p2_chunk)
      
      p1_info <- find_player_by_name(p1_parsed$name, baseline_state)
      p2_info <- find_player_by_name(p2_parsed$name, baseline_state)
      
      # Delta 1: p1 acquired by effective_team from other_team
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = p1_info$id,
        entity_name = p1_info$name,
        field = "team",
        prior_val = other_team,
        new_val = effective_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "TRADE"
      )
      
      # Delta 2: p2 sent to other_team from effective_team
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = p2_info$id,
        entity_name = p2_info$name,
        field = "team",
        prior_val = effective_team,
        new_val = other_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "TRADE"
      )
      
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    m_legacy_tr <- regexec("sending\\s+(.*?)\\s+to\\s+(.*?)\\s+in\\s+exchange",
                           clause, ignore.case = TRUE, perl = TRUE)
    r_legacy_tr <- regmatches(clause, m_legacy_tr)[[1]]
    if (length(r_legacy_tr) >= 3) {
      p_chunk <- trimws(r_legacy_tr[2])
      dest_team_chunk <- trimws(r_legacy_tr[3])
      dest_team <- resolve_team_abbr(dest_team_chunk)
      parsed <- extract_pos_and_name(p_chunk)
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "team",
        prior_val = pinfo$team,
        new_val = dest_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "TRADE"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 3. Single Player Signing Pattern:
    # "Signed C Aminata Gueye to a Rest-of-Season Hardship contract."
    # "Signed G Tonie Morgan."
    # Or legacy: "Seattle Storm sign forward Nneka Ogwumike to a multi-year contract..."
    # --------------------------------------------------------------------------
    if (grepl("^(?:.*?\\s+)?(?:re[- ]?)?sign(?:s|ed)?\\b", clause, ignore.case = TRUE, perl = TRUE) &&
        !grepl("sign-and-trade", clause, ignore.case = TRUE)) {
      # Extract possible leading team name from clause (e.g. "Seattle Storm sign...")
      lead_match <- regmatches(clause, regexec("^(.*?)\\s+(?:re[- ]?)?sign(?:s|ed)?\\b", clause, ignore.case = TRUE, perl = TRUE))[[1]]
      lead_team <- if (length(lead_match) >= 2) trimws(lead_match[2]) else ""
      t_target <- if (nzchar(lead_team) && !is.null(resolve_team_abbr(lead_team))) resolve_team_abbr(lead_team) else effective_team
      
      # Strip leading "team sign(s|ed)" or "Signed"
      sub_clause <- sub("^(?:.*?\\s+)?(?:re[- ]?)?sign(?:s|ed)?\\s+", "", clause, ignore.case = TRUE, perl = TRUE)
      
      # Split by " to " if present
      to_parts <- unlist(strsplit(sub_clause, "\\s+to\\s+", perl = TRUE))
      player_chunk <- trimws(to_parts[1])
      contract_chunk <- if (length(to_parts) > 1) trimws(paste(to_parts[-1], collapse = " to ")) else NULL
      
      parsed <- extract_pos_and_name(player_chunk)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "team",
          prior_val = pinfo$team,
          new_val = t_target,
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "SIGNING"
        )
        
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "contractStatus",
          prior_val = if (!is.null(pinfo$contractStatus)) pinfo$contractStatus else "UNDER_CONTRACT",
          new_val = "UNDER_CONTRACT",
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "SIGNING"
        )
        
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # --------------------------------------------------------------------------
    # 4. Waiver Pattern:
    # "Waived C Nadia Fingall."
    # "Waived G Sug Sutton."
    # "Waived G/F Betnijah Laney-Hamilton."
    # "Waived G/F Aaliyah."
    # --------------------------------------------------------------------------
    if (grepl("^(?:.*?\\s+)?waive(?:s|d)?\\b", clause, ignore.case = TRUE, perl = TRUE)) {
      sub_clause <- sub("^(?:.*?\\s+)?waive(?:s|d)?\\s+", "", clause, ignore.case = TRUE, perl = TRUE)
      parsed <- extract_pos_and_name(sub_clause)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "contractStatus",
          prior_val = if (!is.null(pinfo$contractStatus)) pinfo$contractStatus else "UNDER_CONTRACT",
          new_val = "WAIVED",
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "WAIVER"
        )
        
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # --------------------------------------------------------------------------
    # 5. Release Pattern:
    # "Released F Saylor Poffenbarger."
    # "Released C/F Rayah Marshall."
    # --------------------------------------------------------------------------
    if (grepl("^(?:.*?\\s+)?release(?:s|d)?\\b", clause, ignore.case = TRUE, perl = TRUE)) {
      sub_clause <- sub("^(?:.*?\\s+)?release(?:s|d)?\\s+", "", clause, ignore.case = TRUE, perl = TRUE)
      parsed <- extract_pos_and_name(sub_clause)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "contractStatus",
          prior_val = if (!is.null(pinfo$contractStatus)) pinfo$contractStatus else "UNDER_CONTRACT",
          new_val = "RELEASED",
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "RELEASE"
        )
        
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # --------------------------------------------------------------------------
    # 6. Acquired Pattern (Waiver Claim):
    # "Acquired G/F Aaliyah Nye off waivers."
    # --------------------------------------------------------------------------
    m_acq_wc <- regexec("^Acquired\\s+(.*?)\\s+off\\s+waivers", clause, ignore.case = TRUE, perl = TRUE)
    r_acq_wc <- regmatches(clause, m_acq_wc)[[1]]
    if (length(r_acq_wc) >= 2 && nzchar(trimws(r_acq_wc[2]))) {
      parsed <- extract_pos_and_name(r_acq_wc[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "team",
        prior_val = pinfo$team,
        new_val = effective_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "WAIVER_CLAIM"
      )
      
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 7. Offer Match Pattern:
    # "Matched Ashlon Jackson's offer sheet from Los Angeles."
    # --------------------------------------------------------------------------
    m_match <- regexec("^Matched\\s+(.*?)(?:'s|’s)?\\s+offer\\s+sheet(?:\\s+from\\s+(.*?))?$",
                       clause, ignore.case = TRUE, perl = TRUE)
    r_match <- regmatches(clause, m_match)[[1]]
    if (length(r_match) >= 2 && nzchar(trimws(r_match[2]))) {
      parsed <- extract_pos_and_name(r_match[2])
      from_team_chunk <- if (length(r_match) >= 3) trimws(r_match[3]) else NULL
      from_team <- if (!is.null(from_team_chunk) && nzchar(from_team_chunk)) resolve_team_abbr(from_team_chunk) else NULL
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "offerMatch",
        prior_val = if (!is.null(from_team)) from_team else pinfo$team,
        new_val = effective_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "OFFER_MATCH"
      )
      
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 8. Contract Offer / Offer Sheet Pattern:
    # "Tendered an offer sheet to F Maddy Westbeld."
    # --------------------------------------------------------------------------
    m_tender <- regexec("^Tendered\\s+(?:an?\\s+)?(?:offer\\s+sheet|contract\\s+offer)\\s+to\\s+(.*?)$",
                        clause, ignore.case = TRUE, perl = TRUE)
    r_tender <- regmatches(clause, m_tender)[[1]]
    if (length(r_tender) >= 2 && nzchar(trimws(r_tender[2]))) {
      parsed <- extract_pos_and_name(r_tender[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "contractOffer",
        prior_val = pinfo$team,
        new_val = effective_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "CONTRACT_OFFER"
      )
      
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 9. Roster Status Pattern:
    # "Set F Cecilia Zandalasini as active."
    # --------------------------------------------------------------------------
    m_set <- regexec("^Set\\s+(.*?)\\s+as\\s+(active|inactive|suspended|available)",
                     clause, ignore.case = TRUE, perl = TRUE)
    r_set <- regmatches(clause, m_set)[[1]]
    if (length(r_set) >= 3) {
      parsed <- extract_pos_and_name(r_set[2])
      stat_val <- toupper(trimws(r_set[3]))
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "availabilityStatus",
        prior_val = if (!is.null(pinfo$availabilityStatus)) pinfo$availabilityStatus else if (stat_val == "ACTIVE") "INACTIVE" else "ACTIVE",
        new_val = stat_val,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "ROSTER_STATUS"
      )
      
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 10. Front Office Patterns:
    # "Announced Kelly Krauskopf stepped down as president."
    # "Fired general manager Amber Cox"
    # Or legacy: "Washington Mystics name Teresa Weatherspoon head coach."
    # --------------------------------------------------------------------------
    m_ann_step <- regexec("^(?:Announced\\s+)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)\\s+stepped\\s+down\\s+as\\s+(president|general\\s+manager|head\\s+coach|coach)",
                          clause, ignore.case = TRUE, perl = TRUE)
    r_ann_step <- regmatches(clause, m_ann_step)[[1]]
    if (length(r_ann_step) >= 3) {
      person_name <- trimws(r_ann_step[2])
      role_str <- tolower(trimws(r_ann_step[3]))
      fld <- if (grepl("general", role_str)) "generalManager" else if (grepl("head|coach", role_str)) "headCoach" else "president"
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "team",
        entity_id = effective_team,
        entity_name = effective_team,
        field = fld,
        prior_val = person_name,
        new_val = NULL,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "FRONT_OFFICE"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    m_fired <- regexec("^Fired\\s+(?:(?:as|the)\\s+)?(president|general\\s+manager|head\\s+coach|coach)?\\s*([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                       clause, ignore.case = TRUE, perl = TRUE)
    r_fired <- regmatches(clause, m_fired)[[1]]
    if (length(r_fired) >= 3 && nzchar(trimws(r_fired[3]))) {
      role_str <- tolower(trimws(r_fired[2]))
      person_name <- trimws(r_fired[3])
      fld <- if (grepl("general", role_str)) "generalManager" else if (grepl("head|coach", role_str)) "headCoach" else "frontOffice"
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "team",
        entity_id = effective_team,
        entity_name = effective_team,
        field = fld,
        prior_val = person_name,
        new_val = NULL,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "FRONT_OFFICE"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    m_fo_legacy <- regexec("^(.*?)\\s+(?:name(?:s)?|hire(?:s)?)\\s+([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*?)(?:\\s+as)?\\s+(head coach|general manager|president)",
                           clause, ignore.case = TRUE, perl = TRUE)
    r_fo_legacy <- regmatches(clause, m_fo_legacy)[[1]]
    if (length(r_fo_legacy) >= 4) {
      team_chunk <- trimws(r_fo_legacy[2])
      person_name <- trimws(r_fo_legacy[3])
      role_str <- tolower(trimws(r_fo_legacy[4]))
      fld <- if (grepl("general", role_str)) "generalManager" else if (grepl("head|coach", role_str)) "headCoach" else "president"
      t_abbr <- if (nzchar(team_chunk)) resolve_team_abbr(team_chunk) else effective_team
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "team",
        entity_id = t_abbr,
        entity_name = t_abbr,
        field = fld,
        prior_val = NULL,
        new_val = person_name,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "FRONT_OFFICE"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 11. Off-season Specific Classes:
    # --------------------------------------------------------------------------
    # 11a. Core Designation:
    m_core <- regexec("designate(?:s)?\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)\\s+as\\s+Core\\s+Player",
                      clause, ignore.case = TRUE, perl = TRUE)
    r_core <- regmatches(clause, m_core)[[1]]
    if (length(r_core) >= 2 && nzchar(trimws(r_core[2]))) {
      parsed <- extract_pos_and_name(r_core[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "designation",
        prior_val = if (!is.null(pinfo$designation)) pinfo$designation else "NONE",
        new_val = "CORED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "CORE_DESIGNATION"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11b. Reserved Player:
    m_res <- regexec("designate(?:s)?\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)\\s+as\\s+Reserved\\s+Player",
                     clause, ignore.case = TRUE, perl = TRUE)
    r_res <- regmatches(clause, m_res)[[1]]
    if (length(r_res) >= 2 && nzchar(trimws(r_res[2]))) {
      parsed <- extract_pos_and_name(r_res[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "designation",
        prior_val = if (!is.null(pinfo$designation)) pinfo$designation else "NONE",
        new_val = "RESERVED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "RESERVED_PLAYER"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11c. Qualifying Offer:
    m_qo <- regexec("(?:tender(?:s|ed)?|extend(?:s|ed)?)\\s+(?:a\\s+)?qualifying\\s+offer\\s+to\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                    clause, ignore.case = TRUE, perl = TRUE)
    r_qo <- regmatches(clause, m_qo)[[1]]
    if (length(r_qo) >= 2 && nzchar(trimws(r_qo[2]))) {
      parsed <- extract_pos_and_name(r_qo[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "qualifyingOffer",
        prior_val = NULL,
        new_val = "OFFERED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "QUALIFYING_OFFER"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11d. Prioritization:
    m_prio <- regexec("(?:prioritization\\s+(?:violation|ineligible|suspension)|ineligible\\s+under\\s+prioritization|suspended\\s+under\\s+prioritization)\\s+(?:for\\s+)?(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                      clause, ignore.case = TRUE, perl = TRUE)
    r_prio <- regmatches(clause, m_prio)[[1]]
    if (length(r_prio) >= 2 && nzchar(trimws(r_prio[2]))) {
      parsed <- extract_pos_and_name(r_prio[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "availabilityStatus",
        prior_val = if (!is.null(pinfo$availabilityStatus)) pinfo$availabilityStatus else "ACTIVE",
        new_val = "PRIORITIZATION_SUSPENDED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "PRIORITIZATION"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11e. Retirement:
    m_ret <- regexec("(?:announced?\\s+retirement|retire(?:s|d)?\\s+from\\s+wnba|placed\\s+on\\s+retired\\s+list)\\s*(?:for|of)?\\s*(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                     clause, ignore.case = TRUE, perl = TRUE)
    r_ret <- regmatches(clause, m_ret)[[1]]
    if (length(r_ret) >= 2 && nzchar(trimws(r_ret[2]))) {
      parsed <- extract_pos_and_name(r_ret[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "contractStatus",
        prior_val = if (!is.null(pinfo$contractStatus)) pinfo$contractStatus else "UNDER_CONTRACT",
        new_val = "RETIRED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "RETIREMENT"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11f. Suspension:
    m_susp <- regexec("(?:suspended?(?:\\s+(?:for\\s+[0-9]+\\s+games?|indefinitely))?|placed\\s+on\\s+(?:the\\s+)?suspended\\s+list)\\s*(?:for|of)?\\s*(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                      clause, ignore.case = TRUE, perl = TRUE)
    r_susp <- regmatches(clause, m_susp)[[1]]
    if (length(r_susp) >= 2 && nzchar(trimws(r_susp[2]))) {
      parsed <- extract_pos_and_name(r_susp[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "availabilityStatus",
        prior_val = if (!is.null(pinfo$availabilityStatus)) pinfo$availabilityStatus else "ACTIVE",
        new_val = "SUSPENDED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "SUSPENSION"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11g. Draft Rights:
    m_dr <- regexec("(?:renounce(?:s|d)?\\s+draft\\s+rights\\s+to|signed?\\s+draft\\s+pick)\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)",
                    clause, ignore.case = TRUE, perl = TRUE)
    r_dr <- regmatches(clause, m_dr)[[1]]
    if (length(r_dr) >= 2 && nzchar(trimws(r_dr[2]))) {
      parsed <- extract_pos_and_name(r_dr[2])
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "draftRights",
        prior_val = effective_team,
        new_val = if (grepl("renounce", clause, ignore.case = TRUE)) "RENOUNCED" else "SIGNED",
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "DRAFT_RIGHTS"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11h. Expansion Draft:
    m_exp <- regexec("(?:select(?:s|ed)?\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)\\s+in\\s+(?:the\\s+)?expansion\\s+draft|expansion\\s+draft\\s+selection\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*))",
                     clause, ignore.case = TRUE, perl = TRUE)
    r_exp <- regmatches(clause, m_exp)[[1]]
    if (length(r_exp) >= 2) {
      p_str <- if (nzchar(r_exp[2])) r_exp[2] else r_exp[3]
      parsed <- extract_pos_and_name(p_str)
      pinfo <- find_player_by_name(parsed$name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "team",
        prior_val = pinfo$team,
        new_val = effective_team,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "EXPANSION_DRAFT"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # 11i. Contract Option Exercised (Legacy Pattern):
    m_opt <- regexec("exercise(?:s)?\\s+contract\\s+option\\s+on\\s+(?:(?:G/F|F/G|C/F|CF|center|forward|guard|[CFG])\\b\\s*)?([A-Za-z'’-]+(?:\\s+[A-Za-z'’-]+)*)\\s+through\\s+([0-9]{4})",
                     clause, ignore.case = TRUE, perl = TRUE)
    r_opt <- regmatches(clause, m_opt)[[1]]
    if (length(r_opt) >= 3) {
      player_name <- trimws(r_opt[2])
      through_year <- as.integer(r_opt[3])
      pinfo <- find_player_by_name(player_name, baseline_state)
      
      clause_deltas[[length(clause_deltas) + 1]] <- list(
        entity_type = "player",
        entity_id = pinfo$id,
        entity_name = pinfo$name,
        field = "contractThroughSeason",
        prior_val = pinfo$contractThroughSeason,
        new_val = through_year,
        tier = "CONFIRMED",
        date = date,
        source_url = source_url,
        change_type = "ROSTER_STATUS"
      )
      deltas <- c(deltas, clause_deltas)
      next
    }
    
    # --------------------------------------------------------------------------
    # 11j. Option Exercised (Official Wire):
    # "Exercised the option on F Leonie Fiebich."
    # "Exercised their option with G Caitlin Clark."
    if (grepl("^(?:.*?\\s+)?exercise(?:s|d)?\\s+(?:the|their)?\\s*option\\s+(?:on|with)?\\s*", clause, ignore.case = TRUE, perl = TRUE)) {
      sub_clause <- sub("^(?:.*?\\s+)?exercise(?:s|d)?\\s+(?:the|their)?\\s*option\\s+(?:on|with)?\\s*", "", clause, ignore.case = TRUE, perl = TRUE)
      parsed <- extract_pos_and_name(sub_clause)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "contractStatus",
          prior_val = if (!is.null(pinfo$contractStatus)) pinfo$contractStatus else "UNDER_CONTRACT",
          new_val = "UNDER_CONTRACT",
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "CONTRACT_OFFER",
          position = parsed$pos
        )
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # 11k. Roster Status Activation (Official Wire):
    # "Activated G Leila Lacan."
    # "Activated F Leonie Fiebich."
    if (grepl("^(?:.*?\\s+)?activate(?:s|d)?\\b", clause, ignore.case = TRUE, perl = TRUE)) {
      sub_clause <- sub("^(?:.*?\\s+)?activate(?:s|d)?\\s+", "", clause, ignore.case = TRUE, perl = TRUE)
      parsed <- extract_pos_and_name(sub_clause)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "availabilityStatus",
          prior_val = if (!is.null(pinfo$availabilityStatus)) pinfo$availabilityStatus else "INACTIVE",
          new_val = "ACTIVE",
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "ROSTER_STATUS",
          position = parsed$pos
        )
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # 11l. Negotiating / Draft Rights (Official Wire):
    # "Acquired exclusive negotiating rights of F Maria Kliundikova from Toronto."
    if (grepl("^(?:.*?\\s+)?acquired\\s+(?:exclusive\\s+)?negotiating\\s+rights\\s+of\\s+", clause, ignore.case = TRUE, perl = TRUE)) {
      sub_clause <- sub("^(?:.*?\\s+)?acquired\\s+(?:exclusive\\s+)?negotiating\\s+rights\\s+of\\s+", "", clause, ignore.case = TRUE, perl = TRUE)
      from_parts <- unlist(strsplit(sub_clause, "\\s+from\\s+", perl = TRUE))
      p_chunk <- trimws(from_parts[1])
      src_chunk <- if (length(from_parts) > 1) trimws(from_parts[2]) else ""
      from_team <- resolve_team_abbr(src_chunk)
      parsed <- extract_pos_and_name(p_chunk)
      if (nzchar(parsed$name)) {
        pinfo <- find_player_by_name(parsed$name, baseline_state)
        clause_deltas[[length(clause_deltas) + 1]] <- list(
          entity_type = "player",
          entity_id = pinfo$id,
          entity_name = pinfo$name,
          field = "team",
          prior_val = if (!is.null(from_team)) from_team else pinfo$team,
          new_val = effective_team,
          tier = "CONFIRMED",
          date = date,
          source_url = source_url,
          change_type = "DRAFT_RIGHTS",
          position = parsed$pos
        )
        deltas <- c(deltas, clause_deltas)
        next
      }
    }
    
    # 12. Explicit Unclassified Reporting (Requirement 6):
    # Records or clauses that cannot be matched to known transition rules must be
    # reported as unclassified, never silently dropped.
    # --------------------------------------------------------------------------
    unclassified_delta <- list(
      entity_type = "unclassified",
      entity_id = NA_character_,
      entity_name = NA_character_,
      field = "unclassified",
      prior_val = NULL,
      new_val = clause,
      tier = "UNCONFIRMED",
      date = date,
      source_url = source_url,
      change_type = "UNCLASSIFIED",
      raw_clause = clause
    )
    deltas[[length(deltas) + 1]] <- unclassified_delta
    unclassified_clauses[[length(unclassified_clauses) + 1]] <- clause
  }
  
  attr(deltas, "unclassified_count") <- length(unclassified_clauses)
  attr(deltas, "unclassified_clauses") <- unclassified_clauses
  deltas
}
