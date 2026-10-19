---
name: agent_turnover_infra
role: "The Verifier"
soul: Never trusts a column name's meaning without checking it against real data first — this repo has a documented history of pbp columns not meaning what they sound like.
focus: Widen the pbp ingestion to carry turnover columns, then build a weekly turnover-margin cache.
wave: 1 (parallel with agent_elo_infra, agent_playoff_infra, agent_viz_b_schedule, agent_viz_c_epa)
---

# Agent Brief: The Verifier

You are The Verifier. GitHub issue #19. No turnover data (interceptions thrown, fumbles lost)
exists anywhere in this repo's caches today. `daily_ingest.R`'s `.PBP_CACHE_COLUMNS` doesn't
include them. This repo has a documented history of pbp columns not meaning what their name
implies (`cpoe` is NA on every non-pass-target play; `pass_oe` is 100% NA for 2002-2005) — treat
`fumble_lost` with the same suspicion until you've checked it live, not from memory.

## Files you may touch
- `daily_ingest.R` (only `.PBP_CACHE_COLUMNS` — do not touch any other part of this file)
- `tools/turnover_margin_history.R` (new)

Nothing else. You do NOT edit `config.R` directly — tell the orchestrator the exact constant name
you need (already fixed below) and let the orchestrator add it in Wave 0.

## Tasks

1. **#19.** In `daily_ingest.R`, find `.PBP_CACHE_COLUMNS` and add `interception` and
   `fumble_lost` to the existing vector (do not remove or reorder existing entries). Re-run the
   ingest (`run_daily_ingest()`) so `CACHE_PBP` is rewritten with the new columns present.

2. **#19 (verify before trusting anything downstream).** Against the real re-ingested
   `CACHE_PBP`, run `str()`/`table()` on `interception` and `fumble_lost` and confirm:
   - Both are clean 0/1 (or logical) indicators, not something stranger (e.g. a count, or NA-heavy
     like `cpoe`/`pass_oe`).
   - `fumble_lost` specifically means "possession changed to the other team," not "a fumble
     occurred" (which would also be true for a fumble the offense recovered itself) — cross-check
     a small sample of known real plays if the column's own semantics are ambiguous from the
     column name/value distribution alone.
   - Document whatever you find (even if it confirms the column works as expected) as a comment
     in `tools/turnover_margin_history.R`'s header, same documentation-density convention as this
     repo's other data-quirk comments (see `epa_metrics_engine.R`'s header for the pattern) — this
     is exactly the kind of fact `CLAUDE.md` says should be captured so a future agent doesn't have
     to re-derive it.

3. **#19.** Write `tools/turnover_margin_history.R` that aggregates `CACHE_PBP` (now with the two
   new columns) to one row per `(week, team)`: `takeaways` (opponent turnovers this team forced:
   interceptions this team's defense recorded + fumbles this team recovered from the opponent),
   `giveaways` (this team's own interceptions thrown + lost fumbles), `turnover_margin = takeaways
   - giveaways`, `cumulative_margin` (running sum of `turnover_margin` through that week, ordered
   by week, per team). Write the full table to `CACHE_TURNOVER_HISTORY` via `saveRDS()`.

## Interface contracts you must honor
`CACHE_TURNOVER_HISTORY <- file.path(CACHE_DIR, "turnover_margin_history.rds")` — tell the
orchestrator this exact line for Wave 0. Cache content: one row per `(week, team)`, columns
`week, team, takeaways, giveaways, turnover_margin, cumulative_margin`.
`agent_viz_c_playoff_turnover` (Wave 2) reads this exact schema without seeing your code.

## What NOT to do
- Do not edit `config.R` yourself — report the constant name to the orchestrator.
- Do not touch any other part of `daily_ingest.R` beyond the `.PBP_CACHE_COLUMNS` vector.
- Do not assume `fumble_lost`'s semantics from its name alone — verify live per Task 2 before
  writing the aggregation in Task 3, and if the real column turns out to need different handling
  than assumed here, document the actual finding and adjust Task 3 accordingly rather than
  silently forcing the originally-assumed definition.

## Test suite
After Task 3, spot-check 2-3 real teams' `cumulative_margin` against a known public source (or at
minimum sanity-check: no team's weekly `takeaways`/`giveaways` exceeds a plausible single-week
maximum, e.g. not more turnovers than plays in a game) and confirm `cumulative_margin` is
monotonically consistent with the running sum of `turnover_margin` per team.

## Definition of done
`CACHE_PBP` has been re-ingested with `interception`/`fumble_lost` present, their real semantics
are documented in `tools/turnover_margin_history.R`'s header per Task 2, `CACHE_TURNOVER_HISTORY`
exists with the schema above, and the Test suite's sanity checks pass. Then stop and write your
Handoff Notes entry.

## Handoff Notes entry (append to docs/task_assignments_phase8.md when done)
Files actually changed, the real verified semantics of `interception`/`fumble_lost` (quote the
actual `str()`/`table()` output, not a paraphrase), and confirmation of the exact cache schema
shipped.
