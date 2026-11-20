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
QUEUE="${LOCK}.queue"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
check() { # check "description" command...
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
owner_of_lock() { sed -n 's/^owner=//p' "$LOCK/owner" 2>/dev/null; }
reset_lock() { rm -rf "$LOCK" "$LOCK".stale.* "$QUEUE"; }

ticket_count() {
  local dir="${1:-$QUEUE}" count=0 f
  [ -d "$dir" ] || { printf '0\n'; return 0; }
  for f in "$dir"/*.ticket; do
    [ -f "$f" ] && count=$((count + 1))
  done
  printf '%s\n' "$count"
}

stale_count() {
  local count=0 d
  for d in "$LOCK".stale.*; do
    [ -e "$d" ] && count=$((count + 1))
  done
  printf '%s\n' "$count"
}

wait_for_tickets() {
  local dir="$1" want="$2" tries=0
  while [ "$tries" -lt 80 ]; do
    if [ "$(ticket_count "$dir")" -ge "$want" ]; then
      return 0
    fi
    sleep 0.1 2>/dev/null || sleep 1
    tries=$((tries + 1))
  done
  return 1
}

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
check "SIGTERM trap removes stopped waiter's queue ticket" test "$(ticket_count)" -eq 0

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
echo "# test 6: FIFO queueing prevents starvation and queue-jumping"
reset_lock
as_job runner-a web "$STARTED" > /dev/null 2>&1

as_job_bg runner-b r "$STARTED" "$WORK/fifo-b.log"
B_PID=$BG_PID
check "waiter B enqueues first" wait_for_tickets "$QUEUE" 1

as_job_bg runner-c web "$STARTED" "$WORK/fifo-c.log"
C_PID=$BG_PID
check "waiter C enqueues second" wait_for_tickets "$QUEUE" 2

as_job_bg runner-d web "$STARTED" "$WORK/fifo-d.log"
D_PID=$BG_PID
check "waiter D enqueues third" wait_for_tickets "$QUEUE" 3

as_job runner-a web "$COMPLETED" > /dev/null 2>&1
wait "$B_PID"
check "earliest waiter B acquires first with exit 0" test $? -eq 0
check "lock belongs to earliest waiter B" test "$(owner_of_lock)" = "$(id_of runner-b r)"
check "later waiters C and D remain queued behind B" sh -c "kill -0 $C_PID 2>/dev/null && kill -0 $D_PID 2>/dev/null"

as_job runner-b r "$COMPLETED" > /dev/null 2>&1
wait "$C_PID"
check "second waiter C acquires before D with exit 0" test $? -eq 0
check "lock belongs to second waiter C" test "$(owner_of_lock)" = "$(id_of runner-c web)"
check "third waiter D remains queued behind C" kill -0 "$D_PID"

as_job runner-c web "$COMPLETED" > /dev/null 2>&1
wait "$D_PID"
check "third waiter D acquires last with exit 0" test $? -eq 0
check "lock belongs to third waiter D" test "$(owner_of_lock)" = "$(id_of runner-d web)"
as_job runner-d web "$COMPLETED" > /dev/null 2>&1
check "queue is empty after all FIFO waiters complete" test "$(ticket_count)" -eq 0

# New job arriving while the lock is free during an earlier waiter's sleep must NOT jump the queue.
reset_lock
as_job runner-a web "$STARTED" > /dev/null 2>&1
FRONT_OFFICE_CI_LOCK_POLL_SECONDS=3 as_job_bg runner-x web "$STARTED" "$WORK/fifo-x.log"
X_PID=$BG_PID
check "slow-polling waiter X enqueues while A holds lock" wait_for_tickets "$QUEUE" 1
sleep 1
as_job runner-a web "$COMPLETED" > /dev/null 2>&1

FRONT_OFFICE_CI_LOCK_POLL_SECONDS=1 as_job_bg runner-y r "$STARTED" "$WORK/fifo-y.log"
Y_PID=$BG_PID
check "fast-polling newcomer Y enqueues after X" wait_for_tickets "$QUEUE" 2
sleep 1
check "newcomer Y does not jump ahead while X finishes poll sleep" kill -0 "$Y_PID"
wait "$X_PID"
check "earlier waiter X acquires ahead of newcomer Y" test $? -eq 0
check "lock belongs to earlier waiter X" test "$(owner_of_lock)" = "$(id_of runner-x web)"
check "newcomer Y waits until X finishes" kill -0 "$Y_PID"
as_job runner-x web "$COMPLETED" > /dev/null 2>&1
wait "$Y_PID"
check "newcomer Y acquires after X releases" test $? -eq 0
check "lock belongs to newcomer Y" test "$(owner_of_lock)" = "$(id_of runner-y r)"
as_job runner-y r "$COMPLETED" > /dev/null 2>&1

# ---------------------------------------------------------------------------
echo "# test 7: killed waiter (SIGKILL) ticket is purged after TICKET_STALE_SECONDS"
reset_lock
as_job runner-a web "$STARTED" > /dev/null 2>&1

FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS=2 as_job_bg runner-b r "$STARTED" "$WORK/kill-b.log"
B_PID=$BG_PID
check "waiter B enqueues before SIGKILL" wait_for_tickets "$QUEUE" 1
kill -9 "$B_PID" 2>/dev/null || true
wait "$B_PID" 2>/dev/null || true
check "SIGKILL leaves orphaned ticket in queue" test "$(ticket_count)" -eq 1

as_job runner-a web "$COMPLETED" > /dev/null 2>&1
FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS=2 as_job_bg runner-c web "$STARTED" "$WORK/kill-c.log"
C_PID=$BG_PID
wait "$C_PID"
check "subsequent waiter C recovers and acquires with exit 0" test $? -eq 0
check "stale ticket purge is logged" grep -q "Purged stale queue ticket" "$WORK/kill-c.log"
check "lock belongs to waiter C after stale ticket eviction" test "$(owner_of_lock)" = "$(id_of runner-c web)"
check "no stale tickets remain in queue" test "$(ticket_count)" -eq 0
as_job runner-c web "$COMPLETED" > /dev/null 2>&1

check "default TICKET_STALE_SECONDS is 60 at POLL=10 STALE=3600" bash -c '
  unset FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS
  export FRONT_OFFICE_CI_LOCK_POLL_SECONDS=10 FRONT_OFFICE_CI_LOCK_STALE_SECONDS=3600
  source "$1"
  test "$TICKET_STALE_SECONDS" -eq 60
' _ "$STARTED"
check "default TICKET_STALE_SECONDS scales with POLL_SECONDS*6 when > 60" bash -c '
  unset FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS
  export FRONT_OFFICE_CI_LOCK_POLL_SECONDS=15 FRONT_OFFICE_CI_LOCK_STALE_SECONDS=3600
  source "$1"
  test "$TICKET_STALE_SECONDS" -eq 90
' _ "$STARTED"
check "default TICKET_STALE_SECONDS clamps to STALE_SECONDS when STALE < 60" bash -c '
  unset FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS
  export FRONT_OFFICE_CI_LOCK_POLL_SECONDS=10 FRONT_OFFICE_CI_LOCK_STALE_SECONDS=25
  source "$1"
  test "$TICKET_STALE_SECONDS" -eq 25
' _ "$STARTED"

# ---------------------------------------------------------------------------
echo "# test 8: unlabelled lock clears within UNLABELLED_GRACE_SECONDS and write_owner cleans temp"
reset_lock
mkdir "$LOCK"
FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS=2 as_job_bg runner-e web "$STARTED" "$WORK/unlabelled-e.log"
E_PID=$BG_PID
sleep 0.4 2>/dev/null || true
check "fresh unlabelled lock is not removed before grace period" kill -0 "$E_PID"
wait "$E_PID"
check "waiter clears unlabelled lock after UNLABELLED_GRACE_SECONDS" test $? -eq 0
check "unlabelled stale takeover is logged with grace threshold" grep -q "Removed stale lock held by 'unknown (owner file not written yet)'" "$WORK/unlabelled-e.log"
check "unlabelled takeover reports grace threshold 2s" grep -q "stale threshold 2s" "$WORK/unlabelled-e.log"
check "lock is now owned by waiter E" test "$(owner_of_lock)" = "$(id_of runner-e web)"
check "no stale grave directory remains after unlabelled takeover" test "$(stale_count)" -eq 0
as_job runner-e web "$COMPLETED" > /dev/null 2>&1

# write_owner must clean up owner.tmp.* on mv failure and return non-zero.
reset_lock
mkdir "$LOCK"
bash -c '
  source "$1"
  mv() { return 1; }
  write_owner
' _ "$STARTED" > /dev/null 2>&1
check "write_owner returns non-zero on mv failure" test $? -ne 0
check "write_owner leaves no stray owner.tmp.* files inside lock dir" sh -c '
  for f in "$1"/owner.tmp.*; do
    [ -e "$f" ] && exit 1
  done
  exit 0
' _ "$LOCK"
reset_lock
bash -c '
  source "$1"
  write_owner
' _ "$STARTED" > /dev/null 2>&1
check "write_owner returns non-zero when lock dir is missing" test $? -ne 0

# ---------------------------------------------------------------------------
echo "# test 9: double-takeover post-rename owner mismatch aborts and restores lock"
reset_lock
mkdir "$LOCK"
old=$(( $(date -u +%s) - 7200 ))
printf 'owner=%s\nstarted_epoch=%s\n' "stale-runner|example/repo|1|1|web" "$old" > "$LOCK/owner"
bash -c '
  source "$1"
  describe_holder() {
    printf "owner=%s\nstarted_epoch=%s\n" "winner-runner|example/repo|2|1|r" "$(now)" > "$OWNER_FILE"
    printf "%s" "stale-runner|example/repo|1|1|web"
  }
  take_over_stale "stale-runner|example/repo|1|1|web" 7200 3600
' _ "$STARTED" > "$WORK/double-labelled.log" 2>&1
check "post-rename owner mismatch (labelled) exits 0" test $? -eq 0
check "post-rename mismatch logs abort and restore warning" grep -q "stale-lock takeover aborted" "$WORK/double-labelled.log"
check "winner lock is restored in place after mismatch" test "$(owner_of_lock)" = "winner-runner|example/repo|2|1|r"
check "no stale grave directory remains after restore (labelled)" test "$(stale_count)" -eq 0

# Unlabelled expected, but owner file was written before mv executed.
reset_lock
mkdir "$LOCK"
bash -c '
  source "$1"
  describe_holder() {
    printf "owner=%s\nstarted_epoch=%s\n" "fast-holder|example/repo|3|1|web" "$(now)" > "$OWNER_FILE"
    printf "%s" "unknown (owner file not written yet)"
  }
  take_over_stale "unknown (owner file not written yet)" 65 60
' _ "$STARTED" > "$WORK/double-unlabelled.log" 2>&1
check "post-rename owner mismatch (unlabelled) exits 0" test $? -eq 0
check "post-rename unlabelled mismatch logs abort warning" grep -q "stale-lock takeover aborted" "$WORK/double-unlabelled.log"
check "newly written holder lock is preserved in place" test "$(owner_of_lock)" = "fast-holder|example/repo|3|1|web"
check "no stale grave directory remains after restore (unlabelled)" test "$(stale_count)" -eq 0

# ---------------------------------------------------------------------------
echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
