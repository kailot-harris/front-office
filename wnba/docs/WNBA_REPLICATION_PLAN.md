# WNBA Replication Plan

Goal: replicate the NBA Analytics system (see `REPO_MAP.md` for the full inventory of what exists
today) into a **new sibling directory** `C:\Users\kailo\kayceeslices\WNBA Analytics`, swapping every
NBA-specific data source for a WNBA equivalent. This document is a plan only — no code or folder has
been created yet.

Read `REPO_MAP.md` first. Everything below assumes familiarity with that file's file-by-file inventory,
including which engines already run on synthetic/fabricated data today (RAPM, shot quality, fatigue
slate, props roster, copula, playoff sim, risk ledger) — that matters a lot for scoping, because those
engines need **zero data-source porting work**; they need parameter changes only (roster size, game
count, team list).

---

## (a) Directory Scaffold

Create `C:\Users\kailo\kayceeslices\WNBA Analytics\` as a sibling of `NBA Analytics`, not nested inside
it. Mirror the flat, non-namespaced layout of the NBA repo (this codebase does not use subpackages —
everything lives at repo root plus a single `cache/` subfolder):

```
WNBA Analytics/
├── config.R                          (ported, WNBA constants)
├── daily_ingest.R                    (ported, wehoop loader)
├── player_metrics.R                  (ported, wehoop loader)
├── injury_load_tracker.R             (ported, schedule math is source-agnostic)
├── injury_scraper.R                  (ported, new WNBA injury endpoint)
├── lineup_synergy.R                  (ported as-is, just depends on player_metrics.R)
├── roster_dynamics.R                 (ported as-is)
├── team_embeddings.py                (ported, 13 teams not 30 — see §b)
├── load_embeddings.R                 (ported as-is)
├── live_calibration.R                (ported as-is — pure math, sport-agnostic)
├── enhanced_model.R                  (ported, retrain on WNBA data)
├── sync_rosters.R                    (ported, new ESPN WNBA endpoint)
├── roster_bottom_up_engine.R         (ported, roster size / minutes constants changed)
├── rapm_engine.R                     (ported, team/roster-size constants changed — still synthetic)
├── market_odds_engine.R              (ported, basketball_wnba sport key)
├── player_props_engine.R             (ported, WNBA team list + prop lines)
├── copula_props_engine.R             (ported as-is — sport-agnostic math)
├── shot_quality_engine.R             (ported, WNBA team list — still synthetic)
├── fatigue_travel_engine.R           (ported, new WNBA arena lat/lon/altitude table)
├── playoff_simulator.R               (ported, best-of-5 first round vs best-of-7 — see §b)
├── risk_management_engine.R          (ported as-is — sport-agnostic bankroll math)
├── live_game_listener.R              (ported, basketball_wnba live odds)
├── notify_bets.R                     (ported as-is, new webhook)
├── bet_tracker.r                     (ported as-is)
├── run_full_pipeline.R               (ported, same 13-stage DAG)
├── schedule_daily.bat                (ported, adjusted for WNBA season window — see §e)
├── app.R                             (ported, title/branding + 12-team WNBA constants)
├── xpoints_engine.R                  (ported, drop stats.nba.com endpoint — no WNBA equivalent, keep synthetic-only)
├── NBA_Analysis_Project.Rmd → WNBA_Analysis_Project.Rmd (new baseline report, wehoop instead of hoopR)
├── cache/                            (created at runtime by config.R, same filenames)
└── box_scores_cache.rds, team_embeddings.csv, team_similarity_matrix.csv, latest_player_props.rds
                                       (created at runtime, root-level, same as NBA repo)
```

Do not literally copy `.rds`/`.csv` cache files from the NBA repo — WNBA needs its own caches built
from scratch via the ported ingestion scripts.

---

## (b) Per-Script Porting Notes

### Tier 1 — Copy nearly as-is (pure math / sport-agnostic; change only cosmetic constants or nothing)

- **`live_calibration.R`** — odds math, Brier/BSS/log-loss, logit-drift simulation. Zero changes needed
  beyond removing the NBA-specific `load_market_odds()` fixture team-ID list (cosmetic).
- **`risk_management_engine.R`** — bankroll/drawdown/Kelly-tier math is entirely sport-agnostic. Copy
  verbatim.
- **`copula_props_engine.R`** — Gaussian copula + ZINB math is sport-agnostic. Only the one hardcoded
  demo player (swap "Nikola Jokic" example for a WNBA star, e.g. A'ja Wilson) needs updating; correlation
  matrix and dispersion parameters can stay as a starting point and be re-fit later against real WNBA
  player game logs once available.
- **`live_calibration.R`**, **`notify_bets.R`**, **`bet_tracker.r`** — copy as-is; only the Discord
  webhook env var value changes (generate a **new** webhook — do not reuse the NBA one, see
  `REPO_MAP.md` §10 on the exposed credential).
- **`load_embeddings.R`** — trivial CSV loader, copy as-is.

### Tier 2 — Copy with source-URL / endpoint swap only (logic unchanged)

- **`daily_ingest.R`, `player_metrics.R`** — Replace `hoopR::load_nba_team_box()` /
  `hoopR::load_nba_player_box()` with **`wehoop::load_wnba_team_box()`** /
  **`wehoop::load_wnba_player_box()`** (same call signature/idiom — wehoop is built by the same
  SportsDataverse team as hoopR and intentionally mirrors its API). Season range must change: WNBA
  seasons run May–October (vs NBA Oct–June), and WNBA has many fewer historical seasons of clean
  ESPN-backed box data than NBA's 2019–2026 span — start with whatever wehoop's `load_wnba_team_box()`
  covers cleanly (verify actual season coverage at load time; wehoop advertises play-by-play back to
  2002, but team/player box completeness may vary by year — validate row counts before trusting a
  season). `ROLLING_WINDOW_SIZE` should shrink (see §b roster/season-length note below).
- **`sync_rosters.R`, `injury_scraper.R`** — ESPN's public site-API CDN also serves the WNBA under a
  parallel path: swap `.../sports/basketball/nba/...` for `.../sports/basketball/wnba/...` (teams,
  roster, and injuries endpoints all exist under the same ESPN site-api structure used for NBA; this is
  the same undocumented-but-stable public JSON API, so the `httr2` code needs no structural change,
  only the URL segment). Team-name canonicalization regex in `sync_rosters.R`/`market_odds_engine.R`
  (`resolve_team_name()`, the 30-team `case_when` list) must be entirely rewritten for the 13 WNBA
  franchises (Aces, Sky, Sun, Dream, Fever, Mercury, Sparks, Storm, Liberty, Lynx, Mystics, Wings, and
  the 2026 Golden State Valkyries as a 13th team — verify the current-season franchise count before
  building this list, expansion has been active).
- **`market_odds_engine.R`, `live_game_listener.R`** — The Odds API supports WNBA natively under sport
  key **`basketball_wnba`** (confirmed: the-odds-api.com publishes a dedicated WNBA odds product with
  moneyline/spreads/totals plus player props via the event-odds endpoint). Swap the URL's
  `basketball_nba` segment for `basketball_wnba`; the rest of the parsing logic
  (`parse_multi_book_feed`, sharp-book key detection) is unchanged. Note: WNBA book coverage is
  thinner — see §e risks.
- **`team_embeddings.py`** — logic unchanged; only the team count changes from 30 to the current WNBA
  team count (13 as of 2026, expanding), which shrinks the embedding table and the trainable-parameter
  count even further below the NBA case's already-trivial ~750 params — CPU-only execution remains
  correct and arguably even more clearly justified.
- **`fatigue_travel_engine.R`** — Rebuild `ARENA_DB` with WNBA arena lat/lon/timezone/altitude (13
  arenas instead of 30 — most in lower-altitude cities than NBA's Denver/Utah outliers, so the
  altitude-tax branch may rarely trigger; keep the logic, just note it's a smaller effect for WNBA
  unless/until a Denver-altitude WNBA market exists).
- **`shot_quality_engine.R`, `rapm_engine.R`, `playoff_simulator.R`** — these are already
  synthetic/simulated engines in the NBA repo (see `REPO_MAP.md` §1 caveat); "porting" them is just
  changing the hardcoded 30-team abbreviation list to the 13 WNBA team abbreviations and adjusting
  roster-size constants (`players_per_team <- 10` in `rapm_engine.R` should become `players_per_team <-
  12` to match WNBA's max 12-player active roster, see below). No real data-source work required since
  none of these currently consume a live feed.

### Tier 3 — Requires real logic changes (roster/season/format differences)

- **Roster size (12 vs 15)**: WNBA active rosters are capped at 12 (vs NBA's 15-man active roster,
  13-man minimum + two-way slots). Affects:
  - `roster_bottom_up_engine.R`: `compute_team_live_rating()`'s `slice_head(n = 9)` (top-9 rotation)
    should probably shrink to **top-7 or top-8** rotation players — WNBA teams commonly play an
    8-to-9-player rotation in a 40-minute game, proportionally similar to NBA's 9-man/48-minute
    rotation, but verify against real WNBA minutes distributions once box data is loaded rather than
    guessing a fixed number.
  - `rapm_engine.R`: `players_per_team <- 12` (was 10 — NBA script used 10 as an arbitrary rotation
    depth, not the actual 15-man roster; WNBA equivalent rotation depth is smaller, ~8–9).
  - `player_props_engine.R`: synthetic roster generator's `1:8` players-per-team synthetic fallback
    should shrink to `1:7` or `1:8` to match realistic WNBA rotation depth.
- **Game length (40 vs 48 minutes)**: WNBA games are 4×10-minute quarters (40 min regulation) vs NBA's
  4×12 (48 min). This changes several hardcoded constants:
  - `roster_bottom_up_engine.R`: `tot_proj_min <- 240` (48×5) → **`200`** (40×5) for the 240-minute
    team-minute allocation logic; `allocated_min = (hist_avg_min / tot_proj_min) * 240` → `* 200`.
  - `live_game_listener.R` / `live_calibration.R`: `total_seconds <- 2880` (48 min) → **`2400`**
    (40 min) for live win-probability time-remaining fractions.
  - Point-differential-to-probability sigma constants (11.2 / 11.8 in various files, calibrated from
    NBA scoring variance) need **re-derivation from WNBA score-margin variance** once real WNBA game
    data is loaded — WNBA final margins have different variance than NBA's due to shorter games and
    different pace; do not assume the same sigma transfers. Treat 11.2/11.8 as NBA-specific priors to
    be replaced by an empirically fit value (e.g., via `sd()` of historical WNBA home-margin residuals)
    before trusting spread/ML outputs.
- **Season length (~40 games vs 82)**: WNBA regular season is ~40–44 games (2024+ expanded schedule)
  vs NBA's 82. Affects:
  - `config.R`: `ROLLING_WINDOW_SIZE <- 18` (NBA, ~22% of an 82-game season) → scale proportionally,
    e.g. **`ROLLING_WINDOW_SIZE <- 9`** (~22% of a 40-game season), and re-validate empirically —
    don't just port the fraction blindly, re-run the same "test window sizes" experiment the NBA Rmd
    presumably did originally.
  - `roster_bottom_up_engine.R`: `games_per_opponent <- 82 / (n_teams - 1)` → `WNBA_SEASON_GAMES / (n_teams
    - 1)` where `WNBA_SEASON_GAMES` is config-driven (verify current season's official game count —
    it has changed multiple times, e.g. 34→36→40→44); the zero-sum invariant check
    (`sum(wins) == season_games * n_teams / 2`) ported unchanged, just with the new constant.
  - Monte Carlo season simulation in the WNBA Rmd equivalent: 10,000 sims over ~40 games instead of 82
    — same method, smaller schedule matrix.
- **Playoff format**: NBA `playoff_simulator.R` assumes best-of-7 (2-2-1-1-1) for all rounds. WNBA's
  best-of-7 format for the Finals is similar, but earlier rounds have historically used best-of-5 in
  some years and WNBA has changed formats before (single-elimination first round in some past seasons).
  **Verify the current-season official WNBA playoff format before porting** `simulate_single_series()`
  — the home-court flag sequence (`home_high_flags`) and win-threshold (`w_high < 4`) will need
  different values for a best-of-5 (`w_high < 3`, 2-2-1 home schedule) round if that format is in use.
  Do not assume NBA's format carries over uniformly across rounds.
- **Injury report format**: NBA's official injury report (referenced in `ADR.md` as a future PDF-parsing
  target, though the current code only uses ESPN's JSON feed, not the raw PDF) has a specific structure.
  WNBA's official injury report format/cadence differs and is far less granular/frequent — the league
  does not publish injury reports with the same NBA-style multi-times-daily cadence. Rely on the ESPN
  WNBA injuries JSON endpoint (Tier 2 swap above) as primary; expect **sparser and less frequently
  updated** data than NBA, and keep `injury_scraper.R`'s offseason-fallback pattern but broaden it to
  also trigger during any period where the live feed returns implausibly few rows (not just literal
  0), since partial/stale WNBA injury feeds are more likely than a clean "0 rows = offseason" signal.
- **`NBA_Analysis_Project.Rmd` baseline**: Do not port this by simple find-replace. Re-run the full
  offseason-transition-method comparison (reset vs 50% regress vs decay) and model-architecture
  comparison (LogReg/RF/XGBoost) from scratch on WNBA data, because the ~40-game season length changes
  which offseason-transition method is likely optimal (less in-season signal accumulates before
  cross-season noise starts to matter, so continuity-weighted or decay methods may outperform "fresh
  reset" more than they did for NBA — this needs actual re-benchmarking, not assumption).

---

## (c) Concrete API/Package Names & Access

| Need | NBA source | WNBA equivalent | Access / Auth | Rate limits / caveats |
|---|---|---|---|---|
| Historical + current-season team/player box scores | `hoopR::load_nba_team_box/player_box` | **`wehoop::load_wnba_team_box()`**, **`wehoop::load_wnba_player_box()`** (R package, install via `install.packages("wehoop")` or `pak::pak("sportsdataverse/wehoop")`) | None (public, no key) | Backed by ESPN; same polite chunking/retry pattern as `player_metrics.R` should be kept. Verify season coverage/completeness at load time — do not assume parity with hoopR's 2019–2026 depth. |
| Play-by-play / stint-level data (for a *real* future RAPM, unlike today's synthetic one) | none used yet (NBA RAPM is synthetic) | **`wehoop::load_wnba_pbp()`** and `load_wnba_stats_possessions()` (WNBA Stats API-backed) | None (public) | This is the concrete path to eventually replace the synthetic `rapm_engine.R` with real lineup stints — bigger lift, not required for MVP parity. |
| Team registry / rosters / injuries (JSON) | ESPN site API `.../basketball/nba/...` | ESPN site API **`.../sports/basketball/wnba/...`** (same host `site.api.espn.com`, same JSON shape) | None (public, undocumented) | Same fragility as NBA version — wrap in `tryCatch`, keep offline fallback. |
| Betting odds (moneyline/spread/totals + props) | The Odds API, sport key `basketball_nba` | **The Odds API, sport key `basketball_wnba`** | Free tier (500 req/mo) or paid plans at the-odds-api.com; same `ODDS_API_KEY` env var pattern | WNBA has fewer books offering markets and props than NBA — expect thinner `bookmakers[]` arrays per game and possibly no odds at all outside the WNBA season (May–Oct); confirmed WNBA markets include h2h/spreads/totals plus `player_points`/`player_rebounds`/etc. via the event-odds endpoint (different endpoint than the featured-markets endpoint used today in `market_odds_engine.R` — porting player props from The Odds API would require adding the event-odds call, which the current NBA code doesn't do either; NBA props today come from the in-house Poisson/ZINB model, not from a live market feed, so this is optional parity, not a blocker). Historical odds only from May 2022 onward, paid plans only. |
| Alternative box/team data source (fallback if wehoop gaps exist) | n/a | **balldontlie API** (balldontlie.io) — offers WNBA data alongside NBA under its multi-league API, has a generous free tier and a documented OpenAPI spec | Free tier signup key required | Newer/less battle-tested for WNBA specifically than wehoop; treat as a secondary/cross-check source, not primary, since wehoop is purpose-built by the same team that built hoopR (consistent schemas ease the port). |
| Notifications | Discord webhook | Discord webhook (new one) | Create a new Discord server/channel webhook URL | Free, no rate-limit concern at this volume. |
| Team geo/arena data | Hardcoded lat/lon/altitude table | Hand-build a 13-row WNBA `ARENA_DB` (public knowledge: arena city coordinates + published elevation) | N/A, no API | Manual one-time data-entry task, same pattern as NBA's hardcoded table. |

---

## (d) Phased Implementation Order

**Phase 0 — Scaffold & config (prerequisite for everything else)**
1. Create `WNBA Analytics/` directory; port `config.R` with WNBA constants (season range, rolling
   window, cache paths, new Discord webhook, `WNBA_SEASON_GAMES`, `WNBA_ROSTER_MAX <- 12`,
   `WNBA_GAME_MINUTES <- 40`).
2. Install `wehoop` and confirm `load_wnba_team_box()`/`load_wnba_player_box()` return usable data for
   at least the last 3–4 seasons before building anything on top.

**Phase 1 — Data foundation (must work before any modeling engine is testable)**
3. Port `daily_ingest.R` (wehoop team box) → validate `box_scores_cache.rds` row counts/schema.
4. Port `player_metrics.R` (wehoop player box, BPM constants likely reusable as a starting
   approximation since BPM's box-score weights are not NBA-specific, just recalibrate `-2.0`
   replacement-level anchor once real WNBA distributions are visible).
5. Port `sync_rosters.R` and `injury_scraper.R` (ESPN WNBA endpoints) → validate 13-team,
   ≤12-per-team roster counts.

**Phase 2 — Core rating engine (the thing everything else depends on)**
6. Port `roster_bottom_up_engine.R` with roster-size/minutes constants updated (Tier 3 changes above).
   This is the single most load-bearing script — market odds, props, playoffs, and the dashboard all
   read its output (`projected_30_team_standings.rds` → rename/repoint to a 13-team equivalent, keep
   the same filename for minimal downstream churn or rename consistently, e.g.
   `projected_wnba_standings.rds`, and update every reader).
7. Port `lineup_synergy.R`, `roster_dynamics.R` (no changes needed beyond the shared BPM/roster inputs).
8. Re-run and re-validate the offseason-transition + model-architecture comparisons in a new
   `WNBA_Analysis_Project.Rmd` baseline (per §b Tier 3 note) — this becomes the new "pristine reference"
   analog to the NBA Rmd; treat it with the same non-invasive-baseline discipline once finalized.

**Phase 3 — Fatigue/shot-quality/embeddings layer (depends on Phase 1–2 caches)**
9. Port `fatigue_travel_engine.R` (new arena DB), `shot_quality_engine.R` (team list swap, still
   synthetic), `team_embeddings.py`/`load_embeddings.R` (13-team, unchanged logic).

**Phase 4 — Market/betting layer (depends on Phase 2 ratings + external odds access)**
10. Port `market_odds_engine.R` with `basketball_wnba` sport key; validate against WNBA's actual
    in-season book coverage (test during May–Oct when live games exist; expect null results
    off-season — same fallback pattern as NBA).
11. Port `player_props_engine.R`/`copula_props_engine.R` (synthetic-to-start is fine, same as NBA today).
12. Port `bet_tracker.r`, `risk_management_engine.R`, `notify_bets.R` largely as-is.

**Phase 5 — Live layer & dashboard (last, since it depends on everything above)**
13. Port `live_game_listener.R` (40-minute game clock constants) and `playoff_simulator.R` (verify
    current playoff format first).
14. Port `run_full_pipeline.R` (same 13-stage DAG, WNBA script names) and `schedule_daily.bat`
    (schedule only during WNBA's May–October season — see §e).
15. Port `app.R` last, once all upstream caches exist and are validated — copy the 8-tab structure,
    swap branding/title, and fix the "Team Embeddings" tab to actually plot `team_embeddings.csv` while
    you're in there (a known gap in the NBA original, per `REPO_MAP.md` §9 — optional but cheap to fix
    during the port rather than replicating the bug).

Each phase should be smoke-tested independently (run the script standalone, inspect the resulting
`.rds`) before wiring into `run_full_pipeline.R`, exactly as the NBA repo's own `run_stage()`
try/catch wrapper implies was the original development pattern.

---

## (e) Risks / Gaps Where WNBA Data Is Less Available

1. **Off-season dead time is much longer.** WNBA regular season runs roughly May–September/October
   (plus playoffs into October), vs NBA's October–June with only a ~3-month true offseason. For
   roughly 6–7 months a year there is no live box-score, odds, or injury signal at all. **Workaround**:
   lean harder on the existing "offseason fallback" pattern already present in `injury_scraper.R`
   (hardcoded sample) and `market_odds_engine.R` (fixture slate) — make these WNBA off-season fallbacks
   explicit and clearly labeled in the dashboard (e.g., a banner: "WNBA season inactive — showing last
   completed season's cached ratings") rather than silently serving stale/synthetic data as if live,
   which the NBA version already somewhat risks doing.
2. **Thinner betting market depth.** Fewer sportsbooks post WNBA lines/props than NBA, and coverage is
   inconsistent especially for player props and non-marquee games. **Workaround**: treat
   `market_odds_engine.R`'s multi-book best-price-shopping logic as best-effort; expect the "sharp key"
   detection (pinnacle/circa/lowvig/betonlineag) to sometimes find zero sharp books for a given WNBA
   game and fall back more often to devigged consensus — this fallback already exists in the code, just
   expect it to trigger far more frequently for WNBA than it does for NBA.
3. **Shorter historical data depth for clean, complete box scores.** hoopR's NBA coverage (2019–2026,
   ESPN-backed) is deep and clean; wehoop's WNBA coverage, while going back further in some data types
   (play-by-play claimed back to 2002), may have gaps or inconsistent schemas in earlier years for team/
   player box completeness. **Workaround**: validate actual usable season count empirically at Phase 0
   before committing `ALL_SEASONS`/`HISTORICAL_SEASONS`-equivalent constants; it is fine (and expected)
   for the WNBA config's season range to be materially shorter than NBA's 2019–2026 span.
4. **Real RAPM/stint data is a bigger lift than the current NBA implementation delivers.** Since NBA's
   own `rapm_engine.R` is synthetic today, there's no existing real-stint ingestion code to port at all.
   If real WNBA RAPM is desired, `wehoop::load_wnba_pbp()` is the path, but building a stint-matrix
   extractor from play-by-play is new work, not a port — scope it as a separate future project, not
   part of MVP parity.
5. **Team count volatility.** The WNBA has been actively expanding (Golden State Valkyries joined 2025;
   further expansion teams are publicly planned for coming seasons). Unlike NBA's stable 30-team
   league, hardcoded team lists (`case_when` resolvers, `ARENA_DB`, synthetic roster generators, the
   zero-sum standings `n_teams` constant) will need periodic updates as new teams join — **workaround**:
   centralize the WNBA team list as a single named vector in `config.R` (e.g., `WNBA_TEAMS <- c(...)`)
   rather than repeating it inline in five different files as the NBA version currently does, so future
   expansion only requires one edit.
6. **Injury report granularity/cadence is lower than NBA's.** NBA has a formal, frequently-updated
   (multiple times daily per `ADR.md`) official injury report; WNBA's public injury disclosure is less
   standardized and less frequent. **Workaround**: don't over-trust `team_availability_score()`'s
   real-time responsiveness for WNBA — treat injury data as directionally useful but expect more lag
   than the NBA version implicitly assumes; consider widening the "offseason fallback" trigger condition
   as noted in §b.
7. **No stats.nba.com WNBA equivalent** for `xpoints_engine.R`'s shot-chart endpoint is confirmed usable
   — WNBA shot-location data is not reliably available through a free, keyless public endpoint the way
   NBA's (rate-limited but real) stats.nba.com is. **Workaround**: keep `xpoints_engine.R` and
   `shot_quality_engine.R` synthetic-only for WNBA for now (same as their current NBA state, so this is
   not a regression), and revisit if/when a real WNBA shot-location data source is identified (wehoop's
   play-by-play may carry shot coordinates in some seasons — check `load_wnba_pbp()` schema during
   Phase 0/3 before ruling this out entirely).

---

## Summary Judgment

Roughly **60–65% of the NBA codebase (Tier 1 + Tier 2 above) ports with pure find-and-replace-style
changes** (endpoint URLs, sport keys, team lists, constants) and no algorithmic changes. The remaining
**35–40% (Tier 3)** requires real parameter recalibration (roster/rotation size, game/season length,
sigma constants, playoff format) and, in a few cases (Rmd baseline, sigma constants), genuine
re-benchmarking against real WNBA data rather than assumption-based porting. The single biggest
external dependency to validate first, before writing any code, is **`wehoop`'s actual season/schema
coverage** for WNBA team and player box scores — everything else in the pipeline (BPM, ratings,
standings, odds, props) is downstream of that one data source.
