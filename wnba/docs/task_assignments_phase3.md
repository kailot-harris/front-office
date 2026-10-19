# Task Assignments: Phase 3 (Production Hardening)
Date: 2026-09-15

## Overview
Phase 3 transitions the WNBA Analytics pipeline from an experimental port to a production-grade system. The focus is on Infrastructure Robustness, Predictive Integration, and Operational Efficiency.

## Task Tracker

| Task ID | Stage | Task Description | Assignee | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P3-1.1 | Infra | Implement `httr2::req_retry()` in all API calls | `agent_infra` | COMPLETED | Added `req_retry(max_tries = 3)` to `injury_scraper.R` and `market_odds_engine.R` |
| P3-1.2 | Infra | Create `tools/data_health_probe.R` (Schema/Anomaly checks) | `agent_infra` | COMPLETED | Created probe verifying cache existence, size, schema, and team completeness |
| P3-1.3 | Infra | Initialize `renv` environment lock | `agent_infra` | PENDING | Lock `wehoop`, `torch`, `ranger` |
| P3-1.4 | Infra | Unify logging in `daily_ingest.R` to use `logging_utils.R` | `agent_infra` | COMPLETED | Replaced local `log_message` with centralized `log_info/warn/error` |
| P3-2.1 | Perf | Promote Elo/RAPM differentials to production model | `agent_perf` | COMPLETED | Integrated logistic Elo (K=20) and RAPM (L2 Ridge) into a blended margin model in `roster_bottom_up_engine.R` |
| P3-2.2 | Perf | Wire `team_embeddings.py` into `run_full_pipeline.R` | `agent_perf` | COMPLETED | Added `run_stage` call for `team_embeddings.py` to the pipeline; updated `run_stage` to support Python scripts |
| P3-2.3 | Perf | Empirical Parameterization of Props constants | `agent_perf` | COMPLETED | Derived ZINB theta and pi_0, and Copula sigma_mat, from real WNBA rotation data in `player_props_engine.R` and `copula_props_engine.R` |
| P3-2.4 | Perf | Implement RAPM-based Opponent Adjustment for Props | `agent_perf` | COMPLETED | Updated `player_props_engine.R` to adjust `projected_mu` using team-level defensive RAPM from the current slate |
| P3-3.1 | Ops | Optimize Base Cache I/O in `run_full_pipeline.R` | `agent_ops` | COMPLETED | Loaded `player_box_scores_cache.rds` and `active_rosters_cache.rds` into global env in `run_full_pipeline.R`; updated engines to check globals before disk read |
| P3-3.2 | Ops | Vectorize `player_props_engine.R` player-stat loop | `agent_ops` | COMPLETED | Refactored `price_prop_zinb` to handle vectors and replaced the `for` loop in `generate_active_props_table` with vectorized `dplyr`/`bind_rows` operations |
| P3-3.3 | Ops | Implement Parallel Execution for independent engines | `agent_ops` | COMPLETED | Integrated `future` and `future.apply` in `run_full_pipeline.R`; parallelized Latent Engines and Props Engines groups |

## Handoff Notes
- **P3-1.1 (API Retries):** Implemented `httr2::req_retry(max_tries = 3)` in `injury_scraper.R` and `market_odds_engine.R` for all direct `httr2` requests. Note: `daily_ingest.R` uses `wehoop` package wrappers; as `req_retry` is specific to `httr2` request objects, it was not applicable to the wrapper calls.
- **P3-1.2 (Health Probe):** Created `tools/data_health_probe.R`. It validates critical caches (`box_scores_cache.rds`, `injury_data_cache.rds`, etc.) for existence, non-zero size, and key column presence. Includes a specific check to ensure all 15 `WNBA_TEAMS` are present in the box score cache.
- **P3-1.4 (Logging):** Removed the local `log_message` function from `daily_ingest.R` and migrated all calls to the structured `log_info`, `log_warn`, and `log_error` functions from `logging_utils.R`.
