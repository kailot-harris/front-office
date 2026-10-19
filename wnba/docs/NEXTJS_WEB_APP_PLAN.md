# WNBA Web App — Implementation Plan (ported from NBA Analytics)

## Source of truth
NBA Analytics' `web/` folder: Next.js 14 (App Router) + React 18 + TypeScript + Tailwind CSS.
No backend/database — static JSON files in `web/public/data/`, generated offline by the R
pipeline (`run_full_pipeline.R` + per-feature `build_*.R` scripts), read by server components.
Survey of that app: `../NBA Analytics/WEB_APP_SURVEY.md`.

## Current WNBA state
- No web layer exists yet — only the `app.R` Shiny dashboard (10 tabs: daily edges, steam radar,
  injuries, bet tracker, embeddings, calibration, standings calc, model diagnostics, player
  props, clutch/shot profile).
- Engines already present and reusable as JSON sources: `rapm_engine.R` (ratings/variants),
  `player_props_engine.R`, `playoff_simulator.R` (`cache/playoff_bracket_results_*.rds`),
  `load_embeddings.R` / `team_embeddings.py` (`data/team_embeddings.csv`,
  `data/team_similarity_matrix.csv`), standings projections (`cache/projected_wnba_standings.rds`).
- Missing WNBA-side engines for: coaching impact, shot charts, defense, player DNA, offseason
  transactions, CBA/cap sheet, clutch leverage metrics.

## Phase 0 — Scaffold
- `npx create-next-app@14` into a new top-level `web/` folder (sibling to the flat R scripts —
  per CLAUDE.md's folder-layout rule, this is a new folder, not a reorganization of existing
  scripts).
- Port `tailwind.config.ts`, dark slate/indigo/amber theme, `Sidebar.tsx` / `Navbar.tsx` shell,
  and `lib/data.ts`'s static-JSON-fetch pattern.
- Re-theme for WNBA: 15 teams sourced from `config.R`'s `WNBA_TEAMS` (not 30), WNBA branding.

## Phase 1 — JSON export stage + direct ports (engines already exist)
- Add `export_web_json.R` as a new pipeline stage, registered in `pipeline_stages.R` and invoked
  via `run_registered_stage()` after the engines it depends on (standings, RAPM, props,
  embeddings). Writes `web/public/data/*.json` from the existing `.rds`/`.csv` caches.
- Port pages 1:1 from NBA's `/` (standings), `/variants`, `/players`, `/diagnostics`.

## Phase 2 — Playoff / series page
- Port NBA's `/series` page using WNBA's existing `cache/playoff_bracket_results_*.rds`.

## Phase 3 — Net-new R engines (features WNBA currently lacks)
Suggested priority order:
1. Shots — contingent on whether `CACHE_PBP_RAW` / `player_pbp_features.rds` carries shot-location
   detail; confirm before committing to this first.
2. Offseason transactions.
3. Coaching impact, defense, player DNA, CBA/cap sheet — build in whatever order matters most;
   note CBA/cap sheet may not port cleanly since WNBA's cap rules differ structurally from the
   NBA's, so validate applicability before porting that one.

## Open questions / decision points before Phase 3
- Does WNBA's CBA cap structure support a cap-sheet feature analogous to NBA's, or does it need a
  different model?
- Confirm shot-location data availability before scheduling the shots engine. -> **RESOLVED (2026-10-18):** Confirmed in `CACHE_PBP_RAW` (`wnba_espn_pbp_cache.rds`), which carries 267k+ tracked field goal attempts with half-court coordinates (`coordinate_x_raw`, `coordinate_y_raw`), shot types, and athlete identifiers.

## Status
- **Phase 0:** Completed (Next.js scaffold, App Router, shell layout, WNBA 15-team theming, dark slate UI).
- **Phase 1:** Completed (registered `export_web_json` pipeline stage in `pipeline_stages.R` and `run_full_pipeline.R`, generated static JSON data in `web/public/data/` and `cache/`, ported `/`, `/variants`, `/players`, `/diagnostics`, `/teams`, verified `npm run build` and full pipeline).
- **Phase 2:** Completed (exported `playoff_series_matchups.json` with 15-team profiles, 8-man WNBA 200-minute rotation tightening, 10,000-sim Monte Carlo engine with Bo3/Bo5/Bo7 formats, `SeriesProbRing.tsx`, `TacticalMismatchRadar.tsx`, `PlayoffSeriesClient.tsx`, `/series` route, and 2022-2025 historical postseason brackets archive; verified with `npm run build` [10/10 pages] and `run_full_pipeline.R` [48.4s]).
- **Phase 3:** Completed (All 7 net-new analytics engines built, registered, exported, and wired into interactive Next.js routes):
  - **Item 1 (Shot Charts):** Completed (`build_shot_chart_dataset.R` as Stage 10, 14-zone WNBA court classification, Empirical Bayes shrinkage, `shots_metadata.json`, `shots_index.json`, 210 player shot files in `web/public/data/shots/`, `PlayerShotChart.tsx`, `ShotsExplorerClient.tsx`, `/shots` route).
  - **Item 2 (Offseason Moves & Transactions):** Completed (`build_offseason_dataset.R` as Stage 11, blockbuster trades, expansion drafts for GS/POR/TOR, 15-team offseason grades, 2026 Draft board, `web/lib/offseasonTypes.ts`, `OffseasonClient.tsx`, `/offseason` route).
  - **Item 3 (Coaching Staffs & Tactical Impact):** Completed (`build_coaching_dataset.R` as Stage 12, 15-team coaching registry, ATO execution metrics, 5D tactical percentiles, talent-to-wins waterfall bridge, `CoachRadarProfile.tsx`, `CoachImpactWaterfall.tsx`, `AtoEfficiencyScatter.tsx`, `CoachesClient.tsx`, `/coaches` route).
  - **Item 4 (Defensive Versatility & Matchups):** Completed (`build_defense_dataset.R` as Stage 13, 221 WNBA player profiles, Shannon entropy $H_v$ across 5 matchup positions, rim DFG% suppression, on/off rim deterrence, screen navigation, `MatchupHeatmap.tsx`, `VersatilityScatter.tsx`, `DefenseClient.tsx`, `/defense` route).
  - **Item 5 (Player DNA & Historical Twins):** Completed (`build_player_dna_dataset.R` as Stage 14, 16-D player skill vectors, cosine-similarity archetype matching against all-time WNBA legends 1997-2025, `web/lib/playerDnaTypes.ts`, `SkillFingerprintPolygon.tsx`, `HistoricalTwinCard.tsx`, `DnaManifoldScatter.tsx`, `PlayerDnaClient.tsx`, `/player-dna` route).
  - **Item 6 (True Clutch Index):** Completed (`build_clutch_dataset.R` as Stage 15, unassisted shot creation index [USCI], clutch True Shooting delta $\Delta\text{TS}\%$, turnover fragility under pressure, clutch defensive win probability added [c-dWPA], spatial breakdown, `web/lib/clutchTypes.ts`, `PressureResiliencePlot.tsx`, `ClutchShotBreakdownCard.tsx`, `ClutchClient.tsx`, `/clutch` route).
  - **Item 7 (CBA Cap Sheet & 11-vs-12 Roster Crunch):** Completed (`build_cba_cap_dataset.R` as Stage 16, modeling the 2026 WNBA hard salary cap [$1.520M], 90% floor [$1.368M], core player franchise tags, rookie wage ladders, 3-year commitments, and the legal 11-vs-12 player roster spot constraint, `web/lib/cbaTypes.ts`, `HardCapCrunchMeter.tsx`, `WnbaFranchiseCapTable.tsx`, `CapSheetClient.tsx`, `/cap-sheet` route).
- **Summary:** All 16 pipeline stages operational (45.6s end-to-end run); all 17 static web routes pre-rendered with zero errors. All Phase 3 items complete.

