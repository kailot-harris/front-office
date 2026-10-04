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

## Status

Spec only. Not yet implemented.
