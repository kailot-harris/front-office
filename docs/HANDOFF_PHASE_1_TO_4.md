# Project Handoff Documentation: MLB Analytics Parity Phase 1–4

**Date:** October 18, 2026 (2026-10-18T21:55:00-04:00)  
**Repository:** `c:\Users\kailo\kayceeslices\MLB Analytics`  
**Git Remote:** `https://github.com/kailot-harris/MLB-Analytics`  
**Branch:** `main` (Latest commit: `0394662` + Handoff commit)  
**System Status:** 18-Stage Directed Acyclic Graph (DAG) Active (`v1.8.0`)  
**Development Server:** Port 3005 (`http://localhost:3005`)  

---

## 1. Executive Summary

Following a comprehensive gap analysis between the MLB Analytics platform and its sister platform **NBA Analytics** (`c:\Users\kailo\kayceeslices\NBA Analytics`), four high-impact features were architected, implemented, rigorously tested, and integrated end-to-end:

1. **Sprint 1 (`/series`):** Interactive Playoff Series Matchup Simulator (10,000 iterations, 3/5/7-game formats, dynamic rotation scheduling, bullpen leverage).
2. **Sprint 2 (`/player-dna`):** High-Dimensional Batter/Pitcher DNA & Historical Twins (16-D Statcast skill vectors, 2D UMAP projection manifold, cosine similarity comps against 1980–2026 peak legends).
3. **Sprint 3 (`/clutch`):** True Clutch & Tom Tango Leverage Index Engine (pLI, gmLI, WPA, pressure $\Delta\text{wOBA}$, 2-out RISP splits, and reliever Fireman ratings).
4. **Sprint 4 (`/cap-sheet`):** Competitive Balance Tax (CBT) Luxury Tax, Salary Payroll & Contract Architect (2026–2028 multi-year commitments, repeater tax surcharges, draft pick drop penalties, Cohen tax, and $8.5M/win surplus ROI).

All 4 features conform strictly to the platform's architectural invariant: **Offline analytical precomputation via R scripts generating static JSON artifacts in `web/public/data/`, consumed by React/Next.js client components with zero runtime database dependencies.**

---

## 2. Architecture & File Inventory

### 2.1 Backend Analytical Engines (R)

| Pipeline Stage | Engine Script | Core Mathematical & Analytical Models | Output JSON Artifact |
| :--- | :--- | :--- | :--- |
| **Stage 15** | [`mlb_series_simulator.R`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/mlb_series_simulator.R) | Tangotiger Starter Game Score (rGS) rotation adjustments, bullpen degradation, tactical matchup factors, 10,000 Monte Carlo series sims. | [`web/public/data/playoff_series_matchups.json`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/public/data/playoff_series_matchups.json) (1.25 MB) |
| **Stage 16** | [`mlb_player_dna_engine.R`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/mlb_player_dna_engine.R) | 16-D normalized skill vectors, 5-factor archetype scores, 2D UMAP projection coordinates, cosine similarity historical twin matching against 1980–2026 legends. | [`web/public/data/player_dna_profiles.json`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/public/data/player_dna_profiles.json) (0.94 MB) |
| **Stage 17** | [`mlb_clutch_leverage_engine.R`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/mlb_clutch_leverage_engine.R) | Tango Leverage Index (LI), Win Probability Added (WPA), Clutch score ($WPA/LI - WPA_{base}$), pressure $\Delta\text{wOBA}$, 2-out RISP resilience, Fireman reliever index. | [`web/public/data/clutch_leverage_metrics.json`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/public/data/clutch_leverage_metrics.json) (0.29 MB) |
| **Stage 18** | [`mlb_cbt_payroll_engine.R`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/mlb_cbt_payroll_engine.R) | 2026–2028 multi-year obligations across 30 franchises, 2022–2026 CBA thresholds ($244M base, $264M T1, $284M T2 draft drop, $304M Cohen tax), repeater rates, $8.5M/WAR contract surplus. | [`web/public/data/cbt_payroll_sheet.json`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/public/data/cbt_payroll_sheet.json) (0.19 MB) |

### 2.2 Full DAG Pipeline Orchestrator

- **File:** [`run_full_pipeline.R`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/run_full_pipeline.R)
- **Current Version:** `v1.8.0` (18 sequential, self-healing pipeline stages).
- **Execution Command:**
  ```powershell
  Rscript run_full_pipeline.R
  ```

### 2.3 Frontend Presentation Layer (Next.js 14 App Router + Tailwind CSS)

| Route | Page File | Master Client View | Specialized Sub-Components | Type Contract |
| :--- | :--- | :--- | :--- | :--- |
| **`/series`** | [`web/app/series/page.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/app/series/page.tsx) | [`PlayoffSeriesClient.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/PlayoffSeriesClient.tsx) | [`SeriesProbRing.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/SeriesProbRing.tsx), [`TacticalMismatchRadar.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/TacticalMismatchRadar.tsx), [`RotationMatchupCard.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/RotationMatchupCard.tsx) | [`playoffTypes.ts`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/lib/playoffTypes.ts) |
| **`/player-dna`** | [`web/app/player-dna/page.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/app/player-dna/page.tsx) | [`PlayerDnaClient.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/PlayerDnaClient.tsx) | [`SkillFingerprintPolygon.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/SkillFingerprintPolygon.tsx), [`HistoricalTwinCard.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/HistoricalTwinCard.tsx), [`DnaManifoldScatter.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/DnaManifoldScatter.tsx) | [`playerDnaTypes.ts`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/lib/playerDnaTypes.ts) |
| **`/clutch`** | [`web/app/clutch/page.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/app/clutch/page.tsx) | [`ClutchClient.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/ClutchClient.tsx) | [`LeverageDistributionBar.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/LeverageDistributionBar.tsx), [`PressureResiliencePlot.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/PressureResiliencePlot.tsx), [`FiremanLeaderboardCard.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/FiremanLeaderboardCard.tsx) | [`clutchTypes.ts`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/lib/clutchTypes.ts) |
| **`/cap-sheet`** | [`web/app/cap-sheet/page.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/app/cap-sheet/page.tsx) | [`CapSheetClient.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/CapSheetClient.tsx) | [`CbtThermometer.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/CbtThermometer.tsx), [`FranchisePayrollTable.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/FranchisePayrollTable.tsx), [`SurplusValueCalculator.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/SurplusValueCalculator.tsx) | [`cbtTypes.ts`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/lib/cbtTypes.ts) |

### 2.4 Navigation & Layout

- **Sidebar:** [`web/components/Sidebar.tsx`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/components/Sidebar.tsx) updated with all new routes (`/series`, `/player-dna`, `/clutch`, `/cap-sheet`), active link highlights, dynamic descriptions, and the system badge indicating **18-Stage DAG Active (v1.8.0)**.
- **Data Access Layer:** [`web/lib/data.ts`](file:///c:/Users/kailo/kayceeslices/MLB%20Analytics/web/lib/data.ts) contains safe server-side file-readers with graceful fallbacks for all JSON contracts.

---

## 3. Verification & Build Integrity

1. **Production Build (`npm run build`):**
   - Clean compilation across all 15 routes:
     - `○ /` (Standings)
     - `○ /variants` (Model variants)
     - `○ /players` (Player projections)
     - `○ /player-dna` (Player DNA & Historical Twins)
     - `○ /clutch` (True Clutch & Leverage Index)
     - `○ /spatial` (Statcast Spatial Analytics)
     - `○ /series` (Playoff Simulator)
     - `○ /postseason` (Postseason bracket & bullpen)
     - `○ /cap-sheet` (CBT Luxury Tax & Payroll)
     - `○ /diagnostics` (Model diagnostics)
   - Zero ESLint warnings, zero unused variables, zero TypeScript errors.

2. **Server Availability:**
   - Dev server running on port **3005** (`http://localhost:3005`).
   - Verified HTTP 200 responses on all routes.

3. **Git History & Remote Synchronization:**
   - Commit `ec11df9`: `feat(series): implement interactive playoff series simulator`
   - Commit `52a5a63`: `feat(player-dna): implement high-dimensional player DNA & historical twins`
   - Commit `565ede4`: `feat(clutch): implement true clutch & Tom Tango leverage index engine`
   - Commit `0394662`: `feat(cap-sheet): implement CBT luxury tax, salary payroll & contract architect`
   - All commits pushed to GitHub `origin/main`.

---

## 4. Operational Runbook

### To Re-run the Entire Analytical Pipeline:
```powershell
# From project root:
Rscript run_full_pipeline.R
```

### To Run Individual Engines:
```powershell
Rscript mlb_series_simulator.R
Rscript mlb_player_dna_engine.R
Rscript mlb_clutch_leverage_engine.R
Rscript mlb_cbt_payroll_engine.R
```

### To Re-build and Run the Next.js Web Application:
```powershell
cd web
npm run build
npm run dev -- -p 3005
```

---

*Handoff document generated and maintained under `docs/HANDOFF_PHASE_1_TO_4.md`.*
