# ==============================================================================
# run_pipeline_task.ps1 -- Automated Execution Wrapper for the MLB Pipeline
# Used for Windows Task Scheduler, Cron/Automation, or standalone daemon runs.
#
# Three things were added on 2026-10-26, as step 3b/3c of the four-sport
# publish-cadence work. Each is explained where it appears:
#   1. a SEASONAL GUARD, ported from WNBA's schedule_daily.bat;
#   2. a PUBLISH GATE call, so the pipeline's output can reach the live site
#      without a human in the path; and
#   3. a MODE argument, taking the same words as the three sibling wrappers.
#
# Before this, the file ran run_full_pipeline.R, logged the exit code, and
# stopped. Nothing it produced ever reached git, which is why the four-repo
# audit found MLB's published projections reading 2026-10-23 on 2026-10-26.
#
# The audit attributed that to this missing git step. That turned out to be
# only half the story, and the other half is why the gate is here rather than a
# bare `git add`: the 2026-10-25 20:47 run DID regenerate every artifact, and a
# branch merge later the same evening (4c5306e at 21:15, eddc10d at 23:19)
# checked the committed versions back over the fresh output. The run's work was
# discarded, the working tree was left clean, and the file mtimes were left
# looking current because a checkout rewrites them. A git step alone would have
# found nothing to commit and reported success. tools/publish_web.R's assertion
# F -- which reads the generated_at stamp INSIDE each payload rather than its
# mtime -- is what catches that, and it is the reason this wrapper calls a gate
# instead of calling git.
# ==============================================================================

[CmdletBinding()]
param(
    # MODE, matching NFL's schedule_publish.bat and the NBA/WNBA
    # schedule_daily.bat wrappers so all four sports take the same words:
    #   dryrun          every assertion runs, NOTHING is published  [DEFAULT]
    #   publish         live: commit + push MLB-Analytics main only
    #   strict          dry run, exporter [WARN] lines fatal
    #   publish-strict  live publish, exporter [WARN] lines fatal
    #
    # Dry run is the DEFAULT ON PURPOSE. The unattended push is UNPROVEN on this
    # machine: credentials work in an interactive terminal (gh keyring plus
    # credential.helper=manager), but Task Scheduler's non-interactive session
    # may not reach Git Credential Manager, which would make a scheduled publish
    # hang on an auth prompt or fail obscurely at a time nobody is watching.
    # That is NFL Analytics issue #42, still open, and it applies verbatim here.
    #
    #   >>> Leave the registered task on dryrun until the unattended push is <<<
    #   >>> proven. Read the dry-run reports for a few days first.           <<<
    [ValidateSet('dryrun', 'publish', 'strict', 'publish-strict')]
    [string]$Mode = 'dryrun',

    # Escape hatch for running the pipeline out of season deliberately (a
    # backfill, a one-off re-export). The scheduled task does NOT pass it.
    [switch]$IgnoreSeasonGuard
)

$ErrorActionPreference = 'Continue'

$ProjectDir = "c:\Users\kailo\kayceeslices\front-office\MLB Analytics"
Set-Location -Path $ProjectDir

# Defense-in-depth for git commit identity resolution under Task Scheduler
# (cf. NFL_analytics#53): Windows PowerShell / Task Scheduler sessions do not
# set HOME by default, so git invoked from R's system2() can fail to locate
# ~/.gitconfig unless HOME is populated or publish_web.R passes -c user.name/email.
if (-not $env:HOME -and $env:USERPROFILE) {
    $env:HOME = $env:USERPROFILE
}

$LogFile = Join-Path $ProjectDir "logs\scheduled_runs.log"
function Write-Log([string]$Message) {
    Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message) -Encoding utf8
}

# Append a native command's own console output to the same log.
#
# NOT `& $exe args *>> $LogFile`, which is what this file used to do and what
# produced the interleaved "R s c r i p t . e x e" garbage in logs\scheduled_runs.log:
# PowerShell 5.1's redirection operators write UTF-16LE, while Add-Content above
# writes UTF-8, so the two halves of one log file ended up in two different
# encodings and the Rscript half was unreadable in any viewer that honoured the
# first. Capturing the output and re-writing it with an explicit -Encoding utf8
# keeps one encoding throughout.
#
# $LASTEXITCODE is read by the CALLER immediately after invoking this, not
# inside it -- a function call resets it, so capturing the code here and
# returning it would be the more obvious design and the wrong one.
function Add-NativeOutputToLog($OutputLines) {
    if ($null -eq $OutputLines) { return }
    foreach ($line in $OutputLines) {
        if ($null -eq $line) { continue }
        Add-Content -Path $LogFile -Value $line.ToString() -Encoding utf8
    }
}

# ------------------------------------------------------------------------------
# Seasonal guard. Ported from WNBA's schedule_daily.bat, which the four-repo
# audit flagged as the one sport that had one -- "add WNBA's seasonal guard to
# MLB while you are in there. MLB's dead window is Nov-Mar and it has no guard."
#
# Running the full pipeline daily through the dead months churns cache files
# against a league that is not playing, spends MLB Stats API budget for nothing,
# and -- the reason it actually matters -- keeps rewriting published artifacts
# with recomputed-but-unchanged content, which is the "silently serving stale
# data as if live" failure mode this whole body of work exists to stop.
#
# WINDOW: April through October inclusive. Derived from the 2026 calendar the
# repo already holds -- cache/ingest/mlb_schedule_2026.rds spans 2026-03-23 to
# 2026-11-01 including spring training, and the regular season plus postseason
# (the MATCHUP_GAME_TYPES set in config.R) runs 2026-03-26 to 2026-11-01. March
# is deliberately EXCLUDED even though spring training starts then: spring games
# are not part of MATCHUP_GAME_TYPES, so a March run has no publishable slate to
# build. November is excluded for the same reason at the other end -- a World
# Series ending 11-01 is covered by the final October run plus
# refresh-results.yml, which runs on a hosted runner year-round and patches
# finished results into the committed JSON without needing this machine awake.
#
# Like WNBA's, this window is a MANUAL constant in the wrapper rather than a
# config.R value, because a scheduler wrapper cannot source R before deciding
# whether to start R. Re-verify it at the turn of each season. Unlike WNBA's, it
# is in PowerShell, so it compares integers rather than zero-padded strings.
# ------------------------------------------------------------------------------
$SeasonActiveMonths = 4..10   # April (4) through October (10)
$CurrentMonth = (Get-Date).Month

Write-Log "================================================================"
Write-Log "MLB Analytics Pipeline scheduled run check (month=$CurrentMonth, mode=$Mode)"

if (-not $IgnoreSeasonGuard -and ($SeasonActiveMonths -notcontains $CurrentMonth)) {
    Write-Log "[SKIPPED] Month $CurrentMonth is outside the MLB season window (April-October)."
    Write-Log "[SKIPPED] Pipeline NOT run - avoiding dead-season cache churn and republished-but-unchanged artifacts."
    Write-Log "[SKIPPED] Finished results are still patched year-round by .github/workflows/refresh-results.yml."
    Write-Log "[SKIPPED] Pass -IgnoreSeasonGuard to run anyway (a backfill or a one-off re-export)."
    exit 0
}

# ------------------------------------------------------------------------------
# Resolve Rscript. The absolute path is tried first and PATH only as a fallback,
# which is the right order here: Task Scheduler's non-interactive session does
# not necessarily carry the same PATH as an interactive shell, and a bare
# `Rscript` that resolves to nothing fails later and more obscurely than a
# missing-file check does now.
# ------------------------------------------------------------------------------
$Rscript = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
if (-not (Test-Path $Rscript)) {
    $FromPath = Get-Command Rscript.exe -ErrorAction SilentlyContinue
    if ($null -eq $FromPath) {
        Write-Log "[ERROR] Rscript.exe not found at the expected path and not on PATH. Nothing was run."
        exit 1
    }
    $Rscript = $FromPath.Source
}
Write-Log "Using Rscript: $Rscript"

# ------------------------------------------------------------------------------
# 1. The pipeline.
# ------------------------------------------------------------------------------
Write-Log "[Step 1/2] Starting MLB Analytics pipeline (run_full_pipeline.R)"
$PipelineOutput = & $Rscript "run_full_pipeline.R" 2>&1
# $LASTEXITCODE is read on the very next line, before anything else can reset
# it, and coerced through a null guard: it is $null until a native command has
# run in this session, and an un-guarded $null formats as an empty string, which
# would log the uninformative "failed with Exit Code ." instead of a number.
$PipelineExit = if ($null -eq $LASTEXITCODE) { -1 } else { $LASTEXITCODE }
Add-NativeOutputToLog $PipelineOutput

if ($PipelineExit -eq 0) {
    Write-Log "[Step 1/2] Pipeline executed successfully (Exit Code 0)."
} else {
    Write-Log "[ERROR] [Step 1/2] Pipeline failed with Exit Code $PipelineExit."
}

# ------------------------------------------------------------------------------
# 2. The publish gate.
#
# It runs even when the pipeline reported a non-zero exit, and that is
# deliberate. run_stage() swallows a stage failure and the pipeline continues,
# so the exit code and the artifacts' state are only loosely related in both
# directions: a green run can leave stale output (proven on 2026-10-25) and a
# red run can leave perfectly publishable web payloads if the stage that failed
# was downstream of them. tools/publish_web.R decides on the artifacts, which is
# the only evidence that answers the question. A pipeline failure still shows up
# in the gate's own assertion A or D, which is where it belongs.
# ------------------------------------------------------------------------------
#Explicitly typed [string[]] and wrapped in @(...). Without both, PowerShell
# 5.1's `switch` unrolls a single-element array block (`{ @('--publish') }`)
# into a scalar System.String, and splatting `@PublishArgs` onto a native
# executable then iterates System.String as IEnumerable<char> -- passing
# `'-' '-' 'p' 'u' 'b' 'l' 'i' 's' 'h'` as nine separate argv tokens.
# publish_web.R saw `"--publish" %in% opts == FALSE`, ran in DRY RUN mode, and
# exited 0 while this wrapper logged "Publish gate passed in mode LIVE PUBLISH"
# (root cause of the 2026-10-27 15:50 silent no-op).
[string[]]$PublishArgs = @(switch ($Mode) {
    'dryrun'         { @() }
    'strict'         { '--strict-warnings' }
    'publish'        { '--publish' }
    'publish-strict' { '--publish'; '--strict-warnings' }
})
$ModeLabel = switch ($Mode) {
    'dryrun'         { 'DRY RUN' }
    'strict'         { 'DRY RUN (strict warnings)' }
    'publish'        { 'LIVE PUBLISH' }
    'publish-strict' { 'LIVE PUBLISH (strict warnings)' }
}

# Absolute path, not "tools\publish_web.R": Rscript on this machine SEGFAULTS
# (exit 139 / 0xC0000005) rather than erroring cleanly when handed a relative
# path that does not resolve against the current directory, so a Set-Location
# that silently did not take would surface as an unexplained crash in the log
# rather than as a missing file. This was reproduced while writing the sibling
# .bat wrappers, not assumed.
$PublishScript = Join-Path $ProjectDir "tools\publish_web.R"

Write-Log "----------------------------------------------------------------"
Write-Log "[Step 2/2] MLB web publish gate ($ModeLabel)"

if (-not (Test-Path $PublishScript)) {
    Write-Log "[ERROR] [Step 2/2] $PublishScript is missing. Nothing was published."
    exit $PipelineExit
}

$PublishOutput = & $Rscript $PublishScript @PublishArgs 2>&1
$PublishExit = if ($null -eq $LASTEXITCODE) { -1 } else { $LASTEXITCODE }
Add-NativeOutputToLog $PublishOutput

# Belt-and-braces check against the 2026-10-27 silent dry-run defect: if the
# caller asked for a live publish and the gate exited 0, the gate's own banner
# MUST confirm LIVE PUBLISH rather than DRY RUN.
if ($PublishExit -eq 0 -and ($Mode -eq 'publish' -or $Mode -eq 'publish-strict')) {
    $JoinedOut = ($PublishOutput | ForEach-Object { $_.ToString() }) -join "`n"
    if ($JoinedOut -match 'DRY RUN - nothing will be published' -or $JoinedOut -notmatch 'proceeding to commit and push') {
        $PublishExit = 2
        Write-Log "[ERROR] [Step 2/2] Mode '$Mode' requested LIVE PUBLISH, but publish_web.R ran in DRY RUN mode (argument passing failure)."
    }
}

# publish_web.R exits 0 only when nothing fatal failed and 1 on any fatal
# failure, "so a scheduled caller can branch on it". This is that caller.
if ($PublishExit -eq 0) {
    Write-Log "[OK] [Step 2/2] Publish gate passed in mode $ModeLabel."
} else {
    Write-Log "[ERROR] [Step 2/2] Publish gate exited $PublishExit in mode $ModeLabel."
    Write-Log "[ERROR] At least one fatal assertion failed - NOTHING WAS PUBLISHED."
    Write-Log "[ERROR] Yesterday's correct site stays up rather than a half-updated one."
    Write-Log "[ERROR] Read the '-- Assertions --' block in logs\mlb_pipeline.log: every"
    Write-Log "[ERROR] failing assertion is on a '[FAIL]' line with its id, name, summary"
    Write-Log "[ERROR] and the offending file or value in its detail lines."
}

Write-Log "MLB scheduled run finished (pipeline=$PipelineExit, publish=$PublishExit)."
Write-Log "================================================================"

# The PIPELINE's exit code is what Task Scheduler's "Last Run Result" reflects.
# A blocked publish on good-but-unchanged data is not a pipeline failure, and
# conflating the two would train whoever reads that column to ignore it. The
# gate's verdict is in the log above.
exit $PipelineExit
