# ==============================================================================
# tools/write_data_manifest.R
#
# Writes the sidecar web/public/data/data_manifest.json (front-office#102):
# one entry for EVERY top-level web/public/data/*.json payload. Per entry:
#
#   generated_at        UTC ISO-8601. Taken from the payload's own embedded
#                       stamp when it has one (stamp_source "payload:<field>").
#                       A payload with no embedded stamp is identified by its
#                       content_sha256: if the previous manifest lists the same
#                       file with the same hash, its generated_at is carried
#                       forward unchanged, otherwise the writer's run time is
#                       used (stamp_source "manifest:content_hash"). File
#                       mtimes and git history are never read.
#   through_date        Latest game date actually present in the payload's
#                       CONTENT (through_date_source "payload:<field path>"),
#                       never derived from generated_at. Payloads that are not
#                       game-dated get through_date null, through_date_source
#                       "not_game_dated" and a coverage_note.
#   static/static_reason  explicit exemption from the lag gate.
#
# `schedule_through_date` is the latest completed slate game in the cached
# season schedule (null offline), so publish_web.R assertion H
# (front-office#191) can measure how far each dataset lags the schedule.
#
# Usage:
#   Rscript tools/write_data_manifest.R
#   Rscript -e "source('tools/write_data_manifest.R'); str(build_data_manifest())"
# ==============================================================================

DM_SCHEMA_VERSION <- 1L
DM_SPORT <- "mlb"
DM_MANIFEST_FILE <- "data_manifest.json"
DM_BUILDER <- "tools/write_data_manifest.R"

# Local NULL-default helper (the repo's canonical NULL-coalescing operator lives in logging_utils.R,
# which this builder does not require).
.dm_or <- function(a, b) if (is.null(a)) b else a

# Embedded stamp fields, in priority order (path within the parsed payload).
DM_STAMP_FIELDS <- list(
  "generated_at"          = c("generated_at"),
  "generatedAt"           = c("generatedAt"),
  "updated_at"            = c("updated_at"),
  "updatedAt"             = c("updatedAt"),
  "metadata.generated_at" = c("metadata", "generated_at"),
  "lastPublished"         = c("lastPublished")
)

.dm_is_ymd <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", x)
}

# ------------------------------------------------------------------------------
# Coverage extractors: filename -> function(parsed payload) returning the
# latest game date (YYYY-MM-DD) present in the content, or NA when none.
# Chosen by inspecting the real payloads: only world_series.json carries
# per-game dates at top level. Everything else is listed in
# DM_NOT_GAME_DATED with the reason.
# ------------------------------------------------------------------------------
DM_COVERAGE_EXTRACTORS <- list(
  # Landing digest (front-office#200): the latest FINAL game in yesterday[],
  # dated in US Eastern from its start_time_utc. Never generated_at/slate_date.
  "landing_digest.json" = list(
    field = "yesterday[].start_time_utc (final games, US Eastern date)",
    fn = function(j) {
      d <- vapply(.dm_or(j$yesterday, list()), function(g) {
        if (isTRUE(g$final) && is.character(g$start_time_utc)) {
          t <- as.POSIXct(substr(g$start_time_utc, 1L, 19L), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
          if (is.na(t)) NA_character_ else format(t, "%Y-%m-%d", tz = "America/New_York")
        } else NA_character_
      }, character(1))
      d <- d[!is.na(d)]
      if (length(d)) max(d) else NA_character_
    }
  ),
  "world_series.json" = list(
    field = "games[].game_date (scored games)",
    fn = function(j) {
      d <- vapply(.dm_or(j$games, list()), function(g) {
        if (.dm_is_ymd(g$game_date) && !is.null(g$home_score) && !is.null(g$away_score)) {
          substr(g$game_date, 1L, 10L)
        } else NA_character_
      }, character(1))
      d <- d[!is.na(d)]
      if (length(d)) max(d) else NA_character_
    }
  )
)

DM_NOT_GAME_DATED <- c(
  "cbt_payroll_sheet.json"           = "payroll / luxury-tax sheet; no game dates in content",
  "clutch_leverage_metrics.json"     = "season-aggregate leverage metrics; no per-game dates in content",
  "matchups_index.json"              = "index of week ranges (start/end of the calendar week), not played-game dates; game dates live in matchups/week-NN.json",
  "offseason_monitor.json"           = "off-season transaction monitor; dates are transactions/milestones, not games",
  "player_dna_profiles.json"         = "player profile catalog; no game dates in content",
  "playoff_series_matchups.json"     = "series simulation catalog; no game dates in content",
  "projections_diagnostics.json"     = "model diagnostics; no game dates in content",
  "projections_models_metadata.json" = "model metadata catalog; no game dates in content",
  "projections_postseason_ops.json"  = "postseason odds aggregates; no game dates in content",
  "projections_season_players.json"  = "player projection table; no game dates in content",
  "projections_season_teams.json"    = "team projection table; no game dates in content",
  "spatial_index.json"               = "index of per-player spatial files; no game dates in content",
  "statcast_spatial_analytics.json"  = "season-aggregate Statcast spatial metrics; no game dates in content"
)

.dm_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1 && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) return(cand)
  }
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "config.R"))) return(d)
    p <- dirname(d)
    if (identical(p, d)) break
    d <- p
  }
  NA_character_
}

.dm_fmt_utc <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

.dm_parse_utc <- function(x) {
  if (is.null(x) || !is.character(x) || !length(x) || is.na(x[1]) || !nzchar(x[1])) return(NA)
  as.POSIXct(x[1], format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
}

.dm_get_path <- function(obj, path) {
  for (k in path) {
    if (!is.list(obj) || is.null(names(obj))) return(NULL)
    obj <- obj[[k]]
  }
  obj
}

.dm_embedded_stamp <- function(obj) {
  for (nm in names(DM_STAMP_FIELDS)) {
    t <- .dm_parse_utc(.dm_get_path(obj, DM_STAMP_FIELDS[[nm]]))
    if (!is.na(t)) return(list(time = t, source = paste0("payload:", nm)))
  }
  NULL
}

.dm_sha256 <- function(path) unname(as.character(tools::sha256sum(path)))

# Latest completed slate-game date in the cached season schedule, or
# NA_character_ when the cache is absent/unreadable (offline CI).
dm_latest_completed_schedule_date <- function(season = NULL, schedule_path = NULL) {
  if (is.null(schedule_path)) {
    if (!exists("cache_path", mode = "function") || !exists("MLB_CURRENT_SEASON")) {
      return(NA_character_)
    }
    if (is.null(season)) season <- get("MLB_CURRENT_SEASON")
    # create = FALSE: building the manifest must not create cache directories.
    schedule_path <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", as.integer(season)),
                                create = FALSE)
  }
  if (!file.exists(schedule_path)) return(NA_character_)
  s <- tryCatch(as.data.frame(readRDS(schedule_path), stringsAsFactors = FALSE),
                error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(NA_character_)
  date_col <- intersect(c("official_date", "game_date", "date"), names(s))[1]
  if (is.na(date_col)) return(NA_character_)
  if ("game_type" %in% names(s)) {
    types <- if (exists("MATCHUP_GAME_TYPES")) get("MATCHUP_GAME_TYPES") else c("R", "F", "D", "L", "W")
    s <- s[as.character(s$game_type) %in% types, , drop = FALSE]
  }
  d <- suppressWarnings(as.Date(substr(as.character(s[[date_col]]), 1L, 10L)))
  status_col <- intersect(c("status_detailed_state", "status", "status_abstract_game_state"), names(s))[1]
  done <- if (!is.na(status_col)) {
    grepl("^(Final|Completed Early|Game Over)", as.character(s[[status_col]]), ignore.case = TRUE)
  } else {
    !is.na(d) & d < Sys.Date()
  }
  d <- d[done & !is.na(d)]
  if (!length(d)) return(NA_character_)
  format(max(d), "%Y-%m-%d")
}

.dm_static_info <- function(file, obj) {
  if (identical(file, "world_series.json") && is.list(obj) && identical(obj$status, "complete")) {
    return(list(static = TRUE,
                reason = sprintf("World Series %s complete; payload is final until the next postseason",
                                 as.character(.dm_or(obj$season, "")))))
  }
  list(static = FALSE, reason = NULL)
}

.dm_read_previous <- function(path) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

build_data_manifest <- function(data_dir = NULL, schedule_through_date = NULL,
                                now = Sys.time(), previous = NULL,
                                extractors = DM_COVERAGE_EXTRACTORS) {
  if (is.null(data_dir)) {
    data_dir <- if (exists("WEB_DATA_DIR")) get("WEB_DATA_DIR") else file.path("web", "public", "data")
  }
  if (is.null(previous)) previous <- .dm_read_previous(file.path(data_dir, DM_MANIFEST_FILE))
  if (is.null(schedule_through_date)) schedule_through_date <- dm_latest_completed_schedule_date()
  prev_by_file <- list()
  for (e in .dm_or(previous$datasets, list())) if (is.character(e$file)) prev_by_file[[e$file]] <- e

  files <- sort(setdiff(list.files(data_dir, pattern = "[.]json$"), DM_MANIFEST_FILE))
  datasets <- lapply(files, function(f) {
    path <- file.path(data_dir, f)
    obj <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    sha <- .dm_sha256(path)

    st <- .dm_embedded_stamp(obj)
    if (is.null(st)) {
      prev <- prev_by_file[[f]]
      carried <- if (!is.null(prev) && identical(prev$content_sha256, sha)) .dm_parse_utc(prev$generated_at) else NA
      st <- list(time = if (!is.na(carried)) carried else now, source = "manifest:content_hash")
    }

    ex <- extractors[[f]]
    through <- NA_character_
    if (!is.null(ex)) through <- tryCatch(ex$fn(obj), error = function(e) NA_character_)
    if (!is.null(ex) && !is.na(through)) {
      through_src <- paste0("payload:", ex$field)
      note <- NULL
    } else {
      through_src <- "not_game_dated"
      note <- if (!is.null(ex)) sprintf("no %s present in content", ex$field)
              else if (f %in% names(DM_NOT_GAME_DATED)) unname(DM_NOT_GAME_DATED[[f]])
              else "no coverage extractor registered; content not game-dated"
    }
    si <- .dm_static_info(f, obj)
    list(
      file = f,
      generated_at = .dm_fmt_utc(st$time),
      stamp_source = st$source,
      content_sha256 = sha,
      through_date = if (is.na(through)) NULL else through,
      through_date_source = through_src,
      coverage_note = note,
      static = si$static,
      static_reason = si$reason,
      builder = DM_BUILDER
    )
  })

  sched_out <- if (is.na(schedule_through_date)) NULL else schedule_through_date
  # Top-level generated_at only moves when some entry (or the schedule) moved.
  same <- !is.null(previous) &&
    identical(jsonlite::toJSON(previous$datasets, auto_unbox = TRUE, null = "null"),
              jsonlite::toJSON(datasets, auto_unbox = TRUE, null = "null")) &&
    identical(previous$schedule_through_date, sched_out)
  top_stamp <- if (same && !is.na(.dm_parse_utc(previous$generated_at))) previous$generated_at else .dm_fmt_utc(now)

  list(
    schema_version = DM_SCHEMA_VERSION,
    sport = DM_SPORT,
    generated_at = top_stamp,
    schedule_through_date = sched_out,
    datasets = datasets
  )
}

write_data_manifest <- function(data_dir = NULL, path = NULL, ...) {
  if (is.null(data_dir)) {
    data_dir <- if (exists("WEB_DATA_DIR")) get("WEB_DATA_DIR") else file.path("web", "public", "data")
  }
  if (is.null(path)) path <- file.path(data_dir, DM_MANIFEST_FILE)
  m <- build_data_manifest(data_dir = data_dir, previous = .dm_read_previous(path), ...)
  txt <- jsonlite::toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(txt, path, useBytes = TRUE)
  invisible(path)
}

# Non-interactive entry point (Rscript tools/write_data_manifest.R).
if (!interactive() && sys.nframe() == 0L) {
  root <- .dm_project_root()
  if (is.na(root)) stop("write_data_manifest.R: cannot locate the project root (no config.R).")
  setwd(root)
  suppressPackageStartupMessages(library(jsonlite))
  source("config.R")
  out <- write_data_manifest()
  m <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  cat(sprintf("[INFO] wrote %s (%d datasets, schedule_through_date=%s)\n",
              out, length(m$datasets), .dm_or(m$schedule_through_date, "null")))
}
