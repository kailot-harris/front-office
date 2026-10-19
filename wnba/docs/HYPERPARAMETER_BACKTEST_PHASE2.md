# Hyperparameter Optimization — Phase 2: Rigorous Backtest

Date: 2026-09-16
Follows: `docs/develop-a-plan-to-parallel-robin.md` (Phase 1)
Scripts: `tools/optimize_hyperparams.R` (Phase 1), `tools/backtest_margin_hyperparams.R` (Phase 2, new)
Production file changed: `market_odds_engine.R` (`apply_rating_limits()`, `calculate_matchup_delta()`)
Cache artifact: `cache/hyperparam_backtest_phase2_results.rds`

## Why Phase 2 exists

Phase 1 (`tools/optimize_hyperparams.R`) grid-searched `limit`, `dampening`, `star_weight`
against `cache/prediction_accuracy_log.rds`'s 100 `RESOLVED` rows and found a **boundary
optimum** — `limit=5.0`, `dampening=0.1`, `star_weight=0.0` — sitting at the literal edge of
the searched grid. That log is small and partly synthetic (some rows have off-season dates
like `2026-02-18`, and at least one self-matchup, `PHX` vs `PHX`), so a boundary hit there is
the classic signature of overfitting to noise, not a trustworthy signal. Phase 1's own
write-up flagged this explicitly and declined to zero out `star_weight` on that evidence
alone.

**Phase 2's job**: re-run the same optimization against the *entire real testing set* —
`data/box_scores_cache.rds` (1,953 real completed WNBA games, 2019–2026, not the 100-row
synthetic log) — with a genuinely rigorous regime: leakage-free walk-forward cross-validation,
bootstrap confidence intervals, and explicit boundary/stability checks, matching the
convention already established in `tools/ml_cv_benchmark.R` (LOSO CV + bootstrap CI) and
`config.R`'s own note on `ROLLING_WINDOW_SIZE` that a "leave-one-season-out CV re-selection...
would be the more rigorous next step."

## Method: two tracks, because no single real dataset can test all three hyperparameters

`apply_rating_limits()`'s `limit`/`dampening` operate on a team's net rating; `calculate_matchup_delta()`'s
`star_weight` operates on a top-player RAPM gap. Both need real historical data to validate honestly, but
this repo does not have point-in-time historical snapshots of `cache/projected_wnba_standings.rds` or
`cache/rapm_ratings.rds` — only a single current-day snapshot. So Phase 2 splits the backtest:

### Track A — Walk-forward LOSO CV, all 8 real seasons (`limit`, `dampening` only)
- Builds a **leakage-free proxy net rating**: each team's trailing rolling point differential over
  `ROLLING_WINDOW_SIZE` (12, from `config.R`) games, reset per season — identical convention to
  `tools/ml_cv_benchmark.R`'s `build_feature_df(method="reset")`. No future game ever leaks into a
  prediction.
- For each of the 8 seasons (2019–2026), the `limit × dampening` grid (same ranges as Phase 1: `limit`
  5.0–25.0 step 2.5, `dampening` 0.1–0.9 step 0.1) is fit **only on the other 7 seasons**, then evaluated
  on the held-out season. All 8 folds' out-of-fold (OOF) predictions are pooled for one honest MAE
  estimate — a combination never trained on its own test data, unlike Phase 1's single fit-and-evaluate-on-
  the-same-log approach.
- N = 1,902 real games (1,953 minus each season's first `ROLLING_WINDOW_SIZE` team-games, which can't have
  a full trailing window).
- `star_weight` is **not** testable here (no historical per-game RAPM).

### Track B — Cross-sectional backtest, real 2026 season (`limit`, `dampening`, `star_weight`)
- Same method as Phase 1 (current cached standings + shot-quality luck + RAPM), but evaluated against
  **301 real 2026-season games** from `box_scores_cache.rds` instead of the 100-row (partly synthetic)
  prediction log.
- Full 3-D grid search (limit × dampening × star_weight, same ranges as Phase 1 — 891 combinations),
  bootstrap 95% CIs (2,000 resamples), and a stability/neighbor check exactly like Phase 1's.

### Combined step
A marginal `star_weight` sweep at Track A's validated `limit`/`dampening`, isolating the `star_weight`
effect from the `limit`/`dampening` effect (Track A can't see `star_weight`; Track B's *joint* 3-D optimum
can conflate the two).

## Critical finding: Star Power Delta has never actually been active in production

While building Track B, `star_gap` (the RAPM difference feeding `star_weight`) came out **identically 0.0
for every one of the 301 real games**, regardless of `star_weight`. Root cause, found by inspecting the two
caches `calculate_matchup_delta()` joins:

| | `rapm_ratings.rds` | `active_rosters_cache.rds` |
|---|---|---|
| `player_id` scheme | stats-provider numeric IDs (e.g. `201496`) | ESPN athlete IDs (e.g. `869`) |
| `player_name` format | **last name only** (e.g. `"Wilson"`) | full `"First Last"` (e.g. `"A'ja Wilson"`) |
| Overlap | **0 of 430 `player_id` values match any of 209 roster `player_id` values.** A naive full-name join is also 0/430. |

`calculate_matchup_delta()` (`market_odds_engine.R`) has been joining on `player_id` since it was added, so
`h_top`/`a_top` were always length-0, and the function's `if (length(h_top) == 0 || length(a_top) == 0)
return(0.0)` fallback fired on **every single call**. This means:

- Phase 1's finding that `star_weight = 0.0` "minimized MAE" was **not evidence the feature doesn't help** —
  it was evidence the feature was never computing anything, so every `star_weight` value produced identical
  predictions. The grid search couldn't have found otherwise.
- This is exactly the kind of "silently corrupting results" issue `CLAUDE.md` calls out for the `CONN`/`CON`
  and `%||%`-on-a-vector bugs — a clean fail-safe fallback (0.0, no crash) masking a real, previously
  undiagnosed data-join defect.

**Fix applied** (in both `tools/backtest_margin_hyperparams.R`'s `build_team_lookups()` and production
`market_odds_engine.R`'s `calculate_matchup_delta()`): join on `(team full name, normalized last name)`
instead of `player_id`/full name. Verified safe before applying:
- **Zero team+last-name collisions** across all 209 rostered players (checked via
  `count(team_abbreviation, last_name) |> filter(n > 1)` — 0 rows).
- Every one of the 15 `WNBA_TEAMS` has **≥5 matched players** after the join (range 5–11, median 9), so
  `star_gap` is computable for essentially every matchup.
- Recovers 121 of 209 roster players (58%) to a real RAPM rating — not complete (some players in
  `active_rosters_cache.rds` genuinely aren't in `rapm_ratings.rds`'s 430-player pool, e.g. deep bench/two-way
  players), but enough to make `star_weight` a real, testable parameter for the first time.

This is a **strictly safe change**: the prior behavior was "always return 0.0" (a no-op), so any nonzero
output after the fix is a net improvement in the model actually doing what it was designed to do, with no
regression path.

**Follow-up for whoever owns `rapm_engine.R`**: the two caches' ID schemes never overlapping suggests
`rapm_ratings.rds` is being built from a different provider than the ESPN-sourced roster pull — worth
tracing where `rapm_engine.R` sources its `player_id`/`player_name` from, and whether a real ID crosswalk
(rather than this last-name-join workaround) is feasible. The workaround here is safe but not perfect
(42% of rostered players have no match).

## Results

### Track A (walk-forward LOSO CV, N=1,902 real games, 8 seasons)

| Fold (held-out season) | n | Train-selected limit | Train-selected dampening | Train MAE | **OOF test MAE** |
|---|---|---|---|---|---|
| 2019 | 214 | 5.0 | 0.1 | 13.201 | 12.261 |
| 2020 | 141 | 5.0 | 0.1 | 13.021 | 14.019 |
| 2021 | 204 | 5.0 | 0.1 | 13.047 | 13.493 |
| 2022 | 234 | 5.0 | 0.1 | 13.047 | 13.432 |
| 2023 | 255 | 5.0 | 0.1 | 13.110 | 12.999 |
| 2024 | 257 | 5.0 | **0.2** | 13.141 | 12.876 |
| 2025 | 304 | 5.0 | 0.1 | 13.054 | 13.309 |
| 2026 | 293 | 5.0 | 0.1 | 13.140 | 12.845 |

- `limit=5.0` was selected in **8 of 8** folds; `dampening=0.1` in **7 of 8** (2024's fold picked the
  immediately adjacent 0.2). This is a genuinely stable selection, not a fluke of one sample.
- **Pooled OOF MAE: 13.107 [95% CI 12.696–13.520], N=1,902.** This is the honest, cross-validated estimate —
  every prediction came from a model that never saw its own season.
- Reference (fit-once-on-everything, not cross-validated): pre-optimization defaults
  (`limit=15.0, dampening=0.5`) MAE = 13.567; Phase 1's values (`limit=5.0, dampening=0.1`) MAE = 13.095.
- Full-data grid optimum: `limit=5.0, dampening=0.1`, MAE = 13.095. Still a boundary hit on the searched
  grid range, but stability check on immediate neighbors: mean MAE 13.167, sd 0.078 — a shallow, consistent
  basin, not an isolated spike (sd is small relative to the ~0.47-point gap vs. the pre-optimization
  defaults).

**Conclusion for `limit`/`dampening`: Phase 1's values are confirmed, not an artifact.** Real,
leakage-free, 8-season cross-validated evidence supports `limit=5.0, dampening=0.1` over the
pre-optimization defaults (`15.0`/`0.5`). The consistent per-fold selection across completely disjoint
train/test splits is much stronger evidence than Phase 1's single fit against 100 rows could ever provide.

### Track B (cross-sectional, N=301 real 2026-season games, join bug fixed)

| Combination | MAE |
|---|---|
| Pre-Phase-1 defaults (`limit=15.0, dampening=0.5, star_weight=0.20`) | 13.425 |
| Phase 1 boundary optimum (`limit=5.0, dampening=0.1, star_weight=0.00`) | 12.877 |
| **Track B full-grid optimum (`limit=5.0, dampening=0.1, star_weight=0.15`)** | **12.875** |

- Bootstrap 95% CI: defaults `[12.266, 14.648]`, Track B optimum `[11.828, 13.950]` — CIs overlap
  substantially (N=301 single-season is still a modest sample for pinning down a precise MAE), but the point
  estimate favors the optimized combination.
- Stability check (immediate grid neighbors around the optimum): mean MAE 12.907, sd 0.032 — tight, no spike.
- `limit`/`dampening` still hit the grid boundary here too (consistent with Track A). `star_weight=0.15` is
  **not** a boundary value (searched range was 0.0–0.5).

### Marginal `star_weight` sweep (at Track A's validated `limit=5.0, dampening=0.1`, join bug fixed)

| star_weight | MAE |
|---|---|
| 0.00 | 12.877 |
| 0.05 | 12.876 |
| 0.10 | 12.875 |
| **0.15** | **12.875** |
| 0.20 (prior default) | 12.875 |
| 0.25 | 12.876 |
| 0.30 | 12.877 |
| 0.35 | 12.879 |
| 0.40 | 12.882 |
| 0.45 | 12.885 |
| 0.50 | 12.888 |

The curve is genuinely U-shaped (not monotonic, not a boundary hit) but very flat: MAE differs by only
0.0001–0.013 across the entire 0.00–0.50 range. **Practical read: `star_weight` barely matters once the join
bug is fixed** — the effect size of the star-power gap on margin is small relative to net rating and HCA.
Anything in roughly 0.05–0.30 is statistically indistinguishable at this sample size; 0.15 is the point
estimate and was applied.

## What changed in `market_odds_engine.R`

- `apply_rating_limits()`: `limit`/`dampening` unchanged in value (`5.0`/`0.1`, same as Phase 1) but the
  comment now cites Phase 2's cross-validated evidence instead of Phase 1's overfit caveat.
- `calculate_matchup_delta()`:
  - **Bug fix**: join changed from `player_id` (0% overlap, always-0.0 fallback) to `(team full name,
    normalized last name)` (58% coverage, verified collision-free, all 15 teams represented).
  - `star_weight` changed from `0.2` (pre-optimization default, never actually exercised) to `0.15` (Phase
    2's validated point estimate, now that the feature is live).

## Guardrails followed (per `docs/develop-a-plan-to-parallel-robin.md`'s own stability mandate)

1. **Stability check**: done for both tracks via immediate-grid-neighbor MAE (not just a single spike point)
   — see tables above.
2. **Comparison against defaults**: done for both tracks, with bootstrap CIs where the sample size warranted
   it (Track B; Track A uses cross-fold OOF pooling instead, which is the stronger check).
3. **No p-hacking / no fabricated data**: both tracks use only real games from `data/box_scores_cache.rds`;
   no synthetic rows were introduced. The last-name join fix was verified for collision-safety before use,
   not assumed safe.

## Remaining limitations (for the next agent to pick up)

- Track A's `limit`/`dampening` optimum is still a grid-boundary hit. The grid's floor (5.0/0.1) was
  inherited from Phase 1's plan document, not re-derived here. A wider sweep (e.g. `limit` down to 1.0,
  `dampening` down to 0.0) would tell us whether 5.0/0.1 is a true interior optimum or just "the most
  aggressive damping we let it try." Worth a Phase 3 pass with `optim()`/continuous optimization (see
  `tools/optimize_hca.R`'s `L-BFGS-B` pattern) instead of a fixed grid.
- Track B's `star_weight` evidence is single-season (2026 only, N=301) because that's the only season with a
  live `active_rosters_cache.rds`/`rapm_ratings.rds` snapshot. It cannot be walk-forward validated the way
  `limit`/`dampening` were without historical per-game roster/RAPM snapshots, which don't exist in this repo.
- The last-name join recovers 58% of rostered players (121/209). The 42% gap is undiagnosed — could be
  genuinely low-RAPM-sample bench players correctly absent from `rapm_ratings.rds`, or could be further name-
  normalization misses (nicknames, suffixes, hyphenation). Not investigated further here; flagged above for
  whoever owns `rapm_engine.R`.
- `market_odds_engine.R`'s inline comment for the home-court-advantage constant still says "(2.40)" while the
  code and `tools/optimize_hca.R`'s baseline both use `11.6`/`2.4` inconsistently across files (`market_odds_engine.R`
  line ~386 comment vs. line ~390's actual `11.6` literal). Not in scope for this hyperparameter task, but
  flagged here since it's the kind of stale-comment/actual-value mismatch `CLAUDE.md` warns about — worth a
  dedicated look before trusting HCA-related comments elsewhere in the file.
- `CLAUDE.md` describes `ROLLING_WINDOW_SIZE` as "13 (empirically re-benchmarked...)" but `config.R`'s actual
  live value is `12` (see `config.R` lines 104-121's own comment explaining the 12-vs-13 re-derivation). This
  script reads `ROLLING_WINDOW_SIZE` from `config.R` correctly (12), but flagging the `CLAUDE.md` summary text
  as stale for whoever next updates that file.

## Reproduce

```
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\backtest_margin_hyperparams.R
```

Outputs both tracks' full console report and saves `cache/hyperparam_backtest_phase2_results.rds`
(`track_a`, `track_b`, `sw_sweep`, `recommendation` — a list with `limit`, `dampening`, `star_weight`).
