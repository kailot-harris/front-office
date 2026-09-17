# NFL Analytics — Handoff Document

**Last updated**: 2026-09-17. Most recent commit on disk is `aa990e4` ("Add write-handoff-doc
skill; regenerate docs/HANDOFF.md as a full rewrite"), but **this rewrite documents real,
verified, UNCOMMITTED work on top of that commit** (see `git status --short` — a future agent
should run that itself before trusting this doc's "current state" claims at face value, and
should commit or discard this work deliberately rather than assuming it's already landed).
Written for a future LLM/agent picking this repo back up cold — read this before touching
anything, then read `CLAUDE.md` for environment/data-quirk details this doc doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout, with two labeled exceptions: `risk_management_engine.R` falls back to a
`SYNTHETIC_FALLBACK` seed ledger only when its real ledger (see below — this changed this
session) has zero RESOLVED bets, and `notify_bets.R`'s Discord dispatch is still
console-only-preview (webhook env var not visible to R on this machine — see Known Issues).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

## Current state: 11-stage pipeline

Runs end-to-end against real data. `run_full_pipeline.R`'s `run_stage()` sources each stage
in-process (`call_fn`-style, no auto-run guards) and asserts every declared output's mtime
advanced (`.check_stage_output()`, WARN not fatal, `gc()` after every stage).

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (20-column whitelist), `CACHE_SCHEDULES` |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — ridge+Elo ensemble, QB-adjusted, market-blended `home_win_prob` |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — simplified tiebreak (win% + alphabetical) |
| 8 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — now reads the real ledger (stage 9.5) when it has RESOLVED bets, else `SYNTHETIC_FALLBACK` |
| 9 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real Odds API odds; staking now gated by both `MIN_SAMPLE_GAMES_FOR_STAKE` and the new `LONGSHOT_DECIMAL_ODDS_CAP` (see below) |
| 9.5 | `bet_tracker.r` | `run_bet_tracker()` | **NEW this session.** `CACHE_BETTING_LEDGER` — real bet ledger, writer+grader |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch, still console-only-preview |

Stage 9.5 runs after stage 9 (needs its output to record today's picks) but before stage 10.
**Known ordering gap**: stage 8 (risk management) still runs *before* stage 9.5 grades new bets
within the same pipeline invocation, so a freshly-graded ledger only affects stage 8's
`REAL_LEDGER` read on the *next* pipeline run, one cycle behind — documented in
`run_full_pipeline.R`'s stage-9.5 comment rather than fixed by reordering stages this session
(a larger, separately-reasoned change).

## Build history (chronological)

| Commit | What it added |
|---|---|
| `9155ad1`…`105eb8e` | Phases 1-7: ingestion, EPA/ratings engines, fatigue engine, playoff sim, risk engine, market odds engine, Discord dispatcher. |
| `d1c90aa`, `83682a5` | Phase 8: early-season rating shrinkage + minimum-sample staking gate, then backtested (found Sharpe negative at every threshold — the finding that triggered the model-quality remediation below). |
| `7092bad`…`050aebe` | Model-quality remediation Phases A-4: market blend, QB-injury penalty, ridge Massey rating, MOV-weighted Elo, ridge+Elo ensemble (deployed), GBM stacking (negative result, not deployed). |
| `bb1cd99` | Fixed two `run_full_pipeline.R` OS-kills (`CACHE_PBP` column trim + inter-stage `gc()`). |
| `aa990e4` | Added `write-handoff-doc` skill; full HANDOFF.md rewrite. |
| *(uncommitted, this session)* | Investigated and mitigated Known Issue #5 (long-shot EV clustering); found and fixed a real ridge-model non-determinism bug; built `bet_tracker.r` closing Known Issue #2. See "Recent work" below. |

## Recent work

### Long-shot EV clustering investigation + `LONGSHOT_DECIMAL_ODDS_CAP` (uncommitted, 2026-09-17)

`tools/investigate_ev_clustering.R` (new, permanent analysis tool) confirmed docs/HANDOFF.md's
prior Known Issue #5 against the production `ensemble_ridge_elo` formula: 100% of Kelly-positive
bets at the production staking gate were underdogs, with mean EV% *increasing* as model
probability *decreased* (2.26% in the [0,0.1] probability bin vs. 0.46% in [0.4,0.5]), and 29%
clustering in week 17 alone. Root cause identified: `home_ev = model_prob * decimal_odds - 1`,
and since `MARKET_BLEND_WEIGHT=0.97` anchors the model probability almost entirely to the same
game's own market price used to derive `decimal_odds`, the apparent edge is really the model's
remaining 3% disagreement with the market — a roughly fixed absolute probability delta that gets
amplified multiplicatively by decimal odds, which are largest exactly for long-shot underdogs.
Mitigation: `LONGSHOT_DECIMAL_ODDS_CAP <- 9.7` (config.R), backtested via
`tools/derive_longshot_odds_cap.R` (Sharpe -0.1461 uncapped -> -0.0809 at the optimal cap, n=56
walk-forward bets, seasons 2010-2025) and wired into `market_odds_engine.R`'s staking gate.
- **Result**: roughly halves cumulative backtested loss vs. no cap; Sharpe remains NEGATIVE at
  every cap value tested (see `config.R`'s own constant comment) — this is a mitigation, not a
  validated edge. Real-money staking should stay paused regardless (Known Issue #4, unchanged).
- **Status**: deployed (wired into `market_odds_engine.R`'s `evaluate_betting_slate()`).
- **Full detail**: `tools/investigate_ev_clustering.R`'s own output, `config.R`'s
  `LONGSHOT_DECIMAL_ODDS_CAP` comment, `cache/longshot_odds_cap_derivation.rds`.

### Real bug found during that investigation: `ridge_massey_model.R` non-determinism (uncommitted, 2026-09-17)

While backtesting the odds cap, two back-to-back runs of the *identical* production formula over
identical data produced 124 vs. 56 Kelly-positive bets and Sharpe -0.0816 vs. -0.1511. Root
cause: `fit_ridge_massey()`'s `glmnet::cv.glmnet()` call assigns its 5 CV folds via R's global
RNG with no seed set anywhere in that file or its callers — every model refit (once per season,
~16-23 times per full walk-forward run, and also live in `team_ratings_engine.R`'s production
ratings) was silently non-reproducible. Fixed with a `set.seed(20260917)` local to
`fit_ridge_massey()` (reset on every call, not relying on caller RNG state).
- **Result**: re-running `tools/derive_longshot_odds_cap.R` twice after the fix gave identical
  n=56, Sharpe=-0.1461 both times — confirmed reproducible.
- **Status**: fixed (`tools/ridge_massey_model.R`). **Caveat for future work**: any earlier
  Brier/Sharpe figure elsewhere in this repo that used the ridge model
  (`ridge_only`/`ridge_phase1_combined`/`ensemble_ridge_elo` in
  `tools/model_backtest_harness.R`, including the Phase 2-4 comparison table cited in this doc's
  prior revisions) was computed under the old non-deterministic behavior. Those figures were NOT
  re-run this session (out of scope) — treat them as approximate, not exact, until re-verified.
- **Full detail**: `tools/ridge_massey_model.R`'s `fit_ridge_massey()` comment.

### Real bet ledger: `bet_tracker.r` (uncommitted, 2026-09-17)

Closes Known Issue #2. New `bet_tracker.r`, ported from the WNBA sibling's `bet_tracker.r` with
two deliberate deviations driven by this repo's stricter provenance conventions: (1) cold-starts
with an **empty** ledger rather than WNBA's fabricated 60-bet seed ledger — mixing fake
RESOLVED bets into a ledger `risk_management_engine.R` reads as `REAL_LEDGER` would be exactly
the kind of provenance-loss bug this repo's `SYNTHETIC_FALLBACK`/`market_data_source` markers
exist to prevent elsewhere; the existing (previously-dead) "real ledger has zero RESOLVED bets ->
fall through to synthetic" branch in `risk_management_engine.R` already handles an empty ledger
correctly. (2) only records picks tagged `market_data_source == "LIVE_ODDS_API"`, never a
`SYNTHETIC_FALLBACK` fixture pick. Grades PENDING bets by joining `(team_picked, bet_date)`
against `CACHE_SCHEDULES` (pivoted to long form), computing WIN/LOSS, `profit_units`, and an
approximate CLV (against the bet-time consensus snapshot, not a true kickoff closing line — same
documented limitation WNBA's version has). Added as pipeline stage 9.5, and `config.R` gained
`CACHE_BETTING_LEDGER` (`risk_management_engine.R`'s header had already promised this exact
constant name once a real ledger existed).
- **Result**: end-to-end smoke-tested against a real historical game (BAL @ CAR, 2002-09-08):
  pick recorded PENDING, graded WIN with correct `profit_units`/`clv_pct`, and
  `risk_management_engine.R` correctly switched to `data_source="REAL_LEDGER"`. Test data was
  injected into a backed-up copy of the caches and fully reverted afterward — the real
  `cache/betting_ledger.rds` on disk is genuinely empty (0 rows), not seeded with fake bets.
- **Status**: deployed (`bet_tracker.r`, wired into `run_full_pipeline.R` as stage 9.5). Ledger
  will remain empty until a real slate produces a `LIVE_ODDS_API` pick with `Bankroll_Rec > 0`
  (currently blocked by early-season `MIN_SAMPLE_GAMES_FOR_STAKE` gating — see current
  `cache/latest_value_bets.rds`, every row is `INSUFFICIENT SAMPLE` as of this session).
- **Full detail**: `bet_tracker.r`'s own header comment.

## Known issues / unfinished business

1. **`NFL_DISCORD_WEBHOOK` not visible to R.** Set in `C:\Users\kailo\Documents\.Renviron`, but
   R's user-Renviron lookup resolves to `C:\Users\kailo` directly on this machine. **Fix**: move
   the line into `C:\Users\kailo\.Renviron`, or set it as a Windows env var.
2. ~~`risk_management_engine.R` has no real ledger~~ **CLOSED this session** — `bet_tracker.r`
   now exists and writes `CACHE_BETTING_LEDGER`; see "Recent work" above. The ledger is currently
   empty (no real staked picks yet this season) so `risk_management_engine.R` still reports
   `SYNTHETIC_FALLBACK` in practice until that changes — this is the correct, honest behavior of
   the now-real cold-start path, not a bug.
3. **Playoff seeding uses a simplified tiebreak** (win% + alphabetical), not the NFL's real
   multi-step procedure. Unchanged this session.
4. **Staking is not validated as profitable.** Sharpe remains negative at every staking
   threshold and every long-shot odds cap tested (see "Recent work" above) — real-money staking
   should stay paused regardless of any mitigation shipped this session.
5. ~~Kelly-positive bets cluster in long-shot underdogs / week 17~~ **INVESTIGATED AND MITIGATED
   this session** — see "Recent work" above (`LONGSHOT_DECIMAL_ODDS_CAP`). Root cause understood
   and documented; mitigation reduces but does not eliminate the underlying issue (the model's
   probability estimates are still noisiest in exactly the games most affected — backup QBs,
   rested starters, week 17).
6. **Four competing NFL player-ID schemes** (ESPN/GSIS/PFR/NFL-NGS) remain a real risk for any
   FUTURE player-level join beyond the QB-backup feature already built. `nflreadr::
   load_ff_playerids()` is the canonical crosswalk if a future feature ever mixes ID schemes.
7. **`load_participation()` 2023+ is historical-only** (FTN-sourced, released only after the
   postseason completes) — still unstarted, still correctly unused anywhere in the pipeline.
8. **NEW: any ridge-model-derived backtest figure computed before this session's `set.seed()`
   fix should be re-verified, not cited as exact** — see "Recent work" above. This includes the
   Phase 2-4 model-comparison table figures for `ridge_only`/`ridge_phase1_combined`/
   `ensemble_ridge_elo` cited in earlier revisions of this doc/in `docs/task_assignments_*.md`.
   Re-running `tools/model_backtest_harness.R` for a corrected table is unstarted.
9. **This session's work is uncommitted.** Run `git status --short` and commit (or discard)
   deliberately before starting new work — do not assume the "Recent work" items above are
   already part of the repo's committed history.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed working:
  `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`. NOT installed: `lightgbm`,
  `rstan`/`cmdstanr`/`brms`/`rjags`.
- Real credentials confirmed working: `ODDS_API_KEY`. `NFL_DISCORD_WEBHOOK` is set by the user
  but not currently visible to R (Known Issue #1).
- Inline multi-line `Rscript -e '...'` has segfaulted before on this machine — write ad hoc R to
  a temp `.R` file under `tools/` (delete it after) rather than inlining. This session's
  smoke-tests for `bet_tracker.r` followed that convention (backed up/restored real cache files
  around the test, deleted the temp script after).
- `glmnet::cv.glmnet()` calls anywhere in this repo need an explicit local seed (see the
  `ridge_massey_model.R` fix above) — R's global RNG state is not something to rely on for
  reproducibility across separate script invocations in this environment.

## Suggested next steps, roughly in priority order

1. **Commit this session's uncommitted work** (or explicitly decide to discard parts of it) —
   see Known Issue #9.
2. Fix the `NFL_DISCORD_WEBHOOK` visibility issue (5-minute user-side fix, unblocks real
   notifications).
3. Re-run `tools/model_backtest_harness.R` for a corrected Phase 2-4 comparison table now that
   `ridge_massey_model.R` is deterministic (Known Issue #8) — the previous table's ridge-involving
   rows were computed under non-deterministic CV fold assignment.
4. Consider fixing the stage 8/9.5 ordering gap noted in "Current state" above (risk management
   runs before the same-run's bet grading) if a same-run-fresh ledger read ever becomes
   important — not urgent today since the ledger is empty anyway.
5. If reviving Phase 4/5 model work: `gbm_stack` is a working harness candidate to retry with a
   rolling multi-season validation window; Phase 5 (Bayesian state-space) needs an Rtools/rstan
   install decision first, or a pure-R closed-form Kalman-filter alternative.
6. `player_props_engine.R`, team embeddings, a live dashboard remain explicitly deferred
   non-goals — only start if there's a concrete pull for them.
