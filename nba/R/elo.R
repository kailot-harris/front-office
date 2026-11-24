# ==============================================================================
# R/elo.R - the one shared NBA Elo implementation (NBA_analytics#237)
#
# Before this file, four tools/gif_*.R scripts each recomputed Elo inline with
# different rules (gif_elo_rank_bump.R: K = 20, log margin multiplier, no home
# court; gif_pf_pa_scatter_elo.R: home-adjusted, a different log multiplier), and
# no Elo series was ever saved. This file is the single definition the momentum
# board reads; moving the GIF scripts onto it is a separate follow-up.
#
# RULES (documented here and echoed into momentum_board.json `methods.elo`):
#   K                 ELO_K = 20 rating points per game.
#   Home court        ELO_HOME_ADV = 100 rating points added to the home side's
#                     rating when computing the expected result; 0 at a neutral site.
#   Expected result   E_home = 1 / (1 + 10^(-(R_home + HCA - R_away) / 400)).
#   Margin of victory multiplier (FiveThirtyEight NBA form):
#                     M = (|margin| + 3)^0.8 / (7.5 + 0.006 * D_w),
#                     D_w = winner's rating minus loser's rating, home court
#                     included. Big favourites earn less for a blowout, so
#                     ratings do not run away (autocorrelation guard).
#   Update            shift = K * M * (S_home - E_home), S_home = 1 for a home
#                     win, 0 for a loss; home += shift, away -= shift (zero-sum,
#                     so the league mean stays at ELO_MEAN).
#   Season carry-over Each team starts a season at
#                     ELO_CARRY * (previous season's final rating) + (1 - ELO_CARRY) * ELO_MEAN,
#                     ELO_CARRY = 0.75. When the previous season's games are not
#                     available every team starts at ELO_MEAN (1500), and the
#                     series records seed_method = "flat_1500".
#   Daily series      One row per team per calendar date from the day before the
#                     season's first game (the seed row) through the requested
#                     end date: the rating after every game played on or before
#                     that date. Changes over 7 / 14 days are differences of this
#                     series, never recomputed elsewhere.
#
# Inputs are completed games only: one row per game with home/away team codes,
# scores and the game date. No value is estimated or filled.
# ==============================================================================

ELO_K        <- 20
ELO_HOME_ADV <- 100
ELO_MEAN     <- 1500
ELO_CARRY    <- 0.75
# Rating points per point of scoring margin (FiveThirtyEight NBA convention),
# used only to express an Elo gap in margin points.
ELO_POINTS_PER_MARGIN_POINT <- 28

elo_expected_home <- function(r_home, r_away, neutral = FALSE) {
  hca <- ifelse(neutral %in% TRUE, 0, ELO_HOME_ADV)
  1 / (1 + 10^(-(r_home + hca - r_away) / 400))
}

elo_mov_multiplier <- function(margin, winner_elo_diff) {
  ((abs(margin) + 3)^0.8) / (7.5 + 0.006 * winner_elo_diff)
}

# Apply one game. Returns c(home_new, away_new, shift).
elo_update_game <- function(r_home, r_away, home_pts, away_pts, neutral = FALSE, k = ELO_K) {
  hca <- if (isTRUE(neutral)) 0 else ELO_HOME_ADV
  e_home <- 1 / (1 + 10^(-(r_home + hca - r_away) / 400))
  margin <- home_pts - away_pts
  if (margin == 0) stop("elo_update_game: NBA games cannot end tied")
  s_home <- as.numeric(margin > 0)
  d_w <- if (margin > 0) (r_home + hca - r_away) else (r_away - r_home - hca)
  shift <- k * elo_mov_multiplier(margin, d_w) * (s_home - e_home)
  c(r_home + shift, r_away - shift, shift)
}

# games: data.frame(game_id, game_date (Date), home, away, home_pts, away_pts,
#                   neutral (optional logical)).
# seed: named numeric vector of starting ratings (missing teams start at ELO_MEAN).
# Returns the games with pre/post ratings for both sides, in play order, plus the
# final ratings as attr "final".
elo_run_games <- function(games, seed = NULL, k = ELO_K) {
  games <- as.data.frame(games, stringsAsFactors = FALSE)
  games$game_date <- as.Date(games$game_date)
  if (!"neutral" %in% names(games)) games$neutral <- FALSE
  games$neutral <- games$neutral %in% TRUE
  games <- games[order(games$game_date, as.character(games$game_id)), , drop = FALSE]
  teams <- sort(unique(c(games$home, games$away, names(seed))))
  r <- setNames(rep(ELO_MEAN, length(teams)), teams)
  if (length(seed)) r[names(seed)] <- seed
  n <- nrow(games)
  out <- data.frame(home_elo_pre = numeric(n), away_elo_pre = numeric(n),
                    home_elo_post = numeric(n), away_elo_post = numeric(n))
  for (i in seq_len(n)) {
    h <- games$home[i]; a <- games$away[i]
    u <- elo_update_game(r[[h]], r[[a]], games$home_pts[i], games$away_pts[i],
                         neutral = games$neutral[i], k = k)
    out$home_elo_pre[i] <- r[[h]]; out$away_elo_pre[i] <- r[[a]]
    r[[h]] <- u[1]; r[[a]] <- u[2]
    out$home_elo_post[i] <- u[1]; out$away_elo_post[i] <- u[2]
  }
  res <- cbind(games, out)
  attr(res, "final") <- r
  res
}

# Season carry-over: regress last season's finals toward the mean.
elo_carry_over <- function(final_ratings, carry = ELO_CARRY) {
  carry * final_ratings + (1 - carry) * ELO_MEAN
}

# Daily per-team series from a played-games table (output of elo_run_games).
# start_date: first game date of the season (the seed row is dated start_date - 1).
elo_daily_series <- function(played, seed, teams, start_date, end_date, season) {
  start_date <- as.Date(start_date); end_date <- as.Date(end_date)
  dates <- seq(start_date - 1L, end_date, by = "day")
  teams <- sort(unique(teams))
  r <- setNames(rep(ELO_MEAN, length(teams)), teams)
  if (length(seed)) r[intersect(names(seed), teams)] <- seed[intersect(names(seed), teams)]
  gp <- setNames(integer(length(teams)), teams)
  played <- played[order(played$game_date, as.character(played$game_id)), , drop = FALSE]
  rows <- vector("list", length(dates))
  for (j in seq_along(dates)) {
    d <- dates[j]
    todays <- played[played$game_date == d, , drop = FALSE]
    played_today <- setNames(rep(FALSE, length(teams)), teams)
    for (i in seq_len(nrow(todays))) {
      h <- todays$home[i]; a <- todays$away[i]
      r[[h]] <- todays$home_elo_post[i]; r[[a]] <- todays$away_elo_post[i]
      gp[[h]] <- gp[[h]] + 1L; gp[[a]] <- gp[[a]] + 1L
      played_today[[h]] <- TRUE; played_today[[a]] <- TRUE
    }
    rows[[j]] <- data.frame(season = as.integer(season), date = d, team = teams,
                            elo = unname(r), games_played = unname(gp),
                            played_today = unname(played_today),
                            stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

# Rating of every team on a given date from a daily series (the latest row on or
# before that date; dates before the seed row return the seed).
elo_on_date <- function(daily, date) {
  date <- max(as.Date(date), min(daily$date))
  sub <- daily[daily$date == min(date, max(daily$date)), c("team", "elo")]
  setNames(sub$elo, sub$team)
}

# Changes over `days` ending at end_date, with rank movement (rank 1 = highest).
elo_changes <- function(daily, end_date, days = c(7L, 14L)) {
  end_date <- min(as.Date(end_date), max(daily$date))
  now <- elo_on_date(daily, end_date)
  rank_now <- rank(-now, ties.method = "min")
  out <- data.frame(team = names(now), elo = unname(now), elo_rank = unname(rank_now),
                    stringsAsFactors = FALSE)
  for (d in days) {
    then <- elo_on_date(daily, end_date - d)[names(now)]
    rank_then <- rank(-then, ties.method = "min")
    out[[sprintf("elo_change_%dd", d)]] <- unname(now - then)
    # Positive rank change = moved up the table.
    out[[sprintf("elo_rank_change_%dd", d)]] <- unname(rank_then - rank_now)
  }
  out
}

# Build and persist the season's daily series.
#   current_games / prior_games: games tables as elo_run_games() expects.
#   Writes cache_path (e.g. cache/elo_daily_2027.rds) and returns
#   list(daily, played, seed_method, seed).
elo_build_season <- function(current_games, prior_games = NULL, season, end_date = NULL,
                             teams = NULL, cache_path = NULL) {
  seed_method <- "flat_1500"
  seed <- NULL
  if (!is.null(prior_games) && nrow(prior_games) > 0) {
    prior <- elo_run_games(prior_games)
    seed <- elo_carry_over(attr(prior, "final"))
    seed_method <- sprintf("prior_season_carry_%.2f", ELO_CARRY)
  }
  played <- elo_run_games(current_games, seed = seed)
  teams <- sort(unique(c(teams, current_games$home, current_games$away)))
  start_date <- min(as.Date(current_games$game_date))
  if (is.null(end_date)) end_date <- max(as.Date(current_games$game_date))
  daily <- elo_daily_series(played, seed, teams, start_date, end_date, season)
  attr(daily, "seed_method") <- seed_method
  attr(daily, "rules") <- list(k = ELO_K, home_advantage = ELO_HOME_ADV, mean = ELO_MEAN,
                               carry = ELO_CARRY,
                               mov_multiplier = "(|margin| + 3)^0.8 / (7.5 + 0.006 * winner_elo_diff)")
  if (!is.null(cache_path)) saveRDS(daily, cache_path)
  list(daily = daily, played = played, seed_method = seed_method, seed = seed)
}
