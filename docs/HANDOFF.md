# MLB Analytics — Handoff Document

**Last updated**: 2026-10-17, after commit `4eeaa49` (the repo's only commit so far). Written for
whoever picks this repo up next, cold — read this before touching anything.

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
   eventual deliverable must cover, what "done" looks like, and explicit non-goals.
2. `docs/MLB_REPLICATION_PLAN.md` — **does not exist yet.** This is the actual research deliverable
   `PHASE0_RESEARCH_PLAN.md` describes producing. Don't assume it exists or search for it as if it
   should be there — it's the end product of the GitHub issue tracker's Wave D (see below), not yet
   started.
3. `../NFL Analytics/docs/NFL_REPLICATION_PLAN.md` — the structural template this repo's eventual
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
GitHub sub-issue and blocked-by/blocking relationships (not just prose) — confirmed this session via
`gh api repos/kailot-harris/MLB-Analytics/issues/1/sub_issues`, which returned `[2,3,4,5,6,7,8,9,10]`.
**Cross-checked live via `gh issue list --state all` at the time of writing — all 10 issues are
`OPEN`, zero closed, zero work started on any of them.** Don't trust this table once work begins;
re-run that command rather than assuming it's still accurate.

| Issue | Title | Status | Blocked by |
|---|---|---|---|
| #1 | Epic: Phase 0 research plan | OPEN | — |
| #2 | Phase 0a: R-package ecosystem verification | OPEN, **next up** | none |
| #3 | Phase 0a: Direct vendor/API verification | OPEN, **next up** | none |
| #4 | Phase 0b: Team/player statistics research | OPEN | #2, #3 |
| #5 | Phase 0c: Baseball Elo methodology research | OPEN | #2, #3 |
| #6 | Phase 0d: Specialty model research + ML citation | OPEN | #2, #3 |
| #7 | Phase 0e: Structural divergences research | OPEN | #4 |
| #8 | Phase 0f: Draft `docs/MLB_REPLICATION_PLAN.md` | OPEN | #2,#3,#4,#5,#6,#7 |
| #9 | Phase 0g: Self-check pass | OPEN | #8 |
| #10 | Phase 0h: Present deliverable / close Phase 0 | OPEN | #9 |

Full research questions and required outputs for each issue are in the issue body itself, not
repeated here — read the issue, not just this table.

## What's actually implemented

**Nothing but documentation and tracker scaffolding.** The entire repo content, verified via
`find . -not -path "./.git*" -type f`:

| File | State |
|---|---|
| `docs/PHASE0_RESEARCH_PLAN.md` | Real, 159 lines. The Phase 0 scoping plan (see above) — contains no live-verified baseball research itself, only the questions that research must answer. |

No `config.R`. No `run_full_pipeline.R`. No `.R` files of any kind. No `renv.lock`. No
`.claude/skills/`. `git log --oneline` shows exactly one commit (`4eeaa49`, "Add Phase 0 research
plan for MLB Analytics"). `git status` is clean, `main` is pushed and tracks `origin/main`.

## Environment/tooling notes

- **Remote already configured**: `origin` = `https://github.com/kailot-harris/MLB-Analytics` (both
  fetch/push). `main` is pushed and tracking `origin/main` as of `4eeaa49`.
- **A `.git/` folder already existed in this directory before this session's first commit** —
  empty (no commits, no index) despite an environment reminder that session having stated "Is a git
  repository: false." Not root-caused; this session just used the existing repo (ran `git add`/
  `commit`/`push`, not `git init`) rather than investigating further. Flagging in case it matters
  later — if `git log` ever shows history predating `4eeaa49` that nobody expects, this is why to
  check first.
- **`gh` CLI 2.100.0, authenticated as `kailot-harris`** (`repo`, `workflow`, `read:org`, `gist`
  scopes — `project` scope NOT present, so issues were not added to a GitHub Project board; sub-issue
  linking does not require it). Confirmed this session that `--parent`, `--blocked-by`, and
  `--blocking` flags on `gh issue create` work on this version and actually create native GitHub
  sub-issue/dependency relationships (verifiable via `gh api .../issues/<N>/sub_issues`), not just
  text in the body.
- **Label set**: repo only had GitHub's default labels (`bug`, `documentation`, etc.) before this
  session. Added `phase-0` (color `5319e7`) to tag this research wave; no other custom labels exist.
- **No R environment of any kind set up** — no package installs attempted, no `renv` bootstrap. Not
  needed yet since Phase 0 is research/documentation only.

## The reusable workflow (for working any Phase 0 sub-issue)

This is the pattern to repeat for issues #2 through #7 (the live-research issues):

1. Read the GitHub issue body in full — each one lists its own specific research questions and
   required output shape (e.g. a decision table with named columns).
2. Research live via WebSearch/WebFetch. **Every factual claim needs a fetch date and a real
   source URL** — this document type exists specifically to avoid porting stale/memorized
   assumptions (see `PHASE0_RESEARCH_PLAN.md`'s own framing, itself borrowed from the NFL plan's
   explicit "verified live on 2026-09-16" discipline). Do not write a number or claim from training
   data without an inline citation.
2a. Respect the dependency graph before starting: #2 and #3 are unblocked and can be done in either
    order or in parallel; #4/#5/#6 need #2 and #3 finished first (they ask "which R
    package/API sources this stat/rating," which only #2/#3 can answer); #7 additionally needs #4
    finished (the rolling-window-sizing question in #7 depends on the Pythagorean-exponent framing
    from #4).
3. Write findings directly into the relevant section of `docs/MLB_REPLICATION_PLAN.md` — this file
   doesn't exist yet; issue #8 (Wave D) is technically "create it," but in practice each research
   issue's own findings should be drafted as that section's content when the issue is worked, not
   held until #8 and reconstructed from issue comments. (#8 is then more "assemble and buff the six
   sections into one coherent document" than "write it from scratch.")
4. Close the GitHub sub-issue with the evidence (fetch dates, URLs, key findings) in the closing
   comment — mirrors the sibling NFL/WNBA repos' own convention of evidence-bearing issue-closing
   comments rather than a bare commit message.
5. Commit whatever was added to `docs/MLB_REPLICATION_PLAN.md` referencing the issue (e.g.
   `Closes #2` in the commit body) — but only commit when asked, per standard git-safety practice;
   this session created issues but did not yet write or commit any research content.

No divergences from a reference implementation to document yet — there's no code, so this section
is empty by construction, not by oversight.

## Concrete next step

**Start Wave A: issues #2 and #3, in either order or in parallel** (both are unblocked):

- **#2 — R-package ecosystem verification.** Live-verify current CRAN/GitHub maintenance status and
  function inventory for `baseballr`, `Lahman`, `pitchRx`/`mlbgameday`, `mlbplotR`, and any
  Retrosheet-adjacent R package distinct from `baseballr`'s own wrapper. Output a table (package →
  function(s) → data need → coverage window → maintenance status), explicitly flagging any
  CRAN-archived/orphaned package found as a trap — parallel to how the NFL plan flagged nflfastR's
  deprecated `fast_scraper_*()` functions in favor of `nflreadr`.
- **#3 — Direct vendor/API verification.** Live-verify MLB Stats API, Baseball Savant, FanGraphs ToS,
  the ESPN injuries feed's athlete-ID quirk (confirm or deny it matches the already-documented
  NFL/WNBA/NBA pattern), and The Odds API's MLB sport key/player-prop market-key conventions.

Once both land, issues #4 (team/player stats), #5 (Elo methodology), and #6 (specialty models +
required ML-vs-baseline citation) all unblock and can proceed in parallel. Two steps further out:
#7 (structural divergences, needs #4 first) and then #8 — actually drafting
`docs/MLB_REPLICATION_PLAN.md` itself as a single coherent document, which is the real Phase 0
deliverable nobody has started yet.
