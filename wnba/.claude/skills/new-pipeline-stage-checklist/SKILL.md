---
name: new-pipeline-stage-checklist
description: Checklist for adding, removing, or reordering a stage in run_full_pipeline.R -- DAG placement, entry_fn vs call_fn choice, output= declaration, and parallel-group safety -- to avoid the real mistakes this repo has already made (a parallel-placement OOM contributor, and the documented double-execution trap between entry_fn and call_fn). Use for any change to run_full_pipeline.R's stage list.
---

# New Pipeline Stage Checklist

## Why this exists

The last two stages added to `run_full_pipeline.R` (`pbp_engine.R`, `player_metrics.R`) each got a
real detail wrong on the first attempt: one was placed in a `future_lapply`/`multisession`
parallel group and contributed to an OOM kill; the other risked double-executing because its host
file (`player_metrics.R`) is also `source()`d elsewhere for pure function definitions, a failure
mode `run_full_pipeline.R` already has a comment warning about for `daily_ingest.R`. This checklist
exists so the next stage addition doesn't rediscover either mistake.

## When to use

Adding, removing, or reordering any stage in `run_full_pipeline.R`.

## Procedure

1. **Place it in the DAG by real dependency, not guess.** Read `run_full_pipeline.R`'s existing
   stage order and comments to find what the new stage's inputs actually are (which caches/globals
   must exist first), and insert it immediately after its true producer, not wherever seems
   convenient.
2. **Choose `entry_fn` vs `call_fn` — they are mutually exclusive; `run_stage()` errors if both are
   passed.**
   - Use `entry_fn` only if the script already self-runs via a top-level `if (!interactive())` (or
     equivalent) guard — `entry_fn` is verification-only, `run_stage()` does not invoke it.
   - Use `call_fn` if the script is also `source()`d elsewhere purely for its function definitions
     (e.g. `player_metrics.R` is sourced by `roster_bottom_up_engine.R`; `daily_ingest.R` was
     historically sourced by `prediction_accuracy_logger.R`) — it must NOT self-run on a bare
     `source()`.
   - Either way, confirm the script does not have BOTH an active self-run guard AND a `call_fn`
     invocation — that double-executes it.
3. **Decide on `output =`.** Declare every file the stage writes, unless the stage has legitimate
   no-op-on-no-new-data semantics (e.g. `daily_ingest.R` skips writing when there are no new
   games). Declaring `output =` on a legitimately-quiet stage produces a false staleness `WARN` on
   every quiet run and trains the operator to ignore real ones.
4. **Parallel-group placement.** Before adding the stage to an existing
   `future_lapply(plan(multisession), ...)` group, confirm it is truly independent of every other
   member. Default to sequential placement unless there's a real throughput reason — each
   `multisession` worker is a full separate R process with its own package-load overhead, and this
   repo has a real, documented OOM history from underestimating that cost (`docs/HANDOFF.md`,
   2026-09-17 OOM section; see `run_full_pipeline.R`'s own memory-adaptive-plan comment).
5. **Verify the stage's contract in isolation before a full pipeline run**:
   `Rscript.exe tools/verify_pipeline_stage.R <script.R> --entry_fn|--call_fn <fn> <output_path> [...]`
   (already exists in this repo — read its usage comment, don't reimplement).
6. **Run the full pipeline once for real**
   (`Rscript.exe run_full_pipeline.R`) and confirm the new stage shows `[FRESH]` for every declared
   output and zero `[FAILED]` stages. Pair with the `pipeline-freshness-audit` skill for an
   independent second check on the run's logs.

## Known pitfalls (already hit for real in this repo)

- Assuming a new stage belongs in an existing parallel group without checking real free memory —
  led to an OOM kill (though the actual root cause that day was a large interactive Chrome session
  eating RAM, not the new stage itself; verify with
  `(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory` and
  `Get-CimInstance Win32_Process` before assuming either way).
- Wiring a stage with `entry_fn` when the script is also sourced elsewhere for definitions — it
  will silently no-op inside `run_stage()` since `entry_fn` is never invoked, and the stage's
  output will never regenerate despite the pipeline logging success.
- Wiring a stage with `call_fn` on a script that ALSO self-runs via `!interactive()` — double
  executes on every pipeline run.
