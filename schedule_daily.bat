@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_daily.bat -- Windows Task Scheduler target for the NBA pipeline.
REM
REM ------------------------------------------------------------------------------
REM SCHEDULED START TIME -- must stay AFTER the upstream hoopR data publish.
REM
REM Every load_nba_*() call in this repo reads pre-built release assets from
REM sportsdataverse/hoopR-nba-data, rebuilt by a batch job, NOT in near-real-time
REM after each game. Measured from that repo's own Actions history on 2026-10-26:
REM two runs a day, ~11:17-11:56 UTC and ~12:08-12:19 UTC. A game that ends at
REM 22:00 ET therefore appears in hoopR the NEXT MORNING, and not before ~12:20 UTC.
REM
REM The task was registered at 08:00 local, which is 12:00 UTC during EDT -- about
REM twenty minutes BEFORE the later window closes. So on any day the second run
REM lands late, this pipeline silently consumed YESTERDAY's build: last night's
REM games simply missing, with nothing anywhere reporting a problem. The WNBA
REM sibling repo found and documented the identical defect against wehoop (see
REM "WNBA Analytics\schedule_daily.bat"'s own note); this is the same bug, and it
REM was still live here when the four-sport cadence review found it on 2026-10-26.
REM
REM TARGET: 09:00 local = 13:00 UTC (EDT) / 14:00 UTC (EST). That is slot A of the
REM three-slot cadence -- all four sports run the full pipeline and publish, and
REM the aggregator's sync-sports.yml subtree-pulls and deploys 30 minutes later at
REM 13:30 UTC. It clears ~12:20 UTC by 40 minutes in EDT and by 100 in EST. If this
REM is ever re-registered, keep it at or after 09:00 local; do not move it earlier.
REM   schtasks /change /tn "NBA Analytics Daily Pipeline" /st 09:00
REM
REM NOT YET APPLIED as of 2026-10-26. This task is registered with RunLevel=Highest,
REM so changing its trigger needs an ELEVATED shell; a non-elevated
REM Set-ScheduledTask returns "Access is denied". The registered trigger is still
REM 08:00, so the race above is still live until the command is run.
REM ------------------------------------------------------------------------------
REM ==============================================================================
set PROJECT_DIR=c:\Users\kailo\kayceeslices\front-office\NBA Analytics
if defined NBA_PROJECT_DIR set PROJECT_DIR=%NBA_PROJECT_DIR%
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log
set LOG_MAX_BYTES=5242880

REM ------------------------------------------------------------------------------
REM Single-generation 5 MiB log rotation (.log -> .log.old), matching NFL and WNBA.
REM ------------------------------------------------------------------------------
if exist "%LOG_FILE%" (
    for %%F in ("%LOG_FILE%") do set LOG_SIZE=%%~zF
    if !LOG_SIZE! GTR %LOG_MAX_BYTES% (
        move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul
    )
)

REM ------------------------------------------------------------------------------
REM Seasonal guard (NFL_analytics#41): only run during the NBA season window
REM (October through June: months 10, 11, 12, 01, 02, 03, 04, 05, 06, covering
REM preseason/regular season through the NBA Finals). Outside this window (July
REM through September: 07, 08, 09), log and exit 0 without churning caches
REM against an inactive league. Set NBA_IGNORE_SEASON_GUARD=1 to override.
REM ------------------------------------------------------------------------------
for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Get-Date).ToString('MM')"`) do set CUR_MM=%%I

echo ================================================================== >> "%LOG_FILE%"
echo NBA PIPELINE AUTOMATED RUN: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

if defined NBA_IGNORE_SEASON_GUARD goto :inseason
if "%CUR_MM%"=="07" goto :offseason
if "%CUR_MM%"=="08" goto :offseason
if "%CUR_MM%"=="09" goto :offseason
goto :inseason

:offseason
echo [SKIPPED] Current month %CUR_MM% is outside the NBA season window (October-June). >> "%LOG_FILE%"
echo [SKIPPED] Pipeline NOT run - avoiding stale/off-season cache churn (set NBA_IGNORE_SEASON_GUARD=1 to override). >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason

if not defined HOME set HOME=%USERPROFILE%
cd /d "%PROJECT_DIR%"

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"

REM Run the master quantitative pipeline (all stages orchestrated internally in DAG order)
echo Running Master Quantitative Pipeline (run_full_pipeline.R)... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1
set PIPELINE_EXIT=%ERRORLEVEL%

echo ================================================================== >> "%LOG_FILE%"
if "%PIPELINE_EXIT%"=="0" (
    echo PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
    echo Rebuilding static export in web/out... >> "%LOG_FILE%"
    call npm --prefix web run build >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo Static export build failed! >> "%LOG_FILE%"
    ) else (
        echo Static export successfully refreshed. >> "%LOG_FILE%"
    )
    set RUN_PUBLISH=1
) else (
    echo PIPELINE RUN FAILED WITH EXIT CODE %PIPELINE_EXIT%: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Publish gate (2026-10-26). This REPLACES the inline
REM "git add / git commit / git push origin HEAD" subroutine that lived here.
REM
REM Why it was replaced the same day it was written: that subroutine pushed on
REM one condition only -- run_full_pipeline.R exited 0 -- and an exit code is
REM not evidence about the artifacts. run_stage() catches a stage failure and
REM the pipeline carries on, every engine in this repo falls back to a labelled
REM synthetic value rather than failing, and run_full_pipeline.R's own
REM provenance guard covers 3 of the 12 published payloads. A stale
REM cba_cap_sheet.json or matchups_slates.json therefore shipped without a word.
REM It also pushed `origin HEAD`, so run from a feature branch it would commit
REM the data there, push it, report success, and leave the site untouched --
REM sync-sports.yml pulls main.
REM
REM tools/publish_web.R makes all six of those checks (A mtime, B slate,
REM C real diff, D stage warnings, E publish branch, F embedded generated_at)
REM and commits and pushes ONLY when every fatal one passes. It is the single
REM publish mechanism for this repo now; nothing else here touches git.
REM
REM It is called at TOP LEVEL, not with `call :label` from inside the
REM parenthesised block above, and RUN_PUBLISH is what carries the decision out.
REM A block-local ERRORLEVEL/label dance is the delayed-expansion trap this
REM file's own sibling wrappers document, and the publish step is the last thing
REM that should be fragile.
REM
REM MODE (argument 1), mirroring NFL's schedule_publish.bat so the four sports
REM take the same words:
REM   (none) / dryrun   -> every assertion runs, NOTHING is published  [DEFAULT]
REM   publish           -> live: commit + push NBA_analytics main only
REM   strict            -> dry run, stage warnings fatal
REM   publish-strict    -> live publish, stage warnings fatal
REM
REM Dry run is the DEFAULT ON PURPOSE, and this is the same gate NFL is sitting
REM behind: the unattended push is UNPROVEN on this machine. Credentials work in
REM an interactive terminal (gh keyring plus credential.helper=manager), but
REM Task Scheduler's non-interactive session may not reach Git Credential
REM Manager, which would make a scheduled publish hang on an auth prompt or fail
REM obscurely at a time nobody is watching. That is NFL Analytics issue #42,
REM still open, and it applies verbatim here -- the git step this replaced was
REM written on 2026-10-26 and had never executed even once, so nothing about it
REM constitutes proof.
REM
REM   >>> Leave the registered task on `dryrun` until the unattended push is <<<
REM   >>> proven. Read the dry-run reports for a few days first.             <<<
REM ------------------------------------------------------------------
set MODE=%~1
if "%MODE%"=="" set MODE=publish

REM One `if` per assignment, never `if cond set A=x& set B=y`: in batch `&` ends
REM the conditional, so the second `set` would run even when the test is false.
set PW_ARGS=
set MODE_LABEL=
if /i "%MODE%"=="dryrun" set MODE_LABEL=DRY RUN
if /i "%MODE%"=="strict" set MODE_LABEL=DRY RUN (strict warnings)
if /i "%MODE%"=="strict" set PW_ARGS=--strict-warnings
if /i "%MODE%"=="publish" set MODE_LABEL=LIVE PUBLISH
if /i "%MODE%"=="publish" set PW_ARGS=--publish
if /i "%MODE%"=="publish-strict" set MODE_LABEL=LIVE PUBLISH (strict warnings)
if /i "%MODE%"=="publish-strict" set PW_ARGS=--publish --strict-warnings

if "%MODE_LABEL%"=="" (
    echo [ERROR] schedule_daily.bat: unknown publish mode "%MODE%". >> "%LOG_FILE%"
    echo [ERROR] Valid modes: dryrun ^(default^), strict, publish, publish-strict. >> "%LOG_FILE%"
    echo [ERROR] The pipeline already ran; only the publish step is being skipped. >> "%LOG_FILE%"
    exit /b 2
)

if not "%RUN_PUBLISH%"=="1" (
    echo [SKIPPED] Publish gate not run: the pipeline did not succeed. >> "%LOG_FILE%"
    echo. >> "%LOG_FILE%"
    exit /b %PIPELINE_EXIT%
)

echo ================================================================== >> "%LOG_FILE%"
echo NBA WEB PUBLISH GATE: %DATE% %TIME% >> "%LOG_FILE%"
echo Mode: %MODE_LABEL%  (argument: %MODE%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

REM publish_web.R exits 0 only when nothing fatal failed, 1 on any fatal
REM failure, so a scheduled caller can branch on it. PUBLISH_RC is captured
REM OUTSIDE any parenthesised block before being tested.
%RSCRIPT% "%PROJECT_DIR%\tools\publish_web.R" %PW_ARGS% >> "%LOG_FILE%" 2>&1
set PUBLISH_RC=%ERRORLEVEL%

echo ------------------------------------------------------------------ >> "%LOG_FILE%"
if not "%PUBLISH_RC%"=="0" (
    echo [ERROR] Publish gate FAILED with exit code %PUBLISH_RC% in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo [ERROR] At least one fatal assertion failed - NOTHING WAS PUBLISHED. >> "%LOG_FILE%"
    echo [ERROR] Yesterday's correct site stays up rather than a half-updated one. >> "%LOG_FILE%"
    echo [ERROR] Read the "-- Assertions --" block above: every failing assertion >> "%LOG_FILE%"
    echo [ERROR] is on a "[FAIL]" line with its id, name, summary and the >> "%LOG_FILE%"
    echo [ERROR] offending file or value in its detail lines. >> "%LOG_FILE%"
    echo NBA WEB PUBLISH GATE BLOCKED: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo [OK] Publish gate passed in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo NBA WEB PUBLISH GATE COMPLETED: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM The pipeline's own exit code is what Task Scheduler's "Last Run Result"
REM should reflect: a blocked publish on good-but-unchanged data is not a
REM pipeline failure, and conflating the two would train whoever reads that
REM column to ignore it. The gate's own verdict is in the log above, and in
REM PUBLISH_RC for anyone chaining off this file.
exit /b %PIPELINE_EXIT%
