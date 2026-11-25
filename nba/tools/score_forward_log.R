# ==============================================================================
# tools/score_forward_log.R
#
# Scores the Momentum Board forward log (data/history/momentum_forward_log.csv,
# written by tools/log_momentum_forward.R) against the games that were played
# after each row was logged. Not a pipeline stage; run it by hand.
#
# Comparisons (same target as docs/research/momentum_measures_study.md):
#   window 10 combined score  vs  net10_beyond_elo
#   window 5  combined score  vs  net5_beyond_elo
# netN_beyond_elo = mean over the team's next N games of
#   (point margin - (logged pregame Elo - opponent pregame Elo + 100 x home sign) / 28)
# where home sign is +1 home, -1 away, 0 neutral site, and the team's Elo is the
# value logged on the as-of date (the Elo after its last game, as in the study).
#
# Outcome games: the team's games dated on or after the as-of date and after the
# board's through_date, from the season's team-game panel that the board build
# writes (cache/momentum_team_game_panel_<season>.rds: real box-score margins and
# the shared Elo series). A row is scored only when the team has played all N of
# those games and every one has a margin and an opponent pregame Elo; otherwise it
# is skipped (counted, never filled). A row with no logged combined score is not
# scored either.
#
# Report: docs/research/forward_log_scoring.md with rows logged, rows scored, the
# Pearson correlation and OLS slope with team-season block bootstrap 95% CIs, and
# a plain verdict. Below MIN_SCORED rows or MIN_DATES distinct as-of dates the
# report says "not enough games yet" and gives the counts, with no estimate.
#
# Usage: Rscript tools/score_forward_log.R
# ==============================================================================

FL_MIN_SCORED <- 300L
FL_MIN_DATES  <- 20L
FL_BOOT_N     <- 2000L
FL_COMPARISONS <- list(list(window = 10L, horizon = 10L), list(window = 5L, horizon = 5L))

.fl_score_dir <- local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (length(f) == 1L && grepl("score_forward_log\\.R$", f)) normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
  else getwd()
})
if (!exists("ELO_HOME_ADV") || !exists("ELO_POINTS_PER_MARGIN_POINT")) {
  elo_r <- file.path(.fl_score_dir, "R", "elo.R")
  if (!file.exists(elo_r)) elo_r <- file.path("R", "elo.R")
  source(elo_r, local = TRUE)
}

#' hoopR season year from the board's season label ("2026-27" -> 2027).
fl_season_year <- function(label) {
  m <- regmatches(label, regexec("^(\\d{4})-(\\d{2})$", label))
  vapply(m, function(x) if (length(x) == 3L) as.integer(x[2]) + 1L else NA_integer_, integer(1))
}

#' Default panel loader: the board build's team-game panel for a season.
fl_panel_loader <- function(cache_dir) {
  function(season) {
    path <- file.path(cache_dir, sprintf("momentum_team_game_panel_%d.rds", season))
    if (!file.exists(path)) return(NULL)
    as.data.frame(readRDS(path), stringsAsFactors = FALSE)
  }
}

#' Outcome for every logged row and horizon h; NA (with a reason) when not scorable.
fl_outcomes <- function(log, h, load_panel) {
  n <- nrow(log)
  target <- rep(NA_real_, n); status <- rep("scored", n)
  seasons <- fl_season_year(log$season)
  panels <- list()
  for (i in seq_len(n)) {
    s <- seasons[i]
    if (is.na(s)) { status[i] <- "no season"; next }
    key <- as.character(s)
    if (!key %in% names(panels)) panels[key] <- list(load_panel(s))
    p <- panels[[key]]
    elo <- suppressWarnings(as.numeric(log$elo_pregame[i]))
    if (is.null(p)) { status[i] <- "no results panel"; next }
    if (is.na(elo)) { status[i] <- "no logged Elo"; next }
    as_of <- as.Date(log$as_of_date[i]); through <- as.Date(log$through_date[i])
    g <- p[p$team == log$team[i] & as.Date(p$game_date) >= as_of & as.Date(p$game_date) > through, , drop = FALSE]
    g <- g[order(g$game_date, g$game_id), , drop = FALSE]
    if (nrow(g) < h) { status[i] <- "window incomplete"; next }
    g <- g[seq_len(h), , drop = FALSE]
    if (anyNA(g$margin) || anyNA(g$opp_elo_pre) || anyNA(g$home) || anyNA(g$neutral)) { status[i] <- "missing result values"; next }
    hs <- ifelse(g$neutral, 0, ifelse(g$home, 1, -1))
    expected <- (elo - g$opp_elo_pre + hs * ELO_HOME_ADV) / ELO_POINTS_PER_MARGIN_POINT
    target[i] <- mean(g$margin - expected)
  }
  data.frame(target = target, status = status, stringsAsFactors = FALSE)
}

#' Correlation and slope, with a team-season block bootstrap 95% CI.
fl_block_bootstrap <- function(x, y, block, n_boot = FL_BOOT_N, seed = 20261124L) {
  est <- c(r = stats::cor(x, y), slope = unname(stats::coef(stats::lm(y ~ x))[2]))
  set.seed(seed)
  ub <- unique(block); idx <- split(seq_along(block), block)
  bs <- matrix(NA_real_, n_boot, 2, dimnames = list(NULL, c("r", "slope")))
  for (b in seq_len(n_boot)) {
    take <- unlist(idx[sample(ub, length(ub), replace = TRUE)], use.names = FALSE)
    xb <- x[take]; yb <- y[take]
    if (stats::sd(xb) > 0 && stats::sd(yb) > 0)
      bs[b, ] <- c(stats::cor(xb, yb), unname(stats::coef(stats::lm(yb ~ xb))[2]))
  }
  ci <- apply(bs, 2, stats::quantile, probs = c(0.025, 0.975), na.rm = TRUE)
  list(estimate = est, ci = ci, blocks = length(ub), n_boot = sum(!is.na(bs[, 1])))
}

fl_verdict <- function(lo, hi) {
  if (lo > 0) "positive: the logged score lined up with how teams did over their next games, beyond Elo (95% interval above zero)."
  else if (hi < 0) "negative: the logged score ran opposite to how teams did over their next games (95% interval below zero)."
  else "no reliable relationship: the 95% interval includes zero."
}

#' Score the log. Returns the per-comparison results; writes the report when out_md is set.
score_forward_log <- function(log_path, load_panel, out_md = NULL, min_scored = FL_MIN_SCORED,
                              min_dates = FL_MIN_DATES, n_boot = FL_BOOT_N, now = Sys.time()) {
  log <- if (file.exists(log_path) && file.info(log_path)$size > 0)
    utils::read.csv(log_path, colClasses = "character", na.strings = "", check.names = FALSE) else NULL
  rows_logged <- if (is.null(log)) 0L else nrow(log)
  dates_logged <- if (is.null(log)) 0L else length(unique(log$as_of_date))
  results <- lapply(FL_COMPARISONS, function(cmp) {
    w <- cmp$window; h <- cmp$horizon
    res <- list(window = w, horizon = h, rows_logged = rows_logged, rows_with_score = 0L,
                rows_scored = 0L, dates_scored = 0L, skipped = list(), enough = FALSE)
    if (!rows_logged) return(res)
    score <- suppressWarnings(as.numeric(log[[sprintf("w%d_combined", w)]]))
    oc <- fl_outcomes(log, h, load_panel)
    oc$status[is.na(score) & oc$status == "scored"] <- "no logged combined score"
    keep <- oc$status == "scored" & !is.na(oc$target) & !is.na(score)
    res$rows_with_score <- sum(!is.na(score))
    res$rows_scored <- sum(keep)
    res$dates_scored <- length(unique(log$as_of_date[keep]))
    res$skipped <- as.list(table(oc$status[!keep]))
    res$enough <- res$rows_scored >= min_scored && res$dates_scored >= min_dates
    if (res$enough) {
      block <- paste(log$season[keep], log$team[keep])
      res$boot <- fl_block_bootstrap(score[keep], oc$target[keep], block, n_boot = n_boot)
      res$verdict <- fl_verdict(res$boot$ci[1, "r"], res$boot$ci[2, "r"])
    } else {
      res$verdict <- "not enough games yet"
    }
    res
  })
  if (!is.null(out_md)) fl_write_report(results, rows_logged, dates_logged, out_md, min_scored, min_dates, now)
  invisible(results)
}

fl_report_lines <- function(results, rows_logged, dates_logged, min_scored, min_dates, now) {
  f3 <- function(x) sprintf("%.3f", x)
  L <- c("# Momentum Board forward log: scoring", "",
         sprintf("- Generated: %s", format(as.POSIXct(now), "%Y-%m-%d %H:%M UTC", tz = "UTC")),
         "- Log: data/history/momentum_forward_log.csv (one row per team per run date, written before the games were played)",
         sprintf("- Rows logged: %d across %d as-of dates", rows_logged, dates_logged),
         sprintf("- Minimum sample for a result: %d scored team-dates across at least %d distinct dates", min_scored, min_dates),
         "- Target: mean over the team's next N games of (point margin minus (logged pregame Elo - opponent pregame Elo + 100 x home sign) / 28), as in docs/research/momentum_measures_study.md",
         "- Interval: team-season block bootstrap, 95% percentile", "")
  for (r in results) {
    L <- c(L, sprintf("## Window %d combined score vs next-%d net margin beyond Elo", r$window, r$horizon), "",
           sprintf("- Rows logged: %d (with a combined score: %d)", r$rows_logged, r$rows_with_score),
           sprintf("- Rows scored: %d across %d distinct as-of dates", r$rows_scored, r$dates_scored))
    if (length(r$skipped))
      L <- c(L, sprintf("- Rows skipped: %s", paste(sprintf("%s %d", names(r$skipped), unlist(r$skipped)), collapse = "; ")))
    if (isTRUE(r$enough)) {
      b <- r$boot
      L <- c(L, sprintf("- Correlation: %s (95%% CI %s to %s)", f3(b$estimate[["r"]]), f3(b$ci[1, "r"]), f3(b$ci[2, "r"])),
             sprintf("- Slope (points of next-%d margin beyond Elo per unit of combined score): %s (95%% CI %s to %s)",
                     r$horizon, f3(b$estimate[["slope"]]), f3(b$ci[1, "slope"]), f3(b$ci[2, "slope"])),
             sprintf("- Bootstrap: %d resamples of %d team-season blocks", b$n_boot, b$blocks),
             sprintf("- Verdict: %s", r$verdict), "")
    } else {
      L <- c(L, sprintf("- Verdict: not enough games yet (%d of %d scored rows, %d of %d dates). No estimate is reported.",
                        r$rows_scored, min_scored, r$dates_scored, min_dates), "")
    }
  }
  L
}

fl_write_report <- function(results, rows_logged, dates_logged, out_md, min_scored, min_dates, now) {
  lines <- fl_report_lines(results, rows_logged, dates_logged, min_scored, min_dates, now)
  dir.create(dirname(out_md), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, out_md)
  cat(paste(lines, collapse = "\n"), "\n")
  invisible(out_md)
}

local({
  argv <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", argv[grepl("^--file=", argv)])
  if (!any(grepl("score_forward_log\\.R$", f))) return(invisible(NULL))
  if (nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN", ""))) return(invisible(NULL))
  setwd(.fl_score_dir)
  source("config.R")
  score_forward_log(MOMENTUM_FORWARD_LOG, fl_panel_loader(CACHE_DIR),
                    out_md = file.path("docs", "research", "forward_log_scoring.md"))
})
