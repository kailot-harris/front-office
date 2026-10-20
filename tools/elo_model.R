# ==============================================================================
# MOV-Weighted Elo Rating Model, with Season Carryover + Fatigue Covariate
# (Phase 3, model-quality remediation)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/elo_model.R
#
# Per docs/HANDOFF.md's roadmap: a structurally different candidate from Phases 1-2's
# EPA-differential/ridge lineage - a classic margin-of-victory-weighted Elo rating,
# referencing FiveThirtyEight's publicly documented NFL Elo methodology (github.com/
# fivethirtyeight/nfl-elo-game - K=20, MOV multiplier shape, ~2/3 season-carryover -
# see the research this repo's model-quality plan was built from). Two constants are
# taken directly from that public reference rather than independently re-derived here
# (ELO_HCA_POINTS, the MOV multiplier's 2.2 constant) - a DOCUMENTED DEVIATION from
# this repo's usual "every constant gets its own derivation script" discipline, noted
# honestly as a follow-up rather than silently treated as equivalent to an empirical
# derivation. ELO_K_FACTOR (the rating's sensitivity to each game's surprise) IS
# empirically derived via tools/derive_elo_k.R, same stats::optimize() discipline as
# every other constant in this repo.
#
# UNLIKE Phases 1-2's candidates, Elo cannot be computed as a one-shot vectorized
# transform of a precomputed snapshot table - ratings evolve SEQUENTIALLY, game by
# game, in chronological order, carrying state across the whole history (including
# across season boundaries via the carryover rule). run_elo_walkforward() is
# therefore a genuine sequential simulation, not a predict_fn(games, params)
# one-liner - tools/model_backtest_harness.R wires it in via a candidate whose
# predict_fn simply calls this function once and reads off its pre-update
# probabilities (which are, by construction, computed from information strictly
# before that game - no lookahead, since each team's rating is only ever updated
# AFTER its own game is scored).
#
# FATIGUE COVARIATE: per the plan's "Elo-update covariate OR an additive margin
# term" alternative, this implementation uses the additive-margin form: Elo's own
# rating UPDATE (the K/MOV-multiplier math) is untouched, pure Elo, using only each
# team's own rating history - but the FINAL reported win probability additionally
# folds in fatigue_engine.R's real, already-computed fatigue_drag_pts (the exact
# same quantity market_odds_engine.R already applies to the EPA model), converted
# into Elo's own point-margin scale via the standard "~25 Elo points per point of
# scoring margin" conversion (also a FiveThirtyEight reference figure, not
# independently re-derived) and then converted to a probability via pnorm()/
# NFL_MARGIN_SIGMA - consistent with how every OTHER candidate in this repo produces
# its final probability, rather than Elo's own native logistic curve, so this
# candidate's OUTPUT stays comparable to every other candidate in the harness even
# though its internal rating UPDATE math is genuinely different.
#
# No top-level side effects beyond function/constant definitions - safe to source()
# from any script.
# ==============================================================================

ELO_HCA_POINTS       <- 48    # FiveThirtyEight reference value, not independently re-derived
ELO_MOV_C            <- 2.2   # FiveThirtyEight reference value, not independently re-derived
ELO_POINTS_PER_MARGIN_PT <- 25 # FiveThirtyEight reference conversion, not independently re-derived
ELO_INITIAL_RATING   <- 1500
ELO_SEASON_CARRYOVER <- 2 / 3  # fraction of a team's rating retained at a new season's first game

# ------------------------------------------------------------------------------------------
# run_elo_walkforward(): sch_completed sorted chronologically, fatigue = CACHE_FATIGUE_METRICS
# (long format, one row per team per game - see fatigue_engine.R). k = ELO_K_FACTOR candidate
# value (the one constant this file lets a caller vary, since it's the one actually optimized
# via tools/derive_elo_k.R). Returns one row per game with PRE-update elo ratings/probabilities
# (no lookahead by construction) plus the fatigue-adjusted final probability.
# ------------------------------------------------------------------------------------------
run_elo_walkforward <- function(sch_completed, fatigue, k, return_final_state = FALSE) {
  sch_completed <- sch_completed |> dplyr::arrange(gameday, game_id)
  fatigue_lu <- fatigue |> dplyr::select(game_id, team, fatigue_drag_pts)

  elo <- new.env(parent = emptyenv())     # team -> current rating
  last_season <- new.env(parent = emptyenv()) # team -> season of that team's most recent game

  get_elo <- function(team, season) {
    if (!exists(team, envir = elo, inherits = FALSE)) {
      assign(team, ELO_INITIAL_RATING, envir = elo)
      assign(team, season, envir = last_season)
      return(ELO_INITIAL_RATING)
    }
    prev_season <- get(team, envir = last_season, inherits = FALSE)
    rating <- get(team, envir = elo, inherits = FALSE)
    if (season > prev_season) {
      rating <- ELO_SEASON_CARRYOVER * rating + (1 - ELO_SEASON_CARRYOVER) * ELO_INITIAL_RATING
      assign(team, rating, envir = elo)
    }
    assign(team, season, envir = last_season)
    rating
  }

  n <- nrow(sch_completed)
  out <- vector("list", n)

  fatigue_home <- fatigue_lu |> dplyr::rename(home_drag = fatigue_drag_pts)
  fatigue_away <- fatigue_lu |> dplyr::rename(away_drag = fatigue_drag_pts)

  for (i in seq_len(n)) {
    g <- sch_completed[i, ]
    h <- g$home_team; a <- g$away_team; s <- g$season

    elo_h <- get_elo(h, s)
    elo_a <- get_elo(a, s)

    elo_diff <- (elo_h + ELO_HCA_POINTS) - elo_a
    p_elo <- 1 / (1 + 10^(-elo_diff / 400))

    home_win <- as.integer(g$home_score > g$away_score)
    y <- if (g$home_score == g$away_score) 0.5 else home_win

    mov <- abs(g$home_score - g$away_score)
    winner_elo_diff <- if (home_win == 1) elo_diff else -elo_diff
    mov_mult <- log(max(mov, 1) + 1) * (ELO_MOV_C / (0.001 * winner_elo_diff + ELO_MOV_C))
    shift <- k * mov_mult * (y - p_elo)

    assign(h, elo_h + shift, envir = elo)
    assign(a, elo_a - shift, envir = elo)

    h_drag <- fatigue_home$home_drag[fatigue_home$game_id == g$game_id & fatigue_home$team == h]
    a_drag <- fatigue_away$away_drag[fatigue_away$game_id == g$game_id & fatigue_away$team == a]
    h_drag <- if (length(h_drag) == 0 || is.na(h_drag[1])) 0 else h_drag[1]
    a_drag <- if (length(a_drag) == 0 || is.na(a_drag[1])) 0 else a_drag[1]
    fatigue_adj <- a_drag - h_drag

    elo_margin_pts <- elo_diff / ELO_POINTS_PER_MARGIN_PT
    adjusted_margin <- elo_margin_pts + fatigue_adj

    out[[i]] <- data.frame(
      game_id = g$game_id, season = s, week = g$week,
      home_team = h, away_team = a, home_win = home_win,
      home_elo_pre = elo_h, away_elo_pre = elo_a,
      elo_prob_pure = p_elo, elo_margin_pts = elo_margin_pts,
      fatigue_adj = fatigue_adj,
      home_win_prob = pnorm(adjusted_margin / NFL_MARGIN_SIGMA),
      stringsAsFactors = FALSE
    )
  }

  result <- dplyr::bind_rows(out)

  if (!return_final_state) return(result)

  # Live-inference support (Phase 3 ensemble): expose each team's final rating/season-of-last-
  # game so a caller can project ratings forward to an upcoming game (applying the same season-
  # carryover rule for any team that hasn't played yet this season) without re-running the whole
  # sequential simulation a second time.
  teams_seen <- ls(envir = elo)
  final_elo <- setNames(vapply(teams_seen, function(t) get(t, envir = elo, inherits = FALSE), numeric(1)), teams_seen)
  final_season <- setNames(vapply(teams_seen, function(t) get(t, envir = last_season, inherits = FALSE), numeric(1)), teams_seen)
  list(games = result, final_elo = final_elo, final_season = final_season)
}

# ------------------------------------------------------------------------------------------
# project_elo_rating(): apply the season-carryover rule to a team's stored final rating if it
# hasn't yet played in `current_season` - the same lazy-carryover logic run_elo_walkforward()
# applies internally, exposed here so live inference doesn't need to duplicate it.
# ------------------------------------------------------------------------------------------
project_elo_rating <- function(rating, last_played_season, current_season) {
  if (is.na(rating) || is.na(last_played_season)) return(NA_real_)
  if (current_season > last_played_season) {
    return(ELO_SEASON_CARRYOVER * rating + (1 - ELO_SEASON_CARRYOVER) * ELO_INITIAL_RATING)
  }
  rating
}
