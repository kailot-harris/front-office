# Task Assignments: Phase 4 (NFL Playoff Bracket Simulator)
Date: 2026-09-16

**Naming note:** fourth entry in this repo's `task_assignments_phaseN.md` file-numbering series.
DAG-wise this pulls forward a later-DAG deliverable (playoff simulation isn't its own named DAG
node in `docs/NFL_REPLICATION_PLAN.md` §1, but is explicitly called out in §4.1 as a **real
structural divergence** requiring genuinely new logic, not a port) while `embeddings`/`market/props`
remain blocked on a human decision (Odds API key) or are lower-value optional work. This wave is
scoped to make progress on the un-blocked, high-value structural-divergence item.

## Overview
WNBA's `playoff_simulator.R` models best-of-N series (best-of-3/5/7) — logic that **does not
transfer** to the NFL, which is single-elimination. Per `docs/NFL_REPLICATION_PLAN.md` §4.1: 14
playoff teams (7 per conference: 4 division winners seeded 1-4, 3 wildcards seeded 5-7), only the
#1 seed per conference gets a first-round bye, and the bracket re-seeds after each round (the
lowest remaining seed always plays the highest remaining seed within its conference). This is a
genuinely new bracket-advancement model, not a parameter swap on WNBA's series simulator.

Additionally: unlike WNBA's playoff simulator (which uses *real* current standings but only
demonstrates 3 example matchups, not a full bracket), this wave should simulate a **full real
bracket** end to end using real current in-season records — the closest thing to a fully-worked
example this repo has shipped a "demo" for so far, and it should be done properly.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P4-A | 1 | `nfl_playoff_agent` | `playoff_simulator.R` | REPLICATION_PLAN §4.1 (single-elimination, 14-team, reseeding bracket) | PENDING |
| P4-B | 2 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire the new stage into the existing 6-stage DAG | PENDING |

## File-ownership disjointness check
`playoff_simulator.R` does not currently exist (verified via `Glob`). `run_full_pipeline.R` exists
and is owned exclusively by P4-B, which runs after P4-A lands.

## Interface contract

| Script | Exposed function | Contract | Reads | Writes |
| :--- | :--- | :--- | :--- | :--- |
| `playoff_simulator.R` | `run_playoff_simulator()` | No required args; determines the current real 14-team playoff field (7 per conference: division leaders by real in-season win% seeded 1-4, next-3 by win% among non-division-leaders as wildcards seeded 5-7 — **simplified tiebreak**, not the NFL's full official multi-step tiebreaker procedure; document this simplification explicitly, do not claim official-tiebreaker accuracy), Monte Carlo-simulates the full single-elimination bracket (Wild Card round: seeds 2-7 play with reseeding, #1 seed byes; Divisional round: reseed remaining teams by original seed; Conference Championship; Super Bowl — cross-conference, no reseeding needed) using each team's real `team_ratings.rds` power rating adjusted by `NFL_HCA`/`NFL_MARGIN_SIGMA` per game (home team = higher remaining seed, per NFL's real playoff-hosting rule — verify this is still correct live), `config.R`'s `N_SIMULATIONS`; returns `TRUE`/`FALSE` | `cache/team_ratings.rds` (`CACHE_TEAM_RATINGS`), `CACHE_SCHEDULES` (for real in-season records to seed the field) | new constant `CACHE_PLAYOFF_SIMULATION` (add to `config.R` as the same narrow documented exception pattern used in prior waves) |

## Constraints
- **Requires real conference/division data that does not exist in `config.R` yet.** Add
  `NFL_DIVISIONS` (or equivalent: team -> conference + division, e.g. `AFC East`) as a **narrow,
  documented exception** to `config.R`, live-verified against each of the 32 current `NFL_TEAMS`
  (do not assume divisions haven't changed — verify live) — this is a second authorized config.R
  addition alongside `CACHE_PLAYOFF_SIMULATION`, both cited in Handoff Notes.
- Per `docs/NFL_REPLICATION_PLAN.md` §4.1: verify live that the "higher remaining seed always
  hosts" reseeding rule and the "only the #1 seed gets a bye" rule are both still current for the
  2026 postseason before hardcoding either — the format has changed before (12→14 teams in 2020).
- No `sys.nframe()`/`!interactive()` auto-run guard — this repo's established convention (all 6
  existing stages) is `call_fn`-style explicit invocation.
- A mid-season run (current season incomplete) will produce a real-but-provisional field based on
  in-progress records — this is expected and correct, not a bug to work around; document it as such
  rather than gating the whole stage on the season being complete.
- Simplified seeding note above must be visible in-code (comment) and in Handoff Notes — do not let
  a future reader mistake this for the NFL's actual official tiebreaker procedure.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
