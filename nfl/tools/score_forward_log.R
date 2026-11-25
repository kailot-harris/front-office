# ==============================================================================
# tools/score_forward_log.R - score the QB-change forward log (issue #220 follow-up)
# Research only; NOT part of the pipeline.
#
# Joins the rows tools/log_qb_change_forward.R wrote BEFORE each game with the
# results that came in later (CACHE_SCHEDULES), and compares the margin beyond Elo
# for rows flagged qb_change_last = TRUE with unflagged rows:
#   next game : team margin minus the logged elo_expected_margin
#   next 3    : mean over the team's next 3 regular-season games (the logged game
#               first) of margin minus (logged elo_pre - opponent's pregame Elo +
#               ELO_HCA_POINTS x home sign) / ELO_POINTS_PER_MARGIN_PT, the same
#               expectation the momentum study used (team Elo fixed at the logged
#               value; opponent Elo from the production walk-forward, pregame only).
# Unit: one row per team per logged game (when a team-game was logged on several
# as-of dates, the latest one written before the game is used). Rows whose window
# is not complete yet (any of its games unscored, or fewer games left in the
# season) are skipped and counted. Rows with qb_change_last missing are counted
# and left out of the comparison (no imputation).
# CI: team-season block bootstrap (resample whole team-seasons with replacement),
# 2,000 resamples, 95% percentile interval of flagged minus unflagged.
# Minimum sample per horizon: 20 flagged rows and 200 rows in total; below it the
# report says "not enough games yet" and gives the counts only.
#
# Output: docs/research/forward_log_scoring.md
# Run:    Rscript tools/score_forward_log.R
# Do not commit a report generated from fewer rows than the minimum.
# ==============================================================================

SFL_MIN_FLAGGED <- 20L
SFL_MIN_TOTAL <- 200L
SFL_N_BOOT <- 2000L
SFL_SEED <- 20261124L

# Margin beyond Elo for each logged row, per horizon. Returns a list(rows, counts).
sfl_score_rows <- function(log, sch, elo_games) {
  log <- as.data.frame(log, stringsAsFactors = FALSE)
  sch <- as.data.frame(sch, stringsAsFactors = FALSE)
  sch$gameday <- as.Date(sch$gameday)
  logged_n <- nrow(log)
  # One row per team per logged game: latest as-of date on or before the game date.
  log <- log[as.Date(log$as_of_date) <= as.Date(log$next_game_date), , drop = FALSE]
  log <- log[order(log$team, log$next_game_id, log$as_of_date, decreasing = TRUE), , drop = FALSE]
  log <- log[!duplicated(paste(log$team, log$next_game_id)), , drop = FALSE]
  log <- log[order(log$season, log$week, log$team), , drop = FALSE]
  unit_n <- nrow(log)
  elo_pre_lu <- function(gid, team) {
    e <- elo_games[elo_games$game_id == gid, , drop = FALSE]
    if (!nrow(e)) return(NA_real_)
    if (e$home_team[1] == team) e$home_elo_pre[1] else if (e$away_team[1] == team) e$away_elo_pre[1] else NA_real_
  }
  out <- vector("list", nrow(log))
  for (i in seq_len(nrow(log))) {
    r <- log[i, ]
    reg <- sch[sch$season == as.integer(r$season) & sch$game_type == "REG" &
                 (sch$home_team == r$team | sch$away_team == r$team), , drop = FALSE]
    reg <- reg[order(reg$gameday, reg$game_id), , drop = FALSE]
    k <- match(r$next_game_id, reg$game_id)
    res <- c(beyond1 = NA_real_, beyond3 = NA_real_, complete1 = FALSE, complete3 = FALSE)
    if (!is.na(k)) {
      win <- reg[k:min(nrow(reg), k + 2L), , drop = FALSE]
      scored <- !is.na(win$home_score) & !is.na(win$away_score)
      margin <- ifelse(win$home_team == r$team, win$home_score - win$away_score, win$away_score - win$home_score)
      if (scored[1] && !is.na(r$elo_expected_margin)) {
        res["beyond1"] <- margin[1] - as.numeric(r$elo_expected_margin); res["complete1"] <- TRUE
      }
      if (nrow(win) == 3L && all(scored) && !is.na(r$elo_pre)) {
        hs <- ifelse(win$home_team == r$team, 1, -1)
        opp <- ifelse(win$home_team == r$team, win$away_team, win$home_team)
        opp_elo <- mapply(elo_pre_lu, win$game_id, opp)
        exp_m <- (as.numeric(r$elo_pre) - opp_elo + ELO_HCA_POINTS * hs) / ELO_POINTS_PER_MARGIN_PT
        exp_m[1] <- as.numeric(r$elo_expected_margin)   # first game: the value logged before it
        if (all(!is.na(exp_m))) { res["beyond3"] <- mean(margin - exp_m); res["complete3"] <- TRUE }
      }
    }
    out[[i]] <- data.frame(season = r$season, team = r$team, next_game_id = r$next_game_id,
                           flag = as.logical(r$qb_change_last), beyond1 = res[["beyond1"]],
                           beyond3 = res[["beyond3"]], complete1 = as.logical(res[["complete1"]]),
                           complete3 = as.logical(res[["complete3"]]), stringsAsFactors = FALSE)
  }
  rows <- if (length(out)) do.call(rbind, out) else
    data.frame(season = character(0), team = character(0), next_game_id = character(0), flag = logical(0),
               beyond1 = numeric(0), beyond3 = numeric(0), complete1 = logical(0), complete3 = logical(0))
  list(rows = rows, logged = logged_n, units = unit_n)
}

# Flagged minus unflagged with a team-season block bootstrap CI, or "not enough".
sfl_compare <- function(rows, col, complete_col, n_boot = SFL_N_BOOT, seed = SFL_SEED) {
  d <- rows[rows[[complete_col]] %in% TRUE, , drop = FALSE]
  n_scored <- nrow(d); n_flag_missing <- sum(is.na(d$flag))
  d <- d[!is.na(d$flag), , drop = FALSE]
  nf <- sum(d$flag); nu <- sum(!d$flag); n <- nrow(d)
  base <- list(scored = n_scored, flag_missing = n_flag_missing, flagged = nf, unflagged = nu, total = n)
  if (nf < SFL_MIN_FLAGGED || n < SFL_MIN_TOTAL || nu == 0L) return(c(base, list(enough = FALSE)))
  diff_of <- function(x) mean(x[[col]][x$flag]) - mean(x[[col]][!x$flag])
  blocks <- split(seq_len(n), paste(d$season, d$team))
  set.seed(seed)
  boots <- replicate(n_boot, {
    idx <- unlist(blocks[sample(length(blocks), length(blocks), replace = TRUE)], use.names = FALSE)
    b <- d[idx, , drop = FALSE]
    if (!any(b$flag) || all(b$flag)) NA_real_ else diff_of(b)
  })
  ci <- stats::quantile(boots, c(0.025, 0.975), na.rm = TRUE, names = FALSE)
  c(base, list(enough = TRUE, mean_flagged = mean(d[[col]][d$flag]), mean_unflagged = mean(d[[col]][!d$flag]),
               diff = diff_of(d), ci_lo = ci[1], ci_hi = ci[2]))
}

sfl_report <- function(scored, cmp1, cmp3, generated = Sys.time()) {
  fmt_h <- function(label, cm) {
    head <- sprintf("### %s", label)
    counts <- sprintf("Rows scored: %d (flag missing, left out: %d). Flagged: %d. Unflagged: %d.",
                      cm$scored, cm$flag_missing, cm$flagged, cm$unflagged)
    if (!isTRUE(cm$enough)) {
      return(c(head, "", counts, "",
               sprintf("**Verdict: not enough games yet.** The minimum is %d flagged rows and %d rows in total; no difference is reported below it.",
                       SFL_MIN_FLAGGED, SFL_MIN_TOTAL), ""))
    }
    excl <- cm$ci_lo > 0 || cm$ci_hi < 0
    verdict <- if (excl) {
      sprintf("the 95%% interval excludes zero: after a starting-QB change, teams played %s than Elo expected by %.2f points per game more than other teams.",
              if (cm$diff > 0) "better" else "worse", abs(cm$diff))
    } else "the 95% interval includes zero: no reliable difference between flagged and unflagged rows."
    c(head, "", counts, "",
      "| Group | Mean margin beyond Elo |", "|---|---|",
      sprintf("| QB changed in the latest game | %+.2f |", cm$mean_flagged),
      sprintf("| No QB change | %+.2f |", cm$mean_unflagged),
      sprintf("| Difference (flagged minus unflagged) | %+.2f (95%% CI %+.2f to %+.2f) |", cm$diff, cm$ci_lo, cm$ci_hi),
      "", sprintf("**Verdict:** %s", verdict), "")
  }
  c("# QB-change forward log: scoring", "",
    sprintf("Generated %s by `tools/score_forward_log.R` from `data/history/qb_change_forward_log.csv`.",
            format(generated, "%Y-%m-%d %H:%M %Z")), "",
    "Every row was written before the game it describes, so nothing here was fitted after the fact.",
    "Margin beyond Elo = the team's point margin minus the margin the production Elo expected.",
    sprintf("CI: team-season block bootstrap, %d resamples. Minimum sample: %d flagged rows and %d rows in total.",
            SFL_N_BOOT, SFL_MIN_FLAGGED, SFL_MIN_TOTAL), "",
    sprintf("Rows logged: %d. Team-games logged (latest pregame row per team per game): %d.", scored$logged, scored$units),
    "", fmt_h("Next game", cmp1), fmt_h("Next 3 games", cmp3))
}

score_forward_log <- function(log_path = FORWARD_LOG_QB_CHANGE, schedules_path = CACHE_SCHEDULES,
                              out_path = file.path("docs", "research", "forward_log_scoring.md"),
                              n_boot = SFL_N_BOOT) {
  if (!file.exists(log_path)) stop("score_forward_log: log not found: ", log_path)
  log <- utils::read.csv(log_path, stringsAsFactors = FALSE, na.strings = c("NA", ""), colClasses = "character")
  sch <- as.data.frame(readRDS(schedules_path), stringsAsFactors = FALSE)
  sch$gameday <- as.Date(sch$gameday)
  done <- sch[!is.na(sch$home_score) & !is.na(sch$away_score) & sch$season >= MODERN_ERA_START_SEASON, , drop = FALSE]
  elo_games <- if (nrow(done)) run_elo_walkforward(done, data.frame(game_id = character(0), team = character(0),
                                                                     fatigue_drag_pts = numeric(0)), ELO_K_FACTOR) else
    data.frame(game_id = character(0), home_team = character(0), away_team = character(0),
               home_elo_pre = numeric(0), away_elo_pre = numeric(0))
  scored <- sfl_score_rows(log, sch, elo_games)
  cmp1 <- sfl_compare(scored$rows, "beyond1", "complete1", n_boot)
  cmp3 <- sfl_compare(scored$rows, "beyond3", "complete3", n_boot)
  report_lines <- sfl_report(scored, cmp1, cmp3)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(report_lines, out_path)
  cat(paste(report_lines, collapse = "\n"), "\n")
  invisible(list(scored = scored, next1 = cmp1, next3 = cmp3, path = out_path))
}

if (sys.nframe() == 0L) {
  root <- local({
    env <- Sys.getenv("NFL_PROJECT_DIR", "")
    if (nzchar(env)) return(normalizePath(env, winslash = "/"))
    f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
    r <- if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else getwd()
    while (!file.exists(file.path(r, "config.R"))) {
      p <- dirname(r); if (identical(p, r)) stop("score_forward_log.R: cannot find config.R"); r <- p
    }
    normalizePath(r, winslash = "/")
  })
  setwd(root)
  source("config.R")
  source(file.path("tools", "elo_model.R"))
  score_forward_log()
}
