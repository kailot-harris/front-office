# ==============================================================================
# Automated Daily Play-by-Play / Schedule Ingestion Pipeline (NFL)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/daily_ingest.R
#
# Ported from WNBA Analytics/daily_ingest.R (bootstrap-if-cache-missing, then
# incremental current-season fetch + dedupe idiom). wehoop::load_wnba_team_box()
# is replaced with nflreadr::load_pbp() / nflreadr::load_schedules() - there is
# no WNBA-style non-franchise exhibition-row filtering step here because
# nflreadr's pbp/schedule feeds don't carry that quirk (no filter_real_franchises()
# equivalent is needed).
#
# Per this repo's CLAUDE.md ("Process / conventions") and
# docs/NFL_REPLICATION_PLAN.md §1's sys.nframe()==0 guard failure-mode discussion,
# this script does NOT auto-run on source via a `sys.nframe() == 0` footer (unlike
# the WNBA original). The sole callable is run_daily_ingest(), invoked explicitly
# by run_full_pipeline.R's run_stage() via call_fn.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(nflreadr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "daily_ingest.R"

# ------------------------------------------------------------------------------------------
# Internal helper: bootstrap-or-update a single cache file against a season-parameterized
# nflreadr loader, deduping on the given key column(s). Shared by the PBP and schedules
# halves of run_daily_ingest() so the bootstrap/incremental-update shape (analogous to
# WNBA's daily_box_ingest()) isn't duplicated twice with a chance to drift out of sync.
# ------------------------------------------------------------------------------------------
.ingest_one <- function(cache_path, loader_fn, loader_name, dedupe_keys,
                         force_refresh = FALSE) {
  needs_bootstrap <- force_refresh || !file.exists(cache_path)

  if (needs_bootstrap) {
    log_info(sprintf(
      "%s: cache missing or force_refresh=TRUE. Initializing complete historical ingestion (%d:%d)...",
      loader_name, min(ALL_SEASONS), max(ALL_SEASONS)
    ))
    existing <- tryCatch({
      loader_fn(seasons = ALL_SEASONS)
    }, error = function(e) {
      log_error(sprintf("Initial historical %s bootstrap failed.", loader_name), condition = e,
                call = "run_daily_ingest()", seasons = paste(range(ALL_SEASONS), collapse = "-"))
      stop(e)
    })
    existing <- existing |> distinct(across(all_of(dedupe_keys)), .keep_all = TRUE)
    saveRDS(existing, cache_path)
    log_info(sprintf("Bootstrapped %s cache with %d records.", loader_name, nrow(existing)),
             call = "run_daily_ingest()", rows = nrow(existing), out_path = cache_path)
    return(invisible(existing))
  }

  existing <- readRDS(cache_path)
  log_info(sprintf("%s: loaded existing cache with %d records.", loader_name, nrow(existing)))

  log_info(sprintf("Fetching %s updates for season %d...", loader_name, CURRENT_SEASON),
           call = "run_daily_ingest()", season = CURRENT_SEASON)
  new_rows <- tryCatch({
    loader_fn(seasons = CURRENT_SEASON)
  }, error = function(e) {
    log_warn(sprintf("Error loading current-season %s: %s", loader_name, conditionMessage(e)))
    log_error(sprintf("%s failed for season %d.", loader_name, CURRENT_SEASON),
              condition = e, call = "run_daily_ingest()", season = CURRENT_SEASON)
    NULL
  })

  if (is.null(new_rows) || nrow(new_rows) == 0) {
    log_warn(sprintf("%s: no records returned from API for current season.", loader_name),
             call = "run_daily_ingest()", season = CURRENT_SEASON)
    return(invisible(existing))
  }
  log_info(sprintf("%s: fetched %d current-season rows.", loader_name, nrow(new_rows)),
           call = "run_daily_ingest()", rows = nrow(new_rows), season = CURRENT_SEASON)

  combined <- bind_rows(existing, new_rows) |>
    distinct(across(all_of(dedupe_keys)), .keep_all = TRUE)

  n_new_records <- nrow(combined) - nrow(existing)
  log_info(sprintf("%s: ingestion complete. %d new records identified.", loader_name, n_new_records))

  if (n_new_records > 0) {
    saveRDS(combined, cache_path)
    log_info(sprintf("Updated %s cache with %d new records (%d total).",
                      loader_name, n_new_records, nrow(combined)),
             call = "run_daily_ingest()", new_records = n_new_records, total_rows = nrow(combined),
             out_path = cache_path)
  } else {
    log_info(sprintf("%s cache already up to date; no write necessary.", loader_name),
             call = "run_daily_ingest()")
  }

  invisible(combined)
}

# ------------------------------------------------------------------------------------------
# run_daily_ingest(force_refresh = FALSE)
#
# Sole exposed entry point (per docs/task_assignments_phase0.md's Interface Contracts table).
# No required args. Pulls current-season play-by-play (nflreadr::load_pbp()) and schedule
# (nflreadr::load_schedules()) data; on first run (either cache file missing) or when called
# with force_refresh = TRUE, pulls full history per config.R's ALL_SEASONS instead. Writes to
# CACHE_PBP and CACHE_SCHEDULES. Dedupe keys: game_id + play_id for PBP, game_id for schedules.
# Returns TRUE on success, FALSE if either sub-ingest fails without stop()ping (mirrors the
# run_stage() try/catch contract used by run_full_pipeline.R).
# ------------------------------------------------------------------------------------------
run_daily_ingest <- function(force_refresh = FALSE) {
  log_info("Starting daily NFL play-by-play / schedule ingestion...")

  ok <- TRUE

  pbp_result <- tryCatch({
    .ingest_one(
      cache_path    = CACHE_PBP,
      loader_fn     = nflreadr::load_pbp,
      loader_name   = "nflreadr::load_pbp()",
      dedupe_keys   = c("game_id", "play_id"),
      force_refresh = force_refresh
    )
    TRUE
  }, error = function(e) {
    log_error("PBP ingestion failed.", condition = e, call = "run_daily_ingest()")
    FALSE
  })
  ok <- ok && isTRUE(pbp_result)

  sched_result <- tryCatch({
    .ingest_one(
      cache_path    = CACHE_SCHEDULES,
      loader_fn     = nflreadr::load_schedules,
      loader_name   = "nflreadr::load_schedules()",
      dedupe_keys   = c("game_id"),
      force_refresh = force_refresh
    )
    TRUE
  }, error = function(e) {
    log_error("Schedule ingestion failed.", condition = e, call = "run_daily_ingest()")
    FALSE
  })
  ok <- ok && isTRUE(sched_result)

  if (ok) {
    log_info("Daily NFL ingestion completed successfully.", call = "run_daily_ingest()")
  } else {
    log_warn("Daily NFL ingestion completed with one or more failures.", call = "run_daily_ingest()")
  }

  invisible(ok)
}
