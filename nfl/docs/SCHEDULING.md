# Scheduling the NFL Analytics daily run and redeploy

Operator reference for the two Windows Task Scheduler jobs that keep the public site
current. Written for GitHub issue #39 ("Phase 3: trigger the daily 09:00 redeploy").

> **Read this first:** issue #42 is **settled green as of 2026-10-25** — a real push
> from a genuine session-0, non-interactive scheduled task succeeded for both repos. The
> publish task may now be registered in live mode. See
> [Issue #42: settled](#issue-42-the-unattended-push-probe-settled-green-2026-10-25).

---

## The two tasks

**Both are registered and live as of 2026-10-25.** Verified on the machine:

| Task | LogonType | RunLevel | Trigger | Action |
|---|---|---|---|---|
| `NFL_analytics_task_01` | `S4U` | Limited | 05:15 daily | `schedule_daily.bat` |
| `NFL_analytics_publish_01` | `S4U` | Limited | 09:00 daily | `schedule_publish.bat dryrun` |

Both carry `StartWhenAvailable`, `WakeToRun`, `MultipleInstances: IgnoreNew` and a 2-hour
execution limit. The publish task is in **`dryrun`** mode on purpose — not because
anything blocks it (#42 is settled), but so the freshness gate's assertions get exercised
against real artifacts for a few days before a push happens. Its first run is 09:00 on
2026-10-26.

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
| `LogonType` | `S4U` | `S4U` |
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

### Why `S4U`, and why it is set explicitly

`Register-ScheduledTask` with no `-Principal` silently defaults to **`LogonType
Interactive`** — "run only when the user is logged on." Both tasks were registered that
way on 2026-10-25 before this was caught, which quietly put a login dependency back into
a job whose whole point is running unattended: a logged-off machine, or a restart nobody
logs back into, would skip the 09:00 deploy with **no error at all**, at a time nobody
is watching. That is the exact failure mode issue #42 exists to prevent, arriving by a
different route.

The registration script therefore sets the principal explicitly:

```powershell
New-ScheduledTaskPrincipal -UserId <current user> -LogonType S4U -RunLevel Limited
```

`S4U` ("run whether logged on or not", no stored password) removes the login dependency.
It is safe here **because #42 proved it on this machine**: a real push from a genuine
session-0 S4U task succeeded for both repos with `GH_TOKEN`/`GITHUB_TOKEN` unset, so Git
Credential Manager is reachable from session 0. Had that probe come back red, S4U would
not have been an option and the login dependency would have been the lesser evil.

`RunLevel Limited`, not `Highest`: these tasks run R and git, neither of which needs
elevation. *Registering* them needs an elevated session; *running* them does not.

Note the asymmetry when re-registering: updating an existing task you own needs no
elevation, but applying an S4U principal does. If `-DryRun` shows `LogonType: S4U` and
the applied task reports `Interactive`, you ran it unelevated.

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
| `publish` | `--publish` | Live publish: commit and push `NFL_analytics` only. The deploy is the aggregator's `sync-sports.yml`. |
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
on `front-office` main** — pushing `NFL_analytics` alone triggers no deploy.

**Since 2026-10-26, `publish_web.R` no longer makes that final push.** It used to
subtree-pull into a local aggregator checkout and push `front-office` main itself, which
duplicated the aggregator's own `sync-sports.yml`; two mechanisms pushing one branch meant
whichever ran second hit a non-fast-forward. `sync-sports.yml` is now the only one, because
it does not need this workstation awake. So a `--publish` run makes the artifacts
*available*; the site changes when `sync-sports.yml` next runs or is dispatched.

`publish_web.R` gained **assertion E** in the same change: `HEAD` must be on the branch
`sync-sports.yml` subtree-pulls (`main`). Without it, a `--publish` from a feature branch
pushed that branch, reported success, and left the site untouched — the gate's own
silent-no-op.

`deploy.yml` uses `concurrency: group: pages` with `cancel-in-progress: true`, which is
harmless today because nothing else auto-pushes, but any additional auto-publishing repo
must stagger its schedule or it will cancel this deploy mid-flight (#41).

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
| Deploy-step credential | Local GCM — **proven** unattended (#42) | In-workflow `GITHUB_TOKEN` |

Since #42 came back green, the credential row is no longer a reason to prefer cron: the
local unattended push works. The choice is now purely punctuality (Task Scheduler) vs.
no-laptop-dependency (cron).

This is a documented option, **not** currently implemented; #39 does not ask for the
workflow file and none has been added.

---

## Enabling `--publish` (unblocked 2026-10-25)

Issue **#42 is settled green** — see
[Issue #42](#issue-42-the-unattended-push-probe--settled-green-2026-10-25). A real push
from a session-0, non-interactive scheduled task succeeded for both `NFL_analytics` and
`front-office`, so the credential story that previously blocked live publishing is
proven, not assumed.

The publish task still ships in **`dryrun`** mode by default, and the recommended order
is unchanged:

1. Let the task run in `dryrun` for a few days first and read the gate's assertion
   output in the log. A dry run exercises everything except the push, so it remains the
   cheap way to find *artifact* problems — which are a separate failure class from the
   credential question #42 answered.
2. Then re-register in live mode:

   ```powershell
   powershell -NoProfile -File tools\register_scheduled_tasks.ps1 -PublishMode publish
   ```

   The script warns when you do this.

**The residual risk is real and does not go away with a green probe.** S4U credential
reachability depends on the user's DPAPI-protected store, so it can break **with no code
change** on a Windows password change, a credential-manager or keyring reset, or a GCM
upgrade that changes its store backend. The probe result is point-in-time. Treat a push
failure at publish time as an expected, alertable condition rather than an
impossibility — that is what issue #40 (deploy observability) is for.

---

## Issue #42: the unattended-push probe — SETTLED GREEN (2026-10-25)

**Status: SETTLED. Credentials ARE reachable from a non-interactive scheduled-task
session, for both repos.** The probe pair was run from an elevated PowerShell at
14:58 on 2026-10-25 and both tasks exited 0.

The measurement that settles it, from `logs/credential_probe.log` (the unattended run,
PID 11140):

```
    Environment.UserInteractive: False
    SESSIONNAME                :
    Process session id         : 0
    => NON-INTERACTIVE session. This is the context #42 is about.
    GH_TOKEN                   : (not set)
    GITHUB_TOKEN               : (not set)
...
    NFL_analytics   PUSH OK
    front-office    PUSH OK
```

Why this is the real thing and not a disguised interactive run: `UserInteractive: False`
with `Process session id: 0` and an empty `SESSIONNAME` is the signature of a session-0
"run whether logged on or not" task — the interactive control run 31 seconds earlier
logged `session id: 1` for contrast. Both `GH_TOKEN` and `GITHUB_TOKEN` were unset, so
authentication went through Git Credential Manager, not an ambient token — which is
precisely the mechanism #42 doubted would be reachable from session 0.

Full results, both logon types:

| Task | LogonType | LastTaskResult | NFL_analytics | front-office |
|---|---|---|---|---|
| `NFL_analytics_credprobe_interactive` | Interactive (control) | 0 | READ + WRITE + CLEANUP OK | READ + WRITE + CLEANUP OK |
| `NFL_analytics_credprobe_unattended` | **S4U (session 0)** | 0 | **READ + WRITE + CLEANUP OK** | **READ + WRITE + CLEANUP OK** |

That is the `interactive PASS + unattended PASS` case in the interpretation table below.
Cleanup verified independently afterwards: `git ls-remote --heads origin
"refs/heads/cred-probe/*"` is empty in both repos, and both `main` refs are unchanged
(`843a27d` NFL_analytics, `231ef7c` front-office), so the probe left no trace.

**The earlier blocked attempt is still worth knowing about.** On the first run, an
unelevated agent session could not register the S4U principal at all —
`Register-ScheduledTask` failed with `0x80070005 Access is denied`, because the account
is in `BUILTIN\Administrators` only as a *deny-only* SID on a filtered token. S4U
registration needs real elevation, and UAC needs a desktop, so this probe cannot be
completed by a background agent. Run it from an elevated PowerShell yourself.

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

### How to re-run the probe

This is the sequence that produced the green result above, and the one to re-run if the
residual risk ever fires (password change, keyring reset, GCM store-backend change) and
you need to re-confirm the credential. It needs a session that can register and start an
S4U task, so run it from an **elevated** PowerShell on this machine:

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

### Remedies considered while #42 was open — now moot

**None of the three remedies below is needed.** They were weighed on the assumption that
the unattended push might be broken; it is not, so this subsection is kept only as a
record of the reasoning (and so the options are already scoped if the residual risk ever
fires and the credential stops working).

For the record, the recommendation while #42 was open was the third option — commit at
~05:20 and let a GitHub Actions `schedule` cron deploy. **That is now an architecture
choice, not a remedy**: with the local push proven, cron buys only "no laptop awake at
09:00" and costs 5–20 minutes of punctuality. See "Alternative: a GitHub Actions cron"
above.

Justification against the alternatives, as assessed:

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

No workflow file has been added and #39 still owns the Task-Scheduler-vs-cron decision.
Note for whoever makes it: adopting cron would *not* have disposed of #42 even while it
was open, because the ~05:20 push is itself a scheduled-task push — the correction above
explains why. That no longer matters for unblocking, but it is the kind of reasoning
error worth not repeating.

---

## Related issues

| Issue | Why it matters here |
|---|---|
| #38 | `tools/publish_web.R`, the freshness gate these wrappers call. |
| #39 | This work: the wrappers, the two tasks, the 09:00 redeploy. |
| #41 | Staggering schedules, because `deploy.yml` cancels in-progress Pages deploys. |
| #42 | **Settled green 2026-10-25, no longer blocking.** A real push from a session-0 non-interactive task succeeded for both repos — see "Issue #42: the unattended-push probe" above for the log evidence, the probe tooling, and the residual DPAPI risk that survives a green result. |
| #43 | `config.R` hardcodes `PROJECT_DIR`; the wrappers set a working directory rather than relying on it. |

No secret, token or webhook URL appears in any scheduling file. `config.R`'s
`DISCORD_WEBHOOK` is read from the environment via `Sys.getenv()`, and any future
credential must follow the same pattern.
