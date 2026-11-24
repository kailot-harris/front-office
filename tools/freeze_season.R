# ==============================================================================
# MLB Analytics - Season freeze / thaw for published data files (MLB-Analytics#147)
# Path: <repo root>/tools/freeze_season.R
#
# Off-season, tools/publish_web.R checks a finished season's files by content
# hash instead of by freshness (see config.R, "Data-file lifecycle"). This tool
# is the only writer of that state, config.R's WEB_DATA_LIFECYCLE_REGISTRY.
#
#   freeze (--season <yyyy>)
#     1. The season's last game is the latest COMPLETED slate game of that season
#        in the schedule cache, playoffs included (MATCHUP_GAME_TYPES: R, F, D,
#        L, W). An if-necessary or unplayed game dated in the past does not
#        count. If a game of the season is still uncompleted on or after today,
#        the season is not over and nothing is frozen.
#     2. Every season file (config.R's WEB_DATA_SEASON_FILES) present must reach
#        that game: a game-dated file's through_date (tools/write_data_manifest.R's
#        payload extractors, never the stamp) must be on or after it; an undated
#        file's generated_at must be on or after it, i.e. it was built after the
#        season's last game. Absent files are refused too.
#     3. All or nothing. If ANY file is refused, nothing is written and the exit
#        status is 1. Otherwise each file is recorded as season_final with
#        season, final_through_date (the season's last game), frozen_sha256
#        (config.R's mlb_lifecycle_sha256) and frozen_at.
#
#   thaw (--thaw --season <new yyyy>)
#     Run when the NEW season starts. Every season_final entry of an earlier
#     season whose file name the new season reuses (it is in the new
#     WEB_DATA_SEASON_FILES, e.g. projections_season_teams.json) goes back to
#     live; every other one (e.g. a season-suffixed archive) becomes archived,
#     keeping its season and hash for the record.
#
# Usage:
#   Rscript tools/freeze_season.R --season 2026 --dry-run   # report, write nothing
#   Rscript tools/freeze_season.R --season 2026             # freeze
#   Rscript tools/freeze_season.R --thaw --season 2027      # new season starts
# After a freeze or thaw, the next live publish rewrites data_manifest.json from
# the registry. source()ing this file defines the functions and runs nothing.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

.fs_or <- function(a, b) if (is.null(a)) b else a
.fs_utc <- function(t) format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' The season's last completed game date (Date). Errors when the season has no
#' completed game, or when it still has an uncompleted game on/after `today`.
fs_season_last_game <- function(schedule, season, today = Sys.Date()) {
  s <- if (is.data.frame(schedule)) schedule else as.data.frame(schedule)
  # Drop list columns (such as MLB Stats API `events`) so base operations stay clean.
  list_cols <- vapply(s, is.list, logical(1))
  if (any(list_cols)) s <- s[, !list_cols, drop = FALSE]
  s <- as.data.frame(s, stringsAsFactors = FALSE)

  if (!("season" %in% names(s))) stop("schedule lacks column(s): season")
  date_col <- intersect(c("official_date", "game_date", "date"), names(s))[1]
  if (is.na(date_col)) stop("schedule lacks column(s): official_date/game_date/date")

  has_done_flag <- "is_completed" %in% names(s)
  status_col <- intersect(c("status_detailed_state", "status", "status_abstract_game_state"), names(s))[1]
  if (!has_done_flag && is.na(status_col)) {
    stop("schedule lacks column(s): is_completed/status_detailed_state/status")
  }

  s <- s[!is.na(s$season) & as.integer(s$season) == as.integer(season), , drop = FALSE]
  if ("game_type" %in% names(s)) {
    types <- if (exists("MATCHUP_GAME_TYPES")) get("MATCHUP_GAME_TYPES") else c("R", "F", "D", "L", "W")
    s <- s[as.character(s$game_type) %in% types, , drop = FALSE]
  }
  if (!nrow(s)) stop(sprintf("schedule has no games for season %s", season))

  d <- suppressWarnings(as.Date(substr(as.character(s[[date_col]]), 1L, 10L)))
  done <- if (has_done_flag) {
    !is.na(s$is_completed) & as.logical(s$is_completed)
  } else {
    grepl("^(Final|Completed Early|Game Over)", as.character(s[[status_col]]), ignore.case = TRUE)
  }
  pending <- !done & !is.na(d) & d >= as.Date(today)
  if (any(pending)) {
    stop(sprintf("season %s is not over: %d scheduled game(s) on or after %s are not completed (first %s)",
                 season, sum(pending), format(as.Date(today)), format(min(d[pending]))))
  }
  if (!any(done & !is.na(d))) stop(sprintf("season %s has no completed game", season))
  max(d[done], na.rm = TRUE)
}

.fs_read_registry <- function(path) {
  if (exists("mlb_read_lifecycle_registry", mode = "function")) return(mlb_read_lifecycle_registry(path))
  if (!file.exists(path)) return(list(schema_version = 1L, sport = "mlb", files = list()))
  r <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (is.null(r$files)) r$files <- list()
  r
}

.fs_write_registry <- function(reg, path) {
  if (length(reg$files)) reg$files <- reg$files[order(names(reg$files))]
  else reg$files <- structure(list(), names = character(0))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- jsonlite::toJSON(reg, auto_unbox = TRUE, pretty = TRUE, null = "null")
  writeLines(txt, path, useBytes = TRUE)
  invisible(path)
}

#' Verify and (unless write = FALSE) freeze a season's files.
#' Returns list(ok, last_game, refused = data.frame(file, reason), frozen = named list).
freeze_season <- function(season,
                          data_dir = WEB_DATA_DIR,
                          registry_path = WEB_DATA_LIFECYCLE_REGISTRY,
                          schedule = readRDS(CACHE_MLB_SCHEDULE(season)),
                          season_files = WEB_DATA_SEASON_FILES,
                          today = Sys.Date(),
                          now = Sys.time(),
                          manifest = NULL,
                          write = TRUE) {
  season <- as.integer(season)
  last_game <- fs_season_last_game(schedule, season, today)
  if (is.null(manifest)) {
    # Coverage exactly as the manifest writer derives it (payload game dates for
    # through_date; payload stamp or content-hash carry-forward for generated_at).
    env <- new.env()
    old <- Sys.getenv("MLB_SKIP_MANIFEST_AUTORUN")
    Sys.setenv(MLB_SKIP_MANIFEST_AUTORUN = "1")
    on.exit(if (!nzchar(old)) Sys.unsetenv("MLB_SKIP_MANIFEST_AUTORUN") else Sys.setenv(MLB_SKIP_MANIFEST_AUTORUN = old), add = TRUE)
    writer <- if (exists("MLB_ROOT_DIR")) file.path(MLB_ROOT_DIR, "tools", "write_data_manifest.R") else file.path("tools", "write_data_manifest.R")
    sys.source(writer, envir = env)
    manifest <- env$build_data_manifest(data_dir = data_dir, schedule_through_date = NA_character_,
                                        now = now, lifecycle_fn = NULL)
  }
  entries <- manifest$datasets
  names(entries) <- vapply(entries, function(e) as.character(e$file), character(1))

  refused <- data.frame(file = character(0), reason = character(0), stringsAsFactors = FALSE)
  refuse <- function(f, why) refused[nrow(refused) + 1L, ] <<- list(f, why)
  frozen <- list()
  for (f in season_files) {
    p <- file.path(data_dir, f)
    e <- entries[[f]]
    if (!file.exists(p) || is.null(e)) { refuse(f, "file absent"); next }
    thr <- if (is.null(e$through_date)) as.Date(NA) else as.Date(as.character(e$through_date))
    if (!identical(e$through_date_source, "not_game_dated")) {
      if (is.na(thr)) { refuse(f, "game-dated file has no through_date"); next }
      if (thr < last_game) {
        refuse(f, sprintf("through_date %s is before the season's last game %s", thr, last_game)); next
      }
    } else {
      gen <- suppressWarnings(as.Date(substr(as.character(.fs_or(e$generated_at, "")), 1L, 10L)))
      if (is.na(gen)) { refuse(f, "undated file has no generated_at"); next }
      if (gen < last_game) {
        refuse(f, sprintf("undated file generated %s, before the season's last game %s", gen, last_game)); next
      }
    }
    frozen[[f]] <- list(
      lifecycle = "season_final",
      season = season,
      final_through_date = format(last_game),
      frozen_sha256 = mlb_lifecycle_sha256(p),
      frozen_at = .fs_utc(now)
    )
  }
  ok <- nrow(refused) == 0
  if (ok && isTRUE(write)) {
    reg <- .fs_read_registry(registry_path)
    for (f in names(frozen)) reg$files[[f]] <- frozen[[f]]
    .fs_write_registry(reg, registry_path)
  }
  list(ok = ok, last_game = last_game, refused = refused, frozen = if (ok) frozen else list())
}

#' New season starts: earlier seasons' season_final files move to live (name
#' reused by the new season) or archived (everything else).
#' Returns list(to_live = character, to_archived = character).
thaw_season <- function(new_season,
                        registry_path = WEB_DATA_LIFECYCLE_REGISTRY,
                        season_files = WEB_DATA_SEASON_FILES,
                        write = TRUE) {
  new_season <- as.integer(new_season)
  reg <- .fs_read_registry(registry_path)
  to_live <- character(0); to_archived <- character(0)
  for (f in names(reg$files)) {
    e <- reg$files[[f]]
    if (!identical(e$lifecycle, "season_final")) next
    if (is.null(e$season) || as.integer(e$season) >= new_season) next
    if (f %in% season_files) {
      reg$files[[f]] <- NULL          # back to config.R's default for a season file: live
      to_live <- c(to_live, f)
    } else {
      e$lifecycle <- "archived"
      reg$files[[f]] <- e
      to_archived <- c(to_archived, f)
    }
  }
  if (isTRUE(write)) .fs_write_registry(reg, registry_path)
  list(to_live = to_live, to_archived = to_archived)
}

# ------------------------------------------------------------------------------
# CLI guard: only runs under `Rscript tools/freeze_season.R`.
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (interactive() || !any(grepl("(^|[/\\\\])freeze_season\\.R$", f))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(root, "config.R"))) setwd(root)
  source("logging_utils.R")
  source("config.R")
  opts <- commandArgs(trailingOnly = TRUE)
  si <- match("--season", opts)
  season <- if (!is.na(si) && si < length(opts)) suppressWarnings(as.integer(opts[si + 1L])) else NA_integer_
  if (is.na(season)) stop("usage: Rscript tools/freeze_season.R --season <yyyy> [--dry-run] | --thaw --season <new yyyy>")
  write <- !("--dry-run" %in% opts)
  if ("--thaw" %in% opts) {
    r <- thaw_season(season, write = write)
    cat(sprintf("Thaw for season %d%s: %d file(s) -> live, %d -> archived\n", season,
                if (write) "" else " (dry run, nothing written)", length(r$to_live), length(r$to_archived)))
    for (x in r$to_live) cat("  live      ", x, "\n")
    for (x in r$to_archived) cat("  archived  ", x, "\n")
    quit(status = 0L)
  }
  r <- tryCatch(freeze_season(season, write = write), error = function(e) {
    cat("REFUSED: ", conditionMessage(e), "\n", sep = ""); quit(status = 1L)
  })
  cat(sprintf("Season %d last completed game: %s\n", season, format(r$last_game)))
  if (!r$ok) {
    cat(sprintf("REFUSED - %d file(s) do not reach the season's last game; nothing written:\n", nrow(r$refused)))
    for (i in seq_len(nrow(r$refused))) cat(sprintf("  %-40s %s\n", r$refused$file[i], r$refused$reason[i]))
    quit(status = 1L)
  }
  cat(sprintf("%s %d file(s) as season_final%s\n", if (write) "Froze" else "Would freeze", length(r$frozen),
              if (write) paste0(" in ", WEB_DATA_LIFECYCLE_REGISTRY) else " (dry run, nothing written)"))
  for (x in names(r$frozen)) cat(sprintf("  %-40s %s\n", x, substr(r$frozen[[x]]$frozen_sha256, 1, 16)))
  quit(status = 0L)
})
