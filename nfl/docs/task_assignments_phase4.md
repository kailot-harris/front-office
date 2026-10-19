# Task Assignments: Phase 5 (NFL Risk Management Engine)
Date: 2026-09-16

**Naming note:** fifth entry in this repo's `task_assignments_phaseN.md` file-numbering series.
DAG-wise this is the `risk` half of the `risk/notify` node — the `notify` half (`notify_bets.R`)
is blocked on a human-provisioned `DISCORD_WEBHOOK` and is deferred. The `market/props` node
(`market_odds_engine.R`, `player_props_engine.R`) is blocked on a human-provisioned
`ODDS_API_KEY` and is also deferred — per user decision, this wave proceeds on risk management
alone, ahead of those blocked stages, using an honestly-labeled synthetic fallback.

## Overview
WNBA's `risk_management_engine.R` (bankroll drawdown monitor / dynamic Kelly-multiplier stop-loss)
is **entirely sport-agnostic** — it operates on bankroll units, not points or any sport-specific
stat, and its own header states it was "ported AS-IS" from the NBA original with no logic changes.
Port it the same way here: no NFL-specific math changes, just path/header updates.

**Known limitation, must stay explicit, not hidden**: this repo has no real betting ledger yet
(no `market_odds_engine.R`, no `bet_tracker.r`/ledger-writer exist — both are blocked on the Odds
API key). WNBA's engine already has a documented cold-start behavior for exactly this case: fall
back to a clearly-labeled `SYNTHETIC_FALLBACK` seed ledger (120 simulated bets) rather than
erroring, log a WARN when it does so, and tag the risk report's ledger source so a caller can tell
real from synthetic at a glance. Port that fallback behavior — do not silently present synthetic
numbers as if they were real risk state, and do not skip building this engine just because there's
no real ledger yet (it needs to exist and work correctly *before* a real ledger arrives, so that
`market_odds_engine.R`'s eventual bet ledger has something real to plug into on day one).

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P5-A | 1 | `nfl_risk_agent` | `risk_management_engine.R` | Sport-agnostic bankroll/drawdown/Kelly math, honest synthetic-fallback labeling | PENDING |
| P5-B | 2 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire the new stage into the existing 7-stage DAG | PENDING |

## File-ownership disjointness check
`risk_management_engine.R` does not currently exist (verified via `Glob`). `run_full_pipeline.R`
exists and is owned exclusively by P5-B, which runs after P5-A lands.

## Interface contract

| Script | Exposed function | Contract | Reads | Writes |
| :--- | :--- | :--- | :--- | :--- |
| `risk_management_engine.R` | `run_risk_management()` | No required args; looks for a real betting ledger at a `CACHE_BETTING_LEDGER`-style path (does not exist yet in this repo — the lookup should simply not find it and fall through cleanly, exactly like WNBA's cold-start path); on fallback, uses the same clearly-labeled `SYNTHETIC_FALLBACK` seed-ledger approach as WNBA (log a WARN, tag `data_source` in the output); computes bankroll path, drawdown units/pct, dynamic Kelly-tier multiplier (same 0.25/0.175/0.10/0.00 thresholds — sport-agnostic, do not "recalibrate" for NFL without real data to justify it), rolling 7d/30d CLV, beat-CLV rate; returns `TRUE`/`FALSE` | none required (real ledger path checked but expected absent) | new constant `CACHE_RISK_STATE` (add to `config.R` as the same narrow documented exception pattern used in prior waves) |

## Constraints
- Do not invent NFL-specific risk-tier thresholds or loosen/tighten the Kelly-scaling tiers to
  "compensate" for anything — this is intentionally sport-agnostic bankroll discipline, per WNBA's
  own explicit instruction not to do this for WNBA's thinner markets either.
- The synthetic-fallback ledger must be unambiguously labeled as synthetic in both the log output
  and the returned/cached object (a `data_source` or equivalent field) — this is the single most
  important requirement of this task. A future reader must never mistake this for real P&L.
- No `sys.nframe()`/`!interactive()` auto-run guard — this repo's established convention (all 7
  existing stages) is `call_fn`-style explicit invocation.
- This wave does not build `market_odds_engine.R`, `player_props_engine.R`, `bet_tracker.r`, or
  `notify_bets.R` — those remain blocked/deferred per the Overview above.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
