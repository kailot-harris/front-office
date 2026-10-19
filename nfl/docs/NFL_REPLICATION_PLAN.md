# NFL Replication Plan

Goal: replicate the WNBA Analytics system's architecture (see the sibling repo `WNBA Analytics`,
specifically `docs/WNBA_REPLICATION_PLAN.md`, which itself documents how WNBA Analytics was ported from
an earlier NBA Analytics repo) into a **new sibling directory**
`C:\Users\kailo\kayceeslices\NFL Analytics`. This document is Phase 0 research/planning only — it does
not implement `config.R`, the pipeline DAG, or any `.claude/skills/` tooling (those are being built in
parallel by other agents against this plan). Every claim below marked "verified live" was checked via
web search/fetch on 2026-09-16, not pulled from training-data memory, because nflverse APIs, coverage
windows, and vendor market-key names change and this document exists specifically to avoid porting
stale assumptions.

Unlike the NBA→WNBA port (same data vendor family, wehoop mirroring hoopR's API 1:1), the NFL data
ecosystem is **structurally different** from WNBA's ESPN/wehoop-only world: NFL has a dedicated,
actively maintained open-source data project (`nflverse`, i.e. `nflreadr`/`nflfastR`/`nflreadpy`) with
deep historical play-by-play, participation, and tracking-adjacent data that has no WNBA equivalent.
This changes the shape of the port: less "swap the URL segment," more "choose the right one of several
independently-good sources per data type."

---

## 1. Porting Strategy Narrative

NFL Analytics mirrors WNBA Analytics's architecture directly:

- **`config.R`** is the single source of truth for every sport-specific constant (season window,
  roster/rotation size, rolling-window size, sigma/HCA priors, cache paths, team list, playoff
  structure flags). No script should hardcode a value that also exists in `config.R`.
- **`run_full_pipeline.R`** is a staged DAG (ingest → metrics → ratings → fatigue/embeddings →
  market/props → risk/notify → live/dashboard), each stage wrapped in the same `run_stage()`
  try/catch pattern WNBA/NBA use, so a single failing stage doesn't take down the whole run and is
  independently smoke-testable.
- **`.claude/skills/`** carries the same repo-specific tooling conventions (a separate agent is
  building this in parallel; this plan does not specify skill contents).
- **Phased `task_assignments_phaseN.md`** documents drive implementation in the same phase order used
  for the WNBA port (scaffold/config → data foundation → core rating engine → fatigue/embeddings →
  market/betting → live/dashboard), described in §4/§5 below.

### Three known WNBA failure modes this port must not repeat

These are documented pitfalls from the NBA→WNBA port and apply with equal or greater force here because
NFL has *more* config surface (more constants, more source options, more identifier schemes to
reconcile):

1. **Constants drifting silently between `config.R` and call sites.** A constant (e.g. margin sigma,
   HCA, roster cap) gets defined in `config.R` but a script hardcodes its own copy inline instead of
   referencing the config value; the two silently diverge over time as one gets tuned and the other
   doesn't. Mitigation: every sport-specific numeric literal in an engine script should be traceable to
   a `config.R` symbol, and code review/tests should grep for suspicious bare numeric literals in the
   engine files.
2. **Pipeline stages guarded by a `sys.nframe() == 0` check that silently no-ops under `source()`.**
   A stage script written to "only run its top-level logic when executed directly" (checking
   `sys.nframe() == 0` or similar) will silently do nothing when `run_full_pipeline.R` pulls it in via
   `source()`, because `source()` changes the frame depth. The pipeline reports success (no error
   thrown) while the stage produced no output. Mitigation: stage scripts should expose a callable
   function that `run_full_pipeline.R` invokes explicitly, not rely on frame-depth detection to decide
   whether to execute.
3. **Two caches joined on incompatible player-identifier schemes producing a silent zero-match join.**
   E.g. one cache keyed by an ESPN athlete ID and another keyed by a name-derived or GSIS-style ID; the
   join runs, returns zero (or near-zero) matched rows, and nothing errors — the pipeline just silently
   produces empty/garbage downstream features. This risk is **materially larger for NFL** than it was
   for WNBA/NBA, because the NFL data landscape has at least four competing ID schemes in common use:
   ESPN athlete IDs, GSIS IDs (nflverse's primary key), PFR (Pro-Football-Reference) IDs, and
   NFL.com/NGS-style IDs. `nflreadr` ships an ID-crosswalk table (`load_ff_playerids()` / a bundled
   `ff_playerids`-style crosswalk) specifically because this problem is common enough in the NFL data
   ecosystem to need a dedicated join table — **use it**, and add a post-join row-count/match-rate
   assertion (e.g. fail loudly if match rate on a merge drops below some threshold) rather than trusting
   a join to "just work."

---

## 2. Data-Source Decision Table (verified live, 2026-09-16)

### Core nflverse data (play-by-play, schedules, rosters, tracking-adjacent)

**nflreadr vs nflfastR — verified live: nflreadr is now the primary/canonical interface.** Live checks
of nflfastR's own changelog show `fast_scraper_roster()` and `fast_scraper_schedules()` are officially
deprecated in favor of `load_rosters()`/`load_schedules()`, and nflfastR now **re-exports** nflreadr's
`load_pbp()`, `load_player_stats()`, and `load_team_stats()` rather than maintaining its own — nflfastR
is becoming a modeling/EPA-features package layered on top of nflreadr's data-loading layer, not a
separate data source. As of the 2026 season, nflfastR pulls raw pbp from the `nflverse/nflverse-pbp`
GitHub repo; the older `nflfastR-raw` repo it used to depend on is frozen and **will not receive
2026+ seasons**, so any code (or stale tutorial) that pins to `nflfastR-raw` directly is now broken for
current data. **Decision: call `nflreadr::load_*()` functions directly** (or via nflfastR's re-export,
functionally identical) rather than nflfastR's older `fast_scraper_*()` functions.

Functions confirmed live in the current `nflreadr` reference index (`nflreadr.nflverse.com`) and their
verified coverage windows:

| Function | Purpose | Verified coverage / update cadence |
|---|---|---|
| `load_pbp()` | Play-by-play | Back to **1999** (`seasons = TRUE` loads all). Updates nightly during season after each game day. |
| `load_schedules()` | Game/schedule data | Updates every 5 minutes during the season. |
| `load_rosters()` / `load_rosters_weekly()` | Season and weekly rosters | Roster data updates daily at 07:00 UTC. |
| `load_teams()` | Team graphics/colors/logos | Static reference table. |
| `load_snap_counts()` | Snap counts (source: Pro-Football-Reference) | Starts **2012 season**. Updates 4x/day (00/06/12/18 UTC) in-season. |
| `load_participation()` | Play-level personnel/participation | Starts **2016 season**; per nflreadr's own docs, **2023-onward participation data is sourced from FTN and is only released after all postseason games complete** — i.e. current-season participation is not available in near-real-time the way pbp/schedules are. This is a real coverage gap to design around (do not assume in-season participation features are live-usable for the current season). |
| `load_nextgen_stats()` | Player-level weekly NFL Next Gen Stats (tracking-derived speed/separation/CPOE-adjacent metrics) | Starts **2016 season**. Updates nightly (03:00-05:00 ET) during season. |
| `load_injuries()` | Official injury reports | nflverse-sourced official injury report data (separate from the ESPN JSON feed discussed below — nflverse's injuries loader reflects the league's own injury-report submissions, not ESPN's site). |
| `load_depth_charts()` | Weekly depth charts | — |
| `load_officials()`, `load_trades()`, `load_draft_picks()`, `load_combine()`, `load_pfr_advstats()`, `load_contracts()`, `load_ftn_charting()` | Supplementary structural/context data | Various PFR/OverTheCap/FTN sources, not verified in depth for this plan — flagged as available but out of scope for MVP. |
| `load_ff_playerids()` | Cross-source player ID crosswalk (GSIS/ESPN/PFR/Sleeper/Yahoo/etc.) | Exists specifically to solve failure mode (c) above — **use this as the canonical ID-join table.** |

There is no need for an ESPN-site fallback for pbp/schedules/rosters/tracking data — nflverse is the
better, purpose-built, actively-maintained source for all of these, unlike the WNBA case where ESPN's
site API was often the *only* option.

### Injuries: nflverse `load_injuries()` vs ESPN JSON feed

**Verified live via WebFetch against ESPN's public site API** (`site.web.api.espn.com/apis/site/v2/
sports/football/nfl/injuries`, fetched 2026-09-16): the NFL injuries feed has **the same quirk as the
known WNBA case** — the athlete object in each injury entry does **not** expose a top-level numeric
`id` field. A verbatim example entry retrieved live:

```json
{
  "id": "-2004726",
  "longComment": "ir",
  "shortComment": "ir",
  "status": "Injured Reserve",
  "date": "2026-09-16T17:42Z",
  "athlete": {
    "firstName": "Kitan",
    "lastName": "Crawford",
    "displayName": "Kitan Crawford",
    "shortName": "K. Crawford",
    "links": [{"rel": ["playercard", "desktop", "athlete"],
               "href": "https://www.espn.com/nfl/player/_/id/4430821/kitan-crawford",
               "text": "Player Card"}],
    "headshot": {"href": "https://a.espncdn.com/i/headshots/nfl/players/full/4430821.png"},
    "position": {"id": "36", "name": "Safety"}
  }
}
```

The `"id": "-2004726"` field present is an **injury-report-entry ID, not a player ID**. The actual ESPN
athlete ID (`4430821` here) must be parsed out of the `links[].href` "Player Card" URL (or equivalently
the headshot filename) — **exactly the WNBA workaround pattern**, not something new to invent. Any
injury-scraper port must reuse the same href-parsing regex approach already proven in the WNBA/NBA
`injury_scraper.R`.

Separately, ESPN's **core** API (`sports.core.api.espn.com/.../teams/{id}/injuries`) was found (via
third-party documentation, not independently confirmed live in this session — flagged as unverified)
to represent the athlete as a `$ref` link to a full athlete resource rather than embedding an id or a
player-card href; this is a heavier-weight follow-the-reference pattern and is not recommended as the
primary path given the lighter-weight site-API href-parsing approach already works.

**Decision**: use `nflreadr::load_injuries()` as the primary injury-status source where official
report-level granularity (probable/questionable/out plus practice participation) is needed, since it is
structured, versioned nflverse data. Use the ESPN site-API JSON feed as a frester/more real-time
secondary source for same-day status changes, applying the href-parsing player-ID extraction above. Do
not assume `athlete.id` is present in the ESPN feed — it is not, verified live.

### Odds / lines

- **The Odds API** — verified live: NFL is available under sport key **`americanfootball_nfl`**
  (confirmed via the-odds-api.com's own NFL odds product page). Player-prop market keys follow the
  `player_<stat>` naming convention (e.g. `player_pass_tds`, `player_rush_yds`, `player_pass_yds`), with
  a parallel `_alternate` suffix family (e.g. `player_pass_yds_alternate`) for milestone/alternate-line
  markets — this mirrors the WNBA port's finding that player props require the **event-odds endpoint**
  (`/v4/sports/americanfootball_nfl/events/{eventId}/odds`), not the featured-markets endpoint used for
  h2h/spreads/totals. This confirms the WNBA-repo pattern (props require a second, per-event API call)
  carries over unchanged in shape, just with a much deeper NFL market-key catalog to choose from.
- **SportsDataIO** — not independently re-verified live in this session beyond confirming it is an
  active commercial provider with an NFL odds/props product; treat as a documented alternative, not a
  verified integration target.
- **OpticOdds / SportsGameOdds** — mentioned per the task brief as alternatives; not independently
  verified live in this research pass. Flag as unverified — a human evaluating vendor tradeoffs should
  check current pricing/coverage directly before committing to either.
- Per the non-goals below, this document does **not** pick a final odds/props vendor. It documents
  what's confirmed to exist (Odds API market-key shape) versus what still needs a human evaluation pass
  (SportsDataIO/OpticOdds/SportsGameOdds pricing and NFL-specific coverage depth).

### Player props sources

Two independent paths exist, same shape as WNBA: (1) The Odds API's event-odds endpoint (market data,
requires a paid-tier key for reliable coverage depth), or (2) an in-house Poisson/negative-binomial
model built on nflverse's `load_player_stats()`/`load_nextgen_stats()` box-score and tracking data,
mirroring the WNBA repo's `player_props_engine.R`/`copula_props_engine.R` synthetic-to-start pattern.
No live vendor signup or credential work is in scope here.

---

## 3. Constants That Must Be Empirically Re-Derived (not assumed here)

A separate agent is deriving numeric values for `config.R`. This plan only enumerates **what** needs
re-derivation and **why it cannot be assumed from the WNBA/NBA priors or from memorized NFL trivia**:

- **`NFL_MARGIN_SIGMA`** — the standard deviation of home-margin residuals used to convert point
  spreads/projections to win probabilities. NFL scoring variance, pace, and game count per season all
  differ from NBA/WNBA; must be fit from actual historical NFL final-margin data (e.g. via `load_pbp()`
  final scores or `load_schedules()` results), not carried over from any basketball sigma value.
- **`NFL_HCA`** (home-court/field advantage) — historically often cited informally as "~2-3 points" in
  NFL folk analytics, but this number has reportedly **drifted downward in recent seasons** (a widely
  discussed trend in public NFL analytics circles); this plan does not assert a specific current value
  — it must be empirically fit from recent-seasons schedule/score data, not pulled from an old citation.
- **`HISTORICAL_SEASONS` / `CURRENT_SEASON` cutoff** — nflverse `load_pbp()` covers back to 1999, but
  the config should not naively use the full 1999-present range for modeling; season-count choice
  interacts with rule-change eras (e.g. passing-rule changes, overtime-format changes, playoff-field
  expansion from 12 to 14 teams in 2020) that make older seasons less representative of current dynamics
  — the cutoff choice needs empirical/domain re-validation, not a default of "use everything available."
- **Roster/season/playoff structural constants** — active roster size (53-man roster + practice squad
  rules), regular-season game count (17 games since 2021, up from 16), and playoff field size (14 teams,
  7 per conference, one bye per conference — verified live, see §4) all need to be config-driven
  constants analogous to WNBA's `WNBA_ROSTER_MAX`/`WNBA_SEASON_GAMES`, not hardcoded inline.

---

## 4. Known Structural Divergences from the WNBA Pipeline

1. **Playoff bracket shape**: WNBA's playoff-simulator logic models best-of-N series (best-of-5/7).
   NFL's playoff structure is fundamentally different and **cannot reuse series-win-threshold logic at
   all** — it is **single-elimination**, **14-team field** (verified live for the current format: 7
   teams per conference — 4 division winners seeded 1-4, plus 3 wildcard teams seeded 5-7), with **only
   one first-round bye per conference** (the #1 seed in each conference), so 12 of 14 teams play in the
   opening Wild Card round while the two #1 seeds sit out. This means the playoff simulator needs an
   entirely new bracket-advancement model (single-game win probability per round, re-seeding rules after
   each round per NFL's reseeding format) rather than a ported best-of-N series simulator.
2. **Short-rest scheduling as a fatigue input**: WNBA's fatigue engine models travel distance/altitude
   and circadian effects from game-to-game scheduling. NFL adds a distinct fatigue axis with no WNBA
   analog: **Thursday Night Football (mini-bye/short week) and Monday Night Football (extended
   recovery before/short week after)** create asymmetric rest-day counts between opponents in a single
   game that materially affect performance in published NFL analytics research. This needs a new
   "days of rest" feature (computable directly from `load_schedules()` game dates) layered onto or
   alongside the existing travel/altitude fatigue logic, not a replacement of it — both axes matter for
   NFL.
3. **Season length effects on rolling-window sizing**: NFL's regular season is **17 games** (since 2021;
   16 games before that), dramatically shorter than WNBA's ~40-44 games and far shorter than NBA's 82.
   This means WNBA's own rolling-window fraction (already itself a re-derivation from NBA's 82-game
   window down to ~40) cannot be further scaled down proportionally without risking a window so small it
   captures almost no signal (e.g. a naive proportional scale from WNBA's 9-game window, itself ~22% of
   40 games, would suggest a ~4-game NFL window, which is likely too noisy to be a stable rating input).
   This is exactly the kind of constant flagged in §3 as needing empirical re-validation rather than
   arithmetic scaling — the NFL config should test multiple window sizes against held-out prediction
   accuracy rather than assume a proportional-scaling formula transfers across sports with this much
   game-count disparity.

---

## 5. Modern Modeling Approaches Worth Prototyping

- **EPA/CPOE-based features via nflfastR/nflreadr.** Expected Points Added (EPA) per play and
  Completion Percentage Over Expected (CPOE) are the dominant modern public NFL analytics features,
  computable directly from `load_pbp()`'s play-level data (nflfastR's EPA model ships as part of the
  pbp release itself). These are a strong candidate replacement/supplement for whatever simple
  box-score-derived rating WNBA/NBA analytics used, since NFL's play-by-play depth (unlike WNBA's
  box-score-first data situation) makes play-level features cheaply available from day one.
- **Participation/personnel-based features.** `load_participation()` (2016+, though 2023+ data is
  FTN-sourced and only released post-postseason per §2) exposes personnel groupings (11/12/21 personnel,
  formation, men-in-box) that have no WNBA analog and could feed a more granular matchup model — but the
  post-season-only release cadence for recent seasons means this cannot be a **real-time** in-season
  feature source today; it is better suited to offline model training/backtesting than to a live weekly
  pipeline until nflverse's participation-data cadence changes.
- **ML vs. Pythagorean-expectation comparisons — verified live finding.** A peer-reviewed 2025 paper was
  found and directly fetched: **Weirich, Kim, Yoon, and Jeong, "Advancing NFL win prediction: from
  Pythagorean formulas to machine learning algorithms," published in *Frontiers in Sports and Active
  Living*, September 12, 2025** (PMC12463883). The study used 672 team-season observations across 21
  NFL seasons (2003-2023, sourced from Pro-Football-Reference) and compared three models: the classic
  Pythagorean expectation formula, a Random Forest regressor (100 trees), and a feedforward neural
  network (two hidden layers, 64 and 32 neurons). Reported test metrics (predicting team win
  percentage):

  | Model | MAE | RMSE | R² |
  |---|---|---|---|
  | Pythagorean expectation | 0.066 | 0.082 | 0.816 |
  | Random Forest | 0.061 | 0.075 | 0.857 |
  | Neural Network | **0.052** | **0.064** | **0.891** |

  Both ML approaches outperformed the Pythagorean baseline, with the neural network best overall; the
  paper's SHAP analysis found points-scored and points-allowed remained the dominant features even in
  the ML models, with margin of victory, turnovers, and offensive efficiency as secondary contributors.
  This is a real, independently fetched and confirmed citation (not a memorized/possibly-hallucinated
  one) and supports prototyping a gradient-boosting or small neural-net win-probability/margin model
  as a step beyond a pure Pythagorean or simple regression baseline — but note the paper models
  **season-level win percentage**, not **single-game margin prediction**, which is this repo's actual
  target; a game-level analog of this comparison was not found and would need separate validation before
  assuming the same ML-over-Pythagorean margin holds at the per-game grain.
- Gradient boosting (XGBoost/LightGBM) specifically was not the subject of the paper found above (it
  compared Random Forest and a neural net, not GBM) — if GBM is prototyped, that comparison would need
  its own validation rather than borrowing this paper's numbers.

---

## 6. Non-Goals

- This document does **not** select a single final odds/props vendor. The Odds API's market-key shape
  is verified and documented above; SportsDataIO/OpticOdds/SportsGameOdds are named as alternatives
  worth a human evaluation pass (pricing, coverage depth, historical-data access) but are not vetted
  live here, and no signup or API-key work is performed or assumed.
- This document does **not** write engine implementations (`config.R`, `run_full_pipeline.R`, per-sport
  engine scripts). Those are separate, parallel workstreams; this plan exists to give them a verified
  factual foundation (function names, coverage windows, ID-scheme gotchas, playoff structure) so they
  don't have to re-derive or guess at it.
- No credentials, API keys, or account signups are fabricated or assumed anywhere in this document.

---

## Summary Judgment

The NFL port differs from the WNBA port's core lesson. WNBA's biggest risk was **data scarcity** (ESPN
as the only real option, thin historical coverage, thin odds-book depth). NFL's biggest risk is close to
the opposite: **data abundance with fragmented identifier schemes** — nflverse alone offers a dozen-plus
loader functions across several underlying vendors (PFR, FTN, OverTheCap, NFL NGS), each with its own ID
scheme, coverage start year, and update cadence, on top of a still-separate ESPN JSON injuries feed with
its own athlete-ID quirk (verified live to match the WNBA case exactly: no `athlete.id`, must parse from
the Player Card href). The single biggest engineering discipline to enforce from day one, more so than
in the WNBA port, is **consistent ID-crosswalk usage** (`nflreadr::load_ff_playerids()` or equivalent)
at every join point — this is precisely failure mode (c) from the WNBA postmortem, and NFL's larger
number of competing ID schemes makes it more likely to recur here, not less, unless it's designed against
explicitly from Phase 0.

---

## Sources Consulted (live, 2026-09-16)

- [nflreadr Package index](https://nflreadr.nflverse.com/reference/index.html)
- [nflreadr nflverse Data Update and Availability Schedule](https://nflreadr.nflverse.com/articles/nflverse_data_schedule.html)
- [nflfastR NEWS.md / Changelog](https://nflfastr.com/news/index.html)
- [load_snap_counts (rdrr.io mirror of nflreadr docs)](https://rdrr.io/cran/nflreadr/man/load_snap_counts.html)
- [load_nextgen_stats (rdrr.io mirror)](https://rdrr.io/cran/nflreadr/man/load_nextgen_stats.html)
- [load_participation (rdrr.io mirror)](https://rdrr.io/cran/nflreadr/man/load_participation.html)
- [load_pbp (nflreadr.nflverse.com)](https://nflreadr.nflverse.com/reference/load_pbp.html)
- ESPN NFL injuries JSON feed, fetched live: `https://site.web.api.espn.com/apis/site/v2/sports/football/nfl/injuries`
- ESPN NFL team JSON, fetched live: `https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/1`
- [List of NFL endpoints for ESPN's API (community gist)](https://gist.github.com/nntrn/ee26cb2a0716de0947a0a4e9a157bc1c) — used only for the (unverified live) core-API `$ref` pattern note
- [The Odds API — NFL Odds product page](https://the-odds-api.com/sports/nfl-odds.html)
- [The Odds API V4 documentation](https://the-odds-api.com/liveapi/guides/v4/)
- [Yahoo Sports — NFL playoff bracket format explainer, 2026](https://sports.yahoo.com/articles/nfl-playoff-bracket-explained-byes-160616662.html)
- [Weirich, Kim, Yoon, Jeong — "Advancing NFL win prediction: from Pythagorean formulas to machine learning algorithms," Frontiers in Sports and Active Living, Sept 2025 (PMC12463883)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12463883/)
