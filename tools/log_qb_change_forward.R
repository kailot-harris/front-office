# ==============================================================================
# tools/log_qb_change_forward.R - forward log of the QB-change flag (issue #220 follow-up)
#
# The momentum study (docs/research/momentum_measures_study.md) found no reliable
# momentum signal on past seasons. This logger checks the same question on games
# that have NOT been played yet: every pipeline run appends, for each team that
# plays in the current week, what was known BEFORE that game. A later run of
# tools/score_forward_log.R compares the logged values with what happened.
#
# One row per team per as-of date (the run date), for the team's next game in the
# current week. Teams on a bye that week get no row.
#   season, week, as_of_date, team, opponent, next_game_id, next_game_date, home,
#   elo_pre, opp_elo_pre, elo_expected_margin   (production Elo, tools/elo_model.R)
#   last_game_id, qb_id_last, qb_id_prev, qb_change_last, logged_at
# qb_change_last: TRUE when the starting QB of the team's most recent completed
# regular-season game this season differs from the game before it. The starting
# QB is the passer with the most dropbacks (passer id, or the rusher id on
# scrambles; ties broken by id) - the same definition as tools/momentum_measures_study.R.
# elo_expected_margin: (elo_pre - opp_elo_pre + ELO_HCA_POINTS x home sign) /
# ELO_POINTS_PER_MARGIN_PT, the pure Elo margin (no QB-injury or fatigue shift); the
# listed home team gets home field at every site, as tools/elo_model.R does.
#
# FORWARD-ONLY RULES (enforced in code, see the guards below):
#   * as_of must be today (Sys.Date()); past dates are refused, nothing is backfilled.
#   * only games with no score and a game date on or after as_of are logged.
#   * a team with an earlier game still unscored (data lag) is skipped, not guessed.
#   * missing values stay NA (no imputation); a team with fewer than two completed
#     games this season, or a game absent from the play-by-play, gets NA.
#   * idempotent: rows are keyed on (as_of_date, team); a key already in the log is
#     never rewritten and never appended twice. The file is only ever appended to.
#
# Inputs (caches the pipeline already writes): CACHE_SCHEDULES (daily_ingest.R),
# CACHE_DNA_PBP (current-season play-by-play with dropbacks, refreshed by
# build_passing_dataset.R). Elo is the production walk-forward recomputed from the
# schedules exactly as team_ratings_engine.R does (seasons MODERN_ERA_START_SEASON..
# CURRENT_SEASON, ELO_K_FACTOR); fatigue never enters the rating, so it is not read.
# Output: FORWARD_LOG_QB_CHANGE (config.R), tracked in git, staged by publish_web.R.
#
# Pipeline stage: run_full_pipeline.R calls run_qb_change_forward_logger(). Any
# failure there is a warning only; the pipeline and the publish step continue.
# No top-level side effects beyond definitions.
# ==============================================================================

if (!exists("CACHE_SCHEDULES")) source("config.R")
if (!exists("run_elo_walkforward", mode = "function")) {
  source(file.path(if (exists("PROJECT_DIR")) PROJECT_DIR else getwd(), "tools", "elo_model.R"))
}

QCF_COLUMNS <- c("season", "week", "as_of_date", "team", "opponent", "next_game_id", "next_game_date",
                 "home", "elo_pre", "opp_elo_pre", "elo_expected_margin", "last_game_id",
                 "qb_id_last", "qb_id_prev", "qb_change_last", "logged_at")

.qcf_say <- function(level, msg) {
  fn <- paste0("log_", level)
  if (exists(fn, mode = "function")) {
    tryCatch(get(fn, mode = "function")(msg, script = "tools/log_qb_change_forward.R"),
             error = function(e) message(msg))
  } else message(msg)
}

# Starting QB of one team in one game: passer with the most dropbacks.
qcf_starting_qb <- function(pbp, game_id, team) {
  d <- pbp[pbp$game_id == game_id & pbp$posteam %in% team & pbp$qb_dropback %in% 1, , drop = FALSE]
  if (!nrow(d)) return(NA_character_)
  id <- ifelse(is.na(d$passer_player_id), d$rusher_player_id, d$passer_player_id)
  id <- id[!is.na(id)]
  if (!length(id)) return(NA_character_)
  tab <- table(id)
  tab <- tab[order(-as.integer(tab), names(tab))]
  names(tab)[1]
}

# Each team's production Elo before its next game (season carryover applied).
qcf_elo_state <- function(sch, season) {
  done <- sch[!is.na(sch$home_score) & !is.na(sch$away_score) &
                sch$season >= MODERN_ERA_START_SEASON & sch$season <= season, , drop = FALSE]
  done$gameday <- as.Date(done$gameday)
  if (nrow(done) < 100) stop("log_qb_change_forward: fewer than 100 completed games for the Elo state")
  st <- run_elo_walkforward(done, data.frame(game_id = character(0), team = character(0),
                                             fatigue_drag_pts = numeric(0)),
                            ELO_K_FACTOR, return_final_state = TRUE)
  function(team) {
    r <- st$final_elo[team]; s <- st$final_season[team]
    if (length(r) != 1L || is.na(r) || is.na(s)) return(NA_real_)
    project_elo_rating(unname(r), unname(s), season)
  }
}

qcf_read_log <- function(log_path) {
  if (!file.exists(log_path)) return(NULL)
  x <- utils::read.csv(log_path, stringsAsFactors = FALSE, na.strings = c("NA", ""),
                       colClasses = "character")
  if (!identical(names(x), QCF_COLUMNS)) {
    stop("log_qb_change_forward: existing log header does not match the expected columns; refusing to append to ", log_path)
  }
  x
}

# Build today's rows (does not write). Returns a data.frame with QCF_COLUMNS.
qcf_build_rows <- function(as_of, sch, pbp, season) {
  sch <- as.data.frame(sch, stringsAsFactors = FALSE)
  sch$gameday <- as.Date(sch$gameday)
  reg <- sch[sch$season == season & sch$game_type == "REG", , drop = FALSE]
  unplayed <- is.na(reg$home_score) | is.na(reg$away_score)
  # GUARD: only games not yet played, dated on or after the as-of date.
  upcoming <- reg[unplayed & reg$gameday >= as_of, , drop = FALSE]
  empty <- as.data.frame(setNames(replicate(length(QCF_COLUMNS), character(0), simplify = FALSE), QCF_COLUMNS),
                         stringsAsFactors = FALSE)
  if (!nrow(upcoming)) return(empty)
  week_now <- min(upcoming$week)
  wk <- upcoming[upcoming$week == week_now, , drop = FALSE]
  # GUARD: a team with an earlier game still unscored is skipped (stale data, never guessed).
  stale <- reg[unplayed & reg$gameday < as_of, , drop = FALSE]
  stale_teams <- unique(c(stale$home_team, stale$away_team))
  if (length(stale_teams)) {
    .qcf_say("warn", sprintf("log_qb_change_forward: skipping %s (an earlier game has no score yet)",
                             paste(sort(stale_teams), collapse = ", ")))
  }
  elo_of <- qcf_elo_state(sch, season)
  completed <- reg[!unplayed, , drop = FALSE]
  completed <- completed[order(completed$gameday, completed$game_id), , drop = FALSE]
  rows <- list()
  for (i in seq_len(nrow(wk))) {
    g <- wk[i, ]
    for (side in c("home", "away")) {
      team <- if (side == "home") g$home_team else g$away_team
      opp <- if (side == "home") g$away_team else g$home_team
      if (team %in% stale_teams) next
      hs <- if (side == "home") 1 else -1
      e_t <- elo_of(team); e_o <- elo_of(opp)
      exp_m <- (e_t - e_o + ELO_HCA_POINTS * hs) / ELO_POINTS_PER_MARGIN_PT
      tg <- completed[completed$home_team == team | completed$away_team == team, , drop = FALSE]
      last_id <- NA_character_; qb_last <- NA_character_; qb_prev <- NA_character_; chg <- NA
      if (nrow(tg) >= 1L) last_id <- tg$game_id[nrow(tg)]
      if (nrow(tg) >= 2L) {
        qb_last <- qcf_starting_qb(pbp, tg$game_id[nrow(tg)], team)
        qb_prev <- qcf_starting_qb(pbp, tg$game_id[nrow(tg) - 1L], team)
        if (!is.na(qb_last) && !is.na(qb_prev)) chg <- qb_last != qb_prev
      }
      rows[[length(rows) + 1L]] <- data.frame(
        season = as.character(season), week = as.character(week_now), as_of_date = format(as_of),
        team = team, opponent = opp, next_game_id = g$game_id, next_game_date = format(g$gameday),
        home = as.character(side == "home"),
        elo_pre = if (is.na(e_t)) NA_character_ else sprintf("%.4f", e_t),
        opp_elo_pre = if (is.na(e_o)) NA_character_ else sprintf("%.4f", e_o),
        elo_expected_margin = if (is.na(exp_m)) NA_character_ else sprintf("%.4f", exp_m),
        last_game_id = last_id, qb_id_last = qb_last, qb_id_prev = qb_prev,
        qb_change_last = if (is.na(chg)) NA_character_ else as.character(chg),
        logged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows)
  out[order(out$team), QCF_COLUMNS, drop = FALSE]
}

# Append today's rows. Returns the rows appended (invisibly).
log_qb_change_forward <- function(as_of = Sys.Date(),
                                  schedules_path = CACHE_SCHEDULES,
                                  pbp_path = CACHE_DNA_PBP,
                                  log_path = FORWARD_LOG_QB_CHANGE,
                                  season = CURRENT_SEASON,
                                  dry_run = FALSE) {
  as_of <- as.Date(as_of)
  # GUARD: forward only - never a past date (no backfill), never a future one.
  if (is.na(as_of) || as_of < Sys.Date()) {
    stop(sprintf("log_qb_change_forward: refusing as-of date %s - only today (%s) may be logged; no backfill.",
                 format(as_of), format(Sys.Date())))
  }
  if (as_of > Sys.Date()) {
    stop(sprintf("log_qb_change_forward: refusing future as-of date %s.", format(as_of)))
  }
  if (!file.exists(schedules_path)) stop("log_qb_change_forward: schedules cache not found: ", schedules_path)
  if (!file.exists(pbp_path)) stop("log_qb_change_forward: play-by-play cache not found: ", pbp_path)
  existing <- qcf_read_log(log_path)
  sch <- readRDS(schedules_path)
  pbp <- as.data.frame(readRDS(pbp_path), stringsAsFactors = FALSE)
  need <- c("game_id", "posteam", "qb_dropback", "passer_player_id", "rusher_player_id")
  miss <- setdiff(need, names(pbp))
  if (length(miss)) stop("log_qb_change_forward: play-by-play lacks column(s): ", paste(miss, collapse = ", "))
  if ("season_type" %in% names(pbp)) pbp <- pbp[pbp$season_type %in% "REG", , drop = FALSE]
  pbp <- pbp[, need, drop = FALSE]

  rows <- qcf_build_rows(as_of, sch, pbp, season)
  # GUARD: idempotent - drop any (as_of_date, team) key already in the log.
  if (!is.null(existing) && nrow(rows)) {
    seen <- paste(existing$as_of_date, existing$team)
    rows <- rows[!paste(rows$as_of_date, rows$team) %in% seen, , drop = FALSE]
  }
  if (dry_run) return(invisible(rows))
  if (!nrow(rows)) {
    .qcf_say("info", sprintf("log_qb_change_forward: nothing new to append for %s.", format(as_of)))
    return(invisible(rows))
  }
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)
  # Append-only: header written once, rows appended, nothing rewritten.
  utils::write.table(rows, log_path, sep = ",", row.names = FALSE, qmethod = "double",
                     append = file.exists(log_path), col.names = !file.exists(log_path))
  .qcf_say("info", sprintf("log_qb_change_forward: appended %d row(s) for %s (week %s) to %s.",
                           nrow(rows), format(as_of), rows$week[1], log_path))
  invisible(rows)
}

# Pipeline entry point (run_full_pipeline.R call_fn). Never stops the pipeline.
run_qb_change_forward_logger <- function() {
  tryCatch(log_qb_change_forward(),
           error = function(e) {
             .qcf_say("warn", sprintf("QB-change forward logger skipped this run: %s", conditionMessage(e)))
             warning(sprintf("QB-change forward logger skipped this run: %s", conditionMessage(e)))
             invisible(NULL)
           })
}
