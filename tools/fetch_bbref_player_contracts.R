# ==============================================================================
# tools/fetch_bbref_player_contracts.R
#
# Phase 2a of the Basketball-Reference cap-data automation effort (issue #98,
# gated by #97's reachability/structure findings — see
# cap_data_phase1_findings.md on branch fix/nov13-nba-issue97 / PR #106 at the
# time this was written). Fetches
# https://www.basketball-reference.com/contracts/players.html via httr2 and
# parses the #player-contracts table via rvest into cache/bbref_player_contracts.rds.
#
# Per #97's live findings (2026-11-13):
#   - robots.txt allows /contracts/players.html but specifies Crawl-delay: 3.
#     This script makes exactly one request, so there is nothing to throttle
#     between requests, but a 3s pause is still taken *before* the request as
#     a courteous floor, and req_retry()'s backoff (see below) respects the
#     same minimum if a retry is needed.
#   - The table's season-year column headers (e.g. "2026-27") shift every
#     season. Rows are therefore selected by the stable `data-stat` attribute
#     names (ranker | player | team_id | y1..y6 | remain_gtd), never by
#     fixed column position or header text.
#   - Repeating header rows (every 22nd row, a <th data-stat="ranker"> with
#     text "Rk") are dropped by filtering on data-stat presence/content, not
#     by a fixed row-offset, since BBRef's header placement has shifted
#     across season snapshots before.
#   - 485 data rows were observed live on 2026-11-13; this count drifts
#     through a season as contracts are signed/waived, so no exact row count
#     is enforced here, only a sanity floor (see MIN_EXPECTED_PLAYER_ROWS).
#
# Run standalone: Rscript tools/fetch_bbref_player_contracts.R
# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions alone
# without fetching (matches this repo's other tools/fetch_*-style scripts).
# ==============================================================================

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
  library(httr2)
  library(rvest)
  library(stringi)
})

source(file.path(.THIS_DIR, "..", "config.R"), local = TRUE)

BBREF_CONTRACTS_URL <- "https://www.basketball-reference.com/contracts/players.html"
BBREF_CRAWL_DELAY_SECONDS <- 3
CACHE_BBREF_PLAYER_CONTRACTS <- file.path(CACHE_DIR, "bbref_player_contracts.rds")

# Sanity floor, not an exact target: #97 observed 485 live rows on 2026-11-13
# and documented that the count drifts over a season. A collapse to near-zero
# (e.g. BBRef serving an error/interstitial page that still parses as valid
# HTML) should fail loudly rather than cache a near-empty, garbage result.
MIN_EXPECTED_PLAYER_ROWS <- 300

# A browser-style User-Agent, matching #97's probe. BBRef has not been seen to
# block httr2/rvest requests carrying this (unlike Spotrac's CloudFront block),
# but a plain httr2 default UA is more likely to be treated as a bot.
BBREF_USER_AGENT <- paste(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  "(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
)

#' Fail loudly and clearly. Mirrors the style (not the viz-specific
#' implementation) of this repo's tools/viz_common.R::viz_stop_no_data(): a
#' single marker string a human or a log-grep can key on, plus the concrete
#' reason, so an unreachable page or a changed table structure produces a
#' clear stop() rather than a silent empty/garbage cache write.
bbref_contracts_stop <- function(reason) {
  stop(sprintf(
    "[BBREF_CONTRACTS_FETCH_FAILED] tools/fetch_bbref_player_contracts.R: %s Nothing was cached.",
    reason
  ), call. = FALSE)
}

#' Fetch the live page via httr2, with a short courteous delay (per #97's
#' Crawl-delay: 3 finding) and a clear, loud failure on any network error,
#' non-200 status, or empty body — never a silently-swallowed NULL.
bbref_fetch_contracts_page <- function(url = BBREF_CONTRACTS_URL) {
  Sys.sleep(BBREF_CRAWL_DELAY_SECONDS)

  resp <- tryCatch({
    request(url) |>
      req_user_agent(BBREF_USER_AGENT) |>
      req_timeout(30) |>
      req_retry(max_tries = 3, backoff = function(n) BBREF_CRAWL_DELAY_SECONDS * n) |>
      req_perform()
  }, error = function(e) {
    bbref_contracts_stop(sprintf(
      "Request to %s failed: %s", url, conditionMessage(e)
    ))
  })

  status <- resp_status(resp)
  if (status != 200) {
    bbref_contracts_stop(sprintf(
      "%s returned HTTP %d instead of 200.", url, status
    ))
  }

  body <- resp_body_string(resp)
  if (!nzchar(trimws(body))) {
    bbref_contracts_stop(sprintf("%s returned an empty response body.", url))
  }

  body
}

#' Parse the fetched HTML into one tibble-free data.frame row per player.
#' Selects data rows by the stable `data-stat` attribute set documented in
#' #97 (ranker | player | team_id | y1..y6 | remain_gtd), not by column
#' position or by the season-year header text (which shifts every season).
#' A header/non-player row has no data-stat="player" cell with real content,
#' so filtering on that cell's presence drops repeating header rows without
#' relying on a fixed row-interval that could shift across snapshots.
bbref_parse_contracts_table <- function(html_text) {
  page <- tryCatch(
    read_html(html_text),
    error = function(e) {
      bbref_contracts_stop(sprintf("HTML failed to parse: %s", conditionMessage(e)))
    }
  )

  tbl_node <- html_element(page, "#player-contracts")
  if (inherits(tbl_node, "xml_missing") || length(tbl_node) == 0) {
    bbref_contracts_stop(
      "Table '#player-contracts' was not found in the fetched page. BBRef's page structure may have changed."
    )
  }

  rows <- html_elements(tbl_node, "tbody tr")
  if (length(rows) == 0) {
    bbref_contracts_stop("Table '#player-contracts' has no <tbody> rows. BBRef's page structure may have changed.")
  }

  get_stat <- function(row, stat) {
    cell <- html_element(row, sprintf("[data-stat='%s']", stat))
    if (inherits(cell, "xml_missing") || length(cell) == 0) return(NA_character_)
    txt <- html_text2(cell)
    if (!is.character(txt) || length(txt) == 0) return(NA_character_)
    txt
  }

  player_names_raw <- vapply(rows, get_stat, character(1), stat = "player")

  # Repeating header rows render "Player" (data-stat="player") as a <th>
  # inside the <thead>-style repeat rows BBRef injects into <tbody> every
  # ~22 rows (per #97). Drop rows with no player name and rows whose name
  # IS the header-artifact literal "Player"; this also silently drops any
  # other structurally blank row (e.g. a spacer row), which is desired.
  is_header_or_blank <- is.na(player_names_raw) |
    trimws(player_names_raw) == "" |
    trimws(player_names_raw) == "Player"

  data_rows <- rows[!is_header_or_blank]
  if (length(data_rows) == 0) {
    bbref_contracts_stop(
      "Every row in '#player-contracts' parsed as a header/blank row; expected data-stat='player' columns were not found. BBRef's page structure may have changed."
    )
  }

  clean_money <- function(x) {
    # BBRef renders missing future-year salaries as "" and guaranteed totals
    # with "$"/"," formatting; coerce both to numeric NA / dollars cleanly.
    x <- gsub("[$,]", "", x)
    x[trimws(x) == ""] <- NA
    suppressWarnings(as.numeric(x))
  }

  nfc <- function(x) stri_trans_nfc(x)

  out <- data.frame(
    rank          = suppressWarnings(as.integer(vapply(data_rows, get_stat, character(1), stat = "ranker"))),
    player         = nfc(vapply(data_rows, get_stat, character(1), stat = "player")),
    team           = vapply(data_rows, get_stat, character(1), stat = "team_id"),
    salary_y1      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y1")),
    salary_y2      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y2")),
    salary_y3      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y3")),
    salary_y4      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y4")),
    salary_y5      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y5")),
    salary_y6      = clean_money(vapply(data_rows, get_stat, character(1), stat = "y6")),
    guaranteed_total = clean_money(vapply(data_rows, get_stat, character(1), stat = "remain_gtd")),
    stringsAsFactors = FALSE
  )

  # A player row with no name at all slipped through upstream filtering
  # (e.g. a malformed row) — drop it rather than cache a garbage record, but
  # this should be rare; if it's common, that's itself a sign of a structure
  # change worth failing loudly on.
  out <- out[!is.na(out$player) & trimws(out$player) != "", , drop = FALSE]

  out
}

#' Top-level entrypoint: fetch, parse, validate, cache. Fails loudly (via
#' bbref_contracts_stop(), propagated as a plain stop()) rather than writing
#' a silent empty/garbage cache on any failure along the way.
fetch_bbref_player_contracts <- function() {
  cat("[BBREF_CONTRACTS] Fetching", BBREF_CONTRACTS_URL, "...\n")
  html_text <- bbref_fetch_contracts_page()

  cat("[BBREF_CONTRACTS] Parsing #player-contracts table...\n")
  contracts <- bbref_parse_contracts_table(html_text)

  if (nrow(contracts) < MIN_EXPECTED_PLAYER_ROWS) {
    bbref_contracts_stop(sprintf(
      "Only %d player rows parsed (expected at least %d). BBRef's page structure may have changed.",
      nrow(contracts), MIN_EXPECTED_PLAYER_ROWS
    ))
  }

  attr(contracts, "fetched_at") <- Sys.time()
  attr(contracts, "source_url") <- BBREF_CONTRACTS_URL

  saveRDS(contracts, CACHE_BBREF_PLAYER_CONTRACTS)
  cat(sprintf(
    "[BBREF_CONTRACTS] Cached %d player rows to %s (fetched_at = %s).\n",
    nrow(contracts), CACHE_BBREF_PLAYER_CONTRACTS, format(attr(contracts, "fetched_at"))
  ))

  contracts
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  fetch_bbref_player_contracts()
}
