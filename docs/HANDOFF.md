# MLB Analytics — Handoff Document

**Last updated**: 2026-10-18, after commit `bd90439` ("Phase 1 Wave 1: renv setup, logging, ingestion, stats sync, injury scraper, and 5-way ID crosswalk (#13)"). **`main` is clean and up to date with `origin/main`** (confirmed via `git status -sb` and `git push`). Written for whoever picks this repo up next, cold — read this before touching anything.

## What this project is

`MLB Analytics` is a brand-new sibling to an existing family of sports-analytics repos (`NBA Analytics` → `WNBA Analytics` → `NFL Analytics`, all under `C:\Users\kailo\kayceeslices\`), each later port built on a shared R architecture (`config.R` single-source-of-truth constants, `run_full_pipeline.R` staged DAG, Elo/ridge rating engines, fatigue/market/risk/notify stages, Discord dispatch).

- **Phase 0 (research)**: **100% complete and closed** (all 10 issues #1–#10 closed). Deliverable: `docs/MLB_REPLICATION_PLAN.md`.
- **Phase 1 (data foundation)**: **Wave 1 complete and closed** (#13 closed, verified live against live APIs).
- **Next up**: **Phase 1, Wave 2 (Issue #14)** — `run_full_pipeline.R` pipeline skeleton.

**Read in this order**:
1. `docs/task_assignments_phase1.md` — interface contracts and cache layout for Phase 1.
2. `docs/MLB_IMPLEMENTATION_PLAN.md` (314 lines, committed `4b19f23`) — the Phase 1–9 engine-build roadmap.
3. `docs/MLB_REPLICATION_PLAN.md` (530 lines, committed `1a495e9`, self-check-amended `237d1cb`) — the Phase 0 synthesis deliverable with primary sources and methodology.
4. `docs/research/phase0a-r-packages.md`, `phase0a-vendor-api.md`, `phase0b-team-player-stats.md`, `phase0c-elo-methodology.md`, `phase0d-specialty-models.md`, `phase0e-structural-divergences.md` — primary evidence files.

## Progress tracking

All tracking lives in the GitHub issue tracker (`kailot-harris/MLB-Analytics`), using native GitHub sub-issue and blocked-by/blocking relationships. Live state verified via `gh issue list --state all`.

### Phase 0 (research) — 100% Complete & Closed

| Issue | Title | Status | Evidence |
|---|---|---|---|
| #1 | Epic: Phase 0 research plan | **CLOSED** | All 9 sub-issues completed |
| #2 | Phase 0a: R-package ecosystem verification | CLOSED | `docs/research/phase0a-r-packages.md`; commit `1105811` |
| #3 | Phase 0a: Direct vendor/API verification | CLOSED | `docs/research/phase0a-vendor-api.md`; commit `1105811` |
| #4 | Phase 0b: Team/player statistics research | CLOSED | `docs/research/phase0b-team-player-stats.md`; commit `96acad1` |
| #5 | Phase 0c: Baseball Elo methodology research | CLOSED | `docs/research/phase0c-elo-methodology.md`; commit `0822baa` |
| #6 | Phase 0d: Specialty model research + ML citation | CLOSED | `docs/research/phase0d-specialty-models.md`; commit `e8291cd` (ML citation gap carried forward explicitly) |
| #7 | Phase 0e: Structural divergences research | CLOSED | `docs/research/phase0e-structural-divergences.md`; commit `bc47ebd` |
| #8 | Phase 0f: Draft `docs/MLB_REPLICATION_PLAN.md` | CLOSED | `docs/MLB_REPLICATION_PLAN.md`; commit `1a495e9` |
| #9 | Phase 0g: Self-check pass | CLOSED | `docs/MLB_REPLICATION_PLAN.md` amended; commit `237d1cb` |
| #10 | Phase 0h: Present deliverable / close Phase 0 | **CLOSED** | Accepted and closed |

### Phase 1–9 (engine build) — Live Status

| Issue | Title | Status | Blocked by | Notes |
|---|---|---|---|---|
| #11 | Epic: MLB Analytics engine build (Phases 1-9) | OPEN | — | Top-level epic |
| #12 | Phase 1: Data foundation | OPEN | — | Parent for Wave 1 & Wave 2 |
| **#13** | **Phase 1, Wave 1: Ingestion scripts + ID-crosswalk** | **CLOSED** | — | **Completed in commit `bd90439` with full live verification** |
| **#14** | **Phase 1, Wave 2: Pipeline skeleton (run_full_pipeline.R)** | **OPEN** | none (#13 closed) | **NEXT UP** |
| #15 | Phase 2: Rating engine (Pythagorean + Elo) | OPEN | #12 | Blocked by Phase 1 |
| #16 | Phase 2, Wave 1: Pythagorean baseline + Elo engine | OPEN | #12 | Parallelizable |
| #17 | Phase 2, Wave 2: Constant derivation + park-factor decision | OPEN | #16 | Blocked by #16 |
| #18 | Phase 3: Specialty models (Marcel, bullpen fatigue) | OPEN | #15 | Parallel with #19 once Phase 2 lands |
| #19 | Phase 4: Postseason bracket simulator | OPEN | #15 | Parallel with #18 |
| #20 | Phase 5: Risk management engine (port) | OPEN | #12 | Sport-agnostic port |
| #21 | Phase 6: Market odds engine (port) | OPEN | #12, #15 | Port with `baseball_mlb` sport key |
| #22 | Phase 7: Discord alert dispatcher (port) | OPEN | #21 | Port |
| #23 | Phase 8: Early-season calibration review | OPEN | #15 | Decision point |
| #24 | Phase 9+: Deferred / idea-stage placeholder | OPEN | #12,#15,#18–#23 | Post-ship |

## What's actually implemented

All Wave 1 code is implemented, live-tested, cached, and committed (`bd90439`).

| File | Lines | Type | Callable Entrypoint | Output / Cache |
|---|---|---|---|---|
| `config.R` | 247 | Real | `source("config.R")` | Single source of truth for paths, `cache_path()`, team/ID seed table, `MLB_WAR_SOURCE = "fWAR"`, Phase 2/3 placeholders. |
| `logging_utils.R` | 242 | Real | `log_info()`, `log_warn()`, `log_error()`, `log_live_call()` | Dual logging: console/text (`logs/mlb_pipeline.log`) + DuckDB analytical store (`logs/logs.duckdb`) with secret scrubbing. |
| `mlb_injury_scraper.R` | 151 | Real | `run_injury_scraper(force_refresh = FALSE)` | Scrapes ESPN MLB injuries feed, extracts ESPN athlete ID via Player-Card href. Verified: 280 records parsed, 100% ID extraction. Caches to `cache/injury/mlb_injuries.rds`. |
| `mlb_id_crosswalk.R` | 226 | Real | `run_id_crosswalk(force_refresh = FALSE)`, `query_id_crosswalk(id_scheme, id_val)` | Unified 5-way join table across MLBAM (`mlb_id`), FanGraphs (`fangraphs_id`), BRef (`bref_id`), Retrosheet (`retro_id`), and ESPN (`espn_id`). Ambiguous IDs deduplicated. Verified: 136,455 players indexed, dual-direction query verified. Caches to `cache/id_crosswalk/mlb_id_crosswalk.rds`. |
| `mlb_stats_sync.R` | 227 | Real | `run_stats_sync(seasons = c(2024, 2025, 2026), force_refresh = FALSE)` | Syncs FanGraphs batter leaders (617 rows), pitcher leaders (656 rows), and park factors (30 rows), enforcing `fWAR` as default. Caches to `cache/stats_sync/`. |
| `mlb_ingest.R` | 312 | Real | `run_mlb_ingest(season = 2024, start_date = NULL, end_date = NULL, force_refresh = FALSE)` | Ingests MLB schedule (2,998 games for 2024), box scores (200 team entries), and Statcast pitch records (7,836 rows) with seam annotations (`PITCHf/x` vs `Statcast_out_of_hand`, and 2026 strike zone ABS shift). Caches to `cache/ingest/`. |
| `docs/task_assignments_phase1.md` | 56 | Real | Doc | Phase 1 task assignments, interface contracts, and cache isolation specs. |
| `renv.lock` | — | Config | `renv::restore()` | Locked dependencies: `baseballr` (v2.0.0), `duckdb`, `dplyr`, `dbplyr`, `jsonlite`, `rvest`, `xml2`, etc. |
| `.Rprofile` & `renv/` | — | Config | Auto-bootstraps renv on session start. |

## Environment/tooling notes

- **Remote**: `origin` = `https://github.com/kailot-harris/MLB-Analytics`. Local `main` is clean and in sync with `origin/main`.
- **R Environment**: R 4.5.2 under `renv`. `renv::status()` is clean with zero issues.
- **R Packages**: `baseballr` 2.0.0 installed from CRAN; `duckdb` (1.5.6) provides backend for structured pipeline logs.
- **Global Skill Configuration**: `C:\Users\kailo\.gemini\config\skills.json` points to `~/.claude/skills`, giving Antigravity global access to `write-handoff`, `subagent-brief`, `spec-interview`, etc.
- **Git Ignore**: `cache/`, `logs/`, `renv/library/`, and `.claude/` are ignored so local caches and worktrees do not pollute git.

## The reusable workflow

### For Wave 2 (`run_full_pipeline.R`) and Phase 2+ stages
1. Verify prerequisite issues are closed (`gh issue view <N>` → check `blocked-by`).
2. Sourcing convention: scripts `source("config.R")` and `source("logging_utils.R")` at top.
3. Cache isolation: always use `cache_path("<stage>", "<filename>")` instead of hardcoded paths.
4. Interface contract: expose exactly one top-level `run_<stage>(...)` callable runner with `force_refresh = FALSE` default.
5. In `run_full_pipeline.R`: wrap every stage execution in `run_stage("<stage_name>", function() ...)` with try/catch error logging.
6. Commit with descriptive message and issue reference (`Closes #N`), push to `origin/main`, and post evidence comment on GitHub.

## Concrete next step

**Phase 1, Wave 2 (Issue #14) — Pipeline skeleton (`run_full_pipeline.R`)**:
- Wire Wave 1's four validated scripts into `run_full_pipeline.R`:
  1. `run_injury_scraper()`
  2. `run_id_crosswalk()`
  3. `run_stats_sync()`
  4. `run_mlb_ingest()`
- Implement `run_stage()` with elapsed time tracking, success/failure status, and DuckDB logging.
- Ensure the DAG structure allows Phase 2's rating engine stages (`mlb_pythag_baseline.R`, `mlb_elo_engine.R`) to plug in seamlessly.
- Commit, test end-to-end, and close #14, completing Phase 1 (#12).
