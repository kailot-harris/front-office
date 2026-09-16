# ==============================================================================
# Automated Daily Box Score Ingestion Pipeline (WNBA)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/daily_ingest.R
#
# Ported from NBA Analytics/daily_ingest.R. Swaps hoopR::load_nba_team_box() for
# wehoop::load_wnba_team_box() (same call idiom, sportsdataverse team). Dedupe-on-
# (game_id, team_id) logic and full-historical-bootstrap-if-cache-missing behavior
# are preserved unchanged.
#
# CRITICAL WNBA-SPECIFIC GOTCHA (per task_assignments.md T0 Handoff Notes / config.R
# comments): raw wehoop team box data includes non-franchise All-Star draft-squad and
# Team USA exhibition rows (observed abbreviations change by season - as of 2026-09-12
# validation the live 2026 season data contains "COOP" and "SPO" alongside the 15 real
# franchise codes). These rows have no place in a real-franchise-only cache (they'd
# corrupt any team-level rolling aggregation downstream), so every load is filtered to
# team_abbreviation %in% names(WNBA_TEAMS) immediately after the wehoop call, before any
# dedupe/aggregation/caching.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(wehoop)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "daily_ingest.R"

# Drop non-franchise All-Star/exhibition "team" rows from raw wehoop box data.
#
# IMPORTANT ADDITIONAL GOTCHA discovered during T1 validation (2026-09-12), beyond the
# codes T0 already flagged: ESPN used the abbreviation "CONN" (not "CON") for the
# Connecticut Sun for seasons 2019-2023 (203 real team-game rows), switching to "CON"
# only from the 2024 season onward. "CONN" is a REAL franchise code, not an exhibition
# row - a naive `team_abbreviation %in% names(WNBA_TEAMS)` filter silently drops 5
# seasons of real Connecticut Sun data. Normalize CONN -> CON before filtering.
normalize_team_abbreviation <- function(df) {
  if ("team_abbreviation" %in% names(df)) {
    df <- df |> mutate(team_abbreviation = if_else(team_abbreviation == "CONN", "CON", team_abbreviation))
  }
  if ("opponent_team_abbreviation" %in% names(df)) {
    df <- df |> mutate(opponent_team_abbreviation = if_else(opponent_team_abbreviation == "CONN", "CON", opponent_team_abbreviation))
  }
  df
}

filter_real_franchises <- function(df) {
  if (!"team_abbreviation" %in% names(df)) return(df)
  df <- normalize_team_abbreviation(df)
  dropped <- df |> filter(!(team_abbreviation %in% names(WNBA_TEAMS)))
  if (nrow(dropped) > 0) {
    log_info(sprintf(
      "Filtered out %d non-franchise exhibition/All-Star rows (abbreviations: %s).",
      nrow(dropped), paste(sort(unique(dropped$team_abbreviation)), collapse = ", ")
    ))
  }
  df |> filter(team_abbreviation %in% names(WNBA_TEAMS))
}

daily_box_ingest <- function() {
  log_info("Starting daily WNBA box score ingestion...")

  # 1. Load existing cache
  if (file.exists(CACHE_TEAM_BOX)) {
    existing_box <- readRDS(CACHE_TEAM_BOX)
    log_info(sprintf("Loaded existing cache with %d records.", nrow(existing_box)))
  } else {
    log_info(sprintf(
      "Cache not found. Initializing complete historical ingestion (%d:%d)...",
      min(ALL_SEASONS), max(ALL_SEASONS)
    ))
    existing_box <- tryCatch({
      wehoop::load_wnba_team_box(seasons = ALL_SEASONS) |> filter_real_franchises()
    }, error = function(e) {
      log_error("Initial historical wehoop::load_wnba_team_box() bootstrap failed.", condition = e,
                call = "daily_box_ingest()", seasons = paste(range(ALL_SEASONS), collapse = "-"))
      stop(e)
    })
    saveRDS(existing_box, CACHE_TEAM_BOX)
    log_info(sprintf("Saved initial cache with %d records.", nrow(existing_box)))
    log_info(sprintf("Bootstrapped initial team box cache with %d records.", nrow(existing_box)),
             call = "daily_box_ingest()", rows = nrow(existing_box), out_path = CACHE_TEAM_BOX)
    return(invisible(existing_box))
  }

  # 2. Fetch current season updates
  log_info(sprintf("Fetching updates for season %d from wehoop API...", CURRENT_SEASON))
  log_info(sprintf("Fetching wehoop::load_wnba_team_box() updates for season %d.", CURRENT_SEASON),
           call = "daily_box_ingest()", season = CURRENT_SEASON)
  new_box <- tryCatch({
    wehoop::load_wnba_team_box(seasons = CURRENT_SEASON) |> filter_real_franchises()
  }, error = function(e) {
    log_warn(sprintf("Error loading current season box scores: %s", e$message))
    log_error(sprintf("wehoop::load_wnba_team_box() failed for season %d.", CURRENT_SEASON),
              condition = e, call = "daily_box_ingest()", season = CURRENT_SEASON)
    return(NULL)
  })

  if (is.null(new_box) || nrow(new_box) == 0) {
    log_warn("No records returned from API. Exiting.")
    log_warn("wehoop::load_wnba_team_box() returned zero new records for current season.",
             call = "daily_box_ingest()", season = CURRENT_SEASON)
    return(invisible(existing_box))
  }
  log_info(sprintf("Fetched %d new-season team box rows.", nrow(new_box)),
           call = "daily_box_ingest()", rows = nrow(new_box), season = CURRENT_SEASON)

  # 3. Deduplicate by game_id and team_id
  combined <- bind_rows(existing_box, new_box) |>
    distinct(game_id, team_id, .keep_all = TRUE) |>
    arrange(season, game_date, game_id)

  n_new_records <- nrow(combined) - nrow(existing_box)
  log_info(sprintf("Ingestion complete. %d new records identified.", n_new_records))

  # 4. Save cache back to disk
  if (n_new_records > 0) {
    saveRDS(combined, CACHE_TEAM_BOX)
    log_info(sprintf("Updated %s with %d total records.", CACHE_TEAM_BOX, nrow(combined)))
    log_info(sprintf("Updated team box cache with %d new records (%d total).", n_new_records, nrow(combined)),
             call = "daily_box_ingest()", new_records = n_new_records, total_rows = nrow(combined), out_path = CACHE_TEAM_BOX)
  } else {
    log_info("Cache is already up to date. No write necessary.")
    log_info("Team box cache already up to date; no write necessary.", call = "daily_box_ingest()")
  }

  invisible(combined)
}

# ==============================================================================
# FINDING L-4 (docs/SECURITY_TECHNICAL_REVIEW.md) — DAG membership.
#
# This script — the "Automated Daily Box Score Ingestion Pipeline" — was not among
# run_full_pipeline.R's run_stage() calls at all. Ingestion happened only as an
# implicit side effect of prediction_accuracy_logger.R sourcing this file and calling
# daily_box_ingest() during reconciliation, which meant (a) the dependency was
# invisible, (b) reordering/removing that stage would have stopped ingestion with no
# stage failure, and (c) every ingestion log line was misattributed to
# [prediction_accuracy_logger.R] in the real run log.
#
# As of Phase 4 Wave 2 this is an explicit early DAG stage, invoked BY NAME via
# run_stage()'s `call_fn = "daily_box_ingest"` mechanism, and
# prediction_accuracy_logger.R is a pure consumer of CACHE_TEAM_BOX.
#
# WHY THE GUARD BELOW IS STILL `sys.nframe() == 0` AND NOT `!interactive()`
# (this is the C-2 guard class, so it deserves an explicit answer rather than an
# assumption — confirmed empirically, not reasoned about):
#
#   * run_stage() calls source(script, local = FALSE) from INSIDE a function, where
#     sys.nframe() is ~10, never 0. So this block stays DORMANT on source — which is
#     exactly what we now want, because run_stage() invokes daily_box_ingest()
#     explicitly via call_fn immediately afterward.
#   * Converting it to `!interactive()` would make the ingest fire TWICE per run:
#     once on source, once via call_fn. The C-2 remedy for the four no-op stages is
#     therefore NOT the right remedy here; explicit call_fn invocation is.
#   * The guard still does its original job: `Rscript daily_ingest.R` run by hand has
#     sys.nframe() == 0 and ingests, as before.
#
# Net: under call_fn the guard is inert by design, and that inertness is required
# for correctness rather than merely tolerated. Verified in tools/test_phase4_props.R
# (CHECK L-4a/L-4b).
# ==============================================================================
if (sys.nframe() == 0) {
  daily_box_ingest()
}
