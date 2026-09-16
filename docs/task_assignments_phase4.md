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
| P4-A | 2 | `agent_engine` | `market_odds_engine.R`, `tools/optimize_hca.R`, `tools/backtest_margin_hyperparams.R`, `tools/build_calibration_cache.R` | C-1 (engine), H-1 (call site), H-4, L-1, M-5 (engine side), M-6 (remove local) | COMPLETED |
| P4-B | 2 | `agent_dashboard` | `app.R` | C-1 (app.R), C-3 (Tab 8 filter/label), H-3, M-3, M-6 (remove local), M-8 (display), L-6 (read canonical) | PENDING |
| P4-D | 2 | `agent_pipeline` | `run_full_pipeline.R`, `sync_rosters.R`, `injury_scraper.R`, `roster_bottom_up_engine.R`, `playoff_simulator.R` | C-2, M-1, M-2, M-7 (pipeline side), C-1 (roster/playoff refs), H-2 (roster_bottom_up_engine.R), M-8 (write numeric) | PENDING |
| P4-E | 2 | `agent_props` | `player_props_engine.R`, `prediction_accuracy_logger.R`, `daily_ingest.R`, `tools/generate_diagnostic_data.R` | H-2 (player_props_engine.R), M-4, M-5 (logger side), C-3 (schema/migration), L-4, L-6 (canonical write) | PENDING |
| P4-F | 2 | `agent_cleanup` | `tools/ml_cv_benchmark.R`, `tools/ml_feature_experiments.R`, repo root scratch files, `.gitignore` | L-2 (tools/ comment), L-3, L-5 | COMPLETED |
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

---

### P4-A — `agent_engine` (Wave 2) — COMPLETED 2026-09-16

**Files changed:** `market_odds_engine.R`, `tools/optimize_hca.R`,
`tools/backtest_margin_hyperparams.R`, `tools/build_calibration_cache.R`, new
`tools/test_phase4_engine.R`, plus this tracker file. Nothing else. (`logs/wnba_pipeline.log` and
`logs/logs.duckdb` also show modified — that is the logger writing real rows during the test run,
not a source edit. No `cache/*.rds` artifact was mutated; see the note under CHECK 6 below.)

**What landed**

- **C-1 (engine).** `market_odds_engine.R`'s `fair_margin <- ... + 11.6 + ...` and `hcas[i] <- 11.6`
  now both read `config.R::WNBA_HCA`. The misleading comment block (which documented `2.40` three
  lines above code that added `11.6`) was rewritten to say the value is read from
  `config.R::WNBA_HCA` and must not be restated here, and to record what the bug actually did. The
  file-header note #5 was updated the same way. `tools/build_calibration_cache.R`'s
  `HCA <- 2.40` and `tools/optimize_hca.R`'s `2.4` literals (line 59's base-margin subtraction, the
  `optim(par=)` start value, and the baseline-MAE/`cat()` restatements) all read `WNBA_HCA` now.
  `tools/backtest_margin_hyperparams.R`'s `HCA_CONST <- 11.6  # ...current live constant` — which
  had enshrined the defect as backtest ground truth — is now `HCA_CONST <- WNBA_HCA`. Verified by
  evaluating each file's top-level assignments against a real `source("config.R")`:
  `HCA_CONST = 2.4`, `HCA = 2.4`.
- **H-1 (call site).** The key is no longer interpolated into a URL string *at all*.
  `fetch_market_odds()` now builds a keyless `base_url` and attaches `apiKey` via
  `httr2::req_url_query()` on the request object immediately before `req_perform()`. Only
  `base_url` is ever logged (both the `log_info()` and the `log_error()` in the error handler).
  This is option (a) from the brief — Wave 1's logger-level `.log_redact()` remains as defense in
  depth, not as the only layer.
- **H-4.** `resolve_team_name()` restructured: abbreviation equality is checked first (so 2-char
  `"LV"`/`"NY"`/`"GS"` survive), then a `nchar(trimws(s)) >= 3` gate, then forward-only substring
  matching. The reverse-containment clause `grepl(s, fn, fixed = TRUE)` is **deleted** — that clause
  is what made `""` match all 15 franchises and return `"Atlanta Dream"`. No-match now returns
  `NA_character_` (not the raw input) and emits a `WARN` carrying the unresolved value.
- **L-1.** The nickname clause is now
  `full_names[vapply(nick, function(n) grepl(paste0("\\b", n, "\\b"), s), logical(1))]`.
  The old code handed a length-15 vector to `grepl()`'s `pattern`, so only `nick[1]` (`"dream"`) was
  ever tested and its scalar result was recycled across all 15 positions by `|`. CHECK 2e asserts
  the `argument 'pattern' has length > 1` R warning no longer fires.
- **M-5 (engine half).** `market_data_source` (character, `"LIVE_ODDS_API"` / `"SYNTHETIC_FALLBACK"`)
  is now a column on `fetch_market_odds()`'s return value on **both** branches, per the interface
  contract above.
- **M-6.** The local `%||%` at `market_odds_engine.R:60` is deleted; `source("logging_utils.R")` is
  at line 57 and the first `%||%` use is at line 337, so the canonical hardened definition is always
  the one in scope (CHECK 5b asserts this ordering mechanically, not by inspection).

**NOTE FOR `agent_props` (M-5 contract detail — read this)**

The brief described `market_data_source` as a field on `fetch_market_odds()`'s return value, but
`prediction_accuracy_logger.R::log_todays_predictions()` does not call that function — it reads
`cache/latest_value_bets.rds` (see `prediction_accuracy_logger.R:194`). The marker would therefore
never have reached you. I additionally **carried it through `evaluate_betting_slate()`'s
`output_table` select**, so it is a real column on `cache/latest_value_bets.rds`. It is excluded
from `display_table` so the printed `kable` is unchanged. Read it off the cache alongside
`Model_Win_Prob`; no call into this engine is needed.

**FLAG FOR P4-G (Wave 3 cache invalidation) — new, not in the review**

`tools/optimize_hca.R` recovers an HCA-free base margin as `predicted_margin - WNBA_HCA`. Every row
in `cache/prediction_accuracy_log.rds` written **before** this fix had `11.6` baked into
`predicted_margin`, so for those rows the subtraction leaves a ~9.2-point residual offset that will
bias the optimizer's answer **upward**. A `STALENESS WARNING` comment saying exactly this is now in
the file. **Consequence: do not run `tools/optimize_hca.R` to "derive the real WNBA HCA empirically"
(the review's C-1 fix direction) until P4-G has regenerated or excluded the pre-fix rows** — it
would produce a confidently wrong number from contaminated inputs. Sequencing matters here.

**Second finding: the C-1 blast radius is larger than the review's table shows.** The review's
reproduction table was assumed to be the synthetic fixture slate. It was not — **`ODDS_API_KEY` is
actually provisioned in this environment**, so the standalone run in CHECK 6 pulled 8 **live** games
from The Odds API (`market_data_source = LIVE_ODDS_API`). Two implications: (1) the invalid
`latest_value_bets.rds` / `odds_history.rds` rows P4-G must invalidate are real, live betting
recommendations, not demo data; (2) H-1 was **not** latent — the review's "does not fire today only
because `ODDS_API_KEY` is empty" premise is **false for this machine**, so a single transient
network error would already have written the live key to `logs/wnba_pipeline.log` and
`logs/logs.duckdb`. Both of those files are in the repo tree and predate Wave 1's redaction; the
orchestrator should consider whether P4-G also needs a log-scrub / key-rotation step.

**Also removed (owned file, same finding):** `tools/backtest_margin_hyperparams.R:54` carried an
identical unsafe scalar `%||%` copy that the review's M-6 did not list (it names only `app.R` and
`market_odds_engine.R`). Removed for the same reason; its one use (line 252, a scalar
`[1] %||% 0.0`) now resolves to the canonical `logging_utils.R` definition. CHECK 5c guards it.

**Verification — real output of `"C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_engine.R`**

(Library-load warnings and DuckDB's `~/.duckdb` storage notice elided; everything else verbatim.)

```
=== Phase 4 Wave 2 engine tests (P4-A / agent_engine) ===

  config.R::WNBA_HCA = 2.4 | WNBA_MARGIN_SIGMA = 14
  implied home-prob for two IDENTICAL teams at hca=2.40 (fixed) : 0.568
  implied home-prob for two IDENTICAL teams at hca=11.60 (bug)  : 0.796
[PASS] CHECK 1 (C-1) implied home-win prob for two identical teams in [0.53, 0.60]  -- p = 0.568 (was 0.796 under the 11.6 bug; real WNBA home rate ~55-58%)
[PASS] CHECK 1b (C-1) no hardcoded 11.6 / 2.40 HCA literal remains in engine code  -- 0 literal HCA assignments; both sites read WNBA_HCA

  resolve_team_name() fuzz (warnings below are the new H-4 WARN log lines):
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard). | call: resolve_team_name() | unresolved_value:
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard). | call: resolve_team_name() | unresolved_value: a
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard). | call: resolve_team_name() | unresolved_value: s
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard). | call: resolve_team_name() | unresolved_value:
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard). | call: resolve_team_name() | unresolved_value: xy
    input=""       -> NA_character_
    input="a"      -> NA_character_
    input="s"      -> NA_character_
    input="  "     -> NA_character_
    input="xy"     -> NA_character_
[PASS] CHECK 2a (H-4) degenerate inputs ('', 'a', 's', '  ', 'xy') all return NA_character_  -- 5/5 returned NA (review had ''->Atlanta Dream, 'a'->Atlanta Dream, 's'->Chicago Sky)
    input=Las Vegas Aces           -> Las Vegas Aces
    input=Seattle Storm            -> Seattle Storm
    input=Minnesota Lynx           -> Minnesota Lynx
    input=Connecticut Sun          -> Connecticut Sun
    input=Golden State Valkyries   -> Golden State Valkyries
    input=New York Liberty         -> New York Liberty
[PASS] CHECK 2b (H-4 regression guard) exact full franchise names still resolve to themselves  -- 6/6 exact matches preserved
    abbreviations: LV->Las Vegas Aces, SEA->Seattle Storm, NY->New York Liberty, GS->Golden State Valkyries, CON->Connecticut Sun
[PASS] CHECK 2c (H-4) 2-3 char WNBA_TEAMS abbreviations still resolve (length gate does not eat them)  -- abbreviation branch runs before the nchar(s) < 3 guard
    nicknames: Aces->Las Vegas Aces, Storm->Seattle Storm, Valkyries->Golden State Valkyries
[PASS] CHECK 2d (L-1) nickname clause is vectorized: every nickname tested, not just nick[1]  -- pre-fix, grepl() saw a length-15 pattern and only ever tested 'dream'
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input did not match any WNBA franchise; returning NA. | call: resolve_team_name() | unresolved_value: Unknown FC
[2026-09-16 08:53:06] [WARN] [test_phase4_engine.R] resolve_team_name(): input did not match any WNBA franchise; returning NA. | call: resolve_team_name() | unresolved_value: Toronto Raptors
[PASS] CHECK 2e (L-1) no "argument 'pattern' has length > 1" R warning is raised  -- 0 pattern-length warnings across 4 fuzz inputs
[PASS] CHECK 2f (H-4) unrecognized-but-long inputs return NA, not the raw input passed through  -- 'Unknown FC' -> NA, 'Toronto Raptors' -> NA
[PASS] CHECK 2g (H-4) caller at get_model_slate_probabilities() handles an NA team name without crashing  -- standings filter on NA -> 0 rows (routes to the devigged-consensus fallback); abbr_for(NA) -> NA

  -- H-1: invoking the real fetch_market_odds() with ODDS_API_KEY=SUPERSECRET123 --
  new c:/Users/kailo/kayceeslices/WNBA Analytics/logs/wnba_pipeline.log lines written by that call: 3
    [2026-09-16 08:53:06] [INFO] [test_phase4_engine.R] Querying live multi-region WNBA odds from The Odds API. | call: fetch_market_odds() | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/
    [2026-09-16 08:53:07] [ERROR] [test_phase4_engine.R] Odds API request failed. | call: fetch_market_odds() | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/ | condition_class: httr2_http_401/httr2_http/httr2_error/rlang_error/rlang_error/error/condition | condition_message: HTTP 401 Unauthorized.
    [2026-09-16 08:53:07] [WARN] [test_phase4_engine.R] Using SYNTHETIC_FALLBACK calibrated WNBA fixture slate (no live odds). | call: fetch_market_odds() | data_source: SYNTHETIC_FALLBACK
[PASS] CHECK 3a (H-1) secret absent from logs/wnba_pipeline.log lines written by the real call site  -- secret present in log = FALSE
[PASS] CHECK 3b (H-1) secret absent from console/stdout of the real call site  -- secret present on stdout = FALSE
[PASS] CHECK 3c (H-1) secret absent from the logs.duckdb `logs` table  -- rows in logs.duckdb containing the secret = 0
[PASS] CHECK 3d (H-1) engine source never interpolates api_key into a URL string at all  -- key is attached via httr2::req_url_query(); only the keyless base URL is logged

[PASS] CHECK 4a (M-5) fetch_market_odds() return value carries a market_data_source column  -- columns: game_id, game_date, tip_time_est, matchup, home_team, away_team, best_retail_book, home_ml, away_ml, consensus_home_ml, consensus_away_ml, market_data_source
[PASS] CHECK 4b (M-5) fallback slate is marked SYNTHETIC_FALLBACK  -- unique(market_data_source) = SYNTHETIC_FALLBACK over 6 rows
[PASS] CHECK 4c (M-5) live-parse branch is marked LIVE_ODDS_API  -- parse_multi_book_feed() result is tagged before return
[PASS] CHECK 4d (M-5) marker is carried into cache/latest_value_bets.rds's output_table  -- so prediction_accuracy_logger.R (agent_props) can read it off the cache

  local `%||%` definitions in market_odds_engine.R: 0 | uses: 3
  source("logging_utils.R") at line 57; first %||% use at line 337
[PASS] CHECK 5a (M-6) zero local `%||%` redefinitions remain in market_odds_engine.R  -- 0 definitions; canonical one comes from logging_utils.R
[PASS] CHECK 5b (M-6) logging_utils.R is sourced before the first `%||%` use  -- source line 57 < first use line 337
[PASS] CHECK 5c (M-6) zero local `%||%` redefinitions in tools/backtest_margin_hyperparams.R (owned file)  -- same unsafe scalar copy; removed for the same reason

  -- C-1 end to end: running market_odds_engine.R standalone --
  exit status: 0 | rows produced: 8
  contrib_hca column written by the run:
                                   Matchup contrib_hca contrib_net_diff
1       Washington Mystics vs. Chicago Sky         2.4           10.111
2        Connecticut Sun vs. Atlanta Dream         2.4           10.817
3      Los Angeles Sparks vs. Dallas Wings         2.4            3.040
4         Las Vegas Aces vs. Seattle Storm         2.4          -10.367
5        Phoenix Mercury vs. Portland Fire         2.4           -4.740
6          Indiana Fever vs. Toronto Tempo         2.4          -10.296
7 Portland Fire vs. Golden State Valkyries         2.4            7.990
8      New York Liberty vs. Minnesota Lynx         2.4           -0.230
  predicted_margin Model_Win_Prob market_data_source
1          12.8845          0.821      LIVE_ODDS_API
2          13.4615          0.168      LIVE_ODDS_API
3           5.9275          0.336      LIVE_ODDS_API
4          -8.5385          0.271      LIVE_ODDS_API
5          -2.4375          0.569      LIVE_ODDS_API
6          -8.2965          0.277      LIVE_ODDS_API
7          11.0050          0.216      LIVE_ODDS_API
8           2.3260          0.434      LIVE_ODDS_API
[PASS] CHECK 6a (C-1) market_odds_engine.R completes standalone against real caches  -- exit=0, 8 rows
[PASS] CHECK 6b (C-1) every contrib_hca row equals WNBA_HCA (2.40), not 11.6  -- unique(contrib_hca) = 2.4
[PASS] CHECK 6c (M-5) market_data_source survives into cache/latest_value_bets.rds  -- LIVE_ODDS_API
[PASS] CHECK 6d (C-1 impact) recommendations are no longer all-home / all-max-stake  -- Bankroll_Rec values = 1.41, 1.89, 2.02, 2.29, 3 (review: all 8 pinned at the 3% Kelly cap)
  cached .rds artifacts restored to their pre-test bytes (P4-G owns regeneration).

=== ALL CHECKS PASSED: 0 check(s) failed ===
EXIT=0
```

**On CHECK 6 and the "do not touch cached `.rds` artifacts in Wave 2" constraint.** The brief
requires running `market_odds_engine.R` standalone, and `evaluate_betting_slate()` writes
`cache/latest_value_bets.rds` and `cache/odds_history.rds` unconditionally. The test therefore backs
both files up before the run and restores them byte-for-byte afterwards, so P4-G still owns
regeneration. `git status --porcelain cache/` is clean at handoff. Note this means the shipped
caches **still contain the invalid `contrib_hca = 11.6` rows** — CHECK 6 proves the engine now
*produces* 2.40, it does not fix the stored artifacts. That is P4-G's job and it is still required.

**CHECK 6d, read honestly.** The review's symptom was all 8 picks on the home side at the 3% Kelly
cap. Post-fix the stake distribution is genuinely dispersed (1.41 / 1.89 / 2.02 / 2.29 / 3) and the
home probabilities are no longer uniformly extreme, but one bet still sits at the cap — that is a
legitimate single saturated bet, not the structural artifact. I did not tune anything to make this
number look better.

**`git diff --stat` for my four owned files** (the other modified paths in the repo-wide diffstat
belong to the four `agent_*` peers running concurrently in Wave 2; `logs/*` is the logger's runtime
side effect; `tools/test_phase4_engine.R` is new/untracked):

```
 market_odds_engine.R                | 140 ++++++++++++++++------
 tools/backtest_margin_hyperparams.R |  10 +-
 tools/build_calibration_cache.R     |   8 +-
 tools/optimize_hca.R                |  22 +++-
```

Left uncommitted for orchestrator review.
