# MLB Analytics — Quantitative Sabermetric Engine

[![R Unit Tests & CI](https://github.com/kailot-harris/MLB-Analytics/actions/workflows/ci.yml/badge.svg)](https://github.com/kailot-harris/MLB-Analytics/actions/workflows/ci.yml)
[![R 4.5.2](https://img.shields.io/badge/R-4.5.2-blue.svg)](https://cran.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-grade quantitative sports analytics platform for Major League Baseball, operating as an open front-office research platform alongside sibling repositories (`NBA Analytics`, `WNBA Analytics`, and `NFL Analytics`).

> [!NOTE]
> **Betting-Free Platform Declaration:** This platform is 100% free of commercial betting, gambling apparatuses, odds devigging, Kelly staking, bankroll units, closing line values, and `ODDS_API_KEY`. All pipelines and models operate with pure endogenous statistical mechanics, open-data schedule providers, forecast calibration governance, and operational telemetry.

The system implements modern sabermetric win-expectation baselines, a 4-factor starting-pitcher Elo rating engine, Tom Tango's Marcel player projection system, closed-form hierarchical empirical Bayes partial pooling, bullpen fatigue/workload monitoring, 12-team postseason Monte Carlo bracket simulations, forecast accuracy governance (Straight-Up Accuracy, Brier Skill Score, Log-loss, ECE), and automated Discord operations telemetry.

---

## Architecture & Pipeline DAG

The engine executes as a staged DAG orchestrator with staleness validation and deep error logging in [`run_full_pipeline.R`](run_full_pipeline.R):

| Stage | Module | Methodology / Output |
|:---:|:---|:---|
| **1** | `mlb_ingest.R` | High-throughput batch ingestion of schedules, box scores, and Statcast pitch data (`baseballr`). |
| **2** | `mlb_stats_sync.R` | FanGraphs leaderboards sync for batters, pitchers, and 30-venue park factors. |
| **3** | `mlb_injury_scraper.R` | ESPN MLB injury report scraper with player card ID parsing. |
| **4** | `mlb_id_crosswalk.R` | 5-way crosswalk join across MLBAM, FanGraphs, Baseball-Reference, Retrosheet, and ESPN IDs. |
| **5** | `mlb_pythag_baseline.R` | David Smyth's Pythagenpat variable-exponent run-expectation baseline ($G^{0.287}$). |
| **6** | `mlb_elo_engine.R` | 4-factor team Elo rating engine (HFA, rest, travel, and Tangotiger rolling starter rGS adjustment). |
| **7** | `mlb_marcel_baseline.R` | Tom Tango's 3-year Marcel projection system (5/4/3 weights, regression to mean, age curve). |
| **8** | `mlb_bayes_pooling.R` | Closed-form empirical Bayes partial pooling (Beta-Binomial rates, Normal-Normal continuous stats). |
| **9** | `mlb_bullpen_fatigue.R` | Relief-pitcher cumulative pitch counts, consecutive-day appearances, and velocity decline tracking. |
| **10** | `mlb_postseason_simulator.R`| 12-team Monte Carlo bracket simulator (10,000 runs, best-of-3/5/7 series, regular extra-innings rules). |
| **11** | `accuracy_governance.R` | Forecast governance engine computing Straight-Up Accuracy, Brier Skill Score against baselines, log-loss, and Expected Calibration Error (ECE). |
| **12** | `tools/export_web_data.R` | Exports 30-team Monte Carlo projections, 1,279 batter/pitcher Bayes & Marcel profiles, 10,000-sim bracket odds, bullpen status, and calibration JSON to `web/public/data/`. |
| **13** | `notify_pipeline_ops.R` | Discord front-office operations alert dispatcher broadcasting pipeline telemetry, slate briefings, and availability alerts. |

---

## Quickstart

### 1. Environment Setup
Clone this repository and restore the exact dependency tree pinned in `renv.lock`:

```r
# Start R in the project root
renv::restore()
```

### 2. Configuration & Operations Telemetry
Optional environment variables can be configured in `.Renviron` (or system environment):

```ini
DISCORD_OPS_WEBHOOK_URL="https://discord.com/api/webhooks/..."
```
*(If unset, the pipeline runs cleanly with operations telemetry as a silent no-op).*

### 3. Run the Full Analytics Pipeline
Execute all stages end-to-end:

```bash
Rscript run_full_pipeline.R
```

### 4. Run the Unit Test Suite
Run the automated unit tests covering mathematical shrinkage, Pythagorean monotonicity, Elo formulas, calibration, and governance:

```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

### 5. Automated Scheduling
The pipeline includes pre-configured automation for Windows Task Scheduler and daemon execution:
- **Runner**: `scripts/run_pipeline_task.ps1`
- **Schedule Definition**: `scripts/mlb_pipeline_task.xml` (runs twice daily at 11:00 AM and 5:00 PM local time, logging to `logs/scheduled_runs.log`).

---

## Detailed Documentation & Research
- [`docs/HANDOFF.md`](docs/HANDOFF.md): Engineering handoff guide, architectural decisions, and stage contracts.
- [`reports/Baseball analytics model comparison.md`](reports/Baseball%20analytics%20model%20comparison.md): Comprehensive survey comparing academic literature and production models across win expectation, player projections, and front-office metrics.
- [`ROADMAP.md`](ROADMAP.md): Post-v1 capabilities, experimental ideas, and infrastructure backlog.
