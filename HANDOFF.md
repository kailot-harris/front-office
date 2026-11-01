# HANDOFF — both offseason-monitor PRs merged and synced into both subtrees; deploy green; no slice in flight

**Written** 2026-11-01 ~02:10 local, after `origin/main` = `2f585b9`
(*chore: subtree-pull mlb (automated sync)*). This checkout is **on `main`, 0 ahead / 0 behind
`origin/main`**.
**Working tree is clean.** Nothing dirty, nothing staged, nothing untracked of note.
**The live site reflects this state** — the GitHub Pages deploy for `2f585b9` completed
successfully (`gh run list --workflow "Build and deploy GitHub Pages"`, confirmed this session).
**For** whoever picks this up next, with no memory of the session that wrote it.

There is no prior `HANDOFF.md` in this repo to reconcile against — this is the first one.

## 1. What this project is

`kailot-harris/front-office` is the aggregator monorepo that serves the live site at
`https://kailot-harris.github.io/front-office/`. It has no code of its own for MLB/WNBA/NBA/NFL —
each sport's directory (`mlb/`, `wnba/`, `nba/`, `nfl/`) is a **git subtree** whose real source
lives in a separate per-sport repo:

| Aggregator path | Source repo | Remote name (this checkout) |
|---|---|---|
| `mlb/` | `kailot-harris/MLB-Analytics` | `mlb-origin` |
| `wnba/` | `kailot-harris/WNBA_analytics` | `wnba-origin` |
| `nba/` | `kailot-harris/NBA_analytics` | `nba-origin` |
| `nfl/` | `kailot-harris/NFL_analytics` | `nfl-origin` |

**Content flows source → aggregator, never the reverse.** A periodic/scheduled job runs
`git subtree pull --prefix=<sport> <sport>-origin main` to bring each source repo's latest
`main` into the aggregator. Pushing `front-office`'s `main` triggers the "Build and deploy
GitHub Pages" workflow, which publishes the live site. There's also a "Sync sport subtrees and
deploy" workflow that appears to automate the subtree-pull + deploy step — this session was
explicitly told not to trigger it mid-task (see §6), so its exact behavior wasn't observed
directly; treat that as unverified rather than assumed-safe.

## 2. Progress tracking

No open issues in `kailot-harris/front-office` as of this writing. Two PRs merged this session,
in a strict required order (see §6 for why order matters):

| PR | Repo | Branch | Status | Squash commit |
|---|---|---|---|---|
| #86 | front-office | `fix/offseason-team-attribution-and-test-baseline` | MERGED (1st) | `4a842ea` |
| #50 | MLB-Analytics | `fix/offseason-wire-fixes-and-test-baseline` | MERGED (2nd) | `97c7d7b` (in MLB-Analytics); landed here via subtree pull as part of `2f585b9` |

Both were pre-reviewed before this session — merging was the only action taken on them, no code
written. After both merged, `git subtree pull --prefix=mlb mlb-origin main` was run to bring
MLB-Analytics's `97c7d7b` in (merge commit `2f585b9`), and separately a WNBA subtree pull
(`7ce5e62`) brought in a markdown-rendering fix from `WNBA_analytics` (`5f6f892`) — see that
repo's own handoff for what that fix does.

Full commit sequence this session (oldest first): `87b9110`(mlb-origin, pre-session)
→ `5f6f892`(wnba-origin) → `7ce5e62`(subtree-pull wnba) → `b22689f`(mlb-origin, pre-session,
arrived via automation between pushes) → `00f2fae`(merge, conflict resolved — see §6) →
`4a842ea`(PR #86) → `97c7d7b`(PR #50, via mlb-origin) → `2f585b9`(subtree-pull mlb).

## 3. What's actually implemented

Nothing in this repo is "implemented" in the usual sense — it's pure integration. What's
verified **in this checkout, this session**:

| Claim | Verified how |
|---|---|
| `mlb/` and `MLB Analytics` agree on content | `md5sum` on 9 specific files, both raw (initially reported as 9/9 mismatch) and after stripping `\r` (9/9 match — see §6's CRLF gotcha, this was a false alarm) |
| `wnba/` reflects `WNBA_analytics`'s markdown-rendering fix | Subtree-pull merge diff showed exactly the 3 expected files (`OffseasonMonitorClient.tsx`, `package.json`, `package-lock.json`) |
| Deploy actually publishes | `gh run list --workflow "Build and deploy GitHub Pages"` polled to `completed`/`success` for commits `7ce5e62`, `4a842ea`, and `2f585b9` |

Not verified: that the live site's rendered HTML actually looks correct in a browser post-deploy
— only the build/deploy pipeline's exit status was checked, not visual output.

## 4. Test suite status

This repo has no test suite of its own to run — it's integration-only. The source repos'
test suites were run in their own checkouts (see `MLB Analytics/HANDOFF.md` and
`WNBA Analytics/HANDOFF.md` for what, where, and the actual pass/fail output).

## 5. Environment/tooling notes

- **`core.autocrlf` is `true`** here (checked this session) — files check out with **CRLF**.
  `MLB Analytics`'s own checkout has `core.autocrlf=false` (LF). This is a real, confirmed
  per-repo config difference (no `.gitattributes` anywhere to normalize it), and it makes any
  raw `md5sum`/byte-diff comparison between `front-office-aggregator/mlb/*` and a direct
  `MLB Analytics` checkout **report false mismatches** on every line-ending-sensitive file.
  Always strip `\r` (`tr -d '\r'`) before comparing content across these two checkouts. This
  session burned real time chasing what looked like a failed subtree sync before finding this.
- **This working directory is shared with at least one other concurrent session/agent.** Mid-task,
  `git stash` reported success but a `Permission denied` on removing an empty directory
  (`mlb/web/public/data/archive/`) left the working tree still dirty after the stash claimed to
  have cleaned it — and separately, `git checkout main` was confirmed to succeed, but by the time
  the next command ran, `HEAD` had moved back to a different local branch
  (`fix/offseason-team-attribution-and-test-baseline`) that another process had apparently
  checked out and committed to (`d93ad7f`, a real, legitimate commit — not corruption, just a
  genuine race). A `git subtree pull` run immediately after an unverified `checkout` landed on
  the wrong branch as a result, producing a stray local merge commit. **Caught before pushing**
  by comparing local branch tips against their remote-tracking refs (`git log -1 --format=%H
  <branch>` vs `origin/<branch>`) — nothing leaked to any remote. Recovery was a plain
  `git reset --hard origin/<branch>` on the contaminated local branch, which is safe specifically
  *because* nothing had been pushed yet.
  **Lesson for next time**: after any `git checkout`, re-confirm `git branch --show-current`
  immediately before the next git command that assumes a specific branch — don't trust the
  `checkout` command's own "Switched to branch" output as still valid several commands later in
  this checkout.
- Directory lock errors here may be transient (the `archive/` permission-denied resolved itself
  within about a minute, with no other action taken) — don't assume a locked/undeletable empty
  directory means another process is actively writing files inside it; it may just be a brief
  AV-scan or filesystem-indexer hold.
- Remote names in this checkout: `origin` = `front-office` itself; `mlb-origin`, `wnba-origin`,
  `nba-origin`, `nfl-origin` = the four per-sport source repos (see §1 table). Don't confuse
  `origin` here with a sport-specific remote when scripting subtree commands.

## 6. The reusable workflow (merge-order-dependent PR pairs + subtree sync)

This is the exact sequence this session followed, written out because it has a real ordering
dependency and a real failure mode if skipped:

1. **Verify both PRs are `OPEN` and `MERGEABLE`** before touching anything:
   `gh pr view <N> --repo <owner>/<repo> --json state,mergeable,mergeStateStatus`. If either
   isn't clean, stop — don't try to resolve a conflict yourself; report it.
2. **Merge the aggregator-side PR first, the source-repo PR second**, if the same logical fix
   exists as two independent PRs in both repos. Reason: if the source-repo PR lands first and a
   scheduled subtree-pull fires before the aggregator PR merges, the subtree pull delivers the
   same content through the normal sync path and the aggregator PR becomes a redundant/conflicting
   diff against content that's already there. `gh pr merge <N> --repo <owner>/<repo> --squash` —
   no `--admin`, `--rebase`, or `--auto`; no direct push to `main` either side.
3. **Do not run `git subtree pull` or trigger "Sync sport subtrees and deploy" between the two
   merges.** Only after both are confirmed merged.
4. **Before running `git subtree pull`, confirm you're actually on `main` and the tree is clean**
   — `git branch --show-current` *and* `git status --short`, both checked again immediately
   before the pull, not trusted from an earlier command in the same session (§5's race condition).
5. **`git fetch origin main` and diff `main..origin/main` before every push** in this checkout —
   it has moved underneath this session more than once from unrelated automation.
6. **After `git subtree pull`, verify content agreement with `\r`-stripped hashing, not raw
   `md5sum`**, if comparing against a direct checkout of the source repo (§5).
7. **Push, then poll `gh run list --workflow "Build and deploy GitHub Pages" --json
   status,headSha` for the pushed commit's SHA until `status == completed`** — don't assume a
   push triggers an instant, already-finished deploy; it takes roughly 1–2 minutes.

If a merge conflict appears during `git subtree pull` or a `git pull` on `main` (this session hit
one, resolving a leftover dead-code tail in a file both sides had independently edited): read
both sides of the conflict before resolving — in this session's case the upstream side was simply
stale (an older version of a function this session had already rewritten), so the correct
resolution was keeping the local/HEAD side, not a textual merge of both.

## 7. Concrete next step

Nothing is in flight. If someone picks this up:

- **Before running any further subtree pulls**, re-read §5's branch-race warning and §6 step 4 —
  this checkout has demonstrably had its `HEAD` moved by something else mid-session before.
- **If the next task is another PR-pair merge**, follow §6 exactly; it's a proven sequence, not
  a one-off.
- **If asked to verify cross-repo content parity again**, use `\r`-stripped hashing from the
  start — don't re-discover the CRLF gotcha the slow way.
- **The "Sync sport subtrees and deploy" workflow was never actually triggered or inspected** this
  session (deliberately, per task constraints). If a future task needs to understand what it
  automates, that's genuinely unverified territory — don't assume it behaves like the manual
  sequence in §6 without checking its actual workflow YAML.
