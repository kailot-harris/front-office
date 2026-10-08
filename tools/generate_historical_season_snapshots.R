# ==============================================================================
# tools/generate_historical_season_snapshots.R
#
# GitHub issue #69 (Standings/Bracket) + issue #70 (RAPM, sub-issue of #69 -- the RAPM third
# of #69 that was deliberately split out because it conflicted with rapm_engine.R's
# reattribute_to_current_roster_team() / pooled-cache season-filter behavior; see rapm_engine.R
# fit_rapm_ratings() header comment and CLAUDE.md for the resolved design).
#
# Generates REAL final (non-projected) per-season regular-season standings, playoff-series
# results, AND a real per-season-pooled-team RAPM leaderboard for 2023-2025 from
# data/box_scores_cache.rds (config.R's CACHE_TEAM_BOX) and cache/wnba_pbp_cache.rds via
# rapm_engine.R::fit_rapm_ratings(). 2019-2022 backfill is a separate future ticket.
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

SEASONS <- c(2023, 2024, 2025)

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

    bracket_path <- file.path(CACHE_DIR, sprintf("playoff_bracket_results_%d.rds", yr))
    saveRDS(bracket, bracket_path)
    message(sprintf("Wrote %s (%d series).", bracket_path, nrow(bracket)))

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
