@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_weekly_offseason.bat (MLB Analytics)
REM Windows Task Scheduler target for the MLB Offseason Dynamics Monitor.
REM Path: %~dp0schedule_weekly_offseason.bat
REM
REM Cadence: Daily at 07:00 local (Slot A).
REM Target task name: "MLB Analytics Schedule Weekly Offseason"
REM   (Note: Task and file names are retained historically to preserve compatibility;
REM   cadence is daily 07:00 local per issue #66, matching the 26h freshness gate).
REM
REM Rationale:
REM   In the off-season, there are no live games. What moves is roster,
REM   contract, and organizational state, arriving irregularly as text.
REM   This daily script runs the offline end-to-end DAG regression test suite
REM   (tools/offseason/test_dag_end_to_end.R), executes build_offseason_monitor.R,
REM   and publishes web artifacts via tools/publish_web.R --publish --mode=offseason.
REM
REM Direct Workflow Dispatch (Step 4):
REM   sync-sports.yml's cron ('30 13 * * *') is only a backstop: GitHub has been
REM   starting it hours late (21:21-22:57 UTC observed in November 2026), so a
REM   07:00 publish could sit unpublished most of the day. After a publish that
REM   exited 0 AND actually pushed a new commit (refs/remotes/origin/main moved
REM   during Step 3), this script dispatches:
REM     gh workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb nfl nba wnba" -f deploy=true
REM   All four sports, not just MLB: see the comment at Step 4. Nothing pushed
REM   means no dispatch. A failed dispatch (gh missing, not signed in, network)
REM   is a [WARN] line and never changes this script's exit code.
REM ==============================================================================

set PROJECT_DIR=%~dp0
if "%PROJECT_DIR:~-1%"=="\" set PROJECT_DIR=%PROJECT_DIR:~0,-1%
cd /d "%PROJECT_DIR%"

if not exist "logs" mkdir "logs"
REM LOG_FILE is the R-side structured text sink, owned exclusively by
REM logging_utils.R. cmd.exe must NEVER redirect into it: holding an open write
REM handle here makes the R-side `cat(file = LOG_FILE, append = TRUE)` fail with
REM "cannot open the connection" and halts the pipeline (issue #55). All child
REM process transcripts and this script's own echo lines go to RUN_LOG instead.
set LOG_FILE=%PROJECT_DIR%\logs\mlb_pipeline.log
set RUN_LOG=%PROJECT_DIR%\logs\scheduled_runs.log

echo ================================================================== >> "%RUN_LOG%"
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Starting daily offseason monitor pipeline run. >> "%RUN_LOG%"
echo ================================================================== >> "%RUN_LOG%"

REM ==============================================================================
REM CHECKOUT-SAFETY GUARD (front-office issue #105).
REM
REM This machine's working directories are shared between this scheduled task
REM and interactive/agent sessions. The 2026-11-10 incident (front-office#105):
REM an agent left a sibling checkout on a feature branch with dirty,
REM regenerated output; a publish gate correctly refused it, and a THIRD
REM session then ran `git checkout -- .` to clear the dirty tree before
REM merging -- discarding 8 regenerated JSON files and a cache file instead
REM of stashing them. Published data stayed ~30 hours stale.
REM
REM Rule this guard enforces (see CLAUDE.md "Shared-checkout discipline"):
REM feature work happens in a worktree; THIS primary checkout stays on main
REM and clean for every unattended run; a dirty tree is always
REM stashed, never `git checkout -- .`'d away. If this checkout
REM cannot be verified clean on main, NOTHING below this point runs.
REM
REM `-u` is used ONLY when untracked, not-ignored files exist
REM (`git ls-files --others --exclude-standard` prints something), and those
REM files are listed in RUN_LOG first, because `-u` takes them off disk.
REM With tracked changes only, a plain `git stash push` is used: `-u` then has
REM nothing to save, and on this machine it made git try to clean
REM renv/cache/... and fail with "Permission denied" after creating the stash,
REM so the guard exited 97 every day from 2026-11-13 (MLB-Analytics#106).
REM ==============================================================================
where git >nul 2>&1
if errorlevel 1 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] git not found on PATH. Refusing to run against an unverified checkout. Nothing was run or published. >> "%RUN_LOG%"
    exit /b 97
)

for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set "CURRENT_BRANCH=%%b"
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] HEAD is currently on branch '%CURRENT_BRANCH%'. >> "%RUN_LOG%"

set "GUARD_STATUS_FILE=%TEMP%\mlb_guard_status_%RANDOM%.txt"
git status --porcelain -uall > "%GUARD_STATUS_FILE%" 2>&1
for %%A in ("%GUARD_STATUS_FILE%") do set "STATUS_SIZE=%%~zA"
if not "%STATUS_SIZE%"=="0" (
    REM Decide -u: only when untracked, not-ignored files exist. If ls-files
    REM itself fails, fall back to -u (its error text makes the file non-empty).
    set "GUARD_STASH_U="
    set "GUARD_UNTRACKED_FILE=%TEMP%\mlb_guard_untracked_%RANDOM%.txt"
    git ls-files --others --exclude-standard > "!GUARD_UNTRACKED_FILE!" 2>&1
    if errorlevel 1 set "GUARD_STASH_U=-u"
    for %%A in ("!GUARD_UNTRACKED_FILE!") do if not "%%~zA"=="0" set "GUARD_STASH_U=-u"
    set "GUARD_PREV_STASH=none"
    for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_PREV_STASH=%%s"
    if defined GUARD_STASH_U (
        echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] Working tree is dirty and has untracked, not-ignored files. Stashing with 'git stash push -u' before touching HEAD -- never discarding with 'git checkout -- .'. Untracked files this stash takes off disk ^(git ls-files --others --exclude-standard^): >> "%RUN_LOG%"
        type "!GUARD_UNTRACKED_FILE!" >> "%RUN_LOG%"
        echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] End of untracked file list. >> "%RUN_LOG%"
    ) else (
        echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] Working tree is dirty with tracked changes only. Stashing with 'git stash push' ^(no -u: nothing untracked to save^) before touching HEAD -- never discarding with 'git checkout -- .'. >> "%RUN_LOG%"
    )
    del "!GUARD_UNTRACKED_FILE!" >nul 2>&1
    git stash push !GUARD_STASH_U! -m "auto-stash by schedule_weekly_offseason.bat checkout guard %DATE% %TIME%" >> "%RUN_LOG%" 2>&1
    if errorlevel 1 (
        set "GUARD_NEW_STASH=none"
        for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_NEW_STASH=%%s"
        echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] 'git stash push !GUARD_STASH_U!' failed, so this wrapper is NOT touching HEAD. Newest stash is now !GUARD_NEW_STASH! ^(before this run: !GUARD_PREV_STASH!; if they differ, a stash was created before the failure^). Nothing was run or published. >> "%RUN_LOG%"
        REM A failed push can still have saved a stash (e.g. git saved it, then
        REM could not delete an untracked folder). Git then skips its reset, so
        REM the tree keeps the same changes AND a stash copy exists. Say so by
        REM SHA; refuse anyway. Nothing here drops, pops or discards anything.
        if not "!GUARD_NEW_STASH!"=="!GUARD_PREV_STASH!" (
            echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] Partial stash: 'git stash push !GUARD_STASH_U!' exited non-zero but DID create stash !GUARD_NEW_STASH! ^(stash@{0}^). The working tree may still be dirty ^(git skips its reset after such a failure^), so the same changes may exist both in the tree and in that stash. The stash was left in place for the owner to inspect. Refusing to run. Nothing was run or published. >> "%RUN_LOG%"
        )
        del "%GUARD_STATUS_FILE%" >nul 2>&1
        exit /b 97
    )
) else (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] Working tree is already clean. >> "%RUN_LOG%"
)
del "%GUARD_STATUS_FILE%" >nul 2>&1

if not "%CURRENT_BRANCH%"=="main" (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] HEAD is on '%CURRENT_BRANCH%', not 'main'. Checking out main. >> "%RUN_LOG%"
    git checkout main >> "%RUN_LOG%" 2>&1
    if errorlevel 1 (
        echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] 'git checkout main' failed. Nothing was run or published. >> "%RUN_LOG%"
        exit /b 97
    )
)

REM Final verification -- do not trust the steps above succeeded just because
REM they exited 0; re-read the actual landed state before running anything.
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set "FINAL_BRANCH=%%b"
set "GUARD_STATUS_FILE2=%TEMP%\mlb_guard_status2_%RANDOM%.txt"
git status --porcelain -uall > "%GUARD_STATUS_FILE2%" 2>&1
for %%A in ("%GUARD_STATUS_FILE2%") do set "FINAL_STATUS_SIZE=%%~zA"
del "%GUARD_STATUS_FILE2%" >nul 2>&1

if not "%FINAL_BRANCH%"=="main" (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] Failed to land cleanly on main -- HEAD is '%FINAL_BRANCH%'. Refusing to run the pipeline. Nothing was run or published. >> "%RUN_LOG%"
    exit /b 97
)
if not "%FINAL_STATUS_SIZE%"=="0" (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] HEAD is on main but the working tree is still dirty after stashing. Refusing to run the pipeline. Nothing was run or published. >> "%RUN_LOG%"
    exit /b 97
)
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] Verified: HEAD is on 'main' and the working tree is clean. Proceeding. >> "%RUN_LOG%"

REM ==============================================================================
REM FAST-FORWARD main TO origin/main (MLB-Analytics#101, ported from NBA #162).
REM
REM Without this, merged changes never ran until someone pulled by hand.
REM tools\ff_main.bat logs main's SHA before and after into RUN_LOG; a failed
REM fetch is a [WARN] and the run continues on the local main; a main that
REM cannot fast-forward (diverged, or the merge is blocked) is an [ERROR] and
REM NOTHING below runs. It never resets and never discards a commit.
REM
REM Self-update safety. cmd does not load a .bat into memory: after each
REM command it re-opens the file and reads on from a saved byte offset. If the
REM fast-forward rewrites THIS file, the old offset points into the new text
REM and cmd would run half-lines or skip steps, silently. So the call and ALL
REM of its result handling are one parenthesised block, which cmd parses whole
REM before running any of it. If this file changed, the block starts the
REM updated script fresh with the same arguments (MLB_FF_DONE=1 tells it the
REM fast-forward is already done) and exits with its exit code; nothing after
REM the block is read from the rewritten file. tools\ff_main.bat protects
REM itself the same way.
REM ==============================================================================
set "FF_BEFORE="
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set "FF_BEFORE=%%S"
if defined MLB_FF_DONE (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [FF] MLB_FF_DONE=%MLB_FF_DONE%: fast-forward already done by the instance that relaunched this one. Skipped. main=%FF_BEFORE% >> "%RUN_LOG%"
) else (
    call "%PROJECT_DIR%\tools\ff_main.bat" "%RUN_LOG%"
    if errorlevel 1 (
        echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [FF] main could not be fast-forwarded to origin/main. Nothing was run or published. >> "%RUN_LOG%"
        exit /b 4
    ) else (
        set "FF_AFTER="
        for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set "FF_AFTER=%%S"
        git diff --quiet !FF_BEFORE! !FF_AFTER! -- schedule_weekly_offseason.bat >nul 2>&1
        if errorlevel 1 (
            echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [FF] schedule_weekly_offseason.bat changed in the fast-forward !FF_BEFORE! -^> !FF_AFTER!. Relaunching the updated script once, same arguments: %* >> "%RUN_LOG%"
            set "MLB_FF_DONE=1"
            cmd /c ""%~f0" %*"
            exit /b !ERRORLEVEL!
        )
    )
)
REM Each "exit /b" above is the LAST command of its block on purpose: under
REM "cmd /c", an "exit /b N" followed by more commands in the same block makes
REM the process exit code 0 instead of N (seen in the NBA sandbox for #162).

REM ==============================================================================
REM RUN START (MLB-Analytics#74).
REM
REM Recorded ONCE, here, before Step 1 writes anything, and handed to Step 3 as
REM --run-start=YYYY-MM-DDTHH:MM:SS (local time). tools/publish_web.R's Gate A
REM requires every published dataset to be newer than this value. It used to
REM grep logs\mlb_pipeline.log for "Pipeline run started", a line only the
REM in-season pipeline writes, so off-season runs compared against the last
REM in-season run (2026-10-31 09:00:19) and certified stale files as FRESH.
REM
REM Taken after the checkout guard on purpose: a guard stash rewrites tracked
REM data files, and those rewrites must not count as regenerated by this run.
REM
REM %DATE%/%TIME% are locale-dependent, so the timestamp comes from PowerShell's
REM Get-Date with an explicit format. If it cannot be read, RUN_START stays
REM empty, Step 3 receives "--run-start=" and publish_web.R fails closed
REM (Gate A STALE, publish blocked). Nothing here substitutes a guessed value.
REM ==============================================================================
set "RUN_START="
for /f "usebackq delims=" %%t in (`powershell -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'"`) do set "RUN_START=%%t"
if defined RUN_START (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Run start recorded: !RUN_START! ^(passed to Step 3 as --run-start^). >> "%RUN_LOG%"
) else (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] Could not record the run start. Step 3 will fail closed and publish nothing. >> "%RUN_LOG%"
)

REM Defense-in-depth for git commit identity resolution under Task Scheduler
if not defined HOME if defined USERPROFILE set HOME=%USERPROFILE%

REM Resolve MLB_DISCORD_WEBHOOK from ~/.Renviron for notifications under --vanilla
if not defined MLB_DISCORD_WEBHOOK if exist "%USERPROFILE%\.Renviron" (
    for /f "usebackq tokens=1,* delims==" %%i in ("%USERPROFILE%\.Renviron") do (
        if "%%i"=="MLB_DISCORD_WEBHOOK" set "MLB_DISCORD_WEBHOOK=%%~j"
    )
)

REM Resolve Rscript executable
set "RSCRIPT="
where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "RSCRIPT=Rscript"
) else (
    if exist "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" (
        set "RSCRIPT=C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
    ) else (
        for /d %%i in ("C:\Program Files\R\R-*") do (
            if exist "%%i\bin\Rscript.exe" set "RSCRIPT=%%i\bin\Rscript.exe"
        )
    )
)

if "%RSCRIPT%"=="" (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] Rscript not found on PATH or in C:\Program Files\R. Aborting. >> "%RUN_LOG%"
    exit /b 1
)

REM Step 1: Run offline End-to-End DAG Regression Suite BEFORE building (GitHub issue #62)
REM test_dag_end_to_end.R is a pure offline fixture suite running in isolated temp
REM sandboxes, so running it first guarantees a test failure halts cleanly without
REM modifying tracked web/public/data/*.json and dirtying the primary checkout for
REM the next day's guard; /test-results/ is gitignored per .gitignore (#114).
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 1: Running tools/offseason/test_dag_end_to_end.R... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla tools/offseason/test_dag_end_to_end.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/offseason/test_dag_end_to_end.R failed with exit code %ERRORLEVEL%. Halting build and publication. >> "%RUN_LOG%"
    REM #103: back up the append-only files even when this step failed. %ERRORLEVEL%
    REM in this block was expanded when the block was parsed, so the exit below
    REM still returns the step's exit code, not the backup's.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -ProjectDir "%PROJECT_DIR%" >> "%RUN_LOG%" 2>&1
    exit /b %ERRORLEVEL%
)

REM Step 2: Build Offseason Monitor dataset and reconcile state
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 2: Running build_offseason_monitor.R... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla build_offseason_monitor.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] build_offseason_monitor.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    REM #103: back up the append-only files even when this step failed. %ERRORLEVEL%
    REM in this block was expanded when the block was parsed, so the exit below
    REM still returns the step's exit code, not the backup's.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -ProjectDir "%PROJECT_DIR%" >> "%RUN_LOG%" 2>&1
    exit /b %ERRORLEVEL%
)

REM Step 3: Publish web artifacts and promote staged baseline
REM ORIGIN_BEFORE is the Step 4 gate's "before" value: publish_web.R pushes with
REM `git push origin HEAD`, which also moves refs/remotes/origin/main, so a
REM different value after Step 3 means this run pushed a new commit.
set "ORIGIN_BEFORE="
for /f "delims=" %%S in ('git rev-parse --verify --quiet refs/remotes/origin/main 2^>nul') do set "ORIGIN_BEFORE=%%S"
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 3: Running tools/publish_web.R --publish --mode=offseason --run-start=!RUN_START!... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla tools/publish_web.R --publish --mode=offseason "--run-start=!RUN_START!" >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/publish_web.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    REM #103: back up the append-only files even when this step failed. %ERRORLEVEL%
    REM in this block was expanded when the block was parsed, so the exit below
    REM still returns the step's exit code, not the backup's.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -ProjectDir "%PROJECT_DIR%" >> "%RUN_LOG%" 2>&1
    exit /b %ERRORLEVEL%
)

REM Step 4: Dispatch the aggregator's sync-sports workflow, only when Step 3
REM pushed a new commit (refs/remotes/origin/main moved; Step 3 already exited
REM non-zero above if publish_web.R failed).
REM
REM Why all four sports, not just MLB: sync-sports.yml uses
REM `concurrency: group: sync-sports, cancel-in-progress: false`, and GitHub
REM keeps only ONE pending run per concurrency group, replacing an older
REM pending run with a newer one. A sport-specific request (sports="mlb") can
REM therefore be silently dropped when another sport dispatches while a sync
REM is running. A sync that always pulls all four makes any surviving run
REM correct for every sport.
REM
REM A failed dispatch (gh missing, not signed in, network) is a [WARN] line and
REM never changes this script's exit code: the publish already succeeded and
REM the sync-sports.yml cron is the backstop.
set "ORIGIN_AFTER="
for /f "delims=" %%S in ('git rev-parse --verify --quiet refs/remotes/origin/main 2^>nul') do set "ORIGIN_AFTER=%%S"
set "SYNC_DISPATCH=0"
if not defined ORIGIN_AFTER (
    echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] Step 4: could not read refs/remotes/origin/main after the publish, so whether a new commit was pushed is unknown. Not dispatching; the sync-sports.yml cron will pick up any push. >> "%RUN_LOG%"
) else if "!ORIGIN_AFTER!"=="!ORIGIN_BEFORE!" (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 4: nothing new was pushed ^(origin/main still !ORIGIN_AFTER!^). Skipping the sync-sports dispatch. >> "%RUN_LOG%"
) else (
    set "SYNC_DISPATCH=1"
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 4: publish pushed origin/main !ORIGIN_BEFORE! -^> !ORIGIN_AFTER!. Dispatching aggregator sync-sports workflow for mlb nfl nba wnba... >> "%RUN_LOG%"
)
if "!SYNC_DISPATCH!"=="1" (
    set "GH_EXE="
    where gh >nul 2>&1
    if not errorlevel 1 set "GH_EXE=gh"
    if not defined GH_EXE if exist "%ProgramFiles%\GitHub CLI\gh.exe" set "GH_EXE=%ProgramFiles%\GitHub CLI\gh.exe"
    if not defined GH_EXE (
        echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] Step 4: gh not found on PATH or in %%ProgramFiles%%\GitHub CLI. Sync-sports dispatch NOT sent; the publish stands and the sync-sports.yml cron is the backstop. >> "%RUN_LOG%"
    ) else (
        REM `call` so control returns here even if gh resolves to a .cmd/.bat shim.
        call "!GH_EXE!" workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb nfl nba wnba" -f deploy=true >> "%RUN_LOG%" 2>&1
        if errorlevel 1 (
            echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] Step 4: sync-sports dispatch failed ^(gh exited non-zero: not signed in, network, or workflow not found^). The publish stands; the sync-sports.yml cron is the backstop. >> "%RUN_LOG%"
        ) else (
            echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 4: sync-sports dispatch sent for mlb nfl nba wnba. >> "%RUN_LOG%"
        )
    )
)

REM ==============================================================================
REM BACK UP THE APPEND-ONLY FILES (MLB-Analytics#103, ported from NBA #164).
REM cache/ and logs/ are gitignored and inside this checkout, so nothing else
REM protects history a run builds up and cannot refetch. The script COPIES the
REM files it names (never moves or links them) to a dated folder outside any git
REM checkout, by default %USERPROFILE%\front-office-backups\mlb\YYYY-MM-DD\
REM (override: MLB_BACKUP_ROOT), keeps the 30 newest daily folders, and logs one
REM [BACKUP] line. It always exits 0: a failed copy is a [WARN] line and never
REM changes this run's exit code.
REM ==============================================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -ProjectDir "%PROJECT_DIR%" >> "%RUN_LOG%" 2>&1
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Daily offseason monitor run completed successfully. >> "%RUN_LOG%"
exit /b 0
