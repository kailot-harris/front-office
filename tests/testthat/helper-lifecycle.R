# ==============================================================================
# helper-lifecycle.R
# Shared bootstrap and temp-dir fixtures for the MLB-Analytics#147 lifecycle
# tests (tests/testthat/test-offseason-lifecycle-gate.R and
# tests/testthat/test-season-lifecycle-freeze.R).
#
# Every fixture is written to a fresh tempdir: nothing here reads or writes
# cache/, web/public/data, or data/season_lifecycle.json. The payloads are
# minimal shapes matching tools/write_data_manifest.R's coverage extractors,
# with invented dates: they are test inputs, never published.
# ==============================================================================

lc_bootstrap <- function() {
  if (!file.exists("config.R")) {
    if (file.exists("../../config.R")) setwd(normalizePath("../..", winslash = "/"))
    else stop("Cannot locate the project root (no config.R).", call. = FALSE)
  }
  dir.create("logs", showWarnings = FALSE)
  suppressPackageStartupMessages(library(jsonlite))
  Sys.setenv(MLB_SKIP_MANIFEST_AUTORUN = "1")
  # publish_web.R sources logging_utils.R and config.R; its CLI block runs only
  # under `Rscript tools/publish_web.R`, so sourcing it defines functions only.
  source(file.path("tools", "publish_web.R"), local = globalenv())
  source(file.path("tools", "write_data_manifest.R"), local = globalenv())
  source(file.path("tools", "freeze_season.R"), local = globalenv())
  invisible(getwd())
}

lc_quiet <- function(expr) {
  out <- utils::capture.output(r <- expr)
  attr(r, "out") <- out
  r
}

lc_write <- function(dir, file, obj) {
  writeLines(jsonlite::toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null"),
             file.path(dir, file), useBytes = TRUE)
}

# MLB-shaped schedule frame: spring training ("S"), regular season ("R"),
# postseason rounds ("D", "L", "W") through `last_done`, plus an unplayed
# World Series if-necessary game dated `unplayed`.
lc_schedule <- function(last_done = "2026-10-28", unplayed = "2026-10-31", season = 2026L) {
  data.frame(
    season = season,
    game_type = c("S", "R", "R", "D", "L", "W", "W"),
    official_date = c("2026-03-10", "2026-04-01", "2026-09-27", "2026-10-10", "2026-10-19", last_done, unplayed),
    status_detailed_state = c("Final", "Final", "Final", "Final", "Final", "Final", "Scheduled"),
    if_necessary = c("N", "N", "N", "N", "N", "N", "Y"),
    stringsAsFactors = FALSE
  )
}

# Fixture data dir using MLB's real extractor shapes:
#   offseason_monitor.json         off-season live file (uses `lastPublished`)
#   landing_digest.json            game-dated season file (yesterday[].start_time_utc)
#   world_series.json              game-dated season file (games[].game_date, static complete)
#   projections_season_teams.json  undated season file (stamped `undated_stamp`)
#   legacy_2025_archive.json       archived snapshot fixture
lc_data_dir <- function(live_stamp = "2026-11-30T09:05:00Z",
                        digest_through = "2026-10-24",
                        ws_through = "2026-10-28",
                        undated_stamp = "2026-11-06T19:49:32Z",
                        extra = list()) {
  d <- tempfile("lc_data_")
  dir.create(d)
  mon <- list(version = "2026-2027.1.0", currentWeekNumber = 15L, activePhase = "Pre-Lockout Surge")
  if (!is.null(live_stamp)) mon <- c(list(lastPublished = live_stamp), mon)
  lc_write(d, "offseason_monitor.json", mon)
  lc_write(d, "landing_digest.json", list(
    generated_at = "2026-11-01T12:00:00Z",
    yesterday = list(list(final = TRUE, start_time_utc = paste0(digest_through, "T18:00:00Z")))
  ))
  lc_write(d, "world_series.json", list(
    generated_at = "2026-11-01T12:00:00Z",
    season = 2026L,
    status = "complete",
    games = list(
      list(game_date = "2026-10-23", home_score = 3L, away_score = 2L),
      list(game_date = ws_through, home_score = 4L, away_score = 1L)
    )
  ))
  lc_write(d, "projections_season_teams.json", list(generated_at = undated_stamp, teams = list()))
  lc_write(d, "legacy_2025_archive.json", list(generated_at = "2025-11-05T00:00:00Z", teams = list()))
  for (nm in names(extra)) lc_write(d, nm, extra[[nm]])
  d
}

LC_SEASON_FILES <- c("landing_digest.json", "world_series.json", "projections_season_teams.json")
LC_LIVE         <- "offseason_monitor.json"
LC_ARCHIVED     <- "legacy_2025_archive.json"

# config.R's assignment rule over the fixture's own lists and registry.
lc_assign <- function(registry_path) {
  force(registry_path)
  function(files) {
    mlb_data_lifecycle(files,
                       registry = mlb_read_lifecycle_registry(registry_path),
                       offseason_live = LC_LIVE,
                       season_files = LC_SEASON_FILES,
                       archived_files = LC_ARCHIVED)
  }
}

lc_schedule_rds <- function(sched = lc_schedule()) {
  p <- tempfile("lc_sched_", fileext = ".rds")
  saveRDS(sched, p)
  p
}

# Build the manifest the way a live run would (write_data_manifest.R) over the
# fixture, with lifecycles from the fixture registry.
lc_manifest <- function(d, registry_path, sched_path = lc_schedule_rds(),
                        now = as.POSIXct("2026-11-30 09:10:00", tz = "UTC")) {
  sched_through <- dm_latest_completed_schedule_date(schedule_path = sched_path)
  build_data_manifest(data_dir = d,
                      schedule_through_date = sched_through,
                      now = now,
                      previous = NULL,
                      lifecycle_fn = lc_assign(registry_path))
}

# Record one file as season_final in a fixture registry (what freeze_season.R writes).
lc_freeze_entry <- function(registry_path, d, file, season = 2026L, through = "2026-10-28") {
  reg <- mlb_read_lifecycle_registry(registry_path)
  reg$files[[file]] <- list(
    lifecycle = "season_final",
    season = season,
    final_through_date = through,
    frozen_sha256 = mlb_lifecycle_sha256(file.path(d, file)),
    frozen_at = "2026-11-24T00:00:00Z"
  )
  writeLines(jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE, null = "null"),
             registry_path, useBytes = TRUE)
  invisible(reg)
}
