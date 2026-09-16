---
name: pipeline-freshness-audit
description: Verifies that every stage of run_full_pipeline.R actually regenerated its declared output cache file (mtime advanced past run start), catching silent no-op stages whose logs claim success without doing work. Use immediately after any full-pipeline run, or when asked to verify the pipeline "actually did something" this run.
---

# Pipeline Freshness Audit

## Why this exists

This repo previously had four pipeline stages (`sync_rosters.R`, `injury_scraper.R`,
`roster_bottom_up_engine.R`, `playoff_simulator.R`) gate their real logic on
`sys.nframe() == 0`, a condition that is only true when a script is the *top-level* `Rscript`
entry point — never true when `source()`d from inside `run_stage()`, which is how every stage in
this pipeline actually runs. The result: these stages logged `[COMPLETED]` in well under a second
while doing nothing, and their output caches sat silently stale, sometimes for days, while the
pipeline's own log insisted everything was fresh. `run_full_pipeline.R` now asserts this itself
via `.check_stage_output()`, but this skill exists as an independent, rerunnable second check —
useful when auditing a run's logs after the fact, or when verifying a fix to the guard condition
actually holds across a real run.

## When to use

- Immediately after any `Rscript.exe run_full_pipeline.R` invocation, live or scheduled.
- When asked to confirm a specific stage's fix (e.g. an `interactive()` guard change) actually
  causes that stage to do real work under `source()`.
- When investigating why a downstream number looks stale despite a "successful" pipeline log.

## Procedure

1. Note (or ask the user for) the wall-clock time the pipeline run started. If unknown, use the
   mtime of `pipeline_execution.log`'s first line for that run as a proxy.
2. Run `Rscript.exe scripts/check_freshness.R "<run-start-timestamp>"` (format
   `YYYY-MM-DD HH:MM:SS`). The script holds a hardcoded stage -> output-cache manifest (see
   below) and reports, per stage, whether every declared output file's mtime is at or after the
   given timestamp.
3. For any stage flagged stale:
   - Check the pipeline log for that stage's actual duration. A stage that completed in a
     fraction of a second when its neighbors took several seconds is a strong tell of a silent
     no-op, independent of the mtime check.
   - Open the stage script and check its execution guard (`!interactive()`, `sys.nframe()`, etc.)
     for the exact bug class described above.
   - Do not assume the cache is merely "not updated because there was nothing new" without
     verifying that against the stage's own logic — e.g. `daily_ingest.R` is deliberately
     incremental and may legitimately leave `CACHE_TEAM_BOX`'s mtime unchanged on a day with no
     new games. Distinguish "legitimately nothing to do" from "silently failed to run" by reading
     the stage's actual logic, not just the mtime delta.
4. Report a per-stage fresh/stale table plus a one-line verdict: pipeline run is trustworthy, or
   N stage(s) need investigation before trusting their output.

## Stage -> output manifest (keep in sync with run_full_pipeline.R)

This manifest is hardcoded in `scripts/check_freshness.R` and mirrors the `output = ` arguments
in `run_full_pipeline.R` as of the current DAG:

| Stage script | Declared output(s) |
|---|---|
| `sync_rosters.R` | `cache/active_rosters_cache.rds` |
| `injury_scraper.R` | `config.R`'s `CACHE_INJURY_DATA` |
| `team_embeddings.py` | `logs/analytics.duckdb` |
| `shot_quality_engine.R` | `cache/team_shot_quality.rds` |
| `fatigue_travel_engine.R` | `cache/travel_fatigue_metrics.rds` |
| `rapm_engine.R` | `cache/rapm_ratings.rds` |
| `roster_bottom_up_engine.R` | `cache/projected_wnba_standings.rds` |
| `market_odds_engine.R` | `cache/latest_value_bets.rds`, `cache/odds_history.rds` |
| `player_props_engine.R` | `config.R`'s `CACHE_PLAYER_PROPS` |
| `copula_props_engine.R` | `cache/copula_wilson_pra.rds` |
| `playoff_simulator.R` | `cache/playoff_series_wnba_demo.rds` |
| `risk_management_engine.R` | `cache/risk_state.rds` |
| `bet_tracker.r` | `cache/rolling_bet_metrics.rds` |

Stages deliberately excluded from this manifest (no `output =` declared in
`run_full_pipeline.R`, by design): `tools/data_health_probe.R` (diagnostic only),
`daily_ingest.R` (incremental — see step 3 above), both `prediction_accuracy_logger.R`
invocations (log-append semantics, not a single-file freshness target), and `notify_bets.R`
(dispatch-only, no cache output).

**If `run_full_pipeline.R`'s stage list or output paths ever change, update this table and
`scripts/check_freshness.R` together** — a stale manifest here would itself silently reintroduce
the exact failure mode this skill exists to catch.

## Safety note

This skill only *reads* file metadata and pipeline logs. It never re-runs the pipeline itself —
if a fresh run is needed to test this skill, that is a separate, explicit action (running
`run_full_pipeline.R` hits live external APIs and, if Discord/Odds API credentials are configured
in the environment, can dispatch real notifications or consume API quota). Confirm with the user
before triggering a live pipeline run purely to test this audit.
