# ==============================================================================
# Live NBA Injury Scraper & Roster Availability Feeder
# ==============================================================================

# This file's own directory, derived rather than hardcoded. A hardcoded
# PROJECT_DIR plus setwd() ran ahead of config.R's worktree-safe derivation, so
# from a git worktree this stage silently relocated into the main checkout and
# read that tree's config, caches and siblings. Siblings below are sourced by
# absolute path; `local = TRUE` is a no-op under run_stage() (which sources
# stages into the global environment) and lets a test load this file into a
# throwaway environment. The block is identical in every stage entrypoint and
# tests/test_stage_bootstrap.R asserts that.
.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(jsonlite)
})

source(file.path(.THIS_DIR, "config.R"), local = TRUE)

# Ensure cache path fallback exists
if (!exists("CACHE_INJURY_DATA")) {
  CACHE_INJURY_DATA <- file.path(CACHE_DIR, "injury_data_cache.rds")
}

ESPN_INJURY_URL <- "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/injuries"

# The cache's schema. An unreachable feed, an empty feed or a parse error all
# leave a zero-row table of exactly these columns and types, never invented rows.
empty_injury_table <- function() {
  tibble(
    game_date   = as.Date(character()),
    team_name   = character(),
    player_name = character(),
    player_id   = integer(),
    status      = character(),
    injury_desc = character()
  )
}

# ESPN's injury feed has no athlete id field (NBA_analytics#144): the id only
# appears inside the athlete's link hrefs, e.g.
#   https://www.espn.com/nba/player/_/id/3146557/jock-landale
# The "playercard" link is preferred; any other link carrying /id/<digits> is
# used if it is missing. Returns NA_integer_ when no href carries an id.
ESPN_HREF_ID_PATTERN <- "/id/([0-9]+)(/|$|[?#])"

extract_espn_athlete_id <- function(links) {
  if (is.null(links) || length(links) == 0) return(NA_integer_)
  if (is.data.frame(links)) links <- lapply(seq_len(nrow(links)), function(k) as.list(links[k, , drop = FALSE]))
  hrefs <- vapply(links, function(l) {
    h <- l$href
    if (is.null(h) || length(h) == 0 || is.na(h[[1]])) NA_character_ else as.character(h[[1]])
  }, character(1))
  is_card <- vapply(links, function(l) "playercard" %in% unlist(l$rel), logical(1))
  for (h in c(hrefs[is_card], hrefs[!is_card])) {
    if (is.na(h)) next
    m <- regmatches(h, regexec(ESPN_HREF_ID_PATTERN, h))[[1]]
    if (length(m) >= 2) {
      id <- suppressWarnings(as.integer(m[[2]]))
      if (!is.na(id)) return(id)
    }
  }
  NA_integer_
}

# The injury itself lives in details (type/side/detail, e.g. "Right Hip
# Inflammation"). The entry's type$description is only the status again
# ("out", "day-to-day"), so it is not used as the description.
.injury_description <- function(details) {
  if (is.null(details) || !is.list(details)) return("Undisclosed")
  pick <- function(x) if (is.null(x) || length(x) == 0 || is.na(x[[1]]) || !nzchar(x[[1]])) NULL else as.character(x[[1]])
  parts <- c(pick(details$side), pick(details$type), pick(details$detail))
  if (length(parts) == 0) "Undisclosed" else paste(parts, collapse = " ")
}

.std_injury_status <- function(raw_stat) {
  case_when(
    grepl("out", raw_stat, ignore.case = TRUE)        ~ "Out",
    # A suspended player is unavailable; the feed reports "Suspension".
    grepl("suspen", raw_stat, ignore.case = TRUE)     ~ "Out",
    grepl("doubtful", raw_stat, ignore.case = TRUE)   ~ "Doubtful",
    grepl("probable", raw_stat, ignore.case = TRUE)   ~ "Probable",
    TRUE                                              ~ "Questionable"
  )
}

# Parse an already-decoded feed (no network). Accepts the list from
# resp_body_json(simplifyVector = FALSE) / fromJSON(simplifyVector = FALSE), or
# the data-frame form from simplifyVector = TRUE. Returns the six-column table;
# entries whose id cannot be parsed keep their row with player_id = NA and are
# counted in one WARN line.
parse_espn_injuries <- function(feed, game_date = Sys.Date()) {
  if (is.null(feed) || is.null(feed$injuries) || length(feed$injuries) == 0) {
    return(empty_injury_table())
  }
  teams <- feed$injuries
  if (is.data.frame(teams)) {
    teams <- jsonlite::fromJSON(jsonlite::toJSON(teams, auto_unbox = TRUE, null = "null", na = "null"),
                                simplifyVector = FALSE)
  }

  rows <- list()
  for (t in teams) {
    t_name <- t$displayName %||% NA_character_
    entries <- t$injuries
    if (is.null(entries) || length(entries) == 0) next

    clean_team <- case_when(
      grepl("Trail Blazers|Portland", t_name, ignore.case = TRUE) ~ "Trail Blazers",
      grepl("76ers|Philadelphia", t_name, ignore.case = TRUE)      ~ "76ers",
      TRUE ~ word(t_name, -1)
    )

    for (e in entries) {
      raw_stat <- e$status %||% "Questionable"
      rows[[length(rows) + 1]] <- tibble(
        game_date   = as.Date(game_date),
        team_name   = as.character(clean_team),
        player_name = as.character(e$athlete$displayName %||% NA_character_),
        player_id   = extract_espn_athlete_id(e$athlete$links),
        status      = .std_injury_status(as.character(raw_stat)),
        injury_desc = .injury_description(e$details)
      )
    }
  }
  if (length(rows) == 0) return(empty_injury_table())

  out <- bind_rows(empty_injury_table(), bind_rows(rows))
  n_na <- sum(is.na(out$player_id))
  if (n_na > 0) {
    message(sprintf(">>> [WARN] injury_scraper.R: %d of %d injury entries had no player id in athlete.links[].href; kept with player_id = NA.",
                    n_na, nrow(out)))
  }
  out
}

# The only network call. Returns the decoded feed, or NULL when unreachable.
fetch_injury_feed <- function(url = ESPN_INJURY_URL, timeout_s = 8) {
  tryCatch({
    request(url) |>
      req_timeout(timeout_s) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
  }, error = function(e) {
    cat(sprintf("[INJURY WARNING] Portal unreachable (%s).\n", conditionMessage(e)))
    NULL
  })
}

fetch_live_nba_injuries <- function(url = ESPN_INJURY_URL, cache_path = CACHE_INJURY_DATA,
                                    fetch_fn = fetch_injury_feed) {
  cat("\n==================================================================\n")
  cat("           FETCHING LIVE NBA OFFICIAL INJURY DISCLOSURES          \n")
  cat("==================================================================\n\n")

  cat("[INJURY FEED] Connecting to real-time injury portal...\n")
  raw_resp <- fetch_fn(url)

  # A malformed feed must not stop the pipeline: log it and keep an empty table.
  injury_table <- tryCatch(parse_espn_injuries(raw_resp), error = function(e) {
    message(sprintf(">>> [WARN] injury_scraper.R: injury feed could not be parsed (%s); saving an empty injury table.",
                    conditionMessage(e)))
    NULL
  })
  parse_failed <- is.null(injury_table)
  if (parse_failed) injury_table <- empty_injury_table()

  if (nrow(injury_table) == 0) {
    if (!parse_failed) {
      message(">>> [WARN] publish-irrelevant: injury feed returned no entries (unreachable or empty); saving an empty injury table, no rows invented.")
    }
  } else {
    cat(sprintf("[INJURY SUCCESS] Parsed %d injury entries across %d teams (%d with a player id).\n\n",
                nrow(injury_table), n_distinct(injury_table$team_name), sum(!is.na(injury_table$player_id))))
    print(knitr::kable(injury_table, format = "simple"))
  }

  saveRDS(injury_table, cache_path)
  cat(sprintf("\n[CACHE] Saved injury disclosures to: %s\n", cache_path))

  return(injury_table)
}


# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone;
# run_full_pipeline.R relies on this call, so it stays on by default.
if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  fetch_live_nba_injuries()
}
