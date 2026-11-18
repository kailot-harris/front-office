@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM tools\ff_main.bat -- bring local main up to origin/main before a scheduled run
REM (NBA_analytics issue #162).
REM
REM Usage:  call tools\ff_main.bat "<log file>"
REM Run it from the checkout root, on main, with a clean tree. schedule_daily.bat
REM calls it right after its checkout-safety guard has proved exactly that.
REM
REM   1. git fetch origin main
REM        fails -> [WARN], exit 0: the run continues on the local main. A
REM        missing network or credential under Task Scheduler must not block
REM        the pipeline.
REM   2. git merge --ff-only origin/main
REM        fails -> [ERROR], exit 4: local main has diverged (or the merge is
REM        blocked). Nothing is reset and no commit is discarded; a human
REM        decides. The caller must not run the pipeline.
REM   3. Logs main's SHA before and after, so the run log shows which code ran.
REM ==============================================================================
set "FF_LOG=%~1"
if "%FF_LOG%"=="" (
    echo [ERROR] tools\ff_main.bat: no log file given. Usage: tools\ff_main.bat "<log file>"
    exit /b 2
)

echo [FF] Fast-forward main to origin/main: %DATE% %TIME% >> "%FF_LOG%"

set BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set BEFORE=%%S
if "%BEFORE%"=="" (
    echo [ERROR] tools\ff_main.bat: "git rev-parse HEAD" failed. Pipeline must not run. >> "%FF_LOG%"
    exit /b 4
)
echo [FF] Before: main=%BEFORE% >> "%FF_LOG%"

git fetch origin main >> "%FF_LOG%" 2>&1
if errorlevel 1 (
    echo [WARN] tools\ff_main.bat: "git fetch origin main" failed. Continuing on local main=%BEFORE%. >> "%FF_LOG%"
    exit /b 0
)

set REMOTE=
for /f "delims=" %%S in ('git rev-parse origin/main 2^>nul') do set REMOTE=%%S
echo [FF] Fetched: origin/main=%REMOTE% >> "%FF_LOG%"

REM Self-update safety: the merge below may rewrite THIS file. cmd re-reads a
REM .bat from a saved byte offset after each command, so the merge and
REM everything after it, up to and including the exit, are ONE parenthesised
REM block that cmd parses whole before running it. Nothing is read from this
REM file after the merge. Inside the block, values set after the merge are read
REM with !VAR! (delayed expansion); %VAR% would expand when the block is parsed.
(
    git merge --ff-only origin/main >> "%FF_LOG%" 2>&1
    if errorlevel 1 (
        set COUNTS=
        for /f "delims=" %%C in ('git rev-list --left-right --count HEAD...origin/main 2^>nul') do set COUNTS=%%C
        echo [ERROR] tools\ff_main.bat: main cannot fast-forward to origin/main ^(main-only/origin-only commits: !COUNTS!^). >> "%FF_LOG%"
        echo [ERROR] Local main has diverged or the merge was blocked. Nothing was reset or discarded. >> "%FF_LOG%"
        echo [ERROR] main=%BEFORE% origin/main=%REMOTE%. Pipeline must not run until a human reconciles main. >> "%FF_LOG%"
        exit /b 4
    ) else (
        set AFTER=
        for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set AFTER=%%S
        if "!AFTER!"=="%BEFORE%" (
            echo [FF] Already up to date: main=!AFTER! >> "%FF_LOG%"
        ) else (
            echo [FF] Fast-forwarded main %BEFORE% -^> !AFTER! >> "%FF_LOG%"
        )
        exit /b 0
    )
)
