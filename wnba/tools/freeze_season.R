# ==============================================================================
# WNBA Analytics - Season freeze / thaw for published data files (WNBA#250)
# Path: <repo root>/tools/freeze_season.R
#
# Off-season, tools/publish_web.R checks a finished season's files by content
# hash instead of by freshness (see config.R, "Data-file lifecycle"). This tool
# is the only writer of that state, config.R's WEB_DATA_LIFECYCLE_REGISTRY.
#
#   freeze (--season <yyyy>)
#     1. The season's last game is the latest COMPLETED game of that season in
#        the schedule cache, playoffs included. An if-necessary game that was
#        never played (is_completed FALSE, dated in the past) does not count.
#        If a game of the season is still uncompleted on or after today, the
#        season is not over and nothing is frozen.
#     2. Every season file (config.R's WEB_DATA_SEASON_FILES) present must reach
#        its target game: a game-dated file's through_date (tools/write_data_manifest.R's
#        payload extractors, never the stamp) must be on or after it; an undated
#        file's generated_at must be on or after it, i.e. it was built after that
#        game. Absent files are refused too. The target game is:
#          - the season's last game (step 1), for every season file, except
#          - the season's last completed REGULAR-season game, for a file in
#            config.R's WEB_DATA_REGULAR_SEASON_FILES (content that covers the
#            regular season only, e.g. player_leaders.json). Regular-season games
#            are the schedule cache's season_type 2 rows (3 = playoffs), the same
#            filter build_player_leaders.R applies; the completion and not-over
#            rules of step 1 apply to those rows.
#     3. A file already recorded as season_final for the same season is checked by
#        content: if its frozen_sha256 equals the file's current hash, its entry is
#        kept exactly as it is (same frozen_at), so freezing a newly added file
#        does not rewrite the existing entries. If the hash differs, the file is
#        refused: changed frozen content is never silently re-frozen.
#     4. All or nothing. If ANY file is refused, nothing is written and the exit
#        status is 1. Otherwise each newly frozen file is recorded as season_final
#        with season, final_through_date (its target game from step 2),
#        frozen_sha256 (config.R's wnba_lifecycle_sha256) and frozen_at.
#
#   thaw (--thaw --season <new yyyy>)
#     Run when the NEW season starts. Every season_final entry of an earlier
#     season whose file name the new season reuses (it is in the new
#     WEB_DATA_SEASON_FILES, e.g. projections_season_teams.json) goes back to
#     live; every other one (e.g. playoff_bracket_2026.json) becomes archived,
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

.fs_utc <- function(t) format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' The season's last completed game date (Date). Errors when the season has no
#' completed game, or when it still has an uncompleted game on/after `today`.
#' regular_season_only = TRUE restricts both rules to the regular season
#' (season_type 2 in the schedule cache; 3 is playoffs).
fs_season_last_game <- function(schedule, season, today = Sys.Date(), regular_season_only = FALSE) {
  s <- as.data.frame(schedule)
  need <- c("game_date", "season", "is_completed", if (isTRUE(regular_season_only)) "season_type")
  if (!all(need %in% names(s))) stop("schedule lacks column(s): ", paste(setdiff(need, names(s)), collapse = ", "))
  s <- s[!is.na(s$season) & as.integer(s$season) == as.integer(season), , drop = FALSE]
  if (isTRUE(regular_season_only)) {
    s <- s[!is.na(s$season_type) & as.integer(s$season_type) == 2L, , drop = FALSE]
    if (!nrow(s)) stop(sprintf("schedule has no regular-season games for season %s", season))
  }
  if (!nrow(s)) stop(sprintf("schedule has no games for season %s", season))
  d <- as.Date(substr(as.character(s$game_date), 1, 10))
  done <- !is.na(s$is_completed) & as.logical(s$is_completed)
  lbl <- if (isTRUE(regular_season_only)) "regular season" else "season"
  pending <- !done & !is.na(d) & d >= as.Date(today)
  if (any(pending)) {
    stop(sprintf("%s %s is not over: %d scheduled game(s) on or after %s are not completed (first %s)",
                 lbl, season, sum(pending), format(as.Date(today)), format(min(d[pending]))))
  }
  if (!any(done & !is.na(d))) stop(sprintf("%s %s has no completed game", lbl, season))
  max(d[done], na.rm = TRUE)
}

.fs_read_registry <- function(path) {
  if (exists("wnba_read_lifecycle_registry", mode = "function")) return(wnba_read_lifecycle_registry(path))
  if (!file.exists(path)) return(list(schema_version = 1L, sport = "wnba", files = list()))
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
#' Returns list(ok, last_game, last_regular_game, refused = data.frame(file, reason),
#' frozen = named list of NEW entries, kept = files already frozen with matching hash).
freeze_season <- function(season,
                          data_dir = WEB_DATA_DIR,
                          registry_path = WEB_DATA_LIFECYCLE_REGISTRY,
                          schedule = readRDS(CACHE_WNBA_SCHEDULE),
                          season_files = WEB_DATA_SEASON_FILES,
                          regular_season_files = WEB_DATA_REGULAR_SEASON_FILES,
                          today = Sys.Date(),
                          now = Sys.time(),
                          manifest = NULL,
                          write = TRUE) {
  season <- as.integer(season)
  last_game <- fs_season_last_game(schedule, season, today)
  # Regular-season-only files reach the last completed regular-season game instead.
  regular_files <- intersect(regular_season_files, season_files)
  last_regular <- if (length(regular_files)) {
    fs_season_last_game(schedule, season, today, regular_season_only = TRUE)
  } else as.Date(NA)
  if (is.null(manifest)) {
    # Coverage exactly as the manifest writer derives it (payload game dates for
    # through_date; payload stamp or content-hash carry-forward for generated_at).
    env <- new.env()
    old <- Sys.getenv("WNBA_SKIP_MANIFEST_AUTORUN")
    Sys.setenv(WNBA_SKIP_MANIFEST_AUTORUN = "1")
    on.exit(Sys.setenv(WNBA_SKIP_MANIFEST_AUTORUN = old), add = TRUE)
    sys.source(file.path("tools", "write_data_manifest.R"), envir = env)
    manifest <- env$build_data_manifest(data_dir = data_dir, schedule_path = NULL,
                                        now = now, lifecycle_fn = NULL)
  }
  entries <- manifest$datasets
  names(entries) <- vapply(entries, function(e) as.character(e$file), character(1))
  reg <- .fs_read_registry(registry_path)

  refused <- data.frame(file = character(0), reason = character(0), stringsAsFactors = FALSE)
  refuse <- function(f, why) refused[nrow(refused) + 1L, ] <<- list(f, why)
  frozen <- list()
  kept <- character(0)
  for (f in season_files) {
    p <- file.path(data_dir, f)
    e <- entries[[f]]
    if (!file.exists(p) || is.null(e)) { refuse(f, "file absent"); next }
    prev <- reg$files[[f]]
    if (!is.null(prev) && identical(prev$lifecycle, "season_final") &&
        !is.null(prev$season) && as.integer(prev$season) == season) {
      if (identical(as.character(prev$frozen_sha256), wnba_lifecycle_sha256(p))) {
        kept <- c(kept, f); next        # already frozen, same content: entry left as it is
      }
      refuse(f, sprintf("already frozen for season %d (frozen_at %s) but its content hash changed; not re-frozen",
                        season, as.character(prev$frozen_at %||% "unknown")))
      next
    }
    is_regular <- f %in% regular_files
    target <- if (is_regular) last_regular else last_game
    what <- if (is_regular) "the season's last regular-season game" else "the season's last game"
    thr <- if (is.null(e$through_date)) as.Date(NA) else as.Date(as.character(e$through_date))
    if (!identical(e$through_date_source, "not_game_dated")) {
      if (is.na(thr)) { refuse(f, "game-dated file has no through_date"); next }
      if (thr < target) {
        refuse(f, sprintf("through_date %s is before %s %s", thr, what, target)); next
      }
    } else {
      gen <- as.Date(substr(as.character(e$generated_at %||% ""), 1, 10))
      if (is.na(gen)) { refuse(f, "undated file has no generated_at"); next }
      if (gen < target) {
        refuse(f, sprintf("undated file generated %s, before %s %s", gen, what, target)); next
      }
    }
    frozen[[f]] <- list(lifecycle = "season_final", season = season,
                        final_through_date = format(target),
                        frozen_sha256 = wnba_lifecycle_sha256(p),
                        frozen_at = .fs_utc(now))
  }
  ok <- nrow(refused) == 0
  if (ok && isTRUE(write) && length(frozen)) {
    for (f in names(frozen)) reg$files[[f]] <- frozen[[f]]
    .fs_write_registry(reg, registry_path)
  }
  list(ok = ok, last_game = last_game, last_regular_game = last_regular, refused = refused,
       frozen = if (ok) frozen else list(), kept = if (ok) kept else character(0))
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
  if (!is.na(r$last_regular_game)) {
    cat(sprintf("Season %d last completed regular-season game: %s\n", season, format(r$last_regular_game)))
  }
  if (!r$ok) {
    cat(sprintf("REFUSED - %d file(s) cannot be frozen; nothing written:\n", nrow(r$refused)))
    for (i in seq_len(nrow(r$refused))) cat(sprintf("  %-40s %s\n", r$refused$file[i], r$refused$reason[i]))
    quit(status = 1L)
  }
  cat(sprintf("%s %d file(s) as season_final%s\n", if (write) "Froze" else "Would freeze", length(r$frozen),
              if (write) paste0(" in ", WEB_DATA_LIFECYCLE_REGISTRY) else " (dry run, nothing written)"))
  for (x in names(r$frozen)) cat(sprintf("  %-40s %s  final_through_date %s\n", x,
                                         substr(r$frozen[[x]]$frozen_sha256, 1, 16), r$frozen[[x]]$final_through_date))
  cat(sprintf("Kept %d already-frozen file(s) unchanged (content hash matches)\n", length(r$kept)))
  quit(status = 0L)
})
