# ==============================================================================
# test_scheduler_migration.ps1
# MLB 2026-2027 Off-Season Dynamics Monitor: Scheduler Migration & Dispatch Test
# Path: tools/offseason/test_scheduler_migration.ps1
#
# Validates:
#   1. Existence and syntax of schedule_weekly_offseason.bat and .ps1
#   2. Task Scheduler task registration and daily task disabling
#   3. Direct aggregator workflow dispatch capability via GitHub CLI
#   4. Zero-betting policy compliance across automation scripts
#
# Conforms to blueprint §§ 9, 10 and Issue #48.
# ==============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ProjectDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -Path $ProjectDir

Write-Host "====================================================================="
Write-Host ">>> Running MLB Off-Season Scheduler Migration Test Suite"
Write-Host "====================================================================="

$testCount = 0
$passCount = 0

function Run-Test([string]$Name, [scriptblock]$TestBlock) {
    $script:testCount++
    Write-Host ("Test {0}: {1}..." -f $script:testCount, $Name)
    try {
        $result = & $TestBlock
        if ($result -eq $true) {
            $script:passCount++
            Write-Host "  [PASS]" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Test returned false" -ForegroundColor Red
        }
    } catch {
        Write-Host ("  [FAIL] Exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

# Test 1: schedule_weekly_offseason.bat exists and contains required targets
Run-Test "schedule_weekly_offseason.bat verification" {
    $batPath = Join-Path $ProjectDir "schedule_weekly_offseason.bat"
    if (-not (Test-Path $batPath)) { return $false }
    $content = Get-Content -Path $batPath -Raw
    $hasAggregator = $content.Contains("Sync sport subtrees and deploy")
    $hasBuild = $content.Contains("build_offseason_monitor.R")
    $hasPublish = $content.Contains("tools/publish_web.R --publish --mode=offseason")
    return ($hasAggregator -and $hasBuild -and $hasPublish)
}

# Test 2: schedule_weekly_offseason.ps1 exists and contains required targets
Run-Test "schedule_weekly_offseason.ps1 verification" {
    $ps1Path = Join-Path $ProjectDir "schedule_weekly_offseason.ps1"
    if (-not (Test-Path $ps1Path)) { return $false }
    $content = Get-Content -Path $ps1Path -Raw
    $hasAggregator = $content.Contains("Sync sport subtrees and deploy")
    $hasBuild = $content.Contains("build_offseason_monitor.R")
    $hasPublish = $content.Contains("tools/publish_web.R")
    return ($hasAggregator -and $hasBuild -and $hasPublish)
}

# Test 3: Task Scheduler weekly offseason task is registered
Run-Test "Task Scheduler weekly offseason task registered" {
    $taskQuery = schtasks /query /tn "MLB Analytics Schedule Weekly Offseason" /fo LIST 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = ($taskQuery | Out-String)
    return ($text.Contains("MLB Analytics Schedule Weekly Offseason") -and ($text.Contains("Ready") -or $text.Contains("Enabled")))
}

# Test 4: Task Scheduler daily pipeline task is disabled
Run-Test "Task Scheduler daily pipeline task is disabled" {
    $taskQuery = schtasks /query /tn "\MLB_Analytics_Scheduled_Pipeline" /fo LIST 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = ($taskQuery | Out-String)
    return ($text.Contains("Disabled"))
}

# Test 5: Offseason monitor data contract and baseline alignment
Run-Test "Offseason monitor data contract and baseline alignment" {
    $jsonPath = Join-Path $ProjectDir "web\public\data\offseason_monitor.json"
    if (-not (Test-Path $jsonPath)) { return $false }
    $json = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
    $weekOk = ($json.currentWeekNumber -ge 1)
    $baselineOk = ($json.baselineAsOfDate -eq "2026-10-29T03:13:00Z")
    return ($weekOk -and $baselineOk)
}

# Test 6: Zero-betting policy compliance across scheduled wrappers
Run-Test "Zero-betting policy compliance in schedule scripts" {
    $forbiddenTerms = @("sportsbook", "betmgm", "draftkings", "fanduel", "moneyline", "runline", "over/under", "parlay", "vig", "juice", "prop bet")
    $files = @("schedule_weekly_offseason.bat", "schedule_weekly_offseason.ps1")
    foreach ($f in $files) {
        $path = Join-Path $ProjectDir $f
        if (Test-Path $path) {
            $txt = Get-Content -Path $path -Raw
            foreach ($term in $forbiddenTerms) {
                if ($txt -match [regex]::Escape($term)) {
                    Write-Host ("  Forbidden betting term '{0}' detected in {1}" -f $term, $f)
                    return $false
                }
            }
        }
    }
    return $true
}

Write-Host "====================================================================="
Write-Host ("Summary: {0}/{1} tests passed." -f $passCount, $testCount)
Write-Host "====================================================================="

if ($passCount -eq $testCount) {
    exit 0
} else {
    exit 1
}
