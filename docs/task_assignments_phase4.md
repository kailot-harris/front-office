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
| P4-C | 1 | `agent_foundation` | `config.R`, `logging_utils.R`, new `rapm_join_utils.R` | C-1 (constant), H-1 (redaction helper), H-2 (shared join helper), M-6 (canonical `%||%`), M-7 (log connection lifecycle), L-2 (config.R comment) | PENDING |
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
(Appended by each agent as it completes its wave — empty until Wave 1 starts.)
