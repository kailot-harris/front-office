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
REM   3. Seasonal month guard (NFL_analytics#41): only run during the NFL season
REM      window (September through February, months 09,10,11,12,01,02), skipping
REM      March through August (03..08) unless NFL_IGNORE_SEASON_GUARD=1 is set.
REM
REM Step count differs from NBA/WNBA on purpose. Those wrappers run 3 steps because
REM NFL's run_full_pipeline.R is self-contained (accuracy_governance.R,
REM notify_pipeline_ops.R, and export_web_datasets.R are all run_stage() entries in it) --
REM so re-invoking them here would duplicate stages that just ran. Hence one step.
REM
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
REM from here. The path itself is derived from this file's location (see below).
REM
REM The existing task NFL_analytics_task_01 runs Rscript against an absolute script
REM path with an EMPTY WorkingDirectory, which only survives today because config.R
REM hardcodes PROJECT_DIR (issue #43). This wrapper cd's explicitly instead of
REM relying on that, as the sibling wrappers do.
REM ------------------------------------------------------------------------------
REM The project root is this wrapper's own directory (%~dp0 minus its trailing
REM backslash), so the same file works from any checkout without a hard-coded path.
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

REM Testing/worktree escape hatch: if NFL_PROJECT_DIR is set in the environment, it
REM wins. This lets the wrapper be exercised from a git worktree (or a relocated
REM checkout) without editing the file and without writing logs into the main
REM checkout. The registered scheduled tasks do NOT set it, so production always
REM uses this wrapper's own directory. No secret is involved -- it is a directory path only.
if defined NFL_PROJECT_DIR set PROJECT_DIR=%NFL_PROJECT_DIR%

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

REM ------------------------------------------------------------------------------
REM Seasonal guard (NFL_analytics#41): only run during the NFL season window
REM (September through February: months 09, 10, 11, 12, 01, 02, covering Kickoff
REM through Super Bowl). Outside this window (March through August: 03..08), log
REM and exit 0 without churning caches against an inactive league. Set
REM NFL_IGNORE_SEASON_GUARD=1 in the environment to force an out-of-season run.
REM ------------------------------------------------------------------------------
for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Get-Date).ToString('MM')"`) do set CUR_MM=%%I

if defined NFL_IGNORE_SEASON_GUARD goto :inseason
if "%CUR_MM%"=="03" goto :offseason
if "%CUR_MM%"=="04" goto :offseason
if "%CUR_MM%"=="05" goto :offseason
if "%CUR_MM%"=="06" goto :offseason
if "%CUR_MM%"=="07" goto :offseason
if "%CUR_MM%"=="08" goto :offseason
goto :inseason

:offseason
echo ================================================================== >> "%LOG_FILE%"
echo NFL PIPELINE AUTOMATED RUN CHECK: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"
echo [SKIPPED] Current month %CUR_MM% is outside the NFL season window (September-February). >> "%LOG_FILE%"
echo [SKIPPED] Pipeline NOT run - avoiding stale/off-season cache churn (set NFL_IGNORE_SEASON_GUARD=1 to override). >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason
cd /d "%PROJECT_DIR%"

REM ------------------------------------------------------------------------------
REM Checkout-safety guard (front-office issue #105). %PROJECT_DIR% is the SAME
REM working directory interactive sessions and subagents use -- the 2026-11-10
REM incident happened because a subagent left this exact checkout on
REM chore/nfl-week9-visual-media with uncommitted changes, and a later cleanup ran
REM `git checkout -- .` to force it clean, silently discarding 8 regenerated JSON
REM files and a cache file. This guard never discards: any dirty work (tracked AND
REM untracked, via -u) is `git stash -u`'d -- preserved, recoverable with
REM `git stash pop`, never dropped -- before the checkout lands on main. If it
REM cannot land cleanly on main for ANY reason (stash fails, checkout fails, HEAD
REM isn't main afterward, or main is still dirty afterward), the wrapper fails
REM loudly with a clear [ERROR] log line and a non-zero exit instead of silently
REM running the pipeline from the wrong branch or against a half-clean tree.
REM ------------------------------------------------------------------------------
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Checkout guard: "%CD%" is not a git work tree - refusing to run. >> "%LOG_FILE%"
    exit /b 1
)

set PRE_BRANCH=
for /f "usebackq delims=" %%B in (`git rev-parse --abbrev-ref HEAD`) do set PRE_BRANCH=%%B
echo [GUARD] Checkout guard: starting branch is "%PRE_BRANCH%". >> "%LOG_FILE%"

set GUARD_STATUS_FILE=%TEMP%\nfl_sched_guard_status_%RANDOM%.txt
git status --porcelain > "%GUARD_STATUS_FILE%" 2>nul
set GUARD_DIRTY_SIZE=0
for %%F in ("%GUARD_STATUS_FILE%") do set GUARD_DIRTY_SIZE=%%~zF
del /q "%GUARD_STATUS_FILE%" >nul 2>&1

if not "%GUARD_DIRTY_SIZE%"=="0" (
    set GUARD_PREV_STASH=none
    for /f "usebackq delims=" %%S in (`git stash list "--format=%%H" -1 2^>nul`) do set GUARD_PREV_STASH=%%S
    echo [GUARD] Working tree is dirty on "%PRE_BRANCH%" - stashing tracked+untracked changes before landing on main ^(nothing is discarded; recoverable via "git stash pop"^). >> "%LOG_FILE%"
    git stash push -u -m "schedule_daily.bat-auto-stash" >> "%LOG_FILE%" 2>&1
    set STASH_RC=!ERRORLEVEL!
    if not "!STASH_RC!"=="0" (
        set GUARD_NEW_STASH=none
        for /f "usebackq delims=" %%S in (`git stash list "--format=%%H" -1 2^>nul`) do set GUARD_NEW_STASH=%%S
        echo [ERROR] Checkout guard: git stash -u FAILED with exit code !STASH_RC! - refusing to run. Nothing was discarded; the dirty tree on "%PRE_BRANCH%" is untouched. >> "%LOG_FILE%"
        if not "!GUARD_NEW_STASH!"=="!GUARD_PREV_STASH!" (
            if not "!GUARD_NEW_STASH!"=="none" (
                echo [ERROR] Checkout guard: Partial stash: !GUARD_NEW_STASH! ^(stash@{0}^) was created before failure ^(previous=!GUARD_PREV_STASH!^) - left intact ^(not dropped or popped^). >> "%LOG_FILE%"
            )
        )
        exit /b 1
    )
)

git checkout main >> "%LOG_FILE%" 2>&1
set CHECKOUT_RC=%ERRORLEVEL%
if not "%CHECKOUT_RC%"=="0" (
    echo [ERROR] Checkout guard: git checkout main FAILED with exit code %CHECKOUT_RC% - refusing to run. >> "%LOG_FILE%"
    exit /b 1
)

set POST_BRANCH=
for /f "usebackq delims=" %%B in (`git rev-parse --abbrev-ref HEAD`) do set POST_BRANCH=%%B
if not "%POST_BRANCH%"=="main" (
    echo [ERROR] Checkout guard: assertion FAILED - HEAD=%POST_BRANCH% expected=main. Refusing to run. >> "%LOG_FILE%"
    exit /b 1
)

set GUARD_STATUS_FILE2=%TEMP%\nfl_sched_guard_status2_%RANDOM%.txt
git status --porcelain > "%GUARD_STATUS_FILE2%" 2>nul
set GUARD_DIRTY_SIZE2=0
for %%F in ("%GUARD_STATUS_FILE2%") do set GUARD_DIRTY_SIZE2=%%~zF
del /q "%GUARD_STATUS_FILE2%" >nul 2>&1
if not "%GUARD_DIRTY_SIZE2%"=="0" (
    echo [ERROR] Checkout guard: main is still dirty after stash+checkout - refusing to run. >> "%LOG_FILE%"
    exit /b 1
)

echo [GUARD] Checkout guard: landed cleanly on main (pre-guard branch was "%PRE_BRANCH%"). >> "%LOG_FILE%"

REM ------------------------------------------------------------------------------
REM Fast-forward main to origin/main (issue #148, ported from NBA_analytics #162).
REM Without this, merged changes never ran until someone pulled by hand.
REM tools\ff_main.bat logs main's SHA before and after; a failed fetch is a [WARN]
REM and the run continues on the local main; a main that cannot fast-forward
REM (diverged) is an [ERROR] and the pipeline does NOT run. It never resets and
REM never discards a commit.
REM
REM Self-update safety. cmd does not load a .bat into memory: after each command
REM it re-opens the file and reads on from a saved byte offset. If the
REM fast-forward rewrites THIS file, the old offset points into the new text and
REM cmd would run half-lines or skip steps, silently. So the call and ALL of its
REM result handling are one parenthesised block, which cmd parses whole before
REM running any of it. If schedule_daily.bat changed, the block starts the
REM updated script fresh with the same arguments (NFL_FF_DONE=1 tells it the
REM fast-forward is already done) and exits with its exit code; nothing after
REM the block is read from the rewritten file. tools\ff_main.bat protects itself
REM the same way.
REM ------------------------------------------------------------------------------
set FF_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_BEFORE=%%S
if defined NFL_FF_DONE (
    echo [FF] NFL_FF_DONE=%NFL_FF_DONE%: fast-forward already done by the instance that relaunched this one. Skipped. main=%FF_BEFORE% >> "%LOG_FILE%"
) else (
    call "%PROJECT_DIR%\tools\ff_main.bat" "%LOG_FILE%"
    if errorlevel 1 (
        echo [ERROR] schedule_daily.bat: main could not be fast-forwarded to origin/main. Pipeline NOT run. >> "%LOG_FILE%"
        exit /b 4
    ) else (
        set FF_AFTER=
        for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_AFTER=%%S
        git diff --quiet !FF_BEFORE! !FF_AFTER! -- schedule_daily.bat >nul 2>&1
        if errorlevel 1 (
            echo [FF] schedule_daily.bat changed in the fast-forward !FF_BEFORE! -^> !FF_AFTER!. Relaunched itself after a self-update, same arguments: %* >> "%LOG_FILE%"
            set NFL_FF_DONE=1
            cmd /c ""%~f0" %*"
            exit /b !ERRORLEVEL!
        )
    )
)
REM Each "exit /b" above is the LAST command of its block on purpose: under
REM "cmd /c", an "exit /b N" followed by more commands in the same block makes
REM the process exit code 0 instead of N.

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
REM    -> playoffs -> accuracy governance -> notify ops -> web export; see run_full_pipeline.R).
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

REM ------------------------------------------------------------------------------
REM Back up the append-only files (issue #152, ported from NBA_analytics #164).
REM cache/ and logs/ are gitignored and inside this checkout, so nothing else
REM protects the graded prediction log. tools\backup_accumulated_cache.ps1 COPIES
REM the files it names (never moves or links them) to a dated folder outside any
REM git checkout, by default %USERPROFILE%\front-office-backups\nfl\YYYY-MM-DD\
REM (override: NFL_BACKUP_ROOT), keeps the 30 newest daily folders, and logs one
REM [BACKUP] line. It runs whether or not the pipeline succeeded, and it always
REM exits 0: a failed copy is a [WARN] line and never changes this run's exit code.
REM ------------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -CacheDir "%PROJECT_DIR%\cache" -LogsDir "%PROJECT_DIR%\logs" >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM Exit code reflects the overall outcome so Task Scheduler's own "Last Run Result"
REM surfaces a failed run on top of the [ERROR] log lines -- while a healthy run
REM still exits 0, so Task Scheduler never flags a good run as failed.
if "%PIPELINE_FAILED%"=="1" (
    exit /b 1
) else (
    exit /b 0
)
