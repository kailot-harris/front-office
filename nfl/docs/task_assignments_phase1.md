# Task Assignments: Phase 2 (NFL EPA Metrics & Team Ratings Engine)
Date: 2026-09-16

**Naming note:** per `docs/task_assignments_phase0.md`'s own naming note, this is the second entry
in this repo's `task_assignments_phaseN.md` series (that file's content was logically "Phase 1";
this file's content is logically "Phase 2" per `docs/NFL_REPLICATION_PLAN.md` §1's DAG order:
`ingest → metrics → ratings → fatigue/embeddings → market/props → risk/notify → live/dashboard`).
Ingest is done (Phase 1). This wave builds the `metrics` and `ratings` stages.

## Overview
Builds the repo's first real modeling signal: play-level EPA/CPOE aggregated into rolling team
efficiency metrics, then a team power-rating / point-spread projection layer on top of it. Source
of requirements: `docs/NFL_REPLICATION_PLAN.md` §5 (EPA/CPOE as the modern standard, available
directly from `nflreadr::load_pbp()`'s own columns — no separate nflfastR EPA-model call needed
since nflreadr's pbp release already ships EPA), `config.R`'s `NFL_HCA`/`NFL_MARGIN_SIGMA`/
`ROLLING_WINDOW_SIZE` (which this wave is the **first real consumer of** — until now they were
unused config constants), and `CACHE_PBP`/`CACHE_SCHEDULES` from Phase 1.

Two tasks, disjoint file ownership. `team_ratings_engine.R` depends on `epa_metrics_engine.R`'s
output cache (not its file), so they run in sequence, not parallel — this wave has no
independently-parallel work the way Phase 1's three ingestion scripts did.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P2-A | 1 | `nfl_epa_metrics_agent` | `epa_metrics_engine.R` | REPLICATION_PLAN §5 (EPA/CPOE from `load_pbp()`), rolling-window use of `ROLLING_WINDOW_SIZE` | PENDING |
| P2-B | 2 | `nfl_ratings_agent` | `team_ratings_engine.R` | REPLICATION_PLAN §3 (`NFL_HCA`/`NFL_MARGIN_SIGMA` as first real consumers), §5 (Pythagorean baseline as a comparison point, not the sole model) | PENDING |
| P2-C | 3 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire both new stages into the existing DAG skeleton | PENDING |

## File-ownership disjointness check
`epa_metrics_engine.R`, `team_ratings_engine.R`, and `run_full_pipeline.R` are three distinct
filenames. The first two do not currently exist (verified via `Glob` before this file was
written). `run_full_pipeline.R` exists (Phase 1) and is owned exclusively by P2-C, which runs
after P2-A/P2-B land — no wave overlaps a file another wave is still writing.

## Wave dependency graph
```
Wave 1: nfl_epa_metrics_agent (epa_metrics_engine.R)
   |  writes cache/team_epa_metrics.rds
   v
Wave 2: nfl_ratings_agent (team_ratings_engine.R)     [reads cache/team_epa_metrics.rds]
   |  writes cache/team_ratings.rds, cache/projected_matchups.rds
   v
Wave 3: nfl_pipeline_wire_agent (run_full_pipeline.R) [adds two run_stage() calls after the
                                                         existing three ingestion stages]
```
Sequential because P2-B's function reads P2-A's output cache file, not just its exposed function —
unlike Phase 1's three ingestion scripts, which were mutually independent.

## Interface contracts

| Script | Exposed function | Contract | Reads | Writes (via `config.R` constant or literal cache path) |
| :--- | :--- | :--- | :--- | :--- |
| `epa_metrics_engine.R` | `run_epa_metrics()` | No required args; loads `CACHE_PBP`, computes per-team-per-game offensive/defensive EPA-per-play, success rate, and CPOE (where available — pass plays only), then a rolling `ROLLING_WINDOW_SIZE`-game trailing average per team ordered by schedule date; returns `TRUE`/`FALSE` | `CACHE_PBP` | `cache/team_epa_metrics.rds` (new constant `CACHE_EPA_METRICS` — add it to `config.R`; flag this explicitly since it's outside this task's file ownership — see Constraints) |
| `team_ratings_engine.R` | `run_team_ratings()` | No required args; loads `cache/team_epa_metrics.rds` + `CACHE_SCHEDULES`, produces a per-team power rating and a projected-margin/win-probability for each upcoming (unplayed) scheduled game using `NFL_HCA` + `NFL_MARGIN_SIGMA` (via `pnorm()`-style conversion, per `config.R`'s own comment on that constant's purpose); also compute the simple Pythagorean-expectation baseline from `CACHE_SCHEDULES` results as a comparison column, per REPLICATION_PLAN §5, not as the primary model; returns `TRUE`/`FALSE` | `cache/team_epa_metrics.rds`, `CACHE_SCHEDULES` | `cache/team_ratings.rds`, `cache/projected_matchups.rds` |

**Constants note:** `epa_metrics_engine.R` needs one new `config.R` cache-path constant
(`CACHE_EPA_METRICS`) that doesn't exist yet. Per this repo's single-file-ownership convention,
P2-A does not have `config.R` in its file-ownership column — it must add this one constant to
`config.R` as an explicit, narrowly-scoped exception (same pattern Phase 1's `run_full_pipeline.R`
agent used for the `pipeline-freshness-audit` skill files), and note the addition in its Handoff
Notes so P2-B (which reads that path) isn't surprised by an undocumented change.

## Constraints
- Both engines read `CACHE_PBP`/`CACHE_SCHEDULES`, never write them (Phase 1 ingestion scripts own
  those writes exclusively).
- Per the WNBA failure-mode #1 (constants drifting), `NFL_HCA`/`NFL_MARGIN_SIGMA`/
  `ROLLING_WINDOW_SIZE` must be referenced from `config.R`, never re-typed as literals in either
  engine script. Run `.claude/skills/config-constant-drift-audit` after both land.
- Per failure-mode #3 (ID-scheme joins): team-level joins here use `NFL_TEAMS` abbreviations
  (already the common key across `CACHE_PBP`/`CACHE_SCHEDULES`/`CACHE_ROSTERS` per Phase 1's
  agents' findings — no GSIS/ESPN/PFR player-ID crosswalk is needed at the team-rating grain).
  Player-level ID-crosswalk usage (`load_ff_playerids()`) is deferred to a later player-props wave.
- `CURRENT_SEASON`'s games are partial (in progress) — the rolling EPA window and ratings should
  handle a team with fewer than `ROLLING_WINDOW_SIZE` completed games this season gracefully
  (e.g. fall back to a shorter available window or prior-season data), not error or silently drop
  the team.
- This wave does not implement fatigue/embeddings, market/props, risk/notify, or the dashboard —
  those remain later phases per the DAG order.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
