# ==============================================================================
# WNBA Analytics - Landing digest writer
# Path: <repo root>/tools/build_landing_digest.R
#
# Refs kailot-harris/WNBA_analytics#224 (slot A writer), #225 (slot B/C patch),
# #226 (record + calibration), #227 (ratings history + movers). Contract:
# kailot-harris/front-office#200, spec section 1.
#
# Writes web/public/data/landing_digest.json for the front-office landing page:
#   schema_version, sport, generated_at, slate_date (US Eastern), season_state,
#   next_milestone, today[], yesterday[], record, calibration, movers.
#
# Sources (all real pipeline output, nothing synthesized):
#   * web/public/data/matchups_slates.json - the per-game spine (schedule, final
#     scores) joined to the prediction accuracy log by build_matchups_dataset.R.
#     Only rows carrying a LOGGED model prediction (has_logged_prediction, basis
#     logged_model / logged_model_prob_only) count as predictions here. The
#     team_rating_differential fallback is never graded (WNBA contract), so those
#     games are listed with null probabilities and prediction_status
#     "not_yet_run".
#   * cache/projected_wnba_standings.rds - Net_Rating, the main team rating
#     (roster_bottom_up_engine.R), appended daily to data/history/ratings_history.csv.
#   * web/public/data/offseason_monitor.json - dated milestone calendar used for
#     next_milestone in the off-season.
#
# Shared hit rule: the side the model gave MORE than 50% won. Exact 50% picks,
# ties, and postponed / cancelled / not-played games get hit = null and count as
# `excluded`. No odds, spreads or lines are read or written.
#
# Usage:
#   Rscript tools/build_landing_digest.R      # slot A (run_full_pipeline.R stage)
#   source("tools/build_landing_digest.R")    # functions only
# WNBA_SKIP_DIGEST_AUTORUN=1 suppresses the write even under Rscript.
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))

LD_SCHEMA_VERSION   <- 1L
LD_SPORT            <- "wnba"
LD_TZ               <- "America/New_York"
LD_METRIC           <- "net_rating"
LD_HISTORY_KEEP     <- 400L
LD_MOVER_WINDOWS    <- c(1L, 7L, 21L)
LD_MOVERS_TOP_N     <- 5L
LD_LOGGED_BASES     <- c("logged_model", "logged_model_prob_only")
LD_DIGEST_PATH      <- file.path("web", "public", "data", "landing_digest.json")
LD_MATCHUPS_PATH    <- file.path("web", "public", "data", "matchups_slates.json")
LD_MONITOR_PATH     <- file.path("web", "public", "data", "offseason_monitor.json")
LD_STANDINGS_PATH   <- file.path("cache", "projected_wnba_standings.rds")
LD_HISTORY_PATH     <- file.path("data", "history", "ratings_history.csv")

.ld_utc_now <- function(now = Sys.time()) format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' US Eastern calendar date for `now`.
ld_slate_date <- function(now = Sys.time()) as.Date(format(now, "%Y-%m-%d", tz = LD_TZ))

.ld_chr <- function(x) if (is.null(x) || length(x) == 0 || is.na(x[[1]])) NA_character_ else as.character(x[[1]])
.ld_num <- function(x) if (is.null(x) || length(x) == 0 || is.na(x[[1]])) NA_real_ else suppressWarnings(as.numeric(x[[1]]))
.ld_na_null <- function(x) if (length(x) == 0 || is.na(x[[1]])) NULL else x

# ------------------------------------------------------------------------------
# Matchup rows -> normalized game frame
# ------------------------------------------------------------------------------

#' Normalize matchup rows (data.frame from matchups_slates.json) to the columns
#' the digest needs. home_win_prob is kept ONLY for logged model predictions.
ld_normalize_games <- function(rows) {
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  n <- nrow(rows)
  col <- function(nm, default = NA) if (nm %in% names(rows)) rows[[nm]] else rep(default, n)
  basis <- as.character(col("projection_basis"))
  logged <- (!is.na(col("has_logged_prediction")) & as.logical(col("has_logged_prediction"))) |
    basis %in% LD_LOGGED_BASES
  logged[basis %in% "team_rating_differential"] <- FALSE
  p <- suppressWarnings(as.numeric(col("home_win_prob")))
  p[!logged] <- NA_real_
  data.frame(
    game_id     = as.character(col("game_id")),
    game_date   = as.Date(substr(as.character(col("game_date")), 1, 10)),
    season_type = as.character(col("season_type")),
    home        = as.character(col("home_team")),
    away        = as.character(col("away_team")),
    start_time_utc = as.character(col("start_time_utc", NA_character_)),
    is_completed = !is.na(col("is_completed")) & as.logical(col("is_completed")),
    status_raw  = as.character(col("status", NA_character_)),
    home_score  = suppressWarnings(as.integer(col("home_score"))),
    away_score  = suppressWarnings(as.integer(col("away_score"))),
    home_win_prob = p,
    stringsAsFactors = FALSE
  )
}

#' Game status: final, scheduled, or postponed / cancelled / not_played (a past
#' game that never went final, e.g. an unneeded if-necessary playoff game).
ld_game_status <- function(g, slate_date) {
  raw <- tolower(ifelse(is.na(g$status_raw), "", g$status_raw))
  out <- ifelse(g$is_completed, "final",
         ifelse(grepl("postpon", raw), "postponed",
         ifelse(grepl("cancel", raw), "cancelled",
         ifelse(!is.na(g$game_date) & g$game_date < slate_date, "not_played", "scheduled"))))
  out
}

# ------------------------------------------------------------------------------
# Shared hit rule
# ------------------------------------------------------------------------------

#' Grade one prediction with the shared rule.
#' @return list(predicted_winner, hit, outcome) with outcome one of
#'   "hit", "miss", "excluded", "pending", "no_prediction".
ld_grade <- function(home_win_prob, home, away, home_score, away_score, status) {
  p <- .ld_num(home_win_prob)
  if (is.na(p)) return(list(predicted_winner = NA_character_, hit = NA, outcome = "no_prediction"))
  pw <- if (p > 0.5) home else if (p < 0.5) away else NA_character_
  if (status %in% c("postponed", "cancelled", "not_played")) {
    return(list(predicted_winner = pw, hit = NA, outcome = "excluded"))
  }
  if (!identical(status, "final")) return(list(predicted_winner = pw, hit = NA, outcome = "pending"))
  if (p == 0.5) return(list(predicted_winner = NA_character_, hit = NA, outcome = "excluded"))
  hs <- .ld_num(home_score); as_ <- .ld_num(away_score)
  if (is.na(hs) || is.na(as_) || hs == as_) return(list(predicted_winner = pw, hit = NA, outcome = "excluded"))
  hit <- (p > 0.5) == (hs > as_)
  list(predicted_winner = pw, hit = hit, outcome = if (hit) "hit" else "miss")
}

#' Vectorized grading over a normalized game frame (adds status, predicted_winner,
#' hit, outcome).
ld_grade_games <- function(g, slate_date) {
  g$status <- ld_game_status(g, slate_date)
  gr <- lapply(seq_len(nrow(g)), function(i)
    ld_grade(g$home_win_prob[i], g$home[i], g$away[i], g$home_score[i], g$away_score[i], g$status[i]))
  g$predicted_winner <- vapply(gr, function(x) as.character(x$predicted_winner), character(1))
  g$hit <- vapply(gr, function(x) as.logical(x$hit), logical(1))
  g$outcome <- vapply(gr, `[[`, character(1), "outcome")
  g
}

# ------------------------------------------------------------------------------
# today / yesterday
# ------------------------------------------------------------------------------

.ld_game_obj <- function(r, with_result) {
  has_p <- !is.na(r$home_win_prob)
  o <- list(
    game_id = r$game_id,
    game_date = format(r$game_date),
    start_time_utc = .ld_na_null(r$start_time_utc),
    home = r$home,
    away = r$away,
    status = r$status,
    home_win_prob = if (has_p) round(r$home_win_prob, 4) else NULL,
    away_win_prob = if (has_p) round(1 - r$home_win_prob, 4) else NULL,
    prediction_status = if (has_p) "available" else "not_yet_run"
  )
  if (with_result) {
    o$home_score <- .ld_na_null(r$home_score)
    o$away_score <- .ld_na_null(r$away_score)
    o$final <- identical(r$status, "final")
    o$predicted_winner <- .ld_na_null(r$predicted_winner)
    o$hit <- .ld_na_null(r$hit)
  }
  o
}

ld_day_games <- function(graded, date, with_result) {
  rows <- graded[!is.na(graded$game_date) & graded$game_date == date, , drop = FALSE]
  rows <- rows[order(rows$game_id), , drop = FALSE]
  lapply(seq_len(nrow(rows)), function(i) .ld_game_obj(rows[i, , drop = FALSE], with_result))
}

# ------------------------------------------------------------------------------
# record + calibration (#226)
# ------------------------------------------------------------------------------

.ld_tally <- function(outcome) list(
  hits = as.integer(sum(outcome == "hit")),
  games = as.integer(sum(outcome %in% c("hit", "miss"))),
  excluded = as.integer(sum(outcome == "excluded"))
)

#' Season record and last-7-days record (the 7 US Eastern days before slate_date).
ld_record <- function(graded, slate_date) {
  past <- graded[!is.na(graded$game_date) & graded$game_date < slate_date, , drop = FALSE]
  last7 <- past[past$game_date >= slate_date - 7L, , drop = FALSE]
  list(season = .ld_tally(past$outcome), last_7 = .ld_tally(last7$outcome))
}

#' Season calibration buckets 50-100% by 10, on the favored side's probability.
ld_calibration <- function(graded) {
  g <- graded[graded$outcome %in% c("hit", "miss"), , drop = FALSE]
  conf <- pmax(g$home_win_prob, 1 - g$home_win_prob)
  los <- c(0.5, 0.6, 0.7, 0.8, 0.9)
  lapply(los, function(lo) {
    hi <- lo + 0.1
    sel <- conf >= lo - 1e-9 & (if (lo >= 0.9) conf <= 1 else conf < hi - 1e-9)
    n <- sum(sel)
    list(lo = lo, hi = round(hi, 1),
         predicted_mean = if (n) round(mean(conf[sel]), 4) else NULL,
         actual_rate = if (n) round(mean(g$outcome[sel] == "hit"), 4) else NULL,
         games = as.integer(n))
  })
}

# ------------------------------------------------------------------------------
# season_state + next_milestone
# ------------------------------------------------------------------------------

ld_season_state <- function(g, slate_date) {
  d <- g$game_date[!is.na(g$game_date)]
  if (!length(d)) return(NA_character_)
  reg <- g$game_date[!is.na(g$game_date) & g$season_type %in% c("regular", "2")]
  post <- g$game_date[!is.na(g$game_date) & !(g$season_type %in% c("regular", "2"))]
  if (slate_date > max(d)) return("offseason")
  if (slate_date < min(d)) return("preseason")
  if (length(post) && slate_date >= min(post)) return("postseason")
  if (length(reg) && slate_date > max(reg)) return("postseason")
  "regular"
}

#' Next dated milestone. Off-season: first dated, not-yet-passed entry in the
#' latest off-season monitor edition. Preseason: the first scheduled game.
#' Otherwise null (no guessing).
ld_next_milestone <- function(state, g, slate_date, monitor = NULL) {
  if (identical(state, "preseason")) {
    d <- min(g$game_date, na.rm = TRUE)
    return(list(label = "Regular season opens", date = format(d)))
  }
  if (identical(state, "regular")) {
    post <- g$game_date[!is.na(g$game_date) & !(g$season_type %in% c("regular", "2"))]
    post <- post[post > slate_date]
    if (length(post)) return(list(label = "Playoffs begin", date = format(min(post))))
    return(NULL)
  }
  if (!identical(state, "offseason") || is.null(monitor) || !length(monitor$editions)) return(NULL)
  ed <- monitor$editions[[length(monitor$editions)]]
  ms <- ed$upcomingMilestones
  if (!length(ms)) return(NULL)
  cand <- lapply(ms, function(m) {
    d <- suppressWarnings(as.Date(.ld_chr(m$date)))
    if (is.na(d) || d < slate_date) NULL else list(label = .ld_chr(m$event), date = format(d))
  })
  cand <- Filter(Negate(is.null), cand)
  if (!length(cand)) return(NULL)
  cand[[order(vapply(cand, `[[`, "", "date"))[1]]]
}

# ------------------------------------------------------------------------------
# Ratings history + movers (#227)
# ------------------------------------------------------------------------------

ld_read_history <- function(path = LD_HISTORY_PATH) {
  empty <- data.frame(date = as.Date(character(0)), team = character(0), metric = character(0),
                      value = numeric(0), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  h <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character"),
                error = function(e) NULL)
  if (is.null(h) || !nrow(h)) return(empty)
  data.frame(date = as.Date(h$date), team = h$team, metric = h$metric,
             value = suppressWarnings(as.numeric(h$value)), stringsAsFactors = FALSE)
}

#' Replace today's rows with `ratings` (data.frame team, value), prune to
#' `keep_days`, and write the CSV. Returns the updated history.
ld_update_history <- function(ratings, date, path = LD_HISTORY_PATH, metric = LD_METRIC,
                              keep_days = LD_HISTORY_KEEP) {
  h <- ld_read_history(path)
  h <- h[!(h$date == date & h$metric == metric), , drop = FALSE]
  if (!is.null(ratings) && nrow(ratings)) {
    h <- rbind(h, data.frame(date = date, team = as.character(ratings$team), metric = metric,
                             value = round(as.numeric(ratings$value), 2), stringsAsFactors = FALSE))
  }
  h <- h[h$date > date - keep_days, , drop = FALSE]
  h <- h[order(h$date, h$metric, h$team), , drop = FALSE]
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  out <- h; out$date <- format(out$date)
  utils::write.csv(out, path, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  invisible(h)
}

#' Movers for each window: current = latest history date <= as_of; previous =
#' the nearest history date on or before (current - window). Empty when there is
#' no such earlier date.
ld_movers <- function(history, as_of, metric = LD_METRIC, windows = LD_MOVER_WINDOWS,
                      top_n = LD_MOVERS_TOP_N) {
  h <- history[history$metric == metric & history$date <= as_of & !is.na(history$value), , drop = FALSE]
  empty_win <- list(compared_to = NULL, items = I(list()))
  out <- list(metric = metric, windows = list())
  dates <- sort(unique(h$date))
  for (w in windows) {
    key <- as.character(w)
    if (!length(dates)) { out$windows[[key]] <- empty_win; next }
    cur_d <- max(dates)
    prev_cands <- dates[dates <= cur_d - w]
    if (!length(prev_cands)) { out$windows[[key]] <- empty_win; next }
    prev_d <- max(prev_cands)
    cur <- h[h$date == cur_d, c("team", "value")]
    prev <- h[h$date == prev_d, c("team", "value")]
    j <- merge(prev, cur, by = "team", suffixes = c("_prev", "_cur"))
    j$delta <- j$value_cur - j$value_prev
    j <- j[order(-abs(j$delta), j$team), , drop = FALSE]
    j <- utils::head(j, top_n)
    items <- lapply(seq_len(nrow(j)), function(i) list(
      team = j$team[i], previous = round(j$value_prev[i], 2), current = round(j$value_cur[i], 2),
      delta = round(j$delta[i], 2)))
    out$windows[[key]] <- list(compared_to = format(prev_d), items = I(items))
  }
  out
}

#' Current Net_Rating per team from the projected standings, keyed by the ESPN
#' abbreviation via the matchups payload's team-name crosswalk (falls back to the
#' full name when a team is absent from the crosswalk).
ld_current_ratings <- function(standings_path = LD_STANDINGS_PATH, matchup_rows = NULL) {
  if (!file.exists(standings_path)) return(NULL)
  s <- tryCatch(as.data.frame(readRDS(standings_path)), error = function(e) NULL)
  if (is.null(s) || !all(c("Team", "Net_Rating") %in% names(s))) return(NULL)
  team <- as.character(s$Team)
  if (!is.null(matchup_rows) && all(c("home_team", "home_team_name") %in% names(matchup_rows))) {
    xw <- unique(rbind(
      data.frame(abbr = matchup_rows$home_team, name = matchup_rows$home_team_name, stringsAsFactors = FALSE),
      data.frame(abbr = matchup_rows$away_team, name = matchup_rows$away_team_name, stringsAsFactors = FALSE)))
    ab <- xw$abbr[match(team, xw$name)]
    team <- ifelse(is.na(ab), team, ab)
  }
  r <- data.frame(team = team, value = suppressWarnings(as.numeric(s$Net_Rating)), stringsAsFactors = FALSE)
  r[!is.na(r$value), , drop = FALSE]
}

# ------------------------------------------------------------------------------
# Assemble
# ------------------------------------------------------------------------------

.ld_read_json <- function(path, ...) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, ...), error = function(e) NULL)
}

#' Results-dependent blocks (yesterday, record, calibration) - shared by the
#' slot A writer and the slot B/C patch so both apply the identical rule.
ld_results_blocks <- function(matchup_rows, slate_date) {
  g <- ld_grade_games(ld_normalize_games(matchup_rows), slate_date)
  list(graded = g,
       yesterday = ld_day_games(g, slate_date - 1L, with_result = TRUE),
       record = ld_record(g, slate_date),
       calibration = ld_calibration(g))
}

build_landing_digest <- function(now = Sys.time(),
                                 matchups_path = LD_MATCHUPS_PATH,
                                 monitor_path = LD_MONITOR_PATH,
                                 standings_path = LD_STANDINGS_PATH,
                                 history_path = LD_HISTORY_PATH,
                                 update_history = TRUE) {
  slate <- ld_slate_date(now)
  mp <- .ld_read_json(matchups_path, simplifyVector = TRUE)
  rows <- if (!is.null(mp) && length(mp$matchups)) as.data.frame(mp$matchups, stringsAsFactors = FALSE) else
    data.frame(game_id = character(0))
  rb <- ld_results_blocks(rows, slate)
  g <- rb$graded
  state <- ld_season_state(g, slate)
  monitor <- .ld_read_json(monitor_path, simplifyVector = FALSE)

  if (isTRUE(update_history)) {
    ratings <- ld_current_ratings(standings_path, rows)
    hist <- if (!is.null(ratings)) ld_update_history(ratings, slate, history_path) else ld_read_history(history_path)
  } else {
    hist <- ld_read_history(history_path)
  }

  list(
    schema_version = LD_SCHEMA_VERSION,
    sport = LD_SPORT,
    generated_at = .ld_utc_now(now),
    slate_date = format(slate),
    season_state = if (is.na(state)) NULL else state,
    next_milestone = ld_next_milestone(state, g, slate, monitor),
    today = I(ld_day_games(g, slate, with_result = FALSE)),
    yesterday = I(rb$yesterday),
    record = rb$record,
    calibration = I(rb$calibration),
    movers = ld_movers(hist, slate)
  )
}

ld_json_text <- function(d) {
  as.character(jsonlite::toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null",
                                digits = NA))
}

#' Write when the content (ignoring generated_at) changed. Returns TRUE if written.
ld_write_digest <- function(d, path = LD_DIGEST_PATH) {
  if (file.exists(path)) {
    old <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(old)) {
      a <- old; a$generated_at <- NULL
      b <- jsonlite::fromJSON(ld_json_text(d), simplifyVector = FALSE); b$generated_at <- NULL
      if (identical(a, b)) return(FALSE)
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(ld_json_text(d), path, useBytes = TRUE)
  TRUE
}

#' Slot B/C patch (#225): recompute yesterday, record and calibration from the
#' (freshly patched) matchup rows, keeping the digest's own slate_date. Leaves
#' today, season_state, next_milestone and movers untouched.
ld_patch_digest <- function(matchup_rows, digest_path = LD_DIGEST_PATH, now = Sys.time()) {
  if (!file.exists(digest_path)) return(FALSE)
  d <- jsonlite::fromJSON(digest_path, simplifyVector = FALSE)
  slate <- suppressWarnings(as.Date(.ld_chr(d$slate_date)))
  if (is.na(slate)) return(FALSE)
  rb <- ld_results_blocks(matchup_rows, slate)
  d$yesterday <- I(rb$yesterday)
  d$record <- rb$record
  d$calibration <- I(rb$calibration)
  d$today <- I(d$today)
  for (k in names(d$movers$windows)) d$movers$windows[[k]]$items <- I(d$movers$windows[[k]]$items)
  d$generated_at <- .ld_utc_now(now)
  ld_write_digest(d, digest_path)
}

#' Slot A entry point (pipeline stage `landing_digest`, call_fn).
run_landing_digest <- function() {
  d <- build_landing_digest()
  w <- ld_write_digest(d)
  cat(sprintf("landing_digest: slate %s, season_state %s, today %d, yesterday %d, season record %d/%d (%d excluded)%s\n",
              d$slate_date, if (is.null(d$season_state)) "null" else d$season_state,
              length(d$today), length(d$yesterday),
              d$record$season$hits, d$record$season$games, d$record$season$excluded,
              if (w) "" else " - unchanged"))
  invisible(d)
}

# ------------------------------------------------------------------------------
# CLI guard: only runs under `Rscript tools/build_landing_digest.R`.
# ------------------------------------------------------------------------------
local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (interactive() || !any(grepl("build_landing_digest\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("WNBA_SKIP_DIGEST_AUTORUN"))) return(invisible(NULL))
  root <- normalizePath(dirname(dirname(f[1])), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(root, "config.R"))) setwd(root)
  run_landing_digest()
})
