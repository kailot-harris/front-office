# ==============================================================================
# build_momentum_dataset.R - NBA Momentum Board data layer (NBA_analytics#237)
#
# Writes web/public/data/momentum_board.json (consumed by the /momentum page,
# NBA_analytics#238), cache/elo_daily_<season>.rds (the persisted Elo series,
# via R/elo.R), cache/momentum_team_game_panel_<season>.rds (the team-game panel)
# and appends the weekly rank snapshot to data/history/momentum_rank_history.csv.
#
# INPUTS (all real caches; a missing required input stops the stage):
#   cache/matchups_team_box_<season>.rds   team box scores (scores, FGA/FGM, 3PA/3PM,
#                                          FTA/FTM, OREB/DREB, total turnovers)
#   cache/matchups_schedule_<season>.rds   schedule (neutral site, next-week games)
#   cache/prediction_accuracy_log.rds      logged pregame model margins (residual)
#   cache/nba_pbp_<season>.rds             play-by-play (team clutch)
#   cache/nba_shots_<season>.rds           shot locations (expected eFG, rim/mid/3PT)
#   cache/nba_player_box_<season>.rds      did-not-play rows and minutes (flags 10, 11)
#   cache/nba_player_box_<season - 1>.rds  previous season's results: Elo carry-over
#                                          seed and the out-of-sample check (optional;
#                                          without it Elo starts flat at 1500 and the
#                                          methods block says so)
#   cache/nba_shots_<season - 1>.rds       pooled into the expected-FG baseline the way
#                                          shot_quality_engine.R pools it (optional)
# Not used, by design: cache/travel_fatigue_metrics.rds (empty since #155; travel
# comes from fatigue_travel_engine.R::calculate_travel_fatigue on the schedule, the
# way build_matchups_dataset.R calls it) and cache/injury_data_cache.rds (a current
# snapshot with no history, so it cannot describe a past window).
#
# DEFINITIONS
#   Possessions   per team: FGA - OREB + TOV + 0.44 * FTA (TOV = total turnovers,
#                 team turnovers included); a game's possessions are the mean of
#                 the two teams' estimates, so both sides share one denominator.
#                 The team box has no possessions column (#237 research).
#   Ratings       ORtg = 100 * points / possessions, DRtg = 100 * points allowed /
#                 possessions, NetRtg = ORtg - DRtg, each aggregated over the
#                 window's games (sum of points over sum of possessions).
#   Change        window value minus the team's value over its season games BEFORE
#                 the window (never a season that contains the window). Null, with
#                 null_reason "too few games before this window", when the team has
#                 fewer than BASELINE_MIN_GAMES (5) earlier games. Applies to rating
#                 changes, the four-factor drivers and the combined score's trend.
#   Windows       5, 10 and ROLLING_WINDOW_SIZE (18) most recent games. A team with
#                 fewer games than the window shows its values over the games it
#                 has, with ranked = false and no rank in any sort. Default window =
#                 the longest of 18, 10, 5 in which >= 80% of teams are ranked.
#   Residual      actual minus logged pregame margin, team perspective, averaged
#                 over the window's games that have a RESOLVED LOGGED_PREGAME log
#                 row with a non-missing predicted_margin. Nothing is back-filled:
#                 games without a logged margin are skipped and counted out of
#                 residual_games_in_window.
#   Elo           R/elo.R (one shared implementation; rules in that file).
#
# Set NBA_SKIP_STAGE_AUTORUN=1 to source this file for its definitions only.
# ==============================================================================

.MOMENTUM_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f) && grepl("build_momentum_dataset\\.R$", f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

if (!exists("CACHE_DIR") || !exists("WEB_JSON_MOMENTUM_BOARD")) {
  source(file.path(.MOMENTUM_DIR, "config.R"), local = TRUE)
}
source(file.path(.MOMENTUM_DIR, "R", "elo.R"), local = TRUE)
source(file.path(.MOMENTUM_DIR, "R", "momentum_windows.R"), local = TRUE)

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
# 5, 10 and ROLLING_WINDOW_SIZE; shared with tools/log_momentum_forward.R.
MOMENTUM_WINDOWS <- momentum_windows(ROLLING_WINDOW_SIZE)
# Home-court points, same source of truth as build_matchups_dataset.R
# (prediction_accuracy_logger.R: hca <- 2.40).
MOMENTUM_HCA_POINTS <- 2.40
PYTHAG_EXPONENT <- 14          # NBA Pythagorean exponent (Morey: 13.91)
Z_CRITICAL <- 1.96             # two-sided 5% (one-sided for flags 10 and 11)
EB_PRIOR_WEIGHT <- 15          # web/lib/shotChartUtils.ts M_PRIOR_WEIGHT
MIN_BINOMIAL_N <- 4            # shotChartUtils.ts minAttempts: below this z is not computed
RESIDUAL_MIN_SHARE <- 0.6      # residual sort needs ceiling(0.6 * window) logged games
CLOSE_GAME_MARGIN <- 3
RIM_MAX_FT <- 4
KEY_PLAYER_MIN_SHARE <- 0.10   # share of team minutes in games played (~24 mpg)
KEY_PLAYER_MIN_GAMES <- 3L
NEXT_WEEK_DAYS <- 7L
VALIDATION_HORIZON <- 5L       # games after date d used as the validation target
# "Change" baseline: the team's season games BEFORE the window. Below this many
# earlier games the change (ratings, drivers, trend component) is null.
BASELINE_MIN_GAMES <- 5L
BASELINE_NULL_REASON <- "too few games before this window"
# Default window: the longest window in which at least this share of teams is ranked.
DEFAULT_WINDOW_MIN_SHARE <- 0.8
# Combined momentum score weights over cross-sectional z-scores (see
# validate_combined_weights() and the PR for the out-of-sample evidence). The
# owner reviews these before merge.
# Grid result (2025-26, step 0.1, train = first half of dates): form alone has the
# best train and test correlation in every window; trend and Elo change add less,
# and the 2026-27 residual check is too short to support more than a small weight.
# Form carries most of the weight; trend, residual and Elo change keep 0.1 each so
# the score still reflects change, not only level. Owner to review.
COMBINED_WEIGHTS <- c(form = 0.7, trend = 0.1, residual = 0.1, elo = 0.1)

ESPN_ABBR_FIXUPS_MOMENTUM <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                               NO = "NOP", WSH = "WAS")
NON_NBA_TEAMS <- c("EAST", "WEST", "USA", "WORLD", "STARS", "STRIPES", "OWN", "GLOBAL", "RISING")

canon_team <- function(x) {
  x <- as.character(x)
  hit <- !is.na(x) & x %in% names(ESPN_ABBR_FIXUPS_MOMENTUM)
  x[hit] <- unname(ESPN_ABBR_FIXUPS_MOMENTUM[x[hit]])
  x
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

# ------------------------------------------------------------------------------
# Core math (unit-tested in tests/test_momentum_dataset.R)
# ------------------------------------------------------------------------------
estimate_possessions <- function(fga, oreb, tov, fta) fga - oreb + tov + 0.44 * fta

# Rolling sum over the last w elements ending at each position (NA-free input).
roll_sum <- function(x, w) {
  cs <- cumsum(c(0, x))
  k <- seq_along(x)
  cs[k + 1L] - cs[pmax(0L, k - w) + 1L]
}

# Binomial z against a baseline rate, the machinery web/lib/shotChartUtils.ts uses
# for shot zones: z = (k/n - p0) / sqrt(p0 (1 - p0) / n). NA below MIN_BINOMIAL_N.
binomial_z <- function(k, n, p0, min_n = MIN_BINOMIAL_N) {
  ok <- !is.na(n) & n >= min_n & !is.na(p0) & p0 > 0 & p0 < 1 & !is.na(k)
  out <- rep(NA_real_, length(n))
  out[ok] <- (k[ok] / n[ok] - p0[ok]) / sqrt(p0[ok] * (1 - p0[ok]) / n[ok])
  out
}

# Empirical Bayes posterior rate (shotChartUtils.ts): (k + M p0) / (n + M).
eb_shrink <- function(k, n, p0, m = EB_PRIOR_WEIGHT) (k + m * p0) / (n + m)

is_significant <- function(z, one_sided_high = FALSE) {
  if (is.null(z) || is.na(z)) return(FALSE)
  if (one_sided_high) z >= Z_CRITICAL else abs(z) >= Z_CRITICAL
}

pythag_win_pct <- function(pf, pa, exponent = PYTHAG_EXPONENT) {
  ifelse(pf + pa > 0, pf^exponent / (pf^exponent + pa^exponent), NA_real_)
}

# The residual filter: RESOLVED, LOGGED_PREGAME and a logged predicted margin.
# Nothing else qualifies and nothing is filled (#237 research comment).
residual_eligible_log <- function(log) {
  log[log$status %in% "RESOLVED" &
        log$log_source %in% "LOGGED_PREGAME" &
        !is.na(suppressWarnings(as.numeric(log$predicted_margin))), , drop = FALSE]
}

# Window ranking: only teams with a full window are ranked (rank 1 = best).
rank_ranked <- function(value, ranked, descending = TRUE) {
  out <- rep(NA_integer_, length(value))
  ok <- ranked & !is.na(value)
  if (any(ok)) {
    v <- if (descending) -value[ok] else value[ok]
    out[ok] <- as.integer(rank(v, ties.method = "min"))
  }
  out
}

# Default window: the longest window in which at least ceiling(min_share * teams)
# teams have a full window (are ranked); the shortest window when none qualifies.
default_window_rule_text <- function(min_share = DEFAULT_WINDOW_MIN_SHARE, n_teams = 30L) {
  sprintf("The longest of %s games in which at least %.0f%% of teams (%s) are ranked (have played at least that many games); %d once most teams reach it. If no window qualifies, the shortest window.",
          paste(sort(MOMENTUM_WINDOWS, decreasing = TRUE), collapse = ", "), 100 * min_share,
          sprintf("%d of %d", as.integer(ceiling(min_share * n_teams - 1e-9)), as.integer(n_teams)),
          max(MOMENTUM_WINDOWS))
}
choose_default_window <- function(games_by_team, windows = MOMENTUM_WINDOWS,
                                  min_share = DEFAULT_WINDOW_MIN_SHARE) {
  need <- ceiling(min_share * length(games_by_team) - 1e-9)
  counts <- vapply(windows, function(w) sum(games_by_team >= w), numeric(1))
  ok <- windows[counts >= need]
  as.integer(if (length(ok)) max(ok) else min(windows))
}

# ------------------------------------------------------------------------------
# Loading helpers
# ------------------------------------------------------------------------------
read_required <- function(path, what) {
  if (!file.exists(path)) stop(sprintf("Missing %s input: %s", what, path), call. = FALSE)
  as.data.frame(readRDS(path), stringsAsFactors = FALSE)
}
read_optional <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(as.data.frame(readRDS(path), stringsAsFactors = FALSE), error = function(e) NULL)
}

# Reuse definitions from a stage script without running the stage: evaluate only
# the named top-level assignments. shot_quality_engine.R runs its whole pipeline
# (hoopR fetch, cache writes) when sourced, so it cannot be sourced here.
load_definitions <- function(file, names) {
  env <- new.env(parent = globalenv())
  for (e in parse(file)) {
    if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && as.character(e[[2]]) %in% names) {
      eval(e, env)
    }
  }
  missing <- setdiff(names, ls(env))
  if (length(missing)) stop(sprintf("%s no longer defines: %s", basename(file), paste(missing, collapse = ", ")))
  env
}

# Source a stage script for its definitions with its auto-run switched off.
source_definitions_only <- function(file) {
  old <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  on.exit(if (is.na(old)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN") else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old))
  env <- new.env(parent = globalenv())
  sys.source(file, envir = env)
  env
}

# ------------------------------------------------------------------------------
# 1. Team-game panel
# ------------------------------------------------------------------------------
# Normalised team-game rows: one per team per game.
normalise_team_box <- function(tb) {
  data.frame(
    game_id = as.character(tb$game_id),
    game_date = as.Date(tb$game_date),
    team = canon_team(tb$team_abbreviation),
    team_name = as.character(tb$team_short_display_name),
    team_id = as.character(tb$team_id),
    opp = canon_team(tb$opponent_team_abbreviation),
    home = tb$team_home_away == "home",
    pts = as.numeric(tb$team_score),
    opp_pts = as.numeric(tb$opponent_team_score),
    fga = as.numeric(tb$field_goals_attempted), fgm = as.numeric(tb$field_goals_made),
    fg3a = as.numeric(tb$three_point_field_goals_attempted),
    fg3m = as.numeric(tb$three_point_field_goals_made),
    fta = as.numeric(tb$free_throws_attempted), ftm = as.numeric(tb$free_throws_made),
    oreb = as.numeric(tb$offensive_rebounds), dreb = as.numeric(tb$defensive_rebounds),
    tov = as.numeric(tb$total_turnovers),
    stringsAsFactors = FALSE
  )
}

# Same shape from a player box (used for the previous season, which has no
# team-box cache). Player rows carry no team turnovers, so TOV here is the sum of
# player turnovers; this table feeds the Elo seed (scores only) and the
# out-of-sample check, never a published figure.
team_box_from_player_box <- function(pb, season_types = 2L) {
  pb <- pb[pb$season_type %in% season_types & !(pb$team_abbreviation %in% NON_NBA_TEAMS), , drop = FALSE]
  num <- function(x) { x <- suppressWarnings(as.numeric(x)); ifelse(is.na(x), 0, x) }
  g <- pb %>%
    group_by(game_id, game_date, team_abbreviation, team_short_display_name, team_id,
             opponent_team_abbreviation, home_away) %>%
    summarise(pts = first(as.numeric(team_score)), opp_pts = first(as.numeric(opponent_team_score)),
              fga = sum(num(field_goals_attempted)), fgm = sum(num(field_goals_made)),
              fg3a = sum(num(three_point_field_goals_attempted)), fg3m = sum(num(three_point_field_goals_made)),
              fta = sum(num(free_throws_attempted)), ftm = sum(num(free_throws_made)),
              oreb = sum(num(offensive_rebounds)), dreb = sum(num(defensive_rebounds)),
              tov = sum(num(turnovers)), .groups = "drop")
  data.frame(game_id = as.character(g$game_id), game_date = as.Date(g$game_date),
             team = canon_team(g$team_abbreviation), team_name = g$team_short_display_name,
             team_id = as.character(g$team_id), opp = canon_team(g$opponent_team_abbreviation),
             home = g$home_away == "home", pts = g$pts, opp_pts = g$opp_pts,
             fga = g$fga, fgm = g$fgm, fg3a = g$fg3a, fg3m = g$fg3m, fta = g$fta, ftm = g$ftm,
             oreb = g$oreb, dreb = g$dreb, tov = g$tov, stringsAsFactors = FALSE)
}

build_team_game_panel <- function(rows, neutral_ids = character(0)) {
  rows <- rows[!is.na(rows$pts) & !is.na(rows$opp_pts), , drop = FALSE]
  # Keep only games with both sides present.
  both <- names(which(table(rows$game_id) == 2L))
  rows <- rows[rows$game_id %in% both, , drop = FALSE]
  opp_cols <- c("fga", "fgm", "fg3a", "fg3m", "fta", "ftm", "oreb", "dreb", "tov")
  o <- rows[, c("game_id", "team", opp_cols)]
  names(o) <- c("game_id", "opp", paste0("opp_", opp_cols))
  p <- merge(rows, o, by = c("game_id", "opp"))
  p$neutral <- p$game_id %in% neutral_ids
  p$poss_team <- estimate_possessions(p$fga, p$oreb, p$tov, p$fta)
  p$poss_opp <- estimate_possessions(p$opp_fga, p$opp_oreb, p$opp_tov, p$opp_fta)
  p$poss <- (p$poss_team + p$poss_opp) / 2
  p$margin <- p$pts - p$opp_pts
  p$win <- p$margin > 0
  p$ortg <- 100 * p$pts / p$poss
  p$drtg <- 100 * p$opp_pts / p$poss
  p$net <- p$ortg - p$drtg
  # Four factors, for and against.
  p$efg <- (p$fgm + 0.5 * p$fg3m) / p$fga
  p$opp_efg <- (p$opp_fgm + 0.5 * p$opp_fg3m) / p$opp_fga
  p$tov_pct <- p$tov / (p$fga + 0.44 * p$fta + p$tov)
  p$opp_tov_pct <- p$opp_tov / (p$opp_fga + 0.44 * p$opp_fta + p$opp_tov)
  p$oreb_pct <- p$oreb / (p$oreb + p$opp_dreb)
  p$dreb_pct <- p$dreb / (p$dreb + p$opp_oreb)
  p$ft_rate <- p$fta / p$fga
  p$opp_ft_rate <- p$opp_fta / p$opp_fga
  # Shot-opportunity differential: scoring attempts (FGA + 0.44 FTA) minus the opponent's.
  p$shot_opp_diff <- (p$fga + 0.44 * p$fta) - (p$opp_fga + 0.44 * p$opp_fta)
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  p$game_index <- ave(seq_len(nrow(p)), p$team, FUN = seq_along)
  rownames(p) <- NULL
  p
}

# Rest, back-to-back, travel and altitude via fatigue_travel_engine.R, the way
# build_matchups_dataset.R calls it: previous venue and day gap per team, days_rest
# 0 = back-to-back, season opener = rested at the venue (no drag). Neutral-site
# games have no arena in ARENA_DB, so their travel stays NA (never a guess).
attach_schedule_context <- function(p) {
  if (!exists("calculate_travel_fatigue", mode = "function")) {
    source(file.path(.MOMENTUM_DIR, "fatigue_travel_engine.R"))
  }
  p$venue <- ifelse(p$home, p$team, p$opp)
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  n <- nrow(p)
  p$rest_days <- NA_integer_; p$back_to_back <- FALSE
  p$travel_miles <- NA_real_; p$altitude_ft <- NA_real_; p$fatigue_drag <- NA_real_
  for (i in seq_len(n)) {
    first <- i == 1L || p$team[i] != p$team[i - 1L]
    if (p$neutral[i]) next
    if (first) {
      p$fatigue_drag[i] <- 0; p$travel_miles[i] <- 0
      p$altitude_ft[i] <- calculate_travel_fatigue(p$venue[i], p$venue[i])$destination_elevation
      next
    }
    gap <- as.integer(p$game_date[i] - p$game_date[i - 1L])
    days_rest <- max(0L, gap - 1L)
    origin <- if (p$neutral[i - 1L]) NA_character_ else p$venue[i - 1L]
    p$rest_days[i] <- days_rest
    p$back_to_back[i] <- days_rest == 0L
    if (is.na(origin)) next
    fm <- calculate_travel_fatigue(p$venue[i], origin, days_rest = days_rest,
                                   is_back_to_back = days_rest == 0L)
    p$travel_miles[i] <- as.numeric(fm$travel_miles)
    p$altitude_ft[i] <- as.numeric(fm$destination_elevation)
    p$fatigue_drag[i] <- as.numeric(fm$fatigue_drag_pts)
  }
  o <- p[, c("game_id", "team", "rest_days", "fatigue_drag")]
  names(o) <- c("game_id", "opp", "opp_rest_days", "opp_fatigue_drag")
  p <- merge(p, o, by = c("game_id", "opp"), all.x = TRUE)
  p$rest_advantage <- !is.na(p$rest_days) & !is.na(p$opp_rest_days) & p$rest_days > p$opp_rest_days
  p$rest_known <- !is.na(p$rest_days) & !is.na(p$opp_rest_days)
  p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
}

# Elo pre/post per team-game from the shared series; pregame opponent rating.
attach_elo <- function(p, played) {
  h <- data.frame(game_id = as.character(played$game_id), team = played$home,
                  elo_pre = played$home_elo_pre, elo_post = played$home_elo_post,
                  opp_elo_pre = played$away_elo_pre, stringsAsFactors = FALSE)
  a <- data.frame(game_id = as.character(played$game_id), team = played$away,
                  elo_pre = played$away_elo_pre, elo_post = played$away_elo_post,
                  opp_elo_pre = played$home_elo_pre, stringsAsFactors = FALSE)
  p <- merge(p, rbind(h, a), by = c("game_id", "team"), all.x = TRUE)
  # Opponent-adjusted game net rating: the team's net rating with the opponent's
  # pregame Elo strength, home court and the fatigue differential taken out,
  # all converted to points per 100 possessions. NA when travel is unknown.
  per100 <- 100 / p$poss
  opp_strength <- (p$opp_elo_pre - ELO_MEAN) / ELO_POINTS_PER_MARGIN_POINT
  home_sign <- ifelse(p$neutral, 0, ifelse(p$home, 1, -1))
  p$adj_net <- p$net + per100 * (opp_strength - home_sign * MOMENTUM_HCA_POINTS +
                                   (p$fatigue_drag - p$opp_fatigue_drag))
  p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
}

elo_games_from_panel <- function(p) {
  # Exactly one row per game_id. Non-neutral: the home row. Neutral: the row
  # flagged home when exactly one is, else the alphabetically first team. The
  # stored neutral flag is kept so the Elo update applies no home advantage.
  n_home <- ave(as.integer(p$home %in% TRUE), p$game_id, FUN = sum)
  keep <- ifelse(p$neutral & n_home != 1L, p$team < p$opp, p$home %in% TRUE)
  h <- p[keep, , drop = FALSE]
  if (anyDuplicated(h$game_id)) stop("elo_games_from_panel: duplicate game_id in Elo games")
  data.frame(game_id = h$game_id, game_date = h$game_date, home = h$team, away = h$opp,
             home_pts = h$pts, away_pts = h$opp_pts, neutral = h$neutral, stringsAsFactors = FALSE)
}

# Logged pregame margins, joined by date + home/away short display names (the
# log's ids are repo hashes, not ESPN ids; build_matchups_dataset.R JOIN KEY).
attach_prediction_log <- function(p, pred_log, season_start, season_end) {
  pred_log$game_date <- as.Date(pred_log$game_date)
  in_season <- pred_log[pred_log$game_date >= season_start & pred_log$game_date <= season_end, , drop = FALSE]
  elig <- residual_eligible_log(in_season)
  elig$key <- paste(format(elig$game_date), elig$home_team, elig$away_team)
  elig <- elig[!duplicated(elig$key), , drop = FALSE]
  names_by_game <- p[, c("game_id", "home", "team_name")]
  hn <- setNames(names_by_game$team_name[names_by_game$home], names_by_game$game_id[names_by_game$home])
  an <- setNames(names_by_game$team_name[!names_by_game$home], names_by_game$game_id[!names_by_game$home])
  key <- paste(format(p$game_date), hn[p$game_id], an[p$game_id])
  pm_home <- suppressWarnings(as.numeric(elig$predicted_margin))[match(key, elig$key)]
  p$projected_margin <- ifelse(p$home, pm_home, -pm_home)
  p$model_basis <- ifelse(is.na(p$projected_margin), NA_character_, "logged_pregame_model")
  p$residual <- p$margin - p$projected_margin
  p$residual_eligible <- !is.na(p$residual)
  attr(p, "log_coverage") <- list(
    season_log_rows = nrow(in_season),
    resolved_logged = sum(in_season$status %in% "RESOLVED" & in_season$log_source %in% "LOGGED_PREGAME"),
    resolved_logged_with_margin = nrow(elig),
    panel_games = length(unique(p$game_id)),
    panel_games_with_margin = length(unique(p$game_id[p$residual_eligible])))
  p
}

# Per team-game shot profile and expected eFG from shot_quality_engine.R's own
# prepare_fga / build_xfg_baseline / calc_expected_shot_prob (never its synthetic
# generator). Baseline pooled over the current and previous season's shots.
shot_game_profile <- function(shots_current, shots_prior = NULL) {
  sq <- load_definitions(file.path(.MOMENTUM_DIR, "shot_quality_engine.R"),
                         c("ESPN_ABBR_FIXUPS", "NON_TEAM_ABBRS", "MIN_BIN_ATTEMPTS",
                           "calc_expected_shot_prob", "build_xfg_baseline", "prepare_fga"))
  fga_cur <- sq$prepare_fga(shots_current)
  pool <- if (!is.null(shots_prior)) dplyr::bind_rows(fga_cur, sq$prepare_fga(shots_prior)) else fga_cur
  baseline <- sq$build_xfg_baseline(pool)
  f <- fga_cur %>%
    left_join(baseline %>% select(dist_bin, is_corner_3, x_prob_bin), by = c("dist_bin", "is_corner_3")) %>%
    mutate(x_prob = coalesce(x_prob_bin, sq$calc_expected_shot_prob(dist, is_corner_3)))
  g <- f %>%
    mutate(team = canon_team(team), game_id = as.character(game_id),
           rim = val == 2 & dist <= RIM_MAX_FT, mid = val == 2 & dist > RIM_MAX_FT, three = val == 3) %>%
    group_by(game_id, team) %>%
    summarise(sh_fga = n(), sh_efg_made = sum(made * val / 2, na.rm = TRUE),
              sh_xefg = sum(x_prob * val / 2, na.rm = TRUE),
              rim_a = sum(rim), rim_m = sum(rim & made, na.rm = TRUE),
              mid_a = sum(mid), mid_m = sum(mid & made, na.rm = TRUE),
              three_a = sum(three), three_m = sum(three & made, na.rm = TRUE), .groups = "drop")
  attr(g, "baseline_fga") <- nrow(pool)
  as.data.frame(g)
}

attach_shots <- function(p, sg) {
  if (is.null(sg) || !nrow(sg)) return(p)
  p <- merge(p, sg, by = c("game_id", "team"), all.x = TRUE)
  o <- sg; names(o)[names(o) != "game_id"] <- paste0("opp_", names(o)[names(o) != "game_id"])
  names(o)[names(o) == "opp_team"] <- "opp"
  p <- merge(p, o, by = c("game_id", "opp"), all.x = TRUE)
  p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
}

# Team clutch per game, using build_clutch_dataset.R's clutch filter (4Q/OT,
# <= 5:00, pre-play margin <= 5). Points come from score changes on clutch plays;
# clutch possessions use the same estimator as the box score on clutch events.
team_clutch_by_game <- function(pbp, team_ids) {
  cl <- source_definitions_only(file.path(.MOMENTUM_DIR, "build_clutch_dataset.R"))
  c_pbp <- cl$filter_clutch_pbp(pbp)
  if (is.null(c_pbp) || !nrow(c_pbp)) return(NULL)
  c_pbp$home_pts <- pmax(0, suppressWarnings(as.numeric(c_pbp$home_score)) - c_pbp$pre_home_score)
  c_pbp$away_pts <- pmax(0, suppressWarnings(as.numeric(c_pbp$away_score)) - c_pbp$pre_away_score)
  tt <- as.character(c_pbp$type_text)
  is_ft <- grepl("Free Throw", tt, ignore.case = TRUE) & !grepl("Technical", tt, ignore.case = TRUE)
  is_fga <- c_pbp$shooting_play %in% TRUE & !grepl("Free Throw", tt, ignore.case = TRUE)
  is_oreb <- tt == "Offensive Rebound"
  is_tov <- grepl("Turnover", tt, ignore.case = TRUE)
  side <- ifelse(as.character(c_pbp$team_id) == as.character(c_pbp$home_team_id), "home",
                 ifelse(as.character(c_pbp$team_id) == as.character(c_pbp$away_team_id), "away", NA))
  c_pbp$poss_home <- ifelse(side %in% "home", is_fga - is_oreb + is_tov + 0.44 * is_ft, 0)
  c_pbp$poss_away <- ifelse(side %in% "away", is_fga - is_oreb + is_tov + 0.44 * is_ft, 0)
  g <- c_pbp %>%
    group_by(game_id, home_team_id, away_team_id) %>%
    summarise(h_pts = sum(home_pts, na.rm = TRUE), a_pts = sum(away_pts, na.rm = TRUE),
              h_poss = sum(poss_home), a_poss = sum(poss_away), .groups = "drop")
  poss <- (g$h_poss + g$a_poss) / 2
  out <- rbind(
    data.frame(game_id = as.character(g$game_id), team_id = as.character(g$home_team_id),
               clutch_pts = g$h_pts, clutch_opp_pts = g$a_pts, clutch_poss = poss),
    data.frame(game_id = as.character(g$game_id), team_id = as.character(g$away_team_id),
               clutch_pts = g$a_pts, clutch_opp_pts = g$h_pts, clutch_poss = poss))
  out$clutch_game <- TRUE
  out
}

attach_clutch <- function(p, cg, pbp_game_ids) {
  p$pbp_available <- p$game_id %in% as.character(pbp_game_ids)
  if (is.null(cg)) {
    p$clutch_game <- ifelse(p$pbp_available, FALSE, NA)
    p$clutch_pts <- p$clutch_opp_pts <- p$clutch_poss <- ifelse(p$pbp_available, 0, NA_real_)
    return(p)
  }
  p <- merge(p, cg, by = c("game_id", "team_id"), all.x = TRUE)
  # A game with play-by-play but no clutch plays is a real zero; without
  # play-by-play it stays NA.
  none <- p$pbp_available & is.na(p$clutch_game)
  p$clutch_game[none] <- FALSE
  for (v in c("clutch_pts", "clutch_opp_pts", "clutch_poss")) p[[v]][none] <- 0
  p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
}

# ------------------------------------------------------------------------------
# 2. Window states: one row per team per game, describing the window ending there
# ------------------------------------------------------------------------------
window_states <- function(p, w) {
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  out <- lapply(split(p, p$team), function(t) {
    k <- seq_len(nrow(t))
    n <- pmin(k, w)
    pts_w <- roll_sum(t$pts, w); opp_w <- roll_sum(t$opp_pts, w); poss_w <- roll_sum(t$poss, w)
    pts_s <- cumsum(t$pts); opp_s <- cumsum(t$opp_pts); poss_s <- cumsum(t$poss)
    adj_ok <- !is.na(t$adj_net)
    adj_n <- roll_sum(as.numeric(adj_ok), w)
    adj_sum <- roll_sum(ifelse(adj_ok, t$adj_net, 0), w)
    r_ok <- if ("residual_eligible" %in% names(t)) t$residual_eligible %in% TRUE else rep(FALSE, nrow(t))
    r_n <- roll_sum(as.numeric(r_ok), w)
    r_sum <- roll_sum(ifelse(r_ok, t$residual, 0), w)
    first_idx <- k - n + 1L
    # Baseline: the team's games before the window (games 1 .. first_idx - 1).
    before <- function(x) c(0, cumsum(x))[first_idx]
    n_before <- first_idx - 1L
    pts_b <- before(t$pts); opp_b <- before(t$opp_pts); poss_b <- before(t$poss)
    has_b <- n_before >= BASELINE_MIN_GAMES
    data.frame(
      team = t$team, game_date = t$game_date, game_index = k, window = w,
      games_in_window = n, ranked = k >= w,
      ortg = 100 * pts_w / poss_w, drtg = 100 * opp_w / poss_w,
      net = 100 * (pts_w - opp_w) / poss_w,
      ortg_season = 100 * pts_s / poss_s, drtg_season = 100 * opp_s / poss_s,
      net_season = 100 * (pts_s - opp_s) / poss_s,
      games_before = n_before, baseline_ok = has_b,
      ortg_before = ifelse(n_before > 0, 100 * pts_b / poss_b, NA_real_),
      drtg_before = ifelse(n_before > 0, 100 * opp_b / poss_b, NA_real_),
      net_before = ifelse(n_before > 0, 100 * (pts_b - opp_b) / poss_b, NA_real_),
      adj_form = ifelse(adj_n > 0, adj_sum / adj_n, NA_real_), adj_form_games = adj_n,
      residual = ifelse(r_n > 0, r_sum / r_n, NA_real_), residual_games = r_n,
      elo_change_window = t$elo_post - t$elo_pre[first_idx],
      elo_post = t$elo_post,
      stringsAsFactors = FALSE)
  })
  s <- do.call(rbind, out)
  # Change = window minus the games before the window; null below BASELINE_MIN_GAMES.
  s$net_change <- ifelse(s$baseline_ok, s$net - s$net_before, NA_real_)
  s$ortg_change <- ifelse(s$baseline_ok, s$ortg - s$ortg_before, NA_real_)
  s$drtg_change <- ifelse(s$baseline_ok, s$drtg - s$drtg_before, NA_real_)
  s$residual_ranked <- s$ranked & s$residual_games >= ceiling(RESIDUAL_MIN_SHARE * s$window)
  rownames(s) <- NULL
  s
}

# Each team's latest state on or before `date`.
states_as_of <- function(states, date) {
  s <- states[states$game_date <= as.Date(date), , drop = FALSE]
  s <- s[order(s$team, s$game_index), , drop = FALSE]
  s[!duplicated(s$team, fromLast = TRUE), , drop = FALSE]
}

COMPONENT_COLUMNS <- c(form = "adj_form", trend = "net_change", residual = "residual", elo = "elo_change_window")

# Cross-sectional z-scores among ranked teams; combined score = weighted sum.
# A component that is unavailable for a team (residual with too few logged games;
# trend with fewer than BASELINE_MIN_GAMES games before the window) leaves that
# team's combined score null and unranked; nothing is filled or imputed. The
# component's mean and sd come from the ranked teams that have it.
score_states <- function(st, weights = COMBINED_WEIGHTS) {
  for (nm in names(COMPONENT_COLUMNS)) {
    v <- st[[COMPONENT_COLUMNS[[nm]]]]
    elig <- st$ranked & !is.na(v)
    if (nm == "residual") { elig <- st$residual_ranked & !is.na(v); v[!st$residual_ranked] <- NA }
    mu <- if (sum(elig) >= 3) mean(v[elig]) else NA_real_
    sdv <- if (sum(elig) >= 3) stats::sd(v[elig]) else NA_real_
    # A component with no variation among the ranked teams that have it carries no
    # ranking information: its z is 0 for teams that have the value, not a guess.
    st[[paste0("z_", nm)]] <- if (is.na(sdv)) rep(NA_real_, nrow(st)) else
      if (sdv < 1e-9) ifelse(is.na(v), NA_real_, 0) else (v - mu) / sdv
  }
  w <- weights[names(COMPONENT_COLUMNS)]
  w[is.na(w)] <- 0
  zmat <- as.matrix(st[, paste0("z_", names(COMPONENT_COLUMNS))])
  used <- w > 0
  st$combined <- as.numeric(zmat[, used, drop = FALSE] %*% w[used])
  st$combined_rank <- rank_ranked(st$combined, st$ranked)
  st
}

# Why a scored state row has no combined score (NULL when it has one).
combined_null_reason <- function(s, w, weights = COMBINED_WEIGHTS) {
  if (!is.na(s$combined)) return(NULL)
  if (!isTRUE(s$ranked)) return(sprintf("fewer than %d games played (%d), so unranked in this window", w, s$games_in_window))
  r <- character(0)
  if (weights[["trend"]] > 0 && is.na(s$z_trend)) {
    r <- c(r, if (!isTRUE(s$baseline_ok))
      sprintf("trend component unavailable: %s (%d of %d needed)", BASELINE_NULL_REASON, s$games_before, BASELINE_MIN_GAMES)
      else "trend component unavailable: fewer than 3 ranked teams have enough games before this window")
  }
  if (weights[["residual"]] > 0 && is.na(s$z_residual)) {
    r <- c(r, if (!isTRUE(s$residual_ranked))
      sprintf("model residual has %d logged games in the window; needs %d", s$residual_games, ceiling(RESIDUAL_MIN_SHARE * w))
      else "model residual component unavailable: fewer than 3 ranked teams have enough logged games")
  }
  for (nm in c("form", "elo")) if (weights[[nm]] > 0 && is.na(s[[paste0("z_", nm)]])) r <- c(r, sprintf("%s component unavailable", nm))
  if (!length(r)) r <- "a component is unavailable"
  paste(r, collapse = "; ")
}

# Reasons for a null rank_7d_ago / rank_change_7d. `prev` is the team's scored state
# as of `prev_date` (NULL / zero rows when it had not played by then); `cur_rank`
# and `cur_reason` describe the current combined rank.
rank_change_null_reasons <- function(prev, prev_date, w, cur_rank, cur_reason) {
  r7 <- if (is.null(prev) || !nrow(prev)) sprintf("not ranked 7 days ago: no games played by %s", format(prev_date))
        else if (!is.na(prev$combined_rank)) NULL
        else sprintf("not ranked 7 days ago (as of %s): %s", format(prev_date), combined_null_reason(prev, w))
  rc <- if (is.na(cur_rank)) sprintf("no current rank: %s", cur_reason %||% "no combined score")
        else r7
  list(rank_7d_ago = r7, rank_change_7d = rc)
}

# ------------------------------------------------------------------------------
# 3. Out-of-sample validation of the combined score
# ------------------------------------------------------------------------------
# For every game date d with at least min_ranked ranked teams, score teams with
# games through d only, and compare to each team's mean margin over its next
# `horizon` games (strictly after d). Metric: Spearman rank correlation across
# teams per date, averaged over dates (an information coefficient), plus pooled.
validation_frame <- function(p, w, horizon = VALIDATION_HORIZON, min_ranked = 20L) {
  states <- window_states(p, w)
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  fut <- unlist(lapply(split(p, p$team), function(t) {
    m <- t$margin; n <- length(m)
    vapply(seq_len(n), function(k) if (k + horizon <= n) mean(m[(k + 1):(k + horizon)]) else NA_real_, numeric(1))
  }))
  states <- states[order(states$team, states$game_index), , drop = FALSE]
  states$future_margin <- fut
  dates <- sort(unique(p$game_date))
  rows <- lapply(dates, function(d) {
    st <- states_as_of(states, d)
    if (sum(st$ranked) < min_ranked) return(NULL)
    st <- score_states(st, COMBINED_WEIGHTS)
    st <- st[st$ranked & !is.na(st$future_margin), , drop = FALSE]
    if (nrow(st) < min_ranked) return(NULL)
    st$as_of <- d
    st
  })
  do.call(rbind, rows)
}

ic_summary <- function(vf, score) {
  ok <- !is.na(score) & !is.na(vf$future_margin)
  # Short samples return the same fields as a full one (NA figures), so
  # validation_report() can still build an entry that serialises them as null.
  if (sum(ok) < 10) return(list(mean_ic = NA_real_, ic_t = NA_real_, pooled_spearman = NA_real_,
                                n_dates = 0L, n_obs = sum(ok)))
  ics <- vapply(split(seq_len(nrow(vf))[ok], vf$as_of[ok]), function(ix) {
    if (length(ix) < 5) return(NA_real_)
    suppressWarnings(stats::cor(score[ix], vf$future_margin[ix], method = "spearman"))
  }, numeric(1))
  ics <- ics[!is.na(ics)]
  list(mean_ic = mean(ics), ic_t = if (length(ics) > 1) mean(ics) / (stats::sd(ics) / sqrt(length(ics))) else NA_real_,
       pooled_spearman = suppressWarnings(stats::cor(score[ok], vf$future_margin[ok], method = "spearman")),
       n_dates = length(ics), n_obs = sum(ok))
}

weighted_score <- function(vf, weights) {
  zc <- paste0("z_", names(weights))
  z <- as.matrix(vf[, zc, drop = FALSE])
  as.numeric(z %*% weights)
}

# Simplex grid over the named components (step 0.1).
weight_grid <- function(components, step = 0.1) {
  k <- length(components)
  vals <- seq(0, 1, by = step)
  g <- expand.grid(rep(list(vals), k - 1L))
  g <- g[rowSums(g) <= 1 + 1e-9, , drop = FALSE]
  g[[k]] <- 1 - rowSums(g)
  names(g) <- components
  round(g, 2)
}

# Grid-search on the first half of the dates (train), report on the second half
# (test). Used to choose COMBINED_WEIGHTS; the nightly build reports only the
# fixed weights' out-of-sample figures (validation_report()).
validate_combined_weights <- function(vf, components) {
  vf <- vf[stats::complete.cases(vf[, paste0("z_", components), drop = FALSE]), , drop = FALSE]
  dates <- sort(unique(vf$as_of))
  cut <- dates[ceiling(length(dates) / 2)]
  train <- vf[vf$as_of <= cut, , drop = FALSE]; test <- vf[vf$as_of > cut, , drop = FALSE]
  g <- weight_grid(components)
  res <- do.call(rbind, lapply(seq_len(nrow(g)), function(i) {
    w <- unlist(g[i, ])
    tr <- ic_summary(train, weighted_score(train, w)); te <- ic_summary(test, weighted_score(test, w))
    data.frame(g[i, , drop = FALSE], train_ic = tr$mean_ic, test_ic = te$mean_ic)
  }))
  res[order(-res$train_ic), , drop = FALSE]
}

validation_report <- function(vf, weights, label) {
  if (is.null(vf) || !nrow(vf)) {
    return(list(sample = label, available = FALSE, reason = "no dates with enough ranked teams and a full forward horizon"))
  }
  comps <- names(weights)[weights > 0]
  vf <- vf[stats::complete.cases(vf[, paste0("z_", comps), drop = FALSE]), , drop = FALSE]
  if (!nrow(vf)) return(list(sample = label, available = FALSE, reason = "no complete component rows"))
  combined <- ic_summary(vf, weighted_score(vf, weights[comps]))
  single <- lapply(comps, function(cn) ic_summary(vf, vf[[paste0("z_", cn)]])$mean_ic)
  names(single) <- comps
  eq <- setNames(rep(1 / length(comps), length(comps)), comps)
  list(sample = label, available = TRUE, components_used = comps,
       weights_used = as.list(round(weights[comps], 3)),
       mean_ic = round(combined$mean_ic, 4), ic_t_stat = round(combined$ic_t, 2),
       pooled_spearman = round(combined$pooled_spearman, 4),
       n_dates = combined$n_dates, n_team_dates = combined$n_obs,
       equal_weight_mean_ic = round(ic_summary(vf, weighted_score(vf, eq))$mean_ic, 4),
       single_component_mean_ic = lapply(single, function(x) round(x, 4)),
       date_range = c(format(min(vf$as_of)), format(max(vf$as_of))))
}

# ------------------------------------------------------------------------------
# 4. Flags
# ------------------------------------------------------------------------------
.flag_registry <- new.env(parent = emptyenv())
flag_obj <- function(id, key, group, label, test, value = NA_real_, statistic = NA_real_,
                     significant = FALSE, n = NA_integer_, null_reason = NULL, detail = NULL,
                     value_shrunk = NULL) {
  r <- function(x, d = 4) if (is.null(x) || length(x) == 0 || is.na(x)) NULL else round(as.numeric(x), d)
  .flag_registry[[as.character(id)]] <- list(id = id, key = key, group = group, label = label, test = test)
  out <- list(id = id, key = key, group = group,
              value = r(value), statistic = r(statistic, 3),
              significant = isTRUE(significant), n = if (is.na(n)) NULL else as.integer(n))
  if (!is.null(value_shrunk)) out$value_shrunk <- r(value_shrunk)
  if (is.null(out$value) || is.null(out$statistic)) {
    out$significant <- FALSE
    out$null_reason <- null_reason %||% (if (is.null(out$value)) "no qualifying games in the window" else
      sprintf("sample below the minimum for a test (n < %d)", MIN_BINOMIAL_N))
  }
  if (!is.null(detail)) out$detail <- detail
  out
}

# Pythagorean exponent for clutch-time points. The full-game exponent (14) assumes
# ~220 points a game; over a short segment the margin's dispersion shrinks with the
# square root of the points scored, so the exponent is scaled by
# sqrt(league clutch points per clutch game / league points per game).
clutch_pythag_exponent <- function(p_season) {
  cg <- p_season[p_season$clutch_game %in% TRUE, , drop = FALSE]
  if (!nrow(cg)) return(NA_real_)
  PYTHAG_EXPONENT * sqrt(mean(cg$clutch_pts + cg$clutch_opp_pts) / mean(p_season$pts + p_season$opp_pts))
}

league_context <- function(p_season) {
  list(
    fg3_pct = sum(p_season$fg3m) / sum(p_season$fg3a),
    ft_pct = sum(p_season$ftm) / sum(p_season$fta),
    rest_adv_rate = mean(p_season$rest_advantage[p_season$rest_known]),
    opp_elo_sd = stats::sd(p_season$opp_elo_pre, na.rm = TRUE),
    clutch_exponent = clutch_pythag_exponent(p_season)
  )
}

compute_flags <- function(wg, sg_season, lg, avail) {
  n <- nrow(wg)
  flags <- list()
  # 1. Shot quality vs actual eFG (team shooting luck).
  sh_ok <- !is.na(wg$sh_fga)
  fga <- sum(wg$sh_fga[sh_ok]); act <- sum(wg$sh_efg_made[sh_ok]); xef <- sum(wg$sh_xefg[sh_ok])
  p0 <- if (fga > 0) xef / fga else NA_real_
  z1 <- binomial_z(act, fga, p0)
  opp_ok <- !is.na(wg$opp_sh_fga)
  ofga <- sum(wg$opp_sh_fga[opp_ok]); oact <- sum(wg$opp_sh_efg_made[opp_ok]); oxef <- sum(wg$opp_sh_xefg[opp_ok])
  flags[[1]] <- flag_obj(1, "shot_quality_luck", "luck", "Shot quality vs actual eFG%",
    "binomial z of actual eFG% against location-expected eFG% (shot_quality_engine.R baseline), n = FGA",
    value = if (fga > 0) act / fga - p0 else NA, statistic = z1, significant = is_significant(z1), n = fga,
    value_shrunk = if (fga > 0) eb_shrink(act, fga, p0) - p0 else NULL,
    null_reason = if (fga == 0) "no shot-location rows for the window's games" else NULL,
    detail = list(actual_efg = if (fga > 0) round(act / fga, 4) else NULL,
                  expected_efg = if (fga > 0) round(p0, 4) else NULL,
                  games_with_shots = sum(sh_ok),
                  opponent_actual_efg = if (ofga > 0) round(oact / ofga, 4) else NULL,
                  opponent_expected_efg = if (ofga > 0) round(oxef / ofga, 4) else NULL,
                  opponent_z = if (ofga > 0) round(binomial_z(oact, ofga, oxef / ofga), 3) else NULL))
  # 2. Opponent 3P%.
  o3a <- sum(wg$opp_fg3a); o3m <- sum(wg$opp_fg3m)
  z2 <- binomial_z(o3m, o3a, lg$fg3_pct)
  flags[[2]] <- flag_obj(2, "opponent_three_pct", "luck", "Opponent 3P% vs league",
    "binomial z of opponents' 3P% against the league 3P% season to date, n = opponent 3PA",
    value = if (o3a > 0) o3m / o3a - lg$fg3_pct else NA, statistic = z2, significant = is_significant(z2), n = o3a,
    value_shrunk = if (o3a > 0) eb_shrink(o3m, o3a, lg$fg3_pct) - lg$fg3_pct else NULL,
    detail = list(opponent_three_pct = if (o3a > 0) round(o3m / o3a, 4) else NULL, league_three_pct = round(lg$fg3_pct, 4)))
  # 3. Pythagorean vs actual record.
  pyth <- pythag_win_pct(sum(wg$pts), sum(wg$opp_pts))
  w <- sum(wg$win)
  z3 <- binomial_z(w, n, pyth)
  flags[[3]] <- flag_obj(3, "pythagorean_gap", "luck", "Record vs Pythagorean expectation",
    sprintf("binomial z of win%% against Pythagorean win%% (exponent %d) from window points, n = games", PYTHAG_EXPONENT),
    value = w / n - pyth, statistic = z3, significant = is_significant(z3), n = n,
    detail = list(wins = w, losses = n - w, pythagorean_win_pct = round(pyth, 4)))
  # 4. Clutch record vs clutch net rating.
  cg <- wg[wg$clutch_game %in% TRUE, , drop = FALSE]
  if (any(is.na(wg$clutch_game))) {
    flags[[4]] <- flag_obj(4, "clutch_record_gap", "luck", "Clutch record vs clutch net rating",
      "binomial z of clutch-game win% against the Pythagorean expectation of clutch-time points",
      null_reason = "play-by-play missing for at least one window game")
  } else {
    cp <- pythag_win_pct(sum(cg$clutch_pts), sum(cg$clutch_opp_pts), exponent = lg$clutch_exponent)
    cw <- sum(cg$win)
    z4 <- binomial_z(cw, nrow(cg), cp)
    flags[[4]] <- flag_obj(4, "clutch_record_gap", "luck", "Clutch record vs clutch net rating",
      sprintf("binomial z of clutch-game win%% against the Pythagorean expectation of clutch-time points (exponent %.2f = 14 x sqrt(league clutch points per clutch game / points per game)), n = clutch games", lg$clutch_exponent),
      value = if (nrow(cg)) cw / nrow(cg) - cp else NA, statistic = z4, significant = is_significant(z4), n = nrow(cg),
      null_reason = if (!nrow(cg)) "no clutch games in the window" else if (is.na(cp)) "no clutch points scored" else NULL,
      detail = list(clutch_wins = cw, clutch_losses = nrow(cg) - cw,
                    clutch_net_rating = if (sum(cg$clutch_poss) > 0) round(100 * (sum(cg$clutch_pts) - sum(cg$clutch_opp_pts)) / sum(cg$clutch_poss), 2) else NULL))
  }
  # 5. Opponent FT%.
  ofta <- sum(wg$opp_fta); oftm <- sum(wg$opp_ftm)
  z5 <- binomial_z(oftm, ofta, lg$ft_pct)
  flags[[5]] <- flag_obj(5, "opponent_ft_pct", "luck", "Opponent FT% vs league",
    "binomial z of opponents' FT% against the league FT% season to date, n = opponent FTA",
    value = if (ofta > 0) oftm / ofta - lg$ft_pct else NA, statistic = z5, significant = is_significant(z5), n = ofta,
    value_shrunk = if (ofta > 0) eb_shrink(oftm, ofta, lg$ft_pct) - lg$ft_pct else NULL,
    detail = list(opponent_ft_pct = if (ofta > 0) round(oftm / ofta, 4) else NULL, league_ft_pct = round(lg$ft_pct, 4)))
  # 6. Close games (decided by <= 3).
  close <- wg[abs(wg$margin) <= CLOSE_GAME_MARGIN, , drop = FALSE]
  z6 <- binomial_z(sum(close$win), nrow(close), rep(0.5, 1))
  flags[[6]] <- flag_obj(6, "close_game_record", "luck", sprintf("Record in games decided by %d or fewer", CLOSE_GAME_MARGIN),
    "binomial z of close-game win% against 0.5, n = close games",
    value = if (nrow(close)) mean(close$win) - 0.5 else NA, statistic = z6, significant = is_significant(z6), n = nrow(close),
    null_reason = if (!nrow(close)) "no games decided by 3 or fewer in the window" else NULL,
    detail = list(close_wins = sum(close$win), close_losses = nrow(close) - sum(close$win)))
  # 7. Blowout skew: does the trend survive dropping the largest-margin game?
  season_margin <- avail$season_mean_margin
  sig_z <- function(m) if (length(m) >= 3 && stats::sd(m) > 0) (mean(m) - season_margin) / (stats::sd(m) / sqrt(length(m))) else NA_real_
  z_full <- sig_z(wg$margin)
  drop_ix <- which.max(abs(wg$margin))
  m_drop <- wg$margin[-drop_ix]
  z_drop <- sig_z(m_drop)
  skew <- !is.na(z_full) && !is.na(z_drop) && abs(z_full) >= Z_CRITICAL && abs(z_drop) < Z_CRITICAL
  flags[[7]] <- flag_obj(7, "blowout_skew", "luck", "Signal driven by one blowout",
    "z of the window's mean margin vs season-to-date mean margin, with and without the largest-|margin| game; significant when the full-window z clears 1.96 and the reduced one does not",
    value = mean(wg$margin) - mean(m_drop), statistic = z_drop, significant = skew, n = n,
    null_reason = if (n < 3) "fewer than 3 games in the window" else NULL,
    detail = list(z_full_window = if (is.na(z_full)) NULL else round(z_full, 3),
                  dropped_game_margin = wg$margin[drop_ix], dropped_game_date = format(wg$game_date[drop_ix])))
  # 8. Window opponent strength.
  oe <- wg$opp_elo_pre
  z8 <- if (n >= MIN_BINOMIAL_N && !is.na(lg$opp_elo_sd)) (mean(oe) - ELO_MEAN) / (lg$opp_elo_sd / sqrt(n)) else NA_real_
  flags[[8]] <- flag_obj(8, "opponent_strength", "context", "Window opponent strength",
    "z of the mean pregame opponent Elo against the league mean (1500), sd = league sd of pregame opponent Elo, n = games",
    value = (mean(oe) - ELO_MEAN) / ELO_POINTS_PER_MARGIN_POINT, statistic = z8, significant = is_significant(z8), n = n,
    detail = list(mean_opponent_elo = round(mean(oe), 1), unit = "margin points vs an average opponent"))
  # 9. Home and rest-advantage share.
  hz <- binomial_z(sum(wg$home & !wg$neutral), n, 0.5)
  rk <- wg[wg$rest_known, , drop = FALSE]
  rz <- binomial_z(sum(rk$rest_advantage), nrow(rk), lg$rest_adv_rate)
  flags[[9]] <- flag_obj(9, "home_rest_share", "context", "Share of home and rest-advantage games",
    "binomial z of home share against 0.5 and of rest-advantage share against the league rate; significant when either clears 1.96 (statistic = the larger |z|)",
    value = mean(wg$home & !wg$neutral),
    statistic = if (all(is.na(c(hz, rz)))) NA else c(hz, rz)[which.max(abs(c(ifelse(is.na(hz), 0, hz), ifelse(is.na(rz), 0, rz))))],
    significant = is_significant(hz) || is_significant(rz), n = n,
    detail = list(home_share = round(mean(wg$home & !wg$neutral), 4), home_z = if (is.na(hz)) NULL else round(hz, 3),
                  rest_advantage_share = if (nrow(rk)) round(mean(rk$rest_advantage), 4) else NULL,
                  rest_advantage_z = if (is.na(rz)) NULL else round(rz, 3),
                  league_rest_advantage_rate = round(lg$rest_adv_rate, 4), rest_known_games = nrow(rk)))
  flags[[10]] <- avail$flag10
  flags[[11]] <- avail$flag11
  flags
}

# Flags 10 and 11 from the player box (did_not_play rows and minutes), never the
# injury cache. Gate: every window game must have player-box rows for the team.
availability_flags <- function(pb_team_season, window_game_ids, lg_dnp_rate, tvd_z) {
  label10 <- "Key players missing"; label11 <- "Rotation minutes shift vs season"
  test10 <- sprintf("binomial z (one-sided) of key-player did-not-play rate in the window against the league key-player rate; key player = >= %.0f%% of team minutes in games played and >= %d games", 100 * KEY_PLAYER_MIN_SHARE, KEY_PLAYER_MIN_GAMES)
  test11 <- "total variation distance of window vs season minutes shares; z (one-sided) across teams with a full window"
  covered <- window_game_ids %in% unique(pb_team_season$game_id)
  if (!all(covered)) {
    reason <- sprintf("player box missing for %d of %d window games", sum(!covered), length(covered))
    return(list(flag10 = flag_obj(10, "key_players_missing", "availability", label10, test10, null_reason = reason),
                flag11 = flag_obj(11, "rotation_shift", "availability", label11, test11, null_reason = reason)))
  }
  pbw <- pb_team_season[pb_team_season$game_id %in% window_game_ids, , drop = FALSE]
  kp <- key_players(pb_team_season)
  kr <- pbw[pbw$athlete_id %in% kp$athlete_id, , drop = FALSE]
  missed <- sum(kr$did_not_play %in% TRUE)
  z10 <- binomial_z(missed, nrow(kr), lg_dnp_rate)
  per <- kr %>% group_by(athlete_id, athlete_display_name) %>%
    summarise(games_missed = sum(did_not_play %in% TRUE), games = n(),
              reasons = paste(sort(unique(reason[did_not_play %in% TRUE & !is.na(reason)])), collapse = "; "),
              .groups = "drop") %>%
    filter(games_missed > 0) %>% arrange(desc(games_missed))
  f10 <- flag_obj(10, "key_players_missing", "availability", label10, test10,
    value = if (nrow(kr)) missed / nrow(kr) else NA, statistic = z10,
    significant = is_significant(z10, one_sided_high = TRUE), n = nrow(kr),
    null_reason = if (!nrow(kr)) "no key players identified" else NULL,
    detail = list(key_players = nrow(kp), league_key_dnp_rate = round(lg_dnp_rate, 4),
                  source = "player box did_not_play rows",
                  players = lapply(seq_len(nrow(per)), function(i) list(
                    player = per$athlete_display_name[i], games_missed = per$games_missed[i],
                    games_in_window = per$games[i],
                    reasons = if (nzchar(per$reasons[i])) per$reasons[i] else NULL))))
  sh <- minutes_shift(pb_team_season, window_game_ids)
  f11 <- flag_obj(11, "rotation_shift", "availability", label11, test11,
    value = sh$tvd, statistic = tvd_z, significant = is_significant(tvd_z, one_sided_high = TRUE),
    n = length(window_game_ids),
    null_reason = if (is.na(tvd_z)) "no variation across teams (the window covers each ranked team's whole season)" else NULL,
    detail = list(top_shifts = sh$top))
  list(flag10 = f10, flag11 = f11)
}

key_players <- function(pb_team_season) {
  m <- pb_team_season
  m$min <- ifelse(is.na(m$minutes), 0, m$minutes)   # DNP rows carry NA minutes = 0 played
  team_min <- tapply(m$min, m$game_id, sum)
  played <- m[m$min > 0, , drop = FALSE]
  if (!nrow(played)) return(played[0, c("athlete_id"), drop = FALSE])
  agg <- played %>% group_by(athlete_id) %>%
    summarise(gp = n_distinct(game_id), mins = sum(min),
              team_mins = sum(team_min[as.character(unique(game_id))]), .groups = "drop")
  agg$share <- agg$mins / agg$team_mins
  agg[agg$gp >= KEY_PLAYER_MIN_GAMES & agg$share >= KEY_PLAYER_MIN_SHARE, , drop = FALSE]
}

minutes_shift <- function(pb_team_season, window_game_ids) {
  m <- pb_team_season
  m$min <- ifelse(is.na(m$minutes), 0, m$minutes)
  season <- tapply(m$min, m$athlete_id, sum); season <- season / sum(season)
  w <- m[m$game_id %in% window_game_ids, , drop = FALSE]
  win <- tapply(w$min, w$athlete_id, sum); win <- win / sum(win)
  ids <- union(names(season), names(win))
  s <- setNames(rep(0, length(ids)), ids); s[names(season)] <- season
  v <- setNames(rep(0, length(ids)), ids); v[names(win)] <- win
  d <- v - s
  nm <- setNames(m$athlete_display_name, m$athlete_id)
  top <- head(order(-abs(d)), 3)
  list(tvd = 0.5 * sum(abs(d)),
       top = lapply(top, function(i) list(player = unname(nm[ids[i]]), window_share = round(v[[i]], 4),
                                          season_share = round(s[[i]], 4))))
}

# ------------------------------------------------------------------------------
# 5. Drivers of the net-rating change
# ------------------------------------------------------------------------------
# Four-factor coefficients fitted by OLS on every team-game this season
# (game net rating on the eight factors), applied to the window-minus-season
# change in each factor. Shot-profile split of the offensive eFG term by
# shift-share over rim / mid / 3PT attempt shares and accuracy.
fit_four_factor_model <- function(p) {
  stats::lm(net ~ efg + opp_efg + tov_pct + opp_tov_pct + oreb_pct + dreb_pct + ft_rate + opp_ft_rate, data = p)
}

agg_factors <- function(g) {
  c(efg = (sum(g$fgm) + 0.5 * sum(g$fg3m)) / sum(g$fga),
    opp_efg = (sum(g$opp_fgm) + 0.5 * sum(g$opp_fg3m)) / sum(g$opp_fga),
    tov_pct = sum(g$tov) / sum(g$fga + 0.44 * g$fta + g$tov),
    opp_tov_pct = sum(g$opp_tov) / sum(g$opp_fga + 0.44 * g$opp_fta + g$opp_tov),
    oreb_pct = sum(g$oreb) / sum(g$oreb + g$opp_dreb),
    dreb_pct = sum(g$dreb) / sum(g$dreb + g$opp_oreb),
    ft_rate = sum(g$fta) / sum(g$fga), opp_ft_rate = sum(g$opp_fta) / sum(g$opp_fga))
}

DRIVER_UNIT <- "net rating points per 100 possessions (window minus the team's games before the window)"
DRIVER_KEYS <- c("efg_offense", "efg_defense", "tov_offense", "tov_defense", "oreb_offense",
                 "oreb_defense", "ft_rate_offense", "ft_rate_defense", "unexplained")

# Drivers of the change: window games `wg` against the team's games before the
# window `bg`. Fewer than BASELINE_MIN_GAMES earlier games: every driver is null
# with null_reason (no season-including fallback, nothing imputed).
window_drivers <- function(wg, bg, model, net_change) {
  if (nrow(bg) < BASELINE_MIN_GAMES || is.na(net_change)) {
    out <- c(list(unit = DRIVER_UNIT), setNames(rep(list(NULL), length(DRIVER_KEYS)), DRIVER_KEYS))
    out$games_before_window <- nrow(bg)
    out$null_reason <- BASELINE_NULL_REASON
    return(out)
  }
  out <- driver_decomposition(wg, bg, model, net_change)
  out$games_before_window <- nrow(bg)
  out
}

driver_decomposition <- function(wg, sg, model, net_change) {
  b <- stats::coef(model)
  fw <- agg_factors(wg); fs <- agg_factors(sg)
  contrib <- b[names(fw)] * (fw - fs)
  r2 <- function(x) round(unname(x), 2)
  out <- list(
    unit = DRIVER_UNIT,
    efg_offense = r2(contrib["efg"]), efg_defense = r2(contrib["opp_efg"]),
    tov_offense = r2(contrib["tov_pct"]), tov_defense = r2(contrib["opp_tov_pct"]),
    oreb_offense = r2(contrib["oreb_pct"]), oreb_defense = r2(contrib["dreb_pct"]),
    ft_rate_offense = r2(contrib["ft_rate"]), ft_rate_defense = r2(contrib["opp_ft_rate"]),
    unexplained = r2(net_change - sum(contrib)))
  if (all(!is.na(wg$sh_fga)) && all(!is.na(sg$sh_fga))) {
    zone <- function(g, z) c(a = sum(g[[paste0(z, "_a")]]), m = sum(g[[paste0(z, "_m")]]))
    tot_w <- sum(wg$sh_fga); tot_s <- sum(sg$sh_fga)
    val <- c(rim = 2, mid = 2, three = 3)
    sp <- list()
    for (z in names(val)) {
      zw <- zone(wg, z); zs <- zone(sg, z)
      share_w <- zw[["a"]] / tot_w; share_s <- zs[["a"]] / tot_s
      pps_w <- if (zw[["a"]] > 0) val[[z]] * zw[["m"]] / zw[["a"]] else NA
      pps_s <- if (zs[["a"]] > 0) val[[z]] * zs[["m"]] / zs[["a"]] else NA
      # eFG = sum(share * pps) / 2; scaled into net-rating points by the eFG coefficient.
      rate <- if (!is.na(pps_s)) b[["efg"]] * (share_w - share_s) * pps_s / 2 else NA
      acc <- if (!is.na(pps_w) && !is.na(pps_s)) b[["efg"]] * share_w * (pps_w - pps_s) / 2 else NA
      sp[[paste0(z, "_rate")]] <- if (is.na(rate)) NULL else round(rate, 2)
      sp[[paste0(z, "_accuracy")]] <- if (is.na(acc)) NULL else round(acc, 2)
      sp[[paste0(z, "_attempt_share")]] <- round(share_w, 4)
    }
    out$shot_profile <- sp
  } else {
    out$shot_profile <- NULL
    out$shot_profile_null_reason <- "shot-location rows missing for at least one game"
  }
  out
}

# ------------------------------------------------------------------------------
# 6. Rank history (weekly snapshot, history starts at launch)
# ------------------------------------------------------------------------------
week_start_of <- function(d) { d <- as.Date(d); d - ((as.integer(format(d, "%u")) - 1L)) }

update_rank_history <- function(path, through_date, snap) {
  wk <- week_start_of(through_date)
  new <- data.frame(week_start = format(wk), as_of = format(as.Date(through_date)),
                    window = snap$window, team = snap$team, rank = snap$rank,
                    combined_score = round(snap$combined, 4), reconstruction = FALSE,
                    stringsAsFactors = FALSE)
  old <- if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character") else NULL
  if (!is.null(old) && nrow(old)) {
    old <- old[old$week_start != format(wk), , drop = FALSE]
    old$window <- as.integer(old$window); old$rank <- as.integer(old$rank)
    old$combined_score <- as.numeric(old$combined_score); old$reconstruction <- as.logical(old$reconstruction)
    hist <- rbind(old, new)
  } else hist <- new
  hist <- hist[order(hist$week_start, hist$window, hist$team), , drop = FALSE]
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(hist, path, row.names = FALSE, na = "")
  hist
}

# ------------------------------------------------------------------------------
# 7. Main
# ------------------------------------------------------------------------------
build_momentum_dataset <- function(season = MATCHUPS_HOOPR_SEASON,
                                   cache_dir = CACHE_DIR,
                                   output_json = WEB_JSON_MOMENTUM_BOARD,
                                   history_path = MOMENTUM_RANK_HISTORY,
                                   now = Sys.time()) {
  cat(">>> [MOMENTUM] Building momentum board data layer...\n")
  cp <- function(f) file.path(cache_dir, f)
  tb <- read_required(cp(sprintf("matchups_team_box_%d.rds", season)), "team box")
  sched <- read_required(cp(sprintf("matchups_schedule_%d.rds", season)), "schedule")
  pred_log <- read_required(cp("prediction_accuracy_log.rds"), "prediction log")
  pbp <- read_required(cp(sprintf("nba_pbp_%d.rds", season)), "play-by-play")
  shots <- read_required(cp(sprintf("nba_shots_%d.rds", season)), "shots")
  pb <- read_required(cp(sprintf("nba_player_box_%d.rds", season)), "player box")
  pb_prior <- read_optional(cp(sprintf("nba_player_box_%d.rds", season - 1L)))
  shots_prior <- read_optional(cp(sprintf("nba_shots_%d.rds", season - 1L)))

  neutral_ids <- as.character(sched$game_id[sched$neutral_site %in% TRUE])
  p <- build_team_game_panel(normalise_team_box(tb), neutral_ids)
  through_date <- max(p$game_date)
  season_start <- min(as.Date(sched$game_date)); season_end <- max(as.Date(sched$game_date))
  cat(sprintf(">>> [MOMENTUM] Panel: %d team-games, %d games, %s .. %s\n",
              nrow(p), length(unique(p$game_id)), min(p$game_date), through_date))

  # Elo: prior season (regular season + play-in + playoffs) seeds the carry-over.
  prior_games <- NULL
  if (!is.null(pb_prior)) {
    pp <- build_team_game_panel(team_box_from_player_box(pb_prior, season_types = c(2L, 3L, 5L)))
    prior_games <- elo_games_from_panel(pp)
  }
  elo <- elo_build_season(elo_games_from_panel(p), prior_games, season = season,
                          end_date = through_date, teams = unique(p$team),
                          cache_path = cp(sprintf("elo_daily_%d.rds", season)))
  cat(sprintf(">>> [MOMENTUM] Elo series: %d rows, seed %s -> %s\n", nrow(elo$daily), elo$seed_method,
              cp(sprintf("elo_daily_%d.rds", season))))

  p <- attach_schedule_context(p)
  p <- attach_elo(p, elo$played)
  p <- attach_prediction_log(p, pred_log, season_start, season_end)
  log_cov <- attr(p, "log_coverage")
  sg <- shot_game_profile(shots, shots_prior)
  p <- attach_shots(p, sg)
  team_ids <- unique(p[, c("team_id", "team")])
  p <- attach_clutch(p, team_clutch_by_game(pbp, team_ids), unique(pbp$game_id))
  p <- p[order(p$team, p$game_date, p$game_id), , drop = FALSE]
  saveRDS(p, cp(sprintf("momentum_team_game_panel_%d.rds", season)))
  cat(sprintf(">>> [MOMENTUM] Residual coverage: %d of %d panel games carry a logged pregame margin\n",
              log_cov$panel_games_with_margin, log_cov$panel_games))

  # Season context as of through_date.
  lg <- league_context(p)
  ff_model <- fit_four_factor_model(p)
  rec <- p %>% group_by(team) %>% summarise(w = sum(win), l = sum(!win), gp = n(), .groups = "drop")
  win_pct <- setNames(rec$w / rec$gp, rec$team)
  p$opp_win_pct_now <- unname(win_pct[p$opp])
  team_names <- tapply(p$team_name, p$team, function(x) x[length(x)])
  elo_ch <- elo_changes(elo$daily, through_date)
  rownames(elo_ch) <- elo_ch$team

  # Player box for availability flags.
  pbx <- pb[!(pb$team_abbreviation %in% NON_NBA_TEAMS), , drop = FALSE]
  pbx$team <- canon_team(pbx$team_abbreviation)
  pbx$game_id <- as.character(pbx$game_id)
  pbx$minutes <- suppressWarnings(as.numeric(pbx$minutes))
  pbx <- pbx[pbx$game_id %in% p$game_id, , drop = FALSE]
  pb_by_team <- split(pbx, pbx$team)
  kp_rows <- do.call(rbind, lapply(names(pb_by_team), function(t) {
    k <- key_players(pb_by_team[[t]])
    pb_by_team[[t]][pb_by_team[[t]]$athlete_id %in% k$athlete_id, c("did_not_play"), drop = FALSE]
  }))
  lg_dnp <- mean(kp_rows$did_not_play %in% TRUE)
  pb_coverage <- mean(unique(p$game_id) %in% unique(pbx$game_id))

  # Next-week schedule.
  sch <- sched[!(sched$status_type_completed %in% TRUE) &
                 sched$home_short_display_name != "TBD" & sched$away_short_display_name != "TBD", , drop = FALSE]
  sch$game_date <- as.Date(sch$game_date)
  sch <- sch[sch$game_date > through_date & sch$game_date <= through_date + NEXT_WEEK_DAYS, , drop = FALSE]
  nw <- rbind(
    data.frame(team = canon_team(sch$home_abbreviation), opp = canon_team(sch$away_abbreviation),
               date = sch$game_date, home = TRUE, stringsAsFactors = FALSE),
    data.frame(team = canon_team(sch$away_abbreviation), opp = canon_team(sch$home_abbreviation),
               date = sch$game_date, home = FALSE, stringsAsFactors = FALSE))
  nw$opp_win_pct <- unname(win_pct[nw$opp])
  nw_mean <- tapply(nw$opp_win_pct, nw$team, mean)
  nw_rank <- setNames(as.integer(rank(-nw_mean, ties.method = "min")), names(nw_mean))
  faced_season <- tapply(p$opp_win_pct_now, p$team, mean)
  faced_rank <- setNames(as.integer(rank(-faced_season, ties.method = "min")), names(faced_season))

  # Validation (fixed weights, out of sample).
  cat(">>> [MOMENTUM] Validating combined-score weights out of sample...\n")
  val_current <- lapply(MOMENTUM_WINDOWS, function(w) {
    vf <- validation_frame(p, w)
    validation_report(vf, COMBINED_WEIGHTS, sprintf("%s, window %d", season_label(season), w))
  })
  val_prior <- list()
  if (!is.null(pb_prior)) {
    pp <- build_team_game_panel(team_box_from_player_box(pb_prior, season_types = 2L))
    pe <- elo_run_games(elo_games_from_panel(pp))
    pp$neutral <- FALSE
    pp <- attach_elo(attach_schedule_context(pp), pe)
    w_nores <- COMBINED_WEIGHTS[c("form", "trend", "elo")]
    w_nores <- w_nores / sum(w_nores)
    val_prior <- lapply(MOMENTUM_WINDOWS, function(w) {
      vf <- validation_frame(pp, w)
      r <- validation_report(vf, w_nores, sprintf("%s regular season, window %d", season_label(season - 1L), w))
      r$note <- "residual component excluded: 2025-26 has no LOGGED_PREGAME margins; remaining weights rescaled to sum to 1 for this check only"
      r
    })
  }

  # Default window (80% rule) from games played through through_date.
  games_by_team <- table(p$team)
  default_window <- choose_default_window(as.integer(games_by_team))
  cat(sprintf(">>> [MOMENTUM] Default window: %d (%s)\n", default_window,
              paste(sprintf("%d=%d", MOMENTUM_WINDOWS, vapply(MOMENTUM_WINDOWS, function(w) sum(games_by_team >= w), integer(1))), collapse = ", ")))

  hist_snap <- list()
  boards <- list()
  ranked_counts <- list()
  for (w in MOMENTUM_WINDOWS) {
    states <- window_states(p, w)
    st <- score_states(states_as_of(states, through_date))
    prev_date <- through_date - 7L
    prev <- score_states(states_as_of(states, prev_date))
    prev_rank <- setNames(prev$combined_rank, prev$team)
    # Rank within each sort (only ranked teams; residual also needs enough logged games).
    st$ortg_rank <- rank_ranked(st$ortg, st$ranked)
    st$drtg_rank <- rank_ranked(st$drtg, st$ranked, descending = FALSE)
    st$net_rank <- rank_ranked(st$net, st$ranked)
    st$net_change_rank <- rank_ranked(st$net_change, st$ranked)   # NA where the change is null
    st$residual_rank <- rank_ranked(st$residual, st$residual_ranked)
    st$form_rank <- rank_ranked(st$adj_form, st$ranked)
    st <- st[order(is.na(st$combined_rank), st$combined_rank, -st$games_in_window, st$team), , drop = FALSE]
    ranked_counts[[as.character(w)]] <- sum(st$ranked)
    in_hist <- st$ranked & !is.na(st$combined_rank)
    hist_snap[[length(hist_snap) + 1L]] <- data.frame(window = rep(w, sum(in_hist)), team = st$team[in_hist],
                                                      rank = st$combined_rank[in_hist], combined = st$combined[in_hist],
                                                      stringsAsFactors = FALSE)
    # Flag 11 variation: minutes-share shift of every team with a full window.
    tvd_all <- vapply(names(pb_by_team), function(t2) {
      tg2 <- p[p$team == t2, , drop = FALSE]
      if (nrow(tg2) < w) return(NA_real_)
      minutes_shift(pb_by_team[[t2]], tail(tg2$game_id, w))$tvd
    }, numeric(1))
    tvd_sd <- stats::sd(tvd_all, na.rm = TRUE)
    rows <- lapply(seq_len(nrow(st)), function(i) {
      s <- st[i, ]
      tm <- s$team
      tg <- p[p$team == tm, , drop = FALSE]
      wg <- tail(tg, s$games_in_window)
      # Sparkline: rolling window net rating after each of the last 10 games with a full window.
      ts <- states[states$team == tm & states$ranked, , drop = FALSE]
      ts <- tail(ts, 10)
      my_tvd <- minutes_shift(pb_by_team[[tm]], wg$game_id)$tvd
      tvd_z <- if (!is.na(tvd_sd) && tvd_sd > 1e-9) (my_tvd - mean(tvd_all, na.rm = TRUE)) / tvd_sd else NA_real_
      avail <- availability_flags(pb_by_team[[tm]], wg$game_id, lg_dnp, tvd_z)
      avail$season_mean_margin <- mean(tg$margin)
      flags <- compute_flags(wg, tg, lg, avail)
      ec <- elo_ch[tm, ]
      cw <- wg[wg$clutch_game %in% TRUE, , drop = FALSE]; cs <- tg[tg$clutch_game %in% TRUE, , drop = FALSE]
      clutch_block <- function(g, all_g) {
        if (any(is.na(all_g$clutch_game))) return(list(value = NULL, null_reason = "play-by-play missing for at least one game"))
        list(games = nrow(g), wins = sum(g$win), losses = sum(!g$win),
             points_for = sum(g$clutch_pts), points_against = sum(g$clutch_opp_pts),
             possessions = round(sum(g$clutch_poss), 1),
             net_rating = if (sum(g$clutch_poss) > 0) round(100 * (sum(g$clutch_pts) - sum(g$clutch_opp_pts)) / sum(g$clutch_poss), 2) else NULL)
      }
      faced_w <- mean(wg$opp_win_pct_now)
      nwt <- nw[nw$team == tm, , drop = FALSE]; nwt <- nwt[order(nwt$date), , drop = FALSE]
      combined_null <- combined_null_reason(s, w)
      rc_null <- rank_change_null_reasons(prev[prev$team == tm, , drop = FALSE], prev_date, w,
                                          s$combined_rank, combined_null)
      bg <- head(tg, nrow(tg) - s$games_in_window)   # the team's games before the window
      change_null <- if (isTRUE(s$baseline_ok)) NULL else BASELINE_NULL_REASON
      rating_block <- function(k, rank_col) list(
        value = r2(s[[k]]), rank = if (is.na(s[[rank_col]])) NULL else s[[rank_col]],
        season = r2(s[[paste0(k, "_season")]]), before_window = r2(s[[paste0(k, "_before")]]),
        games_before_window = s$games_before, change = r2(s[[paste0(k, "_change")]]),
        change_null_reason = change_null)
      r2 <- function(x, d = 2) if (is.null(x) || length(x) == 0 || is.na(x)) NULL else round(as.numeric(x), d)
      list(
        team = tm, team_name = unname(team_names[tm]),
        games_played = nrow(tg), record = list(wins = sum(tg$win), losses = sum(!tg$win)),
        window = w, games_in_window = s$games_in_window, ranked = isTRUE(s$ranked),
        rank = if (is.na(s$combined_rank)) NULL else s$combined_rank,
        rank_7d_ago = if (is.na(prev_rank[tm])) NULL else unname(prev_rank[tm]),
        rank_7d_ago_null_reason = if (is.na(prev_rank[tm])) rc_null$rank_7d_ago else NULL,
        rank_change_7d = if (is.na(s$combined_rank) || is.na(prev_rank[tm])) NULL else unname(prev_rank[tm] - s$combined_rank),
        rank_change_7d_null_reason = if (is.na(s$combined_rank) || is.na(prev_rank[tm])) rc_null$rank_change_7d else NULL,
        combined_score = list(value = r2(s$combined, 3), rank = if (is.na(s$combined_rank)) NULL else s$combined_rank,
                              components = list(form_z = r2(s$z_form, 3), trend_z = r2(s$z_trend, 3),
                                                residual_z = r2(s$z_residual, 3), elo_z = r2(s$z_elo, 3)),
                              null_reason = combined_null),
        ratings = list(
          ortg = rating_block("ortg", "ortg_rank"),
          drtg = rating_block("drtg", "drtg_rank"),
          net = c(rating_block("net", "net_rank"),
                  list(change_rank = if (is.na(s$net_change_rank)) NULL else s$net_change_rank))),
        model_residual = list(value = r2(s$residual), residual_games_in_window = s$residual_games,
                              ranked = isTRUE(s$residual_ranked), rank = if (is.na(s$residual_rank)) NULL else s$residual_rank,
                              basis = "logged_pregame_model",
                              null_reason = if (is.na(s$residual)) "no window game has a logged pregame margin" else NULL),
        residual_games_in_window = s$residual_games,
        opponent_adjusted_form = list(value = r2(s$adj_form), games = s$adj_form_games,
                                      rank = if (is.na(s$form_rank)) NULL else s$form_rank),
        drivers = window_drivers(wg, bg, ff_model, s$net_change),
        elo = list(current = r2(ec$elo, 1), rank = ec$elo_rank, change_7d = r2(ec$elo_change_7d, 1),
                   change_14d = r2(ec$elo_change_14d, 1), rank_change_7d = ec$elo_rank_change_7d,
                   rank_change_14d = ec$elo_rank_change_14d, change_in_window = r2(s$elo_change_window, 1)),
        schedule_strength = list(
          faced_window = r2(faced_w, 4), faced_season = r2(faced_season[[tm]], 4), faced_season_rank = faced_rank[[tm]],
          next_week = list(games = nrow(nwt), opponent_win_pct = if (nrow(nwt)) r2(nw_mean[[tm]], 4) else NULL,
                           rank = if (nrow(nwt)) nw_rank[[tm]] else NULL,
                           null_reason = if (!nrow(nwt)) "no games in the next 7 days" else NULL,
                           opponents = lapply(seq_len(nrow(nwt)), function(j) list(
                             date = format(nwt$date[j]), opponent = nwt$opp[j], home = nwt$home[j],
                             opponent_win_pct = r2(nwt$opp_win_pct[j], 4))))),
        clutch = list(window = clutch_block(cw, wg), season = clutch_block(cs, tg)),
        flags = flags,
        sparkline = lapply(seq_len(nrow(ts)), function(j) list(date = format(ts$game_date[j]), net_rating = r2(ts$net[j]))),
        sort_keys = list(
          combined_score = if (isTRUE(s$ranked)) r2(s$combined, 3) else NULL,
          model_residual = if (isTRUE(s$residual_ranked)) r2(s$residual) else NULL,
          net_rating_change = if (isTRUE(s$ranked)) r2(s$net_change) else NULL,
          elo_change_7d = if (isTRUE(s$ranked)) r2(ec$elo_change_7d, 1) else NULL,
          elo_change_14d = if (isTRUE(s$ranked)) r2(ec$elo_change_14d, 1) else NULL,
          schedule_strength = if (isTRUE(s$ranked)) r2(faced_w, 4) else NULL)
      )
    })
    boards[[as.character(w)]] <- list(window = w, ranked_count = sum(st$ranked), team_count = nrow(st),
      note = if (sum(st$ranked) < nrow(st)) sprintf("%d of %d teams have played %d games; the rest are shown unranked with their games so far.",
                                                    sum(st$ranked), nrow(st), w) else NULL,
      rows = rows)
  }

  hist <- update_rank_history(history_path, through_date, do.call(rbind, hist_snap))
  for (wk in names(boards)) {
    hw <- hist[hist$window == as.integer(wk), , drop = FALSE]
    for (i in seq_along(boards[[wk]]$rows)) {
      tm <- boards[[wk]]$rows[[i]]$team
      ht <- hw[hw$team == tm, , drop = FALSE]
      boards[[wk]]$rows[[i]]$rank_history <- lapply(seq_len(nrow(ht)), function(j) list(
        week_start = ht$week_start[j], as_of = ht$as_of[j], rank = ht$rank[j],
        combined_score = ht$combined_score[j], reconstruction = isTRUE(ht$reconstruction[j])))
    }
  }

  methods <- list(
    windows = list(sizes = MOMENTUM_WINDOWS, default = default_window,
                   default_rule = default_window_rule_text(n_teams = length(games_by_team)),
                   default_chosen = sprintf("%d. Teams ranked by window through %s: %s", default_window, format(through_date),
                                            paste(sprintf("%d games = %d of %d", MOMENTUM_WINDOWS,
                                                          vapply(MOMENTUM_WINDOWS, function(w) sum(games_by_team >= w), integer(1)),
                                                          length(games_by_team)), collapse = ", ")),
                   rule = "A team with fewer games than the window shows its values over the games played, with ranked = false and no rank in any sort.",
                   source_of_18 = "ROLLING_WINDOW_SIZE in config.R (the original ROC-AUC window test)"),
    possessions = "Per team FGA - OREB + TOV + 0.44 * FTA (TOV = total turnovers incl. team turnovers); game possessions = mean of both teams' estimates.",
    ratings = sprintf("ORtg/DRtg/NetRtg = 100 * points / possessions over the window's games. season = season to date (includes the window). change = window value minus the team's value over its season games before the window (before_window, games_before_window); null with change_null_reason \"%s\" when the team has fewer than %d games before the window. Ranks: 1 = best (lowest DRtg).", BASELINE_NULL_REASON, BASELINE_MIN_GAMES),
    change_baseline = sprintf("Every change measured against the season (rating changes, drivers, the combined score's trend component) uses the team's season games before the window, never a season that contains the window. Fewer than %d earlier games: null with null_reason \"%s\"; no fallback, nothing imputed.", BASELINE_MIN_GAMES, BASELINE_NULL_REASON),
    model_residual = list(
      definition = "Mean of actual minus logged pregame margin (team perspective) over window games with a RESOLVED LOGGED_PREGAME prediction-log row and a non-missing predicted_margin. Missing margins are skipped, never filled.",
      min_games_for_rank = sprintf("ceiling(%.1f * window) logged games: %s", RESIDUAL_MIN_SHARE,
                                   paste(sprintf("%d of %d", ceiling(RESIDUAL_MIN_SHARE * MOMENTUM_WINDOWS), MOMENTUM_WINDOWS), collapse = ", ")),
      coverage = log_cov),
    opponent_adjusted_form = sprintf("Mean per-game net rating + 100/poss * (opponent pregame Elo strength in points [(Elo - 1500)/%d] - home sign * %.2f home-court points + (own fatigue drag - opponent fatigue drag)); fatigue from fatigue_travel_engine.R::calculate_travel_fatigue (rest, back-to-back, haversine travel, time zones, altitude).", ELO_POINTS_PER_MARGIN_POINT, MOMENTUM_HCA_POINTS),
    drivers = "OLS of game net rating on the eight four-factor terms (eFG%, TOV%, OREB%/DREB%, FTA/FGA, for and against) over every team-game this season; each driver = coefficient x (window minus the team's games before the window) factor change; unexplained = the remainder; every driver null with null_reason when the team has fewer than 5 games before the window. Shot profile splits the offensive eFG term into rim (<= 4 ft), mid-range and 3PT attempt-share (rate) and points-per-shot (accuracy) shifts.",
    combined_score = list(
      formula = "sum_k weight_k * z_k, z_k = cross-sectional z-score among ranked teams of: form = opponent-adjusted form, trend = net-rating change (window minus the team's games before the window), residual = model residual (needs the residual minimum), elo = Elo change across the window's games",
      weights = as.list(COMBINED_WEIGHTS),
      null_rule = sprintf("Null (and unranked) when any weighted component is unavailable; components are never filled or imputed. The trend component is unavailable for a team with fewer than %d games before the window (and for every team when fewer than 3 ranked teams have it); like a residual below its minimum, that leaves the team's combined score and rank null, with the reason in combined_score.null_reason. z-score mean and sd use only the ranked teams that have the component. A component with zero variation among those teams has z = 0, so it adds nothing to the ranking.", BASELINE_MIN_GAMES),
      validation = list(target = sprintf("each team's mean scoring margin over its next %d games after date d", VALIDATION_HORIZON),
                        metric = "mean over dates of the cross-team Spearman correlation of the score at d (games through d only) with the target",
                        current_season = val_current, previous_season = val_prior,
                        weight_selection = "Grid over the simplex (step 0.1) of form / trend / Elo change fitted on the first half of 2025-26 dates and checked on the second half: form alone ranked first in train and test in every window (train IC 0.40-0.42, test IC 0.52-0.61); single-component ICs form 0.47-0.50, Elo change 0.29-0.31, trend 0.08-0.14. Residual weight checked on 2026-27 (window 5: 12 dates, window 10: 5 dates): adding it moved the IC by -0.04 to +0.01. Chosen weights keep form dominant and give trend, residual and Elo change 0.1 each; the owner reviews them. The grid figures above used the earlier season-including trend baseline; current_season and previous_season are re-run with the before-window baseline and the same weights.")),
    elo = list(k = ELO_K, home_advantage_elo = ELO_HOME_ADV, mean = ELO_MEAN, season_carry = ELO_CARRY,
               margin_multiplier = "(|margin| + 3)^0.8 / (7.5 + 0.006 * winner Elo lead incl. home court)",
               seed = elo$seed_method, series = sprintf("cache/elo_daily_%d.rds", season),
               changes = "change_7d / change_14d = rating on through_date minus rating 7 / 14 days earlier from the daily series; rank change positive = moved up"),
    schedule_strength = "Mean current win pct of opponents faced (window and season) and of opponents scheduled in the next 7 days; rank 1 = hardest.",
    clutch = "build_clutch_dataset.R filter (4Q/OT, <= 5:00, pre-play margin <= 5). Clutch games = games with any clutch play; points from score changes on clutch plays; clutch net rating per 100 clutch possessions (same estimator on clutch events).",
    flags = list(definitions = unname(lapply(as.character(sort(as.integer(ls(.flag_registry)))), function(k) .flag_registry[[k]])),
                 badge_rule = "Show a badge only when significant is true; raw value and statistic always present (null with null_reason when not computable).",
                 significance = sprintf("|z| >= %.2f (two-sided 5%%); flags 10 and 11 one-sided (z >= %.2f). Binomial z = (k/n - p0) / sqrt(p0 (1 - p0) / n) and Empirical Bayes value_shrunk = (k + %d p0) / (n + %d) - p0, the shots pipeline's machinery (web/lib/shotChartUtils.ts); z is not computed below n = %d.", Z_CRITICAL, Z_CRITICAL, EB_PRIOR_WEIGHT, EB_PRIOR_WEIGHT, MIN_BINOMIAL_N),
                 availability_source = sprintf("Flags 10 and 11 come from player box did_not_play rows and minutes (coverage %.1f%% of panel games); the injury cache is a current snapshot with no history and is not used.", 100 * pb_coverage)),
    rank_history = list(starts = min(hist$week_start), reconstruction = FALSE,
                        rule = "One snapshot per Monday-start week (latest run in the week); history starts at launch, no backfill. rank_7d_ago and rank_change_7d are recomputed from games through 7 days earlier; when null, rank_7d_ago_null_reason / rank_change_7d_null_reason say why (no games by then, not ranked then, or no current rank)."),
    nulls = "Unsupported values are null with a null_reason; nothing is imputed or synthesised.")

  payload <- list(
    schema_version = 1L,
    generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = season_label(season),
    through_date = format(through_date),
    windows = MOMENTUM_WINDOWS,
    default_window = default_window,
    ranked_counts = ranked_counts,
    sort_options = list(
      list(key = "combined_score", label = "Momentum score", descending = TRUE),
      list(key = "model_residual", label = "Model residual", descending = TRUE),
      list(key = "net_rating_change", label = "Net rating change", descending = TRUE),
      list(key = "elo_change_7d", label = "Elo change 7d", descending = TRUE),
      list(key = "elo_change_14d", label = "Elo change 14d", descending = TRUE),
      list(key = "schedule_strength", label = "Schedule strength faced", descending = TRUE)),
    boards = boards,
    methods = methods)
  dir.create(dirname(output_json), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(payload, output_json, auto_unbox = TRUE, pretty = FALSE, null = "null", na = "null", digits = NA)
  cat(sprintf(">>> [MOMENTUM] Wrote %s (through %s); ranked teams by window: %s\n", output_json, through_date,
              paste(sprintf("%s=%d", names(ranked_counts), unlist(ranked_counts)), collapse = ", ")))
  invisible(payload)
}

if (!nzchar(Sys.getenv("NBA_SKIP_STAGE_AUTORUN"))) {
  build_momentum_dataset()
}
