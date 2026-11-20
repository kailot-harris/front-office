# ==============================================================================
# WNBA Analytics - Data manifest sidecar writer
# Path: <repo root>/tools/write_data_manifest.R
#
# Refs kailot-harris/front-office#102 (per-dataset freshness manifest) and
# kailot-harris/front-office#191 (schedule-coverage lag gate).
#
# Writes web/public/data/data_manifest.json: one entry for EVERY top-level
# web/public/data/*.json payload (the manifest itself excluded), recording when
# each payload was generated, the latest game date its CONTENT actually covers,
# and whether it is an archived static snapshot that no pipeline stage rebuilds.
# tools/publish_web.R Assertion I reads this file.
#
# Stamps (FO#102): a payload's own stamp field is used when present. Otherwise
# the stamp is carried forward from the previous manifest while the payload's
# sha256 is unchanged, and set to the writer run time when the bytes change.
# File mtimes and git history are never consulted.
#
# Coverage (FO#191): through_date comes only from game dates inside the payload
# (DM_COVERAGE_EXTRACTORS). Payloads with no game dates get through_date = null,
# through_date_source = "not_game_dated" and a coverage_note; it is never
# derived from generated_at.
#
# Usage:
#   Rscript tools/write_data_manifest.R          # writes the manifest
#   source("tools/write_data_manifest.R")        # defines functions only
# Setting WNBA_SKIP_MANIFEST_AUTORUN=1 suppresses the write even under Rscript.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

DM_SCHEMA_VERSION <- 1L
DM_MANIFEST_NAME  <- "data_manifest.json"
DM_STATIC_REASON  <- "Archived static snapshot (no pipeline stage rebuilds)"

# Archived payloads (labeled in the UI as archived snapshots, WNBA#212).
DM_STATIC_DATASETS <- c(
  "cba_cap_sheet.json",
  "offseason_draft.json",
  "offseason_teams.json",
  "offseason_transactions.json"
)

.dm_or <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[[1]])) a else b

.dm_utc <- function(t) format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Parse an ISO-8601 / "YYYY-MM-DD HH:MM:SS" stamp to POSIXct UTC, NA on failure.
.dm_parse_time <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]]) || !nzchar(as.character(x[[1]]))) return(as.POSIXct(NA))
  s <- sub("Z$", "", sub("T", " ", as.character(x[[1]])))
  s <- sub("\\.[0-9]+$", "", s)
  as.POSIXct(s, tz = "UTC", tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"),
             optional = TRUE)
}

# ------------------------------------------------------------------------------
# Stamps
# ------------------------------------------------------------------------------
DM_STAMP_FIELDS <- list(
  generated_at = "generated_at",
  updated_at = "updated_at",
  generatedAt = "generatedAt",
  "metadata.generated_at" = c("metadata", "generated_at"),
  lastPublished = "lastPublished"
)

.dm_embedded_stamp <- function(j) {
  if (is.null(j) || is.null(names(j))) return(NULL)
  for (nm in names(DM_STAMP_FIELDS)) {
    v <- tryCatch(Reduce(function(o, k) if (is.list(o) && !is.null(names(o))) o[[k]] else NULL,
                         DM_STAMP_FIELDS[[nm]], j),
                  error = function(e) NULL)
    t <- .dm_parse_time(v)
    if (!is.na(t)) return(list(time = t, source = paste0("payload:", nm)))
  }
  NULL
}

.dm_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

# ------------------------------------------------------------------------------
# Coverage extractors: latest game date genuinely present in each payload.
# Fields chosen by inspecting the committed payloads.
# ------------------------------------------------------------------------------
.dm_max_date <- function(x) {
  d <- suppressWarnings(as.Date(substr(as.character(unlist(x)), 1, 10)))
  d <- d[!is.na(d)]
  if (!length(d)) NA_character_ else format(max(d))
}

DM_COVERAGE_EXTRACTORS <- list(
  "matchups_slates.json" = list(
    source = "payload:matchups[].game_date (is_completed)",
    fn = function(j) .dm_max_date(lapply(Filter(function(g) isTRUE(g$is_completed), j$matchups),
                                         `[[`, "game_date"))),
  "finals_game_predictions_2026.json" = list(
    source = "payload:games[].gameDate (resultAvailable)",
    fn = function(j) .dm_max_date(lapply(Filter(function(g) isTRUE(g$resultAvailable), j$games),
                                         `[[`, "gameDate"))),
  "finals_series_backtest_2026.json" = list(
    source = "payload:games[].gameDate",
    fn = function(j) .dm_max_date(lapply(j$games, `[[`, "gameDate"))),
  "playoff_bracket_2026.json" = list(
    source = "payload:series[].games[].gameDate",
    fn = function(j) .dm_max_date(lapply(j$series, function(s) lapply(s$games, `[[`, "gameDate")))),
  # Landing digest (WNBA#224): latest FINAL game in yesterday[]. Off-season /
  # no-final days yield NA -> not_game_dated with a coverage_note; never generated_at.
  "landing_digest.json" = list(
    source = "payload:yesterday[].game_date (final)",
    fn = function(j) .dm_max_date(lapply(Filter(function(g) isTRUE(g$final), j$yesterday),
                                         `[[`, "game_date"))),
  "offseason_transactions.json" = list(
    source = "payload:[].date",
    fn = function(j) .dm_max_date(lapply(j, `[[`, "date")))
)

DM_UNDATED_NOTES <- c(
  "playoff_series_matchups.json" = "Current-season team ratings plus historical 2022-2025 brackets; no current-season game dates",
  "offseason_monitor.json" = "Off-season edition calendar; not game-dated",
  "projections_models_metadata.json" = "Model metadata catalog; not game-dated",
  "projections_diagnostics.json" = "Aggregate calibration diagnostics; no per-game dates",
  "projections_season_teams.json" = "Season-long team projections; no game dates",
  "projections_season_players.json" = "Season-long player projections; no game dates",
  "shots_index.json" = "Player shot-file index; not game-dated",
  "shots_metadata.json" = "League shot-zone averages; no game dates",
  "clutch_leverage_metrics.json" = "Season player profiles; no game dates",
  "coaching_metrics.json" = "Coaching staff profiles; no game dates",
  "defensive_metrics.json" = "Season player profiles; no game dates",
  "player_dna_profiles.json" = "Season player profiles; no game dates",
  "cba_cap_sheet.json" = "Cap sheet; not game-dated",
  "offseason_draft.json" = "Draft order; not game-dated",
  "offseason_teams.json" = "Team off-season profiles; not game-dated"
)

.dm_read_previous <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

#' Latest completed game date in the schedule cache, or NA when the cache is
#' absent/unreadable (offline CI). Returns a Date.
dm_latest_completed_schedule_date <- function(schedule_path = file.path("cache", "wnba_schedule_cache.rds"),
                                              season = NULL) {
  if (is.null(schedule_path) || !file.exists(schedule_path)) return(as.Date(NA))
  s <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(s) || !"game_date" %in% names(s)) return(as.Date(NA))
  if (!is.null(season) && "season" %in% names(s)) {
    s <- s[!is.na(s$season) & as.integer(s$season) == as.integer(season), , drop = FALSE]
  }
  if ("is_completed" %in% names(s)) {
    s <- s[!is.na(s$is_completed) & as.logical(s$is_completed), , drop = FALSE]
  }
  if (!nrow(s)) return(as.Date(NA))
  d <- suppressWarnings(as.Date(substr(as.character(s$game_date), 1, 10)))
  if (all(is.na(d))) return(as.Date(NA))
  max(d, na.rm = TRUE)
}

#' Build the manifest as an R list (does not write). `previous` defaults to the
#' manifest already on disk and drives content-hash carry-forward.
build_data_manifest <- function(data_dir = file.path("web", "public", "data"),
                                schedule_path = file.path("cache", "wnba_schedule_cache.rds"),
                                static_datasets = DM_STATIC_DATASETS,
                                now = Sys.time(),
                                previous = .dm_read_previous(file.path(data_dir, DM_MANIFEST_NAME)),
                                extractors = DM_COVERAGE_EXTRACTORS) {
  files <- sort(list.files(data_dir, pattern = "\\.json$", full.names = FALSE))
  files <- setdiff(files, DM_MANIFEST_NAME)
  sched_date <- dm_latest_completed_schedule_date(schedule_path)
  prev_entries <- if (!is.null(previous)) previous$datasets else list()
  names(prev_entries) <- vapply(prev_entries, function(e) as.character(.dm_or(e$file, "")), character(1))

  datasets <- lapply(files, function(f) {
    p <- file.path(data_dir, f)
    j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    sha <- .dm_sha256(p)
    st <- .dm_embedded_stamp(j)
    if (!is.null(st)) {
      gen <- .dm_utc(st$time); stamp_src <- st$source
    } else {
      pe <- prev_entries[[f]]
      gen <- if (!is.null(pe) && identical(pe$content_sha256, sha) && !is.null(pe$generated_at))
        pe$generated_at else .dm_utc(now)
      stamp_src <- "manifest:content_hash"
    }
    is_static <- f %in% static_datasets
    ex <- extractors[[f]]
    through <- if (!is.null(ex) && !is.null(j)) tryCatch(ex$fn(j), error = function(e) NA_character_) else NA_character_
    if (is.na(through)) {
      through_src <- "not_game_dated"
      note <- if (identical(f, "landing_digest.json")) "No final game in yesterday[] (off-season or no games yesterday)" else
        if (!is.null(ex)) "Extractor found no game date in payload" else
        .dm_or(unname(DM_UNDATED_NOTES[f]), "No game-dated field in payload")
    } else {
      through_src <- ex$source
      note <- NULL
    }
    lag <- if (is_static || is.na(sched_date) || is.na(through)) NULL else as.integer(sched_date - as.Date(through))
    entry <- list(
      file = f,
      generated_at = gen,
      stamp_source = stamp_src,
      content_sha256 = sha,
      through_date = if (is.na(through)) NULL else through,
      through_date_source = through_src,
      coverage_note = note,
      builder = if (is_static) "archived" else "run_full_pipeline.R",
      static = is_static
    )
    if (is_static) entry$static_reason <- DM_STATIC_REASON
    if (!is.null(lag)) entry$lag_days <- lag
    entry
  })

  sched_str <- if (is.na(sched_date)) NULL else format(sched_date)
  # Top-level generated_at moves only when some entry (or the schedule date) changed.
  top_gen <- .dm_utc(now)
  if (!is.null(previous) && !is.null(previous$generated_at)) {
    enc <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
    if (identical(enc(previous$datasets), enc(datasets)) &&
        identical(previous$schedule_through_date, sched_str)) {
      top_gen <- previous$generated_at
    }
  }

  list(
    schema_version = DM_SCHEMA_VERSION,
    sport = "wnba",
    generated_at = top_gen,
    schedule_through_date = sched_str,
    datasets = datasets
  )
}

#' Build and write the manifest. Returns the output path invisibly.
write_data_manifest <- function(data_dir = file.path("web", "public", "data"),
                                schedule_path = file.path("cache", "wnba_schedule_cache.rds"),
                                ...) {
  m <- build_data_manifest(data_dir = data_dir, schedule_path = schedule_path, ...)
  out <- file.path(data_dir, DM_MANIFEST_NAME)
  txt <- jsonlite::toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(txt, out, useBytes = TRUE)
  invisible(out)
}

# ------------------------------------------------------------------------------
# CLI guard: only runs under `Rscript tools/write_data_manifest.R`.
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (interactive() || !any(grepl("write_data_manifest\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("WNBA_SKIP_MANIFEST_AUTORUN"))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(root, "config.R"))) setwd(root)
  out <- write_data_manifest()
  m <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  cat(sprintf("Wrote %s (%d datasets, schedule_through_date=%s)\n", out, length(m$datasets),
              if (is.null(m$schedule_through_date)) "null" else m$schedule_through_date))
})
