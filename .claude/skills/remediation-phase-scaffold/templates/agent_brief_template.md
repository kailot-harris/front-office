---
name: agent_name
role: SHORT MEMORABLE ROLE NAME (e.g. "The Foundry") — real Phase 4 briefs use these consistently
soul: One line describing this agent's working style/temperament (e.g. "Deliberate, minimal,
  allergic to restating a value in two places.") — sets tone for a persona-framed brief body.
focus: One-sentence statement of what this agent owns, matching the Scope section below.
wave: N (parallel with: agent_x, agent_y | serial — must complete before Wave N+1 starts)
---

# Agent Brief: ROLE NAME HERE

Open with a short persona-framed paragraph addressed directly to the agent ("You are ROLE NAME...
Your job is..."), stating what this agent is responsible for, why it's grouped into this wave, and
which other agents (if any) depend on this agent's output before their own wave can start. Real
Phase 4 briefs use this direct-address framing rather than a passive third-person description —
match it.

If this brief's Interface Contracts (below) are consumed by other agents without them seeing this
agent's code, say so explicitly here — that's the signal to get the exact names/signatures right
the first time, not the "What NOT to do" section further down.

## Files you may touch
- `path/to/file1.R`
- `path/to/file2.R`

Nothing else. If you discover mid-task that a fix requires touching a file owned by another
agent, stop and flag it rather than editing it — that's a sign the file-ownership split needs
revisiting, not something to route around silently.

## Tasks
Numbered, concrete tasks, each tied to a specific finding/requirement ID and file. Include exact
code/signature snippets where precision matters (e.g. a constant's exact value and comment, a
function's exact signature) rather than describing them in prose — real Phase 4 briefs give the
literal code block to land, not just an instruction to "add a constant."

1. **FINDING-ID.** What to change, in which file, with the exact expected result.

## Interface contracts you must honor
Copy the exact name/type/signature this agent must produce or consume from the phase file's
Interface Contracts section verbatim, so this brief is self-contained and doesn't require
cross-referencing the phase file mid-task.

## What NOT to do
- Do not fix findings outside this brief's list, even in an owned file, without flagging it first
  — scope creep here is exactly what breaks the disjoint-ownership safety property for the wave.
- Do not mark your own Task Tracker row COMPLETED — that's the orchestrator's job after reviewing
  your Handoff Notes entry.
- Do not re-derive or second-guess a value/decision explicitly deferred to a later wave or a
  different agent (state explicitly, per task, whether this applies).

## Test suite
Concrete, runnable verification steps for this agent's own changes before considering the brief
done — e.g. "write `tools/test_phaseN_<agent>.R` covering X/Y/Z, run it, paste the real output
into your Handoff Notes entry." Real Phase 4 briefs require an actual executed test, not just a
description of what should be tested.

## Definition of done
The exact passing condition, stated unambiguously — e.g. "`Rscript.exe tools/test_phaseN_<agent>.R`
exits 0 and prints PASS for every check listed above, then stop and write your Handoff Notes
entry." Avoid vague completion criteria ("looks correct") — this section exists so the agent (and
whoever reviews the wave afterward) can check completion mechanically.

## Handoff Notes entry (append to the phase file when done)
Required contents: files actually changed (call out any unexpected diff, e.g. a log file touched
by a test run rather than a source edit), what landed per finding ID, anything explicitly deferred
and to whom, and the actual test output demonstrating the Definition of Done was met.
