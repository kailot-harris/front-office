# Plan: Hyperparameter Optimization for Model Robustness Features

## Context
Following the implementation of the "Ceiling/Floor Adjustment" and "Star Power Delta" in the projection engine, several hyperparameters were introduced as reasonable defaults. To ensure these are not arbitrary and provide genuine predictive benefit, we need a systematic way to optimize them against resolved game data.

## Hardcoded Values to Optimize
The following values were recently introduced in `market_odds_engine.R`:
1.  **Rating Limit (`limit`)**: Currently `15.0`. Defines the threshold where rating dampening begins.
2.  **Dampening Factor (`dampening`)**: Currently `0.5` (50%). The multiplier applied to the portion of the rating exceeding the limit.
3.  **Star Power Weight (`star_weight`)**: Currently `0.2` (20%). The multiplier applied to the difference between the top players' RAPM.

## Proposed Experimental Approach

### 1. Tool Development: `tools/optimize_hyperparams.R`
I will create a new optimization script that performs a multi-dimensional search over the parameter space.

**Search Space:**
- `limit`: `[5.0, 25.0]` (Step: 2.5)
- `dampening`: `[0.1, 0.9]` (Step: 0.1)
- `star_weight`: `[0.0, 0.5]` (Step: 0.05)

**Objective Function:**
The script will minimize the **Mean Absolute Error (MAE)** calculated as:
$\text{MAE} = \text{mean}(|\text{Actual Margin} - \text{Predicted Margin}(\text{limit}, \text{dampening}, \text{star\_weight})|)$

### 2. Optimization Strategy
Since the parameter space is small (approx. $8 \times 8 \times 10 = 640$ combinations), a **Grid Search** is feasible and provides a complete map of the error surface. 

**Process:**
1.  Load `prediction_accuracy_log.rds` and `box_scores_cache.rds`.
2.  Isolate the `predicted_margin_base` (predicted margin minus HCA, Fatigue, and Star Delta).
3.  Iterate through the grid of hyperparameters.
4.  For each combination, calculate the new `predicted_margin` and the resulting MAE.
5.  Identify the combination that yields the lowest MAE.

### 3. Validation and Guardrails
To prevent overfitting to a small sample of resolved games:
- **Stability Check**: Ensure the optimal values aren't isolated "spikes" in the error surface but are part of a broad valley of improvement.
- **Comparison**: Compare the optimized MAE against the current "default" MAE to quantify the actual predictive benefit.

## Critical Files
- `market_odds_engine.R`: To be updated with the optimized constants.
- `tools/optimize_hyperparams.R`: (New) The optimization engine.

## Verification Plan
1.  Run the optimization script and output the "Best Combination" and the "MAE Improvement."
2.  Update the constants in `market_odds_engine.R`.
3.  Run `tools/model_error_analysis.R` to verify that the global MAE has decreased.
