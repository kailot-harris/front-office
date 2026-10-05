# NFL Analytics — Handoff Document

**Last updated**: 2026-10-05, after commit `a5d592f` ("Refresh caches from manual pipeline run;
live-verify Discord webhook dispatch"). Local `main` is **even with `origin/main`** (confirmed via
`git fetch origin && git rev-list --count origin/main..HEAD` → 0 — the previous session's note
that 8 commits were unpushed was stale; they, plus this session's one commit, are all on
`origin/main` already). `git status --short` is clean as of this writing — this session committed
and pushed every cache file its manual pipeline run regenerated. Written for a future LLM/agent
picking this repo back up cold — read this before touching anything, then read `CLAUDE.md` for
environment/data-quirk details this doc doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout. `risk_management_engine.R` reports `SYNTHETIC_FALLBACK` (confirmed live,
2026-09-17) because the real bet ledger (`CACHE_BETTING_LEDGER`, written by `bet_tracker.r`) is
genuinely empty — no staked value bet has cleared the early-season `MIN_SAMPLE_GAMES_FOR_STAKE`
gate yet this season, not a bug. `notify_bets.R`'s Discord dispatch is wired up correctly (Known
Issue #1, fixed 2026-10-04) and has now actually posted live (2026-10-05) — most slates are still
100% `INSUFFICIENT SAMPLE (early season)`-gated so most runs still hit the "0 actionable bets"
no-op path, but at least one long-shot row (excluded from staking by `LONGSHOT_DECIMAL_ODDS_CAP`,
not by the sample gate) has reached and exercised the real POST call.

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

**If you're picking up the accuracy-trajectory monitoring work**, read
`docs/SPEC_accuracy_trajectory_monitoring.md` next, then jump to "Accuracy-trajectory monitoring
(issues #1-#7 shipped, #8/#9 done in-repo but open on GitHub, #10 remains)" below — issues #1-#7
shipped two sessions ago; this session got the user's sign-off (task name
`NFL_analytics_task_01`, daily 5:15 AM ET) and created the real Windows Task Scheduler job, then
live-verified both Discord dispatch paths. **Discrepancy to be aware of**: GitHub issues #8 and
#9 still show OPEN (`gh issue list --state all`) even though the work they describe is done in
this repo — nobody has closed them yet. Not fixed here; see "Known issues" below.

## Current state: 12-stage pipeline (11 numbered `run_stage()` calls + stage 9.5)

Runs end-to-end against real data. `run_full_pipeline.R`'s `run_stage()` sources each stage
in-process (`call_fn`-style, no auto-run guards) and asserts every declared output's mtime
advanced (`.check_stage_output()`, WARN not fatal, `gc()` after every stage).

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (23-column whitelist), `CACHE_SCHEDULES` — incremental-merge bug fixed this session (see Recent work), now correctly picks up in-season score corrections |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` — now also cross-source-ID-crosswalk enriched (see Recent work) |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` — full-game EPA/success/CPOE plus 14 new situational splits (see Recent work) |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — ridge+Elo ensemble, QB-adjusted, market-blended `home_win_prob` (production formula unchanged this session) |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — now the NFL's REAL tiebreaker procedure (see Recent work), not the old simplified one |
| 8 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — reads the real ledger when it has RESOLVED bets, else `SYNTHETIC_FALLBACK` (currently the latter — ledger is empty) |
| 9 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real Odds API odds; staking gated by `MIN_SAMPLE_GAMES_FOR_STAKE` and `LONGSHOT_DECIMAL_ODDS_CAP` |
| 9.5 | `bet_tracker.r` | `run_bet_tracker()` | `CACHE_BETTING_LEDGER` — real bet ledger, writer+grader (currently 0 rows) |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch wiring fixed 2026-10-04 (Known Issue #1); **live-verified 2026-10-05** — a manual full-pipeline run actually posted a real embed (Detroit Lions +1650 long-shot pick, correctly flagged non-stakeable) and got back HTTP 204 from the real `NFL_DISCORD_WEBHOOK` |
| 11 | `accuracy_tracker.R` | `run_accuracy_tracker()` | `CACHE_ACCURACY_HISTORY` — added two sessions ago (issues #1-#7, see below). No `output` declared in its `run_stage()` call (deliberately — see that call site's comment): a legitimate no-new-games day is a clean no-op that doesn't touch the file, which `.check_stage_output()`'s staleness check would otherwise flag as a false-positive C-2 warning. **Discord dispatch live-verified 2026-10-05** — see Recent work |

Stage 9.5 runs after stage 9 (needs its output to record today's picks) but before stage 10.
Stage 11 (`accuracy_tracker.R`) runs last, after stage 10 (`notify_bets.R`). Note: the GitHub
issue series (#1-#7) and `docs/SPEC_accuracy_trajectory_monitoring.md` call this "stage 12" in
their prose, but the actual code comment in `run_full_pipeline.R` numbers it "11." (the file's own
sequential comment numbering, which doesn't count stage 9.5 as a whole number) — don't be
surprised by the mismatch if you're cross-referencing the issue text against the file.
**Known ordering gap, unchanged**: stage 8 still runs *before* stage 9.5 grades new bets within
the same pipeline invocation, so a freshly-graded ledger only affects stage 8's next run — one
cycle behind. Not urgent while the ledger is empty.

## Build history (chronological, one row per phase/effort)

| Commit | Phase | What it added |
|---|---|---|
| `9155ad1`…`105eb8e` | Phases 1-7 | Ingestion, EPA/ratings engines, fatigue engine, playoff sim, risk engine, market odds engine, Discord dispatcher. |
| `d1c90aa`, `83682a5` | Phase 8 | Early-season rating shrinkage + minimum-sample staking gate, then backtested (found Sharpe negative at every threshold — the finding that triggered all model-quality remediation since). |
| `7092bad`…`050aebe` | Remediation A-4 | Market blend, QB-injury penalty, ridge Massey rating, MOV-weighted Elo, ridge+Elo ensemble (deployed), GBM stacking (negative result, not deployed). |
| `bb1cd99` | — | Fixed two `run_full_pipeline.R` OS-kills (`CACHE_PBP` column trim + inter-stage `gc()`). |
| `aa990e4` | — | Added `write-handoff-doc` skill; previous full HANDOFF.md rewrite (baseline for everything below). |
| `4f3c9d3`…`872b4b6` | Remediation continuation | Ridge determinism fix, long-shot EV mitigation, real bet ledger, situational EPA features (Phase 4), Kalman state-space model (Phase 5), market-blend Sharpe re-derivation, real NFL playoff tiebreakers, player-ID crosswalk hardening, participation-data pickup (Known Issue #7, debunked), and a new market-disagreement project (Phases 0-2, one credible positive finding). See "Recent work" below for the compressed per-effort breakdown. |
| `461fdb4` | — | Fixed a real data-freshness bug in `daily_ingest.R`'s incremental merge that had silently frozen every team's current-season `games_played` at 1 since Week 1. |
| `4b90b40` | — | Added `tools/weekly_accuracy_report.R` — walk-forward grading of the in-progress season's already-played weeks, a gap no existing cache filled. |
| `63b2185` | — | Spec'd the accuracy-trajectory monitoring feature (`docs/SPEC_accuracy_trajectory_monitoring.md`) and filed it as 10 GitHub issues (#1-#10). |
| `ee271ea`…`61e2a90` | Accuracy Tracker #1-#7 | Implemented the entire accuracy-trajectory monitoring feature end-to-end: shared grading function, history cache, `accuracy_tracker.R` + Discord dispatch, pipeline wiring. See "Recent work" below. Issues #8-#10 (Task Scheduler automation) remain open. |
| `a5d592f` | — | Created the real Windows Task Scheduler job (`NFL_analytics_task_01`, daily 5:15 AM ET, user sign-off obtained first) covering issue #9's work; ran the full pipeline manually against live data to exercise it, which live-verified both Discord dispatch paths (`notify_bets.R` and `accuracy_tracker.R`, both returned HTTP 204) for the first time against the real webhook, then committed+pushed the regenerated caches. See "Recent work" below. |

## Recent work

Everything below shipped since `aa990e4` (the previous full rewrite), across one long
session. Each entry is compressed — `git show <hash>` has the full investigation narrative.

### Ridge Massey non-determinism fix, long-shot EV mitigation, real bet ledger (`4f3c9d3`)

Three findings from one investigation. (1) `fit_ridge_massey()`'s `glmnet::cv.glmnet()` had no
seed, making every Brier/Sharpe figure that used the ridge model silently non-reproducible —
fixed with a local `set.seed(20260917)`. (2) Root-caused Kelly-positive bets clustering in
long-shot underdogs to `MARKET_BLEND_WEIGHT=0.97` amplifying the model's thin residual
disagreement with market via `decimal_odds`; mitigated (not fixed) with
`LONGSHOT_DECIMAL_ODDS_CAP=9.7`. (3) Built `bet_tracker.r` (pipeline stage 9.5) — a real,
honest-cold-start (empty, not fabricated) bet ledger writer/grader.
- **Result**: Sharpe stays negative at every cap value tested; the ledger closed Known Issue #2
  but remains empty in practice (no picks have cleared the staking gate yet).
- **Status**: all three deployed.

### Model-comparison re-verification post-determinism-fix (`3a98431`)

Re-ran `tools/model_backtest_harness.R` now that ridge is deterministic.
- **Result**: every candidate's Brier matched its previously-reported value to 3-4 decimals
  (e.g. `ensemble_ridge_elo` 0.2130). No production change needed — the aggregate Brier metric
  was already stable; only the small-n Kelly simulation was RNG-sensitive.
- **Status**: re-verification only, `cache/model_comparison_backtest.rds`.

### Phase 4: situational EPA feature engineering (`f520b54`)

Play-by-play was only ever reduced to blunt full-game EPA/success/CPOE means despite
down/yardline/play_type already being cached and unused. Widened `CACHE_PBP` to 23 columns and
added 14 situational per-team-per-game splits (early-down vs. money-down EPA/success, red-zone
success rate, explosive-play rate, PROE) in `epa_metrics_engine.R`, plus a new
`tools/ridge_situational_model.R` candidate.
- **Result**: real, modest Brier/log-loss improvement in every matched pair vs. non-situational
  ridge, but Sharpe gets WORSE once blended with market (`ensemble_ridge_situational_elo`
  Sharpe -0.114 @ tau9 vs. deployed -0.089) — same market-blend noise-amplification mechanism
  as the long-shot finding.
- **Status**: NOT promoted. `ensemble_ridge_elo` stays deployed.

### Phase 5: Kalman-filter state-space model (`5016031`)

`rstan`/`cmdstanr`/`brms` are not installed and installing an MCMC toolchain is a real decision
left to the user — `tools/kalman_state_space_model.R` is the closed-form fallback: each team's
latent strength is a Gaussian random walk with exact bivariate conjugate-Gaussian updates,
using GAME-SPECIFIC predictive variance instead of the fixed `NFL_MARGIN_SIGMA`. Four
hyperparameters derived via `tools/derive_kalman_params.R`.
- **Result**: `kalman_phase1_combined`/`ensemble_ridge_elo_kalman` tie for 2nd-best Brier of 16
  candidates (0.2127 vs. deployed 0.2130) but with meaningfully worse Sharpe (-0.216 vs -0.089
  @ tau9) — same pattern as situational EPA.
- **Status**: NOT promoted.

### `MARKET_BLEND_WEIGHT` re-checked against a Sharpe objective (`ef09fe9`)

The weight was only ever derived by minimizing Brier, never checked against staking
profitability or the actually-deployed formula. New
`tools/derive_market_blend_weight_sharpe.R` re-swept it against `ensemble_ridge_elo` and the
real staking gates.
- **Result**: Sharpe is negative across the ENTIRE `[0,1]` grid. The Sharpe-optimal weight
  (0.748, Sharpe -0.051, n=1,197 bets) beats the current 0.97 (-0.091, n=47) per-bet, but only
  by staking ~25x more games — absolute loss would be far larger (-80% vs -0.6%).
- **Status**: `MARKET_BLEND_WEIGHT` left at 0.97 — its thin bet volume is a safety property
  given no edge exists at any weight, not a flaw.

### Quarto profitability-remediation report (`9157a13`)

`docs/profitability_remediation_report.qmd` (rendered to `.html`/`.pdf`) consolidates the four
efforts above into one reproducible document built entirely from cached derivation artifacts.
Rendered and visually inspected both formats (not just exit-code-checked) per this repo's
`render-and-inspect-quarto` convention; found and fixed two real defects (an overlapping-header
table, `ggplot` code truncated at the PDF margin) before treating it as done.
- **Status**: `docs/profitability_remediation_report.{qmd,html,pdf}`, all committed.

### Real NFL playoff tiebreaker procedure (`c091c9d`)

New `nfl_tiebreakers.R` replaces the old win%→alphabetical shortcut with the NFL's real,
live-verified procedure (head-to-head, division/conference record, common games, strength of
victory/schedule, combined point rankings, net points, with the official "restart at step 1"
cascade rule). Three scope limitations are explicitly documented, not silently approximated:
head-to-head "sweep" for 3+ clubs, net touchdowns, and the literal coin toss all fall back to a
simpler rule (see the file's own header).
- **Result**: smoke-tested against real, complete 2025 season data — correctly resolved every
  real tied group (including a 3-way NFC South tie) without error.
- **Status**: deployed (`playoff_simulator.R` wired to it).

### Player-ID crosswalk hardening (`52b74a5`)

`nflreadr::load_ff_playerids()` had been named "the canonical crosswalk" since Phase 0 but was
never actually called live anywhere in this repo. New `player_id_crosswalk.R` live-verifies it
(12,494 rows), found a real vendor data bug (10 `gsis_id`/4 `espn_id`/4 `pfr_id` values each map
to 2+ distinct players — dropped rather than guessed), and exposes `assert_join_match_rate()`.
Applied concretely in `injury_scraper.R` (each row enriched with the other source's crosswalked
id, never merging rows).
- **Result**: real match rates 83.2% (gsis→espn), 88.9% (espn→gsis), both spot-checked correct
  by name.
- **Status**: deployed. No other join point in this repo currently mixes ID schemes.

### Participation/personnel feature pickup, then debunked (`8b6cc38`, `49a4903`)

Known Issue #7 pickup: `tools/participation_features.R` is the first real use of
`nflreadr::load_participation()` in this repo. Re-verified live: seasons 2016-2025 return real
data; `CURRENT_SEASON` genuinely 404s (a hard wall, not stale docs) — kept in `tools/`, never a
live pipeline stage. Registered `tools/ridge_participation_model.R` as two harness candidates.
- **Result**: no real Brier improvement (0.2320 vs. `ridge_only`'s 0.2318). The one seemingly
  positive Sharpe (+0.0017, n=262) was followed up (`tools/investigate_participation_sharpe.R`)
  and debunked: negative at 9/16 tau thresholds, a bootstrap 95% CI of `[-0.151, +0.100]` (44%
  of resamples positive), and 68% of the underlying bets fall in seasons where the feature is
  pure zero-imputed noise.
- **Status**: NOT promoted. Zero evidence this data source adds value.

### New project: train against market disagreement, not game outcome (`872b4b6`)

Every candidate above predicts the GAME better, then blends with market — but at
`MARKET_BLEND_WEIGHT=0.97` the market is already close to sufficient, so out-predicting the
game doesn't necessarily predict WHERE the market is wrong. This project targets
`market_residual = home_win - market_prob` directly.
- **Phase 0 (fact-check)**: nflreadr's own data dictionary documents `home_moneyline`/
  `spread_line` with zero mention of opening-vs-closing timing or source vendor — genuinely
  undocumented. This repo's `CACHE_ODDS_HISTORY` has only ~1 day of real history. Conclusion:
  every `market_prob` this repo has ever backtested against has unverifiable timing — a real,
  previously-unflagged gap, now documented rather than silently assumed.
- **Phase 1+2**: `tools/market_disagreement_features.R` builds the residual label plus five
  features (rest mismatch, div game, primetime, spread size, QB-backup situation) from
  already-cached columns, with an exploratory diagnostic. Found (and fixed) a real bug along
  the way: `isTRUE()` isn't vectorized in base R and silently collapsed the QB-situation
  bucketing to one category on the first run.
- **Result**: one bucket stood out — `home_backup_only` (home team started a backup QB, away
  team didn't; n=430), 95% CI on the residual excludes zero. Follow-up walk-forward strategy
  test (`tools/verify_qb_backup_market_bias.R`, bias estimated from prior seasons only): n=399
  bets, **Sharpe +0.0911**, cumulative return **+96.6%**, positive in 10/14 seasons, bootstrap
  95% CI `[-0.0058, +0.187]` with **96.7% of resamples positive** — the strongest result in this
  entire remediation arc, categorically different from the participation false-positive above.
  Likely mechanism: `QB_INJURY_RATING_PENALTY_PTS` was derived as one symmetric value for
  home/away backup starts, never checked for asymmetry or against Sharpe.
- **Status**: NOT deployed or staked. Needs: checking against the real production staking gates
  (not done yet), accounting for it being the standout of 8 screened buckets, and ideally a true
  holdout against 2025-2026 data as it accumulates.

### Fixed a real data-freshness bug: `games_played` silently stuck at 1 all season (`461fdb4`)

Asked to run the pipeline for Week 4 predictions, found every team's `home_games_played`/
`away_games_played` in `cache/projected_matchups.rds` reading 1, despite three 2026 weeks
having actually been played — i.e. the model had effectively been running on Week-1-only
ratings (mostly prior-season-weighted via `RATING_SHRINKAGE_GAMES_K` blend) for two extra weeks
without anyone noticing, since nothing about the pipeline's own console output flags this class
of staleness.

Root cause, in `daily_ingest.R`'s shared `.ingest_one()` helper (used by both the PBP and
schedules ingests): (1) `bind_rows(existing, new_rows) |> distinct(...)` put the STALE cached
rows first, and `dplyr::distinct()` keeps the first row per dedupe key — so once the initial
full-history bootstrap had cached every 2026 schedule row (including future weeks with `NA`
scores), no later incremental fetch could ever overwrite those rows with the real final score,
even though `nflreadr::load_schedules()` itself returned correct, up-to-date data every time it
was called (live-verified directly — this was never an upstream data problem). (2) The cache
save was ALSO gated on `n_new_records > 0`, a row-*count* delta that stays `0` when an
already-cached row's *content* changes without the total row count changing — so even fixing
bug (1) alone would not have triggered a write.

Fixed both: `new_rows` is now bound first (so it wins `distinct()`'s tie-break), and the save
condition now compares key-sorted table content via `identical()` rather than counting rows.
Re-ran ingestion and confirmed `cache/schedules_cache.rds` now shows all 16 games/week complete
for weeks 1-3 (previously 16/0/0), then re-ran the full pipeline to regenerate every downstream
cache against the corrected 3-games-played sample.
- **Result**: Week 4 projections shifted modestly once ratings correctly reflected 3 games
  instead of 1 — high-confidence games barely moved (Ravens home win prob stayed ~82.8%), but
  closer games moved more (e.g. Cardinals @ Giants home win prob went from 47.3% to 46.7%). All
  16 Week 4 games are still `INSUFFICIENT SAMPLE`-flagged — correctly, now, since 3 <
  `MIN_SAMPLE_GAMES_FOR_STAKE` (9), not because of this bug.
- **Status**: deployed. This is the kind of silent-staleness bug `run_full_pipeline.R`'s own
  `.check_stage_output()` (finding C-2) is designed to catch for a whole-file no-op, but it does
  NOT catch a partial/wrong-content write that still advances the file's mtime — worth keeping in
  mind if another "the pipeline ran successfully but the numbers look wrong" report comes in.

### New tool: `tools/weekly_accuracy_report.R` — grading the in-progress season (`4b90b40`)

Follow-up question after the fix above: "how accurate were the predictions for the weeks
already played this season?" Neither `cache/projected_matchups.rds` (overwritten every run,
upcoming games only) nor `cache/betting_ledger.rds` (still 0 rows — nothing has cleared
`MIN_SAMPLE_GAMES_FOR_STAKE` yet) preserves a historical record of what the model said before a
played game's kickoff, so there was no existing way to answer this without reconstructing it.

New script walk-forwards `CURRENT_SEASON`'s completed weeks using `tools/backtest_common.R`'s
existing no-lookahead snapshot builder (the same discipline `tools/model_backtest_harness.R`
already uses for historical-season calibration, just pointed at the in-progress season instead),
graded with the exact deployed formula (ridge+Elo ensemble, QB-injury-adjusted, market-blended —
`tools/model_backtest_harness.R`'s validated `ensemble_ridge_elo` candidate, reused rather than
re-derived a third time so this can't silently drift from what `team_ratings_engine.R` actually
computes).
- **Result** (2026 weeks 1-3, 48 games): 66.7% straight-up accuracy (75.0% / 68.8% / 56.2% by
  week), Brier 0.2323 vs. a 0.25 coin-flip baseline. Small sample — the declining week-over-week
  accuracy is worth watching but is not enough data to call a trend yet.
- **Status**: deployed as a standalone report tool (not a pipeline stage — it's a query over
  already-cached data, nothing new to ingest). Output at `cache/weekly_accuracy_report.rds`. Rerun
  any time after new weeks complete; NOT automatically re-run by `run_full_pipeline.R`.

### Accuracy-trajectory monitoring implemented end-to-end via parallel subagents (`ee271ea`…`61e2a90`)

User asked to "resolve git issues using parallel subagents when appropriate." Investigation found
the 10 GitHub issues filed by the previous session's spec work (`63b2185`) as the actionable work
(no actual git conflicts/branch problems existed). Used the `subagent-brief` skill to dispatch
each issue as a worktree-isolated subagent, respecting the dependency graph in 4 sequential waves
(parallel within a wave, serial across waves): Wave 1 — #2 ‖ #4 (no deps); Wave 2 — #3 ‖ #5 (both
only needed Wave 1's output); Wave 3 — #6 (needed #5); Wave 4 — #7 (needed #5 and #6). Every
subagent's result was independently re-verified (code read directly, not just the subagent's
self-report) before merging — see each issue's GitHub comment for the specific evidence.

- **Result**: `tools/backtest_common.R` gained `grade_walkforward_games()` (lines ~300-389,
  extracted verbatim from `weekly_accuracy_report.R` with confirmed byte-for-byte parity) plus
  accuracy-history cache helpers (`empty_/init_/load_/append_accuracy_history()`, lines ~191-266).
  `config.R` gained `CACHE_ACCURACY_HISTORY` (line 560). New `accuracy_tracker.R` (repo root, 200
  lines) exposes `run_accuracy_tracker()`: calls `grade_walkforward_games()`, detects newly-graded
  games via a reconstructed `(season, week, away_full, home_full)` key (the per-game table doesn't
  carry a real `game_id`), appends a history row + posts a Discord embed (reusing `notify_bets.R`'s
  exact webhook pattern) only when something new graded, and is wired into `run_full_pipeline.R` as
  its last stage.
- **Real bug caught mid-session**: every script here `setwd()`s to the hardcoded absolute repo
  root rather than respecting the worktree it's actually running in, so subagent verification runs
  in isolated git worktrees were all writing to the SAME real `cache/accuracy_history.rds` file —
  not isolated at all for cache side effects, even though the code changes themselves were. One
  early subagent's leftover test rows (`n_games_graded` 5 and 6, clearly synthetic) had to be
  manually filtered out of the real cache before the next merge; later subagents were briefed to
  use scratch copies instead and did so correctly. **If you dispatch more subagents against this
  repo's cache-writing scripts, assume the same hazard** — any worktree-isolated agent that runs a
  script touching `cache/*.rds` is mutating the one real shared file, not a worktree-local copy.
- **Status**: #1-#7 closed and merged to local `main` (pushed in a later session, see below).
  `#6`'s Discord dispatch was verified by stubbing `httr::POST()`, not by an actual network call —
  no real `NFL_DISCORD_WEBHOOK` POST had been exercised against the accuracy-tracker's new payload
  yet as of this entry (fixed next session, see below). `cache/accuracy_history.rds` had exactly 1
  real row at the time (2026 season, 48 games graded, 66.7% accuracy, Brier 0.2323).

### Backfilled: two prior-session findings this doc had never recorded (`6e2126f`, `85d08a7`)

Found while re-deriving this doc's state from `git log` rather than trusting the previous
HANDOFF.md text — **the previous version of this doc's own "Known Issue #4" claimed the
home-backup-QB market-bias finding "needs more validation before any deployment consideration,"
but two commits already on `main` at the time that text was written (both dated 2026-09-30, before
the accuracy-tracker session) had already done exactly that validation.** Recording them now
rather than silently rewriting the narrative as if they'd always been reflected here:

- **`6e2126f`** (`tools/verify_qb_backup_market_bias_gated.R`) answered the three open questions
  from the original finding: (1) gate-aware re-run applying `MIN_SAMPLE_GAMES_FOR_STAKE`/
  `LONGSHOT_DECIMAL_ODDS_CAP` shrinks the bet set from n=399 to n=217 but Sharpe actually
  *improves* (0.0911 → 0.1066); the finding is not an artifact of ungated staking. (2) The true
  count of bucket-levels screened by `tools/market_disagreement_features.R` is 14, not the "~8" in
  that script's own loose comment — at that corrected count, `home_backup_only`'s raw p=0.00615
  does NOT survive Bonferroni or Benjamini-Hochberg correction at alpha=0.05 (corrected p=0.086
  both ways). (3) A true 2025-2026 holdout is not currently possible — no depth-chart cache exists
  anywhere in this repo (`team_ratings_engine.R` calls `nflreadr::load_depth_charts()` live,
  never persists it), and only 48 games of 2026 were complete at the time. **Recommendation:
  HOLD, not promote or reject** — this is a materially different (more cautious) conclusion than
  "the standout of 8 screened buckets" framing the older doc text implied.
- **`85d08a7`** (`tools/backtest_shrinkage_optimizer.R`'s sibling, a train/test calibration check)
  confirmed `RATING_SHRINKAGE_GAMES_K`/`tau=9` minimizes TRAIN-period Brier (matching the deployed
  config value) but found the Sharpe-optimal sample threshold is g*=0 — the market blend at
  weight=0.97 already dominates from the first game — reconciled with, not contradicting, the
  existing Sharpe-negative-everywhere finding.
- **Why this matters for the next agent**: this doc is reconstructed from `git log` and live repo
  state each time it's rewritten, specifically so stale narrative text like this can't silently
  persist. If you find another case where this doc's prose doesn't match what a `git log --all`
  pass over the relevant files shows, treat the commit history as ground truth and flag the
  discrepancy here rather than trusting either version blindly.

### Windows Task Scheduler automation created; both Discord dispatch paths live-verified (`a5d592f`)

Picked up issue #8/#9's remaining work. Got the user's explicit sign-off first (task name
`NFL_analytics_task_01`, daily 5:15 AM ET), per issue #8's own text requiring confirmation before
creating anything. Created the job via `schtasks /Create` (see Environment specifics below for a
real quoting gotcha hit along the way), confirmed it's `Ready` with `Next Run Time` tomorrow
5:15:00 AM via `schtasks /Query /V`. System timezone is already `Eastern Standard Time`, so no ET
offset conversion was needed.

Then ran `run_full_pipeline.R` manually end-to-end (85.37s, all 11 numbered stages + 9.5) to
exercise the job's real command once before trusting the scheduler to run it unattended, which
incidentally live-verified both Discord dispatch paths for the first time against the real
`NFL_DISCORD_WEBHOOK` (Known Issue #8, below):
- `notify_bets.R` posted a real embed (Detroit Lions +1650 vs. Carolina Panthers, correctly
  excluded from staking by `LONGSHOT_DECIMAL_ODDS_CAP`) — `status_code: 204`.
- `accuracy_tracker.R` detected 14 newly-graded games (season total 48 → 62) and posted a real
  season-accuracy embed (66.1% over 62 games, Brier 0.2249, Log Loss 0.6415) — `status_code: 204`.
- `bet_tracker.r` logged a C-2 staleness WARN on `betting_ledger.rds` (417.6 hours stale) — correct
  behavior, not a bug: there were no real staked picks to append this run, same as every prior
  run since the ledger went live.

Committed the 11 cache files this run regenerated (`a5d592f`) and pushed — confirmed local `main`
was already even with `origin/main` beforehand (the previous doc's "8 commits unpushed" note was
stale; a prior session had already pushed them).
- **Status**: issue #8/#9's in-repo work is DONE. **Not done**: closing issues #8/#9 on GitHub
  (still show OPEN per `gh issue list --state all` as of this writing — flagging per this skill's
  "surface tracker discrepancies, don't silently fix them" convention, since closing issues is a
  visible tracker action the project owner should decide on). Issue #10 (real-world scheduled-fire
  validation) remains open and can't be completed in one sitting — see below.

## Accuracy-trajectory monitoring (issues #1-#7 shipped, #8/#9 done in-repo, #10 remains)

Full spec: `docs/SPEC_accuracy_trajectory_monitoring.md`. Summary: track the model's
season-to-date prediction accuracy over time (not just a one-off `weekly_accuracy_report.R` run)
via a persisted history cache plus Discord posts, triggered idempotently whenever new games
complete. Explicitly does NOT touch the staking gate (`MIN_SAMPLE_GAMES_FOR_STAKE` is a per-game
flag, not a single season-wide on/off event — this feature is independent of staking status) and
explicitly does NOT build a dashboard (`app.R` does not exist in this repo at all; that's deferred
to a separate future ticket if ever pursued).

Filed as 10 GitHub issues (`gh issue list --state all` to re-check current status). Native GitHub
sub-issue links are set for #2/#3 under #1, and #9/#10 under #8. **#1-#7 closed and merged**
(`ee271ea`…`61e2a90`, since pushed to `origin`); **#8/#9's in-repo work is done but the GitHub
issues are still open** (see "Known issues" #9), and **#10 genuinely remains** — observational,
not something to pick up with a subagent (see below).

| Issue | Title | Depends on | Status |
|---|---|---|---|
| [#1](https://github.com/kailot-harris/NFL_analytics/issues/1) | Extract shared walk-forward grading logic (parent) | — | CLOSED |
| [#2](https://github.com/kailot-harris/NFL_analytics/issues/2) | Sub-issue: extract `grade_walkforward_games()` into `tools/backtest_common.R` | — | CLOSED — `tools/backtest_common.R:300-389` |
| [#3](https://github.com/kailot-harris/NFL_analytics/issues/3) | Sub-issue: update `tools/weekly_accuracy_report.R` to call it | #2 | CLOSED |
| [#4](https://github.com/kailot-harris/NFL_analytics/issues/4) | `CACHE_ACCURACY_HISTORY` constant + history-row schema in `config.R` | informed by #2, can start in parallel | CLOSED — `config.R:560`, helpers `tools/backtest_common.R:191-266` |
| [#5](https://github.com/kailot-harris/NFL_analytics/issues/5) | Build `accuracy_tracker.R` / `run_accuracy_tracker()` core (detect new completed games, append to history; no Discord yet) | #2, #4 | CLOSED — `accuracy_tracker.R` (repo root) |
| [#6](https://github.com/kailot-harris/NFL_analytics/issues/6) | Add Discord dispatch to `accuracy_tracker.R` (reuses `NFL_DISCORD_WEBHOOK`, same channel as `notify_bets.R`) | #5 | CLOSED — payload construction verified via stubbed `POST()`; **live webhook POST live-verified 2026-10-05** (`status_code: 204` against the real `NFL_DISCORD_WEBHOOK` — see Known Issue #8) |
| [#7](https://github.com/kailot-harris/NFL_analytics/issues/7) | Wire `accuracy_tracker.R` into `run_full_pipeline.R` as stage "12" (file comment says "11.", see pipeline table above) | #5, #6 | CLOSED — `run_full_pipeline.R:307-308` |
| [#8](https://github.com/kailot-harris/NFL_analytics/issues/8) | Automate daily execution via Windows Task Scheduler (parent) | #7 | **GitHub status OPEN, but the work is DONE** (2026-10-05) — user signed off on task name `NFL_analytics_task_01` / 5:15 AM ET, task created and confirmed `Ready`. Issue not yet closed on GitHub — see "Known issues" below |
| [#9](https://github.com/kailot-harris/NFL_analytics/issues/9) | Sub-issue: create scheduled-task wrapper script + job definition | #7 | **GitHub status OPEN, but the work is DONE** (2026-10-05) — same as #8, task created via `schtasks /Create` directly (no separate wrapper script was needed — see Recent work) |
| [#10](https://github.com/kailot-harris/NFL_analytics/issues/10) | Sub-issue: validate end-to-end (idempotency + real daily cadence) | #9 | OPEN, genuinely not startable yet — requires observing the scheduled task fire across at least one real game day and one real off day. First real scheduled run: tomorrow (2026-10-05) 5:15 AM ET |

Each issue's GitHub comment thread (not just the commit message) has the closing agent's full
verification evidence — read the issue comment for the specific criteria/evidence, this table only
summarizes. Each issue body also has its own "testable independently" section with full acceptance
criteria.

**Key design facts worth re-reading from the spec before implementing**, since they're easy to
get wrong by assuming instead of checking:
- The staking-sample gate (`market_odds_engine.R` line ~603) is computed **per game**
  (`pmin(home_games_played, away_games_played) < MIN_SAMPLE_GAMES_FOR_STAKE`), not once per
  season — re-verify this line number before citing it, source drifts.
- The new stage's trigger is idempotency (compare current completed-game set against what's
  already in `CACHE_ACCURACY_HISTORY`), NOT a calendar/schedule lookup — this is what makes daily
  unconditional Task Scheduler firing safe without a separate "is today a game day" check.
- History granularity is one row per **run that finds new completed games**, not one row per NFL
  week — a Thursday Night Football finish can produce its own row before the rest of that week is
  done.

## Known issues / unfinished business

1. **`NFL_DISCORD_WEBHOOK` not visible to R — FIXED 2026-10-04.** Was set in
   `C:\Users\kailo\Documents\.Renviron`, but R's user-Renviron lookup resolves to
   `C:\Users\kailo\.Renviron` directly on this machine. Moved into `C:\Users\kailo\.Renviron`;
   confirmed live via `Sys.getenv("NFL_DISCORD_WEBHOOK")` returning a non-empty value (121 chars)
   and via an actual `run_notify_bets()` invocation reaching the `nzchar(webhook_url)` live-POST
   branch (lines ~169-183 of `notify_bets.R`) instead of the console-only fallback. That run
   produced no actual Discord POST only because every row in the current slate was
   insufficient-sample-gated (0 actionable bets) — the webhook-visibility bug itself is resolved.
2. **Staking is not validated as profitable at the ensemble/portfolio level.** Sharpe is
   negative for every deployed-formula candidate across every parameter grid tested this
   session (long-shot cap, market-blend weight, situational/Kalman/participation features) —
   real-money staking should stay paused. The one exception found (home-backup-QB market bias,
   see Recent work) is a narrow, single-signal result not yet validated to the same bar as a
   deployment decision requires.
3. **Stage 8/9.5 pipeline ordering gap.** `risk_management_engine.R` (stage 8) runs before
   `bet_tracker.r` (stage 9.5) grades new bets within the same invocation — one cycle behind.
   Not urgent while the ledger is empty. Not fixed this session (a larger, separately-reasoned
   reordering).
4. **Home-backup-QB market bias: already gate-checked and multiple-comparisons-corrected
   (`6e2126f`, backfilled into Recent work above after this doc was found to have never recorded
   it) — recommendation is HOLD, not "needs more validation."** Gate-aware Sharpe actually
   improves (0.0911 → 0.1066, n=217) so it's not a staking-gate artifact, but the corrected
   bucket-screening count is 14 (not "~8"), and at that count the raw p=0.00615 does NOT survive
   Bonferroni/BH correction at alpha=0.05. A true 2025-2026 holdout remains blocked — no
   depth-chart cache exists in this repo (`load_depth_charts()` is called live, never persisted).
   If you want to revisit deployment: either (a) persist a depth-chart cache so a genuine
   out-of-discovery-window holdout becomes possible as 2026 accumulates more weeks, or (b) treat
   the Bonferroni failure as disqualifying and drop it. Deriving asymmetric
   `HOME_QB_INJURY_PENALTY_PTS` / `AWAY_QB_INJURY_PENALTY_PTS` (replacing the single symmetric
   `QB_INJURY_RATING_PENALTY_PTS`, currently `1.6` per `config.R:321`) is still a reasonable next
   step technically, but shouldn't be read as "this finding just needs one more derivation step
   before shipping" — the multiple-comparisons result is a real caution, not a formality.
5. **Four competing NFL player-ID schemes** — HARDENED this session (`player_id_crosswalk.R`,
   commit `52b74a5`), but remains something any *future* player-level join must use rather than
   a fresh unverified `load_ff_playerids()` call.
6. **`load_participation()`** — STARTED and its Sharpe hypothesis DEBUNKED this session (see
   Recent work). The underlying data-availability limitation (never populated for
   `CURRENT_SEASON`) is permanent, not a bug to fix.
7. **Public bet-percentage/handle data** does not exist anywhere in this repo. A real, explicit,
   deferred paid-vendor decision for the market-disagreement project (Phase 2's "fade the
   public" angle) — not pursued without user sign-off on cost/ToS.
8. **`accuracy_tracker.R`'s Discord dispatch (#6) — FIXED 2026-10-05.** Previously verified only
   via a stubbed `httr::POST()`. A manual full-pipeline run live-POSTed a real season-accuracy
   embed to the real `NFL_DISCORD_WEBHOOK` channel and got back `status_code: 204` — same for
   `notify_bets.R`'s dispatch in the same run. HTTP-level success is confirmed by this agent;
   visual confirmation that the embed *rendered* correctly in the actual Discord channel has not
   been independently checked by an agent — worth a quick human glance, not re-verifiable by HTTP
   status alone.
9. **Windows Task Scheduler automation (issues #8/#9) — DONE in-repo 2026-10-05, but GitHub issues
   #8/#9 are still OPEN.** User signed off on task name `NFL_analytics_task_01` and trigger time
   5:15 AM ET; `schtasks /Create` ran successfully and `schtasks /Query /V` confirms `Status:
   Ready`, `Next Run Time: 10/5/2026 5:15:00 AM`. Nobody has closed #8/#9 on GitHub yet — flagging
   per this doc's own discrepancy-surfacing convention rather than closing them here. Issue #10
   (real-world validation) remains genuinely open regardless of #8/#9's tracker status.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed
  working: `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`, `ggplot2`, `knitr`,
  `rmarkdown`, `tinytex`. NOT installed: `lightgbm`, `rstan`/`cmdstanr`/`brms`/`rjags`,
  `kableExtra`.
- Quarto: **not on PATH** — the real binary is bundled with RStudio at
  `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`. Invoke via full path.
- Real credentials confirmed working: `ODDS_API_KEY`, `NFL_DISCORD_WEBHOOK` (fixed 2026-10-04 —
  moved from `C:\Users\kailo\Documents\.Renviron` to `C:\Users\kailo\.Renviron`; see Known Issue
  #1). `Sys.getenv("NFL_DISCORD_WEBHOOK")` returns a non-empty value as of this writing.
- Inline multi-line `Rscript -e '...'` has segfaulted before on this machine — write ad hoc R to
  a temp `.R` file under `tools/` (delete it after) rather than inlining.
- `glmnet::cv.glmnet()` calls anywhere in this repo need an explicit local seed — R's global RNG
  state is not something to rely on for reproducibility across separate script invocations here.
- `nflreadr`'s `dictionary_*` objects (e.g. `dictionary_schedules`) are lazy-loaded package
  *data*, not namespace functions — `nflreadr:::dictionary_schedules` fails; use
  `data(dictionary_schedules, package = "nflreadr")` first, discovered while fact-checking the
  market-disagreement project.
- `isTRUE()` is not vectorized in base R — using it inside `dplyr::case_when()`/`mutate()` over
  a vector column silently collapses every row to the fallback branch with no error. Use
  `x %in% TRUE` instead. A real bug found and fixed this session
  (`tools/market_disagreement_features.R`).
- `bind_rows(A, B) |> distinct(key, .keep_all = TRUE)` keeps the FIRST row per key — if `A` is a
  stale cache and `B` is a fresh fetch, put `B` first or you'll silently keep discarding real
  updates forever (this bit `daily_ingest.R`'s `.ingest_one()` this session — see Recent work).
  Checked `sync_rosters.R`/`injury_scraper.R` for the same pattern: neither merges against a
  persisted prior-run cache the way `.ingest_one()` does (both effectively rebuild fresh each
  run), so this is currently an isolated instance, not a repo-wide pattern — but re-check any
  NEW incremental-cache-merge code against this trap before trusting it.
- **`schtasks /Create`'s `/TR` argument needs literal backslash-quote sequences from PowerShell,
  not plain embedded double-quotes.** Both `/TR '"path" "path2"'` (single-quoted) and
  `$tr = "`"path`" `"path2`""` (backtick-escaped double-quoted) get re-split by argv parsing and
  fail with `ERROR: Invalid argument/option`. What worked: build the string with literal
  backslash-quote pairs — `$tr = '\"C:\Program Files\...\Rscript.exe\" \"...\run_full_pipeline.R\"'`
  (single-quoted so PowerShell doesn't touch the backslashes) — then pass `$tr` as the `/TR` value.
  Also: Git Bash mangles `schtasks /Create` (and any other leading-`/`-flag Windows CLI) because
  it rewrites `/Create` as a path — use the PowerShell tool for `schtasks`, not Bash.
- **Git-worktree isolation does NOT isolate `cache/*.rds` writes.** Every script in this repo
  `setwd()`s to the hardcoded absolute repo root (`C:\Users\kailo\kayceeslices\NFL Analytics`)
  rather than wherever it's actually being invoked from, so a script run from inside a git
  worktree (e.g. a `subagent-brief`-dispatched subagent's isolated worktree) still reads/writes
  the ONE real shared `cache/` directory, not a worktree-local copy. This bit this session's
  accuracy-tracker work directly — see "Recent work" above. If dispatching parallel subagents
  that run any cache-writing script, either have them use scratch copies of the specific `.rds`
  file under test (point a test harness at a copied path, not the real `CACHE_*` constant) or
  verify the real cache's content before and after merging each subagent's work.

## Suggested next steps, roughly in priority order

1. **Issue #10 (end-to-end scheduled validation) is next, but it's observational, not a coding
   task.** Watch `NFL_analytics_task_01` actually fire tomorrow (2026-10-05, 5:15 AM ET) and on a
   subsequent off day — `schtasks /Query /TN NFL_analytics_task_01 /V` shows `Last Run Time` /
   `Last Result` after it's fired at least once. Confirm idempotency (no duplicate Discord posts
   if run twice with no new completed games) and correct cadence. Consider closing GitHub issues
   #8/#9 at that point too (see "Known issues" #9 — they're done in-repo but still show OPEN).
2. **Decide what to do with the home-backup-QB market-bias finding (Known Issue #4).** It already
   has a HOLD recommendation from a gate-aware, multiple-comparisons-corrected re-check
   (`6e2126f`) that this doc had previously failed to surface — re-read that entry under "Recent
   work" before deciding whether a depth-chart-cache investment to enable a true 2025-2026 holdout
   is worth pursuing, or whether to drop the finding given the failed Bonferroni/BH correction.
3. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data
   angle needs an explicit user decision (new paid vendor or scraping project) before pursuing —
   not started pending that.
4. Consider fixing the stage 8/9.5 ordering gap (Known Issue #3) if a same-run-fresh ledger read
   ever becomes important — not urgent today since the ledger is empty anyway.
5. `player_props_engine.R`, team embeddings, a live dashboard (including the accuracy-trajectory
   dashboard tab explicitly deferred out of the current spec), and a true rstan/cmdstanr install
   for Phase 5's Bayesian state-space idea remain explicitly deferred non-goals — only start if
   there's a concrete pull for them.
