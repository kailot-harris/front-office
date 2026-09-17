# Task Assignments: Phase 7 (NFL Discord Alert Dispatcher)
Date: 2026-09-16

**Naming note:** seventh entry in this repo's `task_assignments_phaseN.md` file-numbering series.
DAG-wise this is the `notify` half of the `risk/notify` node (the `risk` half,
`risk_management_engine.R`, shipped in Phase 5).

## Overview
Ports WNBA's `notify_bets.R` — entirely sport-agnostic Discord embed formatting/dispatch logic,
reading `cache/latest_value_bets.rds` (this repo's `market_odds_engine.R`, Phase 6, already
produces this cache with real live-odds rows) and posting a formatted alert. The only real
adaptation needed is the webhook env var name and wrapping the top-level auto-run script into this
repo's `call_fn`-style exposed-function convention (WNBA's version has no function wrapper at all —
it is a bare top-level script that runs fully on `source()`, which does not fit this repo's
established `run_stage(call_fn = ...)` pattern used by all 9 existing stages).

**Known environment gap, must stay explicit, not hidden**: the user has provisioned a real
`NFL_DISCORD_WEBHOOK` value in a `.Renviron` file, but it is **not currently visible to R
processes in this repo's environment** (a `.Renviron` user-home-vs-Documents lookup-path
mismatch, unrelated to this task — flagged separately for the user to fix). This means
`Sys.getenv("NFL_DISCORD_WEBHOOK", "")` will return `""` and the dispatch step must cleanly no-op
to a console-only preview, exactly like WNBA's own cold-start behavior when no webhook is set —
this is not an error condition to work around, it is the designed fail-safe path, and this task
should verify it end-to-end today, then be ready to work for real the moment the env var becomes
visible.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P7-A | 1 | `nfl_notify_agent` | `notify_bets.R` | Sport-agnostic Discord dispatch, `NFL_DISCORD_WEBHOOK` no-hardcoded-URL convention, `call_fn`-style wrapper | PENDING |
| P7-B | 2 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire the new stage into the existing 9-stage DAG | PENDING |

## File-ownership disjointness check
`notify_bets.R` does not currently exist (verified via `Glob`). `run_full_pipeline.R` exists and
is owned exclusively by P7-B, which runs after P7-A lands.

## Interface contract

| Script | Exposed function | Contract | Reads | Writes |
| :--- | :--- | :--- | :--- | :--- |
| `notify_bets.R` | `run_notify_bets()` | No required args; loads `CACHE_LATEST_VALUE_BETS`, filters for `EV_Percent >= 3.0 & Exp_CLV >= -0.5` (falling back to top-3 by EV if nothing clears that bar, same as WNBA), formats up to 4 picks into a Discord embed payload, dispatches via `POST` to `Sys.getenv("NFL_DISCORD_WEBHOOK", "")` **only if non-empty** — otherwise prints a clearly-labeled console-only preview and logs a WARN, never errors; returns `TRUE`/`FALSE` | `CACHE_LATEST_VALUE_BETS` | none (this stage has no cache output of its own — it is a terminal notification step, matching WNBA's `notify_bets.R`, which also declares no `output` in its `run_stage()` call) |

## Constraints
- **No hardcoded webhook URL anywhere, live or dummy placeholder** — per WNBA's own explicit
  convention (its header comment calls this out by name). `Sys.getenv("NFL_DISCORD_WEBHOOK", "")`
  only.
- Secret handling: if the webhook URL is set, never log it in full (redact per this repo's
  existing `logging_utils.R` `.log_redact()` webhook-path pattern, which already scrubs Discord
  webhook URLs — verify this fires correctly rather than assuming).
- Do not loosen the EV/CLV actionable-bet threshold — port verbatim.
- No `sys.nframe()`/`!interactive()` auto-run guard — wrap WNBA's top-level script body into a
  `run_notify_bets()` function per this repo's established `call_fn`-style convention (all 9
  existing stages use this).
- Must not error when `NFL_DISCORD_WEBHOOK` is unset — this is the expected current state and
  must be verified as a clean no-op, not patched around.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
