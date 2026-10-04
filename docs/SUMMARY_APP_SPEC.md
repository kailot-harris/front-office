# Spec: `summary_app.R` — WNBA Model Summary App (v1)

Produced via a spec interview on 2026-10-04, prior to any implementation. Not yet built.

## Architecture

Pure static-snapshot Shiny app. Reads only pre-computed `.rds`/`.csv` cache files at
startup — no live model fitting, no `wehoop`/`tidymodels` runtime dependency, instant
startup. Live recomputation (e.g. retraining the model-comparison benchmark on launch) is
an explicit future enhancement, not in this version.

## Framework

Lightweight `bslib`/`fluidPage` (e.g. `navset_tab`), not `shinydashboard`. Visually
distinct from the betting-terminal `app.R`. UI/visual polish beyond basic theming is
flagged as a near-term follow-up, not part of this spec.

## File placement

New standalone file at repo root, `summary_app.R`, per the flat-layout convention in
CLAUDE.md. Fully separate from `app.R` — no shared code path, no shared tabs.

## New supporting script

`tools/build_model_benchmark_cache.R` — one-off utility (not added to
`run_full_pipeline.R`'s DAG, matching existing `tools/` convention: `setwd()`s to the
project root and sources `config.R`/siblings by bare filename). Reuses
`WNBA_Analysis_Project.Rmd`'s existing `build_feature_df()` / `build_wnba_recipe()` /
`eval_model()`-style logic (not reimplemented) to fit Logistic Regression, Random Forest,
and XGBoost on seasons `< CURRENT_SEASON`, evaluate out-of-sample on
`season >= CURRENT_SEASON`, and write `data/model_benchmark_results.csv` with columns
Model, Accuracy, ROC-AUC, Brier Score, Log-Loss.

## Tabs

### 1. Season Standings & Projections
- Table: `cache/projected_wnba_standings.rds` as-is (Rank, Team, Net_Rating, Proj_Wins,
  Proj_Losses, Win_Pct, Top_Core_Players).
- Chart: horizontal bar chart of `Proj_Wins` by team.

### 2. Playoff Bracket
- ggplot2-rendered bracket graphic (rectangles/labels per slot, `geom_segment` connectors
  between rounds) — not an HTML/CSS layout; that is a later enhancement.
- First Round + Semifinals: real matchups, win probabilities, fair moneylines from
  `cache/playoff_series_wnba_demo.rds`; series-length stats from
  `cache/series_length_predictions.rds`.
- Finals: rendered as **TBD/pending** — no matchup shown, displays
  `series_length_predictions.rds`'s `finals_note` text ("Finals matchup undetermined
  pending both semifinal series — not simulated."). The Finals matchup present in
  `playoff_series_wnba_demo.rds` is deliberately not shown: that cache disagrees with
  `series_length_predictions.rds` on whether the Finals matchup is determined yet, and
  `series_length_predictions.rds`'s "pending" stance was chosen as the source of truth
  for this tab.

### 3. Model Calibration & Reliability
- Ported essentially verbatim from `app.R` (UI ~lines 277-292, server ~lines 1123-1200):
  reads `cache/model_calibration_input.rds` (1,902 real games, 2019-2026), same Brier/BSS/
  Log-loss value boxes and calibration curve plot.

### 4. Model Comparison
- Table: Logistic Regression vs. Random Forest vs. XGBoost (Accuracy/ROC-AUC/Brier/
  Log-Loss) from the new `data/model_benchmark_results.csv`.
- Chart: rolling-window-size sweep (ROC-AUC vs. window size 3-25, 95% bootstrap CI
  ribbon) read directly from the already-cached `data/window_sweep_3_25_results.csv` — no
  new computation needed for this chart.

### 5. Prediction Accuracy Tracker
- Filtered strictly to `cache/prediction_accuracy_log.rds` rows where
  `is_synthetic == FALSE` and `status == "RESOLVED"` (39 real games as of the last cache
  refresh, as of 2026-10-04). Synthetic `DIAG_*` rows, pending rows, and unresolvable rows
  are excluded entirely — no toggle, no synthetic data surfaced anywhere in this tab.
- Value boxes: overall accuracy %, Brier score, log-loss.
- Table: game_date, home_team, away_team, predicted_winner, actual_winner, correct.
- Chart: cumulative accuracy over time (running win-rate as games resolve chronologically
  by `game_date`). Chosen over a predicted-probability-vs-outcome scatter, since that would
  duplicate the Calibration tab's existing reliability plot on a much smaller sample.

## Explicitly deferred (not in this version)
- Live recomputation of any tab.
- HTML/CSS bracket graphic (ggplot2 version ships first).
- General UI/visual polish beyond basic `bslib` theming.
- Displaying a Finals matchup before both semifinal series actually resolve.

## Data sources referenced (as inspected during spec interview)

| Cache / data file | Shape | Used by |
|---|---|---|
| `cache/projected_wnba_standings.rds` | 15 x 7 (Rank, Team, Net_Rating, Proj_Wins, Proj_Losses, Win_Pct, Top_Core_Players) | Tab 1 |
| `cache/playoff_series_wnba_demo.rds` | list of 3 (first_round, semifinals, finals), each with format/high_seed/low_seed/p_high_seed_win/fair_ml/avg_series_games/exact_outcomes | Tab 2 |
| `cache/series_length_predictions.rds` | list of 6, incl. `finals: NULL` and `finals_note` | Tab 2 |
| `cache/model_calibration_input.rds` | 1,902 x 7 (game_id, season, game_date, home_team, away_team, .pred_Win, target_home_win) | Tab 3 |
| `data/model_benchmark_results.csv` (new, to be produced by `tools/build_model_benchmark_cache.R`) | Model, Accuracy, ROC-AUC, Brier Score, Log-Loss | Tab 4 |
| `data/window_sweep_3_25_results.csv` (existing) | Window_Size, N_Train, N_Test, Accuracy, ROC-AUC, Brier Score, ROC_AUC_CI_Lower/Upper | Tab 4 |
| `cache/prediction_accuracy_log.rds` | 145 x 28; 39 real resolved, 100 synthetic `DIAG_*`, 6 unresolvable, 3 pending | Tab 5 |

## Tickets

Each ticket is a vertical slice: skeleton wiring (if not already present) + data load +
UI + chart/table for exactly one tab, end to end and independently demoable. Max one tab
per ticket. Tickets 2-5 depend on Ticket 1 only for the shared `summary_app.R` skeleton
(nav shell, `bslib` theme, cache-loading boilerplate) — not on each other — so they can be
built in any order once Ticket 1 lands.

| Ticket | Title | Tab | Depends on | Status |
| :--- | :--- | :--- | :--- | :--- |
| SA-1 | App skeleton + Tab 1: Season Standings & Projections | 1 | — | TODO |
| SA-2 | Tab 2: Playoff Bracket (ggplot2) | 2 | SA-1 (skeleton) | TODO |
| SA-3 | Tab 3: Model Calibration & Reliability | 3 | SA-1 (skeleton) | TODO |
| SA-4 | Tab 4: Model Comparison + benchmark cache builder | 4 | SA-1 (skeleton) | TODO |
| SA-5 | Tab 5: Prediction Accuracy Tracker | 5 | SA-1 (skeleton) | TODO |

### SA-1 — App skeleton + Tab 1: Season Standings & Projections
**Builds:** `summary_app.R` at repo root (flat layout, per CLAUDE.md) with `bslib`/
`fluidPage` + `navset_tab` shell, no `shinydashboard`, visually distinct from `app.R`, no
shared code path/tabs with `app.R`. Establishes the cache-loading pattern (startup-only
reads, fail-safe `file.exists()` checks per CLAUDE.md's fail-safe convention) that later
tickets reuse.
**Tab content:** reads `cache/projected_wnba_standings.rds` as-is and renders it as a table
(Rank, Team, Net_Rating, Proj_Wins, Proj_Losses, Win_Pct, Top_Core_Players), plus a
horizontal bar chart of `Proj_Wins` by team.
**Done when:** `Rscript.exe summary_app.R` launches and Tab 1 renders real data with no
console errors (verify via `tools/headless_dashboard_probe.R` pattern or manual browser
check).

### SA-2 — Tab 2: Playoff Bracket
**Builds:** ggplot2-rendered bracket (rectangles/labels per slot, `geom_segment`
connectors between rounds — not HTML/CSS). First Round + Semifinals show real matchups,
win probabilities, and fair moneylines from `cache/playoff_series_wnba_demo.rds`, plus
series-length stats from `cache/series_length_predictions.rds`. Finals renders as
TBD/pending only, using `series_length_predictions.rds`'s `finals_note` text — the Finals
matchup present in `playoff_series_wnba_demo.rds` is deliberately never displayed on this
tab (that cache disagrees with `series_length_predictions.rds` on whether Finals is
determined; the latter is source of truth here).
**Done when:** bracket renders First Round + Semifinals with real probabilities/
moneylines, and Finals shows only the pending note — never a Finals matchup.

### SA-3 — Tab 3: Model Calibration & Reliability
**Builds:** ported essentially verbatim from `app.R` (UI ~lines 277-292, server
~lines 1123-1200) into `summary_app.R`'s own tab — reads `cache/model_calibration_input.rds`
(1,902 real games, 2019-2026) and reproduces the same Brier/BSS/Log-loss value boxes and
calibration curve plot. No shared code path with `app.R`; copy/adapt the logic rather than
sourcing `app.R`.
**Done when:** value boxes and calibration curve render with the same numbers as `app.R`'s
existing tab, computed independently from the same cache.

### SA-4 — Tab 4: Model Comparison + benchmark cache builder
**Builds:** `tools/build_model_benchmark_cache.R` (one-off, not in `run_full_pipeline.R`'s
DAG, matching `tools/` convention: `setwd()` to project root, source siblings by bare
filename). Reuses `WNBA_Analysis_Project.Rmd`'s existing `build_feature_df()` /
`build_wnba_recipe()` / `eval_model()`-style logic — not reimplemented — to fit Logistic
Regression, Random Forest, and XGBoost on seasons `< CURRENT_SEASON` (from `config.R`),
evaluate out-of-sample on `season >= CURRENT_SEASON`, and write
`data/model_benchmark_results.csv` (Model, Accuracy, ROC-AUC, Brier Score, Log-Loss).
**Tab content:** table of the three models' metrics from that CSV, plus a rolling-window-
size sweep chart (ROC-AUC vs. window size 3-25, 95% bootstrap CI ribbon) read directly from
the already-cached `data/window_sweep_3_25_results.csv` — no new computation for the chart.
**Done when:** running `tools/build_model_benchmark_cache.R` produces
`data/model_benchmark_results.csv`, and Tab 4 renders both the table and the sweep chart
from the two CSVs.

### SA-5 — Tab 5: Prediction Accuracy Tracker
**Builds:** reads `cache/prediction_accuracy_log.rds` filtered strictly to
`is_synthetic == FALSE & status == "RESOLVED"` (39 real games as of the last cache refresh)
— synthetic `DIAG_*`, pending, and unresolvable rows excluded entirely, no toggle, no
synthetic data surfaced anywhere on this tab.
**Tab content:** value boxes (overall accuracy %, Brier score, log-loss); table
(game_date, home_team, away_team, predicted_winner, actual_winner, correct); cumulative-
accuracy-over-time chart (running win-rate as games resolve chronologically by
`game_date`) — chosen instead of a probability-vs-outcome scatter to avoid duplicating
Tab 3's reliability plot on a much smaller sample.
**Done when:** value boxes, table, and chart all reflect only the 39 real resolved rows,
with zero synthetic rows reachable in the UI.

## Status

Spec only. Not yet implemented. Tickets SA-1 through SA-5 above are ready to be picked up
in any order once SA-1's skeleton lands.
