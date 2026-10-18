# MLB Analytics — Handoff Document

**Last updated**: 2026-10-18, after completing Phase 10 (Empirical Bayes), the epic close-out (#11), process/infra hardening (tests/CI/README/scheduler), the Next.js 14 web platform build (`web/`), and the 4-tier Statcast Spatial Analytics integration (`/spatial`). **`main` has uncommitted work sitting in the working tree right now — see "Uncommitted work" below before touching anything.** Written for whoever picks this repo up next, cold — read this before touching anything.

---

## Uncommitted work in the working tree (verify before committing or discarding)

As of this writing, `git status` on `main` shows:
- **Modified, unstaged**:
  - `.gitignore`: Adds `/web/node_modules/`, `/web/.next/`, `/web/out/`.
  - `README.md`: Adds Stage 14 row to the pipeline table and web dashboard launching instructions (`cd web && npm run dev`).
  - `run_full_pipeline.R`: Wires Stage 14 (`tools/export_web_data.R`) into the DAG orchestrator with staleness validation.
  - `docs/WEB_IMPLEMENTATION_PLAN.md`: Synchronized with all 7 frontend routes (including `/postseason` and `/spatial`) and 6 phased milestones.
  - `docs/HANDOFF.md`: This comprehensive handoff document.
- **Untracked**:
  - `tools/export_web_data.R`: Synthesizes cached MLB R pipeline outputs across Stages 1–13 into static JSON artifacts for the Next.js frontend (`run_web_export()`).
  - `tools/export_spatial_analytics.R`: Processes Statcast pitch and batted ball coordinate data into `statcast_spatial_analytics.json` across 4 spatial tiers (`export_spatial_analytics()`).
  - `web/`: Complete Next.js 14 + TypeScript + Tailwind web application (7 routes, 11 statically prerendered pages, 0 ESLint errors, 0 build errors).

This is real, verified-working code (full build and test details below), not a stub — it just hasn't been committed yet. Decide whether to commit before starting new work, so you don't mix it with unrelated changes.

---

## What this project is

`MLB Analytics` is a production-grade quantitative sports analytics platform for Major League Baseball, joining sibling repos (`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`), built on an R architecture:
- `config.R`: Single source of truth for constants, paths, and caching contracts.
- `run_full_pipeline.R`: Fail-safe 14-stage DAG orchestrator with staleness validation and deep stack-trace capture.
- Production models: Pythagenpat run-expectation, 4-factor starting-pitcher Elo rating engine, Marcel baseline, Hierarchical Empirical Bayes partial-pooling engine, bullpen workload/fatigue diagnostics, 12-team postseason Monte Carlo bracket simulator, market odds EV engine, dynamic Kelly stop-loss risk management, Discord webhook dispatching, and web JSON export.
- Web layer: Next.js 14 static quantitative terminal dashboard in `web/` reading static JSON from `web/public/data/` (zero-runtime database dependency).

---

## Status of Engine Build (Phases 1–10 + Web Dashboard & Spatial Analytics)

All core predictive, specialty, simulation, risk, market, Bayesian, notification, web, and spatial engines are **100% built, verified, and wired**:

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
- **Phase 11 (Web Dashboard Scaffolding & 6 Routes)**: **100% complete**. Next.js 14 app in `web/` with 30-team standings, 4-engine variants matrix, 1,279 batter/pitcher projections, 12-team postseason bracket + bullpen fatigue + EV bets, and SVG calibration curve.
- **Phase 12 (Statcast 4-Tier Spatial Analytics Integration)**: **100% complete**. `tools/export_spatial_analytics.R` wired into Stage 14 export; interactive `/spatial` route in Next.js with 4 separate tabs (Batted ball spray & 30-ballpark overlays, 3×3 strike zone & catcher framing, pitch movement IVB/HB & pitcher arsenals, defensive positioning & shift BABIP penalty).

---

## Pipeline Execution & Stage Registry

Executing `Rscript -e "source('run_full_pipeline.R'); res <- run_full_pipeline(); print(res)"` runs all 14 stages in **9.29 seconds** with complete staleness assertions:

```text
==================================================================
>>> FULL MLB PIPELINE EXECUTED IN 9.29 SECONDS
------------------------------------------------------------------
  [OK] mlb_ingest.R              : Ingest MLB Schedules, Box Scores & Statcast Pitches (0.42s)
  [OK] mlb_stats_sync.R          : Sync FanGraphs Batter/Pitcher Leaders & Park Factors (0.18s)
  [OK] mlb_injury_scraper.R      : Scrape ESPN MLB Injuries (with Player-Card ID Parsing) (0.13s)
  [OK] mlb_id_crosswalk.R        : Build/Update 5-Way Player ID Crosswalk (MLBAM/FG/BRef/Retro/ESPN) (0.48s)
  [OK] mlb_pythag_baseline.R     : Compute Pythagorean Win-Expectation Baseline (Pythagenpat) (0.09s)
  [OK] mlb_elo_engine.R          : Compute Team Elo Ratings with Starting-Pitcher Adjustment (0.10s)
  [OK] mlb_marcel_baseline.R     : Generate Marcel 3-Year Baseline Projections (Batters & Pitchers) (0.26s)
  [OK] mlb_bayes_pooling.R       : Compute Hierarchical Empirical Bayes Partial Pooling (Batters/Pitchers/Teams) (0.09s)
  [OK] mlb_bullpen_fatigue.R     : Compute Relief-Pitcher Fatigue & Bullpen Workload Diagnostics (0.11s)
  [OK] mlb_postseason_simulator.R: Simulate 12-Team MLB Postseason Bracket (WC/DS/LCS/WS) (0.12s)
  [OK] mlb_market_odds_engine.R  : Ingest MLB Market Odds & Compute +EV Kelly Value Bets (1.05s)
  [OK] mlb_risk_management_engine.R : Monitor Bankroll Drawdown & Enforce Dynamic Kelly Stop-Loss (0.12s)
  [OK] mlb_notify_bets.R         : Dispatch MLB Value Bet & Line Movement Alerts to Discord (0.48s)
  [OK] tools/export_web_data.R   : Export Next.js Web Dashboard JSON Artifacts (web/public/data) (3.44s)
==================================================================
>>> Status: 14/14 stages succeeded.
```

---

## What's Actually Implemented

| File / Component | Lines | Type | Callable Entrypoint | Output / Cache / Artifact |
|---|---|---|---|---|
| `config.R` | 260 | Real | `source("config.R")` | Single source of truth for paths, cache stages, team aliases, derived constants, and Discord webhook. |
| `logging_utils.R` | 242 | Real | `log_info()`, `log_warn()`, `log_error()` | Dual logging (console/log file + DuckDB store) with secret redaction. |
| `run_full_pipeline.R` | 385 | Real | `run_full_pipeline(season, force_refresh)` | 14-stage DAG orchestrator with staleness validation and try/catch. |
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
| `tests/testthat/` | ~300 | Real | `testthat::test_dir('tests/testthat')` | Automated unit test suite (54 assertions) covering Pythagenpat, Elo, game scores, devigging, Kelly staking, ID crosswalk, Bayes shrinkage, and season calibration. |
| `.github/workflows/ci.yml` | 38 | CI | GitHub Actions | Continuous integration running renv restore and testthat unit tests on push/PR. |
| `scripts/run_pipeline_task.ps1` | 27 | Infra | PowerShell / Scheduled Task | Automated production pipeline execution wrapper for Windows Task Scheduler (`MLB_Analytics_Scheduled_Pipeline`). |
| `tools/evaluate_season_calibration.R` | 185 | Real | `run_season_calibration_check()` | Automated in-season probability calibration, Brier score, log loss, and drift detection across 2,432 games. |
| `tools/derive_mlb_constants.R` | 235 | Real | CLI / Script | Empirical constant derivation across 2,432 games. |
| `tools/evaluate_bayes_shrinkage.R` | 210 | Real | `test_shrinkage_monotonicity()` | Monotonicity and variance-reduction verification for empirical Bayes shrinkage. |
| `tools/viz_*.R` | ~600 | Real | `run_all_visualizations()` | 4 publication-ready PNG visualization scripts in modern dark theme. |
| `tools/export_web_data.R` | 960 | Real (**uncommitted**) | `run_web_export(season)` | Joins all engine `.rds` caches and calls spatial export into 6 JSON artifacts under `web/public/data/`. Wired as Stage 14 in `run_full_pipeline.R`. Verified: completes in 3.05s. |
| `tools/export_spatial_analytics.R` | 408 | Real (**uncommitted**) | `export_spatial_analytics(out_dir)` | Parses Statcast coordinates into 4-tier spatial dataset (`statcast_spatial_analytics.json`, 0.26 MB). |
| `web/` (Next.js 14 app) | ~5,500 (TS/TSX) | Real (**uncommitted**) | `cd web && npm run dev` / `npm run build` | 7-route dashboard (`/`, `/teams`, `/variants`, `/players`, `/spatial`, `/postseason`, `/diagnostics`). Statically pre-rendered across 11 production pages. Verified clean: `next lint` (0 errors), `next build` (11/11 pages). |
| `docs/WEB_IMPLEMENTATION_PLAN.md` | 204 | Plan (**uncommitted**) | Document | Phased implementation plan documenting all 7 routes and 6 completed milestones. |

---

## Web Platform & Spatial Analytics Breakdown (`web/`)

Modeled directly after `NBA Analytics/web`, the MLB platform operates with zero runtime database — all views consume statically compiled JSON generated by Stage 14 of the R pipeline.

### JSON Artifacts in `web/public/data/`:
1. `projections_season_teams.json` (30 teams, 1,000 season simulations across 4 variants + Ensemble, p10–p90 ranges, WS%).
2. `projections_season_players.json` (1,279 players: 630 Batters & 649 Pitchers with Empirical Bayes pooled rates and Marcel counting totals).
3. `projections_models_metadata.json` (pipeline parameters, Pythagenpat exponent 1.79 / 0.287, Home Field Advantage 14.9 Elo, weights).
4. `projections_diagnostics.json` (2,430+ games walk-forward calibration, 7 probability bins, Early/Mid/Late drift).
5. `projections_postseason_ops.json` (12-team playoff bracket probabilities, 30-team bullpen fatigue metrics, real-time +EV value bets).
6. `statcast_spatial_analytics.json` (0.26 MB, 7,836 pitches, 1,350 batted balls, 30 ballpark fence geometries, 3×3 strike zone, 10 pitch movement profiles).

### Navigation & Routes:
- **`/` & `/teams`** (`StandingsClient.tsx`, `PlayoffContendersBoxWhisker.tsx`): 162-game Monte Carlo win distributions, .500 (81W) reference lines, AL/NL and 6-division filtering, sortable franchise table.
- **`/variants`** (`VariantsClient.tsx`, `BrierScoreComparison.tsx`): 4-engine comparison (Starting-Pitcher Elo, Empirical Bayes Talent, Pythagenpat Run-Expectation, Marcel + Bullpen Fatigue) vs. Ensemble, model divergence spread ($\Delta W$).
- **`/players`** (`PlayersClient.tsx`): 1,279 player pool with instant **Batters (630)** / **Pitchers (649)** toggle, **Bayes Pooled Rates** vs. **Marcel Counting Totals**, role filters (SP/RP), search, and $|z| \ge 2.0$ outlier highlights.
- **`/spatial`** (`SpatialAnalyticsClient.tsx`): 4 distinct tabs:
  - **Tier 1 (Spray & 30-Park Overlays)**: Interactive SVG diamond with foul lines and distance rings, 30-ballpark fence outlines (Fenway Green Monster, Yankee Stadium short porch, Coors, etc.), hit outcome color-coding, point inspector, and "Home Run in X/30 Parks" bar.
  - **Tier 2 (Strike Zone Heatmaps & Framing)**: Interactive 3×3 Statcast strike zone, metric switcher (Whiff%, Swing%, Called Strike%, Frequency%), 2-inch shadow zone ring, and catcher framing run value calculator (+0.125 runs/called strike).
  - **Tier 3 (Pitch Movement & Arsenals)**: 2D IVB vs. Horizontal Break scatter plot with zero-spin gravity crosshair, pitch type pills, and top pitcher arsenal drill-down with 3D release point coordinates ($X$ and $Z$ in ft).
  - **Tier 4 (Defensive Positioning & Shift Impact)**: Infield dirt sector hit frequency bars, directional BABIP table for LHH/RHH Pull/Center/Oppo, and 2023 shift restriction adaptation analysis.
- **`/postseason`** (`PostseasonOpsClient.tsx`): 12-team bracket simulation across Wild Card (3), Division Series (5), LCS (7), and World Series (7); 30-team bullpen workload/fatigue monitor; devigged +EV value bet tracker with fractional Kelly sizing.
- **`/diagnostics`** (`DiagnosticsClient.tsx`): SVG Reliability Diagram across 7 probability bins against $y = x$ diagonal, Brier Score (0.2449 vs 0.2500 baseline), Early/Mid/Late drift stability.

---

## Concrete Next Steps

1. **Commit and push the uncommitted work**:
   - The uncommitted work is complete, tested, and verified clean (`npm run lint` with 0 warnings, `npm run build` with 11/11 static pages generated, and `run_full_pipeline.R` executing 14/14 stages in 9.29s).
   - Recommended commit staging:
     - Commit 1 (Pipeline & Exporter): `.gitignore`, `run_full_pipeline.R`, `README.md`, `tools/export_web_data.R`, `tools/export_spatial_analytics.R`.
     - Commit 2 (Next.js Web Dashboard): `web/`, `docs/WEB_IMPLEMENTATION_PLAN.md`, `docs/HANDOFF.md`.
2. **Launch the web application locally**:
   - Run `cd web && npm run dev` to interact with the dashboard at `http://localhost:3000`.
3. **If picking up future modeling enhancements (see `ROADMAP.md`)**:
   - Team-quality-adjusted win probability in extra-innings play.
   - Logistic regression meta-model blending Elo and Pythagenpat outputs.
   - Dynamic market devigging enhancements (Shin / power devigging).
