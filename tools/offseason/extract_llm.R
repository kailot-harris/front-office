# ==============================================================================
# tools/offseason/extract_llm.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Layer B Semantic LLM Extraction Engine
# Path: tools/offseason/extract_llm.R
#
# Semantic LLM extraction engine for complex multi-party trades, cash
# considerations, and PTBNL structures.
# Supports mock/offline deterministic mode for CI test harnesses as well as
# API invocation when keys are available.
#
# Evaluates semantic key tuples: (entity_id, field, tier)
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
      stop(sprintf("extract_llm.R: cannot locate repo root (no config.R at or above '%s')", start))
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
      stop(sprintf("Zero-betting policy violation: found '%s' in LLM extraction text", pattern))
    }
  }
}

# Semantic semantic parsing for complex text structures
# Handles:
# 1. Multi-player trades: "Team A traded Player 1 and Player 2 to Team B for Player 3, cash considerations, and a PTBNL."
# 2. Rumors and reported claims: "Sources: Team A discussing trade package involving Player 1 with Team B."
# 3. Contract extension rumors: "Beat report: Player 1 nearing guaranteed extension with Team A."
OLLAMA_HOST <- Sys.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")
# qwen3.5:4b, not gemma4:12b: on CPU-only Ollama, Ollama's grammar-constrained
# `format` JSON mode never emits a stop token for either model (runs away
# generating tokens until the client timeout), and gemma4:12b's plain
# generation is too slow (~1 tok/s decode) to be usable here. qwen3.5:4b with
# `think = FALSE` and plain-JSON prompting (no `format`) returns in seconds.
OLLAMA_MODEL <- Sys.getenv("OLLAMA_MODEL", "qwen3.5:4b")

#' Extract the first top-level {...} JSON object from LLM free-text output
extract_json_object_mlb <- function(text) {
  start <- regexpr("\\{", text)[1]
  if (start == -1) stop("No JSON object found in LLM response")
  depth <- 0
  for (i in start:nchar(text)) {
    ch <- substr(text, i, i)
    if (ch == "{") depth <- depth + 1
    if (ch == "}") depth <- depth - 1
    if (depth == 0) return(substr(text, start, i))
  }
  stop("Unterminated JSON object in LLM response")
}

MLB_LLM_SYSTEM_PROMPT <- "You are an expert MLB front-office intelligence extraction engine.
Extract state transition deltas from unstructured text (trade wires, press releases, beat
reporting) covering multi-party trades, cash considerations, and PTBNL structures.
For each candidate transition output a structured JSON object with:
- entity_id: player_id or team abbreviation from the provided roster baseline
- field: attribute mutated (e.g. 'team', 'cbtPayrollCommitted', 'draftPicks2027')
- prior_val: prior value or null
- new_val: new value
- tier: 'CONFIRMED' (official wire/team announcement), 'REPORTED' (beat reporter claim), or 'SPECULATIVE' (rumor)
- notes: brief explanation of the transition
Respond with ONLY raw JSON, no markdown fences, no commentary, in the exact shape {\"deltas\": [...]}.
Never reference betting markets, odds, or sportsbooks."

#' Call local Ollama (qwen3.5:4b by default) for structured delta extraction
ollama_llm_extract_mlb <- function(raw_text, baseline, as_of_date, source_url) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("httr2 package required for live Ollama extraction")
  }
  user_prompt <- sprintf(
    "As of %s (source: %s), extract state transition deltas from this text:\n\n%s",
    as_of_date,
    if (is.null(source_url)) "unknown" else source_url,
    raw_text
  )
  resp <- httr2::request(paste0(OLLAMA_HOST, "/api/chat")) |>
    httr2::req_body_json(list(
      model = OLLAMA_MODEL,
      think = FALSE,
      messages = list(
        list(role = "system", content = MLB_LLM_SYSTEM_PROMPT),
        list(role = "user", content = user_prompt)
      ),
      options = list(num_ctx = 4096, num_predict = 800, temperature = 0),
      stream = FALSE
    )) |>
    httr2::req_timeout(90) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(resp)
  content <- body$message$content
  parsed <- jsonlite::fromJSON(extract_json_object_mlb(content), simplifyVector = FALSE)
  deltas <- parsed$deltas
  if (is.null(deltas)) deltas <- list()
  validate_zero_betting(vapply(deltas, function(d) paste(unlist(d), collapse = " "), character(1)))
  for (i in seq_along(deltas)) {
    deltas[[i]]$date <- as_of_date
    deltas[[i]]$source_url <- source_url
  }
  deltas
}

extract_llm_semantic <- function(raw_text, baseline, as_of_date = "2026-10-31", source_url = NULL, mock = TRUE) {
  validate_zero_betting(raw_text)

  if (!mock) {
    return(tryCatch({
      ollama_llm_extract_mlb(raw_text, baseline, as_of_date, source_url)
    }, error = function(e) {
      warning("Ollama LLM extraction failed, falling back to offline evaluator: ", e$message)
      extract_llm_semantic(raw_text, baseline, as_of_date, source_url, mock = TRUE)
    }))
  }

  if (mock) {
    # Offline deterministic semantic extractor
    deltas <- list()
    
    # 1. Trade detection (including cash considerations, PTBNL, and multi-player)
    if (grepl("\\btraded?\\b.+\\bto\\b.+\\bfor\\b", raw_text, ignore.case = TRUE)) {
      # Determine confidence tier: if text states "Sources:" or "Report:" -> REPORTED, else CONFIRMED
      tier <- if (grepl("^(?:Sources:|Report:|Rumor:)", raw_text, ignore.case = TRUE)) "REPORTED" else "CONFIRMED"
      
      parts <- regmatches(raw_text, regexec("(?:^.+?:\\s*)?(.+?)\\s+traded?\\s+(.+?)\\s+to\\s+(.+?)\\s+for\\s+(.+?)\\.?$", raw_text, ignore.case = TRUE))[[1]]
      if (length(parts) >= 5) {
        from_team_str <- parts[2]
        pkg1_str <- parts[3]
        to_team_str <- parts[4]
        pkg2_str <- parts[5]
        
        # Helper to extract team code
        source("tools/offseason/extract_regex.R")
        to_team <- resolve_team_abbr(to_team_str)
        from_team <- resolve_team_abbr(from_team_str)
        
        # Scan players in pkg1
        for (pid in names(baseline$players)) {
          dname <- baseline$players[[pid]]$displayName
          if (!is.null(dname) && nchar(dname) > 4 && grepl(dname, pkg1_str, fixed = TRUE)) {
            deltas[[length(deltas) + 1]] <- list(
              entity_id = pid,
              field = "team",
              prior_val = baseline$players[[pid]]$team$value,
              new_val = to_team,
              tier = tier,
              date = as_of_date,
              source_url = source_url,
              notes = "Trade acquisition via pkg1"
            )
          }
        }
        
        # Scan players in pkg2
        for (pid in names(baseline$players)) {
          dname <- baseline$players[[pid]]$displayName
          if (!is.null(dname) && nchar(dname) > 4 && grepl(dname, pkg2_str, fixed = TRUE)) {
            deltas[[length(deltas) + 1]] <- list(
              entity_id = pid,
              field = "team",
              prior_val = baseline$players[[pid]]$team$value,
              new_val = from_team,
              tier = tier,
              date = as_of_date,
              source_url = source_url,
              notes = "Trade acquisition via pkg2"
            )
          }
        }
        
        # Check cash considerations
        if (grepl("cash considerations|cash", pkg2_str, ignore.case = TRUE)) {
          deltas[[length(deltas) + 1]] <- list(
            entity_id = to_team,
            field = "cbtPayrollCommitted",
            prior_val = "COMMITTED_CASH",
            new_val = "CASH_CONSIDERATIONS_OUT",
            tier = tier,
            date = as_of_date,
            source_url = source_url,
            notes = "Cash considerations exchanged in trade"
          )
        }
        
        # Check PTBNL (player to be named later)
        if (grepl("player to be named later|ptbnl", pkg2_str, ignore.case = TRUE)) {
          deltas[[length(deltas) + 1]] <- list(
            entity_id = to_team,
            field = "draftPicks2027",
            prior_val = "UNRESOLVED_PTBNL",
            new_val = "PTBNL_PENDING",
            tier = tier,
            date = as_of_date,
            source_url = source_url,
            notes = "PTBNL obligation created"
          )
        }
      }
      return(deltas)
    }
    
    # 2. Rumor / reported discussion: "Sources: San Diego Padres in active discussions to trade Lucas Giolito to Baltimore Orioles."
    if (grepl("discussions?|rumor|targeting|interested in", raw_text, ignore.case = TRUE)) {
      tier <- "REPORTED"
      for (pid in names(baseline$players)) {
        dname <- baseline$players[[pid]]$displayName
        if (!is.null(dname) && nchar(dname) > 4 && grepl(dname, raw_text, fixed = TRUE)) {
          deltas[[length(deltas) + 1]] <- list(
            entity_id = pid,
            field = "team",
            prior_val = baseline$players[[pid]]$team$value,
            new_val = "PENDING_REPORTED_TRADE",
            tier = tier,
            date = as_of_date,
            source_url = source_url,
            notes = "Reported trade interest"
          )
        }
      }
      return(deltas)
    }
    
    # Fallback to standard regex
    source("tools/offseason/extract_regex.R")
    regex_res <- extract_regex_from_text(raw_text, baseline, as_of_date, source_url)
    return(regex_res)
  }
}
