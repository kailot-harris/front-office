# MLB Analytics — Handoff Document

**Last updated**: 2026-10-18, after completing Phase 10 (Issue #25). **`main` is clean and up to date with `origin/main`**. Written for whoever picks this repo up next, cold — read this before touching anything.

## What this project is

`MLB Analytics` is a production-grade quantitative sports analytics platform for Major League Baseball, joining sibling repos (`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`), built on an R architecture:
- `config.R`: Single source of truth for constants, paths, and caching contracts.
- `run_full_pipeline.R`: Fail-safe staged DAG orchestrator with staleness validation and deep stack-trace capture.
- Production models: Pythagenpat run-expectation, 4-factor starting-pitcher Elo rating engine, Marcel baseline, Hierarchical Empirical Bayes partial-pooling engine, bullpen workload/fatigue diagnostics, 12-team postseason Monte Carlo bracket simulator, market odds EV engine, dynamic Kelly stop-loss risk management, and Discord webhook dispatching.

---

## Status of Engine Build (Phases 1–10)

All core predictive, specialty, simulation, risk, market, Bayesian, and notification engines are **100% built, verified, wired, and pushed to `main`**:

- **Phase 0 (Research)**: **100% complete** (all 10 issues #1–#10 closed). Deliverable: `docs/MLB_REPLICATION_PLAN.md`.
- **Phase 1 (Data Foundation)**: **100% complete** (issues #12, #13, #14 closed). `mlb_ingest.R`, `mlb_stats_sync.R`, `mlb_injury_scraper.R`, `mlb_id_crosswalk.R`, and `run_full_pipeline.R`.
- **Phase 2 (Rating Engine)**: **100% complete** (issues #15, #16, #17 closed). `mlb_pythag_baseline.R`, `mlb_elo_engine.R` (with pitcher adjustment), `tools/derive_mlb_constants.R`, and FanGraphs park factor integration.
- **Phase 3 (Specialty Models)**: **100% complete** (issue #18 closed). Tom Tango's Marcel baseline (`mlb_marcel_baseline.R`) and bullpen fatigue tracking (`mlb_bullpen_fatigue.R`).
- **Phase 4 (Postseason Simulator)**: **100% complete** (issue #19 closed). 12-team Monte Carlo bracket simulator (`mlb_postseason_simulator.R`) with round-specific series lengths (3/5/7) and traditional extra-innings rules.
- **Phase 5 (Risk Management)**: **100% complete** (issue #20 closed). `mlb_risk_management_engine.R` with dynamic Kelly scaling (0.25 / 0.175 / 0.10 / 0.00 halt) and synthetic cold-start fallback.
- **Phase 6 (Market Odds)**: **100% complete** (issue #21 closed). `mlb_market_odds_engine.R` with Odds API `baseball_mlb` integration, devigging, EV/Kelly calculations, and synthetic slate fallback.
- **Phase 7 (Discord Alerts)**: **100% complete** (issue #22 closed). `mlb_notify_bets.R` with baseball branding, embed formatting, institutional EV/CLV edge filtering, and safe console preview.
- **Phase 8 (Calibration Review)**: **100% complete** (issue #23 closed). Backtested 2,432 games; confirmed MLB's 162-game schedule naturally prevents NFL-style probability spikes. 10-game staking gate enforced.
- **Phase 9 (Visualization Suite)**: **100% complete** (issue #24 closed). Modern dark theme (`tools/viz_theme.R`), 4 publication-ready PNG tools in `tools/viz_*.R`, and master runner `tools/run_all_visualizations.R`.
- **Phase 10 (Empirical Bayes Partial Pooling)**: **100% complete** (issue #25 closed). Closed-form hierarchical empirical Bayes shrinkage (`mlb_bayes_pooling.R`), park factor group neutralization, monotonicity verified (`tools/evaluate_bayes_shrinkage.R`), and wired as Stage 8 in `run_full_pipeline.R`.

---

## Issue Tracking Overview

Verified live via `gh issue list --state all`:

| Issue | Title | Status | Evidence / Notes |
|---|---|---|---|
| #11 | Epic: MLB Analytics engine build (Phases 1-9) | CLOSED | Top-level engine build epic closed with all 25 issues completed |
| #12 | Phase 1: Data foundation | CLOSED | Complete (skeleton, ingestion, crosswalk) |
| #13 | Phase 1, Wave 1: Ingestion scripts + ID-crosswalk | CLOSED | `mlb_ingest.R`, `mlb_stats_sync.R`, `mlb_injury_scraper.R`, `mlb_id_crosswalk.R` |
| #14 | Phase 1, Wave 2: Pipeline skeleton | CLOSED | `run_full_pipeline.R` fail-safe orchestrator |
| #15 | Phase 2: Rating engine (Pythagorean + Elo) | CLOSED | Complete (Pythagenpat + 4-factor starting-pitcher Elo) |
| #16 | Phase 2, Wave 1: Pythagorean + Elo engine | CLOSED | `mlb_pythag_baseline.R`, `mlb_elo_engine.R` |
| #17 | Phase 2, Wave 2: Constant derivation + park factors | CLOSED | `tools/derive_mlb_constants.R`, FanGraphs park factors |
| #18 | Phase 3: Specialty models | CLOSED | `mlb_marcel_baseline.R`, `mlb_bullpen_fatigue.R` |
| #19 | Phase 4: Postseason bracket simulator | CLOSED | `mlb_postseason_simulator.R` (12-team, best-of-3/5/7) |
| #20 | Phase 5: Risk management engine | CLOSED | `mlb_risk_management_engine.R` (sport-agnostic Kelly) |
| #21 | Phase 6: Market odds engine | CLOSED | `mlb_market_odds_engine.R` (The Odds API + devig EV) |
| #22 | Phase 7: Discord alert dispatcher | CLOSED | `mlb_notify_bets.R` (rich embeds, webhook dispatch) |
| #23 | Phase 8: Early-season calibration review | CLOSED | Empirical audit complete: zero probability spikes; 10-game sample gate confirmed |
| #24 | Phase 9: Quantitative visualization suite | CLOSED | `tools/viz_*.R` + `tools/run_all_visualizations.R` (4 PNGs in `cache/viz/`) |
| #25 | Phase 10: Hierarchical empirical Bayes partial-pooling engine | CLOSED | `mlb_bayes_pooling.R` + `tools/evaluate_bayes_shrinkage.R` wired as Stage 8 |

---

## Pipeline Execution & Stage Registry

Executing `Rscript -e "source('run_full_pipeline.R'); res <- run_full_pipeline(); print(res)"` runs all 13 stages with complete staleness assertions:

```text
==================================================================
>>> FULL MLB PIPELINE EXECUTED IN 4.05 SECONDS
------------------------------------------------------------------
  [OK] mlb_ingest.R              : Ingest MLB Schedules, Box Scores & Statcast Pitches
  [OK] mlb_stats_sync.R          : Sync FanGraphs Batter/Pitcher Leaders & Park Factors
  [OK] mlb_injury_scraper.R      : Scrape ESPN MLB Injuries (with Player-Card ID Parsing)
  [OK] mlb_id_crosswalk.R        : Build/Update 5-Way Player ID Crosswalk (MLBAM/FG/BRef/Retro/ESPN)
  [OK] mlb_pythag_baseline.R     : Compute Pythagorean Win-Expectation Baseline (Pythagenpat)
  [OK] mlb_elo_engine.R          : Compute Team Elo Ratings with Starting-Pitcher Adjustment
  [OK] mlb_marcel_baseline.R     : Generate Marcel 3-Year Baseline Projections (Batters & Pitchers)
  [OK] mlb_bayes_pooling.R       : Compute Hierarchical Empirical Bayes Partial Pooling (Batters/Pitchers/Teams)
  [OK] mlb_bullpen_fatigue.R     : Compute Relief-Pitcher Fatigue & Bullpen Workload Diagnostics
  [OK] mlb_postseason_simulator.R: Simulate 12-Team MLB Postseason Bracket (WC/DS/LCS/WS)
  [OK] mlb_market_odds_engine.R  : Ingest MLB Market Odds & Compute +EV Kelly Value Bets
  [OK] mlb_risk_management_engine.R : Monitor Bankroll Drawdown & Enforce Dynamic Kelly Stop-Loss
  [OK] mlb_notify_bets.R         : Dispatch MLB Value Bet & Line Movement Alerts to Discord
==================================================================
>>> Status: 13/13 stages succeeded.
```

---

## What's Actually Implemented

| File | Lines | Type | Callable Entrypoint | Output / Cache |
|---|---|---|---|---|
| `config.R` | 260 | Real | `source("config.R")` | Single source of truth for paths, cache stages, team aliases, derived constants, and Discord webhook. |
| `logging_utils.R` | 242 | Real | `log_info()`, `log_warn()`, `log_error()` | Dual logging (console/log file + DuckDB store) with secret redaction. |
| `run_full_pipeline.R` | 365 | Real | `run_full_pipeline(season, force_refresh)` | 13-stage DAG orchestrator with staleness validation and try/catch. |
| `mlb_ingest.R` | 312 | Real | `run_mlb_ingest()` | Ingests schedules, boxscores, and Statcast pitch data. |
| `mlb_stats_sync.R` | 227 | Real | `run_stats_sync()` | Syncs FanGraphs batters, pitchers, and 30-venue park factors. |
| `mlb_injury_scraper.R` | 151 | Real | `run_injury_scraper()` | Scrapes ESPN injuries and parses athlete IDs. |
| `mlb_id_crosswalk.R` | 226 | Real | `run_id_crosswalk()` | 5-way ID crosswalk (MLBAM, FanGraphs, BRef, Retrosheet, ESPN). |
| `mlb_pythag_baseline.R` | 236 | Real | `run_pythag_baseline()` | Pythagenpat variable-exponent run-expectation baseline. |
| `mlb_elo_engine.R` | 589 | Real | `run_elo_engine()` | 4-factor Elo engine with per-pitcher rGS starting pitcher adjustment. |
| `mlb_marcel_baseline.R` | 298 | Real | `run_marcel_baseline()` | Tom Tango's 3-year Marcel projection system with age adjustments. |
| `mlb_bayes_pooling.R` | 385 | Real | `run_bayes_pooling()` | Closed-form empirical Bayes shrinkage for wOBA, ISO, xFIP, K%, BB% with park factor adjustments. |
| `mlb_bullpen_fatigue.R` | 330 | Real | `run_bullpen_fatigue()` | Relief-pitcher cumulative workload, rest days, and velocity monitoring. |
| `mlb_postseason_simulator.R` | 420 | Real | `run_postseason_simulator()` | 12-team Monte Carlo bracket simulator (best-of-3/5/7) under traditional extra-innings rules. |
| `mlb_market_odds_engine.R` | 500 | Real | `run_market_odds_engine()` | The Odds API integration (`baseball_mlb`), sharp devigging, +EV, and fractional Kelly staking. |
| `mlb_risk_management_engine.R` | 255 | Real | `run_risk_management()` | Bankroll drawdown tracking and dynamic Kelly stop-loss tiers. |
| `mlb_notify_bets.R` | 215 | Real | `run_notify_bets()` | Discord value-bet webhook dispatcher with baseball embed formatting. |
| `tools/derive_mlb_constants.R` | 235 | Real | CLI / Script | Empirical constant derivation across 2,432 games. |
| `tools/evaluate_bayes_shrinkage.R` | 210 | Real | `test_shrinkage_monotonicity()` | Monotonicity and variance-reduction verification for empirical Bayes shrinkage. |
| `tools/viz_*.R` | ~600 | Real | `run_all_visualizations()` | 4 publication-ready PNG visualization scripts in modern dark theme. |
| `reports/Baseball analytics model comparison.md` | ~400 | Report | Document | Academic/industry research comparison covering win probability, player projection, Statcast pitching, postseason simulation, and betting market efficiency. |
| `research_notes/` | ~25 files | Notes | Documents | Detailed literature and empirical research notes. |
| `ROADMAP.md` | 55 | Roadmap | Document | Post-v1 capability ideas, automation roadmap, and testing/CI wishlist. |
