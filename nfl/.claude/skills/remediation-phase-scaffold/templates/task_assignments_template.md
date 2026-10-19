# Task Assignments: Phase N (PHASE TITLE HERE)
Date: YYYY-MM-DD

## Overview
State what this phase remediates/builds, the source of the findings (a review doc, enumerated bug
list, or feature spec), and the wave-grouping rationale — normally "agents grouped by disjoint file
ownership, not by finding severity, since two agents in the same wave must never write the same
file" (adjust only if this repo gains real merge tooling, which it does not have as of Phase 4).

**Orchestration principle:** one finding/requirement list → regrouped into a file-ownership DAG →
executed in waves. A wave's agents run in parallel; waves run in series. Within a wave, an agent
may touch only the files listed in its own brief (`agents/agentN_*.md`).

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| PN-A | 1 | `agent_name` | `file1.R`, `file2.R` | FINDING-ID (short description) | PENDING |

## Phase 0 — Orchestrator-Only Setup (optional — include only if this phase needs it)
Some phases need a prerequisite step no subagent should own (e.g. Phase 4's `git init` + baseline
commit, done because the repo had no version control and "did agent X touch only its assigned
files" was otherwise unanswerable). Omit this section entirely if the phase has no such step —
don't manufacture a Phase 0 just to match the template.

## Wave dependency graph
```
Wave 0 (if a Phase 0 setup step exists above)
   |
Wave 1: agent_x  +  agent_y   [parallel if file-disjoint, else serial — state which]
   |
Wave N: ...
```
State explicitly why waves marked parallel are safe to run concurrently (file-ownership columns
above must be pairwise disjoint within a wave — verify by inspection, don't assume).

## Interface contracts (finalize before any wave that depends on them starts)
List every cross-agent dependency here: new schema columns, shared function signatures, renamed
constants. For each: exact name/type/signature, which agent writes it, which agent(s) read it, and
confirmation that all consuming agents were briefed with the same signature before their wave
started.

## Constraints
Note anything requiring explicit user go-ahead before proceeding (e.g. cache invalidation,
external API calls, anything hard to reverse) — mirroring how Phase 4's Wave 3 required explicit
confirmation before invalidating live cache artifacts.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED without
a corresponding entry here.)

---
