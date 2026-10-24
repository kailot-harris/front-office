@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_daily.bat (NFL port) -- GitHub issue #39 scope item 1.
REM Windows Task Scheduler target for the NFL Analytics pipeline (05:15 daily).
REM
REM Ported from NBA Analytics\schedule_daily.bat's structure, plus the two
REM improvements the WNBA wrapper has and the NBA one lacks (both required by #39):
REM   1. PIPELINE_FAILED tracking, so the final banner reflects reality. The NBA
REM      version prints "COMPLETED SUCCESSFULLY" unconditionally; the WNBA repo hit
REM      exactly this on 2026-10-01 (renv breakage hard-failed its steps 2 and 3
REM      with "Execution halted" while the log still claimed success).
REM   2. Single-generation log rotation, so the wrapper log stays bounded.
REM
REM Deliberately NOT ported: the WNBA wrapper's seasonal month guard. The NFL
REM season window is different and nothing in #39 asks for one.
REM
REM Step count differs from NBA/WNBA on purpose. Those wrappers run 3 steps because
REM their bet-grading and +EV steps live outside their DAG. NFL's run_full_pipeline.R
REM is self-contained -- bet_tracker.r, market_odds_engine.R and export_web_datasets.R
REM are all run_stage() entries in it (run_full_pipeline.R:268, :285, :352) -- so
REM re-invoking them here would duplicate stages that just ran. Hence one step.
REM Publishing is NOT a step here either: it is a separate 09:00 task
REM (schedule_publish.bat), per #39 scope item 3, so a long pipeline overrun cannot
REM silently delay the deploy and a publish can be re-run without re-running the
REM pipeline.
REM ==============================================================================

REM ------------------------------------------------------------------------------
REM PROJECT_DIR is the ONE value this file duplicates from config.R:22's PROJECT_DIR.
REM Per CLAUDE.md, a constant normally lives only in config.R and is never re-typed
REM at a call site -- but a .bat file cannot source R, so the project root has to be
REM stated here to be able to cd into it at all. The duplication is deliberately
REM limited to this single path: every other value the run needs (cache paths, web
REM paths, modeling constants) is read by the R code from config.R, not passed in
REM from here. If the repo ever moves, config.R:22 and this line must change together.
REM
REM The existing task NFL_analytics_task_01 runs Rscript against an absolute script
REM path with an EMPTY WorkingDirectory, which only survives today because config.R
REM hardcodes PROJECT_DIR (issue #43). This wrapper cd's explicitly instead of
REM relying on that, as the sibling wrappers do.
REM ------------------------------------------------------------------------------
set PROJECT_DIR=c:\Users\kailo\kayceeslices\front-office\nfl analytics

REM Wrapper log lives under logs\ so .gitignore's existing "logs/*.log" rule (line 56)
REM covers it. It is intentionally a DIFFERENT file from logging_utils.R:15's
REM logs\nfl_pipeline.log, which the R code writes: this one captures wrapper-level
REM stdout/stderr (including an R crash that never reaches the R logger).
set LOG_DIR=%PROJECT_DIR%\logs
set LOG_FILE=%LOG_DIR%\pipeline_execution.log

REM 5 MiB, matching the WNBA wrapper's threshold (LOG_MAX_BYTES=5242880) so the two
REM repos rotate at the same size. Chosen there because a single git commit added
REM 3,755 lines of this file before it was untracked; 5 MiB keeps many runs of
REM troubleshooting history while staying trivially openable in an editor.
set LOG_MAX_BYTES=5242880

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM ------------------------------------------------------------------------------
REM Single-generation log rotation (.log -> .log.old, overwriting any previous .old)
REM rather than a numbered series: this is an operational log for manual
REM troubleshooting, not an audit trail needing long retention.
REM ------------------------------------------------------------------------------
if exist "%LOG_FILE%" (
    for %%F in ("%LOG_FILE%") do set LOG_SIZE=%%~zF
    if !LOG_SIZE! GTR %LOG_MAX_BYTES% (
        move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul
    )
)

cd /d "%PROJECT_DIR%"

REM Resolve Rscript the same way the sibling wrappers do: prefer one already on
REM PATH, else fall back to the newest "C:\Program Files\R\R-*" install. The
REM `where` result is captured into WHERE_RC first so no %ERRORLEVEL% is ever read
REM inside a parenthesized block (see the delayed-expansion note below).
where Rscript >nul 2>&1
set WHERE_RC=%ERRORLEVEL%
if "%WHERE_RC%"=="0" (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo ================================================================== >> "%LOG_FILE%"
echo NFL PIPELINE AUTOMATED RUN: %DATE% %TIME% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"
echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"
echo Working directory: %CD% >> "%LOG_FILE%"

REM ------------------------------------------------------------------------------
REM Failure visibility. PIPELINE_FAILED tracks whether any step failed so the final
REM banner reflects reality instead of claiming success unconditionally.
REM
REM DELAYED-EXPANSION DISCIPLINE (the single most common way a batch wrapper
REM silently reports the wrong result): each step's %ERRORLEVEL% is captured into a
REM dedicated STEPn_RC variable *outside* any parenthesized block, then the block
REM tests that variable. Plain %VAR% expansion inside a ( ... ) block is substituted
REM at PARSE time -- i.e. before the step ran -- so reading %ERRORLEVEL% directly
REM inside a block would test a stale value. Never read %ERRORLEVEL% inside a block
REM in this file.
REM ------------------------------------------------------------------------------
set PIPELINE_FAILED=0

REM 1. Run the full NFL DAG (ingest -> rosters/injuries -> EPA -> ratings -> fatigue
REM    -> playoffs -> market/+EV -> bet ledger -> risk -> notify -> accuracy ->
REM    web export; see run_full_pipeline.R). Note run_stage() deliberately swallows
REM    individual stage failures and the pipeline can still exit 0 -- so a 0 here
REM    means "the orchestrator completed", NOT "every artifact is fresh". That is
REM    precisely why publishing is gated separately by tools/publish_web.R (#38)
REM    rather than chained onto a zero exit from this step.
echo [Step 1/1] Running Full NFL Pipeline... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1
set STEP1_RC=%ERRORLEVEL%
if not "%STEP1_RC%"=="0" (
    set PIPELINE_FAILED=1
    echo [ERROR] Step 1/1 - run_full_pipeline.R - FAILED with exit code %STEP1_RC% >> "%LOG_FILE%"
)

echo ================================================================== >> "%LOG_FILE%"
if "%PIPELINE_FAILED%"=="1" (
    echo NFL PIPELINE RUN COMPLETED WITH ERRORS: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo NFL PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM Exit code reflects the overall outcome so Task Scheduler's own "Last Run Result"
REM surfaces a failed run on top of the [ERROR] log lines -- while a healthy run
REM still exits 0, so Task Scheduler never flags a good run as failed.
if "%PIPELINE_FAILED%"=="1" (
    exit /b 1
) else (
    exit /b 0
)
