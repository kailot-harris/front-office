# ==============================================================================
# build_coaching_dataset.R
# Feature: /coaching head-coach decision profiles, measured from nflverse data
# (NFL_analytics#171).
#
# Replaces the hand-typed web/public/data/coaching_profiles.json. Every number
# this script publishes is measured from nflverse data; nothing is typed in.
#
# Unit and window
#   One profile per team for CURRENT_SEASON (config.R, the same constant
#   /clutch uses). The head coach is the home_coach / away_coach of the team's
#   latest played game in nflverse schedules. A profile covers only the games
#   that coach has coached for the team this season; `since_week` is the first
#   of those weeks and `games_coached` is their count.
#
# Inputs (all nflverse, loaded with nflreadr)
#   - Play-by-play for CURRENT_SEASON: the full nflreadr::load_pbp() table,
#     shared with build_clutch_dataset.R through CACHE_DNA_PBP (refreshed when
#     missing or more than 12 hours old). The 25-column cache/pbp_cache.rds has
#     no timeout, win-probability or replay columns and is never used here.
#   - Schedules for COACHING_HISTORY_START_SEASON (1999) through CURRENT_SEASON
#     from nflreadr::load_schedules(); cache/schedules_cache.rds starts at 2002.
#     Saved to CACHE_COACHING_SCHEDULES so the offline tests can check the
#     published head coaches against it.
#   - FTN charting for CURRENT_SEASON from nflreadr::load_ftn_charting()
#     (play-action). Licence: CC-BY-SA 4.0, attribution "FTN Data via nflverse".
#   - nfl4th::add_4th_probs() for the model estimates on 4th downs.
#
# Minimum samples
#   minimum = max(floor, ceiling(per_game * games_coached)). Below it a figure
#   is published as value = null together with its n and min_n. No default,
#   league average or zero is ever written in its place. The per-game rates and
#   floors are the COACHING_MIN_* constants directly below.
#
# Output
#   web/public/data/coaching_profiles.json (WEB_JSON_COACHING_PROFILES):
#   { generated_at, season, through_week, play_action_through_week,
#     min_sample_rules[], teams[] }. `generated_at` is the first key so the
#   publish gate's Assertion F (tools/publish_web.R) can read it.
#
# Pipeline wiring: Stage 14.4 of run_full_pipeline.R via run_build_coaching_dataset().
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

# ------------------------------------------------------------------------------
# Minimum-sample constants (section 4 of the #171 spec). One per-game rate and
# one floor per figure; minimum = max(floor, ceiling(per_game * games_coached)).
# ------------------------------------------------------------------------------
COACHING_MIN_PER_GAME_FOURTH_DOWN_GO   <- 1.5  # 4th-down go rate: qualifying 4th downs needed per game coached
COACHING_MIN_FLOOR_FOURTH_DOWN_GO      <- 5L   # 4th-down go rate: never fewer than 5 qualifying 4th downs
COACHING_MIN_PER_GAME_NFL4TH_SHOULD_GO <- 0.8  # nfl4th "went when it should": go-favoured 4th downs per game
COACHING_MIN_FLOOR_NFL4TH_SHOULD_GO    <- 3L   # nfl4th "went when it should": never fewer than 3 go-favoured 4th downs
COACHING_MIN_PER_GAME_NFL4TH_SHOULD_KICK <- 1.5 # nfl4th "went when it shouldn't": kick-favoured 4th downs per game
COACHING_MIN_FLOOR_NFL4TH_SHOULD_KICK  <- 5L   # nfl4th "went when it shouldn't": never fewer than 5 kick-favoured 4th downs
COACHING_MIN_PER_GAME_EARLY_DOWN       <- 15   # pass rate over expected and early-down pass rate: neutral early-down plays per game
COACHING_MIN_FLOOR_EARLY_DOWN          <- 40L  # pass rate over expected and early-down pass rate: never fewer than 40 plays
COACHING_MIN_PER_GAME_PLAY_ACTION      <- 10   # play-action rate: charted dropbacks per game
COACHING_MIN_FLOOR_PLAY_ACTION         <- 30L  # play-action rate: never fewer than 30 charted dropbacks
COACHING_MIN_PER_GAME_PACE             <- 15   # seconds per play: neutral snap-to-snap intervals per game
COACHING_MIN_FLOOR_PACE                <- 40L  # seconds per play: never fewer than 40 intervals
COACHING_MIN_PER_GAME_CHALLENGE        <- 0.3  # challenge success: coach challenges per game
COACHING_MIN_FLOOR_CHALLENGE           <- 2L   # challenge success: never fewer than 2 challenges
COACHING_MIN_PER_GAME_TIMEOUT_EPA      <- 0.8  # EPA after own timeout: post-timeout offensive snaps per game
COACHING_MIN_FLOOR_TIMEOUT_EPA         <- 3L   # EPA after own timeout: never fewer than 3 snaps
COACHING_MIN_PER_GAME_TIMEOUT_SHARE    <- 1.5  # share of timeouts in quarters 1-3: timeouts called per game
COACHING_MIN_FLOOR_TIMEOUT_SHARE       <- 5L   # share of timeouts in quarters 1-3: never fewer than 5 timeouts
COACHING_MIN_FLOOR_UNUSED_TIMEOUTS     <- 2L   # unused timeouts when trailing at the end: fixed minimum of 2 close losses

# First season nflverse schedules cover; career figures cannot see earlier games.
COACHING_HISTORY_START_SEASON <- 1999L
# 4th downs at or inside this yard line (distance to the opponent's goal) are left out of the go rate.
COACHING_GO_RATE_MIN_YARDLINE <- 2
# Seconds left in a half below which plays count as end-of-half (the last 2:00).
COACHING_END_OF_HALF_SECONDS <- 120
# Win-probability band for the early-down tendency figures (20% to 80%).
COACHING_NEUTRAL_WP_LOW  <- 0.20
COACHING_NEUTRAL_WP_HIGH <- 0.80
# Largest score margin that still counts as neutral for seconds per play.
COACHING_PACE_MAX_SCORE_MARGIN <- 7
# Largest final losing margin counted as a close loss for unused timeouts.
COACHING_CLOSE_LOSS_MAX_MARGIN <- 8
# Refresh the shared single-season play-by-play cache when it is older than this.
COACHING_PBP_MAX_AGE_HOURS <- 12

# The minimum-sample table, assembled from the constants above. Order is the
# order the page lists the figures in.
coaching_min_sample_rules <- function() {
  data.frame(
    metric = c("fourth_down_go_rate", "nfl4th_go_when_recommended", "nfl4th_go_when_not_recommended",
               "pass_rate_over_expected", "early_down_pass_rate", "play_action_rate",
               "seconds_per_play", "challenge_success_rate", "epa_after_own_timeout",
               "timeouts_q1_q3_share", "unused_timeouts_close_losses"),
    per_game = c(COACHING_MIN_PER_GAME_FOURTH_DOWN_GO, COACHING_MIN_PER_GAME_NFL4TH_SHOULD_GO,
                 COACHING_MIN_PER_GAME_NFL4TH_SHOULD_KICK, COACHING_MIN_PER_GAME_EARLY_DOWN,
                 COACHING_MIN_PER_GAME_EARLY_DOWN, COACHING_MIN_PER_GAME_PLAY_ACTION,
                 COACHING_MIN_PER_GAME_PACE, COACHING_MIN_PER_GAME_CHALLENGE,
                 COACHING_MIN_PER_GAME_TIMEOUT_EPA, COACHING_MIN_PER_GAME_TIMEOUT_SHARE, NA_real_),
    floor = c(COACHING_MIN_FLOOR_FOURTH_DOWN_GO, COACHING_MIN_FLOOR_NFL4TH_SHOULD_GO,
              COACHING_MIN_FLOOR_NFL4TH_SHOULD_KICK, COACHING_MIN_FLOOR_EARLY_DOWN,
              COACHING_MIN_FLOOR_EARLY_DOWN, COACHING_MIN_FLOOR_PLAY_ACTION,
              COACHING_MIN_FLOOR_PACE, COACHING_MIN_FLOOR_CHALLENGE,
              COACHING_MIN_FLOOR_TIMEOUT_EPA, COACHING_MIN_FLOOR_TIMEOUT_SHARE,
              COACHING_MIN_FLOOR_UNUSED_TIMEOUTS),
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
# Pure helpers (loaded by tests/test_coaching_dataset.R via load_ast_symbols)
# ------------------------------------------------------------------------------

# minimum = max(floor, ceiling(per_game * games)). The product is rounded to six
# decimals first so binary floating point (0.3 * 10 = 3.0000000000000004) cannot
# push an exact product up by one. A missing per_game means a fixed minimum.
coaching_min_n <- function(per_game, floor, games_coached) {
  if (is.na(per_game)) return(as.integer(floor))
  as.integer(max(floor, ceiling(round(per_game * games_coached, 6))))
}

# A published figure: value is kept only when n reaches min_n, else NA (JSON null).
coaching_figure <- function(value, n, min_n, digits) {
  n <- as.integer(n)
  min_n <- as.integer(min_n)
  keep <- !is.na(value) && is.finite(value) && n >= min_n
  list(value = if (keep) round(value, digits) else NA_real_, n = n, min_n = min_n)
}

coaching_flag <- function(x) !is.na(x) & x == 1

# Team-game rows from a schedules table: one row per team per game, with the
# coach, the team's final margin and whether the game has a result yet.
coaching_team_games <- function(sched) {
  home <- data.frame(game_id = sched$game_id, season = as.integer(sched$season),
                     week = as.integer(sched$week), game_type = sched$game_type,
                     gameday = as.character(sched$gameday),
                     team = sched$home_team, coach = sched$home_coach,
                     margin = sched$home_score - sched$away_score,
                     played = !is.na(sched$result), stringsAsFactors = FALSE)
  away <- data.frame(game_id = sched$game_id, season = as.integer(sched$season),
                     week = as.integer(sched$week), game_type = sched$game_type,
                     gameday = as.character(sched$gameday),
                     team = sched$away_team, coach = sched$away_coach,
                     margin = sched$away_score - sched$home_score,
                     played = !is.na(sched$result), stringsAsFactors = FALSE)
  out <- rbind(home, away)
  out[order(out$team, out$season, out$week, out$gameday, out$game_id), , drop = FALSE]
}

# The current head coach of `team` in `season`: the coach of its latest played
# game (the first scheduled game if none is played yet), with the games that
# coach has coached for the team this season.
coaching_current_coach <- function(team_games, team, season) {
  tg <- team_games[team_games$team == team & team_games$season == season, , drop = FALSE]
  if (nrow(tg) == 0L) return(NULL)
  played <- tg[tg$played, , drop = FALSE]
  latest <- if (nrow(played)) played[nrow(played), ] else tg[1, ]
  coach <- latest$coach
  if (is.na(coach) || !nzchar(coach)) return(NULL)
  mine <- played[!is.na(played$coach) & played$coach == coach, , drop = FALSE]
  list(
    team = team,
    head_coach = coach,
    latest_game_id = latest$game_id,
    game_ids = mine$game_id,
    games_coached = nrow(mine),
    since_week = if (nrow(mine)) as.integer(min(mine$week)) else NA_integer_
  )
}

# Consecutive seasons, ending at `season`, in which `coach` was head coach of
# `team` for at least one game.
coaching_tenure <- function(team_games, team, coach, season) {
  seasons <- unique(team_games$season[team_games$team == team &
                                        !is.na(team_games$coach) & team_games$coach == coach])
  n <- 0L
  s <- season
  while (s %in% seasons) {
    n <- n + 1L
    s <- s - 1L
  }
  n
}

# Career W-L-T (regular season plus playoffs, every team) and Super Bowl wins
# for `coach` across every played game in team_games.
coaching_career <- function(team_games, coach, history_start = COACHING_HISTORY_START_SEASON) {
  g <- team_games[team_games$played & !is.na(team_games$coach) & team_games$coach == coach, , drop = FALSE]
  wins <- sum(g$margin > 0)
  losses <- sum(g$margin < 0)
  ties <- sum(g$margin == 0)
  first_season <- if (nrow(g)) as.integer(min(g$season)) else NA_integer_
  list(
    career_wins = as.integer(wins),
    career_losses = as.integer(losses),
    career_ties = as.integer(ties),
    career_games = as.integer(nrow(g)),
    career_record = if (ties > 0) sprintf("%d-%d-%d", wins, losses, ties) else sprintf("%d-%d", wins, losses),
    super_bowl_wins = as.integer(sum(g$game_type == "SB" & g$margin > 0)),
    career_first_season = first_season,
    career_possibly_truncated = isTRUE(first_season == history_start)
  )
}

# 4th-down decisions: plays from scrimmage on 4th down that were a run, a pass,
# a punt or a field-goal attempt. went = the offence ran a play.
coaching_fourth_down_decisions <- function(pbp) {
  d <- pbp[!is.na(pbp$down) & pbp$down == 4 &
             !is.na(pbp$play_type) & pbp$play_type %in% c("pass", "run", "punt", "field_goal"), , drop = FALSE]
  d$went <- d$play_type %in% c("pass", "run")
  d
}

# 4th-down go rate: excludes the last 2:00 of either half and 4th downs at or
# inside the opponent's 2-yard line.
coaching_go_rate <- function(decisions, team) {
  d <- decisions[decisions$posteam == team &
                   !is.na(decisions$half_seconds_remaining) &
                   decisions$half_seconds_remaining > COACHING_END_OF_HALF_SECONDS &
                   !is.na(decisions$yardline_100) &
                   decisions$yardline_100 > COACHING_GO_RATE_MIN_YARDLINE, , drop = FALSE]
  list(value = if (nrow(d)) 100 * mean(d$went) else NA_real_, n = nrow(d))
}

# nfl4th figures from decisions that carry go_boost (go win probability minus
# the better kicking option's, in percentage points). Decisions without a
# go_boost are counted separately and left out of both rates.
coaching_nfl4th_rates <- function(decisions, team) {
  d <- decisions[decisions$posteam == team, , drop = FALSE]
  missing <- sum(is.na(d$go_boost))
  d <- d[!is.na(d$go_boost), , drop = FALSE]
  should_go <- d[d$go_boost > 0, , drop = FALSE]
  should_kick <- d[d$go_boost < 0, , drop = FALSE]
  list(
    go_when_recommended = list(value = if (nrow(should_go)) 100 * mean(should_go$went) else NA_real_,
                               n = nrow(should_go)),
    go_when_not_recommended = list(value = if (nrow(should_kick)) 100 * mean(should_kick$went) else NA_real_,
                                   n = nrow(should_kick)),
    without_model_estimate = as.integer(missing)
  )
}

# Early-down neutral plays: 1st and 2nd down runs and passes with win
# probability between 20% and 80%.
coaching_early_down_plays <- function(pbp, team) {
  pbp[pbp$posteam %in% team & !is.na(pbp$down) & pbp$down %in% c(1, 2) &
        !is.na(pbp$play_type) & pbp$play_type %in% c("pass", "run") &
        !is.na(pbp$wp) & pbp$wp >= COACHING_NEUTRAL_WP_LOW & pbp$wp <= COACHING_NEUTRAL_WP_HIGH, , drop = FALSE]
}

# Pass rate over expected: mean nflverse pass_oe (percentage points).
coaching_proe <- function(pbp, team) {
  p <- coaching_early_down_plays(pbp, team)
  v <- p$pass_oe[!is.na(p$pass_oe)]
  list(value = if (length(v)) mean(v) else NA_real_, n = length(v))
}

# Early-down pass rate: dropbacks / (dropbacks + designed runs).
coaching_early_down_pass_rate <- function(pbp, team) {
  p <- coaching_early_down_plays(pbp, team)
  dropback <- coaching_flag(p$qb_dropback)
  run <- !dropback & coaching_flag(p$rush)
  n <- sum(dropback) + sum(run)
  list(value = if (n > 0) 100 * sum(dropback) / n else NA_real_, n = n)
}

# Play-action rate: FTN play-action dropbacks / FTN-charted dropbacks.
coaching_play_action_rate <- function(pbp, ftn, team) {
  db <- pbp[pbp$posteam %in% team & coaching_flag(pbp$qb_dropback), c("game_id", "play_id"), drop = FALSE]
  f <- ftn[!is.na(ftn$is_play_action), c("nflverse_game_id", "nflverse_play_id", "is_play_action"), drop = FALSE]
  m <- merge(db, f, by.x = c("game_id", "play_id"), by.y = c("nflverse_game_id", "nflverse_play_id"))
  n <- nrow(m)
  list(value = if (n > 0) 100 * mean(as.logical(m$is_play_action)) else NA_real_, n = n)
}

# Seconds per play: game-clock seconds between consecutive offensive snaps
# (runs and passes) on the same drive, when both snaps are outside the last
# 2:00 of the half and the later snap has the score within 7.
coaching_seconds_per_play <- function(pbp, team) {
  s <- pbp[pbp$posteam %in% team & !is.na(pbp$play_type) & pbp$play_type %in% c("pass", "run") &
             !is.na(pbp$game_seconds_remaining), , drop = FALSE]
  if (!nrow(s)) return(list(value = NA_real_, n = 0L))
  s <- s[order(s$game_id, s$play_id), , drop = FALSE]
  same <- c(FALSE, s$game_id[-1] == s$game_id[-nrow(s)] &
                     s$fixed_drive[-1] == s$fixed_drive[-nrow(s)] &
                     s$game_half[-1] == s$game_half[-nrow(s)])
  gap <- c(NA_real_, s$game_seconds_remaining[-nrow(s)] - s$game_seconds_remaining[-1])
  prev_hsr <- c(NA_real_, s$half_seconds_remaining[-nrow(s)])
  keep <- same & !is.na(gap) & gap >= 0 &
    !is.na(prev_hsr) & prev_hsr > COACHING_END_OF_HALF_SECONDS &
    !is.na(s$half_seconds_remaining) & s$half_seconds_remaining > COACHING_END_OF_HALF_SECONDS &
    !is.na(s$score_differential) & abs(s$score_differential) <= COACHING_PACE_MAX_SCORE_MARGIN
  v <- gap[keep]
  list(value = if (length(v)) mean(v) else NA_real_, n = length(v))
}

# Coach challenges: plays whose description says "<Team> challenged ...".
# replay_or_challenge also covers booth reviews ("The Replay Official
# reviewed ..."), so the description, not that flag, identifies a coach
# challenge. The challenger is resolved to the home or away team of the game by
# full team name ("Los Angeles Chargers challenged") or, when that is unique in
# the game, by location ("Indianapolis challenged"). Success = the play was
# reversed (replay_or_challenge_result).
coaching_challenges <- function(pbp, team_names) {
  ch <- pbp[!is.na(pbp$desc) & grepl(" challenged ", pbp$desc, fixed = TRUE), , drop = FALSE]
  if (!nrow(ch)) {
    return(data.frame(game_id = character(0), play_id = numeric(0), team = character(0),
                      reversed = logical(0), stringsAsFactors = FALSE))
  }
  location <- sub(" [^ ]+$", "", team_names)
  names(location) <- names(team_names)
  who <- vapply(seq_len(nrow(ch)), function(i) {
    cands <- c(ch$home_team[i], ch$away_team[i])
    full_hit <- cands[vapply(cands, function(t) grepl(paste0(team_names[[t]], " challenged"), ch$desc[i], fixed = TRUE), logical(1))]
    if (length(full_hit) == 1L) return(full_hit)
    locs <- location[cands]
    if (anyDuplicated(locs)) return(NA_character_)
    loc_hit <- cands[vapply(cands, function(t) grepl(paste0(location[[t]], " challenged"), ch$desc[i], fixed = TRUE), logical(1))]
    if (length(loc_hit) == 1L) loc_hit else NA_character_
  }, character(1))
  data.frame(game_id = ch$game_id, play_id = ch$play_id, team = unname(who),
             reversed = !is.na(ch$replay_or_challenge_result) & ch$replay_or_challenge_result == "reversed",
             stringsAsFactors = FALSE)
}

coaching_challenge_success <- function(challenges, team) {
  c2 <- challenges[!is.na(challenges$team) & challenges$team == team, , drop = FALSE]
  list(value = if (nrow(c2)) 100 * mean(c2$reversed) else NA_real_, n = nrow(c2))
}

# Timeouts a team called: the stand-alone "Timeout #N by TEAM" rows. Timeouts
# charged for a lost challenge sit inside the challenged play's row and are not
# counted as called.
coaching_called_timeouts <- function(pbp) {
  pbp[coaching_flag(pbp$timeout) & !is.na(pbp$timeout_team) &
        !is.na(pbp$desc) & grepl("^Timeout #", pbp$desc), , drop = FALSE]
}

# Share of a team's called timeouts that came in quarters 1-3.
coaching_timeout_q13_share <- function(timeouts, team) {
  t <- timeouts[timeouts$timeout_team == team, , drop = FALSE]
  list(value = if (nrow(t)) 100 * mean(t$qtr <= 3) else NA_real_, n = nrow(t))
}

# EPA after own timeout: for each timeout the team called, the next snap in the
# same game and half; counted when that snap is the calling team's offence.
coaching_epa_after_timeout <- function(pbp, timeouts, team) {
  t <- timeouts[timeouts$timeout_team == team, , drop = FALSE]
  if (!nrow(t)) return(list(value = NA_real_, n = 0L))
  snaps <- pbp[!is.na(pbp$play_type) &
                 pbp$play_type %in% c("pass", "run", "punt", "field_goal", "qb_kneel", "qb_spike"), , drop = FALSE]
  snaps <- snaps[order(snaps$game_id, snaps$play_id), , drop = FALSE]
  vals <- numeric(0)
  for (i in seq_len(nrow(t))) {
    nxt <- snaps[snaps$game_id == t$game_id[i] & snaps$game_half == t$game_half[i] &
                   snaps$play_id > t$play_id[i], , drop = FALSE]
    if (!nrow(nxt)) next
    nxt <- nxt[1, ]
    if (!is.na(nxt$posteam) && nxt$posteam == team && !is.na(nxt$epa)) vals <- c(vals, nxt$epa)
  }
  list(value = if (length(vals)) mean(vals) else NA_real_, n = length(vals))
}

# Unused timeouts when trailing at the end: timeouts the team still had on the
# last play of each game it lost by COACHING_CLOSE_LOSS_MAX_MARGIN or fewer.
coaching_unused_timeouts <- function(pbp, team_games, team, game_ids) {
  close <- team_games[team_games$team == team & team_games$played & team_games$game_id %in% game_ids &
                        team_games$margin < 0 & team_games$margin >= -COACHING_CLOSE_LOSS_MAX_MARGIN, , drop = FALSE]
  vals <- numeric(0)
  for (gid in close$game_id) {
    g <- pbp[pbp$game_id == gid, , drop = FALSE]
    if (!nrow(g)) next
    last <- g[which.max(g$play_id), ]
    left <- if (last$home_team == team) last$home_timeouts_remaining else last$away_timeouts_remaining
    if (!is.na(left)) vals <- c(vals, left)
  }
  list(value = if (length(vals)) mean(vals) else NA_real_, n = length(vals))
}

# One team's profile. `inputs` carries the season-wide tables built once in
# run_build_coaching_dataset().
coaching_build_profile <- function(team, inputs, rules = coaching_min_sample_rules()) {
  cc <- coaching_current_coach(inputs$team_games, team, inputs$season)
  if (is.null(cc)) stop(sprintf("No head coach found in schedules for %s in %d.", team, inputs$season))
  games <- cc$games_coached
  mins <- vapply(seq_len(nrow(rules)), function(i) coaching_min_n(rules$per_game[i], rules$floor[i], games),
                 integer(1))
  names(mins) <- rules$metric

  pbp_t <- inputs$pbp[inputs$pbp$game_id %in% cc$game_ids, , drop = FALSE]
  dec_t <- inputs$decisions[inputs$decisions$game_id %in% cc$game_ids, , drop = FALSE]
  to_t <- inputs$timeouts[inputs$timeouts$game_id %in% cc$game_ids, , drop = FALSE]
  ch_t <- inputs$challenges[inputs$challenges$game_id %in% cc$game_ids, , drop = FALSE]

  go <- coaching_go_rate(dec_t, team)
  m4 <- coaching_nfl4th_rates(dec_t, team)
  proe <- coaching_proe(pbp_t, team)
  edpr <- coaching_early_down_pass_rate(pbp_t, team)
  pa <- coaching_play_action_rate(pbp_t, inputs$ftn, team)
  spp <- coaching_seconds_per_play(pbp_t, team)
  chal <- coaching_challenge_success(ch_t, team)
  tepa <- coaching_epa_after_timeout(pbp_t, to_t, team)
  tq <- coaching_timeout_q13_share(to_t, team)
  unused <- coaching_unused_timeouts(pbp_t, inputs$team_games, team, cc$game_ids)

  career <- coaching_career(inputs$team_games, cc$head_coach)

  c(
    list(
      team = team,
      head_coach = cc$head_coach,
      latest_game_id = cc$latest_game_id,
      since_week = cc$since_week,
      games_coached = as.integer(games),
      tenure_seasons = coaching_tenure(inputs$team_games, team, cc$head_coach, inputs$season)
    ),
    career,
    list(
      fourth_down_go_rate = coaching_figure(go$value, go$n, mins[["fourth_down_go_rate"]], 1),
      nfl4th_go_when_recommended = coaching_figure(m4$go_when_recommended$value, m4$go_when_recommended$n,
                                                   mins[["nfl4th_go_when_recommended"]], 1),
      nfl4th_go_when_not_recommended = coaching_figure(m4$go_when_not_recommended$value, m4$go_when_not_recommended$n,
                                                       mins[["nfl4th_go_when_not_recommended"]], 1),
      fourth_downs_without_model_estimate = m4$without_model_estimate,
      pass_rate_over_expected = coaching_figure(proe$value, proe$n, mins[["pass_rate_over_expected"]], 1),
      early_down_pass_rate = coaching_figure(edpr$value, edpr$n, mins[["early_down_pass_rate"]], 1),
      play_action_rate = coaching_figure(pa$value, pa$n, mins[["play_action_rate"]], 1),
      seconds_per_play = coaching_figure(spp$value, spp$n, mins[["seconds_per_play"]], 1),
      challenge_success_rate = coaching_figure(chal$value, chal$n, mins[["challenge_success_rate"]], 1),
      epa_after_own_timeout = coaching_figure(tepa$value, tepa$n, mins[["epa_after_own_timeout"]], 3),
      timeouts_q1_q3_share = coaching_figure(tq$value, tq$n, mins[["timeouts_q1_q3_share"]], 1),
      unused_timeouts_close_losses = coaching_figure(unused$value, unused$n, mins[["unused_timeouts_close_losses"]], 2)
    )
  )
}

# Serialise the dataset. generated_at is the first key (publish gate Assertion F).
coaching_to_json <- function(dataset) {
  jsonlite::toJSON(dataset, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = NA)
}

# ------------------------------------------------------------------------------
# Data loading
# ------------------------------------------------------------------------------
coaching_load_pbp <- function(season) {
  pbp_file <- if (exists("CACHE_DNA_PBP")) CACHE_DNA_PBP else file.path(CACHE_DIR, sprintf("nfl_pbp_%d.rds", season))
  needs_refresh <- !file.exists(pbp_file) ||
    as.numeric(difftime(Sys.time(), file.info(pbp_file)$mtime, units = "hours")) > COACHING_PBP_MAX_AGE_HOURS
  if (needs_refresh) {
    cat(sprintf(">>> [COACHING] Pulling %d play-by-play via nflreadr -> %s...\n", season, pbp_file))
    pbp <- nflreadr::load_pbp(seasons = season)
    saveRDS(pbp, pbp_file)
  } else {
    cat(sprintf(">>> [COACHING] Reading play-by-play from %s...\n", pbp_file))
    pbp <- readRDS(pbp_file)
  }
  pbp <- as.data.frame(pbp)
  pbp <- pbp[!is.na(pbp$season) & pbp$season == season, , drop = FALSE]
  needed <- c("game_id", "play_id", "posteam", "home_team", "away_team", "down", "play_type", "desc",
              "qtr", "game_half", "fixed_drive", "half_seconds_remaining", "game_seconds_remaining",
              "yardline_100", "wp", "pass_oe", "qb_dropback", "rush", "score_differential", "epa",
              "timeout", "timeout_team", "home_timeouts_remaining", "away_timeouts_remaining",
              "replay_or_challenge_result")
  missing <- setdiff(needed, names(pbp))
  if (length(missing)) {
    stop(sprintf("Play-by-play for %d lacks column(s): %s. Refusing to build coaching profiles.",
                 season, paste(missing, collapse = ", ")))
  }
  if (!nrow(pbp)) stop(sprintf("No play-by-play rows for %d; refusing to write coaching profiles.", season))
  pbp
}

# ------------------------------------------------------------------------------
# Main orchestrator
# ------------------------------------------------------------------------------
run_build_coaching_dataset <- function(season = CURRENT_SEASON) {
  cat(">>> [COACHING] Building measured head-coach profiles...\n")
  for (pkg in c("nflreadr", "nfl4th")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required to build coaching_profiles.json.", pkg))
    }
  }
  season <- as.integer(season)

  pbp <- coaching_load_pbp(season)
  cat(sprintf(">>> [COACHING] %d play-by-play rows through week %d.\n", nrow(pbp), max(pbp$week)))

  sched <- as.data.frame(nflreadr::load_schedules(seasons = COACHING_HISTORY_START_SEASON:season))
  sched$home_team <- nflreadr::clean_team_abbrs(sched$home_team, current_location = TRUE, keep_non_matches = TRUE)
  sched$away_team <- nflreadr::clean_team_abbrs(sched$away_team, current_location = TRUE, keep_non_matches = TRUE)
  sched <- sched[order(sched$season, sched$week, sched$gameday, sched$game_id), , drop = FALSE]
  sched_cache <- if (exists("CACHE_COACHING_SCHEDULES")) CACHE_COACHING_SCHEDULES else
    file.path(CACHE_DIR, sprintf("nfl_schedules_coaching_%d_%d.rds", COACHING_HISTORY_START_SEASON, season))
  saveRDS(sched, sched_cache)
  team_games <- coaching_team_games(sched)

  ftn <- as.data.frame(nflreadr::load_ftn_charting(seasons = season))
  ftn_week <- if (nrow(ftn)) as.integer(max(ftn$week, na.rm = TRUE)) else NA_integer_

  decisions <- coaching_fourth_down_decisions(pbp)
  decisions <- decisions[order(decisions$game_id, decisions$play_id), , drop = FALSE]
  cat(sprintf(">>> [COACHING] Running nfl4th::add_4th_probs() on %d 4th-down decisions...\n", nrow(decisions)))
  probs <- as.data.frame(nfl4th::add_4th_probs(decisions))
  if (nrow(probs) != nrow(decisions) || !"go_boost" %in% names(probs)) {
    stop("nfl4th::add_4th_probs() did not return one go_boost per 4th-down decision.")
  }
  decisions$go_boost <- probs$go_boost

  team_names <- NFL_TEAMS
  challenges <- coaching_challenges(pbp, team_names)
  unresolved <- sum(is.na(challenges$team))
  if (unresolved) {
    log_msg <- sprintf("build_coaching_dataset: %d coach challenge(s) could not be tied to a team and were left out.",
                       unresolved)
    if (exists("log_warn")) log_warn(log_msg) else warning(log_msg)
  }

  inputs <- list(season = season, pbp = pbp, team_games = team_games, ftn = ftn,
                 decisions = decisions, timeouts = coaching_called_timeouts(pbp), challenges = challenges)

  teams <- sort(names(NFL_TEAMS))
  profiles <- lapply(teams, coaching_build_profile, inputs = inputs)

  # Every head coach must equal the schedule's coach for that team's latest game.
  for (p in profiles) {
    g <- sched[sched$game_id == p$latest_game_id, , drop = FALSE]
    want <- if (g$home_team == p$team) g$home_coach else g$away_coach
    if (!identical(want, p$head_coach)) {
      stop(sprintf("Head coach mismatch for %s: %s vs schedule %s.", p$team, p$head_coach, want))
    }
  }
  if (length(profiles) != NFL_TEAM_COUNT) {
    stop(sprintf("Built %d coaching profiles, expected %d.", length(profiles), NFL_TEAM_COUNT))
  }

  no_model <- sum(vapply(profiles, function(p) p$fourth_downs_without_model_estimate, integer(1)))
  cat(sprintf(">>> [COACHING] %d 4th-down decision(s) had no nfl4th estimate and were left out of the nfl4th rates.\n",
              no_model))

  dataset <- list(
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = season,
    through_week = as.integer(max(pbp$week, na.rm = TRUE)),
    play_action_through_week = ftn_week,
    history_start_season = COACHING_HISTORY_START_SEASON,
    min_sample_rules = coaching_min_sample_rules(),
    teams = profiles
  )

  out_path <- if (exists("WEB_JSON_COACHING_PROFILES")) WEB_JSON_COACHING_PROFILES else
    file.path("web", "public", "data", "coaching_profiles.json")
  writeLines(coaching_to_json(dataset), out_path, useBytes = TRUE)
  cat(sprintf(">>> [COACHING] Exported %d profiles to %s\n", length(profiles), out_path))
  invisible(dataset)
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  script_dir <- if (length(file_arg) > 0) {
    dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
  } else {
    getwd()
  }
  if (dir.exists(script_dir)) {
    setwd(script_dir)
  }
  source("config.R")
  run_build_coaching_dataset()
}
