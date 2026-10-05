# Handoff — 2026-10-04 (Continuing thread: `summary_app.R` — Playoff Bracket tab rebuilt as a real tournament tree, Tab 5 reordered, commit `2089543` pushed to `main`) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a continuation of the dark-mode/methodology-panel thread immediately below** (same
`summary_app.R` file, different session). That thread's own "Concrete next step" #2 ("run
`summary_app.R` live and look at it… in one real browser session") is **still not fully done** —
this session's own verification was real headless-Chrome runs scoped to Tab 2 and Tab 5 only
(repeated ~6 times across iterations), not a single manual pass over all 5 tabs together. Its
"Concrete next step" #3 (delete the 6 stale `worktree-agent-*` branches) **is now done** — this
session did it first thing, confirmed all 6 merged via `git merge-base --is-ancestor` before
`git branch -d`. Its #4 (renv `DESCRIPTION`-file warnings) is unchanged/not investigated further
this session. Read `CLAUDE.md` first if you haven't already (unchanged, still applies).

## What this thread is

User asked (1) to make Tab 2 ("Playoff Bracket") more visually appealing, then, once an initial
ggplot2 tree redesign was live, flagged two real correctness bugs found by actually looking at the
rendered result — not flagged by any automated check — and (2) asked for a small Tab 5 layout
reorder. All three were fixed in sequence within this one session/thread.

## Bug 1 (user-caught): eliminated team showing in the semifinals

**Symptom**: after the first tree-layout pass, Minnesota Lynx appeared in a Round-2 (semifinal) box
even though Minnesota was actually swept 0-2 by New York in Round 1.

**Root cause**: Tab 2 was reading `cache/playoff_series_wnba_demo.rds`, which is stale,
unrelated demo output from `playoff_simulator.R`'s own self-test suite (it names whatever matchup
that suite's demo happened to use, e.g. "Las Vegas Aces vs Minnesota Lynx" for "semifinals") — it
was never real bracket data and had no mechanism to reflect that Minnesota had since been
eliminated.

**Fix**: switched Tab 2 to read `cache/series_length_predictions.rds` exclusively (produced by
`tools/series_length_predictor.R`, which this session extended — see below). `summary_app.R` no
longer reads `playoff_series_wnba_demo.rds` anywhere (`SERIES_LENGTH_CACHE_PATH` at
`summary_app.R:59` is now the tab's only cache dependency; the old `PLAYOFF_SERIES_CACHE_PATH`
constant was deleted, not just unused).

`tools/series_length_predictor.R` changes (re-run this session to regenerate the cache with the
new schema — re-running it also harmlessly re-triggers `playoff_simulator.R`'s own demo suite as a
documented side effect, same as every prior session that sources that file):
- Added `REAL_2026_ROUND1_RESULTS` (hardcoded, documented, matches
  `WNBA_2026_Postseason_Predictions.qmd`'s own `{r round1-actual}` tribble verbatim — not
  re-derived, since no cache in this repo reliably flags which box-score rows are playoff games;
  `config.R:102-103` already notes the wehoop feed doesn't carry a playoff `season_type`). Saved as
  `cache/series_length_predictions.rds$round1_results`.
- `crossvalidate_series_length()` now also returns the full `mc_result` object (not just the
  length-only `mc_dist` summary), and `run_round()` exposes it as `$series` on each semifinal
  entry — giving `summary_app.R` a real simulated `p_high_seed_win`/`fair_ml_high`/`fair_ml_low`/
  `avg_series_games` for the two real confirmed semifinal matchups (Atlanta-vs-NY, Golden
  State-vs-LV), not just a series-length distribution.

## Bug 2 (user-caught): Round 1 matches wired into the wrong semifinal slot

**Symptom**: after Bug 1's fix, the bracket now showed real teams, but a connector line from New
York Liberty's Round 1 box visually appeared to terminate inside the Atlanta Dream semifinal box
instead of its own correctly-identified New York Liberty slot in that same semifinal box.

**Root cause**: `REAL_2026_ROUND1_RESULTS` is listed in seed-ascending order (`1v8, 2v7, 3v6,
4v5`), and the bracket layout's row-pairing logic assumed adjacent rows in that list feed the same
semifinal. They don't — the real bracket pairs `1v8` with `4v5` (both feed the Atlanta-vs-NY
semifinal) and `2v7` with `3v6` (both feed Golden State-vs-LV), which is the standard
single-elimination bracket-half structure, not seed-ascending order. Round 1 rows 1 and 2 in the
original list order (`1v8`, `2v7`) are *not* bracket-adjacent in reality.

**Fix**, both in `summary_app.R`'s `bracket_plot` reactive (`summary_app.R:357` onward):
1. Reorder `round1` (the list read from the cache) into standard bracket-half order
   (`bracket_half_order <- c(1, 4, 2, 3)`, matched against each entry's `seed_high`) before laying
   out rows, rather than trusting the cache's seed-ascending list order to already be
   bracket-adjacent.
2. Replaced the Round-1-to-Semifinal connector logic with a **team-name lookup**
   (`node_y_for_team()`): each connector now traces from the *actual winning team's* row in the
   Round 1 column to that *same team's* row in the Semifinals column, rather than assuming a fixed
   row-position pairing. This is the more robust fix — it can't silently mis-wire again even if
   list/row order changes later, since it no longer depends on any positional assumption at all.

Both bugs were caught by the user visually inspecting a live screenshot, not by any of this
session's own automated checks (0 `shiny-output-error` elements and 0 console errors were true in
both the buggy and fixed states) — worth remembering that an error-free headless sweep is
necessary but **not sufficient** to catch a logically-wrong-but-cleanly-rendered result.

## Tab 5 reorder (small, user-requested, no bug)

`summary_app.R`'s Tab 5 ("Prediction Accuracy Tracker") card order changed from
HUD → table → plot to **HUD → plot → table** (`summary_app.R:274-292`): the
`accuracy_cumulative_plot` card now comes immediately after the three value-box HUD cards, with
the `accuracy_table` card last. Purely a `card(...)` reordering in the `nav_panel`'s UI block, no
server-side or data changes.

## Verification this session (repeated per-change, not just once at the end)

For every one of the 3 changes above, the same two-step discipline was used (per this repo's
`headless-ui-regression-sweep` skill, adapted since that skill's own probe script
`tools/headless_dashboard_probe.R` is hardcoded to `app.R`, the unrelated betting terminal, not
`summary_app.R`):
1. **Standalone ggplot render first** (throwaway `tools/tmp_bracket_preview*.R` → a `.png`, read
   with the Read tool, deleted after). This is what actually caught Bug 1's root `wrap_line()`
   vectorization issue from the *prior* session's work in one pass, and would have caught either
   of this session's two bugs if they'd been introduced by this session's own code rather than
   pre-existing/newly-surfaced data issues.
2. **Live headless-Chrome verification against the real app**: a throwaway wrapper
   `tools/tmp_summary_probe_dir/app.R` containing just `setwd("../.."); source("summary_app.R")$value`
   (the `$value` is required — a bare nested `source()` call returns a `list(value=, visible=)`
   wrapper, not the `shinyApp()` object itself, which made the very first attempt this session fail
   with `"app.R did not return a shiny.appobj object"`), driven by a throwaway
   `tools/tmp_summary_probe_run.R` using `shinytest2::AppDriver` with `CHROMOTE_CHROME` set
   explicitly and a fixed port (matching `tools/headless_dashboard_probe.R`'s own working
   settings — the default/unset versions of these two timed out on `Page.navigate` intermittently,
   confirmed as a pure timing flake since a bare retry with no code change succeeded both times it
   happened). **Gotcha re-confirmed this session**: `AppDriver`'s screenshot method is
   `$get_screenshot(file = ...)`, not `$screenshot(path = ...)` — same wrong-method-name trap the
   dark-mode-thread section below already flagged once; got hit again this session before being
   caught by R's own "attempt to apply non-function" error. All scratch files
   (`tools/tmp_bracket_preview*.R/.png`, `tools/tmp_summary_probe_dir/`, `tools/tmp_summary_probe_run.R`,
   `tools/tmp_*_screenshot*.png`) were deleted after each use — none are part of the repo.

Every verification pass this session showed 0 `.shiny-output-error` elements and 0 browser console
error log lines, in both the buggy and later-fixed states — see the note above about this being
necessary-but-not-sufficient.

## What's actually changed

- `summary_app.R` — modified, committed, pushed (`2089543`). 900 lines total (up from ~826 at the
  start of this session). Tab 2's `bracket_plot`/`bracket_status` reactives fully rewritten; Tab 5's
  `nav_panel` card order changed; `PLAYOFF_SERIES_CACHE_PATH` constant and its associated
  `playoff_series_data`/`playoff_series_load_error` load block deleted outright (not just
  unreferenced).
- `tools/series_length_predictor.R` — modified, committed, pushed (`2089543`). 389 lines (up from
  ~354). Added `REAL_2026_ROUND1_RESULTS`; `crossvalidate_series_length()` and `run_round()` both
  extended to expose a full simulated series object per real semifinal.
- `cache/series_length_predictions.rds` — modified, committed, pushed (`2089543`). Regenerated by
  re-running `tools/series_length_predictor.R`; now has `$round1_results` and a `$series` sub-list
  on each semifinal entry, in addition to everything it already had.
- `cache/playoff_series_wnba_demo.rds` — modified, committed, pushed (`2089543`). Harmless
  side-effect refresh from `playoff_simulator.R`'s own demo suite re-running when
  `series_length_predictor.R` sources it — same documented precedent as every prior session that
  touched that file. **This file is now read by nothing in `summary_app.R`** (confirmed via
  `grep`), though other scripts may still produce/consume it independently; not otherwise
  investigated this session.
- 6 stale `worktree-agent-*` branches (noted as still-pending cleanup in the section below) —
  deleted this session, confirmed merged first. `git branch --list "worktree-agent-*"` now returns
  nothing.
- Nothing else touched. No other `.R` scripts, no `config.R`, no pipeline files, no other docs.

## Concrete next step

1. **The still-open item from the section below carries forward unchanged**: a single real,
   non-headless, manual browser session clicking through all 5 tabs together has still never been
   done by any session, including this one. This session's own verification was real-browser but
   narrowly scoped (Tab 2 and Tab 5 only, re-run per change, ~6 times total) — worth doing the full
   5-tab manual pass before considering this app "done," especially since two real bugs were caught
   only by a human looking at a screenshot, not by any automated check.
2. **If Round 2 (the semifinals) resolves or progresses**, `cache/series_length_predictions.rds`
   needs to be regenerated the same way this session did it: edit `tools/series_length_predictor.R`
   if the Finals matchup becomes knowable (currently hardcoded as genuinely pending via
   `$finals = NULL` / `$finals_note`), then re-run
   `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/series_length_predictor.R`. The bracket tab
   will pick up the new cache automatically on next app restart — no `summary_app.R` code change
   needed unless the Finals matchup itself needs to stop being a TBD placeholder.
3. **Known environment state, unchanged from before this session**: the `renv` library's
   "missing DESCRIPTION files" warning pattern is still present and was hit again this session
   (`farver`, then a long chain of `testthat`/`shinytest2` transitive deps —  `brio`, `diffobj`,
   `evaluate`, `cli`, `fs`, `desc`, `callr`, `cachem`, `fastmap` — were all individually missing).
   A full `renv::restore(prompt = FALSE)` was run mid-session and completed successfully (exit 0,
   no errors reported), which resolved everything needed for this session's own work, but the
   underlying "why do packages keep going missing between sessions" question (flagged by prior
   sessions, never root-caused) is still open.
4. Unrelated to this thread: every other thread further down this file is exactly where its own
   section leaves it — this thread touched none of them beyond the stale-branch cleanup and
   renv-restore side effects noted above.

---



**This is a continuation of the SA-1..SA-5 thread immediately below** (same `summary_app.R` file,
different session) — that thread shipped all 5 tabs and left some loose ends open. This session
(1) confirmed those loose ends are now resolved (see "Stale-state corrections" below), (2) added
two small, **ad hoc, not-tracked-as-GitHub-issues** features the user asked for directly in
conversation: a dark/light mode toggle, and a methodology explainer for the Net Rating metric on
Tab 1. Both are committed and pushed to `main` (`212f842`). Read `CLAUDE.md` first if you haven't
already.

## Stale-state corrections to the SA-1..SA-5 section immediately below

That section's own "Loose ends not closed out this session" lists three items — this session
re-checked all three against live state (not trusted from the prior write-up):

1. **"GitHub issues #55-#59 are all still OPEN"** — **no longer true.** `gh issue list --state
   closed` shows all 5 (SA-1 through SA-5) were closed on `2026-10-04T20:05:3x` — after that
   section was written, before this session started. Not done by this session; just confirming
   it happened, by whom/how is not recorded in this file.
2. **"`docs/SUMMARY_APP_SPEC.md` has an uncommitted diff"** — **no longer true.** `git log --
   docs/SUMMARY_APP_SPEC.md` shows it was committed at `1acd5b9` (the commit immediately after
   that section's own `76ddf62`). `git diff --stat HEAD -- docs/SUMMARY_APP_SPEC.md` is empty as
   of this session.
3. **"3 leftover `.claude/worktrees/<hash>/` directories"** — the *directories* are gone (`ls
   .claude/worktrees/` is empty), but **6 local branches named `worktree-agent-<hash>` are still
   present** (`git branch --list "worktree-agent-*"`) — all 6 confirmed merged into `main` via
   `git merge-base --is-ancestor`, so they're safe to `git branch -d` whenever someone wants to,
   just not done this session (not asked, and deleting branches is a visible action this skill's
   own conventions leave to explicit request). This is a new instance of the same leftover-branch
   pattern, not the exact 3 directories that section named — don't assume they're the same hashes.

## What this thread added (two ad hoc features, user-requested directly, no GitHub issue filed)

### 1. Dark/light mode toggle (commit `c45c368`, merged `bbd1648`)

Added `bslib::input_dark_mode(id = "dark_mode_toggle")` next to `titlePanel("WNBA Model
Summary")` in `summary_app.R`'s `ui <- page_fluid(...)` block, both wrapped in a flex `div` so the
toggle sits to the right of the title (`summary_app.R:179-189` as of this write-up — re-verify
line numbers before trusting them, this file is edited often). No server-side observer needed —
`bslib`'s native widget toggles Bootstrap 5's `data-bs-theme` attribute client-side.

- **Dispatched via the `subagent-brief` skill**, single full-template brief, Tier 0-1, `isolation:
  "worktree"`. Run id `20261004-211157-fe3f93`, logged under `.subagent-runs/` (gitignored).
- **Caught a repeat of the exact SA-1 omission** the section below already documents: the
  subagent's worktree had the file change but **no commit** — `git merge --no-ff` against its
  branch reported "Already up to date." Fixed the same way as last time: `git add` +
  `git commit` by hand inside the worktree before merging. **This is now a second occurrence of
  "subagent reports success but never committed its own work"** — worth treating as a pattern to
  watch for, not a one-off, in any future `subagent-brief` dispatch on this project.
- **Verified independently**, not just trusted from the subagent's self-report: re-ran the
  subagent's own parse/source check (`parse("summary_app.R"); source("summary_app.R")`) myself
  inside the worktree before merging, got the same `ui`/`server` classes and exit 0. Did **not**
  independently re-run the subagent's headless-browser click-toggle screenshots myself (trusted
  that evidence from the recorded result rather than re-driving Chrome a second time) — if the
  toggle is ever reported broken in a real browser, that's the one piece of this feature's
  verification that was taken on the subagent's word alone.
- Worktree and branch (`.claude/worktrees/agent-a720d9c881678314b`,
  `worktree-agent-a720d9c881678314b`) were both fully removed after merging — `git worktree
  remove --force` succeeded this time (unlike the Windows file-lock failures the SA-1..SA-5
  section reports for 3 other worktrees still sitting on disk as of that section).

### 2. Net Rating methodology explainer (commit `212f842`)

Added a closed-by-default `bslib::accordion()`/`accordion_panel()` panel to the bottom of Tab 1
("Season Standings & Projections"), titled "Methodology: what does Net Rating mean, and how is it
calculated?" (`summary_app.R:203-233` as of this write-up — re-verify, same caveat as above).
**Implemented directly in this session, not delegated** — small enough, single-file, no
subagent-brief dispatch needed.

- **Content was derived by reading the actual calculation**, not written from general WNBA-rating
  knowledge, since `projected_wnba_standings.rds`'s `Net_Rating` column (consumed by
  `summary_app.R`'s Tab 1 table/chart) is produced by `roster_bottom_up_engine.R`, which this
  session read directly (`compute_team_live_rating()` around lines 294-379, and the
  league-centering/standings-assembly logic around lines 590-704 — **re-verify these line
  numbers before trusting them**, this is a different file than `summary_app.R` and drifts on its
  own schedule). The panel explains, in order: (1) what a +10 value means (projected margin vs. a
  league-average team on a neutral court, since all 15 teams are re-centered to average exactly
  0.00 — this centering step is the single most important fact to get right, since it's what
  makes Net Rating a *relative* scale rather than a realized scoring-margin stat like the NBA's
  traditional Net Rating); (2) the actual bottom-up derivation steps: per-player BPM (50/50
  box-score/plus-minus blend, shrunk for low minutes) → top-8 rotation selection → 200
  regulation-minutes allocated proportional to historical minutes (injury-adjusted) →
  minutes-weighted average BPM scaled to a margin → league-wide re-centering; (3) a closing note
  that Net Rating is only one of three inputs (alongside team RAPM and Elo) blended into the
  model's actual win-probability/win-total predictions, so it is not itself the final prediction
  shown elsewhere in the app.
- **Verified live**, not just by reading the diff: wrote a throwaway headless `shinytest2`
  probe (`tmp_methodology_probe.R`, deleted after use, same scratch-file convention as other
  threads in this file) with a wrapper `app.R` that `setwd("..")`s and `source()`s
  `summary_app.R` (needed because `shinytest2::AppDriver$new(app_dir = ...)` otherwise expects
  an `app.R` directly in that directory, and the repo root's own `app.R` is the unrelated betting
  terminal, not `summary_app.R`) — confirmed the accordion panel opens on click, its rendered
  text matches what was written verbatim (checked via `innerText` substring), and
  `.shiny-output-error` count is 0. Did not screenshot (a `$screenshot()` call with the wrong
  method name errored after the real checks had already passed; not worth re-running just for a
  picture given the text/DOM checks already passed).

## What's actually changed (this session only — see the section below for everything before it)

- `summary_app.R` — modified, 2 commits, both pushed: `c45c368` (dark mode toggle, merged via
  `bbd1648`) and `212f842` (methodology panel). 826 lines total as of this write-up (up from 783
  at the start of this session).
- `docs/HANDOFF.md` — this section, new.
- Nothing else touched. No cache files, no other `.R` scripts, no `config.R`, no pipeline files.
- `.subagent-runs/20261004-211157-fe3f93/` — new run directory for the dark-mode dispatch,
  gitignored, status `merged` in its own `meta.json`.
- 6 stale `worktree-agent-*` branches noted above still exist (all merged, not deleted this
  session) — separate from the one this session created and cleaned up itself.

## Concrete next step

1. **Nothing from this session is left half-done** — both features are committed, pushed, and
   independently re-verified (with the one noted exception: the dark-mode toggle's click/screenshot
   evidence was trusted from the subagent's own report, not independently re-driven).
2. **Pick up the SA-1..SA-5 thread's own still-open item**: "run `summary_app.R` live and look at
   it" end-to-end in one real (non-headless) browser session — still not done by any session,
   including this one (this session's own browser checks were both headless/automated, scoped
   narrowly to the two features it added, not a full manual pass over all 5 tabs together).
3. **Optional cleanup, not blocking anything**: `git branch -d` the 6 confirmed-merged
   `worktree-agent-*` branches listed above, if/when someone wants a tidier `git branch` output.
4. **Known environment state, unchanged from before this session**: the `renv` library still
   prints "missing their DESCRIPTION files" warnings for ~30+ packages (`AsioHeaders`, `askpass`,
   `backports`, `bit`, `broom`, `dplyr`, `DT`, etc.) on every bare `Rscript.exe` invocation — same
   long-standing corruption pattern documented repeatedly further down this file. **Did not block
   anything this session** (`shiny`, `bslib`, `shinytest2`, `chromote`, `jsonlite`, `digest` all
   loaded and worked fine for both the dark-mode dispatch and the methodology-panel probe), but
   not re-root-caused either — still an open item if anyone wants to chase it further.
5. Unrelated to this thread: every other thread further down this file is exactly where its own
   section leaves it — this thread touched none of them beyond the stale-state corrections noted
   above.

---

# Handoff — 2026-10-04 (Continuing thread: `summary_app.R` fully implemented — tickets SA-1 through SA-5, issues #55-#59, all merged to `main`) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a continuation of the spec thread immediately below** (same `summary_app.R` feature,
different session) — that thread produced `docs/SUMMARY_APP_SPEC.md` and recorded "nothing
implemented yet." This thread filed 5 GitHub issues from that spec's 5 tabs, then implemented and
merged all 5. Separate from every other thread further down this file; none of them were touched.
Read `CLAUDE.md` first if you haven't already.

## What this thread is

Starting from the already-compiled `docs/SUMMARY_APP_SPEC.md` (previous thread), this thread (1)
added a "Tickets" section to that spec file breaking its 5 tabs into 5 vertical-slice tickets
(SA-1..SA-5, one tab per ticket, SA-1 bundling the shared app skeleton); (2) filed those 5 tickets
as GitHub issues #55-#59; (3) implemented all 5 via the `subagent-brief` skill, one dispatch per
ticket, **run sequentially, not in parallel** — all 5 tickets add a `nav_panel(...)` to the same
`navset_tab(...)` in the same file, so parallel worktrees branching from the same base would have
produced near-certain merge conflicts on `summary_app.R`. Each ticket branched from the
just-merged result of the previous one.

## What exists now

**`summary_app.R`** (783 lines, repo root, **committed to `main`**, 5 merge commits
`c74c990`..`76ddf62`) — the full static-snapshot Shiny app the spec described. All 5
`nav_panel(...)` tabs present (`summary_app.R:183,199,208,224,237`, titles: "Season Standings &
Projections", "Playoff Bracket", "Model Calibration & Reliability", "Model Comparison",
"Prediction Accuracy Tracker"). Every tab's cache path is a named constant near its own load
block, not a bare literal re-typed at the read site:

| Tab | Cache path constant | Reads |
|---|---|---|
| 1. Season Standings | `STANDINGS_CACHE_PATH` (`summary_app.R:44`) | `cache/projected_wnba_standings.rds` |
| 2. Playoff Bracket | `PLAYOFF_SERIES_CACHE_PATH`, `SERIES_LENGTH_CACHE_PATH` (`:49-50`) | `cache/playoff_series_wnba_demo.rds`, `cache/series_length_predictions.rds` |
| 3. Model Calibration | `CALIBRATION_CACHE_PATH` (`:54`) | `cache/model_calibration_input.rds` |
| 4. Model Comparison | `MODEL_BENCHMARK_CACHE_PATH`, `WINDOW_SWEEP_CACHE_PATH` (`:125-126`) | `data/model_benchmark_results.csv` (new, see below), `data/window_sweep_3_25_results.csv` (pre-existing) |
| 5. Prediction Accuracy Tracker | `PREDICTION_ACCURACY_CACHE_PATH` (`:161`) | `cache/prediction_accuracy_log.rds`, filtered to `is_synthetic == FALSE & status == "RESOLVED"` |

Every tab has a `file.exists()` guard + `tryCatch(readRDS(...))`/`read.csv(...)` at startup and a
labeled fallback (warning `div`, empty-but-headered table, placeholder-text plot) if its cache is
missing — verified live for every tab by a fresh agent actually renaming/hiding the relevant cache
file(s) and re-running the app, not just by reading the `file.exists()` line and assuming the
fallback branch works.

**`tools/build_model_benchmark_cache.R`** (239 lines, new, **committed to `main`**, commit
`cb3b196`) — one-off script (not in `run_full_pipeline.R`'s DAG), reuses
`WNBA_Analysis_Project.Rmd`'s `build_feature_df()`/`build_wnba_recipe()`/`eval_model()`-style
logic (lines 136-314/323-334/584-631 of the `.Rmd` as of this session — **re-verify those line
numbers before trusting them**, source drifts), fits Logistic Regression/Random Forest/XGBoost on
`season < CURRENT_SEASON` (read from `config.R`, never hardcoded), evaluates on
`season >= CURRENT_SEASON`, writes **`data/model_benchmark_results.csv`** (new, committed,
`cb3b196`): `Logistic Regression,0.6396,0.6707,0.2265,0.6456` /
`Random Forest,0.6366,0.6815,0.2224,0.6365` / `XGBoost,0.6156,0.6762,0.2324,0.6803` (Model,
Accuracy, ROC-AUC, Brier Score, Log-Loss) — these are real fitted numbers from this session's
actual run, not placeholders.

## A known-stale number in the spec, surfaced not silently fixed

The spec's Tab 5 section (and the previous thread's own summary above it in this file) says "39
real games as of [the 2026-10-04 spec-interview session's] read" for
`cache/prediction_accuracy_log.rds`'s `is_synthetic == FALSE & status == "RESOLVED"` filter. When
SA-5's subagent re-ran that exact filter this session, it got **36**, not 39 — the cache has been
refreshed (presumably by a scheduled pipeline run) between the two sessions, and the spec's count
was always a point-in-time snapshot, not a hardcoded value anywhere in code. Nothing to fix; just
don't be surprised the live app's value box doesn't match the spec doc's number, and don't treat
either number as fixed going forward — it moves every time the cache refreshes.

## Loose ends not closed out this session — flagging, not fixing silently

- **GitHub issues #55-#59 are all still `OPEN`** as of `gh issue list` at the time of this
  writeup, even though all 5 are fully implemented, verified, and merged to `main`. This thread
  did not close them (closing issues is a visible action outside this handoff-writing step's
  scope). Whoever picks this up next should close #55-#59 with a reference to the 5 merge commits
  (`c74c990`, `1754abb`, `3cb230e`, `4f53e15`, `76ddf62`) — or decide not to, if this repo wants a
  human to do that review first.
- **`docs/SUMMARY_APP_SPEC.md` has an uncommitted diff** (80 insertions, the "Tickets" section
  added this session, `git diff --stat docs/SUMMARY_APP_SPEC.md`) — never committed. Worth
  bundling into whatever commit closes out this thread's documentation, or committing standalone.
- **3 of the 5 dispatched subagents' worktree directories are still on disk**, not deregistered
  from git but present as inert folders: `.claude/worktrees/agent-abfee33a93d1a7ad6` (SA-1),
  `.claude/worktrees/agent-a7ef37791d8f6be4a` (SA-3), `.claude/worktrees/agent-a09fc9d4b35b87d2f`
  (SA-4). `git worktree remove --force` failed on these three with `Invalid argument` (a Windows
  file-lock, not a git error) even though `git worktree list` no longer shows them as registered
  and the branch itself was deleted in each case — this matches this file's own standing note
  below ("Leftover `.claude/worktrees/<hash>/` directories can accumulate... harmless, not deleted
  without explicit user confirmation"), now with 3 fresh instances added to that pattern. Safe to
  delete by hand (`rm -rf`) once confirmed with the user; not done here.

## Environment notes (new this session, not yet folded into `CLAUDE.md`'s own section)

- **The `subagent-brief` skill's own `digest`/`jsonlite` R-package dependency was missing from
  this project's renv library** (not just pinned in `renv.lock` — actually absent from
  `renv/library/...`) at two separate points this session, despite the skill's own doc claiming
  "both packages are already in renv.lock." `install.packages("digest", repos =
  "https://cloud.r-project.org")` fixed it in seconds both times (binary install, no compile) —
  but it recurred a second time after already being fixed once mid-session, consistent with this
  file's long-standing, never-fully-root-caused "machine-wide renv package cache gets wiped
  between sessions" pattern (see the standing note at the bottom of this file). Don't assume
  `digest`/`jsonlite` are present in this repo's renv library; check and `install.packages()`
  on the spot if `validate_brief.R`/`runlog.R` error with `R package 'digest' is required`.
- **A freshly dispatched `isolation: "worktree"` subagent's renv library starts out completely
  empty** (not inherited from the main checkout) — SA-1's, SA-4's, and SA-5's subagents all had to
  run `renv::restore()`/`renv::install()` themselves before they could run/test `summary_app.R`,
  adding real wall-clock time to each dispatch (SA-4 took ~46 minutes total, partly model-fitting,
  partly this). Worth knowing up front rather than being surprised when a worktree-isolated
  subagent's first move is a package restore.
- **SA-1's subagent did everything right except commit its own work** — it left `summary_app.R`
  as an uncommitted untracked file in its worktree and reported `status: success` anyway (the
  brief's "Final step: commit" instruction hadn't been written yet for that first ticket). Caught
  by this session's own post-dispatch verification step (`git status --short` inside the
  worktree, before attempting a merge — a plain `git merge` of a branch with no new commits would
  have silently merged nothing). Fixed by committing it by hand before merging, and every
  subsequent brief (SA-2 through SA-5) added an explicit "## Final step: commit before finishing"
  section — none of the other 4 subagents repeated the omission. **Always check
  `git status --short` inside a dispatched subagent's worktree before merging, regardless of what
  its self-reported result claims.**
- **shinytest2's `AppDriver` could not navigate headlessly inside this sandboxed subagent
  environment** for at least one dispatch (SA-2's subagent hit a `Page.navigate` timeout) — worked
  around by directly executing the relevant `renderPlot`/`renderTable` reactive body as plain R
  code against the real cache files instead of driving a real browser DOM. This is a *weaker*
  verification than the live-browser DOM captures SA-1/SA-3/SA-4/SA-5's subagents achieved
  successfully in their own dispatches (same machine, same `chromote`/Chrome setup worked for all
  of them) — SA-2's bracket tab's actual rendered-pixel appearance in a real browser was never
  directly observed by any subagent or by this session's own merge-time verification. If anyone
  later notices the Playoff Bracket tab looks wrong only in a real browser (not via direct
  R-object inspection), start here.

## What's actually changed

- `summary_app.R` — **new, committed**. 783 lines, 5 tabs, all merged to `main` (see table above).
- `tools/build_model_benchmark_cache.R` — **new, committed** (`cb3b196`). 239 lines.
- `data/model_benchmark_results.csv` — **new, committed** (`cb3b196`). 3 rows (real fitted LR/RF/
  XGBoost metrics, see above).
- `docs/SUMMARY_APP_SPEC.md` — **modified, uncommitted** (Tickets section, 80 insertions — see
  "Loose ends" above).
- `.subagent-runs/202610041[6-8]*` (5 run directories: `20261004-160338-5686e2` through
  `20261004-182135-258ac0`) — new, hold this thread's 5 briefs/results. Already gitignored
  (`.gitignore:115`), nothing to decide here.
- `.claude/worktrees/` — 3 leftover directories, already gitignored (`.gitignore:95`), see
  "Loose ends" above for which ones and why they weren't deleted.
- No existing file other than `docs/SUMMARY_APP_SPEC.md` was modified by this thread's own hand
  (every other file in the "What's actually changed" list is new).

## Concrete next step

1. **Decide whether to close GitHub issues #55-#59** (all done, all merged — see "Loose ends"
   above for the exact merge-commit references to cite when closing).
2. **Commit `docs/SUMMARY_APP_SPEC.md`'s pending Tickets-section diff**, and decide whether
   `.subagent-runs/` should be committed or gitignored going forward if it isn't already.
3. **Run `summary_app.R` live and look at it** (`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e
   "shiny::runApp('summary_app.R')"`) — every tab was verified individually by its own
   implementing subagent and cross-checked by this session at merge time, but no one has yet
   opened the finished, all-5-tabs-merged app in one browser session end-to-end. Start with the
   Playoff Bracket tab specifically, per the shinytest2 gap noted above.
4. **The spec's own "Explicitly deferred" list is still fully deferred, untouched this
   session**: live recomputation of any tab, an HTML/CSS bracket graphic, general UI/visual
   polish beyond basic `bslib` theming, and showing a Finals matchup before both semifinals
   resolve (still correctly pending, per Tab 2's verification above). Pick these up only after
   deciding on #55-#59's closure and confirming the merged app actually looks right end-to-end.
5. Unrelated to this thread: every other thread in this file is exactly where its own section
   leaves it — this thread touched none of them.

---

# Handoff — 2026-10-04 (New thread: spec for a new static-snapshot summary app, `summary_app.R` — spec only, not implemented) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a separate thread from every other thread in this file** — it touched no code, no
caches, and no existing docs other than adding one new file. Read `CLAUDE.md` first if you
haven't already.

**Stale-state note on the thread immediately below this one** (the series-length-predictor
thread): its own "Concrete next step" #1 says "decide whether to commit
`tools/series_length_predictor.R`" as if still open — it is not. `git log` shows it was committed
at `23ed8d1` ("feat(tools): add exact series-length predictor for playoff series") sometime after
that section was written. Trust `git log`, not that section's own next-step text, on this point.

## What this thread is

The user asked to present this project's work as a Shiny app for a presentation — specifically
2026 prediction accuracy, 2026 playoff predictions, and model comparison. Discussion proceeded in
three stages: (1) an initial exploratory review of the existing `app.R` (a 1,723-line
`shinydashboard` betting terminal — Daily Edges, Steam Radar, Injuries, Bet Tracker, Embeddings,
Model Calibration, Standings/Matchup Calc, Model Diagnostics, Player Props, Clutch/Shot Profile —
found to have no "results summary" content at all, so trimming it down was ruled out in favor of a
new standalone app); (2) a review of `WNBA_Analysis_Project.Rmd` for additional context (the
rolling-window/offseason-method/model-architecture benchmark notebook); (3) a full `/spec-interview`
(9 sequential Y/N questions, documented turn-by-turn in this thread's own conversation, not
repeated here) that produced a compiled spec. **Nothing was implemented this session** — no `.R`
file was written except the spec doc itself.

## What exists now

**`docs/SUMMARY_APP_SPEC.md`** (new, untracked) — the full compiled spec for a new app,
`summary_app.R`, to be created at repo root. This is the authoritative spec for the next session to
implement from; it is self-contained (states exact tab contents, exact cache files to read, and
every architectural decision with its Y/N rationale) so a fresh agent can build directly from it
without re-running the interview. Read it in full before starting implementation — summary of its
key decisions, for orientation only (the doc itself is the source of truth):

- **Static-snapshot only, v1** — `summary_app.R` reads only pre-computed `.rds`/`.csv` cache files
  at startup, no live model fitting, no `wehoop`/`tidymodels` runtime dependency. Live recomputation
  is explicitly deferred to a future session, not this one.
- **5 tabs**: Season Standings & Projections (table + new bar chart, from
  `cache/projected_wnba_standings.rds`, zero new work); Playoff Bracket (a **ggplot2-rendered**
  bracket graphic — not HTML/CSS, that's deferred — from `cache/playoff_series_wnba_demo.rds` +
  `cache/series_length_predictions.rds`, with Finals rendered as explicitly TBD/pending rather than
  showing the Finals matchup `playoff_series_wnba_demo.rds` claims to know, since
  `series_length_predictions.rds` disagrees and says Finals is undetermined — this thread resolved
  that disagreement in favor of "pending"); Model Calibration & Reliability (ported near-verbatim
  from `app.R`'s existing tab, UI ~lines 277-292 / server ~lines 1123-1200); Model Comparison (a
  **new** table from a **new** script, `tools/build_model_benchmark_cache.R`, which does not exist
  yet — reusing `WNBA_Analysis_Project.Rmd`'s existing `build_feature_df()`/`build_wnba_recipe()`/
  `eval_model()`-style logic to fit LR/RF/XGBoost and write `data/model_benchmark_results.csv` —
  plus the already-cached `data/window_sweep_3_25_results.csv` sweep chart, no new work for that
  half); Prediction Accuracy Tracker (filtered strictly to `cache/prediction_accuracy_log.rds` rows
  with `is_synthetic == FALSE & status == "RESOLVED"` — 39 real games as of this session's read, no
  synthetic `DIAG_*` rows surfaced anywhere, no toggle — value boxes + table + a cumulative-
  accuracy-over-time chart, deliberately not a probability-calibration scatter since that would
  duplicate the Calibration tab).
- **Framework**: lightweight `bslib`/`fluidPage` (`navset_tab`-style), not `shinydashboard` —
  visually distinct from `app.R` on purpose. UI/visual polish beyond basic theming is flagged in the
  spec as a near-term follow-up, not part of this version.
- **File placement**: `summary_app.R` at repo root (flat-layout convention), fully separate from
  `app.R` — no shared code path.

## Data actually inspected this session (confirms the spec's cache references are real, not assumed)

Checked live via a throwaway R script (written to `tools/tmp_inspect_caches.R`, run, then deleted —
not left in the repo):

- `cache/prediction_accuracy_log.rds`: 145 rows x 28 cols. `status` breakdown: 136 RESOLVED, 6
  UNRESOLVABLE, 3 PENDING. `is_synthetic` breakdown: 106 TRUE, 39 FALSE. Of the 136 resolved rows,
  100 are synthetic `DIAG_*` fixture rows (from a diagnostics/calibration-test run, not live
  predictions) and only 39 are real. Overall accuracy across *all* 136 resolved rows (real +
  synthetic mixed) is 80.9% — this blended figure is exactly what the spec's "real-only, no
  synthetic" decision for the Accuracy Tracker tab is designed to avoid reporting.
- `cache/model_calibration_input.rds`: 1,902 rows x 7 cols (`game_id`, `season`, `game_date`,
  `home_team`, `away_team`, `.pred_Win`, `target_home_win`), 2019-2026 — matches what `app.R`'s
  existing calibration tab already reads.
- `cache/playoff_series_wnba_demo.rds`: list of 3 (`first_round`, `semifinals`, `finals`), each with
  `format`/`high_seed`/`low_seed`/`p_high_seed_win`/`fair_ml_*`/`avg_series_games`/`exact_outcomes`.
  Its `finals` entry names New York Liberty vs. Las Vegas Aces with real probabilities.
- `cache/series_length_predictions.rds`: list of 6 — `first_round_example`, `semifinal_atl_ny`,
  `semifinal_gs_lv` (each with `distribution`/`crossvalidation`), `finals = NULL`, `finals_note`
  ("Finals matchup undetermined pending both semifinal series — not simulated."), `generated_at`.
  **This directly contradicts `playoff_series_wnba_demo.rds`'s finals entry above** — flagged to the
  user mid-interview, resolved in favor of this file's "pending" stance for the new app's bracket
  tab (see spec doc).
- `cache/projected_wnba_standings.rds`: 15 rows x 7 cols (Rank, Team, Net_Rating, Proj_Wins,
  Proj_Losses, Win_Pct, Top_Core_Players) — ready to use as-is.
- `data/window_sweep_3_25_results.csv` exists already (referenced in `WNBA_Analysis_Project.Rmd`'s
  own staleness-check logic) — confirmed by reading the `.Rmd`, not independently re-verified on
  disk this session.

## What's actually changed

- `docs/SUMMARY_APP_SPEC.md` — **new, untracked**. The only file this thread added.
- `tools/tmp_inspect_caches.R` — created, used to inspect the caches above, then **deleted** before
  this write-up. Not part of the repo.
- No existing file was modified. `app.R`, `WNBA_Analysis_Project.Rmd`, every cache file, and
  `run_full_pipeline.R` are all untouched.

## Concrete next step

1. **Implement `summary_app.R` per `docs/SUMMARY_APP_SPEC.md`**, in the order the spec lists its
   tabs. Start with `tools/build_model_benchmark_cache.R` first (Tab 4's Model Comparison table
   depends on it; every other tab's data already exists) — reuse `WNBA_Analysis_Project.Rmd`'s
   `build_feature_df()`/`build_wnba_recipe()` helpers rather than reimplementing the recipe/feature
   logic, per the spec's explicit instruction not to duplicate that code.
2. **Validate the Playoff Bracket tab's ggplot2 layout carefully** — it's the one tab with no
   existing precedent in this repo to copy from (unlike Calibration, which ports near-verbatim from
   `app.R`). Render it standalone first and visually inspect before wiring into the Shiny tab, per
   this repo's general "visually inspect, don't trust an absence of errors" discipline (see the
   `headless-ui-regression-sweep`/`render-and-inspect-quarto` skills for the same principle applied
   elsewhere in this repo).
3. **Once v1 ships**, the spec's own "Explicitly deferred" section lists two known follow-ups the
   user already flagged as wanted soon: live recomputation (at least for Model Comparison, per the
   user's own "live recompute later" answer during the interview), and general UI/visual polish
   (the user's own words: "we will make UI enhancements a priority soon").
4. Unrelated to this thread: every other thread in this file is exactly where its own section
   leaves it — this thread touched none of them.

---

# Handoff — 2026-10-04 (New thread: standalone playoff series-length predictor — `tools/series_length_predictor.R`) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a separate thread from the pipeline-rerun/renv thread immediately below** (same calendar
date, different session) — nothing in that thread was touched here, and this thread touched no
`.qmd`/bracket-PNG/renv files. Read `CLAUDE.md` first if you haven't already.

## What this thread is

User asked: how to determine the probability a semifinal series goes 4 games vs. 5 games, how to
break a best-of-3 series into game-by-game predictions, and whether this could be a standalone
script. Planned first (plan mode), then implemented. **This is net-new functionality, not a tracked
GitHub issue** — unlike the control-panel/auth thread further down, this was an ad hoc user request
with no `gh issue` filed for it.

## What exists now

**`tools/series_length_predictor.R`** (353 lines, new, untracked). Deliberately **not** built on top
of `playoff_simulator.R`'s existing Monte Carlo series simulator (`simulate_single_series()`) as the
primary calculation — the series-length state space is tiny (at most `win_threshold^2` states, ≤16
for a Bo7), so it's computed **exactly** via dynamic programming instead of sampled. Monte Carlo is
invoked only as an optional cross-check, never as the production path. Public functions:

- `series_length_distribution(team_high, team_low, net_high, net_low, format, hca_pts)` — the DP
  engine. Reuses `PLAYOFF_FORMATS` and the exact same `pnorm((rating_diff ± WNBA_HCA) /
  WNBA_MARGIN_SIGMA)` margin model `playoff_simulator.R:122-123` already uses, just enumerates the
  `(w_high, w_low)` state space exactly instead of sampling with `runif()`. Returns a tibble of
  `P(length = N)` for every reachable N. Internal `stopifnot(abs(sum(probability) - 1) < 1e-9)` —
  a math invariant, so a hard stop there (unlike this repo's usual file-missing fail-safes) is correct.
- `bo3_game_by_game_breakdown(net_high, net_low, hca_pts)` — answers "how do you break a Bo3 into
  game-by-game predictions" directly: `p1`/`p2`/`p3` (per-game win probs, since home team alternates),
  closed-form `P(length=2) = p1*p2 + (1-p1)*(1-p2)`, `P(length=3) = 1 - P(length=2)`.
- `crossvalidate_series_length(...)` — calls the DP function, then calls the **existing, unmodified**
  `simulate_single_series()` and parses its `$exact_outcomes$scoreline` strings (regex on
  `playoff_simulator.R:165`'s exact `paste0()` format — flagged in-code as a soft coupling) to build
  an independent Monte Carlo length distribution, then diffs the two. Warns (never `stop()`s) past a
  0.02 tolerance.
- `load_real_2026_playoff_seeds()` / `predict_series_length()` / `run_series_length_demo()` —
  convenience wrappers; see "A real bug the user caught" below for why these pull from
  `data/box_scores_cache.rds`, not `cache/projected_wnba_standings.rds`.

Auto-runs via `if (!interactive())` at the bottom (same fixed guard `playoff_simulator.R`'s own
FINDING C-2 already uses — no `sys.nframe()` clause). Saves `cache/series_length_predictions.rds`
(new, untracked): `$first_round_example`, `$semifinal_atl_ny`, `$semifinal_gs_lv`, `$finals = NULL`,
`$finals_note`, `$generated_at`.

## Two real bugs caught and fixed this session, not pre-existing in scope

1. **DP off-by-one** (caught by the DP's own internal `stopifnot` invariant, not by eyeballing): the
   low-seed-wins branch's series-length formula was written as `w_high + w_low + 1 + 1` (copied
   verbatim from the Plan-phase agent's own pseudocode, which had the identical bug) instead of the
   correct `w_high + w_low + 1` — produced an out-of-bounds index on the very first run. Fixed in the
   shipped version; the high-seed-wins branch was already correct and was the reference used to spot
   the asymmetry.
2. **Wrong matchup in the first working version, caught by the user, not by any internal check**: the
   first `run_series_length_demo()` picked semifinal opponents by `Rank == 2` / `Rank == 3` out of
   `cache/projected_wnba_standings.rds` and produced "Las Vegas Aces vs Minnesota Lynx" — a matchup
   that doesn't exist, because Minnesota (the real #1 seed) was already eliminated in Round 1 (see the
   2026-10-03/2026-10-04 sections below) and `projected_wnba_standings.rds` is a forward-looking
   **mid-season** model projection, not a reflection of actual bracket results — exactly the same
   distinction `WNBA_2026_Postseason_Predictions.qmd` lines 217-224 already documents, just not reused
   here the first time. **Fixed** by adding `load_real_2026_playoff_seeds()`, which instead sources
   real per-game net rating from `CACHE_TEAM_BOX` (`data/box_scores_cache.rds`, filtered
   `season == 2026`) and a hardcoded `REAL_2026_BRACKET` seed→abbreviation table matching the verified
   bracket the `.qmd` already cites (Yahoo/CBS/NBC Sports), and hardcodes the real confirmed semifinal
   pairings — **(4) Atlanta Dream vs (8) New York Liberty** and **(2) Golden State Valkyries vs
   (3) Las Vegas Aces** — rather than deriving a pairing generically by rank. The Finals matchup is
   genuinely undetermined pending both semifinals, so it's reported as `$finals = NULL` +
   `$finals_note`, not fabricated.

## Verified results (this session, both semifinals cross-checked against Monte Carlo within tolerance)

- **Atlanta Dream vs New York Liberty (Bo5):** P(3 games) = 28.9%, P(4 games) = 36.2%, P(5 games) = 35.0%.
- **Golden State Valkyries vs Las Vegas Aces (Bo5):** P(3 games) = 25.1%, P(4 games) = 37.1%, P(5 games) = 37.7%.
- Both DP distributions summed to 1 exactly (`sum(probability)`, checked via `readRDS()` on the saved
  cache after the run, not just trusted from the console log) and matched their own
  `simulate_single_series(n_sims = 10000)` cross-check within max `|DP - MC|` of 0.003–0.008 (well
  under the 0.02 tolerance).

## What's actually changed

- `tools/series_length_predictor.R` — **new, untracked**. 353 lines.
- `cache/series_length_predictions.rds` — **new, untracked**. Output of the script's auto-run.
- `cache/playoff_series_wnba_demo.rds` — **modified, uncommitted**. Harmless side effect of
  `source("playoff_simulator.R")` re-running its own demo suite (same documented precedent as every
  other thread in this file that sources that file).
- No existing file was modified (`playoff_simulator.R`, `config.R`, `run_full_pipeline.R` all
  untouched — this is a `tools/`-only addition per `CLAUDE.md`'s folder-layout convention, not part
  of the pipeline DAG).
- Plan-mode artifact (not part of the repo): `C:\Users\kailo\.claude\plans\how-can-we-determine-wondrous-garden.md`.

## Concrete next step

1. **Decide whether to commit** `tools/series_length_predictor.R` + `cache/series_length_predictions.rds`,
   and whether to bundle the `cache/playoff_series_wnba_demo.rds` side-effect diff alongside (this
   repo's established cadence per prior sessions is to commit routine cache-refresh side effects
   together with the intentional work that caused them — not yet done here).
2. **Once either or both real semifinals (ATL vs NY, GS vs LV) actually progress or resolve**,
   re-running the script requires no code change to pick up fresh net ratings (it reads
   `CACHE_TEAM_BOX` live) — but `run_series_length_demo()`'s hardcoded semifinal seed pairs (4v8, 2v3)
   and the Finals section's "undetermined" branch would need manual updates once a Finals matchup is
   actually known, mirroring the same real-results update pattern the 2026-10-03/2026-10-04 sections
   below already established for the `.qmd`/bracket PNG.
3. **Worth considering, not done this session**: `run_series_length_demo()`'s semifinal pairing is
   hardcoded from this session's own read of the real bracket rather than derived programmatically
   from Round 1 results (unlike the `.qmd`'s `adv_prob`-driven approach) — fine for a one-off
   standalone script, but would silently go stale if reused past the current round without noticing.
4. Unrelated to this thread: every other thread in this file (pipeline/renv immediately below,
   `.bat`/renv-repair, control-panel/auth #46 next) is exactly where its own section leaves it — this
   thread touched none of them.

---

# Handoff — 2026-10-04 (Continuing thread: pipeline rerun, Round 1 fully resolved, renv restore root-caused and fixed) — CURRENT STATE FOR THIS THREAD (read this section first)

**Continuation of the 2026-10-03 thread immediately below** (same postseason-predictions thread,
not a new one) — picking up its own "Concrete next step" items 1 and 2. Also closes out, with an
actual root cause rather than a workaround, the renv-corruption escalation that 2026-10-03 section
raised. Separate from the `.bat`/renv-repair thread and the control-panel/auth thread further down,
same as always. Read `CLAUDE.md` first if you haven't already.

## What happened, in order

1. **User asked to rerun the pipeline**, since real games had occurred in the preceding days that
   should determine the next round. Ran `run_full_pipeline.R` directly (`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
   --no-init-file run_full_pipeline.R`, `RENV_CONFIG_SANDBOX_ENABLED=FALSE`) rather than via
   `schedule_daily.bat`, since only a subset of stages mattered for this task.
2. **Root-caused the renv-corruption/restore-failure pattern the 2026-10-03 section could only
   escalate, not fix.** That section found `renv::restore()` dying on `Error: failed to install
   "duckdb"` partway through a C++ source compile, but left open *why* a compile was even being
   attempted when Posit's CRAN snapshot serves Windows binaries. Checked directly this session:
   `renv.lock` pinned `duckdb` at **1.5.5**, but
   `https://packagemanager.posit.co/cran/latest/bin/windows/contrib/4.5/PACKAGES` only publishes a
   binary for **1.5.6** — `renv::restore()` must match the exact locked version, so a version
   mismatch (not memory, not a genuine compile bug) silently forced the fallback to a source build,
   which is what kept dying/getting OOM-killed. Confirmed via `curl`'s own `200` on the binary
   PACKAGES listing and a direct `available.packages()` call showing the mismatch — not guessed.
   **Fix**: `install.packages("duckdb", type = "win.binary", repos =
   "https://packagemanager.posit.co/cran/latest")` (installed in <2 seconds, no compilation) +
   `renv::record("duckdb")` to sync the lockfile entry to 1.5.6. Then **a full `renv::restore(prompt
   = FALSE)` succeeded end-to-end** for the first time all session — `renv::status()` reports
   `$synchronized: TRUE`, 205 packages installed, 0 missing `DESCRIPTION`. Verified by directory
   listing (not inferred from the restore log) that every previously-missing core package is now
   present: `shiny`, `shinydashboard`, `DT`, `future`, `wehoop`, `chromote`, `shinytest2`, `xgboost`,
   `duckdb`. (`RSQLite`/`reticulate` are still absent but confirmed via `grep -rl` to be unused by
   any script currently in the repo — not a blocker.)
   - **Scope of this fix, stated precisely**: this explains and fixes why `renv::restore()` kept
     *failing* this session (and presumably other recent sessions). It does **not** explain the
     older, still-open mystery of why packages go missing from the library *between* sessions in the
     first place (the standing note's `subagent-brief` worktree-cleanup suspicion, never confirmed).
     Both can be true: something intermittently corrupts the library, and separately, the lockfile's
     stale `duckdb` pin made every *recovery* attempt fail until today. Don't conflate the two when
     reading this file's history.
3. **Ran the full pipeline via `run_full_pipeline.R` directly.** `daily_ingest.R` (stage 2 of 20)
   pulled both decisive Round 1 Game 3s that were still missing as of the 2026-10-03 render:
   **Las Vegas Aces 94, Indiana Fever 83** (2026-10-01, LV hosting) and **Golden State Valkyries 77,
   Dallas Wings 73** (2026-10-02, GS hosting) — both favored higher seeds won, consistent with the
   model's pre-game single-game odds (65.3% GS, 59.0% LV) from the 2026-10-03 report.
   **Round 1 is now fully decided, all four series**: (8) New York over (1) Minnesota 2-0, (4)
   Atlanta over (5) Washington 2-0, (2) Golden State over (7) Dallas 2-1, (3) Las Vegas over (6)
   Indiana 2-1. Both semifinals are confirmed: **(4) Atlanta vs (8) New York** and **(2) Golden State
   vs (3) Las Vegas**.
   - **This first `run_full_pipeline.R` invocation still died partway through**, at the same
     `team_embeddings.py` (PyTorch) stage the 2026-09-25/2026-09-26 threads already documented as
     OOM-prone on this machine — confirmed via `Get-CimInstance Win32_OperatingSystem` showing
     ~1.9-2.1 GB free of 15.7 GB at the time. Everything before that stage (including the
     box-score-critical `daily_ingest.R`) had already completed and persisted, so this was not a
     blocker for this thread's actual goal.
   - **A second, independent pipeline run then started and completed in full on its own**, at
     `2026-10-04 05:30:15` per `logs/wnba_pipeline.log` — almost certainly `schedule_daily.bat`'s
     normal scheduled trigger (not something this session invoked), landing a few hours after the
     renv fix. This run **passed `team_embeddings.py` cleanly** (10.19s, no kill) and ran all 20
     stages end-to-end in 38.31 seconds total — the first clean scheduled run visible in the log
     since the renv library started failing. Treat this as live confirmation the renv fix holds
     under real, unattended conditions, not just this session's interactive one.
4. **Updated `WNBA_2026_Postseason_Predictions.qmd`/`.html`**: replaced the `{r round1-actual}`
   chunk's two `TIED_1_1` tribble rows with the real `DECIDED` Game 3 results, updated the
   `#### Round 2` section's intro text (previously "each semifinal's participants are uncertain" —
   no longer true, both matchups are now named directly), and rewrote the Conclusion's closing
   paragraph with the four-team championship odds. Rendered via the same
   `render-and-inspect-quarto` procedure as 2026-10-03 (`"C:\Program Files\Quarto\bin\quarto.exe"
   render`, exit 0, 29/29 chunks) and visually re-verified: title/date correct, Round 1 table shows
   all four rows `DECIDED` with correct per-team scores, championship table caption confirms
   `sum(champ_prob)` == 1.000, prose percentages match the table exactly (Atlanta 37.6%, Golden
   State 32.1%, Las Vegas 20.8%, New York 9.4%).
5. **Regenerated `WNBA_2026_Postseason_Bracket.png`** (the bracket visualization from the prior
   session) with the same real-results update: all eight Round 1 boxes now green/gray (no blue
   "still projected" boxes), both semifinal boxes show the model's real Bo5 series odds (ATL 71.0%
   over NY, GS 57.6% over LV) instead of the old 4-way "winner of X vs winner of Y" uncertainty
   display.
   - **Known minor gotcha**: the `.qmd`'s own championship percentages (37.6/32.1/20.8/9.4) and the
     bracket PNG's independently-recomputed ones in this same session differ by ~0.1-1 point in
     places (e.g. 37.6% vs an earlier 37.5% from a slightly different run) — both call
     `simulate_single_series(..., n_sims = 10000)` with no fixed random seed, so each independent
     R session's Monte Carlo draw differs slightly. This is expected simulation noise, not a
     reasoning bug; only worth fixing (e.g. `set.seed()`) if exact cross-artifact reproducibility is
     ever required.
   - **The bracket-generation R code itself was not committed anywhere** — it was written to
     temporary `tools/tmp_bracket_plot.R`/`tools/tmp_bracket_render.R` files and deleted after each
     use, per this session's own scratch-file convention, not saved as a reusable script. If
     periodic bracket regeneration (e.g. after each remaining round) is wanted going forward, it's
     worth promoting to a permanent `tools/` script instead of re-deriving the ggplot layout logic
     from a cold start each time — see "Concrete next step" below.
6. **Committed and pushed**: `9722478` — bundles the `.qmd`/`.html`/bracket PNG update, the real
   `data/box_scores_cache.rds` diff (the two Game 3s), `cache/injury_data_cache.rds` (routine
   refresh), `cache/playoff_series_wnba_demo.rds` (harmless `playoff_simulator.R` demo-suite
   side effect, same as every prior session), and `renv.lock` (the duckdb 1.5.5→1.5.6 pin fix).
   Pushed to `main` on `kailot-harris/WNBA_analytics`.

## What's actually changed

- `WNBA_2026_Postseason_Predictions.qmd`/`.html`, `WNBA_2026_Postseason_Bracket.png` — committed,
  `9722478`. Round 1 fully resolved; see "What happened" #4-5 above for the exact diff shape.
- `data/box_scores_cache.rds` — committed, `9722478`. Contains the two real Game 3s (3986 total
  rows, confirmed via `daily_ingest.R`'s own log line, not re-derived).
- `renv.lock` — committed, `9722478`. One record changed: `duckdb` 1.5.5 → 1.5.6. No other package
  versions touched.
- `renv/library/windows/R-4.5/x86_64-w64-mingw32/` — **not committed** (gitignored, local-only).
  Fully synchronized per `renv::status()` as of this session; 205 packages, 0 broken.
- **Still uncommitted in the working tree as of this write-up** (from the second, automatic
  `2026-10-04 05:30:15` pipeline run described in "What happened" #3): `cache/betting_ledger.rds`,
  `cache/copula_wilson_pra.rds`, `cache/injury_data_cache.rds` (refreshed again after the committed
  version), `cache/latest_player_props.rds`, `cache/latest_value_bets.rds`, `cache/odds_history.rds`,
  `cache/playoff_series_wnba_demo.rds` (refreshed again), `cache/prediction_accuracy_log.csv`/`.rds`,
  `cache/projected_wnba_standings.rds`, `cache/risk_state.rds`, `cache/rolling_bet_metrics.rds`,
  `cache/team_shot_quality.rds`, `cache/value_bets_history.rds`, `data/team_embeddings.csv`,
  `data/team_similarity_matrix.csv`. These are routine live-pipeline-refresh diffs (market odds,
  props, risk state, team embeddings), not hand-edited and not reviewed line-by-line this session —
  flagging rather than silently committing, per this skill's own "surface anomalies" guidance.
  `data/box_scores_cache.rds` is **not** in this list (0 new records on the second run — already
  current from the first run's commit).

## Concrete next step

1. **Decide what to do with the uncommitted automatic-refresh cache diffs** listed above — commit
   them (this repo's established cadence per `665c494`/other prior sessions is to commit live
   pipeline-rerun cache diffs alongside intentional work, but nothing this session specifically
   needed from them) or leave them for the next scheduled run to overwrite again. Not acted on here.
2. **Both confirmed semifinals (ATL vs NY, GS vs LV) are now presumably underway or about to start**
   — once either resolves (or both), re-run the same update pattern used this session and
   2026-10-03: pull fresh box scores (`daily_ingest.R` via `run_full_pipeline.R`, or just rerun the
   full pipeline now that it reliably completes), update `WNBA_2026_Postseason_Predictions.qmd`'s
   `{r round1-actual}`-equivalent logic for Round 2 (currently there isn't a `{r round2-actual}`
   chunk analogous to `{r round1-actual}` — would need to be added following the same pattern:
   actual/decided rows feed `semi_finalist_prob` instead of the model-only computation), and
   regenerate the bracket PNG.
3. **If bracket regeneration becomes a recurring need**, promote the bracket-plotting logic (see
   "What happened" #5's gotcha) into a permanent `tools/` script that takes the current
   `r1_actual`/semifinal state as input, rather than rewriting the ggplot layout from scratch each
   session.
4. Unrelated to this thread: the `.bat`/renv-repair thread and the control-panel/auth thread further
   down are both still exactly where their own sections leave them — **but note the control-panel
   thread's #46 (and `app.R`, and anything else needing `shiny`/`wehoop`/etc.) is now actually
   unblocked**, since the full renv restore succeeded this session. The 2026-10-03 section's warning
   not to assume those work was accurate as of that section's writing but is now stale.

---

# Handoff — 2026-10-03 (Continuing thread: postseason predictions updated with real Round 1 results — AND a 3rd renv-corruption occurrence, now escalated) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a continuation of the "2026 season accuracy review + postseason predictions `.qmd`"
thread further down this file** (the one that originally built `WNBA_2026_Postseason_Predictions.qmd`)
— not a new thread, but picking that one's own "Concrete next step" #3 back up. It is otherwise
separate from the `.bat`/renv-repair thread immediately below and the control-panel/auth thread
further down — nothing in those is affected by this one, except that the renv-corruption finding
below is the **3rd occurrence** of a pattern those threads already flagged, which the standing note
at the bottom of this file says to escalate at that point. Read `CLAUDE.md` first if you haven't
already (unchanged, still applies everywhere).

## What happened, in order

1. **User asked to pick the postseason-predictions thread back up** (as of 2026-10-03, six days
   after the 2026-09-27 Round 1 tip-off). Per that thread's own "Concrete next step" #3, the
   bracket tree needed re-running round-by-round against real outcomes.
2. **Checked real Round 1 state against `data/box_scores_cache.rds` and
   `cache/prediction_accuracy_log.rds` directly** (not assumed from the original pre-series
   prediction): **#8 New York Liberty swept #1 Minnesota Lynx 2-0** (box scores: 91-75 Liberty
   road win in G1, 87-71 Liberty home win in G2) — eliminating the model's own pre-series
   championship favorite (23.9%) in Round 1. **#4 Atlanta Dream swept #5 Washington Mystics 2-0**
   (92-77, 93-75). The other two series are **tied 1-1**: #2 Golden State vs #7 Dallas (GS won G1
   104-80, Dallas won G2 108-100) and #3 Las Vegas vs #6 Indiana (LV won G1 102-85, Indiana won G2
   99-89). Both decisive Game 3s (LV/IND 2026-10-01, GS/DAL 2026-10-02 per
   `cache/prediction_accuracy_log.rds`'s own `PENDING` rows) **had not yet been ingested into
   `data/box_scores_cache.rds` as of this render** — its max `game_date` was still 2026-09-30 at
   render time, even though today is 2026-10-03. Confirmed, not guessed: `prediction_accuracy_log.rds`
   already has real `LIVE_ODDS_API` rows logged for the ATL-vs-NY semifinal (2026-10-03/10-04),
   which only exist because the pipeline itself has already determined Round 1's top-half winners —
   independent confirmation of the box-score read.
3. **Updated `WNBA_2026_Postseason_Predictions.qmd`** (not a rewrite — inserted one new chunk,
   fixed one existing chunk, updated the Conclusion prose):
   - New `{r round1-actual}` chunk (inserted directly after the original pre-series `{r round1}`
     chunk, before `#### Round 2`): a `tibble::tribble` of the four series' actual state
     (`DECIDED`/`TIED_1_1` + game counts), which computes `p_high_advances` as **0/1 for the two
     decided series** and, for the two still-tied series, **a single-game win probability for the
     decisive Game 3 only** (`single_game_prob_high()`, reusing the same `pnorm((rating_diff +
     WNBA_HCA) / WNBA_MARGIN_SIGMA)` formula `simulate_single_series()` already computes internally
     for a single game — not a fresh best-of-3 simulation, which would understate how resolved a
     1-1 series already is). This `adv_prob` (renamed from the original chunk's identical variable
     name, which it now overwrites) is what Round 2/Round 3's existing, unmodified code consumes —
     no changes were needed to the Round 2/Round 3 chunks themselves, since they were already
     written generically against `adv_prob` rather than against the model's Round 1 output
     directly.
   - **Fixed a latent bug in the "Cross-check against the live pipeline's own Game 1 predictions"
     section**, found while updating this thread, not pre-existing in scope: it filtered
     `cache/prediction_accuracy_log.rds` on `status == "PENDING"` for the 2026-09-27 Game 1s — true
     when the doc was first written (games hadn't been played yet), but those rows are now
     `status == "RESOLVED"` since the games have since been played, so the filter would have
     silently returned **zero rows** without erroring. Changed the filter to `status == "RESOLVED"`
     and added a real `actual_home_win` column (joined from `data/box_scores_cache.rds`) to the
     comparison table, so it now shows live-pipeline-prediction vs. bracket-model-prediction vs.
     real outcome side by side, not just the two pre-game predictions against each other.
   - Updated Conclusion prose with the new post-Round-1 championship odds and an explicit statement
     that this is a living pre-semifinal snapshot, not a final record.
4. **Rendered via the `render-and-inspect-quarto` skill** (`"C:\Program Files\Quarto\bin\quarto.exe"
   render WNBA_2026_Postseason_Predictions.qmd`, `RENV_CONFIG_SANDBOX_ENABLED=FALSE` +
   `RSTUDIO_PANDOC` set per `CLAUDE.md`/this file's standing notes) — exit 0, all 29 chunks executed.
   **Visually inspected the actual HTML**, not just the exit code: title block shows "October 3,
   2026" (the real evaluated `Sys.Date()`, not literal `` `r Sys.Date()` `` or "Invalid Date"); the
   final championship-probability table's own caption confirms `sum(champ_prob)` == exactly 1.000;
   Minnesota Lynx's row independently confirmed at 0.000/0.000/0.000 across
   reach-semis/reach-finals/champion columns, consistent with their Round 1 elimination. Updated
   top three: **Atlanta Dream 41.4%, Golden State Valkyries 21.9%, Las Vegas Aces 13.7%**.
5. **Committed and pushed**: `775f7c3` — `WNBA_2026_Postseason_Predictions.qmd`/`.html` plus the
   harmless `cache/playoff_series_wnba_demo.rds` side-effect diff (from `playoff_simulator.R`'s own
   demo suite re-running as a side effect of being `source()`d — same "harmless" comment the
   original doc's own `{r team-inputs}` chunk already carries). Pushed to `main` on
   `kailot-harris/WNBA_analytics`.

## A 3rd renv-corruption occurrence — now past this file's own escalation threshold

While starting this thread, a plain `Rscript.exe` call failed with `there is no package called
'tidyverse'` — the renv package library was corrupted **again** (same class of issue as the
`.bat`-repair thread immediately below this one from 2026-10-01, which was itself already a
recurrence). This file's own standing note at the bottom already says: *"If the renv-corruption
pattern recurs a third time, it's probably worth escalating from 'known gotcha, re-run restore' to
actually root-causing it."* **This is that third occurrence.** Escalating here, not just re-running
the same recipe silently again:

- **A full `renv::restore(prompt = FALSE)` (after deleting package directories missing
  `DESCRIPTION`, the same recipe the 2026-10-01 thread used) could not be completed this session,
  for two separate reasons, both confirmed, not guessed:**
  1. **The machine was critically low on memory** (~1.8-2.1 GB free of 15.7 GB total) for most of
     this session. Two attempts to run the restore via a backgrounded shell wrapper got their
     *wrapper* killed by this environment's own low-memory guard — but the underlying
     `Rscript.exe` process kept running as an orphan afterward anyway (confirmed via
     `Get-CimInstance Win32_Process -Filter "Name='Rscript.exe'"`'s own `CommandLine` field, not
     assumed), so nothing was actually lost by the wrapper kills — same "orphaned R process" class
     of incident `docs/archive/handoff_history.md`'s "2026-09-25 (pre-Tier-6)" section already
     documents, now recurring under low-memory conditions rather than from a stuck
     `Rscript.exe -e`. **No R process itself was the memory hog** — `Get-Process | Sort-Object
     WorkingSet64 -Descending` at the time showed several Chrome processes, 3 VS Code windows, and
     WSL (`vmmemWSL`) as the actual top consumers, not anything R-related.
  2. **Once memory pressure cleared enough for the restore to actually run to completion, it still
     failed outright** (not killed — a clean `Error: failed to install "duckdb"` from `renv`
     itself) partway through `duckdb`'s C++ source compile under Rtools. The compiler invocation
     itself produced no visible error text before `renv`'s own failure message — ambiguous whether
     this was itself a memory-starved compiler death or a genuine compile error; **not
     distinguished this session**, flagging as unresolved rather than assuming either way. Because
     `renv::restore()` aborts the whole lockfile on a single package failure, this one `duckdb`
     failure left the **rest of the ~150-package lockfile uninstalled** — confirmed via directory
     listing afterward that the following core project packages are still completely missing from
     `renv/library/windows/R-4.5/x86_64-w64-mingw32/`: **`shiny`, `shinydashboard`, `DT`, `future`,
     `wehoop`, `chromote`, `shinytest2`, `RSQLite`, `reticulate`, `xgboost`, `duckdb`** (checked by
     directory existence, not inferred from the restore log). `bslib` and `data.table` happened to
     already be present from before this session's deletion/restore cycle and are fine.
- **Workaround used to unblock this thread's own task** (not a fix for the above): rather than
  fight the full lockfile, ran a narrow `renv::install(c("tidyverse", "knitr", "scales", "here"),
  prompt = FALSE)` — exactly the packages `config.R`/`playoff_simulator.R`/this `.qmd` actually
  `library()`/`::`-call. All 85 transitively-pulled packages came from renv's own local package
  cache (`[linked from cache]` in the install log) in ~12 seconds total — no compilation, so the
  low-memory/duckdb problems above never came into play for this narrow install. **This makes the
  `.qmd` in this thread (and anything else that only needs `config.R`'s own dependency set) work
  again, but does nothing for the packages listed as still-missing above.**
- **Concrete implication for whoever picks up the control-panel thread (#46+) or
  `run_full_pipeline.R`/`app.R` next**: those scripts need `shiny`/`shinydashboard`/`DT`/`future`/
  `wehoop` etc., none of which are currently installed. **Do not assume a bare `library(shiny)`
  (or running `app.R`/`run_full_pipeline.R`/the headless dashboard probe) will work in this
  environment right now** — it was not re-verified working after this session's partial restore,
  and per the directory check above, it almost certainly is not. A full `renv::restore()` still
  needs to actually succeed past `duckdb`, which needs either (a) more free memory than was
  available this session (close Chrome/VS Code/WSL first, re-check with
  `Get-CimInstance Win32_OperatingSystem`'s `FreePhysicalMemory` before attempting), or (b)
  determining why `duckdb` specifically fails to compile here and fixing that directly (worth
  checking whether a prebuilt binary is available from the CRAN snapshot `renv`'s lockfile points
  at, which would avoid the Rtools compile path entirely) — neither was attempted this session.
- **Still not root-caused**: *why* the renv library keeps getting corrupted in the first place
  (missing `DESCRIPTION` files appearing between sessions) remains exactly the open question the
  bottom-of-file standing note already flagged as the long-standing suspect
  (`subagent-brief`'s worktree cleanup step) — this session's finding is additive (duckdb's compile
  failure + low memory as a *compounding* factor during *recovery*, not a cause of the original
  corruption) and doesn't resolve that older open question.

## What's actually changed

- `WNBA_2026_Postseason_Predictions.qmd`/`.html` — modified, committed (`775f7c3`), pushed to
  `main`. See "What happened" #3-4 above for the exact diff shape.
- `cache/playoff_series_wnba_demo.rds` — side-effect diff from re-running `playoff_simulator.R`'s
  own demo suite, committed alongside (harmless, same precedent as the original thread's own render).
- `renv/library/windows/R-4.5/x86_64-w64-mingw32/` — **not committed** (gitignored, local-only).
  Currently holds `tidyverse`/`knitr`/`scales`/`here` plus their transitive deps (85 packages) newly
  restored from cache, plus whatever survived from before. Still missing the packages listed above.
  No `renv.lock` changes were made or needed (no package *versions* changed, just local
  installation state).

## Concrete next step

**Superseded by the 2026-10-04 thread at the top of this file** — items 1 and 2 below are both
done; see that section for the renv root cause (not just a workaround) and the fully-resolved
Round 1. Kept for history:
1. ~~Both pending Round 1 Game 3s... replace the two `TIED_1_1` rows...~~ — done: both Game 3s
   resolved (LV over IND 94-83, GS over DAL 77-73) and ingested via a real `daily_ingest.R` run;
   `r1_actual` now has all four rows `DECIDED`.
2. ~~Before attempting that `daily_ingest.R` run... first get a full `renv::restore()` to actually
   succeed~~ — done, and root-caused (not just retried): see the 2026-10-04 section's renv entry.
3. Once the full postseason bracket resolves (Finals won), this report should get one more pass
   treating it as a closed, final record rather than a living snapshot — **still not needed**, both
   semifinals are in progress as of 2026-10-04.
4. Unrelated to this thread: the `.bat`/renv-repair thread immediately below and the control-panel/
   auth thread further down are both still exactly where their own sections leave them.

---

# Handoff — 2026-10-01 (New thread: scheduled-pipeline failure — `.bat` syntax bug + renv repair + error-visibility logging) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a separate thread from the control-panel/auth thread immediately below and the
postseason-predictions thread further down** — nothing in those threads is affected by this one.
This thread is purely operational (one `.bat` file, plus a one-time environment repair); it has no
relationship to either the #43-#54 control-panel/auth issue tree or the 2026 postseason `.qmd`. Read
`CLAUDE.md` first if you haven't already (unchanged, still applies everywhere).

## What happened, in order

1. **User-reported error:** `Error during pipeline run: Grading yesterday';s bets.'Rolling' is not
   recognized.` — garbled because `cmd.exe` had already split one `echo` line into two statements.
2. **Root cause, found by reading `schedule_daily.bat` directly (not guessed):** line 99's `echo`
   text read `Grading Yesterday's WNBA Bets & Rolling ROI...` — the bare `&` is a `cmd.exe` command
   separator *everywhere*, not just inside `()` blocks, so the line actually ran as two statements:
   `echo ...Bets ` followed by `Rolling ROI...`, and the latter isn't a recognized command. **Fixed**
   by escaping it to `^&` (`schedule_daily.bat:99`, now `Bets ^& Rolling ROI...`) — this was the
   session's first and only fix needed to make the reported error go away.
3. **Separately, confirming the fix via a real `schedule_daily.bat` run surfaced a second, unrelated
   failure:** `renv`'s package library was broken — `Error: package or namespace load failed for
   'dplyr'/'tidyverse': there is no package called 'cli'`, `Execution halted`, on both the
   bet-grading and market-odds steps. This is the **same recurring class of issue the "Standing
   environment/tooling notes" section at the bottom of this file already documents** ("machine-wide
   shared renv package cache has been found wiped/corrupted more than once... if `renv::status()`
   reports packages missing their DESCRIPTION files, `renv::restore(prompt = FALSE)` is idempotent
   and safe to re-run"). This occurrence was **much larger in scope** than the 3-package
   (`foreach`/`hardhat`/`iterators`) case the standing note was based on: **38 packages** had
   library directories missing `DESCRIPTION` (full list in that run's tool output, not reproduced
   here — notably including `cli`, `digest`, `curl`, `data.table`, `DBI`, `bslib`, `chromote`).
   **Important correction to the standing note's recipe, found this session:** a bare
   `renv::restore(prompt = FALSE)` was **not** tried in isolation — this session always deleted the
   broken package directories (those missing `DESCRIPTION`, under
   `renv/library/windows/R-4.5/x86_64-w64-mingw32/`) *before* calling `renv::restore()`. Whether
   `restore()` alone (without deleting first) is actually sufficient is still **not confirmed** —
   flagging this as unresolved rather than assuming the standing note's simpler recipe is complete.
   Fixed and verified: `renv::status()` now reports "No issues found," and a direct
   `library(tidyverse); library(dplyr)` loads cleanly (both checked fresh after the restore, not
   assumed from the restore's own exit code).
4. **Added error-visibility logging to `schedule_daily.bat`**, dispatched through the
   `subagent-brief` skill (run `20261001-125941-ae0646`, brief/result under `.subagent-runs/`,
   status `success`). The `.bat` previously ran its 3 steps (`run_full_pipeline.R`, `bet_tracker.r`,
   `market_odds_engine.R`) unconditionally and always printed "COMPLETED SUCCESSFULLY" regardless of
   whether any step actually failed — which is exactly how step 3's incident went unnoticed until a
   human read the log by hand. Now (`schedule_daily.bat:88-150`): each step's `%ERRORLEVEL%` is
   captured into its own `STEPn_RC` variable right after the call; a nonzero code sets
   `PIPELINE_FAILED=1` and appends a greppable `[ERROR] Step N/3 - <script> - FAILED with exit code
   <n>` line; **all three steps still always run regardless of an earlier failure** (CLAUDE.md's
   fail-safe-pipeline rule, deliberately preserved, not changed); the final banner prints "COMPLETED
   WITH ERRORS" instead of "COMPLETED SUCCESSFULLY" when any step failed; and the script's own exit
   code is now `1` on failure / `0` otherwise, so Windows Task Scheduler's own "Last Run Result"
   surfaces a failure too, on top of the log line.
5. **The `subagent-brief` worktree hit the exact stale-base gotcha this file's own standing notes
   already warn about** ("`isolation: "worktree"` has repeatedly branched a dispatched subagent from
   a stale `main`... always run `git log HEAD..main --oneline` in the worktree before merging... never
   let a subagent resolve its own stale-base merge" — now a 6th documented occurrence, not a new
   bug). Concretely here: the subagent's worktree branched from the committed `main` *before* this
   session's own uncommitted step-2 fix, so a straight merge would have **silently reverted** that
   fix. Resolved per the standing note's advice, by hand, not by the subagent: read the subagent's
   `git diff main -- schedule_daily.bat` inside its worktree, confirmed it only touched the
   error-handling lines (not step 2's `&`), then manually reapplied just those additions onto the
   current `main` file (which already had the `^&` fix) via direct edit rather than a git merge.
   Independently spot-checked afterward (not just trusting the subagent's self-reported evidence):
   rebuilt a standalone test harness in a temp directory (dummy `ok_step.R`/`fail_step.R`, never the
   real pipeline scripts) simulating both an all-succeeding run and a two-step-failing run; confirmed
   `[ERROR]` lines, the correct banner, and the correct exit code in both cases.
6. **Final verification: a real, live full pipeline run via `schedule_daily.bat`** (both fixes in
   place) completed cleanly end-to-end — no `[ERROR]` lines, no `"not recognized"` errors anywhere in
   the log, `market_odds_engine.R` pulled 4 live games from The Odds API and wrote fresh value bets
   to `cache/latest_value_bets.rds` (2 flagged "SHARP +EV"), final banner "COMPLETED SUCCESSFULLY",
   exit code 0.

## What's actually changed

- `schedule_daily.bat` — **modified, uncommitted** on `main` (51-line diff, `wc -l` = 151 total).
  Two changes: the `^&` escape at line 99, and the error-capture/banner/exit-code block at lines
  88-150 described above. Nothing else in the file touched (log rotation, season-window guard,
  `%RSCRIPT%` resolution logic all untouched).
- The cache/data file diffs visible in `git status` (`cache/active_rosters_cache.rds`,
  `cache/latest_value_bets.rds`, `data/box_scores_cache.rds`, etc.) are **side effects of the live
  pipeline rerun in step 6 above**, not hand-edited — expected and fine to commit alongside, or
  leave for whatever this repo's normal cache-commit cadence is.
- No `run_full_pipeline.R`/`bet_tracker.r`/`market_odds_engine.R`/any other `.R` file was touched.
- `.subagent-runs/20261001-125941-ae0646/` holds the full brief + result JSON for the logging work,
  `.subagent-runs/brief-logging.md` and `.subagent-runs/result-logging.json` are this thread's
  working copies of the same brief/result (kept for reference, not auto-cleaned).

## Environment notes (new/refining this session)

- **The renv-corruption standing note (bottom of this file) needs a caveat, not a rewrite**: it's
  confirmed as still live and can be far larger in scope (38 packages this time vs. 3 previously),
  and the fix recipe used this session additionally deleted broken package directories before
  calling `renv::restore(prompt = FALSE)` — whether bare `restore()` alone would have been enough is
  untested and should not be assumed either way by a future session.
- `renv::status()`'s own broken-package list is the fastest diagnostic — don't guess from an
  `Rscript` error message alone (e.g. "there is no package called 'cli'") which packages are
  actually broken; `cli` failing to load is a downstream symptom, the actual broken set is much
  larger and `renv::status()` lists every directory missing a `DESCRIPTION` file directly.

## Concrete next step

**No further code work is required to close out the originally-reported error** — it's fixed and
live-verified. If picking this thread back up:
1. **Decide whether to commit `schedule_daily.bat`** (currently uncommitted) — and whether to
   commit the pipeline-rerun cache-file diffs alongside it or separately, per whatever this repo's
   normal cadence for cache commits is (not established in this thread).
2. If the renv-corruption pattern recurs a third time, it's probably worth escalating from "known
   gotcha, re-run restore" to actually root-causing it — the `subagent-brief` skill's worktree
   cleanup step is the standing suspect (per the existing note) but has never been confirmed; a
   focused look at `cleanup_worktrees.R` and anything it does near `renv/` would be the place to
   start.
3. Unrelated to this thread: the control-panel thread immediately below (#45 done, #46 next) and the
   postseason-predictions thread further down are both still exactly where their own sections leave
   them — this thread didn't touch either.

---

# Handoff — 2026-09-26 (New thread: interactive control-panel app spec — via `/spec-interview`) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a separate thread from every other thread in this file** (the 2026-postseason-`.qmd`
thread immediately below, and the `WNBA_Analysis_Project.Rmd` review-remediation threads further
down) — nothing in those threads is affected by this one, and this thread touched zero files in
the repo. Read `CLAUDE.md` first if you haven't already (unchanged, still applies everywhere).

## What this thread is

The user asked (via the `/spec-interview` skill) to design an interactive web app for triggering
this repo's ML/prediction pipeline stages on demand — something they can "spin up and determine
for myself which analysis needs to be run next," distinct from the existing `app.R`, which is a
**read-only** `shinydashboard` viewer of precomputed `.rds` caches with no way to trigger a stage
run from the browser.

A full Y/N interview (documented turn-by-turn in this thread's own conversation, not repeated
here) produced a compiled spec, which was then filed as **GitHub issues, not a `docs/*.md`
roadmap** — unlike every other multi-tier thread in this file. **The GitHub issues themselves are
the authoritative spec for this feature; there is no separate roadmap doc.** Each issue's body is
self-contained (a fresh agent can implement directly from an issue's text with zero other context).

**Nothing was implemented this session.** No code was written, no files were touched, no commits
were made. This thread's only output is the 12 GitHub issues below.

## The two tickets and their vertical slices (verified against `gh issue list`, not reconstructed from memory)

**Ticket A — interactive control-panel app:**

| Issue | Slice | Depends on |
|---|---|---|
| #43 | Parent/full spec | — |
| #45 | Slice 1 — shared `pipeline_stages.R` registry; refactor `run_full_pipeline.R` to loop over it (adds *declared inputs* per stage, which don't exist anywhere in the repo today) | — (**start here**) |
| #46 | Slice 2 — `control_panel_app.R` MVP: pick + run one stage, see status/log (localhost only, no dependency checks yet) | #45 |
| #47 | Slice 3 — dependency staleness check with hard-block + explicit override | #45, #46 |
| #48 | Slice 4 — multi-select stage queue + global run lock | #46, #47 |
| #49 | Slice 5 — extract shared render helpers out of `app.R`, inline results in control panel | #46 |
| #50 | Slice 6 — network access + placeholder single-password gate (`CONTROL_PANEL_PASSWORD` env var) + `docs/CONTROL_PANEL_SETUP.md` | #46 |

**Ticket B — reusable multi-user auth (split out because it's a distinct subsystem, not a UI
detail of the control panel):**

| Issue | Slice | Depends on |
|---|---|---|
| #44 | Parent/full spec | — |
| #51 | Slice 1 — `auth_utils.R` core: SQLite user store (`cache/auth_users.sqlite` via `RSQLite`) + bcrypt hash/verify | — |
| #52 | Slice 2 — signup flow gated by `CONTROL_PANEL_SIGNUP_KEY` env var | #51 |
| #53 | Slice 3 — mountable Shiny login module, session NOT persisted across browser restarts | #51, #52 |
| #54 | Slice 4 — wire real auth into `control_panel_app.R`, retire the placeholder password gate | #53, **and #50** (cross-ticket: #54 replaces exactly what #50 builds) |

**Recommended build order given the dependency table above:** #45 → #46 → (#47, #49, #50 can
proceed in parallel, all only depend on #46) → #48 → in parallel, #51 → #52 → #53 → #54 (#54 also
needs #50 done first, since it deletes/replaces #50's env-var gate).

## A mistake worth knowing about, not silently corrected

Mid-session, right after filing #43-#44, the assistant reported the wrong issue numbers to the
user for a first draft of the sub-issue plan before the sub-issues actually existed, then caught
and corrected it against real `gh issue list` output before this doc was written. **The table
above is the corrected, verified mapping.** If any other note, comment, or memory from this thread
contradicts it, trust `gh issue list --repo kailot-harris/WNBA_analytics --state all` over
anything remembered.

## Concrete next step

**#45 is done, closed, and pushed to `main`** (commit `8aec5ba`, dispatched via the
`subagent-brief` skill in a separate thread from this handoff's own session — see that skill's
`.subagent-runs/20260926-185108-84c49d/` for the full brief/result record). `pipeline_stages.R`
now holds one entry per each of the 20 real `run_stage()` call sites (the issue title's "13"
undercounted — trust the live file, not the title), including distinct entries for
`prediction_accuracy_logger.R`'s two invocations and both `future_lapply` parallel groups
(a `group` field preserves the "latent_engines"/"props_engines" mechanism unchanged), plus the
new declared **`inputs`** field #47 needs. `git diff` on `run_full_pipeline.R` touches only the
wiring lines — `run_stage()`, the memory-adaptive `plan()` selection, the IO-loading blocks, and
the log-spill merge are untouched.

**Known gap, not yet closed**: a full 20-stage live before/after pipeline run (the QA this issue's
own text asked for) could **not** be completed on this machine — it was OOM-killed at
`team_embeddings.py` (PyTorch) twice in a row under low system-wide free RAM (~2.7GB/16GB, even
after the user freed some), unrelated to the refactor itself. Verification was scoped down
instead: registry fields were diffed 1:1 against the pre-refactor hardcoded call sites, `inputs`
citations were spot-checked against real `readRDS`/`read.csv` lines, and 5 representative stages
spanning both `call_fn` and `entry_fn` modes (`data_health_probe`, `daily_ingest`,
`player_metrics`, `sync_rosters`, `injury_scraper`) were re-run live through the refactored
registry and matched the pre-refactor log stage-for-stage. The remaining 15 stages (both parallel
groups + `team_embeddings.py`) are verified only statically. If a future session has more free
memory to work with, re-running the full pipeline once end-to-end (before making any further #43
changes) would close this gap properly.

**Bonus finds, deliberately not fixed (out of #45's scope)**: `fatigue_travel_engine.R` has no
real schedule input — `evaluate_slate_fatigue()`'s `sample_schedule` is synthetic/demo only, not
backed by any real WNBA schedule feed. `copula_props_engine.R`'s own header comment claims its
A'ja Wilson marquee test derives its per-game means from `cache/player_box_scores_cache.rds`, but
`run_copula_suite()` actually passes hardcoded literal means (`mu_pts = 26.00`, etc.) — the code
and its own documentation disagree. Neither blocks #43/#44's tree; worth a future issue.

**Two steps ahead**: #46 (control panel MVP) is the next real UI work now that #45 has landed, and
is deliberately scoped narrow (single-stage run, no dependency gating, no auth, localhost-only) so
it can be built and manually verified before the riskier slices (#47's dependency gating, #49's
`app.R` render-helper extraction — the highest-regression-risk slice for the *existing* dashboard)
stack on top of it.

---

# Handoff — 2026-09-26 (New thread: 2026 season accuracy review + postseason predictions `.qmd`) — CURRENT STATE FOR THIS THREAD (read this section first)

**This is a separate thread from the `WNBA_Analysis_Project.Rmd` review-remediation work** (Round
2, Tiers 1-5, issues #29-42 — now fully closed; see the "Closed work" table in the "Archived
history" section below, or `docs/archive/handoff_history.md` for the full session-by-session
detail — nothing in this section supersedes that closed work). This section covers a new,
one-shot deliverable: a `.qmd` report that
(1) independently re-verifies the live pipeline's own prediction accuracy against real box scores
for the 2026 regular season, and (2) builds a 2026 WNBA postseason bracket win-probability model.
Read `CLAUDE.md` first (unchanged, still applies everywhere in this repo) if you haven't already.

## What exists now

**`WNBA_2026_Postseason_Predictions.qmd`** (414 lines, repo root, **untracked — not yet committed**)
and its rendered output **`WNBA_2026_Postseason_Predictions.html`** (self-contained,
`embed-resources: true`, also untracked). Both were created and rendered fresh this session; the
render was visually inspected (per the `render-and-inspect-quarto` skill) — title/date/all 9 tables/
2 figures/every inline `` `r` `` value confirmed to have evaluated correctly, zero chunk errors.
Two-part structure:

1. **Part 1 (regular-season accuracy):** Filters `cache/prediction_accuracy_log.rds` to
   `season == 2026 & !is_synthetic`, then independently rejoins every `RESOLVED` row against
   `data/box_scores_cache.rds` on `(game_date, home_team)` and recomputes accuracy/Brier/log-loss/
   margin-MAE/RMSE/bias from scratch — the log's own `correct`/`brier_component` columns are only
   used for a sanity cross-check (same "distrust the log's own columns" discipline
   `tools/check_accuracy_since_0912.R` already established), never trusted directly.
   **Key finding, worth knowing before anyone re-runs or extends this:** real (non-synthetic)
   prediction logging only began 2026-09-17 — every one of the 125 `RESOLVED` 2026 rows dated
   earlier is a `DIAGNOSTIC`-fixture row and is excluded. So "the entire resolved 2026 regular
   season" in practice means **N = 25 real games, 2026-09-17 through 2026-09-23**. 8 of those 25
   are `market_data_source == "UNKNOWN"` (pre-provenance-fix rows — win/loss + Brier scoreable,
   margin permanently `NA`, per `prediction_accuracy_logger.R`'s already-documented Finding C-3/M-5
   history); 17 are `LIVE_ODDS_API` with full margin data. 5 more real predictions (2026-09-24, the
   season's actual final scheduled day) are still `PENDING` because `data/box_scores_cache.rds`
   hadn't ingested those games as of this render — excluded, not guessed at. 4 more `PENDING` rows
   (dated 2026-09-27) are the real postseason Game 1s, which feed the cross-check in Part 2.
2. **Part 2 (postseason bracket model):** The real 2026 postseason bracket/format (no reseeding —
   fixed #1v8/#2v7/#3v6/#4v5, Bo3→Bo5→Bo7) was verified via live web search (cited in the doc:
   Yahoo Sports, CBS Sports, NBC Sports), **not assumed to carry over from a prior season**.
   Real 2026 seeds (confirmed by that same search): (1) Minnesota Lynx, (2) Golden State
   Valkyries, (3) Las Vegas Aces, (4) Atlanta Dream, (5) Washington Mystics, (6) Indiana Fever,
   (7) Dallas Wings, (8) New York Liberty — note this differs from what a naive
   win-pct-plus-point-diff sort of `data/box_scores_cache.rds` alone would produce (that naive sort
   swaps LV↔ATL at 3/4 and WSH↔IND at 5/6 vs. the real, tiebreaker-aware seeding), so the real
   seed list is hardcoded from the cited sources, not re-derived from the box-score cache. Team
   *net ratings* do come from the box-score cache (real empirical per-game point differential for
   the 2026 season, not `cache/projected_wnba_standings.rds`'s forward-looking model projection,
   since the season is actually over), run through `playoff_simulator.R`'s existing
   `get_playoff_adjusted_rating()` — which now takes its **RAPM branch**, not the fallback
   contender-leverage table: `rapm_engine.R`/`cache/rapm_ratings.rds` now exist in this repo (they
   didn't as of the `docs/task_assignments.md` note this doc's own Environment-notes history
   might lead you to expect — re-verified fresh this session, all 8 playoff teams have ≥13 real
   RAPM rows). The bracket itself is **not** a brute-force whole-bracket Monte Carlo; it's an
   analytical probability tree (every possible pairing at each round, given the fixed bracket
   structure, simulated once via `simulate_single_series()` and combined with pairing
   probabilities) — auditable, no bracket-level simulation noise. Verified internally: probabilities
   summed to exactly 1 (championship) and 2 (Final-four) before being written into the doc.
   Championship favorites as of this render: Minnesota Lynx 23.9%, Atlanta Dream 22.4%, Golden
   State Valkyries 21.0%.

**`tools/check_accuracy_since_0912.R`** — already existed, untracked, unmodified this session
(mtime 2026-09-24, predates this thread); read but not edited. If you're continuing this thread,
know this script exists and follows the same independent-reconciliation pattern Part 1 above reuses.

## Environment notes (new this session — not yet folded into `CLAUDE.md`)

- **A new, previously-undocumented hang, distinct from the two `CLAUDE.md` already documents**
  (segfault on inline multi-line `Rscript -e`; the `NOT_CRAN`/`shinytest2` `AppDriver` gotcha):
  a **plain, single-line** `Rscript.exe -e "1"` (no packages, no user code at all) spun
  indefinitely at high and climbing CPU (500-650+ CPU-seconds observed, still rising) instead of
  returning instantly. Root-caused by bisection, not guessed: `Rscript.exe --no-init-file` (skips
  `.Rprofile`, hence skips `source("renv/activate.R")`) returned instantly, so the hang is inside
  renv's activation, not R startup itself. Specifically it's **renv's sandbox-consistency check**
  — confirmed by setting `RENV_CONFIG_SANDBOX_ENABLED=FALSE` as an environment variable (a
  documented, legitimate renv option, not a hack) before invoking `Rscript.exe`/`quarto.exe`
  *with* `.Rprofile` intact: activation then completed in seconds. **Use
  `RENV_CONFIG_SANDBOX_ENABLED=FALSE` (export it, or prefix the command) for any `Rscript.exe`/
  `quarto render` invocation in this repo until someone actually fixes the underlying sandbox
  slowness** (not investigated further this session — routed around, not root-caused at the renv
  level). Worth promoting into `CLAUDE.md`'s Environment section if it recurs; not done this
  session since it's this thread's discovery, not yet confirmed as a permanent machine property.
  Side effects of the two stuck invocations before this was found: they were later killed by the
  environment's own low-memory guard (same failure class as an orphaned-`R.exe`-processes incident
  documented in `docs/archive/handoff_history.md`'s "2026-09-25 (pre-Tier-6)" section) — nothing
  was lost, but it's the same recurring low-memory/orphaned-R-process pattern this repo has now
  seen multiple times across unrelated threads, worth someone eventually investigating
  machine-wide rather than per-session.
- `renv`'s known missing-`DESCRIPTION`-file complaints for `foreach`/`hardhat`/`iterators` (printed
  on every `Rscript.exe` startup line above) are pre-existing per `renv::status()`, not something
  this session caused or fixed — same "leftover from a prior, failed installation" class of issue
  other sessions in this file have flagged for other packages; not blocking (this thread's work
  used base/`tidyverse`/`playoff_simulator.R`'s own dependencies, none of which are these three).
- `quarto.exe` is at `C:\Program Files\Quarto\bin\quarto.exe` on this machine (a standalone Quarto
  install) — **not** only at the RStudio-bundled path
  (`C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`) this file's own
  `render-and-inspect-quarto` skill section currently documents as the sole location. Both may
  exist; the standalone path is the one that was actually used and confirmed working this session.

## Concrete next step

**Superseded by the 2026-10-03 thread at the top of this file** — item 3 below (re-running Part 2
with real Round 1 results) has been done; see that section for what changed and what's still open
(two Round 1 series' Game 3s still pending real data, plus an escalated renv-corruption issue).
Original next-steps, kept for history:
1. ~~Decide whether to `git add`/commit the two new files~~ — done (committed as part of the Round-1
   update, commit `775f7c3`, pushed to `main`).
2. If the 5 still-`PENDING` 2026-09-24 regular-season rows resolve (box scores catch up), Part 1's
   N=25 real-scoreable-game count should grow to N=30 — re-run Part 1's chunks and update the
   headline numbers in the Conclusion before treating this doc as a final record. **Not done in the
   2026-10-03 update** (that session touched only Part 2) — still open.
3. ~~Once the actual 2026-09-27 Game 1 results are known, Part 2's bracket tree should be re-run
   round-by-round~~ — done for Round 1 (2 of 4 series decided, 2 tied 1-1 modeled as a single
   decisive game pending real data) in the 2026-10-03 update above.

---

# Archived history (trimmed 2026-09-26)

Everything that used to follow this point (every session from 2026-09-17 through 2026-09-26's
Round 2 Tier 5) covered **closed, completed work** — the 27-issue Round 1 roadmap, the 14-issue
Round 2 roadmap, the prediction-market alpha research (closed, no edge), the PBP-engine/
`features_cache.rds`/team-depth-signal build-out, the prediction-log data-integrity fix, and the
15-item wishlist — all fully shipped/closed, none of it a live next step. That full
session-by-session detail (bug bisections, verification transcripts, subagent-dispatch incident
writeups) has been moved verbatim to `docs/archive/handoff_history.md` (original section
headers/numbers preserved, not synced to this file's current structure — see that file's own
preamble). Read the condensed table and notes below for the still-relevant takeaways; open the
archive only if you need the full narrative behind a specific past fix.

## Closed work (one-line status each — see archive for full detail)

| Thread | Status | Where the detail lives |
|---|---|---|
| Round 1 review-remediation roadmap (`docs/review_round_1_roadmap.md`, issues #1-27) | **Closed** — all 27 issues shipped | `docs/archive/handoff_history.md`, "2026-09-25 (Tier 6)" and earlier Round-1 sections |
| Round 2 review-remediation roadmap (`docs/review_round_2_roadmap.md`, issues #29-42) | **Closed** — all 14 issues shipped | `docs/archive/handoff_history.md`, "2026-09-26 (Review Round 2, Tier 5)" and earlier Round-2 sections |
| Prediction-market alpha research (Kalshi, 4 hypotheses: game moneyline, player props, season win totals x2 versions) | **Closed, no confirmed edge on any hypothesis** — do not build staking/P&L infrastructure on these results without new evidence | Standing docs (not archived): `docs/prediction_market_alpha_research_plan.md`, `docs/prediction_market_divergence_findings.md`. Full narrative: `docs/archive/handoff_history.md`, "2026-09-17 (Pausing here)" and its "Follow-up" subsections |
| PBP engine / `features_cache.rds` fix / team-depth signal (`pbp_engine.R`, `roster_bottom_up_engine.R`, `player_metrics.R`) | **Shipped, live in production** | Standing docs: `docs/pbp_shot_mix_regression_findings.md`, `docs/team_depth_signal_regression_findings.md`. Full narrative: `docs/archive/handoff_history.md`, "2026-09-17 (Play-by-Play Model Extension...)" |
| Prediction-log `predicted_margin` NA bug + `WNBA_GAME_N` fixture-misclassification gap | **Both fixed** (sessions 2026-09-18/19) | `docs/archive/handoff_history.md`, "2026-09-19" sections |
| 15-item improvement wishlist | Items 1-5, 8-10 **shipped**; remainder tracked in `docs/future-work.md` (standing doc, not archived) | `docs/archive/handoff_history.md`, "2026-09-19 (third/fourth session)" |

## Standing environment/tooling notes (recurring across many past sessions, still live)

- **Pandoc is not on `PATH`/`RSTUDIO_PANDOC` by default in a bare `Rscript.exe` shell** on this
  machine. Before any `rmarkdown::render()`/knit from such a shell:
  `Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")`.
  A standalone Quarto install also exists at `C:\Program Files\Quarto\bin\quarto.exe` (not just
  the RStudio-bundled one at `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`).
- **`renv` is active project-wide** (`.Rprofile` sources `renv/activate.R`). The **machine-wide**
  shared renv package cache has been found wiped/corrupted more than once (suspected cause:
  something in a `subagent-brief` worktree's cleanup step, never fully root-caused) — if
  `renv::status()` reports packages "missing their DESCRIPTION files," `renv::restore(prompt =
  FALSE)` is idempotent and safe to re-run repeatedly until it reports clean.
- **`isolation: "worktree"` has repeatedly branched a dispatched subagent from a stale `main`**
  in this repo (at least 5 separate incidents documented across both review roadmaps). Always run
  `git log HEAD..main --oneline` in the worktree before merging; if non-empty, rebase and resolve
  by hand yourself — never let a subagent resolve its own stale-base merge.
- Leftover `.claude/worktrees/<hash>/` directories can accumulate as inert disk cruft after
  `subagent-brief` dispatches (Windows file-lock on cleanup) — harmless, not deleted without
  explicit user confirmation.

---
