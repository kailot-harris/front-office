#!/usr/bin/env bash
# job-started.sh - GitHub Actions runner job-started hook.
#
# Acquires a host-wide lock so only one CI job runs at a time across every
# runner service on this host. Wire it up with
#   ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
# in each runner's .env file. See README.md in this directory.
#
# Environment overrides:
#   FRONT_OFFICE_CI_LOCK_DIR            lock directory (default /var/lock/front-office-ci.lock)
#   FRONT_OFFICE_CI_LOCK_POLL_SECONDS   seconds between attempts (default 10)
#   FRONT_OFFICE_CI_LOCK_STALE_SECONDS  lock age treated as stale (default 3600)
#
# Exit status: 0 once the lock is held. A non-zero exit fails the job, so it is
# used only when the lock can never be taken (e.g. the parent directory is
# missing or not writable), never for an ordinary wait.

set -u

LOCK_DIR="${FRONT_OFFICE_CI_LOCK_DIR:-/var/lock/front-office-ci.lock}"
POLL_SECONDS="${FRONT_OFFICE_CI_LOCK_POLL_SECONDS:-10}"
STALE_SECONDS="${FRONT_OFFICE_CI_LOCK_STALE_SECONDS:-3600}"
OWNER_FILE="$LOCK_DIR/owner"

RUNNER="${RUNNER_NAME:-unknown-runner}"
RUN_ID="${GITHUB_RUN_ID:-no-run-id}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
JOB="${GITHUB_JOB:-unknown-job}"
REPO="${GITHUB_REPOSITORY:-unknown-repo}"
OWNER_ID="${RUNNER}|${REPO}|${RUN_ID}|${RUN_ATTEMPT}|${JOB}"

log() { printf '[ci-lock] %s\n' "$*"; }
now() { date -u +%s; }

# Print the value of KEY from the owner file (empty if missing).
owner_field() {
  [ -f "$OWNER_FILE" ] || return 0
  sed -n "s/^$1=//p" "$OWNER_FILE" 2>/dev/null | head -n 1
}

# Modification time of a path in epoch seconds (GNU or BSD stat).
path_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || true
}

# Epoch seconds when the current lock was taken (empty if unknown).
lock_started_epoch() {
  local started
  started="$(owner_field started_epoch)"
  case "$started" in
    ''|*[!0-9]*) path_mtime "$LOCK_DIR" ;;
    *) printf '%s\n' "$started" ;;
  esac
}

describe_holder() {
  local holder
  holder="$(owner_field owner)"
  [ -n "$holder" ] || holder="unknown (owner file not written yet)"
  printf '%s' "$holder"
}

write_owner() {
  local t
  t="$(now)"
  {
    printf 'owner=%s\n' "$OWNER_ID"
    printf 'runner=%s\n' "$RUNNER"
    printf 'repository=%s\n' "$REPO"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'run_attempt=%s\n' "$RUN_ATTEMPT"
    printf 'job=%s\n' "$JOB"
    printf 'started_epoch=%s\n' "$t"
    printf 'started_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$OWNER_FILE.tmp.$$" && mv -f "$OWNER_FILE.tmp.$$" "$OWNER_FILE"
}

# Remove a stale lock. The lock is renamed first (atomic) so two waiters that
# both see it as stale cannot both delete it; only the one whose rename
# succeeds removes it.
take_over_stale() {
  local holder="$1" age="$2" grave
  grave="$LOCK_DIR.stale.$$.$(now)"
  # Re-check the holder right before the rename so a lock that changed hands
  # in the meantime is not removed.
  if [ "$(describe_holder)" != "$holder" ]; then
    return 0
  fi
  if mv "$LOCK_DIR" "$grave" 2>/dev/null; then
    rm -rf "$grave"
    log "Removed stale lock held by '$holder' (age ${age}s, stale threshold ${STALE_SECONDS}s)."
  fi
}

parent_dir="$(dirname "$LOCK_DIR")"
if [ ! -d "$parent_dir" ] || [ ! -w "$parent_dir" ]; then
  log "ERROR: lock parent directory '$parent_dir' is missing or not writable; cannot take the lock."
  exit 1
fi

wait_start="$(now)"
announced=""
log "Requesting host CI lock '$LOCK_DIR' for $OWNER_ID."

while :; do
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    if ! write_owner; then
      log "WARNING: could not write owner file '$OWNER_FILE'; lock is held but unlabeled."
    fi
    waited=$(( $(now) - wait_start ))
    log "Acquired host CI lock after waiting ${waited}s ($(( waited / 60 ))m $(( waited % 60 ))s)."
    exit 0
  fi

  if [ ! -d "$LOCK_DIR" ]; then
    # mkdir failed but nothing is there: lost a race with a release, or a
    # permission problem. Retry quickly; the parent check above covers the
    # permanent case.
    sleep 1
    continue
  fi

  holder="$(describe_holder)"
  if [ "$holder" = "$OWNER_ID" ]; then
    log "Host CI lock is already held by this job; continuing."
    exit 0
  fi

  started="$(lock_started_epoch)"
  t="$(now)"
  age=""
  [ -n "$started" ] && age=$(( t - started ))

  if [ -n "$age" ] && [ "$age" -ge "$STALE_SECONDS" ]; then
    take_over_stale "$holder" "$age"
    continue
  fi

  waited=$(( t - wait_start ))
  if [ "$holder" != "$announced" ]; then
    log "Lock held by '$holder' (held for ${age:-?}s). Waiting, polling every ${POLL_SECONDS}s."
    announced="$holder"
  else
    log "Still waiting on '$holder' (held for ${age:-?}s); this job has waited ${waited}s."
  fi
  sleep "$POLL_SECONDS"
done
