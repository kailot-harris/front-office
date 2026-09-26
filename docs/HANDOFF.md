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

**Issue #45** (Slice 1: shared `pipeline_stages.R` registry + `run_full_pipeline.R` refactor).
This is the foundation every other slice in Ticket A depends on, and per its own issue text, the
riskiest single piece: `run_full_pipeline.R`'s external behavior (stage order, log output,
declared-output mtime checks) must be provably unchanged after the refactor, and the new
per-stage **declared inputs** (which don't exist anywhere in the codebase yet) must correctly
reflect what each stage script actually reads — get this wrong and every later staleness-gating
slice (#47) inherits wrong dependency data silently. Read #45's own QA section before starting;
it names the specific verification steps (before/after pipeline diff, the
`pipeline-freshness-audit` skill, manual cross-check of each stage's real `readRDS`/`read.csv`
calls against its declared inputs). The `new-pipeline-stage-checklist` skill is directly relevant
since this touches `run_full_pipeline.R`'s DAG structure.

Two steps ahead: once #45 lands, #46 (control panel MVP) is the next real UI work, and is
deliberately scoped narrow (single-stage run, no dependency gating, no auth, localhost-only) so it
can be built and manually verified before the riskier slices (#47's dependency gating, #49's
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

**None required — this was a one-shot report, not a multi-tier roadmap.** If picking this thread
back up:
1. **Decide whether to `git add`/commit the two new files** (`WNBA_2026_Postseason_Predictions.qmd`
   and `.html`) — they're currently untracked; this session did not commit anything (not asked to).
2. If the 5 still-`PENDING` 2026-09-24 regular-season rows resolve (box scores catch up), Part 1's
   N=25 real-scoreable-game count should grow to N=30 — re-run Part 1's chunks and update the
   headline numbers in the Conclusion before treating this doc as a final record.
3. Once the actual 2026-09-27 Game 1 results are known, Part 2's bracket tree should be re-run
   round-by-round with real outcomes replacing the corresponding round's probability tree (the
   `bracket-helpers`/`round1`/`round2`/`round3` chunks are structured so only the relevant round
   needs re-deriving, not the whole file) — the doc as written is a **pre-Round-1** prediction,
   not a living/updating bracket tracker.

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
