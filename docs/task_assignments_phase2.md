# Phase 2 Task Assignments: Rating Engines (Pythagorean Baseline + Team Elo)

**Phase**: 2 — Rating Engines (Pythagorean Win Expectation + Team Elo Engine)  
**Epic**: #11 (MLB Analytics Engine Build)  
**Parent Tracker Issue**: #15  
**Date**: 2026-10-18  
**Status**: Wave 1 Complete (Issue #16 closed); Wave 2 Queued (Issue #17)  

---

## 1. Wave Architecture & Interface Contracts

Phase 2 builds the core team and pitcher rating systems for the MLB Analytics engine. It consists of two sequential waves:
- **Wave 1 (Issue #16)**: Baseline Pythagorean Win Expectation (`mlb_pythag_baseline.R`) and Team Elo Rating Engine (`mlb_elo_engine.R`) with pregame starting-pitcher adjustment.
- **Wave 2 (Issue #17)**: Empirical constant calibration tool (`tools/derive_mlb_constants.R`) and park-factor adjustment decision.

### Cache Directory Isolation

All stages write exclusively to isolated subdirectories under `cache/` managed by `cache_path(stage, ...)` from `config.R`:
- `cache/pythag/` — Pythagorean standings, residuals, and win expectation estimates (`mlb_pythag_baseline.R`)
- `cache/ratings/` — Team Elo ratings, game history, and pitcher rolling Game Score tracker (`mlb_elo_engine.R`)

---

## 2. Component Deliverables & Status

### Wave 1 Deliverables (Issue #16)

| Component | File | Callable Contract | Output / Cache | Status |
|---|---|---|---|---|
| **Pythagorean Baseline** | `mlb_pythag_baseline.R` | `run_pythag_baseline(season = 2024, method = "pythagenpat", force_refresh = FALSE)` | `cache/pythag/pythag_baseline_<yr>.rds`, `cache/pythag/mlb_pythag_standings.rds` | **Done** (verified live: 30 MLB teams evaluated across Pythagenpat, Pythagenport, Fixed 1.83, and Fixed 2.0; RMSE ~3.23–3.35 wins) |
| **Team Elo Rating Engine** | `mlb_elo_engine.R` | `run_elo_engine(seasons = 2024, force_refresh = FALSE)` | `cache/ratings/mlb_team_ratings.rds`, `cache/ratings/mlb_elo_history.rds`, `cache/ratings/pitcher_rgs_tracker.rds` | **Done** (verified live: 2,432 regular season games simulated walk-forward; Brier score 0.2447, Accuracy 55.35%; 682 pitchers tracked) |
| **Pipeline Integration** | `run_full_pipeline.R` | `run_full_pipeline(season = 2024, force_refresh = FALSE)` | Full 6-stage execution | **Done** (verified live: 6/6 stages completed in 2.64s with cached inputs) |

### Wave 2 Deliverables (Issue #17)

| Component | File | Callable Contract | Prerequisites | Status |
|---|---|---|---|---|
| **Constant Calibration Tool** | `tools/derive_mlb_constants.R` | `derive_mlb_constants(seasons = 2018:2024)` | Wave 1 engines operational | **Queued / Next Up** |
| **Park Factor Decision** | Documentation / Config | Evaluation of 1-yr vs 3-yr vs 5-yr park factors | Empirical comparison | **Queued** |

---

## 3. Mathematical & Architectural Decisions Enforced

1. **Pythagenpat Variable-Exponent Baseline**:
   - Primary formulation: `x = ((RS + RA) / G)^0.287`.
   - Comparative baselines computed alongside: Pythagenport (`0.45 + 0.375 * R/G`), Fixed 1.83 (Bill James standard), and Fixed 2.0 (Pythagorean classical).
   - Residuals recorded as `luck_wins = wins - expected_wins`.
2. **4-Factor Pregame Elo Adjustment**:
   - `adj_home_elo = base_home_elo + HFA + home_rest_adj + home_pitcher_adj`
   - `adj_away_elo = base_away_elo + travel_penalty + away_rest_adj + away_pitcher_adj`
   - Pitcher Adjustment: `ratingAdj = C * (pitcher_rGS - team_rGS)`, where `C = 3.3` (placeholder from 538).
3. **Pitcher Rolling Game Score (`rGS`)**:
   - Game Score formula: `47.4 + K + 1.5*Outs - 2*BB - 2*H - 3*R - 4*HR`, normalized by park factor.
   - Preseason rGS seeded from FanGraphs fWAR metrics (`50 + 1.5 * WAR`, clamped between 35 and 68).
   - In-season updates: `rGS_new = 0.90 * rGS_prev + 0.10 * GS_game`.
   - Team starter baseline: `team_rGS_new = 0.95 * team_rGS_prev + 0.05 * GS_game`.
4. **Opener Heuristic**:
   - Identifies relief openers (>= 5 career starts with average IP < 2.0 in recent 10 starts) and defaults pitcher rating to `team_rGS` to prevent distortion.
5. **Margin of Victory (MOV) Multiplier**:
   - Smooth logarithmic scaling: `mov_mult = ln(score_diff + 1) * (2.2 / (|elo_diff| * 0.001 + 2.2))`.
