# ==============================================================================
# tools/build_landing_digest.R  (NFL_analytics#182-#185, front-office#200)
#
# Writes web/public/data/landing_digest.json, the one payload the front-office
# landing page fetches for NFL. Contract: front-office#200 spec section 1.
#
#   schema_version, sport, generated_at, slate_date (US Eastern),
#   season_state, next_milestone, today[], yesterday[], record, calibration,
#   movers {metric, windows {"1","7","21"}}
#
# WHERE THE NUMBERS COME FROM - nothing here is predicted, only read:
#   * Games, kickoff times, scores and win probabilities come from the
#     committed web/public/data/matchups_current_week.json. That payload is the
#     exporter's published copy of the prediction log
#     (cache/prediction_accuracy_log.rds): every row carries the pre-week
#     home_win_prob the log recorded, and the full season (all weeks), not just
#     the active week. Reading the payload instead of the .rds is deliberate:
#     slots B and C (tools/refresh_live_results.R, GitHub Actions) have no
#     cache/, and slot A must compute record/calibration exactly the way B/C
#     re-compute them, or the numbers would jump between slots.
#   * season_state / next_milestone come from the season schedule
#     (CACHE_SCHEDULES when present, so postseason rows are visible; otherwise
#     the payload's own schedule). Unknown => null, never guessed.
#   * movers come from data/history/ratings_history.csv, one row per team per
#     pipeline day of power_rating (cache/team_ratings.rds, the rating every
#     NFL projection is built from). The file is TRACKED and lives outside both
#     cache/ and web/public/ on purpose (MLB-Analytics#121: a /cache/ ignore
#     rule silently dropped a history file from every commit).
#
# HIT RULE (identical in all four sports):
#   hit = the side the model gave MORE than 50% won.
#   Exactly 50%, a tie, or a postponed/cancelled game => hit = null, counted in
#   `excluded`. `games` counts graded decisions only (hits + misses).
#
# Usage:
#   Rscript tools/build_landing_digest.R          # slot A writer
#   source("tools/build_landing_digest.R")        # helpers only, no writes
# Needs jsonlite only, so refresh_live_results.R can source it on a CI runner.
# ==============================================================================

LANDING_DIGEST_FILENAME       <- "landing_digest.json"
LANDING_DIGEST_SCHEMA_VERSION <- 1L
LANDING_RATINGS_HISTORY       <- file.path("data", "history", "ratings_history.csv")
LANDING_RATING_METRIC         <- "power_rating"
LANDING_HISTORY_KEEP_DAYS     <- 400L
LANDING_MOVER_WINDOWS         <- as.integer(c("1", "7", "21"))  # the movers.windows keys in the landing-digest contract
LANDING_MOVERS_TOP_N          <- 5L
LANDING_TZ                    <- "America/New_York"
# NFL scheduling fact, not a model constant: the Super Bowl is played about
# five weeks after the last regular-season Sunday. Used ONLY to label the gap
# before nflverse has published postseason rows; once they exist they win.
LANDING_POSTSEASON_SPAN_DAYS  <- 35L

# Defined only when absent: run_full_pipeline.R sources this into the global
# env, where logging_utils.R's canonical `%||%` (M-6) must keep winning.
if (!exists("%||%", mode = "function")) `%||%` <- function(a, b) if (is.null(a)) b else a

ld_iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
ld_slate_date <- function(now = Sys.time()) as.Date(format(now, "%Y-%m-%d", tz = LANDING_TZ))

# Kickoff in UTC from nflverse's gameday + gametime, which are US Eastern.
ld_start_time_utc <- function(gameday, gametime) {
  gt <- ifelse(is.na(gametime) | !nzchar(gametime), "00:00", gametime)
  t <- as.POSIXct(paste(gameday, gt), format = "%Y-%m-%d %H:%M", tz = LANDING_TZ)
  out <- ld_iso(t)
  out[is.na(t)] <- NA_character_
  out
}

# ------------------------------------------------------------------------------
# Hit rule
# ------------------------------------------------------------------------------

#' Grade one prediction with the shared hit rule.
#' @return TRUE / FALSE, or NA when excluded (no prediction, exact 50%, tie,
#'   postponed or cancelled, not final).
ld_hit <- function(home_win_prob, home_score, away_score, status = "final") {
  if (is.null(home_win_prob) || length(home_win_prob) != 1 || is.na(home_win_prob)) return(NA)
  if (!identical(status, "final")) return(NA)
  if (is.na(home_score) || is.na(away_score)) return(NA)
  if (home_score == away_score) return(NA)
  if (isTRUE(all.equal(as.numeric(home_win_prob), 0.5))) return(NA)
  (home_win_prob > 0.5) == (home_score > away_score)
}

# Is a final (or a called-off game) excluded from the record?
.ld_is_excluded <- function(status, prob, hs, as_) {
  if (status %in% c("postponed", "cancelled")) return(TRUE)
  if (!identical(status, "final")) return(FALSE)
  is.na(ld_hit(prob, hs, as_, status))
}

# ------------------------------------------------------------------------------
# Games table (from the matchups payload rows)
# ------------------------------------------------------------------------------

#' Normalise payload matchup rows to the digest's game table.
ld_games_table <- function(m) {
  if (is.null(m) || !is.data.frame(m) || nrow(m) == 0) {
    return(data.frame(game_id = character(0), gameday = character(0),
                      start_time_utc = character(0), home = character(0), away = character(0),
                      status = character(0), home_win_prob = numeric(0),
                      away_win_prob = numeric(0), prediction_status = character(0),
                      home_score = integer(0), away_score = integer(0),
                      stringsAsFactors = FALSE))
  }
  col <- function(n, default = NA) if (n %in% names(m)) m[[n]] else rep(default, nrow(m))
  completed <- !is.na(col("is_completed")) & col("is_completed") %in% TRUE
  status <- col("status", NA_character_)
  status <- ifelse(!is.na(status) & tolower(status) %in% c("postponed", "cancelled"),
                   tolower(status), ifelse(completed, "final", "scheduled"))
  p_home <- suppressWarnings(as.numeric(col("home_win_prob")))
  has_proj <- col("has_projection", TRUE)
  has_proj <- is.na(has_proj) | has_proj %in% TRUE
  p_home[!has_proj] <- NA_real_
  p_away <- suppressWarnings(as.numeric(col("away_win_prob")))
  p_away[is.na(p_home)] <- NA_real_
  p_away[!is.na(p_home) & is.na(p_away)] <- round(1 - p_home[!is.na(p_home) & is.na(p_away)], 3)
  data.frame(
    game_id = as.character(col("game_id")),
    gameday = as.character(col("gameday")),
    start_time_utc = ld_start_time_utc(as.character(col("gameday")), as.character(col("gametime"))),
    home = as.character(col("home_team")),
    away = as.character(col("away_team")),
    status = status,
    home_win_prob = p_home,
    away_win_prob = p_away,
    # NFL's game model exists, so a missing probability means it has not run
    # for that game yet - never "no_model".
    prediction_status = ifelse(is.na(p_home), "not_yet_run", "available"),
    home_score = suppressWarnings(as.integer(col("home_score"))),
    away_score = suppressWarnings(as.integer(col("away_score"))),
    stringsAsFactors = FALSE
  )
}

.ld_num <- function(x) if (is.na(x)) NULL else x

ld_today_rows <- function(g) {
  lapply(seq_len(nrow(g)), function(i) list(
    game_id = g$game_id[i], start_time_utc = g$start_time_utc[i],
    home = g$home[i], away = g$away[i], status = g$status[i],
    home_win_prob = .ld_num(g$home_win_prob[i]), away_win_prob = .ld_num(g$away_win_prob[i]),
    prediction_status = g$prediction_status[i]))
}

ld_yesterday_rows <- function(g) {
  lapply(seq_len(nrow(g)), function(i) {
    r <- ld_today_rows(g[i, , drop = FALSE])[[1]]
    final <- identical(g$status[i], "final")
    hs <- g$home_score[i]; as_ <- g$away_score[i]
    p <- g$home_win_prob[i]
    r$home_score <- if (final) .ld_num(hs) else NULL
    r$away_score <- if (final) .ld_num(as_) else NULL
    r$final <- final
    r$predicted_winner <- if (is.na(p) || isTRUE(all.equal(p, 0.5))) NULL else if (p > 0.5) g$home[i] else g$away[i]
    h <- ld_hit(p, hs, as_, g$status[i])
    r$hit <- if (is.na(h)) NULL else h
    r
  })
}

.ld_rows_on <- function(g, date) {
  x <- g[!is.na(g$gameday) & g$gameday == format(date), , drop = FALSE]
  x[order(x$start_time_utc, x$game_id), , drop = FALSE]
}

# ------------------------------------------------------------------------------
# Record and calibration (issue #184)
# ------------------------------------------------------------------------------

.ld_tally <- function(g) {
  hits <- 0L; games <- 0L; excluded <- 0L
  for (i in seq_len(nrow(g))) {
    if (is.na(g$home_win_prob[i]) && !(g$status[i] %in% c("postponed", "cancelled"))) next
    if (.ld_is_excluded(g$status[i], g$home_win_prob[i], g$home_score[i], g$away_score[i])) {
      excluded <- excluded + 1L
      next
    }
    if (!identical(g$status[i], "final")) next
    h <- ld_hit(g$home_win_prob[i], g$home_score[i], g$away_score[i], g$status[i])
    games <- games + 1L
    hits <- hits + as.integer(isTRUE(h))
  }
  list(hits = hits, games = games, excluded = excluded)
}

#' Season and last-7-days record, through the day before slate_date.
ld_record <- function(g, slate_date) {
  d <- suppressWarnings(as.Date(g$gameday))
  past <- !is.na(d) & d < slate_date
  last7 <- past & d >= slate_date - 7
  list(season = .ld_tally(g[past, , drop = FALSE]),
       last_7 = .ld_tally(g[last7, , drop = FALSE]))
}

#' Season calibration in buckets of the PICKED side's probability, 50-100% by 10.
ld_calibration <- function(g, slate_date = NULL) {
  if (!is.null(slate_date)) {
    d <- suppressWarnings(as.Date(g$gameday))
    g <- g[!is.na(d) & d < slate_date, , drop = FALSE]
  }
  pick_p <- numeric(0); hit <- logical(0)
  for (i in seq_len(nrow(g))) {
    h <- ld_hit(g$home_win_prob[i], g$home_score[i], g$away_score[i], g$status[i])
    if (is.na(h)) next
    p <- g$home_win_prob[i]
    pick_p <- c(pick_p, max(p, 1 - p))
    hit <- c(hit, h)
  }
  los <- round(seq(0.5, 0.9, by = 0.1), 1)  # 10-point bins from 50% to 100%
  lapply(los, function(lo) {
    hi <- round(lo + 0.1, 1)
    inb <- pick_p > lo - 1e-12 & (pick_p < hi - 1e-12 | (hi == 1 & pick_p <= 1))
    n <- sum(inb)
    list(lo = lo, hi = hi,
         predicted_mean = if (n) round(mean(pick_p[inb]), 3) else NULL,
         actual_rate = if (n) round(mean(hit[inb]), 3) else NULL,
         games = n)
  })
}

# ------------------------------------------------------------------------------
# Season state and next milestone (from real schedule rows only)
# ------------------------------------------------------------------------------

#' @param sched data.frame with season, gameday, game_type (REG/WC/DIV/CON/SB).
ld_season_state <- function(sched, slate_date, season) {
  none <- list(season_state = NULL, next_milestone = NULL)
  if (is.null(sched) || !nrow(sched) || !all(c("season", "gameday") %in% names(sched))) return(none)
  if (!"game_type" %in% names(sched)) sched$game_type <- "REG"
  s <- sched[sched$season == season, , drop = FALSE]
  d <- as.Date(s$gameday)
  reg <- d[s$game_type == "REG"]
  post <- s[s$game_type != "REG", , drop = FALSE]
  post_d <- as.Date(post$gameday)
  nxt <- sched[sched$season == season + 1 & sched$game_type %in% "REG", , drop = FALSE]
  kickoff_next <- if (nrow(nxt)) list(label = sprintf("%d season kicks off", season + 1),
                                      date = format(min(as.Date(nxt$gameday)))) else NULL
  if (!length(reg)) return(none)
  first <- min(reg); last <- max(reg)
  if (slate_date < first) {
    return(list(season_state = "preseason",
                next_milestone = list(label = sprintf("%d season kicks off", season), date = format(first))))
  }
  if (slate_date <= last) {
    ms <- if (nrow(post)) list(label = "Playoffs begin", date = format(min(post_d)))
          else list(label = "Final regular-season games", date = format(last))
    return(list(season_state = "regular", next_milestone = ms))
  }
  if (nrow(post) && slate_date <= max(post_d)) {
    up <- post[post_d >= slate_date, , drop = FALSE]
    up_d <- as.Date(up$gameday)
    k <- which.min(up_d)
    lbl <- switch(up$game_type[k], WC = "Wild Card round", DIV = "Divisional round",
                  CON = "Conference championships", SB = "Super Bowl", "Playoff games")
    return(list(season_state = "postseason", next_milestone = list(label = lbl, date = format(up_d[k]))))
  }
  if (!nrow(post) && slate_date <= last + LANDING_POSTSEASON_SPAN_DAYS) {
    # Playoff schedule not published yet: the state is known, the date is not.
    return(list(season_state = "postseason", next_milestone = NULL))
  }
  list(season_state = "offseason", next_milestone = kickoff_next)
}

# ------------------------------------------------------------------------------
# Ratings history and movers (issue #185)
# ------------------------------------------------------------------------------

ld_read_history <- function(path = LANDING_RATINGS_HISTORY) {
  empty <- data.frame(date = character(0), team = character(0), metric = character(0),
                      value = numeric(0), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  h <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = c("character", "character", "character", "numeric"))
  if (!nrow(h)) empty else h
}

#' Upsert today's ratings (one row per team per day) and prune to ~400 days.
ld_update_history <- function(history, ratings, date, metric = LANDING_RATING_METRIC,
                              keep_days = LANDING_HISTORY_KEEP_DAYS) {
  d <- format(as.Date(date))
  if (!is.null(ratings) && nrow(ratings)) {
    new <- data.frame(date = d, team = as.character(ratings$team), metric = metric,
                      value = round(as.numeric(ratings[[metric]]), 3), stringsAsFactors = FALSE)
    new <- new[!is.na(new$value), , drop = FALSE]
    history <- history[!(history$date == d & history$metric == metric), , drop = FALSE]
    history <- rbind(history, new)
  }
  history <- history[as.Date(history$date) >= as.Date(date) - keep_days, , drop = FALSE]
  history[order(history$date, history$metric, history$team), , drop = FALSE]
}

ld_write_history <- function(history, path = LANDING_RATINGS_HISTORY) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(history, path, row.names = FALSE, quote = FALSE)
  invisible(path)
}

#' Movers for 1/7/21-day windows. Falls back to the nearest EARLIER history
#' date when the exact comparison date has no rows; empty when none exists.
ld_movers <- function(history, slate_date, metric = LANDING_RATING_METRIC,
                      windows = LANDING_MOVER_WINDOWS, top_n = LANDING_MOVERS_TOP_N) {
  h <- history[history$metric == metric, , drop = FALSE]
  hd <- as.Date(h$date)
  out <- list()
  cur_date <- if (nrow(h) && any(hd <= slate_date)) max(hd[hd <= slate_date]) else as.Date(NA)
  for (w in windows) {
    key <- as.character(w)
    if (is.na(cur_date)) { out[[key]] <- list(compared_to = NULL, items = list()); next }
    target <- cur_date - w
    cands <- hd[hd <= target]
    if (!length(cands)) { out[[key]] <- list(compared_to = NULL, items = list()); next }
    cmp <- max(cands)
    cur <- h[hd == cur_date, c("team", "value")]
    prv <- h[hd == cmp, c("team", "value")]
    j <- merge(prv, cur, by = "team", suffixes = c("_prev", "_cur"))
    j$delta <- j$value_cur - j$value_prev
    j <- j[order(-abs(j$delta), j$team), , drop = FALSE]
    j <- head(j, top_n)
    out[[key]] <- list(compared_to = format(cmp),
                       items = lapply(seq_len(nrow(j)), function(i) list(
                         team = j$team[i], previous = round(j$value_prev[i], 2),
                         current = round(j$value_cur[i], 2), delta = round(j$delta[i], 2))))
  }
  list(metric = metric, windows = out)
}

# ------------------------------------------------------------------------------
# Assemble / patch / write
# ------------------------------------------------------------------------------

#' Build the digest list (no writes).
build_landing_digest <- function(matchups, schedule = NULL, history = NULL,
                                 now = Sys.time(), season = NULL) {
  slate <- ld_slate_date(now)
  g <- ld_games_table(matchups)
  if (is.null(season)) season <- if (nrow(matchups %||% data.frame()) && "season" %in% names(matchups))
    max(matchups$season, na.rm = TRUE) else as.integer(format(slate, "%Y"))
  if (is.null(schedule) && nrow(g)) {
    schedule <- data.frame(season = season, gameday = g$gameday, game_type = "REG", stringsAsFactors = FALSE)
  }
  st <- ld_season_state(schedule, slate, season)
  list(
    schema_version = LANDING_DIGEST_SCHEMA_VERSION,
    sport = "nfl",
    generated_at = ld_iso(now),
    slate_date = format(slate),
    season_state = st$season_state,
    next_milestone = st$next_milestone,
    today = ld_today_rows(.ld_rows_on(g, slate)),
    yesterday = ld_yesterday_rows(.ld_rows_on(g, slate - 1)),
    record = ld_record(g, slate),
    calibration = ld_calibration(g, slate),
    movers = ld_movers(history %||% ld_read_history(""), slate)
  )
}

#' Slot B/C patch: re-grade `yesterday`, `record` and `calibration` against the
#' (freshly patched) matchup rows, keeping the digest's own slate_date. today,
#' movers, season_state and next_milestone are slot A's and stay untouched.
#' generated_at moves only when the content actually changed.
patch_landing_digest <- function(digest, matchups, now = Sys.time()) {
  slate <- as.Date(digest$slate_date)
  g <- ld_games_table(matchups)
  new <- digest
  new$yesterday <- ld_yesterday_rows(.ld_rows_on(g, slate - 1))
  new$record <- ld_record(g, slate)
  new$calibration <- ld_calibration(g, slate)
  same <- identical(ld_json_text(new), ld_json_text(digest))
  if (!same) new$generated_at <- ld_iso(now)
  list(digest = new, changed = !same)
}

ld_json_text <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null",
                                na = "null", digits = NA))
}

# `[]` must stay an array: lists of zero rows serialise as [] with auto_unbox.
ld_write_digest <- function(digest, path) {
  writeLines(ld_json_text(digest), path, useBytes = TRUE)
  invisible(path)
}

#' Slot A entry point (run_full_pipeline.R stage, after the exporter).
run_build_landing_digest <- function(data_dir = if (exists("WEB_DATA_DIR")) WEB_DATA_DIR else file.path("web", "public", "data"),
                                     history_path = LANDING_RATINGS_HISTORY,
                                     ratings_path = if (exists("CACHE_TEAM_RATINGS")) CACHE_TEAM_RATINGS else file.path("cache", "team_ratings.rds"),
                                     schedules_path = if (exists("CACHE_SCHEDULES")) CACHE_SCHEDULES else file.path("cache", "schedules_cache.rds"),
                                     now = Sys.time()) {
  mp <- file.path(data_dir, "matchups_current_week.json")
  if (!file.exists(mp)) stop(sprintf("build_landing_digest: %s is absent - run the exporter first.", mp))
  payload <- jsonlite::fromJSON(mp, simplifyVector = TRUE)
  season <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else NULL
  schedule <- NULL
  if (file.exists(schedules_path)) {
    s <- tryCatch(readRDS(schedules_path), error = function(e) NULL)
    if (!is.null(s) && all(c("season", "gameday", "game_type") %in% names(s)))
      schedule <- data.frame(season = s$season, gameday = as.character(s$gameday),
                             game_type = s$game_type, stringsAsFactors = FALSE)
  }
  history <- ld_read_history(history_path)
  if (file.exists(ratings_path)) {
    r <- readRDS(ratings_path)
    history <- ld_update_history(history, r, ld_slate_date(now))
    ld_write_history(history, history_path)
  }
  digest <- build_landing_digest(payload$matchups, schedule, history, now, season)
  out <- file.path(data_dir, LANDING_DIGEST_FILENAME)
  ld_write_digest(digest, out)
  invisible(out)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("build_landing_digest[.]R$", files))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(files[grepl("build_landing_digest[.]R$", files)][1])),
                        winslash = "/", mustWork = FALSE)
  setwd(root)
  suppressPackageStartupMessages(library(jsonlite))
  if (file.exists("config.R")) source("config.R")
  out <- run_build_landing_digest()
  d <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  cat(sprintf("wrote %s: slate %s, %s, %d today, %d yesterday, season %d-%d (%d excluded)\n",
              out, d$slate_date, d$season_state %||% "null", length(d$today), length(d$yesterday),
              d$record$season$hits, d$record$season$games - d$record$season$hits,
              d$record$season$excluded))
})
