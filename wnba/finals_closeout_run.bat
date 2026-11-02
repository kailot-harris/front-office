@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM finals_closeout_run.bat
REM One-shot Task Scheduler target for closing out the 2026 WNBA Finals
REM (issues #116, #117, #118) once Game 7 lands in the upstream wehoop feed.
REM
REM Registered as a ONE-TIME task for 2026-11-01 09:00 local -- the same
REM publish-clearance floor schedule_daily.bat documents (09:00 local clears
REM the ~10:36 UTC wehoop trigger / ~12:20 UTC worst-case upload completion
REM by a comfortable margin in both EDT and EST).
REM
REM Chain: daily_ingest.R (pull Game 7 box score) -> build_finals_game_predictions.R
REM -> build_playoff_bracket_2026.R -> export_web_json.R -> tools/publish_web.R
REM (DRY RUN ONLY -- no args -- so a human reviews the assertions before anything
REM is pushed live; see issue #116's own acceptance criterion: "dry-run and
REM verify assertions pass cleanly").
REM
REM This does NOT touch run_full_pipeline.R (separate pre-existing recurring
REM task) and does NOT implement #117 (capture_baseline_s0.R) or #118's UI work
REM -- those need the resolved Finals data this script produces as an input,
REM and are done by hand afterward.
REM ==============================================================================

set PROJECT_DIR=%~dp0
if "%PROJECT_DIR:~-1%"=="\" set PROJECT_DIR=%PROJECT_DIR:~0,-1%
set LOG_FILE=%PROJECT_DIR%\finals_closeout.log

if not defined HOME set HOME=%USERPROFILE%
cd /d "%PROJECT_DIR%"

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo ================================================================== >> "%LOG_FILE%"
echo FINALS CLOSEOUT RUN: %DATE% %TIME% >> "%LOG_FILE%"
echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

set CLOSEOUT_FAILED=0

echo [Step 1/5] daily_ingest.R (pull Game 7 box score)... >> "%LOG_FILE%"
%RSCRIPT% "daily_ingest.R" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
    set CLOSEOUT_FAILED=1
    echo [ERROR] Step 1/5 daily_ingest.R FAILED. >> "%LOG_FILE%"
)

echo [Step 2/5] build_finals_game_predictions.R... >> "%LOG_FILE%"
%RSCRIPT% "build_finals_game_predictions.R" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
    set CLOSEOUT_FAILED=1
    echo [ERROR] Step 2/5 build_finals_game_predictions.R FAILED. >> "%LOG_FILE%"
)

echo [Step 3/5] build_playoff_bracket_2026.R... >> "%LOG_FILE%"
%RSCRIPT% "build_playoff_bracket_2026.R" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
    set CLOSEOUT_FAILED=1
    echo [ERROR] Step 3/5 build_playoff_bracket_2026.R FAILED. >> "%LOG_FILE%"
)

echo [Step 4/5] export_web_json.R... >> "%LOG_FILE%"
%RSCRIPT% "export_web_json.R" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
    set CLOSEOUT_FAILED=1
    echo [ERROR] Step 4/5 export_web_json.R FAILED. >> "%LOG_FILE%"
)

echo [Step 5/5] tools/publish_web.R (dry run, no args)... >> "%LOG_FILE%"
%RSCRIPT% "tools\publish_web.R" >> "%LOG_FILE%" 2>&1
if not "%ERRORLEVEL%"=="0" (
    set CLOSEOUT_FAILED=1
    echo [ERROR] Step 5/5 publish_web.R dry run FAILED or reported failing assertions. >> "%LOG_FILE%"
)

echo ================================================================== >> "%LOG_FILE%"
if "%CLOSEOUT_FAILED%"=="1" (
    echo FINALS CLOSEOUT RUN COMPLETED WITH ERRORS: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo FINALS CLOSEOUT RUN COMPLETED SUCCESSFULLY ^(dry run^): %DATE% %TIME% >> "%LOG_FILE%"
    echo Review "%LOG_FILE%" and the regenerated web/public/data/*.json, then run >> "%LOG_FILE%"
    echo tools/publish_web.R --publish by hand once satisfied. >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"

if "%CLOSEOUT_FAILED%"=="1" (
    exit /b 1
) else (
    exit /b 0
)
