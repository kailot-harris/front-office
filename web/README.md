# MLB Analytics — Next.js 14 Web Dashboard

Quantitative sabermetric web platform for Major League Baseball, powered by the 14-stage R pipeline in the repository root.

## Routes & Capabilities

| Route | Component | Description |
| :--- | :--- | :--- |
| `/` & `/teams` | `StandingsClient.tsx`, `PlayoffContendersBoxWhisker.tsx` | 162-game Monte Carlo win distributions (p10–p90 whiskers, IQR box, median), AL/NL & 6-Division filters, 4-Factor Pitcher Elo, Pythagenpat luck, and World Series equity across all 30 MLB franchises. |
| `/variants` | `VariantsClient.tsx`, `BrierScoreComparison.tsx` | Interactive comparison across the **Multi-Model Sabermetric Blend** and 4 distinct MLB engines: **4-Factor Pitcher Elo** (35%), **Hierarchical Empirical Bayes Talent** (25%), **Pythagenpat Run-Expectation** (20%), and **Marcel 3-Yr + Bullpen Fatigue** (20%), plus 30-team divergence matrix ($\Delta W$). |
| `/players` | `PlayersClient.tsx` | Top-level **Batters (630)** / **Pitchers (649)** toggle with **Empirical Bayes Pooled Rates** (`wOBA`, `ISO`, `xFIP`, `K%`, `BB%`, `Park Factor`, `Shrinkage %`) and **Marcel Counting Projections** (`PA/IP`, `HR/SO`, `BB`, `OBP/ERA/rGS`), role filters (`SP`/`RP`), and outlier badges ($\|z\| \ge 2.0$). |
| `/postseason` | `PostseasonOpsClient.tsx` | 3-tab operational hub: **12-Team Postseason Bracket** (10,000 sims across WC/DS/LCS/WS), **30-Club Bullpen Workload & Fatigue Monitor**, and **Tactical Matchup & Upset Vulnerability Hub**. |
| `/diagnostics` | `DiagnosticsClient.tsx` | Walk-forward calibration over 2,430 resolved MLB games: Brier score vs. 0.2500 coin-flip benchmark, Log-Loss, +14.9 Elo Home Field Advantage, custom SVG **Probability Calibration Curve (Reliability Diagram)**, Early/Mid/Late season drift, and residual distribution. |

## Quickstart

```bash
# 1. Regenerate static JSON data from R caches (from repo root)
Rscript tools/export_web_data.R

# 2. Install & start Next.js development server
cd web
npm install
npm run dev
```
