# ==============================================================================
# build_momentum_board.R - NFL Momentum Board data layer (NFL_analytics#226, PR 1)
#
# Writes web/public/data/momentum_board.json (WEB_JSON_MOMENTUM_BOARD) and appends
# the weekly rank snapshot to data/history/momentum_rank_history.csv
# (MOMENTUM_RANK_HISTORY). The /momentum page (PR 2) renders the JSON as published.
#
# The board DESCRIBES recent play. The rolling-window study (#227) found that
# recent form adds nothing measurable beyond Elo: for every window, carry-over
# method and weighting, the 95% interval of the gain over Elo includes zero. The
# board is not a forecast and the methods block says so.
#
# SETTINGS: config.R MOMENTUM_BOARD_* (owner decisions, #226 comment of 2026-11-25):
#   windows 3 / 6 / 9 games (3 = noisiest), carry-over mean_regress, weights per
#   window, no significance badge on any flag.
#
# DEFINITIONS: tools/rolling_window_study.R (study commit MOMENTUM_BOARD_STUDY_COMMIT),
# reused here (the study script itself is research only and is not sourced):
#   * form   = opponent-adjusted EPA per play, offense minus defense allowed. A game's
#              adjusted offense = offensive EPA/play minus the opponent's mean EPA/play
#              allowed over its EARLIER games this season (its whole previous season
#              before its first game); defense likewise (study section 2).
#   * window = the team's last k regular-season games. Under mean_regress, games
#              from earlier seasons are carried: each carried game's value is pulled
#              toward the league average of its own season, value -> avg +
#              KEEP^(seasons back) x (value - avg) (study section 3, window_value()).
#              The board's window ENDS at the team's latest completed game (the study's
#              ends at the game before the one it predicts; the board predicts nothing).
#   * components (study section 7, fit_weights()):
#       form       window mean of form
#       trend      form minus the season-to-date mean of form (this season's games)
#       residual   window mean of (margin - Elo expected margin)
#       elo_change window mean of the per-game Elo change x k (the Elo change over the window)
#     each standardised across teams within the season-week (zweek(): z-score, a
#     component equal for every team is 0, fewer than MOMENTUM_BOARD_MIN_Z_TEAMS
#     teams = no value). On the board a "season-week" is the snapshot of all teams
#     after that week's games (each team at its latest game).
#   * combined score = sum of weight x z over the components (config weights).
#   * flags: the study's candidate flag definitions (section 9; tests from Table 11),
#     computed as raw values over the window. The starting-QB change follows the
#     momentum measures study (#221): the starting QB is the passer with the most
#     dropbacks (passer id, or the rusher id on scrambles; ties by id).
#
# ELO: the production walk-forward (tools/elo_model.R run_elo_walkforward(),
# ELO_K_FACTOR) over every completed game from MODERN_ERA_START_SEASON, with the
# post-game ratings reconstructed exactly as the study does. Same series the study
# used for "Elo change" and "Elo expected margin". No new rating is built.
#
# INPUTS (caches the pipeline already writes; nothing synthetic, nothing imputed):
#   CACHE_SCHEDULES   schedules, all seasons (daily_ingest.R)
#   CACHE_PBP         play-by-play EPA, all seasons (daily_ingest.R) - EPA, success, pass/run
#   CACHE_DNA_PBP     current-season full play-by-play (Stage 14.1) - dropbacks (starting
#                     QB), fumbles and recoveries, field goals, turnovers
#   CACHE_SNAP_COUNTS current-season snap counts (key players missing)
#   CACHE_INJURY_DATA current-season injury reports ("Out")
# A value that cannot be supported is null with a reason.
#
# RANK HISTORY: one row per team per window per COMPLETED week (every regular-season
# game of that week and all earlier weeks has a score), written only when that week
# is not yet in the file, only if every team is ranked at every window, and never
# rewriting a past row (append only). History starts at launch: no backfill.
#
# Usage:
#   Rscript build_momentum_board.R            # build and write
#   source("build_momentum_board.R")          # definitions only, no writes
#   run_stage("build_momentum_board.R", ..., call_fn = "run_build_momentum_board")
# ==============================================================================

suppressPackageStartupMessages(library(jsonlite))
if (!exists("WEB_JSON_MOMENTUM_BOARD") || !exists("MOMENTUM_BOARD_WEIGHTS")) source("config.R")
if (!exists("run_elo_walkforward", mode = "function")) {
  source(file.path(if (exists("PROJECT_DIR")) PROJECT_DIR else getwd(), "tools", "elo_model.R"))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

MB_SCHEMA_VERSION <- 1L
MB_HISTORY_COLUMNS <- c("season", "week", "through_date", "window", "team", "rank",
                        "combined_score", "carried_games", "reconstruction")
MB_COMPONENTS <- c("form", "trend", "residual", "elo_change")
MB_FRANCHISE <- c(OAK = "LV", SD = "LAC", STL = "LA")   # as the study: relocated franchises keep one history
mb_canon <- function(x) { x <- as.character(x); ifelse(x %in% names(MB_FRANCHISE), MB_FRANCHISE[x], x) }

.mb_say <- function(level, msg) {
  fn <- paste0("log_", level)
  if (exists(fn, mode = "function")) {
    tryCatch(get(fn, mode = "function")(msg, script = "build_momentum_board.R"), error = function(e) message(msg))
  } else message(msg)
}

mb_round <- function(x, d) if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else round(as.numeric(x), d)

# ------------------------------------------------------------------------------
# 1. Elo (production walk-forward; post-game ratings as in the study)
# ------------------------------------------------------------------------------
mb_elo_games <- function(sched, last_season) {
  s <- as.data.frame(sched, stringsAsFactors = FALSE)
  s$home_team <- mb_canon(s$home_team); s$away_team <- mb_canon(s$away_team)
  s$gameday <- as.Date(s$gameday)
  done <- s[!is.na(s$home_score) & !is.na(s$away_score) &
              s$season >= MODERN_ERA_START_SEASON & s$season <= last_season, , drop = FALSE]
  if (nrow(done) < 100) stop("build_momentum_board: fewer than 100 completed games for the Elo walk-forward")
  elo <- run_elo_walkforward(done, data.frame(game_id = character(0), team = character(0),
                                              fatigue_drag_pts = numeric(0)), ELO_K_FACTOR)
  elo <- as.data.frame(elo, stringsAsFactors = FALSE)
  sc <- done[match(elo$game_id, done$game_id), ]
  ed <- (elo$home_elo_pre + ELO_HCA_POINTS) - elo$away_elo_pre
  y <- ifelse(sc$home_score == sc$away_score, 0.5, as.numeric(sc$home_score > sc$away_score))
  wd <- ifelse(sc$home_score > sc$away_score, ed, -ed)
  mult <- log(pmax(abs(sc$home_score - sc$away_score), 1) + 1) * (ELO_MOV_C / (0.001 * wd + ELO_MOV_C))
  shift <- ELO_K_FACTOR * mult * (y - elo$elo_prob_pure)
  elo$home_elo_post <- elo$home_elo_pre + shift
  elo$away_elo_post <- elo$away_elo_pre - shift
  elo
}

# ------------------------------------------------------------------------------
# 2. Play-by-play aggregates per team-game
# ------------------------------------------------------------------------------
# EPA series from CACHE_PBP (every regular-season play with posteam, defteam and EPA, as
# epa_metrics_engine.R and the study). Pass plays: pass == 1. Run plays: play_type "run"
# and not pass == 1 (designed runs; CACHE_PBP carries no `rush` column, so scrambles count
# as pass plays, as nflfastR does).
mb_pbp_epa <- function(pbp) {
  p <- as.data.frame(pbp, stringsAsFactors = FALSE)
  p <- p[p$season_type == "REG" & !is.na(p$posteam) & !is.na(p$defteam) & !is.na(p$epa), , drop = FALSE]
  p$posteam <- mb_canon(p$posteam)
  k <- paste(p$game_id, p$posteam)
  m <- function(v, w) { v <- ifelse(rep_len(w, length(v)), v, NA_real_); r <- tapply(v, k, function(z) if (all(is.na(z))) NA_real_ else mean(z, na.rm = TRUE)); r }
  run <- p$play_type %in% "run" & !(p$pass %in% 1)
  list(off_epa = m(p$epa, TRUE), off_sr = m(as.numeric(p$success), TRUE),
       pass_epa = m(p$epa, p$pass %in% 1), rush_epa = m(p$epa, run),
       games = unique(p$game_id))
}

# Detail from the current-season full play-by-play (CACHE_DNA_PBP): fumbles, recoveries,
# opponent field goals, giveaways (interceptions plus fumbles lost, charged to the fumbling
# team), starting QB. Definitions as the study's team_game_stats() and the measures study.
mb_pbp_detail <- function(pbp) {
  if (is.null(pbp) || !nrow(pbp)) return(NULL)
  p <- as.data.frame(pbp, stringsAsFactors = FALSE)
  p <- p[p$season_type == "REG", , drop = FALSE]
  for (cc in intersect(c("posteam", "defteam", "fumbled_1_team", "fumble_recovery_1_team"), names(p))) p[[cc]] <- mb_canon(p[[cc]])
  key <- function(g, t) paste(g, t)
  pos_ok <- !is.na(p$posteam) & !is.na(p$defteam)
  kpos <- key(p$game_id, p$posteam)
  cnt <- function(mask, k) { if (!any(mask)) return(setNames(numeric(0), character(0))); tapply(rep(1, sum(mask)), k[mask], sum) }
  ints <- cnt(pos_ok & p$interception %in% 1, kpos)
  fum_team <- ifelse(is.na(p$fumbled_1_team), p$posteam, p$fumbled_1_team)
  fl <- p$fumble_lost %in% 1 & !is.na(fum_team)
  fum_lost <- cnt(fl, key(p$game_id, fum_team))
  fu <- p$fumble %in% 1 & !is.na(p$fumbled_1_team)
  fumbles <- cnt(fu, key(p$game_id, p$fumbled_1_team))
  fr <- fu & !is.na(p$fumble_recovery_1_team)
  recov <- cnt(fr, key(p$game_id, p$fumble_recovery_1_team))
  fga <- pos_ok & p$field_goal_attempt %in% 1
  fg_att <- cnt(fga, kpos)
  fg_made <- cnt(fga & p$field_goal_result %in% "made", kpos)
  d <- p[p$qb_dropback %in% 1 & pos_ok, , drop = FALSE]
  d$qb_id <- ifelse(is.na(d$passer_player_id), d$rusher_player_id, d$passer_player_id)
  d$qb_name <- ifelse(is.na(d$passer_player_id), d$rusher_player_name, d$passer_player_name)
  d <- d[!is.na(d$qb_id), , drop = FALSE]
  qb <- NULL
  if (nrow(d)) {
    a <- aggregate(list(n = rep(1L, nrow(d))), list(key = key(d$game_id, d$posteam), qb_id = d$qb_id), sum)
    a <- a[order(a$key, -a$n, a$qb_id), ]; a <- a[!duplicated(a$key), ]
    nm <- d[!duplicated(d$qb_id), c("qb_id", "qb_name")]
    a$qb_name <- nm$qb_name[match(a$qb_id, nm$qb_id)]
    qb <- a
  }
  list(ints = ints, fum_lost = fum_lost, fumbles = fumbles, recov = recov, fg_att = fg_att,
       fg_made = fg_made, qb = qb, games = unique(p$game_id))
}

# ------------------------------------------------------------------------------
# 3. Team-game panel (regular season, seasons first_season..season)
# ------------------------------------------------------------------------------
mb_team_games <- function(sched, epa, detail, elo, first_season, season) {
  s <- as.data.frame(sched, stringsAsFactors = FALSE)
  s$home_team <- mb_canon(s$home_team); s$away_team <- mb_canon(s$away_team)
  s$gameday <- as.Date(s$gameday)
  g <- s[s$game_type == "REG" & !is.na(s$home_score) & !is.na(s$away_score) &
           s$season >= first_season & s$season <= season, , drop = FALSE]
  mk <- function(home) data.frame(season = g$season, game_id = g$game_id, game_date = g$gameday, week = g$week,
                                  home = home, neutral = g$location %in% "Neutral",
                                  team = if (home) g$home_team else g$away_team, opp = if (home) g$away_team else g$home_team,
                                  pts = if (home) g$home_score else g$away_score, opp_pts = if (home) g$away_score else g$home_score,
                                  stringsAsFactors = FALSE)
  H <- rbind(mk(TRUE), mk(FALSE))
  k <- paste(H$game_id, H$team); ko <- paste(H$game_id, H$opp)
  gv <- function(tab, key) as.numeric(tab[key])
  H$pbp_found <- H$game_id %in% epa$games
  H$off_epa <- gv(epa$off_epa, k); H$def_epa <- gv(epa$off_epa, ko)
  H$off_sr <- gv(epa$off_sr, k); H$def_sr <- gv(epa$off_sr, ko)
  H$pass_epa <- gv(epa$pass_epa, k); H$rush_epa <- gv(epa$rush_epa, k)
  H$pass_epa_def <- gv(epa$pass_epa, ko); H$rush_epa_def <- gv(epa$rush_epa, ko)
  # detail (current season, full play-by-play); NA where the game is not in that file
  H$detail_found <- !is.null(detail) & H$game_id %in% (detail$games %||% character(0))
  z <- function(tab, key) { v <- if (length(tab)) as.numeric(tab[key]) else rep(NA_real_, length(key)); v[is.na(v) & H$detail_found] <- 0; v[!H$detail_found] <- NA_real_; v }
  if (!is.null(detail)) {
    H$giveaways <- z(detail$ints, k) + z(detail$fum_lost, k)
    H$takeaways <- z(detail$ints, ko) + z(detail$fum_lost, ko)
    H$fumbles_game <- z(detail$fumbles, k) + z(detail$fumbles, ko)
    H$fum_recovered <- z(detail$recov, k)
    H$opp_fg_att <- z(detail$fg_att, ko); H$opp_fg_made <- z(detail$fg_made, ko)
    qi <- if (is.null(detail$qb)) rep(NA_integer_, nrow(H)) else match(k, detail$qb$key)
    H$qb_id <- if (is.null(detail$qb)) NA_character_ else detail$qb$qb_id[qi]
    H$qb_name <- if (is.null(detail$qb)) NA_character_ else detail$qb$qb_name[qi]
  } else {
    for (cc in c("giveaways", "takeaways", "fumbles_game", "fum_recovered", "opp_fg_att", "opp_fg_made")) H[[cc]] <- NA_real_
    H$qb_id <- NA_character_; H$qb_name <- NA_character_
  }
  H$margin <- H$pts - H$opp_pts
  H$win <- ifelse(H$margin > 0, 1, ifelse(H$margin < 0, 0, 0.5))
  e <- elo[match(H$game_id, elo$game_id), ]
  H$elo_pre <- ifelse(H$home, e$home_elo_pre, e$away_elo_pre)
  H$opp_elo_pre <- ifelse(H$home, e$away_elo_pre, e$home_elo_pre)
  H$elo_post <- ifelse(H$home, e$home_elo_post, e$away_elo_post)
  H$home_sign <- ifelse(H$home, 1, -1)   # production Elo gives the listed home team home field at every site
  H$elo_exp_margin <- (H$elo_pre - H$opp_elo_pre + H$home_sign * ELO_HCA_POINTS) / ELO_POINTS_PER_MARGIN_PT
  H$elo_delta <- H$elo_post - H$elo_pre
  H$resid <- H$margin - H$elo_exp_margin
  H <- H[order(H$team, H$game_date, H$game_id), , drop = FALSE]; rownames(H) <- NULL
  if (anyDuplicated(paste(H$game_id, H$team))) stop("build_momentum_board: duplicate team-games")
  if (any(is.na(H$elo_pre))) stop("build_momentum_board: a completed game has no Elo rating")
  N <- nrow(H)
  H$ts <- paste(H$season, H$team)
  H$pos_season <- ave(seq_len(N), H$ts, FUN = seq_along)
  prev_date <- ave(as.numeric(H$game_date), H$team, FUN = function(v) c(NA, v[-length(v)]))
  H$rest_in_season <- ifelse(H$pos_season > 1, as.numeric(H$game_date) - prev_date, NA_real_)
  H$opp_row <- match(paste(H$game_id, H$opp), paste(H$game_id, H$team))
  H$opp_rest <- H$rest_in_season[H$opp_row]
  # starting-QB change vs the team's previous game this season (#221); NA for the first game
  prev_qb <- ave(H$qb_id, H$ts, FUN = function(v) c(NA, v[-length(v)]))
  H$qb_change <- ifelse(is.na(prev_qb) | is.na(H$qb_id), NA, H$qb_id != prev_qb)
  # opponent adjustment (study section 2: the opponent's EARLIER games only)
  prior_mean <- function(x, grp) ave(x, grp, FUN = function(v) {
    n <- length(v); ok <- !is.na(v); s <- cumsum(ifelse(ok, v, 0)); m <- cumsum(ok)
    out <- c(NA_real_, (s / m)[-n]); out[c(TRUE, m[-n] == 0)] <- NA_real_; out[seq_len(n)]
  })
  prev_season_mean <- function(x) { m <- tapply(x, H$ts, mean, na.rm = TRUE); v <- as.numeric(m[paste(H$season - 1L, H$team)]); v[is.nan(v)] <- NA; v }
  baseline_before <- function(x) { pm <- prior_mean(x, H$ts); ifelse(is.na(pm), prev_season_mean(x), pm) }
  opp_base <- function(x) baseline_before(x)[H$opp_row]
  H$adj_off_epa <- H$off_epa - opp_base(H$def_epa)
  H$adj_def_epa <- H$def_epa - opp_base(H$off_epa)
  H$form_epa <- H$adj_off_epa - H$adj_def_epa
  H$form_margin <- H$margin + opp_base(H$margin)
  H
}

# ------------------------------------------------------------------------------
# 4. Window engine (snapshot after a given week)
# ------------------------------------------------------------------------------
# Rows of H usable at a snapshot: earlier seasons, or this season through `week`.
mb_snapshot_rows <- function(H, season, week) which(H$season < season | (H$season == season & H$week <= week))

# For each team, the indices (into H) of its last k games at the snapshot, oldest first.
mb_window_index <- function(H, rows, team, k) {
  r <- rows[H$team[rows] == team]
  if (!length(r)) return(integer(0))
  r <- r[order(H$game_date[r], H$game_id[r])]
  utils::tail(r, k)
}

# League average of a series within each season (over every team-game of that season in H).
mb_season_avg <- function(H, name) tapply(H[[name]], H$season, mean, na.rm = TRUE)

# Window mean under the carry method (study window_value(), mean_regress). NA if any game in
# the window has no value (study: rowMeans without na.rm), or the window is short.
mb_window_mean <- function(H, idx, name, season, k, avg, keep = MOMENTUM_BOARD_REGRESS_KEEP,
                           method = MOMENTUM_BOARD_CARRY_METHOD) {
  if (length(idx) < k) return(NA_real_)
  v <- H[[name]][idx]
  if (any(is.na(v))) return(NA_real_)
  back <- season - H$season[idx]
  if (method == "mean_regress") {
    a <- as.numeric(avg[as.character(H$season[idx])])
    v <- ifelse(back > 0, a + keep^back * (v - a), v)
  } else if (method != "reset") stop("build_momentum_board: unsupported carry method ", method)
  mean(v)
}

# Season-to-date mean (study std_value(), mean_regress): mean of this season's games through
# the snapshot (missing values skipped, as prior_mean_in_group()); with no game yet this
# season, the previous season's mean pulled toward that season's league average.
mb_std_mean <- function(H, rows, team, name, season, avg, keep = MOMENTUM_BOARD_REGRESS_KEEP) {
  cur <- rows[H$team[rows] == team & H$season[rows] == season]
  v <- H[[name]][cur]
  if (length(cur) && any(!is.na(v))) return(mean(v, na.rm = TRUE))
  prev <- rows[H$team[rows] == team & H$season[rows] == season - 1L]
  pv <- H[[name]][prev]
  if (!length(prev) || all(is.na(pv))) return(NA_real_)
  a <- as.numeric(avg[as.character(season - 1L)])
  a + keep * (mean(pv, na.rm = TRUE) - a)
}

# Standardise across teams within the season-week (study zweek()).
mb_zscore <- function(x, min_teams = MOMENTUM_BOARD_MIN_Z_TEAMS) {
  n <- sum(!is.na(x))
  if (n < min_teams) return(rep(NA_real_, length(x)))
  m <- mean(x, na.rm = TRUE); s <- stats::sd(x, na.rm = TRUE)
  z <- (x - m) / s
  if (!is.na(s) && s < 1e-9) z[!is.na(x)] <- 0
  z[!is.finite(z)] <- NA_real_
  z
}

# Combined score: weighted sum of the standardised components. A component with weight 0
# does not enter; a missing weighted component makes the score null.
mb_combine <- function(Z, weights) {
  w <- weights[MB_COMPONENTS]
  use <- names(w)[w > 0]
  out <- as.numeric(as.matrix(Z[, use, drop = FALSE]) %*% w[use])
  out[!stats::complete.cases(Z[, use, drop = FALSE])] <- NA_real_
  out
}

mb_rank_desc <- function(x) { r <- rep(NA_integer_, length(x)); ok <- !is.na(x); r[ok] <- as.integer(rank(-x[ok], ties.method = "min")); r }

# One snapshot: every team at every window. Returns a list keyed by window of data frames
# (one row per team) plus the window indices.
mb_snapshot <- function(H, season, week, teams, windows = MOMENTUM_BOARD_WINDOWS,
                        weights = MOMENTUM_BOARD_WEIGHTS) {
  rows <- mb_snapshot_rows(H, season, week)
  avg <- lapply(setNames(nm = c("form_epa", "resid", "elo_delta", "adj_off_epa", "adj_def_epa", "form_margin",
                                "off_epa", "def_epa", "off_sr", "def_sr", "pass_epa", "rush_epa",
                                "pass_epa_def", "rush_epa_def")), function(n) mb_season_avg(H, n))
  out <- list()
  for (k in windows) {
    wk <- as.character(k)
    idx <- lapply(teams, function(t) mb_window_index(H, rows, t, k))
    wm <- function(name) vapply(idx, function(i) mb_window_mean(H, i, name, season, k, avg[[name]]), 0)
    stdm <- function(name) vapply(teams, function(t) mb_std_mean(H, rows, t, name, season, avg[[name]]), 0)
    form <- wm("form_epa"); std_form <- stdm("form_epa")
    trend <- form - std_form; trend[!is.na(trend) & abs(trend) < 1e-12] <- 0
    raw <- data.frame(form = form, trend = trend, residual = wm("resid"), elo_change = wm("elo_delta") * k)
    Z <- as.data.frame(lapply(raw, mb_zscore))
    combined <- mb_combine(Z, weights[[wk]])
    games_in <- vapply(idx, length, 0L)
    carried <- vapply(idx, function(i) sum(H$season[i] < season), 0L)
    pbp_missing <- vapply(idx, function(i) sum(is.na(H$form_epa[i])), 0L)
    reason <- ifelse(games_in < k, sprintf("fewer than %d games available", k),
              ifelse(pbp_missing > 0, sprintf("%d game(s) in this window have no play-by-play EPA yet", pbp_missing),
              ifelse(is.na(combined), "a weighted component could not be standardised", NA_character_)))
    ranked <- games_in >= k & !is.na(combined)
    combined[!ranked] <- NA_real_
    df <- data.frame(team = teams, games_in_window = games_in, carried_games = carried, ranked = ranked,
                     combined = combined, rank = mb_rank_desc(combined), null_reason = reason, stringsAsFactors = FALSE)
    df <- cbind(df, setNames(raw, paste0("raw_", names(raw))), setNames(Z, paste0("z_", names(Z))))
    for (n in c("adj_off_epa", "adj_def_epa", "form_margin", "off_epa", "def_epa", "off_sr", "def_sr",
                "pass_epa", "rush_epa", "pass_epa_def", "rush_epa_def")) df[[paste0("w_", n)]] <- wm(n)
    df$std_adj_off_epa <- stdm("adj_off_epa"); df$std_adj_def_epa <- stdm("adj_def_epa")
    df$std_form <- std_form
    out[[wk]] <- list(df = df, idx = setNames(idx, teams))
  }
  out
}

# ------------------------------------------------------------------------------
# 5. Flags (raw values; significant is always FALSE - owner decision 4)
# ------------------------------------------------------------------------------
MB_FLAG_DEFS <- list(
  list(key = "one_score", group = "luck", label = "One-score record vs expected",
       value = "win share in one-score games (ties half) minus 0.5",
       test = sprintf("binomial z: wins in one-score games (|margin| <= %d, ties half) vs 0.5", MOMENTUM_BOARD_ONE_SCORE_MARGIN)),
  list(key = "pythagorean", group = "luck", label = "Pythagorean vs actual",
       value = sprintf("win share minus the Pythagorean share of the window's points (exponent %.2f)", MOMENTUM_BOARD_PYTH_EXPONENT),
       test = "binomial z: wins vs the Pythagorean expectation"),
  list(key = "fumble_recovery", group = "luck", label = "Fumble-recovery rate",
       value = "share of all fumbles in the team's games recovered by the team, minus 0.5",
       test = "binomial z: recoveries vs 0.5"),
  list(key = "opp_fg_pct", group = "luck", label = "Opponent field-goal %",
       value = "opponents' field-goal make rate minus the league rate this season",
       test = "binomial z: opponents' field goals made vs the league rate"),
  list(key = "turnover_margin", group = "luck", label = "Turnover margin vs season level",
       value = "window takeaways minus giveaways per game, minus the team's season-to-date level per game",
       test = "Poisson z: window turnover margin vs the team's season level (variance 2 x league giveaways per game)"),
  list(key = "blowout_skew", group = "luck", label = "Blowout skew",
       value = sprintf("share of games decided by %d+ points minus the league share this season", MOMENTUM_BOARD_BLOWOUT_MARGIN),
       test = "binomial z: blowouts vs the league share"),
  list(key = "opponent_strength", group = "context", label = "Opponent strength",
       value = "mean opponent pregame Elo minus the league mean pregame Elo of the game's season",
       test = "none: context only"),
  list(key = "home_share", group = "context", label = "Home share",
       value = "share of the window's games as the listed home team", test = "none: context only"),
  list(key = "rest_bye", group = "context", label = "Rest / bye advantage",
       value = "mean rest-day difference, team minus opponent (games after each team's first of its season)",
       test = "none: context only"),
  list(key = "starting_qb_change", group = "availability", label = "Starting-QB change",
       value = "number of games in the window (this season) whose starting QB differs from the team's previous game",
       test = "none: context only until the forward log (#224) reports"),
  list(key = "key_players_missing", group = "availability", label = "Key players missing",
       value = "share of key player-games in the window (this season) missed: listed Out or no snaps recorded",
       test = "none: raw value only"))

mb_flag <- function(key, value = NA_real_, n = NA_integer_, statistic = NA_real_, null_reason = NULL,
                    detail = NULL, digits = 4) {
  d <- MB_FLAG_DEFS[[which(vapply(MB_FLAG_DEFS, `[[`, "", "key") == key)]]
  f <- list(key = key, group = d$group, value = mb_round(value, digits), n = if (is.na(n)) NA_integer_ else as.integer(n),
            statistic = mb_round(statistic, 2), significant = FALSE)
  if (is.na(f$value)) f$null_reason <- null_reason %||% "not computable for this window"
  if (!is.null(detail)) f$detail <- detail
  f
}

mb_binom_z <- function(x, n, p0) if (is.na(n) || n < 1 || p0 <= 0 || p0 >= 1) NA_real_ else (x - n * p0) / sqrt(n * p0 * (1 - p0))

mb_norm_name <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^a-z ]", "", x)
  x <- gsub("\\b(jr|sr|ii|iii|iv|v)\\b", "", x)
  trimws(gsub("\\s+", " ", x))
}

# Key players at a snapshot (design decision 6): for each team and position, the player with
# the highest snap share over the team's games this season (share per game = the larger of
# offense and defense snap %, 0 for a game without a snap row). Special-teams-only positions
# excluded. Ties broken by player id.
mb_key_players <- function(snaps, team_games) {
  if (is.null(snaps) || !nrow(snaps) || !length(team_games)) return(NULL)
  s <- snaps[snaps$game_id %in% team_games, , drop = FALSE]
  s <- s[!(s$position %in% MOMENTUM_BOARD_KEY_EXCLUDED_POSITIONS), , drop = FALSE]
  if (!nrow(s)) return(NULL)
  s$share <- pmax(ifelse(is.na(s$offense_pct), 0, s$offense_pct), ifelse(is.na(s$defense_pct), 0, s$defense_pct))
  s <- s[s$share > 0, , drop = FALSE]
  if (!nrow(s)) return(NULL)
  tot <- aggregate(share ~ pfr_player_id, data = s, sum)
  tot$share <- tot$share / length(team_games)
  pos <- aggregate(list(n = rep(1L, nrow(s))), list(pfr_player_id = s$pfr_player_id, position = s$position), sum)
  pos <- pos[order(pos$pfr_player_id, -pos$n, pos$position), ]; pos <- pos[!duplicated(pos$pfr_player_id), ]
  tot$position <- pos$position[match(tot$pfr_player_id, pos$pfr_player_id)]
  tot$player <- s$player[match(tot$pfr_player_id, s$pfr_player_id)]
  tot <- tot[order(tot$position, -tot$share, tot$pfr_player_id), ]
  tot[!duplicated(tot$position), c("pfr_player_id", "player", "position", "share")]
}

mb_key_players_missing <- function(H, idx, season, inputs) {
  cur <- idx[H$season[idx] == season]
  if (!length(cur)) return(mb_flag("key_players_missing", null_reason = "no games from this season in the window (snap counts cover this season only)"))
  snaps <- inputs$snaps; inj <- inputs$injuries
  if (is.null(snaps) || !nrow(snaps)) return(mb_flag("key_players_missing", null_reason = "snap count cache (CACHE_SNAP_COUNTS) unavailable"))
  if (is.null(inj) || !nrow(inj)) return(mb_flag("key_players_missing", null_reason = "injury report cache (CACHE_INJURY_DATA) unavailable"))
  team <- H$team[cur[1]]
  ts <- snaps[snaps$team == team, , drop = FALSE]
  covered <- H$game_id[cur] %in% ts$game_id
  if (!all(covered)) return(mb_flag("key_players_missing",
    null_reason = sprintf("snap counts not yet available for %d of the window's %d games this season", sum(!covered), length(cur))))
  season_games <- H$game_id[H$team == team & H$season == season & H$game_date <= max(H$game_date[cur])]
  key <- mb_key_players(ts, season_games)
  if (is.null(key) || !nrow(key)) return(mb_flag("key_players_missing", null_reason = "no key players could be identified from snap counts"))
  played <- unique(paste(ts$pfr_player_id, ts$game_id)[(ifelse(is.na(ts$offense_snaps), 0, ts$offense_snaps) +
                                                          ifelse(is.na(ts$defense_snaps), 0, ts$defense_snaps)) > 0])
  it <- inj[inj$team == team & inj$status %in% "Out", , drop = FALSE]
  out_keys <- unique(paste(mb_norm_name(it$player_name), it$week))
  missed <- 0L; total <- 0L; out_listed <- 0L
  per_player <- list()
  for (j in seq_len(nrow(key))) {
    pm <- 0L
    for (g in cur) {
      total <- total + 1L
      no_snaps <- !(paste(key$pfr_player_id[j], H$game_id[g]) %in% played)
      is_out <- paste(mb_norm_name(key$player[j]), H$week[g]) %in% out_keys
      if (is_out) out_listed <- out_listed + 1L
      if (no_snaps || is_out) { missed <- missed + 1L; pm <- pm + 1L }
    }
    if (pm > 0) per_player[[length(per_player) + 1L]] <- list(player = key$player[j], position = key$position[j], games_missed = pm)
  }
  mb_flag("key_players_missing", value = missed / total, n = total,
          detail = list(key_players = nrow(key), games = length(cur), player_games_missed = missed,
                        listed_out = out_listed, carried_games_excluded = length(idx) - length(cur),
                        missed_players = per_player))
}

mb_flags <- function(H, idx, season, week, team, inputs, league) {
  g <- H[idx, , drop = FALSE]
  n <- nrow(g)
  fl <- list()
  # one-score record
  one <- abs(g$margin) <= MOMENTUM_BOARD_ONE_SCORE_MARGIN
  if (sum(one)) {
    w <- sum(g$win[one]); m <- sum(one)
    fl[[1]] <- mb_flag("one_score", w / m - 0.5, m, mb_binom_z(w, m, 0.5), detail = list(wins = w, games = m))
  } else fl[[1]] <- mb_flag("one_score", n = 0L, null_reason = "no one-score games in this window")
  # Pythagorean
  pf <- sum(g$pts); pa <- sum(g$opp_pts)
  if (n && (pf + pa) > 0) {
    e <- MOMENTUM_BOARD_PYTH_EXPONENT; py <- pf^e / (pf^e + pa^e); w <- sum(g$win)
    fl[[2]] <- mb_flag("pythagorean", w / n - py, n, mb_binom_z(w, n, py), detail = list(win_share = round(w / n, 4), pythagorean_share = round(py, 4)))
  } else fl[[2]] <- mb_flag("pythagorean", null_reason = "no points scored in this window")
  # play-by-play detail flags: this season's games with the full play-by-play only
  gd <- g[g$season == season & g$detail_found, , drop = FALSE]
  excl <- n - nrow(gd)
  det_reason <- if (nrow(gd) == 0) "no games in this window with this season's full play-by-play (CACHE_DNA_PBP)" else NULL
  if (is.null(det_reason) && sum(gd$fumbles_game) > 0) {
    fu <- sum(gd$fumbles_game); rc <- sum(gd$fum_recovered)
    fl[[3]] <- mb_flag("fumble_recovery", rc / fu - 0.5, fu, mb_binom_z(rc, fu, 0.5), detail = list(recovered = rc, fumbles = fu, games = nrow(gd), games_excluded = excl))
  } else fl[[3]] <- mb_flag("fumble_recovery", n = if (is.null(det_reason)) 0L else NA_integer_, null_reason = det_reason %||% "no fumbles in this window's games")
  if (is.null(det_reason) && sum(gd$opp_fg_att) > 0 && !is.na(league$fg)) {
    at <- sum(gd$opp_fg_att); md <- sum(gd$opp_fg_made)
    fl[[4]] <- mb_flag("opp_fg_pct", md / at - league$fg, at, mb_binom_z(md, at, league$fg), detail = list(made = md, attempts = at, league_rate = round(league$fg, 4), games_excluded = excl))
  } else fl[[4]] <- mb_flag("opp_fg_pct", n = if (is.null(det_reason)) 0L else NA_integer_, null_reason = det_reason %||% "no opponent field-goal attempts in this window")
  if (is.null(det_reason) && !is.na(league$giveaways) && league$giveaways > 0) {
    tom <- gd$takeaways - gd$giveaways
    st <- H[H$team == team & H$season == season & H$week <= week & H$detail_found, , drop = FALSE]
    lvl <- mean(st$takeaways - st$giveaways)
    m <- nrow(gd)
    fl[[5]] <- mb_flag("turnover_margin", mean(tom) - lvl, m, (sum(tom) - m * lvl) / sqrt(2 * league$giveaways * m),
                       detail = list(window_per_game = round(mean(tom), 4), season_per_game = round(lvl, 4), games_excluded = excl))
  } else fl[[5]] <- mb_flag("turnover_margin", null_reason = det_reason %||% "league giveaway rate unavailable")
  if (n && !is.na(league$blowout)) {
    b <- sum(abs(g$margin) >= MOMENTUM_BOARD_BLOWOUT_MARGIN)
    fl[[6]] <- mb_flag("blowout_skew", b / n - league$blowout, n, mb_binom_z(b, n, league$blowout), detail = list(blowouts = b, league_share = round(league$blowout, 4)))
  } else fl[[6]] <- mb_flag("blowout_skew", null_reason = "league blowout share unavailable")
  # context
  lm <- as.numeric(league$opp_elo_mean[as.character(g$season)])
  fl[[7]] <- mb_flag("opponent_strength", mean(g$opp_elo_pre - lm), n, digits = 1,
                     detail = list(mean_opponent_elo = round(mean(g$opp_elo_pre), 1)))
  fl[[8]] <- mb_flag("home_share", mean(g$home), n, detail = list(home_games = sum(g$home), neutral_site_games = sum(g$neutral)))
  rd <- g$rest_in_season - g$opp_rest
  if (any(!is.na(rd))) fl[[9]] <- mb_flag("rest_bye", mean(rd, na.rm = TRUE), sum(!is.na(rd)), digits = 2)
  else fl[[9]] <- mb_flag("rest_bye", n = 0L, null_reason = "no game in this window after both teams' first game of the season")
  # starting-QB change (this season's games; the change at a game compares with the previous game)
  gq <- g[g$season == season, , drop = FALSE]
  if (!nrow(gq)) {
    fl[[10]] <- mb_flag("starting_qb_change", null_reason = "no games from this season in the window")
  } else if (any(is.na(gq$qb_id))) {
    fl[[10]] <- mb_flag("starting_qb_change", null_reason = sprintf("starting QB unknown for %d of the window's games this season (no dropbacks in CACHE_DNA_PBP)", sum(is.na(gq$qb_id))))
  } else {
    comp <- !is.na(gq$qb_change)
    last <- H[H$team == team & H$season == season & H$week <= week, , drop = FALSE]
    last <- last[nrow(last), ]
    st <- aggregate(list(starts = rep(1L, nrow(gq))), list(qb_id = gq$qb_id, qb_name = gq$qb_name), sum)
    st <- st[order(-st$starts, st$qb_name), ]
    fl[[10]] <- mb_flag("starting_qb_change", sum(gq$qb_change[comp]), sum(comp), digits = 0,
                        detail = list(current_starter = list(id = last$qb_id, name = last$qb_name),
                                      changed_in_latest_game = if (is.na(last$qb_change)) NA else isTRUE(last$qb_change),
                                      starters_in_window = lapply(seq_len(nrow(st)), function(i) list(id = st$qb_id[i], name = st$qb_name[i], starts = st$starts[i])),
                                      carried_games_excluded = n - nrow(gq)))
  }
  fl[[11]] <- mb_key_players_missing(H, idx, season, inputs)
  fl
}

mb_league_refs <- function(H, season, week) {
  cur <- H[H$season == season & H$week <= week, , drop = FALSE]
  if (!nrow(cur)) cur <- H[H$season == season - 1L, , drop = FALSE]
  cd <- cur[cur$detail_found, , drop = FALSE]
  rows <- mb_snapshot_rows(H, season, week)
  list(fg = if (nrow(cd) && sum(cd$opp_fg_att) > 0) sum(cd$opp_fg_made) / sum(cd$opp_fg_att) else NA_real_,
       giveaways = if (nrow(cd)) mean(cd$giveaways) else NA_real_,
       blowout = if (nrow(cur)) mean(abs(cur$margin) >= MOMENTUM_BOARD_BLOWOUT_MARGIN) else NA_real_,
       opp_elo_mean = tapply(H$opp_elo_pre[rows], H$season[rows], mean))
}

# ------------------------------------------------------------------------------
# 6. Rank history (append only, one completed week at a time)
# ------------------------------------------------------------------------------
mb_read_history <- function(path) {
  if (!file.exists(path)) return(NULL)
  x <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("NA", ""))
  if (!identical(names(x), MB_HISTORY_COLUMNS)) stop("build_momentum_board: rank history header does not match; refusing to append to ", path)
  x
}

# Append the snapshot of `week` unless that week is already in the file. Returns TRUE when
# rows were written. Never rewrites the file.
mb_append_history <- function(path, rows) {
  old <- mb_read_history(path)
  if (!nrow(rows)) return(FALSE)
  if (!is.null(old) && any(old$season == rows$season[1] & old$week == rows$week[1])) return(FALSE)
  rows <- rows[, MB_HISTORY_COLUMNS]
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- file(path, open = if (is.null(old)) "wb" else "ab")
  on.exit(close(con), add = TRUE)
  utils::write.table(rows, con, sep = ",", row.names = FALSE, col.names = is.null(old), quote = c(3, 5), eol = "\n", na = "NA")
  TRUE
}

# ------------------------------------------------------------------------------
# 7. Payload
# ------------------------------------------------------------------------------
# Latest week W such that every regular-season game of weeks 1..W has a score (0 if none).
mb_completed_week <- function(sched, season) {
  s <- sched[sched$season == season & sched$game_type == "REG", , drop = FALSE]
  if (!nrow(s)) return(0L)
  wk <- sort(unique(s$week)); done <- 0L
  for (w in wk) { g <- s[s$week == w, ]; if (all(!is.na(g$home_score) & !is.na(g$away_score))) done <- as.integer(w) else break }
  done
}

mb_build_payload <- function(inputs, season = CURRENT_SEASON, now = Sys.time(), teams = names(NFL_TEAMS),
                             team_names = NFL_TEAMS, history_path = MOMENTUM_RANK_HISTORY, write_history = TRUE) {
  sched <- as.data.frame(inputs$schedules, stringsAsFactors = FALSE)
  sched$home_team <- mb_canon(sched$home_team); sched$away_team <- mb_canon(sched$away_team)
  sched$gameday <- as.Date(sched$gameday)
  elo <- mb_elo_games(sched, season)
  first_season <- season - 2L
  pbp <- inputs$pbp; pbp <- pbp[pbp$season >= first_season & pbp$season <= season, , drop = FALSE]
  H <- mb_team_games(sched, mb_pbp_epa(pbp), mb_pbp_detail(inputs$dna_pbp), elo, first_season, season)
  cur <- H[H$season == season, , drop = FALSE]
  through_week <- if (nrow(cur)) as.integer(max(cur$week)) else 0L
  through_date <- if (nrow(cur)) format(max(cur$game_date)) else format(max(H$game_date))
  complete_week <- mb_completed_week(sched, season)
  phase <- if (through_week == 0L) "preseason" else if (through_week < 3L) "early_season" else "in_season"

  snap <- mb_snapshot(H, season, through_week, teams)
  prev <- if (through_week >= 1L) mb_snapshot(H, season, through_week - 1L, teams) else NULL
  league <- mb_league_refs(H, season, through_week)

  # rank history: the latest completed week, if not written yet and every team is ranked
  hist_written <- FALSE; hist_note <- NULL
  if (complete_week >= 1L) {
    hs <- if (complete_week == through_week) snap else mb_snapshot(H, season, complete_week, teams)
    hd <- format(max(H$game_date[H$season == season & H$week <= complete_week]))
    rows <- do.call(rbind, lapply(names(hs), function(wk) { d <- hs[[wk]]$df
      data.frame(season = season, week = complete_week, through_date = hd, window = as.integer(wk), team = d$team,
                 rank = d$rank, combined_score = round(d$combined, 4), carried_games = d$carried_games,
                 reconstruction = FALSE, stringsAsFactors = FALSE) }))
    if (any(is.na(rows$rank))) {
      hist_note <- sprintf("week %d not written: some teams are unranked (data not complete yet)", complete_week)
    } else if (write_history) {
      hist_written <- mb_append_history(history_path, rows)
    }
  }
  hist <- mb_read_history(history_path)

  # Elo state per team at the snapshot (after its latest game) and a week earlier
  rows_now <- mb_snapshot_rows(H, season, through_week)
  last_row <- function(rows, t) { r <- rows[H$team[rows] == t]; if (length(r)) r[length(r)] else NA_integer_ }
  lr <- vapply(teams, function(t) last_row(rows_now, t), 0L)
  elo_now <- H$elo_post[lr]
  elo_rank <- mb_rank_desc(elo_now)
  rows_prev <- mb_snapshot_rows(H, season, through_week - 1L)
  lp <- vapply(teams, function(t) last_row(rows_prev, t), 0L)
  elo_prev <- ifelse(!is.na(lp) & H$season[lp] == season, H$elo_post[lp], NA_real_)
  elo_prev_rank <- mb_rank_desc(ifelse(is.na(lp), NA_real_, H$elo_post[lp]))

  # next opponent
  future <- sched[sched$season == season & sched$game_type == "REG" & (is.na(sched$home_score) | is.na(sched$away_score)), , drop = FALSE]
  future <- future[order(future$gameday, future$game_id), , drop = FALSE]
  next_of <- function(t, i) {
    f <- future[future$home_team == t | future$away_team == t, , drop = FALSE]
    if (!nrow(f)) return(list(game = NULL, null_reason = "no remaining regular-season game"))
    f <- f[1, ]; home <- f$home_team == t; opp <- if (home) f$away_team else f$home_team
    oi <- match(opp, teams)
    list(game = list(week = as.integer(f$week), date = format(f$gameday), opponent = opp, home = home,
                     opponent_elo = mb_round(if (is.na(oi)) NA else elo_now[oi], 1),
                     opponent_elo_rank = if (is.na(oi)) NA_integer_ else elo_rank[oi]), null_reason = NULL)
  }

  boards <- list()
  for (wk in names(snap)) {
    k <- as.integer(wk); d <- snap[[wk]]$df; idxs <- snap[[wk]]$idx
    pd <- if (!is.null(prev)) prev[[wk]]$df else NULL
    form_rank <- mb_rank_desc(ifelse(d$ranked, d$raw_form, NA))
    margin_rank <- mb_rank_desc(ifelse(d$ranked, d$w_form_margin, NA))
    rws <- lapply(seq_along(teams), function(i) {
      t <- teams[i]; idx <- idxs[[t]]
      ct <- H[H$team == t & H$season == season & H$week <= through_week, , drop = FALSE]
      rp <- if (!is.null(pd)) pd$rank[i] else NA_integer_
      rp_reason <- if (through_week < 2L) "no completed week before this one this season" else if (is.na(rp)) "not ranked a week earlier" else NA_character_
      if (is.na(rp) && is.na(rp_reason)) rp_reason <- "not ranked a week earlier"
      rc <- if (!is.na(rp) && !is.na(d$rank[i])) as.integer(rp - d$rank[i]) else NA_integer_
      wt <- MOMENTUM_BOARD_WEIGHTS[[wk]]
      nx <- next_of(t, i)
      ht <- if (!is.null(hist)) hist[hist$team == t & hist$window == k, , drop = FALSE] else NULL
      if (!is.null(ht)) ht <- ht[order(ht$season, ht$week), , drop = FALSE]
      ec <- if (length(idx)) sum(H$elo_delta[idx]) else NA_real_
      faced_season <- if (nrow(ct)) mean(ct$opp_elo_pre) else NA_real_
      list(
        team = t, team_name = unname(team_names[t]),
        games_played = nrow(ct),
        record = list(wins = sum(ct$margin > 0), losses = sum(ct$margin < 0), ties = sum(ct$margin == 0)),
        window = k, games_in_window = d$games_in_window[i],
        carried_games = d$carried_games[i],
        current_season_games_in_window = d$games_in_window[i] - d$carried_games[i],
        carried_from_season = if (d$carried_games[i] > 0) as.integer(season - 1L) else NA_integer_,
        ranked = d$ranked[i], rank = d$rank[i],
        rank_last_week = rp, rank_last_week_null_reason = if (is.na(rp)) rp_reason else NA_character_,
        rank_change_week = rc, rank_change_week_null_reason = if (is.na(rc)) (if (is.na(d$rank[i])) "not ranked" else rp_reason) else NA_character_,
        combined_score = list(
          value = mb_round(d$combined[i], 3), rank = d$rank[i],
          components = list(form_z = mb_round(d$z_form[i], 3), trend_z = mb_round(d$z_trend[i], 3),
                            residual_z = mb_round(d$z_residual[i], 3), elo_change_z = mb_round(d$z_elo_change[i], 3)),
          raw = list(form = mb_round(d$raw_form[i], 4), trend = mb_round(d$raw_trend[i], 4),
                     residual = mb_round(d$raw_residual[i], 2), elo_change = mb_round(d$raw_elo_change[i], 1)),
          weights = as.list(wt),
          null_reason = if (is.na(d$combined[i])) d$null_reason[i] else NA_character_),
        form = list(epa_per_play = mb_round(d$raw_form[i], 4), rank = form_rank[i],
                    season_to_date = mb_round(d$std_form[i], 4),
                    opponent_adjusted_margin = mb_round(d$w_form_margin[i], 2), opponent_adjusted_margin_rank = margin_rank[i]),
        epa_splits = list(
          offense_adjusted = mb_round(d$w_adj_off_epa[i], 4), defense_adjusted = mb_round(d$w_adj_def_epa[i], 4),
          offense_adjusted_change = mb_round(d$w_adj_off_epa[i] - d$std_adj_off_epa[i], 4),
          defense_adjusted_change = mb_round(d$w_adj_def_epa[i] - d$std_adj_def_epa[i], 4),
          offense = mb_round(d$w_off_epa[i], 4), defense = mb_round(d$w_def_epa[i], 4),
          pass_offense = mb_round(d$w_pass_epa[i], 4), rush_offense = mb_round(d$w_rush_epa[i], 4),
          pass_defense = mb_round(d$w_pass_epa_def[i], 4), rush_defense = mb_round(d$w_rush_epa_def[i], 4),
          success_offense = mb_round(d$w_off_sr[i], 4), success_defense = mb_round(d$w_def_sr[i], 4)),
        residual = list(per_game = mb_round(d$raw_residual[i], 2), basis = "margin minus production Elo expected margin"),
        elo = list(current = mb_round(elo_now[i], 1), rank = elo_rank[i],
                   change_in_window = mb_round(ec, 1),
                   change_since_last_week = mb_round(if (is.na(elo_prev[i])) NA else elo_now[i] - elo_prev[i], 1),
                   change_since_last_week_null_reason = if (is.na(elo_prev[i])) "no game before this week this season" else NA_character_,
                   rank_change_since_last_week = if (is.na(elo_prev_rank[i])) NA_integer_ else as.integer(elo_prev_rank[i] - elo_rank[i])),
        schedule_strength = list(faced_window = mb_round(mean(H$opp_elo_pre[idx]), 1), faced_season = mb_round(faced_season, 1),
                                 next_opponent = nx$game, next_opponent_null_reason = nx$null_reason %||% NA_character_),
        flags = mb_flags(H, idx, season, through_week, t, inputs, league),
        sparkline = lapply(seq_len(nrow(ct)), function(j) list(week = as.integer(ct$week[j]), game_id = ct$game_id[j],
                                                               opponent = ct$opp[j], form_epa = mb_round(ct$form_epa[j], 4))),
        sort_keys = list(combined_score = mb_round(d$combined[i], 3),
                         form_epa = if (d$ranked[i]) mb_round(d$raw_form[i], 4) else NA_real_,
                         opponent_adjusted_margin = if (d$ranked[i]) mb_round(d$w_form_margin[i], 2) else NA_real_,
                         trend = if (d$ranked[i]) mb_round(d$raw_trend[i], 4) else NA_real_,
                         residual = if (d$ranked[i]) mb_round(d$raw_residual[i], 2) else NA_real_,
                         elo_change = if (d$ranked[i]) mb_round(d$raw_elo_change[i], 1) else NA_real_,
                         elo_current = mb_round(elo_now[i], 1)),
        rank_history = if (is.null(ht) || !nrow(ht)) list() else lapply(seq_len(nrow(ht)), function(j) list(
          season = as.integer(ht$season[j]), week = as.integer(ht$week[j]), through_date = ht$through_date[j],
          rank = as.integer(ht$rank[j]), combined_score = ht$combined_score[j],
          carried_games = as.integer(ht$carried_games[j]), reconstruction = isTRUE(as.logical(ht$reconstruction[j]))))
      )
    })
    rws <- rws[order(ifelse(is.na(d$rank), .Machine$integer.max, d$rank), teams)]
    boards[[wk]] <- list(window = k, noisiest = k == MOMENTUM_BOARD_NOISIEST_WINDOW,
                         label = if (k == MOMENTUM_BOARD_NOISIEST_WINDOW) sprintf("Last %d games (noisiest)", k) else sprintf("Last %d games", k),
                         ranked_count = sum(d$ranked), team_count = length(teams),
                         carried_team_count = sum(d$carried_games > 0), rows = rws)
  }
  ranked_counts <- lapply(boards, `[[`, "ranked_count")
  need <- ceiling(0.8 * length(teams) - 1e-9)
  okw <- MOMENTUM_BOARD_WINDOWS[unlist(ranked_counts[as.character(MOMENTUM_BOARD_WINDOWS)]) >= need]
  default_window <- if (length(okw)) max(okw) else min(MOMENTUM_BOARD_WINDOWS)

  list(
    schema_version = MB_SCHEMA_VERSION,
    generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = as.integer(season), season_type = "REG",
    through_date = through_date, through_week = through_week,
    completed_week = complete_week, week_complete = complete_week == through_week,
    season_phase = phase,
    windows = as.integer(MOMENTUM_BOARD_WINDOWS), default_window = as.integer(default_window),
    ranked_counts = ranked_counts,
    sort_options = list(
      list(key = "combined_score", label = "Combined score", descending = TRUE),
      list(key = "form_epa", label = "Opponent-adjusted EPA/play", descending = TRUE),
      list(key = "opponent_adjusted_margin", label = "Opponent-adjusted margin", descending = TRUE),
      list(key = "trend", label = "Trend vs season to date", descending = TRUE),
      list(key = "residual", label = "Margin vs Elo expectation", descending = TRUE),
      list(key = "elo_change", label = "Elo change in window", descending = TRUE),
      list(key = "elo_current", label = "Current Elo", descending = TRUE)),
    boards = boards,
    methods = mb_methods(hist, hist_written, hist_note)
  )
}

mb_methods <- function(hist, hist_written, hist_note) {
  list(
    summary = paste("The board describes how teams have played recently. It is not a forecast: the rolling-window study",
                    "found that recent form adds nothing measurable beyond Elo. For every window, carry-over method and",
                    "weighting tested, the 95% interval of the gain over Elo includes zero. The board does not predict",
                    "results beyond what Elo already predicts."),
    predictive_beyond_elo = FALSE,
    source = list(study = "tools/rolling_window_study.R", report = "docs/research/rolling_window_study.md",
                  issue = 227L, merged_in = 228L, study_commit = MOMENTUM_BOARD_STUDY_COMMIT,
                  measures_study = "tools/momentum_measures_study.R", measures_study_issue = 221L,
                  measures_study_commit = MOMENTUM_BOARD_MEASURES_STUDY_COMMIT,
                  owner_settings = MOMENTUM_BOARD_SETTINGS_URL, board_issue = 226L),
    windows = list(sizes = as.integer(MOMENTUM_BOARD_WINDOWS), noisiest = MOMENTUM_BOARD_NOISIEST_WINDOW,
                   default_rule = "the longest window in which at least 80% of teams are ranked",
                   note = paste("6 and 9 games are the windows the study supports (next-game win and next-game margin).",
                                "3 games is the short recent-games view and the noisiest; the study does not support it predictively.")),
    carry_over = list(method = MOMENTUM_BOARD_CARRY_METHOD, keep = MOMENTUM_BOARD_REGRESS_KEEP,
                      definition = sprintf(paste("Windows run across the season boundary. Each carried game's value is pulled toward",
                                                 "the league average of its own season: value -> average + %.2f^(seasons back) x (value - average).",
                                                 "Every team is ranked from week 1. carried_games counts last season's games in each team's window."),
                                           MOMENTUM_BOARD_REGRESS_KEEP)),
    form = paste("Opponent-adjusted EPA per play, offense minus defense allowed: a game's offensive EPA/play minus the opponent's",
                 "mean EPA/play allowed over its earlier games this season (its previous season before its first game), and",
                 "likewise for defense. Regular season only; every play with an offense, a defense and EPA."),
    combined_score = list(
      components = list(form = "window mean of opponent-adjusted EPA/play",
                        trend = "form minus the season-to-date mean of form",
                        residual = "window mean of point margin minus the production Elo expected margin",
                        elo_change = "Elo change over the window (window mean of per-game Elo change x games)"),
      standardisation = sprintf(paste("Each component is z-scored across teams within the season-week (each team after its latest",
                                      "game that week); a component equal for every team is 0; at least %d teams needed."), MOMENTUM_BOARD_MIN_Z_TEAMS),
      formula = "sum over components of weight x z",
      weights = lapply(MOMENTUM_BOARD_WEIGHTS, as.list),
      weights_source = sprintf("Best held-out weights under mean_regress, rolling-window study Table 10, commit %s; set by the owner (%s).",
                               MOMENTUM_BOARD_STUDY_COMMIT, MOMENTUM_BOARD_SETTINGS_URL),
      flat_surface = paste("The score surface is flat: every weighting tested sits inside the best one's 95% interval, and the",
                           "NBA board's 0.7/0.1/0.1/0.1 was equally supported. No weighting predicts beyond Elo."),
      refit = "Never refit in the nightly build; re-evaluated each offseason by re-running the study in a pull request."),
    elo = list(model = "production walk-forward, tools/elo_model.R run_elo_walkforward()", k = ELO_K_FACTOR,
               home_advantage_elo = ELO_HCA_POINTS, points_per_margin_point = ELO_POINTS_PER_MARGIN_PT,
               season_carryover = ELO_SEASON_CARRYOVER, first_season = MODERN_ERA_START_SEASON,
               expected_margin = "(Elo - opponent Elo + home advantage x home sign) / points per margin point; pregame ratings"),
    flags = list(
      significance_shown = FALSE,
      significance_hidden_reason = sprintf(paste("No candidate flag reaches %d%% simulated detection of a plausible effect at 3, 6 or 9",
                                                 "games (rolling-window study Table 11), so no flag carries a significance badge at any",
                                                 "window. Raw values are shown; statistics are descriptive."), round(100 * MOMENTUM_BOARD_DETECTION_POWER)),
      context_only = c("opponent_strength", "home_share", "rest_bye", "starting_qb_change"),
      definitions = lapply(MB_FLAG_DEFS, function(d) d[c("key", "group", "label", "value", "test")]),
      detail_source = paste("Fumble recovery, opponent field-goal %, turnover margin and the starting QB use this season's full",
                            "play-by-play (CACHE_DNA_PBP); a window's carried games are excluded from them and counted in detail."),
      key_players_missing = paste("Key players: for each team and position, the player with the top snap share over the team's games",
                                  "this season (share per game = the larger of offense and defense snap %; kickers, punters and long",
                                  "snappers excluded). A key player-game is missed when the player is listed Out on that week's injury",
                                  "report (CACHE_INJURY_DATA, matched by name) or records no offensive or defensive snaps",
                                  "(CACHE_SNAP_COUNTS). Value = missed key player-games / key player-games in the window's games this",
                                  "season. Raw value only, no badge. Null with a reason when snap counts or injury reports do not cover the window."),
      starting_qb_change = paste("The starting QB is the passer with the most dropbacks (passer id, or the rusher id on scrambles; ties by",
                                 "id), as in the momentum measures study (#221). Context only until the QB-change forward log (#224) reports.")),
    rank_history = list(file = "data/history/momentum_rank_history.csv",
                        starts = if (!is.null(hist) && nrow(hist)) sprintf("%d week %d", hist$season[1], hist$week[1]) else NA_character_,
                        reconstruction = FALSE, written_this_run = hist_written,
                        note = hist_note %||% NA_character_,
                        rule = paste("One row per team per window per completed week (every regular-season game of that week and",
                                     "earlier weeks has a score), appended once and never rewritten. History starts at launch; no backfill.",
                                     "rank_last_week is recomputed from games through the previous week."))
  )
}

mb_json_text <- function(payload) {
  as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = FALSE, na = "null", null = "null", digits = NA))
}

# ------------------------------------------------------------------------------
# 8. Inputs and entry point
# ------------------------------------------------------------------------------
mb_load_inputs <- function() {
  rd <- function(p, required = TRUE) {
    if (!file.exists(p)) { if (required) stop("build_momentum_board: missing input ", p); return(NULL) }
    as.data.frame(readRDS(p), stringsAsFactors = FALSE)
  }
  snaps <- rd(CACHE_SNAP_COUNTS, FALSE)
  if (!is.null(snaps)) { snaps$team <- mb_canon(snaps$team); if ("game_type" %in% names(snaps)) snaps <- snaps[snaps$game_type %in% "REG", , drop = FALSE] }
  inj <- rd(CACHE_INJURY_DATA, FALSE)
  if (!is.null(inj)) inj$team <- mb_canon(inj$team)
  list(schedules = rd(CACHE_SCHEDULES), pbp = rd(CACHE_PBP), dna_pbp = rd(CACHE_DNA_PBP, FALSE),
       snaps = snaps, injuries = inj)
}

run_build_momentum_board <- function(season = CURRENT_SEASON, output_json = WEB_JSON_MOMENTUM_BOARD,
                                     history_path = MOMENTUM_RANK_HISTORY, now = Sys.time(), inputs = NULL) {
  inputs <- inputs %||% mb_load_inputs()
  payload <- mb_build_payload(inputs, season = season, now = now, history_path = history_path)
  dir.create(dirname(output_json), showWarnings = FALSE, recursive = TRUE)
  writeLines(mb_json_text(payload), output_json, useBytes = TRUE)
  .mb_say("info", sprintf("build_momentum_board: wrote %s (season %d through week %d; ranked %s; history written: %s)",
                          output_json, season, payload$through_week,
                          paste(sprintf("%s:%d", names(payload$ranked_counts), unlist(payload$ranked_counts)), collapse = " "),
                          payload$methods$rank_history$written_this_run))
  invisible(payload)
}

if (identical(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]) |> basename(), "build_momentum_board.R")) {
  run_build_momentum_board()
}
