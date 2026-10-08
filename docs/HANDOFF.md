# Handoff — 2026-10-08 (Issue #69: Standings + Bracket pilot shipped via subagent-brief dispatch; RAPM third of #69 spec'd via a Y/N design interview and filed as sub-issue #70, not yet implemented) — CURRENT STATE FOR THIS THREAD (read this section first, for whoever picks this up next)

## What this thread did

1. **Issue #69** ("Generate real historical per-season Standings/Bracket/RAPM data (2023-2025 pilot)") asked for three artifact types from existing raw data. Split RAPM out immediately (see point 3) because it hits a real design conflict in `rapm_engine.R`; Standings + Bracket were dispatched as a single `subagent-brief`-governed subagent task, run in its own git worktree.
2. **Caught and fixed one real defect before merging**: the dispatched subagent's first pass used short team names (`"Liberty"`, `"Dream"`) in the `Team`/`team_a`/`team_b` columns instead of the full names (`"New York Liberty"`, `"Atlanta Dream"`) the brief explicitly required (to match `cache/projected_wnba_standings.rds`'s existing convention, and because this repo's RAPM-join logic joins on full team name per `CLAUDE.md`). Marked the run `evidence_mismatch` via `runlog.R set-status`, fixed the two `dplyr::first(team_name)` / `dplyr::first(opponent_team_name)` calls to `team_display_name` / `opponent_team_display_name` directly in the kept worktree, re-ran, re-verified independently, then merged by copying the 7 resulting files into the main tree (not a git merge — the worktree's `git worktree remove` failed with an OS-level lock error afterward, so the worktree directory is still sitting on disk, unregistered with git — see "Open items" #4, now two of these).
3. **RAPM third of #69**: ran a `/spec-interview` rather than guessing or building blind, because inspection turned up **two independent problems**, not one — `load_or_build_wnba_pbp_cache(seasons = yr)` silently ignores its `seasons` argument whenever `cache/wnba_pbp_cache.rds` already exists (it does, pooled across 2019-2026), so a historical per-season RAPM call today would fit across all 8 seasons, not just the requested one; and `reattribute_to_current_roster_team()` (added by a prior session, see `CLAUDE.md`) runs unconditionally and would reassign every player to their *current* 2026 roster team, which is wrong for a historical snapshot. Six Y/N questions resolved the design (extract a pure `fit_rapm_ratings()` helper out of `estimate_rapm_ratings()`, add a `team_attribution` parameter, fix the season-filter bug as a no-op for the live caller, scope the fallback hard-stop to the historical path only). Full resolved spec posted to **issue #70**, linked as a GitHub native sub-issue of #69 (`gh api .../issues/69/sub_issues`). **Not implemented** — #70 is a spec only.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `tools/generate_historical_season_snapshots.R` | **New, 121 lines, uncommitted** | Generates `cache/actual_wnba_standings_<year>.rds` and `cache/playoff_bracket_results_<year>.rds` for 2023/2024/2025 from `data/box_scores_cache.rds` (`config.R`'s `CACHE_TEAM_BOX`) via the existing `filter_real_franchises()` (not reimplemented). Does **not** yet contain the RAPM generation step (#70, see point 3 above) — when that's implemented, it extends this same script per the resolved spec, not a new file. |
| `cache/actual_wnba_standings_{2023,2024,2025}.rds` | **New, uncommitted** | Columns `Rank, Team, Wins, Losses, Win_Pct`, `Team` is full team name. Verified: `Wins + Losses` matches an independent per-team game count from `data/box_scores_cache.rds` for all 3 seasons; `Win_Pct` matches to <1e-9. |
| `cache/playoff_bracket_results_{2023,2024,2025}.rds` | **New, uncommitted** | Columns `team_a, team_b, games_played, series_length, winner, games` (nested per-game list-column). 21 series (7×3 seasons) spot-checked against an independent filter of `data/box_scores_cache.rds`, all matched, including 2024's real Liberty-over-Lynx Finals result. |
| `cache/rapm_ratings_{2023,2024,2025}.rds` | **Not created** | Scope of sub-issue #70, not yet implemented. |
| `rapm_engine.R`, `config.R`, `daily_ingest.R`, `app.R`, `summary_app.R` | **Unchanged** | Out of scope for this session's dispatch; `cache/rapm_ratings.rds`'s mtime (`2026-10-08 07:49`) predates this session's work, confirming it. |

**Nothing from this session has been committed.** `git status` shows the 7 new files above as untracked, plus the pre-existing cache-refresh churn from the scheduled pipeline (unrelated, listed in every prior session's own notes) and the two leftover worktree directories under `.claude/worktrees/` (see "Open items" #4).

## Validation performed this session — and what wasn't

- **Performed**: independent recomputation (separate `group_by`/`summarise` and filter scripts, not reusing the subagent's own code) of standings win/loss counts and bracket series results for all 3 pilot seasons before merging; `git status --porcelain` check in the worktree to confirm no existing tracked file was touched; confirmed `cache/rapm_ratings.rds` mtime is untouched.
- **Not performed**: no RAPM generation at all (spec only, issue #70). No test of `tools/generate_historical_season_snapshots.R` being re-run after a future RAPM-generation extension (that re-verification is explicitly called out as required in #70's spec, once that work lands). Nothing committed or pushed — that decision was left to the user.

## Concrete next step

1. **Immediate**: decide whether to commit the 7 new files from issue #69 (script + 6 caches) — nothing before `tools/generate_historical_season_snapshots.R`'s current content needs re-verification first, that was already done this session (see above).
2. **Implement issue #70** (RAPM third of #69) per its posted spec: extract `fit_rapm_ratings()` out of `rapm_engine.R`'s `estimate_rapm_ratings()`, add the `team_attribution` parameter, fix the season-filter bug, then extend `tools/generate_historical_season_snapshots.R` (the same file from #69, not a new one) with the three `cache/rapm_ratings_<year>.rds` outputs. Re-read #70 directly rather than trusting this summary — it's the authoritative, implementation-ready spec.
3. Re-run and re-verify `tools/generate_historical_season_snapshots.R`'s *existing* standings/bracket output isn't broken by the RAPM extension, not just that the new RAPM section works — explicitly called out in #70 as a requirement, easy to skip by accident.

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
| Issue #69 Standings + Bracket pilot (2023-2025) | Shipped this session — uncommitted (`tools/generate_historical_season_snapshots.R` + 6 `cache/*.rds` files). RAPM third split into sub-issue #70, spec'd, not implemented. |

## Open items (standing, unreconciled — confirmed live via `gh issue list --state open` on 2026-10-08)

These have been flagged by **every** session that touched this area since they first appeared and remain genuinely open — not rediscovered this trim, just consolidated into one place instead of being repeated in full in every archived section:

1. **GitHub issue tracker is stale**: `#43`, `#44`, `#49` all still show `OPEN` (re-confirmed 2026-10-08), but #49's code was merged back in commit `e5c97f3` and #43/#44 (its parent epics) have no remaining work blocking them beyond that. Nobody has run `gh issue close` on any of the three. Closing them is a visible tracker action — do it once confirmed, don't just trust this note.
2. **`dashboard_render_helpers.R` does not contain `.normalize_value_bets_dates()`**, so `control_panel_app.R` still carries its own byte-for-byte duplicate of `app.R`'s `r_normalized_value_bets()` reactive logic (deriving `norm_date` on `cache/latest_value_bets.rds`, including the staggered-placeholder-date fallback for thin/demo slates). Recommended fix (never built): hoist into a plain function in `dashboard_render_helpers.R` and have both `app.R` and `control_panel_app.R` call it from there.
3. **Three headless probes never got a login step added**: `tools/headless_control_panel_probe.R`, `tools/headless_control_panel_staleness_probe.R`, `tools/headless_control_panel_queue_lock_probe.R` all predate the control-panel's real auth wall (added in the #43/#44 tree) and will fail against every element they try to drive, since none of them log in first. `tools/headless_login_module_probe.R`'s `set_module_input()` pattern is the one to copy. Not updated in any session since the auth wall landed.
4. **Two leftover worktrees now, not one** (`.claude/worktrees/agent-ae227d715064d6d37`, pre-existing, and `.claude/worktrees/agent-a46276a0f4609d125`, added this session by a `subagent-brief` dispatch for issue #69 whose `git worktree remove` failed with an OS-level file lock). Neither is registered with git any more (`.git/worktrees/` has no entry for either — they're orphaned directories, not real worktrees), both still safe to leave in place rather than force-deleting. `.claude/worktrees/` is still not in `.gitignore`. Re-check before assuming either is still true.
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

## Concrete next step (beyond the top "CURRENT STATE" section's own next steps, and the sibling-deploy sync duty above)

The top section's 3-item list (commit #69's output, implement #70, re-verify after extending the script) is the actual next unit of work. Once that's done, pick from "Open items" above based on priority — none of them are blocking anything else:
1. Tracker hygiene (`gh issue close` for #43/#44/#49) is the cheapest, lowest-risk one to clear.
2. The `.normalize_value_bets_dates()` de-duplication is the only one with real drift risk (two copies of non-trivial logic that can silently diverge — this repo has been bitten by exactly this shape of bug before, per `CLAUDE.md`'s `CONN`/`CON` and RAPM-join notes).
3. The three stale headless probes and the two leftover worktrees are low-urgency cleanup, worth bundling into whatever session next touches `control_panel_app.R` or `.claude/worktrees/` for an unrelated reason.
