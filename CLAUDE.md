# front-office (aggregator) — Working Notes

## Keep the main checkout on `main`

Scheduled refresh tasks (`tools/run_refresh_slot.ps1`) run from this repo's
primary checkout, so:

- Do feature work in a `git worktree`, not in the primary checkout.
- Leave the primary checkout on `main` with a clean tree.
- Never run two builds or test suites in the same checkout at once.
- Never clear a dirty tree with `git checkout -- .` or `git clean`. Stash it
  (`git stash -u`) instead.

`run_refresh_slot.ps1` enforces this with `Assert-ScheduledCheckoutSafety`,
which stashes (never discards) and fails loudly if it can't restore `main`.
Background and follow-ups: issue #105.
