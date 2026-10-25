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

`NFL_PROJECT_DIR` overrides the project root if set, which is how the wrappers can be
exercised from a git worktree without writing into the main checkout. The registered
tasks do not set it.

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

The **09:00** machine dependency can be removed: have the 05:15 run commit and push its
artifacts, then let an Actions `schedule` cron in the aggregator deploy at 09:00. No
laptop needs to be awake *at 09:00*.

Note what this does **not** remove: the 05:15 run still has to push, and it is a
scheduled task, so that push is still non-interactive and still gated on #42. See the
correction under "Recommended remedy, and why" below.

**The cost is punctuality.** Actions cron routinely drifts **5–20 minutes** under load
(it is best-effort, not guaranteed), so "09:00" becomes approximate and the site could
go live anywhere from ~09:04 to ~09:25. Choose on which you care about more:

| | Task Scheduler (current) | Actions cron |
|---|---|---|
| Punctuality | Good — live ~09:04 | Drifts 5–20 min |
| Needs the laptop awake at 09:00 | **Yes** | No |
| Needs an unattended local push | **Yes** (at 09:00) | **Yes** (at ~05:20) |
| Deploy-step credential | Local, unproven (#42) | In-workflow `GITHUB_TOKEN` |

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

## Issue #42: the unattended-push probe, and why it is still unproven

**Status as of 2026-10-25: NOT SETTLED — blocked on local elevation, not on a
credential.** Read this whole section before touching the publish task's mode. The
short version: the probe tooling is finished and verified as far as an unelevated
session can take it, but the one measurement that answers #42 — a real push from a
non-interactive scheduled-task session — could not be executed on this machine by an
unelevated agent, so the honest verdict is still "unknown": not "works", and not
"broken".

### The tooling

Two scripts, both committed, both on-demand only (neither adds nor changes a trigger,
so the daily schedule is untouched):

| Script | Role |
|---|---|
| `tools/test_unattended_push.ps1` | The probe. Pushes the existing `HEAD` to a throwaway `refs/heads/cred-probe/<timestamp>-<pid>` in each repo, then deletes it. Creates no commit, writes nothing local, never touches `main`. Every git call is bounded by `-TimeoutSec` via `Start-Process`, so an auth prompt fails fast as exit 124 instead of hanging. Sets `GIT_TERMINAL_PROMPT=0` / `GCM_INTERACTIVE=never`. Never runs `git credential fill`, so no secret can reach the log. |
| `tools/register_credential_probe_task.ps1` | Registers two on-demand tasks differing in **exactly one** respect, the principal's `LogonType`: `NFL_analytics_credprobe_interactive` (`Interactive`) and `NFL_analytics_credprobe_unattended` (`S4U` — "run whether logged on or not", no stored password). |

**Why the pair matters.** Git Credential Manager stores credentials per interactive
user session. S4U runs in session 0 with no interactive desktop and can silently fail
to reach GCM. A single passing run proves nothing — only the *difference* between the
two logon types is evidence. The interactive task is the control; a pass there does not
close #42.

### What was actually run, 2026-10-25

All commands were run from the issue-42 worktree (`_worktrees/issue42`, branch
`wt/issue42-unattended-push`, HEAD `0c846cd`), with `-AggregatorDir` pointed at the
aggregator checkout on its normal path.

**1. Read-only dry run, interactive shell — PASSED for both repos.**

```
powershell -NoProfile -File tools\test_unattended_push.ps1 \
    -ProjectDir <worktree> -AggregatorDir <aggregator> -DryRun
```

Exit 0. Session context captured: `Environment.UserInteractive: True`,
`SESSIONNAME=Console`, process session id 1, and `GH_TOKEN` / `GITHUB_TOKEN` both
`(not set)`. `READ probe: git ls-remote --heads origin` returned `[OK]` for
`NFL_analytics` (`https://github.com/kailot-harris/NFL_analytics.git`) and for
`front-office` (`https://github.com/kailot-harris/front-office.git`). The WRITE probe
was skipped by design. **This establishes read auth from an interactive session only.
It does not bear on #42**, which asks about write auth in a *non-interactive* session.

**2. Task registration — the control registered; the S4U task was REFUSED.**

```
powershell -NoProfile -File tools\register_credential_probe_task.ps1 \
    -ProjectDir <worktree> -AggregatorDir <aggregator> -DryRun   # plan only, exit 0
powershell -NoProfile -File tools\register_credential_probe_task.ps1 \
    -ProjectDir <worktree> -AggregatorDir <aggregator>           # apply
```

Result: `[UPDATED] NFL_analytics_credprobe_interactive`, then

```
Register-ScheduledTask : Access is denied.
    + CategoryInfo : PermissionDenied: ... [Register-ScheduledTask], CimException
    + FullyQualifiedErrorId : HRESULT 0x80070005,Register-ScheduledTask
```

Cause, confirmed rather than assumed:

```
[Security.Principal.WindowsIdentity]::GetCurrent().Name          # KAILOT_HP\kailo
IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) # False
whoami /groups   # BUILTIN\Administrators -> "Group used for deny only"
```

The account **is** in `BUILTIN\Administrators`, but the running token is the filtered,
unelevated one, so that membership is deny-only. Registering an **S4U** principal
requires elevation; updating an `Interactive` task the same user already owns does not.
That asymmetry is exactly why one call succeeded and the other did not — it is a local
privilege limit, **not** evidence about the credential.

**3. Neither probe task was ever executed.** `Start-ScheduledTask` was also unavailable
to the agent session, so no scheduled-task run of the probe happened in either logon
context. `Get-ScheduledTaskInfo` for the control reported `LastTaskResult 267011`
(`SCHED_S_TASK_HAS_NOT_RUN`) throughout.

**4. Clean-up verified.** Because no WRITE probe ever ran, nothing was pushed:

```
git ls-remote --heads origin "refs/heads/cred-probe/*"   # empty, both repos
git ls-remote origin refs/heads/main   # NFL_analytics 843a27d5... (unchanged)
                                       # front-office  231ef7cf... (unchanged)
git -C <aggregator> status --porcelain  # empty
```

Both probe tasks were then unregistered via
`register_credential_probe_task.ps1 -Remove`, leaving the machine's scheduled-task set
as found. No commit was created in either repo, and no credential value was read,
logged or committed.

### What a future agent must do to finish this

The probe is ready; it needs a session that can register and start an S4U task. From an
**elevated** PowerShell on this machine:

```
powershell -NoProfile -File tools\register_credential_probe_task.ps1 -DryRun  # read the plan
powershell -NoProfile -File tools\register_credential_probe_task.ps1         # apply both

Start-ScheduledTask -TaskName NFL_analytics_credprobe_interactive   # control FIRST
Start-ScheduledTask -TaskName NFL_analytics_credprobe_unattended    # the real test

# Note the Get-ScheduledTask prefix: Get-ScheduledTaskInfo's -TaskName takes a single
# string, so passing the pair to it directly fails with a parameter-transformation error.
Get-ScheduledTask -TaskName NFL_analytics_credprobe_interactive, NFL_analytics_credprobe_unattended |
    Get-ScheduledTaskInfo | Select-Object TaskName, LastRunTime, LastTaskResult
Get-Content logs\credential_probe.log -Tail 80

powershell -NoProfile -File tools\register_credential_probe_task.ps1 -Remove  # clean up
```

Read the pair, not either run alone. In the unattended log, confirm
`Environment.UserInteractive: False` before trusting it as the non-interactive data
point — that line is the discriminator.

- **interactive PASS + unattended PASS** → credentials are reachable unattended. #42
  closes; record the residual risk below.
- **interactive PASS + unattended FAIL** → GCM is unreachable non-interactively, as #42
  predicts. Apply the recommended remedy.
- **interactive FAIL** → the problem is not logon type at all; fix the credential first.

If #42 does close green, the residual risk is real and worth writing on the issue: S4U
credential reachability depends on the user's DPAPI-protected store, so it can break
**without any code change** on a Windows password change, a credential-manager or
keyring reset, or a GCM upgrade that changes its store backend. A green probe is a
point-in-time result, not a permanent guarantee. The 09:00 publish should therefore
treat a push failure as an expected, alertable condition rather than an impossibility.

### Recommended remedy, and why

Of the three remedies #42 names, the recommendation for #39 is the **third: commit at
~05:20 and let a GitHub Actions `schedule` cron in the aggregator deploy**, rather than
pushing from Task Scheduler at all. See "Alternative: a GitHub Actions cron" above for
the already-documented trade-off.

Justification against the alternatives:

- **A PAT in the task's environment** — works, but puts a long-lived push-capable
  credential in a Task Scheduler action or a machine environment variable, readable by
  anything running as that user, and that is the one thing this repo's
  no-hardcoded-secrets convention exists to prevent. It also needs manual rotation, and
  a silently-expired PAT reproduces the original failure (a deploy that stops at a time
  nobody is watching) with an extra layer to debug. **Not recommended.** No PAT was
  created, requested or written anywhere during this work.
- **A dedicated credential store** — plausible, but it adds a component to maintain and
  still leaves the same class of fragility (a store that must be reachable from session
  0), so it trades a proven unknown for an unproven one.
- **Actions cron** — moves the *deploy* to GitHub's runners using the in-workflow
  `GITHUB_TOKEN`: no local credential for that step, no laptop awake at 09:00, no
  rotation. The cost is punctuality (cron drifts 5–20 minutes, so "09:00" becomes
  ~09:04–09:25).

  **Correction (2026-10-25): this does NOT remove the unattended-credential question,
  and an earlier draft of this section wrongly said it did.** The cron design still has
  the 05:15 pipeline run *commit and push* its artifacts (see "Alternative: a GitHub
  Actions cron" above) — and that run is `NFL_analytics_task_01`, a scheduled task, so
  the push happens in exactly the non-interactive session #42 is about. Cron relocates
  the unproven push from 09:00 to ~05:20; it does not eliminate it, and a silent auth
  failure at 05:20 is just as unwatched. **#42 therefore cannot be closed as obsolete by
  adopting cron.** The only designs that genuinely remove the local push credential are
  (a) running the pipeline itself in CI, so no local artifact ever needs pushing, or
  (b) accepting a PAT for the push step. Cron is still worth adopting on its own merits
  — fewer moving parts at deploy time, no 09:00 laptop dependency — but it must be
  paired with a settled answer for the 05:20 push.

This remedy is a **recommendation, not an implementation**: no workflow file has been
added, and #39 still owns that decision. Per the correction above, adopting cron does
*not* dispose of #42 — the 05:20 push still needs an answer, so the probe must either be
finished from an elevated session or the pipeline must move into CI. But do
**not** switch the publish task to `--publish` on the strength of the interactive dry
run above, which proves only that an interactive shell can read.

---

## Related issues

| Issue | Why it matters here |
|---|---|
| #38 | `tools/publish_web.R`, the freshness gate these wrappers call. |
| #39 | This work: the wrappers, the two tasks, the 09:00 redeploy. |
| #41 | Staggering schedules, because `deploy.yml` cancels in-progress Pages deploys. |
| #42 | **Blocks live publish.** Unattended push credential is still unproven — see "Issue #42: the unattended-push probe" above for the probe tooling, what was run on 2026-10-25, why it could not be finished without elevation, and the recommended remedy. |
| #43 | `config.R` hardcodes `PROJECT_DIR`; the wrappers set a working directory rather than relying on it. |

No secret, token or webhook URL appears in any scheduling file. `config.R`'s
`DISCORD_WEBHOOK` is read from the environment via `Sys.getenv()`, and any future
credential must follow the same pattern.
