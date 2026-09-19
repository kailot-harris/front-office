@echo off
REM ==============================================================================
REM schedule_weekly_audit.bat
REM Windows Task Scheduler target for this repo's two repo-health audit skills.
REM Path: c:\Users\kailo\kayceeslices\WNBA Analytics\schedule_weekly_audit.bat
REM
REM Runs orphaned-cache-audit and config-constant-drift-audit and appends their
REM output to logs/weekly_audit.log. Both scripts are advisory only (exit 0
REM regardless of findings) -- this job does not gate anything or send alerts;
REM it exists so findings like the 3-remediation-wave-old orphaned
REM cache/features_cache.rds gap (docs/HANDOFF.md, 2026-09-17) get surfaced on a
REM regular cadence instead of only when someone happens to run the skill by
REM hand. Read logs/weekly_audit.log periodically (or grep it for "ORPHANED",
REM "DEAD", "UNUSED", or "[review]") -- this script does not fail the job or
REM email anyone.
REM
REM NOT wired into schedule_daily.bat / run_full_pipeline.R on purpose: these are
REM static-analysis / repo-hygiene checks against source files and config.R, not
REM part of the daily data pipeline's DAG, and don't need to run more than weekly.
REM
REM One-time setup (not run automatically by anything in this repo -- register by
REM hand once, matching how schedule_daily.bat is registered):
REM   schtasks /create /tn "WNBA Weekly Audit" /tr "\"c:\Users\kailo\kayceeslices\WNBA Analytics\schedule_weekly_audit.bat\"" /sc weekly /d SUN /st 08:00
REM ==============================================================================

set PROJECT_DIR=c:\Users\kailo\kayceeslices\WNBA Analytics
set LOG_FILE=%PROJECT_DIR%\logs\weekly_audit.log

cd /d "%PROJECT_DIR%"
if not exist "logs" mkdir "logs"

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\Rscript.exe"
)

echo ================================================================== >> "%LOG_FILE%"
echo WNBA WEEKLY AUDIT RUN: %DATE% %TIME% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

echo [1/2] orphaned-cache-audit... >> "%LOG_FILE%"
%RSCRIPT% ".claude\skills\orphaned-cache-audit\scripts\audit_caches.R" >> "%LOG_FILE%" 2>&1

echo [2/2] config-constant-drift-audit... >> "%LOG_FILE%"
%RSCRIPT% ".claude\skills\config-constant-drift-audit\scripts\audit_constants.R" >> "%LOG_FILE%" 2>&1

echo WNBA WEEKLY AUDIT RUN COMPLETE: %DATE% %TIME% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

exit /b 0
