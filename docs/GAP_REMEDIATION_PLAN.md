# WNBA Analytics — Gap Remediation Plan (Post-T5 Hardening)

## Spec Being Targeted

Per user spec, upon re-verification the following must hold:
1. **All data originates from live feeds.**
2. **All synthetic-data origin points are fallbacks only**, with a functional live feed actually in
   place above them (not "permanently synthetic by design" left unaddressed).
3. **Accuracy, recall, precision, F1, and ROC-AUC** for the selected ML model are within **<1%** of a
   named industry/academic benchmark.
4. **Deep error logging** is implemented and confirmed via testing (fault injection, not just
   happy-path runs).

## Ground Truth Going In (from `TESTING_PLAN.md`'s Execution Log and `task_assignments.md` Handoff Notes)

Confirmed gaps as of the post-T5 verification pass:
- **No `ODDS_API_KEY`** set in this environment → `market_odds_engine.R`/`live_game_listener.R` always
  hit the (correctly labeled) `SYNTHETIC_FALLBACK` fixture. This is spec-compliant *design* (fallback
  exists, is labeled) but currently has **no live path ever actually exercised** — violates spec #1 until
  a real key is wired and proven live at least once.
- **`rapm_engine.R` was never built at all** — not a labeled fallback, an absence. Violates spec #2:
  there is no live feed above the (nonexistent) synthetic path because there is no path at all.
- **`shot_quality_engine.R`** is synthetic-by-design — T3 flagged that `wehoop::load_wnba_pbp()` might
  carry real shot coordinates in some seasons, never checked. Unresolved per spec #2.
- **`team_embeddings.py`** trained on 1,000 mock random matchup rows, not real games — but T1's real
  `box_scores_cache.rds` (3,906 real rows) already exists and trivially yields a real
  `games_for_embeddings.csv` (`home_team`, `away_team`, `home_win`). This is the cheapest fix in the
  whole plan and should not still be mock.
- **`risk_management_engine.R`** reads the dead `cache/bet_log.rds` path instead of the real
  `cache/betting_ledger.rds` `bet_tracker.r` actually writes — a real bug, not a design choice.
- **`app.R` Tab 6 (Model Calibration)** is a hardcoded fake curve, never wired to
  `live_calibration.R::calibration_analysis()` against real model predictions.
- **No rigorous ML benchmark exists yet.** `WNBA_Analysis_Project.Rmd` has real accuracy numbers from
  T2's re-run, but no formal precision/recall/F1/ROC-AUC table, no cross-validation/confidence intervals,
  and no comparison against a named external benchmark.
- **Logging today is `print()`/`cat()` + a `run_stage()` `tryCatch` wrapper** that swallows errors into a
  one-line message. There is no structured log level, no stack trace capture, and no test that
  deliberately triggers a failure to confirm it's actually captured usefully.

## Important Caveat on Spec Item 3 (flagging now, not burying it)

A `<1%` difference from "industry or academic standards" is a precise-sounding bar that may not be
statistically meaningful here: WNBA has ~3,900 total games across 2019–2026 (vs. NBA datasets an order of
magnitude larger), so a single train/test split's accuracy has real sampling variance — plausibly ±2-3
percentage points just from which season is held out. The remediation plan below does not skip this
requirement, but it makes the comparison honest: Phase 3 will (a) name a specific, citable benchmark
figure (not a vague "industry standard"), (b) report cross-validated metrics with confidence intervals,
and (c) state plainly if the observed gap is inside/outside 1% and whether that gap is distinguishable
from noise given the sample size — rather than tuning a model until a single split happens to clear the
bar.

## Phases & Subagent Assignments

Tracked in `task_assignments_phase2.md`. Phases 1, 2, and 4 touch disjoint files and can run in parallel;
Phase 3 (ML benchmarking) is also file-disjoint from 1/2/4 and can run alongside them. Phase 5 (deep
logging) touches nearly every script and must run **last**, after 1–4 land, so it wraps the final code
rather than being immediately stale. Phase 6 (final spec-compliance verification) is last of all.

| Phase | Title | Agent | Brief | Depends on |
|---|---|---|---|---|
| P1 | Odds API activation + real embeddings training data | `wnba_odds_embeddings_agent` | `agent7.md` | none |
| P2 | Real RAPM stint engine + shot-quality real-data investigation | `wnba_rapm_shotquality_agent` | `agent8.md` | none |
| P3 | Known bug fixes (risk ledger path, calibration tab wiring) | `wnba_bugfix_agent` | `agent9.md` | none |
| P4 | ML benchmark rigor (precision/recall/F1/ROC-AUC vs. named standard) | `wnba_ml_benchmark_agent` | `agent10.md` | none |
| P5 | Deep structured logging + fault-injection tests | `wnba_logging_agent` | `agent11.md` | P1-P4 |
| P6 | Final spec-compliance verification report | `wnba_spec_compliance_agent` | `agent12.md` | P1-P5 |

## Ground Rules for Every Agent in This Round
1. Read this file, `task_assignments_phase2.md`, `task_assignments.md` (original build Handoff Notes),
   `TESTING_PLAN.md`, and `REPO_MAP.md`/`WNBA_REPLICATION_PLAN.md` before touching code.
2. Never claim a live feed works without an actual successful live run's evidence (HTTP 200, real row
   counts, a timestamp) — if a live path genuinely can't be exercised in this environment (e.g., a paid
   key was never provisioned), say so explicitly and document exactly what a human needs to do to
   unblock it, rather than marking it done.
3. Do not weaken or delete an existing synthetic fallback — every fallback stays, spec #2 requires it to
   remain *available* as a fallback, just no longer be the only path.
4. Update `task_assignments_phase2.md` with Status and Handoff Notes exactly like the original build
   round did in `task_assignments.md`.
5. R is at `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH); use the temp-file-then-run pattern.
