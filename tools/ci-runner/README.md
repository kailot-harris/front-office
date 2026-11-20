# CI runner host lock

Two GitHub Actions runner job hooks that let only **one CI job run at a time**
on the self-hosted runner host, across all four sport-repo runner services
(MLB, NBA, NFL, WNBA). One job can use 3-4 GB of memory at peak, so two
browser-test jobs at once could exhaust the host. Workflow `concurrency`
groups cannot help here because they do not span repositories. (Issues #152
and #157, part of the plan in #151.)

| Script | Runner hook | What it does |
| --- | --- | --- |
| `job-started.sh` | `ACTIONS_RUNNER_HOOK_JOB_STARTED` | Enqueues in FIFO order and takes the host-wide lock, waiting until it is free. |
| `job-completed.sh` | `ACTIONS_RUNNER_HOOK_JOB_COMPLETED` | Releases the lock, but only if this job owns it. |

> **Never register a self-hosted runner against this repository.** This repo
> is public, so outside pull requests could run code on the host. The scripts
> live here only because this repo holds the shared operations tooling; the
> runners are registered against the sport repos.

## How it works

- The lock is a directory, created with `mkdir` (atomic), at
  `/var/lock/front-office-ci.lock` by default, followed by atomic `write_owner`
  (writes a temporary file and renames it to `owner`, cleaning up the temp file
  on any error so no stray `owner.tmp.*` files remain inside the lock). Using
  `mkdir` rather than `mv temp_dir "$LOCK_DIR"` is deliberate: POSIX `mv`
  nests a directory inside an existing target directory instead of failing
  atomically.
- Inside the lock, an `owner` file records the runner name, repository, run id,
  run attempt, job name, and start time. The owner identity comes from the
  runner-provided environment: `RUNNER_NAME`, `GITHUB_REPOSITORY`,
  `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT` and `GITHUB_JOB`. Unset values fall back
  to placeholders such as `unknown-runner`.
- **FIFO queue (`<lock>.queue`):** On entry (unless this job already holds the
  lock), `job-started.sh` registers a lexicographically sortable ticket in
  `FRONT_OFFICE_CI_LOCK_QUEUE_DIR` (`/var/lock/front-office-ci.lock.queue` by
  default), named `<ns_epoch>-<zero_padded_pid>-<unique>.ticket` (falling back
  to `%s000000000` if `date +%N` is unavailable). Each ticket stores `owner`,
  `created_epoch`, and `heartbeat_epoch`.
  - A `trap` on `EXIT`, `INT`, and `TERM` removes only this job's own ticket on
    exit or cancellation.
  - Every poll iteration refreshes `heartbeat_epoch` and purges stale tickets
    whose heartbeat age reaches `FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS`
    (recovering if a waiting process is killed with `SIGKILL` or a host crash).
  - Only the job holding the oldest live ticket in the queue attempts `mkdir` or
    stale-lock takeover. Because newcomers also enqueue first, a job arriving
    right after a lock release cannot jump ahead of an earlier waiter that is
    still sleeping between poll ticks. Once `mkdir` succeeds, the job deletes
    its ticket immediately.
- If the lock is held (or an earlier ticket is ahead in the queue),
  `job-started.sh` polls (every 10 s by default) and logs who holds the lock,
  how long they have held it, its queue position when waiting behind another
  ticket, and how long this job has waited.
- When it gets the lock it logs the total wait, e.g.
  `[ci-lock] Acquired host CI lock after waiting 412s (6m 52s).` The runner
  shows hook output as its own step in the job log.
- **Stale-lock recovery and post-rename verification invariant:**
  - A labelled lock older than 60 minutes (`FRONT_OFFICE_CI_LOCK_STALE_SECONDS`,
    default `3600` — the longest CI `timeout-minutes`, 45, plus a margin) is
    assumed to belong to a runner that crashed mid-job.
  - **Unlabelled-lock grace period:** if `$LOCK_DIR` exists with no `owner` file
    (for example, a runner crashed between `mkdir` and `write_owner`), its age
    is measured from the lock directory's mtime and treated as stale once it
    reaches `FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS` (default `60`),
    recovering within a minute rather than waiting 3600 s while still giving a
    live holder plenty of time to finish writing `owner`.
  - **Closing the double-takeover race (`take_over_stale`):** Before moving a
    stale lock aside, the head waiter re-checks `describe_holder` and atomically
    renames `$LOCK_DIR` to `$grave`. Between that pre-check and `mv`, another
    waiter (or recovering process) could finish taking over and create a fresh
    `$LOCK_DIR` under a new owner, causing `mv` to move the *healthy new lock*
    to `$grave`. To make takeover safe, `take_over_stale` **must inspect
    `$grave/owner` immediately after `mv`**: it proceeds with `rm -rf "$grave"`
    only when the owner matches the expected `$holder` (or `[ ! -f "$grave/owner" ]`
    when `$holder` was `"unknown (owner file not written yet)"`). On any mismatch,
    it restores `$grave` back to `$LOCK_DIR` (if `$LOCK_DIR` does not already
    exist), logs a warning, and returns `0` **without** deleting `$grave`.
- `job-completed.sh` removes the lock only when the `owner` file matches the
  current job. If the lock is gone or belongs to another job, it logs that and
  leaves it alone.
- A hook that exits non-zero fails the job, so neither script does that for an
  ordinary wait, an aborted stale takeover, a lock that is already gone, or a
  lock owned by another job. The only non-zero exit is from `job-started.sh`
  when the lock parent directory or queue directory is missing or not writable,
  or when an invalid timing override is supplied.

## Wiring up the four runner services

Copy the two scripts to a location every runner service account can read and
execute, for example `/opt/actions-runner/hooks/`, and make them executable:

```sh
sudo install -m 0755 job-started.sh job-completed.sh /opt/actions-runner/hooks/
```

When upgrading an existing host after merging hook changes, re-install both
scripts to `/opt/actions-runner/hooks/` and restart all four runner services
while idle (see `docs/ci-runner-host.md` §7).

Then add the same two lines to the `.env` file in **each** runner's install
directory (for example `/opt/actions-runner/<runner-dir>/.env`) and restart
that runner service:

```sh
ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hooks/job-completed.sh
```

All four services must point at the same scripts and use the same lock and
queue paths. The runner service accounts must be able to create and remove
directories and ticket files in both the lock's parent directory (`/var/lock` by
default) and `FRONT_OFFICE_CI_LOCK_QUEUE_DIR` (`/var/lock/front-office-ci.lock.queue`
by default); if they cannot, set `FRONT_OFFICE_CI_LOCK_DIR` (and, if needed,
`FRONT_OFFICE_CI_LOCK_QUEUE_DIR`) to paths they can write.

On many Linux hosts `/var/lock` is a sticky directory (mode `1777`), where only
the account that created an entry can remove it. That is fine if all four
runner services run as the same account. If they run as different accounts,
stale-lock takeover or stale-ticket cleanup of another account's entry will fail
(the hook logs a warning and keeps waiting), so either run them as one account
or point `FRONT_OFFICE_CI_LOCK_DIR` (and `FRONT_OFFICE_CI_LOCK_QUEUE_DIR`) at a
directory owned by a shared group without the sticky bit (for example mode `2770`).

## Environment overrides

Set these in each runner's `.env` file (identically on all four) or in the
environment of the tests:

| Variable | Default | Meaning |
| --- | --- | --- |
| `FRONT_OFFICE_CI_LOCK_DIR` | `/var/lock/front-office-ci.lock` | Lock directory. |
| `FRONT_OFFICE_CI_LOCK_QUEUE_DIR` | `${FRONT_OFFICE_CI_LOCK_DIR}.queue` (`/var/lock/front-office-ci.lock.queue`) | Directory holding FIFO queue tickets. |
| `FRONT_OFFICE_CI_LOCK_POLL_SECONDS` | `10` | Seconds between attempts while waiting. |
| `FRONT_OFFICE_CI_LOCK_STALE_SECONDS` | `3600` | Age after which a labelled lock is treated as stale and taken over. |
| `FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS` | `60` | Age (by lock directory mtime) after which an unlabelled lock (no `owner` file) is treated as stale. |
| `FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS` | `max(60, POLL_SECONDS * 6)`, clamped `<= STALE_SECONDS` | Heartbeat age after which an inactive waiter's queue ticket is purged (e.g. after `SIGKILL`). |

If any workflow's `timeout-minutes` is raised above 45, raise
`FRONT_OFFICE_CI_LOCK_STALE_SECONDS` so it stays above the longest timeout
plus a margin; otherwise a slow but healthy job could have its lock taken.

## Wait time counts against `timeout-minutes`

The job-started hook runs inside the job, so **time spent waiting for the lock
counts against the job's `timeout-minutes`**. A job that waits too long is
cancelled by its own timeout before its steps start.

**Worst case (four queued jobs):** if four jobs are queued at once, the fourth
can wait for three full jobs to finish before its own run starts. With the
45-minute maximum timeout that is up to 3 x 45 = **135 minutes of waiting**,
followed by its own run. FIFO queueing ensures the earliest waiter runs next
rather than being starved by newly arriving jobs. Still, either give
`timeout-minutes` enough headroom to cover the queue (wait plus the job's own
run time), or accept that a job at the back of a full queue may time out and
need a re-run.

## Tests

Plain bash, no `bats` needed. They use a temporary directory and short
intervals, never `/var/lock`, and run under Linux and Git Bash on Windows:

```sh
bash tools/ci-runner/tests/run_tests.sh
```

Covered: a second simulated job waits until the first releases the lock (and
logs its wait time), stale-lock takeover, a fresh lock is not taken over (and
`SIGTERM` removes the stopped waiter's ticket), the completed hook leaves
another job's lock alone, the completed hook with no lock, fallback identity
when runner variables are unset, strict FIFO queueing across multiple waiters
(including preventing newcomers from jumping ahead while an earlier waiter
sleeps), stale-ticket eviction after `SIGKILL` past `TICKET_STALE_SECONDS`
(plus default threshold scaling/clamping), unlabelled lock recovery within
`UNLABELLED_GRACE_SECONDS` (plus `write_owner` temp-file cleanup on error), and
double-takeover post-rename owner mismatch detection and lock restoration. Every
hook call that should succeed is checked for exit status 0.
