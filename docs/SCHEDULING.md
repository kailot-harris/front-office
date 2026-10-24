# Scheduling the NFL Analytics daily run and redeploy

Operator reference for the two Windows Task Scheduler jobs that keep the public site
current. Written for GitHub issue #39 ("Phase 3: trigger the daily 09:00 redeploy").

> **Read this first:** the publish task ships in **dry-run mode on purpose** and must
> stay that way until issue #42 is proven. See
> [Do not enable `--publish` until #42 is proven](#do-not-enable---publish-until-42-is-proven).

---

## The two tasks

Two tasks, not one (#39 scope item 3). Keeping them separate means a long pipeline
overrun cannot silently delay the deploy, and a publish can be re-run without
re-running the whole pipeline.

| | Pipeline task | Publish task |
|---|---|---|
| Task name | `NFL_analytics_task_01` | `NFL_analytics_publish_01` |
| Trigger | Daily **05:15** | Daily **09:00** |
| Action | `schedule_daily.bat` | `schedule_publish.bat <mode>` |
| What it does | Runs the full `run_full_pipeline.R` DAG | Runs the `tools/publish_web.R` freshness gate, and publishes only if every assertion passes |
| Working directory | project root (set explicitly) | project root (set explicitly) |
| `StartWhenAvailable` | yes | yes |
| Wake timer (`WakeToRun`) | yes | yes |
| Exit code | 0 all-clear, 1 if any step failed | 0 gate passed, 1 gate blocked, 2 bad mode argument |

Register or update both with:

```powershell
# Always dry-run first: prints both task configurations, applies nothing.
powershell -NoProfile -File tools\register_scheduled_tasks.ps1 -DryRun

# Then apply (needs an elevated session):
powershell -NoProfile -File tools\register_scheduled_tasks.ps1
```

`tools/register_scheduled_tasks.ps1` is **idempotent** — it updates a task of the same
name in place rather than creating a duplicate, so it is safe to re-run after changing
a trigger time. It refuses to register a task whose `.bat` does not exist.

Why the wrappers set their own working directory: the original task invoked
`Rscript.exe` directly with an **empty** `WorkingDirectory`, which only worked because
`config.R` hardcodes `PROJECT_DIR` (issue #43). Both wrappers now `cd /d` explicitly and
the registration script sets `WorkingDirectory`, so neither depends on that.

---

## Mode flags

`schedule_publish.bat` takes one optional argument. **No argument means dry run.**

| Mode | Passes to `publish_web.R` | Effect |
|---|---|---|
| *(none)* / `dryrun` | *(nothing)* | **Default.** Runs every assertion, publishes nothing. |
| `strict` | `--strict-warnings` | Dry run, but exporter `[WARN]` lines are fatal. |
| `publish` | `--publish` | Live publish: commit, push `NFL_analytics`, subtree-pull into the aggregator, push `front-office` main. |
| `publish-strict` | `--publish --strict-warnings` | Live publish with warnings fatal. |

An unrecognised mode exits **2** and runs nothing, rather than silently falling back.

Run a publish by hand any time (it does not disturb the schedule):

```bat
schedule_publish.bat            :: dry run
schedule_publish.bat publish    :: live  -- only after #42 is proven
```

---

## Reading the log

Both wrappers append to **`logs/pipeline_execution.log`** under the project root. They
share one file deliberately: the 05:15 run and the 09:00 publish are two halves of one
daily story, and reading them interleaved is how you actually diagnose "why is the site
stale".

This is *not* the same file as `logs/nfl_pipeline.log`, which the R code writes via
`logging_utils.R`. The wrapper log additionally captures stdout/stderr from an R crash
that never reaches the R logger.

What to look for:

- `NFL PIPELINE RUN COMPLETED SUCCESSFULLY` vs `... COMPLETED WITH ERRORS` — the banner
  reflects a real `PIPELINE_FAILED` flag. (The NBA wrapper prints success
  unconditionally; the WNBA repo hit exactly that on 2026-10-01 when an renv breakage
  hard-failed two steps and the log still claimed success. This wrapper does not.)
- `[ERROR] Step 1/1 - run_full_pipeline.R - FAILED with exit code N`.
- `NFL WEB PUBLISH GATE BLOCKED` plus the `-- Assertions --` block above it. Every
  failing assertion is on a `[FAIL]` line with its id, name and summary; the offending
  file or value is in its detail lines.

> **A pipeline exit code of 0 does not mean the artifacts are good.** `run_stage()`
> deliberately swallows stage failures and the pipeline still exits 0 — the 2026-10-23
> 05:15 run exited 0 while logging a stale-output warning. That is the whole reason
> publishing is gated on artifact assertions (#38) instead of chained to a zero exit.

### Log rotation

`schedule_daily.bat` rotates **single-generation**: when
`logs/pipeline_execution.log` exceeds `LOG_MAX_BYTES` (5 MiB, matching the WNBA
wrapper) it is moved to `logs/pipeline_execution.log.old`, overwriting any previous
`.old`. There is no numbered series — this is an operational log for manual
troubleshooting, not an audit trail needing long retention. **If you need to keep a
log, copy it out**, or two rotations will discard it.

Rotation is owned by the 05:15 task only, so the 09:00 publish can never rotate away a
log the pipeline just wrote. Both the live log and the `.old` generation are gitignored.

---

## Timing: live by about 09:04

The 09:00 trigger is not when the site changes. Deploy latency is roughly **4 minutes**
after the push, so a 09:00 publish means the new site is live around **09:04**.

Budget accordingly: if someone needs fresh numbers by 09:00 sharp, move the publish
task earlier, not the deadline later.

`deploy.yml` lives only in the `front-office` aggregator, so **the final push must land
on `front-office` main** — pushing `NFL_analytics` alone triggers no deploy. It uses
`concurrency: group: pages` with `cancel-in-progress: true`, which is harmless today
because nothing else auto-pushes, but any additional auto-publishing repo must stagger
its schedule or it will cancel this deploy mid-flight (#41).

---

## Failure mode: the laptop is asleep at 09:00

**This is the most likely way the 09:00 redeploy silently does not happen.** It is a
scheduled task on one physical machine.

Mitigations already configured on both tasks:

- **`WakeToRun`** — Task Scheduler asks the machine to wake for the run. This works from
  sleep, but **not** from a full shutdown, and not if the OS or firmware power settings
  forbid wake timers.
- **`StartWhenAvailable`** — if the start was missed anyway (machine off, lid shut,
  travelling), the task runs **as soon as possible** afterwards instead of skipping the
  day. The deploy is then late rather than absent.

Neither helps if the machine stays off all day. Check `Get-ScheduledTaskInfo` for
`LastRunTime` / `LastTaskResult` when the site looks a day stale:

```powershell
Get-ScheduledTask NFL_analytics_task_01, NFL_analytics_publish_01 | Get-ScheduledTaskInfo
```

### Alternative: a GitHub Actions cron

The machine dependency can be removed entirely: have the 05:15 run commit and push its
artifacts, then let an Actions `schedule` cron in the aggregator deploy at 09:00. No
laptop needs to be awake.

**The cost is punctuality.** Actions cron routinely drifts **5–20 minutes** under load
(it is best-effort, not guaranteed), so "09:00" becomes approximate and the site could
go live anywhere from ~09:04 to ~09:25. Choose on which you care about more:

| | Task Scheduler (current) | Actions cron |
|---|---|---|
| Punctuality | Good — live ~09:04 | Drifts 5–20 min |
| Needs the laptop awake | **Yes** | No |
| Credential story | Unproven unattended (#42) | Uses `GITHUB_TOKEN` in-workflow |

This is a documented option, **not** currently implemented; #39 does not ask for the
workflow file and none has been added.

---

## Do not enable `--publish` until #42 is proven

Issue **#42 is open and blocks live publishing.** A push-capable credential exists on
this machine (gh CLI OS keyring, plus `credential.helper=manager` in both repos) — but
that only proves credentials work for an **interactive terminal session**.

Git Credential Manager normally stores credentials for the interactive user session. A
task configured "run whether logged on or not" runs in a **non-interactive session** and
can silently fail to reach GCM. The failure would surface as the 09:00 publish hanging
on an auth prompt, or failing with no obvious cause, **at a time nobody is watching.**

Therefore:

1. The publish task is registered in **`dryrun`** mode. Leave it there.
2. Let it run that way for a few days and read the gate's assertion output in the log.
   A dry run exercises everything except the push, so it is the cheap way to find
   artifact problems first.
3. **Prove #42 separately**: execute one real push *from a scheduled-task context* (not
   an interactive shell) to both `NFL_analytics` and `front-office`. If GCM turns out to
   be unreachable non-interactively, pick and document a remedy — a PAT in the task's
   environment, a dedicated credential store, or a different auth mechanism — rather
   than leaving it to chance.
4. **Only after #42 closes**, re-register the publish task in live mode:

   ```powershell
   powershell -NoProfile -File tools\register_scheduled_tasks.ps1 -PublishMode publish
   ```

   The script warns when you do this.

The honest status until then is "credentials exist for an interactive user", not
"credentials work unattended".

---

## Related issues

| Issue | Why it matters here |
|---|---|
| #38 | `tools/publish_web.R`, the freshness gate these wrappers call. |
| #39 | This work: the wrappers, the two tasks, the 09:00 redeploy. |
| #41 | Staggering schedules, because `deploy.yml` cancels in-progress Pages deploys. |
| #42 | **Blocks live publish.** Unattended push credential is unproven. |
| #43 | `config.R` hardcodes `PROJECT_DIR`; the wrappers set a working directory rather than relying on it. |

No secret, token or webhook URL appears in any scheduling file. `config.R`'s
`DISCORD_WEBHOOK` is read from the environment via `Sys.getenv()`, and any future
credential must follow the same pattern.
