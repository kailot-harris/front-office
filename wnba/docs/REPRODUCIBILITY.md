# Reproducibility & the `generated_at` Policy

Status: landed with GitHub issue **#154** (blocker on repo epic #138 / cross-repo epic
`kailot-harris/front-office#92`).

This file is the authoritative statement of what "two consecutive runs produce identical
output" means in this repo. Several open tickets (#141, #144, #145, #146, #147, #148, #149,
#152) carry an acceptance criterion of that shape; read this before interpreting one of them.

---

## 1. The guarantee

> Two consecutive `Rscript.exe run_full_pipeline.R` runs, with **unchanged inputs** and **no
> ingestion in between**, must produce files under `web/public/data/` that are identical
> **except for the generation-timestamp fields listed in §3**.

"Unchanged inputs" means the caches under `cache/` and `data/` are not refreshed from a live
endpoint between the two runs. A run that re-pulls `wehoop`/`hoopR`/ESPN data and legitimately
receives newer data is **out of scope** for this guarantee — that is a data change, not a
reproducibility defect. When verifying a ticket, run the pipeline twice back to back so any live
pull returns the same payload both times.

## 2. `generated_at` policy

**Decision: timestamps stay wall-clock, and are EXCLUDED from the comparison. The clock is not
made injectable.**

Every published payload carries a provenance stamp written as

```r
generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
```

This is deliberate and must not be frozen, removed, or made deterministic:

- `tools/publish_web.R`'s **publish gate assertion F** ("payload provenance") reads exactly this
  field and asserts that every payload's stamp is **at or after the run's start time**. A frozen
  or injected-constant timestamp would make assertion F either vacuous or permanently failing —
  i.e. the fix would delete a real safety check in order to pass a test.
- The web app renders it as the user-visible "last updated" value.
- `.pw_payload_generated_at()` parses only the snake_case, UTC, trailing-`Z` form above. New
  payloads must use that exact form.

The alternative — a `PIPELINE_RUN_TIMESTAMP` injected from the environment so a verification run
could pin it — was rejected because it would let a stale payload masquerade as fresh, which is
the precise failure mode assertion F exists to catch.

**Consequence for ticket criteria:** a literal byte-identical test on `web/public/data/*.json`
will always fail. The correct test is the field-excluded diff in §4. Any ticket whose criterion
says "byte-identical" should be read as "identical except for the §3 fields".

## 3. Fields excluded from the comparison

These are the only fields permitted to differ between two consecutive runs. Anything else that
differs is a defect.

| field | where | notes |
|---|---|---|
| `generated_at` | every payload | wall-clock UTC stamp of the exporting run; read by publish-gate assertion F |
| `generatedAt` | `playoff_bracket_2026.json`, `finals_game_predictions_2026.json`, `finals_series_backtest_2026.json` | the **source cache artifact's** own `attr(x, "generated_at")`, camelCase, rendered by the web app. Distinct from `generated_at`; see the note at `export_web_json.R:1080-1087`. Also wall-clock. |
| `updated_at` | `shots_metadata.json` | third spelling, written at `build_shot_chart_dataset.R:151`. Same wall-clock semantics; kept as-is because the web app reads this name. Do not "normalize" it to `generated_at` without also updating the payload's consumer — `build_shot_chart_dataset.R:145` already emits a `generated_at` alongside it for assertion F. |

Nothing else. In particular, no *value* field may be excluded — §5 is the list of RNG sites that
used to make value fields drift, and all of them are now pinned.

## 4. How to verify

```sh
R="/c/Program Files/R/R-4.5.2/bin/Rscript.exe"
"$R" run_full_pipeline.R                       # run 1
mkdir -p /tmp/run1 && cp web/public/data/*.json /tmp/run1/
"$R" run_full_pipeline.R                       # run 2
for f in web/public/data/*.json; do
  b=$(basename "$f")
  n=$(diff "/tmp/run1/$b" "$f" | grep -c '^[<>]')
  t=$(diff "/tmp/run1/$b" "$f" | grep -c -E '"(generated_at|generatedAt|updated_at)"')
  [ "$n" != 0 ] && echo "$b: changed=$n ofWhichTimestamp=$t"
done
```

Pass condition: for every file, `changed == ofWhichTimestamp`.

To localise a failure, hash-bisect the caches rather than reading modelling code: hash every
file under `cache/` **and `data/`** before and after each run and diff the hashes. The stage
whose cache moved is the non-deterministic one. Note that `data/` matters — issue #154's root
cause was `data/team_embeddings.csv`, which a `cache/`-only sweep misses entirely.

## 5. RNG sites reached by the publishing path

Every site below is either pinned with a fixed seed or demonstrably not reached by anything
under `web/public/data/`. Seed *values* live in `config.R`'s "Reproducibility Seeds" block, not
inline. **Once a payload has shipped under a given seed, changing the seed is a published-value
change, not a refactor.**

| site | disposition |
|---|---|
| `team_embeddings.py:81` (`nn.Embedding`/`nn.Linear` weight init, then 120 Adam epochs) | **Was the root cause of #154.** Now pinned via `seed_everything()` from `config.R`'s `WNBA_EMBEDDING_SEED`, exported to the Python child by `run_full_pipeline.R`'s `run_stage()`. |
| `team_embeddings.py` `main()` mock-schema fallback (`np.random.randint` / `np.random.choice`) | Pinned by the same `np.random.seed()` call. Fallback kept intact — a fallback that draws randomly is itself a reproducibility bug, so it is seeded rather than removed. |
| `run_full_pipeline.R` latent-engines `future_lapply(..., future.seed = ...)` | Was `future.seed = TRUE`, which derives worker streams from the parent's clock-seeded RNG. Now a fixed `WNBA_PARALLEL_STREAM_SEED`. |
| `playoff_simulator.R` `simulate_single_series()` 10,000-series Monte Carlo (`runif(1)`) | Now `set.seed(WNBA_PLAYOFF_SIM_SEED + <per-matchup offset>)`, following `export_web_json.R`'s per-pair pattern. Writes `cache/playoff_series_wnba_demo.rds`, which no payload reads today; seeded anyway. |
| `export_web_json.R:855-865` per-pair series Monte Carlo | Already correct: `set.seed(42 + <pair index>)`. **Do not change.** This is the reference pattern. |
| `shot_quality_engine.R:137` `generate_team_shot_profiles_synthetic()` | Already seeded `set.seed(42)` at function entry, before any draw; re-seeded on every call, including the per-team fallback. Verified byte-stable: `cache/team_shot_quality.rds` hashed identical across two runs. |
| `build_coaching_dataset.R:69` `set.seed(42)` + the `runif()` block | Already seeded and byte-stable. **It never covered `actualProjectedWins` / `coachingWinsAdded`** — those are read out of `projections_season_teams.json` (`build_coaching_dataset.R:84-89`), so their drift was purely downstream of the embeddings bug. |
| `rapm_engine.R:133-135` `tune_lambda_cv()` CV folds | Seeded `set.seed(seed)`, default `seed = 20260101`. Also gated behind `RAPM_TUNE_LAMBDA` (default `FALSE`). `cache/rapm_ratings.rds` hashed identical across two runs. |
| `live_calibration.R:59` `rnorm()` in `simulate_live_game()` | **Not reached.** `live_calibration.R` is not a `run_full_pipeline.R` stage and `simulate_live_game()` has no caller in the repo's publishing path. |
| `dashboard_render_helpers.R:389` `rnorm()` | **Not reached.** Shiny render helper; `app.R` was retired under #142. Nothing under `web/public/data/` goes through it. |
| `tools/*` (`generate_diagnostic_data.R`, `ml_cv_benchmark.R`, `backtest_margin_hyperparams.R`, `ml_feature_experiments*.R`, `research_*.R`, `test_logging_fault_injection.R`) | **Not reached.** `tools/` is outside `run_full_pipeline.R`'s DAG; each already carries its own fixed seed where it matters. |

## 6. Known non-reproducibility that is NOT covered here

- **Live endpoints.** A stage that re-pulls from `wehoop`/`hoopR`/ESPN can legitimately return
  different data. `cache/injury_data_cache.rds` in particular is re-scraped every run.
- **Fabricated-but-deterministic values.** Issues #129-#135 and #144-#152 track fields that are
  `runif()`-derived rather than measured. A fabricated field that is now *stable* satisfies this
  document and still fails those tickets. Reproducibility and provenance are separate axes.
