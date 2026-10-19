# Plan: NFL Analytics — Parallel Sibling Workspace

## Context

The WNBA Analytics repo (`C:\Users\kailo\kayceeslices\WNBA Analytics`) is itself a "port" of an
earlier NBA Analytics repo — same flat-file layout, same `config.R` centralized-constants
pattern, same 13-stage `run_full_pipeline.R` DAG, same `.claude/skills/` tooling, same
multi-phase `docs/task_assignments_phaseN.md` remediation convention. That port process is well
documented (`WNBA_REPLICATION_PLAN.md`, `REPO_MAP.md`, per-phase Handoff Notes) and already
proved out real failure modes worth avoiding a second time: constants silently drifting between
`config.R` and call sites (Finding C-1), pipeline stages guarded by a `sys.nframe() == 0` check
that never fires under `source()` (four+ silent no-op stages), and two caches joined on
incompatible player-identifier schemes producing a zero-match join that failed silently
(RAPM↔roster). The user wants a **new, parallel sibling workspace for NFL game predictions**
that reuses this architecture, its test-suite/skill conventions, and its hard-won lessons —
plus fresh research into current NFL data APIs and modern prediction approaches, since the NFL
data ecosystem (nflverse) is materially different from WNBA's (`wehoop`/ESPN-only).

This plan produces: a new sibling repo scaffold, adapted/generalized copies of the 5 existing
skills, and a pair of planning documents (a replication/research plan + a Phase 0 task-assignment
file) that lay out the concrete build roadmap. It does **not** write every pipeline engine script
end-to-end — that mirrors how the WNBA repo itself was built (T0 foundation → phased waves over
multiple sessions), and attempting all engines in one shot would repeat the exact
"unverified numbers laundered into confident code" risk this repo's own docs warn about.

## Target layout

New sibling directory: `C:\Users\kailo\kayceeslices\NFL Analytics` (own git repo, `git init` as
its own Phase 0 orchestrator-only step, mirroring how WNBA's Phase 4 did this for the same
reason: "did agent X touch only its assigned files" needs a baseline commit to answer). Same flat
structure as WNBA, ported 1:1:

```
NFL Analytics/
  config.R                        # NFL structural + modeling constants (see below)
  run_full_pipeline.R             # same run_stage() wrapper pattern, NFL-specific DAG
  logging_utils.R                 # copy verbatim (sport-agnostic)
  daily_ingest.R, injury_scraper.R, sync_rosters.R, market_odds_engine.R,
  player_props_engine.R, playoff_simulator.R, risk_management_engine.R,
  notify_bets.R, app.R            # NFL adaptations of each WNBA counterpart (Phase 1+ work)
  agents/                         # per-subagent phase briefs
  docs/                           # NFL_REPLICATION_PLAN.md, task_assignments_phaseN.md
  data/  cache/                   # same split as WNBA (static artifacts vs runtime cache)
  tools/                          # test_phaseN_*.R convention, hyperparameter sweeps, probes
  .claude/skills/                 # 5 skills, adapted (see below)
  CLAUDE.md                       # NFL-specific environment/data quirks (this repo's own CLAUDE.md is the template for structure, not content)
```

## Config constants to define (`config.R`)

Structural (verify each via web search at write-time, same as WNBA's Phase 0 did — do not trust
this plan's numbers as final without re-checking):
- `NFL_TEAMS` — 32-team abbreviation→name map (single source of truth, same rationale as
  `WNBA_TEAMS`: NBA repo's mistake of scattering a team list across files must not repeat).
- `NFL_ROSTER_MAX` (53 total / 48 active gameday), `NFL_SEASON_GAMES` (17 regular season since
  2021), `NFL_GAME_MINUTES` (60, 4x15 quarters — mostly irrelevant to margin modeling unlike
  WNBA's 40 vs NBA's 48, but keep for parity/possible pace features).
- `NFL_PLAYOFF_FIELD` (14 teams, 7 per conference since 2020) and bracket structure — replaces
  `playoff_simulator.R`'s Bo3/Bo5/Bo7 series logic with single-elimination + a bye week for #1
  seeds; this is a **real structural divergence** from WNBA's series format, not a find/replace.
- Data horizons: `HISTORICAL_SEASONS`, `CURRENT_SEASON` (nflreadr PBP goes back to 1999 — decide
  a practical training-data cutoff, do not just default to 1999 without checking data quality
  drift across rule-era changes).
- Modeling hyperparameters to be **empirically derived, not guessed**, exactly like WNBA's
  `ROLLING_WINDOW_SIZE`/`WNBA_MARGIN_SIGMA`/`WNBA_HCA` were (sd of real home-margin data, swept
  rolling window 3–25): `NFL_MARGIN_SIGMA` (NFL scoring variance is well studied — Pythagorean/Vegas
  literature commonly cites σ≈13–14 points, but re-derive from real `nflreadr::load_schedules()`
  margins rather than citing a number secondhand) and `NFL_HCA` (historically ~2.0–2.5 pts,
  reportedly compressed in recent seasons — re-derive, do not hardcode a value from memory; this
  is the exact constant class that caused Finding C-1).
- Cache filepaths (`CACHE_PBP`, `CACHE_SCHEDULES`, `CACHE_ROSTERS`, `CACHE_INJURY_DATA`,
  `CACHE_PARTICIPATION`, `CACHE_NEXTGEN_STATS`, `CACHE_PLAYER_PROPS`), `DISCORD_WEBHOOK` via
  `Sys.getenv()` (never a hardcoded secret, per this repo's existing convention).

## Data source research (for `NFL_REPLICATION_PLAN.md`)

**Play-by-play / schedules / rosters / advanced tracking — primary layer**
| Source | Covers | Benefit | Drawback |
|---|---|---|---|
| `nflreadr` (R, nflverse) | `load_pbp()`, `load_schedules()`, `load_rosters()`, `load_snap_counts()` (PFR, 2012+), `load_participation()` (formations/personnel, 2016+), `load_nextgen_stats()` (NGS speed/separation/CPOE, 2016+), `load_injuries()` | Free, no key, R-native (direct `wehoop`-style replacement), nightly updates in-season, huge community track record | Some tables (participation, NGS) start 2016+ only; historical (pre-1999) not covered |
| `nflfastR` | EPA/WP-enriched PBP (built on nflreadr's raw PBP) | Gives EPA/WPA/CPOE precomputed — the standard modern efficiency metric, avoids re-deriving from scratch | Slower full-history load; nflverse itself now steers new code toward `nflreadr` as the loader, `nflfastR` mainly for its EPA model internals |
| ESPN site API (same pattern as WNBA's `sync_rosters.R`/`injury_scraper.R`) | Live scores, depth charts, transactions | Reusable scraping pattern already proven in this codebase | **Must re-verify whether NFL's injuries endpoint has `athlete.id`** — WNBA's does not (extracted from a "Player Card" href instead); do not assume either way without checking live, since CLAUDE.md's existing WNBA quirk note is sport-specific and NOT guaranteed to transfer |

**Injuries (dedicated cross-check layer)**
- ESPN injury feed (as above) — free, matches existing scraper pattern.
- Official NFL injury report format (Wed/Thu/Fri practice participation + game status) is more
  granular than ESPN's summary and is what sharp models actually weight — investigate whether
  `nflreadr::load_injuries()` (2009–present per nflverse docs) already carries this practice-report
  granularity before building a second bespoke scraper.

**Odds / lines (moneyline, spread, total)**
| Source | Benefit | Drawback |
|---|---|---|
| The Odds API (`americanfootball_nfl` sport key) | **Same account/env var (`ODDS_API_KEY`) as the WNBA repo already uses** — `market_odds_engine.R`'s sharp-book devig/Kelly math is sport-agnostic and ports with only the sport-key string changed, exactly like the WNBA port did from `basketball_nba`→`basketball_wnba` | NFL has far deeper book coverage than WNBA so sharp-book detection (Pinnacle/Circa/lowvig) should actually fire, unlike WNBA's frequent zero-sharp-book fallback — re-verify this assumption live rather than assuming better coverage automatically means better calibration |
| SportsDataIO | Historical odds back to 2019, projections/news bundled | Paid |
| OpticOdds / SportsGameOdds | 100+/85+ books, real-time player-prop and alternate-market feeds | Paid, geared toward live in-play use cases beyond this pipeline's current scope |

**Player props (for a `player_props_engine.R` port)**
- The Odds API's player-props markets (same key as above, historical snapshots from 2023 on paid
  tiers) — lowest-friction reuse of the existing account.
- SportsGameOdds / OddsPapi as free-tier fallbacks if prop coverage on The Odds API proves thin
  for a given market (mirrors WNBA's existing thin-book fallback design — do not weaken staking
  discipline to compensate, per that engine's existing caveat comment, just flag it).

**Modern modeling approaches worth prototyping (from current research)**
- EPA/CPOE-based features (via `nflfastR`) as the baseline efficiency layer — this is the modern
  standard replacing raw yardage stats, analogous to how WNBA's RAPM engine replaced simple box
  scores.
- Participation/personnel data (`load_participation()`) enables formation- and personnel-group
  features (11/12/21 personnel, box count) with no tracking-data license needed.
- 2025 peer-reviewed comparison (Frontiers in Sports & Active Living) found feedforward neural
  nets and Random Forest meaningfully outperform Pythagorean-expectation win% baselines (NN: MAE
  0.052, R²=0.891) on season-level team stats — a reasonable target architecture for a
  season-level standings/win-total model, distinct from a per-game margin model.
- NFL Next Gen Stats + AWS shipped transformer-based run-scheme/blocking-matchup models for the
  2026 season — real tracking data (not publicly available at that granularity) but signals where
  public research is headed; not directly buildable without a tracking-data license, note as a
  stretch goal rather than a Phase-1 deliverable.
- Treat all of the above as candidates to benchmark against each other and against a simple
  Elo/margin baseline (mirroring WNBA's own `tools/ml_cv_benchmark.R`/`ml_feature_experiments*.R`
  pattern) rather than committing to one architecture up front.

## Skill adaptation

Copy all 5 skills from `WNBA Analytics/.claude/skills/` into the new repo's `.claude/skills/`.
Three are sport-agnostic prompt/template skills usable verbatim: `deep-review-to-manuscript`,
`render-and-inspect-quarto`, `remediation-phase-scaffold`. Two ship an R helper script that
hardcodes the WNBA path/naming and need generalizing:
- `config-constant-drift-audit/scripts/audit_constants.R`: hardcodes
  `PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/WNBA Analytics"` and strips a `WNBA_` prefix when
  building the name-proximity heuristic (`gsub("^WNBA_", ...)`). Repoint `PROJECT_ROOT` at the new
  repo and generalize the prefix-strip to `NFL_` (or make it strip whichever prefix matches,
  reading it from the constant names actually present in that repo's `config.R` rather than a
  literal string, so it doesn't need editing a third time for a future sport).
- `pipeline-freshness-audit/scripts/check_freshness.R`: hardcodes the same `PROJECT_ROOT` plus a
  literal WNBA stage→output manifest table. Repoint the path and replace the manifest with the
  new repo's actual `run_full_pipeline.R` stage list once that DAG exists (Phase 1+ work — until
  then, this skill can't be meaningfully tested against the new repo, only copied).
Update each skill's `SKILL.md` "Known-clean baseline" / manifest table text to describe the NFL
repo instead of citing WNBA-specific findings (C-1, the four `sys.nframe()` stages) as its
motivating example — keep the *mechanism* description, replace the specific historical anecdote
with "ported from the WNBA Analytics repo's identically-shaped bug" so the lesson isn't lost.

## Documents to produce

1. **`docs/NFL_REPLICATION_PLAN.md`** — mirrors `WNBA_REPLICATION_PLAN.md`'s role: states the
   porting strategy, the data-source table above with final source decisions, the constants that
   must be empirically re-derived rather than assumed, and known structural divergences from the
   WNBA pipeline (playoff bracket format, bye weeks, Thursday/Monday short-rest scheduling as a
   fatigue-engine input replacing WNBA's travel/circadian-only model, 17-week season vs 44-game
   WNBA season for rolling-window sizing).
2. **`docs/task_assignments_phase0.md`** (via the `remediation-phase-scaffold` skill/template) —
   the first executable wave: repo scaffold + git init (Phase 0 orchestrator-only setup) +
   `config.R` + `daily_ingest.R` (nflreadr-based PBP/schedule ingestion) + `sync_rosters.R` +
   `injury_scraper.R`, each as a disjoint-file-ownership task, matching how WNBA's own T0–T1
   foundation wave was structured.
3. **`CLAUDE.md`** for the new repo — same sections as the WNBA one (Environment, Data quirks,
   Constants convention, Process/conventions, Folder layout), populated with NFL-specific facts
   actually verified during Phase 0 execution (e.g. the ESPN injury `athlete.id` question above),
   not copy-pasted WNBA facts.

## Explicit non-goals for this plan

- Not writing full engine implementations (RAPM/EPA engine, market odds engine, props engine,
  playoff simulator, Shiny dashboard) — those are Phase 1+ execution waves, scoped in
  `task_assignments_phase0.md`'s wave graph but not built now.
- Not selecting a single final odds/props API provider — the plan documents tradeoffs; the actual
  key signup and account setup is a human action (per this repo's own "no fabricated credentials"
  rule), to be documented the same way `docs/ODDS_API_SETUP.md` documents it for WNBA.

## Verification

- After scaffold: `git -C "NFL Analytics" log --oneline` shows the Phase 0 baseline commit; repo
  layout matches the list above.
- After `config.R` is drafted: run the adapted `config-constant-drift-audit` skill against the new
  repo — expect zero findings on a freshly-scaffolded repo (no call sites exist yet to drift).
- After `docs/task_assignments_phase0.md` exists: sanity-check its wave graph has no two agents
  sharing a file, same check the `remediation-phase-scaffold` skill's own procedure requires.
- Treat this plan itself as input to a `render-and-inspect-quarto`-style review only once an
  actual `.qmd`/manuscript is produced later — not applicable to this planning step.
