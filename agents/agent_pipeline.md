---
name: agent_pipeline
role: The Conductor
soul: Paranoid about the gap between "logged COMPLETED" and "actually ran."
focus: run_full_pipeline.R and the four stage scripts whose guards silently no-op.
wave: 2 (parallel with agent_engine, agent_dashboard, agent_props, agent_cleanup)
---

# Agent Brief: The Conductor

You own the orchestrator and the stage scripts whose auto-run guards were found broken. Confirm
`tools/test_phase4_foundation.R` (Wave 1, `agent_foundation`) passes before you start — you'll call
`join_rapm_to_roster()` from `rapm_join_utils.R`.

Read `docs/SECURITY_TECHNICAL_REVIEW.md` findings C-2, M-1, M-2, M-7, C-1 (roster/playoff refs),
H-2 (roster_bottom_up_engine.R only), M-8 in full — C-2 in particular has a harness reproduction
you should re-run yourself before and after your fix to see the behavior actually flip.

## Files you may touch
`run_full_pipeline.R`, `sync_rosters.R`, `injury_scraper.R`, `roster_bottom_up_engine.R`,
`playoff_simulator.R`. Nothing else — `player_props_engine.R` belongs to `agent_props`.

## Tasks

1. **C-2.** Four scripts gate their entry point on `sys.nframe() == 0`, which is never true when
   `run_stage()` sources them: `sync_rosters.R:133`, `injury_scraper.R:193`,
   `roster_bottom_up_engine.R:506`, `playoff_simulator.R:248`. Convert all four to `!interactive()`
   (the pattern already used correctly by `copula_props_engine.R`, `fatigue_travel_engine.R`,
   `rapm_engine.R`, `risk_management_engine.R` — confirm those work today, don't change them).
   Additionally, extend `run_stage()`'s existing `call_fn` parameter
   (`run_full_pipeline.R:58,75-81`, currently used only for `prediction_accuracy_logger.R`) so each
   stage's entry point can optionally be invoked explicitly by name — this makes the DAG's contract
   visible in `run_full_pipeline.R` rather than hidden in each file's footer. Also add an assertion
   in `run_stage()` that the stage's declared output file's `mtime` advanced past the stage's start
   time, logging a `WARN` (not a hard failure — keep the fail-safe principle) when it did not. This
   is the review's own suggested single check that would have caught C-2 automatically — implement
   it for real, don't just note it.

2. **M-1.** At `run_full_pipeline.R:70-71`, capture and check the Python stage's exit status:
   ```r
   status <- system2("python", args = script_name)
   if (status != 0) stop(sprintf("Python stage %s exited with status %d", script_name, status))
   ```
   Let the existing `tryCatch` in `run_stage()` log it as a genuine `[FAILED]`. Add a `PYTHON_BIN`
   constant to `config.R` if you need to resolve the interpreter explicitly — if you need this,
   report it to `agent_foundation`'s Handoff Notes as a follow-up rather than editing `config.R`
   yourself (it's not in your ownership list this wave).

3. **M-2.** Add an explicit `source("config.R")` at `run_full_pipeline.R:26` alongside the existing
   `source("logging_utils.R")`, so `CACHE_DIR` and other constants are the orchestrator's own
   dependency rather than an emergent side effect of stage 0 (`tools/data_health_probe.R`)
   happening to run first and leak globals.

4. **M-7 (pipeline half).** Pass `future.seed = TRUE` to both `future_lapply()` calls
   (`run_full_pipeline.R:156-174, 190-200`). Confirm the "UNRELIABLE VALUE" warning from the
   `future.apply` package no longer appears on a real run.

5. **C-1 (roster/playoff refs).** Replace the hardcoded `2.40` HCA literals at
   `roster_bottom_up_engine.R:304,406,483` and `playoff_simulator.R:98` with `WNBA_HCA` from
   `config.R` (these were already correct in value — this is just centralizing them, not fixing a
   wrong number).

6. **H-2.** Replace `roster_bottom_up_engine.R:83-84`'s naive `left_join(rapm_df, by =
   "player_id")` with a call to `join_rapm_to_roster()` from `rapm_join_utils.R` (built by
   `agent_foundation` in Wave 1). This fix currently has no visible effect while C-2 makes this
   script a no-op — once you fix C-2 above, this stops being a latent bug and starts actually
   running, so fix both in the same pass as the review recommends.

7. **M-8.** In the standings writer inside `roster_bottom_up_engine.R`, store `Win_Pct` as a
   numeric proportion (`0.793`) instead of a formatted string (`"79.3%"`). `agent_dashboard` will
   handle display-time formatting in `app.R` this same wave — don't format it yourself here.

## Test suite — write `tools/test_phase4_pipeline.R`
- Reuse the review's `sys.nframe()` harness pattern: replicate `run_stage()`'s exact sourcing shape
  (source from inside a function) against all 17 DAG stage scripts; assert every one's main body
  now executes (no `>>> MAIN FUNCTION SKIPPED`-equivalent outcome).
- Run `Rscript.exe run_full_pipeline.R` for real, end to end. Assert exit code 0. For every stage's
  declared output cache, assert its `mtime` is at or after the run's start timestamp — this is the
  direct fix verification for C-2 (previously frozen at a 4-day-old `mtime` despite `[COMPLETED]`).
- `grep -c "future.seed" run_full_pipeline.R` — assert 2 occurrences (one per `future_lapply` call).
- Assert the Python stage test: temporarily point `script_name` at a script that `exit(1)`s (a
  scratch fixture, delete after), confirm `run_stage()` now logs `[FAILED]` instead of
  `[COMPLETED]`.
- Load the real `projected_wnba_standings.rds` after your run; assert `class(Win_Pct) ==
  "numeric"` and values are in `[0,1]`.

## Definition of done
`tools/test_phase4_pipeline.R` passes with real command output (the full pipeline run's console
tail, mtimes table) pasted into your Handoff Notes entry under P4-D in
`docs/task_assignments_phase4.md`. `git diff --stat` shows only your five owned files plus your new
test script changed.
