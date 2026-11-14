<#
.SYNOPSIS
    Drives one score-refresh slot (B or C) end to end from this workstation:
    run each sport's tools/refresh_live_results.R locally and push what it
    wrote, then dispatch the aggregator's subtree sync, which publishes.

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
    sequential rather than hoped-for. Measured end-to-end on 2026-10-28:
    refresh 1m00s, sync 13s, Pages deploy ~2m, so a slot completes in about
    3.5 minutes. The 30-minute lag it replaces was absorbing scheduler jitter,
    badly, around work that takes minutes.

    THE SCORE REFRESH RUNS ON THIS BOX, NOT ON A HOSTED RUNNER. The sport
    repos are private, so every hosted "Refresh live results" run drew on the
    account's Actions minutes: four sports, two slots a day, about 300 minutes
    a month for a script that needs R, jsonlite and a public scoreboard. This
    box already has all three. Each sport is refreshed in a dedicated detached
    worktree under <workspace>\.refresh-worktrees\<sport>, reset to
    origin/main at the start of every run, so the refresh sees exactly what a
    hosted runner's fresh clone would see and never touches the sport's
    primary checkout, whatever branch or state that is in. The sport repos
    keep their refresh-results.yml as a manual fallback; -HostedRefresh makes
    this script dispatch those instead. The aggregator is public, so its sync
    and Pages deploy still run hosted at no cost.

    MODEL REFRESH ON NEW RESULTS. Each sport's tools/refresh_live_results.R
    patches finished scores plus the grading and slate counts that follow
    mechanically from them, into already-committed JSON. It cannot refresh
    standings, ratings, projections or playoff odds: those need the pipeline
    caches, which live on this box. Left alone, a Thursday-night final showed
    its score on the site for hours while standings and playoff odds still
    described the world before the game.

    So when a sport's refresh run COMMITS something (new finals were written),
    and that sport is listed in $MODEL_REFRESH below, this script then runs
    that sport's own daily pipeline and publish wrappers locally, the same
    ones Task Scheduler runs for slot A, before dispatching the sync. A refresh
    that found nothing new triggers nothing, so a quiet slot still takes
    minutes. A slot with new NFL finals takes roughly 10-15 minutes longer.

    A failed model refresh is reported and fails the slot's exit code, but
    does not withhold the sync: the publish gate inside each sport's wrapper
    refuses to push a bad payload, so the worst case is the site keeps the
    patched scores with yesterday's odds, which is what it did before.

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

.PARAMETER SkipModelRefresh
    Do not run any local model pipeline, even when a refresh wrote new
    results. Restores the old scores-only behaviour for one run.

.PARAMETER HostedRefresh
    Dispatch each sport's hosted "Refresh live results" workflow instead of
    running the refresh locally. The pre-2026-11-14 behaviour; uses Actions
    minutes on the private sport repos.

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

    [switch] $SkipSync,

    [switch] $SkipModelRefresh,

    [switch] $HostedRefresh
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

# Resolved from this script's own location, same as register_refresh_tasks.ps1
# does for $REPO_DIR -- this is the checkout the scheduled task's
# WorkingDirectory points at, and the one Assert-ScheduledCheckoutSafety (below)
# has to land on `main`.
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$REPO_DIR   = Split-Path -Parent $SCRIPT_DIR

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

# Sports whose model outputs (standings, ratings, projections, playoff odds)
# are rebuilt locally when the score refresh wrote new results. Each step is a
# wrapper in that sport's checkout plus its arguments, run in order; the first
# failing step stops that sport. These are the SAME wrappers Task Scheduler
# runs for slot A, so there is one definition of "run the pipeline" per sport.
#
#   nfl: schedule_daily.bat runs the DAG; publishing is a separate wrapper.
#   nba: schedule_daily.bat runs the DAG and then its own publish gate.
#
# MLB and WNBA are not listed: both are out of season and their daily wrappers
# skip or do offseason work. Add a sport here when its season starts.
$MODEL_REFRESH = [ordered]@{
    nfl = @{
        Dir   = 'NFL Analytics'
        Steps = @(
            , @('schedule_daily.bat')
            , @('schedule_publish.bat', 'publish')
        )
    }
    nba = @{
        Dir   = 'NBA Analytics'
        Steps = @(
            , @('schedule_daily.bat')
        )
    }
}

# How each sport's score refresh is run locally. Dir is the sport's primary
# checkout (only used to reach its git object store); Paths are the files the
# refresh may rewrite, and the only ones ever staged. These mirror the "Commit
# any changes" step of each sport's refresh-results.yml; keep the two in step.
# Args mirror the workflow's input defaults where the script's own default
# differs: run bare, the NBA and WNBA scripts sweep only today, while their
# workflows sweep 3 days back, which is what catches a late final. MLB and NFL
# default to the current season on their own, so nothing is passed.
$SPORT_REFRESH = [ordered]@{
    mlb  = @{ Dir = 'MLB Analytics';  Args = @();    Paths = @('web/public/data') }
    nfl  = @{ Dir = 'NFL Analytics';  Args = @();    Paths = @('web/public/data/matchups_current_week.json', 'web/public/data/model_diagnostics.json') }
    nba  = @{ Dir = 'NBA Analytics';  Args = @('3'); Paths = @('web/public/data/matchups_slates.json') }
    wnba = @{ Dir = 'WNBA Analytics'; Args = @('3'); Paths = @('web/public/data/matchups_slates.json') }
}

# The sport checkouts sit beside the aggregator checkout this script lives in:
#   <workspace>\front-office-aggregator\tools\run_refresh_slot.ps1
#   <workspace>\NFL Analytics\...
# Override with FRONT_OFFICE_ROOT when running from a worktree.
$WORKSPACE_ROOT = if ($env:FRONT_OFFICE_ROOT) { $env:FRONT_OFFICE_ROOT } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

# Scratch worktrees owned by this script, one per sport. Outside every repo so
# they never show up as untracked files in a checkout guard's `git status`.
$REFRESH_WORKTREE_ROOT = Join-Path $WORKSPACE_ROOT '.refresh-worktrees'

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

# --- Local score refresh -------------------------------------------------

function Get-RscriptPath {
    <#
        Rscript from PATH, else the newest R under Program Files. Task
        Scheduler does not always inherit the interactive PATH.
    #>
    $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $found = Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return ''
}

function Invoke-LocalRefresh {
    <#
        Runs one sport's tools/refresh_live_results.R in that sport's scratch
        worktree and pushes a commit if it wrote new results. Returns an object
        with Ok (the refresh ran and anything it wrote is on origin/main) and
        Committed (new results were pushed). Never throws for a sport-level
        failure -- the caller decides whether one sport failing stops the slot.

        The worktree is reset hard to origin/main first. That is safe here and
        nowhere else: it is this script's own scratch space, nothing else
        writes to it, and anything left in it is a failed earlier run's
        half-written output.

        Native output is piped to Out-Host for the reason given in Write-Step:
        anything left on the success stream would become part of the return
        value.
    #>
    param(
        [string] $Sport,
        [switch] $WhatIfOnly
    )

    $cfg     = $SPORT_REFRESH[$Sport]
    $repoDir = Join-Path $WORKSPACE_ROOT $cfg.Dir
    $wt      = Join-Path $REFRESH_WORKTREE_ROOT $Sport
    $result  = [pscustomobject]@{ Ok = $false; Committed = $false }

    if ($WhatIfOnly) {
        Write-Host "  would reset worktree '$wt' to origin/main of '$repoDir'"
        Write-Host "  would run: Rscript tools/refresh_live_results.R $($cfg.Args -join ' ')"
        Write-Host "  would commit and push to main if any of these changed: $($cfg.Paths -join ', ')"
        $result.Ok = $true
        return $result
    }

    Write-Step "refreshing $Sport results locally"

    if (-not (Test-Path (Join-Path $repoDir '.git'))) {
        Write-Step "  $Sport refresh FAILED: no checkout at '$repoDir'"
        return $result
    }
    $rscript = Get-RscriptPath
    if (-not $rscript) {
        Write-Step "  $Sport refresh FAILED: Rscript not found on PATH or under C:\Program Files\R"
        return $result
    }

    & git -C $repoDir fetch --quiet origin main | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Step "  $Sport refresh FAILED: could not fetch origin/main"
        return $result
    }

    if (-not (Test-Path (Join-Path $wt '.git'))) {
        & git -C $repoDir worktree add --quiet --detach $wt origin/main | Out-Host
    }
    else {
        & git -C $wt reset --quiet --hard | Out-Host
        & git -C $wt clean -fdq | Out-Host
        & git -C $wt checkout --quiet --detach origin/main | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Step "  $Sport refresh FAILED: could not prepare worktree '$wt'"
        return $result
    }

    # renv's autoloader is switched off for this call, as the sport repos' CI
    # does: in a fresh worktree it would activate an empty project library and
    # hide the jsonlite installed in the user library.
    $refreshArgs = @($cfg.Args)
    $renvBefore  = $env:RENV_CONFIG_AUTOLOADER_ENABLED
    $env:RENV_CONFIG_AUTOLOADER_ENABLED = 'FALSE'
    Push-Location $wt
    try {
        & $rscript 'tools/refresh_live_results.R' @refreshArgs | Out-Host
        $rc = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $env:RENV_CONFIG_AUTOLOADER_ENABLED = $renvBefore
    }
    if ($rc -ne 0) {
        Write-Step "  $Sport refresh FAILED: refresh_live_results.R exited $rc"
        return $result
    }

    $changed = & git -C $wt status --porcelain -- @($cfg.Paths)
    if ([string]::IsNullOrWhiteSpace(($changed -join ''))) {
        Write-Step "  ${Sport}: no newly finished games; nothing to commit"
        $result.Ok = $true
        return $result
    }

    & git -C $wt add -- @($cfg.Paths) | Out-Host
    & git -C $wt commit --quiet `
        -m 'chore(data): refresh finished game results' `
        -m 'Written by the aggregator''s tools/run_refresh_slot.ps1 running tools/refresh_live_results.R on the scheduling workstation. Scores, plus the grading and counts that follow mechanically from them - no prediction was recomputed and no model was re-fit.' | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Step "  $Sport refresh FAILED: could not commit the refreshed results"
        return $result
    }

    & git -C $wt push --quiet origin HEAD:main | Out-Host
    if ($LASTEXITCODE -ne 0) {
        # Something else landed on main while the refresh ran. Replay the one
        # commit on top of it and try once more.
        Write-Step "  ${Sport}: push rejected; rebasing onto the new origin/main and retrying once"
        & git -C $wt fetch --quiet origin main | Out-Host
        & git -C $wt rebase --quiet origin/main | Out-Host
        if ($LASTEXITCODE -ne 0) {
            & git -C $wt rebase --abort | Out-Host
            Write-Step "  $Sport refresh FAILED: refreshed results conflict with a newer commit on main"
            return $result
        }
        & git -C $wt push --quiet origin HEAD:main | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Step "  $Sport refresh FAILED: could not push the refreshed results"
            return $result
        }
    }

    $sha = ([string] (& git -C $wt rev-parse --short HEAD)).Trim()
    Write-Step "  ${Sport}: pushed refreshed results ($sha)"
    $result.Ok = $true
    $result.Committed = $true
    return $result
}

# --- Checkout safety ------------------------------------------------------

function Assert-ScheduledCheckoutSafety {
    <#
        GUARDS AGAINST THE SHARED-CHECKOUT COLLISION IN front-office issue #105.

        This script's WorkingDirectory IS the same checkout that interactive
        sessions and agents use for feature work (see register_refresh_tasks.ps1,
        which sets -WorkingDirectory $REPO_DIR). On 2026-11-10, a scheduled
        pipeline in a sibling repo ran successfully while a subagent had left
        that same checkout on a feature branch with uncommitted changes. The
        downstream publish gate correctly refused
        ("assertion E FAILED ... HEAD=<branch> expected=main"), but a later
        cleanup pass discarded 8 regenerated JSON files and a cache file by
        running `git checkout -- .` without stashing first, instead of landing
        on main the safe way. Published data stayed stale for ~30 hours.

        So before this script dispatches anything, it forces THIS checkout
        back onto `main`, stashing (never discarding) whatever a feature
        branch left behind, and refuses to proceed -- loudly, non-zero exit --
        if it cannot land cleanly on `main`. Feature work belongs in its own
        `git worktree`; this checkout is for the scheduled pipeline only and
        must stay on `main` and clean. See CLAUDE.md, "Scheduled checkouts
        stay on main".
    #>
    param(
        [Parameter(Mandatory)] [string] $RepoDir,
        [switch] $WhatIfOnly
    )

    function Invoke-CheckoutGit {
        <#
            Native stderr is deliberately NOT redirected -- same reasoning as
            Invoke-Gh above: in Windows PowerShell 5.1, redirecting a native
            command's stderr wraps each line in an ErrorRecord and sets $? to
            $false even on exit code 0 (e.g. git's routine "LF will be
            replaced by CRLF" notice on stash/checkout). Only $LASTEXITCODE is
            trusted for success/failure here.
        #>
        param([string[]] $GitArgs)
        $output = & git -C $RepoDir @GitArgs
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }

    if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
        throw "CHECKOUT GUARD FAILED: $RepoDir does not look like a git checkout (no .git). Refusing to run a scheduled pipeline here."
    }

    $branch = Invoke-CheckoutGit @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($branch.ExitCode -ne 0) {
        throw "CHECKOUT GUARD FAILED: could not determine current branch in $RepoDir -- $($branch.Output)"
    }
    $currentBranch = $branch.Output.Trim()

    $status = Invoke-CheckoutGit @('status', '--porcelain')
    if ($status.ExitCode -ne 0) {
        throw "CHECKOUT GUARD FAILED: 'git status' failed in $RepoDir -- $($status.Output)"
    }
    $isDirty = -not [string]::IsNullOrWhiteSpace($status.Output)

    if ($currentBranch -eq 'main' -and -not $isDirty) {
        Write-Step "checkout guard: already on main and clean -- proceeding"
        return
    }

    Write-Step "checkout guard: HEAD=$currentBranch dirty=$isDirty -- stashing (if needed) and landing on main"

    if ($WhatIfOnly) {
        if ($isDirty) { Write-Host "  would run: git -C $RepoDir stash push -u -m 'issue-105 scheduled-checkout-guard'" }
        Write-Host "  would run: git -C $RepoDir checkout main"
        return
    }

    if ($isDirty) {
        $stash = Invoke-CheckoutGit @('stash', 'push', '-u', '-m', 'issue-105 scheduled-checkout-guard')
        if ($stash.ExitCode -ne 0) {
            throw "CHECKOUT GUARD FAILED: 'git stash -u' failed in $RepoDir -- $($stash.Output). Refusing to touch a dirty checkout it could not safely preserve."
        }
        Write-Step "  stashed dirty tree: $($stash.Output.Trim())"
    }

    $checkout = Invoke-CheckoutGit @('checkout', 'main')
    if ($checkout.ExitCode -ne 0) {
        throw "CHECKOUT GUARD FAILED: 'git checkout main' failed in $RepoDir -- $($checkout.Output). Refusing to run a scheduled pipeline from a non-main checkout. (Work was stashed, not lost -- see 'git stash list'.)"
    }

    # Do not trust exit codes alone -- re-verify the landing spot, since this
    # is exactly the assertion that failed to stop issue #105's bad cleanup.
    $verifyBranch = (Invoke-CheckoutGit @('rev-parse', '--abbrev-ref', 'HEAD')).Output.Trim()
    $verifyStatus = (Invoke-CheckoutGit @('status', '--porcelain')).Output

    if ($verifyBranch -ne 'main') {
        throw "CHECKOUT GUARD FAILED: expected HEAD=main after checkout, got HEAD=$verifyBranch in $RepoDir. Refusing to run."
    }
    if (-not [string]::IsNullOrWhiteSpace($verifyStatus)) {
        throw "CHECKOUT GUARD FAILED: $RepoDir is still dirty after stash+checkout in $RepoDir. Refusing to run. Status:`n$verifyStatus"
    }

    Write-Step "checkout guard: landed cleanly on main"
}

# --- Plan ----------------------------------------------------------------

function Get-RemoteHead {
    <#
        The sha at the tip of a repo's main branch, or '' if it cannot be read.
        Compared before and after a refresh run to learn whether that run
        committed new results. An unreadable sha is treated as "unknown" and
        never triggers a model refresh.
    #>
    param([string] $Repo)

    $sha = & gh api "repos/$Repo/commits/main" --jq '.sha'
    if ($LASTEXITCODE -ne 0 -or -not $sha) { return '' }
    return ([string] $sha).Trim()
}

function Invoke-ModelRefresh {
    <#
        Runs one sport's local pipeline wrappers so standings, ratings and
        playoff odds reflect the results the refresh just committed. Returns
        $true only if every step exited 0.
    #>
    param(
        [string] $Sport,
        [switch] $WhatIfOnly
    )

    $cfg = $MODEL_REFRESH[$Sport]
    $dir = Join-Path $WORKSPACE_ROOT $cfg.Dir

    if ($WhatIfOnly) {
        Write-Host "  would pull main in '$dir', then run:"
        foreach ($step in $cfg.Steps) { Write-Host "    $($step -join ' ')" }
        return $true
    }

    if (-not (Test-Path (Join-Path $dir '.git'))) {
        Write-Step "  $Sport model refresh SKIPPED: no checkout at '$dir'"
        return $false
    }

    # The publish gate only pushes from main, and the pipeline must start from
    # the results the refresh just committed, or its push is rejected.
    $branch = (& git -C $dir rev-parse --abbrev-ref HEAD)
    if ($LASTEXITCODE -ne 0 -or ([string] $branch).Trim() -ne 'main') {
        Write-Step "  $Sport model refresh SKIPPED: checkout is on '$branch', not main"
        return $false
    }
    & git -C $dir pull --quiet --rebase --autostash origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Step "  $Sport model refresh SKIPPED: could not bring the checkout up to date with origin/main"
        return $false
    }

    foreach ($step in $cfg.Steps) {
        $bat = Join-Path $dir $step[0]
        if (-not (Test-Path $bat)) {
            Write-Step "  $Sport model refresh FAILED: missing $bat"
            return $false
        }
        $stepArgs = if ($step.Count -gt 1) { $step[1..($step.Count - 1)] } else { @() }
        Write-Step "  $Sport model refresh: $($step -join ' ')"
        Push-Location $dir
        try {
            & cmd.exe /c $bat @stepArgs
            $rc = $LASTEXITCODE
        }
        finally { Pop-Location }
        if ($rc -ne 0) {
            Write-Step "  $Sport model refresh FAILED: $($step[0]) exited $rc (see that sport's logs)"
            return $false
        }
    }

    Write-Step "  $Sport model refresh completed"
    return $true
}

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
        [switch]   $SkipSync,
        [switch]   $SkipModelRefresh,
        [switch]   $HostedRefresh
    )

    Assert-ScheduledCheckoutSafety -RepoDir $REPO_DIR -WhatIfOnly:$DryRun

    $plan = Get-SlotPlan -Slot $Slot -Sports $Sports

    Write-Output "=== Refresh slot $($plan.Slot)"
    Write-Output "    sports:        $($plan.Sports -join ', ')"
    Write-Output "    refresh:       $(if ($HostedRefresh) { 'hosted workflow (-HostedRefresh)' } else { 'local, in ' + $REFRESH_WORKTREE_ROOT })"
    Write-Output "    publish:     $(if ($SkipSync) { 'NO (-SkipSync)' } else { 'yes, via ' + $SYNC_WORKFLOW })"
    Write-Output "    model refresh: $(if ($SkipModelRefresh) { 'NO (-SkipModelRefresh)' } else { 'on new results, for ' + (@($MODEL_REFRESH.Keys) -join ', ') })"
    if ($DryRun) { Write-Output "    MODE:          DRY RUN, nothing will be dispatched" }
    Write-Output ""

    $failed = @()

    foreach ($sport in $plan.Sports) {
        $repo = $SPORT_REPOS[$sport]
        $wantsModel = (-not $SkipModelRefresh) -and $MODEL_REFRESH.Contains($sport)
        $committed = $false

        if ($HostedRefresh) {
            $headBefore = if ($wantsModel -and -not $DryRun) { Get-RemoteHead -Repo $repo } else { '' }

            $ok = Invoke-WorkflowAndWait `
                -Repo $repo `
                -Workflow $REFRESH_WORKFLOW `
                -WhatIfOnly:$DryRun

            # The hosted refresh commits only when it wrote new finals, so a
            # moved tip is the signal. Another push landing in the same minute
            # would also move it; the cost of that false positive is one extra
            # pipeline run.
            if ($ok -and $headBefore) {
                $headAfter = Get-RemoteHead -Repo $repo
                $committed = [bool] ($headAfter -and $headBefore -ne $headAfter)
            }
        }
        else {
            $refresh   = Invoke-LocalRefresh -Sport $sport -WhatIfOnly:$DryRun
            $ok        = $refresh.Ok
            $committed = $refresh.Committed
        }

        if (-not $ok) { $failed += $sport; continue }
        if (-not $wantsModel) { continue }

        if ($DryRun) {
            Write-Host "  if that refresh commits new results:"
            [void] (Invoke-ModelRefresh -Sport $sport -WhatIfOnly)
            continue
        }

        if ($committed) {
            Write-Step "  $sport has new results; refreshing standings and odds"
            $modelOk = Invoke-ModelRefresh -Sport $sport
            if (-not $modelOk) { $failed += "$sport-model-refresh" }
        }
        else {
            Write-Step "  $sport has no new results; model refresh not needed"
        }
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
            -SkipSync:$SkipSync `
            -SkipModelRefresh:$SkipModelRefresh `
            -HostedRefresh:$HostedRefresh
    }
    finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
    }

    # Non-zero so Task Scheduler records a failing LastTaskResult; a silently
    # green run is the exact failure mode this whole design exists to remove.
    if ($script:SlotFailed) { exit 1 }
}
