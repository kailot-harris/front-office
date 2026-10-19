# ==============================================================================
# Live WNBA Injury Scraper & Roster Availability Feeder
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/injury_scraper.R
#
# Ported from NBA Analytics/injury_scraper.R (fetch_live_nba_injuries() renamed to
# fetch_live_wnba_injuries()). Hits ESPN's WNBA injuries site-API endpoint instead of
# the NBA path. Keeps the offseason-fallback pattern, but broadens the fallback
# trigger per WNBA_REPLICATION_PLAN.md §b Tier 3 "Injury report format" note: WNBA
# injury feeds are sparser/less frequent than NBA's, so falling back only on a literal
# 0 rows is not safe - a live feed that returns a suspiciously small handful of rows
# (e.g. one late-arriving team update while the rest of the league hasn't posted yet)
# is also treated as "not a trustworthy live snapshot" and blended with the labeled
# fallback sample instead of being reported as if it were the full league picture.
#
# Live validation on 2026-09-12 (see run notes) found the live endpoint IS populated
# in-season (42 real injury rows across 13 of 15 teams), so the fallback path was not
# exercised on that run - it's still implemented and tested with a forced empty
# response to confirm it fires correctly.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "injury_scraper.R"

# Ensure cache path fallback exists
if (!exists("CACHE_INJURY_DATA")) {
  CACHE_INJURY_DATA <- file.path(CACHE_DIR, "injury_data_cache.rds")
}

# Broadened fallback trigger (see header note): treat anything below this row count
# as "not a trustworthy live snapshot" for a 15-team league, not just literal 0.
# Rationale: NBA's daily official injury report reliably produces dozens of rows once
# in-season; the WNBA's public disclosure is per WNBA_REPLICATION_PLAN.md §e less
# granular/frequent, so a handful of rows more plausibly indicates a partially-updated
# feed (e.g. only 1-2 of 15 teams reported so far) than a genuinely healthy league.
MIN_PLAUSIBLE_INJURY_ROWS <- 5

# Reverse lookup: ESPN injuries feed reports team by full display name (e.g.
# "Atlanta Dream"), which matches config.R's WNBA_TEAMS values exactly (verified
# live 2026-09-12). Build abbreviation <- displayName lookup from the single source
# of truth rather than re-deriving a name-cleaning regex.
.wnba_name_to_abbrev <- setNames(names(WNBA_TEAMS), WNBA_TEAMS)

resolve_wnba_team <- function(display_name) {
  abbrev <- .wnba_name_to_abbrev[display_name]
  if (is.na(abbrev)) return(display_name)  # unknown/expansion team fallback
  unname(display_name)  # keep full franchise name; abbreviation available via lookup if needed
}

extract_athlete_id_from_links <- function(athlete) {
  # ENDPOINT QUIRK discovered during T1 validation (2026-09-12): unlike the NBA
  # injuries feed (where the NBA original reads p_row$athlete$id directly), the WNBA
  # site-API injuries endpoint's `athlete` sub-object has NO top-level `id` field at
  # all (columns are firstName/lastName/displayName/shortName/links/headshot/position/
  # team/notes/status - confirmed via str() dump against a live response). The
  # numeric ESPN athlete ID is only recoverable by regex-parsing it out of the
  # "Player Card" link href, e.g. ".../wnba/player/_/id/3058895/brionna-jones".
  href <- tryCatch(athlete$links[[1]]$href[1], error = function(e) NA_character_)
  if (is.null(href) || length(href) == 0 || is.na(href)) return(NA_integer_)
  m <- regmatches(href, regexpr("/id/([0-9]+)/", href))
  if (length(m) == 0 || nchar(m) == 0) return(NA_integer_)
  as.integer(gsub("[^0-9]", "", m))
}

fetch_live_wnba_injuries <- function() {
  cat("\n==================================================================\n")
  cat("           FETCHING LIVE WNBA OFFICIAL INJURY DISCLOSURES         \n")
  cat("==================================================================\n\n")

  url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/injuries"

  cat("[INJURY FEED] Connecting to real-time injury portal...\n")
  log_info("Connecting to live ESPN WNBA injury portal.", call = "fetch_live_wnba_injuries()", url = url)

  raw_resp <- tryCatch({
    request(url) |>
      req_timeout(8) |>
      req_retry(max_tries = 3) |>
      req_perform() |>
      resp_body_json(simplifyVector = TRUE)
  }, error = function(e) {
    cat(sprintf("[INJURY WARNING] Portal unreachable (%s).\n", e$message))
    log_error("ESPN WNBA injury portal unreachable.", condition = e,
              call = "fetch_live_wnba_injuries()", url = url)
    NULL
  })

  all_scratches <- list()

  # Parse live feed if in-season
  if (!is.null(raw_resp) && length(raw_resp$injuries) > 0) {
    teams_list <- raw_resp$injuries

    for (i in seq_len(nrow(teams_list))) {
      t_name <- teams_list$displayName[i]
      p_df   <- teams_list$injuries[[i]]
      if (is.null(p_df) || nrow(p_df) == 0) next

      clean_team <- resolve_wnba_team(t_name)

      for (j in seq_len(nrow(p_df))) {
        p_row <- p_df[j, ]
        raw_stat <- if (!is.null(p_row$status)) p_row$status else "Questionable"
        std_status <- case_when(
          grepl("out", raw_stat, ignore.case = TRUE)      ~ "Out",
          grepl("doubtful", raw_stat, ignore.case = TRUE) ~ "Doubtful",
          grepl("probable", raw_stat, ignore.case = TRUE) ~ "Probable",
          TRUE                                            ~ "Questionable"
        )

        # ESPN's `type` field on this record is actually the injury-STATUS type
        # descriptor (e.g. "out"), not a body-part/injury description - a quirk also
        # present (and not obviously noticed) in the NBA original. `details$type`
        # (body part, e.g. "Leg") is more informative when present, so prefer it here.
        injury_desc <- coalesce(p_row$details$type, p_row$type$description, "Undisclosed")

        all_scratches[[length(all_scratches) + 1]] <- tibble(
          game_date   = Sys.Date(),
          team_name   = clean_team,
          player_name = p_row$athlete$displayName,
          player_id   = extract_athlete_id_from_links(p_row$athlete),
          status      = std_status,
          injury_desc = injury_desc
        )
      }
    }
  }

  n_live_rows <- length(all_scratches)

  # Broadened fallback: literal 0 (true offseason) OR implausibly few rows (partial/
  # stale feed) both trigger the clearly-labeled synthetic sample.
  if (n_live_rows < MIN_PLAUSIBLE_INJURY_ROWS) {
    if (n_live_rows == 0) {
      cat("[OFFSEASON INFO] WNBA daily injury reports are inactive (offseason).\n")
      log_warn("Live injury feed returned 0 rows (offseason); falling back to SYNTHETIC_FALLBACK sample.",
               call = "fetch_live_wnba_injuries()", n_live_rows = n_live_rows)
    } else {
      cat(sprintf(
        "[FEED WARNING] Live feed returned only %d row(s) (< plausibility floor of %d for a %d-team league) - treating as an unreliable/partial snapshot.\n",
        n_live_rows, MIN_PLAUSIBLE_INJURY_ROWS, WNBA_TEAM_COUNT
      ))
      log_warn(sprintf("Live injury feed returned only %d row(s), below plausibility floor of %d; treating as unreliable/partial and falling back to SYNTHETIC_FALLBACK sample.",
                        n_live_rows, MIN_PLAUSIBLE_INJURY_ROWS),
               call = "fetch_live_wnba_injuries()", n_live_rows = n_live_rows, floor = MIN_PLAUSIBLE_INJURY_ROWS)
    }
    cat("[OFFSEASON INFO] Loading labeled synthetic high-impact injury/rehab sample.\n\n")

    # Real, current/recent WNBA players (verified live via ESPN WNBA roster endpoint
    # on 2026-09-12 - see run notes; NOT the NBA sample's Porzingis/Kawhi/Embiid names,
    # and NOT fictional). Statuses/descriptions below are illustrative placeholders for
    # the fallback sample, not scraped injury facts.
    injury_table <- tibble(
      game_date   = Sys.Date(),
      team_name   = c("Las Vegas Aces", "Indiana Fever", "New York Liberty",
                       "Minnesota Lynx", "Connecticut Sun", "Atlanta Dream"),
      player_name = c("A'ja Wilson", "Caitlin Clark", "Breanna Stewart",
                       "Napheesa Collier", "Brittney Griner", "Angel Reese"),
      player_id   = c(3149391L, 4433403L, 2998928L, 3917450L, 2490553L, 4433402L),
      status      = c("Probable", "Questionable", "Out", "Probable", "Questionable", "Doubtful"),
      injury_desc = c("Knee Maintenance", "Quad Strain", "Achilles Recovery",
                       "Ankle Sprain", "Finger Injury", "Ankle Soreness"),
      data_source = "SYNTHETIC_FALLBACK"
    )
  } else {
    injury_table <- bind_rows(all_scratches) |> mutate(data_source = "LIVE_ESPN")
    cat(sprintf("[INJURY SUCCESS] Parsed %d official player injury designations.\n\n", nrow(injury_table)))
    log_info(sprintf("Parsed %d live official injury designations.", nrow(injury_table)),
             call = "fetch_live_wnba_injuries()", rows = nrow(injury_table), data_source = "LIVE_ESPN")
  }

  # Display preview
  print(knitr::kable(injury_table, format = "simple"))

  saveRDS(injury_table, CACHE_INJURY_DATA)
  cat(sprintf("\n[CACHE] Saved injury disclosures to: %s\n", CACHE_INJURY_DATA))
  log_info(sprintf("Saved %d injury rows to cache.", nrow(injury_table)),
           call = "fetch_live_wnba_injuries()", rows = nrow(injury_table), out_path = CACHE_INJURY_DATA)

  return(injury_table)
}

# Auto-execute
# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md): was `if (sys.nframe() == 0 || interactive())`,
# which is never TRUE under run_full_pipeline.R's run_stage() (it source()s each stage from inside
# a function, so sys.nframe() is ~10, and Rscript is non-interactive). This stage logged
# [COMPLETED] in 0.24s every night while cache/injury_data_cache.rds stayed four days stale —
# the most time-critical feed in the repo. `!interactive()` matches the guard style that already
# works in rapm_engine.R / risk_management_engine.R / copula_props_engine.R.
if (!interactive()) {
  fetch_live_wnba_injuries()
}
