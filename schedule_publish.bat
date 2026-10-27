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
REM ==============================================================================

REM ------------------------------------------------------------------------------
REM Same single justified duplication as schedule_daily.bat: PROJECT_DIR mirrors
REM config.R:22 because a .bat cannot source R and we must cd somewhere to start.
REM Nothing else is duplicated -- publish_web.R reads WEB_DATA_FILES, WEB_DATA_DIR,
REM CACHE_SCHEDULES and LOG_FILE from config.R / logging_utils.R itself.
REM ------------------------------------------------------------------------------
set PROJECT_DIR=c:\Users\kailo\kayceeslices\front-office\nfl analytics

REM Testing/worktree escape hatch: if NFL_PROJECT_DIR is set in the environment, it
REM wins. This lets the wrapper be exercised from a git worktree (or a relocated
REM checkout) without editing the file and without writing logs into the main
REM checkout. The registered scheduled tasks do NOT set it, so production always
REM uses the path above. No secret is involved -- it is a directory path only.
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
if not defined HOME set HOME=%USERPROFILE%

cd /d "%PROJECT_DIR%"

REM Resolve Rscript exactly as the sibling wrappers do. WHERE_RC keeps %ERRORLEVEL%
REM out of any parenthesized block (see schedule_daily.bat's delayed-expansion note).
where Rscript >nul 2>&1
set WHERE_RC=%ERRORLEVEL%
if "%WHERE_RC%"=="0" (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

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
%RSCRIPT% "tools\publish_web.R" %PW_ARGS% >> "%LOG_FILE%" 2>&1
set PUBLISH_RC=%ERRORLEVEL%

echo ------------------------------------------------------------------ >> "%LOG_FILE%"
if not "%PUBLISH_RC%"=="0" (
    echo [ERROR] Publish gate FAILED with exit code %PUBLISH_RC% in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo [ERROR] At least one fatal assertion failed - NOTHING WAS PUBLISHED. >> "%LOG_FILE%"
    echo [ERROR] Yesterday's correct site stays up rather than a half-updated one. >> "%LOG_FILE%"
    REM Avoid ^-escaped angle brackets here: inside a parenthesized block cmd leaves
    REM the carets in the output, so the hint is written in plain words instead.
    echo [ERROR] Read the "-- Assertions --" block above this line: every failing >> "%LOG_FILE%"
    echo [ERROR] assertion is listed on a "[FAIL]" line with its id, name and a >> "%LOG_FILE%"
    echo [ERROR] summary, and the offending file or value in its detail lines. >> "%LOG_FILE%"
    echo NFL WEB PUBLISH GATE BLOCKED: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo [OK] Publish gate passed in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo NFL WEB PUBLISH GATE COMPLETED: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM No success-dependent step runs after a non-zero exit: there is deliberately no
REM post-publish action chained here at all. On failure we only log and propagate
REM the code, so Task Scheduler's "Last Run Result" shows the failure too.
exit /b %PUBLISH_RC%
