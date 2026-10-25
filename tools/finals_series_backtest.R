# ==============================================================================
# finals_series_backtest.R
# Path: tools/finals_series_backtest.R
#
# Walk-forward backtest of the series-level Finals forecast: what the model
# would have said about the 2026 Finals at each point in the series, given ONLY
# the games that had been played at that moment.
#
# WHY THIS EXISTS. cache/series_length_predictions.rds (generated 2026-10-04)
# archives the two semifinal forecasts but has `finals = NULL` -- on 2026-10-04
# the Finals matchup did not yet exist, so no pre-series Finals forecast was
# ever logged, and build_playoff_bracket_2026.R correctly renders the Finals
# with prediction$available = FALSE rather than fabricating one. This script
# does NOT retro-fill that gap and pass the result off as a contemporaneous
# forecast. Every row it writes is explicitly labeled a reconstruction, the same
# way build_playoff_bracket_2026.R labels its Round 1 rows.
#
# REUSES, NEVER RESTATES:
#   - config.R                     WNBA_HCA, WNBA_MARGIN_SIGMA, CACHE_TEAM_BOX,
#                                  CURRENT_SEASON
#   - playoff_simulator.R          PLAYOFF_FORMATS (home-court pattern),
#                                  get_playoff_adjusted_rating()
#   - tools/series_length_predictor.R
#                                  series_length_distribution() -- used as the
#                                  correctness oracle for the mid-series DP
#                                  below (see validate_against_production()).
#   - daily_ingest.R               filter_real_franchises() -- CLAUDE.md requires
#                                  the CONN->CON normalization + exhibition-row
#                                  drop BEFORE any aggregation.
#
# THE ONE PIECE OF NEW MATH. series_length_distribution() always starts from
# 0-0. A mid-series forecast needs to start from (wins_high, wins_low), so
# series_dp() below generalizes it to an arbitrary live state. It uses the SAME
# two probability formulas (pnorm of the rating gap +/- WNBA_HCA over
# WNBA_MARGIN_SIGMA) and the SAME PLAYOFF_FORMATS home_flags lookup; only the
# initial state differs. validate_against_production() asserts the two agree to
# 1e-9 at the 0-0 state, so this cannot silently drift from the shipped model.
#
# FAIL-SAFE (repo convention): if the box-score cache is missing, or the Finals
# cannot be located in it, the script warns and exits without writing, rather
# than inventing a slate. It never overwrites an archived pre-game forecast.
#
# Output: cache/finals_series_backtest_2026.rds
# ==============================================================================

if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is required to derive PROJECT_DIR portably. Install it with install.packages('here').")
}
PROJECT_DIR <- here::here()
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# Sourcing the predictor for its functions must not fire its demo autorun, which
# re-simulates every series and targets the archived forecast file.
Sys.setenv(WNBA_SERIES_LENGTH_NO_AUTORUN = "1")
if (!exists("WNBA_HCA") || !exists("WNBA_MARGIN_SIGMA")) source("config.R")
if (!exists("series_length_distribution")) source("tools/series_length_predictor.R")
if (!exists("filter_real_franchises")) source("daily_ingest.R")

.LOG_SCRIPT <- "finals_series_backtest.R"
# CLAUDE.md: read the path from config.R, never restate the filename locally.
OUT_PATH <- CACHE_FINALS_SERIES_BACKTEST

message(">>> [FINALS BACKTEST] Walk-forward Finals series forecast reconstruction...")

# ------------------------------------------------------------------------------
# Generalized exact DP over series state. Identical model to
# series_length_distribution(); only the starting state is a parameter.
# ------------------------------------------------------------------------------
series_dp <- function(net_high, net_low, wins_high = 0L, wins_low = 0L,
                      format = "bo7", hca_pts = WNBA_HCA) {
  fmt <- PLAYOFF_FORMATS[[format]]
  thr <- fmt$win_threshold
  max_games <- length(fmt$home_flags)
  if (wins_high >= thr || wins_low >= thr) {
    stop("series_dp() called on an already-decided state; nothing left to forecast.")
  }

  diff <- net_high - net_low
  p_home <- pnorm((diff + hca_pts) / WNBA_MARGIN_SIGMA)
  p_away <- pnorm((diff - hca_pts) / WNBA_MARGIN_SIGMA)

  live <- c(1)
  names(live) <- paste(wins_high, wins_low)
  length_probs <- setNames(numeric(max_games), as.character(seq_len(max_games)))
  p_game_played <- numeric(max_games)
  p_game_win_high <- rep(NA_real_, max_games)
  p_high_series <- 0

  while (length(live) > 0) {
    nxt <- numeric(0)
    for (k in names(live)) {
      mass <- live[[k]]
      ij <- as.integer(strsplit(k, " ", fixed = TRUE)[[1]])
      g <- ij[1] + ij[2] + 1L
      p <- if (isTRUE(fmt$home_flags[g])) p_home else p_away
      p_game_played[g] <- p_game_played[g] + mass
      p_game_win_high[g] <- p
      for (high_wins in c(TRUE, FALSE)) {
        ni <- ij[1] + high_wins
        nj <- ij[2] + !high_wins
        m <- mass * if (high_wins) p else (1 - p)
        if (ni >= thr || nj >= thr) {
          length_probs[g] <- length_probs[g] + m
          if (ni >= thr) p_high_series <- p_high_series + m
        } else {
          kk <- paste(ni, nj)
          nxt[kk] <- (if (is.na(nxt[kk])) 0 else nxt[kk]) + m
        }
      }
    }
    live <- nxt
  }

  stopifnot(abs(sum(length_probs) - 1) < 1e-9)
  keep <- length_probs > 0
  list(
    distribution = tibble(length = as.integer(names(length_probs)[keep]),
                          probability = unname(length_probs[keep])),
    p_high_series = p_high_series,
    expected_length = sum(as.numeric(names(length_probs)) * length_probs),
    per_game = tibble(game = seq_len(max_games),
                      p_game_played = p_game_played,
                      p_high_wins_game = p_game_win_high)
  )
}

# Fair American moneyline from a probability (no vig).
fair_ml <- function(p) if (p >= 0.5) round(-100 * p / (1 - p)) else round(100 * (1 - p) / p)

# ------------------------------------------------------------------------------
# Correctness oracle: at 0-0 the generalized DP must reproduce the production
# series_length_distribution() exactly. Asserted, not assumed.
# ------------------------------------------------------------------------------
validate_against_production <- function(net_high, net_low, format = "bo7") {
  prod <- series_length_distribution("high", "low", net_high, net_low, format = format)
  mine <- series_dp(net_high, net_low, 0L, 0L, format = format)$distribution
  # series_length_predictor.R line 186 rounds its probabilities to 6 dp before
  # returning, so the comparison is made against ours rounded the same way --
  # otherwise an exact match still fails by up to 5e-7 on pure presentation
  # rounding. Tolerance stays at 1e-9 so a REAL divergence is still caught.
  mine$probability <- round(mine$probability, 6)
  joined <- dplyr::inner_join(as_tibble(prod), mine, by = "length",
                              suffix = c("_prod", "_mine"))
  worst <- max(abs(joined$probability_prod - joined$probability_mine))
  if (nrow(joined) != nrow(mine) || worst > 1e-9) {
    stop(sprintf("Mid-series DP diverged from production series_length_distribution() (max abs diff %.2e).", worst))
  }
  message(sprintf(">>> [FINALS BACKTEST] DP validated against production engine at 0-0 (max abs diff %.2e).", worst))
  invisible(worst)
}

# ------------------------------------------------------------------------------
# Resolve the Finals from box scores rather than hardcoding the scorelines, so
# this stays correct as further games are played.
# ------------------------------------------------------------------------------
load_finals_games <- function(high_abb, low_abb, season_yr = CURRENT_SEASON) {
  if (!file.exists(CACHE_TEAM_BOX)) {
    warning(sprintf(">>> [FINALS BACKTEST] %s not found -- cannot run backtest.", CACHE_TEAM_BOX))
    return(NULL)
  }
  box <- filter_real_franchises(readRDS(CACHE_TEAM_BOX)) %>%
    filter(season == season_yr) %>%
    mutate(game_day = as.Date(game_date))

  finals <- box %>%
    filter(season_type == 3L,
           team_abbreviation == high_abb,
           opponent_team_abbreviation == low_abb) %>%
    arrange(game_day)
  if (nrow(finals) == 0) {
    warning(">>> [FINALS BACKTEST] No postseason games found between the two named teams.")
    return(NULL)
  }
  finals %>%
    transmute(game = row_number(), game_day,
              score_high = team_score, score_low = opponent_team_score,
              high_won = team_score > opponent_team_score)
}

# ------------------------------------------------------------------------------
# Net ratings as of a cutoff: mean scoring margin over every CURRENT_SEASON game
# played strictly BEFORE `cutoff`, then run through playoff_simulator.R's
# get_playoff_adjusted_rating().
#
# `season_types` controls the information set:
#   c(2L, 3L) -- everything available at that moment (regular season + whatever
#                postseason has been played). This is the honest walk-forward
#                set and is what the reported forecasts use.
#   2L        -- regular season only. Kept as a leak-free comparison baseline,
#                matching the default that GitHub issue #92 established for
#                load_real_2026_playoff_seeds().
# Because the cutoff is strictly before the game being forecast, neither variant
# can see the outcome it is predicting.
# ------------------------------------------------------------------------------
ratings_as_of <- function(box, cutoff, season_types, high_abb, low_abb) {
  g <- box %>% filter(game_day < cutoff, season_type %in% season_types)
  agg <- g %>%
    group_by(team_abbreviation) %>%
    summarise(n = n(), net = mean(team_score - opponent_team_score), .groups = "drop")
  pick <- function(a, col) {
    v <- agg[[col]][agg$team_abbreviation == a]
    if (length(v) == 0) NA_real_ else v
  }
  list(n_high = pick(high_abb, "n"), n_low = pick(low_abb, "n"),
       raw_high = pick(high_abb, "net"), raw_low = pick(low_abb, "net"))
}

# ------------------------------------------------------------------------------
# Main entry point.
# ------------------------------------------------------------------------------
run_finals_backtest <- function(high_abb = "GS", high_name = "Golden State Valkyries",
                                low_abb = "ATL", low_name = "Atlanta Dream",
                                season_yr = CURRENT_SEASON, format = "bo7",
                                write = TRUE) {
  games <- load_finals_games(high_abb, low_abb, season_yr)
  if (is.null(games)) return(invisible(NULL))

  box <- filter_real_franchises(readRDS(CACHE_TEAM_BOX)) %>%
    filter(season == season_yr) %>%
    mutate(game_day = as.Date(game_date))

  # One information set per decision point: before G1, then after each played
  # game. The cutoff for "after game k" is the day of game k+1 when it exists,
  # else the day after the last played game (so the k-th game is included and
  # nothing later is).
  n_played <- nrow(games)
  cutoffs <- vapply(seq_len(n_played + 1L) - 1L, function(k) {
    if (k == 0L) as.character(games$game_day[1])
    else if (k < n_played) as.character(games$game_day[k + 1L])
    else as.character(games$game_day[n_played] + 1L)
  }, character(1))

  validated <- FALSE
  rows <- list()
  for (k in seq_along(cutoffs) - 1L) {
    cutoff <- as.Date(cutoffs[k + 1L])
    wins_high <- sum(games$high_won[seq_len(k)])
    wins_low <- k - wins_high
    label <- if (k == 0L) "pre-series" else sprintf("after G%d", k)

    for (types in list(c(2L, 3L), 2L)) {
      set_name <- if (length(types) == 2L) "all games to date" else "regular season only"
      r <- ratings_as_of(box, cutoff, types, high_abb, low_abb)
      if (is.na(r$raw_high) || is.na(r$raw_low)) {
        warning(sprintf(">>> [FINALS BACKTEST] No rating data for %s / %s -- skipped.", label, set_name))
        next
      }
      net_high <- get_playoff_adjusted_rating(high_name, r$raw_high)
      net_low  <- get_playoff_adjusted_rating(low_name,  r$raw_low)
      if (!validated) {
        validate_against_production(net_high, net_low, format)
        validated <- TRUE
      }

      # Both conditionings are preserved: the live forecast (conditioned on the
      # actual series state) and the same ratings replayed from 0-0, which
      # isolates how much of any swing is the ratings update vs. the scoreboard.
      for (cond in c("actual_state", "from_0_0")) {
        wh <- if (cond == "actual_state") wins_high else 0L
        wl <- if (cond == "actual_state") wins_low  else 0L
        if (wh >= PLAYOFF_FORMATS[[format]]$win_threshold ||
            wl >= PLAYOFF_FORMATS[[format]]$win_threshold) next
        d <- series_dp(net_high, net_low, wh, wl, format = format)
        rows[[length(rows) + 1L]] <- tibble(
          info_set = label, cutoff_date = cutoff,
          games_played = k, state_high = wh, state_low = wl,
          information = set_name, conditioning = cond,
          team_high = high_name, team_high_abb = high_abb,
          team_low = low_name, team_low_abb = low_abb,
          n_games_high = r$n_high, n_games_low = r$n_low,
          net_raw_high = r$raw_high, net_raw_low = r$raw_low,
          net_adj_high = net_high, net_adj_low = net_low,
          p_high_series = d$p_high_series,
          p_low_series = 1 - d$p_high_series,
          fair_ml_high = fair_ml(d$p_high_series),
          fair_ml_low = fair_ml(1 - d$p_high_series),
          expected_length = d$expected_length,
          distribution = list(d$distribution),
          per_game = list(d$per_game)
        )
      }
    }
  }

  out <- bind_rows(rows)
  # READER-FACING STRING. This is rendered verbatim on the public bracket page, so
  # it is written for a general audience: no filenames, no field names, no code
  # formatting. It explains WHY no forecast exists rather than just asserting it,
  # because "none was logged" alone reads like an admission of a bug. The opening
  # sentence is kept exactly as-is -- the web component matches and strips it when
  # it supplies the same sentence as a styled heading, and reverting to the full
  # string if the wording ever changes is the safe failure (a repeated sentence,
  # never a dropped disclaimer).
  attr(out, "provenance") <- paste0(
    "RECONSTRUCTION, not an archived forecast. Computed ", as.character(Sys.Date()),
    ". The model never published a Finals prediction before the series began — when its last ",
    "forecast was saved on 2026-10-04, both semi-finals were still in progress, so this matchup ",
    "did not yet exist. Each row below is a replay that sees only the ", season_yr, " games ",
    "finished before its own cutoff date, so none of them can peek at the result it is predicting."
  )
  attr(out, "generated_at") <- Sys.time()
  attr(out, "finals_games") <- games

  if (isTRUE(write)) {
    saveRDS(out, OUT_PATH)
    message(sprintf(">>> [FINALS BACKTEST] Saved %s (%d rows across %d information sets).",
                    OUT_PATH, nrow(out), length(unique(out$info_set))))
  }
  invisible(out)
}

if (!interactive() && !identical(Sys.getenv("WNBA_FINALS_BACKTEST_NO_AUTORUN"), "1")) {
  invisible(run_finals_backtest())
}
