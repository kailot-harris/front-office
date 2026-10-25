<#
.SYNOPSIS
    Registers (or updates) the two NFL Analytics scheduled tasks: the 05:15 pipeline
    run and the 09:00 publish-only run. GitHub issue #39 scope items 2, 3 and 4.

.DESCRIPTION
    Idempotent. Each task is described declaratively by Get-NflTaskPlan, then either
    registered fresh or updated in place if a task of that name already exists -- so
    running this script twice leaves the machine in the same state as running it
    once, and it is safe to re-run after editing a trigger time.

    What it fixes relative to the current live configuration:
      * The existing NFL_analytics_task_01 invokes Rscript.exe directly on an
        absolute path to run_full_pipeline.R, with an EMPTY WorkingDirectory. That
        only survives today because config.R hardcodes PROJECT_DIR (issue #43).
        These tasks instead call the .bat wrappers AND set an explicit working
        directory, so neither depends on that hardcoded path.
      * StartWhenAvailable ("run as soon as possible after a missed start") and a
        wake timer are set on both tasks, per #39 scope item 4. A sleeping laptop at
        09:00 is the most likely failure mode -- see docs/SCHEDULING.md.

    The publish task is registered in DRY-RUN mode deliberately. Issue #42 (the
    unattended push credential) is still open: Task Scheduler's non-interactive
    session may not reach Git Credential Manager. Prove #42 before passing
    -PublishMode publish. See docs/SCHEDULING.md.

    NOTHING RUNS AT IMPORT TIME. This file only defines functions plus a single
    guarded entry point, so dot-sourcing it for inspection is side-effect-free.

.PARAMETER DryRun
    Print the resulting configuration for both tasks and apply nothing. Use this
    first, always.

.PARAMETER PublishMode
    Mode argument handed to schedule_publish.bat. 'dryrun' (default), 'strict',
    'publish' or 'publish-strict'. Do not use a publish* mode until #42 is proven.

.PARAMETER ProjectDir
    Project root. Defaults to config.R:22's PROJECT_DIR value. Override only to
    register tasks against a relocated checkout.

.EXAMPLE
    # Always do this first -- shows both task configurations, changes nothing:
    powershell -NoProfile -File tools\register_scheduled_tasks.ps1 -DryRun

.EXAMPLE
    # Apply (dry-run publish task, which is what you want until #42 is proven):
    powershell -NoProfile -File tools\register_scheduled_tasks.ps1

.NOTES
    Registering/updating a scheduled task needs an elevated session.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $DryRun,

    [ValidateSet('dryrun', 'strict', 'publish', 'publish-strict')]
    [string] $PublishMode = 'dryrun',

    # Mirrors config.R:22's PROJECT_DIR. A PowerShell script cannot source R, so
    # the project root is restated here -- the same single, deliberate duplication
    # the .bat wrappers make and justify in their own header comments. Nothing else
    # is duplicated: every other value lives in config.R and is read by the R code.
    [string] $ProjectDir = 'c:\Users\kailo\kayceeslices\front-office\nfl analytics'
)

$ErrorActionPreference = 'Stop'

# Task names. The pipeline task keeps the EXISTING live name so this script updates
# that task in place (repointing it at the wrapper) rather than leaving a duplicate
# 05:15 task behind -- which is what #39 scope item 2 asks for.
$script:PipelineTaskName = 'NFL_analytics_task_01'
$script:PublishTaskName  = 'NFL_analytics_publish_01'

function Get-NflTaskPlan {
    <#
    .SYNOPSIS
        Builds the declarative plan for both tasks. Pure: changes nothing, so the
        -DryRun path and the apply path print an identical configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectDir,
        [Parameter(Mandatory)] [string] $PublishMode
    )

    @(
        [pscustomobject]@{
            Name             = $script:PipelineTaskName
            Description      = 'NFL Analytics: full pipeline run (run_full_pipeline.R via schedule_daily.bat).'
            Execute          = (Join-Path $ProjectDir 'schedule_daily.bat')
            Arguments        = ''
            WorkingDirectory = $ProjectDir
            # 05:15 -- the existing live trigger time, deliberately unchanged.
            At               = '05:15'
        }
        [pscustomobject]@{
            Name             = $script:PublishTaskName
            Description      = "NFL Analytics: web publish gate (tools/publish_web.R via schedule_publish.bat), mode '$PublishMode'."
            Execute          = (Join-Path $ProjectDir 'schedule_publish.bat')
            Arguments        = $PublishMode
            WorkingDirectory = $ProjectDir
            # 09:00 -- deploy latency is ~4 min after the push, so the site is live
            # around 09:04. Staggered well clear of the 05:15 pipeline so a long
            # pipeline overrun cannot silently delay the deploy (#39 scope item 3),
            # and clear of other repos' pushes because deploy.yml uses
            # concurrency: pages with cancel-in-progress: true (#41).
            At               = '09:00'
        }
    )
}

function Show-NflTaskPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Plan,
        [Parameter(Mandatory)] [bool] $WouldApply
    )

    Write-Host ''
    Write-Host '=================================================================='
    if ($WouldApply) {
        Write-Host 'NFL Analytics scheduled tasks -- APPLYING'
    } else {
        Write-Host 'NFL Analytics scheduled tasks -- DRY RUN (nothing will be applied)'
    }
    Write-Host '=================================================================='

    foreach ($t in $Plan) {
        $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        $exists = $null -ne $existing
        if ($exists) { $verb = 'UPDATE in place' } else { $verb = 'REGISTER new' }
        if ([string]::IsNullOrWhiteSpace($t.Arguments)) { $argDisplay = '<none>' } else { $argDisplay = $t.Arguments }

        Write-Host ''
        Write-Host ("  Task              : {0}" -f $t.Name)
        Write-Host ("  Already exists    : {0}  -> would {1}" -f $exists, $verb)
        Write-Host ("  Action            : {0}" -f $t.Execute)
        Write-Host ("  Arguments         : {0}" -f $argDisplay)
        Write-Host ("  WorkingDirectory  : {0}" -f $t.WorkingDirectory)
        Write-Host ("  Trigger           : Daily at {0}" -f $t.At)
        Write-Host  "  StartWhenAvailable: True   (run ASAP after a missed start)"
        Write-Host  "  WakeToRun         : True   (wake the machine for this run)"
        Write-Host  "  ExecutionTimeLimit: 2 hours"
        Write-Host  "  MultipleInstances : IgnoreNew"
        Write-Host ("  Action file exists: {0}" -f (Test-Path -LiteralPath $t.Execute))
        Write-Host ("  Description       : {0}" -f $t.Description)
    }

    Write-Host ''
    if (-not $WouldApply) {
        Write-Host '  DRY RUN -- no task was created, modified, enabled, disabled or deleted.'
    }
    Write-Host '=================================================================='
    Write-Host ''
}

function Register-NflScheduledTasks {
    <#
    .SYNOPSIS
        Idempotently register/update both tasks. Honours -WhatIf via ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ProjectDir,
        [string] $PublishMode = 'dryrun',
        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $ProjectDir)) {
        throw "ProjectDir does not exist: $ProjectDir"
    }

    $plan = Get-NflTaskPlan -ProjectDir $ProjectDir -PublishMode $PublishMode
    Show-NflTaskPlan -Plan $plan -WouldApply (-not $DryRun)

    if ($DryRun) { return }

    foreach ($t in $plan) {
        if (-not (Test-Path -LiteralPath $t.Execute)) {
            throw "Task action does not exist, refusing to register a broken task: $($t.Execute)"
        }
    }

    if ($PublishMode -like 'publish*') {
        Write-Warning ("Registering the publish task in LIVE mode '{0}'. This pushes for real. Issue #42 (unattended push credential) was proven green on 2026-10-25, so this is permitted -- but that result is point-in-time: S4U credential reachability rides on the user's DPAPI store and can break with no code change on a password change, keyring reset or GCM store-backend change. Treat a push failure as alertable, not impossible. See docs/SCHEDULING.md." -f $PublishMode)
    }

    foreach ($t in $plan) {
        # New-ScheduledTaskAction rejects an empty -Argument, so splat it
        # conditionally rather than passing ''.
        $actionArgs = @{ Execute = $t.Execute; WorkingDirectory = $t.WorkingDirectory }
        if (-not [string]::IsNullOrWhiteSpace($t.Arguments)) { $actionArgs['Argument'] = $t.Arguments }
        $action = New-ScheduledTaskAction @actionArgs

        $trigger = New-ScheduledTaskTrigger -Daily -At $t.At

        # StartWhenAvailable: #39 scope item 4's "run as soon as possible after a
        # missed start". WakeToRun: wake the machine rather than skip the run.
        # The 2h execution limit is generous on purpose -- the 2026-10-23 pipeline
        # run took 197s, so 2h is ~36x headroom and still bounds a hung run.
        # IgnoreNew: never stack a second instance on top of a still-running one.
        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -WakeToRun `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
            -MultipleInstances IgnoreNew

        $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue

        if ($existing) {
            # Idempotent path: update the existing task in place, no duplicate.
            if ($PSCmdlet.ShouldProcess($t.Name, 'Update scheduled task')) {
                Set-ScheduledTask -TaskName $t.Name -Action $action -Trigger $trigger -Settings $settings | Out-Null
                Write-Host "  [UPDATED]    $($t.Name)"
            }
        } else {
            if ($PSCmdlet.ShouldProcess($t.Name, 'Register scheduled task')) {
                Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $trigger `
                    -Settings $settings -Description $t.Description -Force | Out-Null
                Write-Host "  [REGISTERED] $($t.Name)"
            }
        }
    }

    Write-Host ''
    Write-Host 'Done. Verify with:'
    Write-Host '  Get-ScheduledTask NFL_analytics_task_01, NFL_analytics_publish_01 | Get-ScheduledTaskInfo'
    Write-Host ''
}

# ------------------------------------------------------------------------------
# Entry point. Guarded so NOTHING runs at import time: the body executes only when
# this file is the script actually being invoked (-File / &), not when it is
# dot-sourced for inspection, where InvocationName is '.'. This is the PowerShell
# analogue of publish_web.R's commandArgs() check, and is used for the same reason
# -- so the functions above can be inspected or reused without side effects.
# ------------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    Register-NflScheduledTasks -ProjectDir $ProjectDir -PublishMode $PublishMode -DryRun:$DryRun
}
