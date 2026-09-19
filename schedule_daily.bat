@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_daily.bat (WNBA port)
REM Windows Task Scheduler target for the WNBA Analytics pipeline.
REM Path: c:\Users\kailo\kayceeslices\WNBA Analytics\schedule_daily.bat
REM
REM Ported from NBA Analytics\schedule_daily.bat's 3-step structure. Per
REM WNBA_REPLICATION_PLAN.md section (e) risk #1, the WNBA off-season is much longer than the
REM NBA's (~6-7 months with zero live signal vs the NBA's ~3-month gap): the 2026 WNBA regular
REM season runs 2026-05-08 to 2026-09-24, with the playoffs tipping off 2026-09-27 (verified via
REM web search 2026-09-12: wnba.com "2026 Regular Season Key Dates" / "2026 Schedule Release").
REM Running the full pipeline daily during the ~7 dead months (Nov-Apr) would just churn stale
REM cache files against a league that isn't playing, burn ESPN/Odds-API rate-limit budget for
REM nothing, and risk the exact "silently serving stale data as if live" failure mode the plan
REM explicitly calls out. Unlike a bare comment-only warning, this file adds a REAL date-check
REM guard below that skips the pipeline run (and logs why) outside the season window, rather
REM than relying on whoever configures Task Scheduler to remember to disable/re-enable the task
REM by hand every year.
REM
REM IMPORTANT: the season window below (05-01 through 10-31, a small buffer around the exact
REM 05-08/09-27 dates above to comfortably cover variable year-to-year start dates and a
REM full postseason) is a MANUAL constant in this .bat file, not read from config.R (batch
REM script date arithmetic cannot easily source an R constant). Re-verify/update the two
REM MM values below at the start of each new WNBA season if the league's actual calendar
REM shifts meaningfully outside this window.
REM ==============================================================================

set PROJECT_DIR=c:\Users\kailo\kayceeslices\WNBA Analytics
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log
set LOG_MAX_BYTES=5242880

REM ------------------------------------------------------------------------------
REM Log rotation (docs/future-work.md item 8): pipeline_execution.log is append-only
REM and was growing unbounded (one git commit alone added 3,755 lines before it was
REM untracked from version control -- see .gitignore's 2026-09-19 update). Untracking
REM it from git only fixes the repo-bloat half of the problem; this keeps the live file
REM on disk bounded too. Single-generation rotation (.log -> .log.old, overwriting any
REM previous .old) rather than a numbered series -- this is an operational log for
REM manual troubleshooting, not an audit trail that needs long retention.
REM ------------------------------------------------------------------------------
if exist "%LOG_FILE%" (
    for %%F in ("%LOG_FILE%") do set LOG_SIZE=%%~zF
    if !LOG_SIZE! GTR %LOG_MAX_BYTES% (
        move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul
    )
)

REM ------------------------------------------------------------------------------
REM Seasonal guard: only run during the WNBA season window (~May through end of October,
REM covering regular season 2026-05-08 to 2026-09-24 plus playoffs starting 2026-09-27 with a
REM buffer for a Finals that could run into late October). Outside this window, log and exit
REM without touching any cache files.
REM ------------------------------------------------------------------------------
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value ^| find "="') do set DT=%%I
set CUR_MM=%DT:~4,2%

echo ================================================================== >> "%LOG_FILE%"
echo WNBA PIPELINE AUTOMATED RUN CHECK: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

REM Season-active months: 05 (May) through 10 (October). Anything else (11,12,01,02,03,04) is
REM off-season -> skip. String comparison works here because CUR_MM is always zero-padded 2 digits.
if "%CUR_MM%"=="01" goto :offseason
if "%CUR_MM%"=="02" goto :offseason
if "%CUR_MM%"=="03" goto :offseason
if "%CUR_MM%"=="04" goto :offseason
if "%CUR_MM%"=="11" goto :offseason
if "%CUR_MM%"=="12" goto :offseason
goto :inseason

:offseason
echo [SKIPPED] Current month %CUR_MM% is outside the WNBA season window (May-October). >> "%LOG_FILE%"
echo [SKIPPED] Pipeline NOT run - avoiding stale/dead-season data churn per WNBA_REPLICATION_PLAN.md (e) risk #1. >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason
cd /d "%PROJECT_DIR%"

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"

REM 1. Run the full 13-stage pipeline (rosters/injuries -> fatigue/shot-quality -> standings ->
REM    market odds -> props -> playoffs -> risk -> notify -> bet grading; see run_full_pipeline.R)
echo [Step 1/3] Running Full WNBA Pipeline... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1

REM 2. Grade yesterday's bets and compute rolling accuracy (also called inside
REM    run_full_pipeline.R itself - same known overlap/non-dedup as the NBA original, per
REM    REPO_MAP.md section 3.1's note; not fixed here since agent6.md doesn't ask for that cleanup)
echo [Step 2/3] Grading Yesterday's WNBA Bets & Rolling ROI... >> "%LOG_FILE%"
%RSCRIPT% "bet_tracker.r" >> "%LOG_FILE%" 2>&1

REM 3. Generate today's new +EV picks
echo [Step 3/3] Updating Today's WNBA Betting Slate (+EV Engine)... >> "%LOG_FILE%"
%RSCRIPT% "market_odds_engine.R" >> "%LOG_FILE%" 2>&1

echo ================================================================== >> "%LOG_FILE%"
echo WNBA PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

exit /b 0
