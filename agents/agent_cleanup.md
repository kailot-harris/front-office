---
name: agent_cleanup
role: The Janitor
soul: Cares that a comment cites a name, not a number that can drift.
focus: tools/ml_cv_benchmark.R, tools/ml_feature_experiments.R, root scratch files.
wave: 2 (parallel with agent_engine, agent_dashboard, agent_pipeline, agent_props)
---

# Agent Brief: The Janitor

Lowest risk, fully disjoint file set from every other Wave 2 agent — you can start immediately
after `agent_foundation`'s Wave 1 lands (no functional dependency, just sequencing convention).

Read `docs/SECURITY_TECHNICAL_REVIEW.md` findings L-2 (tools/ half), L-3, L-5 in full.

## Files you may touch
`tools/ml_cv_benchmark.R`, `tools/ml_feature_experiments.R`, the root-level `temp_*.R` scratch
files, and a new `.gitignore`. Nothing else.

## Tasks

1. **L-2 (tools/ half).** `tools/ml_cv_benchmark.R:62`'s comment says *"window_size default
   overridden by caller to ROLLING_WINDOW_SIZE = 13"* — the code already correctly reads the
   constant, only the comment restates a now-stale value (real value is `12`). Change the comment to
   cite the constant's name, not its value: *"overridden by caller to config.R's
   ROLLING_WINDOW_SIZE"*.

2. **L-3.** `tools/ml_cv_benchmark.R:72,82` (and the same block in `tools/ml_feature_experiments.R`)
   mix `total_turnovers` (in the four-factors rate) and `turnovers` (in the rolling feature) for what
   looks like the same concept, but are genuinely different cache columns
   (`mean(total_turnovers)=14.09` vs `mean(turnovers)=13.17`, confirmed non-identical in the
   review). Pick one column for both uses — `total_turnovers` is the more defensible choice since
   it's the one already used in the four-factors formula it's paired with — and add a one-line
   comment explaining the choice so it reads as deliberate, not accidental.

3. **L-5.** Move `temp_check_rapm.R`, `temp_derive_copula.R`, `temp_derive_props.R`,
   `temp_derive_props_rot.R` from repo root into `tools/` with descriptive names (or delete them if,
   on inspection, they're fully superseded by production code — check whether
   `temp_derive_props_rot.R`'s rotation-selection logic duplicates anything now living in
   `player_props_engine.R` before deciding; if it's genuinely dead, delete rather than relocate).
   Create a `.gitignore` at repo root containing at least `.Rhistory` (23 KB of session transcript
   that could capture a pasted secret in a future interactive session, per the review) — this is
   forward-looking since the repo has no history to purge yet as of Phase 0's `git init`.

## Test suite — write `tools/test_phase4_cleanup.R`
- `grep -c "ROLLING_WINDOW_SIZE = 13" tools/ml_cv_benchmark.R` — assert 0.
- Assert `turnovers`/`total_turnovers` usage is now consistent within the same feature block (same
  column name used for both the rate and the rolling feature).
- Assert no `temp_*.R` files remain at repo root (`Sys.glob("temp_*.R")` from the project root
  returns empty).
- Assert `.gitignore` exists and contains `.Rhistory`.
- Re-run `tools/ml_cv_benchmark.R`'s CV pipeline end to end (it's read-heavy, not destructive);
  assert it still completes without error after your column-naming change — a rename must not
  silently break the pipeline it documents.

## Definition of done
`tools/test_phase4_cleanup.R` passes with real output pasted into your Handoff Notes entry under
P4-F in `docs/task_assignments_phase4.md`. `git diff --stat` shows only your owned files, moved/
deleted scratch files, and `.gitignore` changed.
