# HANDOFF — NBA Analytics

Updated 2026-10-19 (fourth pass, documenting the 6-stage web test and verification pipeline mirroring NFL and WNBA Analytics). Originally written 2026-10-17; second pass documented the #1–#8 parallel-session collision (§2.3); third pass documented #9 and #10 closures.
For whoever picks this up next — human or agent, zero assumed context.

---

## 1. What this project is

A personal Windows-only NBA analytics + quantitative sports-betting pipeline. Mostly R
(tidyverse/tidymodels), one Python file for team embeddings. Runs via `Rscript`, orchestrated by
`schedule_daily.bat` + Windows Task Scheduler (daily ~05:00) and `run_full_pipeline.R`.

**Git Repository:** Remote `origin` → `https://github.com/kailot-harris/NBA_analytics`, default/only branch `main`.
Working tree is clean. All 12 issues (#1 through #12) from
`INCONSISTENCY_REMEDIATION_PLAN.md` are fully resolved, tested, committed, pushed, and closed
on GitHub. Zero open issues remain.

**Read `REPO_MAP.md` first, in full, before touching any code.** It is an exhaustive, verified,
file-by-file inventory (data sources, the pipeline DAG, every script's real vs. synthetic
data status, known filename mismatches, the planning docs' relationship to actual
code). Reading order: `REPO_MAP.md` → `ADR.md` (Phase 1 rationale) → `engineering_log_phase2.md` / `engineering_log_phase3.md` (narrative history) → this file.

**Hard boundary rule (ADR.md Principle I):** never edit `NBA_Analysis_Project.Rmd` or
`NBA_Analysis_Project - Original -no Llm.Rmd` — both are frozen baseline reference reports.

**Sibling Project Notice:** `WNBA_REPLICATION_PLAN.md` has been archived to `docs/archive/WNBA_REPLICATION_PLAN.md` (Issue #12) with a prominent historical disclaimer banner. It describes an initial proposed port written when "no code or folder has been created yet." That proposal was superseded by independent development: `C:\Users\kailo\kayceeslices\WNBA Analytics\` already exists independently with its own `renv.lock`, auth system, pbp engine, prediction logger, and active pipeline. Do not treat the archived plan as live.

---

## 2. Git/GitHub state and issue tracker

### 2.1 Repo history (key commits on `main`)

1. `e514746` — Initial orphan commit from GitHub UI (generic .gitignore).
2. `d544b5a` — Real initial commit: all project scripts, baseline reports, and markdown docs.
3. `d22a4c0` — Merge of orphan history into `main`.
4. `bc201e0` — Added `INCONSISTENCY_REMEDIATION_PLAN.md`.
5. `1819a28` — Initial GitHub issue-tracking state documentation in `HANDOFF.md`.
6. `b7b4c77` — `fix(issue-1)`: Drop dead `sys.nframe()` guard; add C-2 output staleness checker to `run_full_pipeline.R`.
7. `61b327c` — `fix(issue-2)`: Add `roster_join_utils.R`, wire `player_props_engine.R` to real active rosters and box scores.
8. `ab62112` — `fix(issue-3)`: Repoint `risk_management_engine.R` from dead `bet_log.rds` to real `betting_ledger.rds`.
9. `7b5d87c` — `fix(issue-4)`: Add loud `>>> [WARN] Using SYNTHETIC_FALLBACK ...` console logs across all fallback engines.
10. `fddbdf5` — `fix(issue-5)`: Hoist and unify margin-to-win-probability sigma constant to `MARGIN_SIGMA <- 11.8` in `config.R`.
11. `1b0a834` — `fix(issue-6)`: Wire Tab 6 model calibration to live `prediction_accuracy_logger.R` and `live_calibration.R`.
12. `71051ca` — `fix(issue-7)`: Enhance `load_embeddings.R` and plot real 16-D team embeddings in Tab 5 via 2D PCA.
13. `391e47f` — `fix(issue-8)`: Feed risk engine drawdown-tiered Kelly multiplier into bet sizing (`market_odds_engine.R` & `notify_bets.R`).
14. `869c3ad` — `Fix #9`: `live_game_listener.R` now reads `ODDS_API_KEY` first, falling back to `THE_ODDS_API_KEY`.
15. `490afec` — `Fix #10`: Renamed `bet_tracker.r` → `bet_tracker.R` (100% rename, history preserved via `git log --follow`).
16. `ab92d09` — `docs`: Update `HANDOFF.md` with resolution of issues 9 and 10 and clean stale worktree.
17. `5e793c2` — `Fix #11`: Deduplicate `schedule_daily.bat` by delegating directly to `run_full_pipeline.R` DAG.
18. `1ddd3af` — `docs`: Update `HANDOFF.md` with commit hash for issue 11.
19. `f3a44fd` — `Fix #12`: Move `WNBA_REPLICATION_PLAN.md` to `docs/archive/` with historical disclaimer banner.
20. `29a9bf4` — `docs`: Finalize `HANDOFF.md` with Issue 12 resolution and update `.gitignore` for `docs/archive/`.
21. `b4d1c8f` — `feat(projections)`: Implement `season_simulator.R` for 1,000-season Monte Carlo projections across 4 model variants.
22. `bae5652` — `feat(web)`: Implement Phase 2 Next.js projections web application with variants breakout tabs and diagnostics.
23. `be50bff` — `feat(web)`: Integrate official NBA team logos across standings, variants, and player tables.
24. `ab70dcd` — `feat(web)`: Convert top header to responsive left sidebar (`Sidebar.tsx`).
25. `2c662a4` — `feat(web)`: Activate `GeistSans` and `GeistMono` typography from `'geist/font'` across all views.
26. `21571f1` — `feat(web)`: Add Halloween basketball logo, compact margin sigma popover, full column sorting, playoff contenders box-whisker plot, and variant Brier score calibration visualizer.
27. `3dcdd5c` — `feat(web)`: Break up Season Standings into sub-tabs (Playoff Contenders Visualizer vs Full Standings Table) to eliminate scrolling.
28. `6288d0e` — `fix(web)`: Wire Full Standings Table to dedicated sidebar route and fix clickable tab controls.
29. `07e651f` — `refactor(web)`: Keep single Season Standings tab with unified in-page view toggle between visualizer and table.
30. `aad83b0` — `feat`: Complete Sprints 1-5 (Series, Cap Sheet, Player DNA, Defense, Clutch) with 2026-27 Spotrac calibration.
31. `148c797` — `feat(cba)`: Expand verified Spotrac contract registry to 19 franchises and 93 verified players.
32. `c5420c3` — `feat(cba)`: 100% verified Spotrac contract coverage across all 30 NBA franchises.
33. `7787480` — `feat(web)`: Build comprehensive 6-stage test suite and verification pipeline mirroring NFL and WNBA Analytics.

### 2.2 `INCONSISTENCY_REMEDIATION_PLAN.md` → GitHub issues #1–#12

Verified status as of 2026-10-18, all 12 issues resolved (`gh issue list --repo kailot-harris/NBA_analytics --state all`):

| # | Title | Priority | State | Commit | Summary of Resolution |
|---|---|---|---|---|---|
| [#1](https://github.com/kailot-harris/NBA_analytics/issues/1) | `sync_rosters.R` auto-run guard never fires inside the pipeline | P0 | CLOSED | `b7b4c77` | Removed dead `sys.nframe() == 0` guard in `sync_rosters.R` and `daily_ingest.R`; added `.check_stage_output()` staleness verification (Finding C-2) and `call_fn`/`output` params to `run_stage()` in `run_full_pipeline.R`. |
| [#2](https://github.com/kailot-harris/NBA_analytics/issues/2) | `player_props_engine.R` reads `active_rosters.rds`, nothing writes it | P1 | CLOSED | `61b327c` | Created `roster_join_utils.R` (`join_by_id_then_name()`, `build_real_rotation_table()`); declared `CACHE_ACTIVE_ROSTERS` in `config.R`; repointed `player_props_engine.R` to real active rosters + box score caches; wired `output` in `run_full_pipeline.R`. |
| [#3](https://github.com/kailot-harris/NBA_analytics/issues/3) | `risk_management_engine.R` reads `bet_log.rds`, nothing writes it | P1 | CLOSED | `ab62112` | Added `CACHE_BETTING_LEDGER` and `CACHE_RISK_STATE` to `config.R`; repointed `risk_management_engine.R` from dead `cache/bet_log.rds` to `betting_ledger.rds` with `load_real_ledger()` adapter (filtered to `status == "RESOLVED"`); wired `output` in `run_full_pipeline.R`. |
| [#4](https://github.com/kailot-harris/NBA_analytics/issues/4) | Synthetic-data fallbacks are silent — make them loud | P1 | CLOSED | `7b5d87c` | Added explicit `>>> [WARN] Using SYNTHETIC_FALLBACK ...` console alerts across `rapm_engine.R`, `shot_quality_engine.R`, `fatigue_travel_engine.R`, `playoff_simulator.R`, `copula_props_engine.R`, `market_odds_engine.R`, `injury_scraper.R`, `bet_tracker.r`, `xpoints_engine.R`, and `team_embeddings.py`. |
| [#5](https://github.com/kailot-harris/NBA_analytics/issues/5) | Two sigma constants (11.2 vs 11.8) never unified | P2 | CLOSED | `fddbdf5` | Hoisted `MARGIN_SIGMA <- 11.8` into `config.R` as the shared score margin conditional standard deviation; updated `market_odds_engine.R`, `playoff_simulator.R`, `roster_bottom_up_engine.R`, and `app.R`. |
| [#6](https://github.com/kailot-harris/NBA_analytics/issues/6) | `app.R` Tab 6 calibration curve is hardcoded/fake | P2 | CLOSED | `1b0a834` | Built `prediction_accuracy_logger.R` (`get_prediction_log()`, `log_todays_predictions()`, `reconcile_predictions()`); declared `CACHE_PREDICTION_LOG` in `config.R`; upgraded `app.R` Tab 6 with 4 KPI value boxes and dark-themed `live_calibration.R::calibration_analysis()` plot; wired stage into `run_full_pipeline.R`. |
| [#7](https://github.com/kailot-harris/NBA_analytics/issues/7) | `app.R` Tab 5 "Team Embeddings" doesn't plot real embeddings | P2 | CLOSED | `71051ca` | Enhanced `load_embeddings.R` with `get_nba_team_metadata()`, `get_team_embeddings()`, `get_embeddings_pca()`, `get_team_similarity_matrix()`; updated `app.R` Tab 5 with a true 2D PCA projection of the 16-D vectors (`plot_embeddings_pca`) and segregated the shot quality luck profile into its own card (`plot_shot_quality_luck`). |
| [#8](https://github.com/kailot-harris/NBA_analytics/issues/8) | Risk engine's Kelly multiplier not fed back into bet sizing | P2 | CLOSED | `391e47f` | Integrated `CACHE_RISK_STATE` into `market_odds_engine.R` so `calculate_kelly()` scales by `active_kelly_multiplier` (and flags `🛑 TRADING HALTED (Drawdown Stop-Loss)` when 0.0); updated `notify_bets.R` to respect circuit breaker and dynamic Kelly tier; reordered `run_full_pipeline.R` DAG so `risk_management_engine.R` executes before `market_odds_engine.R`. |
| [#9](https://github.com/kailot-harris/NBA_analytics/issues/9) | `live_game_listener.R` env-var naming inconsistency | P3 | CLOSED | `869c3ad` | `live_game_listener.R:17` now reads `Sys.getenv("ODDS_API_KEY", Sys.getenv("THE_ODDS_API_KEY", ""))` — matches `market_odds_engine.R`'s naming, with backward-compatible fallback. `REPO_MAP.md`'s `THE_ODDS_API_KEY` row updated to describe it as a legacy fallback, not an inconsistency. |
| [#10](https://github.com/kailot-harris/NBA_analytics/issues/10) | `bet_tracker.r` lowercase extension | P3 | CLOSED | `490afec` | File renamed `bet_tracker.r` → `bet_tracker.R` (git-verified 100% rename, history intact). `run_full_pipeline.R:108`'s `run_stage("bet_tracker.R", ...)` call site and `REPO_MAP.md`'s six documentation references updated. `app.R` had no reference to update; `schedule_daily.bat` already used the uppercase name. |
| [#11](https://github.com/kailot-harris/NBA_analytics/issues/11) | `schedule_daily.bat`/`run_full_pipeline.R` overlap | P3 | CLOSED | `5e793c2` | Simplified `schedule_daily.bat` to delegate directly to `run_full_pipeline.R` as the single orchestrator; eliminated redundant secondary runs of `bet_tracker.R` and `market_odds_engine.R`; added exit code validation. |
| [#12](https://github.com/kailot-harris/NBA_analytics/issues/12) | `WNBA_REPLICATION_PLAN.md` is stale | P3 | CLOSED | `f3a44fd` | Moved `WNBA_REPLICATION_PLAN.md` to `docs/archive/` preserving git history and prepended a prominent historical disclaimer banner pointing to the standalone `WNBA Analytics` repo. |

Full criteria/evidence for #9 and #10 live in `.subagent-runs/<run-id>/` (run ids
`20261018-032449-67c159` and `20261018-033123-c4df40` respectively — see `runlog.R show --run-id
<id>`), not duplicated here; this table is a pointer, not the evidence itself.

### 2.3 Gotcha: parallel-session collision on issue #1 (2026-10-18)

**Re-verify `git log`/`gh issue list` against live state before starting *any* issue — don't trust
this doc's own tables past the moment they were written.** This repo had two independent sessions
working on it around the same time on 2026-10-18:

- Session A (whichever one produced commits `b7b4c77` through `391e47f` and the first revision of
  this doc) worked through #1–#8 directly, committing and pushing each fix to `main` as it went.
- Session B (using the `subagent-brief` skill — see §5.1 below) read an **earlier** snapshot of
  this doc that still showed #1 as the sole open P0 issue, built a full brief for it, and dispatched
  a subagent into its own git worktree (`subagent/issue-1-sync-rosters`, commit `b36aecd`,
  "Fix dead auto-run guard... (Closes #1)") to fix it. The subagent's fix was functionally
  equivalent to `b7b4c77` (same guard-removal + staleness-check approach) but entirely independent
  work, produced without knowledge that `main` had already moved.
- When Session B's orchestrator tried `git merge subagent/issue-1-sync-rosters` into `main`, it hit
  a real conflict in `run_full_pipeline.R` (both branches had independently added a
  `.check_stage_output()`-style helper at the same location). The orchestrator correctly
  `git merge --abort`'d rather than force a resolution, re-checked `gh issue list --state all`,
  found #1 already `CLOSED` on the real `main`, and discarded the redundant branch/worktree instead
  of merging (`git worktree remove --force` + `git branch -D subagent/issue-1-sync-rosters`, after
  user confirmation). **No code was lost** — `b7b4c77` on `main` is the fix that actually shipped;
  `b36aecd` never merged and no longer exists as a ref.
- Lesson for next time, independent of which session you are: before dispatching any subagent brief
  for an issue, run `gh issue list --repo kailot-harris/NBA_analytics --state all` and `git log
  --oneline -10 main` yourself, live, even if a HANDOFF.md in front of you says the issue is open —
  it may have been closed minutes ago by a session you can't see.

---

## 3. Automation and Pipeline Status (Verified Live)

The daily pipeline runs end-to-end via `Rscript run_full_pipeline.R` in ~21–25 seconds.
All 8 active stages are monitored with `.check_stage_output()` staleness verification (Finding C-2):
- `sync_rosters.R` (`cache/active_rosters_cache.rds`) -> `>>> [FRESH]`
- `injury_scraper.R` (`cache/injury_data_cache.rds`) -> `>>> [FRESH]`
- `roster_bottom_up_engine.R` (`cache/projected_30_team_standings.rds`) -> `>>> [FRESH]`
- `player_props_engine.R` (`cache/latest_player_props.rds`) -> `>>> [FRESH]`
- `risk_management_engine.R` (`cache/risk_state.rds`) -> `>>> [FRESH]`
- `market_odds_engine.R` (`cache/latest_value_bets.rds`) -> `>>> [FRESH]`
- `prediction_accuracy_logger.R` (`cache/prediction_accuracy_log.rds`) -> `>>> [FRESH]`
- `bet_tracker.R` (`cache/betting_ledger.rds`) -> `>>> [FRESH]`

**Pipeline DAG Ordering Note:**
`risk_management_engine.R` is intentionally sequenced **before** `market_odds_engine.R` so that current bankroll drawdown state and the dynamic Kelly multiplier are written to `cache/risk_state.rds` before `market_odds_engine.R` sizes today's slate bets.

---

## 4. Current State: Real vs. Synthetic Data

### Genuinely Live / Real Data Inputs
- `sync_rosters.R`: Real ESPN active rosters fetch for all 30 teams.
- `injury_scraper.R`: Real ESPN injury report JSON feed.
- `market_odds_engine.R`: Live The Odds API feed (46 active NBA games pulled when live).
- `roster_bottom_up_engine.R`: Real BPM calculations from `player_box_scores_cache.rds` joined against real active rosters.
- `player_props_engine.R`: Joined against real active rosters and player box score histories via `roster_join_utils.R`.
- `risk_management_engine.R`: Analyzes real resolved bets from `cache/betting_ledger.rds`.
- `prediction_accuracy_logger.R`: Tracks real model predictions and reconciles against completed box score game outcomes.
- `load_embeddings.R` / `app.R` Tab 5: Computes real 2D PCA on 16-D vectors from `cache/team_embeddings.csv`.
- `bet_tracker.R`: Grades real bets against actual box scores in `cache/betting_ledger.rds`.

### Explicit Loud Fallbacks
When cache files are missing or external APIs are unavailable, engines emit loud `>>> [WARN] Using SYNTHETIC_FALLBACK ...` console logs:
- `rapm_engine.R`: Falls back to simulated stints if `cache/stint_lineups.rds` is absent.
- `shot_quality_engine.R`: Falls back to synthetic shot profile distributions if shot caches are absent.
- `fatigue_travel_engine.R`: Falls back to synthetic 4-game slate if schedule inputs are missing.
- `playoff_simulator.R`: Falls back to default team ratings if RAPM cache is missing.
- `copula_props_engine.R`: Uses Gaussian copula simulation with loud fallback warning when offline.

---

## 5. Environment and tooling notes

### 5.1 The `subagent-brief` skill is the process being used for issue work

This workflow was reused successfully, with no collision, for #9 and #10 (run ids
`20261018-032449-67c159` and `20261018-033123-c4df40`): verify live state → write brief → validate
→ create worktree → register run → dispatch plain `general-purpose` agent into that worktree →
independently re-verify every criterion → `record-result` → fast-forward `git merge` → `set-status
merged` → remove worktree/branch → push → close issue (GitHub auto-closed both from the commit
message's `Fix #N` / closing-keyword text, so the explicit `gh issue close` calls reported
"already closed" — that's expected, not an error). Follow the same sequence for #11 and #12.

Issue work in this repo (at least by Session B above, and recommended for whoever picks up #11–#12)
goes through the user's `subagent-brief` skill
(`C:\Users\kailo\.claude\skills\subagent-brief\`), not ad hoc delegation. Concretely, per issue:

1. Read the issue itself (`gh issue view <N> --repo kailot-harris/NBA_analytics`) — don't work from
   a table summary.
2. **Re-verify it's still actually open live** (§2.3's lesson) before writing a brief.
3. Write a `full` template brief (one task that edits files) under `.subagent-runs/` describing
   Goal/Context/Scope/Out-of-scope/Allowed actions (Tier 0–1 is enough for these; none of #9–#12
   need Tier 2/3)/Success criteria/Stop conditions. Validate it with
   `Rscript scripts/validate_brief.R <path>` until `errors` is empty — in particular, each numbered
   success criterion must be a **single line** (the validator splits criteria text on `\n`, so a
   criterion that wraps onto a second line loses its own `Verify:` clause silently, logged only as
   a non-blocking warning) and each `Tier N` grant line must use the `- Tier N: detail` colon form,
   not free text after the number.
4. Create an actual git worktree yourself first (`git worktree add -b subagent/issue-N-<slug>
   ../<repo>-wt-issue<N> main`), **then** register the run with
   `runlog.R new-run --brief <path> --worktree <that path>`. Do not pass `isolation: "worktree"` to
   the `Agent` tool on top of this — it tries to create its *own* nested worktree inside the
   current one and fails with a `core.worktree redirect` error (confirmed this session). Dispatch a
   plain (non-isolated) `general-purpose` agent and tell it explicitly, in the prompt, which
   pre-made worktree directory to `cd` into and do all its work in.
5. On **PowerShell** (not the Bash tool) to invoke any of the skill's R scripts on this Windows
   machine — `Rscript <script>.R` through the Bash tool's git-bash `sh` segfaults immediately
   (exit 139) on this setup; the identical command through the `PowerShell` tool works fine.
6. After the subagent reports (or, as happened this session, gets cut off by a session rate limit
   mid-report after it had already committed), **independently re-verify every success criterion
   yourself** from git history and on-disk state before calling `runlog.R record-result` — don't
   trust an agent's self-report, and don't assume a cut-off agent failed to do the work; check
   first (this session's `active_rosters_cache.rds` mtime evidence showed the cut-off subagent had
   in fact already run and validated its fix live, it just didn't get to say so).
7. Only after your own verification, `record-result`, then `git merge` the worktree branch into
   `main` locally (no `--no-verify`, no force) and `set-status`. If the merge conflicts, `git merge
   --abort`, don't resolve blindly — re-check whether the issue was independently closed elsewhere
   first (§2.3).

### 5.2 Known clutter in the working tree (not yet cleaned up, needs an explicit decision)

- `.claude/worktrees/agent-acb649a8f99d2e851/` — a locked, unused worktree left over from a failed
  `Agent(isolation: "worktree")` call this session (see §5.1 point 4 for why it failed). It is
  untracked by git (shows up under `git status`) and currently still on disk. Nobody has decided
  whether to `git worktree remove --force` it yet — do that only with explicit user confirmation,
  same as any worktree/branch deletion.
- `.subagent-runs/brief-issue1.md` and `.subagent-runs/result-issue1.json` — the brief and recorded
  result for the superseded issue-#1 run (run id `20261018-010631-9ea09d`, status `rejected`, see
  §2.3). Left in place as the audit trail the skill is designed to produce; not an error, just note
  it's for a fix that never actually merged.
- `.subagent-runs/20261018-010612-01cf47/` — an orphaned run directory from a `new-run` call made
  *before* its worktree existed (registered without `--worktree`, then immediately superseded by a
  second `new-run` call with `--worktree` set, run id `20261018-010631-9ea09d`). Harmless, never
  dispatched to any agent.

---

## 6. Web Application Test Suite & Verification Pipeline (Built 2026-10-19)

Mirrored the NFL Analytics and WNBA Analytics 6-stage test architecture for the NBA Analytics web platform (`web/`):
- **Stage 1: TypeScript (`tsc --noEmit`)**: Strict static typechecking across all components and pages.
- **Stage 2: ESLint (`next lint --max-warnings=0`)**: Next.js core web vitals and TypeScript linting with zero allowed warnings.
- **Stage 3: Contracts, Invariants & Drift (`vitest run --project node`)**:
  - `tests/contracts/schemas.ts`: Strict `.strict()` Zod schemas covering all 15 JSON datasets and 25 per-player shot telemetry files.
  - `tests/contracts/schema.test.ts`: File existence, non-emptiness, valid JSON, no orphan datasets, and Zod adherence.
  - `tests/contracts/types-vs-data.test.ts`: TypeScript interface field parity and union type exhaustiveness.
  - `tests/contracts/invariants.test.ts`: NBA mathematical invariants (30 teams, 82 games, 1,230 league wins, quantile monotonicity $p_{10} \le p_{50} \le p_{90}$, playoff probability sums $\sum \approx 100\%$, CBA cap tiers).
  - `tests/contracts/referential.test.ts`: 30-team code integrity, 330-player pool consistency, shot player mapping.
  - `tests/contracts/assets.test.ts`: Team logo URLs and shot chart file presence.
  - `tests/drift/content-drift.test.ts`: Source code copy drift audit against live data.
- **Stage 4: React Components (`vitest run --project components` in JSDOM)**:
  - 29 unit and integration tests across StandingsClient, PlayersClient, ShotsExplorerClient, PlayoffSeriesClient, and Client Pages.
- **Stage 5: Production Build (`next build`)**:
  - Verifies all 17 static routes prerender cleanly to production HTML and JS bundles without errors.
- **Stage 6: Browser End-to-End (`playwright test`)**:
  - 79 tests across Desktop Chromium (1440×900) and Mobile Chromium (Pixel 7).
  - `smoke.spec.ts`: All 12 routes load 200 OK, render headings & dataset markers, 0 console errors, no failed requests, no placeholders, no horizontal overflow.
  - `layout.spec.ts`: Desktop viewport responsive tests (1280px, 1440px, 1920px) verifying sticky sidebar non-overlap and scroll boundaries.
  - `interactions.spec.ts`: Interactive search, sorting, filtering, and tab switching.
  - `a11y-and-assets.spec.ts`: Accessible landmarks, `<h1>` hierarchy, image `alt` attributes, ESPN CDN resolution.
  - `mobile.spec.ts`: Pixel 7 drawer toggle, navigation transitions, and zero horizontal scrolling.
- **Baseline Defect Reconciliation (`web/tests/known-issues.json`)**:
  - Tracks 3 legitimate upstream data & copy discrepancies (`cbaThresholdSources` undocumented key in `cba_cap_sheet.json`, `clutch_leverage_metrics.json` `tsDelta` arithmetic variance, and stale 2024 cap threshold copy in `app/cap-sheet/page.tsx`), preventing build failure while maintaining total visibility.
- **Test Orchestrator (`web/scripts/run-test-suite.mjs`)**:
  - Supports `--fast`, `--strict`, and `--only=<stage>` with automated Markdown summary generation (`test-results/SUMMARY.md`).
- **Documentation**:
  - Full guide in `web/tests/README.md`.

---

## 7. Concrete Next Steps

All 12 issues from `INCONSISTENCY_REMEDIATION_PLAN.md` (#1 through #12) are completely resolved, tested, committed, and closed on GitHub. The web test pipeline runs cleanly end-to-end via `npm test` or `node scripts/run-test-suite.mjs`.

Future roadmap items:
1. **Upstream Data Fixes (Resolving `known-issues.json`)**:
   - `cba_cap_sheet.json`: Declare `cbaThresholdSources` in `lib/cbaTypes.ts` or omit from `scripts/generate_cba_cap_sheet.py`.
   - `clutch_leverage_metrics.json`: Recalculate `tsDelta` as true `clutchTsPct - baseTsPct` or document volume weighting in exporter.
   - `app/cap-sheet/page.tsx` & `components/CapSheetClient.tsx`: Update fallback constants to mirror 2026-27 thresholds (`165.0 / 200.4 / 209.0 / 221.7`).
2. **Real Stint-Level RAPM**: Replace synthetic stint generation in `rapm_engine.R` with real play-by-play lineup tracking.
3. **Live In-Play Odds Integration**: Connect `live_game_listener.R` to live WebSocket/REST in-play feeds.
4. **Multi-Player Copula**: Expand `copula_props_engine.R` beyond single-player demonstrations to full slate SGPs.


