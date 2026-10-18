# HANDOFF — NBA Analytics

Updated 2026-10-18 (second pass same day, after commit `051dc76`), following a session that
discovered issues #1–#8 had *already* been resolved by a separate parallel session before it could
land its own (redundant) fix for #1 — see §2.3 below, read it before starting #9. Originally
written 2026-10-17.
For whoever picks this up next — human or agent, zero assumed context.

---

## 1. What this project is

A personal Windows-only NBA analytics + quantitative sports-betting pipeline. Mostly R
(tidyverse/tidymodels), one Python file for team embeddings. Runs via `Rscript`, orchestrated by
`schedule_daily.bat` + Windows Task Scheduler (daily ~05:00) and `run_full_pipeline.R`.

**Git Repository:** Remote `origin` → `https://github.com/kailot-harris/NBA_analytics`, default/only branch `main`.
Working tree is clean. Issues #1 through #8 are fully resolved, tested, committed, pushed, and closed on GitHub.

**Read `REPO_MAP.md` first, in full, before touching any code.** It is an exhaustive, verified,
file-by-file inventory (data sources, the pipeline DAG, every script's real vs. synthetic
data status, known filename mismatches, the planning docs' relationship to actual
code). Reading order: `REPO_MAP.md` → `ADR.md` (Phase 1 rationale) → `engineering_log_phase2.md` / `engineering_log_phase3.md` (narrative history) → this file.

**Hard boundary rule (ADR.md Principle I):** never edit `NBA_Analysis_Project.Rmd` or
`NBA_Analysis_Project - Original -no Llm.Rmd` — both are frozen baseline reference reports.

**Sibling Project Notice:** `WNBA_REPLICATION_PLAN.md` in this repo describes a *proposed* port of this codebase to `C:\Users\kailo\kayceeslices\WNBA Analytics\`, written as "no code or folder has been created yet." That is false and badly stale: `WNBA Analytics\` already exists independently with its own `renv.lock`, auth system, pbp engine, prediction logger, and active pipeline. Do not treat `WNBA_REPLICATION_PLAN.md` as a live plan (see Issue #12).

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

### 2.2 `INCONSISTENCY_REMEDIATION_PLAN.md` → GitHub issues #1–#12

Verified status as of 2026-10-18 (`gh issue list --repo kailot-harris/NBA_analytics --state all`):

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
| [#9](https://github.com/kailot-harris/NBA_analytics/issues/9) | `live_game_listener.R` env-var naming inconsistency | P3 | OPEN | — | `live_game_listener.R` reads `THE_ODDS_API_KEY`, while `config.R` and `market_odds_engine.R` read `ODDS_API_KEY`. |
| [#10](https://github.com/kailot-harris/NBA_analytics/issues/10) | `bet_tracker.r` lowercase extension | P3 | OPEN | — | File is named `bet_tracker.r` instead of `bet_tracker.R`, inconsistent with conventions and casing across repo. |
| [#11](https://github.com/kailot-harris/NBA_analytics/issues/11) | `schedule_daily.bat`/`run_full_pipeline.R` overlap | P3 | OPEN | — | `schedule_daily.bat` runs Python embeddings and R pipeline, while `run_full_pipeline.R` also orchestrates stages. Needs deduplication/clear boundaries. |
| [#12](https://github.com/kailot-harris/NBA_analytics/issues/12) | `WNBA_REPLICATION_PLAN.md` is stale | P3 | OPEN | — | Document describes a Phase-0 proposal that was superseded by independent development of the actual `WNBA Analytics` repo. Needs archival banner or update. |

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
- `bet_tracker.r` (`cache/betting_ledger.rds`) -> `>>> [FRESH]`

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
- `bet_tracker.r`: Grades real bets against actual box scores in `cache/betting_ledger.rds`.

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

Issue work in this repo (at least by Session B above, and recommended for whoever picks up #9–#12)
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

## 6. Concrete Next Steps

With all high-priority architectural issues (#1–#8) resolved, remaining work focuses on the four P3
housekeeping and documentation issues. **Re-verify all four are still open** (`gh issue list
--repo kailot-harris/NBA_analytics --state all`) before starting — see §2.3.

1. **Issue [#9](https://github.com/kailot-harris/NBA_analytics/issues/9)**: Standardize environment variable naming.
   - Update `live_game_listener.R` to check `ODDS_API_KEY` (with backward-compatible fallback to `THE_ODDS_API_KEY`).
2. **Issue [#10](https://github.com/kailot-harris/NBA_analytics/issues/10)**: Rename `bet_tracker.r` to `bet_tracker.R`.
   - Use `git mv bet_tracker.r bet_tracker.R` (or two-step rename for Windows case-insensitivity) and update references in `run_full_pipeline.R`, `schedule_daily.bat`, `app.R`, and documentation.
3. **Issue [#11](https://github.com/kailot-harris/NBA_analytics/issues/11)**: Deduplicate `schedule_daily.bat` and `run_full_pipeline.R`.
   - Ensure clean boundary where `schedule_daily.bat` triggers `run_full_pipeline.R` rather than executing redundant individual scripts.
4. **Issue [#12](https://github.com/kailot-harris/NBA_analytics/issues/12)**: Mark `WNBA_REPLICATION_PLAN.md` as archived / superseded.
   - Add clear historical disclaimer banner pointing readers to the actual standalone `WNBA Analytics` repository.

All four are independent (no `Depends on` relationships between them per the original remediation
plan), so they can be worked in any order, including in parallel across separate worktrees/sessions
— just apply §2.3's lesson and re-check live issue state immediately before each one, since this
same repo has now demonstrated that parallel sessions on this machine are a real, not theoretical,
possibility.
