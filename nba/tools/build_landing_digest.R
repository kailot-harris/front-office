# ==============================================================================
# NBA Analytics - landing digest writer (front-office#200, NBA#209 issues 1-4)
# Path: <repo root>/tools/build_landing_digest.R
#
# Writes web/public/data/landing_digest.json, the one payload the front-office
# landing page fetches for this sport:
#   schema_version, sport, generated_at, slate_date (US Eastern), season_state,
#   next_milestone, today[], yesterday[], record, calibration, movers.
#
# SOURCES (all real; nothing is invented)
#   * web/public/data/matchups_slates.json - every game of the season with the
#     model's pregame win probability and the final score. Only rows whose
#     log_source is "LOGGED_PREGAME" count as predictions: those were written to
#     the prediction log before tip-off. Rating-basis projections for games that
#     were never logged, and BACKTEST_PREWEEK rows, are NOT shown as predictions
#     and never graded (prediction_status "not_yet_run", null probabilities).
#   * cache/matchups_schedule_<season>.rds (slot A only) - tip-off times and
#     game status (postponed / cancelled). Absent -> start_time_utc null.
#   * cache/ensemble_team_ratings.rds (slot A only) - ensemble_net_rating, the
#     model's main team rating, appended daily to data/history/ratings_history.csv
#     for the movers block.
#
# HIT RULE (shared by all four sports)
#   The side the model gave MORE than 50% won -> hit TRUE; the other side won ->
#   FALSE. Exactly 50%, ties, and postponed or cancelled games -> hit null and
#   counted as `excluded`. Games not yet final -> hit null and not counted.
#
# Slot A (run_full_pipeline.R) calls build_landing_digest(). Slots B/C
# (tools/refresh_live_results.R) call ld_patch_digest(), which only rewrites
# yesterday, record and calibration from the patched matchups payload.
#
# No odds, spreads or lines: ld_assert_no_betting() refuses to write a payload
# carrying any such term.
#
# Usage:
#   Rscript tools/build_landing_digest.R      # slot A build
#   source("tools/build_landing_digest.R")    # functions only
# NBA_SKIP_STAGE_AUTORUN=1 also suppresses the write when run as a script.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a)) b else a

LD_FILE_NAME      <- "landing_digest.json"
LD_HISTORY_PATH   <- file.path("data", "history", "ratings_history.csv")
LD_METRIC         <- "ensemble_net_rating"
LD_HISTORY_DAYS   <- 400L
LD_WINDOWS        <- as.integer(c("1", "7", "21"))  # the movers.windows keys in the landing-digest contract
LD_TOP_N          <- 5L
LD_BUCKETS        <- list(c(0.5, 0.6), c(0.6, 0.7), c(0.7, 0.8), c(0.8, 0.9), c(0.9, 1.0))
LD_EXCLUDED_STATUS <- c("postponed", "cancelled")
LD_BETTING_RE     <- "odds|spread|moneyline|over/under|over_under|sportsbook|betting|wager"

.ld_utc <- function(x) format(as.POSIXct(x), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
ld_eastern_date <- function(now = Sys.time()) as.Date(format(as.POSIXct(now), "%Y-%m-%d", tz = "America/New_York"))
.ld_num <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else as.numeric(x)
.ld_chr <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_character_ else as.character(x)

# ------------------------------------------------------------------------------
# Hit rule
# ------------------------------------------------------------------------------

#' Grade one game. Returns list(predicted_winner, hit, excluded, graded).
#' graded = counted in `games`; excluded = counted in `excluded`.
ld_grade <- function(home, away, home_prob, home_score, away_score, final, status = NA_character_) {
  p <- .ld_num(home_prob)
  pick <- if (is.na(p) || p == 0.5) NA_character_ else if (p > 0.5) home else away
  st <- tolower(.ld_chr(status))
  if (!is.na(st) && st %in% LD_EXCLUDED_STATUS) {
    return(list(predicted_winner = pick, hit = NA, excluded = !is.na(p), graded = FALSE))
  }
  if (!isTRUE(final) || is.na(p)) return(list(predicted_winner = pick, hit = NA, excluded = FALSE, graded = FALSE))
  hs <- .ld_num(home_score); as_ <- .ld_num(away_score)
  if (is.na(hs) || is.na(as_)) return(list(predicted_winner = pick, hit = NA, excluded = FALSE, graded = FALSE))
  if (p == 0.5 || hs == as_) return(list(predicted_winner = pick, hit = NA, excluded = TRUE, graded = FALSE))
  winner <- if (hs > as_) home else away
  list(predicted_winner = pick, hit = identical(pick, winner), excluded = FALSE, graded = TRUE)
}

# ------------------------------------------------------------------------------
# Rows
# ------------------------------------------------------------------------------

.ld_is_logged <- function(m) {
  ls <- if ("log_source" %in% names(m)) as.character(m$log_source) else rep(NA_character_, nrow(m))
  hp <- if ("has_projection" %in% names(m)) m$has_projection else rep(TRUE, nrow(m))
  !is.na(ls) & ls == "LOGGED_PREGAME" & !is.na(hp) & hp & !is.na(m$predicted_home_win_prob)
}

.ld_status_from_espn <- function(name, state) {
  n <- tolower(as.character(name)); s <- tolower(as.character(state))
  out <- ifelse(grepl("postponed", n, fixed = TRUE), "postponed",
         ifelse(grepl("cancel", n, fixed = TRUE), "cancelled",
         ifelse(s == "post" | grepl("final", n, fixed = TRUE), "final",
         ifelse(s == "in", "in_progress", "scheduled"))))
  out[is.na(out)] <- "scheduled"
  out
}

#' Schedule lookup: game_id -> start_time_utc, status. NULL when no cache.
ld_schedule_lookup <- function(schedule_path) {
  if (is.null(schedule_path) || !length(schedule_path) || is.na(schedule_path) ||
      !file.exists(schedule_path)) return(NULL)
  s <- tryCatch(as.data.frame(readRDS(schedule_path)), error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(NULL)
  id <- as.character(s$game_id %||% s$id)
  st <- as.character(s$start_date %||% s$date)
  t <- as.POSIXct(sub("Z$", "", st), format = "%Y-%m-%dT%H:%M", tz = "UTC")
  data.frame(game_id = id,
             start_time_utc = ifelse(is.na(t), NA_character_, format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
             status = .ld_status_from_espn(s$status_type_name, s$status_type_state),
             season_type = as.integer(s$season_type %||% NA_integer_),
             game_date = as.character(s$game_date),
             stringsAsFactors = FALSE)
}

#' Digest rows for one date. `lookup` is a data.frame(game_id, start_time_utc,
#' status) or NULL; with_result adds the yesterday fields.
ld_rows <- function(m, date, lookup = NULL, with_result = FALSE) {
  if (is.null(m) || !nrow(m)) return(list())
  sel <- which(substr(as.character(m$game_date), 1, 10) == format(as.Date(date)))
  logged <- .ld_is_logged(m)
  lapply(sel, function(i) {
    gid <- as.character(m$game_id[i])
    k <- if (!is.null(lookup)) match(gid, lookup$game_id) else NA_integer_
    done <- isTRUE(m$is_completed[i])
    status <- if (done) "final" else if (!is.na(k)) lookup$status[k] else "scheduled"
    if (status == "final" && !done) status <- "in_progress"   # payload not yet graded
    has_pred <- logged[i]
    hp <- if (has_pred) round(as.numeric(m$predicted_home_win_prob[i]), 4) else NA_real_
    ap <- if (has_pred) round(1 - hp, 4) else NA_real_
    row <- list(game_id = gid,
                game_date = format(as.Date(date)),
                start_time_utc = if (!is.na(k)) lookup$start_time_utc[k] else NA_character_,
                home = as.character(m$home_team[i]),
                away = as.character(m$away_team[i]),
                status = status,
                home_win_prob = hp,
                away_win_prob = ap,
                prediction_status = if (has_pred) "available" else "not_yet_run")
    if (with_result) {
      g <- ld_grade(row$home, row$away, hp, m$home_score[i], m$away_score[i], done, status)
      row$home_score <- if (done) as.integer(m$home_score[i]) else NA_integer_
      row$away_score <- if (done) as.integer(m$away_score[i]) else NA_integer_
      row$final <- done
      row$predicted_winner <- g$predicted_winner
      row$hit <- g$hit
    }
    row
  })
}

# ------------------------------------------------------------------------------
# Record + calibration (issue 3)
# ------------------------------------------------------------------------------

#' Grade every logged pregame prediction in the payload.
#' `postponed_ids`: game ids known postponed/cancelled (counted as excluded).
ld_graded_table <- function(m, postponed_ids = character(0)) {
  if (is.null(m) || !nrow(m)) {
    return(data.frame(game_date = as.Date(character(0)), prob = numeric(0), hit = logical(0),
                      graded = logical(0), excluded = logical(0)))
  }
  logged <- .ld_is_logged(m)
  rows <- lapply(which(logged), function(i) {
    st <- if (as.character(m$game_id[i]) %in% postponed_ids && !isTRUE(m$is_completed[i])) "postponed" else NA
    g <- ld_grade(m$home_team[i], m$away_team[i], m$predicted_home_win_prob[i],
                  m$home_score[i], m$away_score[i], isTRUE(m$is_completed[i]), st)
    p <- as.numeric(m$predicted_home_win_prob[i])
    data.frame(game_date = as.Date(substr(as.character(m$game_date[i]), 1, 10)),
               prob = max(p, 1 - p), hit = isTRUE(g$hit),
               graded = g$graded, excluded = g$excluded)
  })
  if (!length(rows)) return(ld_graded_table(NULL))
  do.call(rbind, rows)
}

.ld_tally <- function(t) list(hits = as.integer(sum(t$hit & t$graded)), games = as.integer(sum(t$graded)),
                              excluded = as.integer(sum(t$excluded)))

ld_record <- function(m, slate_date, postponed_ids = character(0)) {
  t <- ld_graded_table(m, postponed_ids)
  t <- t[t$game_date < as.Date(slate_date), , drop = FALSE]
  last <- t[t$game_date >= as.Date(slate_date) - 7L, , drop = FALSE]
  list(season = .ld_tally(t), last_7 = .ld_tally(last))
}

ld_calibration <- function(m, slate_date, postponed_ids = character(0)) {
  t <- ld_graded_table(m, postponed_ids)
  t <- t[t$graded & t$game_date < as.Date(slate_date), , drop = FALSE]
  lapply(seq_along(LD_BUCKETS), function(b) {
    lo <- LD_BUCKETS[[b]][1]; hi <- LD_BUCKETS[[b]][2]
    inb <- t$prob > lo - 1e-12 & (t$prob < hi | (b == length(LD_BUCKETS) & t$prob <= hi))
    if (b == 1) inb <- inb & t$prob > 0.5      # exact 50% is excluded upstream; belt and braces
    n <- sum(inb)
    list(lo = round(lo * 100), hi = round(hi * 100),
         predicted_mean = if (n) round(mean(t$prob[inb]), 4) else NA_real_,
         actual_rate = if (n) round(mean(t$hit[inb]), 4) else NA_real_,
         games = as.integer(n))
  })
}

# ------------------------------------------------------------------------------
# Season state + next milestone (real schedule only)
# ------------------------------------------------------------------------------

ld_season_state <- function(slate_date, season_start, season_end, lookup = NULL) {
  d <- as.Date(slate_date)
  s <- as.Date(.ld_chr(season_start)); e <- as.Date(.ld_chr(season_end))
  if (is.na(s) || is.na(e)) return(list(state = NA_character_, milestone = NULL))
  if (d < s) return(list(state = "preseason", milestone = list(label = "Regular season opens", date = format(s))))
  if (d <= e) return(list(state = "regular", milestone = list(label = "Regular season ends", date = format(e))))
  post <- if (!is.null(lookup)) lookup[!is.na(lookup$season_type) & lookup$season_type >= 3L &
                                         as.Date(lookup$game_date) >= d, , drop = FALSE] else NULL
  if (!is.null(post) && nrow(post)) {
    return(list(state = "postseason",
                milestone = list(label = "Next postseason game", date = format(min(as.Date(post$game_date))))))
  }
  list(state = "offseason", milestone = NULL)   # next season's dates are not in the cache: no guess
}

# ------------------------------------------------------------------------------
# Ratings history + movers (issue 4)
# ------------------------------------------------------------------------------

ld_read_history <- function(path = LD_HISTORY_PATH) {
  if (!file.exists(path)) return(data.frame(date = character(0), team = character(0),
                                            metric = character(0), value = numeric(0)))
  h <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = c("character", "character", "character", "numeric"))
  h
}

#' Replace `date`'s rows for `metric`, prune to `keep_days`, write sorted.
ld_update_history <- function(ratings, date, path = LD_HISTORY_PATH, metric = LD_METRIC,
                              keep_days = LD_HISTORY_DAYS) {
  h <- ld_read_history(path)
  d <- format(as.Date(date))
  new <- data.frame(date = d, team = as.character(ratings$team), metric = metric,
                    value = round(as.numeric(ratings$value), 2), stringsAsFactors = FALSE)
  new <- new[!is.na(new$value) & nzchar(new$team), , drop = FALSE]
  h <- h[!(h$date == d & h$metric == metric), , drop = FALSE]
  h <- rbind(h, new)
  h <- h[as.Date(h$date) > as.Date(d) - keep_days, , drop = FALSE]
  h <- h[order(h$date, h$metric, h$team), , drop = FALSE]
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(h, path, row.names = FALSE, quote = FALSE)
  invisible(h)
}

#' movers block. Current = the latest history date; each window compares with
#' the latest history date on or before (current - window), recorded as
#' compared_to. No such date -> compared_to null, items empty.
ld_movers <- function(h, metric = LD_METRIC, windows = LD_WINDOWS, top_n = LD_TOP_N) {
  h <- h[h$metric == metric, , drop = FALSE]
  empty <- function() list(compared_to = NA_character_, items = list())
  out <- list()
  if (!nrow(h)) {
    for (w in windows) out[[as.character(w)]] <- empty()
    return(list(metric = metric, as_of = NA_character_, windows = out))
  }
  dates <- sort(unique(as.Date(h$date)))
  cur_d <- max(dates)
  cur <- h[as.Date(h$date) == cur_d, , drop = FALSE]
  for (w in windows) {
    cand <- dates[dates <= cur_d - w]
    if (!length(cand)) { out[[as.character(w)]] <- empty(); next }
    cmp_d <- max(cand)
    prev <- h[as.Date(h$date) == cmp_d, , drop = FALSE]
    j <- merge(cur[, c("team", "value")], prev[, c("team", "value")], by = "team", suffixes = c("_cur", "_prev"))
    j$delta <- j$value_cur - j$value_prev
    j <- j[order(-abs(j$delta), j$team), , drop = FALSE]
    j <- utils::head(j, top_n)
    out[[as.character(w)]] <- list(
      compared_to = format(cmp_d),
      items = lapply(seq_len(nrow(j)), function(r) list(team = j$team[r], previous = round(j$value_prev[r], 2),
                                                        current = round(j$value_cur[r], 2), delta = round(j$delta[r], 2))))
  }
  list(metric = metric, as_of = format(cur_d), windows = out)
}

ld_read_ratings <- function(ratings_path) {
  if (is.null(ratings_path) || !file.exists(ratings_path)) return(NULL)
  r <- tryCatch(as.data.frame(readRDS(ratings_path)), error = function(e) NULL)
  if (is.null(r) || !all(c("team", LD_METRIC) %in% names(r))) return(NULL)
  data.frame(team = as.character(r$team), value = unname(as.numeric(r[[LD_METRIC]])), stringsAsFactors = FALSE)
}

# ------------------------------------------------------------------------------
# Assemble / write
# ------------------------------------------------------------------------------

ld_assert_no_betting <- function(x) {
  txt <- as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null"))
  if (grepl(LD_BETTING_RE, tolower(txt))) stop("landing digest carries a betting term; refusing to write.", call. = FALSE)
  invisible(TRUE)
}

.ld_json_text <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE,
                                                           null = "null", na = "null", digits = NA))

#' Write unless only generated_at would change. Returns TRUE if written.
#' force = TRUE (slot A) always writes, so publish_web.R assertion A (mtime of
#' WEB_DATA_FILES) sees a fresh file every pipeline run.
ld_write <- function(digest, path, force = FALSE) {
  ld_assert_no_betting(digest)
  if (!force && file.exists(path)) {
    old <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(old)) {
      a <- digest; a$generated_at <- NULL; b <- old; b$generated_at <- NULL
      norm <- function(z) jsonlite::fromJSON(.ld_json_text(z), simplifyVector = FALSE)
      if (identical(norm(a), norm(b))) return(FALSE)
    }
  }
  writeLines(.ld_json_text(digest), path, useBytes = TRUE)
  TRUE
}

.ld_postponed_ids <- function(lookup) {
  if (is.null(lookup)) character(0) else lookup$game_id[lookup$status %in% LD_EXCLUDED_STATUS]
}

#' Slot A build.
build_landing_digest <- function(matchups_path = file.path("web", "public", "data", "matchups_slates.json"),
                                 schedule_path = NULL,
                                 ratings_path = file.path("cache", "ensemble_team_ratings.rds"),
                                 history_path = LD_HISTORY_PATH,
                                 out_path = file.path("web", "public", "data", LD_FILE_NAME),
                                 now = Sys.time()) {
  p <- jsonlite::fromJSON(matchups_path, simplifyVector = TRUE)
  m <- p$matchups
  m$game_id <- as.character(m$game_id)
  lookup <- ld_schedule_lookup(schedule_path)
  slate <- ld_eastern_date(now)
  ss <- ld_season_state(slate, p$season_start_date, p$season_end_date, lookup)

  ratings <- ld_read_ratings(ratings_path)
  h <- if (!is.null(ratings)) ld_update_history(ratings, slate, history_path) else ld_read_history(history_path)
  postponed <- .ld_postponed_ids(lookup)

  digest <- list(
    schema_version = 1L,
    sport = "nba",
    generated_at = .ld_utc(now),
    slate_date = format(slate),
    season_state = ss$state,
    next_milestone = ss$milestone,
    today = ld_rows(m, slate, lookup),
    yesterday = ld_rows(m, slate - 1L, lookup, with_result = TRUE),
    record = ld_record(m, slate, postponed),
    calibration = ld_calibration(m, slate, postponed),
    movers = ld_movers(h),
    excluded_game_ids = as.list(intersect(postponed, m$game_id[.ld_is_logged(m)]))
  )
  written <- ld_write(digest, out_path, force = TRUE)
  invisible(list(path = out_path, written = written, digest = digest))
}

#' Slots B/C: refresh yesterday, record and calibration from the (already
#' patched) matchups payload. Everything else is carried through unchanged.
ld_patch_digest <- function(digest, matchups) {
  m <- matchups
  m$game_id <- as.character(m$game_id)
  slate <- as.Date(digest$slate_date)
  postponed <- unlist(digest$excluded_game_ids %||% list())
  # carry start times / statuses the slot A build recorded
  prev <- digest$yesterday %||% list()
  lookup <- if (length(prev)) data.frame(
    game_id = vapply(prev, function(r) as.character(r$game_id), ""),
    start_time_utc = vapply(prev, function(r) .ld_chr(r$start_time_utc), ""),
    status = vapply(prev, function(r) .ld_chr(r$status), ""),
    stringsAsFactors = FALSE) else NULL
  digest$yesterday <- ld_rows(m, slate - 1L, lookup, with_result = TRUE)
  digest$record <- ld_record(m, slate, postponed)
  digest$calibration <- ld_calibration(m, slate, postponed)
  digest
}

#' Read, patch, write. Returns TRUE if the file changed.
ld_patch_digest_file <- function(path, matchups, now = Sys.time()) {
  if (!file.exists(path)) return(FALSE)
  d <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  d2 <- ld_patch_digest(d, matchups)
  d2$generated_at <- .ld_utc(now)
  ld_write(d2, path)
}

#' Pipeline entry (run_full_pipeline.R call_fn). Reads config.R's paths when
#' present; runs from the project root.
run_build_landing_digest <- function() {
  sched <- NULL
  if (exists("CACHE_MATCHUPS_SCHEDULE", mode = "function") && exists("MATCHUPS_HOOPR_SEASON")) {
    sched <- CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON)
  } else if (file.exists("config.R")) {
    env <- new.env()
    ok <- tryCatch({ sys.source("config.R", envir = env); TRUE }, error = function(e) FALSE)
    if (ok) sched <- env$CACHE_MATCHUPS_SCHEDULE(env$MATCHUPS_HOOPR_SEASON)
  }
  res <- build_landing_digest(schedule_path = sched)
  message(sprintf(">>> build_landing_digest: %s %s", if (res$written) "wrote" else "unchanged", res$path))
  invisible(res)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("build_landing_digest\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN", ""))) return(invisible(NULL))
  setwd(normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE))
  run_build_landing_digest()
})
