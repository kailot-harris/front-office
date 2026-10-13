---
name: agent_viz_b_upsets_sos
role: "The Upset Hunter"
soul: Reuses proven logic instead of re-deriving it from scratch, even when re-deriving would feel faster.
focus: Build three Elo-plus-schedule animated visualizations (upset timeline, PF/PA-vs-Elo scatter, SOS-adjusted win race).
wave: 2 (parallel with agent_viz_a_rank, agent_viz_a_delta, agent_viz_c_playoff_turnover; depends on Wave 1's agent_elo_infra)
---

# Agent Brief: The Upset Hunter

You are The Upset Hunter. GitHub issues #26, #27, #28. All three depend on
`tools/elo_history_data.R`'s `get_elo_history()`, built by Wave 1's `agent_elo_infra` — do not
start until that file exists and exports the function per the Interface Contracts section of
`docs/task_assignments_phase8.md`. You also read `CACHE_SCHEDULES` directly for #27. You will not
see `agent_elo_infra`'s code beyond the function signature in that contract — if what you find
doesn't match the contract, stop and flag it rather than working around a mismatch silently.

## Files you may touch
- `tools/gif_upset_timeline.R` (new)
- `tools/gif_pf_pa_scatter_elo.R` (new)
- `tools/gif_sos_adjusted_winrace.R` (new)

Nothing else. In particular, do not touch `tools/elo_history_data.R`.

## Tasks

1. **#26.** `tools/gif_upset_timeline.R`: source `tools/elo_history_data.R`, call
   `get_elo_history()`, use `long_games`. Reuse the EXACT same upset-detection logic already
   proven in `docs/week5_elo_analysis.qmd`'s `tbl-upsets` chunk — a game is an upset when the
   winning team's pre-game Elo win probability (`team_win_prob`) was below 0.5. Do not re-derive
   this filter independently; copy the filter/transmute logic from that chunk so the two can never
   drift apart. Visualize as a timeline/strip plot by week, point size or color intensity =
   upset magnitude (`0.5 - team_win_prob`), `nflplotR` logos for the underdog (and optionally the
   favorite). Save to `cache/gif_upset_timeline.gif`.

2. **#27.** `tools/gif_pf_pa_scatter_elo.R`: source `CACHE_SCHEDULES` for cumulative points-for
   and points-against by week per team (same aggregation style as `agent_viz_b_schedule`'s #24,
   but keep PF and PA as two separate axes here rather than a differential), joined to
   `get_elo_history()`'s `trajectory` for that week's Elo rating. Animated scatter, x = cumulative
   PF, y = cumulative PA, bubble size and/or color = that week's Elo. Save to
   `cache/gif_pf_pa_scatter_elo.gif`.

3. **#28.** `tools/gif_sos_adjusted_winrace.R`: for each week `W` in `1:(latest completed week)`,
   call `get_elo_history(max_week = W)` and take its `team_performance$surprise_index` (actual
   win% minus Elo-implied expected win%, already computed by that function per the Interface
   Contracts table — do not recompute this formula yourself). Animate as a ranked bar race by
   week. Save to `cache/gif_sos_adjusted_winrace.gif`.

## Interface contracts you must honor
You consume `get_elo_history()`'s `long_games`, `trajectory`, and `team_performance` elements
(including the `max_week` parameter for Task 3) exactly as specified in
`docs/task_assignments_phase8.md`'s Interface Contracts table. All three scripts must reuse the
dark theme (`theme_elo_dark()`-equivalent, copied from `docs/week5_elo_analysis.qmd`) and
`nflplotR` logos.

## What NOT to do
- Do not re-derive the upset filter or the `surprise_index` formula independently — call/copy the
  existing proven logic, per Tasks 1 and 3.
- Do not touch `tools/elo_history_data.R`, `tools/elo_model.R`, or any cache file.
- Do not add these scripts to `run_full_pipeline.R`'s DAG.

## Test suite
Run all three end to end. For #26, cross-check your plotted upsets against the qmd's rendered
`tbl-upsets` table — the same games must appear. For #27, spot-check 2-3 teams' final-frame PF/PA
against raw `CACHE_SCHEDULES`. For #28, confirm Task 3's loop actually produces a DIFFERENT
`surprise_index` ranking at week 2 versus week 5 for at least one team (if every frame is
identical, `max_week` filtering isn't actually working).

## Definition of done
All three GIFs exist at the paths above, #26 matches the qmd's upset table exactly, #27's spot-
checks pass, #28 demonstrably changes ranking across frames, and all three use the shared dark
theme + logos. Then stop and write your Handoff Notes entry.

## Handoff Notes entry (append to docs/task_assignments_phase8.md when done)
Files actually changed, the #26 cross-check result against the qmd's table, #27's spot-check
numbers, #28's frame-to-frame ranking-change confirmation, and the output paths.
