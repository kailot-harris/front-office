# MLB Analytics — Handoff Document

**Last updated**: 2026-10-18, after commit `237d1cb` ("Phase 0g: self-check pass on
MLB_REPLICATION_PLAN.md"). **`main` is up to date with `origin/main`** (confirmed via `git fetch` +
`git status -sb` this session — unlike the previous revision of this doc, there is no unpushed
commit right now). However, **the working tree is not clean**: `docs/MLB_IMPLEMENTATION_PLAN.md` is
a real, finished deliverable sitting **uncommitted** at repo root (see "What's actually implemented"
below) — written and left uncommitted deliberately, per explicit instruction this session not to
commit. Don't assume `git log` alone reflects everything written; check `git status` too. Written
for whoever picks this repo up next, cold — read this before touching anything.

## What this project is

`MLB Analytics` is a brand-new sibling to an existing family of sports-analytics repos
(`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`),
each later port built on a shared R architecture (`config.R` single-source-of-truth constants,
`run_full_pipeline.R` staged DAG, Elo/ridge rating engines, fatigue/market/risk/notify stages,
Discord dispatch). **None of that architecture exists in this repo yet — still zero `.R` files of
any kind.** Phase 0 (research-only) is now **functionally complete** (six research files + the
synthesized replication plan + its self-check pass all exist and are committed/pushed), but its
tracker issue (#10, "present deliverable / close Phase 0") is **still open** — see "Progress
tracking" below for why that matters and hasn't just been closed outright.

**Read in this order**:
1. `docs/PHASE0_RESEARCH_PLAN.md` (committed `4eeaa49`) — the scoping plan for the Phase 0 research
   itself. Its "Execution approach" section is stale (says research should happen directly in the
   main session; in practice #2–#7 were each worked as independent delegated subagent runs via the
   `subagent-brief` skill) — everything else in it is still live.
2. `docs/MLB_REPLICATION_PLAN.md` (530 lines, committed `1a495e9`, self-check-amended `237d1cb`) —
   **the actual Phase 0 deliverable, now complete.** Synthesizes all six `docs/research/phase0*.md`
   files into the NFL plan's 6-section template, with a closing Summary Judgment naming MLB's single
   biggest risk (the starting-pitcher Elo mechanism + four-ID-scheme fragmentation, compounded) and
   the unresolved ML-vs-Pythagorean-baseline citation gap carried forward explicitly, not dropped.
   Every numeric constant in it is flagged "needs empirical re-derivation" — **do not copy a number
   out of this document into a future `config.R` and treat it as final.**
3. `docs/MLB_IMPLEMENTATION_PLAN.md` (314 lines, **written this session, not yet committed** — see
   header warning above) — the Phase 1–9 engine-build roadmap that picks up where
   `MLB_REPLICATION_PLAN.md` leaves off. Read this before starting any engine-build work; it cites
   back to specific `MLB_REPLICATION_PLAN.md` sections per phase and explicitly flags which phases
   are new builds (no sibling analog — the starting-pitcher Elo layer, the ID-crosswalk utility)
   versus straight ports (risk engine, market odds engine, Discord dispatcher).
4. `docs/research/phase0a-r-packages.md`, `phase0a-vendor-api.md`, `phase0b-team-player-stats.md`,
   `phase0c-elo-methodology.md`, `phase0d-specialty-models.md`, `phase0e-structural-divergences.md`
   — the six per-issue research files `MLB_REPLICATION_PLAN.md` was assembled from. Read these for
   primary evidence/sources if `MLB_REPLICATION_PLAN.md`'s own citations need re-verifying; each
   file's own "Sources Consulted" section has the URLs and fetch dates.
5. `../NFL Analytics/docs/NFL_REPLICATION_PLAN.md` and `../NFL Analytics/docs/task_assignments_phase*.md`
   — the structural templates `MLB_REPLICATION_PLAN.md` and `MLB_IMPLEMENTATION_PLAN.md` mirror.
   Read for shape/convention (6-section research template; phase-numbered task-assignment docs with
   wave/interface-contract breakdowns), not for baseball-specific content — none of the NFL-specific
   facts transfer.

**Hard boundary rule, now split by phase**: Phase 0 (issues #1–#10) wrote no `config.R`,
`run_full_pipeline.R`, or any engine script, and that rule held for the entire phase. **Phase 1
onward (issues #11–#24, tracked as a separate epic) is explicitly scoped to write that code** — but
as of this writing, **no Phase 1+ work has actually started**; #11–#24 are tracker scaffolding only
(see below), not yet dispatched. No credentials or vendor signups have happened in either phase.

## Progress tracking

All tracking lives in the GitHub issue tracker (`kailot-harris/MLB-Analytics`), using real native
GitHub sub-issue and blocked-by/blocking relationships. Re-run `gh issue list --state all` yourself
before trusting this table — this repo gets worked by more than one concurrent session/agent
(confirmed again this session: issue #9 was closed by a concurrent session while this session was
between tasks), so staleness can happen fast.

### Phase 0 (research) — functionally complete, tracker not fully closed

| Issue | Title | Status | Blocked by | Evidence |
|---|---|---|---|---|
| #1 | Epic: Phase 0 research plan | **OPEN** | — | Stale: its own `- [ ]` checklist for #2–#10 has zero boxes ticked even though #2–#9 are closed. Flagged, not fixed — see below. |
| #2 | Phase 0a: R-package ecosystem verification | CLOSED | none | `docs/research/phase0a-r-packages.md`; commit `1105811` |
| #3 | Phase 0a: Direct vendor/API verification | CLOSED | none | `docs/research/phase0a-vendor-api.md`; commit `1105811` |
| #4 | Phase 0b: Team/player statistics research | CLOSED | #2, #3 | `docs/research/phase0b-team-player-stats.md`; commit `96acad1` |
| #5 | Phase 0c: Baseball Elo methodology research | CLOSED | #2, #3 | `docs/research/phase0c-elo-methodology.md`; commit `0822baa` |
| #6 | Phase 0d: Specialty model research + ML citation | CLOSED | #2, #3 | `docs/research/phase0d-specialty-models.md`; commit `e8291cd` — **includes the explicitly unresolved ML-citation gap, carried forward through #8 and #9, see below** |
| #7 | Phase 0e: Structural divergences research | CLOSED | #4 | `docs/research/phase0e-structural-divergences.md`; commit `bc47ebd` |
| #8 | Phase 0f: Draft `docs/MLB_REPLICATION_PLAN.md` | CLOSED | #2–#7 | `docs/MLB_REPLICATION_PLAN.md`; commit `1a495e9`; evidence comment at `gh issue view 8 --comments` has the full independent-verification trail (headers, URL aggregation, fetch-date carryover, re-derivation caveats all spot-checked before merge) |
| #9 | Phase 0g: Self-check pass | **CLOSED** | #8 | `docs/MLB_REPLICATION_PLAN.md` (amended in place); commit `237d1cb`; closed by a **concurrent session** this repo was sharing mid-session — closed 2 of 7 checklist items that the assembly pass had left open (live re-verified 2 citations; added a consolidated "Explicit Non-Goals" section) |
| #10 | Phase 0h: Present deliverable / close Phase 0 | **OPEN, deliverable already presented, not yet confirmed-closed** | #9 (closed) | The plan was presented to the user in conversation this session (structure, Summary Judgment, self-check results all walked through) — but the user has not yet explicitly said "close it," and whoever picks this up should get that explicit go-ahead before closing #10 and #1, not infer it from the plan simply existing. |

**Tracker-hygiene discrepancy on #1, still not fixed**: flagged in the previous revision of this
doc and still true — issue #1's own body has a `- [ ]` checklist for #2–#10, none ticked despite
#2–#9 being closed. Decide whether to fix this when #10 actually closes (closing #10 is a natural
point to also tick #1's boxes and close #1 itself) — this doc isn't the place to silently fix it.

**The ML-vs-Pythagorean-baseline citation gap (from #6) is still open by design, and has now
survived three downstream passes without being dropped or fabricated**: #6's own research
(`phase0d-specialty-models.md` §5) found no qualifying peer-reviewed MLB citation after an
8-candidate search; #8's assembly carried the gap forward into `MLB_REPLICATION_PLAN.md` §5 and its
Summary Judgment; #9's self-check explicitly verified it was carried forward correctly, not
backfilled with a disqualified candidate. If this gap is ever resolved, `MLB_REPLICATION_PLAN.md` §5
names the most promising unexplored avenue (a *Journal of Quantitative Analysis in Sports* /
*Journal of Sports Analytics* database search not available in this research environment).

### Phase 1–9 (engine build) — epic + tracker scaffolding filed this session, **zero work started**

Filed this session as a new epic, separate from Phase 0's epic (#1), because Phase 0's epic was
scoped specifically to the research deliverable, not the build that follows it. All real GitHub
sub-issue (`--parent`) and dependency (`--blocked-by`) relationships, verified via
`gh api repos/.../issues/<N>/sub_issues` — not just prose nesting.

| Issue | Title | Status | Blocked by | Parallel with |
|---|---|---|---|---|
| #11 | Epic: MLB Analytics engine build (Phases 1-9) | OPEN | #10 (informally — not a real GitHub block, since #10 was still open when this epic was filed; treat #10's closure as a prerequisite in spirit) | — |
| #12 | Phase 1: Data foundation | OPEN | none | #20 (Phase 5) once both start |
| #13 | Phase 1, Wave 1: Ingestion scripts + ID-crosswalk utility | OPEN | none | internally parallel (4 disjoint files — see issue body) |
| #14 | Phase 1, Wave 2: Pipeline skeleton | OPEN | #13 | — |
| #15 | Phase 2: Rating engine (Pythagorean + Elo) | OPEN | #12 | — |
| #16 | Phase 2, Wave 1: Pythagorean baseline + Elo engine | OPEN | #12 | internally parallel (2 disjoint files) |
| #17 | Phase 2, Wave 2: Constant derivation + park-factor decision | OPEN | #16 | — |
| #18 | Phase 3: Specialty models (Marcel, bullpen fatigue) | OPEN | #15 | #19 (Phase 4) |
| #19 | Phase 4: Postseason bracket simulator | OPEN | #15 | #18 (Phase 3) |
| #20 | Phase 5: Risk management engine (port) | OPEN | #12 | #15–#19 (Phases 2–4) |
| #21 | Phase 6: Market odds engine (port) | OPEN | #12, #15 | — |
| #22 | Phase 7: Discord alert dispatcher (port) | OPEN | #21 | — |
| #23 | Phase 8: Early-season calibration review (decision point, not guaranteed build) | OPEN | #15 | — |
| #24 | Phase 9+: Deferred/idea-stage placeholder | OPEN | #12,#15,#18–#23 | — |

**None of #12–#24 have had any code written against them yet** — this is purely the tracked roadmap
from `docs/MLB_IMPLEMENTATION_PLAN.md`, filed as real issues so the parallelism is visible in the
tracker, not just in the planning doc. The `engine-build` label (color `0e8a16`) tags all of #11–#24.

## What's actually implemented

**Still nothing but documentation and tracker scaffolding — no engine code.** Current file state
(`wc -l`, 2026-10-18):

| File | Lines | State |
|---|---|---|
| `docs/PHASE0_RESEARCH_PLAN.md` | 159 | Phase 0 scoping plan. Committed, stable. |
| `docs/MLB_REPLICATION_PLAN.md` | 530 | **Phase 0's finished deliverable.** Committed (`1a495e9`, amended `237d1cb`). All 8 sections present (6 body + Summary Judgment + Sources Consulted), plus a consolidated Explicit Non-Goals section added by #9. |
| `docs/MLB_IMPLEMENTATION_PLAN.md` | 314 | **Phase 1–9 engine-build roadmap. Written this session. Untracked/uncommitted — `git status` shows it as `??`, by explicit instruction not to commit this session.** Covers all 9 phases with per-phase goal/source/deliverables/port-vs-new-build/carried-forward-open-items. |
| `docs/research/phase0a-r-packages.md` | 71 | Done (#2). |
| `docs/research/phase0a-vendor-api.md` | 45 | Done (#3). |
| `docs/research/phase0b-team-player-stats.md` | 77 | Done (#4). |
| `docs/research/phase0c-elo-methodology.md` | 193 | Done (#5). |
| `docs/research/phase0d-specialty-models.md` | 261 | Done (#6). Contains the unresolved ML-citation gap, see above. |
| `docs/research/phase0e-structural-divergences.md` | 205 | Done (#7). |
| `docs/HANDOFF.md` | this file | Rewritten this session. |

No `config.R`. No `run_full_pipeline.R`. No `.R` files of any kind. No `renv.lock`, no `.Rprofile`.
No repo-local `.claude/skills/` (the `subagent-brief` skill used this session lives globally at
`C:\Users\kailo\.claude\skills\subagent-brief`, not in this repo).

## Environment/tooling notes

- **Remote**: `origin` = `https://github.com/kailot-harris/MLB-Analytics`. `main` is in sync with
  `origin/main` as of this writing (`git fetch` + `git status -sb` both confirmed this session) —
  this is a change from the previous revision of this doc, which warned main was 1 commit ahead and
  unpushed. That commit has since been pushed (and more added on top). **Re-check before trusting
  this** — the uncommitted `docs/MLB_IMPLEMENTATION_PLAN.md` means `origin/main` is currently
  *missing* a real, finished file that only exists locally.
- **Leftover artifacts from this session, not cleaned up, safe to review/remove but left for the
  next session to decide**:
  - `brief-issue9.md` (repo root, untracked) — a `subagent-brief`-style prep brief for issue #9,
    written by a concurrent session before #9 was picked up. **#9 is now closed** (by that same or
    another concurrent session), so this file's content is now historical, not actionable. Its own
    annotations (e.g. the "six packages not five" checklist-miscount catch, the exact citation-gap
    verification requirement) were evidently used, since #9's closing comment matches its guidance —
    but the file itself was never committed or deleted. Decide whether to delete it or fold any
    still-useful annotations into this doc.
  - `.claude/worktrees/agent-a06e217ce87e8b5c2/` — the isolated worktree used to dispatch issue #8's
    synthesis subagent. Still registered (`git worktree list` shows it `locked`, pointing at commit
    `28fc320`), even though its one deliverable file was already copied out to the main tree and
    committed. Per the `subagent-brief` skill's own protocol, removing a kept/registered worktree
    needs explicit user confirmation (`cleanup_worktrees.R remove --confirmed-by-user`) — not done
    this session, flagged for whoever has that conversation with the user next.
  - `.subagent-runs/` (git-ignored, per `/.subagent-runs/` in `.gitignore`) now holds 9 run
    directories (`20261017-231637-dc2250` through `20261018-000017-64cd0b`) plus a `batches/`
    directory and a loose `brief-issue6.md`. Each run's `meta.json`/`result.json` is the authoritative
    record of what that dispatch actually did — check `status` and, if present, `blocked_reason`
    before trusting any narrative summary (including this doc's) about what happened in a given run.
    Run `Rscript C:/Users/kailo/.claude/skills/subagent-brief/scripts/check_storage.R` at the start of
    a future session if this directory keeps growing — it wasn't checked this session.
- **`gh` CLI, authenticated as `kailot-harris`** (`repo`, `workflow`, `read:org`, `gist` scopes — no
  `project` scope). `--parent`, `--blocked-by`, `--blocking` on `gh issue create` all confirmed
  working this session for the #11–#24 engine-build tracker (verified via
  `gh api repos/.../issues/<N>/sub_issues`), same as the Phase 0 tracker.
- **Label set**: `phase-0` (color `5319e7`, Phase 0 research) and, new this session, `engine-build`
  (color `0e8a16`, Phase 1–9 engine build) — otherwise only GitHub's defaults.
- **No R environment of any kind set up** — no package installs, no `renv` bootstrap. This will
  actually block Phase 1 (#12/#13) the moment real ingestion code needs to run/test against live
  `baseballr`/MLB Stats API calls — budget time for an `renv` bootstrap as part of (or immediately
  before) Phase 1, Wave 1, since no prior session has done this yet in this repo.
- **Known reproducible platform bug** (carried forward from the previous revision of this doc, not
  re-triggered this session but still worth knowing): an `Agent` call with `isolation: "worktree"`
  can have its worktree directory deleted by something external to the agent while the agent is
  still working, confirmed on two separate Phase 0 runs. The fix each time was dispatching a fresh
  run with a new worktree, not resuming the dead one. Filed as product feedback previously; if it
  recurs, that's worth a fresh feedback note.

## The reusable workflow

### For any single-file Phase 0-style research/synthesis task (proven across #2–#9)
1. Confirm the issue is actually unblocked (`gh issue view <N>` → check `blocked-by`).
2. Write a `subagent-brief` `full`-template brief (goal = issue's own research questions verbatim,
   scope = prerequisite files + exactly one new output file, out-of-scope = touching the tracker or
   unrelated docs, tiers = 0–1 only). Validate with `validate_brief.R`, register with
   `runlog.R new-run --worktree ...`.
3. Dispatch via `Agent` with `isolation: "worktree"`, pasting the registered brief verbatim.
4. **Verify before trusting**: independently re-check at least one cited claim yourself before
   merging — this session re-verified issue #8's subagent-reported header list, URL-aggregation
   count, and re-derivation-caveat line numbers directly against the worktree file before copying it
   out, rather than taking the subagent's self-report at face value. Record the result with
   `runlog.R record-result` (evidence `type` must be `file_ref`/`command`/`test_output`/`diff`/
   `other`, not `file` — and the result JSON needs top-level `schema_version`, `item_id`,
   `summary`, `evidence` array, `blocked_reason`, `needed_action`, and `changes` fields or
   `record-result` fails schema validation — this tripped this session on the first attempt for
   issue #8's result; see `.subagent-runs/20261018-000017-64cd0b/result-raw.json` for a working
   example of the full shape).
5. Copy the new file out of the worktree into the real tree, `git add` + commit with `Closes #N`,
   `git push`. `gh issue close` can no-op ("already closed") if the push already auto-closed it via
   the commit body — use `gh issue comment` to attach the evidence comment instead of erroring.

### For filing a multi-phase tracker (new this session, used for #11–#24)
1. Write the full roadmap as a planning doc first (`docs/MLB_IMPLEMENTATION_PLAN.md`) — decide the
   phase breakdown, dependency graph, and which phases have internally-parallelizable waves *before*
   touching the issue tracker, so the issue bodies can cite a stable source document rather than
   being drafted from scratch per-issue.
2. Create a label for the new epic's issues if none fits (`engine-build`, this session).
3. Create the epic issue first, then each phase issue with `--parent <epic>` and `--blocked-by
   <prereq-phase>`, then each wave issue (where a phase has multiple sequential/parallel waves) with
   `--parent <phase>` and `--blocked-by <prior-wave-or-phase>`.
4. Verify the hierarchy landed as real links, not just issue-body prose: `gh api
   repos/.../issues/<epic>/sub_issues` should list every phase number; repeat per phase for its
   waves. This session did this for #11, #12, #15, and #14's `blocked-by` edge — all confirmed
   correct.
5. **Do not dispatch any Phase 1+ subagent work yet** — #11–#24 are tracker scaffolding only as of
   this writing. When Phase 1 Wave 1 (#13) actually starts, follow the single-task workflow above
   per task, or write a `docs/task_assignments_phase1.md`-style file first (per the NFL-repo
   convention cited in `MLB_IMPLEMENTATION_PLAN.md`'s own "How to use this document" section) if the
   wave's four parallel tasks need tighter interface-contract coordination than one `subagent-brief`
   per task provides.

## Concrete next step

**Two independent next steps, pick based on what the user wants first:**

1. **Close out Phase 0 (issue #10, then #1)** — the deliverable has already been presented to the
   user in this session's conversation (structure, Summary Judgment, self-check results). The only
   remaining action is getting the user's explicit confirmation to close, then: `gh issue close 10`
   (or comment if a push auto-closed it some other way), fix #1's stale checklist, `gh issue close 1`.
   **Do not do this without that explicit confirmation** — it was deliberately left pending this
   session, not forgotten.
2. **Start Phase 1, Wave 1 (issue #13)** — the first real engine-build work: four parallel,
   file-disjoint scripts (`mlb_ingest.R`, `mlb_stats_sync.R`, `mlb_injury_scraper.R`,
   `mlb_id_crosswalk.R`) plus `config.R`. Needs an `renv` bootstrap first (none exists in this repo
   yet — see Environment notes above). Source of requirements: `MLB_IMPLEMENTATION_PLAN.md` Phase 1
   and issue #13's own body (already has the full per-file task table and interface-contract
   convention spelled out). **Two steps out**: Wave 2 (#14, pipeline skeleton) is blocked by Wave 1
   and depends on Wave 1's exposed function signatures being finalized first — don't start #14's
   dispatch until Wave 1's four scripts' signatures are locked, per the Interface Contracts
   convention in the sibling repos' own Phase 1 history.

Also unresolved and worth deciding alongside either step above: `docs/MLB_IMPLEMENTATION_PLAN.md`
is still uncommitted. It's a finished, reviewed deliverable, not a draft — commit it (separately
from any Phase 0 closing-out commit, since it belongs to the Phase 1–9 epic, not Phase 0) once
someone actually wants it on `main`.
