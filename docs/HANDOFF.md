# NFL Analytics — Handoff Document

**Last updated**: 2026-09-17, after commit `d1c90aa` ("Phase 8: early-season rating shrinkage +
minimum-sample staking gate"). Written for a future LLM/agent picking this repo back up cold —
read this before touching anything, then read `CLAUDE.md` for environment/data-quirk details this
doc doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data instead of WNBA's `wehoop`/ESPN-only sources. Real git repo, remote
`origin` = `https://github.com/kailot-harris/NFL_analytics.git` (private).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) research foundation this whole repo was built from: data-source decisions, coverage
windows, the ID-crosswalk risk, playoff-bracket structure, etc. Still accurate as of last
verification (2026-09-16) but nflverse/vendor details can shift — re-verify anything
date-sensitive before trusting it blindly for new work.

## Current state: fully working 10-stage pipeline

`run_full_pipeline.R` runs end-to-end against **real live data** (not synthetic/demo, unlike the
WNBA sibling repo's `fatigue_travel_engine.R`/`risk_management_engine.R` which do use synthetic
data in places — this repo deliberately avoided that shortcut except where explicitly noted below).

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (1.14M+ rows), `CACHE_SCHEDULES` (6,771+ rows) via `nflreadr::load_pbp()`/`load_schedules()` |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` (~2,968 rows, all 32 teams, full season-to-date ledger incl. IR/practice squad — filter on `status == "ACT"` if you want only active roster) |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` — `nflreadr::load_injuries()` primary + ESPN site-API secondary (Player-Card-href athlete-ID workaround, see CLAUDE.md) |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` — rolling per-team offensive/defensive EPA-per-play, success rate, CPOE, window = `ROLLING_WINDOW_SIZE` |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — power ratings (EPA-differential-based, **now shrinkage-adjusted**, see Phase 8 below) + projected margin/win-prob for every upcoming scheduled game, plus a comparison-only Pythagorean-expectation column. **`home_win_prob` is now further adjusted by a QB-backup-starter penalty and blended with real live market odds** — see "Model-quality remediation" below |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` — real rest-days/short-week/travel-haversine/circadian/altitude metrics for every real scheduled game (32-team stadium DB, live-verified incl. 2026 venue renames) |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — genuine single-elimination, 14-team, reseed-after-every-round Monte Carlo bracket sim off real in-season standings (**simplified tiebreak** — win% + alphabetical, not the NFL's real multi-step tiebreaker procedure) |
| 8 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — bankroll drawdown / dynamic Kelly-tier tracking. **Uses a `SYNTHETIC_FALLBACK` seed ledger** (clearly labeled in both logs and the cached object) because no real bet ledger/`bet_tracker.r` exists yet |
| 9 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real live Odds API (`americanfootball_nfl`, h2h) odds, sharp-book devig, EV/Kelly math, **reuses stage 5's `projected_matchups.rds` as the sole model-probability source** (does not re-derive independently, unlike WNBA's version) |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output (terminal stage). Discord embed dispatch, currently **console-only preview** since `NFL_DISCORD_WEBHOOK` isn't visible to R yet (see Known Issues) |

All ten stages use the `call_fn`-style convention (`run_stage(script, desc, call_fn = "fn_name",
output = ...)`) — **no script has a `sys.nframe()`/`!interactive()` auto-run guard**. This was a
deliberate choice from Phase 1 onward to avoid the WNBA repo's own documented silent-no-op bug
class. Do not add one.

`run_full_pipeline.R` also carries the WNBA-ported `run_stage()` infrastructure verbatim: stack-trace
capture, and a C-2-style staleness assertion (`.check_stage_output()`) that WARNs when a stage's
declared output didn't regenerate. **`daily_ingest.R`'s two outputs routinely show `[WARN] stale`**
when `nflreadr` has no new rows since the last run — this is confirmed-correct incremental-skip
behavior, not a bug, and is explicitly documented in the `pipeline-freshness-audit` skill's manifest.

## Build history (chronological, one git commit per phase)

| Commit | Phase | What it added |
|---|---|---|
| `1863559` | — | `.gitignore` fixes (was blanket-hiding `docs/` and `/cache/`; also excludes the ~300MB raw PBP cache and `logs/` noise) |
| `9155ad1` | 1 | `daily_ingest.R`, `sync_rosters.R`, `injury_scraper.R`, `run_full_pipeline.R` skeleton |
| `9c05705` | 2 | `epa_metrics_engine.R`, `team_ratings_engine.R` |
| `a8a4262` | 3 | `fatigue_engine.R` (real, not synthetic — improvement over WNBA's demo version) |
| `cd8734f` | 4 | `playoff_simulator.R` (genuine new single-elimination bracket logic) |
| `226f735` | 5 | `risk_management_engine.R` (ported verbatim math, synthetic-fallback ledger) |
| `55adf5e` | 6 | `market_odds_engine.R` (real live Odds API integration) |
| `105eb8e` | 7 | `notify_bets.R` (Discord dispatch, webhook not yet live) |
| `d1c90aa` | 8 | Rating shrinkage + minimum-sample staking gate (see below) |

Each phase has a corresponding `docs/task_assignments_phaseN.md` with a Task Tracker, wave
dependency graph, interface contracts, and Handoff Notes — **read the relevant phase file before
modifying a script it covers**, it documents exact design decisions and interface contracts that
this summary doc compresses.

**File-numbering vs. content note**: `task_assignments_phase0.md`'s content is actually "Phase 1"
work (ingest scripts) — the file-number sequence and the DAG-phase-number sequence are offset by
one because Phase 0 (scaffold/config/skills) predated the task-assignments convention being used
in this repo. Each phase file's own header explains this; don't be confused when phase numbers in
file names don't match phase numbers in file content.

## Phase 8 detail: why predictions got less extreme

A user asked for Week 2 2026-season predictions and got implausible results (win probs >90%, EV
figures up to +224% against real live odds) because ratings were built on only 1-2 games of real
current-season EPA data. Fix (commit `d1c90aa`, `docs/task_assignments_phase7.md`):

1. **`team_ratings_engine.R`**: each team's power rating now blends `weight * current_raw_rating +
   (1-weight) * prior_season_rating`, where `weight = games_played / (games_played +
   RATING_SHRINKAGE_GAMES_K)` (`K=4`, **not empirically backtested**, a starting heuristic like
   `ROLLING_WINDOW_SIZE`). `prior_season_rating` is derived from each team's final rolling EPA in
   the prior season, run through the *same* rating formula (no second, divergent copy of that
   math). Falls back to league-average (0) only if a team has zero prior-season data (should never
   trigger for any of the current 32 teams — logs a WARN if it ever does).
2. **`market_odds_engine.R`**: forces `Bankroll_Rec <- 0` and `Status <- "⚠ INSUFFICIENT SAMPLE
   (early season)"` when either team has fewer than `MIN_SAMPLE_GAMES_FOR_STAKE` (`=3`, also not
   backtested) real games played this season — EV/win-prob columns still populate for
   transparency, only the stake/dispatch-worthiness is gated.
3. **`notify_bets.R`**: excludes insufficient-sample rows from the actionable-bets filter (and the
   top-3-by-EV fallback) before dispatch.

**As of 2026-09-17 (Week 2), every live game is gated** — all 32 teams have played exactly 1 game.
This is real, expected, and verified end-to-end (the pipeline correctly dispatches zero Discord
picks with a clear log message). The gate will start passing games through once teams accumulate
3+ games played, likely partway through the season.

## Model-quality remediation (Phase A + Phase 1, 2026-09-17)

Following the Phase 8 constant backtest below (which found the model's Sharpe was negative at
every staking threshold), a research + planning pass produced a phased model-quality roadmap
(saved as a plan; ask the user if you need the original plan doc). Phase A and Phase 1 of that
roadmap are DONE:

- **Phase A**: `tools/backtest_shrinkage_optimizer.R`'s walk-forward game-table builder was
  extracted into `tools/backtest_common.R` (a regression check confirmed identical output before/
  after) so it can be reused. `tools/model_backtest_harness.R` is a new general-purpose,
  multi-candidate comparison harness — reports Brier score, log-loss, a calibration/reliability
  table (all primary/threshold-free), plus accuracy/precision/recall/F1/AUC (secondary,
  threshold=0.5, positive class="home win" — stated explicitly per the metric-tension the user's
  original request surfaced) and a real quarter-Kelly Sharpe/ROI simulation against historical
  closing lines, for any candidate `predict_fn`.
- **Phase 1**: two new empirically-derived constants, both via `stats::optimize()` (not a grid
  search) — see config.R's own comments for full figures:
  - `MARKET_BLEND_WEIGHT = 0.97` — blends `team_ratings_engine.R`'s EPA-model probability with
    devigged historical market probability. **Brier dropped from 0.2433 (model only) to 0.2105**
    (2010-2025, n=4,009 games) — the single biggest calibration improvement found in this repo's
    history. The optimizer landing near w=1 (market-only) matches the sports-forecasting
    literature's "market is close to a sufficient statistic" finding — the EPA model contributes
    little once market info is present.
  - `QB_INJURY_RATING_PENALTY_PTS = 1.6` — rating-point penalty applied when a real, no-lookahead,
    depth-chart-derived signal (`tools/qb_injury_features.R`) shows a backup QB started. Smaller
    but real effect: Brier 0.245644 → 0.245437 (2003-2025, n=5,548 games).
  - Both are now wired into the LIVE pipeline (`team_ratings_engine.R::run_team_ratings()`), not
    just the backtest — `CACHE_PROJECTED_MATCHUPS.home_win_prob` is the blended/adjusted value,
    and `market_odds_engine.R`'s "sole model-probability source" consumption contract is
    unchanged (the blend happens upstream, per the plan's Option A).
  - **Real data quirk discovered building this** (not yet in CLAUDE.md — add it if you touch
    `load_depth_charts()` again): `nflreadr::load_depth_charts()` silently returns TWO different
    schemas depending on season. Seasons 2002-2024 use the old nflverse weekly-release shape
    (`season/week/club_code/depth_team/game_type/position`). **Seasons 2025 and 2026 — i.e.
    `CURRENT_SEASON - 1` too, not just `CURRENT_SEASON`** — already return a live ESPN-scrape
    shape instead (`dt`, `team`, `gsis_id`, `pos_abb`, `pos_rank`; no `season`/`week`/`position`
    columns at all). Requesting a season range that spans both schemas silently merges both
    shapes into one wide data frame rather than erroring — `tools/qb_injury_features.R`'s
    historical functions only work on the old (2002-2024) schema; `team_ratings_engine.R::
    get_live_qb_backup_flags()` has its own separate live-schema-aware logic for exactly this
    reason. This also means the QB-injury backtest's real depth-chart coverage is effectively
    2002-2024, not 2002-2025 (499 of 5,548 games got "unknown flag, zero adjustment" — mostly
    real 2025-season coverage gap, not random noise, now that this is understood).
  - Run `tools/model_backtest_harness.R` for the full candidate comparison table (baseline vs.
    market-blend-only vs. QB-injury-only vs. combined) — saved to
    `cache/model_comparison_backtest.rds`.
- **Phase 2 (done, 2026-09-17)**: `tools/ridge_massey_model.R` — a ridge-regularized regression
  (`glmnet::cv.glmnet(alpha=0)`, already installed, no new dependency) that LEARNS how to combine
  current-season vs. prior-season rating signal (features: `diff_raw`, `diff_prior`, and their
  interactions with `avg_gp`, all built from columns already in the walk-forward game table),
  replacing the hand-tuned `RATING_SHRINKAGE_GAMES_K`/`(games_played/(games_played+K))` blend
  formula. Refit once per season, trained only on strictly earlier seasons (season-level walk-
  forward — coarser than the per-week granularity used elsewhere, a documented tradeoff). Cleared
  the harness's acceptance gate against `phase1_combined` (the actual production baseline at the
  time): **Brier 0.2168 → 0.2151, log-loss 0.6257 → 0.6199, F1 0.713 → 0.720, AUC 0.7035 →
  0.7062** (`ridge_phase1_combined` in `tools/model_backtest_harness.R`'s comparison table — full
  figures in `cache/model_comparison_backtest.rds`). Now wired into the LIVE pipeline:
  `team_ratings_engine.R::run_team_ratings()` fits ridge fresh each run on the full historical
  walk-forward table (`build_walkforward_games()`, ~5,548 games, adds ~30-45s to that stage —
  accepted cost, no new cache/stage needed) and uses it in place of the old `(home_rating -
  away_rating) + NFL_HCA` line, with the old formula kept as an explicit fallback if the fit ever
  fails. Live win probabilities are now visibly less extreme/more plausible post-Phase-2 (e.g. a
  32-game live slate ranged ~21%-87% instead of the pre-Phase-1 93%+/<2% extremes that originally
  motivated the Phase 8 shrinkage fix). Verified via a full `run_full_pipeline.R` run (exit 0,
  154s total, all stages fresh) and `config-constant-drift-audit` (zero HIGH findings — Phase 2
  added no new `config.R` constants; ridge's own regularization strength is chosen by glmnet's
  internal cross-validation, not hand-tuned).
- **Not yet done**: Phases 3-5 of the roadmap (MOV-weighted Elo, gradient-boosted trees, Bayesian
  state-space) remain a documented but unimplemented roadmap — see the plan for gating/
  dependencies. Sharpe at the production staking gate (tau=9) is still reported by the harness for
  every candidate including ridge; it's directionally less bad (`ridge_phase1_combined`: -0.0111
  vs. `phase1_combined`'s -0.0332 at tau=9) but still negative — Phase 2 is a calibration win, not
  a proven staking edge, same honesty caveat as Phase 1. `stats::optimize()`'s golden-section
  search on the Sharpe-by-tau sweep isn't guaranteed globally optimal on a non-smooth step-function
  objective (a real limitation — see the harness's own inline caveat) — do not treat any single
  positive-Sharpe reading from that sweep as validated edge without a wider check.

## Known issues / unfinished business

1. **`NFL_DISCORD_WEBHOOK` not visible to R.** The user set it in
   `C:\Users\kailo\Documents\.Renviron`, but R's user-Renviron lookup on this machine resolves to
   `C:\Users\kailo` directly (confirmed via `Sys.getenv("R_USER")`/`Sys.getenv("HOME")` both
   printing `C:\Users\kailo`, not `...\Documents`), so that file is never read by R processes here.
   `ODDS_API_KEY` works fine (it's set somewhere R *does* find — possibly a different/older
   `.Renviron` or a system env var). **Fix**: move the `NFL_DISCORD_WEBHOOK` line into
   `C:\Users\kailo\.Renviron`, or set it as a Windows user/system environment variable. Once
   visible, `notify_bets.R` will dispatch for real with no code changes needed — this was verified
   end-to-end on the no-webhook path already.
2. **`RATING_SHRINKAGE_GAMES_K` and `MIN_SAMPLE_GAMES_FOR_STAKE` are now backtested (2026-09-17)** —
   see `tools/backtest_shrinkage_optimizer.R` (walk-forward, out-of-sample, optimized via
   `stats::optimize()`, not a grid search) and `cache/phase8_constant_backtest.rds`. Findings:
   - `RATING_SHRINKAGE_GAMES_K`: the starting heuristic (4) was already near-optimal against real
     Brier score (2003-2025, n=5,548 games) — updated to the backtested value, `3.6`.
   - `MIN_SAMPLE_GAMES_FOR_STAKE`: updated from 3 to the backtest-optimal `9` (real 2010-2025
     Vegas closing moneylines, n=4,009 games) — **but the Sharpe ratio of the staking simulation
     is negative at every threshold tested, including 9.** The gate only reduces historical losses
     (tau=9 loses ~4x less cumulative % than tau=3); it does not show the underlying EPA-diff
     rating model beats the closing line. See config.R's `MIN_SAMPLE_GAMES_FOR_STAKE` comment for
     the full figures — **this is a stronger reason to keep real-money staking paused (see Known
     Issue #5) than the old "unvalidated heuristic" framing was.** The next real next-step here is
     a model-quality fix (better features / market-aware calibration), not a further threshold
     re-tune.
3. **Playoff seeding uses a simplified tiebreak** (win% + alphabetical), not the NFL's real
   multi-step official tiebreaker (head-to-head, division record, strength of schedule/victory,
   net points, etc.). Documented in `playoff_simulator.R`'s header and the cache object's
   `seeding_method` field. Fine for a probabilistic bracket sim, not fine if someone expects
   official-accuracy seeding.
4. **`risk_management_engine.R` has no real ledger to read yet** — there's no `bet_tracker.r`
   (bet-grading/ledger-writer) in this repo. It correctly falls back to a clearly-labeled
   `SYNTHETIC_FALLBACK` 120-bet seed ledger every run. Building a real `bet_tracker.r` (analogous
   to WNBA's) is unstarted work.
5. **Odds/EV numbers are directionally informative only, not stake-ready**, even with the Phase 8
   gate — the gate prevents *early-season* overconfidence specifically, it doesn't validate the
   model's accuracy in general. No backtest of the full pipeline's predictive accuracy against
   historical results has been done.

## Explicitly not built (documented non-goals / deferred, not forgotten)

- **`player_props_engine.R`** — The Odds API's event-odds endpoint (per-event call, different from
  the h2h featured-markets endpoint `market_odds_engine.R` uses) or an in-house
  Poisson/negative-binomial model on `load_player_stats()`/`load_nextgen_stats()`. Not started.
- **Team embeddings** (WNBA's `team_embeddings.py`, PyTorch-based style-similarity) — explicitly
  deprioritized as a low-value stretch feature relative to the credential-gated market/risk/notify
  work that was built instead. Not started.
- **A live dashboard / Shiny app** (WNBA has `app.R`) — not started.
- **Participation/personnel features** (`nflreadr::load_participation()`, 11/12/21 personnel
  groupings) — flagged in the replication plan as valuable but not real-time-usable in-season
  (2023+ participation data is FTN-sourced, released only after the postseason ends). Better
  suited to offline backtesting than the live pipeline. Not started.
- **`load_ff_playerids()` ID-crosswalk usage** — flagged from Phase 0 as the single biggest
  structural risk in the NFL data ecosystem (four competing player-ID schemes: ESPN, GSIS, PFR,
  NFL/NGS), but no code in this repo currently does a player-level cross-ID join (all joins so far
  are team-level, which uses one consistent scheme — `NFL_TEAMS` abbreviations). This becomes
  necessary the moment player-level work starts (props engine, injury-adjusted ratings, etc.) —
  do not add a naive name-based or single-ID-scheme join without reading
  `docs/NFL_REPLICATION_PLAN.md`'s §1 failure-mode #3 first.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). `nflreadr`, `httr`, `httr2`,
  `dplyr`, `duckdb`, `jsonlite` etc. already installed.
- Real credentials confirmed working in this environment: `ODDS_API_KEY`. `NFL_DISCORD_WEBHOOK` is
  set by the user but not currently visible to R (see Known Issues #1).
- Inline multi-line `Rscript -e '...'` **segfaulted once** during this build (confirmed on this
  machine) — write ad hoc R to a temp `.R` file under `tools/` (delete it after) rather than
  inlining, matching the WNBA repo's own documented convention for the same reason.
- `git log` has a slightly unusual early history (`bfada9a "setup"`, two `"Initial commit"`s, a
  merge commit) from before this repo's build process settled — see commit `1863559`'s own commit
  message for context if it ever looks confusing; it's not corruption, just an early unauthorized
  push by a since-corrected subagent, cleared with the user after the fact.

## Suggested next steps, roughly in priority order

1. Fix the `NFL_DISCORD_WEBHOOK` visibility issue (5-minute user-side fix, unblocks real
   notifications).
2. ~~Backtest `RATING_SHRINKAGE_GAMES_K` and `MIN_SAMPLE_GAMES_FOR_STAKE`~~ **done 2026-09-17** —
   see Known Issue #2 and `tools/backtest_shrinkage_optimizer.R`. The backtest surfaced a bigger
   problem than the constants themselves: the rating model shows negative Sharpe against real
   closing lines at every staking-gate threshold. **New priority #2**: improve the underlying
   rating model (team_ratings_engine.R's EPA-diff formula is Phase 2's original starting signal,
   never revisited) or add a market-aware calibration step, then re-run the same backtest script
   to confirm positive out-of-sample Sharpe before real-money staking is reconsidered.
3. Build `player_props_engine.R` once there's appetite for it (needs the event-odds endpoint +
   real `load_ff_playerids()` crosswalk work, per the deferred item above).
4. Build a real `bet_tracker.r` so `risk_management_engine.R` has a real ledger to read instead of
   its synthetic fallback.
5. Team embeddings / dashboard, only if there's a concrete use case pulling for them — not
   inherently valuable on their own per the original replication plan's own risk assessment.
