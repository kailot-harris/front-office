# NFL Analytics — Handoff Document

**Last updated**: 2026-09-17, after commit `050aebe` ("Model-quality remediation Phase 4:
gradient-boosted trees stacking (negative result)"). Written for a future LLM/agent picking this
repo back up cold — read this before touching anything, then read `CLAUDE.md` for
environment/data-quirk details this doc doesn't repeat. This is a full rewrite (via
`.claude/skills/write-handoff-doc`), not an appended update — every number below was re-checked
against current `config.R`/cache state rather than carried forward from an earlier draft.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout, with two explicitly-labeled exceptions: `risk_management_engine.R` still
falls back to a `SYNTHETIC_FALLBACK` seed ledger (no real bet-tracking ledger exists yet), and
`notify_bets.R`'s Discord dispatch is still console-only-preview (webhook env var not visible to
R on this machine — see Known Issues).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from (data-source decisions, coverage
windows, ID-crosswalk risk, playoff-bracket structure). Re-verify anything date-sensitive before
trusting it blindly for new work; nflverse/vendor details shift over time.

## Current state: 10-stage pipeline

Runs end-to-end against real data. `run_full_pipeline.R`'s `run_stage()` sources each stage
in-process (`call_fn`-style, no `sys.nframe()`/`!interactive()` auto-run guards — deliberate,
avoids a documented WNBA-repo silent-no-op bug class) and asserts every declared output's mtime
advanced (`.check_stage_output()`, WARN not fatal). A `gc()` now runs after every stage (added
2026-09-17, see "Recent work" below).

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (1.14M+ rows, **now trimmed to a 20-column whitelist, ~16MB on disk** — see memory fix below), `CACHE_SCHEDULES` |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` — rolling per-team EPA/play, success rate, CPOE |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — **the production model changed substantially this session, see below; `home_win_prob` is now a ridge+Elo ensemble, QB-adjusted, market-blended** |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` — real rest-days/travel/circadian/altitude metrics |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — Monte Carlo bracket sim, simplified tiebreak (win% + alphabetical, not the NFL's real procedure) |
| 8 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — **still `SYNTHETIC_FALLBACK`**, no real bet ledger exists |
| 9 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real Odds API odds; consumes stage 5's `projected_margin` (see the bug fix below — this now correctly reflects every upstream adjustment) |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch, **still console-only-preview** (webhook not visible to R — Known Issue #1, unresolved) |

## Build history (chronological)

| Commit | What it added |
|---|---|
| `9155ad1`…`105eb8e` | Phases 1-7: ingestion, EPA/ratings engines, fatigue engine, playoff sim, risk engine, market odds engine, Discord dispatcher. See `docs/task_assignments_phase0.md`-`phase7.md` for per-phase detail (file numbers are offset by one from content-phase numbers — Phase 0 was scaffold/config work that predated the task-assignments convention). |
| `d1c90aa` | Phase 8: early-season rating shrinkage (`RATING_SHRINKAGE_GAMES_K`) + minimum-sample staking gate (`MIN_SAMPLE_GAMES_FOR_STAKE`) — both hand-picked heuristics at this point. |
| `83682a5` | Backtested those two Phase 8 constants for the first time (`tools/backtest_shrinkage_optimizer.R`, walk-forward, `stats::optimize()`). Found the model's Sharpe was negative at every staking threshold against real 2010+ closing lines — the finding that triggered everything below. |
| `7092bad` | **Phase A + Phase 1** of a model-quality remediation roadmap (research-backed, literature-grounded — see "Recent work"): generalized the backtest into `tools/model_backtest_harness.R`; added `MARKET_BLEND_WEIGHT`/`QB_INJURY_RATING_PENALTY_PTS`. |
| `6a57752` | **Phase 2**: ridge-regularized Massey rating (`tools/ridge_massey_model.R`) replacing the hand-tuned shrinkage blend. |
| `2e387ce`, `e250764` | **Phase 3**: MOV-weighted Elo (`tools/elo_model.R`), investigated and deployed as a 50/50 ridge+Elo ensemble. `e250764` also fixed a real bug (see below). |
| `050aebe` | **Phase 4**: gradient-boosted trees stacking attempt — negative result, not deployed. |
| `bb1cd99` | Fixed two `run_full_pipeline.R` OS-kills (low memory) — `CACHE_PBP` column trim + inter-stage `gc()`. |

## Recent work

### Model-quality remediation, Phases A–4 (commits `7092bad`…`050aebe`, 2026-09-17)

Triggered by `83682a5`'s finding (Sharpe negative at every staking threshold). A research
subagent surveyed the sports-forecasting literature and produced a ranked candidate list; a
planning subagent turned that into a phased plan. Summary of what shipped, walk-forward Brier
score as the headline comparison metric throughout (`tools/model_backtest_harness.R`, 2003-2025,
n=5,548 games; full table in `cache/model_comparison_backtest.rds`):

| Candidate | Brier | Status |
|---|---|---|
| `baseline_k3.6` (original formula) | 0.2456 | superseded |
| `market_blend_only` | 0.2167 | superseded |
| `phase1_combined` (market blend + QB penalty) | 0.2168 | superseded |
| `ridge_only` | 0.2318 | superseded |
| `ridge_phase1_combined` | 0.2151 | superseded (was production after Phase 2) |
| `elo_mov` | 0.2211 | harness-only |
| `elo_phase1_combined` | 0.2121 | harness-only (best single-model Brier, but a real Sharpe regression — see below) |
| **`ensemble_ridge_elo`** | **0.2130** | **DEPLOYED — current production formula** |
| `gbm_stack` (Phase 4) | 0.2417 | negative result, not deployed |

- **Phase A**: extracted `tools/backtest_shrinkage_optimizer.R`'s walk-forward game-table builder
  into `tools/backtest_common.R` (regression-checked identical output) so
  `tools/model_backtest_harness.R` could reuse it as a pluggable, multi-candidate comparison
  harness (Brier/log-loss/calibration primary; accuracy/precision/recall/F1/AUC secondary,
  explicit threshold=0.5/positive-class="home win"; Sharpe/ROI vs. real closing lines).
- **Phase 1**: `MARKET_BLEND_WEIGHT = 0.97` and `QB_INJURY_RATING_PENALTY_PTS = 1.6`, both derived
  via `stats::optimize()` (see `config.R`'s own comments for exact derivation figures — the market
  blend alone dropped Brier from 0.2433 to 0.2105 on its own 2010-2025 window, the largest single
  improvement found). First player-level join in this repo
  (`tools/qb_injury_features.R`) — turned out not to need an ID crosswalk since
  `nflreadr::load_depth_charts()` is already gsis_id-keyed like everything else it joins against.
- **Phase 2**: `tools/ridge_massey_model.R` — `glmnet::cv.glmnet(alpha=0)` replacing the hand-tuned
  `RATING_SHRINKAGE_GAMES_K` blend with a learned, per-season-refit regression.
- **Phase 3**: `tools/elo_model.R` — MOV-weighted Elo (`ELO_K_FACTOR = 28`, derived; HCA/MOV-shape
  constants are FiveThirtyEight literature references, not independently re-derived — flagged in
  that file's header as a deliberate exception). Elo alone beat ridge on calibration but showed an
  apparent Sharpe regression (-0.1461 vs. ridge's -0.0128 at the production staking gate); a
  bootstrap investigation (5,000 resamples) found both candidates' 90% Sharpe CIs were wide and
  overlapping — not a real distinguishable effect at that sample size (n=86 vs. n=259) — so the
  50/50 ridge+Elo ensemble was deployed instead of discarding Elo's calibration gain.
- **Real bug found and fixed in the same pass** (`e250764`): `market_odds_engine.R` was reading
  `projected_margin` and re-deriving its own probability, never actually consuming the
  market-blended `home_win_prob` — meaning Phase 1's market blend never reached the live
  betting-slate EV math at all, silently, since it landed. Fixed by making `projected_margin` and
  `home_win_prob` self-consistent by construction (`projected_margin` is now
  `qnorm(home_win_prob) * NFL_MARGIN_SIGMA`). Verified live.
- **Phase 4** (`050aebe`): xgboost stacking on ridge+Elo margins — Brier 0.2417, AUC 0.6460 (worse
  than doing nothing). Calibration table showed 91% of predictions collapsed into a single
  `[0.5,0.6)` bin — consistent with the plan's own predicted overfitting risk at this repo's data
  scale. Documented negative result, `gbm_stack` remains a harness candidate for a future retry
  with a different tuning strategy.
- **Phase 5** (Bayesian state-space) was scoped as a research-spike-only item in the original
  plan, gated on MCMC tooling being installable. Checked: `rstan`/`cmdstanr`/`brms`/`rjags` are
  all NOT installed in this environment (would need an Rtools toolchain setup). Not attempted —
  left as an open, reserved-not-committed item.
- **Full detail**: `git show 7092bad`, `6a57752`, `2e387ce`, `e250764`, `050aebe`.

### Pipeline memory fix (`bb1cd99`, 2026-09-17)

Two `run_full_pipeline.R` runs were killed by the OS for low memory, both inside
`daily_ingest.R`'s `bind_rows(existing, new_rows)` for `CACHE_PBP`. Root cause: `nflreadr::
load_pbp()` returns 372 columns/play; the full object was 3.4GB in memory for 1.14M rows, while
`epa_metrics_engine.R` (its only real consumer) touches 9 of them. Fixed: `.PBP_CACHE_COLUMNS`
whitelist (20 columns, ~167MB in memory, ~95% reduction) in `daily_ingest.R`, self-heals the
on-disk cache to the smaller shape automatically; `gc()` added after every pipeline stage. A full
pipeline run afterward completed in 64.19s (vs. ~150-190s before, and vs. two OS-kills).
`docs/memory_optimization_plan.md` documents three further, unimplemented options (avoid
`daily_ingest.R`'s remaining structural double-copy; migrate `CACHE_PBP` to a lazy duckdb/parquet
table; run memory-heavy stages as separate subprocesses) with approach/risk/verification plans
for each. **Full detail**: `git show bb1cd99`, `docs/memory_optimization_plan.md`.

## Known issues / unfinished business

1. **`NFL_DISCORD_WEBHOOK` not visible to R.** Set in `C:\Users\kailo\Documents\.Renviron`, but
   R's user-Renviron lookup resolves to `C:\Users\kailo` directly on this machine. **Fix**: move
   the line into `C:\Users\kailo\.Renviron`, or set it as a Windows env var. Verified end-to-end
   on the no-webhook path already — will dispatch for real with no code changes once visible.
2. **`risk_management_engine.R` has no real ledger** — falls back to a labeled
   `SYNTHETIC_FALLBACK` 120-bet seed ledger every run. Building a real `bet_tracker.r` is
   unstarted.
3. **Playoff seeding uses a simplified tiebreak** (win% + alphabetical), not the NFL's real
   multi-step procedure. Documented in `playoff_simulator.R`'s header and the cache's
   `seeding_method` field.
4. **Staking is not validated as profitable.** The production ensemble (`ensemble_ridge_elo`) has
   Brier 0.2130 (real calibration improvement over every prior formula) but Sharpe at the
   production staking gate (`MIN_SAMPLE_GAMES_FOR_STAKE = 9`) is still negative (-0.0128, per the
   last full harness run). `MIN_SAMPLE_GAMES_FOR_STAKE`'s own `config.R` comment says real-money
   staking should stay paused until a model version is separately backtested to real, positive
   Sharpe — that has not happened yet for any candidate tried so far.
5. **A real EV/Kelly-logic pattern worth a future look, found during Phase 3's bootstrap
   investigation, not yet fixed**: essentially all Kelly-positive bets across every candidate
   tested are long-shot underdogs (~20-30% model win probability, ~18-19% actual win rate),
   clustering heavily in week 17 (rest-players/meaningless-late-season-game noise). This looks
   like a structural quirk of the current EV computation finding "value" in exactly the
   highest-variance, least-reliable part of the slate.
6. **Four competing NFL player-ID schemes** (ESPN/GSIS/PFR/NFL-NGS) remain a real risk for any
   FUTURE player-level join beyond the QB-backup feature already built (which turned out not to
   need a crosswalk — `load_depth_charts()`/`CACHE_ROSTERS`/`CACHE_INJURY_DATA` are all
   gsis_id-keyed). `nflreadr::load_ff_playerids()` is the canonical crosswalk if a future feature
   ever does mix ID schemes (e.g. anything ESPN-athlete-ID-keyed) — see CLAUDE.md.
7. **`load_participation()` 2023+ is historical-only** (FTN-sourced, released only after the
   postseason completes) — not usable for any live in-season feature. Still unstarted, still
   correctly unused anywhere in the pipeline.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed working
  this session: `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`. NOT installed:
  `lightgbm`, `rstan`/`cmdstanr`/`brms`/`rjags` (relevant only if reviving the Phase 4 GBM retry
  or attempting Phase 5).
- Real credentials confirmed working: `ODDS_API_KEY`. `NFL_DISCORD_WEBHOOK` is set by the user but
  not currently visible to R (Known Issue #1).
- Inline multi-line `Rscript -e '...'` has segfaulted before on this machine — write ad hoc R to a
  temp `.R` file under `tools/` (delete it after) rather than inlining.
- This session ran `run_full_pipeline.R` in the background more than once and had it killed by the
  OS for low memory before the fix in `bb1cd99` landed — if a future run gets killed again, check
  `docs/memory_optimization_plan.md` before assuming the `bb1cd99` fix regressed; more likely
  cause is a genuinely larger concurrent memory load (many R sessions, browser tabs, etc.) than
  the pipeline itself re-growing past the fixed footprint.

## Suggested next steps, roughly in priority order

1. Fix the `NFL_DISCORD_WEBHOOK` visibility issue (5-minute user-side fix, unblocks real
   notifications).
2. ~~Backtest `RATING_SHRINKAGE_GAMES_K`/`MIN_SAMPLE_GAMES_FOR_STAKE`~~ done `83682a5`.
   ~~Build a model-comparison harness and try literature-backed model improvements~~ done
   `7092bad`-`050aebe` (Phases A-4; Phase 5 reserved, not attempted — see Known Issue #4, staking
   still not validated as profitable even after all of this).
3. Investigate the week-17/long-shot-clustering EV pattern (Known Issue #5) — plausibly a bigger
   lever on real staking performance than another rating-model iteration.
4. Build a real `bet_tracker.r` so `risk_management_engine.R` has a real ledger (Known Issue #2).
5. If reviving Phase 4/5: `gbm_stack` is a working harness candidate to retry with a rolling
   multi-season validation window instead of single-season early stopping; Phase 5 needs an
   Rtools/rstan install decision first, or a pure-R closed-form Kalman-filter alternative (the
   historically-accurate implementation of Glickman & Stern's original model, avoiding the MCMC
   dependency entirely).
6. `player_props_engine.R`, team embeddings, a live dashboard remain explicitly deferred
   non-goals from the original replication plan — only start if there's a concrete pull for them.
