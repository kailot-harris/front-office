# Task Assignments: Phase 8 (Early-Season Rating Shrinkage + Staking Gate)
Date: 2026-09-17

**Naming note:** eighth entry in this repo's `task_assignments_phaseN.md` file-numbering series.
This is a remediation wave, not a new DAG stage — no new `run_stage()` calls are added, all three
tasks edit existing pipeline stages in place.

## Overview
Week 2 predictions surfaced a real calibration problem: with only 1-2 games of real current-season
data per team, `team_ratings_engine.R`'s power ratings are extremely noisy, and that noise
propagates through `market_odds_engine.R` into implausible EV figures (e.g. +224%, +166% "value
bets" that no real sharp market would ever actually offer). This wave addresses it with three
changes, agreed with the user after a benefits/drawbacks comparison of five candidate approaches:

1. **Rating shrinkage toward an informed prior** (unifies the user's approaches #1 "shrink toward
   league average" and #2 "carry over prior-season final rating" into one mechanism): each team's
   current-season power rating is blended with its **prior-season final rating** (falling back to
   league-average = 0 only if no prior-season data exists), weighted by how many real current-season
   games that team has actually played. Early in the season the blend leans heavily on the
   informed prior-season prior; by mid-season it leans almost entirely on real current-season form.
2. **Minimum-sample staking gate**: `market_odds_engine.R` must not recommend a real stake
   (`Bankroll_Rec`) on any game where either team has fewer than a configured minimum number of
   real current-season games played — regardless of how large the computed EV looks. The
   prediction/EV numbers themselves still display (for transparency/diagnostic purposes), but the
   stake and the dispatch-worthiness must both reflect the sample-size reality.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P8-A | 1 | `nfl_shrinkage_agent` | `team_ratings_engine.R` | Approaches #1+#2: prior-season-informed shrinkage, `games_played` column propagated to `projected_matchups.rds` | PENDING |
| P8-B | 2 | `nfl_staking_gate_agent` | `market_odds_engine.R` | Approach #4: minimum-sample staking gate, reads `games_played` from P8-A's new columns | PENDING |
| P8-C | 3 | `nfl_notify_gate_agent` | `notify_bets.R` | Excludes insufficient-sample rows from Discord dispatch, reads P8-B's new `Status`/`Bankroll_Rec` values | PENDING |

## File-ownership disjointness check
All three files already exist and are each edited by exactly one task, in strict sequence (each
depends on the previous task's new output columns, not just its function existing) — P8-A must
fully land before P8-B starts, P8-B before P8-C starts. No two tasks touch the same file.

## Wave dependency graph
```
Wave 1: nfl_shrinkage_agent (team_ratings_engine.R)
   |  cache/team_ratings.rds gets new columns: games_played, prior_season_rating,
   |  shrinkage_weight, power_rating (now shrinkage-adjusted)
   |  cache/projected_matchups.rds gets new columns: home_games_played, away_games_played
   v
Wave 2: nfl_staking_gate_agent (market_odds_engine.R)
   |  reads home_games_played/away_games_played from projected_matchups.rds
   |  cache/latest_value_bets.rds: Bankroll_Rec forced to 0 and Status set to an
   |  "INSUFFICIENT SAMPLE" marker when either team is under the games threshold
   v
Wave 3: nfl_notify_gate_agent (notify_bets.R)
   reads the new Status marker, excludes those rows from the actionable-bets filter
   regardless of EV/CLV
```

## Interface contract additions

| Script | New/changed behavior | New config.R constants (narrow documented exception, same pattern as prior waves) |
| :--- | :--- | :--- |
| `team_ratings_engine.R` | `run_team_ratings()` unchanged signature; internally computes each team's real current-season `games_played` (from `CACHE_SCHEDULES` completed games in `CURRENT_SEASON`), derives a `prior_season_rating` per team from `CACHE_EPA_METRICS`'s final rolling EPA values in the most recent season `< CURRENT_SEASON` (run through the same EPA-differential-to-points formula already used for the current rating — do not invent a second formula), blends `power_rating <- weight * current_raw_rating + (1 - weight) * prior_season_rating` where `weight = games_played / (games_played + RATING_SHRINKAGE_GAMES_K)`, falls back to `prior_season_rating = 0` (league average) only if a team genuinely has no prior-season data | `RATING_SHRINKAGE_GAMES_K` (new — pick a defensible starting value, e.g. 4, and **document explicitly that it is NOT yet empirically backtested**, same honesty convention as `ROLLING_WINDOW_SIZE`'s existing comment) |
| `market_odds_engine.R` | `run_market_odds_engine()` unchanged signature; joins in `home_games_played`/`away_games_played`, and when `min(home_games_played, away_games_played) < MIN_SAMPLE_GAMES_FOR_STAKE`, forces `Bankroll_Rec <- 0` and `Status <- "⚠ INSUFFICIENT SAMPLE (early season)"` (or similar) **regardless of computed EV** — EV/Model_Win_Prob columns still populate normally for transparency | `MIN_SAMPLE_GAMES_FOR_STAKE` (new — pick a defensible starting value, e.g. 3, document it's a starting heuristic not a backtested threshold) |
| `notify_bets.R` | `run_notify_bets()` unchanged signature; the actionable-bets filter must exclude any row whose `Status` is the insufficient-sample marker, in addition to the existing `EV_Percent >= 3.0 & Exp_CLV >= -0.5` filter — a game must clear BOTH gates to be dispatched | none |

## Constraints
- Do not change `NFL_MARGIN_SIGMA`, `NFL_HCA`, or `ROLLING_WINDOW_SIZE` in this wave — this is
  specifically about the ratings/staking layer, not re-deriving the empirically-fit constants.
- The prior-season EPA-to-rating formula must be the **exact same formula** already used for the
  current-season rating (read the existing code, reuse the function/logic) — do not write a second,
  subtly-different formula that could itself drift (the exact class of bug this repo's CLAUDE.md
  warns about).
- `RATING_SHRINKAGE_GAMES_K` and `MIN_SAMPLE_GAMES_FOR_STAKE` are two **distinct** constants for two
  distinct purposes (one shapes the rating blend, one gates staking) — do not conflate them into one
  constant even though both are "some number of games."
- Re-run the full pipeline after all three tasks land and verify Week 2 output changes sensibly:
  win probabilities should be less extreme than before (less mass near 0/1), and any Week 2 game
  where a team has only 1 prior game should show `Bankroll_Rec = 0` and the insufficient-sample
  Status in `cache/latest_value_bets.rds`, and must NOT appear in `notify_bets.R`'s dispatched
  picks.
- Run `.claude/skills/config-constant-drift-audit` after all three land (two new constants).

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
