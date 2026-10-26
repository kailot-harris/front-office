<#
.SYNOPSIS
    Proves (or disproves) that a push-capable credential is reachable from a
    NON-INTERACTIVE Task Scheduler session. GitHub issue #42.

.DESCRIPTION
    Issue #42's gap: a push-capable credential demonstrably exists on this machine
    (gh CLI OS keyring, plus credential.helper=manager in both repos), but that only
    proves credentials work for an INTERACTIVE terminal session. Git Credential
    Manager stores credentials for the interactive user session; a task configured
    "run whether logged on or not" runs in a non-interactive session and can silently
    fail to reach GCM. The failure mode is the 09:00 publish hanging on an auth prompt
    or failing obscurely at a time nobody is watching.

    This script closes that gap by executing a REAL push from whatever session it is
    run in, to both remotes the live publish touches:
        NFL_analytics   (this repo's origin)
        front-office    (front-office-aggregator's origin -- the Pages repo)

    It is meant to be registered as an ON-DEMAND scheduled task so the push really
    does happen in a scheduler session rather than in a terminal. See
    tools/register_credential_probe_task.ps1 and docs/SCHEDULING.md.

    WHY THIS IS SAFE TO RUN AGAINST PRODUCTION REMOTES
      * It creates NO commit. It pushes the EXISTING HEAD commit to a throwaway remote
        ref, refs/heads/cred-probe/<timestamp>-<pid>, then deletes that ref. Net effect
        on the remote is nothing.
      * It never pushes to main. deploy.yml triggers on "push: branches: [main]" only,
        so a cred-probe/* branch cannot start a Pages deploy. Verified against
        front-office-aggregator/.github/workflows/deploy.yml on 2026-10-24.
      * It creates no local branch and leaves the working tree untouched: the push
        refspec is HEAD:refs/heads/<probe>, so nothing local is written.
      * It CANNOT HANG. GIT_TERMINAL_PROMPT=0 and GCM_INTERACTIVE=never make git fail
        fast instead of prompting, and every git invocation is additionally bounded by
        -TimeoutSec and killed if it overruns. A hang is the specific failure #42
        predicts, so this script turns it into a bounded, logged failure.

    WHAT IT DOES NOT DO
      * It does not read, print or log any credential. It deliberately never calls
        "git credential fill", which would emit a secret into the log. Auth is probed
        only through the pass/fail of real git operations.
      * It does not modify the publish task's mode. Switching schedule_publish.bat
        from dryrun to publish stays a separate, deliberate human step -- see
        docs/SCHEDULING.md "Do not enable --publish until #42 is proven".

    INTERPRETING THE RESULT
      Each repo is probed in two stages so a failure says WHICH half is broken:
        ls-remote  -> can this session authenticate for READ?
        push       -> can this session authenticate for WRITE? (the #42 question)
      A read that works while a write fails points at token scopes; both failing in a
      scheduler session while both work in a terminal is the GCM-unreachable diagnosis
      #42 anticipates, whose documented remedies are a PAT in the task environment, a
      dedicated credential store, or a different auth mechanism.

    Exit codes: 0 = every probe pushed and cleaned up (credentials work in this
    session). 1 = at least one probe failed (read the verdict block). 2 = precondition
    failure, nothing was attempted.

.PARAMETER ProjectDir
    This NFL repo's root. Mirrors config.R's PROJECT_DIR for the same reason the .bat
    wrappers do: a PowerShell script cannot source R, and we must start somewhere.

.PARAMETER AggregatorDir
    The front-office-aggregator checkout, whose origin is the front-office Pages repo.

.PARAMETER TimeoutSec
    Hard per-git-command timeout. 60s is generous for a single-ref push; its purpose
    is bounding the auth-prompt hang, not bounding slow networks.

.PARAMETER DryRun
    Run the context capture and the READ probe (ls-remote) only. Pushes nothing.
    Use this to confirm the script itself works before registering the task. A dry run
    CANNOT answer issue #42 -- only a real push can.

.EXAMPLE
    powershell -NoProfile -File tools\test_unattended_push.ps1 -DryRun

.EXAMPLE
    powershell -NoProfile -File tools\test_unattended_push.ps1

.NOTES
    Log: logs\credential_probe.log (appended; logs/*.log is gitignored at
    .gitignore:56, so probe output is never committed). Kept out of
    pipeline_execution.log on purpose -- this is a one-off diagnostic, and
    schedule_daily.bat owns that file's rotation.
#>
[CmdletBinding()]
param(
    [string] $ProjectDir    = 'c:\Users\kailo\kayceeslices\front-office\nfl analytics',
    [string] $AggregatorDir = 'c:\Users\kailo\kayceeslices\front-office\front-office-aggregator',
    [int]    $TimeoutSec    = 60,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Logging. Writes to both the log file and stdout, so an interactive run shows its
# work and a scheduler run (whose stdout goes nowhere) still leaves a record.
# ------------------------------------------------------------------------------
$script:LogFile = $null

function Write-Probe {
    param([string] $Message)

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line  = "[$stamp] $Message"
    Write-Host $line
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8
    }
}

function Initialize-ProbeLog {
    param([Parameter(Mandatory)] [string] $ProjectDir)

    $logDir = Join-Path $ProjectDir 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $script:LogFile = Join-Path $logDir 'credential_probe.log'
}

# ------------------------------------------------------------------------------
# Bounded git invocation.
#
# Start-Process + WaitForExit(ms) rather than the call operator because the whole
# point is surviving a git that blocks forever on an auth prompt: "& git ..." would
# inherit that block and hang the task until ExecutionTimeLimit kills it hours later.
# Here an overrun is killed, reported as exit 124, and the probe continues.
# ------------------------------------------------------------------------------
function Invoke-GitBounded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $RepoPath,
        [Parameter(Mandatory)] [string[]] $GitArgs,
        [int] $TimeoutSec = 60
    )

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()

    # Quote any argument containing whitespace; the refspecs here do not, but a
    # relocated checkout path would.
    $quoted = foreach ($a in $GitArgs) {
        if ($a -match '\s') { '"' + $a + '"' } else { $a }
    }
    $argLine = $quoted -join ' '

    $result = [pscustomobject]@{
        Command  = "git $argLine"
        ExitCode = $null
        TimedOut = $false
        Stdout   = ''
        Stderr   = ''
    }

    try {
        $proc = Start-Process -FilePath 'git.exe' -ArgumentList $argLine `
            -WorkingDirectory $RepoPath -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        $exited = $proc.WaitForExit($TimeoutSec * 1000)

        if (-not $exited) {
            $result.TimedOut = $true
            $result.ExitCode = 124
            try { $proc.Kill() } catch { }
            # Let the handles release before reading the redirect files.
            Start-Sleep -Milliseconds 250
        } else {
            # The timed WaitForExit($ms) overload returns as soon as the process
            # signals, but the Process object's ExitCode is not populated until the
            # parameterless overload has reaped it -- without this second call
            # ExitCode reads back as $null and every probe looks like a failure.
            $proc.WaitForExit()
            try {
                $result.ExitCode = [int] $proc.ExitCode
            } catch {
                # Never silently coerce an unknown exit into success: an unreadable
                # exit code is itself a failure to report, not a pass.
                $result.ExitCode = 125
            }
        }

        if (Test-Path -LiteralPath $outFile) {
            $result.Stdout = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)
        }
        if (Test-Path -LiteralPath $errFile) {
            $result.Stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }

    return $result
}

function Write-GitOutcome {
    param(
        [Parameter(Mandatory)] [object] $Result,
        [Parameter(Mandatory)] [string] $Label
    )

    if ($Result.TimedOut) {
        Write-Probe ("    [TIMEOUT] {0} -- killed after the timeout. This is the auth-prompt hang #42 predicts." -f $Label)
    } elseif ($Result.ExitCode -eq 0) {
        Write-Probe ("    [OK]      {0}" -f $Label)
    } else {
        Write-Probe ("    [FAIL]    {0} -- git exit {1}" -f $Label, $Result.ExitCode)
    }

    foreach ($stream in @($Result.Stdout, $Result.Stderr)) {
        if (-not [string]::IsNullOrWhiteSpace($stream)) {
            foreach ($l in ($stream -split '\r?\n')) {
                if (-not [string]::IsNullOrWhiteSpace($l)) {
                    Write-Probe ("              | {0}" -f $l.TrimEnd())
                }
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Session context. The whole question #42 asks is "which kind of session is this",
# so record the evidence that distinguishes them rather than assuming.
# ------------------------------------------------------------------------------
function Write-SessionContext {
    Write-Probe '-- Session context ------------------------------------------------'
    Write-Probe ("    User                       : {0}" -f [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-Probe ("    Environment.UserInteractive: {0}" -f [Environment]::UserInteractive)
    Write-Probe ("    SESSIONNAME                : {0}" -f $env:SESSIONNAME)
    Write-Probe ("    Process session id         : {0}" -f (Get-Process -Id $PID).SessionId)
    Write-Probe ("    Machine / PID              : {0} / {1}" -f $env:COMPUTERNAME, $PID)

    # Session 0 with no SESSIONNAME is the signature of a "run whether logged on or
    # not" task; an interactive console run shows SESSIONNAME=Console and a non-zero
    # session id. UserInteractive=False is the clearest single discriminator.
    if ([Environment]::UserInteractive) {
        Write-Probe '    => INTERACTIVE session. A pass here does NOT close #42; see the verdict note.'
    } else {
        Write-Probe '    => NON-INTERACTIVE session. This is the context #42 is about.'
    }

    # Token presence is part of the diagnosis: a PAT in the environment is one of
    # #42's documented remedies, so note WHETHER one is set. The value is never read
    # or logged -- only its presence and length.
    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN')) {
        $val = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrEmpty($val)) {
            Write-Probe ("    {0,-27}: (not set)" -f $name)
        } else {
            Write-Probe ("    {0,-27}: SET (length {1}, value not logged)" -f $name, $val.Length)
        }
    }
    Write-Probe ''
}

# ------------------------------------------------------------------------------
# One repo's probe: read test, then the real write test, then cleanup.
# ------------------------------------------------------------------------------
function Test-RepoPush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $ProbeRef,
        [Parameter(Mandatory)] [int]    $TimeoutSec,
        [switch] $DryRun
    )

    $outcome = [pscustomobject]@{
        Label         = $Label
        RepoPath      = $RepoPath
        Remote        = ''
        Branch        = ''
        Commit        = ''
        ReadOk        = $false
        PushOk        = $false
        PushAttempted = $false
        CleanupOk     = $false
        LeftoverRef   = $null
        Diagnosis     = ''
    }

    Write-Probe ("-- Probe: {0} ----------------------------------------------" -f $Label)

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        $outcome.Diagnosis = "Not a git repository: $RepoPath"
        Write-Probe ("    [FAIL]    {0}" -f $outcome.Diagnosis)
        return $outcome
    }

    $remote = Invoke-GitBounded -RepoPath $RepoPath -GitArgs @('remote', 'get-url', 'origin') -TimeoutSec $TimeoutSec
    if ($remote.ExitCode -ne 0) {
        $outcome.Diagnosis = 'Could not resolve origin URL.'
        Write-GitOutcome -Result $remote -Label 'git remote get-url origin'
        return $outcome
    }
    $outcome.Remote = $remote.Stdout.Trim()

    $branch = Invoke-GitBounded -RepoPath $RepoPath -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD') -TimeoutSec $TimeoutSec
    $commit = Invoke-GitBounded -RepoPath $RepoPath -GitArgs @('rev-parse', 'HEAD') -TimeoutSec $TimeoutSec
    $outcome.Branch = $branch.Stdout.Trim()
    $outcome.Commit = $commit.Stdout.Trim()

    Write-Probe ("    Repo    : {0}" -f $RepoPath)
    Write-Probe ("    Origin  : {0}" -f $outcome.Remote)
    Write-Probe ("    HEAD    : {0} @ {1}" -f $outcome.Branch, $outcome.Commit)
    Write-Probe ("    Probe   : refs/heads/{0}  (pushed then deleted; no commit is created)" -f $ProbeRef)

    # ---- Stage 1: READ auth -------------------------------------------------
    # Separating read from write is what makes a failure actionable: read-ok with
    # write-fail is a scope problem; both failing is a reachability problem.
    $ls = Invoke-GitBounded -RepoPath $RepoPath -GitArgs @('ls-remote', '--heads', 'origin') -TimeoutSec $TimeoutSec
    Write-GitOutcome -Result $ls -Label 'READ probe: git ls-remote --heads origin'
    $outcome.ReadOk = ($ls.ExitCode -eq 0)

    if ($DryRun) {
        Write-Probe '    [SKIP]    WRITE probe skipped (-DryRun). No ref was pushed.'
        Write-Probe '              A dry run cannot answer issue #42 -- only a real push can.'
        Write-Probe ''
        return $outcome
    }

    # ---- Stage 2: WRITE auth -- the actual issue #42 test -------------------
    # HEAD:refs/heads/<probe> pushes the existing commit to a new remote ref without
    # creating anything locally.
    $outcome.PushAttempted = $true
    $push = Invoke-GitBounded -RepoPath $RepoPath `
        -GitArgs @('push', 'origin', ("HEAD:refs/heads/{0}" -f $ProbeRef)) -TimeoutSec $TimeoutSec
    Write-GitOutcome -Result $push -Label ("WRITE probe: git push origin HEAD:refs/heads/{0}" -f $ProbeRef)
    $outcome.PushOk = ($push.ExitCode -eq 0)

    # ---- Stage 3: cleanup ---------------------------------------------------
    # Only meaningful if the push landed. A cleanup failure is reported separately and
    # does NOT fail the probe: the credential question was already answered by then,
    # and the remedy is a one-line manual delete, which we print.
    if ($outcome.PushOk) {
        $del = Invoke-GitBounded -RepoPath $RepoPath `
            -GitArgs @('push', 'origin', '--delete', $ProbeRef) -TimeoutSec $TimeoutSec
        Write-GitOutcome -Result $del -Label ("CLEANUP: git push origin --delete {0}" -f $ProbeRef)
        $outcome.CleanupOk = ($del.ExitCode -eq 0)

        if (-not $outcome.CleanupOk) {
            $outcome.LeftoverRef = $ProbeRef
            Write-Probe '    [WARN]    Probe ref survives on the remote. Delete it with:'
            Write-Probe ("              git -C ""{0}"" push origin --delete {1}" -f $RepoPath, $ProbeRef)
        }
    } else {
        Write-Probe '    [SKIP]    CLEANUP skipped: nothing was pushed, so there is nothing to delete.'
    }

    Write-Probe ''
    return $outcome
}

function Invoke-UnattendedPushTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProjectDir,
        [Parameter(Mandatory)] [string] $AggregatorDir,
        [int]    $TimeoutSec = 60,
        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $ProjectDir)) {
        Write-Error "ProjectDir does not exist: $ProjectDir"
        return 2
    }

    Initialize-ProbeLog -ProjectDir $ProjectDir

    Write-Probe '=================================================================='
    if ($DryRun) {
        Write-Probe 'ISSUE #42 CREDENTIAL PROBE -- DRY RUN (read probe only, pushes nothing)'
    } else {
        Write-Probe 'ISSUE #42 CREDENTIAL PROBE -- LIVE (executes a real push to both remotes)'
    }
    Write-Probe '=================================================================='

    Write-SessionContext

    # Fail fast instead of prompting. Without these two, the exact failure #42
    # predicts manifests as an indefinite block rather than an error -- which is why
    # they are set here and not left to the caller.
    $saved = @{
        GIT_TERMINAL_PROMPT = $env:GIT_TERMINAL_PROMPT
        GCM_INTERACTIVE     = $env:GCM_INTERACTIVE
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE     = 'never'
    Write-Probe 'GIT_TERMINAL_PROMPT=0 and GCM_INTERACTIVE=never for this run: git must fail'
    Write-Probe 'fast rather than wait on a prompt no scheduler session can answer.'
    Write-Probe ''

    $results = @()
    try {
        # One shared timestamp so both repos' probe refs are obviously one run.
        $stamp    = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $probeRef = "cred-probe/$stamp-$PID"

        $targets = @(
            [pscustomobject]@{ Label = 'NFL_analytics'; Path = $ProjectDir }
            [pscustomobject]@{ Label = 'front-office';  Path = $AggregatorDir }
        )

        foreach ($t in $targets) {
            $results += (Test-RepoPush -Label $t.Label -RepoPath $t.Path `
                -ProbeRef $probeRef -TimeoutSec $TimeoutSec -DryRun:$DryRun)
        }
    } finally {
        $env:GIT_TERMINAL_PROMPT = $saved.GIT_TERMINAL_PROMPT
        $env:GCM_INTERACTIVE     = $saved.GCM_INTERACTIVE
    }

    # ---- Verdict ------------------------------------------------------------
    Write-Probe '-- Verdict --------------------------------------------------------'
    $allOk = $true
    foreach ($r in $results) {
        if ($DryRun) {
            if ($r.ReadOk) {
                $state = 'read OK (write not attempted)'
            } else {
                $state = 'READ FAILED'
                $allOk = $false
            }
        } else {
            if ($r.PushOk) {
                $state = 'PUSH OK'
            } else {
                $state = 'PUSH FAILED'
                $allOk = $false
            }
        }
        Write-Probe ("    {0,-15} {1}" -f $r.Label, $state)
    }
    Write-Probe ''

    if ($DryRun) {
        Write-Probe '    DRY RUN: no ref was pushed, so issue #42 remains unproven by design.'
        Write-Probe '    Register the on-demand task and run it without -DryRun to settle it.'
        Write-Probe '=================================================================='
        Write-Probe ''
        if ($allOk) { return 0 } else { return 1 }
    }

    if ($allOk) {
        if ([Environment]::UserInteractive) {
            Write-Probe '    Both pushes succeeded -- but THIS WAS AN INTERACTIVE SESSION, which is'
            Write-Probe '    what #42 already takes for granted. Run this via the scheduled task to'
            Write-Probe '    get an answer that actually closes the issue.'
        } else {
            Write-Probe '    Both pushes succeeded from a NON-INTERACTIVE session. This is the'
            Write-Probe '    evidence issue #42 asks for: credentials are reachable unattended.'
            Write-Probe '    Attach this log to #42, then switch the publish task to live mode per'
            Write-Probe '    docs/SCHEDULING.md (register_scheduled_tasks.ps1 -PublishMode publish).'
        }
    } else {
        Write-Probe '    AT LEAST ONE PUSH FAILED. Do NOT switch the publish task to live mode.'
        Write-Probe '    Read the [FAIL]/[TIMEOUT] lines above. If READ passed and WRITE failed, the'
        Write-Probe '    credential lacks push scope. If both failed in a non-interactive session but'
        Write-Probe '    both pass in a terminal, GCM is unreachable unattended -- #42 names three'
        Write-Probe '    remedies: a PAT in the task environment, a dedicated credential store, or a'
        Write-Probe '    different auth mechanism. Document whichever you choose on the issue.'
    }

    $leftovers = @($results | Where-Object { $_.LeftoverRef })
    if ($leftovers.Count -gt 0) {
        Write-Probe ''
        Write-Probe ("    [WARN] {0} probe ref(s) were not cleaned up; see the CLEANUP lines above." -f $leftovers.Count)
    }

    Write-Probe '=================================================================='
    Write-Probe ''

    if ($allOk) { return 0 } else { return 1 }
}

# ------------------------------------------------------------------------------
# Entry point, guarded exactly as register_scheduled_tasks.ps1 is: nothing runs at
# import time, so this file can be dot-sourced for inspection side-effect-free.
# ------------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $code = Invoke-UnattendedPushTest -ProjectDir $ProjectDir -AggregatorDir $AggregatorDir `
        -TimeoutSec $TimeoutSec -DryRun:$DryRun
    exit $code
}
