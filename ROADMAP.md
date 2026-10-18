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
- **Live scheduling of the full pipeline.** `run_full_pipeline.R` +
  `mlb_notify_bets.R` currently run on demand only. Wiring a cron/Windows
  Task Scheduler job to run on a game-day cadence would make the Discord
  alerting actually operational rather than manually triggered.
  Effort: Medium — needs a persistent scheduler, not just a script change.
- **Multi-book odds aggregation.** `mlb_market_odds_engine.R` (Phase 6)
  currently devigs against a single Odds API feed. Aggregating multiple
  books would sharpen the devig and EV estimate, but depends on the
  existing Phase 6 architecture and may need rework of the devig math.
  Effort: Medium.

## 2. Process / infra items

- **Add a `testthat` suite.** Reviewed in session on 2026-10-18: zero
  automated tests exist anywhere in the repo (only `renv`'s bundled
  copies reference `testthat`). The project currently relies on
  verification/derivation scripts (`tools/derive_mlb_constants.R`,
  `tools/evaluate_bayes_shrinkage.R`) instead of unit tests. Worth a
  deliberate call on whether that's sufficient going forward or whether
  core engines (Pythagenpat, Elo, Marcel, Bayes pooling) need real
  regression tests.
- **Add a root `README.md`.** Currently `docs/HANDOFF.md` is the only
  orientation document for a newcomer; a short README pointing at it
  would lower the barrier for anyone browsing the repo on GitHub.
- **GitHub Actions CI.** No CI currently runs the pipeline or any tests
  on push. Would need the testthat suite above (or at least the parse/
  syntax check done ad hoc this session) wired into a workflow.

## 3. Explicitly out of scope

Nothing has been proposed and rejected yet — this section stays empty
until an idea is raised and deliberately declined, so it doesn't get
re-litigated.
