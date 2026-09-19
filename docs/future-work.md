# Future Work

Wishlist items identified 2026-09-19 during a repo-improvement review. Items 1-5 of the original
15-item wishlist were implemented that same session (see `docs/HANDOFF.md`'s corresponding entry
for what shipped: a pure-function test suite, a weekly cache/constant-drift audit job, a
generalized prediction-log completeness check, an appended value-bets history cache, and a BPM
weight recalibration). This file documents the remaining items — real, identified gaps, not yet
acted on. Renumbered from the original wishlist (items 6-15 there); not in strict priority order,
though roughly grouped by area.

## Model / data integrity

1. **Recheck the VIF ~4.80 collinearity flag** between `trailing_avg_team_top5_bpm` and
   `trailing_avg_margin` (`docs/team_depth_signal_regression_findings.md`) as more seasons
   accumulate — it sits close to the VIF > 5 rule-of-thumb ceiling. Note: the underlying
   coefficients moved on 2026-09-19 after the BPM recalibration (`docs/bpm_recalibration_findings.md`)
   — re-run `tools/research_team_depth_regression.R`'s Section 5 VIF check against the current
   cache next time this is picked up, don't assume the 4.80 figure is still current.
2. **Re-run `tools/research_shot_mix_regression.R` periodically** as more PBP seasons accumulate
   in `cache/wnba_espn_pbp_cache.rds` — unlike the team-depth regression, this one does NOT
   depend on `calculate_bpm_components()` and was not touched by the 2026-09-19 BPM work, so it's
   been longer since it was last re-checked.
3. **A genuine second attempt at the BPM replacement-level anchor and the 8 non-significant
   per-stat weights** (`docs/bpm_recalibration_findings.md`). The 2026-09-19 attempt found: (a)
   a `minutes >= 10` filter is too permissive a proxy for "replacement level" (produced an
   implausible +3.51 vs. the expected deeply-negative convention) — a real derivation needs a
   better replacement-population definition first; (b) a single-game-margin trailing-average
   target has limited statistical power to isolate 9 correlated box categories (R² = 0.05) — a
   season-aggregated or multi-year target (possibly against `cache/rapm_ratings.rds`, a
   real WNBA plus-minus source not used in this attempt) would likely have more power and is the
   more promising next angle, not a re-run of the same method with more seasons.

## Pipeline / infra

4. **Run `run_full_pipeline.R` end-to-end and confirm `[FRESH]`** on every declared output. Still
   not done via the actual `run_stage()` DAG — every verification so far (this session included)
   has been single-stage (`tools/verify_pipeline_stage.R`) or standalone script runs, not a true
   full-pipeline pass. Carried over across multiple sessions now.
5. **Empirically tune `MIN_FREE_MB_FOR_PARALLEL` (currently 4096, an untested first guess)** in
   `run_full_pipeline.R`'s memory-adaptive parallel-plan guard.
6. **Verify the weekly audit job actually gets registered and runs** — `schedule_weekly_audit.bat`
   was created 2026-09-19 (runs `orphaned-cache-audit` + `config-constant-drift-audit`, logs to
   `logs/weekly_audit.log`) but the one-time `schtasks /create` registration documented in its own
   header comment was deliberately NOT run automatically (a persistent system-level scheduling
   change, left for a human to do explicitly) — confirm it's actually registered and producing
   log output on the intended cadence.

## Repo hygiene

7. **Stop committing generated `.rds`/`.csv` cache binaries to git** (or move them to Git LFS /
   `.gitignore` + a documented regeneration step). Every commit in this repo touches a dozen+
   binary caches with zero reviewable diff — this is exactly the kind of noise that made the
   2026-09-19 test-script near-miss (`AGENTS.md`) harder to spot quickly in `git status`.
8. ~~Trim or rotate `pipeline_execution.log`~~ **RESOLVED 2026-09-19.** Root cause: it was
   already listed in `.gitignore` (added Phase 0) but never actually untracked from git's index —
   the exact same already-tracked-before-ignored gap `.gitignore`'s own header comment already
   documented for `.Rhistory`/`logs/*.duckdb`, just missing from that list. Fixed with
   `git rm --cached pipeline_execution.log` (file stays on disk, stops being committed going
   forward) plus real size-based rotation added to `schedule_daily.bat` (`.log` → `.log.old` once
   it exceeds 5MB, tested in isolation before landing in the real script).

## Product / UX

9. ~~Fix the Model Diagnostics tab's cosmetic text-overflow~~ **RESOLVED 2026-09-19.**
   `.diag_empty_plot()` now takes `size`/`wrap_width` params (`strwrap()`-based re-wrapping,
   since plotly doesn't auto-wrap `annotate()` text to the containing box's pixel width); the
   narrow width=4 "Residual Distribution" panel's call site uses a smaller size + tighter wrap
   than the two wider panels. Verified via the `headless-ui-regression-sweep` skill: 10/10 tabs
   clean (0 console errors), screenshot read confirms clean centered wrapping, no overflow/clip.
   Bonus fix: `tab_model_diagnostics` itself was missing from `tools/headless_dashboard_probe.R`'s
   `TAB_VALUES` sweep list entirely (a real, pre-existing coverage gap, not caused by this
   change) — added.
10. ~~Reconcile the `WNBA_GAME_5`/`WNBA_GAME_6` `is_synthetic` discrepancy~~ **RESOLVED
    2026-09-19.** Root cause: there was no real external mystery — the "already TRUE" reading
    reported earlier that same day was a self-inflicted artifact (an in-progress ad hoc test
    script had briefly overwritten the working-tree cache with toy fixture data before being
    caught and restored via `git checkout --`; the committed history at every commit,
    verified via `git show <rev>:cache/prediction_accuracy_log.rds`, has always shown `FALSE`).
    Investigating that also surfaced a REAL, still-live bug: the WNBA_GAME_N classifier fix could
    never have retroactively fixed these two rows anyway, because (a) `migrate_prediction_log()`'s
    `needs_migration` guard skips already-`schema_version == 2` rows entirely, and (b) even past
    that guard, the `coalesce()`-based "preserve anything already stamped" backfill logic would
    have kept the stale incorrect `FALSE` forever (coalesce only fills `NA` gaps). Fixed by
    bumping `PRED_LOG_SCHEMA_VERSION` 2 → 3 (forces a re-scan of all rows) and adding an explicit
    force-override for `is_unprovenanced_fixture` matches that bypasses the coalesce-preserve
    logic (safe because that predicate's definition can never match a genuine post-provenance
    row). Applied to the real cache via `get_prediction_log()`: all 6 `WNBA_GAME_N` rows now
    correctly `is_synthetic = TRUE`, 0 false positives among the other 11 real rows. Regression
    test added: `tools/test_pure_functions.R` CHECK 10b.

## Research (lower priority, no confirmed edge in what's already been tested)

11. **Close out or explicitly shelve the prediction-market research thread**
    (`docs/prediction_market_alpha_research_plan.md`). All four originally-scoped hypotheses
    closed "no confirmed edge" as of 2026-09-17. The only unclosed sub-questions are Polymarket
    connectivity (never checked) and cross-venue arbitrage (doesn't depend on this repo's model
    being right, so unaffected by the negative results) — worth an explicit one-line decision
    (pursue or park) so this doesn't linger as ambiguous scope indefinitely.
