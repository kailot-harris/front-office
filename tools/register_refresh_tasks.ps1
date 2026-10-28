<#
.SYNOPSIS
    Registers (or updates) the two Windows scheduled tasks that drive score
    refresh slots B and C via tools/run_refresh_slot.ps1.

.DESCRIPTION
    Idempotent: each task is described declaratively by Get-RefreshTaskPlan and
    then either registered fresh or updated in place, so running this twice
    leaves the machine as running it once. Safe to re-run after editing a time.

    WHY THESE TASKS EXIST AT ALL: GitHub's cron fired 5-6 hours late on 4 of 4
    observed runs in this workspace, while Task Scheduler on this box fired
    within 2 seconds on 5 of 5 tasks. The full rationale is in the header of
    run_refresh_slot.ps1 -- read that first.

    LOGON TYPE IS INTERACTIVE, AND THAT IS A HARD REQUIREMENT, not a copy of
    what the slot A tasks happen to do. run_refresh_slot.ps1 shells out to
    `gh`, whose OAuth token for this account is stored in the Windows keyring
    ("Logged in to github.com account kailot-harris (keyring)"). The keyring is
    only reachable from the logged-on user's session, so a task registered with
    S4U or as SYSTEM would run, fail every gh call with an auth error, and
    report a failing slot every night. The box therefore has to be logged on,
    not merely powered on.

    StartWhenAvailable is set for the same reason the slot A tasks set it: if
    the box is asleep or off at the trigger time, the slot runs as soon as it
    comes back rather than being skipped. That is what makes "on almost 24/7"
    sufficient here -- a missed 01:00 run is late, not lost.

    WakeToRun is left FALSE to match the existing slot A tasks. If slot C turns
    out to be skipped regularly because the box sleeps overnight, flipping this
    to $true on the slot C task is the fix; it is deliberately not enabled
    pre-emptively, since the existing tasks prove the current setup works.

    NOTHING RUNS AT IMPORT TIME: functions plus one guarded entry point.

.PARAMETER DryRun
    Print the resulting configuration for both tasks and apply nothing. Use
    this first, always.

.PARAMETER Unregister
    Remove both tasks. Does not touch the slot A pipeline tasks.

.EXAMPLE
    powershell -NoProfile -File tools\register_refresh_tasks.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch] $DryRun,
    [switch] $Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolved from this script's own location so a relocated checkout still works,
# rather than hardcoded. NFL issue #43 (config.R hardcoding PROJECT_DIR, so a
# task with an empty WorkingDirectory only worked by accident) is CLOSED, but
# deriving the path costs nothing and keeps this script checkout-agnostic.
$TOOLS_DIR   = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_DIR    = Split-Path -Parent $TOOLS_DIR
$SLOT_SCRIPT = Join-Path $TOOLS_DIR 'run_refresh_slot.ps1'
$LOG_DIR     = Join-Path $REPO_DIR 'logs'

function Get-RefreshTaskPlan {
    # Local times, chosen to match what the retired UTC crons meant during EDT:
    # 18:00 ET = 22:00 UTC (slot B), 01:00 ET = 05:00 UTC (slot C). These are
    # LOCAL and so, unlike cron, they follow DST automatically -- which is
    # strictly better here, because both slot times were picked relative to
    # North American game schedules, which are themselves local.
    @(
        [pscustomobject]@{
            Name = 'Front Office Refresh Slot B'
            Slot = 'B'
            At   = '18:00'
            Why  = 'afternoon finals, before the evening slate'
        },
        [pscustomobject]@{
            Name = 'Front Office Refresh Slot C'
            Slot = 'C'
            At   = '01:00'
            Why  = 'overnight; first hour a full night of games is reliably final'
        }
    )
}

function Register-RefreshTask {
    param([pscustomobject] $Plan, [switch] $DryRun)

    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Slot {1} -LogDir "{2}"' -f `
        $SLOT_SCRIPT, $Plan.Slot, $LOG_DIR

    if ($DryRun) {
        Write-Output "  $($Plan.Name)"
        Write-Output "    trigger: daily $($Plan.At) local  ($($Plan.Why))"
        Write-Output "    action:  powershell.exe $argLine"
        Write-Output "    workdir: $REPO_DIR"
        Write-Output "    principal: $env:USERNAME, Interactive, Limited"
        return
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument $argLine -WorkingDirectory $REPO_DIR

    $trigger = New-ScheduledTaskTrigger -Daily -At $Plan.At

    # RunLevel Limited, deliberately NOT Highest. The slot A pipeline tasks use
    # Highest, but copying that here costs an elevation prompt to register
    # (Register-ScheduledTask returns "Access is denied" / 0x80070005 from a
    # non-elevated shell -- this is how that was found) and buys nothing: this
    # task only shells out to `gh`, which needs no administrator rights. Least
    # privilege also means registering it never requires an admin session.
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
        -LogonType Interactive -RunLevel Limited

    # ExecutionTimeLimit: a slot measured at ~3.5 minutes end to end. Thirty
    # minutes is generous enough for a slow runner queue and short enough that
    # a wedged `gh run watch` cannot sit there until the next slot.
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    $existing = Get-ScheduledTask -TaskName $Plan.Name -ErrorAction SilentlyContinue

    if ($null -ne $existing) {
        Set-ScheduledTask -TaskName $Plan.Name -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings | Out-Null
        Write-Output "  updated: $($Plan.Name)"
    }
    else {
        Register-ScheduledTask -TaskName $Plan.Name -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description "Score refresh slot $($Plan.Slot): $($Plan.Why). Replaces the GitHub crons, which fired 5-6h late. See tools/run_refresh_slot.ps1." | Out-Null
        Write-Output "  registered: $($Plan.Name)"
    }
}

function Invoke-Registration {
    param([switch] $DryRun, [switch] $Unregister)

    if (-not (Test-Path $SLOT_SCRIPT)) {
        throw "Cannot find $SLOT_SCRIPT -- run this from the aggregator checkout."
    }

    $plans = Get-RefreshTaskPlan

    if ($Unregister) {
        foreach ($p in $plans) {
            if ($DryRun) { Write-Output "  would unregister: $($p.Name)"; continue }
            Unregister-ScheduledTask -TaskName $p.Name -Confirm:$false `
                -ErrorAction SilentlyContinue
            Write-Output "  unregistered: $($p.Name)"
        }
        return
    }

    Write-Output "=== Refresh slot tasks$(if ($DryRun) { ' (DRY RUN, nothing applied)' })"
    foreach ($p in $plans) { Register-RefreshTask -Plan $p -DryRun:$DryRun }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Registration -DryRun:$DryRun -Unregister:$Unregister
}
