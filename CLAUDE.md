# CLAUDE.md — NBA Analytics agent-facing operating rules

This file holds operating rules for any agent (or human) working in this
repo's checkouts. It is the canonical place for rules like the one below;
add further agent-facing rules here rather than scattering them across
HANDOFF.md or script comments.

## Checkout isolation (front-office issue #105)

**The primary checkout (`front-office/NBA Analytics`) is shared with the
Windows Task Scheduler job that runs this repo's daily pipeline and publish
gate (`schedule_daily.bat`, registered as "NBA Analytics Daily Pipeline").**
Treat it accordingly:

1. **Feature work happens in a worktree, never in the primary checkout.**
   Create a `git worktree` under `.nba-worktrees/<slug>` (see this
   repository's existing worktrees for the pattern) for any branch work,
   subagent task, or exploratory change. Do not `git checkout` a feature
   branch in the primary checkout.
2. **The primary checkout stays on `main` and clean.** If you ever find
   yourself in the primary checkout (path ends in `...front-office\NBA
   Analytics`, no worktree suffix) on a non-`main` branch, or with
   uncommitted changes that aren't about to be committed immediately,
   that is a bug to fix before doing anything else — not a state to work
   around.
3. **Never run two builds or test suites in the same checkout at once.**
   `web/.next` and R's `cache/` are shared, mutable state; a second
   concurrent `npm run build` / test run in the same checkout will corrupt
   or race the first one's output. Use a worktree (or at minimum, confirm
   nothing else is running there) before starting a build or test run.
4. **Never clear a dirty tree with `git checkout -- .` (or `git reset
   --hard`, `git clean -fd`) without stashing first.** If a checkout is
   unexpectedly dirty, run `git stash -u` (never drop it) before doing
   anything else, and investigate why it was dirty rather than assuming
   it's safe to discard. This is literally the failure mode from issue
   #105: a dirty tree full of regenerated, uncommitted JSON output was
   wiped with a bare `git checkout -- .`, discarding real pipeline output
   with no way to recover it.

### Why this exists

On 2026-11-10, the NFL sibling repo's scheduled pipeline ran successfully
in its primary checkout while a subagent had left that same checkout on
branch `chore/nfl-week9-visual-media`. The 08:00 publish gate correctly
refused to publish (assertion E: `HEAD=chore/nfl-week9-visual-media
expected=main`) — but at 08:03 a different agent cleared the dirty tree
with `git checkout -- .` before merging, discarding 8 regenerated JSON
files and a cache file. Published data stayed ~30 hours stale until a
manual re-run. Two more same-day collisions in sibling repos traced to the
same root cause: one working directory, several concurrent writers (a
session switching branches twice mid-merge; two test/build runs colliding
in one `web/.next` directory). The exposure is identical for every
scheduled task in this family (NBA, NFL, WNBA, MLB, Front Office Refresh
Slot B/C) because every one of them runs in the same directory interactive
sessions and agents also use.

`schedule_daily.bat` now enforces rule 4 mechanically for the scheduled
pipeline itself: before running anything, it `git stash -u`s a dirty tree
and checks out `main`, then verifies HEAD is `main` and the tree is clean
— failing loudly (non-zero exit, `[ERROR]` lines in
`pipeline_execution.log`) and refusing to run the pipeline if it can't
land there cleanly. See the "Checkout-safety guard" block in
`schedule_daily.bat` (just after `cd /d "%PROJECT_DIR%"`) for the exact
implementation. That guard protects the scheduled task; rules 1-3 above
are what keep the primary checkout in a state the guard can actually
recover from, and what protects interactive/agent sessions from each
other and from the scheduled task.
