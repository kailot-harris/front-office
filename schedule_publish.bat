@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_publish.bat -- GitHub issue #39 scope item 3.
REM Windows Task Scheduler target for the publish-only task (09:00 daily),
REM separate from the 05:15 pipeline task (schedule_daily.bat).
REM
REM Why a second task instead of a 4th step in schedule_daily.bat: #39 scope item 3
REM recommends two tasks so (a) a long pipeline overrun cannot silently delay the
REM deploy, and (b) a publish can be re-run without re-running the whole pipeline.
REM
REM This wrapper is ONLY a caller. All freshness logic lives in tools/publish_web.R
REM (#38) and is deliberately not reimplemented here -- the gate asserts on
REM artifacts, not on the pipeline's exit code, because run_stage() swallows stage
REM failures and the pipeline can exit 0 with stale output.
REM
REM MODE (argument 1):
REM   (none) / dryrun   -> Rscript tools/publish_web.R                 [DEFAULT]
REM                        Runs every assertion, publishes NOTHING.
REM   publish           -> Rscript tools/publish_web.R --publish
REM                        Live publish: commit + push NFL_analytics main ONLY.
REM                        It does NOT deploy -- the aggregator's sync-sports.yml
REM                        subtree-pulls and dispatches deploy.yml (2026-10-26:
REM                        one deploy path, so nothing here races it).
REM   strict            -> dry run with --strict-warnings (exporter [WARN] lines
REM                        are treated as fatal).
REM   publish-strict    -> live publish with --strict-warnings.
REM
REM Dry run is the DEFAULT ON PURPOSE. Issue #42 (still OPEN) is that the unattended
REM push is unproven: credentials work in an interactive terminal (gh keyring plus
REM credential.helper=manager) but Task Scheduler's non-interactive session may not
REM reach Git Credential Manager, which would make a 09:00 publish hang on an auth
REM prompt or fail obscurely at a time nobody is watching. So the registered task
REM starts in dry-run mode and the FIRST REAL RUNS ARE DRY RUNS BY DESIGN.
REM
REM   >>> DO NOT switch the registered task to `publish` until #42 is proven. <<<
REM   See docs/SCHEDULING.md for the gate.
REM
REM AGGREGATOR SYNC DISPATCH (2026-11-21). The aggregator's sync-sports.yml cron
REM has been starting hours late, so a morning publish reached the site only in
REM the late afternoon. After a publish that pushed a new commit (publish_web.R
REM exit 0 and HEAD moved), this script now runs
REM   gh workflow run "Sync sport subtrees and deploy" -f sports="mlb nfl nba wnba" -f deploy=true
REM so the run goes live within minutes. Same block as NBA_analytics#221 and
REM WNBA_analytics#235. A failed dispatch is a [WARN] line and never changes the
REM exit code; see the block after the publish gate report.
REM ==============================================================================

REM ------------------------------------------------------------------------------
REM Same single justified duplication as schedule_daily.bat: PROJECT_DIR mirrors
REM config.R:22 because a .bat cannot source R and we must cd somewhere to start.
REM Nothing else is duplicated -- publish_web.R reads WEB_DATA_FILES, WEB_DATA_DIR,
REM CACHE_SCHEDULES and LOG_FILE from config.R / logging_utils.R itself.
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

REM Shares schedule_daily.bat's log file on purpose: the 05:15 run and the 09:00
REM publish are two halves of one daily story, and reading them interleaved in one
REM file is how an operator actually diagnoses "why is the site stale". Rotation is
REM owned by schedule_daily.bat (the earlier task), so this file never rotates and
REM cannot discard a log the pipeline run just wrote.
set LOG_DIR=%PROJECT_DIR%\logs
set LOG_FILE=%LOG_DIR%\pipeline_execution.log

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM ---- Mode selection ----------------------------------------------------------
REM Default with no argument is a dry run (no flags passed to publish_web.R, whose
REM own default is dry_run = TRUE -- see its CLI wrapper comment).
set MODE=%~1
if "%MODE%"=="" set MODE=dryrun

REM One `if` per assignment, never `if cond set A=x& set B=y`: in batch, `&` ends the
REM conditional, so the second `set` would run even when the condition is false.
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
    echo [ERROR] schedule_publish.bat: unknown mode "%MODE%". >> "%LOG_FILE%"
    echo [ERROR] Valid modes: dryrun ^(default^), strict, publish, publish-strict. >> "%LOG_FILE%"
    echo [ERROR] Refusing to run the publish gate with an unrecognised mode. >> "%LOG_FILE%"
    exit /b 2
)

REM Issue #53: cmd.exe (and Task Scheduler's non-interactive session, which also
REM launches through cmd.exe/.bat) does not set HOME the way Git Bash does, so git
REM calls made via R's system2() can't find ~/.gitconfig and refuse to commit with
REM "unable to auto-detect email address". tools/publish_web.R's .pw_git() now
REM passes identity explicitly via `git -c user.name=... -c user.email=...` for the
REM commit step regardless of HOME, but set HOME here too as defense-in-depth.
REM ------------------------------------------------------------------------------
REM Seasonal guard (NFL_analytics#41): mirror schedule_daily.bat's September-
REM February active window (months 09,10,11,12,01,02) so the 09:00 publish gate
REM does not fire false-alarm blocked alerts during the March-August off-season
REM when schedule_daily.bat deliberately skipped the 05:15 pipeline run. Set
REM NFL_IGNORE_SEASON_GUARD=1 in the environment to override.
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
echo NFL WEB PUBLISH GATE CHECK: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"
echo [SKIPPED] Current month %CUR_MM% is outside the NFL season window (September-February). >> "%LOG_FILE%"
echo [SKIPPED] Publish gate NOT run (set NFL_IGNORE_SEASON_GUARD=1 to override). >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason
if not defined HOME set HOME=%USERPROFILE%

cd /d "%PROJECT_DIR%"

REM ------------------------------------------------------------------------------
REM Checkout-safety guard (front-office issue #105). %PROJECT_DIR% is the SAME
REM working directory interactive sessions and subagents use -- the 2026-11-10
REM incident's 08:00 publish gate correctly refused on a dirty non-main HEAD, but
REM at 08:03 a different agent cleared the dirty tree with `git checkout -- .`
REM before merging, silently discarding 8 regenerated JSON files and a cache file.
REM This guard never discards: any dirty work (tracked AND untracked, via -u) is
REM `git stash -u`'d -- preserved, recoverable with `git stash pop`, never dropped
REM -- before the checkout lands on main. If it cannot land cleanly on main for ANY
REM reason (stash fails, checkout fails, HEAD isn't main afterward, or main is
REM still dirty afterward), the wrapper fails loudly with a clear [ERROR] log line
REM and a non-zero exit instead of silently running the publish gate against the
REM wrong branch or a half-clean tree. This guard is intentionally identical in
REM shape to schedule_daily.bat's -- see that file's comment for the full
REM rationale.
REM ------------------------------------------------------------------------------
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Checkout guard: "%CD%" is not a git work tree - refusing to run. >> "%LOG_FILE%"
    exit /b 1
)

set PRE_BRANCH=
for /f "usebackq delims=" %%B in (`git rev-parse --abbrev-ref HEAD`) do set PRE_BRANCH=%%B
echo [GUARD] Checkout guard: starting branch is "%PRE_BRANCH%". >> "%LOG_FILE%"

REM Resolve Rscript exactly as the sibling wrappers do (needed by the guard below).
REM WHERE_RC keeps %ERRORLEVEL% out of any parenthesized block (see
REM schedule_daily.bat's delayed-expansion note).
where Rscript >nul 2>&1
set WHERE_RC=%ERRORLEVEL%
if "%WHERE_RC%"=="0" (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

REM NFL_analytics#154: unlike schedule_daily.bat, the publish step's INPUT is the
REM uncommitted pipeline output (web/public/{data,animations}), so on `main` the
REM guard must NOT stash those paths. tools/publish_guard.R classifies dirty paths
REM using config.R's PIPELINE_OUTPUT_DIRS (the same vector publish_web.R uses) and
REM writes NUL-separated lists: OTHER (code/config/docs -> stashed as before) and
REM OUTPUT (kept for the gate). On any branch other than main nothing is trusted:
REM everything is stashed (old behaviour) and the checkout lands on main.
set "GUARD_TMPDIR=%TEMP%"
set "GUARD_OTHER=%GUARD_TMPDIR%\nfl_guard_other_%RANDOM%.bin"
set "GUARD_OUTPUT=%GUARD_TMPDIR%\nfl_guard_output_%RANDOM%.bin"
set GUARD_OTHER_SIZE=0

set GUARD_STATUS_FILE=%TEMP%\nfl_sched_guard_status_%RANDOM%.txt
git status --porcelain > "%GUARD_STATUS_FILE%" 2>nul
set GUARD_DIRTY_SIZE=0
for %%F in ("%GUARD_STATUS_FILE%") do set GUARD_DIRTY_SIZE=%%~zF
del /q "%GUARD_STATUS_FILE%" >nul 2>&1

if not "%GUARD_DIRTY_SIZE%"=="0" (
    if "%PRE_BRANCH%"=="main" (
        %RSCRIPT% "tools\publish_guard.R" "!GUARD_OTHER!" "!GUARD_OUTPUT!" >> "%LOG_FILE%" 2>&1
        set GUARD_RC=!ERRORLEVEL!
        if not "!GUARD_RC!"=="0" (
            echo [ERROR] Checkout guard: tools\publish_guard.R FAILED with exit code !GUARD_RC! - refusing to run. Nothing was stashed or discarded. >> "%LOG_FILE%"
            exit /b 1
        )
        for %%F in ("!GUARD_OTHER!") do set GUARD_OTHER_SIZE=%%~zF
        if not "!GUARD_OTHER_SIZE!"=="0" (
            set GUARD_PREV_STASH=none
            for /f "usebackq delims=" %%S in (`git stash list "--format=%%H" -1 2^>nul`) do set GUARD_PREV_STASH=%%S
            echo [GUARD] Non-output files are dirty on main - stashing only those ^(pipeline output under PIPELINE_OUTPUT_DIRS is kept for the gate^). >> "%LOG_FILE%"
            git stash push -u -m "schedule_publish.bat-auto-stash" --pathspec-from-file="!GUARD_OTHER!" --pathspec-file-nul >> "%LOG_FILE%" 2>&1
            set STASH_RC=!ERRORLEVEL!
            if not "!STASH_RC!"=="0" (
                set GUARD_NEW_STASH=none
                for /f "usebackq delims=" %%S in (`git stash list "--format=%%H" -1 2^>nul`) do set GUARD_NEW_STASH=%%S
                echo [ERROR] Checkout guard: git stash -u FAILED with exit code !STASH_RC! - refusing to run. Nothing was discarded. >> "%LOG_FILE%"
                if not "!GUARD_NEW_STASH!"=="!GUARD_PREV_STASH!" (
                    if not "!GUARD_NEW_STASH!"=="none" (
                        echo [ERROR] Checkout guard: Partial stash: !GUARD_NEW_STASH! ^(stash@{0}^) was created before failure ^(previous=!GUARD_PREV_STASH!^) - left intact ^(not dropped or popped^). >> "%LOG_FILE%"
                    )
                )
                exit /b 1
            )
        ) else (
            echo [GUARD] Only pipeline output is dirty on main - nothing to stash; leaving it for the gate. >> "%LOG_FILE%"
        )
    ) else (
        set GUARD_PREV_STASH=none
        for /f "usebackq delims=" %%S in (`git stash list "--format=%%H" -1 2^>nul`) do set GUARD_PREV_STASH=%%S
        echo [GUARD] Working tree is dirty on "%PRE_BRANCH%" - stashing tracked+untracked changes before landing on main ^(nothing is discarded; recoverable via "git stash pop"^). >> "%LOG_FILE%"
        git stash push -u -m "schedule_publish.bat-auto-stash" >> "%LOG_FILE%" 2>&1
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

REM Post-checkout verification. On main only non-output files must be clean (the
REM pipeline output is intentionally dirty); anywhere else the tree must be fully clean.
REM The temp lists are only ever deleted by exact file name, never a directory/wildcard.
if "%PRE_BRANCH%"=="main" (
    if exist "!GUARD_OTHER!" del /q "!GUARD_OTHER!" >nul 2>&1
    if exist "!GUARD_OUTPUT!" del /q "!GUARD_OUTPUT!" >nul 2>&1
    %RSCRIPT% "tools\publish_guard.R" "!GUARD_OTHER!" "!GUARD_OUTPUT!" >> "%LOG_FILE%" 2>&1
    set GUARD_RC2=!ERRORLEVEL!
    set GUARD_OTHER_SIZE2=0
    for %%F in ("!GUARD_OTHER!") do set GUARD_OTHER_SIZE2=%%~zF
    if exist "!GUARD_OTHER!" del /q "!GUARD_OTHER!" >nul 2>&1
    if exist "!GUARD_OUTPUT!" del /q "!GUARD_OUTPUT!" >nul 2>&1
    if not "!GUARD_RC2!"=="0" (
        echo [ERROR] Checkout guard: post-check classification FAILED with exit code !GUARD_RC2! - refusing to run. >> "%LOG_FILE%"
        exit /b 1
    )
    if not "!GUARD_OTHER_SIZE2!"=="0" (
        echo [ERROR] Checkout guard: non-output files are still dirty after stash - refusing to run. >> "%LOG_FILE%"
        exit /b 1
    )
) else (
    set GUARD_STATUS_FILE2=%TEMP%\nfl_sched_guard_status2_%RANDOM%.txt
    git status --porcelain > "!GUARD_STATUS_FILE2!" 2>nul
    set GUARD_DIRTY_SIZE2=0
    for %%F in ("!GUARD_STATUS_FILE2!") do set GUARD_DIRTY_SIZE2=%%~zF
    del /q "!GUARD_STATUS_FILE2!" >nul 2>&1
    if not "!GUARD_DIRTY_SIZE2!"=="0" (
        echo [ERROR] Checkout guard: main is still dirty after stash+checkout - refusing to run. >> "%LOG_FILE%"
        exit /b 1
    )
)

echo [GUARD] Checkout guard: landed cleanly on main (pre-guard branch was "%PRE_BRANCH%"). >> "%LOG_FILE%"

REM ------------------------------------------------------------------------------
REM Fast-forward main to origin/main (issue #148), exactly as schedule_daily.bat
REM does; see that file's comment for the self-update reasoning. A failed fetch
REM is a [WARN] and the gate runs on the local main; a main that cannot
REM fast-forward is an [ERROR] and the gate does NOT run. On main the guard above
REM deliberately keeps the uncommitted pipeline output (#154); git refuses the
REM fast-forward only if an incoming commit also changes one of those files, and
REM then this fails loudly instead of touching them. It never resets and never
REM discards a commit or a file. If schedule_publish.bat itself changed, the
REM updated script is relaunched once with the same arguments and NFL_FF_DONE=1.
REM ------------------------------------------------------------------------------
set FF_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_BEFORE=%%S
if defined NFL_FF_DONE (
    echo [FF] NFL_FF_DONE=%NFL_FF_DONE%: fast-forward already done by the instance that relaunched this one. Skipped. main=%FF_BEFORE% >> "%LOG_FILE%"
) else (
    call "%PROJECT_DIR%\tools\ff_main.bat" "%LOG_FILE%"
    if errorlevel 1 (
        echo [ERROR] schedule_publish.bat: main could not be fast-forwarded to origin/main. Publish gate NOT run. >> "%LOG_FILE%"
        exit /b 4
    ) else (
        set FF_AFTER=
        for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_AFTER=%%S
        git diff --quiet !FF_BEFORE! !FF_AFTER! -- schedule_publish.bat >nul 2>&1
        if errorlevel 1 (
            echo [FF] schedule_publish.bat changed in the fast-forward !FF_BEFORE! -^> !FF_AFTER!. Relaunched itself after a self-update, same arguments: %* >> "%LOG_FILE%"
            set NFL_FF_DONE=1
            cmd /c ""%~f0" %*"
            exit /b !ERRORLEVEL!
        )
    )
)
REM Each "exit /b" above is the LAST command of its block on purpose: under
REM "cmd /c", an "exit /b N" followed by more commands in the same block makes
REM the process exit code 0 instead of N.

echo ================================================================== >> "%LOG_FILE%"
echo NFL WEB PUBLISH GATE: %DATE% %TIME% >> "%LOG_FILE%"
echo Mode: %MODE_LABEL%  (argument: %MODE%) >> "%LOG_FILE%"
echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"
echo Working directory: %CD% >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

REM ---- Run the gate ------------------------------------------------------------
REM publish_web.R exits 0 only when nothing fatal failed, 1 on any fatal failure,
REM "so a scheduled caller can branch on it". This is that caller. PUBLISH_RC is
REM captured OUTSIDE any parenthesized block before being tested.
REM PUB_HEAD_BEFORE/AFTER feed the aggregator sync dispatch below.
set PUB_HEAD_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_BEFORE=%%S
%RSCRIPT% "tools\publish_web.R" %PW_ARGS% >> "%LOG_FILE%" 2>&1
set PUBLISH_RC=%ERRORLEVEL%
set PUB_HEAD_AFTER=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_AFTER=%%S

echo ------------------------------------------------------------------ >> "%LOG_FILE%"
if not "%PUBLISH_RC%"=="0" (
    echo [ERROR] Publish gate FAILED with exit code %PUBLISH_RC% in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo [ERROR] Nothing new reached origin: either a fatal assertion failed, or the commit/push step failed. >> "%LOG_FILE%"
    echo [ERROR] If the push step failed, its publish commit was rolled back - the checkout is back in step >> "%LOG_FILE%"
    echo [ERROR] with origin and the regenerated files are still in the working tree for the next run. >> "%LOG_FILE%"
    echo [ERROR] Yesterday's correct site stays up rather than a half-updated one. >> "%LOG_FILE%"
    REM Avoid ^-escaped angle brackets here: inside a parenthesized block cmd leaves
    REM the carets in the output, so the hint is written in plain words instead.
    echo [ERROR] For a push failure, read the "publish_web:" lines above. Otherwise read the >> "%LOG_FILE%"
    echo [ERROR] "-- Assertions --" block above this line: every failing >> "%LOG_FILE%"
    echo [ERROR] assertion is listed on a "[FAIL]" line with its id, name and a >> "%LOG_FILE%"
    echo [ERROR] summary, and the offending file or value in its detail lines. >> "%LOG_FILE%"
    echo NFL WEB PUBLISH GATE BLOCKED: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo [OK] Publish gate passed in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo NFL WEB PUBLISH GATE COMPLETED: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Dispatch the aggregator sync right after a publish that pushed.
REM Pushing NFL_analytics deploys nothing; the site changes only when the
REM aggregator's sync-sports.yml runs, and its cron has been starting
REM hours late. So this asks for a sync now:
REM   gh workflow run "Sync sport subtrees and deploy" -f sports="mlb nfl nba wnba" -f deploy=true
REM
REM New-commit signal: publish_web.R exited 0 AND HEAD moved. publish_web.R
REM commits and pushes only in a live mode with every fatal assertion
REM passed; a failed commit or push stops it with exit 1. A dry run, or a
REM blocked gate, leaves HEAD where it was. So "exit 0 and HEAD changed"
REM means a new commit reached origin/main.
REM
REM All four sports, not just nfl: sync-sports.yml runs in concurrency
REM group sync-sports with cancel-in-progress false, and GitHub keeps only
REM ONE pending run per group, replacing an older pending run with the
REM newer one. If NFL asked for sports=nfl and NBA asked for sports=nba
REM a minute later while a sync was running, NFL's request would be
REM dropped. A sync that always pulls all four makes any surviving run
REM correct.
REM
REM A failed dispatch (gh missing, not signed in, network) is a [WARN]
REM line and never changes this script's exit code: the publish already
REM succeeded and the cron is the backstop. gh is found on PATH or under
REM %ProgramFiles%\GitHub CLI, and run with `call` so a gh.cmd/gh.bat
REM shim returns here instead of ending this script.
REM ------------------------------------------------------------------
set SYNC_DISPATCH=0
if "%PUBLISH_RC%"=="0" if defined PUB_HEAD_BEFORE if defined PUB_HEAD_AFTER if not "%PUB_HEAD_AFTER%"=="%PUB_HEAD_BEFORE%" set SYNC_DISPATCH=1
if not "%SYNC_DISPATCH%"=="1" echo [INFO] Aggregator sync not dispatched: no new commit was pushed ^(publish exit %PUBLISH_RC%, mode %MODE_LABEL%, HEAD %PUB_HEAD_BEFORE% -^> %PUB_HEAD_AFTER%^). >> "%LOG_FILE%"
set GH_BIN=
if "%SYNC_DISPATCH%"=="1" where gh >nul 2>&1
if "%SYNC_DISPATCH%"=="1" if not errorlevel 1 set "GH_BIN=gh"
if "%SYNC_DISPATCH%"=="1" if not defined GH_BIN if exist "%ProgramFiles%\GitHub CLI\gh.exe" set "GH_BIN=%ProgramFiles%\GitHub CLI\gh.exe"
if "%SYNC_DISPATCH%"=="1" if not defined GH_BIN echo [WARN] Aggregator sync NOT dispatched: GitHub CLI ^(gh^) not found on PATH or in "%ProgramFiles%\GitHub CLI". The sync-sports.yml cron will pick this publish up later. >> "%LOG_FILE%"
if "%SYNC_DISPATCH%"=="1" if defined GH_BIN (
    echo [INFO] Dispatching aggregator sync: HEAD %PUB_HEAD_BEFORE% -^> %PUB_HEAD_AFTER%, sports="mlb nfl nba wnba". >> "%LOG_FILE%"
    call "!GH_BIN!" workflow run "Sync sport subtrees and deploy" --repo kailot-harris/front-office -f sports="mlb nfl nba wnba" -f deploy=true >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo [WARN] Aggregator sync dispatch FAILED with exit code !ERRORLEVEL!. Publish is unaffected; the sync-sports.yml cron will pick it up later. >> "%LOG_FILE%"
    ) else (
        echo [INFO] Aggregator sync dispatched. >> "%LOG_FILE%"
    )
)
echo. >> "%LOG_FILE%"

REM The only step chained after the publish is the sync dispatch above, and it
REM runs only after a successful publish that pushed; it never changes the exit
REM code. On failure we only log and propagate the code, so Task Scheduler's
REM "Last Run Result" shows the failure too. This exit /b stays the last line.
exit /b %PUBLISH_RC%
