# MLB Analytics — Handoff Document

**Last updated**: 2026-10-17, after commit `e8291cd` ("Add Phase 0d research: specialty baseball
models", 7 commits total on `main`). **`main` is 1 commit ahead of `origin/main`, not pushed** —
check `git status` before assuming the remote matches; don't push without checking with whoever's
driving, per standard git-safety practice. Written for whoever picks this repo up next, cold — read
this before touching anything.

## What this project is

`MLB Analytics` is a brand-new sibling to an existing family of sports-analytics repos
(`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`),
each later port built on a shared R architecture (`config.R` single-source-of-truth constants,
`run_full_pipeline.R` staged DAG, Elo/ridge rating engines, fatigue/market/risk/notify stages,
Discord dispatch). **None of that architecture exists in this repo yet.** This repo is currently
in **Phase 0: research only** — the stage every sibling port went through first, producing a
`docs/<SPORT>_REPLICATION_PLAN.md` live-verified research document before any engine code gets
written.

**Read in this order**:
1. `docs/PHASE0_RESEARCH_PLAN.md` (committed `4eeaa49`) — the scoping plan for the Phase 0 research
   itself. This is a plan *about* the research, not the research. It defines what six sections the
   eventual deliverable must cover, what "done" looks like, and explicit non-goals. Its "Execution
   approach" section says this research should be done directly in the main session, not delegated
   to subagents — **that approach was superseded partway through**: in practice, each sub-issue
   (#2–#7) has been worked as an independent delegated subagent run (see "The reusable workflow"
   below), one research file per issue under `docs/research/`, because the dependency graph the plan
   itself describes (§2 feeds §3–§5, §3 feeds §6) turned out to decompose cleanly along the GitHub
   sub-issue boundaries once #2/#3 were done and committed. Don't be confused that the plan document
   says one thing and the actual workflow did another — the sub-issues are the source of truth for
   current process, not the plan's "Execution approach" section.
2. `docs/MLB_REPLICATION_PLAN.md` — **still does not exist.** This is the actual research deliverable
   `PHASE0_RESEARCH_PLAN.md` describes producing. It is assembled from the per-issue files in
   `docs/research/` as issue #8 (Wave D), not yet started. Don't search for it as if it should be
   there yet.
3. `docs/research/phase0a-r-packages.md`, `phase0a-vendor-api.md`, `phase0b-team-player-stats.md`,
   `phase0c-elo-methodology.md`, `phase0d-specialty-models.md`, `phase0e-structural-divergences.md`
   — **all six per-issue research files are now complete** (issues #2, #3, #4, #5, #6, #7
   respectively; see Progress tracking below). Read these instead of re-deriving their findings —
   each one's own "Sources Consulted" section has the URLs and fetch dates.
4. `../NFL Analytics/docs/NFL_REPLICATION_PLAN.md` — the structural template this repo's eventual
   `MLB_REPLICATION_PLAN.md` should mirror (6 sections: porting strategy/failure modes, data-source
   decision table, stats worth surfacing, Elo methodology, specialty models, structural divergences;
   closed out with a dated "Sources Consulted" list). Read this for shape, not for baseball-specific
   content — none of its NFL-specific facts transfer.

**Hard boundary rule carried over from every sibling repo**: nothing in this Phase 0 stage writes
`config.R`, `run_full_pipeline.R`, or any engine script. No credentials or vendor signups either.
This is strictly a research/documentation phase — see "Non-goals" in both `PHASE0_RESEARCH_PLAN.md`
and the epic issue (#1, below).

## Progress tracking

All tracking lives in the GitHub issue tracker (`kailot-harris/MLB-Analytics`), using real native
GitHub sub-issue and blocked-by/blocking relationships. Re-run `gh issue list --state all` yourself
before trusting this table — this is a repo that gets worked by more than one concurrent
session/agent (confirmed this session: #4, #5, and #7 landed on `main` from other sessions while
this session was still working #6), so staleness can happen fast.

| Issue | Title | Status | Blocked by | Evidence |
|---|---|---|---|---|
| #1 | Epic: Phase 0 research plan | OPEN | — | — |
| #2 | Phase 0a: R-package ecosystem verification | **CLOSED** | none | `docs/research/phase0a-r-packages.md`; commit `1105811` |
| #3 | Phase 0a: Direct vendor/API verification | **CLOSED** | none | `docs/research/phase0a-vendor-api.md`; commit `1105811` |
| #4 | Phase 0b: Team/player statistics research | **CLOSED** | #2, #3 | `docs/research/phase0b-team-player-stats.md`; commit `96acad1`; closing comment has full summary |
| #5 | Phase 0c: Baseball Elo methodology research | **CLOSED** | #2, #3 | `docs/research/phase0c-elo-methodology.md`; commit `0822baa`; closing comment has full summary |
| #6 | Phase 0d: Specialty model research + ML citation | **CLOSED** | #2, #3 | `docs/research/phase0d-specialty-models.md`; commit `e8291cd`; closing comment has full summary — **includes an explicitly unresolved gap, see below** |
| #7 | Phase 0e: Structural divergences research | **CLOSED** | #4 | `docs/research/phase0e-structural-divergences.md`; commit `bc47ebd`; closing comment has full summary |
| #8 | Phase 0f: Draft `docs/MLB_REPLICATION_PLAN.md` | OPEN, **next up — now unblocked** | #2,#3,#4,#5,#6,#7 (all closed) | not started |
| #9 | Phase 0g: Self-check pass | OPEN | #8 | — |
| #10 | Phase 0h: Present deliverable / close Phase 0 | OPEN | #9 | — |

**Tracker-hygiene discrepancy, flagged not fixed**: issue #1's own body has a `- [ ]` checklist for
sub-issues #2–#10. None of those checkboxes are ticked even though #2–#7 are now all closed. This is
stale tracker bookkeeping on the epic issue itself, not a sign the work isn't done — trust the
sub-issues' own `state` field (via `gh issue list --state all`) over issue #1's checklist. Decide
whether to update it; this doc isn't the place to silently fix it.

**Issue #6's hard requirement came up empty, documented not fabricated**: its spec required finding
a real, peer-reviewed, MLB-specific citation comparing an ML model (RF/GBM/NN) against a Pythagorean
baseline with real MAE/RMSE/R². After a documented 8+-candidate search (table in
`docs/research/phase0d-specialty-models.md` §5), **no qualifying citation exists in the publicly
indexed literature as of the 2026-10-17 fetch date** — flagged prominently in the file itself with
the full search trail (what was checked and why each candidate was disqualified), so a future
session doesn't repeat the same dead ends. If issue #8's `docs/MLB_REPLICATION_PLAN.md` needs this
citation, it will need either a deeper/different search or an explicit decision to publish without
one.

**Issue #6 took two dispatch attempts this session** (run IDs `20261017-233137-8975bb` then
`20261017-233424-5ea53c` in `.subagent-runs/`, both recorded via the `subagent-brief` skill's
`runlog.R`): the first hit the worktree-deletion bug described below before writing anything and is
logged `status: blocked`; the second completed cleanly (`status: success`, `review: merged`) and
produced the file now on `main`. If you see any note elsewhere (including an earlier revision of
this very doc, written mid-session by a concurrent agent) describing the second run as
"abandoned/orphaned with no result recorded" — that was true only transiently, before the result was
recorded; `.subagent-runs/20261017-233424-5ea53c/meta.json` is the authoritative record and shows
`success`/`merged`.

## What's actually implemented

**Still nothing but documentation and tracker scaffolding — no engine code.** Current file state
(`wc -l` on everything under `docs/`, 2026-10-17):

| File | Lines | State |
|---|---|---|
| `docs/PHASE0_RESEARCH_PLAN.md` | 159 | The Phase 0 scoping plan. Its "Execution approach" section is stale (see above) — everything else in it is still the live source of truth for what each section must cover. |
| `docs/HANDOFF.md` | this file | Updated this session. |
| `docs/research/phase0a-r-packages.md` | 71 | Done (issue #2). `baseballr`/`Lahman`/`pitchRx`/`mlbgameday`/`mlbplotR`/`retrosheet` maintenance-status table. Flags `pitchRx` and `mlbgameday` as CRAN-archived traps; flags `baseballr`'s Baseball-Reference/ESPN-backed functions as broken (HTTP 403/500) despite the package overall being actively maintained. |
| `docs/research/phase0a-vendor-api.md` | 45 | Done (issue #3). MLB Stats API, Baseball Savant, FanGraphs ToS, ESPN injuries feed, The Odds API. |
| `docs/research/phase0b-team-player-stats.md` | 77 | Done (issue #4). Pythagenpat exponent, run differential, wOBA/wRC+, FIP/xFIP (SIERA unconfirmed as a `baseballr` column), BABIP, fWAR-vs-bWAR (documented as non-interchangeable; no confirmed `baseballr` path to bWAR), Statcast leading indicators. |
| `docs/research/phase0c-elo-methodology.md` | 193 | Done (issue #5, this session). FiveThirtyEight's MLB Elo methodology cited from an **archived** primary source (live URL now 301s to `abcnews.com/politics`) plus 538's live GitHub `mlb-elo` README. Starting-pitcher adjustment formula `ratingAdj = 4.7 * (pitcher_rGS − team_rGS)` confirmed verbatim against the primary source. Park factors confirmed as a named, designed-in input; exact park-factor coefficients flagged as an open gap, not fabricated. |
| `docs/research/phase0d-specialty-models.md` | 261 | Done (issue #6). Marcel's exact weighting scheme (5/4/3 recency, 1200 PA regression, piecewise age formula, from Tango's own archived write-up), PECOTA as closed-methodology precedent only, bullpen fatigue with an explicit NFL-short-week mechanistic-vs-spiritual distinction, two real peer-reviewed Bayesian partial-pooling papers. **The hard-requirement ML-vs-Pythagorean citation search came up empty, flagged prominently in §5 — see above, don't drop that caveat downstream.** |
| `docs/research/phase0e-structural-divergences.md` | 205 | Done (issue #7). 162-game season / rolling-window coupling to #4's Pythagorean exponent, universal DH history, Manfred-man extra-innings rule (confirmed permanent Feb 2023, regular-season only), 2026 postseason bracket shape, roster-size rules. |

No `config.R`. No `run_full_pipeline.R`. No `.R` files of any kind. No `renv.lock`, no `.Rprofile`.
No repo-local `.claude/skills/` (the `subagent-brief` skill used this session lives globally at
`C:\Users\kailo\.claude\skills\subagent-brief`, not in this repo). `main` is at commit `e8291cd`,
**1 commit ahead of `origin/main` (not yet pushed)** — `docs/HANDOFF.md` itself is also currently
modified-but-uncommitted (this update), by explicit instruction not to commit or push it.

## Environment/tooling notes

- **Remote already configured**: `origin` = `https://github.com/kailot-harris/MLB-Analytics` (both
  fetch/push). `main` tracks `origin/main` but is currently 1 commit ahead, unpushed — see above.
- **A `.git/` folder already existed in this directory before the first session's first commit** —
  flagged historically, never root-caused, hasn't mattered since; mentioning once more only so a
  future `git log` surprise (history predating `4eeaa49`) isn't alarming.
- **`gh` CLI, authenticated as `kailot-harris`** (`repo`, `workflow`, `read:org`, `gist` scopes — no
  `project` scope, so no GitHub Project board; sub-issue linking doesn't need it). `--parent`,
  `--blocked-by`, `--blocking` on `gh issue create` work and create real native sub-issue/dependency
  relationships (verify via `gh api repos/.../issues/<N>/sub_issues`), not just body text.
  **`gh issue close` can no-op with "already closed"** if the merged commit's message contained
  `Closes #N` and had already been pushed — GitHub auto-closes on push to the default branch. If that
  happens, use `gh issue comment` instead to attach the evidence comment; don't treat the no-op as an
  error.
- **Label set**: `phase-0` (color `5319e7`) tags this research wave; otherwise only GitHub's defaults.
- **No R environment of any kind set up** — no package installs, no `renv` bootstrap. Not needed yet;
  Phase 0 is research/documentation only.
- **`.subagent-runs/` is git-ignored** (`/.subagent-runs/` in `.gitignore`) and holds every delegated
  run's brief/meta/result this session, per the `subagent-brief` skill's protocol. Useful for
  reconstructing what happened to a specific issue attempt (see issue #6 note above) — check
  `meta.json`'s `status` field and, if present, `result.json`'s `blocked_reason`/`needed_action`.
- **Known reproducible platform bug, hit at least twice this session**: an `Agent` call with
  `isolation: "worktree"` can have its worktree directory deleted by something external to the agent
  while the agent is still actively working (confirmed via `git worktree list` showing no trace, not
  even a prunable stale entry — i.e. something ran a clean `git worktree remove`, not a crash). Hit on
  the first attempts at both issue #5 (run `20261017-232930-b254f0`) and issue #6 (run
  `20261017-233137-8975bb`). The affected agent correctly stops and returns `status: "blocked"` rather
  than improvising — the fix each time was simply dispatching a fresh run with a new worktree, not
  resuming the dead one. Filed as product feedback (not actionable from inside this repo); if it keeps
  happening, that's worth a fresh feedback note rather than assuming it's fixed.
- **A completed `isolation: "worktree"` agent's worktree can outlive its `git worktree` registration**:
  after a run finishes, `git worktree list` may show the worktree already gone (merged/removed
  cleanly) while the directory under `.claude/worktrees/agent-<id>/` and its file contents are still
  physically present on disk, now sharing the main repo's own `.git` (i.e. `git -C` commands inside it
  report "On branch main"). Treat it as a plain directory to copy the new file(s) out of, not as a
  live git worktree to `git -C ... diff`/`merge` against — `git worktree list` is the source of truth
  for what's actually still registered.
- **An untracked, empty `.claude/worktrees/` directory is present at repo root** as of this
  writing — a leftover from a worktree that was torn down cleanly after merging (the directory
  itself just wasn't cleaned up by that teardown). Harmless, not gitignored, not tracked; safe to
  delete, or add to `.gitignore` alongside the existing `/.subagent-runs/` entry if it keeps
  recurring.
- **This session's final commit (`e8291cd`) was deliberately not pushed**, per explicit
  instruction not to commit-or-push beyond that point. Don't assume `origin/main` reflects it.

## The reusable workflow (for working any Phase 0 sub-issue)

This is the pattern used for issues #2 through #7 (all now closed) and the one to adapt for #8
(synthesis), per step 7 below:

1. Confirm the issue is actually unblocked (`gh issue view <N>` → check `blocked-by`) before starting.
2. Use the globally-installed `subagent-brief` skill (`C:\Users\kailo\.claude\skills\subagent-brief`)
   to write a `full` template brief: goal = the issue's own research questions verbatim, scope = read
   the already-closed prerequisite issues' research files + write exactly one new
   `docs/research/phase0X-<topic>.md` file, out-of-scope = touching `docs/MLB_REPLICATION_PLAN.md`
   (doesn't exist yet) and touching GitHub issues (the orchestrator handles that after review), tiers
   = 0–1 only (no GitHub/network-state-changing actions granted to the subagent). Validate with
   `validate_brief.R`, register with `runlog.R new-run --worktree ...`.
3. Dispatch via the `Agent` tool with `isolation: "worktree"`, pasting the registered brief verbatim
   into the prompt, telling the subagent its final message must be the JSON result block per the
   brief's Output schema.
4. On completion, **verify before trusting**: re-run or re-check at least one of the subagent's cited
   claims yourself (e.g. this session independently `curl`'d the FiveThirtyEight methodology URL to
   confirm the claimed 301 redirect before merging issue #5's file). Record the result with
   `runlog.R record-result` (evidence `type` must be one of `file_ref`/`command`/`test_output`/
   `diff`/`other` — not `file`, that's a schema validation error worth knowing about in advance).
5. If the run came back `blocked` (e.g. the worktree-deletion bug above), don't retry the same
   subagent — register a **new** run with an amended brief (carry forward whatever partial findings
   the blocked run reported, as a lead to re-verify, not as citable fact) and dispatch fresh. Mark the
   dead run `rejected` via `runlog.R set-status`.
6. If the run succeeded, copy the new file out of the worktree into the real tree (see the "outlive
   its registration" note above if `git worktree list` no longer shows it), `git add` + commit with
   `Closes #N` in the commit body, `git push`. Note: pushing with `Closes #N` auto-closes the issue —
   use `gh issue comment` (not `gh issue close`) to attach the evidence-bearing comment afterward.
7. Issue #8 will need a different shape than steps 2–6 above: it's a single synthesis task reading
   all of `docs/research/phase0*.md` and assembling them into one `docs/MLB_REPLICATION_PLAN.md`
   following the NFL plan's 6-section structure — probably still worth a `full`-template brief and a
   worktree, but its "Scope" should explicitly list all six research files as required reading rather
   than naming prerequisite-issue files generically.

No divergences from a reference implementation to document yet — there's no engine code, so this
section is empty by construction, not by oversight.

## Concrete next step

**All of #2–#7 are closed as of commit `e8291cd`. Issue #8 — draft `docs/MLB_REPLICATION_PLAN.md`
— is unblocked and is the real next milestone.** Per issue #8's own body (`gh issue view 8 --json
body --jq .body`):

- Synthesize all six `docs/research/phase0*.md` files into one document, structured on
  `../NFL Analytics/docs/NFL_REPLICATION_PLAN.md`'s 6-section template: (1) porting
  strategy/failure modes, (2) data-source decision table (R-package subsection from #2 + vendor/API
  subsection from #3), (3) team/player statistics (#4), (4) Elo methodology (#5), (5) specialty
  models (#6), (6) structural divergences (#7).
- Every factual claim needs its inline fetch date carried forward from the source file, plus a
  closing "Sources Consulted" section aggregating all six files' source tables with real URLs, and
  a closing "Summary Judgment" paragraph naming MLB's biggest risk/divergence relative to the prior
  sibling ports (candidates already surfaced: the starting-pitcher Elo adjustment with no sibling
  analog from #5; the four-independent-ID-scheme problem named in issue #1's own framing, worse
  than NFL's four; or the still-unresolved ML-vs-baseline citation gap from #6 — **don't drop this
  caveat silently during assembly, it needs an explicit decision, not a quiet omission**).
- This is single-document synthesis, not new live research — the six input files already did the
  research. Shouldn't need new WebSearch/WebFetch calls except to double-check a specific citation
  if something looks stale during assembly. Per step 7 of the workflow above, still probably worth
  a `full`-template `subagent-brief` dispatch and its own worktree, with "Scope" explicitly listing
  all six research files as required reading.
- **Two steps out**: #9 (self-check pass — confirm no section in the assembled plan smuggles in a
  final numeric constant instead of "needs empirical re-derivation," confirm every claim has a dated
  source) and #10 (present the deliverable to the user, close Phase 0 — also the point to force a
  decision on the open ML-citation gap rather than let it linger unresolved). Both are still fully
  unstarted.
