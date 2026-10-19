# ==============================================================================
# NFL Injury Scraper — official nflverse report + same-day ESPN freshness feed
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/injury_scraper.R
#
# Ported from WNBA Analytics/injury_scraper.R (fetch_live_wnba_injuries() ->
# run_injury_scraper()). The WNBA script hit ESPN's site-API as its ONLY source; this
# NFL port is structurally different per docs/NFL_REPLICATION_PLAN.md §2 because NFL has
# a dedicated, official-report-grade source (nflreadr::load_injuries()) that WNBA never
# had. Design (see task_assignments_phase0.md's Interface Contracts row for this file):
#   - PRIMARY / AUTHORITATIVE: nflreadr::load_injuries() — nflverse-sourced official
#     league injury-report submissions (probable/questionable/out + practice
#     participation), keyed by gsis_id/team/week. This is the more complete,
#     versioned, historically-correct source, so it wins whenever both sources cover
#     the same report window.
#   - SECONDARY / FRESHNESS SUPPLEMENT: ESPN's site-API JSON feed
#     (site.web.api.espn.com/.../football/nfl/injuries), which updates more often than
#     nflreadr's nightly/weekly release cadence and can reflect same-day status changes
#     nflreadr hasn't ingested yet.
#   - CONFLICT RULE: the two sources use DIFFERENT player-ID schemes (nflreadr:
#     gsis_id; ESPN: numeric athlete ID recovered from the Player-Card href — see
#     below). Per docs/NFL_REPLICATION_PLAN.md §1 failure-mode 3 ("two caches joined on
#     incompatible ID schemes silently producing a zero-match join"), this script does
#     NOT attempt to join/collapse the two sources into one row per player by
#     name-matching. Both sources are UNION'd (bind_rows) into one tibble with a
#     `data_source` tag ("NFLREADR_OFFICIAL" or "ESPN_LIVE") and left as separate rows.
#     A downstream consumer that wants "most current status for player X" should filter
#     to the freshest `report_date`/`data_source` itself. As of 2026-09-17, run_injury_scraper()
#     ALSO enriches each row with the other source's crosswalked ID (`espn_athlete_id_crosswalked`
#     on NFLREADR_OFFICIAL rows, `gsis_id_crosswalked` on ESPN_LIVE rows) via
#     nflreadr::load_ff_playerids() (player_id_crosswalk.R) — still never merges/collapses rows,
#     just adds an optional matching key a downstream consumer can use instead of a name-string
#     join. See player_id_crosswalk.R's header for the crosswalk's own live-verified quirks
#     (a real duplicate-gsis_id bug in the underlying data, handled by dropping ambiguous IDs).
#
# ESPN JSON quirk (LIVE-VERIFIED 2026-09-16 via tools/_probe_espn_injuries.R against the
# real site.web.api.espn.com/apis/site/v2/sports/football/nfl/injuries feed — this is not
# a paraphrase of docs/NFL_REPLICATION_PLAN.md's §2 example, it was independently
# re-fetched and re-confirmed for this file):
#   Each injuries[i]$injuries[j] entry's own "id" field (e.g. "-2004726" for a real
#   Arizona Cardinals IR entry, player Kitan Crawford) is an INJURY-REPORT-ENTRY id, not
#   a player id. The athlete sub-object has NO top-level "id" field at all (confirmed
#   columns: firstName/lastName/displayName/shortName/links/headshot/position/team/
#   notes/status). The real numeric ESPN athlete ID (4430821 for Kitan Crawford, live
#   example) must be parsed out of athlete$links[[1]]'s "Player Card" row href, e.g.
#   "https://www.espn.com/nfl/player/_/id/4430821/kitan-crawford", or equivalently from
#   the headshot filename "https://a.espncdn.com/i/headshots/nfl/players/full/4430821.png".
#   This is the exact same workaround already proven in WNBA Analytics/injury_scraper.R's
#   extract_athlete_id_from_links() — reused here verbatim in spirit, adapted for the NFL
#   endpoint's link-table shape (athlete$links[[1]] is a small data.frame of ~12 link rows
#   per athlete, e.g. Player Card/Stats/Splits/Game Log/News/Bio/Overview, each with its
#   own href — we must select the "Player Card" (or any) row containing "/id/<digits>/"
#   rather than assuming href is a length-1 scalar).
# ==============================================================================

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "injury_scraper.R"
# Cross-source player-ID crosswalk (nflreadr::load_ff_playerids()) - enriches each row with the
# OTHER source's ID below, never used to merge/collapse rows (see header comment's CONFLICT
# RULE - that design is unchanged). See player_id_crosswalk.R's own header for the live-verified
# schema/quirks (a real duplicate-gsis_id data bug in the underlying crosswalk, handled there).
source("player_id_crosswalk.R")

suppressPackageStartupMessages({
  library(nflreadr)
  library(dplyr)
  library(tibble)
})

if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

# ESPN site-API injuries feed. No API key required (confirmed live, see
# docs/NFL_REPLICATION_PLAN.md §2 / CLAUDE.md's quirks section).
.ESPN_NFL_INJURIES_URL <- "https://site.web.api.espn.com/apis/site/v2/sports/football/nfl/injuries"

# ------------------------------------------------------------------------------------------
# extract_espn_athlete_id(): the Player-Card-href workaround (see header comment).
# `links` is expected to be the data.frame found at athlete$links[[1]] for a single injury
# row (columns include rel/href/text). We never assume athlete$id exists - it does not,
# verified live 2026-09-16. Falls back to the headshot filename if no href matches.
# ------------------------------------------------------------------------------------------
extract_espn_athlete_id <- function(links_df, headshot_href = NA_character_) {
  href <- NA_character_
  if (!is.null(links_df) && is.data.frame(links_df) && nrow(links_df) > 0 && "href" %in% names(links_df)) {
    hrefs <- links_df$href
    # Prefer the row ESPN itself labels "Player Card"; fall back to any href
    # matching the /id/<digits>/ athlete-URL pattern (Stats/Splits/etc. rows carry
    # the same numeric ID in their path).
    card_idx <- which(grepl("player card", links_df$text, ignore.case = TRUE))
    candidates <- if (length(card_idx) > 0) hrefs[card_idx] else hrefs
    id_match <- candidates[grepl("/id/[0-9]+/", candidates)]
    if (length(id_match) > 0) href <- id_match[1]
  }
  if (is.na(href) && !is.na(headshot_href)) href <- headshot_href

  if (is.na(href) || length(href) == 0) return(NA_integer_)
  m <- regmatches(href, regexpr("/id/([0-9]+)/", href))
  if (length(m) == 0 || nchar(m) == 0) {
    # headshot filename form: .../full/4430821.png
    m2 <- regmatches(href, regexpr("([0-9]+)\\.png", href))
    if (length(m2) == 0 || nchar(m2) == 0) return(NA_integer_)
    return(as.integer(gsub("[^0-9]", "", m2)))
  }
  as.integer(gsub("[^0-9]", "", m))
}

# ------------------------------------------------------------------------------------------
# fetch_nflreadr_injuries(): PRIMARY source. Official nflverse injury/practice report data
# for the current season. More complete/authoritative than ESPN's feed (per header), so this
# wins on any overlap - callers should treat NFLREADR_OFFICIAL rows as canonical and
# ESPN_LIVE rows as a same-day supplement only.
# ------------------------------------------------------------------------------------------
fetch_nflreadr_injuries <- function() {
  log_info("Pulling primary injury source: nflreadr::load_injuries().", seasons = CURRENT_SEASON)
  df <- tryCatch({
    nflreadr::load_injuries(seasons = CURRENT_SEASON)
  }, error = function(e) {
    log_error("nflreadr::load_injuries() failed.", condition = e, seasons = CURRENT_SEASON)
    NULL
  })

  if (is.null(df) || nrow(df) == 0) {
    log_warn("nflreadr::load_injuries() returned 0 rows for current season (early season / not yet posted).",
             seasons = CURRENT_SEASON)
    return(tibble(
      season = integer(0), week = integer(0), team = character(0),
      player_name = character(0), gsis_id = character(0), espn_athlete_id = integer(0),
      status = character(0), injury_desc = character(0), report_date = as.Date(character(0)),
      data_source = character(0)
    ))
  }

  df <- as_tibble(df) |>
    transmute(
      season          = season,
      week            = week,
      team            = team,
      player_name     = full_name,
      gsis_id         = gsis_id,
      espn_athlete_id = NA_integer_,
      status          = coalesce(report_status, practice_status, "Unspecified"),
      injury_desc     = coalesce(report_primary_injury, practice_primary_injury, "Undisclosed"),
      report_date     = Sys.Date(),
      data_source     = "NFLREADR_OFFICIAL"
    )
  log_info(sprintf("Parsed %d rows from nflreadr::load_injuries().", nrow(df)), rows = nrow(df))
  df
}

# ------------------------------------------------------------------------------------------
# fetch_espn_live_injuries(): SECONDARY source. Same-day freshness supplement only - see
# header comment for why this is never joined/collapsed against the nflreadr rows.
# ------------------------------------------------------------------------------------------
fetch_espn_live_injuries <- function() {
  log_info("Pulling secondary injury source: ESPN site-API JSON feed.", url = .ESPN_NFL_INJURIES_URL)

  raw <- tryCatch({
    con <- url(.ESPN_NFL_INJURIES_URL)
    on.exit(try(close(con), silent = TRUE), add = TRUE)
    txt <- readLines(con, warn = FALSE)
    jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = TRUE)
  }, error = function(e) {
    log_error("ESPN NFL injuries feed unreachable.", condition = e, url = .ESPN_NFL_INJURIES_URL)
    NULL
  })

  rows <- list()
  if (!is.null(raw) && !is.null(raw$injuries) && is.data.frame(raw$injuries) && nrow(raw$injuries) > 0) {
    teams_df <- raw$injuries
    for (i in seq_len(nrow(teams_df))) {
      team_name <- teams_df$displayName[i]
      p_df <- teams_df$injuries[[i]]
      if (is.null(p_df) || !is.data.frame(p_df) || nrow(p_df) == 0) next

      for (j in seq_len(nrow(p_df))) {
        athlete <- p_df$athlete[j, ]
        links_df <- tryCatch(athlete$links[[1]], error = function(e) NULL)
        headshot_href <- tryCatch(athlete$headshot$href[1], error = function(e) NA_character_)
        espn_id <- extract_espn_athlete_id(links_df, headshot_href)

        raw_status <- p_row_status <- tryCatch(p_df$status[j], error = function(e) NA_character_)
        std_status <- dplyr::case_when(
          grepl("injured reserve|^ir$", raw_status, ignore.case = TRUE) ~ "IR",
          grepl("out", raw_status, ignore.case = TRUE)                  ~ "Out",
          grepl("doubtful", raw_status, ignore.case = TRUE)             ~ "Doubtful",
          grepl("probable", raw_status, ignore.case = TRUE)             ~ "Probable",
          grepl("questionable", raw_status, ignore.case = TRUE)         ~ "Questionable",
          TRUE                                                          ~ dplyr::coalesce(raw_status, "Unspecified")
        )

        injury_desc <- tryCatch(
          dplyr::coalesce(p_df$details$type[j], p_df$type$description[j], "Undisclosed"),
          error = function(e) "Undisclosed"
        )

        rows[[length(rows) + 1]] <- tibble(
          season          = CURRENT_SEASON,
          week            = NA_integer_,
          team            = team_name,
          player_name     = athlete$displayName,
          gsis_id         = NA_character_,
          espn_athlete_id = espn_id,
          status          = std_status,
          injury_desc     = injury_desc,
          report_date     = Sys.Date(),
          data_source     = "ESPN_LIVE"
        )
      }
    }
  }

  if (length(rows) == 0) {
    log_warn("ESPN live injury feed returned 0 parsable rows.", url = .ESPN_NFL_INJURIES_URL)
    return(tibble(
      season = integer(0), week = integer(0), team = character(0),
      player_name = character(0), gsis_id = character(0), espn_athlete_id = integer(0),
      status = character(0), injury_desc = character(0), report_date = as.Date(character(0)),
      data_source = character(0)
    ))
  }

  out <- bind_rows(rows)
  n_missing_id <- sum(is.na(out$espn_athlete_id))
  if (n_missing_id > 0) {
    log_warn(sprintf("%d/%d ESPN_LIVE rows had no recoverable athlete ID from Player-Card href/headshot.",
                      n_missing_id, nrow(out)), n_missing = n_missing_id, n_total = nrow(out))
  }
  log_info(sprintf("Parsed %d rows from ESPN live injury feed.", nrow(out)), rows = nrow(out))
  out
}

# ------------------------------------------------------------------------------------------
# run_injury_scraper(): the sole callable this script exposes, per
# docs/task_assignments_phase0.md's Interface Contracts. No required args. Pulls both
# sources, unions them (never joins - see header), writes CACHE_INJURY_DATA, returns
# TRUE/FALSE. Never auto-runs at source() time - run_full_pipeline.R's run_stage() calls
# this explicitly (see CLAUDE.md's Process/conventions section on the sys.nframe() pitfall).
# ------------------------------------------------------------------------------------------
run_injury_scraper <- function() {
  log_info("Starting NFL injury scraper run.")

  primary   <- tryCatch(fetch_nflreadr_injuries(),   error = function(e) { log_error("Primary source pull failed unexpectedly.", condition = e); NULL })
  secondary <- tryCatch(fetch_espn_live_injuries(),  error = function(e) { log_error("Secondary source pull failed unexpectedly.", condition = e); NULL })

  if (is.null(primary))   primary   <- primary[FALSE, ]
  if (is.null(secondary)) secondary <- secondary[FALSE, ]

  combined <- bind_rows(primary, secondary)

  if (nrow(combined) == 0) {
    log_error("Both injury sources returned 0 rows; refusing to overwrite cache with an empty table.")
    return(FALSE)
  }

  # ---- Player-ID crosswalk enrichment (see header CONFLICT RULE + player_id_crosswalk.R) ----
  # Adds each row's OTHER source's id as a new, clearly-provenance-labeled column - never
  # overwrites the row's own reported gsis_id/espn_athlete_id, never merges rows. A downstream
  # consumer wanting "current status for player X across both sources" can now match on either
  # scheme without inventing a name-string join - closing the exact gap this file's header used
  # to flag as unsolved (nflreadr::load_ff_playerids() "if it ever needs to reconcile the two ID
  # spaces"). Falls back to all-NA crosswalk columns (never fails the whole scraper run) if the
  # crosswalk itself can't be loaded.
  crosswalk <- tryCatch(load_player_id_crosswalk(), error = function(e) {
    log_error("load_player_id_crosswalk() failed - proceeding without ID-crosswalk enrichment.", condition = e)
    NULL
  })

  if (!is.null(crosswalk)) {
    cw_by_gsis <- crosswalk |> filter(!is.na(gsis_id)) |> distinct(gsis_id, .keep_all = TRUE) |>
      transmute(gsis_id, espn_athlete_id_crosswalked = suppressWarnings(as.integer(espn_id)))
    cw_by_espn <- crosswalk |> filter(!is.na(espn_id)) |> distinct(espn_id, .keep_all = TRUE) |>
      transmute(.espn_chr = espn_id, gsis_id_crosswalked = gsis_id)

    combined <- combined |>
      left_join(cw_by_gsis, by = "gsis_id") |>
      mutate(.espn_chr = as.character(espn_athlete_id)) |>
      left_join(cw_by_espn, by = ".espn_chr") |>
      select(-.espn_chr)

    assert_join_match_rate(
      sum(!is.na(combined$gsis_id) & !is.na(combined$espn_athlete_id_crosswalked)),
      sum(!is.na(combined$gsis_id)), "injury_scraper: gsis_id -> espn_id"
    )
    assert_join_match_rate(
      sum(!is.na(combined$espn_athlete_id) & !is.na(combined$gsis_id_crosswalked)),
      sum(!is.na(combined$espn_athlete_id)), "injury_scraper: espn_athlete_id -> gsis_id"
    )
  } else {
    combined$espn_athlete_id_crosswalked <- NA_integer_
    combined$gsis_id_crosswalked <- NA_character_
  }

  saved_ok <- tryCatch({
    saveRDS(combined, CACHE_INJURY_DATA)
    TRUE
  }, error = function(e) {
    log_error("Failed to write injury cache.", condition = e, out_path = CACHE_INJURY_DATA)
    FALSE
  })

  if (!saved_ok) return(FALSE)

  log_info(sprintf("Injury scraper run complete: %d total rows (%d NFLREADR_OFFICIAL, %d ESPN_LIVE) saved to cache.",
                    nrow(combined), sum(combined$data_source == "NFLREADR_OFFICIAL"),
                    sum(combined$data_source == "ESPN_LIVE")),
           rows = nrow(combined), out_path = CACHE_INJURY_DATA)

  TRUE
}
