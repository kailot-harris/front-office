#!/usr/bin/env bash
# job-completed.sh - GitHub Actions runner job-completed hook.
#
# Releases the host-wide CI lock taken by job-started.sh, but only if this job
# owns it. Wire it up with
#   ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/opt/actions-runner/hooks/job-completed.sh
# in each runner's .env file. See README.md in this directory.
#
# Uses the same FRONT_OFFICE_CI_LOCK_DIR override as job-started.sh.
#
# Exit status: always 0. A missing lock or a lock owned by another job is
# logged and left alone; a hook failure here would only fail a finished job.

set -u

LOCK_DIR="${FRONT_OFFICE_CI_LOCK_DIR:-/var/lock/front-office-ci.lock}"
OWNER_FILE="$LOCK_DIR/owner"

RUNNER="${RUNNER_NAME:-unknown-runner}"
RUN_ID="${GITHUB_RUN_ID:-no-run-id}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
JOB="${GITHUB_JOB:-unknown-job}"
REPO="${GITHUB_REPOSITORY:-unknown-repo}"
OWNER_ID="${RUNNER}|${REPO}|${RUN_ID}|${RUN_ATTEMPT}|${JOB}"

log() { printf '[ci-lock] %s\n' "$*"; }

if [ ! -d "$LOCK_DIR" ]; then
  log "No host CI lock at '$LOCK_DIR'; nothing to release."
  exit 0
fi

holder=""
if [ -f "$OWNER_FILE" ]; then
  holder="$(sed -n 's/^owner=//p' "$OWNER_FILE" 2>/dev/null | head -n 1)"
fi

if [ "$holder" != "$OWNER_ID" ]; then
  log "Host CI lock is held by '${holder:-unknown}', not this job ($OWNER_ID); leaving it in place."
  exit 0
fi

started="$(sed -n 's/^started_epoch=//p' "$OWNER_FILE" 2>/dev/null | head -n 1)"
if rm -rf "$LOCK_DIR" 2>/dev/null && [ ! -d "$LOCK_DIR" ]; then
  case "$started" in
    ''|*[!0-9]*) log "Released host CI lock." ;;
    *) log "Released host CI lock after holding it for $(( $(date -u +%s) - started ))s." ;;
  esac
else
  log "WARNING: could not remove '$LOCK_DIR'; it will be taken over once stale."
fi
exit 0
