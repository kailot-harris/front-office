# Handoff — 2026-09-25 — CURRENT STATE (read this section first)

**This section supersedes every pointer further down this file, including both 2026-09-24
sections immediately below it.** Same review-remediation thread: implementing the 27-issue
roadmap in `docs/review_round_1_roadmap.md` against `WNBA_Analysis_Project.Rmd` (repo root).
Still a **separate thread** from the pipeline/dashboard work covered by the rest of this file
(2026-09-19 and earlier). Written after commit `a190873`.

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
