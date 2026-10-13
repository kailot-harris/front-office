# Task Assignments: Phase 9 (Week 1-5 Team-Level Visualization GIFs)
Date: 2026-10-13

**Naming note:** this repo's `task_assignments_phaseN.md` filenames run one behind the title's
"Phase N" number (`phase0.md` is titled "Phase 1", ..., `phase7.md` is titled "Phase 8") — this
file continues that convention: ninth title, eighth-numbered filename.

## Overview
Source: GitHub issues #17-#19 (infra) and #20-#33 (14 visualizations), scoped in a planning
session from a brainstorm of 30 team-level visualization ideas. The user picked three groups
(Elo-based, standings/scores, playoff-odds/EPA/turnovers) and asked for 4+ GIFs; this phase
delivers all 14 plus the 3 infra prerequisites they depend on.

This is a feature-build wave, not a bug remediation — "findings" below are GitHub issue numbers,
not defect IDs. Two of the three infra tasks exist because the data those visualizations need
doesn't exist yet in any cache: `CACHE_PLAYOFF_ODDS` is a point-in-time snapshot with no week
dimension (issue #18), and no turnover (interception/fumble) data is cached anywhere in this repo
at all (issue #19). The third infra task (issue #17) is a pure refactor: extract the Elo-history
computation already proven in `docs/week5_elo_analysis.qmd` into a reusable function so the seven
Elo-dependent visualizations don't each re-derive it and risk drifting out of sync (the exact
failure class `CLAUDE.md`'s constants-single-source-of-truth section warns about).

**Orchestration principle:** 9 agents grouped by disjoint file ownership into 2 waves. Wave 1's
5 agents build infra plus the visualizations that need no new data (`CACHE_SCHEDULES` /
`CACHE_EPA_METRICS` only). Wave 2's 4 agents consume Wave 1's new caches/functions. Waves run in
series; agents within a wave run in parallel.

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Issues Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P9-A | 1 | `agent_elo_infra` | `tools/elo_history_data.R`, `docs/week5_elo_analysis.qmd` | #17 | PENDING |
| P9-B | 1 | `agent_playoff_infra` | `tools/playoff_odds_history_backfill.R` | #18 | PENDING |
| P9-C | 1 | `agent_turnover_infra` | `daily_ingest.R`, `tools/turnover_margin_history.R` | #19 | PENDING |
| P9-D | 1 | `agent_viz_b_schedule` | `tools/gif_point_diff_race.R`, `tools/gif_division_standings_race.R` | #24, #25 | PENDING |
| P9-E | 1 | `agent_viz_c_epa` | `tools/gif_epa_quadrant_scatter.R`, `tools/gif_epa_net_race.R` | #29, #30 | PENDING |
| P9-F | 2 | `agent_viz_a_rank` | `tools/gif_elo_rank_bump.R`, `tools/gif_elo_heatmap.R` | #20, #21 | PENDING |
| P9-G | 2 | `agent_viz_a_delta` | `tools/gif_elo_delta_race.R`, `tools/gif_elo_volatility_race.R` | #22, #23 | PENDING |
| P9-H | 2 | `agent_viz_b_upsets_sos` | `tools/gif_upset_timeline.R`, `tools/gif_pf_pa_scatter_elo.R`, `tools/gif_sos_adjusted_winrace.R` | #26, #27, #28 | PENDING |
| P9-I | 2 | `agent_viz_c_playoff_turnover` | `tools/gif_playoff_prob_bump.R`, `tools/gif_playoff_odds_heatmap.R`, `tools/gif_turnover_margin_race.R` | #31, #32, #33 | PENDING |

## Phase 0 — Orchestrator-Only Setup
`config.R` gets exactly 2 new constants this phase: `CACHE_PLAYOFF_ODDS_HISTORY` and
`CACHE_TURNOVER_HISTORY`. `config.R` is a shared file no two Wave-1 agents may edit in the same
wave (P9-B and P9-C both need a new constant in it). The **orchestrator** appends both lines to
the end of the existing `CACHE_*` block serially, after P9-B and P9-C have each told the
orchestrator their exact constant name/value (both are already fixed below in Interface
Contracts, so in practice this is a single orchestrator edit done once both agents confirm no
change to the agreed names was needed) — neither agent edits `config.R` directly.

## Wave dependency graph
```
Wave 0: orchestrator appends CACHE_PLAYOFF_ODDS_HISTORY + CACHE_TURNOVER_HISTORY to config.R
   |
Wave 1 (parallel, 5 agents, disjoint files):
   agent_elo_infra        (tools/elo_history_data.R, docs/week5_elo_analysis.qmd)
   agent_playoff_infra    (tools/playoff_odds_history_backfill.R)
   agent_turnover_infra   (daily_ingest.R, tools/turnover_margin_history.R)
   agent_viz_b_schedule   (tools/gif_point_diff_race.R, tools/gif_division_standings_race.R)
   agent_viz_c_epa        (tools/gif_epa_quadrant_scatter.R, tools/gif_epa_net_race.R)
   |  agent_elo_infra produces get_elo_history() -> consumed by P9-F, P9-G, P9-H
   |  agent_playoff_infra produces CACHE_PLAYOFF_ODDS_HISTORY -> consumed by P9-I
   |  agent_turnover_infra produces CACHE_TURNOVER_HISTORY -> consumed by P9-I
   v
Wave 2 (parallel, 4 agents, disjoint files):
   agent_viz_a_rank              (tools/gif_elo_rank_bump.R, tools/gif_elo_heatmap.R)
   agent_viz_a_delta             (tools/gif_elo_delta_race.R, tools/gif_elo_volatility_race.R)
   agent_viz_b_upsets_sos        (tools/gif_upset_timeline.R, tools/gif_pf_pa_scatter_elo.R,
                                   tools/gif_sos_adjusted_winrace.R)
   agent_viz_c_playoff_turnover  (tools/gif_playoff_prob_bump.R, tools/gif_playoff_odds_heatmap.R,
                                   tools/gif_turnover_margin_race.R)
```
Wave 1 is safe to run fully in parallel: each agent's file list above is pairwise disjoint from
every other Wave-1 agent's, and none of the 5 Wave-1 tasks reads another Wave-1 task's output
mid-wave (P9-D and P9-E are pure leaf tasks with no phase-internal dependency at all). Wave 2 is
likewise pairwise file-disjoint and safe to parallelize, but every Wave-2 agent reads at least one
Wave-1 artifact, so Wave 2 must not start until Wave 1 is fully merged and Wave 0's `config.R`
edit has landed.

## Interface contracts (finalize before Wave 2 starts)

| Contract | Written by | Read by | Shape |
| :--- | :--- | :--- | :--- |
| `get_elo_history(max_week = NULL)` in `tools/elo_history_data.R` | `agent_elo_infra` (P9-A) | P9-F, P9-G, P9-H | Returns a list with 4 elements matching the shapes already computed inline in `docs/week5_elo_analysis.qmd`'s `compute-elo` chunk: `long_games` (game-level, team-perspective, pre-game Elo for team+opponent), `trajectory` (team/week/elo, pre-game rating per week played + a final current-rating point), `current_ratings` (one row per team: `final_elo`, `last_season`, `current_elo`, `division`, `conference`), `team_performance` (one row per team: `games_played`, `wins`, `win_pct`, `expected_win_pct`, `avg_opponent_elo`, `surprise_index`, `current_elo`, `division`, `conference`). `max_week = NULL` means "through the latest completed week" (today's qmd behavior, unchanged); a non-NULL integer filters to games through that week only — P9-H's SOS-adjusted win race (#28) calls this once per week 1..latest to build its animation frames. |
| `CACHE_PLAYOFF_ODDS_HISTORY` constant + cache file | `agent_playoff_infra` (P9-B) names the constant; **orchestrator** adds the line to `config.R` | P9-I | `CACHE_PLAYOFF_ODDS_HISTORY <- file.path(CACHE_DIR, "playoff_odds_history.rds")`. Cache schema: one row per `(week, team)` — columns `week, team, division_win_prob, playoff_prob, bye_prob` (same fields `playoff_odds_engine.R` already produces per-trial for "now", just snapshotted per historical week). |
| `CACHE_TURNOVER_HISTORY` constant + cache file | `agent_turnover_infra` (P9-C) names the constant; **orchestrator** adds the line to `config.R` | P9-I | `CACHE_TURNOVER_HISTORY <- file.path(CACHE_DIR, "turnover_margin_history.rds")`. Cache schema: one row per `(week, team)` — columns `week, team, takeaways, giveaways, turnover_margin, cumulative_margin`. |
| Shared dark theme + logos | Already exists (`theme_elo_dark()` in `docs/week5_elo_analysis.qmd`) | All 14 viz tasks (P9-D through P9-I) | Every new `tools/gif_*.R` script must reuse this theme (copy the function verbatim into each script, or — agent's judgment — factor it into a small shared snippet if that doesn't create a new cross-wave file-ownership conflict) plus `nflplotR::geom_nfl_logos()` for team identity, for visual consistency with the existing `cache/elo_scatter_animation.gif`. |

## Constraints
- **Issue #18's backfill cost**: re-running the Monte Carlo playoff simulation once per historical
  week (not once total) is roughly `(latest completed week)` times the normal single-snapshot
  cost. `agent_playoff_infra` must confirm `N_SEASON_SIMULATIONS`'s real wall-clock cost for one
  snapshot before running the full backfill unattended, and flag to the orchestrator if the
  multiplied cost is impractical (e.g. consider a reduced simulation count for the
  historical-backfill cache specifically, documented as a deliberate precision/cost tradeoff, not
  silently applied).
- **Issue #19's column semantics**: `agent_turnover_infra` must verify live (via `readRDS`/`str()`
  against the real re-ingested `CACHE_PBP`, not assumed from memory) that `fumble_lost` is a clean
  0/1 "possession changed" indicator and not conflated with fumbles recovered by the fumbling
  team's own offense, before trusting the turnover-margin aggregation — this repo's documented
  pbp quirks (`cpoe` NA handling, `pass_oe` pre-2006 NA) are exactly this class of surprise.
- Every new `config.R` constant follows this repo's existing "Constants note" narrow-exception
  pattern (see `CACHE_EPA_METRICS`/`CACHE_TEAM_RATINGS` comments) — document it inline, do not
  silently add an undocumented line.
- None of the 14 visualization scripts are part of `run_full_pipeline.R`'s DAG — same category as
  `tools/weekly_accuracy_report.R` and `tools/plot_week5_projections.R`, ad-hoc/on-demand scripts,
  not wired into `run_stage()`.
- Run `.claude/skills/config-constant-drift-audit` after Wave 0's two new constants land.

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
