<#
.SYNOPSIS
  Copy the WNBA pipeline's append-only files to a dated folder OUTSIDE any git
  checkout (WNBA_analytics issue #200; ported from NBA_analytics #164/#182).

.DESCRIPTION
  cache/ and logs/ are gitignored and live inside the checkout, so nothing backs
  them up. On 2026-11-16 a `git worktree remove` that followed a cache/ junction
  (NBA_analytics #163, WNBA #199) emptied the NBA primary checkout's cache/.
  This script, run by schedule_daily.bat and schedule_weekly_offseason.bat after
  their pipeline steps, copies only the files a run builds up and cannot
  refetch into:

      <BackupRoot>\wnba\YYYY-MM-DD\cache\...
      <BackupRoot>\wnba\YYYY-MM-DD\logs\...

  - <BackupRoot> is -BackupRoot, else $env:WNBA_BACKUP_ROOT, else
    $env:USERPROFILE\front-office-backups.
  - Files are COPIED (Copy-Item), never moved and never linked, and each copy
    is checked against its source by SHA-256.
  - A second run on the same day refreshes that day's folder.
  - Retention: keeps the $Keep newest daily folders. It deletes only folders
    under its own <BackupRoot>\wnba\ whose name is exactly YYYY-MM-DD AND that
    hold the marker file this script writes, and never one with a link inside.
  - Refuses (logs [WARN], copies nothing) when the destination is inside a git
    checkout or worktree.
  - A named file that is missing is a [WARN] line; the others are still copied.
  - Prints one [BACKUP] line with the path and file count. Any failure prints
    [WARN] and the script still exits 0, so the scheduled run always finishes.

  APPEND-ONLY FILES (sorted for #200; everything else in cache/ is skipped):
    cache/prediction_accuracy_log.rds / .csv
        prediction_accuracy_logger.R: get_prediction_log() (:277-278) reads the
        existing log, log_todays_predictions() (:493) adds today's pre-game
        rows and reconcile_predictions() (:584) grades finished games, and
        save_prediction_log() (:281-283) writes the whole log back to both
        files. Pre-game probabilities cannot be recomputed after the fact.
    cache/series_length_predictions.rds
        The archived 2026 semifinal forecasts, generated 2026-10-04 before the
        series were played. tools/series_length_predictor.R (:524-531) writes it
        only when it is absent or overwrite = TRUE; build_playoff_bracket_2026.R
        (:82) reads it and never writes it. Write-once, not rebuildable. (It is
        also tracked in git; this copy is a second safety net.)
    logs/logs.duckdb
        The run log database. logging_utils.R opens the existing file (:111),
        CREATE TABLE IF NOT EXISTS (:113) and INSERTs each log row (:217).
  Not included: cache/finals_game_predictions_2026.rds is rebuilt from the
  bracket artifact on every run (build_finals_game_predictions.R:209-392 never
  reads its previous copy), and the other caches are re-derivable from fetched
  data. cache/raw_ingest_archive/ is append-only too, but is not copied here:
  it is 26 MB of raw fetched pages and was left for the owner to decide (#200).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1 -CacheDir .\cache -LogsDir .\logs -BackupRoot $env:TEMP\wnba-bk
#>
[CmdletBinding()]
param(
    [string]$CacheDir,
    [string]$LogsDir,
    [string]$BackupRoot,
    [int]$Keep = 30
)

# Named append-only files (see the header for the reasoning behind each).
# Copied into <day>/cache/ and <day>/logs/ respectively, so a restore is a straight copy back.
$AppendOnlyCache = @(
    'prediction_accuracy_log.rds',
    'prediction_accuracy_log.csv',
    'series_length_predictions.rds'
)
$AppendOnlyLogs = @(
    'logs.duckdb'
)
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
    if (-not $LogsDir)  { $LogsDir  = Join-Path $repoRoot 'logs' }
    if (-not $BackupRoot) {
        if ($env:WNBA_BACKUP_ROOT) { $BackupRoot = $env:WNBA_BACKUP_ROOT }
        else { $BackupRoot = Join-Path $env:USERPROFILE 'front-office-backups' }
    }
    if ($Keep -lt 1) { $Keep = 1 }

    $sportRoot = [System.IO.Path]::GetFullPath((Join-Path $BackupRoot 'wnba'))
    $dest      = Join-Path $sportRoot (Get-Date -Format 'yyyy-MM-dd')

    $checkout = Get-GitCheckoutRoot $dest
    if ($checkout) {
        Write-BackupLine "[WARN] backup_accumulated_cache: refusing to back up into a git checkout or worktree ($checkout). Nothing copied."
        exit 0
    }

    # Resolve the named files; a missing one is a [WARN], the rest still copy.
    $wanted = @()
    foreach ($n in $AppendOnlyCache) { $wanted += [pscustomobject]@{ Sub = 'cache'; Path = (Join-Path $CacheDir $n) } }
    foreach ($n in $AppendOnlyLogs)  { $wanted += [pscustomobject]@{ Sub = 'logs';  Path = (Join-Path $LogsDir  $n) } }

    $files = @()
    foreach ($w in $wanted) {
        $item = Get-Item -LiteralPath $w.Path -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            Write-BackupLine "[WARN] backup_accumulated_cache: append-only file not found, not copied: $($w.Path)"
            continue
        }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-BackupLine "[WARN] backup_accumulated_cache: $($w.Path) is a link, not copied."
            continue
        }
        $files += [pscustomobject]@{ Sub = $w.Sub; Item = $item }
    }
    if ($files.Count -eq 0) {
        Write-BackupLine "[WARN] backup_accumulated_cache: no append-only files found under $CacheDir or $LogsDir. Nothing copied."
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $marker = Join-Path $dest $MarkerName
    if (-not (Test-Path -LiteralPath $marker)) {
        Set-Content -LiteralPath $marker -Value 'Created by WNBA tools/backup_accumulated_cache.ps1. Retention may delete this folder.' -Encoding ASCII
    }

    $copied = 0
    $bad = @()
    foreach ($f in $files) {
        $subDir = Join-Path $dest $f.Sub
        New-Item -ItemType Directory -Force -Path $subDir | Out-Null
        $target = Join-Path $subDir $f.Item.Name
        try {
            Copy-Item -LiteralPath $f.Item.FullName -Destination $target -Force -ErrorAction Stop
            $h1 = (Get-FileHash -LiteralPath $f.Item.FullName -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($h1 -ne $h2) { $bad += "$($f.Sub)/$($f.Item.Name) (hash mismatch)" } else { $copied++ }
        } catch {
            $bad += "$($f.Sub)/$($f.Item.Name) ($($_.Exception.Message.TrimEnd('.')))"
        }
    }

    # Retention: only YYYY-MM-DD folders under our own wnba\ root that carry our marker.
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
        Write-BackupLine "[WARN] backup_accumulated_cache: not backed up: $($bad -join '; ')"
    }
    Write-BackupLine ("[BACKUP] {0} append-only files copied to {1} (daily folders kept: {2}, pruned: {3})" -f $copied, $dest, ([Math]::Min($ours.Count, $Keep)), $pruned)
    exit 0
}
catch {
    Write-BackupLine "[WARN] backup_accumulated_cache: backup failed: $($_.Exception.Message.TrimEnd('.')). The run continues."
    exit 0
}
