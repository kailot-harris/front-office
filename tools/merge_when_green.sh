#!/usr/bin/env bash
# ==============================================================================
# tools/merge_when_green.sh -- squash-merge a pull request only when every
# check on its reviewed head commit has passed.
#
# GitHub cannot enforce "checks must pass" on this private repository on the
# current plan, so this script is the guard. Agents merge with it, never with
# a bare `gh pr merge` (see CLAUDE.md, "Merging pull requests").
#
# Usage:
#   tools/merge_when_green.sh <pr-number> <reviewed-head-sha> [--timeout-min N] [--dry-run]
#
# It refuses (non-zero exit, nothing merged) when:
#   - the PR is not open, or its head is not the reviewed commit (full SHA);
#   - the PR has no checks at all;
#   - any check failed or was cancelled;
#   - checks are still running when the timeout (default 60 minutes) ends;
#   - the head moved while it was waiting.
# Otherwise it runs `gh pr merge --squash --match-head-commit <sha>`.
# --dry-run does every check and prints the merge command instead of running it.
#
# Exit codes: 0 merged (or would merge, with --dry-run), 1 refused, 2 bad usage.
# Needs: gh (signed in), and a checkout of the repository as the working
# directory so gh can find the repo.
# ==============================================================================
set -euo pipefail

usage() {
  echo "usage: tools/merge_when_green.sh <pr-number> <reviewed-head-sha> [--timeout-min N] [--dry-run]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
PR="$1"; SHA="$2"; shift 2
TIMEOUT_MIN=60
DRY_RUN=0
POLL_SEC="${MERGE_WHEN_GREEN_POLL_SEC:-30}"
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-min) [ $# -ge 2 ] || usage; TIMEOUT_MIN="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "refused: PR number must be numeric, got '$PR'" >&2; exit 2; }
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "refused: give the full 40-character head SHA you reviewed, got '$SHA'" >&2; exit 2; }
[[ "$TIMEOUT_MIN" =~ ^[0-9]+$ ]] || usage

refuse() { echo "refused: $*" >&2; exit 1; }

head_and_state() {
  gh pr view "$PR" --json state,headRefOid --jq '.state + " " + .headRefOid'
}

read -r STATE HEAD <<< "$(head_and_state)"
[ "$STATE" = "OPEN" ] || refuse "PR #$PR is $STATE, not OPEN"
[ "$HEAD" = "$SHA" ] || refuse "PR #$PR head is $HEAD, not the reviewed commit $SHA"

deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
while :; do
  # `gh pr checks` exits non-zero while checks are pending or failing, so its
  # exit code is ignored and the JSON is read instead.
  checks="$(gh pr checks "$PR" --json name,bucket --jq '.[] | .bucket + "\t" + .name' 2>/dev/null || true)"
  if [ -z "$checks" ]; then
    total=0
  else
    total=$(printf '%s\n' "$checks" | wc -l | tr -d ' ')
  fi
  failed=$(printf '%s\n' "$checks" | awk -F'\t' '$1=="fail" || $1=="cancel" {print $2}')
  pending=$(printf '%s\n' "$checks" | awk -F'\t' '$1=="pending" {print $2}')

  if [ -n "$failed" ]; then
    echo "Checks on PR #$PR:" >&2
    printf '%s\n' "$checks" | sed 's/^/  /' >&2
    refuse "failed or cancelled check(s): $(printf '%s' "$failed" | paste -sd, -)"
  fi
  if [ "$total" -gt 0 ] && [ -z "$pending" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    if [ "$total" -eq 0 ]; then
      refuse "PR #$PR has no checks after ${TIMEOUT_MIN} min; CI did not run"
    fi
    refuse "checks still running after ${TIMEOUT_MIN} min: $(printf '%s' "$pending" | paste -sd, -)"
  fi
  if [ "$total" -eq 0 ]; then
    echo "waiting: no checks reported yet on PR #$PR"
  else
    echo "waiting: $(printf '%s\n' "$pending" | grep -c .) of $total check(s) still running"
  fi
  sleep "$POLL_SEC"
done

read -r STATE HEAD <<< "$(head_and_state)"
[ "$STATE" = "OPEN" ] || refuse "PR #$PR became $STATE while waiting"
[ "$HEAD" = "$SHA" ] || refuse "PR #$PR head moved to $HEAD while waiting; review it again"

echo "All $total check(s) passed on $SHA:"
printf '%s\n' "$checks" | sed 's/^/  /'
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run: would run: gh pr merge $PR --squash --match-head-commit $SHA"
  exit 0
fi
gh pr merge "$PR" --squash --match-head-commit "$SHA"
echo "merged PR #$PR at $SHA"
