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
| P9-A | 1 | `agent_elo_infra` | `tools/elo_history_data.R`, `docs/week5_elo_analysis.qmd` | #17 | COMPLETED |
| P9-B | 1 | `agent_playoff_infra` | `tools/playoff_odds_history_backfill.R` | #18 | COMPLETED |
| P9-C | 1 | `agent_turnover_infra` | `daily_ingest.R`, `tools/turnover_margin_history.R` | #19 | COMPLETED |
| P9-D | 1 | `agent_viz_b_schedule` | `tools/gif_point_diff_race.R`, `tools/gif_division_standings_race.R` | #24, #25 | COMPLETED |
| P9-E | 1 | `agent_viz_c_epa` | `tools/gif_epa_quadrant_scatter.R`, `tools/gif_epa_net_race.R` | #29, #30 | COMPLETED |
| P9-F | 2 | `agent_viz_a_rank` | `tools/gif_elo_rank_bump.R`, `tools/gif_elo_heatmap.R` | #20, #21 | COMPLETED |
| P9-G | 2 | `agent_viz_a_delta` | `tools/gif_elo_delta_race.R`, `tools/gif_elo_volatility_race.R` | #22, #23 | COMPLETED |
| P9-H | 2 | `agent_viz_b_upsets_sos` | `tools/gif_upset_timeline.R`, `tools/gif_pf_pa_scatter_elo.R`, `tools/gif_sos_adjusted_winrace.R` | #26, #27, #28 | COMPLETED |
| P9-I | 2 | `agent_viz_c_playoff_turnover` | `tools/gif_playoff_prob_bump.R`, `tools/gif_playoff_odds_heatmap.R`, `tools/gif_turnover_margin_race.R` | #31, #32, #33 | COMPLETED |

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

### Wave 0 (orchestrator) — 2026-10-13
`CACHE_PLAYOFF_ODDS_HISTORY` and `CACHE_TURNOVER_HISTORY` added to `config.R` (both narrowly-scoped
documented exceptions, same pattern as `CACHE_PLAYOFF_ODDS`). Committed as `1040491`.

### P9-A (`agent_elo_infra`, issue #17) — 2026-10-13
`get_elo_history(max_week = NULL)` extracted into `tools/elo_history_data.R`, returning
`list(long_games, trajectory, current_ratings, team_performance)` per the Interface Contracts
table, no deviation. `docs/week5_elo_analysis.qmd`'s `compute-elo` chunk rewired to call it; no
other chunk touched. Logic moved verbatim (orchestrator-verified via diff) with one additive
`max_week` filter guard. Orchestrator independently re-ran `get_elo_history(max_week=3)` vs
`max_week=5)` post-merge: trajectory caps at week 4/6, `team_performance$games_played` sums to
96/158 — matches the agent's reported numbers exactly. Agent's own `render-and-inspect-quarto`
pass reported no visual regression (not independently re-rendered by the orchestrator). Merged at
`cd55e09`.

### P9-B (`agent_playoff_infra`, issue #18) — 2026-10-13
`tools/playoff_odds_history_backfill.R` reuses `.seed_conference()`/`build_tiebreak_data()`
unmodified via a new `.simulate_one_season_asof(week_cutoff, ...)` twin of
`playoff_odds_engine.R`'s `.simulate_one_season()`. Measured single-week cost (355.76 sec @ 1000
trials) before running the full backfill; total runtime 880.5 sec (14.67 min) across weeks 1-5 —
well under the impractical threshold, so `N_SEASON_SIMULATIONS` was never reduced. Orchestrator
independently confirmed `cache/playoff_odds_history.rds`: dim 160x5, columns `week, team,
division_win_prob, playoff_prob, bye_prob` (160 = 5 weeks x 32 teams). Note: week-over-week
"decisiveness" sanity check showed only a modest difference (week 1 sd=0.376 vs week 5 sd=0.395)
because `CACHE_TEAM_RATINGS` is a single current snapshot reused for every backfilled week — only
the real-vs-simulated game split changes by week, not the underlying team-strength assessment;
this is a property of the existing ratings/engine design, not a defect in this backfill. Merged at
`5cfbfff`.

### P9-C (`agent_turnover_infra`, issue #19) — 2026-10-13
`.PBP_CACHE_COLUMNS` widened with `interception`/`fumble_lost`; `CACHE_PBP` re-ingested (1,156,874
rows, 25 columns). Live-verified against real re-ingested 2024-season data (quoted in
`tools/turnover_margin_history.R`'s header): both are clean 0/1 indicators; `fumble_lost` confirmed
to mean "possession changed," NOT merely "a fumble occurred" — 378 of 663 real fumble plays (57%)
were self-recovered (`fumble_lost == 0`); using `fumble` instead would have overstated giveaways
~2.3x. `CACHE_TURNOVER_HISTORY` (orchestrator-verified: 158 rows, columns `week, team, takeaways,
giveaways, turnover_margin, cumulative_margin`) committed separately as a generated cache artifact
(`ad2da9b`) since the agent's isolated worktree wrote it directly to the shared main-repo `cache/`
(see Known Issue below). Merged at `d69e7b2`.

### P9-D (`agent_viz_b_schedule`, issues #24/#25) — 2026-10-13
`tools/gif_point_diff_race.R` and `tools/gif_division_standings_race.R` built cleanly, fully
isolated in their own worktree (no shared-cache writes — read `CACHE_SCHEDULES`, wrote only new
files). Both GIFs visually inspected (orchestrator confirmed dark theme + `nflplotR` logos render
correctly) and numerically sanity-checked against `CACHE_SCHEDULES` directly (3 teams each, exact
match). Merged at `b1ce7fd`.

### P9-E (`agent_viz_c_epa`, issues #29/#30) — 2026-10-13
`tools/gif_epa_quadrant_scatter.R` and `tools/gif_epa_net_race.R` built; quadrant reference lines
confirmed computed live per-frame via `mean()`, never hardcoded. Agent caught and self-corrected
its own worktree-isolation leak mid-task (an initial run wrote GIFs to the shared main-repo
`cache/`; agent deleted the stray files and fixed both scripts to write to its own worktree
`cache/` instead) — orchestrator confirmed no stray EPA files exist in the main repo. Short-history
teams: zero `CURRENT_SEASON` rows had `games_in_window < ROLLING_WINDOW_SIZE` (every team already
has 4 trailing games via 2025 carryover), logged rather than assumed. Merged at `f26fb54`.

### Known issue: `config.R`'s hardcoded `PROJECT_DIR` undermines cache-level worktree isolation
Every Wave-1 `tools/*.R` script follows this repo's existing convention of `setwd()`-ing to the
absolute main-repo path before `source("config.R")`. That convention predates this phase and is
correct for normal (non-worktree) invocation, but it means every isolated worktree agent's script
run still reads/writes the *shared main-repo* `cache/` and `logs/` directories, not an
isolated copy — `CACHE_PBP` (P9-C) and `logs/logs.duckdb` were both mutated directly in the main
repo mid-wave. This caused two concrete frictions this wave: (1) P9-A's independent orchestrator
re-verification was blocked for ~15 minutes by a `logs.duckdb` file lock held by P9-B's
concurrently-running simulation; (2) P9-E's agent initially wrote its GIFs to the main repo by
mistake before self-correcting. No actual data corruption occurred this wave because no two
Wave-1 tasks read/wrote the same cache file concurrently, but this is luck, not a guarantee — a
future wave with overlapping cache dependencies could race. Worth a scoped fix (e.g. an opt-in
worktree-relative `PROJECT_DIR` override) before relying on worktree isolation for concurrent
cache-writing tasks again.

### Known issue: Wave 2 worktrees were provisioned from a stale pre-Wave-1 base commit
All 4 Wave 2 dispatches (and one re-dispatch) were given isolated git worktrees branched from an
old commit (the pre-Wave-1 "Scaffold Phase 9..." commit) rather than current main — even though
Wave 1 was already fully merged at dispatch time. `agent_viz_a_rank`'s first attempt correctly
detected the missing `tools/elo_history_data.R` dependency and returned `blocked` rather than
guessing; the orchestrator then `git merge main --no-edit`'d into all remaining live Wave-2
worktrees (including a freshly-created one for the retry, which was *also* stale) to unblock them
mid-flight, and re-dispatched the blocked task as a fresh run. No data was lost, but this cost one
wasted dispatch and several manual merges. Root cause not confirmed (likely a cached worktree base
ref in the dispatch tooling, not a `config.R`/repo issue) — flagged to the tool vendor; future
orchestrators dispatching multiple `isolation: "worktree"` agents after merging commits mid-session
should verify each new worktree's base commit before trusting its view of main.

### Wave 2 (`agent_viz_a_rank` / P9-F, issues #20/#21) — 2026-10-13
`tools/gif_elo_rank_bump.R` (division-colored rank-bump line race, `rank(-elo)` per week) and
`tools/gif_elo_heatmap.R` (static `geom_tile()` heatmap, diverging scale centered on
`ELO_INITIAL_RATING`) built on a second dispatch after the stale-worktree blocker above. Final-
frame rank order orchestrator-verified to exactly match `current_ratings` sorted by `current_elo`
descending (32/32 teams); 3 spot-checked heatmap cells matched `trajectory`'s raw Elo exactly.
Static PNG chosen for the heatmap (documented rationale: a heatmap shows the full team x week grid
at once, progressive reveal would only hide information). Merged at `a991a44`.

### Wave 2 (`agent_viz_a_delta` / P9-G, issues #22/#23) — 2026-10-13
`tools/gif_elo_delta_race.R` (single-step `delta = elo - lag(elo)` bar race, signed color) and
`tools/gif_elo_volatility_race.R` (expanding-window `sd()` of that delta, genuine `NA` — not
0 — for teams with <2 observations) built cleanly, fully isolated. 3 delta spot-checks exact;
volatility confirmed to appear only from each team's first 2-observation week and to rise for a
team (ATL) with an early blowout-magnitude swing. Merged at `757bac6`.

### Wave 2 (`agent_viz_b_upsets_sos` / P9-H, issues #26/#27/#28) — 2026-10-13
`tools/gif_upset_timeline.R` reused the qmd's `tbl-upsets` filter verbatim — orchestrator-verified
its top row against the rendered qmd's table, exact match (29 total upsets through week 5).
`tools/gif_pf_pa_scatter_elo.R`'s 3-team PF/PA spot-check against raw `CACHE_SCHEDULES` matched
exactly. `tools/gif_sos_adjusted_winrace.R` calls `get_elo_history(max_week = W)` once per week;
30 of 32 teams' `surprise_index` rank changed between week 2 and week 5, confirming `max_week`
filtering genuinely drives different output per frame. Merged at `2c609a9`.

### Wave 2 (`agent_viz_c_playoff_turnover` / P9-I, issues #31/#32/#33) — 2026-10-13
Both upstream cache schemas verified live before any plotting code was written (exact match to
contract). `tools/gif_playoff_prob_bump.R`: decisiveness (mean |playoff_prob - 0.5|) rose from
0.354 (week 1) to 0.374 (week 5). `tools/gif_playoff_odds_heatmap.R`: static PNG (only 5 weeks of
history; a heatmap has no trajectory element that benefits from progressive reveal), row order
orchestrator-verified to match a direct descending sort of week-5 `playoff_prob`.
`tools/gif_turnover_margin_race.R`: 3-team final-frame spot-check against a manual running sum of
`turnover_margin` matched exactly. Agent left an out-of-scope temp schema-check helper
(`tools/_verify_schemas.R`); orchestrator deleted it before committing. Merged at `b4786c6`.

---
