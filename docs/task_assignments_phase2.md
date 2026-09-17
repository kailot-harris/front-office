# Task Assignments: Phase 3 (NFL Fatigue / Short-Rest / Travel Engine)
Date: 2026-09-16

**Naming note:** third entry in this repo's `task_assignments_phaseN.md` series (file-numbering
convention, not DAG-stage numbering — see `task_assignments_phase0.md`'s naming note). DAG-wise
this is the `fatigue/embeddings` stage per `docs/NFL_REPLICATION_PLAN.md` §1's order
(`ingest → metrics → ratings → fatigue/embeddings → market/props → risk/notify → live/dashboard`).
Ingest (Phase 1) and metrics/ratings (Phase 2) are done.

## Overview
Builds a **real, schedule-driven** fatigue engine — a deliberate improvement over the WNBA repo's
`fatigue_travel_engine.R`, which is a known **synthetic/demo** script (hardcoded 4-game sample
slate, not wired to a real schedule feed; see that file's own header/footer). This repo has real
`CACHE_SCHEDULES` data (real game dates, real matchups) from Phase 1, so there is no excuse to ship
a synthetic demo here — compute real rest-days and real travel/circadian metrics for every game in
`CACHE_SCHEDULES`, not a 4-row toy example.

Per `docs/NFL_REPLICATION_PLAN.md` §4.2, NFL adds a fatigue axis with no WNBA analog: **short-week
scheduling** (Thursday Night Football creates a "mini-bye" for the team that played the prior
Sunday and a short week for whoever they play next; Monday Night Football creates the mirror
effect). This must be a genuinely new "days of rest" feature layered onto the travel/circadian math
(which ports from WNBA largely unchanged, since haversine/timezone-shift physiology is
sport-agnostic) — not a replacement of it.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P3-A | 1 | `nfl_fatigue_agent` | `fatigue_engine.R` | REPLICATION_PLAN §4.2 (short-rest axis), sport-agnostic haversine/circadian math ported from WNBA, `config.R`'s `REST_DAYS_CAP` (first real consumer) | PENDING |
| P3-B | 2 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire the new stage into the existing 5-stage DAG | PENDING |

## File-ownership disjointness check
`fatigue_engine.R` does not currently exist (verified via `Glob`). `run_full_pipeline.R` exists and
is owned exclusively by P3-B, which runs after P3-A lands. No overlap.

## Wave dependency graph
```
Wave 1: nfl_fatigue_agent (fatigue_engine.R)     [reads CACHE_SCHEDULES only — no dependency on
                                                    epa_metrics_engine.R / team_ratings_engine.R
                                                    output, so this could technically have run in
                                                    parallel with Phase 2, but is scoped as its own
                                                    wave/phase for review clarity]
   v
Wave 2: nfl_pipeline_wire_agent (run_full_pipeline.R)  [adds one run_stage() call after the
                                                          existing five]
```

## Interface contract

| Script | Exposed function | Contract | Reads | Writes |
| :--- | :--- | :--- | :--- | :--- |
| `fatigue_engine.R` | `run_fatigue_engine()` | No required args; for every game in `CACHE_SCHEDULES` (played and upcoming), compute each team's days-of-rest since its prior game (capped/flagged per `config.R`'s `REST_DAYS_CAP`), a short-week flag (Thursday game after a Sunday game = mini-bye for that team, short week for its next opponent — derive from actual game weekday, not an assumed schedule slot), and travel-fatigue metrics (haversine distance + timezone-shift circadian tax) between each team's prior game site and the current game site, using a real, live-verified 32-team NFL stadium lat/lon/timezone/altitude table (`NFL_STADIUM_DB` or similar — build this the same rigor as WNBA's `ARENA_DB`: verified via web search, not fabricated, cited in comments); returns `TRUE`/`FALSE` | `CACHE_SCHEDULES` | new constant `CACHE_FATIGUE_METRICS` (add to `config.R` as the same narrow documented exception pattern used in Phase 2) |

## Constraints
- **No synthetic/demo data.** Every game in `CACHE_SCHEDULES` must get a real computed row — this
  is the one explicit thing this wave must NOT copy from WNBA's fatigue engine.
- Team stadium geographic data must be **live-verified** (web search each of the 32 current
  `NFL_TEAMS` franchises' current home stadium — note the Rams/Chargers share SoFi Stadium, and
  double-check any other shared-stadium or recently-relocated/renamed-venue cases) — not typed from
  memory or copy-pasted from an NBA/NFL-adjacent source without verification. Cite sources in
  comments, same convention as WNBA's `ARENA_DB` header.
- `REST_DAYS_CAP` (config.R, currently unused) becomes this stage's first real consumer — reference
  it, don't hardcode 14 (or any other cap value) again.
- No `sys.nframe()`/`!interactive()` auto-run guard — this repo's established convention (all five
  existing stages) is `call_fn`-style explicit invocation by the orchestrator.
- A bye-week team (no prior game to compute rest-days from at the start of a stretch, or a team
  coming off its bye) is a real, expected case — handle it explicitly (e.g. NA rest-days / a
  distinct "off bye" flag) rather than erroring or silently producing a wrong small number.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
