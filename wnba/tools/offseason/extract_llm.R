# ==============================================================================
# extract_llm.R
# WNBA Offseason Dynamics Monitor — LLM Extraction Harness (Layer B / Phase 3)
#
# Formats prompt and structured JSON schema for LLM-based delta extraction.
# Parses LLM structured JSON output into candidate deltas with confidence tiers:
#   - Tier 1: CONFIRMED (Official transactions, filings, formal releases)
#   - Tier 2: REPORTED (Attributed beat reports, ESPN/Athletic rumors)
#   - Tier 3: SPECULATIVE (Linkage, trade speculation, player hints)
#
# Supports mock/offline testing mode to enable offline evaluation and scoring.
#
# Usage:
#   Rscript tools/offseason/extract_llm.R [--input=<file>] [--mock]
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

# LLM Extraction System Prompt defining structured delta schema
LLM_SYSTEM_PROMPT <- "You are an expert sports intelligence extraction engine for the WNBA Offseason Monitor.
Your task is to extract state transition deltas from unstructured text (transaction wires, press releases, beat reporting).
For each candidate transition, you must output a structured JSON object with:
- entity_type: 'player' or 'team'
- entity_id: player_id (e.g. '1068') or team_abbrev (e.g. 'SEA', 'CHI')
- entity_name: full human-readable name
- field: attribute mutated (e.g. 'team', 'contractStatus', 'designation', 'headCoach', 'generalManager', 'contractThroughSeason', 'tradeSpeculation')
- prior_val: prior value or null
- new_val: new value
- tier: 'CONFIRMED' (official wire/team announcement), 'REPORTED' (beat reporter claim), or 'SPECULATIVE' (trade rumor/speculation)
- confidence_score: numeric between 0.0 and 1.0
- rationale: brief explanation of attribution and evidence"

#' Generate Mock LLM structured response for benchmark / offline evaluation
mock_llm_extract <- function(raw_text, date = NULL, source_url = NULL, baseline_state = NULL) {
  warning("[MOCK MODE] mock_llm_extract invoked: returning synthetic offline evaluation deltas.", call. = FALSE)
  # Deterministic semantic parsing simulating LLM reasoning across tiers
  deltas <- list()
  
  # Check for Tier 2 reported claims
  # e.g., "Sources: Phoenix Mercury seeking veteran point guard in upcoming free agency."
  if (grepl("seeking veteran point guard", raw_text, ignore.case = TRUE) && grepl("Phoenix Mercury|PHX", raw_text, ignore.case = TRUE)) {
    deltas[[length(deltas) + 1]] <- list(
      entity_type = "team",
      entity_id = "PHX",
      entity_name = "Phoenix Mercury",
      field = "reportedTarget",
      prior_val = NULL,
      new_val = "Veteran point guard",
      tier = "REPORTED",
      confidence_score = 0.85,
      rationale = "Attributed beat report on positional target"
    )
    return(deltas)
  }
  
  # Check for Tier 3 speculative claims
  # e.g., "League chatter connects Chicago Sky to several potential frontcourt trades."
  if (grepl("chatter connects|trade speculation", raw_text, ignore.case = TRUE) && grepl("Chicago Sky|CHI", raw_text, ignore.case = TRUE)) {
    deltas[[length(deltas) + 1]] <- list(
      entity_type = "team",
      entity_id = "CHI",
      entity_name = "Chicago Sky",
      field = "tradeSpeculation",
      prior_val = NULL,
      new_val = "Frontcourt trade discussions",
      tier = "SPECULATIVE",
      confidence_score = 0.55,
      rationale = "General league chatter without formal confirmation"
    )
    return(deltas)
  }
  
  # Otherwise delegate to regex parser for confirmed deltas
  if (file.exists(file.path("tools", "offseason", "extract_regex.R"))) {
    if (!exists("extract_deltas_regex")) {
      source(file.path("tools", "offseason", "extract_regex.R"))
    }
    raw_deltas <- extract_deltas_regex(raw_text, date, source_url, baseline_state)
    for (d in raw_deltas) {
      d$confidence_score <- 0.99
      d$rationale <- "Official wire confirmed transaction"
      deltas[[length(deltas) + 1]] <- d
    }
  }
  
  deltas
}

OLLAMA_HOST <- Sys.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")
# qwen3.5:4b, not gemma4:12b: on CPU-only Ollama, Ollama's grammar-constrained
# `format` JSON mode never emits a stop token for either model (runs away
# generating tokens until the client timeout), and gemma4:12b's plain
# generation is too slow (~1 tok/s decode) to be usable here. qwen3.5:4b with
# `think = FALSE` and plain-JSON prompting (no `format`) returns in seconds.
OLLAMA_MODEL <- Sys.getenv("OLLAMA_MODEL", "qwen3.5:4b")

#' Extract the first top-level {...} JSON object from LLM free-text output
extract_json_object <- function(text) {
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

#' Call local Ollama (qwen3.5:4b by default) for structured delta extraction
ollama_llm_extract <- function(raw_text, date = NULL, source_url = NULL, baseline_state = NULL) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("httr2 package required for live Ollama extraction")
  }
  user_prompt <- sprintf(
    "Extract state transition deltas from the following text as of %s (source: %s).\nRespond with ONLY raw JSON, no markdown fences, no commentary, in the exact shape {\"deltas\": [...]}.\n\n%s",
    if (is.null(date)) "unknown date" else date,
    if (is.null(source_url)) "unknown" else source_url,
    raw_text
  )
  resp <- httr2::request(paste0(OLLAMA_HOST, "/api/chat")) |>
    httr2::req_body_json(list(
      model = OLLAMA_MODEL,
      think = FALSE,
      messages = list(
        list(role = "system", content = LLM_SYSTEM_PROMPT),
        list(role = "user", content = user_prompt)
      ),
      options = list(num_ctx = 4096, num_predict = 800, temperature = 0),
      stream = FALSE
    )) |>
    httr2::req_timeout(90) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(resp)
  content <- body$message$content
  parsed <- jsonlite::fromJSON(extract_json_object(content), simplifyVector = FALSE)
  deltas <- parsed$deltas
  if (is.null(deltas)) deltas <- list()
  deltas
}

# Alias for external callers expecting `extract_claims_mock`
extract_claims_mock <- mock_llm_extract

#' Extract deltas using LLM (or mock offline harness)
extract_deltas_llm <- function(raw_text,
                               date = NULL,
                               source_url = NULL,
                               baseline_state = NULL,
                               mock = FALSE,
                               api_key = Sys.getenv("GEMINI_API_KEY")) {
  if (isTRUE(mock)) {
    warning("[MOCK MODE] extract_deltas_llm running with mock = TRUE; outputs are synthetic offline evaluation deltas and must not be written to production artifacts.", call. = FALSE)
    return(mock_llm_extract(raw_text, date, source_url, baseline_state))
  }

  # Live mode: call local Ollama (qwen3.5:4b). Never fall back to synthetic mock
  # extraction in production mode; if the LLM backend is unreachable or errors,
  # log a warning and return an empty list.
  tryCatch({
    ollama_llm_extract(raw_text, date, source_url, baseline_state)
  }, error = function(e) {
    warning(
      "Live LLM extraction failed or no LLM backend reachable (mock = FALSE; refusing to fall back to synthetic mock extractor): ",
      e$message,
      call. = FALSE
    )
    list()
  })
}

#' Extract claims from normalized raw items (batch entrypoint, defaults mock = FALSE)
extract_claims_from_raw <- function(raw_items,
                                    mock = FALSE,
                                    baseline_state = NULL,
                                    api_key = Sys.getenv("GEMINI_API_KEY")) {
  if (isTRUE(mock)) {
    warning("[MOCK MODE] extract_claims_from_raw running with mock = TRUE; outputs are synthetic offline evaluation claims.", call. = FALSE)
  }
  if (is.null(baseline_state)) {
    baseline_path <- file.path("cache", "league_state_baseline.json")
    if (file.exists(baseline_path)) {
      baseline_state <- tryCatch(
        jsonlite::fromJSON(baseline_path, simplifyVector = FALSE),
        error = function(e) NULL
      )
    }
  }
  all_deltas <- list()
  for (item in raw_items) {
    txt <- if (is.list(item)) {
      if (!is.null(item$raw_text)) item$raw_text else if (!is.null(item$text)) item$text else ""
    } else {
      as.character(item)
    }
    dt <- if (is.list(item)) {
      if (!is.null(item$event_date)) item$event_date else item$date
    } else {
      NULL
    }
    url <- if (is.list(item)) {
      if (!is.null(item$source_url)) item$source_url else item$url
    } else {
      NULL
    }
    if (nzchar(trimws(txt))) {
      item_deltas <- extract_deltas_llm(
        raw_text = txt,
        date = dt,
        source_url = url,
        baseline_state = baseline_state,
        mock = mock,
        api_key = api_key
      )
      if (length(item_deltas) > 0) {
        all_deltas <- c(all_deltas, item_deltas)
      }
    }
  }
  all_deltas
}
