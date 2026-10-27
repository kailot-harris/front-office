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

PWP_HCA   <- 2.40
PWP_SIGMA <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8

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
  need <- c("team", "team_name", "ensemble_net_rating", "rating_disagreement_sd")
  miss <- setdiff(need, names(e))
  if (length(miss)) stop(sprintf("ensemble ratings lack %s", paste(miss, collapse = ", ")))
  num <- function(x) suppressWarnings(as.numeric(x))
  list(
    rating = c(setNames(num(e$ensemble_net_rating), as.character(e$team_name)),
               setNames(num(e$ensemble_net_rating), as.character(e$team))),
    # A present-but-nonfinite SD contributes nothing and the game collapses to
    # the plain MARGIN_SIGMA, matching build_matchups_dataset.R's .sd_for().
    sd = c(setNames(num(e$rating_disagreement_sd), as.character(e$team_name)),
           setNames(num(e$rating_disagreement_sd), as.character(e$team))),
    n = nrow(e)
  )
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

main <- function() {
  do_write <- "--write" %in% commandArgs(trailingOnly = TRUE)
  spine <- .pwp_spine()
  season_start <- min(spine$game_date)
  spine$slate <- .pwp_slate_of(spine$game_date, season_start)

  slate_arg <- .pwp_arg("--slate")
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
  .pwp_check_previous(log_df, spine, season_start, slate)

  r <- .pwp_ratings()
  cat(sprintf("  ratings          : %d teams from ensemble_team_ratings.rds\n\n", r$n))

  hn <- wk$home_short_display_name
  an <- wk$away_short_display_name
  unrated <- setdiff(c(hn, an), names(r$rating)[!is.na(r$rating)])
  if (length(unrated)) stop(sprintf("no ensemble rating for: %s", paste(unrated, collapse = ", ")))

  fin <- function(v) { v <- unname(as.numeric(v)); ifelse(is.finite(v) & v > 0, v, 0) }
  margin <- unname(r$rating[hn] - r$rating[an]) + PWP_HCA
  sigma_game <- sqrt(PWP_SIGMA^2 + fin(r$sd[hn])^2 + fin(r$sd[an])^2)
  prob <- pnorm(margin / sigma_game)

  new_rows <- tibble(
    game_id                 = as.character(wk$game_id),
    game_date               = wk$game_date,
    season                  = 2026L,   # the log labels BOTH seasons 2026; joins are by DATE
    home_team               = hn,
    away_team               = an,
    prediction_timestamp    = Sys.time(),
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
    .sigma_game             = round(as.numeric(sigma_game), 2)
  ) %>% arrange(.data$game_date, .data$game_id)

  cat("-- Week projections (PENDING; graded later from box scores) -----\n")
  print(as.data.frame(new_rows %>% transmute(
    date = format(.data$game_date), game_id, away_team, home_team,
    margin = .data$predicted_margin, sigma = .data$.sigma_game,
    p_home = .data$predicted_home_win_prob, winner = .data$predicted_winner)),
    row.names = FALSE)
  new_rows$.sigma_game <- NULL

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
