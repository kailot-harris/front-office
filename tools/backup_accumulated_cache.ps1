<#
.SYNOPSIS
  Copy the NBA pipeline's append-only cache files to a dated folder OUTSIDE
  any git checkout (NBA_analytics issue #164).

.DESCRIPTION
  cache/ is gitignored and lives inside the checkout, so nothing backs it up.
  On 2026-11-16 a `git worktree remove` that followed a cache/ junction (#163)
  emptied the primary checkout's cache/, and the backups that sat in the same
  folder went with it. This script, run by schedule_daily.bat after the
  pipeline and publish steps, copies only the files a run builds up and cannot
  refetch into:

      <BackupRoot>\nba\YYYY-MM-DD\

  - <BackupRoot> is -BackupRoot, else $env:NBA_BACKUP_ROOT, else
    $env:USERPROFILE\front-office-backups.
  - Files are COPIED (Copy-Item), never moved and never linked, and each copy
    is checked against its source by SHA-256.
  - A second run on the same day refreshes that day's folder.
  - Retention: keeps the $Keep newest daily folders. It deletes only folders
    under its own <BackupRoot>\nba\ whose name is exactly YYYY-MM-DD AND that
    hold the marker file this script writes, and never one with a link inside.
  - Refuses (logs [WARN], copies nothing) when the destination is inside a git
    checkout or worktree.
  - Prints one [BACKUP] line with the path and file count. Any failure prints
    [WARN] and the script still exits 0, so the scheduled run always finishes.

  APPEND-ONLY FILES (everything else in cache/ is rebuilt from fetched data on
  every run and is skipped):
    prediction_accuracy_log.rds / .csv
        prediction_accuracy_logger.R reads the existing log, adds today's
        pre-game win probabilities and grades finished games, and writes the
        whole log back. Pre-tip-off probabilities cannot be recomputed after
        the fact, so earlier rows exist nowhere else.
    prediction_accuracy_log.backup-*.rds
        Written by tools/backfill_week1_predictions.R before it inserts rows;
        a snapshot of the log at that moment.
    nba_predictions_YYYY-MM-DD.png / .gif
        tools/plot_today_predictions.R writes one dated pair per day and never
        rewrites an earlier date. (nba_predictions_today.* is overwritten every
        run and is skipped.)
  Not included: box_scores_cache.rds and the other *_cache.rds files grow run
  by run but are re-downloadable from hoopR, and most live outside cache/.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1 -CacheDir .\cache -BackupRoot $env:TEMP\nba-bk
#>
[CmdletBinding()]
param(
    [string]$CacheDir,
    [string]$BackupRoot,
    [int]$Keep = 30
)

# Named append-only files (see the header for the reasoning behind each).
$AppendOnlyPatterns = @(
    'prediction_accuracy_log.rds',
    'prediction_accuracy_log.csv',
    'prediction_accuracy_log.backup-*.rds',
    'nba_predictions_????-??-??.png',
    'nba_predictions_????-??-??.gif'
)
$DatedImageRegex = '^nba_predictions_\d{4}-\d{2}-\d{2}\.(png|gif)$'
$DayFolderRegex  = '^\d{4}-\d{2}-\d{2}$'
$MarkerName      = '.created-by-backup_accumulated_cache'

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
    if (-not $CacheDir) { $CacheDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache' }
    if (-not $BackupRoot) {
        if ($env:NBA_BACKUP_ROOT) { $BackupRoot = $env:NBA_BACKUP_ROOT }
        else { $BackupRoot = Join-Path $env:USERPROFILE 'front-office-backups' }
    }
    if ($Keep -lt 1) { $Keep = 1 }

    $sportRoot = [System.IO.Path]::GetFullPath((Join-Path $BackupRoot 'nba'))
    $dest      = Join-Path $sportRoot (Get-Date -Format 'yyyy-MM-dd')

    $checkout = Get-GitCheckoutRoot $dest
    if ($checkout) {
        Write-BackupLine "[WARN] backup_accumulated_cache: refusing to back up into a git checkout or worktree ($checkout). Nothing copied."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $CacheDir -PathType Container)) {
        Write-BackupLine "[WARN] backup_accumulated_cache: cache folder not found ($CacheDir). Nothing copied."
        exit 0
    }

    $files = Get-ChildItem -LiteralPath $CacheDir -File -Force | Where-Object {
        $name = $_.Name
        $hit = $false
        foreach ($pat in $AppendOnlyPatterns) { if ($name -like $pat) { $hit = $true; break } }
        if ($hit -and $name -like 'nba_predictions_*') { $hit = $name -match $DatedImageRegex }
        $hit -and -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    }
    if (-not $files) {
        Write-BackupLine "[WARN] backup_accumulated_cache: no append-only files found in $CacheDir. Nothing copied."
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $marker = Join-Path $dest $MarkerName
    if (-not (Test-Path -LiteralPath $marker)) {
        Set-Content -LiteralPath $marker -Value 'Created by NBA tools/backup_accumulated_cache.ps1. Retention may delete this folder.' -Encoding ASCII
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

    # Retention: only YYYY-MM-DD folders under our own nba\ root that carry our marker.
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
    Write-BackupLine ("[BACKUP] {0} append-only cache files copied to {1} (daily folders kept: {2}, pruned: {3})" -f $copied, $dest, ([Math]::Min($ours.Count, $Keep)), $pruned)
    exit 0
}
catch {
    Write-BackupLine "[WARN] backup_accumulated_cache: backup failed: $($_.Exception.Message.TrimEnd('.')). The run continues."
    exit 0
}
