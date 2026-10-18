# Phase 1 Task Assignments: Data Foundation

**Phase**: 1 — Data Foundation: Ingestion Scripts + ID-Crosswalk Utility + Pipeline Skeleton  
**Epic**: #11 (MLB Analytics Engine Build)  
**Parent Tracker Issue**: #12  
**Date**: 2026-10-18  
**Status**: Wave 1 in progress / nearing completion; Wave 2 queued  

---

## 1. Wave Architecture & Interface Contracts

Phase 1 establishes the foundational data layer for the MLB Analytics engine. It consists of two sequential waves:
- **Wave 1 (Issue #13)**: 4 parallel, file-disjoint data acquisition and mapping scripts sharing `config.R` and `logging_utils.R`.
- **Wave 2 (Issue #14)**: The pipeline orchestration skeleton `run_full_pipeline.R` wiring all stages via `run_stage()` with try/catch logging.

### Cache Directory Isolation

All stages write exclusively to isolated subdirectories under `cache/` managed by `cache_path(stage, ...)` from `config.R`:
- `cache/ingest/` — MLB schedule, box scores, and Statcast pitch caches (`mlb_ingest.R`)
- `cache/stats_sync/` — FanGraphs batter, pitcher, and park factor caches (`mlb_stats_sync.R`)
- `cache/injury/` — ESPN injury reports (`mlb_injury_scraper.R`)
- `cache/id_crosswalk/` — Master 5-way player ID crosswalk table (`mlb_id_crosswalk.R`)

---

## 2. Component Deliverables & Status

### Wave 1 Deliverables (Issue #13)

| Component | File | Callable Contract | Output / Cache | Status |
|---|---|---|---|---|
| **Configuration** | `config.R` | `source("config.R")` (defines `cache_path()`, team table, `MLB_WAR_SOURCE = "fWAR"`, placeholders for Phase 2+ constants) | Shared configuration | **Done** (committed & pushed) |
| **Structured Logging** | `logging_utils.R` | `log_info()`, `log_warn()`, `log_error()`, `log_live_call()` | Console + `logs/mlb_pipeline.log` + DuckDB | **Done** |
| **Environment Setup** | `renv.lock`, `.Rprofile` | `renv::restore()`, `renv::status()` | Consistent R package library (`baseballr` v2.0.0, `duckdb`, `dplyr`, `jsonlite`, etc.) | **Done** |
| **Injury Scraper** | `mlb_injury_scraper.R` | `run_injury_scraper(force_refresh = FALSE)` | `cache/injury/mlb_injuries.rds` | **Done** (verified live: 280 injuries parsed, 100% ESPN athlete IDs extracted via Player-Card href) |
| **ID Crosswalk** | `mlb_id_crosswalk.R` | `run_id_crosswalk(force_refresh = FALSE)`, `query_id_crosswalk(id_scheme, id_value)` | `cache/id_crosswalk/mlb_id_crosswalk.rds` | **Done** (verified live: 136k players indexed across MLBAM, FanGraphs, BRef, Retrosheet, ESPN) |
| **Stats Sync** | `mlb_stats_sync.R` | `run_stats_sync(seasons = c(2024, 2025, 2026), force_refresh = FALSE)` | `cache/stats_sync/fg_batters.rds`, `fg_pitchers.rds`, `fg_park.rds` | **Done** (verified live: 617 batters, 656 pitchers, 30 park factors, fWAR default enforced) |
| **Data Ingestion** | `mlb_ingest.R` | `run_mlb_ingest(season = 2024, start_date = NULL, end_date = NULL, force_refresh = FALSE)` | `cache/ingest/mlb_schedule_<yr>.rds`, `mlb_boxscores_<yr>.rds`, `statcast_pitches_<dates>.rds` | **Done / In verification** (schedule, box scores, seam-annotated Statcast) |

### Wave 2 Deliverable (Issue #14)

| Component | File | Callable Contract | Prerequisites | Status |
|---|---|---|---|---|
| **Pipeline Skeleton** | `run_full_pipeline.R` | `run_full_pipeline(season = 2024, force_refresh = FALSE)` | Wave 1 contracts finalized | **Queued** (blocked by #13) |

---

## 3. Methodological Decisions Enforced

1. **fWAR as Default WAR Source**:
   Per `MLB_REPLICATION_PLAN.md` §2a and `config.R`, `MLB_WAR_SOURCE <- "fWAR"`. `mlb_stats_sync.R` explicitly ensures `fWAR` is populated from FanGraphs leaderboards.
2. **Ambiguous ID Dropping**:
   Following sibling repo discipline, `mlb_id_crosswalk.R` drops duplicate ID values mapping to multiple distinct players rather than guessing.
3. **Statcast Coverage Seams**:
   `mlb_ingest.R` annotates pitch records with `tracking_system` (`PITCHf_x_adjusted` pre-2017 vs. `Statcast_out_of_hand` 2017+) and `sz_reference_point` (`middle_of_plate_ABS` 2026+ vs `front_of_plate`).
