# Weekly prediction projector -- the schedule-fed replacement for the betting slate.
#
# WHAT IT REPLACES
# ----------------
# log_todays_predictions() (prediction_accuracy_logger.R:577) parses
# cache/latest_value_bets.rds, a betting artifact derived from The Odds API.
# That made the whole grading chain depend on a paid, key-gated, quota-limited
# feed: when the key hit its monthly cap the feed 401'd, market_odds_engine.R
# fell back to a synthetic slate with placeholder ids, the schedule spine
# contract rejected every row, nothing was logged, and because
# build_matchups_dataset.R:579 grades a game ONLY when the log has it RESOLVED,
# the public site silently froze at the last week that happened to be logged --
# with real final scores already sitting in box_scores_cache.rds.
#
# This script takes the slate from the ESPN schedule spine instead
# (cache/matchups_schedule_<season>.rds -- the SAME artifact
# build_matchups_dataset.R joins against and the one the spine contract already
# validates against), and prices it from the ensemble team ratings. No API key,
# no bookmaker, no quota. That is front-office#12 for NBA, and it removes the
# last betting input from the grading path (#10).
#
# log_todays_predictions() already accepts an injected `slate`, so nothing in
# the logger's upsert, spine-contract or reconciliation machinery changes.
#
# CADENCE
# -------
# Season weeks in this repo are Tuesday->Monday: slate =
# floor((date - season_start) / 7) + 1 with season_start = 2026-10-20, which is
# a Tuesday. So week 1 is Oct 20-26, week 2 is Oct 27-Nov 2, and the natural
# cadence is to project a week on its opening Tuesday, once the previous week
# has finished and graded. Run with no arguments on a Tuesday and that is
# exactly what happens; the previous week's resolution is CHECKED and reported
# before anything is written.
#
# Predictions are written PENDING. They are graded later by
# reconcile_predictions() against official box scores, so this script never
# scores its own forecasts.
#
# Usage:
#   Rscript tools/project_week_predictions.R                 # dry run, current week
#   Rscript tools/project_week_predictions.R --write         # insert them
#   Rscript tools/project_week_predictions.R --slate 3       # a specific week
#   Rscript tools/project_week_predictions.R --slate 3 --write

suppressPackageStartupMessages({
  library(dplyr)
})

.pw_root <- function() {
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand) && file.exists(cand)) {
      cand_root <- normalizePath(dirname(dirname(cand)), winslash = "/", mustWork = FALSE)
      if (file.exists(file.path(cand_root, "config.R"))) return(cand_root)
    }
  }
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1 && nzchar(f) && file.exists(f)) {
    cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(cand, "config.R"))) return(cand)
  }
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "config.R"))) return(d)
    p <- dirname(d); if (identical(p, d)) break; d <- p
  }
  stop("project_week_predictions.R: cannot locate the project root.")
}
local({
  root <- .pw_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})
source("config.R")

PWP_HCA     <- 2.40
PWP_SIGMA   <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8
PWP_WEIGHTS <- c(bottom_up = 0.35, rapm = 0.25, shot_fatigue = 0.20, embeddings = 0.20)
PWP_ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                          NO = "NOP", WSH = "WAS")
PWP_SNAPSHOT_COLS <- c(
  "comp_bottom_up", "comp_rapm", "comp_shot_fatigue", "comp_embeddings",
  "comp_home_court", "comp_schedule", "sigma_game"
)

FATIGUE_ENGINE_LIBRARY_ONLY <- TRUE
source(file.path(.pw_root(), "fatigue_travel_engine.R"), local = TRUE)

.pwp_arg <- function(flag) {
  a <- commandArgs(trailingOnly = TRUE)
  i <- which(a == flag)
  if (!length(i) || i[1] == length(a)) return(NULL)
  a[i[1] + 1L]
}

# ------------------------------------------------------------------------------
# Schedule spine, reduced to the fields a prediction needs. Same TBD filtering
# publish_web.R's slate assertion applies, so a placeholder pairing cannot be
# priced as if it were a real game.
# ------------------------------------------------------------------------------
.pwp_spine <- function(season = MATCHUPS_HOOPR_SEASON) {
  path <- CACHE_MATCHUPS_SCHEDULE(season)
  if (!file.exists(path)) {
    stop(sprintf(paste0("schedule spine absent: %s. Run the matchups stage (it pulls ",
                        "hoopR::load_nba_schedule) before projecting a week."), path))
  }
  s <- as.data.frame(readRDS(path))
  need <- c("game_id", "game_date", "home_short_display_name", "away_short_display_name")
  miss <- setdiff(need, names(s))
  if (length(miss)) stop(sprintf("schedule spine lacks %s", paste(miss, collapse = ", ")))
  s$game_date <- as.Date(s$game_date)
  tbd <- s$home_short_display_name == "TBD" | s$away_short_display_name == "TBD"
  tbd[is.na(tbd)] <- FALSE
  s <- s[!tbd & !is.na(s$game_date), , drop = FALSE]
  s[order(s$game_date, s$game_id), , drop = FALSE]
}

# Tuesday->Monday weeks, keyed off the spine's own first game date. Duplicated
# from build_matchups_dataset.R:541 and publish_web.R's slate assertion rather
# than imported, for the reason publish_web.R documents: a shared helper here
# would have to source a stage file that refits models on load.
.pwp_slate_of <- function(dates, season_start) {
  as.integer(floor(as.numeric(dates - season_start) / 7) + 1)
}

.pwp_ratings <- function() {
  path <- file.path(CACHE_DIR, "ensemble_team_ratings.rds")
  if (!file.exists(path)) {
    stop(sprintf(paste0("ensemble ratings absent: %s. Run season_simulator.R; this script ",
                        "deliberately does not fall back to a single-model rating."), path))
  }
  e <- as.data.frame(readRDS(path))
  need <- c(
    "team", "team_name", "ensemble_net_rating", "rating_disagreement_sd",
    "rating_bottom_up", "rating_rapm", "rating_shot_fatigue", "rating_embeddings"
  )
  miss <- setdiff(need, names(e))
  if (length(miss)) stop(sprintf("ensemble ratings lack %s", paste(miss, collapse = ", ")))
  num <- function(x) suppressWarnings(as.numeric(x))
  by_both <- function(col) {
    v <- num(e[[col]])
    c(setNames(v, as.character(e$team_name)),
      setNames(v, as.character(e$team)))
  }
  list(
    rating = by_both("ensemble_net_rating"),
    # A present-but-nonfinite SD contributes nothing and the game collapses to
    # the plain MARGIN_SIGMA, matching build_matchups_dataset.R's .sd_for().
    sd = by_both("rating_disagreement_sd"),
    bottom_up = by_both("rating_bottom_up"),
    rapm = by_both("rating_rapm"),
    shot_fatigue = by_both("rating_shot_fatigue"),
    embeddings = by_both("rating_embeddings"),
    abbr = c(setNames(as.character(e$team), as.character(e$team_name)),
             setNames(as.character(e$team), as.character(e$team))),
    n = nrow(e)
  )
}

.pwp_canonical_abbr <- function(names_vec, raw_abbr_vec = NULL, abbr_lookup = NULL) {
  vals <- as.character(names_vec)
  mapped <- rep(NA_character_, length(vals))
  if (!is.null(raw_abbr_vec)) {
    raw <- as.character(raw_abbr_vec)
    has_raw <- !is.na(raw) & nzchar(raw)
    raw_fixed <- ifelse(raw %in% names(PWP_ESPN_ABBR_FIXUPS),
                        unname(PWP_ESPN_ABBR_FIXUPS[raw]), raw)
    mapped[has_raw] <- raw_fixed[has_raw]
  }
  if (!is.null(abbr_lookup) && length(vals)) {
    miss <- is.na(mapped) | !nzchar(mapped)
    from_lookup <- unname(abbr_lookup[vals[miss]])
    mapped[miss] <- from_lookup
  }
  miss <- is.na(mapped) | !nzchar(mapped)
  if (any(miss)) {
    mapped[miss] <- ifelse(vals[miss] %in% names(PWP_ESPN_ABBR_FIXUPS),
                           unname(PWP_ESPN_ABBR_FIXUPS[vals[miss]]), vals[miss])
  }
  mapped
}

# Exact mirror of build_matchups_dataset.R's schedule context calculation:
# builds per-team appearances across the full season spine in date order and
# computes away_fatigue_drag - home_fatigue_drag via fatigue_travel_engine.R.
.pwp_compute_schedule_adjustments <- function(spine, abbr_lookup = NULL) {
  if (!nrow(spine)) {
    return(data.frame(
      game_id = character(0),
      home_fatigue_drag = numeric(0),
      away_fatigue_drag = numeric(0),
      schedule_adjustment = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  home_raw <- if ("home_abbreviation" %in% names(spine)) spine$home_abbreviation else NULL
  away_raw <- if ("away_abbreviation" %in% names(spine)) spine$away_abbreviation else NULL
  games <- data.frame(
    game_id = as.character(spine$game_id),
    game_date = as.Date(spine$game_date),
    home_team = .pwp_canonical_abbr(spine$home_short_display_name, home_raw, abbr_lookup),
    away_team = .pwp_canonical_abbr(spine$away_short_display_name, away_raw, abbr_lookup),
    stringsAsFactors = FALSE
  )
  games <- games[order(games$game_date, games$game_id), , drop = FALSE]

  appearances <- rbind(
    data.frame(team = games$home_team, game_date = games$game_date,
               venue = games$home_team, stringsAsFactors = FALSE),
    data.frame(team = games$away_team, game_date = games$game_date,
               venue = games$home_team, stringsAsFactors = FALSE)
  )
  appearances <- appearances[order(appearances$team, appearances$game_date), ]

  prev_venue <- character(nrow(appearances))
  prev_gap   <- rep(NA_real_, nrow(appearances))
  for (j in seq_len(nrow(appearances))) {
    if (j > 1 && identical(appearances$team[j], appearances$team[j - 1])) {
      prev_venue[j] <- appearances$venue[j - 1]
      prev_gap[j]   <- as.numeric(difftime(appearances$game_date[j],
                                           appearances$game_date[j - 1], units = "days"))
    } else {
      prev_venue[j] <- appearances$venue[j]
      prev_gap[j]   <- NA_real_
    }
  }
  ctx_key <- paste(appearances$team, format(appearances$game_date, "%Y-%m-%d"), sep = "|")
  ctx_prev_venue <- setNames(prev_venue, ctx_key)
  ctx_prev_gap   <- setNames(prev_gap, ctx_key)

  .side_drag <- function(team, game_date, dest) {
    k <- paste(team, format(game_date, "%Y-%m-%d"), sep = "|")
    gap <- unname(ctx_prev_gap[k])
    origin <- unname(ctx_prev_venue[k])
    if (is.null(gap) || length(gap) == 0 || is.na(gap)) return(0)
    days_rest <- max(0, as.integer(round(gap)) - 1L)
    fm <- calculate_travel_fatigue(dest, origin,
                                   days_rest = days_rest,
                                   is_back_to_back = days_rest == 0L)
    as.numeric(fm$fatigue_drag_pts)
  }

  games$home_fatigue_drag <- vapply(seq_len(nrow(games)), function(i) {
    .side_drag(games$home_team[i], games$game_date[i], games$home_team[i])
  }, numeric(1))
  games$away_fatigue_drag <- vapply(seq_len(nrow(games)), function(i) {
    .side_drag(games$away_team[i], games$game_date[i], games$home_team[i])
  }, numeric(1))
  games$schedule_adjustment <- round(games$away_fatigue_drag - games$home_fatigue_drag, 2)
  games[, c("game_id", "home_fatigue_drag", "away_fatigue_drag", "schedule_adjustment"), drop = FALSE]
}

.pwp_build_week_projections <- function(wk, full_spine, r, prediction_timestamp = Sys.time()) {
  hn <- as.character(wk$home_short_display_name)
  an <- as.character(wk$away_short_display_name)
  unrated <- setdiff(c(hn, an), names(r$rating)[!is.na(r$rating)])
  if (length(unrated)) stop(sprintf("no ensemble rating for: %s", paste(unrated, collapse = ", ")))

  sched_df <- .pwp_compute_schedule_adjustments(full_spine, abbr_lookup = r$abbr)
  sched_idx <- match(as.character(wk$game_id), sched_df$game_id)
  if (any(is.na(sched_idx))) {
    stop(sprintf("schedule adjustment missing for game_id(s): %s",
                 paste(wk$game_id[is.na(sched_idx)], collapse = ", ")))
  }
  comp_schedule <- as.numeric(sched_df$schedule_adjustment[sched_idx])

  fin <- function(v) { v <- unname(as.numeric(v)); ifelse(is.finite(v) & v > 0, v, 0) }
  comp_bottom_up    <- round(PWP_WEIGHTS[["bottom_up"]]    * unname(r$bottom_up[hn]    - r$bottom_up[an]),    4)
  comp_rapm         <- round(PWP_WEIGHTS[["rapm"]]         * unname(r$rapm[hn]         - r$rapm[an]),         4)
  comp_shot_fatigue <- round(PWP_WEIGHTS[["shot_fatigue"]] * unname(r$shot_fatigue[hn] - r$shot_fatigue[an]), 4)
  comp_embeddings   <- round(PWP_WEIGHTS[["embeddings"]]   * unname(r$embeddings[hn]   - r$embeddings[an]),   4)
  comp_home_court   <- rep(as.numeric(PWP_HCA), nrow(wk))

  margin <- unname(r$rating[hn] - r$rating[an]) + comp_home_court + comp_schedule
  sigma_game_val <- sqrt(PWP_SIGMA^2 + fin(r$sd[hn])^2 + fin(r$sd[an])^2)
  prob <- pnorm(margin / sigma_game_val)

  tibble(
    game_id                 = as.character(wk$game_id),
    game_date               = as.Date(wk$game_date),
    season                  = 2026L,   # the log labels BOTH seasons 2026; joins are by DATE
    home_team               = hn,
    away_team               = an,
    prediction_timestamp    = prediction_timestamp,
    predicted_home_win_prob = round(as.numeric(prob), 4),
    .pred_Win               = round(as.numeric(prob), 4),
    predicted_winner        = ifelse(prob >= 0.5, hn, an),
    predicted_margin        = round(as.numeric(margin), 2),
    target_home_win         = NA_character_,
    actual_winner           = NA_character_,
    correct                 = NA,
    brier_component         = NA_real_,
    log_loss_component      = NA_real_,
    status                  = "PENDING",
    resolved_timestamp      = as.POSIXct(NA),
    log_source              = "LOGGED_PREGAME",
    comp_bottom_up          = as.numeric(comp_bottom_up),
    comp_rapm               = as.numeric(comp_rapm),
    comp_shot_fatigue       = as.numeric(comp_shot_fatigue),
    comp_embeddings         = as.numeric(comp_embeddings),
    comp_home_court         = as.numeric(comp_home_court),
    comp_schedule           = as.numeric(comp_schedule),
    sigma_game              = round(as.numeric(sigma_game_val), 4)
  ) %>% arrange(.data$game_date, .data$game_id)
}

# The cadence precondition: every game in the previous week must be graded.
# Reported, never fatal -- a postponed game would otherwise block the new week
# indefinitely.
.pwp_check_previous <- function(log_df, spine, season_start, slate) {
  if (slate <= 1) return(invisible(NULL))
  prev <- spine[.pwp_slate_of(spine$game_date, season_start) == (slate - 1L), , drop = FALSE]
  if (!nrow(prev)) return(invisible(NULL))
  key_log <- paste(format(as.Date(log_df$game_date)), log_df$home_team, log_df$away_team)
  res <- log_df$status == "RESOLVED"
  pk <- paste(format(prev$game_date), prev$home_short_display_name, prev$away_short_display_name)
  done <- pk %in% key_log[res]
  cat(sprintf("  previous week (%d): %d of %d game(s) graded\n", slate - 1L, sum(done), length(done)))
  if (any(!done)) {
    cat(sprintf("  [WARN] week %d still has %d ungraded game(s); projecting week %d anyway:\n",
                slate - 1L, sum(!done), slate))
    for (k in head(pk[!done], 10)) cat(sprintf("         %s\n", k))
  }
  invisible(NULL)
}

main <- function(do_write = NULL, slate = NULL) {
  if (is.null(do_write)) {
    do_write <- "--write" %in% commandArgs(trailingOnly = TRUE)
  }
  spine <- .pwp_spine()
  season_start <- min(spine$game_date)
  spine$slate <- .pwp_slate_of(spine$game_date, season_start)

  slate_arg <- if (is.null(slate)) .pwp_arg("--slate") else slate
  today <- Sys.Date()
  slate <- if (!is.null(slate_arg)) {
    as.integer(slate_arg)
  } else {
    s <- .pwp_slate_of(today, season_start)
    max(1L, min(s, max(spine$slate)))
  }

  cat("================================================================\n")
  cat(sprintf("Weekly prediction projector  [%s]\n",
              if (do_write) "WRITE" else "DRY RUN - nothing is written"))
  cat("================================================================\n")
  cat(sprintf("  today            : %s (%s)\n", format(today), format(today, "%a")))
  cat(sprintf("  season start     : %s (%s) - weeks run %s->Mon\n",
              format(season_start), format(season_start, "%a"), format(season_start, "%a")))
  cat(sprintf("  target week      : %d\n", slate))
  cat(sprintf("  slate source     : %s (ESPN schedule spine, no API key)\n",
              basename(CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON))))

  wk <- spine[spine$slate == slate, , drop = FALSE]
  if (!nrow(wk)) stop(sprintf("no scheduled games in week %d", slate))
  cat(sprintf("  week %d window    : %s .. %s (%d games)\n\n",
              slate, format(min(wk$game_date)), format(max(wk$game_date)), nrow(wk)))

  log_df <- as.data.frame(readRDS(CACHE_PREDICTION_LOG))
  # log_source distinguishes a genuine pre-game forecast from a hindsight-
  # seeded backfill row (prediction_accuracy_logger.R's .classify_log_source
  # heuristic). A log written before this column existed needs it backfilled
  # here too, since this script reads CACHE_PREDICTION_LOG directly rather
  # than through get_prediction_log()'s migration seam.
  if (!"log_source" %in% names(log_df)) {
    pt <- as.Date(log_df$prediction_timestamp, tz = "")
    gd <- as.Date(log_df$game_date)
    log_df$log_source <- ifelse(!is.na(pt) & !is.na(gd) & pt < gd,
                                 "LOGGED_PREGAME", "BACKTEST_SEEDED")
  }
  for (sc in PWP_SNAPSHOT_COLS) {
    if (!sc %in% names(log_df)) log_df[[sc]] <- NA_real_
  }
  .pwp_check_previous(log_df, spine, season_start, slate)

  r <- .pwp_ratings()
  cat(sprintf("  ratings          : %d teams from ensemble_team_ratings.rds\n\n", r$n))

  new_rows <- .pwp_build_week_projections(wk, spine, r, prediction_timestamp = Sys.time())

  cat("-- Week projections (PENDING; graded later from box scores) -----\n")
  print(as.data.frame(new_rows %>% transmute(
    date = format(.data$game_date), game_id, away_team, home_team,
    sched = .data$comp_schedule, margin = .data$predicted_margin,
    sigma = round(.data$sigma_game, 2),
    p_home = .data$predicted_home_win_prob, winner = .data$predicted_winner)),
    row.names = FALSE)

  key <- function(d) paste(format(as.Date(d$game_date)), d$home_team, d$away_team)
  dup <- key(new_rows) %in% key(log_df)
  cat(sprintf("\n  existing log: %d rows | already logged: %d of %d\n",
              nrow(log_df), sum(dup), nrow(new_rows)))
  if (any(dup)) new_rows <- new_rows[!dup, , drop = FALSE]
  if (!nrow(new_rows)) {
    cat(sprintf("  week %d is already fully logged. Nothing to do.\n", slate))
    cat("================================================================\n")
    return(0L)
  }

  if (!do_write) {
    cat(sprintf("\nDRY RUN: would insert %d row(s). Re-run with --write to apply.\n", nrow(new_rows)))
    cat("================================================================\n")
    return(0L)
  }

  bk <- file.path(CACHE_DIR, sprintf("prediction_accuracy_log.backup-%s.rds",
                                     format(Sys.time(), "%Y%m%d-%H%M%S")))
  saveRDS(log_df, bk)
  cat(sprintf("\n  backed up %d existing rows to %s\n", nrow(log_df), basename(bk)))
  out <- bind_rows(log_df, new_rows)
  out <- out[order(as.Date(out$game_date), out$game_id), , drop = FALSE]
  saveRDS(out, CACHE_PREDICTION_LOG)
  if (exists("PRED_LOG_CSV")) utils::write.csv(out, PRED_LOG_CSV, row.names = FALSE, na = "")
  cat(sprintf("  inserted %d row(s); log is now %d rows.\n", nrow(new_rows), nrow(out)))
  cat("================================================================\n")
  0L
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("project_week_predictions\\.R$", files))) return(invisible(NULL))
  quit(status = main())
})
