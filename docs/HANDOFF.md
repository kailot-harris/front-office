# NFL Analytics — Handoff Document

**Last updated**: 2026-10-05, after commit `61e2a90` ("Wire accuracy_tracker.R into
run_full_pipeline.R as stage 12"). Local `main` is **8 commits ahead of `origin/main`**
(`ee271ea`…`61e2a90`, confirmed via `git log origin/main..HEAD` — none of this session's work has
been pushed yet). `git status --short` is NOT clean: `docs/HANDOFF.md` (this file, updated this
session) is now modified, a new untracked `cache/accuracy_history.rds` exists (real content, see
below — not a stray test artifact), and nine `cache/*.rds` files show as modified — eight of those
predate this session (present at session start, unrelated to this session's work) plus
`cache/weekly_accuracy_report.rds` which this session's work legitimately regenerated (same
schema, new run timestamp). Written for a future LLM/agent picking this repo back up cold — read
this before touching anything, then read `CLAUDE.md` for environment/data-quirk details this doc
doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout, with two labeled exceptions: `risk_management_engine.R` reports
`SYNTHETIC_FALLBACK` (confirmed live, 2026-09-17) because the real bet ledger
(`CACHE_BETTING_LEDGER`, written by `bet_tracker.r`) is genuinely empty — no staked value bet
has cleared the early-season `MIN_SAMPLE_GAMES_FOR_STAKE` gate yet this season, not a bug — and
`notify_bets.R`'s Discord dispatch, while now wired up correctly (see Known Issues #1 — fixed
2026-10-04), still has nothing to actually post: every row in the current slate is still
`INSUFFICIENT SAMPLE (early season)`-gated, so live-fired runs hit the "0 actionable bets" no-op
path by design rather than reaching the POST call.

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

**If you're picking up the accuracy-trajectory monitoring work**, read
`docs/SPEC_accuracy_trajectory_monitoring.md` next, then jump to "Accuracy-trajectory monitoring
(issues #1-#7 shipped, #8-#10 remain)" below — issues #1-#7 (the entire in-repo implementation)
shipped this session; what's left is Windows Task Scheduler automation, which needs your
sign-off on a task name/trigger time before a future agent creates it.

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
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch wiring fixed 2026-10-04 (Known Issue #1) — live-POST branch confirmed reachable, but nothing has posted yet since the current slate is 100% `INSUFFICIENT SAMPLE`-gated |
| 11 | `accuracy_tracker.R` | `run_accuracy_tracker()` | `CACHE_ACCURACY_HISTORY` — NEW this session (issues #1-#7, see below). No `output` declared in its `run_stage()` call (deliberately — see that call site's comment): a legitimate no-new-games day is a clean no-op that doesn't touch the file, which `.check_stage_output()`'s staleness check would otherwise flag as a false-positive C-2 warning |

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
- **Status**: #1-#7 closed and merged to local `main` (not yet pushed — see header). `#6`'s Discord
  dispatch was verified by stubbing `httr::POST()`, not by an actual network call — no real
  `NFL_DISCORD_WEBHOOK` POST has been exercised against the accuracy-tracker's new payload yet
  (the webhook env var itself works fine for `notify_bets.R`, per Known Issue #1). `cache/
  accuracy_history.rds` currently has exactly 1 real row (2026 season, 48 games graded, 66.7%
  accuracy, Brier 0.2323 — matches `weekly_accuracy_report.rds`'s own numbers, as expected since
  both now share `grade_walkforward_games()`).

## Accuracy-trajectory monitoring (issues #1-#7 shipped, #8-#10 remain)

Full spec: `docs/SPEC_accuracy_trajectory_monitoring.md`. Summary: track the model's
season-to-date prediction accuracy over time (not just a one-off `weekly_accuracy_report.R` run)
via a persisted history cache plus Discord posts, triggered idempotently whenever new games
complete. Explicitly does NOT touch the staking gate (`MIN_SAMPLE_GAMES_FOR_STAKE` is a per-game
flag, not a single season-wide on/off event — this feature is independent of staking status) and
explicitly does NOT build a dashboard (`app.R` does not exist in this repo at all; that's deferred
to a separate future ticket if ever pursued).

Filed as 10 GitHub issues (`gh issue list --state all` to re-check current status). Native GitHub
sub-issue links are set for #2/#3 under #1, and #9/#10 under #8. **#1-#7 closed and merged this
session** (`ee271ea`…`61e2a90`, not yet pushed to `origin`); **#8-#10 remain open** and need your
input, not a subagent, before proceeding (see below).

| Issue | Title | Depends on | Status |
|---|---|---|---|
| [#1](https://github.com/kailot-harris/NFL_analytics/issues/1) | Extract shared walk-forward grading logic (parent) | — | CLOSED |
| [#2](https://github.com/kailot-harris/NFL_analytics/issues/2) | Sub-issue: extract `grade_walkforward_games()` into `tools/backtest_common.R` | — | CLOSED — `tools/backtest_common.R:300-389` |
| [#3](https://github.com/kailot-harris/NFL_analytics/issues/3) | Sub-issue: update `tools/weekly_accuracy_report.R` to call it | #2 | CLOSED |
| [#4](https://github.com/kailot-harris/NFL_analytics/issues/4) | `CACHE_ACCURACY_HISTORY` constant + history-row schema in `config.R` | informed by #2, can start in parallel | CLOSED — `config.R:560`, helpers `tools/backtest_common.R:191-266` |
| [#5](https://github.com/kailot-harris/NFL_analytics/issues/5) | Build `accuracy_tracker.R` / `run_accuracy_tracker()` core (detect new completed games, append to history; no Discord yet) | #2, #4 | CLOSED — `accuracy_tracker.R` (repo root) |
| [#6](https://github.com/kailot-harris/NFL_analytics/issues/6) | Add Discord dispatch to `accuracy_tracker.R` (reuses `NFL_DISCORD_WEBHOOK`, same channel as `notify_bets.R`) | #5 | CLOSED — payload construction verified via stubbed `POST()`; **live webhook POST itself not yet exercised** (no real webhook call made — see Known Issues) |
| [#7](https://github.com/kailot-harris/NFL_analytics/issues/7) | Wire `accuracy_tracker.R` into `run_full_pipeline.R` as stage "12" (file comment says "11.", see pipeline table above) | #5, #6 | CLOSED — `run_full_pipeline.R:307-308` |
| [#8](https://github.com/kailot-harris/NFL_analytics/issues/8) | Automate daily execution via Windows Task Scheduler (parent) | #7 | OPEN — **needs your sign-off on task name/trigger time before creating**, per the issue's own explicit "confirm with the user" note |
| [#9](https://github.com/kailot-harris/NFL_analytics/issues/9) | Sub-issue: create scheduled-task wrapper script + job definition | #7 | OPEN — blocked on #8's sign-off |
| [#10](https://github.com/kailot-harris/NFL_analytics/issues/10) | Sub-issue: validate end-to-end (idempotency + real daily cadence) | #9 | OPEN — inherently can't be done in one sitting; requires observing the scheduled task fire across at least one real game day and one real off day |

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
4. **Home-backup-QB market bias needs more validation before any deployment consideration**
   (see Recent work's last entry): check against `MIN_SAMPLE_GAMES_FOR_STAKE`/
   `LONGSHOT_DECIMAL_ODDS_CAP`, account for multiple-comparisons risk (it was the standout of 8
   screened buckets), and ideally hold out 2025-2026 data rather than reusing the discovery
   window. The natural next step if pursued: derive separate `HOME_QB_INJURY_PENALTY_PTS` /
   `AWAY_QB_INJURY_PENALTY_PTS` (replacing the single symmetric `QB_INJURY_RATING_PENALTY_PTS`)
   via `stats::optimize()` against Sharpe, then re-run the full comparison harness.
5. **Four competing NFL player-ID schemes** — HARDENED this session (`player_id_crosswalk.R`,
   commit `52b74a5`), but remains something any *future* player-level join must use rather than
   a fresh unverified `load_ff_playerids()` call.
6. **`load_participation()`** — STARTED and its Sharpe hypothesis DEBUNKED this session (see
   Recent work). The underlying data-availability limitation (never populated for
   `CURRENT_SEASON`) is permanent, not a bug to fix.
7. **Public bet-percentage/handle data** does not exist anywhere in this repo. A real, explicit,
   deferred paid-vendor decision for the market-disagreement project (Phase 2's "fade the
   public" angle) — not pursued without user sign-off on cost/ToS.
8. **`accuracy_tracker.R`'s Discord dispatch (#6) has never made a real network POST.** Verified
   only via a stubbed `httr::POST()` in a worktree test harness. The payload-construction logic is
   independently confirmed correct, but a live end-to-end post to the real `NFL_DISCORD_WEBHOOK`
   channel has not happened. Low risk (it's the exact same POST pattern `notify_bets.R` already
   uses live), but don't assume it's been seen in the actual Discord channel until it has.
9. **Windows Task Scheduler automation (issues #8-#10) is not started**, and issue #8's own text
   explicitly says not to create the scheduled task silently — it needs your confirmation on the
   exact task name and daily trigger time first (the spec suggests "once daily in the
   evening/late night" to catch all of that day's completed games, but wants explicit sign-off
   since it determines Discord-update freshness on game days).

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

1. **Get the user's sign-off on GitHub issue [#8](https://github.com/kailot-harris/NFL_analytics/issues/8)'s
   task name and daily trigger time**, then pick up [#9](https://github.com/kailot-harris/NFL_analytics/issues/9)
   (scheduled-task wrapper script + `schtasks` job definition) — this is the next unimplemented
   piece of the accuracy-trajectory monitoring work. Do not create the Task Scheduler entry
   without that confirmation; issue #8's own text says so explicitly.
2. Once #9 is live, #10 (end-to-end validation) is an observational task, not a one-sitting
   coding task — it requires watching the scheduled task actually fire across at least one real
   game day and one real off day, confirming idempotency and correct Discord cadence both times.
3. Commit the currently-uncommitted work described in this doc's header (`docs/HANDOFF.md` itself)
   and decide what to do with the modified `cache/*.rds` files — eight predate this session, one
   (`weekly_accuracy_report.rds`) was legitimately regenerated this session, and
   `cache/accuracy_history.rds` is a new real file (1 row, not a test artifact — see "Recent work"
   above) that should probably be committed rather than left untracked, since every other
   `CACHE_*` file in this repo is tracked.
4. `git push` once committed — local `main` is 8 commits ahead of `origin/main` as of this
   writing; confirm with `git log origin/main..HEAD` before pushing since the count will drift.
5. Exercise `accuracy_tracker.R`'s Discord dispatch against the real `NFL_DISCORD_WEBHOOK` at
   least once (Known Issue #8) — it has only been verified via a stubbed `POST()` so far.
6. Validate or reject the home-backup-QB market bias (Known Issue #4) — the one credible
   positive-Sharpe finding from a prior session. Check it against the real production staking
   gates, then either derive asymmetric QB-injury-penalty constants and re-run the comparison
   harness, or let it season against 2025-2026 data as a true holdout before deciding.
7. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data
   angle needs an explicit user decision (new paid vendor or scraping project) before pursuing —
   not started pending that.
8. Consider fixing the stage 8/9.5 ordering gap (Known Issue #3) if a same-run-fresh ledger read
   ever becomes important — not urgent today since the ledger is empty anyway.
9. `player_props_engine.R`, team embeddings, a live dashboard (including the accuracy-trajectory
   dashboard tab explicitly deferred out of the current spec), and a true rstan/cmdstanr install
   for Phase 5's Bayesian state-space idea remain explicitly deferred non-goals — only start if
   there's a concrete pull for them.
