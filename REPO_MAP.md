# NBA Analytics — Repository Map

Read this before touching anything. It is written for an AI agent with zero prior context on this
codebase. The project is a personal, local-only (no git) NBA analytics + quantitative sports-betting
pipeline. It is primarily R (tidyverse/tidymodels style) with one Python file for embeddings. Nothing
is containerized; everything runs via `Rscript` on Windows, orchestrated by a `.bat` file and Windows
Task Scheduler.

Location: `C:\Users\kailo\kayceeslices\NBA Analytics`

---

## 1. Overview

The system evolved in phases (see the markdown logs at repo root — they are primary sources and
should be read for narrative history, not re-derived from code alone):

- **Baseline (`NBA_Analysis_Project.Rmd` / `.pdf`)**: A clean, "pristine" R Markdown report. Team-level
  18-game rolling box-score features → Random Forest (`ranger`) game-outcome classifier. Benchmarked
  Logistic Regression vs Random Forest vs XGBoost, plus a 10,000-run Monte Carlo 82-game season
  simulation. This file is treated as an immutable reference baseline — see `ADR.md` Principle I
  ("Non-Invasive Satellite Topology"): **never edit this Rmd**. There is also an "Original - No LLM"
  Rmd/PDF pair which appears to be an earlier/manual version of the same analysis, kept for comparison.
- **Phase 1 (T1–T7, see `ADR.md` / `pipeline_architecture_decisions.md`)**: Added player-level BPM,
  injury/fatigue tracking, lineup synergy, roster continuity, team embeddings, live calibration, and a
  Shiny dashboard, all as "satellite" scripts feeding a new orchestrator `run_full_pipeline.R`.
- **Phase 2 (`engineering_log_phase2.md`)**: Turned it into an automated betting pipeline —
  `enhanced_model.R` (feature fusion + XGBoost), `market_odds_engine.R` (+EV/Kelly), `bet_tracker.R`
  (ledger + rolling ROI), Windows Task Scheduler automation via `schedule_daily.bat` (05:00 daily).
- **Phase 3 (`engineering_log_phase3.md`)**: Live odds ingestion from The Odds API, CLV (closing-line
  value) tracking, Discord webhook alerts (`notify_bets.R`), roster sync from ESPN CDN
  (`sync_rosters.R`), a bottom-up player-composed team-rating/standings engine
  (`roster_bottom_up_engine.R`), a live in-play polling daemon (`live_game_listener.R`), and a
  Poisson-based player-props engine (`player_props_engine.R`).
- **Phase 4 (`phase4_recommendations_and_wishlist.md`, `next_researcher_handoff_prompt.md`)**: Wishlist
  for an 8-tab dashboard, in-play "steam sniping", and ZINB (Zero-Inflated Negative Binomial) props.
  Mostly implemented in the current code (see `app.R` 8 tabs, `player_props_engine.R` ZINB, ZINB copula
  engine, risk management engine).
- **Phase 5 (comments inside `run_full_pipeline.R`, `market_odds_engine.R`, `shot_quality_engine.R`,
  `fatigue_travel_engine.R`)**: RAPM (regularized adjusted plus-minus), spatial shot-quality (xeFG%),
  haversine travel/circadian fatigue, multivariate Gaussian-copula player props, playoff series Monte
  Carlo, and a bankroll drawdown/risk-management engine.

**Important caveat found while reading the code**: many of the "Phase 4/5" engines
(`rapm_engine.R`, `shot_quality_engine.R`, `fatigue_travel_engine.R` slate function,
`player_props_engine.R` roster fallback, `playoff_simulator.R`, `risk_management_engine.R`,
`copula_props_engine.R`) generate **synthetic/simulated input data** (`set.seed(42)`, `rnorm`,
hard-coded team lists) when a real cache file is missing, rather than pulling live stats for those
specific slices. They are structurally real engines (the math is genuine) but are frequently exercised
against fabricated inputs rather than fully live NBA data. Treat their headline numbers (e.g. specific
player RAPM values, shot-quality profiles) as demo/prototype output, not verified live values, unless
`cache/*.rds` was populated from a real upstream call. This matters a lot for the WNBA replication plan
(see companion doc) because "porting" some of these files is mostly a no-op — they don't actually
depend on NBA-specific data at all today.

---

## 2. Data Sources & APIs

| Source | Used by | Mechanism | Notes |
|---|---|---|---|
| **`hoopR`** (R package, ESPN-backed loaders) | `daily_ingest.R`, `player_metrics.R`, `lineup_synergy.R` (via `player_metrics.R`), `roster_dynamics.R` (via `player_metrics.R`), `NBA_Analysis_Project.Rmd` | `hoopR::load_nba_team_box(seasons = ...)`, `hoopR::load_nba_player_box(seasons = ...)` | Historical + current-season team and player box scores, 2019–2026. Chunked season-by-season with `MAX_RETRIES = 3` and `RATE_LIMIT_SLEEP_SEC = 1.5` in `player_metrics.R`. |
| **ESPN Site API (JSON, undocumented public CDN)** | `sync_rosters.R`, `injury_scraper.R` | `GET https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams` (team list), `GET .../teams/{team_id}/roster` (roster per team), `GET https://site.api.espn.com/apis/site/v2/sports/basketball/nba/injuries` (injury report) | Uses `httr2::request()/req_perform()`. No API key. Standardizes franchise names via regex (`case_when` on team name substrings). Falls back to a hardcoded offseason injury sample if the feed returns 0 rows. |
| **NBA.com Stats API (`stats.nba.com`)** | `xpoints_engine.R` | `GET https://stats.nba.com/stats/shotchartdetail?...&TeamID=...&Season=...` with spoofed browser headers (`User-Agent`, `Referer`, `x-nba-stats-origin`, `x-nba-stats-token`) | Shot-chart detail for expected-points/shot-quality modeling. Heavily rate-limited/blocked in practice — the script auto-falls-back to `generate_synthetic_shots()` (a fabricated 2,500-shot sample) whenever the request fails or is non-200. In the current repo state, this is effectively always running on synthetic data. |
| **The Odds API** (`the-odds-api.com`) | `market_odds_engine.R`, referenced (not yet wired) in `live_game_listener.R` | `GET https://api.the-odds-api.com/v4/sports/basketball_nba/odds/?apiKey=...&regions=us,us2,eu&markets=h2h&oddsFormat=american` | Requires `ODDS_API_KEY` env var (`Sys.getenv("ODDS_API_KEY","")`). If empty or the call fails, falls back to a **hardcoded 6-game "calibrated schedule slate"** (fabricated fixture with fixed matchups/odds dated Oct 2026). Sharp-book detection looks for bookmaker keys `pinnacle`, `circa`, `lowvig`, `betonlineag` among the returned `bookmakers[].key` values. |
| **Discord Webhooks** | `notify_bets.R`, `live_game_listener.R` | `httr::POST(DISCORD_WEBHOOK_URL, body=payload, encode="json")` | Webhook URL read from `Sys.getenv("DISCORD_WEBHOOK", "<dummy>")`. **`config.R` line 37 hardcodes a live Discord webhook URL via `Sys.setenv(...)`** — this is a real credential checked into a plaintext file; treat it as compromised/rotate it, don't copy it into the WNBA project. |
| Synthetic/local fixtures | `rapm_engine.R`, `shot_quality_engine.R`, `fatigue_travel_engine.R`, `playoff_simulator.R`, `risk_management_engine.R`, `copula_props_engine.R`, `player_props_engine.R` (roster fallback) | In-process R `rnorm`/`rpois`/`runif` with `set.seed(42)` or similar | No external network call at all; these compute on fabricated but structurally realistic data unless a real `cache/*.rds` upstream artifact already exists. |

No paid data-provider account is strictly required to run most of the pipeline: hoopR/ESPN paths are
free and keyless; only `ODDS_API_KEY` (The Odds API) is a real paid/free-tier external key, and it is
optional (silent fallback to fixture data).

---

## 3. Pipeline Architecture

### 3.1 Two separate orchestrators exist

1. **`schedule_daily.bat`** (Windows Task Scheduler target, runs daily ~05:00 EST per the phase-2 log):
   ```
   cd NBA Analytics
   Rscript run_full_pipeline.R   >> pipeline_execution.log
   Rscript bet_tracker.R         >> pipeline_execution.log
   Rscript market_odds_engine.R  >> pipeline_execution.log
   ```
   Note: `run_full_pipeline.R` itself already calls `bet_tracker.r` and effectively duplicates
   `market_odds_engine.R`'s role — the `.bat` file predates some later additions to
   `run_full_pipeline.R` and the two are not perfectly deduplicated. This is a known inconsistency,
   not a bug to "fix" blindly — verify current intent before touching.

2. **`run_full_pipeline.R`** (the "master" DAG, called by the `.bat` and directly runnable). Executes,
   in order, via a `run_stage(script_name, description)` helper that `source()`s each file inside a
   `tryCatch` (so failures don't halt the whole run):
   ```
   1. sync_rosters.R          -> cache/active_rosters_cache.rds
   2. injury_scraper.R        -> cache/injury_data_cache.rds
   3. shot_quality_engine.R   -> cache/team_shot_quality.rds
   4. fatigue_travel_engine.R -> cache/travel_fatigue_metrics.rds
   5. rapm_engine.R           -> cache/rapm_ratings.rds
   6. roster_bottom_up_engine.R -> cache/projected_30_team_standings.rds
   7. market_odds_engine.R    -> cache/latest_value_bets.rds, cache/odds_history.rds
   8. player_props_engine.R   -> latest_player_props.rds, cache/latest_player_props.rds
   9. copula_props_engine.R   -> cache/copula_jokic_pra.rds
   10. playoff_simulator.R    -> cache/playoff_series_bos_nyk.rds
   11. risk_management_engine.R -> cache/risk_state.rds
   12. notify_bets.R          -> Discord webhook dispatch (reads latest_value_bets.rds)
   13. bet_tracker.r          -> cache/betting_ledger.rds, cache/rolling_bet_metrics.rds
   ```
   Notably **not** called from `run_full_pipeline.R`: `daily_ingest.R`, `player_metrics.R`,
   `lineup_synergy.R`, `roster_dynamics.R`, `team_embeddings.py`, `load_embeddings.R`,
   `live_calibration.R`, `enhanced_model.R`, `live_game_listener.R`, `xpoints_engine.R`. These are
   either (a) meant to be run standalone/manually (embeddings, enhanced model retraining are not
   cheap/daily operations), (b) an earlier Phase-1 layer superseded by the Phase-3/4/5 bottom-up
   engine, or (c) a long-running daemon (`live_game_listener.R`) meant to run during game windows, not
   in the morning batch. `ADR.md`'s original 7-step DAG (config → daily_ingest → player_metrics →
   injury_load_tracker → lineup_synergy/roster_dynamics → team_embeddings → live_calibration → app.R)
   describes the **Phase-1** pipeline; `run_full_pipeline.R` as it exists today is the **Phase-3/4/5**
   pipeline and has diverged significantly. Both are real, but only the current `run_full_pipeline.R`
   is what actually executes daily.

### 3.2 ASCII data-flow (current `run_full_pipeline.R`, Phase 3–5 state)

```
 [ESPN CDN]                         [ESPN injuries feed]
     |                                     |
     v                                     v
 sync_rosters.R                     injury_scraper.R
     |                                     |
     v                                     v
 cache/active_rosters_cache.rds   cache/injury_data_cache.rds
     |                                     |
     |         (synthetic)                 |
     v                                     |
 shot_quality_engine.R  --> cache/team_shot_quality.rds
 fatigue_travel_engine.R --> cache/travel_fatigue_metrics.rds
     |                                     |
     v                                     |
 rapm_engine.R (synthetic stints) --> cache/rapm_ratings.rds
     |                                     |
     v                                     |
 roster_bottom_up_engine.R  <--------------+
   reads: player_box_scores_cache.rds (real, from player_metrics.R/hoopR),
          active_rosters_cache.rds, injury_data_cache.rds
   writes: cache/projected_30_team_standings.rds  (30-team net ratings, zero-sum 1230 wins)
     |
     v
 market_odds_engine.R
   reads: The Odds API (or fixture), cache/projected_30_team_standings.rds,
          cache/team_shot_quality.rds, cache/travel_fatigue_metrics.rds
   writes: cache/latest_value_bets.rds, cache/odds_history.rds
     |
     +--> player_props_engine.R --> latest_player_props.rds / cache/latest_player_props.rds
     +--> copula_props_engine.R --> cache/copula_jokic_pra.rds
     +--> playoff_simulator.R (reads cache/rapm_ratings.rds) --> cache/playoff_series_bos_nyk.rds
     |
     v
 risk_management_engine.R --> cache/risk_state.rds
     |
     v
 notify_bets.R  (Discord webhook, reads latest_value_bets.rds)
     |
     v
 bet_tracker.r  (grades yesterday's bets from box_scores_cache.rds,
                 writes cache/betting_ledger.rds, cache/rolling_bet_metrics.rds)
     |
     v
 app.R  (Shiny dashboard — reads ALL of the above cache/*.rds files, zero live calls on load)
```

### 3.3 Legacy / Phase-1 side-pipeline (not in `run_full_pipeline.R`, run manually)

```
hoopR API
  -> daily_ingest.R          -> box_scores_cache.rds (team box, root dir, not cache/)
  -> player_metrics.R        -> cache/player_box_scores_cache.rds (player box + BPM aggregation)
       -> lineup_synergy.R   (HHI / star overlap, no persisted cache; returns a tibble)
       -> roster_dynamics.R  (continuity %, no persisted cache; returns a tibble)
  -> team_embeddings.py      -> team_embeddings.csv, team_similarity_matrix.csv (root dir)
       -> load_embeddings.R  (loader/join helper, no own cache)
  -> live_calibration.R      (odds-conversion + calibration utility functions; sourced by other
                               scripts, e.g. roster_bottom_up_engine.R and bet_tracker.R for
                               american_to_prob/remove_vig helpers — not just Phase-1)
  -> enhanced_model.R         (one-off: fuses rolling box features + fatigue + embeddings into
                               ranger/xgboost models; writes cache/enhanced_rf_fit.rds; this is the
                               script that produced the Phase-2 benchmark table, not part of the daily
                               batch)
```

`enhanced_model.R` and `player_metrics.R`/`lineup_synergy.R`/`roster_dynamics.R` require
`box_scores_cache.rds` (root) and `cache/player_box_scores_cache.rds` to already exist — these are the
two large hoopR-backed caches (20,480 team-game rows and 200,000+ player-game rows respectively per the
ADR). If they're missing, `daily_ingest.R`/`player_metrics.R` do a full historical pull
(`ALL_SEASONS <- 2019:2026`) which is the only genuinely slow step in this whole system.

---

## 4. File-by-File Reference

### Configuration & orchestration

- **`config.R`** — Global constants sourced by nearly every script: `PROJECT_DIR`, `CACHE_DIR` (creates
  `cache/` if missing), `HISTORICAL_SEASONS <- 2019:2025`, `TEST_SEASON <- 2026`,
  `CURRENT_SEASON <- 2026`, `ALL_SEASONS <- 2019:2026`, `SIMULATION_SEASON <- 2027`,
  `ROLLING_WINDOW_SIZE <- 18`, `OFFSEASON_METHOD <- "reset"`, `REST_DAYS_CAP <- 7`,
  `N_SIMULATIONS <- 10000`, cache file path constants (`CACHE_TEAM_BOX`, `CACHE_PLAYER_BOX`,
  `CACHE_FEATURES`, `CACHE_EMBEDDINGS`, `CACHE_SIMILARITY`, `CACHE_INJURY_DATA`,
  `CACHE_PLAYER_PROPS`), `RATE_LIMIT_SLEEP_SEC <- 1.5`, `MAX_RETRIES <- 3`, and
  `Sys.setenv(DISCORD_WEBHOOK = "<live URL>")` — **hardcoded secret, see §2**.
- **`run_full_pipeline.R`** — Master DAG (13 stages, see §3.2). No inputs/outputs of its own beyond
  orchestrating; prints elapsed time per stage and total.
- **`schedule_daily.bat`** — Windows Task Scheduler target. 3 steps (see §3.1). Writes to
  `pipeline_execution.log` (append mode).
- **`pipeline_execution.log`** — Rolling text log of past automated runs (artifact, not code).

### Ingestion & rosters

- **`daily_ingest.R`** — `daily_box_ingest()`: loads `box_scores_cache.rds`, pulls current-season
  updates via `hoopR::load_nba_team_box(seasons = CURRENT_SEASON)`, dedupes on `(game_id, team_id)`,
  re-saves. Full historical bootstrap (`ALL_SEASONS`) if cache absent. Auto-runs if executed as a
  top-level script (`sys.nframe() == 0`).
- **`sync_rosters.R`** — `sync_active_rosters()`: pulls all 30 team IDs from ESPN teams endpoint, then
  one roster call per team (`Sys.sleep(0.05)` between calls), builds
  `team_name/team_id/player_id/player_name/position/jersey`, saves
  `cache/active_rosters_cache.rds`. Standardizes franchise display names via regex (handles "Trail
  Blazers"/"76ers" specially, else takes last word of team name).
- **`injury_scraper.R`** — `fetch_live_nba_injuries()`: hits ESPN's public injuries JSON endpoint,
  normalizes status strings to `Out/Doubtful/Questionable/Probable`, else falls back to a **hardcoded
  6-player offseason sample** (Porzingis, Kawhi, Embiid, Middleton, OG Anunoby, GG Jackson with
  specific `player_id`s) when the live feed returns nothing (i.e., offseason). Saves
  `cache/injury_data_cache.rds`.

### Player-level metrics (Phase 1, legacy path)

- **`player_metrics.R`** — `get_player_box_scores_chunked()`: chunked per-season
  `hoopR::load_nba_player_box()` pulls with retry/backoff, cached to
  `cache/player_box_scores_cache.rds`. `calculate_bpm_components()`: computes a hand-tuned per-36-minute
  linear BPM approximation (weights: PTS 0.60, REB 0.70, AST 1.05, STL 1.40, BLK 1.15, TOV -1.20,
  missed FGA -0.45, missed FTA -0.35, 3PM +0.30, replacement-level anchor -2.0). `get_player_features()`:
  aggregates to team-game level — `team_weighted_bpm` (minutes-weighted), `team_top5_bpm` (mean of top 5
  by BPM), `team_minutes_concentration` (HHI of minutes). No own persisted output; returns a tibble
  consumed by other scripts.
- **`lineup_synergy.R`** — `get_lineup_features()`: per game/team, computes `top5_combined_pts`,
  `minutes_hhi`, `star_overlap_pct` (both top-2 minute-earners played ≥30 min), `lineup_continuity_score`.
  Depends on `player_metrics.R`'s chunked loader. No persisted cache.
- **`roster_dynamics.R`** — `get_roster_continuity()`: season-over-season `returning_minutes_pct` per
  team (minutes retained from players present in both consecutive seasons) and
  `roster_stability_score = max(0.20, returning_minutes_pct)`. `apply_continuity_adjustment()`: shrinks
  rolling features toward league mean by `(1 - roster_stability_score)`. No persisted cache.

### Embeddings

- **`team_embeddings.py`** — Reads `cache/games_for_embeddings.csv` (`home_team, away_team, home_win`).
  If PyTorch is importable: trains a tiny `TeamEmbeddingNet` (30×16 embedding table, concat →
  Linear(32,8)→ReLU→Linear(8,1), sigmoid + home-court bias scalar), Adam lr=0.01, BCE loss, 120 epochs,
  CPU only. Else: falls back to a 16-rank truncated SVD of the pairwise win-differential matrix (pure
  NumPy, no PyTorch dependency). Either path writes `team_embeddings.csv` (16-D vectors per team) and
  `team_similarity_matrix.csv` (30×30 cosine similarity). If the CSV source doesn't exist, generates a
  1,000-row random mock instead of failing.
- **`load_embeddings.R`** — `get_team_embeddings()`: thin reader/loader for `team_embeddings.csv` into a
  tibble with `team_id` coerced to integer.

### Injury/fatigue/schedule

- **`injury_load_tracker.R`** — `get_schedule_features()`: per team-game, `days_since_prior`,
  `is_back_to_back`, `is_3_in_4`, `is_4_in_5`, `travel_flag` (home/away transition), composite
  `schedule_fatigue_index = 1.5*b2b + 1.0*3in4 + 1.0*4in5 + 0.5*travel`. `load_injury_data()`: reads
  `cache/injury_data_cache.rds` or returns an empty typed tibble. `team_availability_score()`: maps
  injury status → probability-out weight (`Out=1.0, Doubtful=0.75, Questionable=0.50, Probable=0.10`),
  combines with player BPM to compute a team availability multiplier floored at 0.70.
- **`fatigue_travel_engine.R`** — `ARENA_DB`: hardcoded lat/lon/timezone-offset/altitude for all 30 NBA
  arenas. `haversine_dist_miles()`: great-circle distance. `calculate_travel_fatigue()`: combines
  distance tax, timezone/circadian tax (east > west), altitude tax (Denver/Utah, worse on 0 days rest),
  and back-to-back tax into `fatigue_drag_pts`. `evaluate_slate_fatigue()` runs this over a **hardcoded
  4-game sample slate** and writes `cache/travel_fatigue_metrics.rds`. Auto-runs when sourced
  non-interactively.

### Modeling / rating engines

- **`rapm_engine.R`** — `solve_ridge_rapm()`: generic weighted ridge regression via sparse normal
  equations (`Matrix` package) for a stint design matrix. `estimate_rapm_ratings()`: **generates a fully
  synthetic stint dataset** (30 teams × 10 players, 6,500 random stints, `set.seed(42)`, true off/def
  ratings drawn from `rnorm`), solves ridge with `lambda=1850`, writes `cache/rapm_ratings.rds`
  (`player_id, team, orapm, drapm, total_rapm`). There is no real play-by-play/lineup ingestion feeding
  this yet — it demonstrates the RAPM math on fabricated data (wishlist W7 says "replace regularized BPM
  with full possession-by-possession ridge using real 5-man stint matrices" — not yet done).
- **`roster_bottom_up_engine.R`** — The core "real" team-rating engine.
  `get_player_bpm_ratings()`: reads real `cache/player_box_scores_cache.rds`, computes per-36 box
  creation (`0.55*PTS+0.60*REB+1.10*AST+1.40*STL+1.20*BLK-1.25*TOV`) fused 50/50 with a
  minutes-shrunk empirical plus-minus (`shrinkage = min/(min+500)`), season-2025+ weighted 1.5x, output
  bounded to [-5, 12]. `compute_team_live_rating()`: joins real `active_rosters_cache.rds` to those BPM
  ratings (primary key `athlete_id`/`player_id`, fallback `player_name`), replacement level -2.0 BPM for
  unmatched/rookies, applies live injury-status minute haircuts, selects top-9 rotation by
  `avg_min*(bpm+5.5)`, allocates 240 team-minutes proportionally, nets to a bounded team rating
  ([-10.5, 14.0]). `predict_live_matchup()`: single H2H spread/ML calculator (HCA=2.4,
  sigma=11.8). `project_all_30_teams()`: **auto-runs on source** — recenters all 30 team ratings to
  exactly 0 mean, simulates a zero-sum round-robin 82-game schedule (`pnorm(margin/11.8)`), guarantees
  Σwins ≈ 1230 (μ=41), writes `cache/projected_30_team_standings.rds`. `get_fair_spread(home, away)`:
  interactive query helper against the saved standings.
- **`live_calibration.R`** — Pure utility/library file (no auto-run): `american_to_prob()`,
  `remove_vig()`, `calibration_analysis()` (Brier/BSS/log-loss + reliability plot),
  `load_market_odds()` (10-game **synthetic** fixture stub), `compare_model_vs_market()`,
  `simulate_live_game()` (4-quarter logit-space in-play drift simulation, decay factor 0.70,
  divisor 3.0). Sourced by `bet_tracker.R`, `roster_bottom_up_engine.R`, `enhanced_model.R` (indirectly)
  for the odds-math helpers.
- **`shot_quality_engine.R`** — `calc_expected_shot_prob()`: distance-bucketed expected FG% curve
  (rim/short mid/long mid/corner-3/above-break-3/deep). `generate_team_shot_profiles()`: **fully
  synthetic** 30-team, 15-game simulated shot distributions (team 3pt-heavy flags hardcoded for
  BOS/GSW/DAL/MIL/SAC; talent tiers hardcoded for BOS/DEN/OKC vs CHA/DET/WAS/POR), computes
  `shooting_luck_pts = actual - expected` and a `regression_signal` (OVERVALUED/UNDERVALUED/NEUTRAL).
  Writes `cache/team_shot_quality.rds`. Auto-runs on source.
- **`xpoints_engine.R`** — Standalone prototype (not called by `run_full_pipeline.R`). Attempts
  `stats.nba.com` shotchartdetail with spoofed headers; on failure (typical) falls back to
  `generate_synthetic_shots()`. Fits `glm(shot_made ~ shot_distance + factor(shot_value))`, reports
  actual vs expected points and a "luck" residual. No cache output — console-only demonstration script.
- **`enhanced_model.R`** — One-off retraining script (not in daily DAG). Reads real `box_scores_cache.rds`,
  builds 18-game rolling differentials (reuses the Rmd's feature logic), joins
  `get_schedule_features()` (fatigue) and `get_team_embeddings()` (style similarity via cosine sim of
  16-D vectors), trains `ranger` RF (300 trees) and `xgboost` (200 trees, depth 4) via `tidymodels`
  workflows on strict home/away differential features only (raw components stripped in the recipe to
  avoid leakage), evaluates on 2026 out-of-sample season, prints feature-importance table, saves
  `cache/enhanced_rf_fit.rds`. This produced the Phase-2 benchmark numbers in
  `engineering_log_phase2.md`.

### Betting / market layer

- **`market_odds_engine.R`** — `fetch_market_odds()`: The Odds API call (see §2) or hardcoded 6-game
  fallback slate. `parse_multi_book_feed()`: per-game, per-bookmaker parsing of `h2h` market outcomes,
  UTC→America/New_York tip-time conversion, best-price shopping across books, sharp-book detection
  (pinnacle/circa/lowvig/betonlineag). `get_model_slate_probabilities()`: pulls
  `cache/projected_30_team_standings.rds` net ratings, adjusts by shot-quality luck (`-0.5*luck`) and
  fatigue drag if those caches exist, else falls back to devigged market consensus as the "model"
  probability. `evaluate_betting_slate()` (auto-runs on source): computes home/away EV%, expected CLV%
  vs consensus, Quarter-Kelly stake (`calculate_kelly`, capped at 3% bankroll), tags each game
  `🔥 SHARP +EV` (EV≥5% & CLV>0), `★ VALUE BET` (EV≥3%), or `No Action`. Appends a timestamped snapshot to
  `cache/odds_history.rds` and writes `cache/latest_value_bets.rds`.
- **`player_props_engine.R`** — ZINB (Zero-Inflated Negative Binomial) pricing. Fixed per-category
  dispersion (`theta`) and zero-inflation (`pi_0`) constants for PTS/REB/AST/FG3M/STL/BLK.
  `price_prop_zinb()`: computes fair over/under probabilities, decimal-odds EV, Quarter-Kelly stake per
  prop. `generate_active_props_table()`: reads `cache/active_rosters.rds` if present (note: different
  filename than `sync_rosters.R`'s `active_rosters_cache.rds` — likely a naming mismatch/bug), else
  **fabricates** an 8-player-per-team × 30-team synthetic rotation with hand-set per-player stat means.
  Writes both `latest_player_props.rds` (root) and `cache/latest_player_props.rds`.
- **`copula_props_engine.R`** — Multivariate Gaussian copula (`mvtnorm::rmvnorm`) over PTS/REB/AST with
  a fixed 3×3 correlation matrix (PTS-AST +0.18, PTS-REB +0.12, REB-AST -0.08), transforms through
  ZINB inverse-CDF marginals (`qzinb_approx`), computes joint PRA over/under, double-double/triple-double
  probabilities, and compares against a naive independent-Poisson convolution to show the "copula edge".
  `run_copula_suite()` runs one hardcoded example (Nikola Jokic, mu_pts=26.4/mu_reb=12.3/mu_ast=9.2,
  line=47.5), writes `cache/copula_jokic_pra.rds`. Not parameterized over the full roster yet.
- **`bet_tracker.r`** (lowercase `.r` — note the inconsistent extension) — `get_bet_ledger()`: loads
  `cache/betting_ledger.rds` or seeds a synthetic 30-day/2-bets-per-day historical ledger.
  `append_todays_picks()`: pulls `★`/`VALUE`-tagged rows from `latest_value_bets.rds`, appends as
  `PENDING` (dedup by team+date). `grade_yesterday_bets()` (auto-runs on source): joins pending bets to
  `box_scores_cache.rds` on `(team_picked, bet_date)` ↔ `(team_short_display_name, game_date)` to
  determine WIN/LOSS, computes realized CLV% against `closing_odds`, recomputes rolling 7d/30d/all-time
  win rate, ROI%, avg CLV, beat-CLV rate, writes `cache/betting_ledger.rds` and
  `cache/rolling_bet_metrics.rds`.
- **`notify_bets.R`** — Loads `latest_value_bets.rds`, filters `EV≥3.0% & CLV≥-0.5%` (falls back to top
  3 by EV if nothing qualifies), builds a Discord embed (title, per-game fields with pick/book/odds/EV/
  CLV/Kelly stake), POSTs to `DISCORD_WEBHOOK_URL`. Console-prints the same info regardless of whether
  Discord is configured.
- **`risk_management_engine.R`** — `compute_risk_state()`: loads `cache/bet_log.rds` (note: yet another
  differently-named ledger file not otherwise referenced elsewhere in the repo — appears to be dead/stale
  path; falls back to a synthetic 120-bet ledger) or real data if present. Computes cumulative
  bankroll path (base 100 units), high-water-mark drawdown, and a **tiered Kelly-scaling policy**:
  0.25 normal / 0.175 at ≥3-unit drawdown / 0.10 at ≥5-unit drawdown / 0.00 ("TRADING_HALT") at
  ≥8-unit drawdown. Writes `cache/risk_state.rds` (consumed by `app.R` Tab 4).

### Live / in-game

- **`live_game_listener.R`** — `calc_live_win_prob()`: time-remaining-weighted margin model
  (48-min game clock, `sqrt(time_frac)` variance decay) — independent of, and simpler than,
  `live_calibration.R`'s logit-drift version. `send_live_steam_snipe_alert()`: Discord alert with
  10-minute per-game de-dup (`ALERT_LOG`). `poll_live_inplay_steam()`: iterates a **single hardcoded
  fake live game** (`BOS_NYK_LIVE`) comparing DraftKings vs Pinnacle mock live prices; fires an alert if
  the pre-game favorite trails by ≥8 in Q2 and EV≥8%. `ODDS_API_KEY` is read but **not actually used**
  anywhere in this file yet — wishlist item (Phase 4 recommendation #2 / handoff Priority 2) to wire it
  to The Odds API's live in-play endpoint is not yet implemented.
- **`playoff_simulator.R`** — `get_playoff_adjusted_rating()`: boosts a team's regular-season net
  rating using top-3 RAPM average (from `cache/rapm_ratings.rds`, itself synthetic — see above) times
  0.35, or a hardcoded contender-leverage table if RAPM missing. `simulate_single_series()`: 10,000-sim
  best-of-7 (2-2-1-1-1 home schedule), tracks exact scorelines, series win probability, fair series
  moneyline, and spread-cover probabilities (series -1.5/-2.5 games). `simulate_playoff_suite()`
  auto-runs one hardcoded example (BOS vs NYK), writes `cache/playoff_series_bos_nyk.rds`.

### Dashboard

- **`app.R`** — Single-file Shiny app (`shinydashboard` + `DT` + `ggplot2`), dark theme via custom CSS.
  8 tabs, each reactively reading `cache/*.rds` (falling back to inline synthetic data or re-running the
  relevant engine script if a cache is missing — so the app never crashes on cold start):
  1. **Daily Actionable Edges** — `latest_value_bets.rds` table with date filter, EV/CLV/Kelly columns.
  2. **Steam Radar & Line Movement** — derives open/current/sharp line drift from `odds_history.rds`.
  3. **Injury & Load Monitor** — `injury_data_cache.rds` table with a hardcoded spread-impact heuristic
     by status string.
  4. **Bet Tracker & Performance Audit** — KPI boxes (rolling 7d/30d CLV%, beat-CLV rate, current
     drawdown) + bankroll area chart + risk-engine status text + full graded ledger, all from
     `risk_state.rds`.
  5. **Team Embeddings & Similarity** — scatter of points-created vs shooting-luck from
     `team_shot_quality.rds` (mislabeled as "embeddings" in the UI — it does not actually plot the
     16-D `team_embeddings.csv` vectors).
  6. **Model Calibration & Reliability** — **hardcoded/simulated** calibration curve (not read from any
     real model's predictions) — cosmetic placeholder.
  7. **30-Team Standings & Matchup Calc** — `projected_30_team_standings.rds` table + interactive
     home/away team picker computing fair spread/win-prob/ML client-side (re-implements
     `get_fair_spread()`'s math inline).
  8. **Player Proposition Terminal (PRA Alpha)** — `latest_player_props.rds`/ZINB filters
     (stat/EV/side/name), per-row ZINB density plot.

### Baseline analysis documents (do not modify per ADR)

- **`NBA_Analysis_Project.Rmd`** / **`NBA_Analysis_Project.pdf`** — Current published baseline: hoopR
  team box 2019–2026, 18-game rolling features, 3 offseason-transition methods compared (reset vs 50%
  regress vs 80/20 decay — "reset" won and is what `config.R`'s `OFFSEASON_METHOD` is set to), 3 model
  architectures compared (LogReg/RF/XGBoost — RF won), 10,000-sim Monte Carlo 2027 season projection.
- **`NBA_Analysis_Project - Original -no Llm.Rmd`** / **`.pdf`** — An earlier/manual (non-LLM-assisted)
  version of the same report, kept as a historical comparison point.

---

## 5. R Package Dependencies (grepped from all `library()`/`require()` calls)

Core: `tidyverse` (includes dplyr/tidyr/ggplot2/purrr/stringr/readr), `hoopR`, `slider`, `tidymodels`,
`ranger`, `xgboost`, `Matrix`, `mvtnorm`.

HTTP/JSON: `httr`, `httr2`, `jsonlite`.

Dashboard: `shiny`, `shinydashboard`, `DT`, `scales` (plus `ggplot2`, `dplyr`, `tidyr` already listed).

Reporting: `knitr` (used via `knitr::kable(...)` throughout — not always explicitly `library()`'d),
`ggridges` (Rmd only, for Monte Carlo ridge plots).

Python (`team_embeddings.py`): `pandas`, `numpy`, optionally `torch` (graceful fallback to pure NumPy
SVD if unavailable — no `requirements.txt` exists, dependency is entirely implicit/try-import).

No `renv.lock`, `DESCRIPTION`, or `requirements.txt` exists anywhere in the repo — dependencies are
managed by ambient R/Python environment only. `app.R` self-installs missing packages via
`install.packages()` at the top (only for the dashboard-specific set: shiny/shinydashboard/DT/ggplot2/
dplyr/tidyr/scales) — no other script does this.

---

## 6. Data Artifacts & Caching

Two cache locations are used inconsistently:
- **Project root** (`PROJECT_DIR`): `box_scores_cache.rds` (team box, ~20K rows), `team_embeddings.csv`,
  `team_similarity_matrix.csv`, `latest_player_props.rds` (a root-level duplicate of
  `cache/latest_player_props.rds`).
- **`cache/`** (`CACHE_DIR`, auto-created by `config.R`): `player_box_scores_cache.rds` (player box,
  200K+ rows), `active_rosters_cache.rds`, `injury_data_cache.rds`, `team_shot_quality.rds`,
  `travel_fatigue_metrics.rds`, `rapm_ratings.rds`, `projected_30_team_standings.rds`,
  `latest_value_bets.rds`, `odds_history.rds`, `latest_player_props.rds`, `copula_jokic_pra.rds`,
  `playoff_series_bos_nyk.rds`, `risk_state.rds`, `betting_ledger.rds`, `rolling_bet_metrics.rds`,
  `enhanced_rf_fit.rds`, `games_for_embeddings.csv` (input to `team_embeddings.py`).

Known filename mismatches (verify before relying on any of these in new code):
- `player_props_engine.R` reads `cache/active_rosters.rds`, but `sync_rosters.R` writes
  `cache/active_rosters_cache.rds` — these never actually connect; the props engine always falls back
  to its synthetic roster.
- `risk_management_engine.R` reads `cache/bet_log.rds`, which nothing else in the repo writes; it
  always falls back to its synthetic ledger. The *real* ledger lives at `cache/betting_ledger.rds`
  (written by `bet_tracker.r`) and is a different schema.
- `.rds` is R's native single-object serialization format (binary, not portable across languages
  without `pyreadr`/similar). All caches are `readRDS`/`saveRDS`.

All caching is "fail-safe": nearly every script checks `file.exists()` and either loads the cache,
re-fetches from a live source, or — commonly — generates a plausible synthetic substitute so the
pipeline never hard-crashes on a cold machine. This is a deliberate design principle (`ADR.md`
Principle III), but it means "the pipeline ran successfully" does **not** guarantee real data was used
anywhere past the roster/injury layer unless you specifically verify each cache file's provenance.

---

## 7. Betting / Notification Layer Summary

- **Odds source**: The Odds API (`basketball_nba`, `h2h` market only currently; live in-play `h2h` is
  referenced but not implemented) with a hardcoded fixture fallback.
- **Model probability**: bottom-up player-composed net ratings (`roster_bottom_up_engine.R`) adjusted by
  shot-quality "luck" residual and travel/fatigue drag, converted to win probability via
  `pnorm(margin/11.2)` (note: 11.2 here vs 11.8 in `roster_bottom_up_engine.R`'s own internal
  `pnorm(margin/11.8)` — two slightly different sigma constants coexist across files; not unified).
- **Edge criteria**: `🔥 SHARP +EV` = EV≥5% AND CLV>0%; `★ VALUE BET` = EV≥3%; else "No Action".
  `notify_bets.R` uses a looser bar (EV≥3% & CLV≥-0.5%) for what actually gets Discord-alerted.
- **Staking**: Quarter-Kelly (`0.25 × Kelly fraction`), capped at 3% of bankroll per bet
  (`market_odds_engine.R`), separately scaled down by `risk_management_engine.R`'s drawdown-tiered
  multiplier (0.25 → 0.175 → 0.10 → 0.00) — these two Kelly-scaling mechanisms are not currently wired
  together in code (risk engine's multiplier isn't read back into `calculate_kelly()`'s `fraction` arg
  anywhere); reconciling them would be a natural next step, not something already done.
- **Ledger & grading**: `bet_tracker.r`, compound-key join on `(team_picked, game_date)==(team_name,
  bet_date)` against real box scores, tracks CLV% realized vs the closing sharp line.
- **Notification**: Discord webhook only (no SMS/Telegram/push despite `next_researcher_handoff_prompt.md`
  mentioning "Discord/Telegram" — Telegram was never implemented).

---

## 8. Shiny App Summary

See §4 "Dashboard" above for the full 8-tab breakdown. Key point for extension: **every reactive in
`app.R` reads from disk (`cache/*.rds` or root `.rds`/`.csv`) and never calls a live API directly** —
this is intentional (ADR-08 / T7: "zero live API dependencies on load"). If you add a WNBA version of
this dashboard, preserve that pattern; do not make `app.R` itself perform network I/O.

---

## 9. Known Issues / Wishlist (from `phase4_recommendations_and_wishlist.md`, `wishlist.md`,
`next_researcher_handoff_prompt.md`)

Still open as of the current code (verified by inspection, not just doc claims):
- **W7 / RAPM**: `rapm_engine.R` is still synthetic-stint-only; no real lineup/stint ingestion exists.
- **Tab 6 calibration curve** in `app.R` is a hardcoded fake curve, not computed from real model
  predictions — despite `live_calibration.R` having a fully working `calibration_analysis()` function
  that is never actually wired into the dashboard.
- **Live in-play odds integration** (Phase 4 Rec #2 / Handoff Priority 2): `live_game_listener.R` still
  polls one hardcoded fake game; `ODDS_API_KEY` is read but unused there.
- **ZINB done, but props roster is still synthetic**: `player_props_engine.R`'s ZINB math (Phase 4 Rec
  #3) is implemented, but it's fed by a fabricated 8-player/team roster because of the
  `active_rosters.rds` vs `active_rosters_cache.rds` filename mismatch noted in §6.
- **Copula engine** (Phase 5 wishlist) is implemented but only demonstrated on one hardcoded player
  (Jokic) — not run across the full roster.
- **Risk engine ↔ Kelly sizing** not reconciled (see §7).
- **`app.R` "Team Embeddings" tab** doesn't actually visualize the 16-D embeddings.
- Filename/path inconsistencies noted throughout (`active_rosters.rds` vs `active_rosters_cache.rds`,
  `bet_log.rds` vs `betting_ledger.rds`, root vs `cache/` duplication of some `.rds` files, `bet_tracker.r`
  lowercase extension vs everything else `.R`).
- Two different sigma constants (11.2 vs 11.8) for the margin→probability normal-CDF conversion across
  `market_odds_engine.R` vs `roster_bottom_up_engine.R`/`playoff_simulator.R`.
- `schedule_daily.bat` and `run_full_pipeline.R` overlap (both eventually call bet grading / odds
  evaluation) — not unified into one clean invocation.

---

## 10. Config / Secrets Required

| Name | Where read | Required? | Notes |
|---|---|---|---|
| `ODDS_API_KEY` | `market_odds_engine.R` (`Sys.getenv("ODDS_API_KEY","")`) | Optional | Empty → silent fallback to fixture slate. Get a key from the-odds-api.com. |
| `THE_ODDS_API_KEY` | `live_game_listener.R` (`Sys.getenv("ODDS_API_KEY", Sys.getenv("THE_ODDS_API_KEY", ""))`) | Optional, currently unused downstream | Legacy fallback name. `live_game_listener.R` now reads `ODDS_API_KEY` first (matching `market_odds_engine.R`) and falls back to `THE_ODDS_API_KEY` if only that is set — no longer an inconsistency, fixed per issue #9. |
| `DISCORD_WEBHOOK` | `notify_bets.R`, `live_game_listener.R` | Effectively always set | **Hardcoded live value in `config.R` line 37** via `Sys.setenv(...)`. Treat as an exposed credential — rotate/regenerate this webhook before any public sharing of this repo, and do not carry the literal value into the WNBA project; generate a fresh webhook instead. |

No `.Renviron`, `.env`, or credentials file exists — the one real secret lives in plaintext in
`config.R` itself.
