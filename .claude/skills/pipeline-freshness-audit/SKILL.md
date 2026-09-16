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

**PLACEHOLDER — not yet populated.** This repo does not have a `run_full_pipeline.R` DAG yet (it's
Phase 1+ work); there is nothing real to mirror here. The table below shows the *shape* this
manifest must take once the pipeline exists — same columns, one row per stage — ported from the
WNBA Analytics repo's equivalent table for reference, not as a claim about this repo's actual
stages. Do not fabricate NFL-specific stage/script names to fill this in prematurely.

| Stage script | Declared output(s) |
|---|---|
| `TODO: populate from run_full_pipeline.R once it exists` | `TODO` |

**Once `run_full_pipeline.R` exists in this repo:**
1. Replace the placeholder row(s) above with one row per real stage, mirroring that script's
   `output = ` arguments.
2. Populate the matching `manifest` list in `scripts/check_freshness.R` (currently an empty
   placeholder that errors loudly if run before this step is done) with the same stage/output
   pairs.
3. Note here which stages are deliberately excluded (diagnostic-only scripts, incremental
   ingestion stages, log-append-only stages, dispatch-only stages) and why, mirroring the kind of
   exclusions the WNBA repo's pipeline needed.

**If `run_full_pipeline.R`'s stage list or output paths ever change, update this table and
`scripts/check_freshness.R` together** — a stale manifest here would itself silently reintroduce
the exact failure mode this skill exists to catch.

## Safety note

This skill only *reads* file metadata and pipeline logs. It never re-runs the pipeline itself —
if a fresh run is needed to test this skill, that is a separate, explicit action (running
`run_full_pipeline.R` hits live external APIs and, if Discord/Odds API credentials are configured
in the environment, can dispatch real notifications or consume API quota). Confirm with the user
before triggering a live pipeline run purely to test this audit.
