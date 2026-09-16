# Task Assignments: Phase 4 (Security & Data-Integrity Remediation)
Date: 2026-09-16

## Overview
Phase 4 remediates all 21 findings in `docs/SECURITY_TECHNICAL_REVIEW.md` (3 Critical / 4 High /
8 Medium / 6 Low). Unlike Phases 1-3, this phase runs multiple subagents **concurrently**. Because
several findings share hub files (`app.R`, `market_odds_engine.R`, `run_full_pipeline.R`,
`roster_bottom_up_engine.R`), agents are grouped by **disjoint file ownership** — no two agents in
the same wave ever write the same file — rather than by finding severity. This is the only way to
parallelize safely in a repo with no version control to merge conflicting edits.

**Orchestration principle:** one severity list (the review) → regrouped into a file-ownership DAG →
executed in waves. A wave's agents run in parallel; waves run in series. Within a wave, an agent may
touch only the files listed in its own brief (`agents/agent_*.md`) — this is enforced by instruction
in the subagent prompt and checked mechanically post-hoc via `git diff --stat` (see Phase 0).

## Phase 0 — Safety Infrastructure (orchestrator, not a subagent)
This repo currently has no version control, which makes "did agent X touch only its assigned
files" and "can we roll back a bad wave" unanswerable. Before Wave 1:
1. `git init` + one commit of the current tree (baseline before any Phase 4 edit).
2. One commit **per wave** after its integration checkpoint passes (see below), never per-agent —
   agents in a wave finish and get verified together.
3. This is additive/reversible and does not touch any existing file; flagged here for visibility,
   not because it's risky.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P4-0 | 0 | orchestrator | (repo-wide) `git init` + baseline commit | — | PENDING |
| P4-C | 1 | `agent_foundation` | `config.R`, `logging_utils.R`, new `rapm_join_utils.R` | C-1 (constant), H-1 (redaction helper), H-2 (shared join helper), M-6 (canonical `%||%`), M-7 (log connection lifecycle), L-2 (config.R comment) | COMPLETED |
| P4-I | 1 | orchestrator | new `docs/REMEDIATION_INTERFACE_CONTRACTS.md` | interface contracts consumed by Wave 2 | PENDING |
| P4-A | 2 | `agent_engine` | `market_odds_engine.R`, `tools/optimize_hca.R`, `tools/backtest_margin_hyperparams.R`, `tools/build_calibration_cache.R` | C-1 (engine), H-1 (call site), H-4, L-1, M-5 (engine side), M-6 (remove local) | PENDING |
| P4-B | 2 | `agent_dashboard` | `app.R` | C-1 (app.R), C-3 (Tab 8 filter/label), H-3, M-3, M-6 (remove local), M-8 (display), L-6 (read canonical) | PENDING |
| P4-D | 2 | `agent_pipeline` | `run_full_pipeline.R`, `sync_rosters.R`, `injury_scraper.R`, `roster_bottom_up_engine.R`, `playoff_simulator.R` | C-2, M-1, M-2, M-7 (pipeline side), C-1 (roster/playoff refs), H-2 (roster_bottom_up_engine.R), M-8 (write numeric) | PENDING |
| P4-E | 2 | `agent_props` | `player_props_engine.R`, `prediction_accuracy_logger.R`, `daily_ingest.R`, `tools/generate_diagnostic_data.R` | H-2 (player_props_engine.R), M-4, M-5 (logger side), C-3 (schema/migration), L-4, L-6 (canonical write) | PENDING |
| P4-F | 2 | `agent_cleanup` | `tools/ml_cv_benchmark.R`, `tools/ml_feature_experiments.R`, repo root scratch files, `.gitignore` | L-2 (tools/ comment), L-3, L-5 | PENDING |
| P4-CK1 | 2.5 | orchestrator | (verification only, no edits) | integration checkpoint for Wave 2 | PENDING |
| P4-G | 3 | orchestrator (confirm with user first) | `cache/latest_value_bets.rds`, `cache/odds_history.rds`, `cache/prediction_accuracy_log.rds` (non-DIAG rows) | C-1 fix-direction's data-invalidation step | PENDING |
| P4-V | 4 | orchestrator | new `docs/SECURITY_REMEDIATION_VERIFICATION.md` | re-run all 21 reproductions, sign off | PENDING |

## Wave dependency graph
```
Wave 0 (git init)
   |
Wave 1: agent_foundation  +  orchestrator writes interface-contracts doc   [serial before Wave 2]
   |
Wave 2 (parallel): agent_engine | agent_dashboard | agent_pipeline | agent_props | agent_cleanup
   |
Wave 2.5: orchestrator integration checkpoint (full pipeline run + dashboard probe)
   |
Wave 3: cache invalidation/regen (needs explicit user go-ahead — see Constraints)
   |
Wave 4: orchestrator verification doc, sign-off
```
Wave 2 agents are safe to run concurrently because their file-ownership columns above are
pairwise disjoint — verified by inspection against the full file list in
`docs/SECURITY_TECHNICAL_REVIEW.md`'s findings.

## Interface contracts (must be fixed *before* Wave 2 starts, since agent_dashboard, agent_pipeline,
and agent_props each independently produce/consume these without seeing each other's code)
- **`is_synthetic`** (logical) — new column on `prediction_accuracy_log.rds` schema
  (`schema_version` bump). `agent_props` (writer, via `tools/generate_diagnostic_data.R` and
  `log_todays_predictions()`) and `agent_dashboard` (reader, in the Tab 8 reactive) both build
  against this exact name/type.
- **`market_data_source`** (character: `"LIVE_ODDS_API"` / `"SYNTHETIC_FALLBACK"`) — new column on
  the same log, mirroring the existing `injury_data_source` pattern. Written by `agent_engine`
  (`fetch_market_odds()`) and `agent_props` (`log_todays_predictions()`); not read by anyone in
  Wave 2 (consumed later by a reporting task, out of scope here).
- **`join_rapm_to_roster(rost, rapm)`** — function signature for the shared helper in
  `rapm_join_utils.R`, built by `agent_foundation`. Returns a data frame keyed by
  `(team_abbreviation, player identity)` with at least `total_rapm`. `agent_pipeline` and
  `agent_props` both call this in place of their local naive joins — same signature, no
  coordination needed once Wave 1 lands.
- **`WNBA_HCA`** (numeric, `config.R`) — `2.40`. Read by `agent_engine`, `agent_dashboard`, and
  `agent_pipeline`. No script restates the literal `2.40`/`11.6` after Wave 2.
- **`Win_Pct`** — stored as numeric proportion (`0.793`, not `"79.3%"`) by `agent_pipeline`
  (the writer in `roster_bottom_up_engine.R`); formatted at display time only by `agent_dashboard`
  (`scales::percent()`). `agent_pipeline` must land its Wave-2 change and `agent_dashboard` must
  not assume the old string format — both stated explicitly in each brief so this doesn't need
  runtime coordination.

## Constraints (apply to every agent in every wave)
- Touch **only** the files listed in your row of the Task Tracker, plus you may create new test
  scripts under `tools/test_phase4_*.R`. If a fix seems to require touching a file outside your
  ownership list, stop and report it rather than editing it — flag it back to the orchestrator as a
  cross-wave dependency that was missed.
- Every fix must cite the finding ID (`C-1`, `H-2`, etc.) in the code comment or commit-adjacent
  note, not just fix the symptom silently.
- Do not touch cached `.rds` artifacts in Wave 2 — regeneration is explicitly deferred to Wave 3
  pending user confirmation (see P4-G).
- Follow `CLAUDE.md`'s R-execution rule: no inline multi-line `Rscript -e`; write to a temp `.R`
  file and run `Rscript.exe path\to\temp.R`.
- Verify empirically (run the script, inspect the cache, reproduce the fixed behavior) — do not
  mark a task COMPLETED on a read-only code review of your own diff.

## Handoff Notes
(Appended by each agent as it completes its wave.)

---

### P4-C — `agent_foundation` (Wave 1) — COMPLETED 2026-09-16

**Files changed:** `config.R`, `logging_utils.R`, new `rapm_join_utils.R`, new
`tools/test_phase4_foundation.R`. Nothing else. (`logs/logs.duckdb` and `logs/wnba_pipeline.log`
also show as modified in `git status` — that is the logger writing real rows during the test run,
not a source edit.)

**What landed**

- **C-1 (constant).** `config.R` now defines `WNBA_HCA <- 2.40` in its own section directly after
  `WNBA_MARGIN_SIGMA`, with provenance: NBA-inherited per T2, **not** independently re-derived for
  the WNBA, deliberately not re-derived in this wave. Value only — no call site was rewired (that
  is `agent_engine`/`agent_dashboard`/`agent_pipeline`'s Wave 2 work).
- **M-6 (canonical `%||%`).** Kept in `logging_utils.R` in the hardened `is.na(a)[1]` form,
  now with a comment marking it as the single definition and explaining why the subscript is
  load-bearing. Local copies in `app.R:50` and `market_odds_engine.R:60` were **left in place**
  for `agent_dashboard` / `agent_engine` to delete in Wave 2, as briefed.
- **H-2 (shared join).** New `rapm_join_utils.R` exporting
  `join_rapm_to_roster(rost, rapm, matched_only = TRUE)` plus
  `normalize_rapm_last_name(x, from_full_name = TRUE)`.
- **H-1 (redaction).** New `.log_redact()` applied to (a) every `...` value in
  `.log_format_extra()`, (b) the `msg` itself, and (c) the DuckDB `extra_json` builder — so the
  console, `logs/wnba_pipeline.log` and the `logs` table are all covered. Scrubs
  `apiKey`/`api_key`/`api-key`/`token`/`access_token`/`auth`/`webhook`/`secret`/`password`/
  `passwd`/`signature`/`key` as query or form params, the same names in JSON `"k": "v"` form,
  Discord webhook paths (`.../api/webhooks/<id>/<token>`), and `Bearer`/`Basic` auth headers.
- **M-7 (logging half only).** `.log_write()` no longer opens a connection per line. A
  process-lifetime connection is held in a `.log_state` env, created lazily, revalidated with
  `dbIsValid()`, re-established transparently if invalidated, and closed via
  `reg.finalizer(..., onexit = TRUE)`. The `future.seed` half remains `agent_pipeline`'s.
- **L-2 (config.R half only).** The window-sweep citation now points at
  `data/window_sweep_3_25_results.csv` and names it authoritative; verified empirically that
  `cache/window_sweep_3_25_results.rds` holds identical numbers for all 23 window sizes (differing
  only in column naming, `ROC-AUC` vs `ROC.AUC`) and labelled it a redundant copy. The
  `OFFSEASON_METHOD` block got an explicit **STALENESS FLAG**: the `"reset"` benchmark was run at
  `window_size = 13` and has *not* been rechecked at the current `ROLLING_WINDOW_SIZE`; not
  re-derived here (out of Wave 1 scope), flagged per the brief's second option.

**FINDINGS FOR WAVE 2 — read these, they contradict existing documentation**

1. **`CLAUDE.md` and `market_odds_engine.R:100-103`'s "verified zero team+last-name collisions"
   claim is only half true.** It holds on the **roster** side (0 duplicate `(team_name, last_name)`
   groups across all 209 rostered players — re-verified, see CHECK 2b). It does **not** hold on the
   **RAPM** side: `rapm_ratings.rds` carries every player who logged possessions for a franchise, so
   it has **15** duplicate `(team, last_name)` groups (both Ogwumike sisters on LA, two "Jones" on
   CON, three "Williams" on PHX, etc.). The existing inline join therefore **fans out**: 121 matched
   roster players become **128 joined rows**. Harmless for `calculate_matchup_delta()` (which takes a
   per-team max) but it would have silently double-counted in the possession-weighted team
   aggregates in `player_props_engine.R::get_team_def_rapm()` and
   `roster_bottom_up_engine.R::compute_team_rapm_ratings()` — i.e. copying the "fixed"
   market_odds join verbatim into those two files would have introduced a *new* bug.
   `join_rapm_to_roster()` resolves it: one RAPM row per `(team, last_name)`, chosen by most total
   possessions (`n_off_poss + n_def_poss`), ties broken deterministically by `total_rapm` then
   `player_id`. This correctly picks Nneka over Chiney Ogwumike, Kelsey Mitchell, Jackie Young and
   Jonquel Jones. Affected rows carry `rapm_ambiguous = TRUE` (7 of 121) for auditing.
2. **No behaviour change for `agent_engine`.** CHECK 2d is a regression guard: per-team
   `max(total_rapm)` from the helper is **identical** to the legacy inline fan-out join across all
   15 teams (max abs diff = 0). Dropping the helper into `calculate_matchup_delta()` will not move
   the star-power delta or any downstream number.
3. **Contract detail for `agent_pipeline` / `agent_props`.** `join_rapm_to_roster()` defaults to
   `matched_only = TRUE` (inner-join semantics). Both of your call sites aggregate with
   `na.rm = TRUE` over possession weights, so inner vs. left join give arithmetically identical
   results — just call it with the two documented args. Pass `matched_only = FALSE` if you want all
   209 roster rows back with `total_rapm` NA-filled plus a `rapm_matched` logical. Returned key is
   `(team_abbreviation, player_id)` where `player_id` is always the **roster/ESPN** ID; the RAPM-side
   ID is preserved separately as `rapm_player_id`. Fail-safe per repo convention: NULL/empty/missing
   -column input warns and returns a 0-row typed frame, never errors.
4. **M-7 trade-off `agent_pipeline` must know about.** DuckDB permits exactly one *writing process*
   per file. Holding the connection for the process lifetime removes connection churn in the parent
   but means a second process (a `future_lapply` worker, or the Shiny app running next to the
   pipeline) cannot open `logs.duckdb` at all while the parent lives. Verified empirically with two
   concurrent `Rscript` processes: the contender **does not crash** (exit 0, all text-log lines
   written) but its DuckDB rows would previously have been dropped silently. To stop the logger
   losing records, a failed DB write now spills to a per-PID TSV
   (`logs/logs_pending_<pid>.tsv`, path via `LOG_SPILL_FILE()`) and console `[LOG DB ERROR]` output
   is throttled to once per 60s. **Open item for `agent_pipeline`:** the complementary half — having
   workers buffer rows and return them to the parent, or merging the spill files back into the
   `logs` table at end of run — is yours; the spill files are the handoff artifact.
5. `tools/data_health_probe.R` reports `OVERALL HEALTH: FAILED` — this is **pre-existing and
   unrelated**: `cache/features_cache.rds` is missing. Flagging so nobody attributes it to Wave 1.

**Verification — real output of `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_foundation.R`**

```
=== Phase 4 Wave 1 foundation tests ===

[PASS] CHECK 1 (C-1) config.R defines WNBA_HCA == 2.40  -- WNBA_HCA = 2.4 (class numeric)

  roster rows: 209   rapm rows: 430
  raw player_id types -- roster: integer, rapm: character; raw ID overlap: 0

  matched players per team:
 team_abbreviation matched
               ATL       9
               CHI       8
               CON       9
               DAL       9
                GS       9
               IND       8
                LA       6
                LV       5
               MIN       6
                NY      10
               PHX      10
               POR       8
               SEA       8
               TOR       5
               WSH      11
[PASS] CHECK 2a (H-2) all 15 WNBA_TEAMS have >= 1 matched player  -- 15/15 teams matched, min 5 players/team; missing: none

  duplicate (team,last_name) groups -- roster side: 0 | rapm side: 15
  helper output: 121 rows for 121 distinct roster players (7 ambiguous, deduped)
[PASS] CHECK 2b (H-2) 0 duplicate (team,last_name) on roster side; helper emits 1 row/player  -- roster_dups=0, output_dup_groups=0 (rapm side has 15 collision groups, resolved by helper)
[PASS] CHECK 2c (H-2) output carries a numeric total_rapm with no NAs  -- range -5.03 .. 5.94
[PASS] CHECK 2d (H-2) per-team top total_rapm identical to legacy market_odds_engine join  -- max abs diff = 0 across 15 teams
[PASS] CHECK 2e (H-2) fail-safe on NULL input (warn + 0 rows, no error)  -- returned 0-row frame

  .log_format_extra() rendered ->  | call: fetch_market_odds() | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=***REDACTED***&regions=us,us2,eu&markets=h2h&oddsFormat=american | condition_message: GET failed for https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=***REDACTED***&regions=us,us2,eu&markets=h2h&oddsFormat=american
[PASS] CHECK 3a (H-1) apiKey scrubbed from .log_format_extra() output  -- secret present = FALSE
  .log_redact(discord webhook) -> https://discord.com/api/webhooks/***REDACTED***
[PASS] CHECK 3b (H-1) Discord webhook path scrubbed
  -- log_error() end-to-end (line below is the real logger output) --
[2026-09-16 08:46:14] [ERROR] [test_phase4_foundation.R] PHASE4 FOUNDATION TEST (H-1 redaction probe). | call: fetch_market_odds() | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=***REDACTED***&regions=us,us2,eu&markets=h2h&oddsFormat=american | webhook: https://discord.com/api/webhooks/***REDACTED***
[PASS] CHECK 3c (H-1) secret absent from text log AND logs.duckdb row  -- duckdb extra_json = call=fetch_market_odds(); url=https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=***REDACTED***&regions
[2026-09-16 08:46:14] [INFO] [test_phase4_foundation.R] PHASE4 M-7 connection reuse probe.
[PASS] CHECK 3d (M-7) .log_write() reuses one process-lifetime DuckDB connection  -- same connection object = TRUE; rows 115 -> 116 across one log_error()
[2026-09-16 08:46:14] [ERROR] [test_phase4_foundation.R] PHASE4 M-7 spill probe. | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=***REDACTED***&regions=us,us2,eu&markets=h2h&oddsFormat=american
[LOG DB ERROR] simulated: DB locked by another process
  spill file -> c:/Users/kailo/kayceeslices/WNBA Analytics/logs/logs_pending_30072.tsv
  spill line -> 2026-09-16 08:46:14	ERROR	test_phase4_foundation.R	PHASE4 M-7 spill probe.	url=https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?
[PASS] CHECK 3e (M-7) DB write failure spills the record to disk instead of dropping it  -- spilled=1 line(s), secret leaked=FALSE

  NULL %||% 'fallback' -> fallback ; NA %||% 7 -> 7 ; c(NA,NA,NA) %||% 0 -> 0
[PASS] CHECK 4 (M-6) canonical %||% handles scalar and full-NA vector without erroring

  config.R cites: data/window_sweep_3_25_results.csv, cache/window_sweep_3_25_results.rds (all exist = TRUE)
[PASS] CHECK 5 (L-2) window-sweep citations resolve to real files + offseason staleness flagged  -- citations_exist=TRUE, offseason_staleness_flag=TRUE

=== ALL CHECKS PASSED: 0 check(s) failed ===
EXIT=0
```

**Concurrency probe (M-7 trade-off, two simultaneous `Rscript` processes):**

```
[LOG DB ERROR] init failed: {"exception_type":"IO","exception_message":"Cannot open file \"...\\logs\\logs.duckdb\": The process cannot access the file because it is being used by another process.
File is already open in C:\PROGRA~1\R\R-45~1.2\bin\x64\Rscript.exe (PID 28680)"}
[2026-09-16 08:44:53] [INFO] [_tmp_lock_contender.R] CONTENDER line 1
...
[2026-09-16 08:44:58] [INFO] [_tmp_lock_contender.R] CONTENDER line 5
CONTENDER SURVIVED (no crash)
CONTENDER_EXIT=0
```

**`git diff --stat` at handoff** (`logs/*` = runtime side effect of the test run, not source edits;
`rapm_join_utils.R` + `tools/test_phase4_foundation.R` are untracked/new):

```
 config.R               |  33 ++++++++++-
 logging_utils.R        | 156 ++++++++++++++++++++++++++++++++++++++++++++-----
 logs/logs.duckdb       | Bin 1060864 -> 1060864 bytes
 logs/wnba_pipeline.log |  14 +++++
 4 files changed, 187 insertions(+), 16 deletions(-)
```

Left uncommitted for orchestrator review. Wave 2 is unblocked.
