#!/usr/bin/env bash
# Plain-bash tests for the CI runner lock hooks (no bats needed).
# Run with:  bash tools/ci-runner/tests/run_tests.sh
# Uses a temporary directory only; never touches /var/lock.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
STARTED="$HERE/../job-started.sh"
COMPLETED="$HERE/../job-completed.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ci-lock-test.XXXXXX")"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$WORK"' EXIT

export FRONT_OFFICE_CI_LOCK_DIR="$WORK/front-office-ci.lock"
export FRONT_OFFICE_CI_LOCK_POLL_SECONDS=1
export FRONT_OFFICE_CI_LOCK_STALE_SECONDS=3600
LOCK="$FRONT_OFFICE_CI_LOCK_DIR"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
check() { # check "description" command...
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
owner_of_lock() { sed -n 's/^owner=//p' "$LOCK/owner" 2>/dev/null; }
reset_lock() { rm -rf "$LOCK" "$LOCK".stale.*; }

# Run a hook as a simulated job: as_job <runner> <job> <script>
# The subshell execs the hook, so when backgrounded `$!` is the hook process
# itself and `kill` actually stops it.
as_job() {
  local runner="$1" job="$2" script="$3"
  ( exec env RUNNER_NAME="$runner" GITHUB_REPOSITORY="example/repo" GITHUB_RUN_ID="100" \
    GITHUB_RUN_ATTEMPT="1" GITHUB_JOB="$job" bash "$script" )
}
# Background variant: as_job_bg <runner> <job> <script> <logfile>; sets BG_PID.
as_job_bg() {
  local runner="$1" job="$2" script="$3" logfile="$4"
  ( exec env RUNNER_NAME="$runner" GITHUB_REPOSITORY="example/repo" GITHUB_RUN_ID="100" \
    GITHUB_RUN_ATTEMPT="1" GITHUB_JOB="$job" bash "$script" ) > "$logfile" 2>&1 &
  BG_PID=$!
}
stop_job() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }
id_of() { printf '%s|example/repo|100|1|%s' "$1" "$2"; }

# ---------------------------------------------------------------------------
echo "# test 1: second job waits until the first releases the lock"
reset_lock
as_job runner-a web "$STARTED" > "$WORK/a-start.log" 2>&1
check "job A acquires the free lock with exit 0" test $? -eq 0
check "lock is owned by job A" test "$(owner_of_lock)" = "$(id_of runner-a web)"

as_job_bg runner-b r "$STARTED" "$WORK/b-start.log"
B_PID=$BG_PID
sleep 3
check "job B is still waiting while A holds the lock" kill -0 "$B_PID"
check "lock is still owned by job A while B waits" test "$(owner_of_lock)" = "$(id_of runner-a web)"
check "job B logs who it is waiting on" grep -q "Lock held by '$(id_of runner-a web)'" "$WORK/b-start.log"

as_job runner-a web "$COMPLETED" > "$WORK/a-done.log" 2>&1
check "job A's completed hook exits 0" test $? -eq 0
wait "$B_PID"
B_RC=$?
check "job B's started hook exits 0 after an ordinary wait" test "$B_RC" -eq 0
check "lock is now owned by job B" test "$(owner_of_lock)" = "$(id_of runner-b r)"
check "job B logs the time spent waiting" grep -Eq "Acquired host CI lock after waiting [1-9][0-9]*s" "$WORK/b-start.log"
echo "  job B log:"; sed 's/^/    | /' "$WORK/b-start.log"

as_job runner-b r "$COMPLETED" > /dev/null 2>&1
check "job B releases the lock" test ! -d "$LOCK"

# ---------------------------------------------------------------------------
echo "# test 2: stale lock is taken over"
reset_lock
mkdir "$LOCK"
old=$(( $(date -u +%s) - 7200 ))
printf 'owner=%s\nstarted_epoch=%s\n' "crashed-runner|example/repo|1|1|web" "$old" > "$LOCK/owner"
as_job runner-c web "$STARTED" > "$WORK/c-start.log" 2>&1
check "started hook exits 0 after stale takeover" test $? -eq 0
check "stale takeover is logged" grep -q "Removed stale lock held by 'crashed-runner|example/repo|1|1|web'" "$WORK/c-start.log"
check "lock is now owned by the new job" test "$(owner_of_lock)" = "$(id_of runner-c web)"
echo "  takeover log:"; sed 's/^/    | /' "$WORK/c-start.log"

# A lock younger than the threshold must NOT be taken over.
reset_lock
mkdir "$LOCK"
printf 'owner=%s\nstarted_epoch=%s\n' "busy-runner|example/repo|2|1|r" "$(date -u +%s)" > "$LOCK/owner"
as_job_bg runner-d web "$STARTED" "$WORK/d-start.log"
D_PID=$BG_PID
sleep 2
check "a fresh lock is not taken over" test "$(owner_of_lock)" = "busy-runner|example/repo|2|1|r"
check "waiting job stays blocked on a fresh lock" kill -0 "$D_PID"
stop_job "$D_PID"
check "stopped waiter is gone (no stray process)" sh -c "! kill -0 $D_PID 2>/dev/null"

# ---------------------------------------------------------------------------
echo "# test 3: completed hook does not remove someone else's lock"
reset_lock
mkdir "$LOCK"
printf 'owner=%s\nstarted_epoch=%s\n' "other-runner|example/repo|9|1|web" "$(date -u +%s)" > "$LOCK/owner"
as_job runner-e web "$COMPLETED" > "$WORK/e-done.log" 2>&1
check "completed hook exits 0 for a lock owned by another job" test $? -eq 0
check "the other job's lock is left in place" test "$(owner_of_lock)" = "other-runner|example/repo|9|1|web"
check "leaving the lock is logged" grep -q "leaving it in place" "$WORK/e-done.log"

# Same runner and job name but a different run attempt is a different owner.
RUNNER_NAME=other-runner GITHUB_REPOSITORY=example/repo GITHUB_RUN_ID=9 \
  GITHUB_RUN_ATTEMPT=2 GITHUB_JOB=web bash "$COMPLETED" > /dev/null 2>&1
check "a different run attempt does not remove the lock" test -d "$LOCK"

# ---------------------------------------------------------------------------
echo "# test 4: completed hook with the lock already gone"
reset_lock
as_job runner-f web "$COMPLETED" > "$WORK/f-done.log" 2>&1
check "completed hook exits 0 when no lock exists" test $? -eq 0
check "missing lock is logged" grep -q "nothing to release" "$WORK/f-done.log"

# ---------------------------------------------------------------------------
echo "# test 5: fallback identity when runner env vars are unset"
reset_lock
env -u RUNNER_NAME -u GITHUB_RUN_ID -u GITHUB_RUN_ATTEMPT -u GITHUB_JOB -u GITHUB_REPOSITORY \
  bash "$STARTED" > /dev/null 2>&1
check "started hook exits 0 with no runner env" test $? -eq 0
check "fallback owner id is recorded" test "$(owner_of_lock)" = "unknown-runner|unknown-repo|no-run-id|1|unknown-job"
env -u RUNNER_NAME -u GITHUB_RUN_ID -u GITHUB_RUN_ATTEMPT -u GITHUB_JOB -u GITHUB_REPOSITORY \
  bash "$COMPLETED" > /dev/null 2>&1
check "completed hook with the same fallback id releases the lock" test ! -d "$LOCK"

# ---------------------------------------------------------------------------
echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
