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
8. **Trim or rotate `pipeline_execution.log`** — it has added thousands of lines in single commits
   before; either gitignore it or add real log rotation.

## Product / UX

9. **Fix the Model Diagnostics tab's cosmetic text-overflow** in the narrow "Residual
   Distribution" panel (`app.R`) — flagged in two prior sessions, still open, low priority.
10. **Reconcile the `WNBA_GAME_5`/`WNBA_GAME_6` `is_synthetic` discrepancy** noted in
    `docs/HANDOFF.md`'s 2026-09-19 (first) session entry — the live cache already shows the
    correct `TRUE` value for both rows, but no session has determined what actually changed it
    (the classifier fix landed the same day but, per the idempotency guard, could not itself have
    touched an already-`schema_version == 2` row). A `git log -p -- cache/prediction_accuracy_log.rds`
    dig (accepting it'll be a binary diff, but commit timestamps/messages may narrow it down) is
    the likely next step, not a re-guess.

## Research (lower priority, no confirmed edge in what's already been tested)

11. **Close out or explicitly shelve the prediction-market research thread**
    (`docs/prediction_market_alpha_research_plan.md`). All four originally-scoped hypotheses
    closed "no confirmed edge" as of 2026-09-17. The only unclosed sub-questions are Polymarket
    connectivity (never checked) and cross-venue arbitrage (doesn't depend on this repo's model
    being right, so unaffected by the negative results) — worth an explicit one-line decision
    (pursue or park) so this doesn't linger as ambiguous scope indefinitely.
