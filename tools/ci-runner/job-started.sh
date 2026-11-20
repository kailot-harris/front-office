#!/usr/bin/env bash
# job-started.sh - GitHub Actions runner job-started hook.
#
# Acquires a host-wide FIFO lock so only one CI job runs at a time across every
# runner service on this host. Wire it up with
#   ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/actions-runner/hooks/job-started.sh
# in each runner's .env file. See README.md in this directory.
#
# Environment overrides:
#   FRONT_OFFICE_CI_LOCK_DIR                      lock directory (default /var/lock/front-office-ci.lock)
#   FRONT_OFFICE_CI_LOCK_QUEUE_DIR                FIFO ticket queue dir (default ${LOCK_DIR}.queue)
#   FRONT_OFFICE_CI_LOCK_POLL_SECONDS             seconds between attempts (default 10)
#   FRONT_OFFICE_CI_LOCK_STALE_SECONDS            labelled lock age treated as stale (default 3600)
#   FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS unlabelled lock age treated as stale (default 60)
#   FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS     queue ticket heartbeat age treated as stale
#                                                 (default max(60, POLL_SECONDS*6), clamped <= STALE_SECONDS)
#
# Exit status: 0 once the lock is held. A non-zero exit fails the job, so it is
# used only when the lock can never be taken (e.g. the parent or queue
# directory is missing or not writable), never for an ordinary wait.

set -u

LOCK_DIR="${FRONT_OFFICE_CI_LOCK_DIR:-/var/lock/front-office-ci.lock}"
QUEUE_DIR="${FRONT_OFFICE_CI_LOCK_QUEUE_DIR:-${LOCK_DIR}.queue}"
POLL_SECONDS="${FRONT_OFFICE_CI_LOCK_POLL_SECONDS:-10}"
STALE_SECONDS="${FRONT_OFFICE_CI_LOCK_STALE_SECONDS:-3600}"
UNLABELLED_GRACE_SECONDS="${FRONT_OFFICE_CI_LOCK_UNLABELLED_GRACE_SECONDS:-60}"
OWNER_FILE="$LOCK_DIR/owner"

RUNNER="${RUNNER_NAME:-unknown-runner}"
RUN_ID="${GITHUB_RUN_ID:-no-run-id}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
JOB="${GITHUB_JOB:-unknown-job}"
REPO="${GITHUB_REPOSITORY:-unknown-repo}"
OWNER_ID="${RUNNER}|${REPO}|${RUN_ID}|${RUN_ATTEMPT}|${JOB}"

TICKET_FILE=""
TICKET_CREATED=""
SLEEP_PID=""
QUEUE_HEAD_NAME=""
QUEUE_HEAD_OWNER=""
QUEUE_POS=0
QUEUE_LEN=0

log() { printf '[ci-lock] %s\n' "$*"; }
now() { date -u +%s; }

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

if ! is_uint "$POLL_SECONDS" || ! is_uint "$STALE_SECONDS" || ! is_uint "$UNLABELLED_GRACE_SECONDS"; then
  log "ERROR: timing overrides must be non-negative integers."
  exit 1
fi

if [ -n "${FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS:-}" ]; then
  TICKET_STALE_SECONDS="$FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS"
  if ! is_uint "$TICKET_STALE_SECONDS"; then
    log "ERROR: FRONT_OFFICE_CI_LOCK_TICKET_STALE_SECONDS must be a non-negative integer."
    exit 1
  fi
else
  TICKET_STALE_SECONDS=$(( POLL_SECONDS * 6 ))
  [ "$TICKET_STALE_SECONDS" -lt 60 ] && TICKET_STALE_SECONDS=60
  [ "$TICKET_STALE_SECONDS" -gt "$STALE_SECONDS" ] && TICKET_STALE_SECONDS="$STALE_SECONDS"
fi

# Monotonic-friendly nanosecond epoch for lexicographic FIFO ordering even when
# multiple waiters start inside the same second. Falls back to %s000000000 when
# date +%N is unavailable (e.g. BSD/macOS date).
now_ns() {
  local ts
  ts="$(date -u '+%s%N' 2>/dev/null || true)"
  case "$ts" in
    ''|*[!0-9]*)
      printf '%s000000000\n' "$(now)"
      ;;
    *)
      printf '%s\n' "$ts"
      ;;
  esac
}

# Read KEY=VALUE from a metadata file without spawning external processes.
read_kv_field() {
  local key="$1" file="$2" k="" v=""
  [ -f "$file" ] || return 0
  {
    while IFS='=' read -r k v || [ -n "$k" ]; do
      if [ "$k" = "$key" ]; then
        v="${v%$'\r'}"
        printf '%s\n' "$v"
        return 0
      fi
    done < "$file"
  } 2>/dev/null || true
}

# Print the value of KEY from the lock owner file (empty if missing).
owner_field() {
  read_kv_field "$1" "${2:-$OWNER_FILE}"
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
  if [ ! -f "$OWNER_FILE" ]; then
    printf '%s' "unknown (owner file not written yet)"
    return 0
  fi
  holder="$(owner_field owner)"
  if [ -n "$holder" ]; then
    printf '%s' "$holder"
  else
    printf '%s' "unknown (empty or invalid owner file)"
  fi
}

# Retry mv -f briefly to tolerate transient sharing locks when another waiter is
# concurrently reading the target file (e.g. on Windows Git Bash / NTFS).
mv_replace() {
  local src="$1" dst="$2" attempt=0
  while [ "$attempt" -lt 5 ]; do
    if mv -f "$src" "$dst" 2>/dev/null; then
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 0.05 2>/dev/null || true
  done
  return 1
}

write_owner() {
  local t tmp
  t="$(now)"
  tmp="$OWNER_FILE.tmp.$$"
  if {
    printf 'owner=%s\n' "$OWNER_ID"
    printf 'runner=%s\n' "$RUNNER"
    printf 'repository=%s\n' "$REPO"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'run_attempt=%s\n' "$RUN_ATTEMPT"
    printf 'job=%s\n' "$JOB"
    printf 'started_epoch=%s\n' "$t"
    printf 'started_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$tmp" 2>/dev/null && mv_replace "$tmp" "$OWNER_FILE"; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

write_ticket_atomically() {
  local target="$1" created="$2" hb="$3" tmp
  tmp="$(mktemp "$QUEUE_DIR/.hb.$$.XXXXXX" 2>/dev/null)" || return 1
  if {
    printf 'owner=%s\n' "$OWNER_ID"
    printf 'created_epoch=%s\n' "$created"
    printf 'heartbeat_epoch=%s\n' "$hb"
  } > "$tmp" 2>/dev/null && mv_replace "$tmp" "$target"; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

enqueue_ticket() {
  local ts pid_pad tmp suffix t target
  ts="$(now_ns)"
  pid_pad="$(printf '%010d' "$$")"
  t="$(now)"
  tmp="$(mktemp "$QUEUE_DIR/.tmp.${pid_pad}.XXXXXX" 2>/dev/null)" || return 1
  suffix="${tmp##*.}"
  target="$QUEUE_DIR/${ts}-${pid_pad}-${suffix}.ticket"
  if {
    printf 'owner=%s\n' "$OWNER_ID"
    printf 'created_epoch=%s\n' "$t"
    printf 'heartbeat_epoch=%s\n' "$t"
  } > "$tmp" 2>/dev/null && mv_replace "$tmp" "$target"; then
    TICKET_FILE="$target"
    TICKET_CREATED="$t"
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

refresh_ticket() {
  local t
  t="$(now)"
  if [ -z "${TICKET_FILE:-}" ] || [ ! -f "$TICKET_FILE" ]; then
    log "WARNING: queue ticket '${TICKET_FILE:-unset}' missing; re-enqueueing at tail."
    enqueue_ticket
    return $?
  fi
  write_ticket_atomically "$TICKET_FILE" "$TICKET_CREATED" "$t"
}

remove_own_ticket() {
  local pid_pad
  if [ -n "${TICKET_FILE:-}" ]; then
    rm -f "$TICKET_FILE" 2>/dev/null || true
  fi
  if [ -n "${QUEUE_DIR:-}" ] && [ -d "$QUEUE_DIR" ]; then
    pid_pad="$(printf '%010d' "$$")"
    rm -f "$QUEUE_DIR/.hb.$$."* "$QUEUE_DIR/.tmp.${pid_pad}."* 2>/dev/null || true
  fi
}

cleanup_on_exit() {
  if [ -n "${SLEEP_PID:-}" ]; then
    kill "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""
  fi
  remove_own_ticket
}

interruptible_sleep() {
  local secs="$1"
  [ "$secs" -gt 0 ] 2>/dev/null || return 0
  sleep "$secs" &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || true
  SLEEP_PID=""
}

scan_queue_and_purge() {
  local t f name hb age stale_grave stale_owner
  local live_names="" sorted_names="" own_name idx line

  t="$(now)"
  own_name="${TICKET_FILE##*/}"

  # Clean up any leftover hidden temp files from crashed processes.
  for f in "$QUEUE_DIR"/.*; do
    name="${f##*/}"
    [ "$name" = "." ] || [ "$name" = ".." ] && continue
    [ -f "$f" ] || continue
    hb="$(path_mtime "$f")"
    is_uint "$hb" || continue
    age=$(( t - hb ))
    if [ "$age" -ge "$TICKET_STALE_SECONDS" ]; then
      rm -f "$f" 2>/dev/null || true
    fi
  done

  for f in "$QUEUE_DIR"/*.ticket; do
    [ -f "$f" ] || continue
    if [ "$f" = "$TICKET_FILE" ]; then
      live_names="${live_names}${own_name}
"
      continue
    fi

    hb="$(read_kv_field heartbeat_epoch "$f")"
    if ! is_uint "$hb"; then
      hb="$(read_kv_field created_epoch "$f")"
      if ! is_uint "$hb"; then
        hb="$(path_mtime "$f")"
      fi
    fi

    if is_uint "$hb"; then
      age=$(( t - hb ))
      if [ "$age" -ge "$TICKET_STALE_SECONDS" ]; then
        stale_grave="$QUEUE_DIR/.stale.$$.$(now_ns)"
        if mv "$f" "$stale_grave" 2>/dev/null; then
          stale_owner="$(read_kv_field owner "$stale_grave")"
          rm -f "$stale_grave" 2>/dev/null || true
          log "Purged stale queue ticket for '${stale_owner:-unknown}' (heartbeat age ${age}s, stale threshold ${TICKET_STALE_SECONDS}s)."
        fi
        continue
      fi
    fi

    live_names="${live_names}${f##*/}
"
  done

  QUEUE_HEAD_NAME=""
  QUEUE_HEAD_OWNER=""
  QUEUE_POS=0
  QUEUE_LEN=0

  [ -n "$live_names" ] || return 0

  sorted_names="$(printf '%s' "$live_names" | LC_ALL=C sort)"
  idx=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    idx=$(( idx + 1 ))
    if [ "$idx" -eq 1 ]; then
      QUEUE_HEAD_NAME="$line"
      QUEUE_HEAD_OWNER="$(read_kv_field owner "$QUEUE_DIR/$line")"
    fi
    if [ "$line" = "$own_name" ]; then
      QUEUE_POS="$idx"
    fi
  done <<EOF
$sorted_names
EOF
  QUEUE_LEN="$idx"
}

# Remove a stale lock. The lock is renamed first (atomic) so two waiters that
# both see it as stale cannot both delete it; only the one whose rename
# succeeds inspects $grave/owner. If the owner changed between the pre-check
# and the rename (another waiter took over and created a fresh lock), restore
# $grave instead of deleting it.
take_over_stale() {
  local holder="$1" age="$2" threshold="${3:-$STALE_SECONDS}"
  local grave actual_match=0 grave_owner actual_desc

  grave="$LOCK_DIR.stale.$$.$(now_ns)"
  # Re-check the holder right before the rename so a lock that changed hands
  # in the meantime is not moved.
  if [ "$(describe_holder)" != "$holder" ]; then
    return 0
  fi

  if mv "$LOCK_DIR" "$grave" 2>/dev/null; then
    if [ "$holder" = "unknown (owner file not written yet)" ]; then
      [ ! -f "$grave/owner" ] && actual_match=1
    elif [ "$holder" = "unknown (empty or invalid owner file)" ]; then
      [ -f "$grave/owner" ] && [ -z "$(owner_field owner "$grave/owner")" ] && actual_match=1
    else
      grave_owner="$(owner_field owner "$grave/owner")"
      [ "$grave_owner" = "$holder" ] && actual_match=1
    fi

    if [ "$actual_match" -ne 1 ]; then
      if [ ! -f "$grave/owner" ]; then
        actual_desc="unknown (owner file not written yet)"
      else
        actual_desc="$(owner_field owner "$grave/owner")"
        [ -n "$actual_desc" ] || actual_desc="unknown (empty or invalid owner file)"
      fi
      if [ ! -d "$LOCK_DIR" ]; then
        if mv "$grave" "$LOCK_DIR" 2>/dev/null; then
          log "WARNING: stale-lock takeover aborted; lock owner changed from '$holder' to '$actual_desc' before rename; restored lock."
        else
          log "WARNING: stale-lock takeover aborted; lock owner changed from '$holder' to '$actual_desc' before rename; could not restore '$grave' (left in place)."
        fi
      else
        log "WARNING: stale-lock takeover aborted; lock owner changed from '$holder' to '$actual_desc' before rename and '$LOCK_DIR' already exists (leaving '$grave' intact)."
      fi
      return 0
    fi

    rm -rf "$grave"
    log "Removed stale lock held by '$holder' (age ${age}s, stale threshold ${threshold}s)."
  elif [ -d "$LOCK_DIR" ]; then
    log "WARNING: could not remove stale lock held by '$holder' (age ${age}s); check that every runner account can remove it (sticky lock parent directory?)."
  fi
}

main() {
  local parent_dir wait_start announced
  local waited holder t started age threshold status_key

  parent_dir="$(dirname "$LOCK_DIR")"
  if [ ! -d "$parent_dir" ] || [ ! -w "$parent_dir" ]; then
    log "ERROR: lock parent directory '$parent_dir' is missing or not writable; cannot take the lock."
    exit 1
  fi

  if [ -e "$QUEUE_DIR" ] && [ ! -d "$QUEUE_DIR" ]; then
    log "ERROR: lock queue path '$QUEUE_DIR' exists and is not a directory; cannot take the lock."
    exit 1
  fi
  if [ ! -d "$QUEUE_DIR" ]; then
    mkdir -p "$QUEUE_DIR" 2>/dev/null || true
  fi
  if [ ! -d "$QUEUE_DIR" ] || [ ! -w "$QUEUE_DIR" ]; then
    log "ERROR: lock queue directory '$QUEUE_DIR' is missing or not writable; cannot take the lock."
    exit 1
  fi

  if [ -d "$LOCK_DIR" ] && [ "$(owner_field owner)" = "$OWNER_ID" ]; then
    log "Host CI lock is already held by this job; continuing."
    exit 0
  fi

  wait_start="$(now)"
  announced=""
  log "Requesting host CI lock '$LOCK_DIR' for $OWNER_ID."

  trap 'cleanup_on_exit' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! enqueue_ticket; then
    log "ERROR: could not create queue ticket in '$QUEUE_DIR'; cannot take the lock."
    exit 1
  fi

  while :; do
    if ! refresh_ticket; then
      if [ ! -d "$QUEUE_DIR" ] || [ ! -w "$QUEUE_DIR" ]; then
        log "ERROR: queue directory '$QUEUE_DIR' is no longer writable; cannot continue."
        exit 1
      fi
      log "WARNING: transient failure refreshing queue ticket '$TICKET_FILE'; retrying on next poll."
      interruptible_sleep "$POLL_SECONDS"
      continue
    fi

    scan_queue_and_purge

    if [ "$QUEUE_POS" -eq 1 ]; then
      if mkdir "$LOCK_DIR" 2>/dev/null; then
        if ! write_owner; then
          log "WARNING: could not write owner file '$OWNER_FILE'; lock is held but unlabeled."
        fi
        remove_own_ticket
        waited=$(( $(now) - wait_start ))
        log "Acquired host CI lock after waiting ${waited}s ($(( waited / 60 ))m $(( waited % 60 ))s)."
        exit 0
      fi

      if [ ! -d "$LOCK_DIR" ]; then
        # mkdir failed but nothing is there: lost a race with a release, or a
        # permission problem. Retry quickly; the parent check above covers the
        # permanent case.
        interruptible_sleep 1
        continue
      fi

      holder="$(describe_holder)"
      if [ "$holder" = "$OWNER_ID" ]; then
        remove_own_ticket
        log "Host CI lock is already held by this job; continuing."
        exit 0
      fi

      t="$(now)"
      age=""
      threshold="$STALE_SECONDS"
      if [ ! -f "$OWNER_FILE" ]; then
        started="$(path_mtime "$LOCK_DIR")"
        threshold="$UNLABELLED_GRACE_SECONDS"
        [ "$threshold" -gt "$STALE_SECONDS" ] && threshold="$STALE_SECONDS"
      else
        started="$(lock_started_epoch)"
      fi
      [ -n "$started" ] && age=$(( t - started ))

      if [ -n "$age" ] && [ "$age" -ge "$threshold" ]; then
        take_over_stale "$holder" "$age" "$threshold"
        # A failed or aborted takeover leaves the lock in place; back off instead of spinning.
        [ -d "$LOCK_DIR" ] && interruptible_sleep "$POLL_SECONDS"
        continue
      fi

      waited=$(( t - wait_start ))
      if [ "$holder" != "$announced" ]; then
        log "Lock held by '$holder' (held for ${age:-?}s). Waiting, polling every ${POLL_SECONDS}s."
        announced="$holder"
      else
        log "Still waiting on '$holder' (held for ${age:-?}s); this job has waited ${waited}s."
      fi
      interruptible_sleep "$POLL_SECONDS"
      continue
    fi

    # Not at the head of the FIFO queue yet; wait for earlier waiter(s).
    t="$(now)"
    waited=$(( t - wait_start ))
    if [ -d "$LOCK_DIR" ]; then
      holder="$(describe_holder)"
      if [ "$holder" = "$OWNER_ID" ]; then
        remove_own_ticket
        log "Host CI lock is already held by this job; continuing."
        exit 0
      fi
      started="$(lock_started_epoch)"
      age=""
      [ -n "$started" ] && age=$(( t - started ))
      status_key="held:${holder}:head:${QUEUE_HEAD_NAME}"
      if [ "$status_key" != "$announced" ]; then
        log "Lock held by '$holder' (held for ${age:-?}s); queued at position ${QUEUE_POS}/${QUEUE_LEN} behind '${QUEUE_HEAD_OWNER:-unknown}'. Waiting, polling every ${POLL_SECONDS}s."
        announced="$status_key"
      else
        log "Still waiting on '$holder' (held for ${age:-?}s); queued at position ${QUEUE_POS}/${QUEUE_LEN}; this job has waited ${waited}s."
      fi
    else
      status_key="free:head:${QUEUE_HEAD_NAME}"
      if [ "$status_key" != "$announced" ]; then
        log "Lock is free, queued at position ${QUEUE_POS}/${QUEUE_LEN} behind '${QUEUE_HEAD_OWNER:-unknown}'. Waiting, polling every ${POLL_SECONDS}s."
        announced="$status_key"
      else
        log "Still queued at position ${QUEUE_POS}/${QUEUE_LEN} behind '${QUEUE_HEAD_OWNER:-unknown}'; this job has waited ${waited}s."
      fi
    fi
    interruptible_sleep "$POLL_SECONDS"
  done
}

if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
  main "$@"
fi
