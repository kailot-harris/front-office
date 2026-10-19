---
name: remediation-phase-scaffold
description: Scaffolds a new dated docs/task_assignments_phaseN.md (with Task Tracker table, wave dependency graph, interface contracts, and an append-only Handoff Notes section) plus per-agent brief files, matching this repo's existing multi-phase remediation conventions. Use when starting a new multi-phase or multi-agent remediation/audit effort. Not for a single-agent, single-file fix.
---

# Remediation Phase Scaffold

## Why this exists

This convention was ported from the WNBA Analytics repo's identically-shaped need: that repo ran
four remediation phases (`docs/task_assignments.md` through `docs/task_assignments_phase4.md`),
each following the same structure — a Task Tracker table keyed by short task IDs, agents grouped
into waves by disjoint file ownership (not by finding severity — two agents in the same wave must
never write the same file, since there's no merge tooling to reconcile conflicting edits), an
explicit interface-contracts section for any schema/column/function-signature that multiple
agents' work depends on, and an append-only Handoff Notes section where each agent records exactly
what changed and why, including any findings *not* addressed and reasons. This repo is a fresh
scaffold with no phase history yet, but the same convention applies from Phase 1 onward: future
agents are expected to read prior phases' Handoff Notes before touching a script another agent
already built, because actual filenames/schemas sometimes diverge from what an earlier plan
document proposed — this only works if every phase actually follows the convention from the
start.

## When to use

- Starting a new remediation, audit-fix, or feature effort that will involve more than one
  agent/subagent, or more than one wave of sequential work by the same agent.
- Not for a single, self-contained fix one agent can complete in one pass — that doesn't need a
  phase file, just do the work.

## Procedure

1. Determine the next phase number: `ls docs/task_assignments_phase*.md`, take the highest N,
   use N+1 (or, if this is the first phase-numbered effort, check whether `docs/task_assignments.md`
   without a number already exists as "Phase 1" implicitly).
2. Copy `templates/task_assignments_template.md` to
   `docs/task_assignments_phaseN.md`, filling in:
   - Today's date and a one-line phase title describing its scope (mirroring
     "Security & Data-Integrity Remediation" style specificity, not a generic name).
   - The source of the findings being remediated (a review doc, a bug report, user-specified
     scope) — every past phase traces its Task Tracker rows back to a specific enumerated finding
     list; do not create tasks that aren't traceable to a stated finding or requirement.
   - Waves grouped by **disjoint file ownership**, verified by inspection: list every file each
     agent will touch and confirm no two agents in the same wave share a file. If two findings
     require touching the same file, they go in the same agent's brief, or in different waves.
   - An Interface Contracts section for anything cross-agent (new columns, new shared function
     signatures, renamed constants) that more than one wave-2+ agent depends on without seeing
     each other's code — this must be finalized *before* the wave that depends on it starts.
3. For each agent in the plan, copy `templates/agent_brief_template.md` to
   `agents/agentN_<name>.md` (matching the existing `agents/agent1.md`-style naming already in
   this repo) with its specific file ownership, findings/tasks covered, and any interface
   contracts it must honor.
4. Leave the Task Tracker's Status column as `PENDING` for all rows at creation time — this
   skill only scaffolds the plan, it does not execute any remediation work itself. Update
   statuses to `IN PROGRESS`/`COMPLETED` and append Handoff Notes only as the actual work
   happens, in a separate step.
5. Do not delete or rewrite any prior phase's file. This convention is append-only and historical
   — later phases reference earlier ones' Handoff Notes as provenance.

## Handoff Notes discipline (for whoever executes the scaffolded plan later)

Each entry must be self-contained enough that a future agent can trust it without re-reading the
diff: files changed (and an explicit note for any unrelated-looking modified file, e.g. a log
file touched by a test run rather than a source edit), what landed per finding/task ID, and
anything explicitly deferred to a later wave with a named owner. Never mark a Task Tracker row
`COMPLETED` without a corresponding Handoff Notes entry — an untraceable "completed" status is
exactly the kind of gap this convention exists to prevent.

## Testing/cleanup note

When scaffolding a test/dry-run of this skill itself (not a real phase), name the output file
with an unambiguous marker (e.g. `docs/task_assignments_phase5_TEST.md`) and delete it after
verifying structure — never leave a test scaffold indistinguishable from a real phase file in
`docs/`.
