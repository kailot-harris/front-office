@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM tools\schedule_slot_c.bat -- Windows Task Scheduler target for NBA Slot C
REM (01:00 local).
REM
REM Regenerates nba_predictions_<date>.png/.gif and nba_predictions_today.png/.gif
REM for the new calendar day (with a clean no-games fallback card when zero
REM games are scheduled) via tools\refresh_slot_c.R, and runs tools\publish_web.R
REM so media-only diffs publish cleanly through Assertion C (NBA_analytics#130).
REM
REM MODE (argument 1), matching schedule_daily.bat:
REM   (none) / publish  -> render + live publish (commit + push main)  [DEFAULT]
REM   dryrun            -> render + publish gate dry run
REM   strict            -> render + dry run (stage warnings fatal)
REM   publish-strict    -> render + live publish (stage warnings fatal)
REM ==============================================================================

set PROJECT_DIR=%~dp0..
for %%I in ("%PROJECT_DIR%") do set PROJECT_DIR=%%~fI
if defined NBA_PROJECT_DIR set PROJECT_DIR=%NBA_PROJECT_DIR%
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log

for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Get-Date).ToString('MM')"`) do set CUR_MM=%%I

echo ================================================================== >> "%LOG_FILE%"
echo NBA SLOT C REFRESH: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

if defined NBA_IGNORE_SEASON_GUARD goto :inseason
if "%CUR_MM%"=="07" goto :offseason
if "%CUR_MM%"=="08" goto :offseason
if "%CUR_MM%"=="09" goto :offseason
goto :inseason

:offseason
echo [SKIPPED] Current month %CUR_MM% is outside the NBA season window (October-June). >> "%LOG_FILE%"
exit /b 0

:inseason
if not defined HOME set HOME=%USERPROFILE%
cd /d "%PROJECT_DIR%"

set MODE=%~1
if "%MODE%"=="" set MODE=publish

set SC_ARGS=
set MODE_LABEL=
if /i "%MODE%"=="dryrun" set MODE_LABEL=DRY RUN
if /i "%MODE%"=="dryrun" set SC_ARGS=--dry-run
if /i "%MODE%"=="strict" set MODE_LABEL=DRY RUN (strict warnings)
if /i "%MODE%"=="strict" set SC_ARGS=--dry-run --strict-warnings
if /i "%MODE%"=="publish" set MODE_LABEL=LIVE PUBLISH
if /i "%MODE%"=="publish" set SC_ARGS=--publish
if /i "%MODE%"=="publish-strict" set MODE_LABEL=LIVE PUBLISH (strict warnings)
if /i "%MODE%"=="publish-strict" set SC_ARGS=--publish --strict-warnings

if "%MODE_LABEL%"=="" (
    echo [ERROR] schedule_slot_c.bat: unknown mode "%MODE%". >> "%LOG_FILE%"
    exit /b 2
)

REM Checkout-safety guard (front-office#105): ensure clean main before writing.
set GUARD_TMP=%PROJECT_DIR%\.slotc_guard.tmp
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set PRE_BRANCH=%%B
git status --porcelain -u > "%GUARD_TMP%" 2>&1
set DIRTY=0
for %%A in ("%GUARD_TMP%") do if %%~zA GTR 0 set DIRTY=1
del "%GUARD_TMP%" >nul 2>&1

if "%DIRTY%"=="1" (
    echo [GUARD] Working tree is dirty on "%PRE_BRANCH%" - stashing before checkout. >> "%LOG_FILE%"
    git stash push -u -m "schedule_slot_c.bat auto-stash %DATE% %TIME%" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo [ERROR] schedule_slot_c.bat: git stash failed. Slot C NOT run. >> "%LOG_FILE%"
        exit /b 3
    )
)

git checkout main >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] schedule_slot_c.bat: git checkout main failed. Slot C NOT run. >> "%LOG_FILE%"
    exit /b 3
)

call "%PROJECT_DIR%\tools\ff_main.bat" "%LOG_FILE%"
if errorlevel 1 (
    echo [ERROR] schedule_slot_c.bat: main could not be fast-forwarded. Slot C NOT run. >> "%LOG_FILE%"
    exit /b 4
)

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

set PUB_HEAD_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_BEFORE=%%S

%RSCRIPT% --vanilla "%PROJECT_DIR%\tools\refresh_slot_c.R" %SC_ARGS% >> "%LOG_FILE%" 2>&1
set SLOTC_RC=%ERRORLEVEL%

set PUB_HEAD_AFTER=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_AFTER=%%S

if not "%SLOTC_RC%"=="0" (
    echo [ERROR] Slot C refresh FAILED with exit code %SLOTC_RC% in mode %MODE_LABEL%. >> "%LOG_FILE%"
    exit /b %SLOTC_RC%
)

echo [OK] Slot C refresh completed in mode %MODE_LABEL%. >> "%LOG_FILE%"

set SYNC_DISPATCH=0
if defined PUB_HEAD_BEFORE if defined PUB_HEAD_AFTER if not "%PUB_HEAD_AFTER%"=="%PUB_HEAD_BEFORE%" set SYNC_DISPATCH=1
set GH_BIN=
if "%SYNC_DISPATCH%"=="1" where gh >nul 2>&1
if "%SYNC_DISPATCH%"=="1" if not errorlevel 1 set "GH_BIN=gh"
if "%SYNC_DISPATCH%"=="1" if not defined GH_BIN if exist "%ProgramFiles%\GitHub CLI\gh.exe" set "GH_BIN=%ProgramFiles%\GitHub CLI\gh.exe"
if "%SYNC_DISPATCH%"=="1" if defined GH_BIN (
    echo [INFO] Dispatching aggregator sync after Slot C publish: HEAD %PUB_HEAD_BEFORE% -^> %PUB_HEAD_AFTER%. >> "%LOG_FILE%"
    call "!GH_BIN!" workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb nfl nba wnba" -f deploy=true >> "%LOG_FILE%" 2>&1
)

exit /b 0
