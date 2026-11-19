# ==============================================================================
# pbp_cache_utils.R
# Shared helpers for the play-by-play stages (build_stint_dataset.R,
# build_tactical_events_dataset.R). Issue #143.
#
# 1. pbp_bind_seasons(): hoopR play-by-play does not keep one column type across
#    seasons (`id` is numeric in 2025-26 and character in 2026-27), so a plain
#    bind_rows() of two seasons fails. Columns whose class differs are coerced to
#    a common type first: character when any season has it as character (or when
#    the classes are otherwise incompatible), numeric when all are numeric/logical.
#    Values are not changed beyond the type.
#
# 2. pbp_cache_decision() / load_pbp_season_cached(): a non-empty per-season
#    cache used to be returned without checking whether it was current, so
#    cache/nba_pbp_<current>.rds never refreshed once written. The current season
#    is now refetched when its latest game_date is behind; completed seasons keep
#    coming from cache. A failed or empty refetch keeps the existing cache and
#    logs a ">>> [WARN]" line; it never empties the cache or stops the stage.
# ==============================================================================

suppressPackageStartupMessages(library(dplyr))

# Integer-valued doubles (ESPN ids) become plain digit strings, never "4e+09".
.pbp_as_character <- function(x) {
  if (is.double(x) && all(is.na(x) | x == round(x))) {
    out <- sprintf("%.0f", x)
    out[is.na(x)] <- NA_character_
    return(out)
  }
  as.character(x)
}

.pbp_class <- function(x) paste(class(x), collapse = "/")

# Returns a data.frame (name + one class column per frame) of every column whose
# class differs between the frames. Columns present in only one frame are not
# type conflicts (bind_rows fills them with NA) and are not listed.
pbp_type_mismatches <- function(frames, labels = NULL) {
  if (is.null(labels)) labels <- paste0("frame_", seq_along(frames))
  cols <- unique(unlist(lapply(frames, names)))
  rows <- lapply(cols, function(cl) {
    cls <- vapply(frames, function(f) if (cl %in% names(f)) .pbp_class(f[[cl]]) else NA_character_, "")
    if (length(unique(na.omit(cls))) > 1) {
      as.data.frame(as.list(setNames(c(cl, cls), c("name", labels))), stringsAsFactors = FALSE)
    } else NULL
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) {
    return(as.data.frame(setNames(replicate(length(labels) + 1, character(0), simplify = FALSE),
                                  c("name", labels)), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# Coerce mismatched columns to a common type, then bind.
pbp_bind_seasons <- function(frames, labels = NULL, tag = "PBP") {
  frames <- Filter(function(f) !is.null(f) && nrow(f) > 0, frames)
  if (length(frames) == 0) return(NULL)
  frames <- lapply(frames, as.data.frame)
  if (length(frames) == 1) return(frames[[1]])
  if (is.null(labels) || length(labels) != length(frames)) labels <- paste0("frame_", seq_along(frames))
  mm <- pbp_type_mismatches(frames, labels)
  for (cl in mm$name) {
    vals <- lapply(frames, function(f) if (cl %in% names(f)) f[[cl]] else NULL)
    vals <- Filter(Negate(is.null), vals)
    all_numeric <- all(vapply(vals, function(v) (is.numeric(v) || is.logical(v)) && !is.factor(v), TRUE))
    to <- if (all_numeric) "numeric" else "character"
    frames <- lapply(frames, function(f) {
      if (cl %in% names(f)) f[[cl]] <- if (to == "numeric") as.numeric(f[[cl]]) else .pbp_as_character(f[[cl]])
      f
    })
    message(sprintf(">>> [%s] Column `%s` differs across seasons (%s); coerced to %s before binding.",
                    tag, cl, paste(sprintf("%s=%s", labels, unlist(mm[mm$name == cl, labels])), collapse = ", "), to))
  }
  bind_rows(frames)
}

# Pure decision, no I/O, so it can be tested without the network.
#   "fetch"   - no usable cache; fetch it.
#   "refetch" - current season whose cache is behind; try to refresh it.
#   "cache"   - use the cache as is.
# The current season is behind when its latest game_date is before yesterday
# (games from yesterday may not be published yet) and the file has not already
# been refreshed within min_refresh_age_hours (so back-to-back stages, or an
# off-day with no new games, do not refetch on every call).
#
# reference_date (optional): when given, the cache is behind when its latest game_date is
# before that date, instead of before yesterday. The player box cache passes the later of
# the play-by-play max date and the latest completed game, so it can never lag the
# play-by-play it is joined to (front-office#191).
pbp_cache_decision <- function(season, current_season, cache_rows, cache_max_date,
                               cache_age_hours, today = Sys.Date(),
                               min_refresh_age_hours = 6, reference_date = NULL) {
  if (is.null(cache_rows) || is.na(cache_rows) || cache_rows == 0) return("fetch")
  if (season < current_season) return("cache")
  if (is.null(cache_max_date) || is.na(cache_max_date)) return("refetch")
  behind_by <- if (!is.null(reference_date) && !is.na(reference_date)) as.Date(reference_date) else (as.Date(today) - 1)
  behind <- as.Date(cache_max_date) < behind_by
  recently_refreshed <- !is.na(cache_age_hours) && cache_age_hours < min_refresh_age_hours
  if (behind && !recently_refreshed) "refetch" else "cache"
}

.pbp_max_date <- function(d) {
  if (is.null(d) || !"game_date" %in% names(d)) return(as.Date(NA))
  suppressWarnings(max(as.Date(d$game_date), na.rm = TRUE))
}

# Load one season of play-by-play from cache_dir/<prefix>_<season>.rds,
# applying pbp_cache_decision(). fetch_fn is called as fetch_fn(seasons = season).
load_pbp_season_cached <- function(season, cache_dir, current_season, fetch_fn,
                                   tag = "PBP", label = "play-by-play",
                                   prefix = "nba_pbp", today = Sys.Date(),
                                   reference_date = NULL) {
  path <- file.path(cache_dir, sprintf("%s_%d.rds", prefix, season))
  cached <- NULL
  age_h <- NA_real_
  if (file.exists(path)) {
    cached <- tryCatch(readRDS(path), error = function(e) NULL)
    if (!is.null(cached) && nrow(cached) == 0) cached <- NULL
    age_h <- as.numeric(difftime(Sys.time(), file.mtime(path), units = "hours"))
  }
  cache_max <- .pbp_max_date(cached)
  decision <- pbp_cache_decision(season, current_season,
                                 if (is.null(cached)) 0L else nrow(cached),
                                 cache_max, age_h, today = today,
                                 reference_date = reference_date)

  if (decision == "cache") {
    message(sprintf(">>> [%s] Loaded season %d %s from cache (%s rows, through %s).",
                    tag, season, label, format(nrow(cached), big.mark = ","), format(cache_max)))
    return(as.data.frame(cached))
  }

  if (decision == "refetch") {
    message(sprintf(">>> [%s] Season %d %s cache ends %s; refreshing via hoopR...",
                    tag, season, label, format(cache_max)))
  } else {
    message(sprintf(">>> [%s] Fetching season %d %s via hoopR...", tag, season, label))
  }
  fresh <- tryCatch(fetch_fn(seasons = season), error = function(e) {
    message(sprintf(">>> [WARN] hoopR %s fetch failed for season %d: %s", label, season, conditionMessage(e)))
    NULL
  })

  ok <- !is.null(fresh) && nrow(fresh) > 0 &&
        (is.null(cached) || nrow(fresh) >= nrow(cached))
  if (ok) {
    saveRDS(fresh, path)
    message(sprintf(">>> [%s] Saved season %d %s (%s rows, through %s).",
                    tag, season, label, format(nrow(fresh), big.mark = ","), format(.pbp_max_date(fresh))))
    return(as.data.frame(fresh))
  }
  if (!is.null(cached)) {
    if (!is.null(fresh) && nrow(fresh) > 0) {
      message(sprintf(">>> [WARN] hoopR returned fewer %s rows for season %d (%s) than the cache (%s); keeping the cache.",
                      label, season, format(nrow(fresh), big.mark = ","), format(nrow(cached), big.mark = ",")))
    } else {
      message(sprintf(">>> [WARN] Season %d %s refresh returned nothing; keeping the cache (through %s).",
                      season, label, format(cache_max)))
    }
    return(as.data.frame(cached))
  }
  NULL
}

# Latest completed game date in the team box cache (box_scores_cache.rds), or NA when the
# file is absent/unreadable. Used as one reference for player box freshness.
latest_completed_game_date <- function(team_box_path) {
  if (is.null(team_box_path) || !file.exists(team_box_path)) return(as.Date(NA))
  d <- tryCatch(readRDS(team_box_path), error = function(e) NULL)
  .pbp_max_date(d)
}

# The date the current-season player box cache must reach: the later of the play-by-play
# max date and the latest completed game (NA parts ignored).
box_reference_date <- function(pbp, team_box_path = NULL) {
  ds <- c(.pbp_max_date(pbp), latest_completed_game_date(team_box_path))
  ds <- ds[!is.na(ds)]
  if (length(ds) == 0) as.Date(NA) else max(ds)
}

# One player-box season through the same staleness refetch as play-by-play.
load_player_box_season_cached <- function(season, cache_dir, current_season, fetch_fn,
                                          reference_date = NULL, tag = "BOX", today = Sys.Date()) {
  load_pbp_season_cached(season, cache_dir, current_season, fetch_fn, tag = tag,
                         label = "player box", prefix = "nba_player_box", today = today,
                         reference_date = reference_date)
}
