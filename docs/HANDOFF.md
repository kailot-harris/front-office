# Handoff — 2026-10-18 (Next.js web app, Phase 0: plan + scaffold) — CURRENT STATE FOR THIS THREAD (read this section first, for whoever picks this up next)

## What this thread did

User asked to review progress on a sibling project, `C:\Users\kailo\kayceeslices\NBA Analytics`,
which has a `web/` subfolder (Next.js 14 App Router + React 18 + TypeScript + Tailwind, static
JSON data layer — no backend/DB) presenting that repo's Monte Carlo season-simulation outputs,
and plan + start porting equivalent functionality into this repo. Surveyed the NBA app's routes
(`web/components/Sidebar.tsx`, `web/app/*`) and its own `WEB_APP_SURVEY.md`, then cross-checked
against this repo's existing engines (`rapm_engine.R`, `player_props_engine.R`,
`playoff_simulator.R`, `load_embeddings.R`/`team_embeddings.py`, `projected_wnba_standings.rds`)
to see what's portable now vs. what needs new R engines first.

Wrote the phased plan to `docs/NEXTJS_WEB_APP_PLAN.md` (commit `7a40498`), then executed Phase 0
of that plan: scaffolded `web/` with `create-next-app@14.2.35` (`--typescript --tailwind --eslint
--app --no-src-dir --import-alias "@/*"`), added `geist`/`lucide-react` to match the NBA app's
`package.json`, ported its `next.config.mjs` (ESPN CDN `remotePatterns`), `tailwind.config.ts`,
and dark slate/indigo theme, and wrote a WNBA-rebranded `Sidebar.tsx` and a placeholder `page.tsx`
(commit `a3c293a`). Verified with `npm run build` (clean compile, 2 static routes) before
committing; deleted the `.next/` build output afterward since it's gitignored. Both commits
pushed to `main`.

## What's actually implemented (new/changed this session)

| File | State |
|---|---|
| `docs/NEXTJS_WEB_APP_PLAN.md` | New, ~50 lines. Records Phase 0 (scaffold, done) through Phase 3 (net-new R engines: shots, offseason, coaching, defense, player-dna, CBA/cap-sheet, clutch — not started) and two explicit open questions (WNBA cap-sheet applicability, shot-location data availability) that block starting Phase 3. |
| `web/` (new top-level folder, Next.js 14 project) | Scaffold only — **no data layer, no real pages**. `web/app/page.tsx` (16 lines) is a static placeholder explaining the scaffold state, not a real standings page. `web/components/Sidebar.tsx` (207 lines) has 5 working nav links (`/`, `/variants`, `/players`, `/series`, `/diagnostics`) that currently 404 except `/` — those routes don't exist yet, that's Phase 1. A "Planned (Phase 3)" list in the sidebar is plain text, not links. `web/app/layout.tsx` (35 lines), `web/tailwind.config.ts` (23 lines), `web/next.config.mjs` (14 lines) are direct ports of the NBA app's versions, re-branded. No `lib/data.ts`, no `lib/types.ts`, no `public/data/*.json` — those are Phase 1 (the `export_web_json.R` pipeline stage). |
| `run_full_pipeline.R` / `pipeline_stages.R` | **Unchanged.** No new pipeline stage registered yet — Phase 1 work, not started. |

## Anomalies noticed while gathering state for this handoff — flagged, not fixed

Nothing new. Re-checked the same things the 2026-10-17 entry below flagged and found no change:
tracker still shows `#43`/`#44`/`#49`/`#71` open (`gh issue list --state open`, re-run this
session), and the same four orphaned worktree-shaped directories are still present under
`.claude/worktrees/` (`agent-a46276a0f4609d125`, `agent-a55aa191aa09f4d54`,
`agent-ae227d715064d6d37`, `bracket-rounds-fix`) — `git worktree list` still only shows `main`.

## Concrete next step

Phase 1 of `docs/NEXTJS_WEB_APP_PLAN.md`: add `export_web_json.R` as a new pipeline stage
(register it in `pipeline_stages.R`, wire it via `run_registered_stage()` after the
standings/RAPM/props/embeddings stages it reads from), writing JSON into `web/public/data/`
from `cache/projected_wnba_standings.rds`, `cache/rapm_ratings.rds`, `cache/latest_player_props.rds`,
and `data/team_embeddings.csv`. Then add `web/lib/data.ts` (`fs.readFileSync` + `JSON.parse`
pattern, copy NBA's `web/lib/data.ts`) and `web/lib/types.ts`, and replace the placeholder
`web/app/page.tsx` with a real Standings page (port of NBA's `StandingsClient.tsx`, 15 teams not
30). Validate by running `npm run build` again and spot-checking the rendered page locally
(`npm run dev`) before moving to `/variants`/`/players`/`/diagnostics`. Phase 2 (playoff
`/series` page from `cache/playoff_bracket_results_*.rds`) and Phase 3 (net-new R engines) come
after — see the plan doc for the open questions to resolve before starting Phase 3.

---

# Handoff — 2026-10-17 (renv library repair + full pipeline rerun) — superseded by the entry above; kept for its Open Items/environment notes, which are still live

## What this thread did

User asked to rerun the pipeline. `Rscript.exe run_full_pipeline.R` failed immediately at the
`risk_management_engine.R` stage with `Error in library(duckdb) : there is no package called
'duckdb'`, plus a `renv` warning that ~30+ other packages (`bslib`, `cli`, `DBI`, `digest`,
`fs`, `evaluate`, etc.) were "missing their DESCRIPTION files" — the project's `renv` library on
this machine was corrupted again (a prior, different occurrence of this same failure shape is
already documented below in "Closed work" and in the environment notes). Ran
`renv::restore(prompt = FALSE)` (via a temp `tools/tmp_renv_restore.R`, since inline multi-line
`-e` segfaults on this machine — see environment notes; the temp file was deleted after use, not
left in the repo). It completed with exit code 0 and reinstalled the broken packages. Reran
`run_full_pipeline.R`, which then completed cleanly in **38.06 seconds**, all stages reporting
`[FRESH]`/`[COMPLETED]`, ending with the playoff simulator, risk-state audit, Discord bet-alert
dispatch, and bet-grading/CLV stages all succeeding and writing fresh caches.

**This was a from-scratch `renv::restore()` against an already-populated-but-broken library**,
not a brand-new clean library — so it does not fully close "Open items" #5 below (nobody has
yet restored into a genuinely empty library from this `renv.lock`), but it is a second
confirmation that `restore()` against *this* lockfile reliably repairs a corrupted library in
one pass, on top of the 2026-10-06 incident referenced below.

## What's actually implemented (new/changed this session)

Nothing — this was an environment-repair + pipeline-rerun session, no source files were
changed. No new commits were made. `git status` still shows only the same shape of
pipeline-refreshed cache/data files as dirty (`cache/*.rds`, `data/box_scores_cache.rds`,
`data/team_embeddings.csv`, `data/team_similarity_matrix.csv`) — these are expected working-tree
diffs from any pipeline run, not evidence of a code change, and were left uncommitted per normal
git-safety convention (only commit when asked).

## Anomalies noticed while gathering state for this handoff — flagged, not fixed

- **Two commits landed since the last HANDOFF entry below with no corresponding HANDOFF update**:
  `e08e5d6` ("add round labels to historical playoff bracket data (issue #69 follow-up)") and
  `00ee515` ("backfill 2019-2022 historical standings/RAPM, 2022 playoff bracket"), both from a
  different session (`Claude-Session: .../session_01D5QKdxbPb1ZNwFnJp3PEpb`, not this thread's
  session). Read `git show <hash>` directly if you need their detail; summarizing here only
  enough to flag the gap: `00ee515` extends `tools/generate_historical_season_snapshots.R` from
  2023-2025 back to 2019-2025, adding `cache/actual_wnba_standings_{2019..2022}.rds`,
  `cache/rapm_ratings_{2019..2022}.rds`, and `cache/playoff_bracket_results_2022.rds` — but
  **2019-2021 have no bracket file**, documented in that commit's own message as a deliberate
  limitation (the old bye-based playoff format breaks `assign_bracket_rounds()`'s chronological
  reconstruction), not a bug to fix.
- **Issues #69 and #70 are now `CLOSED`** on the tracker (confirmed via `gh issue view`), resolving
  the tracker-hygiene item the previous HANDOFF top section used to flag as open. Someone did this
  outside any session reflected in this file.
- **A new issue, `#71`, is open and unaddressed**: "RAPM: ORAPM/DRAPM are highly correlated
  (0.77), suppressing Total RAPM for every star player (e.g. A'Ja Wilson nets to 0.64)" — a real
  methodology issue in `rapm_engine.R`'s possession-level ridge fit per its own description, not
  a display/join bug. Nobody has started on it in any session reflected in this file.
- **A fourth orphaned worktree-shaped directory has appeared**: `.claude/worktrees/bracket-rounds-fix`
  (in addition to the three already tracked in "Open items" #4 below). Like the other three, `git
  worktree list` does not register it (only `main` shows). Not investigated further or removed
  this session — folded into the existing open item rather than duplicating it.

## Concrete next step

1. Nothing is currently broken or blocking — the pipeline runs clean end to end as of this
   session. The next unit of work is whichever "Open items" entry below is highest priority; #71
   (the RAPM ORAPM/DRAPM correlation bug) is the newest and most concrete, since it has a detailed
   ticket already filed and affects every star player's displayed rating.
2. If `renv` breaks again on this machine, the fix is the same one-liner used this session:
   write `renv::restore(prompt = FALSE)` to a temp `.R` file (never inline `-e`, see environment
   notes) and run it with the full `Rscript.exe` path before retrying the pipeline.

---

# Handoff — 2026-10-07 (New thread: isolated `summary_app.R` into a standalone sibling directory, `C:\Users\kailo\kayceeslices\wnba_summary_app_deploy`, for publishing to shinyapps.io — **no files in this repo were touched**, this is a pure read-and-copy operation from this repo's perspective) — superseded by the entry above; kept for the standing risk/procedure it introduced

This thread never edited any file in this repo — it isolated `summary_app.R` into a standalone sibling directory, `C:\Users\kailo\kayceeslices\wnba_summary_app_deploy` (outside this repo, dependency set confirmed by grepping every `source()`/`readRDS()`/`read.csv()`/`library()`/`::` call: `config.R`, `rapm_join_utils.R`, 8 cache/data files, 15 team logos), renamed `summary_app.R` → `app.R`, verified it loads standalone with no cache-fallback triggered, and found it already deployed to shinyapps.io (`https://kailot-harris.shinyapps.io/wnba_summary_app_deploy/`, appId `18119397`) from a separate action outside this thread. Full narrative moved to `docs/archive/handoff_history.md`; what's still live and relevant is the standing risk below.

## ⚠️ Standing risk — read before editing `summary_app.R`

**There is now a second, disconnected copy of `summary_app.R`'s logic living outside this repo, with no automated sync.** Any future change to this repo's `summary_app.R` — a new tab, a bug fix, a new cache dependency, a renamed `config.R` constant — will **not** propagate to the deployed shinyapps.io app unless someone manually repeats the copy-and-redeploy procedure below. There is currently no CI, no git submodule, no symlink, and no script in this repo that does this automatically.

**Procedure to update the sibling deploy after a change lands here:**
1. Diff this repo's `summary_app.R` against the sibling's `app.R` (they should be identical except for the filename) to see what changed.
2. Re-grep the new version of `summary_app.R` for `source()`/`readRDS()`/`read.csv()`/`library()`/`::` calls — don't assume the 8-cache-file/15-logo/2-sourced-script manifest above is still complete; a new tab could add a new cache file, a new sourced helper, or a new package.
3. Copy this repo's updated `summary_app.R` over the sibling's `app.R` (keep the rename), and copy any newly-required cache/data/logo/script files into the sibling's matching subfolders.
4. Re-run the local load test described in "What this thread did" item 4 (fresh `setwd()` + `source("app.R")` from inside the sibling directory, confirm no cache-not-found fallback messages and a clean `shiny.appobj` return) before redeploying — this is the only validation performed so far; nobody has done a live browser click-through of the actually-deployed instance yet (see the sibling's own `HANDOFF.md` for that still-open item).
5. From R: `rsconnect::deployApp("C:/Users/kailo/kayceeslices/wnba_summary_app_deploy")`. The existing `.dcf` record means this updates the live app in place rather than creating a new shinyapps.io slug.

**If this sync needs to happen more than once or twice**, the better fix is a small script in this repo (e.g. `tools/sync_summary_app_deploy.R`) that automates steps 1–3 against a fixed file list, rather than redoing this by hand every time — nobody has built that yet; it's a reasonable candidate for a future ticket if `summary_app.R` keeps changing after shinyapps.io publication. Full validation/next-step narrative for this thread is in `docs/archive/handoff_history.md`'s 2026-10-07 section.

---

## Closed work (archived 2026-10-07)

Everything below this point used to be ~2,475 lines of session-by-session postmortems for work
that is now either fully shipped or superseded by a later session's own summary of the same work.
Moved verbatim to `docs/archive/handoff_history.md` (appended after that file's existing
2026-09-26 archive batch, with its own preamble) during this trim — read that file only if you
need the detailed narrative (bug bisections, live-validation transcripts, design-interview
rationale) behind one of the rows below, not to determine current state.

| Closed-work session (original heading, abbreviated) | Result |
|---|---|
| Tab 6 min-possessions filter (ad hoc, no ticket) | Shipped — **commit `153c9de`**. The archived section itself still says "uncommitted, not pushed"; that framing is stale as of this trim, the code is in `main`. |
| Tab 6 "Player Ratings (RAPM)" end to end (SA-6a/b/c, #66/#67/#68) | Shipped — merged `82c1ca6`/`1b66152`/`b36c1af`, all 3 issues closed on the tracker. |
| Tab 6 spec interview + ticket filing | Superseded by the row above (spec → shipped). |
| `renv` library repopulation + lockfile fix | Shipped — committed `9894265`. `shinyjs` now a real top-level lockfile entry; ~29 other packages' pinned versions corrected. |
| Issue #49 (Slice 5: shared render helpers) implementation + worktree cleanup | Shipped — merged `e5c97f3`, pushed. **Issue tracker still shows #49 open** — see "Open items" below. |
| 28-commit push backlog + tracker cleanup (14 issues closed) + Tab 1 dark-mode support | Shipped — pushed `4b70058`. 14 issues closed; #43/#44/#49 deliberately left open pending #49 (then #49 itself shipped in the row above, but was never closed — see "Open items"). |
| Dunks & Threes visual pass (6 tickets, #60-65) + entire control-panel/auth tree (#43-54 minus #49) | Shipped — merged `13919fc`, issues #60-65/#46-48/#50-54 all code-complete (tracker never reconciled, see "Open items"). |
| Dunks & Threes spec interview + ticket filing | Superseded by the row above (spec → shipped). |
| `summary_app.R`: logos, Tab 5 collapsible log, win-projection dot-and-whisker chart | Shipped — pushed `888d75c`. |
| `summary_app.R` SA-1 through SA-5 (issues #55-#59) | Shipped — all merged. |
| `summary_app.R` initial spec (static-snapshot summary app) | Superseded by the row above (spec → shipped). |
| `tools/series_length_predictor.R` (standalone playoff series-length predictor) | Shipped. |
| Pipeline rerun / Round 1 resolution / renv restore root-cause fix | Shipped (historical renv incident, distinct from the 2026-10-06 lockfile fix above). |
| 2026 season accuracy review + postseason predictions `.qmd`, incl. a 3rd renv-corruption occurrence | Shipped (historical renv incident). |
| Scheduled-pipeline failure (`.bat` syntax bug + renv repair + error-visibility logging) | Shipped. |
| Interactive control-panel app spec interview (2026-09-26) | Superseded by the control-panel/auth row above (spec → shipped). |
| Isolated `summary_app.R` into standalone sibling deploy dir + shinyapps.io publish | Shipped (no repo files touched). Standing risk/re-sync procedure kept live above, full narrative archived. |
| Issue #69 Standings + Bracket pilot (2023-2025, later backfilled to 2019-2022 and given round labels in undocumented follow-up commits `e08e5d6`/`00ee515` — see 2026-10-17 entry above) | Shipped and **tracker-closed** (confirmed via `gh issue view 69` on 2026-10-17). |
| Issue #70 RAPM third of #69 (season-pooled 2023-2025 RAPM snapshots) | Shipped — committed/merged `5d7711f`, independently re-verified, and **tracker-closed** (confirmed via `gh issue view 70` on 2026-10-17). |
| `renv` library corruption, 2nd documented occurrence (missing `duckdb` + ~30 packages' DESCRIPTION files, blocking `run_full_pipeline.R`) | Repaired via `renv::restore(prompt = FALSE)` on 2026-10-17 (see current top section). Not a from-scratch clean-library restore — "Open items" #5 below is still open. |

## Open items (standing, unreconciled — last cross-checked live via `gh issue list --state open` / `gh issue view` on 2026-10-17)

These have been flagged by **every** session that touched this area since they first appeared and remain genuinely open — not rediscovered this trim, just consolidated into one place instead of being repeated in full in every archived section:

1. **GitHub issue tracker is partially stale**: `#43`, `#44`, `#49` still show `OPEN` (re-confirmed 2026-10-17), but #49's code was merged in `e5c97f3` and #43/#44 (parent epics of #49) have no remaining work blocking them beyond that. (`#69`/`#70` were in this same bucket as of 2026-10-08 but are now confirmed `CLOSED` as of 2026-10-17 — that part of this item is resolved.) Nobody has run `gh issue close` on #43/#44/#49. Closing them is a visible tracker action — do it once confirmed, don't just trust this note.
1a. **New issue `#71` (filed 2026-10-09, still open as of 2026-10-17)**: RAPM's `ORAPM`/`DRAPM` are highly correlated (0.77) in `rapm_engine.R`'s possession-level ridge fit, which suppresses `total_rapm` for every star player (e.g. A'Ja Wilson nets to 0.64 despite elite `orapm`/`drapm` individually). Read the full ticket (`gh issue view 71`) before starting — it's a real methodology issue in the ridge fit itself, not a display or join bug, and has no implementation started in any session reflected in this file.
2. **`dashboard_render_helpers.R` does not contain `.normalize_value_bets_dates()`**, so `control_panel_app.R` still carries its own byte-for-byte duplicate of `app.R`'s `r_normalized_value_bets()` reactive logic (deriving `norm_date` on `cache/latest_value_bets.rds`, including the staggered-placeholder-date fallback for thin/demo slates). Recommended fix (never built): hoist into a plain function in `dashboard_render_helpers.R` and have both `app.R` and `control_panel_app.R` call it from there.
2a. **Three headless probes never got a login step added**: `tools/headless_control_panel_probe.R`, `tools/headless_control_panel_staleness_probe.R`, `tools/headless_control_panel_queue_lock_probe.R` all predate the control-panel's real auth wall (added in the #43/#44 tree) and will fail against every element they try to drive, since none of them log in first. `tools/headless_login_module_probe.R`'s `set_module_input()` pattern is the one to copy. Not updated in any session since the auth wall landed.
4. **Four leftover worktree-shaped directories now, not three** (`.claude/worktrees/agent-ae227d715064d6d37`, pre-existing; `.claude/worktrees/agent-a46276a0f4609d125`, added by a prior session's `subagent-brief` dispatch for issue #69 whose `git worktree remove` failed with an OS-level file lock; `.claude/worktrees/agent-a55aa191aa09f4d54`, added by a later #70 dispatch with the same failure shape; and `.claude/worktrees/bracket-rounds-fix`, noticed new as of 2026-10-17 — not yet attributed to a specific session, not investigated beyond confirming `git worktree list` doesn't register it either). None of the four are registered with git any more (`.git/worktrees/` has no entry for any of them — orphaned directories, not real worktrees), all still safe to leave in place rather than force-deleting. `.claude/worktrees/` is still not in `.gitignore`. Re-check before assuming any of this is still true — this count has grown every session that's dispatched a writer subagent on this machine, suggesting the OS-level lock issue is systemic to this environment rather than a one-off, and may be worth a real fix (e.g. a short delay/retry around `git worktree remove`, or an explicit `tools/cleanup_orphaned_worktrees.R`) rather than re-flagging it every session.
5. **Nobody has run a from-scratch `renv::restore()`** against the fixed `renv.lock` (post-`9894265`) on a clean library to confirm it restores in one pass — the 2026-10-06 session only ever repaired *this machine's* already-populated-but-broken library incrementally.

## Standing environment/tooling notes (still live, condensed from archived sessions)

- R is not on `PATH` on this machine — use the full path `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`.
- Inline multi-line `Rscript -e "..."` segfaults on this machine — always write to a temp `.R` file and run `Rscript.exe <path>.R` instead.
- `here::here()` (used by `config.R` for `PROJECT_DIR`) falls back silently to `getwd()` when no `.git`/project marker exists in a directory's ancestry — confirmed empirically this session from a bare folder with no `.git`.
- `shinytest2::AppDriver` (real headless Chrome) works on this machine as of the most recent session that exercised it (two full `tools/headless_dashboard_probe.R` runs during the #49 implementation) — a prior session's report of it being "unusable system-wide" was concurrent multi-session memory pressure, not a lasting environment problem. If it fails again, check free memory / other active Claude sessions on this machine before assuming a regression.
- `shiny::testServer()` is a better *first* verification tool than a live browser for reactive-logic claims on this repo's Shiny apps (in-process, deterministic, much faster) — reserve real `AppDriver` browser checks for actual DOM/CSS rendering or multi-tab-alive-simultaneously timing, which `testServer()` cannot simulate correctly (a session's `onSessionEnded()` fires when its `testServer()` block returns, not at some independently-controllable moment).
- A git worktree's `renv` library is often *not* pre-populated even with a correct `renv.lock` — run `renv::restore(prompt = FALSE)` once per fresh worktree before trusting a `library()` failure to mean a real missing dependency.
- `renv::install()` has a reproducible bug in its dependency-graph resolver (`renv_graph_install` → `vapply(downloadable, ...)`) on batches containing certain packages (seen for `curl`/`data.table`/`glmnet`/`lubridate`/`magrittr`/`processx`/`RcppArmadillo`/`stringi`/`systemfonts`/`xml2`/`diffobj`). Workaround: `Rscript.exe --no-init-file <script>.R` (skips `.Rprofile`, so `renv`'s `install.packages()` shim never loads) + direct `utils::install.packages(..., dependencies = NA)` into the project library path.
- `fastshap` and `vip` are archived off live CRAN (as of 2026) but both still install cleanly from `https://cran.r-project.org/src/contrib/Archive/<pkg>/<pkg>_<version>.tar.gz` with this machine's Rtools.
- Writing a `subagent-brief` result JSON by hand: Windows paths need forward slashes or doubled backslashes (a literal single-backslash Windows path is invalid JSON and makes `runlog.R record-result` fail with an unhelpful parse error); result files should live under this repo's own tracked directories, not `/tmp/...`, since Windows-native `Rscript.exe` doesn't reliably resolve MSYS `/tmp` mounts.
- Agent-tool `isolation: "worktree"` dispatches have, at least once, branched from a *stale* snapshot of `main` taken at session start rather than `main`'s live tip at actual dispatch time, within the same long-running session — if a dispatched subagent reports a precondition file is missing that you know is already merged, suspect this before suspecting the brief.
- The `subagent-brief` skill's scripts (`runlog.R`, `validate_brief.R`, etc.) live under the **user's home directory** (`C:\Users\kailo\.claude\skills\subagent-brief\scripts\`), not under this repo's own `.claude/skills/` (which only holds this repo's own project-scoped skills, e.g. `config-constant-drift-audit`). Calling them with a relative path like `.claude/skills/subagent-brief/scripts/runlog.R` resolves to a nonexistent file in *this* repo and reproducibly **segfaults** `Rscript.exe` (exit code 139 in Git Bash / `-1073741819` in PowerShell) rather than failing with a normal "file not found" error — don't mistake that segfault for the already-documented inline-`-e` segfault issue; always invoke this skill's scripts by their full home-directory path.
- `runlog.R record-result` validates against `schema/result.v1.json`, which requires top-level `schema_version`, `item_id`, `summary`, `evidence` (a separate array of `{id, type, ref, excerpt}` objects, not inline per-criterion text), `blocked_reason`, `needed_action`, and `changes: {worktree, files_changed}` — a result JSON built only from the brief template's minimal per-criterion `{id, met, evidence}` shape (no top-level `evidence` array, no `changes`) fails schema validation. Read `schema/result.v<N>.json` directly before hand-writing a result file rather than inferring the shape from the brief template's "Output schema" section alone.

## Concrete next step (beyond the top "CURRENT STATE" section's own next step, and the sibling-deploy sync duty above)

Nothing is currently blocking — `main` is clean-running (pipeline verified end to end on
2026-10-17) and #69/#70's tracker hygiene is already resolved. Pick from "Open items" above
based on priority:
1. **Issue #71** (RAPM `ORAPM`/`DRAPM` correlation suppressing `total_rapm` for star players) is
   the newest, most concrete, and has real user-visible impact (wrong-looking ratings in the
   Shiny app) — read the full ticket before starting.
2. Tracker hygiene (`gh issue close` for #43/#44/#49) is the cheapest, lowest-risk one to clear.
3. The `.normalize_value_bets_dates()` de-duplication is the only one with real drift risk (two copies of non-trivial logic that can silently diverge — this repo has been bitten by exactly this shape of bug before, per `CLAUDE.md`'s `CONN`/`CON` and RAPM-join notes).
4. The three stale headless probes and the four leftover worktree-shaped directories are low-urgency cleanup, worth bundling into whatever session next touches `control_panel_app.R` or `.claude/worktrees/` for an unrelated reason — though the worktree-cleanup failure recurring across multiple dispatches (see Open items #4) is starting to look worth a real fix rather than more cleanup.
