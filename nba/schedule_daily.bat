@echo off
set PROJECT_DIR=c:\Users\kailo\kayceeslices\front-office\NBA Analytics
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

REM Run the master quantitative pipeline (all stages orchestrated internally in DAG order)
echo Running Master Quantitative Pipeline (run_full_pipeline.R)... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1
set PIPELINE_EXIT=%ERRORLEVEL%

echo ================================================================== >> "%LOG_FILE%"
if "%PIPELINE_EXIT%"=="0" (
    echo PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo PIPELINE RUN FAILED WITH EXIT CODE %PIPELINE_EXIT%: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

exit /b %PIPELINE_EXIT%