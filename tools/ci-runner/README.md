# CI runner host lock

Two GitHub Actions runner job hooks that let only **one CI job run at a time**
on the self-hosted runner host, across all four sport-repo runner services
(MLB, NBA, NFL, WNBA). One job can use 3-4 GB of memory at peak, so two
browser-test jobs at once could exhaust the host. Workflow `concurrency`
groups cannot help here because they do not span repositories. (Issue #152,
part of the plan in #151.)

| Script | Runner hook | What it does |
| --- | --- | --- |
| `job-started.sh` | `ACTIONS_RUNNER_HOOK_JOB_STARTED` | Takes the host-wide lock, waiting until it is free. |
| `job-completed.sh` | `ACTIONS_RUNNER_HOOK_JOB_COMPLETED` | Releases the lock, but only if this job owns it. |

> **Never register a self-hosted runner against this repository.** This repo
> is public, so outside pull requests could run code on the host. The scripts
> live here only because this repo holds the shared operations tooling; the
> runners are registered against the sport repos.

## How it works

- The lock is a directory, created with `mkdir` (atomic), at
  `/var/lock/front-office-ci.lock` by default. Inside it, an `owner` file
  records the runner name, repository, run id, run attempt, job name and the
  start time.
- The owner identity comes from the runner-provided environment:
  `RUNNER_NAME`, `GITHUB_REPOSITORY`, `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT`
  and `GITHUB_JOB`. Unset values fall back to placeholders such as
  `unknown-runner`.
- If the lock is held, `job-started.sh` polls (every 10 s by default) and logs
  who holds it, how long they have held it, and how long this job has waited.
- When it gets the lock it logs the total wait, e.g.
  `[ci-lock] Acquired host CI lock after waiting 412s (6m 52s).` The runner
  shows hook output as its own step in the job log.
- **Stale-lock recovery:** a lock older than 60 minutes (the longest CI
  `timeout-minutes`, 45, plus a margin) is assumed to belong to a runner that
  crashed mid-job. The waiting hook removes it, logs that it did, and takes
  the lock.
- `job-completed.sh` removes the lock only when the `owner` file matches the
  current job. If the lock is gone or belongs to another job, it logs that and
  leaves it alone.
- A hook that exits non-zero fails the job, so neither script does that for an
  ordinary wait, a lock that is already gone, or a lock owned by another job.
  The only non-zero exit is from `job-started.sh` when the lock's parent
  directory is missing or not writable, since the lock could then never be
  taken.

## Wiring up the four runner services

Copy the two scripts to a location every runner service account can read and
execute, for example `/opt/actions-runner/hooks/`, and make them executable:

```sh
sudo install -m 0755 job-started.sh job-completed.sh /opt/actions-runner/hooks/
```

Then add the same two lines to the `.env` file in **each** runner's install
directory (for example `/opt/actions-runner/<runner-dir>/.env`) and restart
that runner service:

```sh
ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hooks/job-completed.sh
```

All four services must point at the same scripts and use the same lock path.
The runner service accounts must be able to create and remove directories in
the lock's parent directory (`/var/lock` by default); if they cannot, set
`FRONT_OFFICE_CI_LOCK_DIR` to a path they can write.

## Environment overrides

Set these in each runner's `.env` file (identically on all four) or in the
environment of the tests:

| Variable | Default | Meaning |
| --- | --- | --- |
| `FRONT_OFFICE_CI_LOCK_DIR` | `/var/lock/front-office-ci.lock` | Lock directory. |
| `FRONT_OFFICE_CI_LOCK_POLL_SECONDS` | `10` | Seconds between attempts while waiting. |
| `FRONT_OFFICE_CI_LOCK_STALE_SECONDS` | `3600` | Age after which a lock is treated as stale and taken over. |

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
followed by its own run. Either give `timeout-minutes` enough headroom to
cover the queue (wait plus the job's own run time), or accept that a job at
the back of a full queue may time out and need a re-run.

## Tests

Plain bash, no `bats` needed. They use a temporary directory and short
intervals, never `/var/lock`, and run under Linux and Git Bash on Windows:

```sh
bash tools/ci-runner/tests/run_tests.sh
```

Covered: a second simulated job waits until the first releases the lock (and
logs its wait time), stale-lock takeover, a fresh lock is not taken over, the
completed hook leaves another job's lock alone, the completed hook with no
lock, and the fallback identity when runner variables are unset. Every hook
call that should succeed is checked for exit status 0.
