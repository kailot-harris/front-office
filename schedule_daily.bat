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
    echo Rebuilding static export in web/out... >> "%LOG_FILE%"
    call npm --prefix web run build >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo Static export build failed! >> "%LOG_FILE%"
    ) else (
        echo Static export successfully refreshed. >> "%LOG_FILE%"
    )
    call :commit_outputs
) else (
    echo PIPELINE RUN FAILED WITH EXIT CODE %PIPELINE_EXIT%: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

exit /b %PIPELINE_EXIT%

REM ------------------------------------------------------------------
REM Commit the refreshed web data so the published site tracks the run.
REM Never fails the pipeline: logs whatever goes wrong and returns 0.
REM ------------------------------------------------------------------
:commit_outputs
where git >nul 2>&1
if errorlevel 1 (
    echo git not found on PATH; skipping commit of refreshed data. >> "%LOG_FILE%"
    exit /b 0
)

echo Committing refreshed pipeline outputs... >> "%LOG_FILE%"
git add -A -- web/public/data >> "%LOG_FILE%" 2>&1
git diff --cached --quiet -- web/public/data
if not errorlevel 1 (
    echo No data changes to commit. >> "%LOG_FILE%"
    exit /b 0
)

git commit -m "data: automated pipeline refresh %DATE%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo Commit of refreshed data failed! >> "%LOG_FILE%"
    exit /b 0
)
echo Refreshed data committed. >> "%LOG_FILE%"

echo Pushing refreshed data to origin... >> "%LOG_FILE%"
git push origin HEAD >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo Push of refreshed data failed! >> "%LOG_FILE%"
) else (
    echo Refreshed data pushed. >> "%LOG_FILE%"
)
exit /b 0
