@echo off
set PROJECT_DIR=c:\Users\kailo\kayceeslices\NBA Analytics
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log

echo ================================================================== >> "%LOG_FILE%"
echo NBA PIPELINE AUTOMATED RUN: %DATE% %TIME% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

cd /d "%PROJECT_DIR%"

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"

REM 1. Ingest yesterday's box scores
echo [Step 1/3] Running Daily Ingestion... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1

REM 2. Grade yesterday's bets and compute rolling accuracy
echo [Step 2/3] Grading Yesterday's Bets & Rolling ROI... >> "%LOG_FILE%"
%RSCRIPT% "bet_tracker.R" >> "%LOG_FILE%" 2>&1

REM 3. Generate today's new +EV picks
echo [Step 3/3] Updating Today's Betting Slate (+EV Engine)... >> "%LOG_FILE%"
%RSCRIPT% "market_odds_engine.R" >> "%LOG_FILE%" 2>&1

echo ================================================================== >> "%LOG_FILE%"
echo PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

exit /b 0