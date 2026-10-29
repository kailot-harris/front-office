# WNBA Analytics — Quantitative Front-Office Research Platform

Analyzing WNBA games, lineups, and players to deliver pure statistical game projections, Bayesian player evaluations, tactical matchup hubs, and a Monte Carlo season simulation pipeline that projects full-season win totals, playoff seeding, and series outcomes.

> [!NOTE]
> **Betting-Free Platform Declaration:** This platform is 100% free of commercial betting, gambling apparatuses, odds devigging, Kelly staking, bankroll units, and `ODDS_API_KEY`. All pipelines and models operate with pure endogenous statistical mechanics, open-data schedule providers, forecast calibration governance (`accuracy_governance.R`), and operational telemetry (`notify_pipeline_ops.R`).

## Pipeline & Architecture

The analytical pipeline executes as a deterministic, reproducible workflow orchestrated by `run_full_pipeline.R`:
1. **Ingest & Data Sync:** Real-time and historical box-score feeds via `wehoop`.
2. **Ratings & Models:** Endogenous team ratings, margin projections, and Poisson/normal game models.
3. **Forecast Governance:** `accuracy_governance.R` calculates Straight-Up Accuracy (STD and rolling 30-game), Brier Skill Score against standard baselines, log-loss, and Expected Calibration Error (ECE) with decile bins.
4. **Operations Telemetry:** `notify_pipeline_ops.R` dispatches non-betting health reports, slate summaries, and injury/availability alerts via `DISCORD_OPS_WEBHOOK_URL` (clean no-op if unset).

## Setup & Dependencies

1. **Clone and open the repo:** Open the project root in RStudio or your terminal.
2. **Install R:** Ensure R (>= 4.5.0) is installed.
3. **Restore environment:** Dependencies are pinned via `renv`:
   ```r
   renv::restore()
   ```

## Running the Pipeline

Execute the full daily quantitative pipeline:
```bash
Rscript run_full_pipeline.R
```

Render the comprehensive research report:
```r
rmarkdown::render("WNBA_Analysis_Project.Rmd")
```
*(PDF output requires `tinytex`).*
