# ==============================================================================
# Automated Daily Box Score Ingestion Pipeline (WNBA)
# Path: daily_ingest.R
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

# ==============================================================================
# SCHEDULE INGESTION + REST / BACK-TO-BACK DERIVATION (GitHub issue #93)
#
# WHY IT LIVES HERE (and not in fatigue_travel_engine.R): rest is a property of the
# SCHEDULE, not of the fatigue model. Deriving it at ingest time means (a) the
# normalization-then-filter rule for team codes is applied exactly once, in the same
# file that owns normalize_team_abbreviation(), and (b) every future consumer
# (fatigue, props, Finals per-game) reads one cached, already-correct frame instead of
# re-deriving rest from raw wehoop columns and getting it subtly different.
#
# WHY A SCHEDULE AT ALL: CACHE_TEAM_BOX only contains games that have been PLAYED, so
# rest computed from it is a retrodiction. wehoop::load_wnba_schedule() includes future
# games (`status_type_completed == FALSE`, `status_type_state == "pre"`), which is the
# only way to know a team's rest before a game is played.
#
# SHAPE: the raw schedule is one row per GAME with home_abbreviation/away_abbreviation.
# It is pivoted to one row per TEAM per GAME so that (i) normalize_team_abbreviation()
# applies (it keys on `team_abbreviation` / `opponent_team_abbreviation`, and is used
# as-is -- never reimplemented), and (ii) days_rest / is_back_to_back are per-team
# quantities and only make sense in long form.
# ==============================================================================

# ESPN/wehoop status_type_name values for games that were postponed or cancelled
# and therefore never played (and involved no team travel).
is_non_played_schedule_status <- function(status_type_name) {
  s <- tolower(dplyr::coalesce(as.character(status_type_name), ""))
  grepl("postpon|cancel", s)
}

# Long-form (one row per team per game) view of the raw wehoop schedule.
schedule_to_long <- function(sched) {
  req <- c("game_id", "game_date", "home_abbreviation", "away_abbreviation")
  if (!all(req %in% names(sched))) {
    log_warn(sprintf("Schedule frame missing expected columns (%s); cannot pivot to long form.",
                     paste(setdiff(req, names(sched)), collapse = ", ")))
    return(NULL)
  }
  completed <- if ("status_type_completed" %in% names(sched)) as.logical(sched$status_type_completed) else NA
  base <- tibble::tibble(
    game_id      = as.character(sched$game_id),
    game_date    = as.Date(sched$game_date),
    season       = if ("season" %in% names(sched)) sched$season else NA_integer_,
    season_type  = if ("season_type" %in% names(sched)) sched$season_type else NA_integer_,
    home_abbreviation = sched$home_abbreviation,
    away_abbreviation = sched$away_abbreviation,
    is_completed = dplyr::coalesce(completed, FALSE),
    status_type_name = if ("status_type_name" %in% names(sched)) as.character(sched$status_type_name) else NA_character_,
    notes_headline = if ("notes_headline" %in% names(sched)) sched$notes_headline else NA_character_
  )

  home_rows <- base |>
    transmute(game_id, game_date, season, season_type, is_completed, status_type_name, notes_headline,
              team_abbreviation = home_abbreviation,
              opponent_team_abbreviation = away_abbreviation,
              is_home = TRUE,
              venue_team = home_abbreviation)
  away_rows <- base |>
    transmute(game_id, game_date, season, season_type, is_completed, status_type_name, notes_headline,
              team_abbreviation = away_abbreviation,
              opponent_team_abbreviation = home_abbreviation,
              is_home = FALSE,
              venue_team = home_abbreviation)

  bind_rows(home_rows, away_rows)
}

# For each row i, return the value from the most recent prior row j < i where active[j] is TRUE.
.carry_forward_active <- function(vals, active) {
  out <- rep(vals[NA_integer_], length(vals))
  last_val <- vals[NA_integer_]
  for (i in seq_along(vals)) {
    out[i] <- last_val
    if (isTRUE(active[i])) last_val <- vals[i]
  }
  out
}

# days_rest / is_back_to_back per team per scheduled game.
#
# days_rest = calendar days between a team's previous active (non-postponed/cancelled)
# scheduled game and this one, MINUS 1 (so consecutive calendar days -> 0 days of rest,
# i.e. a back-to-back; one idle day in between -> 1). is_back_to_back is exactly
# days_rest == 0, which is the condition calculate_travel_fatigue()'s b2b_tax and
# altitude tax already branch on. A team's first game of the season has no predecessor:
# days_rest is left NA and is_back_to_back FALSE (no fabricated rest value).
#
# Postponed/cancelled games (e.g. 2026-07-16 DAL vs NY game_id 401857072, STATUS_POSTPONED,
# made up 2026-07-20 under 401892393; #259) were never played and involved no travel, so
# they are skipped when carrying forward prev_game_date/prev_venue and receive NA rest.
#
# last_played_at = the TEAM CODE OF THE VENUE of that team's previous game (the previous
# game's home team), which is the travel ORIGIN argument calculate_travel_fatigue()
# expects. For a team's first game it falls back to its own code (i.e. zero travel).
derive_rest_features <- function(sched_long) {
  has_status <- "status_type_name" %in% names(sched_long)
  sched_long |>
    mutate(.active_game = if (has_status) !is_non_played_schedule_status(status_type_name) else TRUE) |>
    arrange(team_abbreviation, game_date, game_id) |>
    group_by(team_abbreviation) |>
    mutate(
      prev_game_date = .carry_forward_active(game_date, .active_game),
      prev_venue     = .carry_forward_active(venue_team, .active_game),
      days_rest      = if_else(.active_game, as.integer(as.numeric(game_date - prev_game_date) - 1), NA_integer_),
      is_back_to_back = if_else(.active_game, dplyr::coalesce(days_rest == 0, FALSE), FALSE),
      last_played_at = if_else(.active_game, dplyr::coalesce(prev_venue, team_abbreviation), NA_character_)
    ) |>
    ungroup() |>
    select(-".active_game") |>
    arrange(game_date, game_id, desc(is_home))
}

# Keep a played game "completed" across schedule re-ingests.
#
# ROOT CAUSE this guards (#253): the schedule feed (wehoop) can lag ESPN, so a game that
# is already FINAL in the box-score cache (or was already completed in the previous
# schedule cache) can come back with status_type_completed == FALSE. daily_schedule_ingest()
# used to overwrite CACHE_WNBA_SCHEDULE wholesale from the feed, which silently undid the
# one-off patch from tools/espn_game7_fallback.R and flipped 2026 Finals Game 7 back to
# not completed.
#
# Completion is only ever RAISED here, and only on evidence some source reported:
#   * a final box score: the game has a box row for BOTH sides with a non-NA team_score
#   * the previous schedule cache already had it completed (a source reported that earlier)
# It never touches any other column and never invents a score or status.
reconcile_schedule_completed <- function(sched_long, box = NULL, prior_sched = NULL) {
  if (is.null(sched_long) || nrow(sched_long) == 0 || !"is_completed" %in% names(sched_long)) {
    return(sched_long)
  }
  ids <- as.character(sched_long$game_id)

  final_ids <- character(0)
  if (!is.null(box) && all(c("game_id", "team_score") %in% names(box))) {
    scored <- box[!is.na(box$team_score), , drop = FALSE]
    n_sides <- tapply(seq_len(nrow(scored)), as.character(scored$game_id), length)
    final_ids <- names(n_sides)[n_sides >= 2L]
  }
  prior_ids <- character(0)
  if (!is.null(prior_sched) && all(c("game_id", "is_completed") %in% names(prior_sched))) {
    prior_ids <- unique(as.character(prior_sched$game_id[prior_sched$is_completed %in% TRUE]))
  }

  keep <- ids %in% union(final_ids, prior_ids)
  flip <- keep & !(sched_long$is_completed %in% TRUE)
  if (any(flip)) {
    log_info(sprintf("Schedule reconcile: kept %d team-game row(s) completed (game_id %s) that the feed reported as not completed.",
                     sum(flip), paste(unique(ids[flip]), collapse = ", ")),
             call = "reconcile_schedule_completed()")
    sched_long$is_completed[flip] <- TRUE
  }
  sched_long
}

# Fetch + cache the schedule. Fail-safe: any error or empty response leaves any existing
# cache untouched and returns NULL; it never stops the ingest pipeline.
daily_schedule_ingest <- function(season = CURRENT_SEASON) {
  log_info(sprintf("Fetching wehoop::load_wnba_schedule() for season %d...", season),
           call = "daily_schedule_ingest()", season = season)

  raw <- tryCatch({
    wehoop::load_wnba_schedule(seasons = season)
  }, error = function(e) {
    log_warn(sprintf("Error loading WNBA schedule: %s", e$message))
    log_error(sprintf("wehoop::load_wnba_schedule() failed for season %d.", season),
              condition = e, call = "daily_schedule_ingest()", season = season)
    return(NULL)
  })

  if (is.null(raw) || nrow(raw) == 0) {
    log_warn("Schedule fetch returned no rows; leaving any existing schedule cache in place.",
             call = "daily_schedule_ingest()", season = season)
    return(invisible(NULL))
  }

  sched_long <- schedule_to_long(raw)
  if (is.null(sched_long) || nrow(sched_long) == 0) {
    log_warn("Schedule frame could not be pivoted to long form; schedule cache not written.",
             call = "daily_schedule_ingest()", season = season)
    return(invisible(NULL))
  }

  # NORMALIZE FIRST, THEN FILTER -- never the other way round. filter_real_franchises()
  # calls normalize_team_abbreviation() (CONN -> CON) before the
  # `%in% names(WNBA_TEAMS)` franchise filter; filtering first would silently discard
  # real Connecticut Sun rows along with the exhibition/All-Star rows.
  sched_long <- filter_real_franchises(sched_long)
  sched_long <- sched_long |> filter(opponent_team_abbreviation %in% names(WNBA_TEAMS))

  sched_long <- derive_rest_features(sched_long)

  # Never let a lagging feed flip a played game back to not completed (#253).
  box_cache  <- if (file.exists(CACHE_TEAM_BOX)) tryCatch(readRDS(CACHE_TEAM_BOX), error = function(e) NULL) else NULL
  prior_cache <- if (file.exists(CACHE_WNBA_SCHEDULE)) tryCatch(readRDS(CACHE_WNBA_SCHEDULE), error = function(e) NULL) else NULL
  sched_long <- reconcile_schedule_completed(sched_long, box = box_cache, prior_sched = prior_cache)

  saveRDS(sched_long, CACHE_WNBA_SCHEDULE)
  n_unplayed <- sum(!sched_long$is_completed)
  log_info(sprintf(
    "Wrote schedule cache: %d team-game rows (%d unplayed), dates %s to %s.",
    nrow(sched_long), n_unplayed,
    as.character(min(sched_long$game_date, na.rm = TRUE)),
    as.character(max(sched_long$game_date, na.rm = TRUE))
  ), call = "daily_schedule_ingest()", rows = nrow(sched_long),
     unplayed_rows = n_unplayed, out_path = CACHE_WNBA_SCHEDULE)

  invisible(sched_long)
}

daily_box_ingest <- function() {
  log_info("Starting daily WNBA box score ingestion...")

  # 0. Schedule ingest (issue #93). Deliberately inside this function rather than as a
  # new DAG stage: the daily_ingest stage is invoked by `call_fn = "daily_box_ingest"`
  # (see pipeline_stages.R), so extending it here needs no DAG change and cannot
  # double-execute. Wrapped so a schedule-feed outage never blocks box ingestion.
  tryCatch(daily_schedule_ingest(), error = function(e) {
    log_warn(sprintf("Schedule ingest failed (non-fatal): %s", e$message))
    NULL
  })

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
