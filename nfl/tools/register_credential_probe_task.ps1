<#
.SYNOPSIS
    Registers the two ON-DEMAND scheduled tasks that settle GitHub issue #42, by
    running tools/test_unattended_push.ps1 in each of the two logon contexts.

.DESCRIPTION
    Issue #42 asks for one real push executed from a scheduled-task context rather
    than an interactive shell. Answering it needs a CONTROL, not just a single run --
    so this script registers two tasks that differ in exactly one respect, their
    principal's logon type:

      NFL_analytics_credprobe_interactive   LogonType Interactive
          The context every live task on this machine already uses (verified
          2026-10-24: NFL_analytics_task_01, the NBA, MLB and WNBA tasks are all
          InteractiveToken). A push here is expected to work and proves little on its
          own -- it is the control that makes the other result interpretable.

      NFL_analytics_credprobe_unattended    LogonType S4U
          "Run whether logged on or not", with no stored password. THIS is the context
          #42 is about: it runs in a non-interactive session which may not reach Git
          Credential Manager, and under S4U the user's DPAPI-protected credential
          store is the specific thing that may be unavailable.

    Read the pair together:
      interactive PASS + unattended PASS -> credentials work unattended. #42 closes.
      interactive PASS + unattended FAIL -> GCM is unreachable non-interactively,
          exactly as #42 predicts. Pick a documented remedy (a PAT in the task's
          environment, a dedicated credential store, or a different auth mechanism)
          rather than leaving the 09:00 publish to chance.
      interactive FAIL                   -> the problem is not about logon type at
          all; fix the credential itself first.

    NEITHER TASK HAS A TRIGGER. Both are on-demand only, so registering them changes
    nothing about the daily schedule and nothing runs until you start one explicitly.
    That is deliberate: a credential probe is a diagnostic you run once and read, not
    a recurring job.

    This script does NOT touch NFL_analytics_task_01 or NFL_analytics_publish_01, and
    does NOT change the publish task's dryrun/publish mode. That switch stays a
    separate human decision -- see docs/SCHEDULING.md "Do not enable --publish until
    #42 is proven".

    NOTHING RUNS AT IMPORT TIME, same guarded-entry-point convention as
    register_scheduled_tasks.ps1, so this file can be dot-sourced for inspection.

.PARAMETER DryRun
    Print both task configurations and apply nothing. Use this first, always.

.PARAMETER Remove
    Unregister both probe tasks. Use when #42 is settled -- the probe is a one-off
    diagnostic and should not outlive the question it answers.

.PARAMETER ProjectDir
    Project root. Mirrors config.R's PROJECT_DIR, the same single deliberate
    duplication register_scheduled_tasks.ps1 and the .bat wrappers make and justify.

.PARAMETER TimeoutSec
    Passed through to the probe's own per-git-command timeout.

.PARAMETER AggregatorDir
    The front-office-aggregator checkout, passed through to the probe EXPLICITLY
    rather than left to the probe's own default. The registered task is what a
    future reader audits with Get-ScheduledTask, and an implicitly-defaulted path
    is invisible there -- so both repos the probe writes to are named in the
    task's Arguments string.

.EXAMPLE
    # Always first -- shows both tasks, changes nothing:
    powershell -NoProfile -File tools\register_credential_probe_task.ps1 -DryRun

.EXAMPLE
    # Register both on-demand tasks (needs an elevated session):
    powershell -NoProfile -File tools\register_credential_probe_task.ps1

.EXAMPLE
    # Then run them, control first, and read logs\credential_probe.log:
    Start-ScheduledTask -TaskName NFL_analytics_credprobe_interactive
    Start-ScheduledTask -TaskName NFL_analytics_credprobe_unattended
    Get-ScheduledTaskInfo NFL_analytics_credprobe_interactive, NFL_analytics_credprobe_unattended |
        Select-Object TaskName, LastRunTime, LastTaskResult

.EXAMPLE
    # Clean up once #42 is answered:
    powershell -NoProfile -File tools\register_credential_probe_task.ps1 -Remove

.NOTES
    Registering a scheduled task, and especially an S4U principal, needs an elevated
    session. If the S4U registration is refused by policy, the documented fallback is
    a task with a stored password (LogonType Password), which this script deliberately
    does not create because it would have to collect that password.

    LastTaskResult is the probe's exit code: 0 = both pushes OK, 1 = at least one
    failed, 2 = precondition failure. The detail is in logs\credential_probe.log.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $DryRun,
    [switch] $Remove,

    # Mirrors config.R's PROJECT_DIR; see register_scheduled_tasks.ps1's note on why
    # this one value is restated in PowerShell rather than read from config.R.
    [string] $ProjectDir = 'c:\Users\kailo\kayceeslices\front-office\nfl analytics',

    [int] $TimeoutSec = 60,

    # Forwarded to the probe explicitly rather than left to the probe's own default.
    # The registered task is the artifact a future reader audits, so every input the
    # probe acts on should be visible in the task's Arguments string -- an implicit
    # default is invisible in Get-ScheduledTask output.
    [string] $AggregatorDir = 'c:\Users\kailo\kayceeslices\front-office\front-office-aggregator'
)

$ErrorActionPreference = 'Stop'

$script:InteractiveTaskName = 'NFL_analytics_credprobe_interactive'
$script:UnattendedTaskName  = 'NFL_analytics_credprobe_unattended'

function Get-ProbeTaskPlan {
    <#
    .SYNOPSIS
        Declarative plan for both probe tasks. Pure: the -DryRun path and the apply
        path print an identical configuration because both read this.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectDir,
        [Parameter(Mandatory)] [int]    $TimeoutSec,
        [Parameter(Mandatory)] [string] $AggregatorDir
    )

    $probeScript = Join-Path $ProjectDir 'tools\test_unattended_push.ps1'

    # -NoProfile: a profile could alter PATH or git config and make the probe measure
    # something other than the scheduler's own environment.
    $argTemplate = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ProjectDir "{1}" -AggregatorDir "{2}" -TimeoutSec {3}'
    $arguments   = ($argTemplate -f $probeScript, $ProjectDir, $AggregatorDir, $TimeoutSec)

    @(
        [pscustomobject]@{
            Name        = $script:InteractiveTaskName
            LogonType   = 'Interactive'
            Description = 'NFL Analytics issue #42 CONTROL probe: real push from an INTERACTIVE scheduled-task session. On-demand only, no trigger.'
            Execute     = 'powershell.exe'
            Arguments   = $arguments
            ProbeScript = $probeScript
        }
        [pscustomobject]@{
            Name        = $script:UnattendedTaskName
            LogonType   = 'S4U'
            Description = 'NFL Analytics issue #42 probe: real push from a NON-INTERACTIVE (run whether logged on or not) scheduled-task session. On-demand only, no trigger.'
            Execute     = 'powershell.exe'
            Arguments   = $arguments
            ProbeScript = $probeScript
        }
    )
}

function Show-ProbeTaskPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Plan,
        [Parameter(Mandatory)] [bool]     $WouldApply,
        [Parameter(Mandatory)] [string]   $UserId
    )

    Write-Host ''
    Write-Host '=================================================================='
    if ($WouldApply) {
        Write-Host 'Issue #42 credential probe tasks -- APPLYING'
    } else {
        Write-Host 'Issue #42 credential probe tasks -- DRY RUN (nothing will be applied)'
    }
    Write-Host '=================================================================='

    foreach ($t in $Plan) {
        $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        $exists = $null -ne $existing
        if ($exists) { $verb = 'UPDATE in place' } else { $verb = 'REGISTER new' }

        Write-Host ''
        Write-Host ("  Task              : {0}" -f $t.Name)
        Write-Host ("  Already exists    : {0}  -> would {1}" -f $exists, $verb)
        Write-Host ("  LogonType         : {0}" -f $t.LogonType)
        Write-Host ("  RunAs             : {0}" -f $UserId)
        Write-Host ("  Action            : {0}" -f $t.Execute)
        Write-Host ("  Arguments         : {0}" -f $t.Arguments)
        Write-Host ("  WorkingDirectory  : {0}" -f $ProjectDir)
        Write-Host  "  Trigger           : NONE (on-demand only -- nothing runs on a schedule)"
        Write-Host  "  ExecutionTimeLimit: 15 minutes"
        Write-Host  "  MultipleInstances : IgnoreNew"
        Write-Host ("  Probe script exists: {0}" -f (Test-Path -LiteralPath $t.ProbeScript))
        Write-Host ("  Description       : {0}" -f $t.Description)
    }

    Write-Host ''
    Write-Host '  Each run executes a REAL push of the existing HEAD commit to a throwaway'
    Write-Host '  refs/heads/cred-probe/* ref on NFL_analytics and front-office, then deletes'
    Write-Host '  it. No commit is created, main is never pushed, and deploy.yml (push to main'
    Write-Host '  only) cannot fire. See tools/test_unattended_push.ps1 for the full rationale.'
    Write-Host ''
    if (-not $WouldApply) {
        Write-Host '  DRY RUN -- no task was created, modified, enabled, disabled or deleted.'
        Write-Host '  No push was attempted: registering a task does not run it.'
    }
    Write-Host '=================================================================='
    Write-Host ''
}

function Remove-ProbeTasks {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    foreach ($name in @($script:InteractiveTaskName, $script:UnattendedTaskName)) {
        $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            Write-Host "  [ABSENT]     $name (nothing to remove)"
            continue
        }
        if ($PSCmdlet.ShouldProcess($name, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "  [REMOVED]    $name"
        }
    }
}

function Register-ProbeTasks {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ProjectDir,
        [Parameter(Mandatory)] [int]    $TimeoutSec,
        [Parameter(Mandatory)] [string] $AggregatorDir,
        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $ProjectDir)) {
        throw "ProjectDir does not exist: $ProjectDir"
    }

    $userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $plan   = Get-ProbeTaskPlan -ProjectDir $ProjectDir -TimeoutSec $TimeoutSec -AggregatorDir $AggregatorDir

    Show-ProbeTaskPlan -Plan $plan -WouldApply (-not $DryRun) -UserId $userId

    if ($DryRun) { return }

    foreach ($t in $plan) {
        if (-not (Test-Path -LiteralPath $t.ProbeScript)) {
            throw "Probe script does not exist, refusing to register a broken task: $($t.ProbeScript)"
        }
    }

    # No trigger is passed to Register-ScheduledTask at all -- an on-demand task is
    # precisely a task with no trigger, which is safer than registering a dated
    # one-shot trigger that could fire unattended before anyone is ready to read it.
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
        -MultipleInstances IgnoreNew

    foreach ($t in $plan) {
        $action = New-ScheduledTaskAction -Execute $t.Execute -Argument $t.Arguments -WorkingDirectory $ProjectDir

        # RunLevel Limited on purpose: the live publish will not run elevated either,
        # and an elevated probe could reach a credential store the real task cannot,
        # which would produce a falsely reassuring answer to #42.
        $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType $t.LogonType -RunLevel Limited

        $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue

        if ($existing) {
            if ($PSCmdlet.ShouldProcess($t.Name, 'Update scheduled task')) {
                Set-ScheduledTask -TaskName $t.Name -Action $action -Settings $settings -Principal $principal | Out-Null
                Write-Host "  [UPDATED]    $($t.Name)"
            }
        } else {
            if ($PSCmdlet.ShouldProcess($t.Name, 'Register scheduled task')) {
                Register-ScheduledTask -TaskName $t.Name -Action $action -Settings $settings `
                    -Principal $principal -Description $t.Description -Force | Out-Null
                Write-Host "  [REGISTERED] $($t.Name)"
            }
        }
    }

    Write-Host ''
    Write-Host 'Registered on-demand only -- nothing has run and nothing will run on a schedule.'
    Write-Host ''
    Write-Host 'Run the CONTROL first, then the unattended one:'
    Write-Host ("  Start-ScheduledTask -TaskName {0}" -f $script:InteractiveTaskName)
    Write-Host ("  Start-ScheduledTask -TaskName {0}" -f $script:UnattendedTaskName)
    Write-Host ''
    Write-Host 'Then read the result (exit 0 = both pushes OK, 1 = a push failed):'
    Write-Host ("  Get-ScheduledTaskInfo {0}, {1} | Select-Object TaskName, LastRunTime, LastTaskResult" -f $script:InteractiveTaskName, $script:UnattendedTaskName)
    Write-Host ("  Get-Content '{0}' -Tail 60" -f (Join-Path $ProjectDir 'logs\credential_probe.log'))
    Write-Host ''
}

# ------------------------------------------------------------------------------
# Entry point. Guarded so NOTHING runs at import time -- same convention and same
# reason as register_scheduled_tasks.ps1 and publish_web.R's commandArgs() check.
# ------------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    if ($Remove) {
        Remove-ProbeTasks
    } else {
        Register-ProbeTasks -ProjectDir $ProjectDir -TimeoutSec $TimeoutSec -AggregatorDir $AggregatorDir -DryRun:$DryRun
    }
}
