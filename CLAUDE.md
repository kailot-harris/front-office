# MLB Analytics — Working Notes

Agent-facing operating rules for this repo. This file did not exist before
front-office issue #105; it was created specifically to hold the
shared-checkout rule below, and is the place to add future repo-wide
operating rules (mirroring the sibling NFL/WNBA Analytics repos' own
`CLAUDE.md` files).

## Shared-checkout discipline (front-office issue #105)

This repo's primary checkout (`MLB Analytics`) is shared between unattended
scheduled tasks and interactive/agent sessions. On 2026-11-10, that sharing
caused a real incident in a sibling sport repo with the identical setup:

1. A scheduled pipeline run succeeded, but a subagent had left the shared
   checkout on a feature branch (`chore/nfl-week9-visual-media`) with dirty,
   regenerated output instead of on `main`.
2. The next scheduled publish gate correctly refused to publish
   (`assertion E FAILED ... HEAD=chore/nfl-week9-visual-media expected=main`).
3. A *different* session then cleared the dirty tree with `git checkout -- .`
   before merging, rather than stashing it — permanently discarding 8
   regenerated JSON files and a cache file. Published data stayed ~30 hours
   stale until a manual re-run.
4. Two more same-day collisions in that repo had the same root cause: one
   working directory, several concurrent writers (a session switching
   branches twice mid-merge; two test/build runs colliding in one `.next`
   build directory).

The exposure is identical here: `scripts/run_pipeline_task.ps1` (the
Task-Scheduler-registered pipeline/publish run, `scripts/mlb_pipeline_task.xml`)
and `schedule_weekly_offseason.bat` (the daily offseason-monitor publish run)
both execute, unattended, in this same checkout that agents and interactive
sessions also use.

**Rules, going forward:**

- **Feature work happens in a worktree** (e.g. `.mlb-worktrees/<issue>`,
  matching the layout under `front-office/.mlb-worktrees/`), never directly
  in the primary `MLB Analytics` checkout. The primary checkout is treated as
  shared infrastructure, not a scratch workspace.
- **The primary checkout stays on `main` and clean.** If you must switch it
  to another branch for a one-off reason, switch it back to `main` and leave
  it with a clean working tree before you finish — do not leave it parked on
  a feature branch, and do not leave uncommitted output sitting in it.
- **Never run two builds, test suites, or pipeline invocations in one
  checkout at the same time.** Concurrent writers against one working
  directory is the root cause of all three 2026-11-10 collisions, not just
  the branch one.
- **Never clear a dirty tree with `git checkout -- .` (or `git reset --hard`,
  `git clean -fd`) without stashing first.** Always `git stash -u` (the `-u`
  matters — untracked regenerated artifacts are exactly what got discarded
  on 2026-11-10) before doing anything that could discard working-tree state
  you did not create and cannot reconstruct. If you don't need the stash
  afterward, drop it explicitly once you've confirmed you don't — don't rely
  on a destructive command to do that pruning for you.
- **Both scheduled entrypoints enforce this mechanically**, not just by
  convention: `scripts/run_pipeline_task.ps1`'s `Invoke-CheckoutSafetyGuard`
  and `schedule_weekly_offseason.bat`'s equivalent inline guard each
  `git stash -u` any dirty state, check out `main`, then re-verify (not just
  assume) that HEAD landed on `main` with a clean tree — and exit non-zero
  with a `[Checkout Guard]`-tagged log line in `logs/scheduled_runs.log`
  *before running anything else* if that verification fails. Neither guard
  silently discards work or silently runs from the wrong branch; both either
  land clean or refuse to proceed.
