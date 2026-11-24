@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_daily.bat -- Windows Task Scheduler target for the NBA pipeline.
REM
REM ------------------------------------------------------------------------------
REM SCHEDULED START TIME -- must stay AFTER the upstream hoopR data publish.
REM
REM Every load_nba_*() call in this repo reads pre-built release assets from
REM sportsdataverse/hoopR-nba-data, rebuilt by a batch job, NOT in near-real-time
REM after each game. Measured from that repo's own Actions history on 2026-10-26:
REM two runs a day, ~11:17-11:56 UTC and ~12:08-12:19 UTC. A game that ends at
REM 22:00 ET therefore appears in hoopR the NEXT MORNING, and not before ~12:20 UTC.
REM
REM The task was registered at 08:00 local, which is 12:00 UTC during EDT -- about
REM twenty minutes BEFORE the later window closes. So on any day the second run
REM lands late, this pipeline silently consumed YESTERDAY's build: last night's
REM games simply missing, with nothing anywhere reporting a problem. The WNBA
REM sibling repo found and documented the identical defect against wehoop (see
REM "WNBA Analytics\schedule_daily.bat"'s own note); this is the same bug, and it
REM was still live here when the four-sport cadence review found it on 2026-10-26.
REM
REM TARGET: 09:00 local = 13:00 UTC (EDT) / 14:00 UTC (EST). That is slot A of the
REM three-slot cadence -- all four sports run the full pipeline and publish, and
REM the aggregator's sync-sports.yml subtree-pulls and deploys 30 minutes later at
REM 13:30 UTC. It clears ~12:20 UTC by 40 minutes in EDT and by 100 in EST. If this
REM is ever re-registered, keep it at or after 09:00 local; do not move it earlier.
REM   schtasks /change /tn "NBA Analytics Daily Pipeline" /st 09:00
REM
REM AGGREGATOR SYNC DISPATCH (2026-11-21). That 13:30 UTC cron has been
REM starting at 21:00-23:00 UTC, so slot A output reached the site only in the
REM late afternoon. After a publish that pushed a new commit (publish_web.R
REM exit 0 and HEAD moved), this script now runs
REM   gh workflow run "Sync sport subtrees and deploy" -f sports="mlb nfl nba wnba" -f deploy=true
REM so the run goes live within minutes. A failed dispatch is a [WARN] line
REM and never changes the exit code; see the block after the publish gate.
REM
REM NOT YET APPLIED as of 2026-10-26. This task is registered with RunLevel=Highest,
REM so changing its trigger needs an ELEVATED shell; a non-elevated
REM Set-ScheduledTask returns "Access is denied". The registered trigger is still
REM 08:00, so the race above is still live until the command is run.
REM ------------------------------------------------------------------------------
REM ==============================================================================
REM Project dir defaults to this script's own folder (%~dp0 minus its trailing
REM backslash); NBA_PROJECT_DIR still overrides it.
set PROJECT_DIR=%~dp0
if "%PROJECT_DIR:~-1%"=="\" set PROJECT_DIR=%PROJECT_DIR:~0,-1%
if defined NBA_PROJECT_DIR set PROJECT_DIR=%NBA_PROJECT_DIR%
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log
set LOG_MAX_BYTES=5242880

REM ------------------------------------------------------------------------------
REM Single-generation 5 MiB log rotation (.log -> .log.old), matching NFL and WNBA.
REM ------------------------------------------------------------------------------
if exist "%LOG_FILE%" (
    for %%F in ("%LOG_FILE%") do set LOG_SIZE=%%~zF
    if !LOG_SIZE! GTR %LOG_MAX_BYTES% (
        move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul
    )
)

REM ------------------------------------------------------------------------------
REM Seasonal guard (NFL_analytics#41): only run during the NBA season window
REM (October through June: months 10, 11, 12, 01, 02, 03, 04, 05, 06, covering
REM preseason/regular season through the NBA Finals). Outside this window (July
REM through September: 07, 08, 09), log and exit 0 without churning caches
REM against an inactive league. Set NBA_IGNORE_SEASON_GUARD=1 to override.
REM ------------------------------------------------------------------------------
for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Get-Date).ToString('MM')"`) do set CUR_MM=%%I

echo ================================================================== >> "%LOG_FILE%"
echo NBA PIPELINE AUTOMATED RUN: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

if defined NBA_IGNORE_SEASON_GUARD goto :inseason
if "%CUR_MM%"=="07" goto :offseason
if "%CUR_MM%"=="08" goto :offseason
if "%CUR_MM%"=="09" goto :offseason
goto :inseason

:offseason
echo [SKIPPED] Current month %CUR_MM% is outside the NBA season window (October-June). >> "%LOG_FILE%"
echo [SKIPPED] Pipeline NOT run - avoiding stale/off-season cache churn (set NBA_IGNORE_SEASON_GUARD=1 to override). >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason

if not defined HOME set HOME=%USERPROFILE%
cd /d "%PROJECT_DIR%"

REM ------------------------------------------------------------------
REM Checkout-safety guard (front-office issue #105). %PROJECT_DIR% is
REM the SAME working directory interactive sessions and agents use --
REM not a dedicated worktree. On 2026-11-10 that caused three same-day
REM collisions on the NFL sibling: a scheduled run executed
REM successfully on a stray feature branch a subagent had left checked
REM out; the 08:00 publish gate correctly refused
REM (assertion E: "HEAD=chore/nfl-week9-visual-media expected=main");
REM and a LATER agent then cleared the dirty tree with
REM `git checkout -- .` before merging -- with no stash first -- and
REM discarded 8 regenerated JSON files and a cache file. Published
REM data stayed ~30 hours stale until a manual re-run. The exposure is
REM identical here: run_full_pipeline.R and tools/publish_web.R both
REM write into %PROJECT_DIR%, so this guard runs BEFORE either, every
REM scheduled run, no exceptions.
REM
REM   1. If the tree is dirty (tracked OR untracked), `git stash -u`
REM      it under a labelled message. NOTHING is discarded.
REM   2. `git checkout main`.
REM   3. Verify HEAD really is main AND the tree is clean. If either
REM      check fails, STOP: do not run the pipeline against the wrong
REM      branch or a tree this guard could not land cleanly. A stash
REM      created in step 1 is left in `git stash list` for a human or
REM      agent to inspect and `git stash pop` -- this script never
REM      drops or clears a stash itself.
REM
REM This is the minimum-acceptable fix from issue #105 (stash + land
REM on main + fail loud), not the "dedicated worktree" best fix, which
REM needs a second checkout and a Task Scheduler env var this script
REM cannot provision or verify on its own.
REM ------------------------------------------------------------------
set GUARD_TMP=%PROJECT_DIR%\.checkout_guard.tmp
echo ------------------------------------------------------------------ >> "%LOG_FILE%"
echo NBA CHECKOUT-SAFETY GUARD: %DATE% %TIME% >> "%LOG_FILE%"

for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set PRE_BRANCH=%%B
echo [GUARD] Pre-guard branch: %PRE_BRANCH% >> "%LOG_FILE%"

git status --porcelain -u > "%GUARD_TMP%" 2>&1
set DIRTY=0
for %%A in ("%GUARD_TMP%") do if %%~zA GTR 0 set DIRTY=1

if "%DIRTY%"=="1" (
    set "GUARD_PREV_STASH=none"
    for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_PREV_STASH=%%s"
    echo [GUARD] Working tree is dirty on branch "%PRE_BRANCH%" - stashing ^(git stash -u^) before checkout. >> "%LOG_FILE%"
    git stash push -u -m "schedule_daily.bat auto-stash %DATE% %TIME%" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        set "GUARD_NEW_STASH=none"
        for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_NEW_STASH=%%s"
        echo [ERROR] schedule_daily.bat: "git stash -u" FAILED on branch "%PRE_BRANCH%". Newest stash is now !GUARD_NEW_STASH! ^(before this run: !GUARD_PREV_STASH!^). >> "%LOG_FILE%"
        REM A failed push can still have saved a stash (e.g. git saved it, then
        REM could not delete an untracked file or folder). Git skips its reset,
        REM so the tree keeps the changes AND a stash copy exists. Log the SHA;
        REM never drop, pop, or discard anything.
        if not "!GUARD_NEW_STASH!"=="!GUARD_PREV_STASH!" (
            echo [ERROR] Partial stash: "git stash push -u" exited non-zero but DID create stash !GUARD_NEW_STASH! ^(stash@{0}^). The working tree may still be dirty, so the same changes may exist both in the tree and in that stash. The stash was left in place for inspection. >> "%LOG_FILE%"
        )
        echo [ERROR] Refusing to touch this checkout further. Pipeline NOT run. >> "%LOG_FILE%"
        del "%GUARD_TMP%" >nul 2>&1
        exit /b 3
    )
)

git checkout main >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [ERROR] schedule_daily.bat: "git checkout main" FAILED ^(was on "%PRE_BRANCH%"^). >> "%LOG_FILE%"
    echo [ERROR] Pipeline NOT run. If a stash was just created above, it is still in >> "%LOG_FILE%"
    echo [ERROR] the stash list ^("git stash list"^) - nothing was discarded. >> "%LOG_FILE%"
    del "%GUARD_TMP%" >nul 2>&1
    exit /b 3
)

for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>^&1') do set POST_BRANCH=%%B
git status --porcelain -u > "%GUARD_TMP%" 2>&1
set POST_DIRTY=0
for %%A in ("%GUARD_TMP%") do if %%~zA GTR 0 set POST_DIRTY=1
del "%GUARD_TMP%" >nul 2>&1

if not "%POST_BRANCH%"=="main" (
    echo [ERROR] schedule_daily.bat: checkout-safety guard FAILED. >> "%LOG_FILE%"
    echo [ERROR] HEAD=%POST_BRANCH% expected=main after "git checkout main". Pipeline NOT run. >> "%LOG_FILE%"
    exit /b 3
)
if "%POST_DIRTY%"=="1" (
    echo [ERROR] schedule_daily.bat: checkout-safety guard FAILED. >> "%LOG_FILE%"
    echo [ERROR] Branch is main but the tree is still dirty after stash+checkout. Pipeline NOT run. >> "%LOG_FILE%"
    exit /b 3
)

echo [GUARD] OK - HEAD=main, tree clean. Proceeding with pipeline. >> "%LOG_FILE%"
echo ------------------------------------------------------------------ >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Fast-forward main to origin/main (issue #162). Without this, merged
REM changes never ran until someone pulled by hand. tools\ff_main.bat
REM logs main's SHA before and after; a failed fetch is a [WARN] and the
REM run continues on the local main; a main that cannot fast-forward
REM (diverged) is an [ERROR] and the pipeline does NOT run. It never
REM resets and never discards a commit.
REM
REM Self-update safety. cmd does not load a .bat into memory: after each
REM command it re-opens the file and reads on from a saved byte offset.
REM If the fast-forward rewrites THIS file, the old offset points into the
REM new text and cmd would run half-lines or skip steps, silently. So the
REM call and ALL of its result handling are one parenthesised block, which
REM cmd parses whole before running any of it. If schedule_daily.bat
REM changed, the block starts the updated script fresh with the same
REM arguments (NBA_FF_DONE=1 tells it the fast-forward is already done)
REM and exits with its exit code; nothing after the block is read from
REM the rewritten file. tools\ff_main.bat protects itself the same way.
REM ------------------------------------------------------------------
set FF_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_BEFORE=%%S
if defined NBA_FF_DONE (
    echo [FF] NBA_FF_DONE=%NBA_FF_DONE%: fast-forward already done by the instance that relaunched this one. Skipped. main=%FF_BEFORE% >> "%LOG_FILE%"
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
            set NBA_FF_DONE=1
            cmd /c ""%~f0" %*"
            exit /b !ERRORLEVEL!
        )
    )
)
REM Each "exit /b" above is the LAST command of its block on purpose: under
REM "cmd /c", an "exit /b N" followed by more commands in the same block makes
REM the process exit code 0 instead of N (seen in the sandbox for #162).
echo ------------------------------------------------------------------ >> "%LOG_FILE%"

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
    set RUN_PUBLISH=1
) else (
    echo PIPELINE RUN FAILED WITH EXIT CODE %PIPELINE_EXIT%: %DATE% %TIME% >> "%LOG_FILE%"
    REM #161: tell GitHub, because publish_web.R (and its #145 alert) will not run. Never changes PIPELINE_EXIT.
    %RSCRIPT% "tools\notify_pipeline_failure.R" %PIPELINE_EXIT% "%LOG_FILE%" >> "%LOG_FILE%" 2>&1
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Publish gate (2026-10-26). This REPLACES the inline
REM "git add / git commit / git push origin HEAD" subroutine that lived here.
REM
REM Why it was replaced the same day it was written: that subroutine pushed on
REM one condition only -- run_full_pipeline.R exited 0 -- and an exit code is
REM not evidence about the artifacts. run_stage() catches a stage failure and
REM the pipeline carries on, every engine in this repo falls back to a labelled
REM synthetic value rather than failing, and run_full_pipeline.R's own
REM provenance guard covers 3 of the 12 published payloads. A stale
REM cba_cap_sheet.json or matchups_slates.json therefore shipped without a word.
REM It also pushed `origin HEAD`, so run from a feature branch it would commit
REM the data there, push it, report success, and leave the site untouched --
REM sync-sports.yml pulls main.
REM
REM tools/publish_web.R makes all six of those checks (A mtime, B slate,
REM C real diff, D stage warnings, E publish branch, F embedded generated_at)
REM and commits and pushes ONLY when every fatal one passes. It is the single
REM publish mechanism for this repo now; nothing else here touches git.
REM
REM It is called at TOP LEVEL, not with `call :label` from inside the
REM parenthesised block above, and RUN_PUBLISH is what carries the decision out.
REM A block-local ERRORLEVEL/label dance is the delayed-expansion trap this
REM file's own sibling wrappers document, and the publish step is the last thing
REM that should be fragile.
REM
REM MODE (argument 1), mirroring NFL's schedule_publish.bat so the four sports
REM take the same words:
REM   (none) / dryrun   -> every assertion runs, NOTHING is published  [DEFAULT]
REM   publish           -> live: commit + push NBA_analytics main only
REM   strict            -> dry run, stage warnings fatal
REM   publish-strict    -> live publish, stage warnings fatal
REM
REM Dry run is the DEFAULT ON PURPOSE, and this is the same gate NFL is sitting
REM behind: the unattended push is UNPROVEN on this machine. Credentials work in
REM an interactive terminal (gh keyring plus credential.helper=manager), but
REM Task Scheduler's non-interactive session may not reach Git Credential
REM Manager, which would make a scheduled publish hang on an auth prompt or fail
REM obscurely at a time nobody is watching. That is NFL Analytics issue #42,
REM still open, and it applies verbatim here -- the git step this replaced was
REM written on 2026-10-26 and had never executed even once, so nothing about it
REM constitutes proof.
REM
REM   >>> Leave the registered task on `dryrun` until the unattended push is <<<
REM   >>> proven. Read the dry-run reports for a few days first.             <<<
REM ------------------------------------------------------------------
set MODE=%~1
if "%MODE%"=="" set MODE=publish

REM One `if` per assignment, never `if cond set A=x& set B=y`: in batch `&` ends
REM the conditional, so the second `set` would run even when the test is false.
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
    echo [ERROR] schedule_daily.bat: unknown publish mode "%MODE%". >> "%LOG_FILE%"
    echo [ERROR] Valid modes: dryrun ^(default^), strict, publish, publish-strict. >> "%LOG_FILE%"
    echo [ERROR] The pipeline already ran; only the publish step is being skipped. >> "%LOG_FILE%"
    exit /b 2
)

if not "%RUN_PUBLISH%"=="1" (
    echo [SKIPPED] Publish gate not run: the pipeline did not succeed. >> "%LOG_FILE%"
    REM #164: back up the append-only cache files even when the pipeline failed.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -CacheDir "%PROJECT_DIR%\cache" >> "%LOG_FILE%" 2>&1
    echo. >> "%LOG_FILE%"
    exit /b %PIPELINE_EXIT%
)

echo ================================================================== >> "%LOG_FILE%"
echo NBA WEB PUBLISH GATE: %DATE% %TIME% >> "%LOG_FILE%"
echo Mode: %MODE_LABEL%  (argument: %MODE%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

REM publish_web.R exits 0 only when nothing fatal failed, 1 on any fatal
REM failure, so a scheduled caller can branch on it. PUBLISH_RC is captured
REM OUTSIDE any parenthesised block before being tested.
REM PUB_HEAD_BEFORE/AFTER feed the aggregator sync dispatch below.
set PUB_HEAD_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_BEFORE=%%S
%RSCRIPT% "%PROJECT_DIR%\tools\publish_web.R" %PW_ARGS% >> "%LOG_FILE%" 2>&1
set PUBLISH_RC=%ERRORLEVEL%
set PUB_HEAD_AFTER=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_AFTER=%%S

echo ------------------------------------------------------------------ >> "%LOG_FILE%"
if not "%PUBLISH_RC%"=="0" (
    echo [ERROR] Publish gate FAILED with exit code %PUBLISH_RC% in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo [ERROR] Either a fatal assertion failed or the commit/push step failed - nothing was pushed to NBA_analytics. >> "%LOG_FILE%"
    echo [ERROR] If the push step failed, its publish commit was undone: the local branch is back in step with origin >> "%LOG_FILE%"
    echo [ERROR] and the regenerated files are still in the working tree. See the "publish_web: step failed" lines above. >> "%LOG_FILE%"
    echo [ERROR] Yesterday's correct site stays up rather than a half-updated one. >> "%LOG_FILE%"
    echo [ERROR] Read the "-- Assertions --" block above: every failing assertion >> "%LOG_FILE%"
    echo [ERROR] is on a "[FAIL]" line with its id, name, summary and the >> "%LOG_FILE%"
    echo [ERROR] offending file or value in its detail lines. >> "%LOG_FILE%"
    echo NBA WEB PUBLISH GATE BLOCKED: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo [OK] Publish gate passed in mode %MODE_LABEL%. >> "%LOG_FILE%"
    echo NBA WEB PUBLISH GATE COMPLETED: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Dispatch the aggregator sync right after a publish that pushed.
REM Pushing NBA_analytics deploys nothing; the site changes only when the
REM aggregator's sync-sports.yml runs, and its 13:30 UTC cron has been
REM starting 8-9 hours late. So this asks for a sync now:
REM   gh workflow run "Sync sport subtrees and deploy" -f sports="mlb nfl nba wnba" -f deploy=true
REM
REM New-commit signal: publish_web.R exited 0 AND HEAD moved. publish_web.R
REM commits and pushes only in a live mode with every fatal assertion
REM passed; a failed commit or push stops it with exit 1. A dry run, or a
REM gate that finds nothing to publish, leaves HEAD where it was. So
REM "exit 0 and HEAD changed" means a new commit reached origin/main.
REM
REM All four sports, not just nba: sync-sports.yml runs in concurrency
REM group sync-sports with cancel-in-progress false, and GitHub keeps only
REM ONE pending run per group, replacing an older pending run with the
REM newer one. If NBA asked for sports=nba and WNBA asked for sports=wnba
REM a minute later while a sync was running, NBA's request would be
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

REM ------------------------------------------------------------------
REM Back up the append-only cache files (issue #164). cache/ is gitignored
REM and inside this checkout, so nothing else protects the graded
REM prediction log. tools\backup_accumulated_cache.ps1 COPIES the files it
REM names (never moves or links them) to a dated folder outside any git
REM checkout, by default %USERPROFILE%\front-office-backups\nba\YYYY-MM-DD\
REM (override: NBA_BACKUP_ROOT), keeps the 30 newest daily folders, and logs
REM one [BACKUP] line. It always exits 0: a failed copy is a [WARN] line and
REM never changes this run's exit code.
REM ------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -CacheDir "%PROJECT_DIR%\cache" >> "%LOG_FILE%" 2>&1
echo. >> "%LOG_FILE%"

REM The pipeline's own exit code is what Task Scheduler's "Last Run Result"
REM should reflect: a blocked publish on good-but-unchanged data is not a
REM pipeline failure, and conflating the two would train whoever reads that
REM column to ignore it. The gate's own verdict is in the log above, and in
REM PUBLISH_RC for anyone chaining off this file.
exit /b %PIPELINE_EXIT%
