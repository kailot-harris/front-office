# front-office (aggregator) — Working Notes

## Scheduled checkouts stay on `main`

**Rule: feature work happens in a `git worktree`. The primary checkout
(this repo's own working directory, the one Task Scheduler's "Front Office
Refresh Slot B" / "Front Office Refresh Slot C" tasks run from — see
`tools/register_refresh_tasks.ps1` and `tools/run_refresh_slot.ps1`) stays on
`main` and clean. Never run two builds or test suites in the same checkout at
once. Never clear a dirty tree with `git checkout -- .` (or `git clean`)
without stashing (`git stash -u`) first.**

Why this is written down (front-office issue #105): on 2026-11-10,
`NFL_analytics_task_01` (a sibling repo's 04:15 scheduled pipeline) ran
successfully in a shared checkout, but a subagent had left that same checkout
on branch `chore/nfl-week9-visual-media`. The 08:00 publish gate correctly
refused (`assertion E FAILED ... HEAD=chore/nfl-week9-visual-media
expected=main`), but at 08:03 a different agent "fixed" the dirty tree with
`git checkout -- .` before merging — discarding 8 regenerated JSON files and a
cache file instead of stashing them. Published data stayed stale for ~30
hours until a manual re-run. The same day, two more collisions traced to the
same root cause (one working directory, several writers): a second session
switching branches twice mid-merge, and two test/build runs colliding in one
`web/.next` directory (a false "Production build" failure plus 7-8 Playwright
timeouts).

The exposure is generic to every scheduled task that runs from a checkout
interactive sessions and agents also use for feature work — in this repo,
that is `tools/run_refresh_slot.ps1` (Slot B / Slot C), which is dispatched
with `-WorkingDirectory` pointed at this repo's root.

**Mitigation in this repo:** `run_refresh_slot.ps1` now runs
`Assert-ScheduledCheckoutSafety` as the first step of `Invoke-RefreshSlot`,
before dispatching anything. That function:
1. Checks whether the checkout is on `main` and clean; if so, it's a no-op.
2. Otherwise, if the tree is dirty, runs `git stash push -u` — never
   `git checkout -- .` / `git clean`, which discard rather than preserve.
3. Runs `git checkout main`.
4. Re-verifies `HEAD` is actually `main` and the tree is actually clean
   (does not trust exit codes alone — the original incident's publish gate
   *did* assert correctly; it was the manual cleanup afterward that bypassed
   it).
5. On any failure in steps 2–4, **throws** with a `CHECKOUT GUARD FAILED:`
   message and leaves the checkout exactly as it found it (stash, if any, is
   left in `git stash list` — nothing is discarded). An uncaught throw from
   `-File` exits non-zero, so Task Scheduler records the failure instead of a
   silently-green run.

If this ever needs to go further (dedicated worktree pinned to `main`, e.g.
`<repo>/.sched`, wired in the same way `register_refresh_tasks.ps1` already
derives `$REPO_DIR` from the script's own location), that is the next step up
— but it is not implemented here, since `-WorkingDirectory` for the existing
scheduled tasks already points at this single shared checkout and changing
that is a bigger change than the guard above.

**Out of scope here on purpose:** this does not add a build/test lock file
around `web/.next` or any pipeline build step — see front-office issue #105
for that follow-up; this doc and `run_refresh_slot.ps1`'s guard cover only the
checkout-branch/dirty-tree hazard, not concurrent builds in one `.next` dir.
