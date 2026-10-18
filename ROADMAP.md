# Feature Wishlist & Roadmap — MLB Analytics

This is **not a commitment list**. Every entry here is a candidate to be
scoped into its own GitHub issue/slice when someone actually picks it up
(see `docs/HANDOFF.md` for the issue/phase pattern this repo uses). Items
move out of this file once they ship (they live in git history / HANDOFF's
phase table instead) or once they're explicitly rejected (see §3 below).

## 1. New capability ideas

Roughly ordered by value-to-effort, not a strict priority queue.

- **[SHIPPED 2026-10-18] Recurring/automated calibration re-check.** Implemented
  `tools/evaluate_season_calibration.R` and `tests/testthat/test-calibration.R`.
  Evaluates walk-forward Brier scores (0.2447 vs 0.2500 coin-flip), log loss (0.6824),
  7 probability bin reliability checks (weighted calib error = 1.82%), chronological
  progression (Early/Mid/Late), and automated flags for extreme outliers or drift.
- **Bankroll P&L dashboard over time.** `mlb_risk_management_engine.R`
  already tracks a bankroll ledger; there's no visualization of drawdown/
  growth history yet. Would reuse `tools/viz_theme.R` for styling.
  Effort: Small-medium.
- **Multi-book odds aggregation.** `mlb_market_odds_engine.R` (Phase 6)
  currently devigs against a single Odds API feed. Aggregating multiple
  books would sharpen the devig and EV estimate, but depends on the
  existing Phase 6 architecture and may need rework of the devig math.
  Effort: Medium.

## 2. Process / infra items

- **[SHIPPED 2026-10-18] Live scheduling of full pipeline.** Operationalized via
  `scripts/run_pipeline_task.ps1` and registered under Windows Task Scheduler
  (`MLB_Analytics_Scheduled_Pipeline`) on a twice-daily cadence (11:00 AM morning
  slate, 5:00 PM pre-game lineups) logging to `logs/scheduled_runs.log`.
- **[SHIPPED 2026-10-18] Automated `testthat` suite & GitHub Actions CI.**
  Implemented formal unit test suite under `tests/testthat/` (54 assertions covering
  Pythagorean win expectation, Elo updates, Tangotiger game score math, market odds
  devigging & Kelly staking, 5-way player crosswalk, empirical Bayes shrinkage
  monotonicity, and season calibration). Integrated with GitHub Actions CI workflow
  (`.github/workflows/ci.yml`).
- **[SHIPPED 2026-10-18] Add a root `README.md`.** Complete orientation guide with
  badges, architecture table, quickstart setup, testing commands, and documentation links.



## 3. Explicitly out of scope

Nothing has been proposed and rejected yet — this section stays empty
until an idea is raised and deliberately declined, so it doesn't get
re-litigated.
