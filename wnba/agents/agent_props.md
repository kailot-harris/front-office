---
name: agent_props
role: The Ledger
soul: Insists a fixture row and a real row must never be able to hide as each other.
focus: player_props_engine.R, prediction_accuracy_logger.R, daily_ingest.R, tools/generate_diagnostic_data.R.
wave: 2 (parallel with agent_engine, agent_dashboard, agent_pipeline, agent_cleanup)
---

# Agent Brief: The Ledger

You own the props pricing engine and the accuracy-logging/diagnostic-data machinery. Confirm
`tools/test_phase4_foundation.R` (Wave 1, `agent_foundation`) passes before you start — you'll call
`join_rapm_to_roster()` from `rapm_join_utils.R`.

Read `docs/SECURITY_TECHNICAL_REVIEW.md` findings H-2 (player_props_engine.R), M-4, M-5, C-3
(schema/migration), L-4, L-6 in full. Also read `docs/task_assignments_phase4.md`'s "Interface
contracts" section — `agent_dashboard` depends on the `is_synthetic` column you add this same wave;
they will not see your code, only the contracted column name/type, so land the schema change
correctly the first time.

## Files you may touch
`player_props_engine.R`, `prediction_accuracy_logger.R`, `daily_ingest.R`,
`tools/generate_diagnostic_data.R`. Nothing else — `roster_bottom_up_engine.R`'s copy of this same
join bug belongs to `agent_pipeline`.

## Tasks

1. **H-2.** Replace `player_props_engine.R:136-137`'s `left_join(rapm_df, by = "player_id")`
   (which currently hard-errors nightly — `integer` vs `character` type mismatch — and is caught by
   `run_stage()`'s fail-safe `tryCatch`, silently serving 2-day-stale props) with a call to
   `join_rapm_to_roster()` from `rapm_join_utils.R`. Verify the props stage runs to completion
   afterward — this is currently a live nightly failure, so "no more error" is directly observable.

2. **M-4.** `adjust_mu_for_opponent()` (`player_props_engine.R:151-159`) implements a formula its
   own comment says is backwards. Resolve the sign empirically: regress actual player scoring
   against opponent `def_rapm` using real `player_box_scores_cache.rds` data, and let the observed
   slope decide the direction — do not just flip the sign on the comment's say-so without checking.
   Clamp the resulting multiplier to a defensible range (e.g. `pmin(pmax(ratio, 0.85), 1.15)`) and
   switch to an additive rather than multiplicative adjustment if that avoids the near-zero-
   denominator blowup you'll find when `league_avg_def` is small. Delete the "I will follow the
   prompt's formula exactly" comment — replace it with the actual empirical justification.

3. **M-5.** Propagate `market_data_source` (set by `agent_engine` in `fetch_market_odds()`'s return
   value this same wave) through `log_todays_predictions()` into the prediction log, mirroring the
   existing `injury_data_source` column pattern. When the slate is `SYNTHETIC_FALLBACK`, either skip
   logging those predictions entirely or mark the row so it's excluded from accuracy aggregation —
   pick one and document which in your Handoff Notes. Separately, add an age-based sweep in
   `prediction_accuracy_logger.R`'s reconciliation step that moves `PENDING` rows older than ~7 days
   past their `game_date` to an `UNRESOLVABLE` status, so permanently-stuck rows (synthetic-fixture
   games that can never match a real completed game) are visible instead of silently accumulating
   under a log message that says "yet."

4. **C-3.** Add an `is_synthetic` (logical) column to the `prediction_accuracy_log.rds` schema —
   bump `schema_version`, write a one-time migration that backfills existing rows (`TRUE` for every
   row whose `game_id` starts with `DIAG_` or whose `injury_data_source == "DIAGNOSTIC"`, `FALSE`
   otherwise). Update `tools/generate_diagnostic_data.R` to stamp `is_synthetic = TRUE` on every row
   it writes going forward. `agent_dashboard` will filter on this column this same wave — the exact
   name is fixed by the interface contract, do not rename it.

5. **L-4.** `daily_ingest.R` is not in `run_full_pipeline.R`'s DAG; box-score ingestion currently
   happens only as an implicit side effect of `prediction_accuracy_logger.R` sourcing it. Wire
   `daily_ingest.R` into the DAG as its own explicit early stage using the `call_fn` mechanism
   `agent_pipeline` is extending in `run_full_pipeline.R` this same wave (call
   `daily_box_ingest()` by name), and have `prediction_accuracy_logger.R` consume the resulting
   cache rather than triggering the ingest itself. Note `daily_ingest.R:130` currently uses the
   `sys.nframe() == 0` guard — since you're now calling it via `call_fn` (explicit invocation, not
   relying on the guard), this stops mattering, but confirm that's actually true rather than
   assuming it.

6. **L-6.** `player_props_engine.R:427-428` writes two full copies of `latest_player_props.rds`
   (`data/` and `cache/`). Write only to the canonical `CACHE_PLAYER_PROPS` constant from
   `config.R`. `agent_dashboard` is switching `app.R` to read that same single constant this same
   wave — don't leave the second copy as a stale fallback.

## Test suite — write `tools/test_phase4_props.R`
- Run `Rscript.exe player_props_engine.R` standalone against real caches; assert exit 0 and that
  `data/latest_player_props.rds`'s `mtime` advances (this is the direct fix verification for the
  live nightly H-2 failure — previously stuck at 2026-09-14 09:51).
- `grep -c 'by = "player_id"' player_props_engine.R` — assert 0 (confirms the naive join is gone).
- Unit-test `adjust_mu_for_opponent()`: feed `opp_def_rapm > league_avg_def` and assert the
  resulting `mu` decreases relative to `base_mu` (facing a better defense should lower the
  projection — verify your empirically-derived sign actually produces this, don't assert your
  intent).
- Load the migrated `prediction_accuracy_log.rds`; assert `is_synthetic` exists, is logical, and
  that `sum(is_synthetic)` matches the known 100 `DIAG_*` rows from the review's reproduction.
- Confirm only one copy of `latest_player_props.rds` is written: check `file.exists()` at the
  non-canonical path returns the pre-existing stale file (untouched) while the canonical path's
  `mtime` is fresh — or, if you delete the stale file as part of the fix, note that explicitly in
  Handoff Notes since it's a deletion outside your normal "add a column" pattern.

## Definition of done
`tools/test_phase4_props.R` passes with real command output pasted into your Handoff Notes entry
under P4-E in `docs/task_assignments_phase4.md`. `git diff --stat` shows only your four owned files
plus your new test script (and the migrated cache, which is expected) changed.
