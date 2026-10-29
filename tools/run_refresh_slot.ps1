<#
.SYNOPSIS
    Drives one score-refresh slot (B or C) end to end from this workstation:
    dispatch each sport's "Refresh live results", wait for each to finish, then
    dispatch the aggregator's subtree sync, which publishes.

.DESCRIPTION
    WHY THIS EXISTS -- READ THIS BEFORE "SIMPLIFYING" IT BACK INTO CRON.

    GitHub's scheduled triggers are best-effort: delayed under load and dropped
    outright during peak periods, with no notification either way. Measured in
    this workspace on 2026-10-28, across every scheduled run that has ever
    fired here (4 of 4):

        MLB        `0 11 * * *`  ->  17:09:37Z, 16:15:19Z   (~5h15m late)
        aggregator `30 13 * * *` ->  19:27:10Z, 18:47:05Z   (~5h17m late)

    Windows Task Scheduler on this box, same day, across all five registered
    pipeline tasks: fired at :00:02. Two seconds.

    That gap is the whole argument. The old design had each sport refresh on a
    GitHub cron and the aggregator sync 30 minutes behind it, with correct
    ordering depending on both crons being punctual. They are not, and they are
    not even late by the SAME amount -- so the 30-minute lag was never a
    guarantee, just a bet that happened to keep winning. Worse, slot B (22:00
    UTC) delayed 5-6 hours lands on top of slot C (05:00 UTC): the two slots
    collapse into one overnight cluster and the afternoon refresh silently
    stops existing.

    So the trigger moves here, where it fires in seconds, and ordering becomes
    sequential rather than hoped-for. The actual work still runs on GitHub's
    hosted runners -- this script only starts things and waits. Measured
    end-to-end on 2026-10-28: refresh 1m00s, sync 13s, Pages deploy ~2m, so a
    slot completes in about 3.5 minutes. The 30-minute lag it replaces was
    absorbing scheduler jitter, badly, around work that takes minutes.

    WHAT THIS DOES NOT DO: it does not refresh projections, ratings or anything
    model-derived. Those belong to slot A (09:00 local, the full DAG, on this
    same box). Each sport's tools/refresh_live_results.R patches finished
    scores plus the grading and slate counts that follow mechanically from
    them, into already-committed JSON. See that script's header.

    WHY IT ALWAYS SYNCS, even when a refresh changed nothing: the aggregator's
    sync-sports.yml only dispatches deploy.yml when a subtree pull produced a
    new commit, so a quiet night publishes nothing. Detecting "did anything
    change" here as well would duplicate a guard that already exists one layer
    down, and get it subtly wrong the first time a sport is added.

    NOTHING RUNS AT IMPORT TIME. This file defines functions plus one guarded
    entry point, so dot-sourcing it for inspection is side-effect-free.

.PARAMETER Slot
    'B' (afternoon, 18:00 local) or 'C' (overnight, 01:00 local). This is a
    LABEL ONLY: it names the slot in the log so an unattended run can be told
    apart from its sibling. The work the two slots do is identical, and
    deliberately so -- re-patching an already-final score is idempotent, while
    missing one is not, so there is no reason to narrow the overnight sweep.

.PARAMETER DryRun
    Print every command that would be issued and change nothing. Use this
    first, always.

.PARAMETER Sports
    Override which sports to refresh. Defaults to all four sports (mlb, nfl,
    nba, wnba).

.PARAMETER LogDir
    Write a transcript of the run to this directory as slot-<Slot>-<stamp>.log.
    Unattended runs should always set this -- Task Scheduler records only an
    exit code, which tells you a slot failed but never why. Start-Transcript
    captures Write-Host, which is why progress goes through Write-Step.

.PARAMETER SkipSync
    Refresh the sport repos but do not dispatch the aggregator sync, so nothing
    is published. For debugging a single sport's refresh in isolation.

.EXAMPLE
    # Always do this first -- shows the full plan, changes nothing:
    powershell -NoProfile -File tools\run_refresh_slot.ps1 -Slot C -DryRun

.EXAMPLE
    # One sport, no publish, for debugging:
    powershell -NoProfile -File tools\run_refresh_slot.ps1 -Slot B -Sports nba -SkipSync
#>

[CmdletBinding()]
param(
    [ValidateSet('B', 'C')]
    [string] $Slot = 'C',

    [switch] $DryRun,

    [string[]] $Sports,

    [string] $LogDir = '',

    [switch] $SkipSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration -------------------------------------------------------

# Sport -> GitHub repo slug. These are NOT uniformly named (MLB uses a hyphen
# and title case, the other three use an underscore and lowercase 'analytics');
# do not try to derive them from the sport name.
#
# WNBA is formally included now (addressing WNBA_analytics Issue #103 and
# front-office Issue #38). WNBA has its refresh-results.yml workflow and slate
# patching in place, so it is dispatched and synchronized along with MLB, NFL,
# and NBA.
$SPORT_REPOS = [ordered]@{
    mlb  = 'kailot-harris/MLB-Analytics'
    nfl  = 'kailot-harris/NFL_analytics'
    nba  = 'kailot-harris/NBA_analytics'
    wnba = 'kailot-harris/WNBA_analytics'
}

$AGGREGATOR_REPO   = 'kailot-harris/front-office'
$REFRESH_WORKFLOW  = 'Refresh live results'
$SYNC_WORKFLOW     = 'Sync sport subtrees and deploy'

# NO DISPATCH INPUTS ARE SENT, and that is a decision, not an omission.
#
# The three refresh workflows do NOT share an input name -- MLB and NFL take
# `season` (default '2026'), NBA takes `lookback_days` (default '3'). An
# earlier version of this script passed lookback_days to all three and got
# HTTP 422 "Unexpected inputs provided" from MLB on the first real run.
#
# Every one of those inputs is `required: false` with a default declared in
# the workflow itself, so sending nothing makes each workflow use its own
# default. That keeps the default in ONE place -- the workflow -- instead of
# duplicating it here, where it would drift the first time a season rolls
# over. If a slot ever genuinely needs a non-default input, add a per-sport
# input map; do not add a single slot-wide one, because the names differ.

# How long to wait for a dispatched run to appear in the API before giving up.
# A dispatch returns no run id, so the run has to be found by polling; this is
# normally satisfied on the first or second attempt.
$RUN_DISCOVERY_ATTEMPTS = 10
$RUN_DISCOVERY_DELAY_S  = 3

# --- Helpers -------------------------------------------------------------

function Write-Step {
    <#
        Write-Host, not Write-Output, and this is load-bearing. These messages
        are emitted from inside functions whose return value the caller
        assigns ($ok = Invoke-WorkflowAndWait ...). Anything written to the
        success stream there becomes part of that return value: the caller
        gets an array instead of a boolean, every progress line vanishes from
        the console, and the truthiness check silently starts passing. Caught
        on the first dry run of this script.
    #>
    param([string] $Message)
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}

function Invoke-Gh {
    <#
        Runs gh and returns stdout. Native stderr is deliberately NOT
        redirected: in Windows PowerShell 5.1 redirecting a native command's
        stderr wraps each line in an ErrorRecord and sets $? to $false even on
        exit code 0, which would make every successful gh call look like a
        failure. Exit code is the only thing trusted here.
    #>
    param([string[]] $GhArgs)

    $output = & gh @GhArgs
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($GhArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    return $output
}

function Get-LatestDispatchedRunId {
    <#
        Finds the run id for a workflow_dispatch just issued. `gh workflow run`
        prints a URL but exits without the id in a machine-readable form, so
        the run is located by taking the newest workflow_dispatch run created
        at or after the moment of dispatch.

        $Since is compared as an ISO-8601 string against createdAt, which is
        safe because GitHub always returns UTC with a trailing Z and the
        comparison is lexicographic over a fixed-width format.
    #>
    param(
        [string] $Repo,
        [string] $Workflow,
        [string] $Since
    )

    for ($attempt = 1; $attempt -le $RUN_DISCOVERY_ATTEMPTS; $attempt++) {
        $json = Invoke-Gh @(
            'run', 'list', '-R', $Repo, '-w', $Workflow, '-L', '10',
            '--json', 'databaseId,createdAt,event'
        )
        $runs = $json | ConvertFrom-Json

        $match = $runs |
            Where-Object { $_.event -eq 'workflow_dispatch' -and $_.createdAt -ge $Since } |
            Sort-Object createdAt -Descending |
            Select-Object -First 1

        if ($null -ne $match) { return $match.databaseId }

        Start-Sleep -Seconds $RUN_DISCOVERY_DELAY_S
    }

    throw "Dispatched a run of '$Workflow' in $Repo but it never appeared in the API"
}

function Invoke-WorkflowAndWait {
    <#
        Dispatches a workflow, waits for it to finish, and returns $true only
        if it concluded successfully. Does not throw on a failed run -- the
        caller decides whether one sport failing should stop the slot.
    #>
    param(
        [string]   $Repo,
        [string]   $Workflow,
        [string[]] $Inputs = @(),
        [switch]   $WhatIfOnly
    )

    $dispatch = @('workflow', 'run', $Workflow, '-R', $Repo)
    foreach ($i in $Inputs) { $dispatch += @('-f', $i) }

    if ($WhatIfOnly) {
        Write-Host  "  would run: gh $($dispatch -join ' ')"
        Write-Host  "  would then wait for completion with: gh run watch <id> -R $Repo --exit-status"
        return $true
    }

    # Stamped BEFORE the dispatch so the run cannot be created in the gap
    # between stamping and dispatching and then be missed by the >= filter.
    $since = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    Write-Step "dispatching '$Workflow' in $Repo"
    Invoke-Gh $dispatch | Out-Null

    $runId = Get-LatestDispatchedRunId -Repo $Repo -Workflow $Workflow -Since $since
    Write-Step "  run $runId started; waiting"

    & gh run watch $runId -R $Repo --exit-status --interval 15 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)

    if ($ok) { Write-Step "  run $runId succeeded" }
    else      { Write-Step "  run $runId FAILED (see: gh run view $runId -R $Repo --log-failed)" }

    return $ok
}

# --- Plan ----------------------------------------------------------------

function Get-SlotPlan {
    param(
        [string]   $Slot,
        [string[]] $Sports
    )

    $explicitOverride = ($null -ne $Sports -and $Sports.Count -gt 0)
    $selected = if ($explicitOverride) { $Sports } else { @($SPORT_REPOS.Keys) }

    foreach ($s in $selected) {
        if (-not $SPORT_REPOS.Contains($s)) {
            throw "Unknown sport '$s'. Known: $($SPORT_REPOS.Keys -join ', ')."
        }
    }

    # Step 1 (refresh) dispatches each sport in $selected. Step 2 (subtree sync)
    # syncs all 4 sports on a default full-slot run.
    # When -Sports is passed explicitly for single-sport debugging, narrow the
    # sync to match.
    $syncList = $selected

    return [pscustomobject]@{
        Slot       = $Slot
        Sports     = $selected
        SyncSports = ($syncList -join ' ')
    }
}

# --- Entry point ---------------------------------------------------------

function Invoke-RefreshSlot {
    param(
        [string]   $Slot,
        [switch]   $DryRun,
        [string[]] $Sports,
        [switch]   $SkipSync
    )

    $plan = Get-SlotPlan -Slot $Slot -Sports $Sports

    Write-Output "=== Refresh slot $($plan.Slot)"
    Write-Output "    sports:        $($plan.Sports -join ', ')"
    Write-Output "    publish:       $(if ($SkipSync) { 'NO (-SkipSync)' } else { 'yes, via ' + $SYNC_WORKFLOW })"
    if ($DryRun) { Write-Output "    MODE:          DRY RUN, nothing will be dispatched" }
    Write-Output ""

    $failed = @()

    foreach ($sport in $plan.Sports) {
        $repo = $SPORT_REPOS[$sport]
        $ok = Invoke-WorkflowAndWait `
            -Repo $repo `
            -Workflow $REFRESH_WORKFLOW `
            -WhatIfOnly:$DryRun

        if (-not $ok) { $failed += $sport }
    }

    # The sync still runs when a sport failed. A failed refresh leaves that
    # repo's JSON untouched, so syncing cannot publish bad data -- and
    # withholding the sync would also withhold the sports that DID succeed.
    if (-not $SkipSync) {
        Write-Output ""
        $syncOk = Invoke-WorkflowAndWait `
            -Repo $AGGREGATOR_REPO `
            -Workflow $SYNC_WORKFLOW `
            -Inputs @("sports=$($plan.SyncSports)", 'deploy=true') `
            -WhatIfOnly:$DryRun

        if (-not $syncOk) { $failed += 'aggregator-sync' }
    }

    Write-Output ""
    if ($failed.Count -gt 0) {
        Write-Output "=== slot $($plan.Slot) finished WITH FAILURES: $($failed -join ', ')"
        # Flag rather than `exit` here: `exit` inside a function unwinds the
        # whole script WITHOUT running the caller's finally block, which would
        # leave Start-Transcript open and the log truncated. The exit code is
        # set at the bottom, after the transcript is closed.
        $script:SlotFailed = $true
        return
    }

    Write-Output "=== slot $($plan.Slot) completed cleanly"
}

if ($MyInvocation.InvocationName -ne '.') {
    # Transcript is started here rather than inside Invoke-RefreshSlot so that
    # a parameter-validation throw (an unknown sport, say) is still captured.
    $script:SlotFailed = $false
    $transcribing = $false
    if ($LogDir) {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        Start-Transcript -Path (Join-Path $LogDir "slot-$Slot-$stamp.log") | Out-Null
        $transcribing = $true
    }

    try {
        Invoke-RefreshSlot `
            -Slot $Slot `
            -DryRun:$DryRun `
            -Sports $Sports `
            -SkipSync:$SkipSync
    }
    finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }

    # Non-zero so Task Scheduler records a failing LastTaskResult; a silently
    # green run is the exact failure mode this whole design exists to remove.
    if ($script:SlotFailed) { exit 1 }
}
