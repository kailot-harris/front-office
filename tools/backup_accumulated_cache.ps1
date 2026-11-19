<#
.SYNOPSIS
  Copy the MLB pipeline's append-only files to a dated folder OUTSIDE any git
  checkout (MLB-Analytics issue #103; ported from NBA_analytics #164/#182).

.DESCRIPTION
  cache/ and logs/ are gitignored and live inside the checkout, so nothing backs
  them up. On 2026-11-16 a `git worktree remove` that followed a cache/ junction
  emptied a sibling sport's primary cache/ (NBA_analytics #163). This script, run
  by the scheduled entry points after each run, copies only the files a run
  builds up and cannot refetch into:

      <BackupRoot>\mlb\YYYY-MM-DD\<same relative path as in the checkout>

  - <BackupRoot> is -BackupRoot, else $env:MLB_BACKUP_ROOT, else
    $env:USERPROFILE\front-office-backups.
  - Files are COPIED (Copy-Item), never moved and never linked, and each copy
    is checked against its source by SHA-256.
  - A second run on the same day refreshes that day's folder.
  - Retention: keeps the $Keep newest daily folders. It deletes only folders
    under its own <BackupRoot>\mlb\ whose name is exactly YYYY-MM-DD AND that
    hold the marker file this script writes, and never one with a link inside.
  - Refuses (logs [WARN], copies nothing) when the destination is inside a git
    checkout or worktree.
  - Prints one [BACKUP] line with the path and file count. Any failure, or a
    named file that is missing, prints [WARN] and the script still exits 0, so
    the scheduled run always finishes.

  APPEND-ONLY FILES (sorted for #103; everything else is rebuilt from fetched
  data and is skipped):
    logs\logs.duckdb
        logging_utils.R:213 INSERTs one row per log call into the existing
        `logs` table (CREATE TABLE IF NOT EXISTS, :97). Every earlier run's rows
        exist only here.
    logs\logs_pending_*.tsv
        logging_utils.R:120-127 append log rows here when the DuckDB store
        cannot be opened; nothing drains them back, so they exist only here.
  Checked and skipped (rebuilt on every write, no earlier copy is read):
    cache\ratings\mlb_elo_history.rds, cache\ratings\pitcher_rgs_tracker.rds
        mlb_elo_engine.R:576-578 rewrite both from a full walk-forward replay
        of the season schedule (simulate_elo_walkforward); the old files are
        only read on the cache-hit path (:540-546), never merged.
    cache\accuracy_governance.rds
        accuracy_governance.R:133-140 recompute it from mlb_elo_history.rds and
        overwrite it.
    cache\offseason_wire_items.json, cache\ingestion_manifest.json,
    cache\raw_ingest_archive\YYYYMMDD\, cache\league_state_staged.json
        Re-fetched or recomputed per run by tools/offseason/ingest_sources.R and
        reconcile_state.R; league_state_baseline.json is tracked in git.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_accumulated_cache.ps1 -ProjectDir . -BackupRoot $env:TEMP\mlb-bk
#>
[CmdletBinding()]
param(
    [string]$ProjectDir,
    [string]$BackupRoot,
    [int]$Keep = 30
)

# Named append-only files, relative to the checkout root (see the header for
# the evidence behind each). Exact names are expected to exist and give a
# [WARN] when missing; wildcard patterns may match nothing.
$AppendOnlyFiles    = @('logs\logs.duckdb')
$AppendOnlyPatterns = @('logs\logs_pending_*.tsv')
$Sport          = 'mlb'
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

function Test-IsLink($Item) {
    return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

$ErrorActionPreference = 'Stop'
try {
    if (-not $ProjectDir) { $ProjectDir = Split-Path -Parent $PSScriptRoot }
    $ProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
    if (-not $BackupRoot) {
        if ($env:MLB_BACKUP_ROOT) { $BackupRoot = $env:MLB_BACKUP_ROOT }
        else { $BackupRoot = Join-Path $env:USERPROFILE 'front-office-backups' }
    }
    if ($Keep -lt 1) { $Keep = 1 }

    $sportRoot = [System.IO.Path]::GetFullPath((Join-Path $BackupRoot $Sport))
    $dest      = Join-Path $sportRoot (Get-Date -Format 'yyyy-MM-dd')

    $checkout = Get-GitCheckoutRoot $dest
    if ($checkout) {
        Write-BackupLine "[WARN] backup_accumulated_cache: refusing to back up into a git checkout or worktree ($checkout). Nothing copied."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
        Write-BackupLine "[WARN] backup_accumulated_cache: project folder not found ($ProjectDir). Nothing copied."
        exit 0
    }

    # Collect sources as (relative path, FileInfo). Links are never copied.
    $sources = @()
    foreach ($rel in $AppendOnlyFiles) {
        $full = Join-Path $ProjectDir $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $fi = Get-Item -LiteralPath $full -Force
            if (Test-IsLink $fi) {
                Write-BackupLine "[WARN] backup_accumulated_cache: $rel is a link; not copied."
            } else {
                $sources += [pscustomobject]@{ Rel = $rel; File = $fi }
            }
        } else {
            Write-BackupLine "[WARN] backup_accumulated_cache: expected append-only file is missing: $rel"
        }
    }
    foreach ($pat in $AppendOnlyPatterns) {
        $dirRel = Split-Path -Parent $pat
        $leaf   = Split-Path -Leaf $pat
        $dirFull = Join-Path $ProjectDir $dirRel
        if (-not (Test-Path -LiteralPath $dirFull -PathType Container)) { continue }
        foreach ($fi in (Get-ChildItem -LiteralPath $dirFull -File -Force | Where-Object { $_.Name -like $leaf })) {
            if (Test-IsLink $fi) { continue }
            $sources += [pscustomobject]@{ Rel = (Join-Path $dirRel $fi.Name); File = $fi }
        }
    }
    if (-not $sources) {
        Write-BackupLine "[WARN] backup_accumulated_cache: no append-only files found under $ProjectDir. Nothing copied."
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $marker = Join-Path $dest $MarkerName
    if (-not (Test-Path -LiteralPath $marker)) {
        Set-Content -LiteralPath $marker -Value 'Created by MLB tools/backup_accumulated_cache.ps1. Retention may delete this folder.' -Encoding ASCII
    }

    $copied = 0
    $bad = @()
    foreach ($s in $sources) {
        $target = Join-Path $dest $s.Rel
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $s.File.FullName -Destination $target -Force -ErrorAction Stop
            $h1 = (Get-FileHash -LiteralPath $s.File.FullName -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($h1 -ne $h2) { $bad += "$($s.Rel) (SHA-256 mismatch)" } else { $copied++ }
        } catch {
            $bad += "$($s.Rel) ($($_.Exception.Message.TrimEnd('.')))"
        }
    }

    # Retention: only YYYY-MM-DD folders under our own mlb\ root that carry our marker.
    $ours = @(Get-ChildItem -LiteralPath $sportRoot -Directory -Force | Where-Object {
        $_.Name -match $DayFolderRegex -and
        -not (Test-IsLink $_) -and
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
