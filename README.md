# MLB Analytics — Quantitative Sabermetric Engine

[![R Unit Tests & CI](https://github.com/kailot-harris/MLB-Analytics/actions/workflows/ci.yml/badge.svg)](https://github.com/kailot-harris/MLB-Analytics/actions/workflows/ci.yml)
[![R 4.5.2](https://img.shields.io/badge/R-4.5.2-blue.svg)](https://cran.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-grade quantitative sports analytics platform for Major League Baseball, joining sibling repos (`NBA Analytics`, `WNBA Analytics`, and `NFL Analytics`).

The system implements modern sabermetric win-expectation baselines, a 4-factor starting-pitcher Elo rating engine, Tom Tango's Marcel player projection system, closed-form hierarchical empirical Bayes partial pooling, bullpen fatigue/workload monitoring, 12-team postseason Monte Carlo bracket simulations, sharp market odds devigging, dynamic Kelly stop-loss risk management, and automated Discord bet dispatching.

---

## Architecture & Pipeline DAG

The engine executes as a staged DAG orchestrator with staleness validation and deep error logging in [`run_full_pipeline.R`](file:///run_full_pipeline.R):

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
| **11** | `mlb_market_odds_engine.R` | The Odds API (`baseball_mlb`), consensus sharp devigging, +EV detection, and fractional Kelly staking. |
| **12** | `mlb_risk_management_engine.R` | Bankroll drawdown tracking and dynamic Kelly stop-loss tiers (0.250 / 0.175 / 0.100 / 0.000 halt). |
| **13** | `mlb_notify_bets.R` | Discord webhook notification dispatcher with institutional CLV and sample-size edge filtering. |

---

## Quickstart

### 1. Environment Setup
Clone this repository and restore the exact dependency tree pinned in `renv.lock`:

```r
# Start R in the project root
renv::restore()
```

### 2. Configuration & Secrets
Copy or create `.Renviron` in the project root (gitignored) to configure optional API keys and webhooks:

```ini
ODDS_API_KEY="your_the_odds_api_key_here"
MLB_DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
```
*(If keys are absent, the system seamlessly operates on calibrated synthetic fallbacks with zero runtime errors).*

### 3. Run the Full Analytics Pipeline
Execute all 13 stages end-to-end:

```bash
Rscript run_full_pipeline.R
```

### 4. Run the Unit Test Suite
Run the 54 automated unit tests covering mathematical shrinkage, Pythagorean monotonicity, Elo formulas, odds devigging, and calibration:

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
- [`reports/Baseball analytics model comparison.md`](reports/Baseball%20analytics%20model%20comparison.md): Comprehensive survey comparing academic literature and production models across win expectation, player projections, and market efficiency.
- [`ROADMAP.md`](ROADMAP.md): Post-v1 capabilities, experimental ideas, and infrastructure backlog.
