# NFL Analytics — Handoff Document

**Last updated**: 2026-09-30, after commit `4b90b40` ("Add tools/weekly_accuracy_report.R for
grading in-progress-season predictions"). `git status --short` is clean — everything described
below is committed, **but local `main` is 1 commit ahead of `origin/main`** (`461fdb4`
"Fix daily_ingest.R silently freezing schedule/PBP rows at bootstrap-time state" was pushed;
`4b90b40` was not — push it if you want the remote caught up). Written for a future LLM/agent
picking this repo back up cold — read this before touching anything, then read `CLAUDE.md` for
environment/data-quirk details this doc doesn't repeat.

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
`notify_bets.R`'s Discord dispatch is still console-only-preview (webhook env var not visible to
R on this machine — see Known Issues).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

## Current state: 11-stage pipeline

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
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch, still console-only-preview |

Stage 9.5 runs after stage 9 (needs its output to record today's picks) but before stage 10.
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

## Known issues / unfinished business

1. **`NFL_DISCORD_WEBHOOK` not visible to R.** Set in `C:\Users\kailo\Documents\.Renviron`, but
   R's user-Renviron lookup resolves to `C:\Users\kailo` directly on this machine. **Fix**: move
   the line into `C:\Users\kailo\.Renviron`, or set it as a Windows env var. Unchanged.
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

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed
  working: `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`, `ggplot2`, `knitr`,
  `rmarkdown`, `tinytex`. NOT installed: `lightgbm`, `rstan`/`cmdstanr`/`brms`/`rjags`,
  `kableExtra`.
- Quarto: **not on PATH** — the real binary is bundled with RStudio at
  `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`. Invoke via full path.
- Real credentials confirmed working: `ODDS_API_KEY`. `NFL_DISCORD_WEBHOOK` is set by the user
  but not currently visible to R (Known Issue #1).
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

## Suggested next steps, roughly in priority order

1. `git push` — local `main` (`4b90b40`) is 1 commit ahead of `origin/main` (`461fdb4`). Trivial,
   but do it before starting new work so `origin` isn't stale.
2. Fix the `NFL_DISCORD_WEBHOOK` visibility issue (5-minute user-side fix, unblocks real
   notifications) — Known Issue #1, still open.
3. Validate or reject the home-backup-QB market bias (Known Issue #4) — the one credible
   positive-Sharpe finding this session produced. Check it against the real production staking
   gates, then either derive asymmetric QB-injury-penalty constants and re-run the comparison
   harness, or let it season against 2025-2026 data as a true holdout before deciding.
4. Re-run `tools/weekly_accuracy_report.R` after each new week completes to build up a real
   accuracy trend line (only 3 data points exist so far — not enough to distinguish signal from
   noise yet). Worth watching whether the Week 1→3 accuracy decline (75.0%→68.8%→56.2%) continues
   or was noise.
5. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data
   angle needs an explicit user decision (new paid vendor or scraping project) before pursuing —
   not started pending that.
6. Consider fixing the stage 8/9.5 ordering gap (Known Issue #3) if a same-run-fresh ledger read
   ever becomes important — not urgent today since the ledger is empty anyway.
7. `player_props_engine.R`, team embeddings, a live dashboard, and a true rstan/cmdstanr install
   for Phase 5's Bayesian state-space idea remain explicitly deferred non-goals — only start if
   there's a concrete pull for them.
