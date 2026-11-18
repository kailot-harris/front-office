<#
.SYNOPSIS
    Remove a git worktree of this repository only when it holds no directory links.

.DESCRIPTION
    NBA_analytics issue #163. On 2026-11-16, plain `git worktree remove` followed
    Windows directory junctions (web/node_modules) from worktrees into the primary
    checkout and deleted files there. This guard removes a worktree only when that
    cannot happen:

      1. Refuses the primary checkout (the main worktree, the first entry of
         `git worktree list --porcelain`).
      2. Refuses a path that is not a registered worktree of this repository.
      3. Scans the worktree for reparse points (junctions, symlinks, mount points,
         any directory or file link) without following any of them. If it finds
         one, it refuses and lists each, with its target where Windows reports it.
         Delete each link on its own first, never recursively, for example
         `cmd /c rmdir "<link>"` or `[System.IO.Directory]::Delete("<link>", $false)`,
         then run this script again.
      4. Only then runs `git worktree remove` (never --force: git still refuses a
         worktree with uncommitted changes).

    -WhatIf reports what would happen and changes nothing.

    "This repository" is the one this script lives in (its parent folder's repo).

.PARAMETER Path
    The worktree to remove.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/remove_worktree.ps1 -Path ..\.nba-worktrees\issue159 -WhatIf

.NOTES
    Exit codes: 0 removed (or -WhatIf found nothing blocking), 1 links found,
    2 path is the primary checkout, 3 path is not a registered worktree,
    4 the scan could not read part of the worktree, 5 git worktree remove failed,
    6 this script's folder is not inside a git repository.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalPath([string]$p) {
    $full = [System.IO.Path]::GetFullPath($p.Replace('/', '\'))
    return $full.TrimEnd('\')
}

$repoDir = Split-Path -Parent $PSScriptRoot
$porcelain = & git -C $repoDir worktree list --porcelain 2>$null
if ($LASTEXITCODE -ne 0 -or -not $porcelain) {
    Write-Host "[ERROR] remove_worktree.ps1: '$repoDir' is not inside a git repository."
    exit 6
}

$worktrees = @()
foreach ($line in $porcelain) {
    if ($line -like 'worktree *') { $worktrees += (Get-NormalPath $line.Substring(9)) }
}
$mainWorktree = $worktrees[0]

if ([System.IO.Path]::IsPathRooted($Path)) {
    $target = Get-NormalPath $Path
} else {
    $target = Get-NormalPath (Join-Path (Get-Location).ProviderPath $Path)
}

if ($target -ieq $mainWorktree) {
    Write-Host "[REFUSED] '$target' is the primary checkout (main worktree). This script never removes it."
    exit 2
}
if (-not ($worktrees | Where-Object { $_ -ieq $target })) {
    Write-Host "[REFUSED] '$target' is not a registered worktree of this repository."
    Write-Host "          Registered worktrees: see 'git worktree list'."
    exit 3
}

# Walk the tree without following links: a reparse point is recorded and never entered.
$links = New-Object System.Collections.Generic.List[object]
$unreadable = New-Object System.Collections.Generic.List[string]
$pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
$rootInfo = New-Object System.IO.DirectoryInfo($target)
if ($rootInfo.Exists) {
    if ($rootInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $links.Add($rootInfo)
    } else {
        $pending.Push($rootInfo)
    }
}
while ($pending.Count -gt 0) {
    $dir = $pending.Pop()
    try {
        $entries = $dir.GetFileSystemInfos()
    } catch {
        $unreadable.Add($dir.FullName)
        continue
    }
    foreach ($e in $entries) {
        if ($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $links.Add($e)
        } elseif ($e -is [System.IO.DirectoryInfo]) {
            $pending.Push($e)
        }
    }
}

if ($links.Count -gt 0) {
    Write-Host "[REFUSED] '$target' contains $($links.Count) link(s) (reparse points). git worktree remove could follow them and delete the target's files:"
    foreach ($l in $links) {
        $kind = 'link'
        $dest = '(target not reported)'
        try {
            $item = Get-Item -LiteralPath $l.FullName -Force
            if ($item.PSObject.Properties['LinkType'] -and $item.LinkType) { $kind = $item.LinkType }
            if ($item.PSObject.Properties['Target'] -and $item.Target) { $dest = ($item.Target | Select-Object -First 1) }
        } catch { }
        Write-Host "  - [$kind] $($l.FullName) -> $dest"
    }
    Write-Host "Delete each link on its own, non-recursively (cmd /c rmdir `"<link>`"), then run this script again."
    exit 1
}
if ($unreadable.Count -gt 0) {
    Write-Host "[REFUSED] Could not read $($unreadable.Count) folder(s) under '$target', so the link scan is incomplete:"
    foreach ($u in $unreadable) { Write-Host "  - $u" }
    exit 4
}

Write-Host "[OK] '$target' is a registered worktree with no links."
if ($PSCmdlet.ShouldProcess($target, 'git worktree remove')) {
    & git -C $repoDir worktree remove $target
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git worktree remove failed (exit $LASTEXITCODE). Nothing else was done."
        exit 5
    }
    Write-Host "[REMOVED] $target"
} else {
    Write-Host "[WHATIF] Nothing was changed."
}
exit 0
