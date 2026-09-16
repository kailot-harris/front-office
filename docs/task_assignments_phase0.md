# Task Assignments: Phase 1 (NFL Data-Foundation Ingestion Scripts)
Date: 2026-09-16

**Naming note:** this is the first `docs/task_assignments*.md` file created in this repo. The
scaffold/config/skills/docs work three parallel agents already completed (`config.R`,
`tools/derive_nfl_constants.R`, `docs/NFL_REPLICATION_PLAN.md`, `.claude/skills/`) is referred to
throughout this repo as "Phase 0" — it produced no task-tracker file of its own since it predates
this skill's use here. This file is named `task_assignments_phase0.md` per the explicit file
assignment for the agent that wrote it, but its content documents the **next** executable wave of
work (i.e. the wave that would be numbered "Phase 1" under the `remediation-phase-scaffold`
skill's own numbering convention). Whoever scaffolds the wave after this one should name that file
`docs/task_assignments_phase1.md` and treat this file as the first entry in that same numbered
series, not as a second "Phase 0."

## Overview
This phase builds the repo's first real data-ingestion scripts and the pipeline-orchestration
skeleton that will eventually run them, per `docs/NFL_REPLICATION_PLAN.md`'s §1 porting-strategy
narrative and §2 data-source decision table. Source of requirements: `docs/NFL_REPLICATION_PLAN.md`
(nflreadr function/coverage table in §2, the ESPN injury `athlete.id` quirk in §2, the
`sys.nframe() == 0` pipeline-guard failure mode in §1) plus `config.R`'s existing cache-path
constants, which these scripts must write to rather than inventing new filenames.

Four tasks, grouped by disjoint file ownership (not by finding severity — no two agents in the
same wave may write the same file, since this repo has no merge tooling to reconcile conflicting
edits): three independent ingestion scripts in Wave 1, then the pipeline skeleton that wires them
together in Wave 2 (it depends on the function signatures Wave 1 exposes, finalized below in
Interface Contracts before Wave 1 starts).

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P1-A | 1 | `nfl_ingest_agent` | `daily_ingest.R` | REPLICATION_PLAN §2 (`load_pbp()`, `load_schedules()`; nflreadr not `fast_scraper_*`) | PENDING |
| P1-B | 1 | `nfl_roster_agent` | `sync_rosters.R` | REPLICATION_PLAN §2 (`load_rosters()`/`load_rosters_weekly()`) | PENDING |
| P1-C | 1 | `nfl_injury_agent` | `injury_scraper.R` | REPLICATION_PLAN §2 (ESPN Player-Card-href workaround; `nflreadr::load_injuries()` as primary, ESPN site-API JSON as secondary) | PENDING |
| P1-D | 2 | `nfl_pipeline_skeleton_agent` | `run_full_pipeline.R` | REPLICATION_PLAN §1 (staged DAG, `run_stage()` try/catch, no `sys.nframe()`-style guard) | PENDING |

No Phase-0-style orchestrator-only setup step is needed here (this repo already has git
initialized and `config.R`/skills in place from the prior wave), so no "Wave 0" section is
included.

## File-ownership disjointness check
Verified by inspection, not assumed: `daily_ingest.R`, `sync_rosters.R`, `injury_scraper.R`, and
`run_full_pipeline.R` are four distinct filenames, none of which currently exist in this repo (a
fresh `Glob` of the repo root at the time this file was written showed only `config.R`,
`docs/NFL_REPLICATION_PLAN.md`, `tools/derive_nfl_constants.R`, `.claude/skills/**`, and empty
`.gitkeep`-only `agents/`, `docs/`, `data/`, `cache/`, `tools/` directories — no prior version of
any of these four files to collide with). No two rows in the Task Tracker above share a file.
Wave 1's three files (`daily_ingest.R`, `sync_rosters.R`, `injury_scraper.R`) are pairwise
disjoint from each other, so they may run fully in parallel. Wave 2's single file
(`run_full_pipeline.R`) is disjoint from all three Wave 1 files, so there is no write conflict
between waves either — Wave 2 depends on Wave 1 only through the Interface Contracts below (the
callable function names/signatures each ingestion script exposes), not through any shared file.
All four scripts read (never write) `config.R` — read-only access to a shared file by multiple
agents is not a conflict.

## Wave dependency graph
```
Wave 1: nfl_ingest_agent (daily_ingest.R)
      +  nfl_roster_agent (sync_rosters.R)
      +  nfl_injury_agent (injury_scraper.R)         [parallel — file-disjoint, verified above]
   |
Wave 2: nfl_pipeline_skeleton_agent (run_full_pipeline.R)   [serial after Wave 1 —
                                                              sources Wave 1's scripts by bare
                                                              filename and calls their exposed
                                                              stage functions per the Interface
                                                              Contracts below]
```
Wave 1 is safe to run concurrently because its three agents' file-ownership columns are pairwise
disjoint (checked above) and none of them read each other's output caches (each ingestion script
is independently runnable/testable against live nflreadr/ESPN data with no dependency on another
Wave-1 script's output). Wave 2 must run after Wave 1 lands because `run_full_pipeline.R` sources
all three ingestion scripts by bare filename and calls the specific function names fixed in the
Interface Contracts section below — those names must exist before Wave 2 can smoke-test its
`run_stage()` wiring against real (not stubbed) stage functions.

## Interface contracts (finalize before Wave 1 starts)
Each Wave 1 script must expose one top-level callable function (not a `sys.nframe() == 0` /
`!interactive()`-style top-level-only guard — see `docs/NFL_REPLICATION_PLAN.md` §1's second
failure mode and this repo's `CLAUDE.md` "Process / conventions" section) that
`run_full_pipeline.R`'s `run_stage()` will call explicitly. Fixed signatures, so Wave 2 can be
written and smoke-tested without re-reading Wave 1's internals line by line:

| Script | Exposed function | Contract | Writes (via `config.R` constant) |
| :--- | :--- | :--- | :--- |
| `daily_ingest.R` | `run_daily_ingest()` | No required args; pulls current-season (and, on first run / `force_refresh = TRUE`, full-history per `ALL_SEASONS`) play-by-play and schedule data via `nflreadr::load_pbp()` / `nflreadr::load_schedules()`; returns `TRUE`/`FALSE` (or throws, per `run_stage()`'s try/catch contract) | `CACHE_PBP`, `CACHE_SCHEDULES` |
| `sync_rosters.R` | `run_sync_rosters()` | No required args; pulls current rosters via `nflreadr::load_rosters()` (and/or `load_rosters_weekly()` for in-season weekly granularity); returns `TRUE`/`FALSE` | `CACHE_ROSTERS` |
| `injury_scraper.R` | `run_injury_scraper()` | No required args; primary path `nflreadr::load_injuries()`, secondary/same-day-freshness path ESPN's site-API JSON feed with the Player-Card-href athlete-ID extraction (never assume `athlete$id` exists); returns `TRUE`/`FALSE` | `CACHE_INJURY_DATA` |

`run_full_pipeline.R` (Wave 2) must call these three functions by these exact names, each wrapped
in its own `run_stage()` call, and must not itself duplicate any `config.R` constant (cache paths,
season windows) at the call site — per this repo's `CLAUDE.md` constants convention. Any
Wave-1 agent that finds a real reason to deviate from its fixed signature (e.g. an argument turns
out to be unavoidable) must update this table and flag the change explicitly for the Wave-2 agent
before Wave 2 starts — do not let Wave 2 discover a signature mismatch by trial and error.

## Constraints
- All four scripts hit live external endpoints (nflreadr's nflverse-hosted data releases,
  ESPN's public site-API JSON feed). No credentials are required for any of these three sources
  (confirmed in `docs/NFL_REPLICATION_PLAN.md` §2 — none of `load_pbp()`/`load_schedules()`/
  `load_rosters()`/`load_injuries()`/the ESPN site API need an API key), so no human
  credential-provisioning step blocks this wave, unlike a future odds/props wave that will need a
  human-provisioned Odds API key per `docs/NFL_REPLICATION_PLAN.md` §2's Odds/lines section.
  `run_full_pipeline.R`'s skeleton (P1-D) should still be written so a future
  market/props stage can be added without restructuring the DAG.
- `run_full_pipeline.R` in this wave is a **skeleton**: it must wire up and correctly
  `run_stage()`-call the three Wave 1 ingestion functions with real error handling and logging
  (not a folder of empty stubs), but later phases will extend the DAG (metrics → ratings →
  fatigue/embeddings → market/props → risk/notify → live/dashboard per
  `docs/NFL_REPLICATION_PLAN.md` §1) — do not block this wave on those later stages existing.
- Per this repo's `.claude/skills/pipeline-freshness-audit` skill, once `run_full_pipeline.R`
  exists its stage → output-cache manifest placeholder in that skill's `SKILL.md` must be
  populated with these three real stages/outputs — flagged here for whichever agent finishes
  Wave 2, not performed by this scaffolding task itself.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
