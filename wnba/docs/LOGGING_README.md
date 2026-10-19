# WNBA Pipeline — Structured Logging (Task P5)

`wnba_logging_agent`, `task_assignments_phase2.md` Task P5. Replaces ad-hoc `print()`/`cat()`
console-only output at key call sites with structured, leveled, persistent logging, verified via
deliberate fault injection (not just happy-path runs).

## Files

- `logging_utils.R` — the logging utility itself (new).
- `test_logging_fault_injection.R` — fault-injection test suite (new, actually executed — see
  "Real test results" below).
- This file.

## Log format

One line per event, written to BOTH the console (`cat()`) and the persistent log file:

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [script.R] message text | key1: value1 | key2: value2 ...
```

Real example (captured during the fault-injection run below):

```
[2026-09-12 07:42:07] [ERROR] [test_logging_fault_injection.R] Deliberate fault-injection: broken-host fetch failed. | call: fetch_broken() | url: http://this-host-does-not-exist.wnba-fault-injection-test.invalid/odds | condition_class: httr2_failure/httr2_error/rlang_error/error/condition | condition_message: Failed to perform HTTP request. Caused by error in `curl::curl_fetch_memory()`: ! Could not resolve hostname [this-host-does-not-exist.wnba-fault-injection-test.invalid]: Could not resolve host: this-host-does-not-exist.wnba-fault-injection-test.invalid
```

### Levels

- **INFO** (`log_info()`) — successful operations (a live feed returning N real rows, a cache
  write, a pipeline stage completing).
- **WARN** (`log_warn()`) — degraded-but-handled conditions: a labeled `SYNTHETIC_FALLBACK` path
  firing, a partial/implausible live response being treated cautiously, a stage script not found.
- **ERROR** (`log_error()`) — failed operations. If called with `condition = <caught condition
  object>`, automatically logs the REAL condition class (`condition_class`), the real message
  (`condition_message`), and the offending call (`call`, from `conditionCall()`) — never a
  generic "an error occurred" placeholder. Extra `...` context (e.g. `stack_trace =`,
  `http_status =`) is appended the same way as `log_info`/`log_warn`.

No DEBUG/TRACE level exists — only the three requested by the brief.

### API

```r
source("logging_utils.R")
.LOG_SCRIPT <- "my_script.R"   # optional; tags every log_*() call from this script

log_info("Fetched live data.", rows = 42, call = "my_fetch_fn()")
log_warn("Falling back to SYNTHETIC_FALLBACK.", data_source = "SYNTHETIC_FALLBACK")
log_error("Fetch failed.", condition = e, call = "my_fetch_fn()", url = url)
```

`script =` can be passed explicitly to any `log_*()` call to override `.LOG_SCRIPT` (used e.g. by
`run_full_pipeline.R`'s `run_stage()`, which always tags its own lines `run_full_pipeline.R`
regardless of which stage script is executing inside it).

## Log file location & rotation policy

- **Location:** `logs/wnba_pipeline.log` (relative to `PROJECT_DIR`; the `logs/` directory is
  created automatically on first use).
- **Policy: append, with size-based rotation.** Every run APPENDS to the same file (so a single
  run's — or a chain of related failures' — log lines stay in one place, in order, rather than
  being split across per-run files). When the file exceeds 5 MB (`LOG_MAX_BYTES` in
  `logging_utils.R`), the NEXT write rotates it: the existing file is renamed to
  `logs/wnba_pipeline_<YYYYMMDD_HHMMSS>.log` and a fresh empty `wnba_pipeline.log` is started.
  This requires no extra package (no `logger`/`futile.logger` dependency — `logger` was checked
  and confirmed NOT installed in this environment via
  `"logger" %in% rownames(installed.packages())` → `FALSE`) and is sufficient for a
  single-machine, cron-style pipeline.

## Scripts wired with real logging instrumentation

Per agent11.md's brief ("run_full_pipeline.R's run_stage()" plus "at minimum" the listed
live-feed call sites), the following files now call `log_info()`/`log_warn()`/`log_error()` at
their real network/cache-dependent branch points (full list, not abbreviated):

1. **`run_full_pipeline.R`** — `run_stage()` itself: logs `INFO` on stage completion, `WARN` if a
   stage script file is missing, and `ERROR` (with real condition class/message + a full call
   stack captured via `withCallingHandlers()`, see "Stack trace capture" below) on stage failure
   — WITHOUT removing the existing fail-safe "continue to next stage" behavior. Also logs pipeline
   start/finish.
2. **`market_odds_engine.R`** — `fetch_market_odds()`: `INFO` on a successful Odds API pull (row
   count) and on successful bookmaker-odds parsing; `ERROR` with the real HTTP/connection
   condition on API failure; `WARN` when `ODDS_API_KEY` is unset or the API returns no usable
   odds, both times before falling to the `SYNTHETIC_FALLBACK` fixture slate (which is itself also
   logged as a `WARN`, clearly labeled). `evaluate_betting_slate()` also logs `INFO` on cache save.
3. **`sync_rosters.R`** — `sync_active_rosters()`: `INFO` on the team-registry fetch and the final
   roster count; `ERROR` (with real condition) if the ESPN team endpoint is unreachable; `ERROR`
   per-team if a specific team's roster fetch fails, `WARN` if a team's roster response has no
   athletes.
4. **`injury_scraper.R`** — `fetch_live_wnba_injuries()`: `INFO` on connecting to the live portal
   and on a successful live parse (row count); `ERROR` (real condition) if the portal is
   unreachable; `WARN` when the live feed returns 0 rows (offseason) or an implausibly small
   partial snapshot (`< MIN_PLAUSIBLE_INJURY_ROWS`), both before falling back to the labeled
   `SYNTHETIC_FALLBACK` sample; `INFO` on the final cache save.
5. **`daily_ingest.R`** — `daily_box_ingest()`: `ERROR` (real condition, then re-thrown, unchanged
   fail-safe behavior at the `run_stage()` level) if the initial historical bootstrap pull fails;
   `INFO` on the initial bootstrap and on fetching/caching current-season updates; `ERROR` (real
   condition) if the current-season `wehoop::load_wnba_team_box()` call fails; `WARN` if it
   returns zero new records.
6. **`player_metrics.R`** — `get_player_box_scores_chunked()`: `ERROR` (real condition) per failed
   retry attempt of `wehoop::load_wnba_player_box()`, `ERROR` if all retries for a season are
   exhausted (before the pre-existing `stop()`), `INFO` per season ingested and on final cache
   save.
7. **`rapm_engine.R`** (P2's new file — its possession/shots pulls and its documented fallback
   branch, per P2's Handoff Notes explicitly flagging this as "a real code path worth testing")
   — `load_or_build_wnba_pbp_cache()`: `INFO` on the pull starting, per-season pull success;
   `ERROR` (real condition) per-season possession/shots pull failure; `ERROR` if no season's data
   could be pulled at all; `INFO` on the final cache write.
   `estimate_rapm_box_plusminus_fallback()`: `ERROR` if the fallback's own required cache is also
   missing; `WARN` when this fallback path fires (real box-score data, but not the primary
   possession-level path).
   `estimate_rapm_ratings()`: `ERROR` if the pbp-cache loader itself errors; `WARN` when falling
   through to the box-score fallback; `INFO` on the final real possession-level RAPM save (row
   count, low-sample-flag count).
8. **`risk_management_engine.R`** (added beyond the brief's explicit minimum list, per P2/P3's
   Handoff Notes explicitly requesting this real-ledger-read branch be logged) —
   `load_real_ledger()`: `ERROR` (real condition) if the real ledger file is missing/corrupted;
   `INFO` on a successful real-ledger read (resolved-bet count vs. total rows). `compute_risk_state()`:
   `WARN` if the real ledger read itself fails (falling back to the synthetic seed), `WARN` if the
   real ledger exists but has zero RESOLVED bets, `WARN` if `cache/betting_ledger.rds` doesn't
   exist yet, `WARN` when the `SYNTHETIC_FALLBACK` 120-bet seed ledger is actually used, and
   `INFO` on the final computed risk state (status/Kelly/drawdown/bets audited).

### Stack-trace capture technique (`run_stage()`)

`tryCatch()` is an **exiting** handler: by the time its `error =` function runs, R has already
unwound the call stack back to the `tryCatch()` call, so `sys.calls()` inside it only shows this
function's own frame — not the deeper chain that actually failed. `run_stage()` works around this
with a nested `withCallingHandlers()` (a **non-exiting** handler, which runs at the point the
error is signaled, before any unwinding): it records `sys.calls()` into a local variable, then
lets the condition propagate normally up to the outer `tryCatch()`, which does the actual logging
(with the real captured stack) and the fail-safe continue. See `run_full_pipeline.R`'s `run_stage()`
comment block for the full explanation.

## Fault-injection test suite — real results

Run with:

```
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" "test_logging_fault_injection.R"
```

This actually executes 4 deliberate failure scenarios and re-reads `logs/wnba_pipeline.log` from
disk after each one to assert the real log line is present (not "should be" — the test fails if
the expected line, condition class, or return value isn't actually found). **Real result from the
last run of this exact file (2026-09-12): all 4 scenarios PASSED (exit code 0).** See
`task_assignments_phase2.md`'s P5 Handoff Notes for the full real log-line evidence for each
scenario, or re-run the command above to reproduce.

Scenarios:
1. **Broken URL / unreachable host** — a real `httr2` request to a deliberately non-resolving
   hostname, wrapped in the same `tryCatch()` + `log_error(condition = e)` idiom used in
   `market_odds_engine.R`/`sync_rosters.R`/`injury_scraper.R`. Confirms the REAL DNS/connection
   error message and class (`httr2_failure/httr2_error/...`) are captured, not a generic string.
2. **Corrupted cache file (2a)** — writes genuine garbage bytes to a throwaway temp `.rds` path
   and calls `risk_management_engine.R`'s real `load_real_ledger()` (extracted from the actual
   file by parsing, not retyped) against it. Confirms `readRDS()`'s real "unknown input format"
   error is captured via `log_error()`. **Missing cache file (2b)** — runs the real
   `compute_risk_state()` from a temp working directory with no `betting_ledger.rds` at all;
   confirms the missing-ledger branch is both exercised (returns the synthetic 120-bet report)
   AND logged via `log_warn()`, not silently absorbed. Neither sub-scenario touches the real
   production `cache/betting_ledger.rds`/`cache/risk_state.rds` (verified: their file
   modification times are unchanged by the test run).
3. **`run_stage()` dummy stage failure + continuation** — extracts the real `run_stage()`
   definition from `run_full_pipeline.R` (by parsing, not retyping) and calls it on a temp dummy
   script that deliberately `stop()`s. Confirms `run_stage()` returns `FALSE`, logs an `ERROR`
   line with the real error message, stage path, and a non-empty `stack_trace`, and — critically —
   that a SUBSEQUENT `run_stage()` call on a different (succeeding) dummy script still runs and
   returns `TRUE` afterward, re-verifying the fail-safe "continue to next stage" design still
   holds after adding logging.

## Known limitation (documented, not hidden)

`risk_management_engine.R` does not itself `library(tibble)` — it relies on `tibble()` being
already attached transitively by earlier `library(tidyverse)` calls in the same R session when run
as part of the full `run_full_pipeline.R` DAG. This is pre-existing behavior (not introduced by
this task); the fault-injection test's scenario 2 explicitly loads `tibble`/`dplyr`/`tidyr` itself
before calling the extracted function bodies, since it does not source the whole file, to isolate
the fault under test from this unrelated ordering dependency. Flagged here for whoever next
revisits `risk_management_engine.R` standalone execution.
