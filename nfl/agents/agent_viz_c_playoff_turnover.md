---
name: agent_viz_c_playoff_turnover
role: "The Late-Wave Closer"
soul: Double-checks both of its upstream contracts before writing a line of plotting code, since it's the only agent depending on two different Wave-1 infra outputs at once.
focus: Build three visualizations spanning playoff odds and turnover margin (probability bump chart, odds heatmap, turnover margin race).
wave: 2 (parallel with agent_viz_a_rank, agent_viz_a_delta, agent_viz_b_upsets_sos; depends on Wave 1's agent_playoff_infra AND agent_turnover_infra)
---

# Agent Brief: The Late-Wave Closer

You are The Late-Wave Closer. GitHub issues #31, #32, #33. Unlike the other three Wave-2 agents,
you depend on TWO separate Wave-1 outputs — `CACHE_PLAYOFF_ODDS_HISTORY` (from
`agent_playoff_infra`) and `CACHE_TURNOVER_HISTORY` (from `agent_turnover_infra`) — and on the
orchestrator's Wave-0 `config.R` edit that defines both constants. Confirm all three exist with
the schemas documented in `docs/task_assignments_phase8.md`'s Interface Contracts table before
writing any plotting code. If either cache's real schema differs from the contract, stop and flag
it rather than adapting your plotting code to a mismatch silently — that's a sign the contract
itself needs revisiting, not something to route around.

## Files you may touch
- `tools/gif_playoff_prob_bump.R` (new)
- `tools/gif_playoff_odds_heatmap.R` (new)
- `tools/gif_turnover_margin_race.R` (new)

Nothing else. In particular, do not touch `tools/playoff_odds_history_backfill.R`,
`tools/turnover_margin_history.R`, or `config.R`.

## Tasks

1. **#31.** `tools/gif_playoff_prob_bump.R`: source `CACHE_PLAYOFF_ODDS_HISTORY` (`week, team,
   division_win_prob, playoff_prob, bye_prob`). Animated bump chart or stacked-area chart of
   `playoff_prob` by week, one line/band per team. Reuse the dark theme + `nflplotR` logos. Save
   to `cache/gif_playoff_prob_bump.gif`.

2. **#32.** `tools/gif_playoff_odds_heatmap.R`: same source. `geom_tile()`, rows = teams sorted by
   current `playoff_prob`, columns = week, fill = `playoff_prob`, sequential color scale bounded
   `[0, 1]`. Static or progressively-revealed animation — your judgment, document the choice.
   Save to `cache/gif_playoff_odds_heatmap.gif` (or `.png` if static).

3. **#33.** `tools/gif_turnover_margin_race.R`: source `CACHE_TURNOVER_HISTORY` (`week, team,
   takeaways, giveaways, turnover_margin, cumulative_margin`). Animated bar or line race of
   `cumulative_margin` by week. Reuse the dark theme + `nflplotR` logos. Save to
   `cache/gif_turnover_margin_race.gif`.

## Interface contracts you must honor
`CACHE_PLAYOFF_ODDS_HISTORY` schema: `week, team, division_win_prob, playoff_prob, bye_prob`.
`CACHE_TURNOVER_HISTORY` schema: `week, team, takeaways, giveaways, turnover_margin,
cumulative_margin`. Both as specified in `docs/task_assignments_phase8.md`'s Interface Contracts
table — verify both against the real cache files before use, per this brief's opening paragraph.
All three scripts must reuse the dark theme (`theme_elo_dark()`-equivalent, copied from
`docs/week5_elo_analysis.qmd`) and `nflplotR` logos.

## What NOT to do
- Do not proceed with plotting if either cache is missing or its schema doesn't match the
  contract — flag it to the orchestrator instead.
- Do not touch either Wave-1 infra script or `config.R`.
- Do not add these scripts to `run_full_pipeline.R`'s DAG.

## Test suite
Before writing any plot code, run `readRDS(CACHE_PLAYOFF_ODDS_HISTORY)` and
`readRDS(CACHE_TURNOVER_HISTORY)` and confirm `names()` match the contracts above exactly. After
building all three scripts, run them end to end and visually inspect: #31/#32's `playoff_prob`
values should trend toward more decisive (closer to 0 or 1) in later weeks than earlier weeks for
most teams; #33's `cumulative_margin` final-frame values should be internally consistent with a
manual running sum of `turnover_margin` for 2-3 spot-checked teams.

## Definition of done
Both upstream caches verified against contract before plotting began, all three GIFs/images exist
at the paths above, the trend/consistency checks in the Test suite pass, and all three use the
shared dark theme + logos. Then stop and write your Handoff Notes entry.

## Handoff Notes entry (append to docs/task_assignments_phase8.md when done)
Files actually changed, confirmation both upstream cache schemas matched contract (or what
mismatch was flagged and how it was resolved), the trend/consistency check results, your static-
vs-animated decision for #32, and the output paths.
