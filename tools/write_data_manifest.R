# ==============================================================================
# tools/write_data_manifest.R  (front-office#102, front-office#191)
#
# Writes the sidecar web/public/data/data_manifest.json: one entry per
# top-level web/public/data/*.json payload, saying WHEN it was generated, WHICH
# builder wrote it, and WHAT game date its CONTENT runs through - so the publish
# gate (tools/publish_web.R, assertion H) and the web contract suite can ask "is
# every shipped dataset accounted for, and is any of it lagging the schedule?"
#
# Usage:
#   Rscript tools/write_data_manifest.R        # regenerate the manifest
#   source("tools/write_data_manifest.R")      # define helpers only, no writes
#
# Sourcing has zero side effects. The autorun keys off commandArgs() (was I
# invoked as `Rscript tools/write_data_manifest.R`), and is additionally
# suppressed when NFL_SKIP_MANIFEST_AUTORUN is set to a non-empty value.
#
# generated_at (stamp_source):
#   * "payload:<field>"        - the payload's own embedded stamp (generated_at,
#                                updated_at, generatedAt; top level or first
#                                array element).
#   * "manifest:content_hash"  - no embedded stamp: the previous manifest's
#                                generated_at is carried forward while the file's
#                                sha256 is unchanged; otherwise this run's time.
#   File mtime and git history are NEVER consulted (they move on checkout).
#
# through_date (through_date_source):
#   * "payload:<path>"   - latest game date actually present in the payload.
#                          Week-numbered payloads are resolved to a date through
#                          the season schedule carried in matchups_current_week.json.
#   * "not_game_dated"   - content carries no game date (profiles, indexes,
#                          catalogs); through_date is null, coverage_note says
#                          why, and the gate checks generated_at freshness instead.
#   through_date is NEVER derived from generated_at.
# salary_cap_profiles.json is an annual CBA snapshot and is declared static.
#
# lifecycle (NFL_analytics#214):
#   Each entry also carries `lifecycle` ("live" | "season_final" | "archived"),
#   assigned via config.R's nfl_data_lifecycle() (all "live" in season). When
#   `season_final`, entries also carry season, final_through_date,
#   frozen_sha256, and frozen_at. publish_web.R Assertion L verifies these.
# ==============================================================================

DATA_MANIFEST_FILENAME       <- "data_manifest.json"
DATA_MANIFEST_SCHEMA_VERSION <- 1L
DATA_MANIFEST_DEFAULT_MAX_LAG_DAYS <- 8L   # weekly NFL cadence + one day of slack
DATA_MANIFEST_SCHEDULE_FILE  <- "matchups_current_week.json"

.dm_iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
.dm_date <- function(x) {
  d <- suppressWarnings(as.Date(substr(as.character(unlist(x)), 1, 10)))
  d <- d[!is.na(d)]
  if (!length(d)) NA_character_ else format(max(d), "%Y-%m-%d")
}

# Completed games of the published schedule (data frame: week, gameday).
.dm_completed_games <- function(data_dir) {
  p <- file.path(data_dir, DATA_MANIFEST_SCHEDULE_FILE)
  if (!file.exists(p)) return(NULL)
  m <- tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  g <- m$matchups
  if (is.null(g) || !is.data.frame(g) || !all(c("week", "gameday", "is_completed") %in% names(g))) return(NULL)
  g[g$is_completed %in% TRUE, c("week", "gameday"), drop = FALSE]
}

# Latest completed gameday of a given week (or of any week <= it).
.dm_week_to_date <- function(week, data_dir) {
  g <- .dm_completed_games(data_dir)
  if (is.null(g) || is.null(week) || is.na(suppressWarnings(as.integer(week)))) return(NA_character_)
  .dm_date(g$gameday[g$week <= as.integer(week)])
}

# filename -> list(extract = function(parsed, data_dir) -> "YYYY-MM-DD"|NA, path = label)
# or list(note = "...") for not-game-dated content.
DATA_MANIFEST_SPECS <- list(
  "clutch_leverage_metrics.json" = list(builder = "build_clutch_dataset.R",
    path = "[].throughWeek (week -> latest completed gameday via matchups_current_week.json)",
    extract = function(x, dd) .dm_week_to_date(suppressWarnings(max(vapply(x, function(r) as.numeric(r$throughWeek %||% NA), 0), na.rm = TRUE)), dd)),
  "coaching_profiles.json" = list(builder = "build_coaching_dataset.R",
    path = "through_week (week -> latest completed gameday via matchups_current_week.json)",
    extract = function(x, dd) .dm_week_to_date(x$through_week, dd)),
  "landing_digest.json" = list(builder = "tools/build_landing_digest.R",
    path = "yesterday[final].start_time_utc (US Eastern date of the latest final)",
    note = "No final in the digest's yesterday list (no NFL game was played that day)",
    extract = function(x, dd) {
      t <- vapply(Filter(function(g) isTRUE(g$final), x$yesterday),
                  function(g) as.character(g$start_time_utc %||% NA), "")
      t <- as.POSIXct(t, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      t <- t[!is.na(t)]
      if (!length(t)) NA_character_ else format(max(t), "%Y-%m-%d", tz = "America/New_York")
    }),
  "matchups_current_week.json" = list(builder = "export_web_datasets.R",
    path = "matchups[is_completed].gameday",
    extract = function(x, dd) .dm_date(lapply(Filter(function(g) isTRUE(g$is_completed), x$matchups), `[[`, "gameday"))),
  "model_diagnostics.json" = list(builder = "export_web_datasets.R",
    note = "Accuracy history keyed by evaluation run time (last_evaluated), not by game date"),
  "passing_index.json" = list(builder = "build_passing_dataset.R",
    note = "QB catalog for the passing charts; carries no game date"),
  "passing_metadata.json" = list(builder = "build_passing_dataset.R",
    note = "League zone averages for the season; carries no game date"),
  "momentum_board.json" = list(builder = "build_momentum_board.R",
    path = "through_date (latest completed regular-season game on the board)",
    note = "No completed regular-season game this season yet",
    extract = function(x, dd) .dm_date(x$through_date)),
  "player_dna_profiles.json" = list(builder = "build_player_dna_dataset.R",
    path = "throughWeek (week -> latest completed gameday via matchups_current_week.json)",
    extract = function(x, dd) .dm_week_to_date(x$throughWeek, dd)),
  "player_leaders.json" = list(builder = "build_player_leaders.R",
    path = "through_date (latest game date across the leader cards)",
    note = "No current-season game in any leader card's source yet",
    extract = function(x, dd) .dm_date(x$through_date)),
  "player_qb_profiles.json" = list(builder = "export_web_datasets.R",
    note = "Rolling QB profiles; carries no game date"),
  "playoff_picture.json" = list(builder = "export_web_datasets.R",
    note = "Simulated seeding probabilities; carries no game date"),
  "salary_cap_profiles.json" = list(builder = "export_web_datasets.R", static = TRUE,
    static_reason = "Annual NFL salary cap snapshot",
    note = "Annual cap snapshot; carries no game date"),
  "standings_projections.json" = list(builder = "export_web_datasets.R",
    note = "Team ratings and projections carry games_played counts, not game dates"),
  "team_epa_profiles.json" = list(builder = "export_web_datasets.R",
    note = "Rolling team EPA profiles; carries no game date"),
  "visual_media_index.json" = list(builder = "export_web_datasets.R",
    note = "Media catalog; carries no game date")
)

`%||%` <- function(a, b) if (is.null(a)) b else a

# Top-level *.json payloads in data_dir, excluding the manifest itself.
dm_list_payloads <- function(data_dir) {
  f <- list.files(data_dir, pattern = "[.]json$", full.names = FALSE)
  sort(setdiff(f, DATA_MANIFEST_FILENAME))
}

dm_sha256 <- function(path) {
  # Base R (>= 4.5) so CI needs no extra package.
  unname(tools::sha256sum(path))
}

# Embedded stamp: list(value = ISO string, field = name) or NULL.
dm_embedded_stamp <- function(parsed) {
  # A top-level array of items (visual_media_index.json) has no stamp of its
  # own; each item carries the time it was made. Use the NEWEST item's stamp.
  # Taking item [0] made the catalog as old as whichever still image happened
  # to sort first, which never re-renders, so assertion H blocked every
  # publish once #192 made the per-item stamps honest (2026-11-21).
  if (is.null(names(parsed)) && length(parsed) &&
      all(vapply(parsed, function(o) is.list(o) && !is.null(names(o)), logical(1)))) {
    for (k in c("generated_at", "updated_at", "generatedAt")) {
      v <- unlist(lapply(parsed, function(o) if (is.character(o[[k]]) && length(o[[k]]) == 1) o[[k]] else NA_character_))
      t <- as.POSIXct(v, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
      if (any(!is.na(t))) return(list(value = .dm_iso(max(t, na.rm = TRUE)), field = paste0("[max].", k)))
    }
  }
  cands <- list(parsed)
  if (is.null(names(parsed)) && length(parsed)) cands <- c(cands, list(parsed[[1]]))
  for (o in cands) {
    if (!is.list(o) || is.null(names(o))) next
    for (k in c("generated_at", "updated_at", "generatedAt")) {
      v <- o[[k]]
      if (is.character(v) && length(v) == 1) {
        t <- as.POSIXct(v, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
        if (!is.na(t)) return(list(value = .dm_iso(t),
                                   field = if (identical(o, parsed)) k else paste0("[0].", k)))
      }
    }
  }
  NULL
}

# Latest completed-game date for the current season, or NA_character_ when the
# schedules cache is absent (CI / test sandboxes) or unreadable.
dm_schedule_through_date <- function(schedules_path = if (exists("CACHE_SCHEDULES")) CACHE_SCHEDULES else NA_character_,
                                     season = if (exists("CURRENT_SEASON")) CURRENT_SEASON else NA) {
  if (is.na(schedules_path) || !file.exists(schedules_path)) return(NA_character_)
  s <- tryCatch(readRDS(schedules_path), error = function(e) NULL)
  if (is.null(s) || !all(c("season", "gameday") %in% names(s))) return(NA_character_)
  if (!is.na(season)) s <- s[s$season == season, , drop = FALSE]
  done <- rep(FALSE, nrow(s))
  if ("result" %in% names(s)) done <- done | !is.na(s$result)
  if (all(c("home_score", "away_score") %in% names(s))) done <- done | (!is.na(s$home_score) & !is.na(s$away_score))
  .dm_date(as.character(s$gameday[done]))
}

DM_LIFECYCLE_FIELDS <- c("season", "final_through_date", "frozen_sha256", "frozen_at")

.dm_default_lifecycle_fn <- function() {
  if (exists("nfl_data_lifecycle", mode = "function")) {
    get("nfl_data_lifecycle", mode = "function")
  } else {
    function(files) {
      files <- basename(files)
      out <- lapply(files, function(f) list(lifecycle = "live"))
      names(out) <- files
      out
    }
  }
}

# Build (but do not write) the manifest list. `previous` is the prior manifest
# (parsed list) used for content-hash carry-forward; defaults to the one on disk.
build_data_manifest <- function(data_dir = if (exists("WEB_DATA_DIR")) WEB_DATA_DIR else file.path("web", "public", "data"),
                                schedule_through_date = dm_schedule_through_date(),
                                now = Sys.time(),
                                previous = dm_read_previous(data_dir),
                                lifecycle_fn = .dm_default_lifecycle_fn()) {
  files <- dm_list_payloads(data_dir)
  lifecycles <- if (is.function(lifecycle_fn)) lifecycle_fn(files) else list()
  datasets <- list()
  for (f in files) {
    p <- file.path(data_dir, f)
    spec <- DATA_MANIFEST_SPECS[[f]]
    if (is.null(spec)) spec <- list(builder = "unknown", note = "No coverage extractor registered for this file")
    parsed <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    sha <- dm_sha256(p)
    stamp <- if (is.null(parsed)) NULL else dm_embedded_stamp(parsed)
    if (!is.null(stamp)) {
      gen <- stamp$value; src <- paste0("payload:", stamp$field)
    } else {
      prev <- previous$datasets[[f]]
      gen <- if (!is.null(prev) && identical(prev$content_sha256, sha) && is.character(prev$generated_at))
        prev$generated_at else .dm_iso(now)
      src <- "manifest:content_hash"
    }
    td <- NA_character_
    if (!is.null(spec$extract) && !is.null(parsed)) td <- tryCatch(spec$extract(parsed, data_dir), error = function(e) NA_character_)
    entry <- list(builder = spec$builder, generated_at = gen, stamp_source = src, content_sha256 = sha)
    if (!is.na(td)) {
      entry$through_date <- td
      entry$through_date_source <- paste0("payload:", spec$path)
      entry$coverage_note <- NULL
    } else {
      entry["through_date"] <- list(NULL)
      entry$through_date_source <- "not_game_dated"
      entry$coverage_note <- spec$note %||% "Coverage extractor found no game date in the payload"
    }
    if (isTRUE(spec$static)) {
      entry$static <- TRUE
      entry$static_reason <- spec$static_reason
    } else {
      entry$static <- FALSE
      entry$max_lag_days <- DATA_MANIFEST_DEFAULT_MAX_LAG_DAYS
    }
    lc <- lifecycles[[f]]
    if (!is.null(lc) && !is.null(lc$lifecycle)) {
      entry$lifecycle <- lc$lifecycle
      if (identical(lc$lifecycle, "season_final")) {
        for (k in DM_LIFECYCLE_FIELDS) if (!is.null(lc[[k]])) entry[[k]] <- lc[[k]]
      }
    }
    if (is.null(entry$coverage_note)) entry["coverage_note"] <- list(NULL)
    datasets[[f]] <- entry
  }
  top_gen <- .dm_iso(now)
  if (!is.null(previous) && is.character(previous$generated_at) &&
      identical(jsonlite::toJSON(previous$datasets, auto_unbox = TRUE, null = "null"),
                jsonlite::toJSON(datasets, auto_unbox = TRUE, null = "null")))
    top_gen <- previous$generated_at
  list(schema_version = DATA_MANIFEST_SCHEMA_VERSION,
       sport = "nfl",
       generated_at = top_gen,
       schedule_through_date = if (is.na(schedule_through_date)) NULL else schedule_through_date,
       datasets = datasets)
}

dm_read_previous <- function(data_dir) {
  p <- file.path(data_dir, DATA_MANIFEST_FILENAME)
  if (!file.exists(p)) return(NULL)
  tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
}

write_data_manifest <- function(data_dir = if (exists("WEB_DATA_DIR")) WEB_DATA_DIR else file.path("web", "public", "data"),
                                schedule_through_date = dm_schedule_through_date(),
                                now = Sys.time(),
                                lifecycle_fn = .dm_default_lifecycle_fn()) {
  m <- build_data_manifest(data_dir, schedule_through_date, now, lifecycle_fn = lifecycle_fn)
  if (is.null(m$schedule_through_date)) m["schedule_through_date"] <- list(NULL)
  out <- file.path(data_dir, DATA_MANIFEST_FILENAME)
  txt <- jsonlite::toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(txt, out, useBytes = TRUE)
  invisible(out)
}

local({
  if (nzchar(Sys.getenv("NFL_SKIP_MANIFEST_AUTORUN", ""))) return(invisible(NULL))
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("write_data_manifest[.]R$", files))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(files[grepl("write_data_manifest[.]R$", files)][1])),
                        winslash = "/", mustWork = FALSE)
  setwd(root)
  suppressPackageStartupMessages(library(jsonlite))
  if (file.exists("config.R")) source("config.R")
  out <- write_data_manifest()
  m <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  cat(sprintf("wrote %s: %d dataset(s), schedule_through_date=%s\n", out, length(m$datasets),
              if (is.null(m$schedule_through_date)) "null" else m$schedule_through_date))
  for (f in names(m$datasets)) cat(sprintf("  %-30s %-22s %s\n", f, m$datasets[[f]]$stamp_source,
                                           m$datasets[[f]]$through_date_source))
})
