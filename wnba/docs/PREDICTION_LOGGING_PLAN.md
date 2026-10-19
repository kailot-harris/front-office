# Prediction Accuracy Logging — Implementation Plan

## Goal

Build a **daily, structured, append-only log of the model's own pre-game win-probability predictions
vs. actual game outcomes**, distinct from `bet_tracker.r`'s betting ledger (which only tracks games that
were actually bet on, filtered by EV/CLV thresholds). This log must capture **every** real game the
model made a prediction for, whether or not it became a bet, so it can support future analysis of
model accuracy/calibration/drift and inform model-refinement decisions — the explicit purpose stated in
the request. Only log/reconcile on days real games actually occurred; do not write empty/no-op rows
during the off-season.

## Why this is a new artifact, not a repurposing of `betting_ledger.rds`

`bet_tracker.r`'s ledger only contains games that passed `notify_bets.R`'s EV≥3%/CLV≥-0.5% filter or
`market_odds_engine.R`'s `★ VALUE BET`/`🔥 SHARP +EV` tagging — a biased subset (implicitly favors games
where the model disagreed with the market). A fair accuracy/calibration analysis needs **every** game the
model priced, not just the ones deemed +EV. This mirrors the same reasoning already documented in
`docs/ML_BENCHMARK_REPORT.md` for why backtesting needs the full game set, not a filtered one.

## Existing patterns this design deliberately reuses (read these first)

1. **`bet_tracker.r`'s two-phase PENDING → RESOLVED pattern** (`append_todays_picks()` then
   `grade_yesterday_bets()`, joining against `box_scores_cache.rds` on `(team, game_date)`). This is the
   proven, working precedent in this exact codebase for "record a prediction now, reconcile it against
   reality once known" — the new logger mirrors this structure rather than inventing a different one.
2. **`roster_bottom_up_engine.R::predict_live_matchup(home_team, away_team, active_rosters,
   player_ratings, injury_df)`** — returns `Home_Win_Prob`, `Fair_Spread`, `Fair_Home_ML`,
   `Home_Rating`, `Away_Rating` for a given matchup. This is the model's actual prediction function;
   reuse it directly rather than re-deriving win probability differently.
3. **`market_odds_engine.R::get_model_slate_probabilities(slate_df)`** already computes model win
   probabilities for every real game in that day's slate (from `fetch_market_odds()`'s live Odds API
   pull) as part of normal daily operation, and `evaluate_betting_slate()` writes a `Model_Win_Prob`
   column to `cache/latest_value_bets.rds` for every game with usable market odds. This is the
   lowest-risk source of "today's real games + today's model prediction" — reuse this computation
   instead of recomputing predictions from scratch, to guarantee the logged prediction is the exact same
   number the rest of the pipeline (EV, notify_bets) actually acted on that day. Note: `latest_value_bets.rds`
   itself is **not** a valid historical log — it's overwritten daily and filtered to bettable games — it
   is only used here as a same-day data source to read from, not written to.
4. **`P5`'s `logging_utils.R`** (`log_info()`/`log_warn()`/`log_error()`, `logs/wnba_pipeline.log`) — for
   *operational* visibility ("logged N predictions," "reconciled N outcomes," "0 games today, skipped").
   This is explicitly **not** where the analytical data goes — see Best Practice #4 below.

## A real, pre-existing gap this plan must account for

**`daily_ingest.R` (which refreshes `box_scores_cache.rds` with real completed-game results) is not a
stage in `run_full_pipeline.R`'s 13-stage DAG** — confirmed by reading `run_full_pipeline.R` directly.
`bet_tracker.r` already silently depends on this file being fresh and has no defensive refresh
(`box_scores <- if (file.exists(CACHE_TEAM_BOX)) readRDS(CACHE_TEAM_BOX) else tibble()` — no incremental
pull). This means bet grading today may already be running against stale box scores if nobody manually
ran `daily_ingest.R` recently. **The new reconciliation step must not repeat this mistake**: it should
call `daily_box_ingest()` (from `daily_ingest.R`) defensively before reading `box_scores_cache.rds`, to
guarantee freshness regardless of DAG ordering. (Fixing `bet_tracker.r`'s pre-existing version of this
same gap is out of scope for this task — flag it in `docs/USER_TASKS.md` Stage 4 backlog instead, since
it's a separate, already-shipped script this task shouldn't need to modify.)

## Schema — `cache/prediction_accuracy_log.rds`

One row per `(game_id)`, append-only (never delete/overwrite past rows; only update a matching row's
status from `PENDING` to `RESOLVED`). Tidy, typed, one observation per row:

| Column | Type | Notes |
|---|---|---|
| `schema_version` | int | `1L` — bump if columns ever change, so old rows remain parseable |
| `game_id` | chr | join key; dedup key for idempotency |
| `game_date` | Date | |
| `season` | int | |
| `home_team`, `away_team` | chr | canonical `WNBA_TEAMS` abbreviations |
| `prediction_timestamp` | POSIXct | when the prediction was logged (same-day, pre-outcome) |
| `predicted_home_win_prob` | dbl | from `predict_live_matchup()`/`get_model_slate_probabilities()` |
| `predicted_winner` | chr | derived: home if prob ≥ 0.5 else away |
| `model_rolling_window_size`, `model_margin_sigma`, `model_rotation_size`, `model_offseason_method` | — | **config snapshot** — the active `config.R` constants at prediction time, so future analysis can tell whether an accuracy shift came from a real model change or just different games (config values do change over time in this repo, as seen this session) |
| `injury_data_source`, `shot_quality_data_source` | chr | were prediction inputs live or fallback that day (data completeness matters for fair analysis) |
| `status` | chr | `PENDING` / `RESOLVED` |
| `actual_winner` | chr | filled in on reconciliation |
| `correct` | lgl | filled in on reconciliation |
| `brier_component` | dbl | `(predicted_home_win_prob - actual_home_win)^2`, filled in on reconciliation |
| `log_loss_component` | dbl | filled in on reconciliation |
| `resolved_timestamp` | POSIXct | filled in on reconciliation |

Stored as `.rds` (matches project convention); also write a `.csv` mirror for easy manual inspection
(matches the precedent set by `window_sweep_3_25_results.csv`).

## Best practices applied (and why each one, explicitly — not just "because it's good practice")

1. **Idempotency.** Safe to run the pipeline multiple times a day without duplicate rows — dedupe on
   `game_id` before inserting new `PENDING` rows (exact same discipline `bet_tracker.r`'s
   `append_todays_picks()` already uses).
2. **Append-only / immutable history.** Never rewrite a `PENDING` row's `predicted_home_win_prob` after
   the fact — only add the outcome fields once known. This is what makes the log trustworthy for future
   analysis: it proves the prediction was genuinely made *before* the result was known, preventing
   hindsight bias from contaminating later model-refinement decisions.
3. **Point-in-time correctness (no leakage).** Predictions are logged same-day, pre-outcome, using only
   data available at prediction time — this is guaranteed by construction (reusing the pipeline's actual
   same-day prediction output), not something to re-derive after the fact.
4. **Separation of operational logs from analytical data.** `logs/wnba_pipeline.log` (P5) answers "did
   the job run OK" for a human/on-call context; `cache/prediction_accuracy_log.rds` answers "how good is
   the model" for a data-analysis context. Conflating the two (e.g. parsing accuracy stats out of text
   log lines) would be fragile and wrong — keep them as separate systems that both exist, per project
   convention.
5. **Config/provenance snapshotting.** Record the model config and data-completeness flags active at
   prediction time (see schema above) — essential for correctly attributing future accuracy changes to
   real causes rather than confounding them with unrelated data/config drift.
6. **Trigger-gated, not unconditional.** Only write/reconcile rows when real games actually occurred that
   day (check real row counts from the slate/box-score sources before acting) — matches this project's
   established off-season-fallback discipline (no noise rows during the ~6-7 month WNBA off-season).
7. **Fail-safe.** Wrapped in `tryCatch`, logged via `logging_utils.R`, never allowed to crash
   `run_full_pipeline.R` if it fails — matches every other stage's `run_stage()` behavior.
8. **Schema versioning.** `schema_version` column from day one, even though there's only one version now
   — cheap to add now, expensive to retrofit onto months of accumulated real data later.

## Phased Implementation (single agent, sequential within one run)

**Phase 1 — Core logger script (`prediction_accuracy_logger.R`)**
1. `log_todays_predictions()`: get today's real games + model win-probabilities (prefer reading
   already-computed `Model_Win_Prob` values from the same source `market_odds_engine.R` uses that day,
   falling back to calling `predict_live_matchup()` directly per real active game if a game lacks market
   coverage — read `market_odds_engine.R` first to confirm the exact reusable function/variable to call
   rather than duplicating its logic). Skip entirely (log an `INFO`, not an `ERROR`) if zero real games
   are found for today. Append new `PENDING` rows, deduped by `game_id`.
2. `reconcile_predictions()`: defensively ensure fresh box scores (call `daily_box_ingest()` first, per
   the gap noted above), then join `PENDING` rows against real completed games by `(game_id)` or
   `(team, game_date)` (mirror `bet_tracker.r`'s exact join-key pattern — verify `game_id` is actually
   consistent/joinable across the odds slate and `box_scores_cache.rds`; if not, fall back to the same
   `(team_name, game_date)` join `bet_tracker.r` uses). Compute `actual_winner`/`correct`/
   `brier_component`/`log_loss_component`, flip status to `RESOLVED`. Skip gracefully if there's nothing
   to reconcile.
3. Both functions guarded with `tryCatch` + `logging_utils.R` calls; write to
   `cache/prediction_accuracy_log.rds` + `.csv` mirror.

**Phase 2 — Wire into `run_full_pipeline.R`**
4. Add two new `run_stage()` calls: reconciliation early (after rosters/injuries sync, so it can use
   fresh data, but logically independent of other stages) and today's-prediction-logging after
   `roster_bottom_up_engine.R`/`market_odds_engine.R` have produced today's ratings/slate (so it can read
   their real output rather than recomputing). Read the current stage list in `run_full_pipeline.R` to
   pick exact insertion points; do not reorder existing stages.

**Phase 3 — Basic analysis helper**
5. Add `summarize_prediction_accuracy(window = c("7d","30d","season","all"))` to
   `prediction_accuracy_logger.R`: rolling accuracy/Brier/log-loss over `RESOLVED` rows for a given
   window — a thin, real function future analysis (or a future dashboard tab) can call, not a full
   dashboard integration (out of scope for this task; note it as a natural follow-up in the Handoff
   Notes instead of building it now).

**Phase 4 — Verification (do not skip)**
6. Actually run the new stages end-to-end via `Rscript.exe` against real data (temp-file-then-run
   pattern; R at `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`, not on PATH) and confirm real rows are
   written with sane values. Since reconciliation needs a *past* `PENDING` row to resolve, and this is
   the first real run, either (a) run `log_todays_predictions()` then manually backdate/test
   `reconcile_predictions()` against yesterday's real completed games as a one-off validation, or
   (b) write a small standalone test that feeds a synthetic `PENDING` row for a real already-completed
   historical game and confirms reconciliation computes correct `brier_component`/`correct` values —
   document whichever approach was used and why.
7. Re-run the existing `tools/headless_dashboard_probe.R` afterward to confirm the two new
   `run_full_pipeline.R` stages don't break anything the dashboard reads (they shouldn't touch any
   existing cache file, but verify rather than assume).

## Tracking

Add a new dated section to `docs/task_assignments_phase2.md` (continuing this project's established
Handoff Notes convention) documenting what was built, real verification evidence, and any deviation from
this plan. Update `docs/USER_TASKS.md` if this surfaces any new user-facing step (e.g., "let the pipeline
run for N real game-days before the accuracy log has enough rows to be useful for analysis").
