# NFL Analytics — Quantitative Front-Office Research Platform

A production quantitative sports analytics platform for the National Football League, providing pure game-level statistical modeling, situational EPA metrics, power ratings, Monte Carlo playoff simulations, and front-office decision support.

> [!NOTE]
> **Betting-Free Platform Declaration:** This platform is 100% free of commercial betting, gambling apparatuses, odds devigging, Kelly staking, bankroll units, and `ODDS_API_KEY`. All pipelines and models operate with pure endogenous statistical mechanics, open-data schedule providers, forecast calibration governance (`accuracy_governance.R`), and operational telemetry (`notify_pipeline_ops.R`).

## Pipeline & Architecture

The analytical pipeline executes as a deterministic, reproducible DAG orchestrated by `run_full_pipeline.R`:
1. **Ingest & Data Sync:** Play-by-play, schedules, rosters, and depth charts via `nflreadr`.
2. **EPA & Ratings Engines:** Situational EPA/CPOE engines, Elo ratings, Ridge models, and fatigue metrics.
3. **Playoff Simulator & Projections:** Monte Carlo bracket simulations and division/conference race projections.
4. **Forecast Governance:** `accuracy_governance.R` computes Straight-Up Accuracy (STD and rolling 30-game), Brier Skill Score against baselines, log-loss, and Expected Calibration Error (ECE) across 10 deciles, stored in `cache/accuracy_governance.rds`.
5. **Web Exporter:** `export_web_datasets.R` outputs JSON datasets for the web application to `web/public/data/`.
6. **Operations Telemetry:** `notify_pipeline_ops.R` dispatches non-betting health reports, slate summaries, and injury/availability alerts via `DISCORD_OPS_WEBHOOK_URL` (clean no-op if unset).

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
