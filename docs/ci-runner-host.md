# CI runner host runbook

How to build, run and maintain the self-hosted GitHub Actions runner host for
the four private sport repos (MLB-Analytics, NBA_analytics, NFL_analytics,
WNBA_analytics). Part of the plan in #151; host setup is #153, the job lock
is #152, cutover and measurements are #154.

> **Rule: never register a self-hosted runner on this repository.**
> front-office is public, so a pull request from anyone could run code on the
> host. Runners are registered only on the four private sport repos. This
> repo holds the runbook and the lock hooks because it holds the shared
> operations tooling, nothing more.

Placeholders used below: `<user>` is the Linux user that owns the runners,
`<host>` is a short name for the machine, `<sport>` is one of `mlb`, `nba`,
`nfl`, `wnba`. Do not commit real machine names, user names, IP addresses or
registration tokens to this file.

## Overview

- A Windows desktop that is almost always on runs Ubuntu under WSL2, capped
  at 8 GB of memory.
- Inside Ubuntu, four runner services run as `<user>`, one per sport repo,
  because a personal account cannot share one runner between repositories.
- Job hooks from `tools/ci-runner/` allow only one CI job at a time across
  all four runners.
- Each sport repo picks its runner from the repository variable `CI_RUNNER`.
  Set to `self-hosted`, CI runs here; cleared, CI runs on GitHub-hosted
  runners.

| Item | Location |
| --- | --- |
| Runner installs | `~/runners/<sport>/actions-runner/` |
| Deployment clone of this repo (stays on `main`) | `~/runners/front-office/` |
| Installed lock hooks | `/opt/actions-runner/hooks/` |
| Lock directory (exists only while a job runs) | `/var/lock/front-office-ci.lock` |
| Lock queue directory (tickets while jobs wait) | `/var/lock/front-office-ci.lock.queue` |
| Runner logs | `~/runners/<sport>/actions-runner/_diag/` |
| Memory cap | `%UserProfile%\.wslconfig` on Windows |

## 1. WSL2 and Ubuntu

From an administrator PowerShell:

```powershell
wsl --install -d Ubuntu
```

Reboot, open Ubuntu, and create the Linux user (`<user>`).

## 2. Memory cap

Create `.wslconfig` in the Windows user profile folder:

```ini
[wsl2]
memory=8GB
swap=4GB
```

Then run `wsl --shutdown` from PowerShell and reopen Ubuntu. Check:

```sh
free -h
```

`Mem: total` should show about 7.8Gi and `Swap: total` 4.0Gi.

## 3. systemd

The runners are installed as systemd services, so systemd must be on.
`/etc/wsl.conf` should contain:

```ini
[boot]
systemd=true
```

This is the default on current Ubuntu images. Check with `ps -p 1 -o comm=`,
which should print `systemd`. If you edit the file, run `wsl --shutdown` and
reopen.

## 4. One-time packages

Install these once, so CI steps do not have to install them on every run:

```sh
sudo apt-get update
sudo apt-get install -y build-essential git curl r-base libmagick++-dev
# Node.js: install the version the sport repos' CI uses.
npx playwright install-deps chromium   # NFL and NBA browser tests
```

`libmagick++-dev` is needed by the NBA R tests. Add other R system libraries
here if an R job fails on a missing header.

## 5. sudo decision

Some CI steps call `sudo` (`apt-get install`, `playwright install
--with-deps`). Either the runner user can run `sudo` without a password, or
`sudo` stays locked and those steps skip when the package is already present.

The choice made for this host, and how it is configured, is recorded in the
owner's private host notes, not in this public repository. If it changes,
update those notes and, where needed, the `sudo` steps in each sport repo's CI.

## 6. Register the four runners

Repeat for each sport repo:

1. In the sport repo on GitHub: Settings → Actions → Runners → New
   self-hosted runner → Linux, x64. Keep the page open for the token.
2. In Ubuntu, download and unpack the runner into its own folder, using the
   download commands from that page:

   ```sh
   mkdir -p ~/runners/<sport>/actions-runner && cd ~/runners/<sport>/actions-runner
   # curl -o actions-runner-linux-x64-<version>.tar.gz -L <url from the page>
   tar xzf ./actions-runner-linux-x64-<version>.tar.gz
   ```

3. Configure it with the one-time token from the page. Name it
   `<host>-<sport>` and keep the default `self-hosted` label:

   ```sh
   ./config.sh --url https://github.com/kailot-harris/<SportRepo> \
     --token <token> --name <host>-<sport> --unattended
   ```

4. Install and start it as a service:

   ```sh
   sudo ./svc.sh install <user>
   sudo ./svc.sh start
   ```

Registration tokens expire after about an hour and are single use, so there is
nothing to store. The runner should show as **Idle** in the repo's runner list.

## 7. Job lock hooks

The hooks in `tools/ci-runner/` (see its README) let only one job run at a
time across all four runners, using FIFO queueing
(`/var/lock/front-office-ci.lock.queue` by default, with heartbeat-based stale
ticket eviction), a short grace timeout for unlabelled locks
(`FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS`, default `60` s), and
post-rename owner verification inside `take_over_stale` so concurrent stale
takeovers cannot delete a freshly acquired lock. Run their tests on the host,
then install them from the deployment clone:

```sh
git clone https://github.com/kailot-harris/front-office.git ~/runners/front-office
bash ~/runners/front-office/tools/ci-runner/tests/run_tests.sh   # must end "failed: 0"
sudo install -d /opt/actions-runner/hooks
sudo install -m 0755 \
  ~/runners/front-office/tools/ci-runner/job-started.sh \
  ~/runners/front-office/tools/ci-runner/job-completed.sh \
  /opt/actions-runner/hooks/
```

Add these two lines to `.env` in each of the four runner folders:

```sh
ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hooks/job-completed.sh
```

Restart the four services (see [Everyday commands](#everyday-commands)). All
four run as `<user>`, so the default lock and queue paths under `/var/lock`
work, stale-lock takeover works, and stale-ticket cleanup works.

The next job on any runner should show a `[ci-lock]` hook step in its log.

**Updating the hooks:** pulling `main` in `~/runners/front-office` does not
change the installed copies under `/opt/actions-runner/hooks/`. After any hook
change is merged, pull `main`, run the test suite, re-install both scripts to
`/opt/actions-runner/hooks/`, verify the installed copies match with `cmp`, and
restart all four runner services:

```sh
git -C ~/runners/front-office pull
bash ~/runners/front-office/tools/ci-runner/tests/run_tests.sh   # must end "failed: 0"
sudo install -m 0755 \
  ~/runners/front-office/tools/ci-runner/job-started.sh \
  ~/runners/front-office/tools/ci-runner/job-completed.sh \
  /opt/actions-runner/hooks/
cmp ~/runners/front-office/tools/ci-runner/job-started.sh /opt/actions-runner/hooks/job-started.sh
cmp ~/runners/front-office/tools/ci-runner/job-completed.sh /opt/actions-runner/hooks/job-completed.sh
for s in mlb nba nfl wnba; do
  sudo systemctl restart "$(cat ~/runners/$s/actions-runner/.service)"
done
```

Do it while the runners are idle. Keep the deployment clone on `main`; do
feature work in a separate worktree or clone.

Time spent waiting for the lock counts against each job's `timeout-minutes`.
The FIFO queue, environment overrides, unlabelled grace period, post-rename
takeover invariant, worst-case wait, and stale-lock timeouts are explained in
`tools/ci-runner/README.md`.

## 8. Start with the machine

WSL2 does not start at boot, and it stops a distribution that has nothing
attached to it. A Task Scheduler entry starts Ubuntu at boot and keeps it
running.

The task must run as the Windows account that owns the Ubuntu distribution:
the account whose normal (non-administrator) PowerShell lists Ubuntu in
`wsl -l -v`. An administrator PowerShell may be running as a *different*
account (for example when the elevation prompt asks for another account's
password), so name the owner explicitly rather than using `$env:USERNAME`.

A task that runs while nobody is logged on uses a batch logon, which needs the
**Log on as a batch job** right (`SeBatchLogonRight`). Windows gives it to
administrators but not to standard users, and registering the task does not
grant it. Without it the task fails at boot with Task Scheduler events 101 and
104 and error `0x80070569` ("The user has not been granted the requested logon
type"). If the owning account is a standard user, grant the right first, from
an administrator PowerShell (`secpol.msc` → Local Policies → User Rights
Assignment does the same on editions that have it):

```powershell
$owner = "$env:COMPUTERNAME\<wsl-owner>"
$sid = (New-Object System.Security.Principal.NTAccount($owner)).Translate([System.Security.Principal.SecurityIdentifier]).Value
$inf = "$env:TEMP\batch-right.inf"; $db = "$env:TEMP\batch-right.sdb"
secedit /export /cfg $inf /areas USER_RIGHTS | Out-Null
$lines = [string[]](Get-Content $inf)
$i = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -like 'SeBatchLogonRight*' })
if ($i -ge 0) { if ($lines[$i] -notlike "*$sid*") { $lines[$i] += ",*$sid" } }
else { $j = [array]::IndexOf($lines, '[Privilege Rights]'); $lines = $lines[0..$j] + "SeBatchLogonRight = *$sid" + $lines[($j+1)..($lines.Count-1)] }
$lines | Set-Content $inf -Encoding Unicode
secedit /configure /db $db /cfg $inf /areas USER_RIGHTS
Remove-Item $inf, $db
```

Check: `secedit /export /cfg $env:TEMP\r.inf /areas USER_RIGHTS; Select-String SeBatchLogonRight $env:TEMP\r.inf`
should list the account's SID (`*S-1-5-21-…`).

Turn on Task Scheduler history so a failed boot run can be diagnosed later:
`wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true`.

From an administrator PowerShell, create the task **WSL Ubuntu keep-alive**,
replacing `<wsl-owner>` with that account's user name:

```powershell
Unregister-ScheduledTask -TaskName "WSL Ubuntu keep-alive" -Confirm:$false -ErrorAction SilentlyContinue
$cred = Get-Credential -UserName "$env:COMPUTERNAME\<wsl-owner>" -Message "Windows password of the account that owns the WSL distribution"
$action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wsl.exe" -Argument '-d Ubuntu --exec /bin/sh -c "exec sleep infinity"'
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "WSL Ubuntu keep-alive" -Action $action -Trigger $trigger -Settings $settings -User $cred.UserName -Password $cred.GetNetworkCredential().Password
```

The WSL distribution belongs to one Windows user, so the task runs as that
user, and stores that user's password so it can run before anyone logs in.
With a Microsoft account, enter the account password, not the PIN. If the
distribution has a different name, change `-d Ubuntu` (`wsl -l -v` lists
names). If the Windows password changes, re-run the script to update the
stored one, or the task fails at the next boot.

The task stores a password, so only an administrator can read it; check it
from an administrator PowerShell, not from inside Ubuntu.

### How to check

1. **Manual run.** `wsl` commands act on the account that runs them, so run
   `wsl` in a normal PowerShell of the owning account, and `schtasks` in an
   administrator PowerShell:

   ```powershell
   wsl --shutdown                                # owner's normal PowerShell
   schtasks /run /tn "WSL Ubuntu keep-alive"     # administrator PowerShell
   wsl -l -v                                     # owner's normal PowerShell
   ```

   Ubuntu should show **Running**, and still show it two minutes later. The
   task's Last Run Result in Task Scheduler should be "The task is currently
   running" (0x41301).
2. **Closing a terminal.** Open and close an Ubuntu window. All four runners
   stay **Idle** on GitHub.
3. **Cold reboot, no login.** Reboot and leave the machine at the login
   screen. From another device, open each sport repo's Settings → Actions →
   Runners. All four runners should show **Idle** within about 5 minutes, and
   still be Idle 15 minutes later.
4. **Started at boot, not at login.** After logging in, compare
   `(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` in PowerShell with
   `uptime -s` in Ubuntu. Ubuntu's start time should be within a minute or two
   of the Windows boot, well before the login.

If the runners are **Offline** after the reboot, check the task's History tab.
The usual causes are a wrong or outdated stored password, or the task running
as a different Windows user from the one that owns the distribution.

Windows Update restarts are ordinary reboots with nobody logged in; after the
first one, confirm the runners came back to Idle.

## 9. Power settings

Turn off sleep and hibernation on the Windows host so queued jobs can run.
From an administrator PowerShell:

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /hibernate off
```

Turning the display off is fine. `powercfg /hibernate off` also turns off Fast
Startup, so a shutdown fully stops Windows and the next start runs the
at-startup task normally.

### How to check

1. **Settings.** `powercfg /a` should say "Hibernation has not been enabled",
   and `powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE` should show
   `Current AC Power Setting Index: 0x00000000` (never).
2. **No sleep overnight.** Leave the machine idle overnight, then:

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=42; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue
   ```

   No output means the machine did not sleep (event 42 is logged on every
   sleep). The runners should still be Idle on GitHub.

## Everyday commands

Run from the runner's folder, `~/runners/<sport>/actions-runner`:

```sh
sudo ./svc.sh status
sudo ./svc.sh stop
sudo ./svc.sh start
```

Each runner folder has a `.service` file holding its systemd unit name, so all
four can be handled at once:

```sh
for s in mlb nba nfl wnba; do
  sudo systemctl restart "$(cat ~/runners/$s/actions-runner/.service)"
done
```

Is a job running right now? `pgrep -f Runner.Worker` lists running jobs; `ls
/var/lock/front-office-ci.lock` exists only while a job holds the lock, and
its `owner` file says which job.

## Updating the runner software

Runners update themselves by default when GitHub releases a new version. No
regular action is needed.

If a runner shows **Offline** after an update:

1. Check the service: `sudo ./svc.sh status` in that runner's folder.
2. If it is stopped, `sudo ./svc.sh start`.
3. If it will not stay up, read the newest `Runner_*.log` in `_diag/`. As a
   last resort, remove the runner (below) and register it again with the
   current release.

## Removing a runner

1. In the sport repo: Settings → Actions → Runners → the runner → Remove.
   Copy the removal command's token.
2. In the runner's folder:

   ```sh
   sudo ./svc.sh stop
   sudo ./svc.sh uninstall
   ./config.sh remove --token <removal token>
   ```

3. Delete the folder if it will not be reused.

## Fallback to hosted runners

If the host is off or broken, clear the `CI_RUNNER` repository variable in the
affected sport repo (Settings → Secrets and variables → Actions → Variables).
CI goes back to GitHub-hosted runners on the next run, which bills Actions
minutes. Set it back to `self-hosted` when the host is healthy.

Jobs queued while the host is off wait up to about 24 hours, then fail. Re-run
them after the host is back, or after clearing the variable.

## Measurements

To be filled in during cutover (#154): wall-clock time per job and peak memory
inside Ubuntu, per sport repo; results of the overlap test, the fallback drill
and the host-off test.

| Repo | `web` time | `r` time | Peak memory, `web` / `r` |
| --- | --- | --- | --- |
| MLB | | | |
| WNBA | | | |
| NBA | about 3m 12s | about 45s | 2.8 GiB / 2.0 GiB |
| NFL | about 5m 17s | about 15s | 3.4 GiB / 1.9 GiB |

How the NBA and NFL rows were measured (2026-11-15, manual CI runs on `main`,
both repos started at the same moment):

- `free -m` sampled every 2 s, together with the owner of the job lock, so
  each sample belongs to the job holding the lock.
- **Peak memory** is Ubuntu's total `used` memory while that job held the
  lock. It includes about 1.4 GiB used with the runners idle, so the job's own
  share is roughly 1.4–2.0 GiB for `web` and about 0.6 GiB for `r`.
- No swap was used. The highest `used` memory was 3.4 GiB, during the NFL
  `web` job, well under the 8 GB cap and the 6 GB per-job threshold in #154.
  `available` memory never dropped below 4.4 GiB.
- **Times** are how long each job held the lock (to within the 2 s sampling).
  GitHub's job duration is longer for a job that waited, because the wait for
  the lock is counted inside the job.

Overlap: with both repos started together, the four jobs ran one at a time in
lock order (NFL `r`, NBA `r`, NFL `web`, NBA `web`). NBA `web` waited about
5.5 minutes for the lock, and both runs passed.
