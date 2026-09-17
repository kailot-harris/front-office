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

### Model-comparison harness re-run post-determinism-fix (uncommitted, 2026-09-17)

Re-ran `tools/model_backtest_harness.R` (unchanged) now that `ridge_massey_model.R` is
deterministic. Full comparison table (Brier/log-loss/accuracy/precision/recall/F1/AUC/Sharpe/
calibration, all 10 candidates, n=5,548 walk-forward games, 2003-2025) saved to
`cache/model_comparison_backtest.rds`.
- **Result**: every candidate's Brier score matched its previously-reported value to 3-4 decimal
  places (`ensemble_ridge_elo`: 0.2130 -> 0.212987; `ridge_phase1_combined`: 0.2151 -> 0.215074;
  `elo_phase1_combined`: 0.2121 -> 0.212098; all others equally stable). `ensemble_ridge_elo`
  remains the best deployed candidate (Brier 0.2130) and `elo_phase1_combined` remains the best
  single-model Brier (0.2121) but with the same real Sharpe regression noted previously
  (-0.1461 at tau_best vs. ensemble's -0.0839).
- **Status**: no production formula change — this was a re-verification, not a new candidate.
  Closes Known Issue #8's re-verification ask.
- **Full detail**: `cache/model_comparison_backtest.rds`.

### Situational EPA feature engineering (Phase 4 continuation, uncommitted, 2026-09-17)

Closed the "PBP is only used for blunt full-game EPA averages" gap flagged in `tools/gbm_model.R`'s
header and `docs/memory_optimization_plan.md`. `daily_ingest.R`'s `.PBP_CACHE_COLUMNS` widened
from 20 to 23 columns (`score_differential`, `yards_gained`, `pass_oe` added; all three confirmed
present in a live `nflreadr::load_pbp()` pull before adding) — required a `force_refresh = TRUE`
re-bootstrap of `CACHE_PBP` (1,145,788 rows, 2002-2026, re-ran clean). `epa_metrics_engine.R` now
also computes 14 situational per-team-per-game columns (+ their `ROLLING_WINDOW_SIZE` rolling
versions): early-down vs. money-down EPA/success split, red-zone success rate, explosive-play
rate, and PROE (pass rate over expected, situation-neutral early downs only) — offense and
defense-allowed versions of each. New config.R constants: `RED_ZONE_YARDLINE_MAX`,
`EXPLOSIVE_PASS_YARDS`, `EXPLOSIVE_RUSH_YARDS`, `MONEY_DOWN_MIN`, `GARBAGE_TIME_ABS_SCORE_DIFF`
(standard sabermetric-convention thresholds, not locally backtested — same status as
`team_ratings_engine.R`'s `.PYTHAGOREAN_EXPONENT`), plus `SITUATIONAL_EPA_ROLL_COLS` (single
source of truth for the column-name list, referenced by `tools/backtest_common.R`).
- **Data quirk found**: `pass_oe` is 100% NA for every play in seasons 2002-2005 (nflverse's
  pass-over-expected model doesn't cover that era) — documented in `epa_metrics_engine.R`'s
  header; `off_proe_roll`/`def_proe_allowed_roll` are structurally NA for ~16% of team-game rows
  as a result. Not a bug — `.safe_mean()`/`.roll_mean_trailing()` already degrade gracefully.
- These are ADDITIVE columns only — `team_ratings_engine.R`'s live rating formula is unchanged
  and still reads only the pre-existing full-game columns.
- `tools/backtest_common.R`'s `build_week_snapshot()`/`build_walkforward_games()` extended to
  carry every `SITUATIONAL_EPA_ROLL_COLS` column (as-of snapshot, no lookahead) into the
  walk-forward game table as `home_<col>`/`away_<col>` pairs.
- New `tools/ridge_situational_model.R` (deliberately a separate file from
  `tools/ridge_massey_model.R`, not an edit to it — the live production fallback path must not be
  touched by an unvalidated candidate): same ridge/Massey approach plus 14 situational-EPA-diff
  regressors (NA diffs imputed to 0). Registered as three new `tools/model_backtest_harness.R`
  candidates: `ridge_situational_only`, `ridge_situational_phase1_combined`,
  `ensemble_ridge_situational_elo`.
- **Result (full re-run, n=5,548 walk-forward games, 2003-2025)**: situational features give a
  real but modest Brier/log-loss improvement in every matched pair vs. their non-situational
  counterpart (`ridge_only` 0.2318 -> `ridge_situational_only` 0.2302; `ridge_phase1_combined`
  0.2151 -> `ridge_situational_phase1_combined` 0.2146; `ensemble_ridge_elo` 0.2130 ->
  `ensemble_ridge_situational_elo` 0.2127) — genuine calibration signal from richer PBP usage.
  But Sharpe gets WORSE once blended with market/Elo (`ensemble_ridge_elo` -0.089 @ tau9 ->
  `ensemble_ridge_situational_elo` -0.114) — same mechanism as Known Issue #5's long-shot EV
  clustering: at `MARKET_BLEND_WEIGHT=0.97`, extra features add noise to the model's ~3%
  residual disagreement with market, and that noise is what the tail-selected Kelly simulation
  picks up.
- **Status**: NOT promoted to production — `ensemble_ridge_elo` remains deployed (best Brier
  among ensembles at 0.2130 is statistically indistinguishable from the situational variant's
  0.2127; `elo_phase1_combined` remains the best single-model Brier at 0.2121). Documented as a
  modest-positive-but-not-decisive result, following this repo's own precedent for `gbm_stack`'s
  negative result — the candidate code stays in the harness for future revisiting (e.g. feature
  selection to drop the weakest situational regressors, or a missingness indicator instead of
  zero-imputation for the 2002-2005 PROE gap), not deleted.
- **Full detail**: `tools/ridge_situational_model.R`'s header, `epa_metrics_engine.R`'s header,
  `config.R`'s "Situational EPA Feature Thresholds" section, `cache/model_comparison_backtest.rds`.

### Phase 5: Kalman-filter state-space model (uncommitted, 2026-09-17)

Per this doc's own prior roadmap note ("Phase 5 (Bayesian state-space) needs an Rtools/rstan
install decision first, or a pure-R closed-form Kalman-filter alternative") - `rstan`/`cmdstanr`/
`brms`/`rjags` remain NOT installed on this machine (CLAUDE.md), and installing an MCMC toolchain
is a real install decision left to the user rather than done silently mid-session. Built the
documented fallback instead: `tools/kalman_state_space_model.R`, a genuine Bayesian state-space
model - each team's latent point-margin-scale strength is a Gaussian random walk, updated via
exact conjugate-Gaussian (Kalman) math (bivariate assumed-density-filtering update, same
independence approximation TrueSkill/Glicko make - full derivation in that file's header).
Structurally different from ridge/Elo: it tracks each team's own POSTERIOR VARIANCE explicitly
(wide for a team with little recent history, narrow for a stable one) and uses that
GAME-SPECIFIC combined variance for win probability, instead of every other candidate's fixed
`NFL_MARGIN_SIGMA`. Interface mirrors `tools/elo_model.R`'s `run_elo_walkforward()`/
`project_elo_rating()` shape (`run_kalman_walkforward()`/`project_kalman_state()`).
- Four hyperparameters (`KALMAN_INITIAL_VARIANCE`, `KALMAN_PROCESS_VARIANCE`,
  `KALMAN_OBSERVATION_VARIANCE`, `KALMAN_SEASON_CARRYOVER`) empirically derived via new
  `tools/derive_kalman_params.R` (`stats::optim()`, L-BFGS-B, box-constrained joint search -
  same discipline as `ELO_K_FACTOR`'s derivation, generalized from 1 to 4 params). Brier at
  optimum 0.2202 vs. 0.2225 at literature-informed starting values.
- **Found and fixed a real memory issue during derivation**: the first `run_kalman_walkforward()`
  implementation built a length-6,499 list of one-row `data.frame()`s per simulation and
  `bind_rows()`-ed them - called once per `optim()` iteration, this caused a real background
  process OOM kill on this machine (already memory-constrained per `bb1cd99`'s pipeline-OOM
  history). Rewrote to preallocate plain vectors and build one `data.frame()` at the end: same
  output shape, no observed OOM on retry.
- Registered three new `tools/model_backtest_harness.R` candidates: `kalman_pure` (standalone,
  scored against its own `kalman_pred_var`, not `NFL_MARGIN_SIGMA`), `kalman_phase1_combined`
  (QB-injury + market blend, same additive-margin form every other candidate uses),
  `ensemble_ridge_elo_kalman` (3-way unweighted probability average).
- **Result (n=5,548 walk-forward games, 2003-2025)**: `kalman_pure` (Brier 0.2211) ties
  `elo_mov` (0.2211) as a standalone candidate - not decisively better alone. But
  `kalman_phase1_combined` and `ensemble_ridge_elo_kalman` (both Brier 0.2127) land in a
  statistical tie for SECOND-BEST BRIER of all 16 candidates in the harness, edging out the
  deployed `ensemble_ridge_elo` (0.2130) - a genuine calibration improvement from a structurally
  different filtering approach. Sharpe, however, is WORSE than deployed at every one of these:
  `kalman_phase1_combined` -0.216 @ tau9 (vs. deployed -0.089), `ensemble_ridge_elo_kalman`
  -0.125 @ tau9 - the same mechanism as Known Issue #5/the situational-feature finding above
  (extra disagreement-with-market signal gets amplified in the thin, tail-selected Kelly sample).
- **Status**: NOT promoted to production - `ensemble_ridge_elo` remains deployed. The Brier gap
  (0.2127 vs 0.2130) isn't decisive enough to justify a real Sharpe regression. Documented as a
  genuine calibration-positive/staking-negative result, same honesty discipline as `gbm_stack`'s
  precedent - code stays in the harness for future revisiting (e.g. a proper joint covariance
  update instead of the independence approximation, or tuning KALMAN_* against Sharpe instead of
  Brier), not deleted.
- **Full detail**: `tools/kalman_state_space_model.R`'s header (full derivation math),
  `tools/derive_kalman_params.R`'s header, `config.R`'s "Kalman State-Space Model
  Hyperparameters" section, `cache/model_comparison_backtest.rds`.

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
8. ~~Any ridge-model-derived backtest figure computed before the `set.seed()` fix should be
   re-verified~~ **RE-VERIFIED this session** — `tools/model_backtest_harness.R` re-run after
   the fix; every candidate's Brier score matched the previously-reported figure to 3-4 decimal
   places (e.g. `ensemble_ridge_elo` 0.2130 -> 0.212987, `ridge_phase1_combined` 0.2151 ->
   0.215074). The aggregate Brier metric (n=5,548 games) was already stable across CV-fold RNG
   noise; only the small-n, tail-selected Kelly-staking simulation was sensitive to it (matches
   the mechanism found investigating Known Issue #5). `ensemble_ridge_elo` remains the best
   deployed candidate — no change to the production formula needed. Full table saved to
   `cache/model_comparison_backtest.rds`.
9. **This session's work is committed** (`4f3c9d3` and the model-comparison re-run above, not
   yet committed as of writing this line — see `git status --short`).

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
3. ~~Re-run `tools/model_backtest_harness.R` for a corrected Phase 2-4 comparison table~~ **DONE**
   this session — see "Recent work" above; figures confirmed stable, no formula change needed.
4. Consider fixing the stage 8/9.5 ordering gap noted in "Current state" above (risk management
   runs before the same-run's bet grading) if a same-run-fresh ledger read ever becomes
   important — not urgent today since the ledger is empty anyway.
5. If reviving Phase 4/5 model work: `gbm_stack` is a working harness candidate to retry with a
   rolling multi-season validation window; Phase 5 (Bayesian state-space) needs an Rtools/rstan
   install decision first, or a pure-R closed-form Kalman-filter alternative.
6. `player_props_engine.R`, team embeddings, a live dashboard remain explicitly deferred
   non-goals — only start if there's a concrete pull for them.
