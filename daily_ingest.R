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
# ------------------------------------------------------------------------------------------
# Memory-reduction Option 2 (docs/memory_optimization_plan.md, item done inline here rather
# than as a separate doc since it shipped immediately - see that file for Options 3-5, which
# are planned but not yet implemented). nflreadr::load_pbp() returns 372 raw columns per play
# (live-verified 2026-09-17: the full CACHE_PBP object is 3.4GB in memory for 1.14M rows,
# ~311MB on disk). epa_metrics_engine.R - CACHE_PBP's ONLY real consumer, confirmed via a
# repo-wide grep - only ever touches 9 of those columns (posteam, defteam, epa, success, cpoe,
# game_id, game_date, season, week). .PBP_CACHE_COLUMNS below is that set plus a modest,
# documented margin of cheap, commonly-useful play-level fields (situational/opponent-adjusted
# EPA features flagged in the Phase 4 model-quality roadmap will likely want down/ydstogo/
# yardline_100/play_type) - trimmed to this whitelist, CACHE_PBP drops to ~167MB in memory
# (~95% reduction), which was the direct cause of two OS-level low-memory process kills during
# a full run_full_pipeline.R run (both died inside .ingest_one()'s bind_rows(existing, new_rows)
# step below, which transiently holds TWO full copies of `existing` at once).
#
# Widening this list later (a new feature needs a column not on it) requires a one-time
# force_refresh = TRUE re-bootstrap (or tools/migrate_pbp_cache_trim.R-style one-off script) to
# pull the dropped column back in for historical rows - narrowing it is instant (just drop the
# name here), the cache self-heals to the smaller shape on its next real incremental update.
# ------------------------------------------------------------------------------------------
.PBP_CACHE_COLUMNS <- c(
  "game_id", "play_id", "game_date", "season", "week", "season_type", "game_type",
  "home_team", "away_team", "posteam", "defteam", "posteam_type",
  "play_type", "pass", "down", "ydstogo", "yardline_100", "qtr",
  "epa", "success", "cpoe"
)

.ingest_one <- function(cache_path, loader_fn, loader_name, dedupe_keys,
                         force_refresh = FALSE, select_cols = NULL) {
  needs_bootstrap <- force_refresh || !file.exists(cache_path)

  .trim <- function(df) {
    if (is.null(select_cols)) return(df)
    df |> select(any_of(select_cols))
  }

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
    existing <- .trim(existing) |> distinct(across(all_of(dedupe_keys)), .keep_all = TRUE)
    saveRDS(existing, cache_path)
    log_info(sprintf("Bootstrapped %s cache with %d records (%d columns).", loader_name, nrow(existing), ncol(existing)),
             call = "run_daily_ingest()", rows = nrow(existing), out_path = cache_path)
    return(invisible(existing))
  }

  existing <- readRDS(cache_path)
  n_cols_before_trim <- ncol(existing)
  existing <- .trim(existing)
  # Memory-reduction Option 2: if the on-disk cache still has the old wide shape (pre-trim),
  # persist the trim immediately even with zero new NFL rows this run, so the file/memory
  # footprint shrinks on the VERY NEXT run_daily_ingest() call rather than waiting for real new
  # play data to arrive (which could be days, for an off-week).
  needs_retrim_save <- !is.null(select_cols) && n_cols_before_trim > ncol(existing)
  log_info(sprintf("%s: loaded existing cache with %d records (%d columns%s).",
                    loader_name, nrow(existing), ncol(existing),
                    if (needs_retrim_save) ", trimmed down from a wider cached shape this run" else ""))

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
    if (needs_retrim_save) {
      saveRDS(existing, cache_path)
      log_info(sprintf("Re-saved %s cache in its trimmed shape (no new records this run).", loader_name),
               call = "run_daily_ingest()", out_path = cache_path)
    }
    return(invisible(existing))
  }
  new_rows <- .trim(new_rows)
  log_info(sprintf("%s: fetched %d current-season rows.", loader_name, nrow(new_rows)),
           call = "run_daily_ingest()", rows = nrow(new_rows), season = CURRENT_SEASON)

  combined <- bind_rows(existing, new_rows) |>
    distinct(across(all_of(dedupe_keys)), .keep_all = TRUE)

  n_new_records <- nrow(combined) - nrow(existing)
  log_info(sprintf("%s: ingestion complete. %d new records identified.", loader_name, n_new_records))

  if (n_new_records > 0 || needs_retrim_save) {
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
      force_refresh = force_refresh,
      select_cols   = .PBP_CACHE_COLUMNS
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
