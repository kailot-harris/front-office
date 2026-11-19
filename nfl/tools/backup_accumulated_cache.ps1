<#
.SYNOPSIS
  Copy the NFL pipeline's append-only files to a dated folder OUTSIDE any git
  checkout (NFL_analytics issue #152; ported from NBA_analytics #164).

.DESCRIPTION
  cache/ and logs/ are gitignored and live inside the checkout, so nothing
  backs them up. On 2026-11-16 a `git worktree remove` that followed a cache/
  junction (NBA_analytics #163) emptied the NBA primary checkout's cache/. This
  script, run by schedule_daily.bat after the pipeline, copies only the files a
  run builds up and cannot refetch into:

      <BackupRoot>\nfl\YYYY-MM-DD\

  - <BackupRoot> is -BackupRoot, else $env:NFL_BACKUP_ROOT, else
    $env:USERPROFILE\front-office-backups.
  - Files are COPIED (Copy-Item), never moved and never linked, and each copy
    is checked against its source by SHA-256.
  - A second run on the same day refreshes that day's folder.
  - Retention: keeps the $Keep newest daily folders. It deletes only folders
    under its own <BackupRoot>\nfl\ whose name is exactly YYYY-MM-DD AND that
    hold the marker file this script writes, and never one with a link inside.
  - Refuses (logs [WARN], copies nothing) when the destination is inside a git
    checkout or worktree.
  - Prints one [BACKUP] line with the path and file count. A named file that is
    missing, or any failure, prints [WARN] and the script still exits 0, so the
    scheduled run always finishes.

  APPEND-ONLY FILES (everything else in cache/ is rebuilt from fetched data,
  or is tracked in git, and is skipped):
    cache/prediction_accuracy_log.rds
        prediction_accuracy_logger.R reads the existing log (:383-385), adds
        new pre-game forecasts, grades finished games and writes the whole log
        back (:831). Pre-kickoff forecasts are frozen at kickoff (#149) and
        cannot be recomputed later, so earlier rows exist nowhere else.
    cache/accuracy_history.rds
        accuracy_tracker.R (:140) calls tools/backtest_common.R's
        append_accuracy_history(), which loads the existing history (:251),
        binds one new row per run and saves it (:265). Each row is a dated
        snapshot of that run's season-to-date figures.
    logs/logs.duckdb (and logs/logs.duckdb.wal when present)
        logging_utils.R (:27, :235) INSERTs every log row into this database;
        it is never rebuilt. Named in issue #152.
  Skipped on purpose:
    the weekly playoff probability history (config.R:720)  its backfill tool
        in tools/ rebuilds any missing week from completed games (a full
        backfill when the file is absent), and the file is tracked in git.
    turnover_margin_history.rds  tools/turnover_margin_history.R rebuilds it
        from CACHE_PBP on every call without reading the old copy, and the file
        is tracked in git.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1 -CacheDir .\cache -LogsDir .\logs -BackupRoot $env:TEMP\nfl-bk
#>
[CmdletBinding()]
param(
    [string]$CacheDir,
    [string]$LogsDir,
    [string]$BackupRoot,
    [int]$Keep = 30
)

# Named append-only files (see the header for the reasoning behind each).
# 'Required' files give a [WARN] when missing; optional ones are copied only if present.
$CacheFiles    = @('prediction_accuracy_log.rds', 'accuracy_history.rds')
$LogFiles      = @('logs.duckdb')
$OptionalLogs  = @('logs.duckdb.wal')
$DayFolderRegex = '^\d{4}-\d{2}-\d{2}$'
$MarkerName     = '.created-by-backup_accumulated_cache'

function Write-BackupLine([string]$Text) { Write-Output $Text }

function Get-GitCheckoutRoot([string]$Path) {
    # Walk up from $Path (which may not exist yet) looking for a .git folder
    # or a .git file (a linked worktree). Returns the checkout root or $null.
    $p = [System.IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath (Join-Path $p '.git')) { return $p }
        $parent = [System.IO.Path]::GetDirectoryName($p)
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
    return $null
}

function Test-HasReparsePoint([string]$Dir) {
    $items = Get-ChildItem -LiteralPath $Dir -Force -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue
    return [bool]$items
}

$ErrorActionPreference = 'Stop'
try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    if (-not $CacheDir) { $CacheDir = Join-Path $repoRoot 'cache' }
    if (-not $LogsDir)  { $LogsDir  = Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($CacheDir))) 'logs' }
    if (-not $BackupRoot) {
        if ($env:NFL_BACKUP_ROOT) { $BackupRoot = $env:NFL_BACKUP_ROOT }
        else { $BackupRoot = Join-Path $env:USERPROFILE 'front-office-backups' }
    }
    if ($Keep -lt 1) { $Keep = 1 }

    $sportRoot = [System.IO.Path]::GetFullPath((Join-Path $BackupRoot 'nfl'))
    $dest      = Join-Path $sportRoot (Get-Date -Format 'yyyy-MM-dd')

    $checkout = Get-GitCheckoutRoot $dest
    if ($checkout) {
        Write-BackupLine "[WARN] backup_accumulated_cache: refusing to back up into a git checkout or worktree ($checkout). Nothing copied."
        exit 0
    }

    # Build the list of source files: (dir, name, required).
    $wanted = @()
    foreach ($n in $CacheFiles)   { $wanted += ,@($CacheDir, $n, $true) }
    foreach ($n in $LogFiles)     { $wanted += ,@($LogsDir,  $n, $true) }
    foreach ($n in $OptionalLogs) { $wanted += ,@($LogsDir,  $n, $false) }

    $files = @()
    $missing = @()
    foreach ($w in $wanted) {
        $src = Join-Path $w[0] $w[1]
        $item = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
        if ($item -and -not $item.PSIsContainer -and -not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            $files += $item
        } elseif ($w[2]) {
            $missing += $src
        }
    }
    if ($missing.Count -gt 0) {
        Write-BackupLine "[WARN] backup_accumulated_cache: append-only file(s) not found, not backed up: $($missing -join ', ')"
    }
    if ($files.Count -eq 0) {
        Write-BackupLine "[WARN] backup_accumulated_cache: no append-only files found. Nothing copied."
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $marker = Join-Path $dest $MarkerName
    if (-not (Test-Path -LiteralPath $marker)) {
        Set-Content -LiteralPath $marker -Value 'Created by NFL tools/backup_accumulated_cache.ps1. Retention may delete this folder.' -Encoding ASCII
    }

    $copied = 0
    $bad = @()
    foreach ($f in $files) {
        $target = Join-Path $dest $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force -ErrorAction Stop
        $h1 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($h1 -ne $h2) { $bad += $f.Name } else { $copied++ }
    }

    # Retention: only YYYY-MM-DD folders under our own nfl\ root that carry our marker.
    $ours = @(Get-ChildItem -LiteralPath $sportRoot -Directory -Force | Where-Object {
        $_.Name -match $DayFolderRegex -and
        -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName $MarkerName))
    } | Sort-Object Name -Descending)
    $pruned = 0
    foreach ($old in ($ours | Select-Object -Skip $Keep)) {
        if (Test-HasReparsePoint $old.FullName) {
            Write-BackupLine "[WARN] backup_accumulated_cache: not pruning $($old.FullName): it contains a link."
            continue
        }
        Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction Stop
        $pruned++
    }

    if ($bad.Count -gt 0) {
        Write-BackupLine "[WARN] backup_accumulated_cache: SHA-256 mismatch after copy for: $($bad -join ', ')"
    }
    Write-BackupLine ("[BACKUP] {0} append-only files copied to {1} (daily folders kept: {2}, pruned: {3})" -f $copied, $dest, ([Math]::Min($ours.Count, $Keep)), $pruned)
    exit 0
}
catch {
    Write-BackupLine "[WARN] backup_accumulated_cache: backup failed: $($_.Exception.Message.TrimEnd('.')). The run continues."
    exit 0
}
