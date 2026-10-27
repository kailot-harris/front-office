# One-off backfill: prediction-log rows for 2026-10-26, the tail of week 1.
#
# WHY THIS EXISTS
# ---------------
# The prediction log is fed by log_todays_predictions(), which parses
# cache/latest_value_bets.rds -- a BETTING artifact built from The Odds API. The
# odds key hit its monthly quota, so the feed now 401s, market_odds_engine.R
# falls back to a synthetic slate with placeholder ids (GAME_1..GAME_6), the
# schedule spine contract correctly rejects all of them, and NOTHING has been
# logged since. build_matchups_dataset.R:579 grades a game only when the log has
# it RESOLVED, so 2026-10-26's nine games sat on the site as "not yet played"
# with their real final scores already in box_scores_cache.rds.
#
# Week 1's other 43 games (2026-10-20 .. 10-25) were logged on 2026-10-17 and
# are already RESOLVED. 2026-10-26 is the only gap, so this script writes nine
# rows and nothing else.
#
# This is the gap-filling half of front-office#12 (native open-data schedule
# providers replacing The Odds API) and #10 (grade vs actual outcomes, not CLV).
# The forward-looking half -- projecting each new week off the schedule spine
# every Tuesday -- is tools/project_week_predictions.R.
#
# NO LEAKAGE: WHERE THE RATINGS COME FROM
# ---------------------------------------
# A backfill that used today's ratings would be cheating: today's
# cache/projected_30_team_standings.rds was rewritten this morning and its
# bottom-up win totals have drifted from their pre-week-1 values by a mean of
# 0.59 and a maximum of 4.6 wins (Bucks). roster_bottom_up_engine.R reads no
# game results at all -- it is a pure roster/player-value model -- so that drift
# is roster and injury news from DURING week 1. The Bucks played on 2026-10-26,
# so that particular leak would land directly on a game being backfilled.
#
# The ratings here are therefore reconstructed from
# web/public/data/projections_season_teams.json as committed in bae5652
# (2026-10-18 00:44, before week 1's first tip on 2026-10-20). That payload is
# the last committed artifact that predates week 1, and it carries each of the
# four ensemble variants' projected win totals.
#
# Win totals are not net ratings, so they are inverted back to the rating scale
# through roster_bottom_up_engine.R:255-272's OWN expected-wins map (balanced
# 82-game round robin, half home half away, HCA 2.40, MARGIN_SIGMA 11.8). No new
# model is introduced. The inverter is validated in-script against ground truth:
# inverting today's Proj_Wins must recover today's stored Net_Rating, which it
# does to a maximum of 0.03 points. The script ABORTS if that check regresses.
#
# The four recovered variant ratings are then blended on season_simulator.R's
# own weights (0.35 bottom-up / 0.25 RAPM / 0.20 shot-fatigue / 0.20
# embeddings) and their weight-respecting spread becomes the per-team
# disagreement SD, exactly as season_simulator.R:515-519 computes it, so the
# per-game sigma widens for teams the models argue over -- the same treatment
# build_matchups_dataset.R gives a live ensemble projection.
#
# PREDICTION_TIMESTAMP is written as the INFORMATION CUTOFF (bae5652's commit
# time), not as the moment this script ran. For forecast scoring that field has
# to mean "what was knowable when the forecast was made", and nothing later than
# 2026-10-18 00:44 enters these nine rows. The rows are written PENDING and are
# NOT graded here: reconcile_predictions() grades them against the official box
# scores through the production path, so this script cannot flatter its own
# numbers.
#
# Usage:
#   Rscript tools/backfill_week1_predictions.R            # dry run, writes nothing
#   Rscript tools/backfill_week1_predictions.R --write    # back up, then insert

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
})

.bf_project_root <- function() {
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
  stop("backfill_week1_predictions.R: cannot locate the project root.")
}
local({
  root <- .bf_project_root()
  if (!identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE), root)) setwd(root)
})
source("config.R")

# ------------------------------------------------------------------------------
# Constants. HCA is duplicated in three places in this repo
# (prediction_accuracy_logger.R:169, roster_bottom_up_engine.R:187/254/312,
# build_matchups_dataset.R); 2.40 is the value all of them use.
# ------------------------------------------------------------------------------
BF_HCA          <- 2.40
BF_SIGMA        <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8
BF_TARGET_DATE  <- as.Date("2026-10-26")
BF_PRE_COMMIT   <- "bae5652"
BF_PRE_PATH     <- "web/public/data/projections_season_teams.json"
BF_CUTOFF       <- as.POSIXct("2026-10-18 00:44:01", tz = "")
BF_WEIGHTS      <- c(bottom_up = 0.35, rapm = 0.25, shot_fatigue = 0.20, embeddings = 0.20)
BF_VARIANT_COLS <- c(bottom_up    = "variant_bottom_up_mean_wins",
                     rapm         = "variant_rapm_mean_wins",
                     shot_fatigue = "variant_shot_fatigue_mean_wins",
                     embeddings   = "variant_embeddings_mean_wins")
BF_INVERT_TOL   <- 0.10   # points; validation abort threshold

# Transcribed from roster_bottom_up_engine.R:255-272.
.bf_expected_wins <- function(r) {
  n <- length(r); gpo <- 82 / (n - 1); out <- numeric(n)
  for (i in seq_len(n)) {
    tot <- 0
    for (j in seq_len(n)) {
      if (i == j) next
      d <- r[i] - r[j]
      tot <- tot + (0.5 * pnorm((d + BF_HCA) / BF_SIGMA) +
                    0.5 * pnorm((d - BF_HCA) / BF_SIGMA)) * gpo
    }
    out[i] <- tot
  }
  out
}

# Damped fixed point. The map is monotone and close to affine near the league
# mean, so a constant slope (~2.73 wins per rating point over 82 games) is
# enough; ratings are re-centred each step because only differences matter.
.bf_invert_wins <- function(target, iters = 400L, slope = 2.73) {
  r <- (target - mean(target)) / slope
  for (k in seq_len(iters)) {
    r <- r - (.bf_expected_wins(r) - target) / slope * 0.5
    r <- r - mean(r)
  }
  r
}

# Guard: the inverter must reproduce a rating vector this repo already stores.
.bf_validate_inverter <- function() {
  p <- file.path(CACHE_DIR, "projected_30_team_standings.rds")
  if (!file.exists(p)) {
    cat("[BACKFILL] projected_30_team_standings.rds absent; inverter UNVALIDATED.\n")
    return(invisible(NA_real_))
  }
  st <- as.data.frame(readRDS(p))
  rec <- .bf_invert_wins(st$Proj_Wins)
  worst <- max(abs(rec - st$Net_Rating))
  cat(sprintf("[BACKFILL] inverter validation: max |recovered - stored| = %.3f pts over %d teams\n",
              worst, nrow(st)))
  if (worst > BF_INVERT_TOL) {
    stop(sprintf(paste0("inverter validation FAILED (%.3f > %.3f pts). The forward map in ",
                        "roster_bottom_up_engine.R has probably changed; re-derive it before ",
                        "trusting this backfill."), worst, BF_INVERT_TOL))
  }
  invisible(worst)
}

# Pre-week-1 payload, read straight out of git so the provenance is the commit.
.bf_load_pre_week1 <- function() {
  txt <- suppressWarnings(system2("git", c("show", paste0(BF_PRE_COMMIT, ":", BF_PRE_PATH)),
                                  stdout = TRUE, stderr = FALSE))
  if (!length(txt)) {
    stop(sprintf("could not read %s:%s -- is this a full checkout?", BF_PRE_COMMIT, BF_PRE_PATH))
  }
  df <- jsonlite::fromJSON(paste(txt, collapse = ""), simplifyVector = TRUE)
  need <- c("team_name", unname(BF_VARIANT_COLS))
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop(sprintf("pre-week-1 payload lacks %s", paste(miss, collapse = ", ")))
  }
  df[order(df$team_name), , drop = FALSE]
}

main <- function() {
  do_write <- "--write" %in% commandArgs(trailingOnly = TRUE)

  cat("================================================================\n")
  cat(sprintf("Week-1 prediction backfill  [%s]\n",
              if (do_write) "WRITE" else "DRY RUN - nothing is written"))
  cat("================================================================\n")
  cat(sprintf("  target date      : %s\n", format(BF_TARGET_DATE)))
  cat(sprintf("  rating provenance: %s:%s\n", BF_PRE_COMMIT, BF_PRE_PATH))
  cat(sprintf("  information cutoff: %s\n", format(BF_CUTOFF)))
  cat(sprintf("  HCA %.2f | MARGIN_SIGMA %.1f\n\n", BF_HCA, BF_SIGMA))

  .bf_validate_inverter()

  pre <- .bf_load_pre_week1()
  teams <- pre$team_name
  rmat <- sapply(BF_VARIANT_COLS, function(v) .bf_invert_wins(pre[[v]]))
  rownames(rmat) <- teams
  ens <- as.numeric(rmat %*% BF_WEIGHTS)
  dis <- sqrt(as.numeric(((rmat - ens)^2) %*% BF_WEIGHTS))
  names(ens) <- teams; names(dis) <- teams
  cat(sprintf("[BACKFILL] recovered %d pre-week-1 variant rating vectors; blended ensemble\n", ncol(rmat)))
  cat(sprintf("[BACKFILL] rating range %.2f .. %.2f pts | disagreement SD mean %.2f (%.2f .. %.2f)\n\n",
              min(ens), max(ens), mean(dis), min(dis), max(dis)))

  sched <- as.data.frame(readRDS(CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON)))
  s <- sched[as.Date(sched$game_date) == BF_TARGET_DATE, , drop = FALSE]
  if (!nrow(s)) stop(sprintf("no scheduled games on %s in the schedule cache", BF_TARGET_DATE))
  hn <- s$home_short_display_name
  an <- s$away_short_display_name
  unrated <- setdiff(c(hn, an), teams)
  if (length(unrated)) {
    stop(sprintf("no pre-week-1 rating for: %s", paste(unrated, collapse = ", ")))
  }

  margin <- (ens[hn] - ens[an]) + BF_HCA
  sigma_game <- sqrt(BF_SIGMA^2 + dis[hn]^2 + dis[an]^2)
  prob <- pnorm(margin / sigma_game)
  winner <- ifelse(prob >= 0.5, hn, an)

  # sigma_game is only ever reported, never stored (the log has no column for
  # it). It is carried through the SAME frame as everything else rather than
  # spliced in at print time: computed in schedule order and printed against an
  # arrange()d tibble, it would silently pair each game with another game's
  # sigma.
  new_rows <- tibble(
    game_id                 = as.character(s$game_id),
    game_date               = BF_TARGET_DATE,
    season                  = 2026L,   # the log labels BOTH seasons 2026; joins are by DATE
    home_team               = hn,
    away_team               = an,
    prediction_timestamp    = BF_CUTOFF,
    predicted_home_win_prob = round(as.numeric(prob), 4),
    .pred_Win               = round(as.numeric(prob), 4),
    predicted_winner        = winner,
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

  cat("-- Rows to insert (PENDING; graded later by reconcile_predictions) ----\n")
  print(as.data.frame(new_rows %>% transmute(
    game_id, away_team, home_team,
    margin = .data$predicted_margin,
    sigma  = .data$.sigma_game,
    p_home = .data$predicted_home_win_prob,
    winner = .data$predicted_winner)), row.names = FALSE)

  # Dropped before the row ever reaches the log, so the stored schema is
  # untouched and the web contracts see exactly the columns they expect.
  new_rows$.sigma_game <- NULL

  log_df <- as.data.frame(readRDS(CACHE_PREDICTION_LOG))
  key <- function(d) paste(format(as.Date(d$game_date)), d$home_team, d$away_team)
  dup <- key(new_rows) %in% key(log_df)
  cat(sprintf("\n[BACKFILL] existing log: %d rows | already present: %d of %d\n",
              nrow(log_df), sum(dup), nrow(new_rows)))
  if (any(dup)) {
    cat("[BACKFILL] skipping rows already in the log (idempotent):\n")
    for (k in key(new_rows)[dup]) cat(sprintf("           %s\n", k))
    new_rows <- new_rows[!dup, , drop = FALSE]
  }
  if (!nrow(new_rows)) {
    cat("\n[BACKFILL] nothing to insert. Done.\n")
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
  cat(sprintf("\n[BACKFILL] backed up %d existing rows to %s\n", nrow(log_df), basename(bk)))

  out <- bind_rows(log_df, new_rows)
  out <- out[order(as.Date(out$game_date), out$game_id), , drop = FALSE]
  saveRDS(out, CACHE_PREDICTION_LOG)
  if (exists("PRED_LOG_CSV")) utils::write.csv(out, PRED_LOG_CSV, row.names = FALSE, na = "")
  cat(sprintf("[BACKFILL] inserted %d row(s); log is now %d rows.\n", nrow(new_rows), nrow(out)))
  cat("[BACKFILL] they are PENDING. Run the logger's reconcile step to grade them.\n")
  cat("================================================================\n")
  0L
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  files <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("backfill_week1_predictions\\.R$", files))) return(invisible(NULL))
  quit(status = main())
})
