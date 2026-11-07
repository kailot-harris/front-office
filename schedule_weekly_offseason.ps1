# ==============================================================================
# schedule_weekly_offseason.ps1 (MLB Analytics)
# PowerShell companion for the MLB Offseason Dynamics Monitor.
# Path: scripts/schedule_weekly_offseason.ps1 or repo root
#
# Cadence: Daily at 07:00 local (Slot A).
# Target task name: "MLB Analytics Schedule Weekly Offseason"
#   (Note: Task and file names are retained historically to preserve compatibility;
#   cadence is daily 07:00 local per issue #66, matching the 26h freshness gate).
#
# Flow:
#   1. Runs build_offseason_monitor.R
#   2. Runs tools/offseason/test_dag_end_to_end.R (pre-publish regression suite)
#   3. Runs tools/publish_web.R --publish --mode=offseason
#   4. Direct aggregator workflow dispatch:
#      gh workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb" -f deploy=true
#
# Conforms to blueprint §§ 9, 10 and zero-betting policy.
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('dryrun', 'publish')]
    [string]$Mode = 'publish',
    [switch]$AllowDegraded
)

$ErrorActionPreference = 'Stop'

$ProjectDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectDir "config.R"))) {
    $ProjectDir = Split-Path -Parent $ProjectDir
}
Set-Location -Path $ProjectDir

# Defense-in-depth for git commit identity resolution under Task Scheduler
if (-not $env:HOME -and $env:USERPROFILE) {
    $env:HOME = $env:USERPROFILE
}

$LogDir = Join-Path $ProjectDir "logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$LogFile = Join-Path $LogDir "mlb_pipeline.log"

function Write-PipelineLog([string]$Level, [string]$Message) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] [schedule_weekly_offseason.ps1] $Message"
    Add-Content -Path $LogFile -Value $entry -Encoding utf8
    if ($Level -eq "ERROR") {
        Write-Error $Message
    } else {
        Write-Host $entry
    }
}

Write-PipelineLog "INFO" "=================================================================="
Write-PipelineLog "INFO" "Starting daily offseason monitor pipeline run (Mode=$Mode)..."
Write-PipelineLog "INFO" "=================================================================="

# Locate Rscript
$Rscript = "Rscript"
$rscriptCmd = Get-Command "Rscript" -ErrorAction SilentlyContinue
if (-not $rscriptCmd) {
    $knownR = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
    if (Test-Path $knownR) {
        $Rscript = $knownR
    } else {
        $rDirs = Get-ChildItem -Path "C:\Program Files\R" -Filter "R-*" -ErrorAction SilentlyContinue
        if ($rDirs) {
            $latest = $rDirs | Sort-Object Name -Descending | Select-Object -First 1
            $candidate = Join-Path $latest.FullName "bin\Rscript.exe"
            if (Test-Path $candidate) {
                $Rscript = $candidate
            }
        }
    }
}

# Step 1: Execute build_offseason_monitor.R
Write-PipelineLog "INFO" "Step 1: Running build_offseason_monitor.R..."
$buildArgs = @("--vanilla", "build_offseason_monitor.R")
if ($AllowDegraded) {
    $buildArgs += "--allow-degraded"
}

$buildProcess = Start-Process -FilePath $Rscript -ArgumentList $buildArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir "offseason_build_stdout.tmp") -RedirectStandardError (Join-Path $LogDir "offseason_build_stderr.tmp")

if (Test-Path (Join-Path $LogDir "offseason_build_stdout.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_build_stdout.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_build_stdout.tmp") -Force
}
if (Test-Path (Join-Path $LogDir "offseason_build_stderr.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_build_stderr.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_build_stderr.tmp") -Force
}

if ($buildProcess.ExitCode -ne 0) {
    Write-PipelineLog "ERROR" "build_offseason_monitor.R failed with exit code $($buildProcess.ExitCode)."
    exit $buildProcess.ExitCode
}

# Step 2: Run End-to-End DAG Regression Suite prior to publishing (GitHub issue #62)
Write-PipelineLog "INFO" "Step 2: Running tools/offseason/test_dag_end_to_end.R..."
$testArgs = @("--vanilla", "tools/offseason/test_dag_end_to_end.R")
$testProcess = Start-Process -FilePath $Rscript -ArgumentList $testArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir "offseason_test_stdout.tmp") -RedirectStandardError (Join-Path $LogDir "offseason_test_stderr.tmp")

if (Test-Path (Join-Path $LogDir "offseason_test_stdout.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_test_stdout.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_test_stdout.tmp") -Force
}
if (Test-Path (Join-Path $LogDir "offseason_test_stderr.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_test_stderr.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_test_stderr.tmp") -Force
}

if ($testProcess.ExitCode -ne 0) {
    Write-PipelineLog "ERROR" "tools/offseason/test_dag_end_to_end.R failed with exit code $($testProcess.ExitCode). Halting publication."
    exit $testProcess.ExitCode
}

# Step 3: Publish web artifacts and promote staged baseline
$publishModeFlag = if ($Mode -eq 'publish') { "--publish" } else { "--dry-run" }
Write-PipelineLog "INFO" "Step 3: Running tools/publish_web.R $publishModeFlag --mode=offseason..."
$publishArgs = @("--vanilla", "tools/publish_web.R", $publishModeFlag, "--mode=offseason")
if ($AllowDegraded) {
    $publishArgs += "--allow-degraded"
}

$publishProcess = Start-Process -FilePath $Rscript -ArgumentList $publishArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir "offseason_publish_stdout.tmp") -RedirectStandardError (Join-Path $LogDir "offseason_publish_stderr.tmp")

if (Test-Path (Join-Path $LogDir "offseason_publish_stdout.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_publish_stdout.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_publish_stdout.tmp") -Force
}
if (Test-Path (Join-Path $LogDir "offseason_publish_stderr.tmp")) {
    Get-Content (Join-Path $LogDir "offseason_publish_stderr.tmp") | Add-Content -Path $LogFile -Encoding utf8
    Remove-Item (Join-Path $LogDir "offseason_publish_stderr.tmp") -Force
}

if ($publishProcess.ExitCode -ne 0) {
    Write-PipelineLog "ERROR" "tools/publish_web.R failed with exit code $($publishProcess.ExitCode)."
    exit $publishProcess.ExitCode
}

# Step 4: Direct aggregator workflow dispatch to overcome Winter DST inversion
if ($Mode -eq 'publish') {
    Write-PipelineLog "INFO" "Step 4: Dispatching aggregator sync-sports workflow via GitHub CLI..."
    $ghCmd = Get-Command "gh" -ErrorAction SilentlyContinue
    $ghPath = if ($ghCmd) { "gh" } elseif (Test-Path "C:\Program Files\GitHub CLI\gh.exe") { "C:\Program Files\GitHub CLI\gh.exe" } else { $null }

    if ($ghPath) {
        $dispatchArgs = @(
            "workflow", "run", "Sync sport subtrees and deploy",
            "--repo", "kailot-harris/front-office",
            "-f", "sports=mlb",
            "-f", "deploy=true"
        )
        $dispatchProcess = Start-Process -FilePath $ghPath -ArgumentList $dispatchArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir "dispatch_stdout.tmp") -RedirectStandardError (Join-Path $LogDir "dispatch_stderr.tmp")
        
        if (Test-Path (Join-Path $LogDir "dispatch_stdout.tmp")) {
            Get-Content (Join-Path $LogDir "dispatch_stdout.tmp") | Add-Content -Path $LogFile -Encoding utf8
            Remove-Item (Join-Path $LogDir "dispatch_stdout.tmp") -Force
        }
        if (Test-Path (Join-Path $LogDir "dispatch_stderr.tmp")) {
            Get-Content (Join-Path $LogDir "dispatch_stderr.tmp") | Add-Content -Path $LogFile -Encoding utf8
            Remove-Item (Join-Path $LogDir "dispatch_stderr.tmp") -Force
        }

        if ($dispatchProcess.ExitCode -eq 0) {
            Write-PipelineLog "INFO" "Aggregator sync-sports workflow successfully triggered."
        } else {
            Write-PipelineLog "WARN" "Aggregator workflow dispatch exited with code $($dispatchProcess.ExitCode)."
        }
    } else {
        Write-PipelineLog "WARN" "GitHub CLI (gh) not found on PATH; skipping direct workflow dispatch."
    }
}

Write-PipelineLog "INFO" "Daily offseason monitor pipeline run completed successfully."
exit 0
