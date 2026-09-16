# Model Error Analysis & Projection Refinement Report

## Overview
This document outlines the diagnostics, optimizations, and architectural changes made to the WNBA probabilistic margin model to reduce projection error and improve explainability.

## 1. Initial Error Diagnostics
Using `tools/model_error_analysis.R`, we identified several systemic failure patterns:
- **High Mean Absolute Error (MAE)**: Initial MAE was $\sim 20.6$ points, with extreme residuals in blowouts.
- **Strong Home Bias**: A mean bias of $+6.22$ indicated the model significantly under-predicted home team performance.
- **Component Decoupling**: Residuals had low correlation with Net Rating and Fatigue components, suggesting the model was missing critical latent variables.

## 2. Home Court Advantage (HCA) Optimization
We replaced the hardcoded HCA (2.4) with an empirically optimized value using the L-BFGS-B algorithm to minimize MAE over resolved games.

- **Method**: Varied HCA within a bound of $[2.0, 50.0]$.
- **Result**: Optimal HCA found at **11.615**.
- **Impact**: 
  - MAE reduced from $20.62 \rightarrow 18.00$.
  - Mean Bias reduced from $+6.22 \rightarrow -2.99$.

## 3. Model Robustness Improvements
To prevent "runaway" projections and account for individual star impact, two new mechanisms were added to `market_odds_engine.R`:

### A. Ceiling/Floor Adjustment (`apply_rating_limits`)
- **Rationale**: Extreme Net Ratings can lead to unrealistic projections.
- **Logic**: Ratings beyond $\pm 15.0$ are dampened by 50% for the portion exceeding the limit.
- **Effect**: Smooths out projections for the league's most dominant and struggling teams.

### B. Star Power Delta (`calculate_matchup_delta`)
- **Rationale**: Team-level ratings often mask the impact of a single dominant player.
- **Logic**: identifies the top player by `total_rapm` for each team and adds $20\%$ of the difference between their ratings to the margin.
- **Effect**: Accounts for individual matchups that can swing a game regardless of team-average efficiency.

## 4. XAI & Tooling Implementation
### A. Random Forest XAI
Integrated `fastshap` into `tools/ml_cv_benchmark.R` to provide SHAP values for out-of-fold predictions. This replaces impurity-based importance with mathematically rigorous feature contributions.

### B. Diagnostics Dashboard
Added a **Model Diagnostics** tab to `app.R` featuring:
- **Global Metrics**: Real-time MAE, RMSE, and Mean Bias.
- **Residual Scatter**: Predicted vs. Actual margin plot.
- **Team Bias Chart**: Identification of teams the model consistently misses.

## Summary of Updated Constants
| Constant | Old Value | New Value | Source |
| :--- | :--- | :--- | :--- |
| **HCA** | 2.4 | **11.6** | `optimize_hca.R` |
| **Rating Limit** | N/A | **$\pm 15.0$** | `market_odds_engine.R` |
| **Star Weight** | N/A | **20%** | `market_odds_engine.R` |
