# ==============================================================================
# WNBA Cache Refresh Utilities (Issue #210)
# Path: wnba_cache_utils.R
#
# Shared, pure, offline-testable helpers for determining whether WNBA multi-season
# build-once caches (wnba_espn_pbp_cache.rds, wnba_pbp_cache.rds,
# wnba_shots_cache.rds, player_box_scores_cache.rds) are up to date relative to
# the latest completed game in CACHE_WNBA_SCHEDULE (with CACHE_TEAM_BOX fallback),
# and for safely replacing ONLY CURRENT_SEASON rows while preserving historical
# seasons intact.
# ==============================================================================

.wnba_default_current_season <- function() {
  if (exists("CURRENT_SEASON", inherits = TRUE)) {
    as.integer(get("CURRENT_SEASON", inherits = TRUE))
  } else {
    as.integer(format(Sys.Date(), "%Y"))
  }
}

.wnba_default_schedule_path <- function() {
  if (exists("CACHE_WNBA_SCHEDULE", inherits = TRUE)) {
    get("CACHE_WNBA_SCHEDULE", inherits = TRUE)
  } else {
    file.path("cache", "wnba_schedule_cache.rds")
  }
}

.wnba_default_team_box_path <- function() {
  if (exists("CACHE_TEAM_BOX", inherits = TRUE)) {
    get("CACHE_TEAM_BOX", inherits = TRUE)
  } else {
    file.path("data", "box_scores_cache.rds")
  }
}

.wnba_coerce_date <- function(x) {
  if (is.null(x) || length(x) == 0L) return(as.Date(character(0)))
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) {
    tz_val <- attr(x, "tzone")
    tz_arg <- if (!is.null(tz_val) && length(tz_val) >= 1L && nzchar(tz_val[1L])) tz_val[1L] else ""
    return(suppressWarnings(as.Date(x, tz = tz_arg)))
  }
  if (is.factor(x) || is.character(x)) {
    xc <- trimws(as.character(x))
    out <- rep(as.Date(NA), length(xc))
    ok <- !is.na(xc) & nzchar(xc)
    if (any(ok)) {
      parsed <- suppressWarnings(as.Date(substr(xc[ok], 1L, 10L), format = "%Y-%m-%d"))
      miss <- is.na(parsed)
      if (any(miss)) {
        parsed[miss] <- suppressWarnings(as.Date(xc[ok][miss]))
      }
      out[ok] <- parsed
    }
    return(out)
  }
  tryCatch(suppressWarnings(as.Date(x)), error = function(e) rep(as.Date(NA), length(x)))
}

.wnba_as_logical <- function(x) {
  if (is.null(x) || length(x) == 0L) return(logical(0))
  if (is.logical(x)) return(x)
  if (is.numeric(x)) {
    out <- rep(NA, length(x))
    ok <- !is.na(x)
    out[ok] <- x[ok] != 0
    return(out)
  }
  xc <- tolower(trimws(as.character(x)))
  out <- rep(NA, length(xc))
  ok <- !is.na(xc) & nzchar(xc)
  out[ok] <- xc[ok] %in% c("true", "t", "1", "yes", "y")
  out
}

.wnba_safe_read_rds <- function(path) {
  if (is.null(path) || !is.character(path) || length(path) != 1L || !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }
  tryCatch(readRDS(path), error = function(e) {
    warning(sprintf("[CACHE UTILS] Failed to read RDS %s: %s", path, conditionMessage(e)))
    NULL
  })
}

.wnba_filter_season <- function(df, target_season) {
  if (!is.data.frame(df) || nrow(df) == 0L) return(df)
  if (!"season" %in% names(df)) return(df)
  seasons_int <- suppressWarnings(as.integer(df$season))
  target_int <- as.integer(target_season)
  df[!is.na(seasons_int) & seasons_int == target_int, , drop = FALSE]
}

#' Extract maximum completed game date for `current_season` from schedule or box cache.
#'
#' Checks `schedule_path` (`CACHE_WNBA_SCHEDULE`, requiring `is_completed` or
#' `status_type_completed` == TRUE) first, then falls back to `team_box_path`
#' (`CACHE_TEAM_BOX`, where every row is a played game). Returns `as.Date(NA)` if
#' neither source has completed `current_season` games.
wnba_schedule_completed_max_date <- function(
  current_season = .wnba_default_current_season(),
  schedule_path = .wnba_default_schedule_path(),
  team_box_path = .wnba_default_team_box_path()
) {
  sched <- .wnba_safe_read_rds(schedule_path)
  if (is.data.frame(sched) && nrow(sched) > 0L && "game_date" %in% names(sched)) {
    comp_col <- if ("is_completed" %in% names(sched)) {
      "is_completed"
    } else if ("status_type_completed" %in% names(sched)) {
      "status_type_completed"
    } else {
      NULL
    }
    if (!is.null(comp_col)) {
      sched_sub <- .wnba_filter_season(sched, current_season)
      if (nrow(sched_sub) > 0L) {
        completed <- .wnba_as_logical(sched_sub[[comp_col]])
        sched_sub <- sched_sub[completed %in% TRUE, , drop = FALSE]
        if (nrow(sched_sub) > 0L) {
          dates <- .wnba_coerce_date(sched_sub$game_date)
          dates <- dates[!is.na(dates)]
          if (length(dates) > 0L) return(max(dates))
        }
      }
    }
  }

  box <- .wnba_safe_read_rds(team_box_path)
  if (is.data.frame(box) && nrow(box) > 0L && "game_date" %in% names(box)) {
    box_sub <- .wnba_filter_season(box, current_season)
    if (nrow(box_sub) > 0L) {
      dates <- .wnba_coerce_date(box_sub$game_date)
      dates <- dates[!is.na(dates)]
      if (length(dates) > 0L) return(max(dates))
    }
  }

  as.Date(NA)
}

#' Extract the current-season maximum date from a WNBA cache object.
#'
#' Supports both data.frame caches (`wnba_espn_pbp_cache.rds`,
#' `player_box_scores_cache.rds`, `wnba_shots_cache.rds`) and `rapm_engine.R`'s
#' list shape (`list(possessions = <df>, pulled_at = <POSIXct>, ...)`).
#' When a cache table (`wnba_pbp_cache$possessions`, `wnba_shots_cache`) has
#' rows for `current_season` but no `game_date` column (because the upstream
#' WNBA Stats API loader omits game dates), falls back to `pulled_at` metadata
#' if present; returns `as.Date(NA)` if `current_season` has no rows or no date
#' metadata is available.
wnba_cache_max_date <- function(
  cache_obj,
  current_season = .wnba_default_current_season()
) {
  if (is.null(cache_obj)) return(as.Date(NA))

  df <- NULL
  pulled_at <- NULL

  if (is.data.frame(cache_obj)) {
    df <- cache_obj
    pulled_at <- attr(cache_obj, "pulled_at", exact = TRUE)
  } else if (is.list(cache_obj)) {
    if ("possessions" %in% names(cache_obj) && is.data.frame(cache_obj[["possessions"]])) {
      df <- cache_obj[["possessions"]]
    } else {
      for (el in cache_obj) {
        if (is.data.frame(el)) {
          df <- el
          break
        }
      }
    }
    pulled_at <- if (!is.null(cache_obj[["pulled_at"]])) {
      cache_obj[["pulled_at"]]
    } else {
      attr(cache_obj, "pulled_at", exact = TRUE)
    }
  } else {
    return(as.Date(NA))
  }

  if (!is.data.frame(df) || nrow(df) == 0L) return(as.Date(NA))

  sub_df <- .wnba_filter_season(df, current_season)
  if (nrow(sub_df) == 0L) return(as.Date(NA))

  if ("game_date" %in% names(sub_df)) {
    dates <- .wnba_coerce_date(sub_df$game_date)
    dates <- dates[!is.na(dates)]
    if (length(dates) > 0L) return(max(dates))
    return(as.Date(NA))
  }

  if (!is.null(pulled_at)) {
    pd <- .wnba_coerce_date(pulled_at)
    pd <- pd[!is.na(pd)]
    if (length(pd) > 0L) return(max(pd))
  }

  as.Date(NA)
}

#' Decide cache action ("fetch", "refetch", or "cache") with rationale details.
wnba_cache_decision_detail <- function(
  cache_exists,
  cache_non_empty = TRUE,
  cache_max_date = as.Date(NA),
  schedule_max_date = as.Date(NA),
  cache_mtime = as.POSIXct(NA),
  now = Sys.time(),
  force_refresh = FALSE,
  min_refresh_age_hours = 6,
  current_season_requested = TRUE
) {
  if (isTRUE(force_refresh)) {
    return(list(
      decision = "fetch",
      reason = "force_refresh=TRUE",
      age_hours = NA_real_,
      cache_max_date = .wnba_coerce_date(cache_max_date)[1L],
      schedule_max_date = .wnba_coerce_date(schedule_max_date)[1L]
    ))
  }

  if (!isTRUE(cache_exists) || !isTRUE(cache_non_empty)) {
    return(list(
      decision = "fetch",
      reason = if (!isTRUE(cache_exists)) "cache_missing" else "cache_empty_or_invalid",
      age_hours = NA_real_,
      cache_max_date = as.Date(NA),
      schedule_max_date = .wnba_coerce_date(schedule_max_date)[1L]
    ))
  }

  sched_dt <- .wnba_coerce_date(schedule_max_date)
  sched_dt <- if (length(sched_dt) > 0L) sched_dt[1L] else as.Date(NA)
  cache_dt <- .wnba_coerce_date(cache_max_date)
  cache_dt <- if (length(cache_dt) > 0L) cache_dt[1L] else as.Date(NA)

  age_hours <- if (!is.null(cache_mtime) && length(cache_mtime) > 0L && !is.na(cache_mtime)[1L]) {
    as.numeric(difftime(now, cache_mtime[1L], units = "hours"))
  } else {
    NA_real_
  }

  if (!isTRUE(current_season_requested)) {
    return(list(
      decision = "cache",
      reason = "current_season_not_requested",
      age_hours = age_hours,
      cache_max_date = cache_dt,
      schedule_max_date = sched_dt
    ))
  }

  if (is.na(sched_dt)) {
    return(list(
      decision = "cache",
      reason = "no_completed_schedule_games",
      age_hours = age_hours,
      cache_max_date = cache_dt,
      schedule_max_date = sched_dt
    ))
  }

  if (!is.na(cache_dt) && cache_dt >= sched_dt) {
    return(list(
      decision = "cache",
      reason = "up_to_date",
      age_hours = age_hours,
      cache_max_date = cache_dt,
      schedule_max_date = sched_dt
    ))
  }

  if (!is.na(age_hours) && age_hours < min_refresh_age_hours) {
    return(list(
      decision = "cache",
      reason = "within_refresh_cooldown",
      age_hours = age_hours,
      cache_max_date = cache_dt,
      schedule_max_date = sched_dt
    ))
  }

  list(
    decision = "refetch",
    reason = if (is.na(cache_dt)) "current_season_missing_or_undated" else "cache_lags_schedule",
    age_hours = age_hours,
    cache_max_date = cache_dt,
    schedule_max_date = sched_dt
  )
}

#' Pure cache refresh decision: returns "fetch", "refetch", or "cache".
wnba_cache_decision <- function(
  cache_exists,
  cache_non_empty = TRUE,
  cache_max_date = as.Date(NA),
  schedule_max_date = as.Date(NA),
  cache_mtime = as.POSIXct(NA),
  now = Sys.time(),
  force_refresh = FALSE,
  min_refresh_age_hours = 6,
  current_season_requested = TRUE
) {
  wnba_cache_decision_detail(
    cache_exists = cache_exists,
    cache_non_empty = cache_non_empty,
    cache_max_date = cache_max_date,
    schedule_max_date = schedule_max_date,
    cache_mtime = cache_mtime,
    now = now,
    force_refresh = force_refresh,
    min_refresh_age_hours = min_refresh_age_hours,
    current_season_requested = current_season_requested
  )$decision
}

.wnba_align_pair_cols <- function(df_a, df_b) {
  shared <- intersect(names(df_a), names(df_b))
  for (col in shared) {
    va <- df_a[[col]]
    vb <- df_b[[col]]
    if (inherits(va, "POSIXlt")) {
      va <- as.POSIXct(va)
      df_a[[col]] <- va
    }
    if (inherits(vb, "POSIXlt")) {
      vb <- as.POSIXct(vb)
      df_b[[col]] <- vb
    }
    if (identical(class(va), class(vb))) next

    # All-NA column on one side (often parsed as logical by upstream loaders)
    if (length(va) > 0L && all(is.na(va)) && !(length(vb) > 0L && all(is.na(vb)))) {
      df_a[[col]] <- vb[rep(NA_integer_, length(va))]
      next
    }
    if (length(vb) > 0L && all(is.na(vb)) && !(length(va) > 0L && all(is.na(va)))) {
      df_b[[col]] <- va[rep(NA_integer_, length(vb))]
      next
    }

    if (is.factor(va)) {
      va <- as.character(va)
      df_a[[col]] <- va
    }
    if (is.factor(vb)) {
      vb <- as.character(vb)
      df_b[[col]] <- vb
    }
    if (identical(class(va), class(vb))) next

    # Date alignment
    if (inherits(va, "Date") && (is.character(vb) || inherits(vb, "POSIXt"))) {
      vb_dt <- .wnba_coerce_date(vb)
      if (all(is.na(vb) == is.na(vb_dt))) {
        df_b[[col]] <- vb_dt
      } else {
        df_a[[col]] <- as.character(va)
        df_b[[col]] <- as.character(vb)
      }
      next
    }
    if (inherits(vb, "Date") && (is.character(va) || inherits(va, "POSIXt"))) {
      va_dt <- .wnba_coerce_date(va)
      if (all(is.na(va) == is.na(va_dt))) {
        df_a[[col]] <- va_dt
      } else {
        df_a[[col]] <- as.character(va)
        df_b[[col]] <- as.character(vb)
      }
      next
    }

    # Numeric / integer / logical promotions
    is_num_a <- is.numeric(va) || is.integer(va) || is.logical(va)
    is_num_b <- is.numeric(vb) || is.integer(vb) || is.logical(vb)
    if (is_num_a && is_num_b) {
      if (is.integer(va) && is.logical(vb)) {
        df_b[[col]] <- as.integer(vb)
      } else if (is.integer(vb) && is.logical(va)) {
        df_a[[col]] <- as.integer(va)
      } else {
        df_a[[col]] <- as.numeric(va)
        df_b[[col]] <- as.numeric(vb)
      }
      next
    }

    # Numeric/integer vs character: try lossless numeric parse when matching integer/numeric, else character
    if ((is.numeric(va) || is.integer(va)) && is.character(vb)) {
      vb_num <- suppressWarnings(as.numeric(vb))
      ok_b <- !is.na(vb) & nzchar(trimws(vb))
      if (all(!is.na(vb_num[ok_b]))) {
        df_a[[col]] <- as.numeric(va)
        df_b[[col]] <- if (is.integer(va) && all(vb_num[ok_b] == floor(vb_num[ok_b]))) as.integer(vb_num) else vb_num
      } else {
        df_a[[col]] <- as.character(va)
        df_b[[col]] <- vb
      }
      next
    }
    if ((is.numeric(vb) || is.integer(vb)) && is.character(va)) {
      va_num <- suppressWarnings(as.numeric(va))
      ok_a <- !is.na(va) & nzchar(trimws(va))
      if (all(!is.na(va_num[ok_a]))) {
        df_b[[col]] <- as.numeric(vb)
        df_a[[col]] <- if (is.integer(vb) && all(va_num[ok_a] == floor(va_num[ok_a]))) as.integer(va_num) else va_num
      } else {
        df_a[[col]] <- va
        df_b[[col]] <- as.character(vb)
      }
      next
    }

    # General fallback: coerce differing atomic types to character so bind_rows cannot fail
    if (is.atomic(va) && is.atomic(vb)) {
      df_a[[col]] <- as.character(va)
      df_b[[col]] <- as.character(vb)
    }
  }
  list(a = df_a, b = df_b)
}

#' Safely bind a list of data frames across seasons with schema/type reconciliation.
wnba_bind_rows_safe <- function(dfs) {
  dfs <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, dfs)
  if (length(dfs) == 0L) return(tibble::tibble())
  acc <- tibble::as_tibble(dfs[[1L]])
  if (length(dfs) == 1L) return(acc)
  for (i in 2:length(dfs)) {
    nxt <- tibble::as_tibble(dfs[[i]])
    aligned <- .wnba_align_pair_cols(acc, nxt)
    acc <- dplyr::bind_rows(aligned$a, aligned$b)
  }
  acc
}

#' Replace only `target_season` rows in `existing_df` with `new_df`, preserving historical rows.
#'
#' If `new_df` is NULL or contains zero rows for `target_season`, returns `existing_df`
#' intact so a failed/empty refresh never wipes cached data.
wnba_replace_season_rows <- function(
  existing_df,
  new_df,
  target_season = .wnba_default_current_season()
) {
  target_int <- as.integer(target_season)

  if (is.null(new_df) || !is.data.frame(new_df) || nrow(new_df) == 0L) {
    return(existing_df)
  }

  new_clean <- new_df
  if ("season" %in% names(new_clean)) {
    s_new <- suppressWarnings(as.integer(new_clean$season))
    new_clean <- new_clean[!is.na(s_new) & s_new == target_int, , drop = FALSE]
  } else {
    new_clean$season <- target_int
  }

  if (nrow(new_clean) == 0L) {
    return(existing_df)
  }

  if (is.null(existing_df) || !is.data.frame(existing_df) || nrow(existing_df) == 0L) {
    return(tibble::as_tibble(new_clean))
  }

  hist_df <- if ("season" %in% names(existing_df)) {
    s_old <- suppressWarnings(as.integer(existing_df$season))
    existing_df[is.na(s_old) | s_old != target_int, , drop = FALSE]
  } else {
    existing_df[0L, , drop = FALSE]
  }

  if (nrow(hist_df) == 0L) {
    return(tibble::as_tibble(new_clean))
  }

  aligned <- .wnba_align_pair_cols(tibble::as_tibble(hist_df), tibble::as_tibble(new_clean))
  dplyr::bind_rows(aligned$a, aligned$b)
}

#' Inspect on-disk cache state and compute refresh decision for a cache writer.
wnba_inspect_cache_state <- function(
  cache_path,
  seasons,
  force_refresh = FALSE,
  current_season = .wnba_default_current_season(),
  schedule_path = .wnba_default_schedule_path(),
  team_box_path = .wnba_default_team_box_path(),
  min_refresh_age_hours = 6,
  now = Sys.time(),
  expect_list_field = NULL
) {
  cache_exists <- !is.null(cache_path) && is.character(cache_path) &&
    length(cache_path) == 1L && nzchar(cache_path) && file.exists(cache_path)

  existing_cache <- if (cache_exists) .wnba_safe_read_rds(cache_path) else NULL

  cache_non_empty <- if (is.null(expect_list_field)) {
    !is.null(existing_cache) && is.data.frame(existing_cache) && nrow(existing_cache) > 0L
  } else {
    !is.null(existing_cache) &&
      is.list(existing_cache) &&
      !is.data.frame(existing_cache) &&
      expect_list_field %in% names(existing_cache) &&
      is.data.frame(existing_cache[[expect_list_field]]) &&
      nrow(existing_cache[[expect_list_field]]) > 0L
  }

  schedule_max_date <- wnba_schedule_completed_max_date(
    current_season = current_season,
    schedule_path = schedule_path,
    team_box_path = team_box_path
  )

  cache_max_date <- if (cache_non_empty) {
    wnba_cache_max_date(existing_cache, current_season = current_season)
  } else {
    as.Date(NA)
  }

  cache_mtime <- if (cache_exists) {
    tryCatch(file.info(cache_path)$mtime[1L], error = function(e) as.POSIXct(NA))
  } else {
    as.POSIXct(NA)
  }

  current_season_requested <- as.integer(current_season) %in% suppressWarnings(as.integer(seasons))

  detail <- wnba_cache_decision_detail(
    cache_exists = cache_exists,
    cache_non_empty = cache_non_empty,
    cache_max_date = cache_max_date,
    schedule_max_date = schedule_max_date,
    cache_mtime = cache_mtime,
    now = now,
    force_refresh = force_refresh,
    min_refresh_age_hours = min_refresh_age_hours,
    current_season_requested = current_season_requested
  )

  list(
    decision = detail$decision,
    reason = detail$reason,
    existing_cache = existing_cache,
    cache_exists = cache_exists,
    cache_non_empty = cache_non_empty,
    cache_max_date = detail$cache_max_date,
    schedule_max_date = detail$schedule_max_date,
    cache_mtime = cache_mtime,
    age_hours = detail$age_hours
  )
}
