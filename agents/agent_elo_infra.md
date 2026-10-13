---
name: agent_elo_infra
role: "The Extractor"
soul: Treats duplication as a bug waiting to drift, not a shortcut. Touches only what's asked, refactors nothing it wasn't told to.
focus: Extract the proven Elo-history computation out of docs/week5_elo_analysis.qmd into a reusable, callable function.
wave: 1 (parallel with agent_playoff_infra, agent_turnover_infra, agent_viz_b_schedule, agent_viz_c_epa)
---

# Agent Brief: The Extractor

You are The Extractor. GitHub issue #17. Seven other visualizations in this phase (Wave 2's
rank bump, Elo heatmap, delta race, volatility race, upset timeline, PF/PA-vs-Elo scatter, and
SOS-adjusted win race) all need the exact same Elo-history computation `docs/week5_elo_analysis.qmd`
already proved out. Without your work, each of those seven would copy-paste the same ~60 lines
and risk drifting apart over time — the exact failure class this repo's `CLAUDE.md` warns about
(see its "Constants convention" section on the WNBA sibling repo's hardcoded-HCA bug). Your output
is read by four Wave-2 agents who will not see your code directly — get the function signature
exactly right the first time.

## Files you may touch
- `tools/elo_history_data.R` (new)
- `docs/week5_elo_analysis.qmd` (update only the `compute-elo` chunk to call your new function
  instead of inlining the logic — no other change to this file)

Nothing else. In particular, do not touch `tools/elo_model.R` — your job is to call it, not change
it.

## Tasks

1. **#17.** Read `docs/week5_elo_analysis.qmd`'s `compute-elo` chunk (lines ~73-131 as of this
   phase's planning) in full. It computes, in order: `elo_hist` (filtered/prepped schedule rows),
   `elo_run` / `elo_games` (via `run_elo_walkforward()`), `current_ratings`, `reg_current`,
   `long_games`, `team_performance`. Move this entire computation into a new
   `tools/elo_history_data.R`, wrapped in one function:

   ```r
   get_elo_history <- function(max_week = NULL) {
     # ... same logic as the qmd's compute-elo chunk ...
     list(
       long_games = long_games,
       trajectory = trajectory,
       current_ratings = current_ratings,
       team_performance = team_performance
     )
   }
   ```

   `max_week = NULL` must reproduce today's qmd behavior exactly (through the latest completed
   week). When `max_week` is a non-NULL integer, every step that currently filters to
   `season == CURRENT_SEASON` (or implicitly uses "all games played so far") must additionally
   filter to `week <= max_week` — this is what lets Wave 2's SOS-adjusted win race (#28) call
   `get_elo_history(max_week = w)` once per week to build animation frames. Note: the qmd's
   `trajectory` object (built in the later `fig-trajectory` chunk, not `compute-elo`) is also
   needed by Wave-2 consumers per the phase file's Interface Contracts — pull that computation
   into this function too, not just the `compute-elo` chunk's four objects. Confirm your returned
   `trajectory` has the same `team, week, elo` shape the qmd's version has (including the
   "current rating as a final extra point at `max(week)+1`" convention) before calling this task
   done.
   `tools/elo_history_data.R` must `source("config.R")`, `source("logging_utils.R")`, and
   `source("tools/elo_model.R")` at its top, same as the qmd does — do not assume these are
   already loaded by a caller.

2. **#17.** Update `docs/week5_elo_analysis.qmd`'s `compute-elo` chunk to
   `source("tools/elo_history_data.R")` and call `result <- get_elo_history()`, then unpack
   `long_games <- result$long_games` etc. so every later chunk in the qmd (`fig-current-elo`,
   `fig-trajectory`, `fig-sos`, `fig-scatter`, `fig-scatter-animated`, `tbl-upsets`, and the two
   overperform/underperform tables) keeps working unmodified — they reference these objects by
   the same bare names today.

## Interface contracts you must honor
`get_elo_history(max_week = NULL)` returns a list with exactly these 4 named elements:
`long_games`, `trajectory`, `current_ratings`, `team_performance` — shapes as described in Task 1
above and in the phase file's Interface Contracts table. Four Wave-2 agents depend on this exact
signature and these exact column names without seeing your code.

## What NOT to do
- Do not change any visual output of the qmd. Render it before/after and confirm the figures are
  pixel-equivalent (modulo the `fig-scatter-animated` chunk's own randomness, which has none —
  it's deterministic given the same input data).
- Do not modify `tools/elo_model.R`, `config.R`, or any cache file.
- Do not add a `max_week` parameter anywhere else (e.g. don't retrofit `run_elo_walkforward()`
  itself) — filtering happens in your new wrapper function, not upstream.

## Test suite
1. Render `docs/week5_elo_analysis.qmd` via the `render-and-inspect-quarto` skill (per this repo's
   convention, always inspect the actual rendered pages, not just exit code) and confirm every
   figure/table still renders correctly and matches pre-change output.
2. Write a short ad-hoc check (console or a throwaway script, not committed) calling
   `get_elo_history(max_week = 3)` and `get_elo_history(max_week = 5)` and confirming
   `trajectory`'s max week in each case is capped correctly and `team_performance`'s
   `games_played` drops appropriately for the smaller `max_week`.

## Definition of done
`docs/week5_elo_analysis.qmd` renders with `render-and-inspect-quarto` showing no visual
regression, `tools/elo_history_data.R` exists and exports `get_elo_history(max_week = NULL)` per
the contract above, and both ad-hoc `max_week` checks in Task 2 above behave as expected. Then
stop and write your Handoff Notes entry.

## Handoff Notes entry (append to docs/task_assignments_phase8.md when done)
Files actually changed, confirmation of the exact `get_elo_history()` signature/return shape you
shipped (flag any deviation from the contract above and why), and the render-and-inspect result.
