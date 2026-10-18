# MLB Analytics — Handoff Document

**Last updated**: 2026-10-18, after completing Phases 1–7 (Issues #12–#22). **`main` is clean and up to date with `origin/main`** (latest commit `7e37aeb`). Written for whoever picks this repo up next, cold — read this before touching anything.

## What this project is

`MLB Analytics` is a production-grade quantitative sports analytics platform for Major League Baseball, joining sibling repos (`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`), built on an R architecture:
- `config.R`: Single source of truth for constants, paths, and caching contracts.
- `run_full_pipeline.R`: Fail-safe staged DAG orchestrator with staleness validation and deep stack-trace capture.
- Production models: Pythagenpat run-expectation, 4-factor starting-pitcher Elo rating engine, Marcel baseline, bullpen workload/fatigue diagnostics, 12-team postseason Monte Carlo bracket simulator, market odds EV engine, dynamic Kelly stop-loss risk management, and Discord webhook dispatching.

---

## Status of Engine Build (Phases 1–9)

All core predictive, specialty, simulation, risk, market, and notification engines are **100% built, verified, wired, and pushed to `main`**:

- **Phase 0 (Research)**: **100% complete** (all 10 issues #1–#10 closed). Deliverable: `docs/MLB_REPLICATION_PLAN.md`.
- **Phase 1 (Data Foundation)**: **100% complete** (issues #12, #13, #14 closed). `mlb_ingest.R`, `mlb_stats_sync.R`, `mlb_injury_scraper.R`, `mlb_id_crosswalk.R`, and `run_full_pipeline.R`.
- **Phase 2 (Rating Engine)**: **100% complete** (issues #15, #16, #17 closed). `mlb_pythag_baseline.R`, `mlb_elo_engine.R` (with pitcher adjustment), `tools/derive_mlb_constants.R`, and FanGraphs park factor integration.
- **Phase 3 (Specialty Models)**: **100% complete** (issue #18 closed). Tom Tango's Marcel baseline (`mlb_marcel_baseline.R`) and bullpen fatigue tracking (`mlb_bullpen_fatigue.R`).
- **Phase 4 (Postseason Simulator)**: **100% complete** (issue #19 closed). 12-team Monte Carlo bracket simulator (`mlb_postseason_simulator.R`) with round-specific series lengths (3/5/7) and traditional extra-innings rules.
- **Phase 5 (Risk Management)**: **100% complete** (issue #20 closed). `mlb_risk_management_engine.R` with dynamic Kelly scaling (0.25 / 0.175 / 0.10 / 0.00 halt) and synthetic cold-start fallback.
- **Phase 6 (Market Odds)**: **100% complete** (issue #21 closed). `mlb_market_odds_engine.R` with Odds API `baseball_mlb` integration, devigging, EV/Kelly calculations, and synthetic slate fallback.
- **Phase 7 (Discord Alerts)**: **100% complete** (issue #22 closed). `mlb_notify_bets.R` with baseball branding, embed formatting, institutional EV/CLV edge filtering, and safe console preview.
- **Phase 8 (Calibration Review)**: **Audited & Documented** (issue #23 open). Backtested 2,432 games; confirmed MLB's 162-game schedule naturally prevents NFL-style probability spikes. Brief prepared: `subagent_brief_issue_23.md`.
- **Phase 9+ (Deferred Ideas)**: Open issue #24 for future roadmap enhancements.

---

## Issue Tracking Overview

Verified live via `gh issue list --state all`:

| Issue | Title | Status | Evidence / Notes |
|---|---|---|---|
| #11 | Epic: MLB Analytics engine build (Phases 1-9) | OPEN | Parent epic |
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
| **#23** | **Phase 8: Early-season calibration review** | **OPEN** | **Decision point backtest complete; ready for formal closure** |
| #24 | Phase 9+: Deferred / idea-stage | OPEN | Post-build enhancements |

---

## Pipeline Execution & Stage Registry

Executing `Rscript -e "source('run_full_pipeline.R'); res <- run_full_pipeline(); print(res)"` runs all 12 stages in parallel/sequence with complete staleness assertions:

```text
==================================================================
>>> FULL MLB PIPELINE EXECUTED IN 4.86 SECONDS
------------------------------------------------------------------
  [OK] mlb_ingest.R              : Ingest MLB Schedules, Box Scores & Statcast Pitches
  [OK] mlb_stats_sync.R          : Sync FanGraphs Batter/Pitcher Leaders & Park Factors
  [OK] mlb_injury_scraper.R      : Scrape ESPN MLB Injuries (with Player-Card ID Parsing)
  [OK] mlb_id_crosswalk.R        : Build/Update 5-Way Player ID Crosswalk (MLBAM/FG/BRef/Retro/ESPN)
  [OK] mlb_pythag_baseline.R     : Compute Pythagorean Win-Expectation Baseline (Pythagenpat)
  [OK] mlb_elo_engine.R          : Compute Team Elo Ratings with Starting-Pitcher Adjustment
  [OK] mlb_marcel_baseline.R     : Generate Marcel 3-Year Baseline Projections (Batters & Pitchers)
  [OK] mlb_bullpen_fatigue.R     : Compute Relief-Pitcher Fatigue & Bullpen Workload Diagnostics
  [OK] mlb_postseason_simulator.R: Simulate 12-Team MLB Postseason Bracket (WC/DS/LCS/WS)
  [OK] mlb_market_odds_engine.R  : Ingest MLB Market Odds & Compute +EV Kelly Value Bets
  [OK] mlb_risk_management_engine.R : Monitor Bankroll Drawdown & Enforce Dynamic Kelly Stop-Loss
  [OK] mlb_notify_bets.R         : Dispatch MLB Value Bet & Line Movement Alerts to Discord
==================================================================
>>> Status: 12/12 stages succeeded.
```

---

## Exact Next Steps for Incoming Agent

1. **Close Issue #23 (Phase 8 Calibration Review)**:
   - Empirical findings are documented in [`subagent_brief_issue_23.md`](file:///C:/Users/kailo/.gemini/antigravity/brain/b4b6228b-1520-4053-9a0d-48a90d4e4fb5/subagent_brief_issue_23.md).
   - Findings: MLB does not suffer from NFL-style small-sample win probability explosions (all 2,432 games stayed strictly within 0.293–0.770; SD = 0.0288 in games 1–300).
   - Post completion audit comment to `gh issue close 23`.
2. **Close Epic #11**:
   - Once #23 is closed, all scoped engine development phases (Phases 1–8) are complete. Review open items in #24 and close Epic #11.
