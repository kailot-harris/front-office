# Feature Wishlist & Roadmap — MLB Analytics

This is **not a commitment list**. Every entry here is a candidate to be
scoped into its own GitHub issue/slice when someone actually picks it up
(see `docs/HANDOFF.md` for the issue/phase pattern this repo uses). Items
move out of this file once they ship (they live in git history / HANDOFF's
phase table instead) or once they're explicitly rejected (see §3 below).

## 1. New capability ideas

Roughly ordered by value-to-effort, not a strict priority queue.

- **Recurring/automated calibration re-check.** Phase 8 (issue #23) was a
  one-time backtest audit. Turn it into a repeatable check that reuses the
  `tools/evaluate_bayes_shrinkage.R` monotonicity-check pattern so
  calibration drift gets caught each season rather than audited once.
  Effort: Small-medium.
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
  Implemented formal unit test suite under `tests/testthat/` (44 assertions covering
  Pythagorean win expectation, Elo updates, Tangotiger game score math, market odds
  devigging & Kelly staking, 5-way player crosswalk, and empirical Bayes shrinkage
  monotonicity). Integrated with GitHub Actions CI workflow (`.github/workflows/ci.yml`).
- **Add a root `README.md`.** Currently `docs/HANDOFF.md` is the only
  orientation document for a newcomer; a short README pointing at it
  would lower the barrier for anyone browsing the repo on GitHub.


## 3. Explicitly out of scope

Nothing has been proposed and rejected yet — this section stays empty
until an idea is raised and deliberately declined, so it doesn't get
re-litigated.
