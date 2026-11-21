@echo off
setlocal EnableDelayedExpansion
REM ==============================================================================
REM schedule_daily.bat (WNBA port)
REM Windows Task Scheduler target for the WNBA Analytics pipeline.
REM Path: schedule_daily.bat
REM
REM Ported from NBA Analytics\schedule_daily.bat's 3-step structure. Per
REM WNBA_REPLICATION_PLAN.md section (e) risk #1, the WNBA off-season is much longer than the
REM NBA's (~6-7 months with zero live signal vs the NBA's ~3-month gap): the 2026 WNBA regular
REM season runs 2026-05-08 to 2026-09-24, with the playoffs tipping off 2026-09-27 (verified via
REM web search 2026-09-12: wnba.com "2026 Regular Season Key Dates" / "2026 Schedule Release").
REM Running the full pipeline daily during the ~7 dead months (Nov-Apr) would just churn stale
REM cache files against a league that isn't playing, burn ESPN/Odds-API rate-limit budget for
REM nothing, and risk the exact "silently serving stale data as if live" failure mode the plan
REM explicitly calls out. Unlike a bare comment-only warning, this file adds a REAL date-check
REM guard below that skips the pipeline run (and logs why) outside the season window, rather
REM than relying on whoever configures Task Scheduler to remember to disable/re-enable the task
REM by hand every year.
REM
REM ------------------------------------------------------------------------------
REM SCHEDULED START TIME -- must stay AFTER the upstream wehoop data publish.
REM Every load_wnba_*() call in this repo reads pre-built release assets from
REM github.com/sportsdataverse/sportsdataverse-data (tags espn_wnba_team_boxscores,
REM espn_wnba_player_boxscores, espn_wnba_schedules, espn_wnba_pbp). Those assets are
REM rebuilt by a ONCE-DAILY BATCH JOB, not in near-real-time after each game:
REM sportsdataverse/wehoop-wnba-data's "Update WNBA Data" workflow (daily_wnba.yml)
REM is triggered by a repository_dispatch pinned at ~10:36 UTC every day, with a second
REM scheduled backstop run landing ~09:20-12:40 UTC. Verified 2026-10-25 over 130 runs
REM spanning 2026-06-18..2026-10-25: exactly two runs/day, never an overnight refresh.
REM Release assets finish uploading ~10:39-11:20 UTC (worst observed run 45 min).
REM => A game that ends at 22:00 ET appears in wehoop the NEXT MORNING, ~06:40-07:20 ET.
REM
REM The task was originally registered at 05:30 local (= 09:30 UTC during EDT), i.e. about
REM an hour BEFORE the publish, so every in-season run silently consumed the PREVIOUS day's
REM build -- last night's finals games were missing until the following day. It was moved to
REM 08:00 local on 2026-10-25.
REM
REM 08:00 WAS STILL TOO EARLY, and the 2026-10-26 four-sport cadence review is what caught
REM it. 08:00 local is 12:00 UTC during EDT, and the publish-completion window measured
REM above ends at ~12:07 UTC in the ordinary case -- so 08:00 cleared the TRIGGER (~10:36
REM UTC) but raced the UPLOAD it actually depends on, by about seven minutes. The sibling
REM NBA repo had the identical defect against hoopR, whose equivalent window ends ~12:19
REM UTC; taking the later of the two as the binding constraint puts the floor at ~12:20 UTC
REM for both sports.
REM
REM TARGET: 09:00 local = 13:00 UTC (EDT) / 14:00 UTC (EST). That is slot A of the
REM three-slot cadence -- all four sports run the full pipeline and publish, and the
REM aggregator's sync-sports.yml subtree-pulls and deploys 30 minutes later at 13:30 UTC.
REM It clears ~12:20 UTC by 40 minutes in EDT and by 100 in EST. If this is ever
REM re-registered, keep it at or after 09:00 local; do not move it earlier.
REM   schtasks /change /tn "WNBA Analytics Schedule Daily" /st 09:00   (needs elevation)
REM
REM NOT YET APPLIED as of 2026-10-26: the change above requires an elevated shell and the
REM registered trigger is still 08:00. Until it is run, every in-season WNBA run has a
REM ~7-minute chance of consuming the previous day's wehoop build.
REM
REM AGGREGATOR SYNC DISPATCH (2026-11-21). That 13:30 UTC cron has been starting at
REM 21:00-23:00 UTC, so slot A output reached the site only in the late afternoon. After a
REM publish that pushed a new commit (publish_web.R exit 0 and HEAD moved), this script
REM now runs
REM   gh workflow run "Sync sport subtrees and deploy" -f sports="mlb nfl nba wnba" -f deploy=true
REM so the run goes live within minutes. A failed dispatch is a [WARN] line and never
REM changes the exit code; see the block after the publish gate (step 4).
REM ------------------------------------------------------------------------------
REM
REM IMPORTANT: the season window below (05-01 through 10-31, a small buffer around the exact
REM 05-08/09-27 dates above to comfortably cover variable year-to-year start dates and a
REM full postseason) is a MANUAL constant in this .bat file, not read from config.R (batch
REM script date arithmetic cannot easily source an R constant). Re-verify/update the two
REM MM values below at the start of each new WNBA season if the league's actual calendar
REM shifts meaningfully outside this window.
REM ==============================================================================

REM Issue #90: derived from this script's own location (%~dp0) instead of a hardcoded
REM absolute path. The old literal pointed at the repo's pre-move location, which still
REM exists as a logs-only stub, so Task Scheduler kept running the pipeline against a
REM directory holding none of the stage scripts -- 26 of 30 stages silently skipped while
REM the run still reported success. %~dp0 always resolves to the folder holding this file.
set PROJECT_DIR=%~dp0
if "%PROJECT_DIR:~-1%"=="\" set PROJECT_DIR=%PROJECT_DIR:~0,-1%
set LOG_FILE=%PROJECT_DIR%\pipeline_execution.log
set LOG_MAX_BYTES=5242880

REM ------------------------------------------------------------------------------
REM Log rotation (docs/future-work.md item 8): pipeline_execution.log is append-only
REM and was growing unbounded (one git commit alone added 3,755 lines before it was
REM untracked from version control -- see .gitignore's 2026-09-19 update). Untracking
REM it from git only fixes the repo-bloat half of the problem; this keeps the live file
REM on disk bounded too. Single-generation rotation (.log -> .log.old, overwriting any
REM previous .old) rather than a numbered series -- this is an operational log for
REM manual troubleshooting, not an audit trail that needs long retention.
REM ------------------------------------------------------------------------------
if exist "%LOG_FILE%" (
    for %%F in ("%LOG_FILE%") do set LOG_SIZE=%%~zF
    if !LOG_SIZE! GTR %LOG_MAX_BYTES% (
        move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul
    )
)

REM ------------------------------------------------------------------------------
REM Seasonal guard: only run during the WNBA season window (~May through end of October,
REM covering regular season 2026-05-08 to 2026-09-24 plus playoffs starting 2026-09-27 with a
REM buffer for a Finals that could run into late October). Outside this window, log and exit
REM without touching any cache files.
REM ------------------------------------------------------------------------------
REM wmic is removed on newer Windows builds (e.g. Windows 11 24H2+); use PowerShell's
REM Get-Date instead, which is present on every supported Windows version here.
for /f "usebackq" %%I in (`powershell -NoProfile -Command "(Get-Date).ToString('MM')"`) do set CUR_MM=%%I

echo ================================================================== >> "%LOG_FILE%"
echo WNBA PIPELINE AUTOMATED RUN CHECK: %DATE% %TIME% (month=%CUR_MM%) >> "%LOG_FILE%"
echo ================================================================== >> "%LOG_FILE%"

REM Season-active months: 05 (May) through 10 (October). Anything else (11,12,01,02,03,04) is
REM off-season -> skip. String comparison works here because CUR_MM is always zero-padded 2 digits.
if "%CUR_MM%"=="01" goto :offseason
if "%CUR_MM%"=="02" goto :offseason
if "%CUR_MM%"=="03" goto :offseason
if "%CUR_MM%"=="04" goto :offseason
if "%CUR_MM%"=="11" goto :offseason
if "%CUR_MM%"=="12" goto :offseason
goto :inseason

:offseason
echo [SKIPPED] Current month %CUR_MM% is outside the WNBA season window (May-October). >> "%LOG_FILE%"
echo [SKIPPED] Pipeline NOT run - avoiding stale/dead-season data churn per WNBA_REPLICATION_PLAN.md (e) risk #1. >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"
exit /b 0

:inseason
if not defined HOME set HOME=%USERPROFILE%
cd /d "%PROJECT_DIR%"

REM ------------------------------------------------------------------------------
REM Issue #105 checkout-safety guard. This directory is the SAME checkout that
REM interactive sessions and agents use for feature work -- it can be sitting on
REM a feature branch with uncommitted edits when Task Scheduler fires this job.
REM The 2026-11-10 front-office incident (issue #105) is what this prevents: a
REM scheduled run landed on a feature branch left dirty by a subagent, the
REM publish gate correctly refused, and a LATER agent "fixed" the dirty tree
REM with `git checkout -- .`, silently discarding 8 regenerated JSON files and a
REM cache file. See CLAUDE.md's "Shared-checkout safety (issue #105)" section.
REM
REM Rule enforced here: stash (never discard) whatever is sitting in the
REM checkout, land on main, and verify we are actually there and clean before
REM running a single pipeline stage. Any failure at any step aborts with a
REM non-zero exit code and a clear [ERROR] log line -- nothing downstream runs,
REM and nothing is ever cleared with a bare `checkout -- .`.
REM ------------------------------------------------------------------------------
git rev-parse --is-inside-work-tree >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo [ERROR] Checkout-safety guard: "%PROJECT_DIR%" is not a usable git work tree ^(git not found or not a repo^). Aborting - nothing was run. >> "%LOG_FILE%"
    exit /b 1
)

REM Capture the top stash SHA before running `git stash push -u` so a failed
REM stash push can tell whether git created a partial stash before failing
REM (e.g. saved the stash, then failed to clean an untracked folder and skipped
REM its reset, leaving the same changes both in the working tree and in stash).
REM Nothing here ever drops, pops, or discards a stash.
set "GUARD_PREV_STASH=none"
for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_PREV_STASH=%%s"

echo [INFO] Checkout-safety guard: stashing any uncommitted work ^(tracked + untracked^) before touching branches... >> "%LOG_FILE%"
git stash push -u -m "schedule_daily.bat auto-stash %DATE% %TIME%" >> "%LOG_FILE%" 2>&1
set "STASH_RC=!ERRORLEVEL!"
echo [INFO] Checkout-safety guard: git stash push -u exit code !STASH_RC! ^(0 = stashed or nothing to stash, both fine^). >> "%LOG_FILE%"
if not "!STASH_RC!"=="0" (
    set "GUARD_NEW_STASH=none"
    for /f "delims=" %%s in ('git stash list --format^=%%H -1 2^>nul') do set "GUARD_NEW_STASH=%%s"
    echo [ERROR] Checkout-safety guard: "git stash push -u" FAILED with exit code !STASH_RC!. Aborting before touching main - nothing was run, nothing was discarded. Newest stash is now !GUARD_NEW_STASH! ^(before this run: !GUARD_PREV_STASH!; if they differ, a stash was created before the failure^). >> "%LOG_FILE%"
    if not "!GUARD_NEW_STASH!"=="!GUARD_PREV_STASH!" (
        echo [ERROR] Checkout-safety guard: Partial stash: "git stash push -u" exited !STASH_RC! but DID create stash !GUARD_NEW_STASH! ^(stash@{0}^). The working tree may still be dirty ^(git skips its reset after such a failure^), so the same changes may exist both in the tree and in that stash. The stash was left in place for the owner to inspect. Refusing to run. >> "%LOG_FILE%"
    )
    exit /b 1
)

git checkout main >> "%LOG_FILE%" 2>&1
set CHECKOUT_RC=%ERRORLEVEL%
if not "%CHECKOUT_RC%"=="0" (
    echo [ERROR] Checkout-safety guard: "git checkout main" FAILED with exit code %CHECKOUT_RC%. Aborting - nothing was run, nothing was discarded; any stashed work is still in `git stash list`. >> "%LOG_FILE%"
    exit /b 1
)

set CUR_BRANCH=
for /f "usebackq delims=" %%B in (`git rev-parse --abbrev-ref HEAD`) do set CUR_BRANCH=%%B
if not "%CUR_BRANCH%"=="main" (
    echo [ERROR] Checkout-safety guard assertion FAILED: HEAD=%CUR_BRANCH% expected=main. Aborting - nothing was run. >> "%LOG_FILE%"
    exit /b 1
)

git diff --quiet
if not "%ERRORLEVEL%"=="0" (
    echo [ERROR] Checkout-safety guard assertion FAILED: main has uncommitted tracked changes after checkout - refusing to run the pipeline against an unclean main. Aborting - nothing was run. >> "%LOG_FILE%"
    exit /b 1
)

git diff --cached --quiet
if not "%ERRORLEVEL%"=="0" (
    echo [ERROR] Checkout-safety guard assertion FAILED: main has staged uncommitted changes after checkout. Aborting - nothing was run. >> "%LOG_FILE%"
    exit /b 1
)

echo [OK] Checkout-safety guard: landed cleanly on main ^(HEAD=%CUR_BRANCH%^). Proceeding with the pipeline. >> "%LOG_FILE%"

REM ------------------------------------------------------------------------------
REM Fast-forward main to origin/main (issue #198; ported from NBA_analytics #162).
REM Without this, merged changes never ran until someone pulled by hand.
REM tools\ff_main.bat logs main's SHA before and after; a failed fetch is a
REM [WARN] and the run continues on the local main; a main that cannot
REM fast-forward (diverged) is an [ERROR] and the pipeline does NOT run. It
REM never resets and never discards a commit.
REM
REM Self-update safety. cmd does not load a .bat into memory: after each
REM command it re-opens the file and reads on from a saved byte offset.
REM If the fast-forward rewrites THIS file, the old offset points into the
REM new text and cmd would run half-lines or skip steps, silently. So the
REM call and ALL of its result handling are one parenthesised block, which
REM cmd parses whole before running any of it. If schedule_daily.bat
REM changed, the block starts the updated script fresh with the same
REM arguments (WNBA_FF_DONE=1 tells it the fast-forward is already done)
REM and exits with its exit code; nothing after the block is read from
REM the rewritten file. tools\ff_main.bat protects itself the same way.
REM ------------------------------------------------------------------------------
set FF_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set FF_BEFORE=%%S
if defined WNBA_FF_DONE (
    echo [FF] WNBA_FF_DONE=%WNBA_FF_DONE%: fast-forward already done by the instance that relaunched this one. Skipped. main=%FF_BEFORE% >> "%LOG_FILE%"
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
            set WNBA_FF_DONE=1
            cmd /c ""%~f0" %*"
            exit /b !ERRORLEVEL!
        )
    )
)
REM Each "exit /b" above is the LAST command of its block on purpose: under
REM "cmd /c", an "exit /b N" followed by more commands in the same block makes
REM the process exit code 0 instead of N (seen in the NBA sandbox for #162).

where Rscript >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set RSCRIPT=Rscript
) else (
    for /d %%i in ("C:\Program Files\R\R-*") do set RSCRIPT="%%i\bin\x64\Rscript.exe"
)

echo Using Rscript: %RSCRIPT% >> "%LOG_FILE%"

REM ------------------------------------------------------------------------------
REM Failure visibility: the .bat used to run all three steps unconditionally and always
REM print "COMPLETED SUCCESSFULLY" at the end, regardless of whether any step actually
REM failed (incident: 2026-10-01 renv breakage made steps 2/3 both hard-fail with
REM "Execution halted", but the log still claimed success). PIPELINE_FAILED tracks whether
REM any step failed so the final banner reflects reality; each step's own %ERRORLEVEL% is
REM captured into a dedicated STEPn_RC variable *outside* any parenthesized block (so plain
REM %...% expansion is safe/current per EnableDelayedExpansion gotcha, see CLAUDE.md) before
REM being checked. Steps keep running unconditionally after a failure - this only adds
REM visibility, it does not abort the pipeline.
REM ------------------------------------------------------------------------------
set PIPELINE_FAILED=0

REM 1. Run the full 13-stage pipeline (rosters/injuries -> fatigue/shot-quality -> standings ->
REM    market odds -> props -> playoffs -> risk -> notify -> bet grading; see run_full_pipeline.R)
echo [Step 1/3] Running Full WNBA Pipeline... >> "%LOG_FILE%"
%RSCRIPT% "run_full_pipeline.R" >> "%LOG_FILE%" 2>&1
set STEP1_RC=%ERRORLEVEL%
if not "%STEP1_RC%"=="0" (
    set PIPELINE_FAILED=1
    echo [ERROR] Step 1/3 - run_full_pipeline.R - FAILED with exit code %STEP1_RC% >> "%LOG_FILE%"
)

REM 2. Grade yesterday's bets and compute rolling accuracy (also called inside
REM    run_full_pipeline.R itself - same known overlap/non-dedup as the NBA original, per
REM    REPO_MAP.md section 3.1's note; not fixed here since agent6.md doesn't ask for that cleanup)
echo [Step 2/3] Grading Yesterday's WNBA Bets ^& Rolling ROI... >> "%LOG_FILE%"
%RSCRIPT% "bet_tracker.r" >> "%LOG_FILE%" 2>&1
set STEP2_RC=%ERRORLEVEL%
if not "%STEP2_RC%"=="0" (
    set PIPELINE_FAILED=1
    echo [ERROR] Step 2/3 - bet_tracker.r - FAILED with exit code %STEP2_RC% >> "%LOG_FILE%"
)

REM 3. Generate today's new +EV picks
echo [Step 3/3] Updating Today's WNBA Betting Slate (+EV Engine)... >> "%LOG_FILE%"
%RSCRIPT% "market_odds_engine.R" >> "%LOG_FILE%" 2>&1
set STEP3_RC=%ERRORLEVEL%
if not "%STEP3_RC%"=="0" (
    set PIPELINE_FAILED=1
    echo [ERROR] Step 3/3 - market_odds_engine.R - FAILED with exit code %STEP3_RC% >> "%LOG_FILE%"
)

REM ------------------------------------------------------------------------------
REM 4. Publish gate (2026-10-26). Commits and pushes web/public/{data,media} to
REM    WNBA_analytics -- but only when tools/publish_web.R's six assertions all
REM    pass.
REM
REM    WHY THIS STEP DID NOT EXIST BEFORE: it simply did not. Steps 1-3 produced
REM    eighteen JSON payloads and a trajectory GIF and then stopped; every byte
REM    of this repo's output reached the live site only when a human ran a sync
REM    by hand. This is the step that closes that, and the gate is why it is safe
REM    to close it automatically.
REM
REM    WHY A GATE RATHER THAN A BARE `git add`: an exit code is not evidence
REM    about the artifacts. Per CLAUDE.md every script here is deliberately
REM    fail-safe -- "check file.exists(), fall back to a clearly labeled
REM    synthetic value, never hard-crash the pipeline" -- which is right for an
REM    unattended run and means a run that substituted synthetic data for
REM    everything still exits 0. The 2026-10-25 run did exactly that for the odds
REM    slate (two SYNTHETIC_FALLBACK lines, surfaced by the gate's assertion D).
REM    The artifact looks structurally perfect either way.
REM
REM    It runs even when PIPELINE_FAILED=1, and that is deliberate: steps 2 and 3
REM    are bet grading and the +EV slate, and a failure in either says nothing
REM    about whether step 1's web payloads are publishable. The gate decides that
REM    on the artifacts themselves. What a step failure DOES do is show up in
REM    assertion A or D, which is where it belongs.
REM
REM MODE (argument 1), the same vocabulary as NFL's schedule_publish.bat and
REM NBA's schedule_daily.bat so the four sports take the same words:
REM   (none) / dryrun   -> every assertion runs, NOTHING is published  [DEFAULT]
REM   publish           -> live: commit + push WNBA_analytics main only
REM   strict            -> dry run, SYNTHETIC_FALLBACK/[WARN] lines fatal
REM   publish-strict    -> live publish, those lines fatal
REM
REM Dry run is the DEFAULT ON PURPOSE. The unattended push is UNPROVEN on this
REM machine: credentials work in an interactive terminal (gh keyring plus
REM credential.helper=manager), but Task Scheduler's non-interactive session may
REM not reach Git Credential Manager, which would make a scheduled publish hang
REM on an auth prompt or fail obscurely at a time nobody is watching. That is
REM NFL Analytics issue #42, still open, and it applies verbatim here.
REM
REM   >>> Leave the registered task on `dryrun` until the unattended push is <<<
REM   >>> proven. Read the dry-run reports for a few days first.             <<<
REM
REM Note the seasonal interaction: outside the May-October window this file
REM exits at :offseason long before here, so the gate never runs out of season.
REM It carries no season window of its own -- a second copy of these month
REM numbers is a second thing to drift. See tools/publish_web.R's header.
REM ------------------------------------------------------------------------------
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

set PUBLISH_RC=0
if "%MODE_LABEL%"=="" (
    echo [ERROR] schedule_daily.bat: unknown publish mode "%MODE%". >> "%LOG_FILE%"
    echo [ERROR] Valid modes: dryrun ^(default^), strict, publish, publish-strict. >> "%LOG_FILE%"
    echo [ERROR] Steps 1-3 already ran; only the publish step is being skipped. >> "%LOG_FILE%"
    set PUBLISH_RC=2
)

if "%PUBLISH_RC%"=="0" (
    echo [Step 4/4] WNBA Web Publish Gate ^(%MODE_LABEL%^)... >> "%LOG_FILE%"
)
REM PUB_HEAD_BEFORE/AFTER feed the aggregator sync dispatch below.
set PUB_HEAD_BEFORE=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_BEFORE=%%S
if "%PUBLISH_RC%"=="0" %RSCRIPT% "%PROJECT_DIR%\tools\publish_web.R" %PW_ARGS% >> "%LOG_FILE%" 2>&1
if "%PUBLISH_RC%"=="0" set PUBLISH_RC=%ERRORLEVEL%
set PUB_HEAD_AFTER=
for /f "delims=" %%S in ('git rev-parse HEAD 2^>nul') do set PUB_HEAD_AFTER=%%S

if not "%PUBLISH_RC%"=="0" (
    echo [ERROR] Step 4/4 - publish gate - exit code %PUBLISH_RC% in mode %MODE_LABEL% >> "%LOG_FILE%"
    echo [ERROR] NOTHING WAS PUBLISHED. Yesterday's correct site stays up rather >> "%LOG_FILE%"
    echo [ERROR] than a half-updated one. Read the "-- Assertions --" block above: >> "%LOG_FILE%"
    echo [ERROR] every failing assertion is on a "[FAIL]" line with its id, name, >> "%LOG_FILE%"
    echo [ERROR] summary and the offending file or value in its detail lines. >> "%LOG_FILE%"
) else (
    echo [OK] Step 4/4 - publish gate passed in mode %MODE_LABEL%. >> "%LOG_FILE%"
)

REM ------------------------------------------------------------------------------
REM Dispatch the aggregator sync right after a publish that pushed.
REM Pushing WNBA_analytics deploys nothing; the site changes only when the
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
REM All four sports, not just wnba: sync-sports.yml runs in concurrency
REM group sync-sports with cancel-in-progress false, and GitHub keeps only
REM ONE pending run per group, replacing an older pending run with the
REM newer one. If WNBA asked for sports=wnba and NBA asked for sports=nba
REM a minute later while a sync was running, WNBA's request would be
REM dropped. A sync that always pulls all four makes any surviving run
REM correct.
REM
REM A failed dispatch (gh missing, not signed in, network) is a [WARN]
REM line and never changes this script's exit code: the publish already
REM succeeded and the cron is the backstop. gh is found on PATH or under
REM %ProgramFiles%\GitHub CLI, and run with `call` so a gh.cmd/gh.bat
REM shim returns here instead of ending this script.
REM ------------------------------------------------------------------------------
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

REM ------------------------------------------------------------------------------
REM Back up the append-only files (issue #200; ported from NBA_analytics #164).
REM cache/ and logs/ are gitignored and inside this checkout, so nothing else
REM protects the graded prediction log. tools\backup_accumulated_cache.ps1 COPIES
REM the files it names (never moves or links them) to a dated folder outside any
REM git checkout, by default %USERPROFILE%\front-office-backups\wnba\YYYY-MM-DD\
REM (override: WNBA_BACKUP_ROOT), keeps the 30 newest daily folders, and logs
REM one [BACKUP] line. It always exits 0: a failed copy is a [WARN] line and
REM never changes this run's exit code. It runs whether or not a step failed.
REM ------------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\tools\backup_accumulated_cache.ps1" -CacheDir "%PROJECT_DIR%\cache" -LogsDir "%PROJECT_DIR%\logs" >> "%LOG_FILE%" 2>&1

echo ================================================================== >> "%LOG_FILE%"
if "%PIPELINE_FAILED%"=="1" (
    echo WNBA PIPELINE RUN COMPLETED WITH ERRORS: %DATE% %TIME% >> "%LOG_FILE%"
) else (
    echo WNBA PIPELINE RUN COMPLETED SUCCESSFULLY: %DATE% %TIME% >> "%LOG_FILE%"
)
echo ================================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM Exit code reflects overall outcome (1 if any step failed, 0 otherwise) so Task Scheduler's
REM own "Last Run Result" surfaces a failed run too, on top of the [ERROR] log lines - but a
REM normal all-steps-succeeded run still exits 0, so Task Scheduler never flags a healthy run
REM as failed (criterion 5).
if "%PIPELINE_FAILED%"=="1" (
    exit /b 1
) else (
    exit /b 0
)
