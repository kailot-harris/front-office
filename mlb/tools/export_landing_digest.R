# ==============================================================================
# tools/export_landing_digest.R — web/public/data/landing_digest.json
#
# The front-office landing page's MLB feed (spec: front-office#200, sport epic
# MLB-Analytics#123). One small payload:
#
#   schema_version, sport, generated_at, slate_date (US Eastern),
#   season_state, next_milestone,
#   today[], yesterday[]   games from the cached season schedule, with the
#                          model's pre-game probability where one exists
#   record, calibration    from the prediction log (matchups/week-NN.json)
#   movers                 main team rating (Elo) change over 1 / 7 / 21 days,
#                          from the tracked data/history/ratings_history.csv
#
# Hit rule (identical across sports): the side the model gave MORE than 50%
# won. Exact 50% picks, ties and postponed / cancelled / suspended games get
# hit = null and count as `excluded`. Nothing here odds, lines or spreads.
#
# Written by the slot A pipeline (run_full_pipeline.R stage 14c). Slots B/C
# patch yesterday / record / calibration through tools/refresh_live_results.R,
# which reuses the pure helpers below (they read no caches).
#
# Usage:
#   Rscript tools/export_landing_digest.R
# ==============================================================================

LD_SCHEMA_VERSION <- 1L
LD_SPORT          <- "mlb"
LD_FILE           <- "landing_digest.json"
# Main team rating: the pitcher-adjusted Elo rating the Elo engine already
# produces (cache/ratings/mlb_team_ratings.rds, column elo_rating).
LD_METRIC         <- "elo_rating"
LD_HISTORY_PATH   <- file.path("data", "history", "ratings_history.csv")
LD_HISTORY_KEEP_DAYS <- 400L
LD_MOVER_WINDOWS  <- c(1L, 7L, 21L)
LD_MOVER_TOP_N    <- 5L
LD_TZ             <- "America/New_York"

LD_GAME_TYPES       <- c("R", "F", "D", "L", "W")
LD_POSTSEASON_TYPES <- c("F", "D", "L", "W")
LD_FINAL_STATUSES   <- c("Final", "Completed Early", "Game Over")
LD_VOID_PATTERN     <- "^(Postponed|Cancelled|Canceled|Suspended)"

.ld_or <- function(a, b) if (is.null(a) || length(a) == 0) b else a
.ld_num <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else as.numeric(x)
.ld_int <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA_integer_ else as.integer(x)
.ld_na_null <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NULL else x

ld_eastern_date <- function(time = Sys.time()) {
  as.Date(format(as.POSIXct(time, tz = "UTC"), tz = LD_TZ, usetz = FALSE))
}

.ld_utc_iso <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return(NA_character_)
  t <- as.POSIXct(substr(x, 1, 19), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  if (is.na(t)) NA_character_ else format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# ------------------------------------------------------------------------------
# Hit rule
# ------------------------------------------------------------------------------

#' Shared hit rule. Vectorised.
#' @return logical: TRUE/FALSE, NA = excluded (or ungradable)
ld_hit <- function(home_win_prob, home_score, away_score, status = "Final") {
  status <- as.character(status)
  status[is.na(status)] <- ""
  out <- (home_win_prob > 0.5) == (home_score > away_score)
  void <- is.na(home_win_prob) | home_win_prob == 0.5 |
    is.na(home_score) | is.na(away_score) | home_score == away_score |
    grepl(LD_VOID_PATTERN, status, ignore.case = TRUE)
  out[void] <- NA
  as.logical(out)
}

ld_predicted_winner <- function(home, away, home_win_prob) {
  if (is.na(home_win_prob) || home_win_prob == 0.5) return(NA_character_)
  if (home_win_prob > 0.5) home else away
}

# ------------------------------------------------------------------------------
# Prediction log (committed matchups/week-NN.json)
# ------------------------------------------------------------------------------

LD_LOG_COLS <- c("game_pk", "game_date", "status_detail", "is_completed", "home_team_id",
                 "home_team", "away_team_id", "away_team", "home_win_prob", "away_win_prob",
                 "projection_source", "home_score", "away_score")

ld_read_prediction_log <- function(data_dir) {
  fs <- sort(list.files(file.path(data_dir, "matchups"), pattern = "^week-[0-9]+[.]json$",
                        full.names = TRUE))
  rows <- lapply(fs, function(f) {
    d <- jsonlite::fromJSON(f, simplifyDataFrame = TRUE)
    if (!is.data.frame(d) || !nrow(d)) return(NULL)
    for (c in setdiff(LD_LOG_COLS, names(d))) d[[c]] <- NA
    d[, LD_LOG_COLS]
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) {
    return(as.data.frame(setNames(replicate(length(LD_LOG_COLS), logical(0), simplify = FALSE),
                                  LD_LOG_COLS)))
  }
  do.call(rbind, rows)
}

# Rows that are honest pre-game predictions and are decided (or voided)
# before slate_date. Only walk_forward probabilities count: current_elo
# probabilities on already-played games are hindsight and are never graded.
.ld_graded_rows <- function(log, slate_date) {
  if (!nrow(log)) return(log)
  d <- as.Date(substr(as.character(log$game_date), 1, 10))
  decided <- isTRUE_vec(log$is_completed) |
    grepl(LD_VOID_PATTERN, as.character(log$status_detail), ignore.case = TRUE)
  keep <- !is.na(d) & d < as.Date(slate_date) & decided &
    !is.na(log$home_win_prob) & as.character(log$projection_source) %in% "walk_forward"
  out <- log[keep, , drop = FALSE]
  out$date <- d[keep]
  out$hit <- ld_hit(as.numeric(out$home_win_prob), as.numeric(out$home_score),
                    as.numeric(out$away_score), out$status_detail)
  out
}

isTRUE_vec <- function(x) !is.na(x) & as.logical(x)

.ld_tally <- function(hit) {
  list(hits = as.integer(sum(hit %in% TRUE)),
       games = as.integer(sum(!is.na(hit))),
       excluded = as.integer(sum(is.na(hit))))
}

#' record: season and last 7 days (the 7 calendar days before slate_date)
ld_record <- function(log, slate_date) {
  g <- .ld_graded_rows(log, slate_date)
  last7 <- if (nrow(g)) g$date >= as.Date(slate_date) - 7L else logical(0)
  list(season = .ld_tally(g$hit), last_7 = .ld_tally(g$hit[last7]))
}

#' calibration: season-long buckets 50-100% by 10, on the favoured side
ld_calibration <- function(log, slate_date) {
  g <- .ld_graded_rows(log, slate_date)
  g <- g[!is.na(g$hit), , drop = FALSE]
  p <- pmax(as.numeric(g$home_win_prob), 1 - as.numeric(g$home_win_prob))
  lapply(seq(50, 90, by = 10), function(lo) {
    hi <- lo + 10
    in_b <- p >= lo / 100 & (if (hi == 100) p <= 1 else p < hi / 100)
    n <- sum(in_b)
    list(lo = as.integer(lo), hi = as.integer(hi),
         predicted_mean = if (n) round(mean(p[in_b]), 4) else NULL,
         actual_rate = if (n) round(mean(g$hit[in_b]), 4) else NULL,
         games = as.integer(n))
  })
}

# ------------------------------------------------------------------------------
# Games (today / yesterday) from the cached schedule
# ------------------------------------------------------------------------------

.ld_team_abbr_map <- function(log) {
  ids <- c(log$home_team_id, log$away_team_id)
  ab <- c(as.character(log$home_team), as.character(log$away_team))
  keep <- !is.na(ids) & !is.na(ab) & !duplicated(ids)
  setNames(ab[keep], as.character(ids[keep]))
}

.ld_schedule_games <- function(schedule, date) {
  s <- as.data.frame(schedule, stringsAsFactors = FALSE)
  if (!nrow(s)) return(s)
  s <- s[as.character(s$game_type) %in% LD_GAME_TYPES &
           as.character(s$official_date) == format(as.Date(date)), , drop = FALSE]
  if (!nrow(s)) return(s)
  # A postponed game and its makeup can share a game_pk: keep the played row.
  played <- as.character(s$status_detailed_state) %in% LD_FINAL_STATUSES
  s <- s[order(s$game_pk, !played), , drop = FALSE]
  s <- s[!duplicated(s$game_pk), , drop = FALSE]
  s[order(s$game_date, s$game_pk), , drop = FALSE]
}

#' Build today[] or yesterday[] rows
ld_game_rows <- function(schedule, log, date, slate_date, with_result = FALSE) {
  s <- .ld_schedule_games(schedule, date)
  if (!nrow(s)) return(list())
  abbr <- .ld_team_abbr_map(log)
  team <- function(id, name) .ld_or(unname(abbr[as.character(id)]), name)
  lapply(seq_len(nrow(s)), function(i) {
    r <- s[i, ]
    j <- match(r$game_pk, log$game_pk)
    hp <- if (is.na(j)) NA_real_ else .ld_num(log$home_win_prob[j])
    ap <- if (is.na(j)) NA_real_ else .ld_num(log$away_win_prob[j])
    if (!is.na(hp) && is.na(ap)) ap <- round(1 - hp, 4)
    pstatus <- if (!is.na(hp)) "available" else if (is.na(j)) "not_yet_run" else "no_model"
    home <- team(r$teams_home_team_id, r$teams_home_team_name)
    away <- team(r$teams_away_team_id, r$teams_away_team_name)
    status <- as.character(r$status_detailed_state)
    row <- list(
      game_id = as.character(r$game_pk),
      start_time_utc = .ld_na_null(.ld_utc_iso(r$game_date)),
      home = home, away = away, status = status,
      home_win_prob = .ld_na_null(hp), away_win_prob = .ld_na_null(ap),
      prediction_status = pstatus
    )
    if (with_result) {
      final <- status %in% LD_FINAL_STATUSES
      hs <- if (final) .ld_int(r$teams_home_score) else NA_integer_
      as_ <- if (final) .ld_int(r$teams_away_score) else NA_integer_
      row$home_score <- .ld_na_null(hs)
      row$away_score <- .ld_na_null(as_)
      row$final <- final
      row$predicted_winner <- .ld_na_null(ld_predicted_winner(home, away, hp))
      row$hit <- .ld_na_null(if (final) ld_hit(hp, hs, as_, status) else NA)
    }
    row
  })
}

# ------------------------------------------------------------------------------
# Season state and next milestone
# ------------------------------------------------------------------------------

ld_season_state <- function(schedule, slate_date) {
  s <- as.data.frame(schedule, stringsAsFactors = FALSE)
  d <- as.Date(slate_date)
  sd <- as.Date(as.character(s$official_date))
  ty <- as.character(s$game_type)
  reg <- sd[ty == "R"]; post <- sd[ty %in% LD_POSTSEASON_TYPES]; pre <- sd[ty %in% c("S", "E")]
  if (!length(reg)) return("offseason")
  if (d >= min(reg) && d <= max(reg)) return("regular")
  if (length(post) && d > max(reg) && d <= max(post)) return("postseason")
  if (d < min(reg)) return(if (length(pre) && d >= min(pre)) "preseason" else "offseason")
  "offseason"
}

#' Next milestone from real data only, or NULL.
#' In-season: from the schedule. Off-season: the earliest Confirmed upcoming
#' milestone in the latest offseason_monitor.json edition.
ld_next_milestone <- function(state, schedule, slate_date, monitor = NULL) {
  s <- as.data.frame(schedule, stringsAsFactors = FALSE)
  d <- as.Date(slate_date)
  sd <- as.Date(as.character(s$official_date))
  ty <- as.character(s$game_type)
  first_after <- function(types) {
    x <- sd[ty %in% types & sd > d]
    if (length(x)) min(x) else NA
  }
  ms <- function(label, date) if (is.na(date)) NULL else list(label = label, date = format(date))
  if (identical(state, "preseason") || (identical(state, "offseason") && !is.na(first_after("R")))) {
    return(ms("Opening Day", first_after("R")))
  }
  if (identical(state, "regular")) return(ms("Postseason begins", first_after(LD_POSTSEASON_TYPES)))
  if (identical(state, "postseason")) return(NULL)
  eds <- monitor$editions
  if (!length(eds)) return(NULL)
  wk <- vapply(eds, function(e) as.integer(.ld_or(e$weekNumber, NA)), integer(1))
  ed <- eds[[which.max(wk)]]
  cand <- Filter(function(m) identical(m$status, "Confirmed") && is.character(m$date) &&
                   !is.na(as.Date(m$date, optional = TRUE)) && as.Date(m$date) >= d,
                 .ld_or(ed$upcomingMilestones, list()))
  if (!length(cand)) return(NULL)
  m <- cand[[order(vapply(cand, function(m) m$date, character(1)))[1]]]
  list(label = m$event, date = m$date)
}

# ------------------------------------------------------------------------------
# Ratings history and movers
# ------------------------------------------------------------------------------

ld_read_history <- function(path = LD_HISTORY_PATH) {
  if (!file.exists(path)) {
    return(data.frame(date = character(0), team = character(0), metric = character(0),
                      value = numeric(0), stringsAsFactors = FALSE))
  }
  h <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = c("character", "character",
                                                                      "character", "numeric"))
  h[, c("date", "team", "metric", "value")]
}

#' Replace the rows for `date`, prune to keep_days, sort.
ld_update_history <- function(hist, date, teams, values, metric = LD_METRIC,
                              keep_days = LD_HISTORY_KEEP_DAYS) {
  date <- format(as.Date(date))
  hist <- hist[!(hist$date == date & hist$metric == metric), , drop = FALSE]
  add <- data.frame(date = date, team = as.character(teams), metric = metric,
                    value = round(as.numeric(values), 1), stringsAsFactors = FALSE)
  hist <- rbind(hist, add[!is.na(add$value), , drop = FALSE])
  hist <- hist[as.Date(hist$date) >= as.Date(date) - keep_days, , drop = FALSE]
  hist <- hist[order(hist$date, hist$metric, hist$team), , drop = FALSE]
  rownames(hist) <- NULL
  hist
}

ld_write_history <- function(hist, path = LD_HISTORY_PATH) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(hist, path, row.names = FALSE, quote = FALSE)
  invisible(path)
}

#' One-time backfill from the Elo engine's per-game history: each team's
#' rating after its last game on or before each game date (US Eastern).
ld_backfill_from_elo <- function(elo_history, abbr_map, metric = LD_METRIC) {
  h <- as.data.frame(elo_history, stringsAsFactors = FALSE)
  h$d <- format(ld_eastern_date(as.POSIXct(substr(h$game_date, 1, 19),
                                           format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")))
  long <- rbind(
    data.frame(d = h$d, gd = h$game_date, team_id = h$home_team_id, value = h$post_home_elo),
    data.frame(d = h$d, gd = h$game_date, team_id = h$away_team_id, value = h$post_away_elo)
  )
  long <- long[order(long$team_id, long$gd), ]
  dates <- sort(unique(long$d))
  out <- list()
  for (tid in unique(long$team_id)) {
    t <- long[long$team_id == tid, ]
    idx <- findInterval(as.numeric(as.Date(dates)), as.numeric(as.Date(t$d)))
    ok <- idx > 0
    out[[length(out) + 1L]] <- data.frame(
      date = dates[ok], team = .ld_or(unname(abbr_map[as.character(tid)]), as.character(tid)),
      metric = metric, value = round(t$value[idx[ok]], 1), stringsAsFactors = FALSE)
  }
  res <- do.call(rbind, out)
  res[order(res$date, res$team), ]
}

#' movers for windows 1/7/21: compared_to = nearest history date on or before
#' (current date - window); empty when there is no such date.
ld_movers <- function(hist, slate_date, metric = LD_METRIC, windows = LD_MOVER_WINDOWS,
                      top_n = LD_MOVER_TOP_N) {
  h <- hist[hist$metric == metric, , drop = FALSE]
  h$d <- as.Date(h$date)
  h <- h[!is.na(h$d) & h$d <= as.Date(slate_date), , drop = FALSE]
  empty <- function() list(compared_to = NULL, items = list())
  win <- setNames(lapply(windows, function(w) empty()), as.character(windows))
  if (!nrow(h)) return(list(metric = metric, windows = win))
  cur_d <- max(h$d)
  cur <- h[h$d == cur_d, , drop = FALSE]
  for (w in windows) {
    prior <- h$d[h$d <= cur_d - w]
    if (!length(prior)) next
    pd <- max(prior)
    prev <- h[h$d == pd, , drop = FALSE]
    m <- merge(cur[, c("team", "value")], prev[, c("team", "value")], by = "team",
               suffixes = c("_cur", "_prev"))
    m$delta <- round(m$value_cur - m$value_prev, 1)
    m <- m[m$delta != 0, , drop = FALSE]
    m <- m[order(-abs(m$delta), m$team), , drop = FALSE]
    m <- utils::head(m, top_n)
    win[[as.character(w)]] <- list(
      compared_to = format(pd),
      items = lapply(seq_len(nrow(m)), function(i) list(
        team = m$team[i], previous = m$value_prev[i], current = m$value_cur[i], delta = m$delta[i])))
  }
  list(metric = metric, windows = win)
}

# ------------------------------------------------------------------------------
# Assembly
# ------------------------------------------------------------------------------

build_landing_digest <- function(schedule, log, history, monitor = NULL,
                                 now = Sys.time(), slate_date = ld_eastern_date(now)) {
  slate_date <- as.Date(slate_date)
  state <- ld_season_state(schedule, slate_date)
  list(
    schema_version = LD_SCHEMA_VERSION,
    sport = LD_SPORT,
    generated_at = format(as.POSIXct(now, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    slate_date = format(slate_date),
    season_state = state,
    next_milestone = ld_next_milestone(state, schedule, slate_date, monitor),
    today = ld_game_rows(schedule, log, slate_date, slate_date, with_result = FALSE),
    yesterday = ld_game_rows(schedule, log, slate_date - 1L, slate_date, with_result = TRUE),
    record = ld_record(log, slate_date),
    calibration = ld_calibration(log, slate_date),
    movers = ld_movers(history, slate_date)
  )
}

ld_to_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
}

#' Slot A entry point (run_full_pipeline.R stage 14c)
run_landing_digest_export <- function(season = MLB_CURRENT_SEASON,
                                      data_dir = WEB_DATA_DIR,
                                      history_path = LD_HISTORY_PATH,
                                      now = Sys.time()) {
  schedule <- readRDS(CACHE_MLB_SCHEDULE(season))
  log <- ld_read_prediction_log(data_dir)
  slate_date <- ld_eastern_date(now)

  hist <- ld_read_history(history_path)
  elo_hist_path <- cache_path("ratings", "mlb_elo_history.rds", create = FALSE)
  if (!nrow(hist) && file.exists(elo_hist_path)) {
    hist <- ld_backfill_from_elo(readRDS(elo_hist_path), .ld_team_abbr_map(log))
  }
  ratings_path <- cache_path("ratings", "mlb_team_ratings.rds", create = FALSE)
  if (file.exists(ratings_path)) {
    r <- as.data.frame(readRDS(ratings_path))
    abbr <- .ld_team_abbr_map(log)
    teams <- vapply(r$team_id, function(id) .ld_or(unname(abbr[as.character(id)]),
                                                   as.character(id)), character(1))
    hist <- ld_update_history(hist, slate_date, teams, r[[LD_METRIC]])
  } else {
    hist <- ld_update_history(hist, slate_date, character(0), numeric(0))
  }
  ld_write_history(hist, history_path)

  monitor_path <- file.path(data_dir, "offseason_monitor.json")
  monitor <- if (file.exists(monitor_path)) {
    jsonlite::fromJSON(monitor_path, simplifyVector = FALSE)
  } else NULL

  digest <- build_landing_digest(schedule, log, hist, monitor, now = now, slate_date = slate_date)
  out <- file.path(data_dir, LD_FILE)
  writeLines(ld_to_json(digest), out, useBytes = TRUE)
  message(sprintf("landing digest: %s (%s, today=%d, yesterday=%d, history rows=%d)",
                  out, digest$season_state, length(digest$today), length(digest$yesterday),
                  nrow(hist)))
  invisible(digest)
}

if (!interactive() && sys.nframe() == 0L) {
  suppressPackageStartupMessages(library(jsonlite))
  source("config.R")
  run_landing_digest_export()
}
