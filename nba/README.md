# NBA Analytics — Quantitative Front-Office Research Platform

A production quantitative sports analytics platform for the National Basketball Association, providing game-level statistical modeling, tactical matchup hubs, Monte Carlo playoff simulations, and front-office decision support.

> [!NOTE]
> **Betting-Free Platform Declaration:** This platform is 100% free of commercial betting, gambling apparatuses, odds devigging, Kelly staking, bankroll units, and `ODDS_API_KEY`. All pipelines and models operate with pure endogenous statistical mechanics, open-data schedule providers, forecast calibration governance (`accuracy_governance.R`), and operational telemetry (`notify_pipeline_ops.R`).

## Pipeline & Architecture

The analytical pipeline executes as a deterministic, reproducible workflow orchestrated by `run_full_pipeline.R`:
1. **Ingest & Rosters:** Box scores, active rosters, and injury feeds via `hoopR` and ESPN feeds.
2. **Ratings & Models:** Endogenous team ratings, margin projections, and stacking ensembles.
3. **Forecast Governance:** `accuracy_governance.R` computes Straight-Up Accuracy (STD and rolling 30-game), Brier Skill Score against 50/50 and home baselines, log-loss, and Expected Calibration Error (ECE) across 10 deciles, stored in `cache/accuracy_governance.rds`.
4. **Operations Telemetry:** `notify_pipeline_ops.R` dispatches non-betting health reports, slate summaries, and injury/availability alerts via `DISCORD_OPS_WEBHOOK_URL` (clean no-op if unset).

## Setup & Execution

1. **Environment Setup:** Ensure R (>= 4.5.0) is installed.
2. **Optional Telemetry Configuration:** Add your Discord webhook to `.Renviron` if alert broadcasting is desired:
   ```ini
   DISCORD_OPS_WEBHOOK_URL="https://discord.com/api/webhooks/..."
   ```
   *(If unset, the pipeline runs cleanly with operations telemetry as a silent no-op).*
3. **Run Pipeline:**
   ```bash
   Rscript run_full_pipeline.R
   ```
4. **Web Application:** The accompanying Next.js web application is located under `web/`:
   ```bash
   cd web && npm install && npm run dev
   ```
