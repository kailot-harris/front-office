# Memory Optimization Plan — NFL Analytics Pipeline

**Written**: 2026-09-17, after two `run_full_pipeline.R` runs were killed by the OS for low
system memory (both died inside `daily_ingest.R`'s `.ingest_one()`, in the
`bind_rows(existing, new_rows)` step for `CACHE_PBP`). Root cause, confirmed empirically:
`nflreadr::load_pbp()` returns 372 raw columns per play; the full `CACHE_PBP` object was **3.4GB
in memory** for 1.14M rows, while `epa_metrics_engine.R` — its only real consumer — touches 9 of
those columns. Five mitigation options were scoped (see the conversation this doc was produced
from, or `docs/HANDOFF.md`'s cross-reference, for the original 5-option comparison with
benefit/risk/impact/difficulty ratings). **Options 1 and 2 are already implemented** (see
`run_full_pipeline.R::run_stage()`'s `gc()` call, and `daily_ingest.R`'s `.PBP_CACHE_COLUMNS`
whitelist). This document plans **Options 3, 4, and 5**, which are NOT yet implemented — read the
option's own section before starting any of them, and update this doc's status line at the top of
that section when work begins/completes, matching this repo's other planning-doc conventions.

Options 1-2 reduced `CACHE_PBP` from 3.4GB → ~167MB in memory (~95%) and eliminated the specific
crash observed. The options below are further hardening for scenarios options 1-2 don't fully
cover: continued season-over-season row growth (trimming columns is a one-time win; row count
still grows ~45K plays/season), and any future large object elsewhere in the pipeline (e.g.
Phase 2/3's historical walk-forward rebuilds in `team_ratings_engine.R`, which are already
multi-second, non-trivial-memory operations run fresh every pipeline invocation).

---

## Option 3: Avoid the `bind_rows(existing, new_rows)` triple-copy in `daily_ingest.R`

**Status**: planned, not started.

### Problem this solves
Even with Option 2's column trim, `.ingest_one()`'s incremental-update path still does:
```r
existing <- readRDS(cache_path)          # copy 1
new_rows <- loader_fn(seasons = CURRENT_SEASON)
combined <- bind_rows(existing, new_rows) |> distinct(...)   # copy 2, while copy 1 still referenced
```
`existing` and `combined` are both live in memory simultaneously during `bind_rows()`+`distinct()`
(R's copy-on-modify semantics mean `bind_rows()` allocates a new object rather than mutating
`existing` in place). With the Option 2 trim this is now cheap (~167MB × 2 ≈ 334MB peak) — but the
`existing` object grows every season (~45K new plays/season × ~20 columns), and if `.PBP_CACHE_COLUMNS`
is ever widened for a new feature (e.g. Phase 4's situational EPA splits), this peak grows again.
This option removes the *structural* doubling, not just shrinks its current magnitude.

### Approach
Since only `CURRENT_SEASON`'s rows can possibly change on an incremental run (prior seasons are
final, completed history — `nflreadr` does not retroactively revise old play-by-play), there is no
need to re-combine-and-dedupe the ENTIRE historical cache every run. Concretely:
1. Split `existing` into `existing_prior_seasons <- existing |> filter(season != CURRENT_SEASON)`
   and `existing_current_season <- existing |> filter(season == CURRENT_SEASON)` immediately after
   load.
2. Dedupe/merge only `existing_current_season` against the freshly-fetched `new_rows` (a much
   smaller frame — thousands of rows, not 1.1M+) via the existing `bind_rows()` +
   `distinct(across(all_of(dedupe_keys)))` logic.
3. Re-combine: `combined <- bind_rows(existing_prior_seasons, updated_current_season)`. This still
   allocates one more full-size copy at the very end (unavoidable if the on-disk format stays a
   single flat `.rds` — see Option 4 for the version that removes even this), but the expensive
   `distinct()` computation (which likely dominates CPU/memory over just holding the data) no
   longer scans the full historical row count every run.
4. Alternative/complementary micro-optimization: use `data.table::rbindlist()` +
   `unique()`/`duplicated()` instead of `dplyr::bind_rows()`/`distinct()` for the merge step —
   `data.table` is documented to have a meaningfully smaller memory footprint for these exact
   operations than dplyr's tibble-based equivalents, at the cost of a new dependency (need to
   confirm `data.table` is installed; it is NOT currently a dependency anywhere else in this
   repo, per a repo-wide grep — flag as a new-package risk, same class as `docs/HANDOFF.md`'s
   Phase 2/4 `glmnet`/`xgboost` flags, though `data.table` is a very common, stable package with
   low install risk).

### Files touched
- `daily_ingest.R` (`.ingest_one()`'s incremental-update branch only — the bootstrap branch
  already only runs once and isn't the observed crash site).

### Risks
- Moderate. This changes the actual merge/dedupe LOGIC, not just a `select()` projection like
  Option 2 — a bug here could silently drop or duplicate historical rows in a way that's easy to
  miss (e.g. `epa_metrics_engine.R`'s rolling-window calculations would look "reasonable" even
  with a small silent data gap). Needs a row-count and dedupe-key-uniqueness assertion added
  around the new logic, and a before/after `nrow()`/`sum(duplicated(...))` comparison against the
  current (already-correct) implementation as a regression check before trusting it.
- The `data.table` sub-option specifically also risks style inconsistency (this repo is
  deliberately dplyr-idiomatic throughout) — prefer the season-split approach alone first, and
  only reach for `data.table` if profiling shows the `distinct()` step is still the dominant cost
  after the split.

### Verification plan
1. Before changing anything, capture `nrow(readRDS(CACHE_PBP))` and a hash/fingerprint (e.g.
   `sum(as.numeric(as.factor(paste(game_id, play_id))))` or similar) of the current cache as a
   known-good baseline.
2. Implement the season-split merge.
3. Run `run_daily_ingest()` with `force_refresh = FALSE` (normal incremental path) against the
   current real cache; confirm `nrow()` and the fingerprint are unchanged (no new real NFL games
   should be expected between test runs on the same day, so a genuinely correct implementation
   should reproduce byte-identical row counts unless real new plays actually arrived).
4. Run `run_daily_ingest(force_refresh = TRUE)` once (full historical re-bootstrap) and diff its
   output against the incrementally-merged version — they must match exactly.
5. Re-run `epa_metrics_engine.R` and spot-check a few known teams' rolling EPA figures are
   unchanged from before this change.

---

## Option 4: Migrate `CACHE_PBP` to a disk-backed duckdb/parquet table

**Status**: planned, not started.

### Problem this solves
Options 2-3 both still fundamentally load the FULL `CACHE_PBP` history into R's in-process memory
as one `data.frame`/tibble on every stage that touches it (`daily_ingest.R`, `epa_metrics_engine.R`).
That's bounded-but-growing (season-over-season row growth) and doesn't allow any consumer to query
"just the columns/rows I need" without first paying the cost of materializing everything. This
option removes that ceiling entirely by making `CACHE_PBP` a disk-backed table queried lazily.

### Approach
`nflreadr` already uses `duckdb` internally (confirmed live — every `nflreadr::load_*()` call in
this repo prints duckdb's extension-storage message), and this repo's `.duckdb` local extension
cache already exists (`~/.duckdb`, referenced in every run's console output), so the dependency
is already present, not new.
1. Replace `CACHE_PBP`'s single `.rds` file with a duckdb database file (e.g.
   `cache/pbp_cache.duckdb`) containing one `pbp` table, written via `DBI`/`duckdb` (`dbWriteTable`)
   instead of `saveRDS()`.
2. `daily_ingest.R`'s incremental-update logic becomes a SQL `INSERT ... ON CONFLICT`/upsert (or a
   `DELETE` + `INSERT` for the current season's rows specifically, mirroring Option 3's
   season-split idea but at the SQL layer, where duckdb can do it without ever pulling the full
   table into R) rather than an R-side `bind_rows()`/`distinct()`.
3. `epa_metrics_engine.R` switches from `pbp <- readRDS(CACHE_PBP)` to a lazy `dplyr::tbl(con,
   "pbp")` connection, with its existing `filter()`/`group_by()`/`summarise()` pipeline (already
   written in dplyr verbs) translated to SQL by `dbplyr` automatically, and only the small final
   aggregated result (`team_game`, currently ~13K rows) ever gets pulled into R memory via
   `collect()`. This is the single highest-leverage change in this option — it means
   `epa_metrics_engine.R` NEVER holds more than the current season/window's worth of raw play
   data in R memory, regardless of how large the total historical `pbp` table grows.
4. Any other future consumer of raw PBP (e.g. Phase 4's situational-feature engineering) should be
   written against the same lazy `tbl()` pattern from the start, not `readRDS()`.

### Files touched
- `daily_ingest.R` (PBP ingestion path only — schedules stay as `.rds`, they're small and don't
  need this).
- `epa_metrics_engine.R` (read path — `readRDS(CACHE_PBP)` → `tbl(con, "pbp")`, its transform
  logic is largely reusable since it's already dplyr-verb-based, but every step needs to be
  verified to be dbplyr-translatable — e.g. this repo's custom `.roll_mean_trailing()` rolling-
  window helper is NOT SQL-translatable and would need to stay an R-side operation on the much
  smaller post-aggregation `team_game` table, which it already operates on — should be fine, but
  confirm before assuming).
- `config.R` (`CACHE_PBP`'s path/extension changes from `.rds` to `.duckdb`, and its meaning
  changes from "a file `readRDS()`-able into a tibble" to "a database file `dbConnect()`-able" —
  a real interface-contract change worth a clear comment update, not a silent rename).
- `.claude/skills/pipeline-freshness-audit` (its freshness check currently likely assumes
  `file.info(path)$mtime` works the same way for any file type — should still work for a
  `.duckdb` file, but verify; the skill's manifest may also reference `CACHE_PBP` by its old
  `.rds` extension somewhere and need updating).
- `.gitignore` (currently excludes `cache/pbp_cache.rds` by name specifically, for its size — a
  `cache/pbp_cache.duckdb` file needs the equivalent exclusion, likely similarly large or larger
  than the current 311MB `.rds` — though post-Option-2-trim it may now be small enough not to
  need excluding at all; re-evaluate at implementation time against GitHub's 100MB limit).

### Risks
- High-ish, but bounded: `dbplyr`'s SQL translation doesn't support 100% of dplyr syntax (window
  functions, some `case_when()` patterns, and any base-R function called inside a `mutate()` can
  silently fail to translate or translate to something subtly different) — every transform in
  `epa_metrics_engine.R` needs individual verification against its SQL-translated behavior, not
  just "the dplyr code still runs."
- This is the first genuine "not every cache is a plain `.rds`" exception in this repo's
  architecture — worth flagging explicitly in `CLAUDE.md`'s folder-layout/cache-conventions
  section if implemented, so a future agent doesn't assume `readRDS(CACHE_PBP)` still works.
- `duckdb`'s R package has its own versioning/ABI concerns (already visible in this repo's own
  console warnings — "package 'duckdb' was built under R version 4.5.3") — confirm read/write
  compatibility isn't fragile across the specific `duckdb`/R versions installed here before
  committing to this as the long-term cache format.

### Verification plan
1. Implement behind the existing `CACHE_PBP` constant name (just repoint it to the new path/
   format) so no other file needs to change its OWN constant references, only its read pattern.
2. Build both the old `.rds`-based and new `duckdb`-based `epa_metrics_engine.R` read paths
   side by side during development (e.g. a temporary `run_epa_metrics_duckdb()` variant), run
   both against the same underlying data, and `all.equal()`/diff their `CACHE_EPA_METRICS` outputs
   until they match exactly, THEN cut over and delete the old path.
3. Re-run `tools/backtest_shrinkage_optimizer.R` and `tools/model_backtest_harness.R` (which
   consume `CACHE_EPA_METRICS`, not `CACHE_PBP`, directly — but are the best available end-to-end
   regression check that nothing downstream silently changed) and confirm they reproduce the
   exact same Brier/Sharpe figures already on record in `cache/model_comparison_backtest.rds`.
4. Full `run_full_pipeline.R` run, monitoring peak memory (e.g. via Windows Task Manager or
   `ps`/`wmic` snapshots taken during the run, same technique used to diagnose the original
   crash) to confirm the expected reduction actually materializes, not just "it didn't crash."

---

## Option 5: Run memory-heavy pipeline stages as separate subprocesses

**Status**: planned, not started.

### Problem this solves
`run_full_pipeline.R` currently `source()`s every one of its 10 stages into ONE long-lived R
process (`run_stage()`'s `source(script_name, local = FALSE)`), by explicit design (stages share
`.GlobalEnv` so later stages can call earlier ones' functions/read their cache-writer side effects
directly — see that file's own header comment). This means any stage's peak memory usage is never
FULLY released back to the OS until the whole pipeline finishes, only reduced by garbage
collection (Option 1's `gc()` call helps, but `gc()` reclaims memory *within* the process's
already-reserved heap — it does not necessarily return pages to the OS the way a process exiting
does). A stage with an unusually large peak (today: `daily_ingest.R`'s PBP merge; potentially in
the future: `team_ratings_engine.R`'s per-run historical walk-forward rebuild for the ridge/Elo
ensemble, or a future Phase 4 GBM training step) can leave the process's overall memory high-water
mark elevated for every subsequent stage, compounding risk.

### Approach
Run each stage (or at minimum, the memory-heavy ones: `daily_ingest.R`, `epa_metrics_engine.R`,
`team_ratings_engine.R`) as its own `Rscript` subprocess rather than an in-process `source()`,
using base R's `system2()` or the `callr` package (`callr::r()` gives cleaner return-value/error
propagation than raw `system2()` + parsing stdout, but is a new dependency — check installed
status first, same as any other new-package option in this plan).
1. Each stage subprocess does its own `source("config.R"); source("<stage script>.R");
   run_stage_fn()` and exits — the OS reclaims 100% of its memory the moment the subprocess ends,
   with no dependency on R's own garbage collector timing.
2. `run_stage()` in `run_full_pipeline.R` needs reworking: instead of `source()` + direct function
   call + `tryCatch()`/`withCallingHandlers()` around it, it becomes something like
   `result <- callr::r(function() { source("config.R"); source(script_name); get(call_fn)() },
   error = "print")` — error propagation, the existing stack-trace capture (the
   `withCallingHandlers()`/`sys.calls()` mechanism), and the C-2 staleness check
   (`.check_stage_output()`, which is file-mtime-based and doesn't actually care which process
   wrote the file, so it likely needs NO change) all need to be re-verified to still work
   correctly across a process boundary rather than assumed to "just work."
3. Logging (`logging_utils.R`'s `log_info()`/`log_warn()`/`log_error()`) needs to still funnel
   into the same log destination from a child process — confirm its current implementation (file-
   or duckdb-backed, per its own module) is safe for concurrent/sequential multi-process writes,
   not just single-process.

### Files touched
- `run_full_pipeline.R` (`run_stage()`'s core execution model — the single biggest, most
  "hardened, ported-from-WNBA, don't rewrite it" piece of infrastructure in this repo per that
  file's own header comments; this is the option most likely to require the most careful,
  incremental rollout).
- Possibly `logging_utils.R` if its logging sink isn't already safe for multi-process writes.
- No changes needed to any individual stage script itself (`daily_ingest.R`,
  `epa_metrics_engine.R`, etc.) — they already expose a single `run_*()` callable with no
  auto-run guard, which is exactly the contract a subprocess-based `run_stage()` needs.

### Risks
- High. This is the most invasive option in this plan — it changes how errors surface (a
  subprocess crash needs to be distinguished from a subprocess returning `FALSE`, and the
  existing stack-trace capture technique specifically exploits same-process `sys.calls()`, which
  doesn't exist across a process boundary the same way) and could silently weaken this repo's
  existing fail-safe guarantees (each stage's failure is caught and logged, pipeline continues) if
  not reimplemented carefully.
- Slower wall-clock time per stage (subprocess startup/package-load overhead, paid 10 times
  instead of once) — likely still a net win for total memory safety, but a real, measurable
  regression on total pipeline runtime (currently ~150-190s end to end) that should be measured,
  not assumed acceptable.
- Should be attempted LAST, after Options 3-4 (or instead of them, if 3-4 alone prove sufficient)
  — it's the most work for what may be a redundant benefit if Option 4's duckdb migration already
  keeps every stage's memory bounded and small.

### Verification plan
1. Prototype on a SINGLE stage first (`daily_ingest.R`, the current worst offender) before
   converting all 10 — confirm subprocess-based execution reproduces identical `CACHE_PBP`/
   `CACHE_SCHEDULES` output to the current in-process version, and that a deliberately-injected
   error in the stage script still surfaces correctly (logged, pipeline continues to the next
   stage) rather than silently swallowed or crashing the whole orchestrator.
2. Measure wall-clock overhead of the subprocess approach vs. today's in-process approach for
   that one stage, to get a real per-stage cost estimate before committing to converting all 10.
3. Only after the single-stage prototype is fully verified (output-identical, error-handling-
   identical, memory-behavior-improved), convert the remaining stages one at a time, re-running
   the full pipeline after each conversion to catch any stage that assumed `.GlobalEnv` access to
   an earlier stage's in-process side effects (a real risk this repo's own header comments flag as
   the reason stages currently share one process — auditing for any such implicit cross-stage
   dependency is real work, not a formality).
