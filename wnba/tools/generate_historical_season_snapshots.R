# ==============================================================================
# tools/generate_historical_season_snapshots.R
#
# GitHub issue #69 (Standings/Bracket) + issue #70 (RAPM, sub-issue of #69 -- the RAPM third
# of #69 that was deliberately split out because it conflicted with rapm_engine.R's
# reattribute_to_current_roster_team() / pooled-cache season-filter behavior; see rapm_engine.R
# fit_rapm_ratings() header comment and CLAUDE.md for the resolved design).
#
# Generates REAL final (non-projected) per-season regular-season standings, playoff-series
# results, AND a real per-season-pooled-team RAPM leaderboard for 2019-2025 from
# data/box_scores_cache.rds (config.R's CACHE_TEAM_BOX) and cache/wnba_pbp_cache.rds via
# rapm_engine.R::fit_rapm_ratings(). 2019-2022 backfill (this extension): confirmed both
# source caches actually cover these seasons before running -- box_scores_cache.rds has
# season_type 2/3 rows for every year 2019-2022, and wnba_pbp_cache.rds$possessions has
# 23.5k-38k rows per season across the same range -- so the only reason this was previously
# deferred was scope/time, not missing data.
#
# RAPM note (issue #70): this is the ONLY caller in the repo that ever passes
# team_attribution = "season_pooled" to fit_rapm_ratings() -- it fits RAPM separately per
# historical season (seasons = yr, not ALL_SEASONS) and keeps the per-season
# possession-vote team (not the player's current/2026 roster team, which would be wrong for
# a historical snapshot). This script NEVER writes to cache/rapm_ratings.rds -- that file is
# owned exclusively by rapm_engine.R::estimate_rapm_ratings() (team_attribution =
# "current_roster", the live path).
#
# season_type mapping (empirically verified against the live cache this session via
# table(box$season_type) and spot-checking 2023 postseason game_ids/dates against the
# real WNBA playoff calendar): 2 = regular season, 3 = postseason. Not documented in
# config.R or wehoop's own docs -- re-verify against the live cache if this ever looks off.
#
# Standings tiebreak rule (ties in Win_Pct, which this box-score-only source cannot break
# any more meaningfully than the NBA/WNBA's real head-to-head/division tiebreakers, which
# aren't reconstructable from team-level box scores alone): Win_Pct desc, then Wins desc,
# then Team full name ascending (alphabetical) -- fully deterministic, no randomness.
#
# Playoff pairing: a "series" is every season_type==3 game between an unordered pair of
# teams in that season. Verified empirically (2023/2024/2025) that every such pair occurs
# exactly once per season with a single contiguous date range -- i.e. no team meets the same
# opponent in two different rounds of the same season in this data, so pairing on
# (season, unordered team pair) alone cleanly resolves one series per pairing.
# ==============================================================================

PROJECT_DIR <- here::here()
setwd(PROJECT_DIR)
source("config.R")
source("daily_ingest.R")
source("rapm_engine.R")

suppressPackageStartupMessages(library(dplyr))

SEASONS <- 2019:2025

# ------------------------------------------------------------------------------
# assign_bracket_rounds(bracket_df)
#
# Derives a `round` label for each series in a single season's bracket, purely
# from that season's own data (no new data source): series' earliest game_date
# (chronological order of play) plus the already-computed `winner` column.
#
# Algorithm (see tools/generate_historical_season_snapshots.R header / issue #69
# handoff notes for full rationale):
#   1. Order the season's series by the earliest game_date in each series'
#      `games` list-column (ascending).
#   2. Walk in that order, keeping a running wins_so_far count per team
#      (starts at 0 for every team at the top of the season).
#   3. round number for a series = 1 + max(wins_so_far[team_a], wins_so_far[team_b]).
#      Both participants should already have equal prior win counts (a round-N
#      matchup only happens between two teams who each won exactly N-1 prior
#      series that season) -- if they disagree, the chronological-ordering
#      assumption has broken down for this season and we stop() rather than
#      silently guessing a label.
#   4. After resolving winner, increment wins_so_far[winner].
#   5. Map round numbers -> labels using THIS season's own bracket size: number
#      of first-round participants = number of distinct teams across the
#      season's series; number of rounds = log2(that count) (validated to be a
#      whole number -- if not, that's a non-power-of-2 bracket, e.g. a play-in
#      game, and we fall back to numeric "Round N" labels for every round
#      instead of forcing Semifinals/Finals labels that don't fit).
#      Highest round number -> "Finals", one before -> "Semifinals", one before
#      that -> "Quarterfinals" (only if present), anything earlier -> "Round 1".
# ------------------------------------------------------------------------------
assign_bracket_rounds <- function(bracket_df, season = NULL) {
  if (nrow(bracket_df) == 0) {
    bracket_df$round <- character(0)
    return(bracket_df)
  }

  # Earliest game_date within each series' own games list (reuses the game_log
  # already built per-series -- no refetching from box).
  first_game_date <- vapply(bracket_df$games, function(gl) {
    min(vapply(gl, function(g) g$game_date, numeric(1)))
  }, numeric(1))

  order_idx <- order(first_game_date)
  n_series <- nrow(bracket_df)

  # Pre-2022 WNBA playoff format (2016-2021): 8 teams, 7 series with double-byes
  # for seeds 1-2 and single-byes for seeds 3-4.
  # Chronological series:
  #   Series 1-2: Round 1 (seeds 5-8 single elimination)
  #   Series 3-4: Round 2 (seeds 3-4 join, single elimination)
  #   Series 5-6: Semifinals (seeds 1-2 join, best of 5)
  #   Series 7:   Finals (best of 5)
  if (!is.null(season) && season %in% 2016:2021 && n_series == 7) {
    rounds <- character(n_series)
    rounds[order_idx[1:2]] <- "Round 1"
    rounds[order_idx[3:4]] <- "Round 2"
    rounds[order_idx[5:6]] <- "Semifinals"
    rounds[order_idx[7]]   <- "Finals"
    bracket_df$round <- rounds
    return(bracket_df)
  }

  wins_so_far <- new.env()
  round_number <- integer(nrow(bracket_df))

  for (i in order_idx) {
    team_a <- bracket_df$team_a[i]
    team_b <- bracket_df$team_b[i]
    wa <- if (exists(team_a, envir = wins_so_far, inherits = FALSE)) get(team_a, envir = wins_so_far) else 0L
    wb <- if (exists(team_b, envir = wins_so_far, inherits = FALSE)) get(team_b, envir = wins_so_far) else 0L

    if (wa != wb) {
      stop(sprintf(
        paste0("assign_bracket_rounds: chronological-reconstruction assumption broke down -- ",
                "series %s vs %s has mismatched prior win counts (%d vs %d). ",
                "Cannot safely assign a round label; stopping rather than guessing."),
        team_a, team_b, wa, wb
      ))
    }

    round_number[i] <- wa + 1L

    winner <- bracket_df$winner[i]
    current_winner_wins <- if (exists(winner, envir = wins_so_far, inherits = FALSE)) get(winner, envir = wins_so_far) else 0L
    assign(winner, current_winner_wins + 1L, envir = wins_so_far)
  }

  # Bracket size for this season: distinct teams across all its series.
  n_teams <- length(unique(c(bracket_df$team_a, bracket_df$team_b)))
  n_rounds_exact <- log2(n_teams)
  is_power_of_2 <- abs(n_rounds_exact - round(n_rounds_exact)) < 1e-9
  max_round <- max(round_number)

  if (is_power_of_2) {
    n_rounds <- round(n_rounds_exact)
    label_for <- function(rn) {
      from_top <- n_rounds - rn  # 0 = Finals, 1 = Semifinals, 2 = Quarterfinals (if earlier rounds exist), else Round 1
      if (from_top == 0) "Finals"
      else if (from_top == 1) "Semifinals"
      else if (from_top == 2 && rn > 1) "Quarterfinals"  # only a distinct stage when >1 round precedes it
      else "Round 1"
    }
  } else {
    # Non-power-of-2 bracket (e.g. a play-in game) -- don't force a label that
    # doesn't fit; use numeric round labels instead.
    label_for <- function(rn) sprintf("Round %d", rn)
  }

  bracket_df$round <- vapply(round_number, label_for, character(1))
  bracket_df
}

generate_historical_season_snapshots <- function(seasons = SEASONS) {
  box <- readRDS(CACHE_TEAM_BOX) |> filter_real_franchises()

  for (yr in seasons) {
    # ---- Standings (regular season, season_type == 2) ----
    reg <- box |> filter(season == yr, season_type == 2)

    standings <- reg |>
      group_by(team_abbreviation) |>
      summarise(
        Team    = dplyr::first(team_display_name),
        Wins    = sum(team_winner == TRUE, na.rm = TRUE),
        Losses  = sum(team_winner == FALSE, na.rm = TRUE),
        .groups = "drop"
      ) |>
      mutate(Win_Pct = Wins / (Wins + Losses)) |>
      arrange(desc(Win_Pct), desc(Wins), Team) |>
      mutate(Rank = row_number()) |>
      select(Rank, Team, Wins, Losses, Win_Pct)

    standings_path <- file.path(CACHE_DIR, sprintf("actual_wnba_standings_%d.rds", yr))
    saveRDS(standings, standings_path)
    message(sprintf("Wrote %s (%d teams).", standings_path, nrow(standings)))

    # ---- Playoff bracket (postseason, season_type == 3) ----
    post <- box |> filter(season == yr, season_type == 3)

    game_level <- post |>
      group_by(game_id) |>
      summarise(
        game_date  = dplyr::first(game_date),
        team_a     = dplyr::first(team_display_name),
        team_a_abb = dplyr::first(team_abbreviation),
        score_a    = dplyr::first(team_score),
        team_b     = dplyr::first(opponent_team_display_name),
        team_b_abb = dplyr::first(opponent_team_abbreviation),
        score_b    = dplyr::first(opponent_team_score),
        .groups = "drop"
      ) |>
      mutate(
        pair_key = paste(pmin(team_a_abb, team_b_abb), pmax(team_a_abb, team_b_abb))
      )

    bracket <- game_level |>
      group_by(pair_key) |>
      group_modify(function(games, key) {
        games <- games |> arrange(game_date)
        team_x <- games$team_a[1]
        team_x_abb <- games$team_a_abb[1]
        team_y <- games$team_b[1]
        team_y_abb <- games$team_b_abb[1]

        wins_x <- sum(
          (games$team_a_abb == team_x_abb & games$score_a > games$score_b) |
          (games$team_b_abb == team_x_abb & games$score_b > games$score_a)
        )
        wins_y <- nrow(games) - wins_x
        winner <- if (wins_x > wins_y) team_x else team_y

        game_log <- lapply(seq_len(nrow(games)), function(i) {
          list(
            game_date = games$game_date[i],
            team_a = games$team_a[i], score_a = games$score_a[i],
            team_b = games$team_b[i], score_b = games$score_b[i]
          )
        })

        tibble::tibble(
          team_a = team_x, team_b = team_y,
          games_played = nrow(games),
          series_length = nrow(games),
          winner = winner,
          games = list(game_log)
        )
      }) |>
      ungroup() |>
      select(-pair_key)

    # In 2016-2021, WNBA used a bye-based format; assign_bracket_rounds() handles this
    # when given season = yr.
    bracket_rounds <- tryCatch(
      assign_bracket_rounds(bracket, season = yr),
      error = function(e) {
        warning(sprintf(
          "Skipping playoff_bracket_results_%d.rds -- assign_bracket_rounds() failed: %s",
          yr, conditionMessage(e)
        ))
        NULL
      }
    )

    if (!is.null(bracket_rounds)) {
      bracket_path <- file.path(CACHE_DIR, sprintf("playoff_bracket_results_%d.rds", yr))
      saveRDS(bracket_rounds, bracket_path)
      message(sprintf("Wrote %s (%d series).", bracket_path, nrow(bracket_rounds)))
    }

    # ---- RAPM (issue #70): real, season-specific, season-pooled-team snapshot ----
    # team_attribution = "season_pooled" is used ONLY here in the whole repo -- it fits RAPM
    # for this single historical season (seasons = yr, not ALL_SEASONS) and keeps the
    # per-season possession-vote team instead of the player's current (2026) roster team,
    # which would be wrong for a historical snapshot. Per fit_rapm_ratings()'s documented
    # contract, this path hard-stops via stop() rather than falling back to the career-pooled
    # box-score fallback if real possession data isn't available for this season -- we let
    # that propagate rather than catching it, so a missing-data problem for one pilot season
    # is loud, not silently swallowed into a wrong leaderboard.
    rapm_season <- fit_rapm_ratings(seasons = yr, lambda = 900, team_attribution = "season_pooled")
    rapm_season$season <- yr

    rapm_path <- file.path(CACHE_DIR, sprintf("rapm_ratings_%d.rds", yr))
    saveRDS(rapm_season, rapm_path)
    message(sprintf("Wrote %s (%d players, data_source = %s).",
                     rapm_path, nrow(rapm_season),
                     paste(unique(rapm_season$data_source), collapse = ",")))
  }
}

generate_historical_season_snapshots()
