---
name: pipeline-freshness-audit
description: Verifies that every stage of run_full_pipeline.R actually regenerated its declared output cache file (mtime advanced past run start), catching silent no-op stages whose logs claim success without doing work. Use immediately after any full-pipeline run, or when asked to verify the pipeline "actually did something" this run.
---

# Pipeline Freshness Audit

## Why this exists

This check was ported from the WNBA Analytics repo's identically-shaped bug: several of that
repo's pipeline stages gated their real logic on `sys.nframe() == 0`, a condition that is only
true when a script is the *top-level* `Rscript` entry point — never true when `source()`d from
inside a `run_stage()`-style orchestrator, which is how every stage in that pipeline actually ran.
The result: those stages logged a success line in well under a second while doing nothing, and
their output caches sat silently stale, sometimes for days, while the pipeline's own log insisted
everything was fresh. The lesson generalizes directly here: once this repo has a
`run_full_pipeline.R` DAG, any stage-invocation guard (`sys.nframe()`, `!interactive()`, or
similar) is a latent instance of the exact same bug class until proven otherwise, and a log line
claiming success is not evidence a stage actually did work — only an advancing output-file mtime
is. This skill exists as an independent, rerunnable check for that, separate from whatever
in-pipeline assertion the DAG itself may eventually add.

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
     verifying that against the stage's own logic — an incremental ingestion stage may
     legitimately leave its output's mtime unchanged on a run with no new source data.
     Distinguish "legitimately nothing to do" from "silently failed to run" by reading the
     stage's actual logic, not just the mtime delta.
4. Report a per-stage fresh/stale table plus a one-line verdict: pipeline run is trustworthy, or
   N stage(s) need investigation before trusting their output.

## Stage -> output manifest (keep in sync with run_full_pipeline.R)

Populated from `run_full_pipeline.R`'s Wave 1 skeleton (task P1-D, `docs/task_assignments_phase0.md`)
— three real ingestion stages — plus Phase 2's two metrics/ratings engine stages (task P2-C,
`docs/task_assignments_phase1.md`), Phase 3's fatigue engine stage (task P3-B,
`docs/task_assignments_phase2.md`), Phase 4's playoff bracket simulator stage (task P4-B, `docs/task_assignments_phase3.md`),
Phase 5's risk management engine stage (task P5-B, `docs/task_assignments_phase4.md`), and
Phase 6's market odds / value-betting engine stage (task P6-B, `docs/task_assignments_phase5.md`).
No stub/placeholder stages remain for later-phase engines that don't exist yet (embeddings/player
props/notify; see that file's Constraints section — notify_bets.R remains blocked on a Discord
webhook).

| Stage script | Declared output(s) |
|---|---|
| `daily_ingest.R` | `cache/pbp_cache.rds` (`CACHE_PBP`), `cache/schedules_cache.rds` (`CACHE_SCHEDULES`) |
| `sync_rosters.R` | `cache/rosters_cache.rds` (`CACHE_ROSTERS`) |
| `injury_scraper.R` | `cache/injury_data_cache.rds` (`CACHE_INJURY_DATA`) |
| `epa_metrics_engine.R` | `cache/team_epa_metrics.rds` (`CACHE_EPA_METRICS`) |
| `team_ratings_engine.R` | `cache/team_ratings.rds` (`CACHE_TEAM_RATINGS`), `cache/projected_matchups.rds` (`CACHE_PROJECTED_MATCHUPS`) |
| `fatigue_engine.R` | `cache/fatigue_metrics.rds` (`CACHE_FATIGUE_METRICS`) |
| `playoff_simulator.R` | `cache/playoff_simulation.rds` (`CACHE_PLAYOFF_SIMULATION`) |
| `risk_management_engine.R` | `cache/risk_state.rds` (`CACHE_RISK_STATE`) |
| `market_odds_engine.R` | `cache/latest_value_bets.rds` (`CACHE_LATEST_VALUE_BETS`), `cache/odds_history.rds` (`CACHE_ODDS_HISTORY`) |

**Deliberate exclusion / known false-positive source:** `daily_ingest.R` is an incremental
ingestion stage — `.ingest_one()` legitimately skips the write ("cache already up to date; no
write necessary") when `nflreadr::load_pbp()` / `nflreadr::load_schedules()` return zero new rows
for the current season, which is the common case on a quiet day (or on a second run shortly after
the first). A `[STALE]` verdict for this stage's outputs is therefore not automatically a silent
no-op bug the way it would be for `sync_rosters.R` or `injury_scraper.R` (which unconditionally
`saveRDS()` on every successful run) — cross-check the pipeline log for that run (was `force_refresh`
used? did the log report "N new records identified" as 0?) before concluding a real failure, per
Procedure step 3 above. This was confirmed empirically: forcing `run_daily_ingest(force_refresh =
TRUE)` produces a real rewrite that this check correctly reports `[FRESH]`; a normal incremental
run immediately afterward (0 new rows) correctly reports `[STALE]` because nothing was written —
both are the script behaving as designed, not a bug in the freshness check itself.

**If `run_full_pipeline.R`'s stage list or output paths ever change, update this table and
`scripts/check_freshness.R` together** — a stale manifest here would itself silently reintroduce
the exact failure mode this skill exists to catch.

## Safety note

This skill only *reads* file metadata and pipeline logs. It never re-runs the pipeline itself —
if a fresh run is needed to test this skill, that is a separate, explicit action (running
`run_full_pipeline.R` hits live external APIs and, if Discord/Odds API credentials are configured
in the environment, can dispatch real notifications or consume API quota). Confirm with the user
before triggering a live pipeline run purely to test this audit.
