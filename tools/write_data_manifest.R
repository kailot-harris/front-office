# ==============================================================================
# NBA Analytics - web data manifest writer (front-office#102 / front-office#191)
# Path: <repo root>/tools/write_data_manifest.R
#
# Writes web/public/data/data_manifest.json: one sidecar entry per top-level
# web/public/data/*.json payload saying WHEN it was generated, WHICH game date
# its content actually runs through, which builder writes it, how far it may
# trail the schedule before the publish gate (tools/publish_web.R assertion H)
# blocks, and its `lifecycle` (NBA_analytics#235: "live" for every file in
# season; verified by publish_web.R assertion L).
#
# Usage:
#   Rscript tools/write_data_manifest.R            # writes the manifest
#   source("tools/write_data_manifest.R")          # defines functions only
# NBA_SKIP_STAGE_AUTORUN=1 also suppresses the write when run as a script.
#
# DERIVATION RULES - read from the payload bytes only:
#   through_date  the latest game date the payload's CONTENT carries, via a
#                 per-dataset extractor (DM_COVERAGE) -> through_date_source
#                 "payload:<field path>". Payloads whose content carries no game
#                 date (profiles, indexes, catalogs, cap sheets) get NULL,
#                 through_date_source "not_game_dated" and a coverage_note; the
#                 gate checks those on generated_at only and labels them
#                 [UNDATED]. through_date is NEVER derived from generated_at, so
#                 a payload rebuilt today from a stale cache still reads stale.
#   generated_at  the payload's own embedded stamp when it has one
#                 (stamp_source "payload:<field>"). Otherwise content-hash
#                 carry-forward (stamp_source "manifest:content_hash"): if the
#                 previous manifest recorded the same content_sha256 for the
#                 file, its generated_at is carried forward unchanged; otherwise
#                 the file is stamped with this writer run's time. File-system
#                 times and VCS history are never consulted: a checkout rewrites
#                 the former and the latter only moves when bytes change.
#   top-level generated_at changes only when some dataset entry (or the
#   schedule date) changed, so an idle publish produces no manifest diff.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a)) b else a

# Per-dataset specification. Every top-level payload must be listed; a payload
# on disk that is missing here is written with builder "<unregistered>", which
# assertion H rejects - adding a dataset means adding a row.
#
# max_lag_days: allowance (days) between the schedule's latest completed game
# date and the dataset's through_date (or, for not_game_dated datasets, the UTC
# date of generated_at).
#   2  daily pipeline outputs, one missed run of slack (lag 0 when healthy).
#      shots_*: NBA#205's PBP refresh is live and shots_metadata.json's content
#      runs through the schedule date, so no PBP-specific slack is needed.
#   10 projections_season_teams/players: bare arrays with no stamp, so their
#      generated_at is content-hash carry-forward, which only advances when the
#      bytes change - and these change only when inputs move (the committed
#      history shows gaps of up to ~7 days between real changes).
DM_SPEC <- list(
  "cba_cap_sheet.json"               = list(builder = "build_cba_cap_dataset.R",    max_lag_days = 2L,
    coverage_note = "Cap/payroll snapshot; content carries no game date."),
  "clutch_leverage_metrics.json"     = list(builder = "build_clutch_dataset.R",     max_lag_days = 2L),
  "coaching_metrics.json"            = list(builder = "build_coaching_dataset.R",   max_lag_days = 2L,
    coverage_note = "Per-staff ratings; content carries no game date."),
  "defensive_metrics.json"           = list(builder = "build_defense_dataset.R",    max_lag_days = 2L),
  "landing_digest.json"              = list(builder = "build_landing_digest.R", max_lag_days = 2L,
    coverage_note = "No final game in the digest's yesterday list (off day or off-season)."),
  "matchups_slates.json"             = list(builder = "build_matchups_dataset.R",   max_lag_days = 2L),
  "momentum_board.json"              = list(builder = "build_momentum_dataset.R",   max_lag_days = 2L),
  "momentum_methodology.json"        = list(builder = "publish_momentum_methodology.R", max_lag_days = 0L,
    static_reason = "Frozen momentum measures study results (study run date and source commit inside the file); copied by tools/publish_momentum_methodology.R only when the study is re-run, never by the daily pipeline."),
  "leader_methodology.json"          = list(builder = "build_leader_methodology.R", max_lag_days = 0L,
    static_reason = "Frozen leader reliability study results plus config.R owner minimums (study run date and source commit inside the file); built by tools/build_leader_methodology.R when the study or minimums change, never by the daily pipeline."),
  "player_leaders.json"              = list(builder = "build_player_leaders.R",     max_lag_days = 2L),
  "visual_media_index.json"          = list(builder = "export_visual_media_index.R", max_lag_days = 2L,
    coverage_note = "Media inventory (per-item build stamps); content carries no game date."),
  "player_dna_profiles.json"         = list(builder = "build_player_dna_dataset.R", max_lag_days = 2L),
  "playoff_series_matchups.json"     = list(builder = "playoff_simulator.R",        max_lag_days = 2L,
    coverage_note = "Series simulation catalog; content carries no game date."),
  "projections_diagnostics.json"     = list(builder = "accuracy_governance.R",      max_lag_days = 2L,
    coverage_note = "Aggregate accuracy metrics (resolved-game counts, no per-game dates); exposing a coverage date needs a builder change."),
  "projections_models_metadata.json" = list(builder = "season_simulator.R",         max_lag_days = 2L,
    coverage_note = "Model metadata catalog; content carries no game date."),
  "projections_season_players.json"  = list(builder = "season_simulator.R",         max_lag_days = 10L,
    coverage_note = "Season-long player projections; content carries no game date or stamp."),
  "projections_season_teams.json"    = list(builder = "season_simulator.R",         max_lag_days = 10L,
    coverage_note = "Season-long team projections; content carries no game date or stamp."),
  "shots_index.json"                 = list(builder = "build_shot_chart_dataset.R", max_lag_days = 2L,
    coverage_note = "Player shot index (counts only); content carries no game date. Coverage lives in shots_metadata.json."),
  "shots_metadata.json"              = list(builder = "build_shot_chart_dataset.R", max_lag_days = 2L),
  "offseason_draft.json"             = list(builder = "build_offseason_dataset.R",  max_lag_days = 0L,
    static_reason = "Static 2026 off-season draft snapshot (labeled in the UI per NBA#193); not refreshed in-season."),
  "offseason_teams.json"             = list(builder = "build_offseason_dataset.R",  max_lag_days = 0L,
    static_reason = "2026 off-season team-moves snapshot (labeled in the UI per NBA#193): the move set is frozen; only its baseline wins are re-derived per run, so it carries no game-date coverage."),
  "offseason_transactions.json"      = list(builder = "build_offseason_dataset.R",  max_lag_days = 0L,
    static_reason = "Hand-curated 2026 off-season transaction catalog; an input to build_offseason_dataset.R, not a per-run output.")
)

# Coverage extractors: filename -> function(parsed payload) -> list(date, source).
# Each field was chosen by inspecting the committed payload.
.dm_date_field <- function(field) function(j) {
  v <- if (is.list(j) && !is.null(names(j))) j[[field]] else NULL
  list(date = if (is.null(v)) NA_character_ else as.character(v), source = paste0("payload:", field))
}
DM_COVERAGE <- list(
  "clutch_leverage_metrics.json" = .dm_date_field("throughDate"),
  "defensive_metrics.json"       = .dm_date_field("throughDate"),
  "player_dna_profiles.json"     = .dm_date_field("throughDate"),
  "shots_metadata.json"          = .dm_date_field("through_date"),
  "momentum_board.json"          = .dm_date_field("through_date"),
  "player_leaders.json"          = .dm_date_field("through_date"),
  "landing_digest.json" = function(j) {
    # Latest FINAL game in yesterday[]: never generated_at or slate_date.
    d <- vapply(j$yesterday %||% list(), function(g)
      if (isTRUE(g$final) && !is.null(g$game_date)) as.character(g$game_date) else NA_character_, character(1))
    d <- d[!is.na(d)]
    list(date = if (length(d)) as.character(max(as.Date(d))) else NA_character_,
         source = "payload:yesterday[final].game_date")
  },
  "matchups_slates.json" = function(j) {
    d <- vapply(j$matchups %||% list(), function(m)
      if (isTRUE(m$is_completed)) as.character(m$game_date) else NA_character_, character(1))
    d <- d[!is.na(d)]
    list(date = if (length(d)) as.character(max(as.Date(d))) else NA_character_,
         source = "payload:matchups[is_completed].game_date")
  }
)

DM_SOURCE_SEASON <- "2026-27"
DM_FILE_NAME <- "data_manifest.json"
DM_LIFECYCLE_FIELDS <- c("season", "final_through_date", "frozen_sha256", "frozen_at")

# Lifecycle helper (NBA_analytics#235). Uses config.R's nba_data_lifecycle()
# when loaded; otherwise assigns "live" to every top-level file in season.
.dm_default_lifecycle_fn <- function() {
  if (exists("nba_data_lifecycle", mode = "function")) {
    get("nba_data_lifecycle", mode = "function")
  } else {
    function(files) {
      files <- basename(files)
      out <- lapply(files, function(f) list(lifecycle = "live"))
      names(out) <- files
      out
    }
  }
}

.dm_utc <- function(x) format(as.POSIXct(x), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

.dm_parse_stamp <- function(val) {
  if (is.null(val) || !length(val) || is.na(val[1]) || !nzchar(val[1])) return(NA)
  v <- sub(" ", "T", as.character(val[1]), fixed = TRUE)
  if (grepl("Z$", v)) as.POSIXct(sub("Z$", "", v), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  else as.POSIXct(v, format = "%Y-%m-%dT%H:%M:%S", tz = "")   # no suffix = pipeline-local time
}

# Embedded stamp: top-level keys first, then metadata.generated_at, then a
# stamp carried by the elements of a top-level array (coaching_metrics.json:
# [].provenance.generatedAt, local time; the latest is used).
.dm_embedded_stamp <- function(j) {
  if (is.list(j) && !is.null(names(j))) {
    for (k in c("generated_at", "generatedAt", "updated_at", "lastPublished")) {
      t <- .dm_parse_stamp(j[[k]])
      if (!is.na(t)) return(list(time = t, source = paste0("payload:", k)))
    }
    t <- .dm_parse_stamp(j$metadata$generated_at)
    if (!is.na(t)) return(list(time = t, source = "payload:metadata.generated_at"))
  } else if (is.list(j) && length(j)) {
    paths <- list(c("generated_at"), c("generatedAt"), c("provenance", "generatedAt"))
    for (p in paths) {
      v <- unique(unlist(lapply(j, function(e) {
        for (k in p) { if (!is.list(e)) return(NULL); e <- e[[k]] }
        e
      })))
      if (length(v) >= 1L) {
        t <- .dm_parse_stamp(max(v))
        if (!is.na(t)) return(list(time = t, source = paste0("payload:[].", paste(p, collapse = "."))))
      }
    }
  }
  NULL
}

# Latest date on which a (non-TBD) game in the schedule cache is completed.
# NA when the cache is absent/unreadable or carries no completion column.
dm_latest_completed_schedule_date <- function(schedule_path) {
  if (is.null(schedule_path) || !length(schedule_path) || is.na(schedule_path) ||
      !file.exists(schedule_path)) return(as.Date(NA))
  s <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(s) || !nrow(s) || !"game_date" %in% names(s)) return(as.Date(NA))
  done <- if ("status_type_completed" %in% names(s)) as.logical(s$status_type_completed)
          else if ("status_type_state" %in% names(s)) s$status_type_state == "post"
          else return(as.Date(NA))
  if (all(c("home_short_display_name", "away_short_display_name") %in% names(s))) {
    tbd <- s$home_short_display_name == "TBD" | s$away_short_display_name == "TBD"
    done <- done & !(tbd %in% TRUE)
  }
  gd <- as.Date(as.character(s$game_date))[done %in% TRUE]
  gd <- gd[!is.na(gd)]
  if (!length(gd)) as.Date(NA) else max(gd)
}

.dm_entry <- function(path, spec, prev_entry, now, lc = NULL) {
  f <- basename(path)
  sha <- unname(as.character(tools::sha256sum(path)))
  j <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)

  st <- if (!is.null(j)) .dm_embedded_stamp(j) else NULL
  if (!is.null(st)) {
    gen <- .dm_utc(st$time); stamp_source <- st$source
  } else {
    stamp_source <- "manifest:content_hash"
    gen <- if (!is.null(prev_entry) && identical(prev_entry$content_sha256, sha) &&
               !is.null(prev_entry$generated_at)) prev_entry$generated_at else .dm_utc(now)
  }

  static <- !is.null(spec$static_reason)
  through <- NA_character_; through_source <- "not_game_dated"
  note <- spec$coverage_note %||% NULL
  ext <- DM_COVERAGE[[f]]
  if (static) {
    through_source <- "static"; note <- NULL
  } else if (!is.null(ext) && !is.null(j)) {
    r <- ext(j)
    if (!is.na(r$date) && !is.na(as.Date(r$date, optional = TRUE))) {
      through <- format(as.Date(r$date)); through_source <- r$source; note <- NULL
    } else {
      note <- sprintf("extractor %s found no game date in the payload", r$source)
    }
  } else if (is.null(note)) {
    note <- "no coverage extractor registered; content treated as not game-dated"
  }

  entry <- list(
    generated_at        = gen,
    through_date        = if (is.na(through)) NULL else through,
    through_date_source = through_source,
    stamp_source        = stamp_source,
    content_sha256      = sha,
    coverage_note       = note,
    source_season       = DM_SOURCE_SEASON,
    builder             = spec$builder %||% "<unregistered>",
    max_lag_days        = as.integer(spec$max_lag_days %||% 0L),
    static              = static,
    static_reason       = spec$static_reason %||% NULL
  )
  if (!is.null(lc) && !is.null(lc$lifecycle)) {
    entry$lifecycle <- lc$lifecycle
    if (identical(lc$lifecycle, "season_final")) {
      for (k in DM_LIFECYCLE_FIELDS) if (!is.null(lc[[k]])) entry[[k]] <- lc[[k]]
    }
  }
  entry
}

.dm_read_prev <- function(prev_path) {
  if (is.null(prev_path) || !file.exists(prev_path)) return(NULL)
  tryCatch(jsonlite::fromJSON(prev_path, simplifyVector = FALSE), error = function(e) NULL)
}

build_data_manifest <- function(data_dir = file.path("web", "public", "data"),
                                schedule_path = NULL,
                                now = Sys.time(),
                                prev_manifest = .dm_read_prev(file.path(data_dir, DM_FILE_NAME)),
                                lifecycle_fn = .dm_default_lifecycle_fn()) {
  files <- setdiff(sort(list.files(data_dir, pattern = "\\.json$")), DM_FILE_NAME)
  lifecycles <- if (is.function(lifecycle_fn)) lifecycle_fn(files) else list()
  datasets <- list()
  for (f in files) {
    datasets[[f]] <- .dm_entry(file.path(data_dir, f), DM_SPEC[[f]] %||% list(),
                               prev_manifest$datasets[[f]], now,
                               lc = lifecycles[[f]])
  }
  sched <- dm_latest_completed_schedule_date(schedule_path)
  if (is.na(sched) && !is.null(datasets[["matchups_slates.json"]]$through_date)) {
    # No schedule cache (offline checkout): the latest graded game in the
    # published slate's content is the best committed evidence of coverage.
    sched <- as.Date(datasets[["matchups_slates.json"]]$through_date)
  }
  sched_chr <- if (is.na(sched)) NULL else format(sched)

  # Round-trip through JSON so the comparison sees exactly what would be written.
  norm <- function(x) jsonlite::fromJSON(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"),
                                         simplifyVector = FALSE)
  unchanged <- !is.null(prev_manifest) && !is.null(prev_manifest$generated_at) &&
    identical(norm(datasets), norm(prev_manifest$datasets)) &&
    identical(sched_chr, prev_manifest$schedule_through_date)
  list(schema_version = 1L, sport = "nba",
       generated_at = if (unchanged) prev_manifest$generated_at else .dm_utc(now),
       schedule_through_date = sched_chr,
       datasets = datasets)
}

write_data_manifest <- function(data_dir = file.path("web", "public", "data"), ...) {
  m <- build_data_manifest(data_dir = data_dir, ...)
  out <- file.path(data_dir, DM_FILE_NAME)
  txt <- jsonlite::toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  writeLines(txt, out, useBytes = TRUE)
  invisible(out)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("write_data_manifest\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN", ""))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  setwd(root)
  sched <- NULL
  lc_fn <- NULL
  if (file.exists("config.R")) {
    env <- new.env()
    ok <- tryCatch({ sys.source("config.R", envir = env); TRUE }, error = function(e) FALSE)
    if (ok && exists("CACHE_MATCHUPS_SCHEDULE", envir = env))
      sched <- env$CACHE_MATCHUPS_SCHEDULE(env$MATCHUPS_HOOPR_SEASON)
    if (ok && exists("nba_data_lifecycle", envir = env))
      lc_fn <- env$nba_data_lifecycle
  }
  out <- if (is.function(lc_fn)) {
    write_data_manifest(schedule_path = sched, lifecycle_fn = lc_fn)
  } else {
    write_data_manifest(schedule_path = sched)
  }
  message(sprintf(">>> write_data_manifest: wrote %s", out))
})
