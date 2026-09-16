# ==============================================================================
# Live WNBA Roster Synchronizer (Automated Offseason Trade Tracker)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/sync_rosters.R
#
# Ported from NBA Analytics/sync_rosters.R. Hits ESPN's WNBA site API instead of the
# NBA path (same host/JSON shape, per WNBA_REPLICATION_PLAN.md §c). The NBA original's
# team-name canonicalization regex (`word(team_name, -1)` + special-cased Trail
# Blazers/76ers) is REWRITTEN here rather than reused, because live validation
# (2026-09-12) showed ESPN's WNBA teams endpoint already returns an `abbreviation`
# field that matches config.R's WNBA_TEAMS names vector exactly (e.g. "ATL", "GS",
# "TOR"), so canonicalization is a direct join against WNBA_TEAMS instead of fragile
# substring/regex matching on the display name. This is more robust than the NBA
# version's approach, not a functional regression.
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
.LOG_SCRIPT <- "sync_rosters.R"

sync_active_rosters <- function() {
  cat("\n==================================================================\n")
  cat("        FETCHING LIVE WNBA ACTIVE ROSTERS & OFFSEASON TRADES      \n")
  cat("==================================================================\n\n")

  # 1. Fetch all WNBA teams and IDs
  teams_url <- "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/teams"

  cat("[ROSTER SYNC] Fetching team registry from live CDN...\n")
  log_info("Fetching WNBA team registry from ESPN.", call = "sync_active_rosters()", url = teams_url)
  teams_resp <- tryCatch({
    request(teams_url) |>
      req_timeout(6) |>
      req_perform() |>
      resp_body_json(simplifyVector = TRUE)
  }, error = function(e) {
    log_error("Failed to reach ESPN WNBA team endpoint.", condition = e,
              call = "sync_active_rosters()", url = teams_url)
    stop("Failed to reach ESPN WNBA team endpoint: ", e$message)
  })

  teams_data <- teams_resp$sports$leagues[[1]]$teams[[1]]$team

  # Canonicalize against config.R's WNBA_TEAMS (single source of truth - see
  # task_assignments.md T0 Handoff Notes). ESPN's own `abbreviation` field matched
  # WNBA_TEAMS's names exactly for all 15 franchises at validation time; fall back to
  # the raw ESPN abbreviation/displayName (with a loud warning) for any team ESPN
  # returns that isn't yet in WNBA_TEAMS, so a new expansion franchise doesn't silently
  # get dropped - it just won't have a "known" canonical name until config.R is updated.
  unknown_abbrevs <- setdiff(teams_data$abbreviation, names(WNBA_TEAMS))
  if (length(unknown_abbrevs) > 0) {
    warning(sprintf(
      "[ROSTER SYNC] ESPN returned team abbreviation(s) not in config.R's WNBA_TEAMS: %s. Update WNBA_TEAMS.",
      paste(unknown_abbrevs, collapse = ", ")
    ))
  }

  roster_list <- list()

  cat(sprintf("[ROSTER SYNC] Querying active rosters for all %d WNBA franchises...\n", nrow(teams_data)))

  for (i in seq_len(nrow(teams_data))) {
    team_id     <- teams_data$id[i]
    espn_abbrev <- teams_data$abbreviation[i]
    clean_team  <- unname(WNBA_TEAMS[espn_abbrev])
    if (is.na(clean_team)) clean_team <- teams_data$displayName[i]  # unknown/expansion fallback

    # Roster endpoint for this specific team
    roster_url <- sprintf("https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/teams/%s/roster", team_id)

    roster_resp <- tryCatch({
      request(roster_url) |>
        req_timeout(4) |>
        req_perform() |>
        resp_body_json(simplifyVector = TRUE)
    }, error = function(e) {
      log_error(sprintf("Roster fetch failed for team %s (%s).", espn_abbrev, clean_team),
                condition = e, call = "sync_active_rosters()", url = roster_url, team = espn_abbrev)
      NULL
    })

    if (is.null(roster_resp) || is.null(roster_resp$athletes)) {
      if (!is.null(roster_resp)) {
        log_warn(sprintf("Roster response for team %s had no athletes; skipping this team.", espn_abbrev),
                 call = "sync_active_rosters()", team = espn_abbrev)
      }
      next
    }

    athletes <- roster_resp$athletes

    roster_list[[i]] <- tibble(
      team_abbreviation = espn_abbrev,
      team_name   = clean_team,
      team_id     = as.integer(team_id),
      player_id   = as.integer(athletes$id),
      player_name = athletes$displayName,
      position    = athletes$position$abbreviation,
      jersey      = athletes$jersey
    )

    Sys.sleep(0.05) # Polite micro-delay
  }

  active_rosters <- bind_rows(roster_list)

  cat(sprintf(
    "\n[SUCCESS] Synchronized %d active WNBA players across all %d rosters.\n\n",
    nrow(active_rosters), nrow(teams_data)
  ))

  # Preview latest roster movements
  cat("Preview of live rosters (sample teams):\n")
  print(head(active_rosters |> select(team_name, player_name, position, jersey), 12))

  out_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  saveRDS(active_rosters, out_path)
  cat(sprintf("\n[CACHE] Saved active rosters to: %s\n", out_path))
  log_info(sprintf("Synchronized %d active WNBA players across %d rosters.", nrow(active_rosters), nrow(teams_data)),
           call = "sync_active_rosters()", rows = nrow(active_rosters), teams = nrow(teams_data), out_path = out_path)

  return(active_rosters)
}

# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md): this guard used to read
# `if (sys.nframe() == 0 || interactive())`. `sys.nframe() == 0` is true ONLY when a file is
# the top-level script of an `Rscript` invocation — it is never 0 inside a source()'d file, and
# run_full_pipeline.R's run_stage() sources every stage from *inside a function* (nframe ~10).
# The stage therefore defined sync_active_rosters() and returned in ~0.2s while logging
# [COMPLETED], leaving cache/active_rosters_cache.rds frozen for days. `!interactive()` is the
# pattern that already works correctly in copula_props_engine.R / fatigue_travel_engine.R /
# rapm_engine.R / risk_management_engine.R: TRUE under Rscript whether run directly or sourced,
# FALSE in an interactive session (so opening this file in RStudio still does not fire a live
# ESPN scrape). run_full_pipeline.R also declares this entry point explicitly via run_stage()'s
# `entry_fn` argument so the DAG's contract is visible there, not only here.
if (!interactive()) {
  sync_active_rosters()
}
