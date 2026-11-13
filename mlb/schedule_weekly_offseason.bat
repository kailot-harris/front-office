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
REM   This daily script executes build_offseason_monitor.R, runs the pre-publish
REM   end-to-end regression test suite (tools/offseason/test_dag_end_to_end.R), and
REM   publishes web artifacts via tools/publish_web.R --publish --mode=offseason.
REM
REM Winter DST Direct Workflow Dispatch:
REM   sync-sports.yml runs at cron: '30 13 * * *' (13:30 UTC). Under Eastern
REM   Standard Time (EST), 07:00 local is 12:00 UTC (90 min before the cron);
REM   under EDT, 07:00 local is 11:00 UTC (2.5h before). To ensure the published
REM   edition deploys immediately rather than waiting for the scheduled cron,
REM   this script directly dispatches:
REM     gh workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb" -f deploy=true
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
REM `git stash -u`'d, never `git checkout -- .`'d away. If this checkout
REM cannot be verified clean on main, NOTHING below this point runs.
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
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] [Checkout Guard] Working tree is dirty. Stashing with 'git stash -u' before touching HEAD -- never discarding with 'git checkout -- .'. >> "%RUN_LOG%"
    git stash push -u -m "auto-stash by schedule_weekly_offseason.bat checkout guard %DATE% %TIME%" >> "%RUN_LOG%" 2>&1
    if errorlevel 1 (
        echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] [Checkout Guard] 'git stash -u' failed, so this wrapper is NOT touching HEAD. Nothing was run or published. >> "%RUN_LOG%"
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

REM Step 1: Build Offseason Monitor dataset and reconcile state
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 1: Running build_offseason_monitor.R... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla build_offseason_monitor.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] build_offseason_monitor.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 2: Run End-to-End DAG Regression Suite prior to publishing (GitHub issue #62)
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 2: Running tools/offseason/test_dag_end_to_end.R... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla tools/offseason/test_dag_end_to_end.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/offseason/test_dag_end_to_end.R failed with exit code %ERRORLEVEL%. Halting publication. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 3: Publish web artifacts and promote staged baseline
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 3: Running tools/publish_web.R --publish --mode=offseason... >> "%RUN_LOG%"
"%RSCRIPT%" --vanilla tools/publish_web.R --publish --mode=offseason >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/publish_web.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 4: Direct aggregator workflow dispatch to overcome Winter DST inversion
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 4: Dispatching aggregator sync-sports workflow... >> "%RUN_LOG%"
where gh >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\GitHub CLI\gh.exe" set "PATH=%PATH%;C:\Program Files\GitHub CLI"
)
gh workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb" -f deploy=true >> "%RUN_LOG%" 2>&1
if errorlevel 1 (
    echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] Workflow dispatch returned non-zero exit code. >> "%RUN_LOG%"
) else (
    echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Workflow dispatch successfully triggered. >> "%RUN_LOG%"
)

echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Daily offseason monitor run completed successfully. >> "%RUN_LOG%"
exit /b 0
