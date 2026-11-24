# ==============================================================================
# lifecycle_fixtures.R
# Shared bootstrap, assertion helper and temp-dir fixtures for the WNBA#250
# lifecycle tests (tests/unit/test_offseason_lifecycle_gate.R and
# tests/unit/test_season_lifecycle_freeze.R).
#
# Base R + jsonlite only, so the tests run on CI's package list. Every fixture is
# written to a fresh tempdir: nothing here reads or writes cache/,
# web/public/data or the real lifecycle registry. The payloads are minimal
# shapes of the real ones (the fields tools/write_data_manifest.R's coverage
# extractors read), with invented dates: they are test inputs, never published.
# ==============================================================================

lc_bootstrap <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
  if (length(f) == 1 && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) setwd(cand)
  }
  cur <- getwd()
  while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) cur <- dirname(cur)
  if (file.exists(file.path(cur, "config.R"))) setwd(cur)
  dir.create("logs", showWarnings = FALSE)
  suppressPackageStartupMessages(library(jsonlite))
  Sys.setenv(WNBA_SKIP_MANIFEST_AUTORUN = "1")
  # publish_web.R sources logging_utils.R and config.R; its CLI block runs only
  # under `Rscript tools/publish_web.R`, so sourcing it defines functions only.
  source(file.path("tools", "publish_web.R"), local = globalenv())
  source(file.path("tools", "write_data_manifest.R"), local = globalenv())
  source(file.path("tools", "freeze_season.R"), local = globalenv())
  invisible(getwd())
}

.lc_fail <- 0L
check <- function(label, cond, info = NULL) {
  if (isTRUE(cond)) {
    cat("[PASS]", label, "\n")
  } else {
    cat("[FAIL]", label, if (!is.null(info)) paste0("\n       ", paste(info, collapse = "\n       ")), "\n")
    .lc_fail <<- .lc_fail + 1L
  }
  invisible(isTRUE(cond))
}
lc_finish <- function() {
  cat(sprintf("\n%d failure(s)\n", .lc_fail))
  if (.lc_fail > 0L) quit(status = 1L)
}

quiet <- function(expr) { out <- utils::capture.output(r <- expr); attr(r, "out") <- out; r }

lc_write <- function(dir, file, obj) {
  writeLines(jsonlite::toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null"),
             file.path(dir, file), useBytes = TRUE)
}

# Long-form schedule like CACHE_WNBA_SCHEDULE: regular season, then playoffs
# through `last_done`, plus an if-necessary game that was never played.
lc_schedule <- function(last_done = "2026-10-29", unplayed = "2026-10-31", season = 2026L) {
  data.frame(
    game_date = as.Date(c("2026-05-08", "2026-09-10", "2026-10-24", last_done, unplayed)),
    season = season,
    season_type = c(2L, 2L, 3L, 3L, 3L),
    is_completed = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
}

# A fixture data dir. Payloads:
#   offseason_monitor.json         off-season live file, stamped `live_stamp`
#   playoff_bracket_2026.json      season file, last game `bracket_through`, old stamp
#   matchups_slates.json           season file, completed games through `matchups_through`
#   projections_season_teams.json  undated season file, stamped `undated_stamp`
#   cba_cap_sheet.json             archived static snapshot
lc_data_dir <- function(live_stamp = "2026-11-30T09:05:00Z",
                        bracket_through = "2026-10-24",
                        matchups_through = "2026-10-29",
                        undated_stamp = "2026-11-06T19:49:32Z",
                        extra = list()) {
  d <- tempfile("lc_data_"); dir.create(d)
  mon <- list(version = "2026-2027.1.0", editions = list())
  if (!is.null(live_stamp)) mon <- c(list(generated_at = live_stamp), mon)
  lc_write(d, "offseason_monitor.json", mon)
  lc_write(d, "playoff_bracket_2026.json", list(
    generated_at = "2026-11-01T12:00:00Z", season = 2026L,
    series = list(list(games = list(list(gameDate = "2026-10-20"), list(gameDate = bracket_through))))))
  lc_write(d, "matchups_slates.json", list(
    generated_at = "2026-11-01T12:00:00Z",
    matchups = list(list(game_date = "2026-10-20", is_completed = TRUE),
                    list(game_date = matchups_through, is_completed = TRUE))))
  lc_write(d, "projections_season_teams.json", list(generated_at = undated_stamp, teams = list()))
  lc_write(d, "cba_cap_sheet.json", list(generated_at = "2026-11-07T05:55:22Z", teams = list()))
  for (nm in names(extra)) lc_write(d, nm, extra[[nm]])
  d
}

LC_SEASON_FILES <- c("playoff_bracket_2026.json", "matchups_slates.json", "projections_season_teams.json")
LC_LIVE         <- "offseason_monitor.json"
LC_ARCHIVED     <- "cba_cap_sheet.json"

# config.R's assignment rule over the fixture's own lists and registry.
lc_assign <- function(registry_path) {
  force(registry_path)
  function(files) wnba_data_lifecycle(files, registry = wnba_read_lifecycle_registry(registry_path),
                                      offseason_live = LC_LIVE, season_files = LC_SEASON_FILES,
                                      archived_files = LC_ARCHIVED)
}

lc_schedule_rds <- function(sched = lc_schedule()) {
  p <- tempfile("lc_sched_", fileext = ".rds"); saveRDS(sched, p); p
}

# Build the manifest the way a live run would (write_data_manifest.R) over the
# fixture, with lifecycles from the fixture registry.
lc_manifest <- function(d, registry_path, sched_path = lc_schedule_rds(),
                        now = as.POSIXct("2026-11-30 09:10:00", tz = "UTC")) {
  build_data_manifest(data_dir = d, schedule_path = sched_path, now = now, previous = NULL,
                      lifecycle_fn = lc_assign(registry_path))
}

# Record one file as season_final in a fixture registry (what freeze_season.R writes).
lc_freeze_entry <- function(registry_path, d, file, season = 2026L, through = "2026-10-29") {
  reg <- wnba_read_lifecycle_registry(registry_path)
  reg$files[[file]] <- list(lifecycle = "season_final", season = season, final_through_date = through,
                            frozen_sha256 = wnba_lifecycle_sha256(file.path(d, file)),
                            frozen_at = "2026-11-24T00:00:00Z")
  writeLines(jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE, null = "null"), registry_path)
  invisible(reg)
}
