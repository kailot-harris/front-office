# HANDOFF.md archive — closed/superseded session history

Moved here 2026-09-26 during a `docs/HANDOFF.md` trim (via the `trim-handoff` skill). This file
is **non-load-bearing history** — nothing here should be read to determine current project state
or the next unit of work. Everything below was, at the time this trim happened, either fully
closed/shipped work or a superseded intermediate "current state" snapshot from a session that has
since been superseded by a later one.

Section headers, numbering, and all cross-references (commit hashes, issue numbers, "see the
section above/below" pointers) are preserved **exactly as originally written** — they do not
match `docs/HANDOFF.md`'s current structure, and are not being kept in sync with it. This is
intentional: old commit messages, PR/issue comments, and prior HANDOFF sections may cite this
content by its original wording, so an exact-text match here keeps it grep-able. Do not edit this
file to "fix" a stale cross-reference; if you need current state, `docs/HANDOFF.md` is the only
place that's kept accurate.

For a condensed, current-state summary of everything archived below, see
`docs/HANDOFF.md`'s "Closed work" table and "Standing environment/tooling notes" section (added
during this same trim).

---

# Handoff — 2026-09-26 (Review Round 2, Tier 5 — ROADMAP COMPLETE) — CURRENT STATE (read this section first, supersedes everything below)

**All 14 issues (#29-#42) of `docs/review_round_2_roadmap.md` are now closed.** Tier 5 (#41, #42)
was the last tier; see "What this session did (#41-42, Tier 5)" below for what happened and a
recurring environment bug (stale worktree base) worth knowing about before dispatching any future
`subagent-brief` work in this repo. The section immediately below (originally written as the
Tier 4 current-state section) is kept for its Tier 1-4 history/table but is otherwise superseded
by this paragraph.

# Handoff — 2026-09-25 (Review Round 2, Tier 4) — superseded by the Tier 5 section above

**For whoever picks this up next with zero prior context:** this repo (`WNBA Analytics`) is a
WNBA sports-analytics/betting pipeline — team/player rating models, market-odds integration, a
Shiny dashboard (`app.R`), and a separate academic-submission deliverable,
`WNBA_Analysis_Project.Rmd`, which is the *only* file this entire thread touches. Read this repo's
`CLAUDE.md` first (data quirks, config-constant discipline, environment gotchas that apply
everywhere in the repo); it is not superseded by anything below. This section of `HANDOFF.md`
then covers only the current thread: implementing `docs/review_round_2_roadmap.md`'s 14-issue
review of `WNBA_Analysis_Project.Rmd`. The rest of this very long, append-only file is a
chronological archive of every earlier thread (the pipeline/dashboard work, and the prior
27-issue Round 1 roadmap) — each dated section below states in its own header whether it's
superseded; don't treat anything below this section as current without checking that.

**This section supersedes every pointer further down this file, including the "Tier 6" section
immediately below it.** New thread, same document: `docs/review_round_2_roadmap.md` is a fresh
14-issue re-review of `WNBA_Analysis_Project.Rmd`, run after the Round 1 roadmap (the 27 issues
covered by the rest of this file) was fully closed on 2026-09-25. Round 2 is **not** a re-check of
Round 1's items — it's a new pass over the document as it now stands. Read
`docs/review_round_2_roadmap.md` for the full finding text; this section only tracks
implementation status and per-session verification evidence.

## Where the thread actually stands (verified against `gh issue list`, not assumed from docs)

**All 14 issues are closed. The Round 2 roadmap is complete.**

| Tier | Roadmap items | Issues | Status |
|---|---|---|---|
| 1 — Correctness bugs | 1, 2 | #29, #30 | Closed — commit `211c5c0` |
| 2 — Reproducibility | 3, 4, 5 | #31, #32, #33 | Closed — commit `956b5f9` |
| 3 — Integration/narrative | 6, 7, 8, 9 | #34, #35, #36, #37 | Closed — commit `7127711` |
| 4 — Visualization | 10, 11, 12 | #38, #39, #40 | Closed — commit `2267484` |
| 5 — Code quality | 13, 14 | #41, #42 | Closed — commit `528b455` |

## What this session did (#41-42, Tier 5) via `subagent-brief`

Two full-brief dispatches were needed. **The first (run `20260926-002636-586b30`) hit the
stale-worktree-base bug for the third time this roadmap** (after Tiers 2 and 4) — its
`isolation: "worktree"` agent was silently branched from commit `44ef8e0` (9 commits behind
`main`, the same pre-Tier-1-3 commit implicated in the Tier 4 incident), not current `main`. This
time, unlike Tier 4, the subagent **did not self-resolve** the mismatch — it correctly returned
`status: blocked` after being prompted to re-check its own stale-base output (it had misread `git
log HEAD..main --oneline`'s non-empty output as confirmation the check was clean). That is the
correct subagent behavior this file has been asking for since the Tier 4 incident. But the
work was still unusable as-is: refactoring `build_feature_df()`'s `mean_regress`/`decay` branch
against that stale base silently dropped Tier 1's issue #30 fix (the
`league_season_means`/`prior_season_lookup`/`league_prior_means`/`prior_lm_*` mechanism), reverting
to the pre-#30 bug (`mean(team_score, na.rm = TRUE)` inside `group_by(team_id)` — each team's own
all-history mean instead of the prior season's league-wide average). That worktree was kept at
`.claude/worktrees/agent-a7e4dc6b1b436249f` (reason: `blocked`) rather than deleted or merged.

**Given three stale-base incidents in a row, the orchestrator stopped trusting `isolation:
"worktree"` to branch from the right commit and instead created the worktree manually**
(`git worktree add .claude/worktrees/tier5-retry -b worktree-tier5-retry main`, confirmed
`git rev-parse HEAD` == current `main` before dispatch) for the second dispatch (run
`20260926-032020-87b620`), and pointed the subagent at that fixed path instead of letting it
create its own. That run succeeded, and — unlike some earlier tiers — the orchestrator
independently re-derived (not just re-read) the subagent's key claim before merging: re-diffed
the `mean_regress`/`decay` league-mean block against `main` (byte-identical), and independently
ran `build_feature_df()` for all three offseason methods against both the pre- and post-refactor
chunk in isolation, confirming `all.equal()` was `TRUE` for all three (`reset`, `mean_regress`,
`decay`) rather than trusting the subagent's own claimed comparison. `vip`'s renv.lock entry and
the caveat-paragraph rewrite were also independently grep-verified.

| Issue | What | Verified how |
|---|---|---|
| #41 | The ~20-line eFG%/TOV%/FTR/TS%/`roll_*` block, previously duplicated verbatim between `build_feature_df()`'s `reset` and `mean_regress`/`decay` branches, factored into one `compute_rolling_features(df, window_size)` helper called from both. The `league_season_means`/`prior_season_lookup`/`league_prior_means`/`prior_lm_*` mechanism (Tier 1's #30 fix) was left untouched. | Targeted diff of that region between `main` and the edited chunk returned no differences; orchestrator ran `build_feature_df(box_scores, ROLLING_WINDOW_SIZE, method)` for `reset`/`mean_regress`/`decay` against both the pre- and post-refactor `calc-features-function` chunk loaded into separate environments — `all.equal()` was `TRUE` for all three, matching dimensions (1927x45, 1969x45, 1969x45 respectively). |
| #42 | Added a `feature-plots-permutation` chunk calling `vip::vi_permute(rf_fit, ..., metric = "accuracy", nsim = 10)` for a second, less-biased top-10 importance chart alongside the existing Gini-impurity chart; pinned `vip@0.4.2` in `renv.lock` (`vip` was archived from live CRAN on 2025-12-02 — installed via `renv::install("vip@0.4.2")` against the CRAN Archive, not a bare `renv::install("vip")`); rewrote the caveat paragraph to describe both charts instead of claiming `vip` was uninstalled. | `grep -n '"vip"' renv.lock` shows the pinned entry (single clean 60-line addition, confirmed via `git diff --stat` — no unrelated `renv.lock` drift); `grep -n "not currently an installed" WNBA_Analysis_Project.Rmd` returns no match; subagent's full render (37/37 chunks, PDF, both charts visually confirmed) was not independently re-run by the orchestrator but is consistent with the independently-verified code correctness above. |

Fast-forward merged to `main` as `528b455` (worktree committed directly, no conflicts since it was
correctly branched from current `main`). Closed #41-#42 via `gh issue close`. The
`tier5-retry` worktree's git registration was removed cleanly; its on-disk directory survived
(same Windows file-lock pattern as three other leftover directories under `.claude/worktrees/`,
none deleted without user confirmation). The blocked worktree
(`.claude/worktrees/agent-a7e4dc6b1b436249f`) remains kept, untouched, for reference.

**Takeaway for future `subagent-brief` dispatches in this repo:** `isolation: "worktree"` has now
mis-branched from a stale base in 3 of 5 Round-2 tiers (2, 4, 5), always landing on commit
`44ef8e0` or thereabouts. Until that's root-caused, prefer creating the worktree yourself
(`git worktree add <path> -b <branch> main`, verify `git rev-parse HEAD` before dispatch) and
pointing the subagent at the fixed path, rather than trusting the tool's own worktree creation.
Separately, subagents in this repo have twice now tried to "wait for a background monitor
notification" between turns and gotten stuck doing nothing, because nothing wakes a subagent
back up once its turn ends unless it has a live background child — tell any future brief
explicitly to poll synchronously within a turn (or finish with an honest partial-status result)
instead of ending a turn "holding."

All 14 issues were filed in the Tier 1-2 session (they didn't exist before — `gh issue list`
previously topped out at #28). Issue numbering matches roadmap item numbering minus 28 (item 1 =
#29, item 14 = #42) — useful for cross-referencing `docs/review_round_2_roadmap.md`'s numbered list
directly.

## What this session did (#38-40, Tier 4) via `subagent-brief`

One full-brief `subagent-brief` dispatch (`.subagent-runs/brief_tier4.md`, run
`20260925-233758-123413`) in its own isolated git worktree.

**Process deviation caught and fixed — read this before trusting any future Tier 4/5 worktree
without re-checking:** the subagent's worktree was silently branched from a stale pre-Tier-1-3
base (`44ef8e0`, the commit right after Round 1 closed), not current `main`. The subagent noticed
this itself mid-task (its own `git diff main` showed Tiers 1-3's code missing), and — contrary to
this file's own documented rule ("don't let a subagent do this — it doesn't have the context of
what changed on `main` since its branch point") — resolved the resulting 3-way merge conflict
itself rather than stopping and returning `blocked`. The orchestrator did not treat the subagent's
self-report of success as sufficient: independently re-diffed the subagent's merge resolution
(`git diff main HEAD -- WNBA_Analysis_Project.Rmd` in the worktree) and confirmed it touched only
the three intended `ggplot` chunks with zero disturbance to Tier 1-3 content, so the resolution was
accepted rather than redone from scratch. Separately, that same merge had dropped
`data/window_sweep_3_25_results.csv`/`.hash` from git's index (left as untracked regenerated files
on disk) — caught via `git status --short` before merging, fixed by re-`git add`ing and
re-committing both files (verified the CSV's point-estimate columns and the hash's md5sum both
still matched the pre-Tier-4 baseline/current `box_scores_cache.rds` before doing so).
**Takeaway: subagents in this repo should never resolve a stale-base merge on their own — if a
worktree brief's assumed branch point turns out wrong, the correct subagent behavior is `blocked`,
not self-resolution, even when the fix looks obviously correct in hindsight.**

| Issue | What | Verified how |
|---|---|---|
| #38 | Added `fig.cap` to all three `ggplot()` chunk headers (`window-size-experiment`, `feature-plots`, `ridge-plot`), each with a short descriptive caption matching this document's existing table-caption tone. | `grep -n "fig.cap"` shows exactly 3 matches, one per chunk; fresh render shows numbered figure captions ("Figure 1/2/3: ...") under each plot in the rendered PDF. |
| #39 | Ridge plot's `fill = team_name` now routes through `scale_fill_viridis_d()` (colorblind-safe, perceptually uniform) instead of ggplot2's default categorical hue palette. `viridisLite` was already a transitive dependency (via ggplot2/scales), so `renv.lock` needed no change. | `grep -n "scale_fill_viridis_d"` shows it added to the ridge-plot chunk's layer chain; visually confirmed in the re-rendered PDF. |
| #40 | `eval_window_size()` now bootstrap-resamples (200 draws, with replacement) the already-computed held-out `preds` per window size, recomputes `roc_auc()` on each resample, and takes the 2.5th/97.5th percentiles as a 95% CI (`ROC_AUC_CI_Lower`/`ROC_AUC_CI_Upper`, new columns) — seeded via `digest::digest2int()` + a nested `withr::with_seed()` composing with the existing per-iteration seed from issue #31. Plotted as a `geom_ribbon()` band around the existing ROC-AUC line. Existing `Accuracy`/`ROC-AUC`/`Brier Score` point estimates are byte-identical to the pre-edit baseline — only new columns were added. | `grep -n "geom_ribbon"` shows the new layer; re-running the sweep twice (deleting the staleness sidecar between runs) produced byte-identical CSVs, confirming deterministic seeding; window=3/4 rows' `Accuracy`/`ROC-AUC`/`Brier Score` values diffed identical against `git show main:data/window_sweep_3_25_results.csv`. |

Fast-forward merged to `main` as `2267484` (after the orchestrator's fix-up commit on top of the
subagent's merge). Closed #38-#40 via `gh issue close N --comment "..."` citing the commit and this
session's run ID, with a note about the process deviation above. Git-worktree registration for
`.claude/worktrees/agent-a8e25c3957ee0186e` was removed (`git worktree remove` + `git branch -d`),
but the directory itself survived — same Windows file-lock pattern already flagged for two other
leftover directories below (`agent-a7b9acfce9fb44490`, `agent-af10fe384664826e6`); now three inert,
unregistered leftover directories exist under `.claude/worktrees/`, none deleted without user
confirmation.

## What this session did (#34-37, Tier 3) via `subagent-brief`

One full-brief `subagent-brief` dispatch (`.subagent-runs/brief_tier3.md`, run
`20260925-231216-3efd00`) in its own isolated git worktree, branched cleanly from `main` after the
Tier 1-2 merges (confirmed via `git log HEAD..main --oneline` returning empty both before dispatch
and again at merge time — no stale-base issue this time, unlike the prior two tiers).

| Issue | What | Verified how |
|---|---|---|
| #34 | Introduction's hardcoded "3,906 real team-game rows" replaced with a live inline `` `r nrow(box_scores)` `` expression (`WNBA_Analysis_Project.Rmd:41`). Since `box_scores` was previously only defined later in the `import-box-scores` chunk, an equivalent cache-first-load block (mirroring that chunk's own `normalize_team_abbreviation()` logic, with a comment pointing to it) was added to the earlier `setup` chunk so the value is available for the Introduction's inline expression. | `grep -n "3,906\|3906"` returns no match; `grep -n "nrow(box_scores)"` shows it used inline at line 41; a fresh render shows the live count (3916, reflecting Tier 1's CONN-normalization fix) instead of the stale 3,906. |
| #35 | Internal engineering bookkeeping (`task_assignments.md`, `wnba_rating_engine_agent`, "T2"/"T0/T1" codenames) removed from the Introduction and the Data Ingestion narrative sentence, rephrased to describe what the cache validates/normalizes without citing the internal tracking doc. All `# Issue #N:` code-maintenance comments (Tier 1/2's own, e.g. `# Issue #29:`, `# Issue #23:`) were explicitly left untouched, per this brief's clarification that #35's intent is the academic narrative, not maintenance comments. | `grep -n "task_assignments\|wnba_rating_engine_agent\|T2 /\|T0/T1"` shows only one remaining match, line 927 in the Conclusion's process-notes paragraph (out of this brief's scope); `git diff -- WNBA_Analysis_Project.Rmd \| grep "Issue #"` returns no output, confirming zero maintenance comments changed. |
| #36 | Long " - "-chained sentences in the Introduction (`:15-33`) and the window-size-sweep results-framing paragraphs (`:446-463` pre-edit) split into single-idea sentences, with every fact/qualifier preserved (82-game/30-team NBA vs. 44-game/15-franchise WNBA, the three re-tested modeling choices, the {5,7,9,11,13}-vs-full-3-25-sweep comparison, the single-split/non-cross-validated caveat, the `ML_BENCHMARK_REPORT.md` CV follow-up note). | Read the diff directly (`git diff main..worktree-agent-ae400f7cf8130ae91 -- WNBA_Analysis_Project.Rmd`); every clause from the pre-edit version appears in the post-edit version, just sentence-split. |
| #37 | The "A note on this document's provenance" paragraph rewritten to state the same facts (2026-09-24 render date, `rmarkdown::render()` command, TinyTeX/MiKTeX toolchain, what the tables are, re-render instructions, `ADR.md` Principle I) without the defensive rebuttal framing ("read before trusting any number below", "not a copy-pasted stand-in", "rather than trusted indefinitely"). | Read the edited paragraph directly; all factual claims present, rebuttal phrasing removed. |

Fast-forward merged to `main` as `7127711` (no conflicts — worktree was current with `main`). Closed
#34-#37 via `gh issue close N --comment "..."` citing the commit and this session's run ID.
Worktree and branch (`.claude/worktrees/agent-ae400f7cf8130ae91`,
`worktree-agent-ae400f7cf8130ae91`) removed after merge.

## Concrete next step (superseded — see the Tier 5 current-state section at the top of this file)

Tier 5 (#41, #42) is now done; the Round 2 roadmap is complete. See the top of this file for
what happened, including a third stale-worktree-base incident.

## What this session did (#29-33, Tiers 1-2) via `subagent-brief`

Two separate `subagent-brief` dispatches, one per tier, each as a single full-brief agent in its
own isolated git worktree — same one-tier-per-worktree pattern Round 1 used for its later tiers.

**Tier 1 (`.subagent-runs/brief_tier1.md`, run `20260925-184256-03b2d0`):**

| Issue | What | Verified how |
|---|---|---|
| #29 | The no-cache box-score fallback branch (`WNBA_Analysis_Project.Rmd:82-99`, the `else` of `if (file.exists(CACHE_TEAM_BOX))`) now `source("player_metrics.R")`s and calls `normalize_team_abbreviation()` on the raw `wehoop::load_wnba_team_box()` output before filtering to `names(WNBA_TEAMS)`, fixing the reintroduced CONN→CON Connecticut Sun data-loss bug on a fresh checkout with no pre-existing cache. | Synthetic reproduction (CONN rows 2019-2023 + CON 2024-2026 + one exhibition row) run through both the old and new filter logic in a temp `.R` file: old logic dropped all 5 CONN-era rows, new logic retains all 8 real franchise rows and drops only the exhibition row. Independently re-verified: `grep -n normalize_team_abbreviation` shows the call at line 96 inside the fallback branch. |
| #30 | `build_feature_df()`'s `mean_regress`/`decay` offseason-transition code (`WNBA_Analysis_Project.Rmd:169-245`) now computes `league_season_means` grouped only by `season` (a true across-team average, replacing the old `group_by(team_id)` mean of a team's own history) and joins each new-season row to the immediately **prior** season's league mean only (via a `season_order`/`prior_season_lookup` join, not `season - 1` arithmetic) — fixing both the wrong regression target (team's own mean, not league average) and the look-ahead leak (previously used the full column including future seasons). | Hand-computable synthetic 2-team/2-season dataset in a temp `.R` file: true 2025 cross-team league mean (67) matched `league_season_means` exactly (not either team's own mean of 72 or 62); every 2026 transition row's `prior_lm_team_score` was exactly 67 with zero dependence on any 2026 value. Independently re-verified by reading `WNBA_Analysis_Project.Rmd:181-212` directly. |

**Tier 2 (`.subagent-runs/brief_tier2.md`, run `20260925-221129-0d9bdd`):**

| Issue | What | Verified how |
|---|---|---|
| #31 | Both `map_dfr()` sweeps (window-size at ~298, offseason method at ~424) now seed each iteration independently via `withr::with_seed(iter_seed, {...})`, with `iter_seed` derived from that iteration's own parameter (window size or method name) via `digest::digest2int()`, instead of one blanket `set.seed(42)` for the whole sweep. `library(withr)` added to the package-load chunk. | Two independent full sweep recomputes (forcing recompute by deleting the staleness sidecar between runs) produced byte-identical CSVs. |
| #32 | Added `is_window_sweep_csv_fresh(csv_path, hash_path, box_cache_path)` (`WNBA_Analysis_Project.Rmd:331-344`): compares an `tools::md5sum()` of `CACHE_TEAM_BOX` (read from `config.R`, not hardcoded) against a sidecar hash file `data/window_sweep_3_25_results.hash`, written alongside the CSV each time it's regenerated. Fail-safe default is `FALSE` (recompute) if the CSV, sidecar, or box cache is missing/unreadable. | Read the function directly; confirmed both branches empirically — a missing/stale sidecar triggers recomputation and rewrites both the CSV and sidecar, an untouched matching sidecar reuses the CSV (render time dropped from ~42s to ~22s on the cached path). |
| #33 | All three hand-pasted "Actual result" tables (window-size sweep ~426-435, offseason comparison ~514-521, model benchmark ~597-603) replaced with live `knitr::kable()` calls reading the same variable (`window_size_results`/`offseason_results`/`benchmark_results`) the chunk above computed, plus inline `` `r` `` expressions for narrative numbers (e.g. `` `r offseason_best_name` ``, `` `r offseason_best_row$"ROC-AUC"` ``) driving the surrounding prose. These numbers can no longer silently drift from what the live code produces. | `grep -n "Actual [Rr]esult"` shows each location now precedes a `kable(` call reading a live variable, not a literal number table; full render's output at each location matches the live chunk by construction (they're the same object). |

**Merge-conflict note:** the Tier 2 worktree was branched from `main` *before* Tier 1's `211c5c0`
merge landed (confirmed via `git log HEAD..main --oneline` showing `211c5c0` missing from the
worktree's history) — the exact stale-base failure mode flagged in the Tier 6 section below.
Caught before merging: `git stash`ed the Tier 2 working-tree changes, `git rebase main` (fast, no
worktree commits to replay), then `git stash apply` — one real content conflict resulted at
`WNBA_Analysis_Project.Rmd`'s offseason "Actual result" section, because Tier 1 hand-pasted a
corrected number table there and Tier 2 independently replaced that same table with a live
`kable()`/inline-`r` version. Resolved by keeping Tier 2's version: it reads the same
already-Tier-1-corrected `offseason_results` object, making it a strict superset of Tier 1's fix,
not a conflicting one. Re-rendered after resolution to confirm the merged document still knits.
**Anyone dispatching another `subagent-brief` worktree for this repo should keep checking `git log
HEAD..main --oneline` before merging — this is the second time in this repo's history (see the
Tier 6 section below for the first) that a worktree was silently based on a stale `main`.**

## Environment notes (new this session)

- Same `RSTUDIO_PANDOC` gap as every prior session in this repo: no `pandoc` on `PATH` in a bare
  `Rscript.exe` shell. Both subagents and the orchestrator's own verification pointed
  `RSTUDIO_PANDOC` at `C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools` (the
  RStudio-bundled pandoc, confirmed present via `find "/c/Program Files/RStudio" -iname
  pandoc.exe`).
- Tier 2's `withr` dependency was already pinned in `renv.lock` (top-level entry, 3.0.3) but not
  physically installed in that worktree's private `renv` library — `renv::install/renv::restore`
  linked it in from the shared package cache without needing `renv::snapshot()` (confirmed
  `git diff --stat renv.lock` was empty after the merge).
- **Disk cruft found, not cleaned up (flagging per policy, not fixing silently):** two directories
  under `.claude/worktrees/` — `agent-a7b9acfce9fb44490` and `agent-af10fe384664826e6` — are
  leftover checkout copies with **no matching entry in `git worktree list`** (their
  `.git/worktrees/<id>` admin metadata was removed when the Tier 2 worktree was torn down, but the
  working-directory copies survived because Windows reported the folder as busy/locked, likely a
  lingering agent process handle). They're inert (not tracked by git as active worktrees) but still
  consume disk space. A third, `.claude/worktrees/agent-a6cc7eaf0b38f47c9`, **is** a real registered
  worktree (`git worktree list` shows it `locked`, HEAD at `03d50f5` — a Tier 5 leftover, predates
  this session). None of these were deleted — removal wasn't confirmed by the user this session.
- `.subagent-runs/` briefs for Tiers 1-2 (`brief_tier1.md`, `brief_tier2.md`) are the exact text
  dispatched; results are recorded under each run's own directory
  (`.subagent-runs/20260925-184256-03b2d0/`, `.subagent-runs/20260925-221129-0d9bdd/`), both marked
  `merged` via `runlog.R set-status`.

## The reusable workflow for the remaining tiers (#34-42)

1. Read the roadmap item(s) for the tier in `docs/review_round_2_roadmap.md` — re-verify its line
   numbers against the *current* `WNBA_Analysis_Project.Rmd` yourself before writing a brief; line
   numbers have already drifted twice (Tier 1's and Tier 2's own edits shifted everything after
   them by dozens of lines).
2. Write a `subagent-brief` full-brief (`.subagent-runs/brief_tierN.md`), validate it
   (`validate_brief.R`), register it (`runlog.R new-run`), dispatch into an isolated worktree.
3. **Before merging, always run `git log HEAD..main --oneline` in the worktree.** If it's non-empty,
   `git stash` the worktree's changes, `git rebase main`, `git stash apply`, resolve any conflict
   by hand (don't let a subagent do this — it doesn't have the context of what changed on `main`
   since its branch point), and re-render before merging. This has now bitten two tiers in a row on
   this repo across two different roadmaps.
4. Verify at least one cited criterion yourself (re-run a command or re-read a `file:line`) before
   merging — don't trust a subagent's self-reported `success` status alone.
5. Merge (fast-forward when possible), close the tier's GitHub issues with `gh issue close N
   --comment "..."` citing the merge commit and verification method, `runlog.R set-status --status
   merged`, clean up the worktree (`git worktree remove`, `git branch -d`).

## Concrete next step

**Tier 3 — Integration/narrative (issues #34, #35, #36, #37; roadmap items 6-9).** All four are
prose/comment edits to `WNBA_Analysis_Project.Rmd`, no code-behavior changes, so this tier should
be lower-risk than Tiers 1-2 but touches more scattered locations:
- #34 (item 6): derive the Introduction's hardcoded row count (was "3,906 real team-game rows" as
  of the original roadmap text, `:28` pre-Tier-1/2 edits — re-verify the current line and current
  count) from a live `` `r nrow(box_scores)` `` expression.
- #35 (item 7): strip issue numbers, agent codenames, and `task_assignments.md` references out of
  prose and code comments — this **will** collide with Tier 1/2's own newly-added comments (e.g.
  the `# Issue #29:` / `# Issue #30:` / `# Issue #31:` comments this session just added) since those
  are exactly the pattern #35 asks to remove from *reader-facing prose*, but the roadmap's intent
  (re-read item 7 carefully) is about the **academic narrative sections** a grader reads standalone,
  not inline code comments documenting a fix for the next engineer — clarify this distinction in the
  Tier 3 brief so the subagent doesn't strip legitimate maintenance comments.
- #36 (item 8): break up long em-dash-heavy sentences in the Introduction/results framing.
- #37 (item 9): tone down the "provenance" paragraph's defensive framing.
After Tier 3, two tiers remain: Tier 4 (visualization, #38-40 — `fig.cap`, colorblind-safe ridge
plot palette, uncertainty bands on the window-size sweep chart) and Tier 5 (code quality, #41-42 —
factor the duplicated feature-computation block, pin `vip` for permutation importance).

---

# Handoff — 2026-09-25 (Tier 6) — Round 1 CURRENT STATE at the time it was written (superseded above)

**This section supersedes every pointer further down this file, including the "Written after
commit `03d50f5`" section immediately below it.** Same review-remediation thread: implementing
the 27-issue roadmap in `docs/review_round_1_roadmap.md` against `WNBA_Analysis_Project.Rmd`
(repo root). This is the **final tier of that roadmap** — all 27 issues are now closed. Still a
**separate thread** from the pipeline/dashboard work covered by the rest of this file (2026-09-19
and earlier).

## Where the thread actually stands (verified against `gh issue list`, not assumed from docs)

**All six tiers (#1-27) are done. The review-remediation roadmap is complete.**

| Tier | Issues | Status |
|---|---|---|
| 1 — Reproducibility | #1-7 | Closed |
| 2 — Correctness bugs | #8, #9, #10 | Closed |
| 3 — Integration/consistency | #11, #12, #13 | Closed |
| 4 — Narrative | #14, #15, #16, #17 | Closed (commit `58f5ca8`) |
| 5 — Visualization | #18, #19, #20, #21 | Closed (commit `03d50f5`) |
| 6 — Code quality | #22-27 | **Closed this session — commit `12ebd9c`** |

## What this session did (#22-27, Tier 6) via `subagent-brief`

Dispatched via the `subagent-brief` skill as a single full-brief agent in an isolated git
worktree, following the same pattern as Tiers 4/5. **Found the worktree's branch was based on an
older commit than `main`** (missing Tier 5's `03d50f5`/`25cf89c` Rmd and HANDOFF changes) before
committing — rebased onto `main` first (`git rebase main`, one binary conflict on
`WNBA_Analysis_Project.pdf` resolved by taking `main`'s copy and re-rendering fresh; the `.Rmd`
text itself auto-merged with zero conflicts, confirming Tier 6's edits and Tier 5's edits touched
disjoint regions of the file). **Anyone dispatching another `subagent-brief` agent into a fresh
worktree for this repo should check `git log HEAD..main --oneline` before committing** — this repo
has had multiple concurrent worktrees per tier and a stale branch base is an easy way to silently
revert a previous tier's work on merge.

| Issue | What | Verified how |
|---|---|---|
| #22 | Extracted the ~20-line `step_rm()` exclusion list + `step_normalize()` call (duplicated identically across `window-size-experiment`, `offseason-comparison`, `model-benchmarks`) into one `build_wnba_recipe(train_data)` function, defined once right after `build_feature_df()` in the `calc-features-function` chunk. All three chunks now call `rec <- build_wnba_recipe(train_data)` / `wnba_recipe <- build_wnba_recipe(train_data)` instead of redefining the list. | `grep -n "step_rm("` shows exactly one definition site; `grep -n "build_wnba_recipe"` shows the function def plus three call sites. |
| #23 | `build_feature_df()`'s `inner_join(home_df, away_df, by = "game_id")` now passes `relationship = "one-to-one"` (dplyr 1.2.1 installed here, well past the 1.1.0 minimum) so a duplicate-row cardinality violation errors loudly instead of silently fanning out rows. | Confirmed `packageVersion("dplyr")` is 1.2.1 via a temp `.R` file; render still completes with the same row counts as before, meaning no violation exists in the real data. |
| #24 | Investigated rather than blindly coerced: `readRDS(CACHE_TEAM_BOX)$team_id` is already native `integer` (`str()` output: `int [1:3916] 3 20 5 9 11 14 16 18 19 8 ...`), and `home_team`/`away_team`/`current_season_df`/`sched_sim`/`predictions_sim` all derive that column via `select()`/mutate-preserving joins with no intervening character coercion anywhere in the pipeline. `team_lookup`'s explicit `as.integer(team_id)` is therefore a no-op on real data, not a fix for an active bug. No coercions added elsewhere (would be a no-op change, and adding dead code isn't the fix the issue asked for) — closed with this evidence instead. | Temp `.R` file: `source("config.R"); box_scores <- readRDS(CACHE_TEAM_BOX); class(box_scores$team_id); str(box_scores$team_id)`. |
| #25 | `build_feature_df()` now captures `n_before_dropna <- nrow(joined_df)` before the `mutate() |> drop_na()` chain and `n_after_dropna <- nrow(model_df)` after, then `message()`s the counts (e.g. "removed 51 of 1958 joined rows (1907 retained)"). Used plain `message()`, not `cli::cli_inform()` — `cli` is present transitively via `renv.lock` but never `library()`-loaded in the Rmd, and the brief said prefer no new dependency surface. | Ran the extracted function standalone via `knitr::purl()` + `eval()`; confirmed the message fires: `build_feature_df(window_size=12, method=reset): drop_na() removed 51 of 1958 joined rows (1907 retained)`. |
| #26 | `monte-carlo-sim` chunk's `team_wins_matrix <- sapply(teams_vec, function(t_id) {...})` replaced with `vapply(teams_vec, function(t_id) {...}, FUN.VALUE = numeric(n_sims))`, producing the identical `n_sims x length(teams_vec)` matrix shape the downstream `as.vector(team_wins_matrix)` / `sim_results` tibble construction expects. | `grep -n "sapply("` no longer matches this chunk; `grep -n "vapply("` shows the replacement; full render produced the same Monte Carlo standings numbers (Lynx mean 31.2, 95% CI 25-37) as the pre-edit baseline. |
| #27 | `dynamic-simulation` chunk's `sched_list <- list(); for (i in 1:n_teams) {...; sched_list[[i]] <- tibble(...)}; sched_sim <- bind_rows(sched_list)` replaced with `sched_sim <- purrr::map_dfr(1:n_teams, function(i) {...})`, iterating `1:n_teams` in the same order (preserving the `set.seed(42)`-seeded `sample()` draw sequence from issue #10's balanced-round-robin fix, unchanged). | `grep -n "sched_list\[\[i\]\]"` no longer matches; `grep -n "map_dfr"` shows the replacement; rendered standings tables (Table 4/5, analytical + Monte Carlo) match the pre-edit baseline exactly. |

**Behavior-preservation check (per the brief's stop condition):** re-rendered end-to-end twice
(once before discovering the stale rebase base, once after) and diffed every "Actual result"
pasted-prose table against the freshly-rendered `kable()` output. `window-size-experiment` (loads
from `data/window_sweep_3_25_results.csv`, untouched) and `model-benchmarks` matched exactly.
`offseason-comparison`'s `mean_regress`/`decay` rows do **not** match the pasted prose table
(reset matches; `mean_regress` live-renders 0.615/0.663/0.230 vs. the pasted 0.632/0.658/0.232;
`decay` live-renders 0.605/0.651/0.234 vs. the pasted 0.618/0.656/0.233) — **but this mismatch is
pre-existing, not caused by this session's edit.** Verified by extracting the *original,
pre-Tier-6* `build_feature_df()`/`eval_offseason_method()` code from git history and running it
standalone in the same environment: it reproduces the identical live numbers (0.615/0.663/0.230
and 0.605/0.651/0.234), proving the pasted prose table in the document was already stale before
this session touched anything. Left as-is — re-matching a pasted table to a fresh render is a
Tier 1/3 reproducibility concern (already closed), not a Tier 6 code-quality one, and is out of
this session's scope. Flagging here rather than silently leaving it undocumented.

All six closed via `gh issue close N --comment "..."` referencing this session's commit and the
verification method above.

## Environment notes (new this session)

- Same `renv` cache-wipe failure mode as the last two sessions (`Package 'here' is required...`
  on first `Rscript.exe` invocation) — `renv::restore(prompt = FALSE)` repaired it in ~1s (packages
  were present in the shared cache, just not linked into this worktree's private library). This is
  now three sessions in a row hitting this on a fresh `subagent-brief` worktree; worth someone
  eventually isolating the root cause rather than continuing to route around it per-session.
- Confirmed (again) `RSTUDIO_PANDOC` must be set by hand in a bare `Rscript.exe` shell:
  `Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")`.
- `pdfcrop.exe did not succeed` warnings during knit (three of them, once per `ggplot2` chunk) are
  cosmetic MiKTeX image-cropping failures, not knit errors — render still completes and produces a
  valid PDF; `Quitting from`/`Error in` grep on the render log returns zero matches.

## Concrete next step

**None — the 27-issue roadmap is complete.** Any further work on `WNBA_Analysis_Project.Rmd`
should start a new roadmap/tier rather than assuming there's an open item left in
`docs/review_round_1_roadmap.md`.

---

# Handoff — 2026-09-25 (pre-Tier-6) — superseded, kept for the Tier 4/5 record below

**This section is stale — see the section above for current tier status.** Written after commit
`03d50f5`.

## Where the thread actually stands (verified against `gh issue list`, not assumed from docs)

**Tiers 1-5 are done. Tier 6 (Code quality) is next.**

| Tier | Issues | Status |
|---|---|---|
| 1 — Reproducibility | #1-7 | Closed |
| 2 — Correctness bugs | #8, #9, #10 | Closed |
| 3 — Integration/consistency | #11, #12, #13 | Closed |
| 4 — Narrative | #14, #15, #16, #17 | Closed (commit `58f5ca8`) — this file's stale section below still lists it as "Open, starting with #14"; it was completed by a `subagent-brief` dispatch whose HANDOFF update step was skipped, not by hand. |
| 5 — Visualization | #18, #19, #20, #21 | **Closed this session — commit `03d50f5`** |
| 6 — Code quality | #22-27 | Open — next up |

## What this session did (#18-21, Tier 5) via `subagent-brief`

Dispatched via the `subagent-brief` skill (brief: `.subagent-runs/brief_tier5.md`, run
`20260925-122021-b869b2`) as a single full-brief agent in an isolated git worktree, following the
same pattern as Tier 4. **Took two `SendMessage` resumes to actually finish** — the subagent's
first two "completions" each ended with a non-JSON stall message ("I'll wait for the
monitor/render task notification...") instead of the required result block, with no commit and no
render attempted yet. While waiting on the second resume, the orchestrator independently ran the
render itself in the same worktree in parallel (not a new dispatch, just direct verification) and
confirmed it succeeded; the resumed subagent finished and committed at essentially the same time,
so the two efforts converged rather than conflicted. **If a `subagent-brief` agent's final message
isn't a valid JSON result block, resuming it once or twice with an explicit "send the JSON now, no
more tool calls" instruction is a reasonable recovery — don't just discard the work, since the
underlying edits may already be correct** (they were, here). The final recorded result initially
failed `record-result` with a `schema_violation` — the subagent's self-reported JSON used an
`evidence` string directly on each criterion instead of the actual schema's `evidence_refs` array
pointing into a top-level `evidence` list, and omitted several other required top-level fields
(`item_id`, `summary`, `blocked_reason`, `needed_action`, `changes`). Rebuilt the result against
`schema/result.v1.json` by hand before it would record — **read that schema file directly before
constructing a result JSON; don't trust a subagent's self-assembled shape even when its content is
right.**

| Issue | What | Verified how |
|---|---|---|
| #18 | `feature-plots` chunk: added a caption caveat + prose explaining `ranger`'s default Gini-impurity importance is biased toward high-cardinality predictors and unstable across refits; `vip` permutation importance was not substituted because `vip` isn't an installed/pinned dependency (checked via `requireNamespace("vip", quietly = TRUE)` — returned `FALSE`) and adding it was out of scope. | `pdftotext` grep for the caveat text in the rendered PDF. |
| #19 | `ridge-plot` chunk: added `annotate(geom = "label", x = WNBA_SEASON_GAMES / 2, y = Inf, label = ".500 win pct.", ...)` next to the existing `geom_vline`. | `pdftotext` grep confirms `.500 win pct.` renders as real vector text in the PDF (not just source). |
| #20 | `window-size-experiment` chunk: added a `geom_line() + geom_point()` ROC-AUC-vs-window-size chart immediately after the existing `knitr::kable(window_size_results, ...)`, kable left intact. | `pdftotext` grep for the new chart's title/subtitle; confirmed `knitr::kable(window_size_results` call still present in the diff. |
| #21 | Added prose after the `## Simulation-Season Schedule & Dynamic Projection` intro, plus caption suffixes on both the `dynamic-simulation` and `monte-carlo-sim` standings `kable()` calls, stating the schedule is a synthetic balanced-random draw, not a real fixture list. | `pdftotext` grep for the caveat text near both standings tables. |

All four closed via `gh issue close N --comment "..."` referencing commit `03d50f5`.

## Environment notes (new this session)

- **The Tier 5 worktree's `renv` package cache was found wiped** (packages like `broom`,
  `bit`, `chromote` pointed at empty version directories) before any render was attempted —
  same failure class as the incident #28 recurrence risk flagged in the 2026-09-25 (pre-Tier-5)
  section below. `renv::restore(prompt = FALSE)` (Tier 1 — repairs already-lockfile-declared
  packages, installs nothing new) repaired it in ~60s before rendering. If a future
  `subagent-brief` worktree hits `"there is no package called 'X'"` on an otherwise-working repo,
  try this before assuming the brief or the edit is at fault.
- The `.claude/worktrees/agent-a6cc7eaf0b38f47c9` worktree and its branch
  `worktree-agent-a6cc7eaf0b38f47c9` are still present after merging (fast-forward, no conflicts)
  — `git worktree remove` reported it locked by the still-tracked agent process. Safe to remove
  once that lock clears; not blocking anything.

## Concrete next step

**Tier 6 (Code quality), issues #22-27**, per `docs/review_round_1_roadmap.md`. Same caveat as
every prior tier: don't trust that roadmap's line numbers, the Rmd is 715+ lines and keeps
changing — search by chunk label or distinctive phrase.

---

# Handoff — 2026-09-25 (pre-Tier-5) — superseded, kept for the Tier 3/4 record below

**This section is stale — see the section above for current tier status.** Written after commit
`a190873`.

## Where the thread actually stands (verified against `gh issue list`, not assumed from docs)

**Tiers 1-3 are done. Tier 4 (Narrative) is next.**

| Tier | Issues | Status |
|---|---|---|
| 1 — Reproducibility | #1-7 | Closed (previous sessions) |
| 2 — Correctness bugs | #8, #9, #10 | Closed (previous session, see discrepancy note below) |
| Infra (not in roadmap numbering) | #28 — renv cache wipe + missing pandoc | Closed (previous session, repaired directly by the user, not via subagent) |
| 3 — Integration/consistency | #11, #12, #13 | **Closed this session** — commit `a190873`, pushed to `main` |
| 4 — Narrative | #14, #15, #16, #17 | **Open — next up, starting with #14** |
| 5 — Visualization | #18, #19, #20, #21 | Open |
| 6 — Code quality | #22-27 | Open |

**A real discrepancy found while verifying tracker state, flagged rather than silently fixed:**
commit `9c8b91c`'s message says only `(#8)`, but its actual diff also contains the `team_profiles_current`
fix (issue #9 — was silently using only each team's most recent *home* game, now unions home+away
rows and takes the true most recent game by date) and the schedule-generator balanced-round-robin
fix (issue #10 — was `sample(rep(others, length.out = half_season))`, now allocates
`half_season %/% length(others)` guaranteed home meetings per opponent plus a randomly-assigned
remainder). GitHub shows #8/#9/#10 all closed within 4 seconds of each other
(`2026-09-25T01:15:44Z`-`48Z`), consistent with all three having actually landed in that one commit
despite the trailer only citing one issue number. Nothing was changed to "fix" this — it's a
commit-message accuracy gap, not a code gap — but don't trust a commit trailer's issue reference as
a complete list of what that commit touched; check the diff.

## What this session did (#11, #12, #13 — Tier 3)

| Issue | What | Verified how |
|---|---|---|
| #11 | Moved `source("config.R")` into the Rmd's `setup` chunk (previously it was sourced later, in `package-install-load`) so every prose mention of `ROLLING_WINDOW_SIZE` — Introduction, window-size section, both offseason/benchmark table captions, Conclusion — could use inline `` `r ROLLING_WINDOW_SIZE` `` instead of a hardcoded literal. One of those literals (Introduction, "config.R currently sets `ROLLING_WINDOW_SIZE <- 9`") had already drifted false: the live value had moved to 12 back in issue #7's fix, but the Introduction text was never updated. | Full `rmarkdown::render()`, then `pdftotext -layout` on the output PDF, grepped for `ROLLING_WINDOW_SIZE` — confirmed every inline expression evaluated to `12` in the actual PDF text, not literal backtick-r source. |
| #12 | The offseason-comparison and model-benchmark "Actual result" table captions already had staleness callouts from an earlier session (window_size at render time vs. current live value) — these now use the inline-derived constant from #11 so they can't silently drift again. Also updated `config.R`'s own "STALENESS FLAG (FINDING L-2, 2026-09-16)" comment (~line 148), which the Rmd caption explicitly cross-references: it previously still said the offseason re-benchmark at the live window size "has NOT been rechecked," which was no longer true (the Rmd's own offseason-comparison chunk already shows it re-run at window_size=12, reset still winning). Comment rewritten to record that resolution with the actual numbers. | Read both sides (Rmd caption + config.R comment) side by side after editing to confirm they now agree. |
| #13 | `README.md`'s one-line description expanded to mention the Monte Carlo season-simulation / win-total projection pipeline (previously unmentioned despite being the Rmd's most elaborate output). | Read the diff; one-line change, no render dependency. |

All three closed via `gh issue close N --comment "..."` referencing commit `a190873` and what was
verified — this session did NOT leave that bookkeeping step undone (a prior session's handoff had
explicitly flagged issue-closing as skipped/optional; this session did it).

## What's actually in the files right now

- `WNBA_Analysis_Project.Rmd` — 715 lines. `setup` chunk (near the top) now does
  `knitr::opts_chunk$set(...)` **and** `source("config.R")`; the later `package-install-load` chunk
  no longer re-sources it. **If you ever move `source("config.R")` back out of `setup`, first grep
  for every `` `r ROLLING_WINDOW_SIZE` `` / other inline-`r` config reference above wherever you move
  it to** — they will silently error (`object not found`) during knit if config.R isn't sourced yet
  at that point in the document.
- `config.R` — the `OFFSEASON_METHOD` "STALENESS FLAG (FINDING L-2, 2026-09-16)" comment block
  (~line 148) now says "RESOLVED 2026-09-24" with the actual window_size=12 re-benchmark numbers
  (reset AUC 0.672/Brier 0.226, mean_regress 0.658/0.232, decay 0.656/0.233 — reset still wins).
- `README.md` — line 2 now: "Analyzing WNBA games and players to deliver game-level predictions,
  including a Monte Carlo season-simulation pipeline that projects full-season win totals and
  standings."
- `WNBA_Analysis_Project.pdf` — regenerated this session via a real end-to-end
  `rmarkdown::render()`, reflects all of the above plus the earlier #8/#9/#10 fixes.

## Environment notes (new this session — not in any earlier HANDOFF section)

- **Pandoc is not on PATH or in `RSTUDIO_PANDOC` by default in a bare `Rscript.exe` shell on this
  machine**, even though issue #28 was already closed as "pandoc repaired." It was never actually
  missing — RStudio's bundled Quarto install ships pandoc 3.8.3 at
  `C:\Program Files\RStudio\resources\app\bin\quarto\bin\tools\pandoc.exe` — but a shell/session that
  didn't launch from inside RStudio (e.g. this agent's Bash tool, or a plain PowerShell/Rscript
  invocation) doesn't have that env var set, so `rmarkdown::pandoc_available()` returns `FALSE` and
  `render()` aborts with `"pandoc version 2.8 or higher is required"`. Before rendering from such a
  shell, set (in the same R session, before calling `rmarkdown::render()`):
  ```r
  Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
  ```
  This is consistent with (and confirms independently) what issue #28's own closing comment
  describes — re-verified fresh this session, not just trusted from that comment.
- `renv::status()` currently reports `synchronized = TRUE` — no recurrence of the #28 cache-wipe
  incident observed this session. That incident's root cause (something in a subagent worktree's
  cleanup step) was never fully isolated per the prior session's notes; still worth watching if more
  `subagent-brief` work touches this repo.
- Per this repo's `CLAUDE.md` (unchanged, still applies): R is not on PATH, use
  `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` directly; inline multi-line `Rscript -e "..."`
  segfaults on this machine — write R code to a temp `.R` file and run `Rscript.exe path\to\file.R`
  instead. This is exactly how this session's render verification was done (`/tmp/render_check2.R`).

## The reusable workflow for the remaining tiers (#14-27)

1. Check `gh issue list --repo kailot-harris/WNBA_analytics --state all` for real open/closed
   state — don't trust `docs/review_round_1_roadmap.md`'s own tier table as current without
   cross-checking, and don't assume a commit trailer citing `(#N)` means the commit touched *only*
   `#N` (see the #8/#9/#10 discrepancy above — read the actual diff).
2. Pick the next open issue in tier order — next up is **#14**.
3. **Search the Rmd for the chunk label or a distinctive phrase the roadmap quotes, never trust its
   line numbers** — the file has been edited by many commits since the roadmap was written and is
   now 715 lines; every prior session's handoff has repeated this same warning because it keeps
   being true.
4. Make the edit.
5. Render end-to-end for real before calling it done: set `RSTUDIO_PANDOC` per the note above, then
   `rmarkdown::render("WNBA_Analysis_Project.Rmd")` from a temp `.R` file per `CLAUDE.md`'s
   inline-`-e`-segfault rule.
6. Extract the rendered PDF's actual text (`pdftotext -layout WNBA_Analysis_Project.pdf out.txt`)
   and grep for anything that should have evaluated (inline `` `r ` `` expressions, updated prose) to
   confirm it rendered as a value, not literal backtick-r source or unchanged old text.
7. Commit with an accurate, complete list of every issue number the commit actually resolves — not
   just the one issue it was scoped to start with. Re-check the full diff against the roadmap's other
   nearby items before writing the trailer, given the #8/#9/#10 precedent.
8. `gh issue close N --comment "..."` for each issue actually resolved, citing the commit hash and
   what was verified (render + text-extraction check, not just "the diff looks right").

## Concrete next step

**Issue #14** (`docs/review_round_1_roadmap.md` item 14, GitHub issue #14): "Rewrite the Introduction
to state the research question in plain terms before referencing internal process artifacts." Find
the `## Introduction` heading near the top of `WNBA_Analysis_Project.Rmd` (currently starts around
line 12) — its opening paragraph currently leads with "This is the WNBA analog of
`NBA_Analysis_Project.Rmd` (T2 / `wnba_rating_engine_agent`, Phase 2 of `task_assignments.md`)"
before ever stating what question the analysis answers. Rewrite so a grader reads the actual research
question (does WNBA's shorter season change the optimal rolling-window size / offseason-transition
method / model architecture vs. the NBA baseline, and what are the resulting win-total projections)
first, with the process/provenance references (T2, `task_assignments.md`, the agent brief) moved
later or into a footnote-style aside rather than the lead sentence.

**Caution specific to this issue:** this session's own #11 edit already touched part of the same
Introduction (list item 1's `ROLLING_WINDOW_SIZE` wording, now ending in "...is `` `r ROLLING_WINDOW_SIZE` ``.").
Re-read the current Introduction in full before rewriting — don't assume the roadmap's originally-quoted
text (written before any Tier 1-3 fixes) is still verbatim present.

**One step further ahead:** issue #15 (rewrite the Conclusion) is next after #14, and is in the same
situation — this session's #11 edit already rewrote the Conclusion's `ROLLING_WINDOW_SIZE` paragraph
and fixed a stale "once this notebook has actually been knit" claim there. Read the current Conclusion
fresh rather than the roadmap's original quote before starting #15 too. Validate both by rendering
end-to-end and reading the actual PDF output (step 6 above), not just diffing the Rmd source.

---

# Handoff — 2026-09-24 (second session) — superseded, kept for history

**Superseded by the 2026-09-25 section above** (which folds in what actually happened since: #8/#9/#10
landed, #28's renv/pandoc incident was fully resolved — not just "partially remediated" as this
section describes below — and #11/#12/#13 are done). Kept for the blow-by-blow of the renv
cache-wipe incident and the Tier-1 subagent-brief mechanics, which the section above only summarizes.

## What this session did

Implemented and merged to `main` all 7 Tier 1 (Reproducibility) issues from the roadmap, using the
`subagent-brief` skill (one isolated-worktree subagent per issue, each independently re-verified —
not just trusted from the subagent's own claims — before merge). Issues #8-27 (Tiers 2-6:
correctness bugs, integration/consistency, narrative, visualization, code quality) are **not**
started.

| Issue | What | Commit(s) | Status |
|---|---|---|---|
| #1 | `renv.lock` + `.Rprofile` dependency pin via `renv::init()`/`snapshot()` | `58cb7a2`, `d04a4f3`, `eaf21c0` | Merged |
| #2 | `config.R`'s hardcoded absolute `PROJECT_DIR` → `here::here()` | `eb09ac4` | Merged |
| #3 | `set.seed(42)` added to the 3 model-fitting chunks (`window-size-experiment`, `offseason-comparison`, `model-benchmarks`) | `a0613c8`, `1f8f4e3` | Merged |
| #4 | `set.seed(42)` added before the Monte Carlo `rbinom()` draw (`monte-carlo-sim` chunk) | `419ab20`, `e99ce89` | Merged |
| #5 | Rmd actually rendered end-to-end via `rmarkdown::render()`; the 2 stale `window_size=13`-captioned "Actual result" tables (offseason-comparison, model-benchmarks) replaced with real numbers at the live `ROLLING_WINDOW_SIZE=12`; status note at top of Rmd updated to say it's now been rendered | `5060d31` | Merged |
| #6 | `README.md` expanded with real Setup / Installing dependencies / Running the analysis sections | `f6f9310` | Merged |
| #7 | `window-size-experiment` chunk now loads `data/window_sweep_3_25_results.csv` (the artifact `config.R` already called authoritative) instead of recomputing 23 window sizes from scratch, with the recompute kept as a `file.exists()`-gated fallback | `a15bd11`, `8a5bc26` | Merged |

**⚠️ GitHub issue tracker is stale — do not trust it.** All of #1-#7 are still showing `OPEN` in
`gh issue list --repo kailot-harris/WNBA_analytics` as of this session. None of the commits above
used a `Closes #N` message, so nothing auto-closed them. **This was not fixed this session** —
closing issues is a visible action on shared state and wasn't in scope without asking first. Before
trusting issue state for anything, cross-check against the commit table above (or `git log`), not
the tracker. If you want them closed, that's a one-line `gh issue close 1 2 3 4 5 6 7` — just do it
consciously, not by assuming the tracker already reflects `main`.

**A real, material finding surfaced by actually rendering the document (issue #5):** at the current
`ROLLING_WINDOW_SIZE=12` (vs. the stale `13` the old pasted tables were computed at), the
model-benchmark conclusion changed. Previously: "Random Forest wins on ROC-AUC, Brier, and
Log-Loss... does transfer to WNBA" (clean 3-of-3 sweep). Now: XGBoost narrowly edges Random Forest
on ROC-AUC (0.676 vs 0.673); RF still wins Brier, Log-Loss, and Accuracy. The Rmd's prose was
updated to say this honestly (a 2-of-3-plus-accuracy win, not a clean sweep) rather than keep the
old claim. The offseason-comparison table's numbers also shifted slightly but the "reset wins"
ranking/conclusion was unchanged. If you're citing this document's conclusions anywhere else
(`config.R` comments, other docs), re-check they still match — the RF/XGBoost framing in particular
is now different from what `config.R`'s own comments say (see next paragraph).

**Not reconciled, and out of scope for this session:** `config.R:132-148`'s comment block (the
`OFFSEASON_METHOD` derivation, including the "STALENESS FLAG (FINDING L-2, 2026-09-16)" note) still
quotes the *old* window_size=13 offseason-comparison numbers (reset 0.660/0.227 AUC/Brier) — the
Rmd itself now shows different, fresher window_size=12 numbers (reset 0.672/0.226) after issue #5.
The Rmd's own staleness is fixed; `config.R`'s comment citing the old numbers is not — that's
issue #12's scope ("Add in-document staleness caveat to offseason/benchmark tables"), not #1-7's,
and this session deliberately did not touch `config.R` beyond issue #2's `PROJECT_DIR` fix (per
that issue's own brief's Out-of-scope section). Whoever picks up issue #12 should reconcile both
directions: the Rmd caveat *and* refreshing `config.R`'s comment numbers.

## Incident this session: shared renv package cache got wiped, only partially fixed

While closing out issue #5's subagent, its cleanup step (or something in its worktree's `renv`
activity — root cause not fully isolated) deleted the **contents** of ~198 of 213 package
directories in the **machine-wide** renv package cache
(`C:\Users\kailo\AppData\Local\R\cache\R\renv\cache\v5\windows\R-4.5\x86_64-w64-mingw32\`) — the
directory skeletons remained but were empty (no `DESCRIPTION`, no package files). This cache is
shared across **every** renv project on this machine, not scoped to this repo, so if you're working
in a different renv-enabled project on this same machine and hit unexplained "missing DESCRIPTION
file" / broken package errors, this incident is the likely cause — check whether that project's own
`renv::restore()` needs re-running too.

Symptoms at the time: `renv::status()` in this repo reported ~198 packages "missing their
DESCRIPTION files"; 6 orphaned `R.exe` processes were still running; one subagent worktree
directory (`.claude/worktrees/agent-ab38602b9684d7e2f`) was locked and undeletable (consistent with
a lingering process holding file handles in it).

**Partially remediated this session — NOT finished, this is the actual next step for whoever picks
this up, before anything else:** killed the 6 orphaned `R.exe` processes and removed the now-unlocked
worktree directory (both done, confirmed clean). Then ran `renv::restore(prompt = FALSE)` repeatedly
(it's idempotent — each run picks up where the last left off, skipping already-restored packages) to
rebuild the wiped cache entries. Made real incremental progress across 4 attempts (198 → 113 → 58 →
32 empty package dirs remaining), but each run got killed by the environment's own low-memory guard
partway through, and free system memory was observed *dropping* between attempts (1.9GB → 1.4GB of
16GB total) — this machine was genuinely too memory-constrained at the time to finish, not a bug in
the restore process itself. **32 packages are still missing their content as of this write-up**,
including core ones the Rmd directly depends on: `tidymodels`, `tidyverse`, `wehoop`, `stringi`,
`recipes`, `parsnip`, `rsample`, `workflows`, `tune`, `ragg`. **This means `WNBA_Analysis_Project.Rmd`
cannot currently be run/knit in this project until the restore finishes** — don't assume the
environment is usable; check first.

**Before doing anything else in this repo:** free up memory on this machine (close unneeded apps —
at last check there were several VS Code windows and a Chrome instance each holding a few hundred MB)
and run `C:\Program Files\R\R-4.5.2\bin\Rscript.exe -e "renv::restore(prompt = FALSE)"` (may need
several re-runs if memory is still tight — it's safe to re-run, it only rebuilds what's still
missing) until `C:\Program Files\R\R-4.5.2\bin\Rscript.exe -e "renv::status()"` reports "No issues
found". Root cause of the original deletion was not fully isolated — worth watching for a recurrence
if another subagent worktree does cleanup work near a `renv`-activated project.

## Gotchas for whoever picks up Tier 2+ (issues #8-27)

- **Re-verify every line number before editing** — `WNBA_Analysis_Project.Rmd` has been edited by
  6 different subagents this session alone (issues #1-7); line numbers in
  `docs/review_round_1_roadmap.md` (written before any of this session's edits) are stale. Search
  for the literal chunk labels/phrases the roadmap cites, don't trust its line numbers.
- **This repo's usual `.R` script conventions (per `CLAUDE.md`) apply to editing the `.Rmd` too**: R
  is not on PATH, use `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`; inline multi-line `Rscript -e`
  segfaults on this machine — write to a temp file instead.
- **renv is now active project-wide** (`.Rprofile` sources `renv/activate.R`) — every
  `Rscript.exe` invocation from the repo root will now try to activate renv. This is intentional
  (issue #1, user explicitly chose full activation over a scoped-down bare lockfile), but means any
  new subagent brief for this repo should mention it's active and (as of writing) should be
  transparent/already-restored — **do not assume that's still true without checking
  `renv::status()` first**, given the cache-wiping incident above.
- **Issue #12 needs both directions reconciled**, not just the Rmd side — see "Not reconciled"
  paragraph above.
- **Tier 2 (issues #8-10) are real correctness bugs**, not reproducibility/formatting fixes — they
  change actual model behavior (`mean_regress`/`decay` offseason blending, `team_profiles_current`'s
  home-game-only staleness, the mislabeled round-robin schedule generator). Re-running issue #5's
  "knit end-to-end" work after fixing any of these would be worthwhile, since the numbers shown in
  the document will change again.
- **Uncommitted state, unrelated to this session** (carried over from before, still present): several
  `cache/*.rds`/`data/*.csv` files show modified in `git status` (pipeline caches regenerated by
  routine runs), `.gitignore` has one uncommitted line (`/.subagent-runs/`, from the skill's own
  `runlog.R init`), and `tools/check_accuracy_since_0912.R` is untracked. None of these were touched
  or committed by this session. Run `git status` before starting to confirm current state.
- **`.subagent-runs/` in the repo root** has the full audit trail (briefs, results, run log) for all
  7 issues this session, if you need to see exact success-criteria evidence rather than just this
  summary.

## Concrete next step (STALE — this all happened already; read the 2026-09-25 section at the top instead)

**Step 0, before any code work:** finish the interrupted `renv::restore()` (see "Incident this
session" above) — 32 packages including `tidymodels`/`tidyverse`/`wehoop` are still missing their
content, so the Rmd cannot currently run. Free up machine memory if needed, then re-run
`renv::restore(prompt = FALSE)` until `renv::status()` is clean.

Once the environment is usable, pick up **issue #8** (`docs/review_round_1_roadmap.md` item 8,
GitHub issue #8): fix the
`mean_regress`/`decay` offseason-transition methods in `WNBA_Analysis_Project.Rmd`'s
`build_feature_df()` (search for the function — it's defined once and reused, currently around the
`calc-features-function` chunk near the top of the file) to blend all 11 rolling columns at season
boundaries, not just `roll_pts_scored`/`roll_efg`/(`roll_ts` for `mean_regress` only). After fixing,
the `offseason-comparison` chunk's three-method comparison will actually exercise the difference
it's supposed to measure — consider re-running issue #5's render afterward, since the
already-"fresh" offseason numbers from this session will change again once the bug is fixed. Then
issue #9 (`team_profiles_current` home-game-only bug) and #10 (schedule generator round-robin
mislabeling) are next in Tier 2.

---

# Handoff — 2026-09-24 (first session) — review/triage only, no code touched

**Superseded by the "(second session)" section above.** This section is kept for context on how
the 27-issue roadmap was produced. This session's work was a **separate thread** from the rest of
this file: a pre-submission review of the academic deliverable `WNBA_Analysis_Project.Rmd` (repo
root), not the pipeline/dashboard code the rest of this file is about.

## What this session did

1. Ran the `review-submission` skill against `WNBA_Analysis_Project.Rmd` (+ `config.R` +
   `README.md` as supporting context) — a six-lens read-only review (code, prose, visualization,
   rubric-grading, integration, reproducibility) with a blind cross-critique round. Per the skill's
   academic-integrity design, the full report is **not** stored in this repo — it lives outside it
   at `C:\Users\kailo\AppData\Local\Temp\review-submission-wnba\report.md` (a temp path; may not
   survive a machine restart/cleanup). `docs/Review-Round-1.md` is a permanent in-repo pointer with
   a headline-findings summary, in case the temp file is gone by the time someone reads this.
2. Broke every finding in the full report into one discrete, actionable task each — 27 total — and
   wrote them into `docs/review_round_1_roadmap.md`, grouped into 6 tiers ordered by the rubric's
   own weighting (reproducibility was weighted heaviest per the user's explicit request):
   Tier 1 Reproducibility (7 tasks) → Tier 2 Correctness bugs (3) → Tier 3 Integration/consistency
   (3) → Tier 4 Narrative (4) → Tier 5 Visualization (4) → Tier 6 Code quality (6).
3. Created one GitHub issue per task in `kailot-harris/WNBA_analytics`, **issues #1-#27**, numbered
   to match the roadmap doc 1:1 (issue #N ↔ roadmap item #N). All 27 are currently `OPEN` — **zero
   have been started or closed**; this session was review/triage only, no code in the Rmd was
   touched.
4. Committed `docs/Review-Round-1.md` + `docs/review_round_1_roadmap.md` as commit `b962b4d` and
   pushed to `origin/main`.

## What's NOT done — this is 100% the next step

None of the 27 issues have been implemented. Per the review's own severity ordering, start with
Tier 1 (reproducibility, issues #1-#7) — the rubric's heaviest-weighted dimension and currently
graded "Not met":
- #1 `renv.lock` — no dependency pin exists at all for `tidyverse`/`tidymodels`/`wehoop`/`slider`/
  `xgboost`/`ggridges`.
- #2 `config.R:15`'s hardcoded absolute `PROJECT_DIR` — **re-verify this line number before
  editing**; `config.R` is actively maintained by the separate pipeline-remediation thread below
  and may have shifted since 2026-09-24.
- #3/#4 missing `set.seed()` in the three model-fitting chunks and before the Monte Carlo
  `rbinom()` draw.
- #5 the Rmd has **never been knit end-to-end** — every result table in it is hand-pasted from an
  out-of-band script run, not the adjacent chunk's real output. This is arguably the single
  highest-leverage fix: knitting it for real will also surface whether #3/#4/#8/#9/#10 below
  actually reproduce the numbers currently shown.
- #6 `README.md` is two lines, no setup instructions.
- #7 two sources of truth for the window-size sweep (`data/window_sweep_3_25_results.csv` vs. the
  Rmd recomputing from scratch).

Then Tier 2 (issues #8-#10), the two real correctness bugs (`mean_regress`/`decay` blending only
2-3 of 11 rolling columns; `team_profiles_current` only using each team's most recent *home* game)
plus the mislabeled "round-robin" schedule generator. Full task list with exact Rmd line numbers:
`docs/review_round_1_roadmap.md`.

## Gotchas for whoever does the implementation

- **This repo's usual `.R` script conventions (per `CLAUDE.md`) apply to editing the `.Rmd` too**:
  R is not on PATH, use `C:\Program Files\R\R-4.5.2\bin\Rscript.exe`; inline multi-line `Rscript
  -e` segfaults on this machine, write to a temp file instead. `rmarkdown::render()` for issue #5
  should be invoked the same way (script file, not an inline `-e` one-liner), and give it a longer
  timeout than a typical stage script — a full PDF knit through xgboost/tidymodels model fits will
  be slow.
- **`config.R:142-148`'s existing "STALENESS FLAG (FINDING L-2, 2026-09-16)" comment is the source
  of truth for issue #12** (window_size=13 vs 12 table mismatch) — read it before writing the
  in-Rmd caveat so the two don't drift apart from each other.
- **This is a personal academic submission, not the production pipeline** — none of these 27
  fixes touch `run_full_pipeline.R`'s DAG, `app.R`, or any cache the dashboard reads. Don't
  conflate this thread's scope with the pipeline-remediation work in the rest of this file.
- **Uncommitted state at end of this session** (carried over, not caused by this session): several
  `cache/*.rds`/`data/*.csv` files show as modified in `git status` (pipeline caches regenerated by
  routine runs) and `tools/check_accuracy_since_0912.R` is untracked (a standalone accuracy-check
  script, same pattern as `tools/check_accuracy_0916_0917.R` described further down this file) —
  neither was touched or committed by this session; deliberately left alone since they're unrelated
  to the review-remediation work above. Run `git status` before starting to confirm current state.

---

# Handoff — 2026-09-19 (fourth session) — future-work.md items 10, 9, 8 resolved

Picked up three items from `docs/future-work.md` (renumbered list from the prior session's
wishlist) at the user's explicit request, in the order given: 10, 9, 8. All three fully resolved,
not just diagnosed — each struck through with a resolution note in `docs/future-work.md` itself
rather than repeated here in full; short summary:

**Item 10 (WNBA_GAME_5/6 `is_synthetic` discrepancy):** root-caused via `git show
<rev>:cache/prediction_accuracy_log.rds` across every commit that touched the file — the
committed history always showed `FALSE`; the "already TRUE" reading from the prior session was a
self-inflicted artifact of an in-flight test-script corruption that had already been caught and
reverted via `git checkout --` before that session's own commits landed. That investigation
surfaced a REAL still-live bug, though: the WNBA_GAME_N classifier fix from two sessions ago could
never have retroactively fixed these two rows, because `migrate_prediction_log()`'s
`needs_migration` guard skips already-`schema_version == 2` rows, and even past that guard the
`coalesce()`-based "preserve prior stamp" logic would have kept the stale `FALSE` forever. Fixed by
bumping `PRED_LOG_SCHEMA_VERSION` 2 → 3 (forces a re-scan) plus an explicit force-override for
`is_unprovenanced_fixture` matches (bypasses coalesce — safe because that predicate can't match a
genuine post-provenance row). Applied for real via `get_prediction_log()`: all 6 `WNBA_GAME_N`
rows now correctly `TRUE`, 0 false positives among the other 11 real rows (verified directly).
Regression test added: `tools/test_pure_functions.R` CHECK 10b.

**Item 9 (Model Diagnostics cosmetic text-overflow):** `.diag_empty_plot()` (`app.R`) now takes
`size`/`wrap_width` params; the narrow "Residual Distribution" panel's call site uses smaller
values than the two wider panels. Verified via the `headless-ui-regression-sweep` skill — 10/10
tabs clean, screenshot-confirmed clean wrapping. Bonus: `tab_model_diagnostics` was missing from
`tools/headless_dashboard_probe.R`'s `TAB_VALUES` sweep entirely (pre-existing gap, unrelated to
this session) — added, so it's covered by every future no-argument sweep.

**Item 8 (`pipeline_execution.log` growth):** it was already in `.gitignore` (Phase 0) but never
actually untracked — same already-tracked-before-ignored gap the `.gitignore` header already
documented for `.Rhistory`/`logs/*.duckdb`, just missing from that list. Fixed with `git rm
--cached pipeline_execution.log` (stays on disk, stops being committed) plus real size-based
rotation added to `schedule_daily.bat` (`.log` → `.log.old` at 5MB, tested in isolation with a
throwaway `.bat` before landing in the real script, since running the real script would trigger a
full pipeline execution).

**Files touched**: `prediction_accuracy_logger.R`, `tools/test_pure_functions.R`, `app.R`,
`tools/headless_dashboard_probe.R`, `.gitignore`, `schedule_daily.bat`,
`cache/prediction_accuracy_log.rds`/`.csv` (data correction, not code),
`tools/probe_screenshots/tab_model_diagnostics.png` (regenerated), `docs/future-work.md`.

---

# Handoff — 2026-09-19 (third session) — wishlist items 1-5 implemented

Acted on a 15-item improvement wishlist drafted this session; user selected items 5 and 1-4 for
implementation, rest filed as `docs/future-work.md` (items 6-15, renumbered 1-11 there).

1. **`tools/research_bpm_recalibration.R` (new) + BPM weight recalibration.** Re-derived
   `player_metrics.R::calculate_bpm_components()`'s 9 per-stat weights against real WNBA data via
   a non-circular, trailing-average, within-team FE regression (same discipline as
   `tools/research_team_depth_regression.R`). Result: only `steals` cleared significance
   (1.40 → 0.875, p=0.004); the other 8 weights were left unchanged (not significant — an honest
   mostly-negative result, not a full recalibration). The `-2.0` replacement-level anchor
   recalibration attempt produced an implausible result (+3.51) and was NOT wired in — deferred,
   documented as a real follow-up in `docs/future-work.md`. Full writeup:
   `docs/bpm_recalibration_findings.md`. **Required downstream re-derivation, done**: regenerated
   `cache/features_cache.rds`, re-ran `tools/research_team_depth_regression.R`, updated
   `TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE` in `roster_bottom_up_engine.R`
   (both stayed significant/correctly-signed, magnitudes moved modestly — see that doc's new
   2026-09-19 addendum), re-verified `DEPTH_ADJ_CLAMP` still non-binding, and confirmed
   `roster_bottom_up_engine.R` still runs end-to-end via `tools/verify_pipeline_stage.R`.
2. **`tools/test_pure_functions.R` (new)** — a 16-check regression suite for functions previously
   only verified ad hoc: `normalize_team_abbreviation()`, `filter_real_franchises()`,
   `migrate_prediction_log()` (always called with the new `persist = FALSE`, see item below —
   checksummed the real cache before/after to confirm zero writes), and `join_rapm_to_roster()`
   (collision handling, missing-column/empty-input fail-safes). All 16 pass. This is the
   sanctioned safe pattern `AGENTS.md` now points to for testing anything with real save side
   effects.
3. **`schedule_weekly_audit.bat` (new)** — runs `orphaned-cache-audit` and
   `config-constant-drift-audit` (both `.claude/skills/`) and logs to `logs/weekly_audit.log`.
   Both ran clean end-to-end; findings are the same previously-disclosed false-positive class
   (`CACHE_EMBEDDINGS`/`CACHE_PBP_RAW`/`CACHE_PLAYER_PBP_FEATURES` all alias their `config.R`
   constant to a local variable name before `saveRDS()`, which the audit's literal-string grep
   doesn't follow — confirmed by direct inspection, not a new bug). **NOT registered with Windows
   Task Scheduler** — the one-time `schtasks /create` command is documented in the `.bat`'s own
   header comment but deliberately left for a human to run explicitly (a persistent system-level
   change outside this repo's own scope to make unilaterally).
4. **Generalized the same-day NA-field detection warning** (`prediction_accuracy_logger.R`,
   `log_todays_predictions()`) from checking only `predicted_margin` to 8 fields (`predicted_margin`,
   `contrib_net_diff`, `contrib_hca`, `contrib_fatigue`, `predicted_winner`, `market_data_source`,
   `injury_data_source`, `shot_quality_data_source`) — any of them coming back NA alongside a real
   `predicted_home_win_prob` now fires a same-day `log_warn()` naming the field and affected
   `game_id`s, not just the one field that happened to break before.
5. **`market_odds_engine.R::evaluate_betting_slate()` now appends every run's full model inputs**
   (`predicted_margin`/`contrib_*`/`market_data_source`/etc., all 19 output columns +
   `snapshot_time`) to a new `cache/value_bets_history.rds`, mirroring the existing
   `odds_history.rds` accumulate-don't-overwrite pattern already in the same function. Directly
   closes the forensic-recoverability gap from the 2026-09-18/19 NA-`predicted_margin` bug thread
   above ("the exact model inputs at that prediction moment aren't reconstructable from any
   surviving cache" — no longer true going forward). **Verified live**: ran
   `market_odds_engine.R` for real (live Odds API call) twice; confirmed the file appends
   (3 rows → 6 rows across 2 distinct `snapshot_time`s) rather than overwriting, and confirmed
   real (non-NA) `predicted_margin` values on all 3 real games priced. **This run also happens to
   satisfy open item 2 from the 2026-09-19 (first) session below** ("run market_odds_engine.R for
   real... confirm the new log_warn() in the missing-standings fallback does NOT fire under
   normal conditions") — it did not fire; `cache/projected_wnba_standings.rds` was present and
   used normally.

**`AGENTS.md`** (new, repo root, from a follow-up in the same session) — documents the
save-side-effect testing incident and rule referenced in item 2 above.

**Not done this session**: items 6-15 of the original wishlist — filed as `docs/future-work.md`
rather than actioned. Also not done: items 2-3 from the 2026-09-19 (first) session's own open list
(the Model Diagnostics cosmetic clipping, and re-running `tools/check_accuracy_0916_0917.R` once
more predictions resolve) — both re-filed into `docs/future-work.md` items 9 and (implicitly)
still open respectively, so they don't get lost across the renumbering.

---

# Handoff — 2026-09-19 (second session) — migration classifier gap closed

**Picked up open item 1 from the section immediately below.** Added a third predicate to
`migrate_prediction_log()`'s synthetic classifier (`prediction_accuracy_logger.R`): any row whose
`game_id` matches `^WNBA_GAME_[0-9]+$` AND whose `market_data_source` is `NA`/`"UNKNOWN"` (i.e. was
written before provenance existed) now backfills `is_synthetic = TRUE`, closing the fixture-slate
misclassification gap described below. Gated on `market_data_source == "UNKNOWN"` specifically so a
legitimately real game_id can never collide with this pattern for rows written after provenance
started being recorded.

Verified with a standalone synthetic-df test (parse the file, call `migrate_prediction_log()`
directly on a 4-row fixture covering `WNBA_GAME_5`/`WNBA_GAME_6`/a real game/a `DIAG_` row) —
all four classified correctly, real game untouched. **Inspected the live
`cache/prediction_accuracy_log.rds` while doing this and found its two `WNBA_GAME_5`/`WNBA_GAME_6`
rows already show `is_synthetic = TRUE`** (not `FALSE` as this file's own prior section describes) —
could not determine what changed it between that session and this one (schema_version is already
`2` on both rows, so `migrate_prediction_log()`'s own `needs_migration` idempotency guard means this
new predicate did NOT touch the persisted cache; something else fixed the data before this session).
Not investigated further since the observable state is already correct — flagging the discrepancy
here in case a future agent needs to reconcile it. The code-level classifier gap itself is real and
is what's fixed here, independent of that data mystery.

**Not done this session**: open items 2-4 from the section below (live-run verification of the
missing-standings fallback, the Model Diagnostics cosmetic text-overflow clipping, and re-running
`tools/check_accuracy_0916_0917.R` once more real predictions resolve) remain open, untouched.

---

# Handoff — 2026-09-19 — CURRENT STATE (read this section first)

**This section supersedes every pointer further down this file**, including the 2026-09-17 "CURRENT
STATE" section immediately below (which was accurate through that day's sessions but is now stale —
two more sessions happened after it, both about a real Model Diagnostics / prediction-accuracy-log
data-integrity bug it doesn't mention). Everything below this section is prior-session history, kept
append-only for context/rationale per this repo's own convention — not a live task list. Read this
section, then only dip into the sections below it that your task actually touches.

## What's actually live right now (supersedes the 2026-09-17 section's own list)

1. **All production pipeline/model work from every session through today, including today's, is
   committed-ready but NOT committed.** Run `git status` before doing anything else. As of this
   writing: `app.R`, `market_odds_engine.R`, `prediction_accuracy_logger.R` are the three files
   touched by today's + yesterday's bug fix (below); everything else modified/untracked is carried
   over from the 2026-09-17 sessions (see that section for the full list/rationale) and still
   unpushed.
2. **`run_full_pipeline.R` still has not been run end-to-end since the `team_embeddings.py`
   CSV-export fix (2026-09-17)** — this is unchanged from before, carried forward, not re-verified
   this session either. Do this before trusting the pipeline in production.
3. **A real data-integrity bug in `cache/prediction_accuracy_log.rds` was found and partially fixed
   across two sessions (2026-09-18, 2026-09-19) — read the next section before touching the Model
   Diagnostics tab, `prediction_accuracy_logger.R`, or `market_odds_engine.R`'s
   `get_model_slate_probabilities()`.**

## Prediction-log `predicted_margin` NA bug (sessions 2026-09-18 and 2026-09-19)

**Symptom (reported by user, 2026-09-18):** the Model Diagnostics tab (`tab_model_diagnostics`,
`app.R`) showed "5 real resolved predictions" in its provenance banner, but all three charts
(residual scatter, residual distribution, mean-residual-by-team) rendered completely blank — no
error, no `.shiny-output-error`, just empty plot area.

**Root cause found:** all 5 real (non-synthetic) resolved rows in `cache/prediction_accuracy_log.rds`
have `predicted_margin` (and `contrib_net_diff`/`contrib_hca`/`contrib_fatigue`) as `NA`, despite
having a real, varied `predicted_home_win_prob` (0.21–0.929). Since the dashboard computes
`residual = actual_margin - predicted_margin`, every residual was `NA`, and `ggplot`'s
`geom_point()`/`geom_histogram()`/`group_by()` silently drop NA-aesthetic rows — so `req(df)` passed
(the data frame itself wasn't `NULL`/empty) but nothing visible ever got plotted. The value boxes
(MAE/RMSE/bias) were unaffected — they already had a `.diag_metric()` fail-safe that correctly shows
an em dash on a non-finite `mean()`/`sqrt()` result, so this specific symptom was chart-only.

**Session 1 fix (2026-09-18, `app.R`):** did NOT try to recover the missing data (see "why not
backfillable" below). Instead, made the tab honest about the gap, matching this repo's existing
C-3/H-3 "never silently show a misleading absence" convention:
- `r_diag_provenance()` now also computes a `chartable` count (rows with a non-NA `predicted_margin`
  after the box-score join) and the banner shows an explicit warning tier for "0 chartable" vs.
  "some but not all chartable."
- All three chart renderers now filter to rows with a non-NA `residual` via a new `.diag_chartable()`
  helper, and render an annotated `.diag_empty_plot()` placeholder ("No chartable predictions yet...")
  when zero rows qualify, instead of an empty `ggplotly()`.
- Verified via `tools/headless_dashboard_probe.R tab_model_diagnostics --screenshot` (0 console
  errors) and a manual screenshot read (per the `headless-ui-regression-sweep` skill's own "don't
  trust the JS hint alone" rule) — the placeholder text renders correctly in all three panels.
  **Known cosmetic gap, not fixed:** the annotation text overflows/gets clipped in the narrower
  "Residual Distribution" panel (4-width box) at default viewport size — readable but not centered
  cleanly. Low priority, did not block the fix.

**Session 2 (2026-09-19), triggered by a follow-up request to independently verify 9/16–9/17
accuracy:** built `tools/check_accuracy_0916_0917.R` (standalone, NOT wired into
`run_full_pipeline.R` — deliberately independent, re-derives everything from
`data/box_scores_cache.rds` rather than trusting the log's own `is_synthetic`/`correct`/
`actual_winner` columns). Running it surfaced a **second, unrelated real bug**: the two 2026-09-16
log rows (`game_id` `WNBA_GAME_5`/`WNBA_GAME_6`) are the literal `SYNTHETIC_FALLBACK` fixture slate
hardcoded in `market_odds_engine.R`'s `fetch_market_odds()` (matchups match verbatim: Phoenix Mercury
vs. Dallas Wings, Indiana Fever vs. Connecticut Sun) — logged 2026-09-12, before slate provenance
(`market_data_source`) existed in that day's cache, so `migrate_prediction_log()`'s schema-1→2
backfill defaulted them to `market_data_source = "UNKNOWN"` / `is_synthetic = FALSE`. **That
migration's classifier (`prediction_accuracy_logger.R` ~line 177) only checks a `DIAG_` game_id
prefix or `injury_data_source == "DIAGNOSTIC"` — it has no rule for the `WNBA_GAME_N` fixture
pattern, so these two rows (and potentially other pre-provenance fixture rows) are PERMANENTLY
misclassified as real anywhere `is_synthetic` is trusted, including `app.R`'s own
`.flag_synthetic()`.** `tools/check_accuracy_0916_0917.R` works around this with its own independent
`grepl("^WNBA_GAME_[0-9]+$", game_id)` screen, but **this migration-classifier gap itself is NOT
fixed** — flagging it here rather than fixing it, since it wasn't the task asked for either session;
next agent's call whether to add a third detection rule to `migrate_prediction_log()`.

Independent (box-score-verified, non-fixture) result for 2026-09-17's 5 real games: 80.0% win/loss
accuracy (4/5), Brier 0.2025, log loss 0.6026, margin-based MAE/RMSE/bias still unavailable (same NA
`predicted_margin` issue). Full output reproducible via
`Rscript.exe tools/check_accuracy_0916_0917.R`.

**Then, per an explicit "how do we fix the MAE calculation" follow-up, went looking for the root
cause of the NA `predicted_margin` itself (not just its symptom):**
- **Could NOT forensically confirm the exact historical trigger for the 5 already-NA rows** —
  `cache/latest_value_bets.rds` is overwritten on every `evaluate_betting_slate()` run, so the
  2026-09-17 snapshot that produced them no longer exists to inspect. Ruled out several candidate
  causes by direct reproduction in R (documented in-session, not re-derived here): a
  standings-lookup NA would have also nulled `predicted_home_win_prob` (it didn't, since that field
  is real/varied on all 5 rows); the "team not found in standings" fallback branch inside
  `get_model_slate_probabilities()`'s main `if` block defaults `fair_margins[i]` to `0` via
  `numeric(nrow(slate_df))`, not `NA`.
- **Did find and fix one real, currently-live, reproducible bug that's a plausible cause and is
  worth fixing regardless of whether it's THE cause**: `get_model_slate_probabilities()`
  (`market_odds_engine.R`) had a **second** fallback — separate from the per-team one above — for
  when `cache/projected_wnba_standings.rds` itself doesn't exist at all. That fallback returned
  `slate_df |> mutate(model_home_prob = 0.50)`: a flat 50/50 guess with **no `predicted_margin`/
  `contrib_*` columns whatsoever**, silently, with no log line. Downstream, `evaluate_betting_slate()`'s
  `select(predicted_margin = predicted_margin, ...)` would have hard-errored on the missing column
  (not degraded gracefully) — a violation of this repo's own explicit CLAUDE.md fail-safe convention
  ("never hard-crash the pipeline... fall back to a clearly labeled synthetic value").
- **Fix applied (`market_odds_engine.R`, `get_model_slate_probabilities()`)**: that fallback now
  calls `log_warn()` naming the degraded state explicitly, and fills `predicted_margin`/`contrib_*`
  with `NA_real_` (honest "unknown," not a fabricated number) so the schema stays consistent and
  `select()` no longer crashes.
- **Fix applied (`prediction_accuracy_logger.R`, `log_todays_predictions()`)**: added a same-day
  detection check — if any new row has a real `predicted_home_win_prob` but `NA` `predicted_margin`,
  `log_warn()` fires naming the affected `game_id`s. This is the actual forward-looking fix: if this
  class of bug recurs, it's now visible in logs the same day it happens, not rediscovered a week
  later while debugging an empty dashboard chart.
- **NOT done**: no attempt to backfill/recompute the 5 already-logged NA rows' `predicted_margin` —
  that data is genuinely gone (the exact model inputs at that prediction moment aren't reconstructable
  from any surviving cache), and fabricating a plausible-looking number would be strictly worse than
  the current honest `NA` (which the 2026-09-18 dashboard fix and the 2026-09-19 check script both
  already handle correctly). They will simply remain permanently unscoreable on margin.

**Files touched by this two-session thread**: `app.R` (chart/provenance fix),
`market_odds_engine.R` (missing-standings fallback fix), `prediction_accuracy_logger.R` (write-time
consistency warning), `tools/check_accuracy_0916_0917.R` (new, standalone, reusable for a future
date-window spot-check — not part of `run_full_pipeline.R`'s DAG). None of this was run through a
full `run_full_pipeline.R` pass this session — see item 2 in "What's actually live right now" above.

**Open items for the next agent:**
1. Add a `WNBA_GAME_N` (or more generally, a `market_data_source == "UNKNOWN"` combined with a
   known-fixture-matchup) detection rule to `migrate_prediction_log()`'s synthetic classifier, so
   pre-provenance fixture rows stop being permanently misclassified as real. Not fixed this session
   — flagged only.
2. Run `market_odds_engine.R` (or the full pipeline) for real at least once and confirm the new
   `log_warn()` in the missing-standings fallback does NOT fire under normal conditions (i.e.
   `cache/projected_wnba_standings.rds` is present as expected) — this fix has not been exercised
   against a live run yet, only syntax-checked.
3. The Model Diagnostics tab's cosmetic text-overflow gap (narrow-panel annotation clipping, noted
   above) is still open if anyone wants to polish it.
4. Once more real games resolve with a populated `predicted_margin` (post-fix), re-run
   `tools/check_accuracy_0916_0917.R` (or extend its date window) to confirm MAE/RMSE actually
   compute for new data — this was not observable this session since no new real predictions had
   resolved yet.

---

# Handoff — 2026-09-17 — CURRENT STATE

**This section was the "read this first" pointer through the 2026-09-17 sessions; superseded by the
2026-09-19 section above.** Kept here, unedited, as prior-session history per this repo's append-only
convention.

## What's actually live right now

1. **Production pipeline/model work (sessions 1-3) is committed-ready but NOT committed.** Run
   `git status` before doing anything else — nothing from today has been pushed. See "State of the
   repo right now" further down for the exact file list.
2. **`run_full_pipeline.R` has not been run end-to-end since the `team_embeddings.py` CSV-export
   fix** (session 3). Verified standalone, not via a full `run_stage()` invocation. Run it once and
   confirm `[FRESH]` on all three outputs (`logs/analytics.duckdb`, `CACHE_EMBEDDINGS`,
   `CACHE_SIMILARITY`) before trusting it in production.
3. **The prediction-market alpha research thread (sessions 4-6) is CLOSED, negative result, and is
   NOT wired into production.** Full detail immediately below — read this before re-opening that
   thread, so you don't redo work that's already been done and don't miss why it was closed.

## Prediction-market alpha research — CLOSED, no confirmed edge (sessions 4-6, same day)

**Do not re-open this thread assuming there's unexplored upside without reading
`docs/prediction_market_divergence_findings.md` first** — it is short and has the full picture,
including a result that reversed itself on a harder re-test (a useful cautionary example, not just a
formality to skim past).

**One-paragraph summary:** researched whether trading real-money Kalshi WNBA prediction-market
contracts against this repo's existing model outputs has tradeable alpha. Feasibility was confirmed
real (broad Kalshi WNBA coverage, public no-auth API, real historical price data). Built real,
leakage-free (no-lookahead) divergence measurements against real settled Kalshi markets for all four
testable hypotheses:

| Hypothesis | Script | N | Result |
|---|---|---|---|
| Game moneyline (`KXWNBAGAME`) | `tools/research_prediction_market_divergence.R` | 52 real games | No edge — market beat model |
| Player props (`KXWNBAPTS`/`REB`/`AST`) | `tools/research_prediction_market_props_divergence.R` | 198 real settled props | No edge — market beat/matched model |
| Season win totals (`KXWNBAWINS`), v1 | `tools/research_prediction_market_futures_divergence.R` (superseded) | 26 | Looked promising (model favored-side right 84% vs market 60%) |
| Season win totals (`KXWNBAWINS`), v2 | same script, rewritten | 907 snapshots / 53 real markets, clustered | **Reversed v1**: market's favored side right 96.2% vs model's 75.5% in the genuine early-season test window |

**Net result: all four tested hypotheses close as "no confirmed edge." Do not build backtest,
staking, or P&L infrastructure on any of them** — this was the plan's own explicit gate
(`docs/prediction_market_alpha_research_plan.md`'s "Next steps" discipline: measure divergence
first, only build execution infra if a real edge survives), and none did.

**Why the win-totals reversal matters (read this if tempted to trust a first-pass positive result
anywhere in this repo)**: v1 used one observation per market and a plug-in binomial probability
(no parameter uncertainty, produced near-0/near-1 overconfident calls). A follow-up explicitly
requested two fixes — more sample size, better calibration — which were implemented as (a)
multi-snapshot sampling of each market's full daily candlestick history (907 observations across the
same 53 real markets, clustered stats reported since within-market days aren't independent) and (b)
a Beta-Binomial replacing the plug-in binomial. That re-test ALSO caught a second real bug: these
threshold markets close early once mathematically decided, so late-window snapshots are trivially
easy to call correctly for both sides, inflating apparent accuracy without testing real skill.
Splitting into early (≥30 days before close, the genuine test) vs late regimes reversed the
conclusion: the model's Brier score is nominally lower (a calibration-moderation artifact — its
probabilities are less extreme, so wrong calls cost less in squared-error terms), but the market's
favored side is right far more often, which is the decision-relevant number.

**What's NOT closed / could be resumed later, each a real separate question:**
- Polymarket has not been API-checked (Kalshi only, so far).
- Cross-venue arbitrage (Kalshi vs Polymarket vs sportsbook) is untested and doesn't depend on the
  WNBA model being right — unaffected by the above results.
- `KXWNBAH2HPTS`/`KXWNBAH2HPRA` (head-to-head player props) had zero settled markets as of
  2026-09-17 — re-check later, not tested here.
- MVP/DPOY/ROY/COY/championship futures have zero settled markets (2026 season awards not yet
  decided) and this repo has no award-prediction model to compare against regardless.

**Files**: `docs/prediction_market_alpha_research_plan.md` (hypotheses, feasibility, Next Steps
status), `docs/prediction_market_divergence_findings.md` (all four results, full method, the
Brier-vs-win-rate disagreement explained), `tools/research_prediction_market*.R` (four reproducible
scripts, none wired into `run_full_pipeline.R` or any production file), `tools/research_output/*.csv`
(raw per-market/per-snapshot result tables).

---

# Handoff — 2026-09-17 — Play-by-Play Model Extension, `features_cache.rds` Fix, Team-Depth Signal

**Author:** Claude (session ending 2026-09-17). **Audience:** the next agent/human picking this
repo up. Read this before touching `pbp_engine.R`, `player_props_engine.R`, `roster_bottom_up_engine.R`,
`player_metrics.R`, or `run_full_pipeline.R` — several non-obvious decisions and traps are recorded here.

## What this session did, in order

1. Extended the player-level model to use real play-by-play (PBP) data (previously the model only
   used box scores + possession-level RAPM + shot-location data).
2. Built `pbp_engine.R`, a new engine, wired it into the pipeline and dashboard.
3. Empirically derived and wired in a real regression coefficient (`SHOT_MIX_PTS_SLOPE`) linking
   PBP-derived shot mix to prop pricing.
4. Fixed a full-pipeline OOM crash (memory-adaptive parallel plan).
5. Root-caused and fixed a 3-remediation-wave-old "missing `cache/features_cache.rds`" gap.
6. Empirically derived and wired in a second coefficient pair (team depth/rotation-strength) into
   the team-rating margin model.
7. Folded every one-off scratch/verification script produced along the way into reusable `tools/`
   utilities — do not recreate ad hoc probes/checkers this session already generalized (see below).

## New files

| File | Purpose |
|---|---|
| `pbp_engine.R` | New engine. Ingests real ESPN play-by-play (`wehoop::load_wnba_pbp()`, all 8 seasons, 763,018 events) into `cache/wnba_espn_pbp_cache.rds` (config.R: `CACHE_PBP_RAW`). Computes per-player clutch scoring, assists, and shot-mix tendencies (rim/off-dribble/catch-and-shoot/3PT rate) into `cache/player_pbp_features.rds` (config.R: `CACHE_PLAYER_PBP_FEATURES`). Entry point: `compute_player_pbp_features()`, self-runs via `if (!interactive())`. |
| `docs/pbp_shot_mix_regression_findings.md` | Full writeup of the `SHOT_MIX_PTS_SLOPE` derivation (see below). |
| `docs/team_depth_signal_regression_findings.md` | Full writeup of the `TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE` derivation (see below). |
| `tools/research_pbp_granularity.R` | Original feasibility research for PBP (schema dump, ID-namespace check, clutch-scoring prototype). Read-only research artifact, not part of the DAG. |
| `tools/research_shot_mix_regression.R` | Reproducible, single-script derivation of `SHOT_MIX_PTS_SLOPE` (join-check → panel → regression → clamp sanity → live spot-check). Re-run this if `CACHE_PBP_RAW`/`CACHE_PLAYER_BOX` grow with more seasons, to confirm the coefficient is still current. |
| `tools/research_team_depth_regression.R` | Same pattern for the team-depth derivation. |
| `tools/verify_pipeline_stage.R` | Generalized stage-contract checker (mimics `run_stage()`'s entry_fn/call_fn + output-freshness checks for any single stage, without paying for a full pipeline run). Usage: `Rscript.exe tools/verify_pipeline_stage.R <script.R> --entry_fn|--call_fn <fn> <output_path> [...]`. **Use this before adding/changing any pipeline stage** rather than writing a new one-off checker. |
| `tools/probe_screenshots/` | Output dir for `tools/headless_dashboard_probe.R --screenshot`. |
| `tools/research_output/` | Scratch CSV/RDS outputs from the research scripts above (schema dumps, panels). Not consumed by any production code. |

## Modified files and why

- **`config.R`** — added `CACHE_PBP_RAW`, `CACHE_PLAYER_PBP_FEATURES`, `CACHE_FEATURES`'s producer
  now actually exists (see below). No existing constants changed.
- **`player_metrics.R`** — added `compute_and_cache_player_features()`, a thin wrapper around the
  long-existing (but never-called) `get_player_features()`. **Deliberately invoked via
  `run_stage()`'s `call_fn`, not an auto-run footer** — `roster_bottom_up_engine.R` already sources
  this file purely for its function definitions and must not trigger a recompute as a source()
  side effect.
- **`player_props_engine.R`** — added `SHOT_MIX_PTS_SLOPE`/`SHOT_MIX_PTS_CLAMP`/
  `adjust_mu_for_shot_mix()`/`get_player_pct_rim()`, wired additively into the **PTS path only** of
  `generate_active_props_table()`, composed multiplicatively on top of (never replacing) the
  existing `adjust_mu_for_opponent()`/`OPP_DEF_MU_SLOPE` RAPM adjustment, which was not touched.
- **`roster_bottom_up_engine.R`** — added `TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE`/
  `DEPTH_ADJ_CLAMP`/`get_team_depth_signal()`/`adjust_margin_for_depth()`, wired additively into
  `expected_margin` in **both** `predict_live_matchup()` and the inline formula inside
  `project_all_wnba_teams()`'s round-robin loop (the latter does NOT call the former — it
  recomputes the same formula itself; both had to be updated or the signal would never reach
  `cache/projected_wnba_standings.rds`). `rating_diff`/`rapm_diff`/`elo_margin`/`hca`/the
  0.4/0.4/0.2 weights were not touched.
- **`run_full_pipeline.R`** — three changes:
  1. New stage: `player_metrics.R` / `compute_and_cache_player_features` (writes `CACHE_FEATURES`),
     placed right after box-score ingestion (its only dependency), before roster sync.
  2. New stage: `pbp_engine.R` / `compute_player_pbp_features` (writes `CACHE_PLAYER_PBP_FEATURES`),
     placed **sequentially**, right after the 3-way parallel "Latent Engines" group — see the OOM
     note below for why it is not itself inside that parallel group.
  3. **Memory-adaptive parallel plan**: before launching the `future_lapply(multisession)` groups,
     the pipeline now checks real free RAM via `(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory`
     and falls back to `plan(sequential)` below a 4096MB threshold, instead of always using
     `plan(multisession)`. See "OOM root cause" below.
- **`app.R`** — new "Clutch & Shot Profile" tab (`tab_clutch_shot_profile`), reads
  `CACHE_PLAYER_PBP_FEATURES` with a fail-safe "not yet generated" fallback, `DT` table, low-FGA
  players hidden by default (toggle to show), percentages formatted via `scales::percent()`.
- **`tools/headless_dashboard_probe.R`** — generalized: added `tab_clutch_shot_profile` to the
  standard sweep, added an optional `--screenshot` flag (per-tab screenshot + row/header check).
  **Bug fixed during this generalization**: an unscoped `document.querySelector("table.dataTable")`
  silently matched whichever tab's table happened to render first in the DOM (Shiny/bslib keep
  every tab's DOM mounted, just hidden) instead of the actually-active tab. Fixed with a
  visibility-based lookup (`.filter(t => t.offsetParent !== null)`). If you add table-content
  checks to this probe again, use that pattern, not a bare `.active` class selector (tried that
  first — this app's tab panes don't reliably carry one either).

## Root causes found and fixed (read before re-investigating these)

### 1. `cache/features_cache.rds` "missing" (flagged and ignored across 3 remediation waves)

`config.R` declared `CACHE_FEATURES` since Phase 0. `tools/data_health_probe.R` checked for it the
whole time. **Nothing ever produced it** — `player_metrics.R::get_player_features()` was fully
implemented and real-data-backed from the start, just never invoked by any stage. Three separate
past waves (`docs/task_assignments_phase4.md` lines ~181, ~1040, ~1257) flagged the resulting
health-probe warning as "pre-existing and unrelated" without tracing it this far. **Also
important: there was no consumer either** — nothing read `team_weighted_bpm`/`team_top5_bpm`/
`team_minutes_concentration` anywhere. Fixed in two tiers: Tier 1 (producer wired up, see
`player_metrics.R`/`run_full_pipeline.R` above) landed first; Tier 2 (a real consumer, see the
team-depth regression below) followed once Tier 1 was verified. `tools/data_health_probe.R` now
reports `OVERALL HEALTH: PASSED` for the first time in this repo's history.

### 2. Full pipeline OOM-killed twice

Both kills happened inside the parallel "Latent Engines Group" (`future_lapply(plan(multisession))`).
**Initial hypothesis (wrong): blamed on adding `pbp_engine.R` as a 4th parallel worker.** Moved it
out of the parallel group — pipeline was OOM-killed again anyway, this time during `rapm_engine.R`
with only the original 3 workers. **Actual cause**: this machine's real free RAM at the time was
genuinely low (~3.2-3.9GB) because of an ordinary ~40-tab interactive Chrome session (confirmed via
`Get-CimInstance Win32_Process` — none of those processes carried `--headless`/`--remote-debugging-port`
flags, i.e. NOT leftover test automation, a real user browser session that must never be
touched/killed by this pipeline). Each `future_lapply` `multisession` worker is a full separate R
process with its own package-loading overhead; 3+ concurrent workers exceeded available RAM.
**Fix**: `run_full_pipeline.R` now checks free RAM and falls back to `plan(sequential)` below
4096MB (see "Modified files" above) instead of hardcoding sequential (which would needlessly slow
down every future run, including the unattended scheduled one in `schedule_daily.bat`, where this
contention likely won't exist). **If you see this OOM again**: don't immediately blame the newest
stage — check `Get-CimInstance Win32_OperatingSystem` free memory and running Chrome/R processes
first, exactly as done here.

### 3. `rapm_engine.R` / `pbp_engine.R` naming collision (caught and avoided, not a live bug)

`rapm_engine.R` already owned both a function named `load_or_build_wnba_pbp_cache()` and the cache
literal `cache/wnba_pbp_cache.rds` — for a **different** dataset (WNBA-Stats-API possessions/shots,
not ESPN event-level PBP). `pbp_engine.R`'s first draft collided with this and loaded the wrong
cache. Renamed to `load_or_build_wnba_espn_pbp_cache()` / `cache/wnba_espn_pbp_cache.rds`. **If you
add another data-ingestion engine, grep for existing function/cache-literal names first** — this
repo has multiple engines that sound similar (`rapm_engine.R`'s possessions vs. `pbp_engine.R`'s
events vs. `shot_quality_engine.R`'s shot locations) and nothing enforces uniqueness automatically.

## Empirical results wired into the live model (re-validate periodically — see below)

### `SHOT_MIX_PTS_SLOPE` (`player_props_engine.R`)

Within-player fixed-effects regression, 13,037 player-games / 235 players (2019-2026): a player's
rim-attempt share (`pct_rim`, from `pbp_engine.R`) predicts that game's fractional scoring output
beyond their own season average, **+0.1174 fractional pts per +1.0 pct_rim** (p = 2.51e-13),
controlling for minutes. Wired additively (multiplicative ratio, clamped ±10%, non-binding on real
data). Full derivation: `docs/pbp_shot_mix_regression_findings.md`, reproducible in
`tools/research_shot_mix_regression.R`.

### `TOP5_BPM_MARGIN_SLOPE` / `MINUTES_CONCENTRATION_MARGIN_SLOPE` (`roster_bottom_up_engine.R`)

Within-team fixed-effects regression, 3,831 team-games / 15 teams: a team's **trailing** (strictly
prior games, avoiding same-game circularity — `team_top5_bpm`/`team_minutes_concentration` are
computed FROM the same box stats that determine that game's own margin, so same-game regression
would be near-tautological) rolling averages of starting-unit strength and rotation
concentration both predict its next game's margin, controlling for its own trailing-average
margin:
- `team_top5_bpm`: **+1.1563 pts/unit** (p = 0.0011) — sign as expected.
- `team_minutes_concentration`: **-120.82 pts/unit** (p = 0.0217) — sign was NOT predictable a
  priori (short rotation could mean "stars carry the load" or "thin-bench fragility"); came out
  negative (fragility reading). **Flagged collinearity**: VIF up to 4.80 (ceiling is usually ~5) —
  close but not disqualifying; both terms remain independently significant. Worth re-checking as
  more seasons of `cache/features_cache.rds` accumulate.

Wired additively into `expected_margin`, clamped ±6pts (non-binding, real spread ±4.14). Full
derivation: `docs/team_depth_signal_regression_findings.md`, reproducible in
`tools/research_team_depth_regression.R`.

## Known limitations / open items for the next agent

1. ~~`get_player_bpm_ratings()` (`roster_bottom_up_engine.R`) vs. `calculate_bpm_components()`
   (`player_metrics.R`) are two independent, differently-weighted BPM implementations.`~~
   **AUDITED 2026-09-17, closed as "deliberately decoupled, safe as-is"** — see
   `docs/bpm_implementation_audit_findings.md`. Confirmed no call site mixes raw values from both;
   each feeds a separate, independently-calibrated term summed into `expected_margin`. Cross-
   reference comments added at both function definitions so a future edit to either doesn't
   silently invalidate the other's empirical calibration (in particular: `TOP5_BPM_MARGIN_SLOPE`/
   `MINUTES_CONCENTRATION_MARGIN_SLOPE` are regressed against `calculate_bpm_components()`'s exact
   weights — changing them requires re-running `tools/research_team_depth_regression.R`).
2. **Both new BPM-derived signals (props shot-mix, team depth) still ultimately trace back to
   `player_metrics.R`'s NBA-inherited, never-recalibrated-for-WNBA BPM weights** (see that file's
   own `TODO(recalibrate)` comment). The depth-signal regression validates that the SIGNAL predicts
   real outcomes even with those weights, which is reassuring, but recalibrating the underlying
   weights against real WNBA data (as that TODO has asked for since Phase 0) could still change
   the numbers `team_top5_bpm ` /`team_weighted_bpm` produce.
3. **Re-run both regression scripts periodically** (`tools/research_shot_mix_regression.R`,
   `tools/research_team_depth_regression.R`) as more seasons accumulate in
   `cache/wnba_espn_pbp_cache.rds` / `cache/features_cache.rds` — both coefficients are real,
   re-checkable empirical results, not one-time assertions, exactly like `OPP_DEF_MU_SLOPE`'s own
   convention.
4. **The `MIN_FREE_MB_FOR_PARALLEL <- 4096` threshold in `run_full_pipeline.R` is a first guess**,
   not itself empirically tuned — if the pipeline still OOMs above that threshold, or runs slower
   than necessary well below it, revisit the number rather than assuming it's exactly right.
5. **`docs/task_assignments_phase4.md`'s Handoff Notes still describe `cache/features_cache.rds`
   as missing** — those are historical, append-only records and were deliberately NOT edited (per
   this repo's own convention of never rewriting past phase files); this `HANDOFF.md` is the
   up-to-date pointer instead.
6. Two scratch verification scripts from mid-session (`tools/test_pbp_stage_integration.R`,
   `tools/probe_clutch_tab.R`) were folded into `tools/verify_pipeline_stage.R` and
   `tools/headless_dashboard_probe.R --screenshot` respectively and then deleted — if you find
   references to those two filenames anywhere (there shouldn't be any left), they're stale.

## How to verify current state quickly

```
# Full pipeline (uses existing caches, no force-refresh):
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" run_full_pipeline.R

# Single-stage contract check (no full pipeline run):
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/verify_pipeline_stage.R pbp_engine.R --entry_fn compute_player_pbp_features cache/player_pbp_features.rds
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/verify_pipeline_stage.R player_metrics.R --call_fn compute_and_cache_player_features cache/features_cache.rds

# Dashboard sweep (all 9 tabs, headless Chrome):
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/headless_dashboard_probe.R --screenshot

# Re-check both empirical derivations against current data:
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/research_shot_mix_regression.R
"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/research_team_depth_regression.R
```

A skill (`empirical-signal-integration`) was drafted alongside this handoff to make the
research → derive → wire-in → verify → document process repeatable for the next granular-data
extension — see `.claude/skills/empirical-signal-integration/SKILL.md`.

## Follow-up (same day, second session)

1. **Built the three planned skills below** (`orphaned-cache-audit`, `new-pipeline-stage-checklist`,
   `headless-ui-regression-sweep`) — all now exist under `.claude/skills/`.
2. **Ran `orphaned-cache-audit` for real** and found a genuine `ORPHANED` finding:
   `CACHE_EMBEDDINGS`/`CACHE_SIMILARITY` (`data/team_embeddings.csv` /
   `data/team_similarity_matrix.csv`) had a real consumer (`load_embeddings.R`) but zero producer
   — `team_embeddings.py` had migrated to writing only `logs/analytics.duckdb` (already flagged,
   unresolved, in `run_full_pipeline.R`'s own 2026-09-17 comment). Fixed additively:
   `team_embeddings.py::save_to_db()` now writes both CSVs again alongside duckdb (verified real
   15x16/15x15 output on disk), and `run_full_pipeline.R`'s `team_embeddings.py` stage now declares
   all three outputs. Note: the audit script still reports this pair `ORPHANED` even after the fix,
   because the producer writes via aliased Python variable names rather than the literal path
   string — a disclosed limitation of the audit's name/literal grep, not a real bug; confirmed by
   direct file inspection instead.
3. **Audited the BPM-implementation open item and closed it** — see
   `docs/bpm_implementation_audit_findings.md` and the "Known limitations" section above (struck
   through, not deleted).

## Planned skills (ALL THREE BUILT — see Follow-up section above; specs below kept for historical record only, not actionable anymore)

Three more skill gaps were identified this session, motivated by real recurring pain points (not
hypothetical). They are specced in full detail below so the next agent can build them directly
without re-deriving the rationale. **When actually writing each `SKILL.md`, keep it concise** —
`empirical-signal-integration/SKILL.md` (built this session) is comprehensive but long, and that
length should not be the template going forward. Target roughly half that length per skill:
frontmatter, a 2-4 sentence "why this exists," a short bulleted "when to use," and a direct
numbered procedure — steps should be imperative instructions, not restated rationale/history
paragraphs. Put the "why" detail (the specific past bug, the specific past incident) in ONE
sentence with a pointer to this handoff or the relevant script's own comments, not repeated prose
inside the skill body. The specs below are intentionally more detailed than the eventual SKILL.md
files should be — they're the design notes, not a draft to copy-paste.

### 1. `orphaned-cache-audit`

**Motivation:** `cache/features_cache.rds` had a `config.R` constant, a `tools/data_health_probe.R`
check, and zero producer AND zero consumer for at least 3 remediation waves before this session
traced it. `config-constant-drift-audit` already exists for numeric-literal drift against
`config.R`; nothing plays the equivalent role for `CACHE_*` cache-path constants going stale/dead.

**Purpose:** for every `CACHE_*`/cache-path constant declared in `config.R` (plus known
intentional literals — see allowlist below), report whether anything actually writes it
(producer) and whether anything actually reads it (consumer), and flag the four possible states.

**Detailed procedure to implement:**
1. Parse `config.R` for every `NAME <- file.path(...)`/`NAME <- "cache/....rds"`-style constant
   whose value resolves under `cache/` or `data/` (reuse or adapt `config-constant-drift-audit`'s
   existing `config.R`-constant parser rather than writing a second one from scratch — check
   `.claude/skills/config-constant-drift-audit/scripts/audit_constants.R` first).
2. Resolve each constant to its literal path string (evaluate the `file.path()` call or read the
   literal), since some real consumers reference the LITERAL PATH instead of the constant name —
   this is not hypothetical: CLAUDE.md documents `cache/projected_wnba_standings.rds` as
   **deliberately** a bare literal repeated across `app.R`, `market_odds_engine.R`,
   `roster_bottom_up_engine.R`, `rapm_engine.R`, etc., with no `config.R` constant at all. The
   audit must match BOTH the symbolic constant name AND its resolved literal string against every
   `saveRDS(...)`/`readRDS(...)`/`write.csv(...)`/`read.csv(...)`/`file.exists(...)` call site
   repo-wide (`*.R`, `*.r`, `*.py`), not just symbol occurrences.
3. Classify each cache path into: `OK` (>=1 producer and >=1 consumer other than
   `tools/data_health_probe.R`'s own existence check), `ORPHANED` (>=1 consumer, zero producer —
   the exact `features_cache.rds` shape before this session's fix), `DEAD` (>=1 producer, zero
   consumer beyond the health probe), `UNUSED` (declared in `config.R`, zero producer, zero
   consumer anywhere).
4. Maintain an explicit allowlist/known-exceptions block (mirroring
   `config-constant-drift-audit`'s "Known-clean baseline" section) for legitimately
   producer-only-for-now or diagnostic-only caches, so the audit doesn't cry wolf on every run —
   but any NEW entry added to that allowlist must be justified in the audit's own output, not
   silently excluded.
5. Print a findings table (cache path | constant name or "LITERAL ONLY" | producer file(s) |
   consumer file(s) | classification) and a one-line verdict.

**When to use:** before merging any change that adds/removes a `CACHE_*` constant or a
`saveRDS`/`readRDS` call site; as a periodic health check; whenever `tools/data_health_probe.R`
reports a cache missing and it's not immediately obvious why.

**Files to create:** `.claude/skills/orphaned-cache-audit/SKILL.md`,
`.claude/skills/orphaned-cache-audit/scripts/audit_caches.R`.

### 2. `new-pipeline-stage-checklist`

**Motivation:** this session added two new stages to `run_full_pipeline.R` and got real details
wrong on the first attempt each time — a parallel-group placement that contributed to (though
wasn't solely responsible for) an OOM kill, and an `entry_fn`/`call_fn` choice that has a
documented double-execution failure mode elsewhere in this same file (see the `daily_ingest.R`
comment block in `run_full_pipeline.R` about why it deliberately uses `call_fn` and NOT the
`!interactive()` migration). This is narrower than `empirical-signal-integration` (no
modeling/regression content) and applies to any new stage, modeling-related or not.

**Detailed procedure to implement:**
1. Identify the new stage's real dependencies (which caches/globals must already exist) and place
   it in the DAG after whatever produces them — verify by reading `run_full_pipeline.R`'s existing
   stage order and comments, don't guess.
2. Decide `entry_fn` vs. `call_fn` (mutually exclusive, per `run_stage()`'s own `stop()` if both
   are passed): if the script already self-runs via `if (!interactive())` or `sys.nframe() == 0`,
   use `entry_fn` (verification only — `run_stage()` does not invoke it). If the script is also
   `source()`d elsewhere for its pure function definitions (as `player_metrics.R` is by
   `roster_bottom_up_engine.R`, and `daily_ingest.R` was historically by
   `prediction_accuracy_logger.R`), it must NOT self-run on a bare source — use `call_fn` to invoke
   explicitly, and confirm the script's own footer does NOT also fire under `source()` (a stage
   with both an active self-run guard AND a `call_fn` invocation double-executes).
3. Decide whether to declare `output=`. Declare every file the stage writes UNLESS the stage has
   legitimate no-op-on-no-new-data semantics (e.g. `daily_ingest.R` skips writing when there are no
   new games) — declaring `output=` on a legitimately-quiet stage produces a false staleness `WARN`
   on every quiet run and trains the operator to ignore real ones.
4. If the stage is a candidate for an existing `future_lapply(plan(multisession), ...)` parallel
   group: confirm it's truly independent of every other member of that group, and default to
   sequential placement instead unless there's a real throughput reason — each `multisession`
   worker is a full separate R process (its own package loads, no memory sharing), and this repo
   has a real, documented OOM history from underestimating that cost (see this handoff's OOM
   section above and `run_full_pipeline.R`'s own 2026-09-17 memory-adaptive-plan comment).
5. Before a full pipeline run, verify the stage's contract in isolation with
   `tools/verify_pipeline_stage.R <script.R> --entry_fn|--call_fn <fn> <output_path> [...]`
   (already exists in this repo — read its usage comment, don't reimplement).
6. Run the full pipeline once for real and confirm the new stage shows `[FRESH]` for every
   declared output and no `[FAILED]`/staleness `[WARN]`.

**When to use:** adding, removing, or reordering any stage in `run_full_pipeline.R`.

**Files to create:** `.claude/skills/new-pipeline-stage-checklist/SKILL.md` (this one likely needs
no separate `scripts/` — it orchestrates existing tools rather than adding a new one).

### 3. `headless-ui-regression-sweep`

**Motivation:** `app.R` changes in this repo have shipped real, silent bugs before (the injury-tab
`%||%`-on-a-vector crash that motivated `tools/headless_dashboard_probe.R`'s own creation), and
this session found a bug IN THE PROBE ITSELF (an unscoped `table.dataTable` selector silently
matching the wrong tab) that only surfaced because a screenshot was manually inspected rather than
trusting the JS row-count check alone. A skill should make "verify visually, don't just trust
`.shiny-output-error` absence" a forced habit, not something remembered ad hoc.

**Detailed procedure to implement:**
1. After ANY `app.R` edit, run `tools/headless_dashboard_probe.R` with no arguments (full sweep,
   all tabs, fast, error-only) as a first-pass regression check.
2. If the edit added/changed a specific tab's content (new table, new reactive, new column), also
   run it scoped with `--screenshot`: `tools/headless_dashboard_probe.R <tab_value> --screenshot`.
3. Read the saved screenshot in `tools/probe_screenshots/<tab_value>.png` with the Read tool and
   visually confirm real data renders correctly — do NOT treat the JS-reported row-count hint as
   authoritative by itself; it has a known reliability gap on at least one DT rendering pattern in
   this app (documented in `tools/headless_dashboard_probe.R`'s own comment). The header-line
   check (confirms the right tab's table was found) and the screenshot are the trustworthy signals.
4. If a tab was added/removed/renamed, update the `TAB_VALUES` constant in
   `tools/headless_dashboard_probe.R` itself so the no-argument full sweep keeps covering it.
5. Treat ANY `.shiny-output-error` element or browser console `SEVERE`/`error` log line as a hard
   blocker — do not report a UI task done with either present.

**When to use:** any `app.R` change, before declaring a dashboard/UI task complete.

**Files to create:** `.claude/skills/headless-ui-regression-sweep/SKILL.md` (no new script needed —
this skill orchestrates the existing `tools/headless_dashboard_probe.R`).

---

# Handoff — 2026-09-17 — Pausing here (third session, same day)

**Audience:** whoever picks this repo up next, possibly after a long gap. Read this section first
— it's the actual current state. Everything above this line is prior-session history, kept for
context/rationale, not a live task list (the "Planned skills" section above is fully resolved).

## State of the repo right now

- All production pipeline/model work from the first two sessions today is committed-ready but
  **not yet committed** — check `git status` before doing anything else. Nothing was pushed.
- `run_full_pipeline.R` has not been run end-to-end since the `team_embeddings.py` CSV-export fix
  (see below) — the CSVs were verified by running `team_embeddings.py` standalone, not via a full
  pipeline run. Run the full pipeline once and confirm `[FRESH]` on all three of its outputs
  (`logs/analytics.duckdb`, `CACHE_EMBEDDINGS`, `CACHE_SIMILARITY`) before trusting it in
  production, per the `new-pipeline-stage-checklist` skill.
- A brand-new, **separate, not-production** research track was started this session: prediction-
  market alpha research. It touches no production file and is safe to ignore entirely if the next
  agent's task is unrelated — see its own section below.

## What happened this session, in order

1. Read the existing `docs/HANDOFF.md` (from the prior two sessions) at the user's request.
2. Built the three previously-specced-but-not-built skills: `orphaned-cache-audit`,
   `new-pipeline-stage-checklist`, `headless-ui-regression-sweep` (all under `.claude/skills/`).
   Details in the "Follow-up (same day, second session)" section above.
3. Ran `orphaned-cache-audit` for real, found and fixed a genuine orphaned-cache bug
   (`CACHE_EMBEDDINGS`/`CACHE_SIMILARITY` — `team_embeddings.py` had stopped producing them after
   migrating to duckdb). Fix, verification, and a disclosed limitation of the audit tool itself are
   in that same "Follow-up" section.
4. Audited and closed the `get_player_bpm_ratings()` vs. `calculate_bpm_components()` open item —
   see `docs/bpm_implementation_audit_findings.md`. Closed as "deliberately decoupled, safe as-is,"
   not as a code change (cross-reference comments only).
5. Kicked off a new research side project at the user's request: does trading real-money
   prediction-market contracts (Kalshi, Polymarket) against this repo's existing model outputs have
   alpha potential? See the dedicated section immediately below — this is the part most likely to
   need picking back up after a long pause, since it's mid-flight by design (explicitly staged,
   not meant to be finished in one sitting).

## Prediction-market alpha research — where it stands

**Full writeup:** `docs/prediction_market_alpha_research_plan.md` (revenue-stream hypotheses,
feasibility findings, explicit "next steps in order" list — read that file's own "Next steps"
section before doing anything else on this thread, don't re-derive the plan from scratch).

**One-paragraph state:** Feasibility is confirmed real (not assumed) — Kalshi's WNBA market
coverage is broad (game lines, spreads/totals, player props including head-to-head, season
awards/futures) via a fully public, no-auth REST API, with real minute-level historical price data
confirmed on an actual settled game. `tools/research_prediction_markets.R` exists and does exactly
one thing so far: verifies a real, empirically-checked 15/15 team-code join between Kalshi's
tickers and `config.R`'s `WNBA_TEAMS`, catching two real code mismatches along the way (`CONN`/`CON`,
matching the known wehoop gotcha, plus a **new** one this script found itself: `PDX`/`POR` for
Portland). Polymarket has not been API-tested yet.

**What is explicitly NOT done yet** (do not assume any of this happened):
- No model-vs-market divergence has been measured. This is the very next step and the single most
  important one — it determines whether any of this is worth pursuing further at all. See
  `docs/prediction_market_alpha_research_plan.md`'s "Next steps," item 2, for exactly how to do it
  (retrospective/no-lookahead win probability vs. real historical Kalshi prices, joined via
  `normalize_kalshi_team_code()`).
- No backtest, no P&L simulation, no fee/slippage modeling.
- No Polymarket connectivity check.
- No paper-trading or live-trading infrastructure of any kind. No money has been risked and none
  should be without a separate, explicit, later authorization — this is pure research using public
  read-only market data.
- Nothing from this thread is wired into `run_full_pipeline.R`, `app.R`, or any betting-facing
  production file. It is 100% isolated to `tools/research_prediction_markets.R` and the two docs
  named above.

**To resume:** read `docs/prediction_market_alpha_research_plan.md` end to end (it's short), run
`tools/research_prediction_markets.R` again to reconfirm the join still holds (team codes could
have changed), then proceed to "Next steps" item 2 (the divergence measurement) — that is the
actual next unit of work, not a re-scoping exercise.

## Follow-up (same day, fourth session) — prediction-market divergence measured, no edge found

Picked up the prediction-market thread at "Next steps item 2" (the one explicitly flagged as the
most important, do-this-before-anything-else step). Built
`tools/research_prediction_market_divergence.R`, which pulls all 260 real settled `KXWNBAGAME`
Kalshi markets, joins 129 of them uniquely to real games in `data/box_scores_cache.rds` (correctly
rejecting the 1 non-franchise All-Star exhibition event in the pull), prices 52 of those at their
last pre-tip-off candlestick, and compares that market price to a retrospective/no-lookahead model
win probability (same leakage-free trailing-rolling-margin method as
`tools/backtest_margin_hyperparams.R`'s Track A — deliberately NOT `predict_live_matchup()`, which
reads today's caches and would leak future information into a historical comparison).

**Real result: no edge.** Model Brier score (0.2047) is worse than the market's (0.1963), and at
every divergence threshold tested, the **market's** favored side won ~67-71% of the time vs. the
**model's** favored side winning only ~37-44% — the opposite of what a tradeable-edge hypothesis
needs. Full writeup and disclosed limitations (N=52 is small, single 7-week window, 60% of matched
games lacked a usable pre-tip-off price) in `docs/prediction_market_divergence_findings.md`.
`docs/prediction_market_alpha_research_plan.md`'s "Next steps" section is updated to reflect this:
step 2 done, step 3 (backtest/P&L infra) explicitly NOT recommended for hypotheses #1/#2 given this
result, step 4 (player props / season futures divergence) is the actual next open item on this
thread if anyone picks it back up — a separate empirical question with a different liquidity
profile, not ruled out by this result.

No production file touched. This remains 100% isolated to `tools/research_prediction_market*.R`
and the two docs named above, per the thread's own stated scope.

## Follow-up (same day, fifth session) — hypotheses #3 (player props) and #4 (win totals) tested

Extended the divergence measurement to the two remaining testable hypotheses from the plan's Next
Steps #4. Built `tools/research_prediction_market_props_divergence.R` (hypothesis #3) and
`tools/research_prediction_market_futures_divergence.R` (hypothesis #4). Full results in the
now-3-hypothesis `docs/prediction_market_divergence_findings.md`; `docs/prediction_market_alpha_research_plan.md`'s
Next Steps updated to mark #4 done.

**#3 (player props, KXWNBAPTS/REB/AST): no edge.** Real coverage was far deeper than expected —
5,695 settled single-player prop markets pulled, 5,515 joined cleanly to
`data/player_box_scores_cache.rds` with a 0-mismatch sanity check. N=198 priced (reproducible random
sample of the ~4,000 qualifying markets, to bound API load). Model Brier (0.1977) slightly worse
than market's (0.1931); market's favored side right more often at most divergence thresholds.
Closed as tested, same disposition as the game-moneyline result.

**#4 (season win totals, KXWNBAWINS): a real but small/fragile signal.** Real settled markets exist
mid-season because these threshold markets close early once mathematically decided. **Caught and
fixed a real methodology bug during this run**: all 53 real settled markets opened before the
season's first game, so an initial leakage-free "trailing in-season win rate" degenerated to a
blind 0.5 for every team (zero real signal, not a meaningful test at all). Fixed by falling back to
that team's real prior-season win rate as a leakage-free preseason prior, blended in as real games
accumulate. After the fix: N=26 priced markets, model Brier 0.1276 vs market's 0.2482, model's
favored side right 84% vs market's 60% — but flagged as likely overconfident (plug-in binomial, no
parameter uncertainty on the win-rate estimate) and too small a sample (one season, ~15-20 distinct
team-thresholds) to trust yet. Documented as "worth a second look with more data + a better
probability model," explicitly NOT as confirmed edge or a reason to build staking infrastructure.

**Overall: 2 of 3 tested hypotheses (game moneyline, player props) show no edge; the third (win
totals) shows a promising but unconfirmed signal.** No production file touched.

## Follow-up (same day, sixth session) — win-totals "signal" re-tested harder, reversed to no edge

Directly acted on the #4 result's own stated caveats (small N, likely-overconfident probability
model) per explicit follow-up request: "how do we increase sample size, how do we calibrate a
better probability model, implement." Rewrote
`tools/research_prediction_market_futures_divergence.R`:

- **Sample size**: instead of one price-at-`open_time` observation per market (N=26), pull each of
  the 53 real settled `KXWNBAWINS` markets' full daily candlestick history in a single API call,
  then take a snapshot every 5 days (907 total observations across the same 53 real markets).
  Reports both pooled (labeled anti-conservative) and market-clustered statistics, since
  within-market snapshots are correlated.
- **Calibration**: replaced the plug-in binomial (which had produced near-0/near-1 overconfident
  probabilities) with a Beta-Binomial — Beta prior seeded from real prior-season win rate,
  updated with real current-season wins/losses, `PRIOR_STRENGTH` swept over 5 values rather than
  asserted (full sweep saved to `tools/research_output/prediction_market_futures_divergence_prior_sweep.csv`).

**Caught a second real methodology bug during this re-test**: `KXWNBAWINS` markets close early once
mathematically decided, so snapshots taken close to each market's real close date are close to a
trivially certain outcome for both series — both naturally converge toward 0/1, which would make
"who called it right" look artificially close to 100% for both without testing real forecasting
skill. Fixed by splitting every snapshot into EARLY (≥30 days before that market's close) vs LATE
regimes. **Result: in the genuine EARLY-regime test, the market's favored side was right 96.2% of
the time vs. the model's 75.5%** — even though the model's Brier score is nominally still lower (a
calibration/moderation artifact, explained in the findings doc, not evidence of real model skill).
**This reverses v1's "promising signal" conclusion.**

`docs/prediction_market_divergence_findings.md` rewritten with the full v1-vs-v2 comparison and the
Brier-vs-win-rate disagreement explained; `docs/prediction_market_alpha_research_plan.md`'s Next
Steps updated. **Net result across the whole prediction-market thread: all four tested hypotheses
(#1/#2 game moneyline, #3 player props, #4 win totals) now close as "no confirmed edge" — do not
build backtest/staking/P&L infrastructure for any of them.** The #4 reversal is itself the most
useful finding here: a promising-looking first-pass result did not survive a harder, more honest
re-test, which is the concrete demonstration of why this plan's "measure before building" discipline
exists. No production file touched.

## Everything else still open (carried over, unchanged, from earlier sessions)

- Re-run `tools/research_shot_mix_regression.R` / `tools/research_team_depth_regression.R`
  periodically as more seasons accumulate (unchanged advice from earlier in this file).
- `MIN_FREE_MB_FOR_PARALLEL <- 4096` in `run_full_pipeline.R` is still an untuned first guess.
- A full pipeline run to confirm the `team_embeddings.py` CSV fix survives a real `run_stage()`
  invocation (not just a standalone script run) has not been done — see "State of the repo right
  now" above.

---

# Archive addition — moved 2026-10-07 during a `docs/HANDOFF.md` trim (via `trim-handoff`)

Everything from this point to the end of the file was, at the time of this trim, either fully
closed/shipped work or a superseded intermediate "current state" snapshot from a session that has
since been superseded by a later one. Section headers, numbering, and all cross-references
(commit hashes, issue numbers, "see the section above/below" pointers) are preserved **exactly as
originally written** in `docs/HANDOFF.md` before this trim — they do not match the live doc's
current structure. Two things worth flagging for anyone reading this archived material:

- The session titled "added a user-adjustable minimum-possessions filter to Tab 6" (immediately
  below) describes its own edit to `summary_app.R` as **"uncommitted, not pushed"** at the time it
  was written. That is no longer true: `git log` confirms this work was committed as `153c9de`
  ("feat(summary_app): make Tab 6's RAPM possession filter user-adjustable") sometime after that
  session ended and before this trim. Treat the code as shipped; only the tracker-status framing
  in that section's own text is stale.
- The GitHub issue tracker discrepancy flagged repeatedly throughout the sessions below (#43, #44,
  #49 shown `OPEN` despite #49's underlying code being merged back in session `e5c97f3`) is **still
  unreconciled** as of this trim (`gh issue list --state open` on 2026-10-07 still shows all three
  open) — see `docs/HANDOFF.md`'s current "Open items" section for the up-to-date pointer; don't
  rely on any single archived section's framing of this, several of them repeat the same flag.

For current project state, environment notes that are still live, and the actual next step, see
`docs/HANDOFF.md` — this archive is non-load-bearing history only.

---

# Handoff — 2026-10-07 (New thread: added a user-adjustable minimum-possessions filter to Tab 6 "Player Ratings (RAPM)" — no issue ticket, ad hoc user request, direct edit (no subagent dispatch) — **uncommitted, not pushed** as of this writing) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail)

**This supersedes the section immediately below as the "current state," but everything in that section not explicitly updated here is still accurate** — this thread only touched `summary_app.R`. `docs/SUMMARY_APP_SPEC.md` was not read or updated (this was a small ad hoc tweak, not a spec'd ticket). The user asked, in two steps: (1) "For tab 6, let's default filter out players with fewer than 1000 possessions and have a button to filter back in those players," (2) after that landed, "adjust the filter to 2500, and then let the user decide what value to filter out."

## What this thread did

1. **First pass (now superseded by step 2, kept here for the full story)**: added `RAPM_MIN_POSSESSIONS_DEFAULT <- 1000` and an `input_switch("rapm_include_low_poss", ...)` (default off) in the Team Filter card, then had `r_rapm_filtered()` drop any row with `n_off_poss + n_def_poss < 1000` unless the switch was on.
2. **Second pass, replacing the switch entirely**: changed the default to `RAPM_MIN_POSSESSIONS_DEFAULT <- 2500` (`summary_app.R:369`) and swapped the on/off `input_switch` for a `numericInput("rapm_min_possessions", "Minimum total possessions (offensive + defensive)", value = RAPM_MIN_POSSESSIONS_DEFAULT, min = 0, step = 100, width = "350px")` (`summary_app.R:559-564`), so the user picks the exact cutoff rather than a fixed value — setting it to `0` shows every matched player. `r_rapm_filtered()` (`summary_app.R:1693` onward) now reads `input$rapm_min_possessions` directly each time (falling back to `RAPM_MIN_POSSESSIONS_DEFAULT` if blank/`NA`), computes `total_poss` via `coalesce(n_off_poss, 0) + coalesce(n_def_poss, 0)` (per `CLAUDE.md`'s rule against vector `%||%`), and only applies the cutoff when `min_poss > 0`.
3. **Validated with `parse(file = "summary_app.R")`** (written to a temp `.R` file and run via the full `Rscript.exe` path, per `CLAUDE.md`'s segfault warning about inline multi-line `-e`) after each pass — syntax-only, confirmed clean both times.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `summary_app.R` | **Modified, not committed.** 1,869 → 1,896 lines (+33/-6 net per `git diff --stat`). | Tab 6's possession filter: `RAPM_MIN_POSSESSIONS_DEFAULT` constant (~line 369), `numericInput("rapm_min_possessions", ...)` in the Team Filter card (~line 559), filtering logic inside `r_rapm_filtered()` (~line 1693-1710). The table (`output$rapm_table`) and chart (`output$rapm_top_bottom_plot`) both read `r_rapm_filtered()` already, so both picked up the new filter automatically — neither was edited directly. **Line numbers will drift — re-grep by symbol name (`RAPM_MIN_POSSESSIONS_DEFAULT`, `rapm_min_possessions`), don't trust these as permanent.** |

## Validation actually performed this session — and what wasn't

- **`parse(file = "summary_app.R")`** run via `Rscript.exe` after each of the two edit passes — both clean, no syntax errors. This is the *only* validation performed.
- **Not done this session**: no `Rscript.exe summary_app.R` live-launch smoke test (unlike the prior Tab 6 session, which ran one with a timeout wrapper), no headless browser check of Tab 6 (the `headless_dashboard_probe.R` gap flagged in the section below is still open and still applies here), and no check against real `cache/rapm_ratings.rds` data that the numeric input actually narrows the table/chart as expected in a running app. This was treated as a small, low-risk, pattern-matching UI tweak (mirrors the existing team-filter reactive exactly), not as justifying the same validation depth as a full new tab — but a real browser check of the numeric input (including an invalid/blank value, and setting it to `0`) is still worth doing before this is considered fully verified.
- Pre-existing uncommitted `cache/prediction_accuracy_log.csv`/`.rds` and `data/box_scores_cache.rds` changes (present at session start, same scheduled-pipeline churn every prior session has flagged and left alone) are still sitting in the working tree, untouched by this thread.

## Concrete next step

1. **Do a real browser check of the new control** before trusting it fully: launch `summary_app.R` (e.g. via RStudio's "Run App" or `shiny::runApp("summary_app.R")` from an interactive session, not a backgrounded `Rscript.exe` call which blocks), go to Tab 6, confirm the table and chart both shrink/grow as the "Minimum total possessions" numeric input changes, and confirm `0` shows every matched player and an invalid/blank value falls back to `2500` rather than erroring.
2. **Decide whether to commit.** This thread's edits are uncommitted and unpushed — the user has not yet asked for a commit. If/when asked, stage only `summary_app.R` (the pre-existing cache-file churn should stay out, per every prior session's convention).
3. Tab 6's still-open validation gap from the section below (no headless-probe coverage for `summary_app.R`, no live-data correctness check against real `cache/rapm_ratings.rds`) remains open and is now slightly larger in scope (one more interactive control to cover).
4. The stale issue tracker (`#43`/`#44`/`#49` still shown `OPEN` as of this session's `gh issue list --state open` — re-confirmed, unchanged from every prior session's flag) is still unreconciled.

---

# Handoff — 2026-10-07 (New thread: implemented Tab 6 "Player Ratings (RAPM)" end to end — SA-6a/SA-6b/SA-6c, issues #66/#67/#68 — via the `/subagent-brief` workflow, 3 isolated-worktree subagents, 1 manual merge-conflict resolution, all merged to `main` and pushed as of commit `b36c1af`) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail)

**This supersedes the section immediately below as the "current state," but everything in that section not explicitly updated here (the renv/library notes, the reusable-workflow list, the "Issue tracker state" discrepancy) is still accurate and still applies** — this thread only touched `summary_app.R`, `docs/HANDOFF.md`, and GitHub issues #66/#67/#68; `docs/SUMMARY_APP_SPEC.md` (already committed in `7e1bc29`, the commit immediately before this thread started) was read but not modified. This thread's user asked, in sequence: (1) use `/subagent-brief` to dispatch the three already-filed SA-6x tickets, (2) (after all three landed) "commit and push," (3) this handoff update.

## What this thread did

1. **Dispatched SA-6a (#66) as a single Tier-0/1 `full.md` brief** (`.subagent-runs/20261006-232312-c333cd`) in an isolated git worktree. The subagent added the cache loads, the fail-safe `rapm_join_utils.R` source block, and the Tab 6 UI/reactives/table described in the "Concrete next step" of the section below. **Coordinator independently re-verified every criterion** (re-ran the grep checks and the `parse(file=...)` check in the worktree myself, not just trusting the subagent's report) before committing (`82c1ca6`) and fast-forward-merging into `main`.
2. **Dispatched SA-6b (#67) and SA-6c (#68) in parallel**, each its own `full.md` brief (`20261006-233020-f2cc16`, `20261006-233033-0e72fd`) in its own worktree branched from post-SA-6a `main`. Both only depend on #66 (not on each other), per the dependency graph in `docs/SUMMARY_APP_SPEC.md`. **Both independently re-verified** the same way as SA-6a (re-read the actual diff, cross-checked SA-6c's methodology text line-by-line against `rapm_join_utils.R`'s real collision-resolution code rather than trusting the subagent's paraphrase).
3. **SA-6c (#68) merged clean** (fast-forward, commit `1b66152`) since its worktree had picked up SA-6a before starting.
4. **SA-6b (#67) hit a real merge conflict**: its worktree branched from `main` *before* SA-6c merged, so both branches independently inserted new UI content (a chart card vs. an accordion) immediately after the same leaderboard-table line in `summary_app.R`. Per the `subagent-brief` skill's hard rule ("no automatic conflict resolution — escalate"), the coordinator ran `git merge --abort` on the first conflicting attempt, recorded the run as `merge_conflict` (not silently as `merged`), kept the worktree, and reported the exact conflict (file:line, both sides' content) to the user rather than guessing at a resolution. **The user then explicitly specified the resolution** ("table -> chart -> accordion"), which the coordinator applied by hand (re-running `git merge --no-commit`, editing the two conflict-marker blocks to that order, re-running the `parse(file=...)` check, then committing the merge as `b36c1af`).
5. **Closed all three issues via `gh issue close N -c "..."`** referencing the merge commit — **not** via a `Closes #N` commit-message trailer (the convention the prior session's "Concrete next step" described). Both achieve the same end state (issue closed, linked to the work), but if this repo's convention is specifically "trailer auto-closes," note the divergence; nothing currently enforces one over the other.
6. **Committed and pushed to `origin/main`** on explicit user request ("commit and push") — `7e1bc29..b36c1af`, 4 commits. The pre-existing uncommitted cache churn (next section) was deliberately left out of the push, same as every prior session.

## Issue tracker state — re-confirmed this session

`gh issue list --state all --limit 30` this session: `#66`/`#67`/`#68` are now **CLOSED** (closed by this thread, timestamps `23:28`–`00:16` on 2026-10-06/07). `#43`, `#44`, `#49` are **still OPEN** — same pre-existing staleness flagged by the last two sessions, still not reconciled (out of scope for this thread; #49's underlying work was merged via `e5c97f3` per the section below, but nobody has closed the issue itself).

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `summary_app.R` | Modified, committed (`82c1ca6`, `1b66152`, `2e8048d`+`b36c1af`) | Grew from 1,527 → 1,869 lines. Tab 6 "Player Ratings (RAPM)" is now real: `RAPM_RATINGS_CACHE_PATH`/`ACTIVE_ROSTERS_CACHE_PATH` fail-safe loads (~line 362), fail-safe `rapm_join_utils.R` source block (~line 345), `nav_panel("Player Ratings (RAPM)", ...)` with team filter → `reactableOutput("rapm_table")` → `plotOutput("rapm_top_bottom_plot")` → collapsed `accordion()` (that exact order, ~line 544–599), server reactives `r_rapm_joined()` (single `join_rapm_to_roster(..., matched_only = TRUE)` call, ~line 1659) → `r_rapm_filtered()` (team filter, ~line 1678) → `output$rapm_table` (`renderReactable`, ~line 1724) and `output$rapm_top_bottom_plot` (`renderPlot`, ~line 1814, reuses `r_rapm_filtered()`, no second join/filter). **Line numbers will drift — re-grep by symbol name (`r_rapm_joined`, `rapm_top_bottom_plot`, etc.), don't trust these as permanent.**
| `rapm_join_utils.R` | **Untouched**, as planned | `join_rapm_to_roster()` called, not reimplemented, per `CLAUDE.md`. |
| `docs/SUMMARY_APP_SPEC.md`, `config.R` | **Untouched** | Spec was read for ticket detail; `WNBA_TEAMS` was read for the team-filter dropdown, neither modified. |
| GitHub issues `#66`, `#67`, `#68` | **Closed** | See "What this thread did" above for how; `docs/SUMMARY_APP_SPEC.md`'s SA-6a/b/c sections are still the spec of record. |
| `.subagent-runs/` (3 run directories) | New, gitignored | Full brief/result/evidence for each of the 3 dispatches — read `20261006-233020-f2cc16`'s `meta.json`/`result.json` first if you need the merge-conflict details beyond what's summarized here. |

## Validation actually performed this session — and what wasn't

- **Every subagent's `parse(file = "summary_app.R")` check was independently re-run by the coordinator** in the relevant worktree after the subagent reported success, not just trusted — this was true for all three dispatches.
- **After the final merge (`b36c1af`), the coordinator also ran `Rscript.exe summary_app.R` for real** (not just `parse()`) from the main checkout, which has a populated `renv` library (unlike the throwaway worktrees — see next section). It ran for the full 20-second timeout with **zero error output** before being killed, consistent with a Shiny server actually starting and serving (shiny's `print.shiny.appobj` blocks on `runApp()`), which is as close to "launches cleanly" as a non-interactive terminal check gets.
- **Not done this session**: a real headless browser click-through of Tab 6 specifically (the kind `headless_dashboard_probe.R` does for `app.R`'s tabs). There is no equivalent probe script for `summary_app.R` in this repo as of this session. If a UI regression in Tab 6 (e.g. the chart not re-rendering on team-filter change, badge styling not actually visible) is suspected, that's the first gap to close — either extend `headless_dashboard_probe.R`'s pattern to `summary_app.R` or do a manual browser check.
- **Not exercised**: real data correctness (e.g. does the leaderboard actually show sensible RAPM numbers, does the chart's 10/20-row fallback threshold actually trigger for a small-roster team filter). All three subagents' worktrees had an **empty `renv` library** (see below) and could only verify structurally (grep + parse), never by running the join/table/chart against real cache data. The coordinator's own `Rscript.exe summary_app.R` smoke-test (above) didn't inspect *rendered output*, just absence of startup errors.

## Environment/tooling notes (new this session)

- **Git worktrees created via the Agent tool's `isolation: "worktree"` do *not* inherit a populated `renv` library.** `renv/library/` is gitignored, so a fresh worktree gets `renv/library/windows/R-4.5/x86_64-w64-mingw32/` with either nothing or (per one subagent's report) ~0 real packages — `library(dplyr)` etc. fail there even though the main checkout (after commit `9894265`, see below) has every package installed. **Practical effect**: any subagent brief dispatched into an isolated worktree can only validate via `parse(file = ...)` (syntax only), never via `source()`/actual execution — build this limitation into the brief's success-criteria wording up front (as this session's three briefs did) rather than discovering it mid-run. If a future task genuinely needs live execution inside a worktree, the fix is almost certainly `renv::restore()` inside that worktree first (expect it to be slow — see the prior session's notes on this being a multi-step, failure-prone process on this machine) — not yet attempted from inside a worktree.
- **`Rscript.exe <file>.R` run non-interactively still executes a trailing bare `shinyApp(ui, server)` call** (it's the file's last top-level expression, and Shiny's `print.shiny.appobj` method launches the server on auto-print) — this blocks forever. Use a wall-clock `timeout <seconds> Rscript.exe ...` wrapper (as this session did, 20s) to smoke-test "does it error before serving" without hanging the session; absence of a timeout-kill exit code (124 on this environment) paired with empty stderr is the signal of a clean, blocking start, not literal silence/failure.
- **The `subagent-brief` skill's JSON result files are real JSON, not R-source-style strings** — a Windows path like `C:\Users\...\worktrees\...` written directly into a `"worktree"` field with single backslashes is **invalid JSON** (`\U`, `\k`, etc. aren't valid escapes) and makes `runlog.R record-result` fail with the unhelpful "No parseable JSON object found in output." error, independent of the result's actual correctness. Always write Windows paths into these result JSON files with forward slashes (`C:/Users/...`) or doubled backslashes — verified the hard way this session on the first `record-result` attempt for SA-6c.
- **The project-level skill path is `.claude/skills/subagent-brief`, but this skill is actually installed at the *user* level, `C:\Users\kailo\.claude\skills\subagent-brief`** (not under this repo at all). Running `Rscript.exe .claude/skills/subagent-brief/scripts/runlog.R ...` from the project root segfaults instantly with no error message (not a parse/logic error — a true SIGSEGV, exit 139) because the file doesn't exist at that path; the correct invocation is the absolute user-level path. This cost one full debugging round-trip this session (initially looked like the known "inline multi-line `-e` segfaults" issue from `CLAUDE.md`, but it wasn't — it was a wrong path to a script *file* argument, which should normally just error "file not found," not segfault).
- Every `Rscript.exe` invocation in the main checkout now prints a ~10-15 second `NOTE: Dependency discovery took N seconds during snapshot...` renv message to stdout *before* any real output — harmless, but don't mistake it for an error, and don't let it make you think a command hung (it resolves and the real output follows after a blank line).

## The reusable workflow this session added

1. **For a GitHub-issue-tracker-sourced multi-ticket slice with a known dependency graph** (here: #67/#68 both depend on #66, not on each other): dispatch the hard-dependency ticket first as a single run, verify + merge it for real (don't just trust the subagent report — re-run at least one grep/parse check yourself against the actual merged `main`), *then* dispatch the independent downstream tickets in parallel from post-merge `main`. This is faster than fully serial dispatch but still risks the exact UI-insertion-point conflict this session hit if two downstream tickets both touch "the end of the same panel" — when briefing two such tickets, consider either sequencing them anyway or explicitly stating the final relative order in both briefs up front (this session's briefs didn't, which is *why* the conflict happened; worth fixing in the template next time).
2. **On a Tier-1 (file-writing) subagent dispatch, the worktree-returned branch has *uncommitted* changes, not a commit** — the subagent edits files but does not commit (nothing in the brief asked it to). The coordinator must `git add` + `git commit` *inside the worktree* before any `git merge`/`git merge --ff-only` from the main checkout will see anything to merge; a `git diff main worktree-branch --stat` showing empty output right after a subagent reports success is this, not a sign the subagent did nothing — check `git status` inside the worktree itself first.
3. **On a real merge conflict from a subagent's worktree branch**: never resolve by re-running the subagent or re-generating its diff — the fix is almost always structural/cosmetic (ordering, adjacent-but-not-overlapping insertions), so `git merge --no-commit --no-ff <branch>`, read the actual conflict markers, decide (or escalate to the user for) the resolution, hand-edit, re-run whatever syntax/test check the brief specified, then commit the merge normally. Record the run's status as `merge_conflict` (not `merged`) until the human-confirmed resolution actually lands, and only then update it to `merged`.

## Concrete next step

Tab 6 (SA-6a/b/c) is now fully implemented, merged, and pushed — there is no open ticket in this slice. Two candidate next steps, pick based on priority:
1. **Close the validation gap flagged above**: either extend `tools/headless_dashboard_probe.R`'s click-through pattern to cover `summary_app.R`'s 6 tabs (it currently only drives `app.R`), or do a one-off manual browser check of Tab 6 specifically — team filter actually narrowing both the table and the chart, badge styling actually visible for any `low_sample_flag`/`rapm_ambiguous` rows in the real `cache/rapm_ratings.rds` data, chart's <20-row fallback actually triggering for a small-roster team.
2. **Reconcile the stale issue tracker** (`#43`, `#44`, `#49` shown open despite `#49`'s work being merged) — flagged by three consecutive sessions now without anyone actually closing them; this is a quick `gh issue close` pass once a human confirms `#43`/`#44` (the control-panel-app and auth-system issues) are genuinely still open work and not also already done.

---

# Handoff — 2026-10-06 (New thread: spec interview for a 6th `summary_app.R` tab — "Player Ratings (RAPM)" — spec written into `docs/SUMMARY_APP_SPEC.md`, 3 GitHub issues filed (#66/#67/#68), nothing implemented yet) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail — e.g. the spec-writing workflow, the `/spec-interview` answers)

**This is purely additive to the section immediately below** — no code from the renv/lockfile thread was touched, and this thread's own cache-file churn (see "Pre-existing uncommitted changes" below) predates this session and is unrelated to it. This thread's user asked three things in sequence: (1) "What could be a valuable 6th tab in the summary_app?" (open-ended, answered directly, not implemented), (2) run `/spec-interview` on the chosen idea ("player ratings tab"), (3) "Save spec. Write multiple issue tickets to accomplish this work."

## What this thread did

1. **Answered the open-ended "what's a valuable 6th tab" question** by reading `summary_app.R`'s existing 5 tabs (Season Standings & Projections, Playoff Bracket, Model Calibration & Reliability, Model Comparison, Prediction Accuracy Tracker — all team-level) and `rapm_join_utils.R`, and recommending a **Player Ratings (RAPM)** leaderboard as the one genuinely new angle missing (everything else is team-level), since it needs zero new modeling — just `cache/rapm_ratings.rds` joined to `cache/active_rosters_cache.rds` via the already-proven `join_rapm_to_roster()` helper. Flagged a **Market Odds / Model Edge** tab as a runner-up idea, not pursued (it would need live API calls, cutting against this app's static-snapshot design).
2. **Ran a 9-question Y/N spec interview** (`/spec-interview`) on the Player Ratings tab, resolving: league-wide table with a team filter (not team-grouped) → full RAPM breakdown columns (not just total) → unmatched roster players excluded entirely (`matched_only = TRUE`, the helper's default) → add a chart, not table-only → diverging top-10/bottom-10 chart (not top-N-only) → team filter drives the chart too, not just the table → low-sample/ambiguous rows get visible badge styling, not plain boolean columns → table gets a team-logo column (`team_logo_img_tag()`, same helper as Tab 1) → add a collapsed-by-default methodology accordion (mirroring Tab 1's Net Rating explainer).
3. **Wrote the compiled spec into `docs/SUMMARY_APP_SPEC.md`**: a new "### 6. Player Ratings (RAPM)" subsection under `## Tabs`, two new rows in the "Data sources referenced" table (`cache/rapm_ratings.rds`, `cache/active_rosters_cache.rds`), three new rows in the ticket table (SA-6a/SA-6b/SA-6c), three new detailed ticket sections (mirroring the existing SA-1..SA-5 format), and an updated `## Status` line correcting a pre-existing staleness in that file (it still said "Spec only. Not yet implemented" for SA-1 through SA-5, which have actually been closed and merged since 2026-10-04 — see issues #55-#59, #60-#65).
4. **Filed 3 new GitHub issues** (not 1 — the tab was split into vertical slices, same "max one tab per ticket" convention as SA-1..SA-5, but a single tab is 3 slices here): `#66` (SA-6a: cache load + join wiring + leaderboard table — the only hard dependency for the other two), `#67` (SA-6b: top/bottom RAPM chart, depends on #66), `#68` (SA-6c: methodology accordion, depends on #66).

## Issue tracker state — ⚠️ pre-existing discrepancy, re-confirmed not reconciled this session

`gh issue list --state all --limit 30` this session shows `#43`, `#44`, `#49` still **OPEN** — this is the same staleness the prior 2 sessions below already flagged and left alone (issue #49's work was actually merged via `e5c97f3` per the section below, but the issue itself was never closed). This thread did not touch the tracker beyond filing the 3 new issues above; `#43`/`#44`/`#49` remain exactly as stale as the prior session described.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `docs/SUMMARY_APP_SPEC.md` | Modified, **not yet committed** | New Tab 6 subsection, 2 new data-source-table rows, 3 new ticket-table rows, 3 new detailed ticket sections (SA-6a/b/c), corrected `## Status` line. |
| `summary_app.R` | **Untouched** | Still exactly 5 tabs, 1,527 lines, as of this session — no Tab 6 code exists yet. |
| `rapm_join_utils.R` | **Untouched** | 149 lines, already proven/shared by `market_odds_engine.R`/`player_props_engine.R`/`roster_bottom_up_engine.R` — SA-6a's plan is to reuse `join_rapm_to_roster()` as-is, not modify it. |
| GitHub issues `#66`, `#67`, `#68` | New, open | See ticket detail in `docs/SUMMARY_APP_SPEC.md`'s SA-6a/b/c sections — the issue bodies summarize the same spec but the doc is the source of truth if they ever drift. |

## Pre-existing uncommitted changes — not from this session, flagging not fixing

`git status` at both the start and end of this session also shows `cache/prediction_accuracy_log.csv`, `cache/prediction_accuracy_log.rds`, and `data/box_scores_cache.rds` as modified-but-unstaged. These predate this thread (present in the very first `git status` this session saw) and are almost certainly scheduled-pipeline cache churn, not anything this thread touched — left alone, same as this session left `docs/SUMMARY_APP_SPEC.md`'s own edit uncommitted (no commit was requested this session).

## Environment/tooling notes (new this session)

None — this was a pure spec/doc/tracker session, no R code run, no new tooling exercised.

## The reusable workflow this session added

1. For an open-ended "what should tab N be" question on this app: read every existing tab's data source in `summary_app.R` first (grep the `*_CACHE_PATH`/`*_data` load blocks), then check which *categories* of existing cache/helper infrastructure (e.g. `rapm_join_utils.R`) are unused by any tab yet — that's the fastest way to find an idea that needs zero new pipeline/modeling work.
2. When `/spec-interview` produces a single-tab spec that still has 3+ independently-buildable pieces (cache+table, chart, explainer), split it into that many GitHub issues with explicit `Depends on` links, rather than one issue — matches this repo's existing SA-1..SA-5 "max one tab per ticket" convention one level deeper.
3. Before writing a new ticket's body text, re-derive the columns/behavior from the actual helper's doc comment (`rapm_join_utils.R`'s own header comment, in this case) rather than from memory of the interview answers alone — the helper's comment is more precise about exact column names (`orapm`, `drapm`, `n_off_poss`, `n_def_poss`, `low_sample_flag`, `rapm_ambiguous`) than the interview's own phrasing was.

## Concrete next step

Pick up **SA-6a** (issue `#66`) — the hard prerequisite for `#67`/`#68`. Concretely, in `summary_app.R`:
1. Add `library(dplyr)` and `library(stringr)` near the top (alongside the existing `library(shiny)`/`library(bslib)`/etc. block) — required because `join_rapm_to_roster()` in `rapm_join_utils.R` calls unqualified `mutate()`/`word()`, so it needs both packages *attached*, not just available.
2. Source `rapm_join_utils.R` the same fail-safe way `config.R` is already sourced (see the existing `.config_constants <- tryCatch({ ... source("config.R", ...) ... }, error = function(e) NULL)` block) — do not reimplement the join inline, per `CLAUDE.md`.
3. Add two new startup-only cache loads (`cache/rapm_ratings.rds`, `cache/active_rosters_cache.rds`) using the exact same `file.exists()` + `tryCatch` + `*_load_error` pattern every other tab in this file already uses (see `STANDINGS_CACHE_PATH`'s load block as the template).
4. Add a 6th `nav_panel("Player Ratings (RAPM)", ...)` inside the existing `navset_tab(...)` in the `ui` object, with a team-filter `selectInput`/`selectizeInput` and a `reactableOutput`.
5. In `server()`, build a reactive that calls `join_rapm_to_roster(roster_data, rapm_data, matched_only = TRUE)` once, then a second reactive that applies the team filter on top of it; render the table off the filtered reactive with `team_logo_img_tag()` for the Logo column and visible badge/highlight styling for `low_sample_flag`/`rapm_ambiguous` rows (reuse the existing colored-cell pattern from `net_rating_cell()` in Tab 1 as a shape reference, don't copy its exact diverging-bar logic since this is boolean flags, not a numeric diverge).
6. Validate with `Rscript.exe summary_app.R` (full path, per `CLAUDE.md` — R is not on this machine's `PATH`) and, once the headless probe or a manual browser check confirms Tab 6 renders with no console errors, close `#66` with a `Closes #66` commit trailer.

After SA-6a lands, SA-6b (#67, the chart) and SA-6c (#68, the accordion) can be built in either order — both only depend on #66's reactive data/filter existing, not on each other.

---

# Handoff — 2026-10-06 (New thread: repopulated the almost-entirely-empty `renv` project library, fixed the stale/incomplete `renv.lock`, committed and pushed — commit `9894265` is `HEAD`) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail — e.g. "Bugs found," "Environment/tooling notes," "The reusable workflow")

**This directly resolves "Concrete next step" item 3 of the section immediately below** ("Reconcile the `renv` lockfile") — everything else in that section, and everything below it, is still accurate and unchanged. This thread was a single user-flagged observation ("renv lockfile is missing several packages actually needed to source() these files standalone") followed by "Run it" once a plan was proposed. No application code was touched — `renv.lock` is the only file changed.

## What this thread did

1. **Confirmed the originally-reported gap first**: grepped every `.R` file for `library(...)`/`pkg::` usage and diffed against `renv.lock`'s `Packages` list. `shinyjs` is used directly in `control_panel_app.R` (`library(shinyjs)` plus `shinyjs::disable()`/`enable()`/`html()` calls at lines 644, 646, 732, 741, 776, 786, 801, 802) but had **no top-level lockfile entry** — it only appeared incidentally inside another package's `"Config/Needs/check"` field. (`hoopR`, by contrast, only appears in comments/docs across this repo — not a real gap, left alone.)
2. **Discovered the gap was much bigger than one missing package while attempting the fix**: `renv/library/windows/R-4.5/x86_64-w64-mingw32/` contained ~211 package-name directories, but every single one (apart from `renv` itself) was an **empty shell with no `DESCRIPTION` file** — i.e. nothing was actually installed. The global renv cache (`%LOCALAPPDATA%/R/cache/R/renv/cache/v5/...`) was likewise empty at the start. `renv::snapshot()` failed outright on first attempt ("required packages are not installed") rather than just omitting `shinyjs`.
3. **Repopulated the library and then snapshotted**, in this order (see "Environment/tooling notes" below for why each step was needed):
   - `renv::restore(prompt = FALSE)` — downloaded all ~190 packages into the global cache successfully every time, but kept dying partway through the **install** step, killed each time by an external low-memory condition on this machine (not caused by the restore job itself — see below). Because `renv`'s default install is **transactional** (all evicted and restarted from zero on any interruption), the first 2 attempts made *zero* persisted progress despite completing the download step both times.
   - Set `Sys.setenv(RENV_CONFIG_INSTALL_TRANSACTIONAL = "FALSE")` + `options(Ncpus = 1)` so partial installs actually persist across retries — after that, each kill preserved real progress (98 → 117 → 133 packages installed across successive retries).
   - Hit a second, unrelated problem once most packages were in: `renv::restore()`/`renv::install()` (even called as plain `install.packages()`, since this project's `.Rprofile` shims `install.packages()` to route through `renv::install()`) threw `Error in vapply(downloadable, [[, character(1L), "url") : values must be length 1, but FUN(X[[9]]) result is length 0` — a real bug inside `renv`'s own dependency-graph resolver (`renv_graph_install`), reproducible and deterministic for the same cluster of packages (`curl`, `data.table`, `glmnet`, `lubridate`, `magrittr`, `processx`, `RcppArmadillo`, `stringi`, `systemfonts`, `xml2`, `diffobj`), not a transient/memory issue — confirmed by installing `curl` directly via `install.packages()` outside renv's shim, which worked immediately.
   - **Fix**: ran `Rscript.exe --no-init-file <script>.R` (the `--no-init-file` flag skips `.Rprofile`, so `renv`'s `install.packages()` shim never loads) calling base `utils::install.packages()` directly against the project library path, with `dependencies = NA` (not `TRUE` — see pitfall below). This installed all remaining packages cleanly in one pass.
   - Two packages (`fastshap` 0.1.1, `vip` 0.4.2 — both pinned in the lockfile) are **no longer on live CRAN at all**, archived upstream in 2026 ("issues were not corrected despite reminders"). Installed both from `https://cran.r-project.org/src/contrib/Archive/<pkg>/<pkg>_<version>.tar.gz` via `download.file()` + `install.packages(..., repos = NULL, type = "source")` — both built cleanly with the already-installed Rtools toolchain.
   - One version conflict surfaced only at `renv::snapshot()` time: `processx` (now `3.9.0`) requires `ps >= 1.9.3`, but `ps 1.9.1` had been installed as a dependency earlier in the sequence. Updated `ps` directly, then snapshot succeeded.
4. **Ran `renv::snapshot(prompt = FALSE)`** (this time with `.Rprofile` active, since snapshot itself isn't affected by the install-shim bug) and committed the result. `shinyjs` is now a real top-level lockfile entry (`2.1.1`). ~29 other packages moved from a stale pinned version to whatever's actually installed now (`curl` 7.0.0→8.0.0, `data.table`→1.18.6.1, `stringi`→1.8.9, `RcppArmadillo`→15.6.0-1, `xml2`→1.6.0, etc. — full list in commit `9894265`'s diff). A handful of pure-base-R packages (`boot`, `cluster`, `foreign`, `mgcv`, `nlme`, `spatial`) dropped their pinned version in favor of `renv`'s own `*` convention for packages that ship with R itself — this is `renv`'s normal behavior for base packages, not a regression.
5. **Committed and pushed** (`9894265`, pushed to `origin/main` immediately after, per explicit user instruction — "Commit and push"). Only `renv.lock` changed; all scratch files under `tools/tmp_*` were deleted before committing and never staged.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `renv.lock` | **125 insertions, 278 deletions** (net smaller — pinned-version metadata blocks for base packages shrank) | `shinyjs` added; ~29 packages' pinned versions updated to match what's actually installed. No application `.R` file touched. |
| `renv/library/windows/R-4.5/x86_64-w64-mingw32/` (not tracked by git, local machine state only) | Went from ~1 real package (`renv` itself) to 211 real, fully-installed packages | This is the actual fix — the lockfile diff alone doesn't capture that the library itself was reconstructed from near-nothing. A *different* machine restoring from this lockfile via a healthy `renv::restore()` should now succeed without hitting any of the bugs below, since the lockfile itself is now accurate — but see the `renv_graph_install` bug note below, which is a bug in `renv` itself, not specific to this machine's prior broken state, and could resurface on a future restore here or elsewhere. |

## Environment/tooling notes (new this session)

- **This machine killed 4 separate backgrounded `Rscript.exe` jobs mid-run, each reported as "stopped because the system is running low on memory."** Checked system memory directly (`Get-CimInstance Win32_OperatingSystem`): 16GB total, ~2.9GB free at the time, with several memory-heavy apps already open (multiple VS Code windows, multiple Chrome processes, RStudio + an active `rsession-utf8`, Windows Defender's `MsMpEng` at ~500MB). The renv restore/install step itself is not especially memory-hungry per package — the kills are plausibly this machine's general multi-app memory pressure tipping over a watchdog threshold, not a problem with the restore job. **If a future session hits the same "killed... low on memory" pattern on a long-running background job here, check free memory and open apps before assuming the job itself is the problem — and know that `renv`'s default transactional install means a kill normally loses ALL progress, not just the in-flight package, unless `RENV_CONFIG_INSTALL_TRANSACTIONAL=FALSE` is set first.**
- **`renv::install()` (and, transitively, this project's shimmed `install.packages()`) has a real, reproducible bug in its dependency-graph resolver** (`renv_graph_install` → `vapply(downloadable, \`[[\`, character(1L), "url")`) that throws when some package in the batch has zero resolvable download candidates (saw this consistently for the same ~11-package cluster across 2 separate attempts with different batch compositions, always erroring on a different numeric index into an internal list — i.e. not file/package-specific, a genuine resolver bug). **Workaround**: `Rscript.exe --no-init-file <script>.R` to skip sourcing `.Rprofile` (which is what activates `renv`'s shim via `source("renv/activate.R")`), then call `.libPaths(c(<project lib>, .libPaths()))` and `utils::install.packages(...)` directly. This bypasses `renv::install()`'s buggy graph resolver entirely while still installing into the correct project-local library path.
- **`install.packages(..., dependencies = TRUE)` is far too aggressive for this use** — it pulls in every `Suggests`/`Enhances` transitively, not just `Depends`/`Imports`/`LinkingTo`, and one attempt this session produced a ~300-package plan including completely unrelated packages (`tseries`, `vars`, `titanic`, `XML`, `V8`, `vdiffr`, ...). Use `dependencies = NA` (the R default — hard dependencies only) unless there's a specific reason to want Suggests too.
- **`fastshap` and `vip` were both archived off live CRAN in 2026** ("issues were not corrected despite reminders" — confirmed via CRAN's own package status pages) but both are still fetchable at their exact lockfile-pinned versions from `https://cran.r-project.org/src/contrib/Archive/<pkg>/<pkg>_<version>.tar.gz`, and both still build cleanly from source with this machine's Rtools (`C:\rtools45`). If a future `renv::restore()` fails specifically on these two packages, this is almost certainly why — don't assume a local environment problem before checking CRAN's archive page for the package.
- **A multi-line inline `Rscript.exe -e '...'` call segfaulted** when passed via this session's Bash tool (`for` loop + `download.file()` + `install.packages()`, several lines, piped through a POSIX shell to a Windows-native `Rscript.exe`) — consistent with `CLAUDE.md`'s existing warning about this exact pattern. Writing the same code to a temp `.R` file and invoking `Rscript.exe <path>.R` worked immediately with no changes to the R code itself. Nothing new here beyond what `CLAUDE.md` already says — just a fresh confirmation it's still true, caught the hard way once this session before remembering the existing rule.
- Confirmed via `gh issue list --state open` that the tracker is unchanged from the section below: `#43`, `#44`, `#49` are still open (the prior session's own already-flagged tracker staleness — #49 is actually done/merged, see the section below for why it wasn't closed). This session touched zero issues; not in scope for what was asked.

## The reusable workflow this session added

1. Before touching an `renv` project's library/lockfile on this machine, run a quick census first: grep every `.R` file for `library(...)`/`pkg::` usage, diff against `renv.lock`'s `Packages` list, *and* spot-check that at least a couple of already-"present" package directories actually contain a `DESCRIPTION` file (`for d in <lib>/*/; do [ -f "${d}DESCRIPTION" ] || basename "$d"; done`) before trusting that the lockfile gap is the only problem — an empty-shell library looks identical to a healthy one from `renv.lock` alone.
2. If `renv::restore()`/`renv::install()` needs multiple retries on this machine, set `Sys.setenv(RENV_CONFIG_INSTALL_TRANSACTIONAL = "FALSE")` first so retries are additive instead of all-or-nothing.
3. If `renv::install()` throws the `vapply(downloadable, ...)` error from `renv_graph_install`, don't keep retrying the same call — switch to `Rscript.exe --no-init-file` + direct `utils::install.packages()` for the remaining packages, then come back to a normal (`.Rprofile`-active) `Rscript.exe` session just for the final `renv::snapshot()`.
4. Always clean up `tools/tmp_*` scratch scripts/logs before the final commit — this session generated ~10 of them across the retry loop and none were left behind or staged.

## Concrete next step

The section below's own "Concrete next step" items 1, 2, 4, 5 (tracker hygiene, de-duplicating `.normalize_value_bets_dates()`, the last leftover worktree, `.gitignore` for `.claude/worktrees/`) are **all still open and untouched by this thread** — this thread only addressed that section's item 3. Beyond those:

1. If anyone restores this project's `renv` library on a *different* machine, watch for the `renv_graph_install` bug above resurfacing — it's a bug in `renv` itself (reproduced on this machine across 2 separate package-batch compositions), not something this session's fix guarantees won't happen elsewhere. The `--no-init-file` + direct `install.packages()` workaround above is the fastest path through it if it does.
2. Nobody has yet re-run `renv::restore()` from a **clean** checkout against the now-fixed `renv.lock` to confirm it restores cleanly end-to-end in one pass on a fresh library — this session only ever fixed *this machine's* already-populated-but-broken library incrementally, never validated a from-scratch restore against the final committed lockfile. Worth doing once, ideally in a disposable worktree, before trusting the lockfile is fully self-consistent.

---

# Handoff — 2026-10-05 (New thread: implemented issue #49 — Slice 5 — in two subagent-brief waves, pushed to `origin/main`, cleaned up 11 of 12 leftover `.claude/worktrees/` dirs — commit `e5c97f3` is `HEAD`) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail — e.g. "Bugs found," "Environment/tooling notes," "The reusable workflow")

**This supersedes the "#49 NOT STARTED" framing of the section immediately below** (same repo,
prior session — everything else in that section, and everything below it, is still accurate
unless noted otherwise here). This thread's user asked three things in sequence: (1) implement
issue #49 "in waves of parallel agents", (2) clean up the leftover `.claude/worktrees/` dirs
flagged as a 552MB open item in the section below + commit + push, (3) write this handoff.

## What this thread did

1. **Implemented issue #49** (Slice 5 of #43: "Extract shared render helpers + inline results in
   control panel") using the `subagent-brief` skill (`.claude/skills/subagent-brief`, global —
   not project-local), as two **sequential** waves, not parallel ones — the task is a single
   dependent refactor of two shared files (`app.R` then `control_panel_app.R`), and the brief's
   own hard rules (worktree isolation per writer, no automatic retries) make faking concurrency
   on shared-file edits a net loss (guaranteed merge conflicts) rather than a speedup. See
   "The reusable workflow" below for the exact mechanics, including a real gotcha hit twice.
   - **Wave 1** (commit `a063415`, merged via `b9df1a7`): extracted the plot/table-*building*
     logic (not the `input$`-dependent data-fetching) out of 15 `renderPlot`/`renderPlotly`/
     `renderDT` blocks in `app.R`'s `server()` into a new file, `dashboard_render_helpers.R`, as
     15 plain `build_*()` functions with zero `input$`/`session$` reference (so a different Shiny
     app can call them later — see Wave 2). Verified via two full runs of
     `tools/headless_dashboard_probe.R --screenshot`, once against the original `app.R` and once
     against the refactored one: identical per-tab results, 0 new console errors, screenshots
     pixel-identical across all 10 affected tabs.
   - **Wave 2** (commit `a39cf1a`, merged via `e5c97f3`): wired `control_panel_app.R` to call
     those same `build_*()` helpers after a pipeline stage finishes, so the control panel shows a
     real chart/table preview of the cache file the stage just wrote, **next to** (not replacing)
     the existing raw log dump. New `STAGE_PREVIEW_MAP` + `render_stage_preview(stage_id)`
     (`control_panel_app.R:343-401`) cross-check `pipeline_stages.R`'s `PIPELINE_STAGES[[id]]
     $output` field before reading the `.rds` and calling the matching helper, wrapped in
     `tryCatch()` that falls back to "no extra preview" (never an error) on any missing
     mapping/file/schema mismatch. Verified for 2 of the 5 mapped stages
     (`roster_bottom_up_engine` → `cache/projected_wnba_standings.rds`, `market_odds_engine` →
     `cache/latest_value_bets.rds`) by comparing the preview's rendered row count/columns against
     calling the same `build_*()` helper directly on the same cache file — exact match both
     times. The other 3 mapped stages (`injury_scraper`, `player_props_engine`, `pbp_engine`)
     were wired the same way but not individually re-verified this session.
2. **Cleaned up `.claude/worktrees/`**: 12 leftover worktrees existed from unrelated prior
   sessions/agents, all already fully merged into `main` (confirmed via `git merge-base
   --is-ancestor <worktree HEAD> main` on each, before removing anything). Removed 11 via
   `git worktree remove -f -f` + `git branch -D`; the 12th
   (`.claude/worktrees/agent-ae227d715064d6d37`) is still held by an OS-level file lock from a
   still-running process (`rm` fails with "Device or resource busy") — **left in place**, not
   force-deleted, since the owning process wasn't this session's to kill. Directory size dropped
   from 552MB to 20KB. Still not in `.gitignore` (see "Concrete next step").
3. **Pushed `origin/main`** (`fd40802..e5c97f3`, 4 commits: the two feature commits above plus
   their two merge commits). Nothing else was pending to commit — working tree was already clean
   going into this thread.

## Issue tracker state — ⚠️ discrepancy, not reconciled this session

`gh issue list --state open` still shows **#49, #44, #43 all OPEN** as of this session. #49's
code is done, merged, and pushed (see above) — the tracker is now stale on this point, same
pattern the section below already warned about once. **This was deliberately not fixed this
session**: closing issues is a visible, semi-reversible action outside what the user asked for
this thread (implement #49, clean worktrees, commit/push, write this doc — closing tickets
wasn't one of the three). Whoever picks this up next should close #49 (citing commit `e5c97f3`),
then #43 and #44 (both were open only pending #49) — don't take my word for "done," re-check
`git log` / the commits above first, per this doc's own stated principle.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `dashboard_render_helpers.R` | **New**, 643 lines | 15 `build_*()` functions, one per extracted render output (full list: `build_tbl_daily_edges`, `build_tbl_steam_radar`, `build_tbl_injuries`, `build_plot_bankroll_drawdown`, `build_tbl_graded_ledger`, `build_plot_embeddings_pca`, `build_plot_embeddings_heatmap`, `build_plot_calibration_curve`, `build_tbl_bottom_up_standings`, `build_plot_residual_scatter`, `build_plot_residual_dist`, `build_plot_team_bias`, `build_tbl_props_terminal`, `build_plot_prop_zinb_curve`, `build_tbl_clutch_shot_profile`) plus a shared `.diag_empty_plot()` helper. None reference `input$`/`session$` — grep-verified. Sourced from `app.R:100`. |
| `app.R` | 1,213 lines (was ~1,723 before this session, −510 net incl. the new `source()` line) | Each of the 15 outputs above now just calls its `build_*()` helper with explicit data args; `input$`-dependent filtering (e.g. `input$clutch_show_low_volume`, row-selection on `tbl_props_terminal`) stays inline in `app.R` and is passed into the helper call. |
| `control_panel_app.R` | 886 lines (was ~724 before this session, +162) | New `STAGE_PREVIEW_MAP` (5 entries) + `render_stage_preview()` (`:343-401`), a new `uiOutput("stage_preview")` near the existing `verbatimTextOutput("output_log")` (`:567`), and `output$stage_preview <- renderUI(...)` wired into the existing `observeEvent(rv$results, ...)` block (`:865-871`). Also adds a locally-scoped `.normalize_value_bets_dates()` (`:315-341`) — see "known residual risk" immediately below, this is a deliberate duplicate, not an oversight. |

Every other file in the repo is unchanged this session.

## Known residual risk — flagged, not fixed, candidate for a future slice

`control_panel_app.R`'s `.normalize_value_bets_dates()` (`:315-341`) is a **documented
byte-for-byte duplicate** of `app.R`'s `r_normalized_value_bets()` reactive (`app.R:591-622`) —
the logic that derives a `norm_date` column on `cache/latest_value_bets.rds`'s raw contents
(including a staggered-placeholder-date fallback for thin/demo slates where the real
`game_date` column isn't yet distinct across rows). `build_tbl_daily_edges()` requires
`norm_date` to exist; the raw cache file doesn't have it; `app.R` only ever calls the helper
*after* its reactive derives it. This couldn't be shared in Wave 2 because (a) `app.R` was
explicitly out of scope for that brief, and (b) the original is a Shiny `reactive()`, which
can't be called from outside a reactive context anyway. This repo has been bitten by exactly
this shape of bug before (see the `CONN`/`CON` team-abbreviation note and the RAPM/roster-join
note in `CLAUDE.md`) — two copies of non-trivial logic that can silently drift. **Recommended
next slice**: hoist this into a plain function in `dashboard_render_helpers.R` (it has no
`input$`/`session$` dependency either, so it fits that file's existing contract) and have both
`app.R` and `control_panel_app.R` call it from there.

## Environment/tooling notes (new this session)

- **The `subagent-brief` skill's `Agent` tool `isolation: "worktree"` parameter branches new
  worktrees from a *stale snapshot* of `main` taken at session start, not from `main`'s live tip
  at dispatch time, at least within a single long-running session that itself advances `main` via
  merges partway through.** Hit this twice dispatching Wave 2: two separate `isolation:
  "worktree"` dispatches both landed on commit `fd40802` (3 commits behind the `main` tip at
  actual dispatch time, `b9df1a7`), so `dashboard_render_helpers.R` (which Wave 2's brief
  required as a precondition) was missing both times, and both subagents correctly stopped with
  `status: blocked` rather than guessing — the briefs' explicit "confirm the precondition first,
  stop if missing" instruction did its job. **Workaround that worked**: create the worktree
  manually (`git worktree add -b <branch> <path> main`) instead of using the `isolation`
  parameter, copy the brief file into it by hand (it lives under the gitignored
  `.subagent-runs/`, which a tool-created worktree also won't contain — see next bullet), and
  dispatch a plain (non-`isolation`) agent instructed to `cd` into that exact path for every
  command. If this recurs, suspect the same stale-base cause before suspecting the brief itself.
- **`.subagent-runs/` (the `subagent-brief` skill's run log) is gitignored by design** (the
  skill's own `init` command adds the `.gitignore` entry) — which also means any
  `isolation: "worktree"`-created worktree won't contain it, since worktree creation only copies
  tracked content. Any brief file a subagent needs to read must be placed into that specific
  worktree manually if you're not using the `isolation` parameter's own (also-apparently-stale)
  worktree.
- `runlog.R record-result` rejected a hand-written result JSON that put free-text evidence
  directly on each criterion (`{"id":1,"met":"yes","evidence":"..."}`) — the actual
  `schema/result.v1.json` requires top-level `item_id`/`summary`/`evidence`/`blocked_reason`/
  `needed_action`/`changes` keys too, and each criterion needs `text` + `evidence_refs` (an array
  of IDs) pointing into the top-level `evidence` array, not an inline `evidence` string. Read
  `schema/result.v1.json` directly rather than inferring the shape from the template's prose.
- `runlog.R record-result --result <path>` **failed silently with "No parseable JSON object
  found in output"** when `<path>` was a file under `/tmp/...` (a Git-Bash/MSYS path) passed to
  the Windows-native `Rscript.exe` — moving the same file under the repo's own `.subagent-runs/`
  directory (a plain Windows-relative path) fixed it immediately. Suspect Windows-native R not
  resolving MSYS `/tmp` mounts correctly; avoid `/tmp` for any file a Windows `Rscript.exe`
  invocation needs to read.
- `.claude/worktrees/` is now 20KB (was 552MB per the section below) — see "What this thread did"
  item 2. Still not in `.gitignore`; `git status` doesn't flag it as untracked either (worth
  figuring out why on a future session — possibly a global excludesfile — before assuming
  it's git-clean by default).
- Working tree is clean as of `HEAD` (`e5c97f3`), already pushed to `origin/main`.

## The reusable workflow this session added (on top of the prior sessions' lists below)

1. For a refactor that touches two files with a real dependency order (extract-then-consume,
   like Wave 1 → Wave 2 here), **don't force artificial parallelism** — run it as sequential
   `subagent-brief` waves, one subagent per wave, each in its own worktree, merged back to `main`
   before the next wave's brief is even written (the next brief needs to cite real post-merge
   line numbers/function names, which don't exist until the merge happens).
2. Before trusting a `subagent-brief` dispatch's `isolation: "worktree"` result, **independently
   re-run at least one cited check yourself** against the actual worktree path the tool result
   returns (e.g. `grep -c "^build_" dashboard_render_helpers.R`, `git diff --stat`) — this caught
   nothing wrong this session (both subagents' claims checked out), but the stale-worktree bug
   above means the tool-provided isolation can't be trusted blindly for *dispatch correctness*
   either, not just for the subagent's own claims.
3. When recording a subagent's final JSON into `runlog.R record-result` and it doesn't match
   `schema/result.v1.json` (common, since subagents often free-form the `evidence` field per the
   brief template's loose prose example), **don't fight the subagent for a re-run** — just
   reshape the same evidence into a schema-compliant JSON yourself from the subagent's reported
   text and record that; the schema is about the run log's bookkeeping, not about re-verifying
   the work a second time (you already did that per item 2 above).

## Concrete next step

1. **Tracker hygiene**: close #49 (cite `e5c97f3`), then #43 and #44 (both blocked only on #49).
   Not done this session — see "Issue tracker state" above for why.
2. **De-duplicate `.normalize_value_bets_dates()`** per "Known residual risk" above — hoist it
   into `dashboard_render_helpers.R` and have both `app.R` and `control_panel_app.R` call the
   shared version.
3. **Reconcile the `renv` lockfile**: both this session's subagents had to `renv::install()`
   several packages inside their worktrees just to get `source("app.R")` /
   `source("control_panel_app.R")` to run standalone — `duckdb`, `tidyverse`, `here`, `RSQLite`,
   `bcrypt`, `ranger` were all missing from the lockfile despite being actually required. This
   was never caught before because these files are normally only ever run inside a live Shiny
   session (`shiny::runApp()`), which must be picking up these packages from somewhere outside
   `renv`'s tracked library (global library? an untracked local install?) — worth a dedicated
   session to run `renv::snapshot()` and understand why the lockfile drifted, rather than
   re-discovering the same gaps piecemeal every time a fresh worktree sources these files.
4. Remove the last leftover worktree, `.claude/worktrees/agent-ae227d715064d6d37`, once whatever
   process is holding its lock (check `tasklist` for the PID the lock file names) exits — its
   branch is already deleted, just the directory remains.
5. Add `.claude/worktrees/` to `.gitignore` while addressing item 4 above's "why doesn't `git
   status` already flag this" question — they're likely the same root cause.

---

# Handoff — 2026-10-05 (New thread: pushed a 28-commit unpushed backlog to `origin/main`, closed out the tracker per the prior session's own instructions, then added dark-mode support to `summary_app.R`'s Tab 1 — commit `4b70058` is `HEAD`) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail — e.g. "Bugs found," "Environment/tooling notes," "The reusable workflow")

**This supersedes the issue-tracker-is-stale framing of the section immediately below** (same
day, earlier session — everything else in that section, and everything below it, is still
accurate). This thread did three unrelated things in sequence, triggered by three separate user
requests in one conversation: (1) pushed `main`, which turned out to be 28 commits ahead of
`origin/main` (every commit back through the entire control-panel/auth + D&T thread below had
only ever been committed locally, never pushed — `git push` had apparently not been run in any
prior session), (2) closed the 14 issues the prior session's handoff explicitly identified as
code-complete-but-tracker-stale, (3) a new, unrelated user request — "the projected-standings
table and plots look bad in dark mode" — answered by wiring real dark-mode support into
`summary_app.R`'s Tab 1 (and, for consistency, all 5 tabs' tables/plots), not tracked by any
GitHub issue.

## What this thread did

1. **Pushed `origin/main`** (`365b9e8..3bf8f50..4b70058`). If a future session sees `git status`
   report "ahead of origin by N commits" again, don't assume that's expected steady-state for
   this repo — check whether the previous session simply forgot to push before assuming
   anything else is wrong.
2. **Closed 14 of the 17 open control-panel/auth/D&T issues** (`gh issue close <N> -c "..."`,
   each comment citing the exact merge commit) **exactly per the prior session's own "Concrete
   next step" instruction** (see the section below, which said to do exactly this): #46, #47,
   #48, #50, #51, #52, #53, #54, #60, #61, #62, #63, #64, #65. Left #43, #44, #49 open, also per
   that same prior instruction — #43/#44 are epics that cover #49, which is still unstarted.
   **No code was written for this step** — pure tracker hygiene, verified against `git log`
   before each close, not against the stale table alone.
3. **Added dark-mode support to `summary_app.R`** (ad hoc user request, not from either issue
   tracker thread below). `input_dark_mode()` was already wired into the UI shell (visible in
   `summary_app.R` since an earlier session) but only ever toggled Bootstrap's own CSS
   variables — `reactable`'s inline-styled tables and every `ggplot`'s rendered-to-PNG output
   ignored the toggle completely and stayed a fixed white/light block regardless of mode. Fixed
   for all 5 tabs (not just the one the user pointed at), since the same two problems existed on
   every tab, not just Tab 1. See "What's actually implemented" below for the mechanism.

## Issue tracker state (current, verified via `gh issue list --state open` this session)

| # | Title | Code status |
|---|---|---|
| 43 | Add interactive control-panel app (epic) | **Open** — blocked on #49 |
| 44 | Add reusable multi-user auth system (epic) | **Open** — blocked on #49 |
| 49 | Slice 5: Extract shared render helpers | **Open, NOT STARTED** — see "Concrete next step" |
| 46, 47, 48, 50, 51, 52, 53, 54, 60, 61, 62, 63, 64, 65 | (titles in the table below this section) | **Closed** this session, all pre-existing merges from the prior session (see commit hashes in the table below) |

Only 3 issues remain open on the tracker now: #43, #44, #49 — all three for the same reason
(#49 unstarted, #43/#44 are its parent epics). This is a real reduction from "17 open, 14 of them
actually done" to "3 open, all genuinely unstarted work" — the tracker is no longer stale as of
this session.

## What's actually implemented (new/changed this session)

| File | Status | Notes |
|---|---|---|
| `summary_app.R` | 1,527 lines (was 1,419 before this session, +108) | New dark-mode plumbing: `r_dark_mode()` reactive (top of `server()`, reads `input$dark_mode_toggle == "dark"`) feeds every table/plot output. New top-level helpers (defined right after the `library()` block, before any UI/server code): `gg_line_ink()`, `gg_text_ink()`, `gg_muted_ink()` (color pickers for ggplot elements that are colored explicitly rather than through `theme()`), `gg_dark_overrides(dark)` (full axis/grid/title/background override, for every `theme_minimal()`-based plot), `gg_dark_overrides_void(dark)` (background-only override, for every `theme_void()`-based plot — see "Bugs found" below for why this had to be separate), `reactable_dark_theme(dark)` (a `reactable::reactableTheme()` for all 3 `reactable` tables). All 3 `reactable(...)` calls gained `theme = reactable_dark_theme(dark)`; the accuracy table's per-row outcome tint (`rowStyle`) also gained a dark-mode variant since its light-mode near-black text colors (`#0B4A3E`/`#7B241C`) were unreadable against a dark table background. All 6 `renderPlot({...})` calls gained `bg = "transparent"` and a `+ gg_dark_overrides(dark)` (or `_void` variant) appended to their final `theme()` chain. |

Every other file in this repo is unchanged this session — no other `.R` file was touched.

## Bugs found and fixed this session

1. **`gg_dark_overrides(dark)`'s `axis.text`/`axis.title` entries silently re-enabled the
   playoff bracket's hidden axes.** The bracket plot (and every "no data available" placeholder
   plot across all 5 tabs) uses `theme_void()`, which deliberately blanks all axis
   text/titles/grid. The first implementation pass appended the same `gg_dark_overrides(dark)`
   used by the `theme_minimal()` plots to these too — `theme_void() + theme(axis.text =
   element_text(...), ...)` re-enables exactly the elements `theme_void()` had just blanked,
   since later `theme()` calls override earlier ones element-by-element, not wholesale. This
   was **not** caught by `shiny::testServer()` or by the absence of
   `.shiny-output-error` — it's a purely visual regression, only visible in an actual rendered
   screenshot (confirmed live: the bracket plot grew numeric axis ticks/labels — `"6" "3" "y"
   "0" "-3"` down the left edge, `"0" "5" "10" "15" "x"` along the bottom — that don't belong on
   a bracket diagram at all). Fixed by splitting into `gg_dark_overrides_void()` (background-only,
   no axis entries) for every `theme_void()` call site. **This is exactly the kind of bug this
   session's "verify with a real screenshot, not just an error-class check" step exists to
   catch** — see "The reusable workflow" below, which is new this session and worth reading if
   touching any plot here again.

## Environment/tooling notes (new this session)

- **The prior session's note that `shinytest2::AppDriver` was "unusable system-wide" due to
  memory pressure did not reproduce this session** — `AppDriver` worked normally once a real
  Chrome process could launch cleanly. If it fails for you, check for orphaned background `R.exe`
  processes first (see next bullet) before assuming a repeat of the prior session's memory-
  pressure issue.
- **A failed/interrupted `AppDriver$new()` call can leave an orphaned background `R.exe` process
  running the Shiny app it was trying to connect to**, and these accumulate across repeated
  failed attempts (10 were found running simultaneously this session, from unrelated earlier
  probe attempts within the same session). Symptom: every subsequent `AppDriver$new()` call times
  out with `Chromote: timed out waiting for response to command Page.navigate`, even against a
  trivial app, with no indication the real cause is resource contention from prior orphans, not
  the new attempt. Fix: `tasklist //FI "IMAGENAME eq R.exe"` to check, `taskkill //F //IM R.exe`
  to clear them (safe only if no *legitimate* long-running R process is active — check the list
  first). This is a different failure mode from the prior session's memory-pressure one, with an
  easy local fix, not an unfixable environment constraint — don't conflate the two if you hit an
  `AppDriver` failure in a future session.
- **`shinytest2::AppDriver$new(app_dir = <path to a single .R file>)` does not work the way it
  looks like it should**, and fails in two different unhelpful ways depending on exactly how you
  get it wrong: `app_dir = "somefile.R"` → `Error: attempt to apply non-function` (unrelated to
  the real cause); pointing it at a directory containing an `app.R` written as a bare `source("real
  target.R")` (no return value capture) → `Error in func(fname, ...) : app.R did not return a
  shiny.appobj object.` The fix (used successfully this session, and already documented as the
  right pattern in the prior session's "Bugs found" item 3 below — worth re-confirming since it
  bears repeating): write a throwaway wrapper directory containing just an `app.R` that does
  `setwd("<absolute project root>"); source("real_target.R")$value` (the trailing `$value` is
  required — `source()` alone returns an invisible `list(value=, visible=)`, not the
  `shiny.appobj` itself), and point `app_dir` at that wrapper directory, not at the target file.
- **`AppDriver`'s screenshot method is `get_screenshot(file = ...)`, not `screenshot(...)`** —
  the latter doesn't exist on this version and fails with `Error: attempt to apply non-function`,
  easily confused with the wrapper-app-file mistake above since both produce the identical error
  text. Run `ls(shinytest2::AppDriver$public_methods)` once if unsure which method names this
  installed version actually exposes, rather than guessing from memory/other projects' usage.
- `.claude/worktrees/` is still untracked, still not in `.gitignore`, still 552MB across 11
  worktrees, exactly as the prior session flagged — unchanged this session, still an open item,
  see "Concrete next step" below.
- Working tree is clean as of `HEAD` (`4b70058`) except for the pre-existing, un-actioned
  `.claude/worktrees/` untracked directory noted above — `git status --short` shows nothing else.

## The reusable workflow this session added (on top of the prior session's list below)

1. After any `ggplot`/plot-related change, **take an actual headless-browser screenshot and look
   at it** before calling the change done — don't rely on `shiny::testServer()` or an absence of
   `.shiny-output-error` alone. Both of those are blind to purely visual regressions (see "Bugs
   found" above); a reactive-value assertion has no way to notice a plot grew axis labels it
   shouldn't have.
2. For a quick one-off visual probe of a specific app file (rather than the full
   `tools/headless_dashboard_probe.R` sweep, which is `app.R`-specific), the throwaway-wrapper-
   directory pattern above is the fastest path: write the 2-line wrapper `app.R`, point
   `AppDriver$new(app_dir = <wrapper dir>)` at it, `wait_for_idle()`, then `get_screenshot()`.
   Clean up the wrapper directory and any `tools/tmp_*` scratch files afterward — none of this
   session's probe scaffolding was committed or left behind.

## Concrete next step

Unchanged from the prior session's own next-step list below, since this thread didn't touch #49:

1. **Issue #49** (Slice 5) is still the only unstarted ticket, still blocking #43/#44. See the
   prior session's "Concrete next step" item 1 below for the full detail (re-verify
   `AppDriver` health first, read `control_panel_app.R`'s `run_pipeline_stage_captured()` before
   starting). One update: `AppDriver` health is no longer in question as of this session (see
   "Environment/tooling notes" above) — the "don't start until confirmed healthy" gate from the
   prior session's note is now cleared, assuming no new regression since.
2. Once #49 lands, close #43 and #44 on the tracker — the only two issues left after that.
3. The three stale headless probes (`tools/headless_control_panel_probe.R`, `tools/headless_
   control_panel_staleness_probe.R`, `tools/headless_control_panel_queue_lock_probe.R`) still
   need the login step added, per the prior session's item 3 below — not touched this session.
4. `.claude/worktrees/` cleanup (`.gitignore` entry + confirmed `cleanup_worktrees.R` run) is
   still pending, per the prior session's item 4 below — not touched this session, still 552MB.

---

# Handoff — 2026-10-05 (Continuing thread: all 6 Dunks & Threes tickets (#60-65) AND the entire control-panel + auth tree (#43-54, all slices except #49) implemented and merged to `main` — 14 of 16 open GitHub issues closed out by code, commit `13919fc` is `HEAD`) — PRIOR SESSION'S STATE (superseded by the section above, kept for its still-accurate detail — e.g. "Bugs found," "Environment/tooling notes," "The reusable workflow")

**This supersedes the "spec interview only, nothing implemented yet" framing of the section
immediately below** (same day, earlier in the day — that section's own content, the spec and
issue list it describes, is still accurate and worth reading for ticket rationale, just not its
"nothing implemented yet" status). This session also picked up the entire separate, older
control-panel/auth issue tree (#43-54, filed 2026-09-26, described starting at the
`2026-09-26 (New thread: interactive control-panel app spec...)` section far below) and finished
every slice in it except #49.

## What this thread did

Ran all 16 then-open GitHub issues through implementation in parallel waves (`subagent-brief`
skill, `isolation: "worktree"`, up to 4 concurrent dispatches), with the orchestrator
independently re-verifying every subagent's own self-reported evidence before merging — this
caught several real problems subagents' own probes missed or caused (see "Bugs found" below).
Partway through, this machine hit two real constraints: a Claude session rate limit (resumed
after reset) and sustained system-wide memory pressure that made `shinytest2::AppDriver` (real
headless Chrome) unusable for the back half of the session — confirmed by `main`'s own
**already-merged, previously browser-tested** `summary_app.R` failing to launch via `AppDriver`
identically to every new change, i.e. not caused by any of this session's diffs. The later
tickets (#63, #50, #53's final verification, #54) were implemented directly by the orchestrator
(not dispatched to subagents) and verified via `shiny::testServer()` instead of a real browser —
see "The reusable workflow" below for why that turned out to be the *better* verification tool,
not just a fallback.

## Issue tracker is now stale — flagging, not fixing silently

**`gh issue list --state open` still shows all 16 of these issues as `OPEN`.** Nobody in this
session closed any of them (closing issues is a visible, judgment-call action this skill's
git-safety conventions leave to the repo owner, not something to do unprompted while writing a
handoff). The actual code state, verified against `git log`/file contents, not the tracker:

| # | Title | Code status |
|---|---|---|
| 60 | Reactable: Standings table | **Merged**, `98d37c2` |
| 61 | Reactable: Model benchmark table | **Merged**, `40272f5` |
| 62 | Reactable: Accuracy table | **Merged**, `972ab89` |
| 63 | Typography & chart-minimalism visual pass | **Merged**, `530c42c` |
| 64 | Offense/Defense rating split | **Merged**, `0365dbb` |
| 65 | Quadrant scatter chart (ORTG vs DRTG) | **Merged**, `b3b56c9` |
| 43 | Add interactive control-panel app (epic) | Parent of 46-50; all its slices except 49 merged |
| 44 | Add reusable multi-user auth system (epic) | Parent of 51-54; **all 4 slices merged** |
| 46 | Slice 2: control_panel_app.R MVP | **Merged**, `0d60468` |
| 47 | Slice 3: Dependency staleness check | **Merged**, `1b87d28` |
| 48 | Slice 4: Multi-select queue + run lock | **Merged**, `eaf1736` |
| 49 | Slice 5: Extract shared render helpers | **NOT STARTED** — see "Concrete next step" |
| 50 | Slice 6: Network access + password gate + docs | **Merged**, `9491801` |
| 51 | Slice 1: auth_utils.R core | **Merged**, `92c6987` |
| 52 | Slice 2: Signup key-phrase gate | **Merged**, `ab029c3` |
| 53 | Slice 3: Mountable login module | **Merged**, `dd9a491` |
| 54 | Slice 4: Wire auth into control_panel_app.R | **Merged**, `13919fc` |

Whoever picks this up should close 43, 44, 46-48, 50-54, 60-65 on the tracker (43/44 only once
49 is also done, since they're epics covering the whole slice list) — left undone here
deliberately, not forgotten.

## What's actually implemented (new/changed files, with real line counts)

| File | Status | Notes |
|---|---|---|
| `summary_app.R` | 1,419 lines (was 1,108 before this thread) | All 3 tables (`standings_table`, `model_benchmark_table`, `accuracy_table`) are `reactable` now, not `renderTable`. New `ortg_drtg_quadrant_plot`. New top-level `tags$style()` CSS block (card-header small-caps, padding). Every `renderPlot` now has the thin-gridline `theme()` extension. |
| `roster_bottom_up_engine.R` | +~120 lines | `project_all_wnba_teams()`'s cache output gained `Off_Rating`/`Def_Rating` columns, reconciling exactly (`Off_Rating - Def_Rating == Net_Rating`, verified to floating-point tolerance) to the pre-existing `Net_Rating`. New `config.R` constant: `WNBA_OFF_REB_SHARE <- 0.24` (derivation comment in `config.R`). |
| `auth_utils.R` | 222 lines, new | `create_user()`, `verify_user()` (constant-time, no username-enumeration leak via a fixed dummy bcrypt hash), `create_account_if_authorized()` (key-phrase-gated signup). SQLite store at `cache/auth_users.sqlite`, fully decoupled from `logs/analytics.duckdb`. |
| `auth_login_module.R` | 229 lines, new | `mod_login_ui(id)`/`mod_login_server(id)`, mountable in any Shiny app. Returns a `reactive(TRUE/FALSE)`. No persisted session (same-tab refresh = new session = re-login, by design). |
| `control_panel_app.R` | 724 lines, new | Pick stage(s) from `pipeline_stages.R`'s `PIPELINE_STAGES` registry, multi-select queue, per-stage staleness gate with override, cross-session run lock (`.PIPELINE_RUN_LOCK`, in-memory, package-scope, `session$onSessionEnded()` release + 20-min fallback self-clear), real login wall (`mod_login_ui("auth")`/`mod_login_server("auth")`) gating the whole control-panel body. `CONTROL_PANEL_PASSWORD` (the #50 placeholder) is **fully dead**, zero remaining reference. |
| `docs/CONTROL_PANEL_SETUP.md` | 71 lines, new (rewritten once, by #54) | Setup instructions for `CONTROL_PANEL_SIGNUP_KEY` + network launch. The first version (written by #50) documented `CONTROL_PANEL_PASSWORD` instead — fully replaced, not left as a stale alternate path. |
| `tools/demo_login_app.R` | 98 lines, new | Throwaway demo app for #53's own QA. **Had a real bug, now fixed** — see "Bugs found" below. |
| `tools/headless_login_module_probe.R` | 265 lines, new | Live-browser probe for the login module. Last known-good run (before `AppDriver` became unusable) passed all 5 criteria after the demo-app fix. |
| `tools/headless_control_panel_probe.R`, `tools/headless_control_panel_staleness_probe.R`, `tools/headless_control_panel_queue_lock_probe.R` | Pre-existing (from #46/#47/#48), now **stale** | Flagged with a header comment each: none of them log in first, so every element they drive (`run_btn`, `stage_id`, etc.) no longer exists pre-auth as of #54. Need a login step added (same `set_module_input()`-via-`Shiny.setInputValue()` pattern as `headless_login_module_probe.R`) before they can run again. Not updated this session — see "Environment notes." |

## Bugs found and fixed this session (not pre-existing, introduced by subagents this session)

1. **`control_panel_app.R` (issue #46's own agent): hardcoded absolute-path `setwd()`.**
   `PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"; setwd(PROJECT_DIR)` silently
   escaped into the **main repo** whenever the script ran from a git worktree at a different
   path (which coincidentally still existed on this machine) — would have broken under any
   worktree-based testing, including this session's own verification pattern. Fixed: no
   `setwd()` at all, `.CONTROL_PANEL_ROOT <- getwd()` captured once at source time instead
   (matches every other script's "assume cwd = project root" convention per `CLAUDE.md`).
2. **`tools/demo_login_app.R` (issue #53's own agent): a genuine infinite reactive loop.**
   `protected_render_count(protected_render_count() + 1)` inside a `renderUI` that also
   *reads* `logged_in()` — reading `protected_render_count()` un-isolated inside the same
   render subscribes that render to its own future invalidation, so the write immediately
   re-triggers it, forever. This is what caused every single "hung"/"timed out"/"killed for
   low memory" result on a *successful* login path, across multiple independent verification
   attempts (both live-browser and, initially, `testServer()`) — misdiagnosed for a while as
   environment/memory pressure before the pattern (always hangs at the exact same semantic
   point: the only code path that reaches this line) gave it away. Fixed with `isolate()`
   around the read. **This was in the throwaway test fixture, not in `auth_login_module.R`
   itself**, which was clean the whole time (confirmed: `verify_user()` timed at ~0.2s
   standalone, completely unrelated to the hang).
3. **Three separate agents' own `shinytest2::AppDriver` probes pointed `app_dir` at a bare
   `.R` *file* path** (e.g. `app_dir = file.path(project_dir, "summary_app.R")`) instead of a
   directory — `shinytest2` silently falls back to looking for a literal `./app.R` in the
   resulting directory, launching the **wrong app** (whichever `app.R` happens to live
   alongside the intended file) with no error. One agent's saved "passing" screenshot was
   actually of `app.R` (the unrelated betting-terminal dashboard), not the file it claimed to
   test. The correct pattern (used successfully by later tickets): write a throwaway wrapper
   `app.R` in a tempdir that does `setwd(project_dir); source("real_target.R")$value`, and
   point `AppDriver` at that tempdir.
4. **A test probe (issue #48's own agent) polled the wrong Shiny session's output.**
   `status_text_js(tab_b)` (a second, independent browser tab/session, used to observe the
   cross-session lock) was also used to check whether the *first* session's queue had
   finished — but `status_ui` is per-session reactive state; `tab_b` never ran anything, so
   its own `status_ui` stayed `"Idle."` forever regardless of what `tab_a` was doing. Fixed by
   reading `app_a$get_text("#status_ui")` (the session that actually started the queue)
   instead.

## Environment/tooling notes (new this session)

- **`shinytest2::AppDriver` (real headless Chrome) became unusable system-wide partway
  through this session** and stayed that way for the rest of it — confirmed not caused by any
  code change here (tested against `main`'s own pre-existing, previously browser-verified
  `summary_app.R`, which failed identically: `Error in value[[3L]](cond): Error sourcing
  .../app.R`, no further detail surfaced). System free memory was observed falling from
  ~4.5GB to ~3.5GB over the course of the session with no Chrome/R processes of this
  session's own still running at the time of several kills — this machine runs multiple
  concurrent Claude Code sessions (see `ListAgents`-visible peer sessions), and the likely
  cause is memory contention from those, not anything fixable from within this repo. If
  `AppDriver` is still failing in a future session, don't assume it's your own change; check
  `Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory` and whether other
  sessions are active first.
- **`shiny::testServer()` is a far better primary verification tool than a live headless
  browser for this repo's Shiny apps**, not just a fallback when Chrome is unavailable — it
  runs in-process (no Chrome, no httpuv networking, no port-conflict/zombie-process risk),
  completes in under a second for scenarios that took the browser-based probes 60-480+
  seconds (or never finished), and its determinism is exactly what caught bugs #2 and #4
  above that the flakier browser probes had been silently failing to catch (misattributing
  the hang to environment issues). Pattern used repeatedly this session:
  `source("control_panel_app.R")` (or whichever app file) at top level, then
  `testServer(server, { session$setInputs(...); ...; cat(isolate(some_reactive())) })`. Two
  *separate* top-level `testServer()` calls simulate two independent sessions (e.g. two real
  logged-in users) correctly for most purposes, but note: a session's `onSessionEnded()`
  callbacks fire when its `testServer()` block *returns*, so this does NOT correctly simulate
  "two sessions alive at the same moment" for anything that depends on one session's teardown
  timing relative to another still-open one (e.g. don't trust it for testing a lock still
  held by session A while session B's block is executing — session A has already "ended" by
  then). For that specific shape, the live-browser raw-`chromote`-tab pattern in
  `tools/headless_control_panel_queue_lock_probe.R` is the right tool, when Chrome is healthy.
- **A git worktree's own `renv` library is often NOT pre-populated** even though
  `renv.lock` is correct — `renv::restore(prompt = FALSE)` (links from the shared cache,
  near-instant, no network) is needed once per fresh worktree before any `library()` call
  that isn't already in every worktree's base state will work. Symptom if skipped:
  `Error in library(X) : there is no package called 'X'` even though `X` is genuinely in
  `renv.lock`.
- **`.claude/worktrees/` is not in `.gitignore`.** 11 worktrees (552MB total, all from this
  session's `subagent-brief` dispatches, all already merged into `main`) are sitting
  untracked at `.claude/worktrees/*` right now — `git status --short` shows them as a single
  `?? .claude/worktrees/` line. Not deleted this session (removal needs
  `--confirmed-by-user` per the `subagent-brief` skill's own rules, and that confirmation
  wasn't sought this session). Flagging two separate things for whoever picks this up: (a) a
  `.gitignore` entry for `.claude/worktrees/` would prevent an accidental `git add -A` from
  ever staging this, (b) once confirmed safe, `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
  "C:\Users\kailo\.claude\skills\subagent-brief\scripts\cleanup_worktrees.R" remove --all
  --confirmed-by-user` would reclaim the 552MB — all 11 branches are already merged, nothing
  would be lost.
- **Several `cache/*.rds` and `data/*.csv` files show as modified in `git status` that this
  session never touched** (`betting_ledger.rds`, `copula_wilson_pra.rds`,
  `injury_data_cache.rds`, `latest_player_props.rds`, `latest_value_bets.rds`,
  `odds_history.rds`, `playoff_series_wnba_demo.rds`, `prediction_accuracy_log.{csv,rds}`,
  `risk_state.rds`, `rolling_bet_metrics.rds`, `value_bets_history.rds`,
  `team_embeddings.csv`, `team_similarity_matrix.csv`) — left exactly as found, not staged or
  committed by this session. Almost certainly a concurrent peer session's pipeline run on
  this shared machine, not a regression; worth a quick `git diff --stat` check before trusting
  these files' current on-disk state for anything.
- `cache/projected_wnba_standings.rds` **was** intentionally regenerated and committed this
  session (commit `3a91c68`) specifically to pick up #64's new `Off_Rating`/`Def_Rating`
  columns — that one file's change was deliberate, unlike the list above.

## The reusable workflow this session converged on (repeat this for future subagent-heavy tickets)

1. Write the brief via the `subagent-brief` skill (`templates/full.md`), dispatch with
   `isolation: "worktree"`.
2. **Never trust the subagent's own final JSON result at face value** — re-run at least one
   cited command or re-read at least one cited `file:line` yourself, per the skill's own
   rule. This session, that rule caught all 4 bugs listed above; none of them would have
   surfaced from reading the subagent's report alone (all 4 subagents reported `"status":
   "success"` with plausible-looking evidence).
3. Prefer `shiny::testServer()` over a live `AppDriver` browser probe as the *first*
   verification attempt for Shiny reactive-logic claims (order-of-execution, lock state,
   gating) — reserve the real browser for things that generically can't be simulated
   in-process (actual DOM rendering/CSS, multi-tab-alive-simultaneously timing). See
   "Environment/tooling notes" above for the one real gap in `testServer()`'s simulation.
4. When a worktree's `library()` call fails with "there is no package called", run
   `renv::restore(prompt = FALSE)` in that worktree before assuming it's a real missing
   dependency.
5. Commit in the worktree, `git merge --no-ff` into `main` from the main checkout (not inside
   the worktree), then record the result via `runlog.R record-result` /
   `runlog.R set-status --status merged` so the run log stays an accurate audit trail.
6. If a ticket's own file conflicts with a sibling ticket's (e.g. multiple D&T tickets all
   touching `summary_app.R`), merging them one at a time in sequence auto-resolved cleanly in
   every case this session — no manual conflict resolution was actually needed, despite every
   brief flagging it as a risk.

## Concrete next step

1. **Issue #49** (Slice 5: "Extract shared render helpers + inline results in control
   panel") is the only unstarted ticket from this thread. Its own brief/QA explicitly calls
   it "the highest-risk slice for regressing the existing, working dashboard" and requires
   visually confirming `app.R`'s charts are pixel-equivalent before/after refactoring
   `app.R`'s `server` function to extract shared render helpers into a new
   `dashboard_render_helpers.R` — this is **not** safely doable via `testServer()` alone (it
   needs real rendered pixels, not just reactive-value assertions), so **do not start this
   until `shinytest2::AppDriver` is confirmed healthy again** (quick check: `Rscript -e
   'shinytest2::AppDriver$new(app_dir = "."); cat("OK")'` from the repo root, or re-run
   `tools/headless_dashboard_probe.R` against `app.R` directly). Read `control_panel_app.R`'s
   `run_pipeline_stage_captured()` (the existing captured-text-output renderer `control_panel_app.R`
   currently uses) before starting, since #49's whole point is replacing that with real
   chart/table previews once a stage's own cache is written.
2. Once #49 lands, close out issue #43 (the control-panel epic) and #44 (the auth epic) on
   the tracker, plus every individual slice listed as "Merged" in the table above.
3. Update the three stale headless probes (`tools/headless_control_panel_probe.R`,
   `tools/headless_control_panel_staleness_probe.R`,
   `tools/headless_control_panel_queue_lock_probe.R`) to log in first — each has a header
   comment now pointing at `tools/headless_login_module_probe.R`'s `set_module_input()`
   pattern to copy. Do this once `AppDriver` is healthy, so the update can actually be
   live-tested rather than guessed at blind (this session's own mistake-pattern #3 above is
   exactly the kind of bug that creeps in when a probe script is edited without being run).
4. Decide what to do about the `.claude/worktrees/` situation flagged above (`.gitignore`
   entry + confirmed cleanup) — not urgent, but 552MB is real disk, and the missing
   `.gitignore` entry is a live risk for an accidental future commit.

---

# Handoff — 2026-10-05 (New thread: Dunks & Threes visual-language emulation for `summary_app.R` — spec interview only, nothing implemented yet, 6 GitHub issues filed: #60-#65) — CURRENT STATE FOR THIS THREAD (read this section first, for whoever picks this up next)

**This is a separate thread from everything below it** — grounded in the same `summary_app.R`
(1,108 lines, unchanged this session) but zero code was written. The thread did three things in
sequence: (1) dispatched a research subagent to screenshot comparable public sports-analytics
dashboards, (2) ran a `spec-interview` with the user to turn "emulate Dunks & Threes" into a
concrete spec, (3) wrote that spec to disk and filed it as 6 GitHub issues. Read `CLAUDE.md` first
if you haven't already (unchanged, still applies).

## What this thread is

User asked to find comparable projects online for visual/UX comparison. A general-purpose
subagent researched and screenshotted ~8-10 public NBA/WNBA analytics dashboards and
tournament-bracket UI examples into `C:\tmp\screenshots\` (**outside this repo, not committed,
not part of version control** — a local Windows path, resolved there because the subagent's R
script ran on Windows R even though the directory was requested as `/tmp/screenshots/`; if that
directory is needed again, check `C:\tmp\screenshots\` first, not `/tmp/screenshots/` under Git
Bash's POSIX emulation, which stayed empty). The user picked **Dunks & Threes**
(https://dunksandthrees.com/) as the primary design reference, then asked for a `spec-interview`
to scope "emulate it" into concrete tickets, then asked to save the spec and file GitHub issues.

## What exists now

**`docs/SPEC_dunksandthrees_emulation.md`** (198 lines, **new, UNCOMMITTED** — `git status
--short` shows it as `??`, untracked) — the full compiled spec from the interview. Read this file
directly for the complete rationale/decisions; don't re-derive from this summary. Covers:
- Why this needed a design discussion (new `reactable` dependency decision, which table columns
  are bar-appropriate, and a real architectural fork: the Dunks & Threes quadrant scatter
  (ORTG vs DRTG) turned out to require new model-engine work, since **this repo's rating engine
  only ever produces a single blended Net Rating — confirmed zero references to
  `offensive`/`defensive` anywhere in `roster_bottom_up_engine.R`**, not just a missing chart.
- 6 decisions: whole-app scope (not one tab), add `reactable` as a new dependency, convert all 3
  existing tables (not just the obvious one), specific bar-column choices per table (including an
  **inverted-scale** bar for Brier Score/Log-Loss, since those are lower-is-better metrics), the
  quadrant chart is in scope but split into its own ticket blocked on the engine work, and a
  6-ticket breakdown prioritizing parallelizability (user's explicit ask: "4+ tickets... prioritize
  high parallelizability").

**GitHub issues #60-#65** (all `OPEN`, all labeled `enhancement`, filed this session) — one issue
per ticket in the spec, bodies are the ticket text verbatim plus file/line pointers:

| # | Title | Depends on | Parallelizable with |
|---|---|---|---|
| [#60](https://github.com/kailot-harris/WNBA_analytics/issues/60) | Reactable: Standings table | — | 61, 62, 63 |
| [#61](https://github.com/kailot-harris/WNBA_analytics/issues/61) | Reactable: Model benchmark table | — | 60, 62, 63 |
| [#62](https://github.com/kailot-harris/WNBA_analytics/issues/62) | Reactable: Accuracy table | — | 60, 61, 63 |
| [#63](https://github.com/kailot-harris/WNBA_analytics/issues/63) | Typography & chart-minimalism visual pass | — | 60, 61, 62 |
| [#64](https://github.com/kailot-harris/WNBA_analytics/issues/64) | Offense/Defense rating split (model engine) | — | 60-63 |
| [#65](https://github.com/kailot-harris/WNBA_analytics/issues/65) | Quadrant scatter chart (ORTG vs DRTG) | **#64** | none (blocked) |

Issues 60-64 can be dispatched in parallel (e.g. via `subagent-brief`, `isolation: "worktree"`) —
**but note tickets 60-63 all touch `summary_app.R`** (60/61/62 each convert a different
`tableOutput`/`renderTable` pair to `reactable`; 63 touches the `ui` block's CSS plus every
`renderPlot`'s `theme()` call). They're logically independent but **not conflict-free if merged
in parallel against the same base** — same caveat this file has flagged before for the SA-1..SA-5
tickets (see far below): either serialize the merges (branch each from the previous one's merged
result, like the SA-1..SA-5 thread did), or expect manual conflict resolution on `summary_app.R`
at merge time. Ticket 64 (`roster_bottom_up_engine.R`) has zero file overlap with 60-63 and is
genuinely conflict-free to run alongside them.

## Loose ends not closed out this session — flagging, not fixing silently

- **`docs/SPEC_dunksandthrees_emulation.md` is uncommitted.** Not committed this session (the user
  didn't ask to commit/push, and this skill's own `git-safety` convention is to only commit on
  explicit request). Whoever picks this up next should commit it (and decide whether it belongs in
  its own `docs:` commit or bundled with the first implementation PR that references it).
- **`C:\tmp\screenshots\` (10 PNGs, ~4MB total) is local-machine-only, not part of this repo, not
  backed up anywhere.** If the design-comparison screenshots are needed again later, they'd need
  to be re-captured (2 of the original 10 failed to capture cleanly: `pbpstats.png` and
  `teamrankings_bracket.png` are actually ERR_CONNECTION_RESET/CloudFront-403 error pages, not
  real site screenshots — don't mistake them for valid comparisons if revisiting that folder).

## Environment notes (new this session)

- Confirmed `summary_app.R` has **zero** `library(reactable)`/`library(DT)` references today —
  tickets 60-62 are a genuinely new dependency add, not wiring up something already imported.
  `renv.lock` will need a `reactable` entry (`renv::snapshot()`) as part of whichever ticket lands
  first among 60/61/62.
- Confirmed via `grep` that `roster_bottom_up_engine.R` has zero `offensive`/`defensive`
  references — ticket 64 is new rating-decomposition logic, not a rename/refactor of something
  that already computes the split internally.

## What's actually changed

- `docs/SPEC_dunksandthrees_emulation.md` — **new, uncommitted**. 198 lines.
- `docs/HANDOFF.md` — this section, new.
- GitHub issues #60-#65 — new, filed via `gh issue create`, not a local file change.
- `summary_app.R`, `roster_bottom_up_engine.R` — **unchanged this session** (read for research/
  grounding during the interview, not edited). Line counts confirmed still 1,108 and 801
  respectively.
- Nothing else touched. No cache files, no other `.R` scripts, no `config.R`, no pipeline files.

## Concrete next step

1. **Commit `docs/SPEC_dunksandthrees_emulation.md`** (currently untracked) — first thing, before
   any implementation work starts, so the spec that tickets #60-65 reference is actually in the
   repo history.
2. **Start implementation on #60-64** (all independently startable; #65 is blocked on #64). Given
   the merge-conflict risk on `summary_app.R` noted above for 60/61/62/63, either: (a) serialize
   them (one `subagent-brief` dispatch at a time, each branching from the previous one's merged
   result, matching the SA-1..SA-5 thread's precedent far below in this file), or (b) run them
   genuinely in parallel and accept manual conflict resolution at merge time. #64
   (`roster_bottom_up_engine.R`) has no file overlap and can run alongside either approach safely.
3. **#65 (quadrant chart) cannot meaningfully start** until #64's offensive/defensive cache columns
   exist — don't dispatch it early expecting only UI scaffolding to get done; the spec notes even
   scaffolding is of limited value without the real data shape to design against.
4. Unrelated to this thread: every other thread below is exactly where its own section leaves it —
   this thread touched none of them.

---

# Handoff — 2026-10-04 (Continuing thread: `summary_app.R` — team logos, Tab 5 collapsible log, Tab 1 win-projection chart reworked into a dot-and-whisker plot, commit `888d75c` pushed to `main`) — CURRENT STATE FOR THIS THREAD (read this section first, for whoever picks this up next)

**This is a continuation of the Playoff Bracket tree / Tab 5 reorder thread immediately
below** (same `summary_app.R` file, different session). This thread is a UI/UX pass
requested directly by the user in conversation — no GitHub issue was filed for any of it
(same "ad hoc feature" pattern as the dark-mode-toggle/methodology-panel thread two
sections down). Read `CLAUDE.md` first if you haven't already (unchanged, still applies).

## Stale-state corrections to the section immediately below

That section's own "Concrete next step" listed open items — re-checked against live state
this session, not trusted from the prior write-up:

1. **GitHub issues #55-#59 (SA-1..SA-5)** — confirmed **CLOSED** via `gh issue list --state
   all` (closed `2026-10-04T20:05:3x`, same as the section two below this one already
   noted). Nothing to do here.
2. **6 stale `worktree-agent-*` branches** — confirmed **gone**: `git branch --list
   "worktree-agent-*"` returns nothing, `git branch -a` shows only `main`.
3. **renv "out-of-sync"/"missing DESCRIPTION files" warnings** — a plain `Rscript.exe`
   invocation with no project code (`cat("test\n")`) printed **no warning** this session,
   and `renv::status()` reports *"No issues found — the project is in a consistent
   state."* This may just be this session's own `renv::snapshot()` run (see below)
   clearing whatever was out of sync at the time, not a root-cause fix of the
   long-standing pattern prior sessions flagged — don't assume it's permanently resolved,
   but it is clean as of right now.
4. **The still-open item from two sections below carries forward unchanged**: a single
   real, non-headless, manual browser session clicking through all 5 tabs together has
   still never been done by any session, including this one. Every verification this
   session (like every session before it) was headless-Chrome via `shinytest2`.

## What this thread is

Three user requests, handled in sequence in one session:

1. **"let's improve the UI + UX of the summary app. I want to use the team logo icons in
   the visualizations if possible."** — added real team logos to Tab 1 (standings table +
   chart) and Tab 2 (playoff bracket boxes).
2. **"Tab 5: make the log a drop down similar to methodology on tab 1"** — wrapped the
   "Real Resolved Predictions" table in a closed-by-default `accordion()`, matching Tab 1's
   existing Net Rating methodology panel.
3. **"plot on tab 1 needs a major rework. what is the industry standard for this type of
   projection?"** followed by **"Uncertainty bars on a horizontal dot plot with a 50/50
   line"** — replaced Tab 1's win-projection bar chart with a FiveThirtyEight/ESPN-BPI-style
   horizontal dot-and-whisker plot, with a real (not fabricated) ~95% CI and a .500
   reference line.

## What exists now

### 1. Team logos (`www/logos/<ABBR>_logo.png`, 15 files, new)

Fetched from ESPN's public team-logo CDN (`https://a.espncdn.com/i/teamlogos/wnba/500/
<espn-slug>.png`) and saved under `config.R`'s `WNBA_TEAMS` abbreviations. **Filename
pattern is `<ABBR>_logo.png`, not a bare `<ABBR>.png`** — Connecticut Sun's abbreviation is
`CON`, and `CON` (with or without an extension) is a reserved Windows device name (same
family as `PRN`/`AUX`/`NUL`/`COM1-9`/`LPT1-9`). A bare `CON.png` can be `ls`-listed by Git
Bash's POSIX emulation but **cannot be opened via a normal Win32 path** — `git add` failed
outright mid-session with `error: open("www/logos/CON.png"): No such file or directory`
even though the file visibly existed on disk. If any future WNBA franchise is ever
abbreviated `PRN`, `AUX`, `NUL`, or `COM1-9`/`LPT1-9`, the same collision will recur; the
`_logo` suffix on every file (not just `CON`) sidesteps this for any future case too.

`summary_app.R:52-61` sources `config.R` into an isolated `new.env()` once at the top of
the file (not line-by-line `get()` calls scattered around) to pull `WNBA_TEAMS` (abbr →
full name) and `WNBA_SEASON_GAMES` (44, used for the .500 line below) — the only two
constants this file borrows from `config.R`; this doesn't violate the file's own "no shared
code path with `app.R`" design note at the top, since `config.R` is a pure constants file,
not `app.R` itself.

Logo helper functions, `summary_app.R:84-131`:
- `LOGO_DIR` (`:84`) — resolved to an **absolute path** via `normalizePath()` at source
  time, not a bare relative `"www/logos"` string.
- `shiny::addResourcePath("wnba_logos", LOGO_DIR)` (`:92`) — registered explicitly, not
  relying on Shiny's implicit `www/`-folder auto-mount.
- `team_abbr_for()` / `team_logo_path()` / `team_logo_raster()` (with a small in-session
  raster cache, `.logo_raster_cache`) / `team_logo_img_tag()` (`:96-131`) — all fail-safe,
  return `NA`/`NULL`/`""` on any lookup miss rather than erroring.

**A real bug caught and fixed by looking at a live screenshot, not by an error-free
headless pass**: both the absolute-path resolution and the explicit `addResourcePath()`
call exist *because* the first attempt (relative `"www/logos"` string, implicit `www/`
auto-mount) rendered every logo blank in a real shinytest2/Chrome session, even though it
worked perfectly in a standalone `Rscript` render — `shiny::runApp()` changes the process
working directory to the app's own directory for the life of the server, and this repo's
own headless-probe convention (a wrapper `app.R` that `setwd()`s and sources
`summary_app.R` from a different directory — see `CLAUDE.md`) makes the directory mismatch
even more likely to bite in production too. 0 `.shiny-output-error` elements were true in
*both* the broken and fixed states — the same "absence of an error is not sufficient"
lesson the Playoff Bracket tree thread (two sections below) already recorded once.

Used in:
- Tab 1 standings table (`summary_app.R:414`) — a `Logo` column of `<img>` tags via
  `team_logo_img_tag()`, rendered with `sanitize.text.function = function(x) x` on
  `renderTable()` (needed for the HTML to render as an image instead of being escaped).
- Tab 2 playoff bracket (`summary_app.R:728` onward) — each decided bracket box gets a team
  logo in its left third via `annotation_custom(rasterGrob(...))`, with the team-name text
  label shifted right to make room (`nodes_df$text_x`/`logo_x`, added this session). Pending
  ("TBD") Finals boxes have no logo, same as before.
- Tab 1 win-projection chart (`summary_app.R:478`) — see below.

### 2. Tab 5: collapsible "Real Resolved Predictions" log (`summary_app.R:378-384`)

The table that used to be an always-open `card()` is now `accordion(open = FALSE,
accordion_panel("Real Resolved Predictions ...", tableOutput("accuracy_table")))` —
visually matching Tab 1's existing Net Rating methodology accordion.

**A real bug caught and fixed, same "don't trust an error-free check" pattern as above**:
wrapping the table in a *closed-by-default* accordion made Shiny **permanently suspend its
rendering** — confirmed live via DOM inspection (`aria-expanded` flipped to `"true"` on
click, but `#accuracy_table`'s `innerHTML` stayed empty, 0 rows, even after the panel
visibly opened). Unlike a `tabsetPanel`, a bslib accordion's expand/collapse doesn't trigger
Shiny's visibility-based re-render hook. Fixed with `outputOptions(output, "accuracy_table",
suspendWhenHidden = FALSE)` (`summary_app.R:1074`), which forces the table to render in the
background regardless of the accordion's open/closed state. Re-verified after the fix: 36
real resolved rows present in the DOM both before and after toggling, 0
`.shiny-output-error` elements. **If any future tab ever puts a `tableOutput`/`plotOutput`
inside a closed-by-default `accordion_panel`, apply the same `suspendWhenHidden = FALSE`
fix up front** — this is a general bslib-accordion gotcha, not specific to this one table.

### 3. Tab 1: win-projection chart reworked into a horizontal dot-and-whisker plot

Replaced the old horizontal bar chart (`geom_col`) with a FiveThirtyEight/ESPN-BPI-style
plot (`summary_app.R:428-521`, `output$standings_chart`):
- **Dot** = `Proj_Wins` point estimate, one row per team, ordered highest-to-lowest
  top-to-bottom, team logo as the row label (no axis text).
- **Whisker** = a real ~95% CI, `Proj_Wins ± 1.96 × Proj_Wins_SD`, clipped to
  `[0, WNBA_SEASON_GAMES]`. **This is not a fabricated/placeholder band** — see below for
  where `Proj_Wins_SD` comes from.
- **Dashed vertical line at `WNBA_SEASON_GAMES / 2`** (22 wins, read from `config.R`, not
  hardcoded), labeled `.500 (22 wins)`.
- **Color split at the playoff line**: `Rank <= 8` (8 of 15 teams make the playoffs, per Tab
  2's bracket) is teal (`#18BC9C`), everyone else is a muted grey-blue (`#7F93A8`), with a
  top legend ("Playoff position (top 8)" / "Outside playoff line").

**`Proj_Wins_SD` is new, added to `roster_bottom_up_engine.R`'s `project_all_wnba_teams()`**
(`roster_bottom_up_engine.R:668,696-701,715-722`): an **analytic** standard deviation on the
win total, derived from the model's own already-computed per-opponent home/away win
probabilities (`p_win_home`/`p_win_away`, same loop that already computes the `Proj_Wins`
expectation) — each team's season is modeled as `games_per_opponent/2` independent home
Bernoulli(`p_win_home`) trials plus `games_per_opponent/2` independent away
Bernoulli(`p_win_away`) trials against each of the other 14 opponents, so `Var(total wins) =
Σ_opponents [(games_per_opponent/2)·p_home·(1-p_home) + (games_per_opponent/2)·p_away·
(1-p_away)]` by independence-of-sum-of-independent-Bernoullis. `summary_app.R` turns this
into the ±1.96·SD interval via a normal approximation (reasonable for ~44 trials spread
across 14 opponents). **Explicitly not fabricated**: when asked for uncertainty bars, the
alternative considered and rejected was inventing a plausible-looking band with no real
basis — this derivation was written instead specifically to avoid that.

`cache/projected_wnba_standings.rds` was **regenerated this session** by re-running
`roster_bottom_up_engine.R` directly (`"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
roster_bottom_up_engine.R`) to populate the new `Proj_Wins_SD` column — real fitted values
this session, ~3.0–3.2 wins across all 15 teams (sensible spread for a 44-game season), not
placeholders. The new column also now appears in Tab 1's standings table (nothing hides
it). Every other consumer of this cache (`app.R`, `market_odds_engine.R`,
`playoff_simulator.R`, `rapm_engine.R`, `live_game_listener.R`) was checked before adding
the column — all access it by column name, never positionally, so the schema addition is
safe for them.

## Environment/tooling notes new this session

- **`png` package was not in `renv.lock`** before this session (needed for
  `png::readPNG()` + `grid::rasterGrob()` to draw logos inside `ggplot2` plots via
  `annotation_custom()`) — installed (`install.packages("png", ...)`, binary, no compile)
  and pinned via `renv::snapshot(prompt = FALSE)`. The resulting `renv.lock` diff also
  backfilled some metadata-only fields on unrelated existing entries (`duckdb`, `vip`) —
  reviewed, no version changes, safe.
- **Windows reserved device names collide with team abbreviations** — see the `CON.png`
  writeup above. Worth remembering for *any* future per-team-abbreviation filename in this
  repo, not just logos.
- **`geom_errorbarh()` is deprecated in the installed ggplot2 (4.0.0+)** — the Tab 1 chart
  uses `geom_errorbar(..., orientation = "y")` instead, which is silent (no deprecation
  warning) and behaves identically for a horizontal error bar.

## The reusable workflow this session followed (repeat this for future `summary_app.R` UI work)

Same two-step discipline the Playoff Bracket tree thread (two sections below) established,
applied three times this session (once per user request):
1. **Standalone `ggplot2` render first** — a throwaway `tools/tmp_*_preview.R` writing a
   `.png`, read with the Read tool, deleted after. Caught nothing new this session (all
   three standalone previews looked right first try), but is what *would* catch a layout
   bug before it reaches the browser.
2. **Live headless-Chrome verification against the real app** — a throwaway wrapper
   `tools/tmp_summary_probe_dir/app.R` (`setwd("../..")` then
   `source("summary_app.R")$value`) driven by a throwaway `tools/tmp_summary_probe_run.R`
   using `shinytest2::AppDriver` with `CHROMOTE_CHROME` set explicitly and a fixed
   `shiny_args = list(port = ...)`. **This is what actually caught both real bugs this
   session** (blank logos, blank Tab 5 table) — neither was visible in the standalone
   render, both were only visible by actually looking at (or DOM-querying) the live app.
   - **New gotcha this session, not previously documented**: a screenshot taken
     immediately after `app$wait_for_idle()` can still be blank/stale even though Shiny's
     own `shiny:value` events already fired — `Sys.sleep(3)` after `wait_for_idle()` was
     needed before `get_screenshot()` reliably showed real content. A 1.5s sleep was not
     enough and produced a convincingly-empty-looking screenshot that could be
     misread as "nothing rendered" when the actual content was present moments later.
   - For verifying the Tab 5 accordion specifically, screenshot timing was unreliable
     enough that **DOM-level assertions** (`document.querySelectorAll(...).length`,
     `getAttribute('aria-expanded')`) were used as the real evidence instead of trusting a
     screenshot — worth doing this any time a toggle/collapse interaction is being verified,
     not just a static render.
   - All scratch files (`tools/tmp_*_preview.R/.png`, `tools/tmp_summary_probe_dir/`,
     `tools/tmp_summary_probe_run*.R`, `tools/tmp_screenshot_*.png`,
     `tools/tmp_check_*.R`) were deleted after each use — confirmed via `git status
     --short` showing a clean tree before the final commit; none are part of the repo.

## What's actually changed

- `summary_app.R` — modified, committed, pushed (`888d75c`). 1,108 lines (up from 900 at
  the start of this session).
- `roster_bottom_up_engine.R` — modified, committed, pushed (`888d75c`). 801 lines.
  `project_all_wnba_teams()`'s i/j loop extended with the `expected_wins_var` accumulator;
  `Proj_Wins_SD` added to the saved `team_df`.
- `cache/projected_wnba_standings.rds` — regenerated, committed, pushed (`888d75c`). Same
  15-row schema as before plus `Proj_Wins_SD`.
- `www/logos/*_logo.png` — 15 new files, committed, pushed (`888d75c`). ~740KB total.
- `renv.lock` — modified, committed, pushed (`888d75c`). `png` pinned; incidental metadata
  backfill on `duckdb`/`vip` entries (see above).
- Nothing else touched. No other `.R` scripts, no pipeline files, no other docs (this
  section is the first edit to `docs/HANDOFF.md` this session).

## Concrete next step

1. **The still-open item from two sections below carries forward again**: a single real,
   non-headless, manual browser session clicking through all 5 tabs together has still
   never been done by any session. This session's own checks were all headless/automated
   and scoped to the specific tabs/features it touched (Tab 1, Tab 2's bracket boxes, Tab
   5), same pattern as every session before it.
2. **No further UI/UX requests are currently pending** — the user's three asks this session
   (logos, Tab 5 dropdown, Tab 1 dot-plot rework) are all implemented, verified live, and
   pushed. If the user asks for more visual polish, the two real-bug patterns documented
   above (relative-path/working-directory mismatches for any new static asset; `bslib`
   accordion + `suspendWhenHidden` for any new collapsible panel) are the first two things
   to check before assuming a new feature "just didn't render."
3. **If Tab 2's bracket semifinals resolve**, the existing next-step from the thread two
   sections below still applies unchanged (regenerate
   `cache/series_length_predictions.rds` via `tools/series_length_predictor.R`) — this
   session did not touch that cache or that tab's data logic, only added logos to its
   existing boxes.
4. Unrelated to this thread: every other thread further down this file is exactly where its
   own section leaves it — this thread touched none of them beyond the stale-state
   corrections noted above.

---



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
