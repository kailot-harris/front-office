@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_weekly_offseason.bat (MLB Analytics)
REM Windows Task Scheduler target for the MLB Offseason Dynamics Monitor.
REM Path: %~dp0schedule_weekly_offseason.bat
REM
REM Cadence: Weekly on Mondays at 09:00 local (Slot A).
REM Target task name: "MLB Analytics Schedule Weekly Offseason"
REM
REM Rationale:
REM   In the off-season, there are no live games. What moves is roster,
REM   contract, and organizational state, arriving irregularly as text.
REM   This weekly script executes build_offseason_monitor.R, runs the pre-publish
REM   end-to-end regression test suite (tools/offseason/test_dag_end_to_end.R), and
REM   publishes web artifacts via tools/publish_web.R --publish --mode=offseason.
REM
REM Winter DST Direct Workflow Dispatch:
REM   sync-sports.yml runs at cron: '30 13 * * *' (13:30 UTC). Under Eastern
REM   Standard Time (EST), 09:00 local is 14:00 UTC, so the aggregator pull fires
REM   30 minutes BEFORE the local pipeline starts, causing a 24h deploy lag.
REM   To solve this across DST boundaries, this script directly dispatches:
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
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Starting weekly offseason monitor pipeline run. >> "%RUN_LOG%"
echo ================================================================== >> "%RUN_LOG%"

REM Defense-in-depth for git commit identity resolution under Task Scheduler
if not defined HOME if defined USERPROFILE set HOME=%USERPROFILE%

REM Resolve Rscript executable
set RSCRIPT=
where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    if exist "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" (
        set RSCRIPT="C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
    ) else (
        for /d %%i in ("C:\Program Files\R\R-*") do (
            if exist "%%i\bin\Rscript.exe" set RSCRIPT="%%i\bin\Rscript.exe"
        )
    )
)

if "%RSCRIPT%"=="" (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] Rscript not found on PATH or in C:\Program Files\R. Aborting. >> "%RUN_LOG%"
    exit /b 1
)

REM Step 1: Build Offseason Monitor dataset and reconcile state
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 1: Running build_offseason_monitor.R... >> "%RUN_LOG%"
%RSCRIPT% --vanilla build_offseason_monitor.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] build_offseason_monitor.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 2: Run End-to-End DAG Regression Suite prior to publishing (GitHub issue #62)
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 2: Running tools/offseason/test_dag_end_to_end.R... >> "%RUN_LOG%"
%RSCRIPT% --vanilla tools/offseason/test_dag_end_to_end.R >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/offseason/test_dag_end_to_end.R failed with exit code %ERRORLEVEL%. Halting publication. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 3: Publish web artifacts and promote staged baseline
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 3: Running tools/publish_web.R --publish --mode=offseason... >> "%RUN_LOG%"
%RSCRIPT% --vanilla tools/publish_web.R --publish --mode=offseason >> "%RUN_LOG%" 2>&1
if %ERRORLEVEL% neq 0 (
    echo [%DATE% %TIME%] [ERROR] [schedule_weekly_offseason.bat] tools/publish_web.R failed with exit code %ERRORLEVEL%. >> "%RUN_LOG%"
    exit /b %ERRORLEVEL%
)

REM Step 4: Direct aggregator workflow dispatch to overcome Winter DST inversion
echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Step 4: Dispatching aggregator sync-sports workflow... >> "%RUN_LOG%"
set GH_BIN=
where gh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set GH_BIN=gh
) else (
    if exist "C:\Program Files\GitHub CLI\gh.exe" (
        set GH_BIN="C:\Program Files\GitHub CLI\gh.exe"
    )
)

if not "%GH_BIN%"=="" (
    %GH_BIN% workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb" -f deploy=true >> "%RUN_LOG%" 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Workflow dispatch successfully triggered. >> "%RUN_LOG%"
    ) else (
        echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] Workflow dispatch returned exit code !ERRORLEVEL!. >> "%RUN_LOG%"
    )
) else (
    echo [%DATE% %TIME%] [WARN] [schedule_weekly_offseason.bat] GitHub CLI (gh) not found; skipping direct workflow dispatch. >> "%RUN_LOG%"
)

echo [%DATE% %TIME%] [INFO] [schedule_weekly_offseason.bat] Weekly offseason monitor run completed successfully. >> "%RUN_LOG%"
exit /b 0
