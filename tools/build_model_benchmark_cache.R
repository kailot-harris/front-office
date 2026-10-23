# build_model_benchmark_cache.R
# ------------------------------------------------------------------------------------------
# SA-4 (GitHub issue #58) - one-off cache builder for the summary app's "Model Comparison" tab.
#
# ORPHANED PRODUCER (declared 2026-10-23): its only consumer has retired. The summary app that
# read this script's output now lives in a separate repository
# (`kailot-harris/DATA-607-Agentic_Coding-WNBA-Summary`), and that app's stale fork in THIS
# repo has been deleted. So `data/model_benchmark_results.csv` is currently produced here and
# consumed by nothing in this repo. This is expected, not a bug -- the orphaned-cache-audit
# skill will
# flag the artifact and this note is the answer. The producer is kept deliberately: it is the
# only thing that regenerates the benchmark table, and re-deriving it from
# WNBA_Analysis_Project.Rmd's chunk would be the duplication issue #58 removed.
# NOT added to run_full_pipeline.R's DAG (matches tools/ convention: setwd() to the absolute
# project root, then source() siblings by bare filename, so it runs correctly regardless of
# invocation directory - see CLAUDE.md's "Folder layout" section).
#
# Reuses WNBA_Analysis_Project.Rmd's "Model Benchmarking Architecture" chunk
# (build_feature_df() ~lines 158-314, build_wnba_recipe() ~lines 323-334, eval_model()
# ~lines 605-622, the model-fitting chunk itself ~lines 584-631) rather than reimplementing
# feature engineering from scratch. Because an .Rmd's chunks cannot be source()'d directly
# like a plain .R file, this script copies those three functions essentially verbatim from
# the Rmd - the same "closely adapt, don't reimplement" pattern already established by
# tools/ml_cv_benchmark.R (see its own header comment, lines 6-13 and 74-82, citing the exact
# same Rmd functions and doing the same verbatim-copy move for the identical reason).
#
# Fits Logistic Regression, Random Forest (ranger), and XGBoost (boost_tree) on seasons
# < CURRENT_SEASON (read from config.R, not hardcoded) and evaluates out-of-sample on
# season >= CURRENT_SEASON, writing data/model_benchmark_results.csv with columns
# Model, Accuracy, ROC-AUC, Brier Score, Log-Loss (exactly 3 rows).
#
# Per the brief: this script itself is allowed to error out if model fitting genuinely
# fails (fail-safe is the consuming app tab's job, not this one-off builder's).
#
# Run: "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools\build_model_benchmark_cache.R
# ------------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(slider)
  library(xgboost)
})

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics/.claude/worktrees/agent-a09fc9d4b35b87d2f"
setwd(PROJECT_DIR)
source("config.R")

set.seed(42)  # matches WNBA_Analysis_Project.Rmd's model-benchmarks chunk (line 585)

# ------------------------------------------------------------------------------------------
# 1. Load real data (same cache-first logic as WNBA_Analysis_Project.Rmd's setup/
#    import-box-scores chunks: CACHE_TEAM_BOX if present, else regenerate via wehoop with
#    the CONN->CON normalization and exhibition-row filter applied first).
# ------------------------------------------------------------------------------------------
if (file.exists(CACHE_TEAM_BOX)) {
  box_scores <- readRDS(CACHE_TEAM_BOX)
} else {
  source("player_metrics.R")
  box_scores <- wehoop::load_wnba_team_box(seasons = ALL_SEASONS) |>
    normalize_team_abbreviation() |>
    filter(team_abbreviation %in% names(WNBA_TEAMS))
  saveRDS(box_scores, CACHE_TEAM_BOX)
}

cat(sprintf(
  "[data] box_scores_cache.rds: %d real team-game rows, seasons %s\n",
  nrow(box_scores), paste(range(box_scores$season), collapse = "-")
))

# ------------------------------------------------------------------------------------------
# 2. Feature engineering - copied verbatim from WNBA_Analysis_Project.Rmd
#    (compute_rolling_features() lines 136-156, build_feature_df() lines 158-314,
#    build_wnba_recipe() lines 323-334). method = "reset" is the Rmd's own re-benchmarked
#    winner for the WNBA (see WNBA_Analysis_Project.Rmd's "Contrary to the plan's
#    speculation..." paragraph, ~line 567), which is also what the model-benchmarks chunk
#    itself (~line 586) uses.
# ------------------------------------------------------------------------------------------
compute_rolling_features <- function(df, window_size) {
  df |>
    mutate(
      efg = (field_goals_made + 0.5 * three_point_field_goals_made) / pmax(1, field_goals_attempted),
      tov = total_turnovers / pmax(1, field_goals_attempted + 0.44 * free_throws_attempted + total_turnovers),
      ftr = free_throws_attempted / pmax(1, field_goals_attempted),
      ts  = team_score / pmax(1, 2 * (field_goals_attempted + 0.44 * free_throws_attempted)),

      roll_pts_scored = slide_dbl(team_score, mean, .before = window_size, .after = -1),
      roll_oreb       = slide_dbl(offensive_rebounds, mean, .before = window_size, .after = -1),
      roll_dreb       = slide_dbl(defensive_rebounds, mean, .before = window_size, .after = -1),
      roll_ast        = slide_dbl(assists, mean, .before = window_size, .after = -1),
      roll_stl        = slide_dbl(steals, mean, .before = window_size, .after = -1),
      roll_blk        = slide_dbl(blocks, mean, .before = window_size, .after = -1),
      roll_tov        = slide_dbl(turnovers, mean, .before = window_size, .after = -1),
      roll_efg        = slide_dbl(efg, mean, .before = window_size, .after = -1),
      roll_tovp       = slide_dbl(tov, mean, .before = window_size, .after = -1),
      roll_ftr        = slide_dbl(ftr, mean, .before = window_size, .after = -1),
      roll_ts         = slide_dbl(ts, mean, .before = window_size, .after = -1)
    )
}

build_feature_df <- function(data, window_size = ROLLING_WINDOW_SIZE, method = "reset") {
  if (method == "reset") {
    features <- data |>
      arrange(team_id, season, game_date) |>
      group_by(season, team_id) |>
      compute_rolling_features(window_size) |>
      mutate(
        days_rest       = pmin(REST_DAYS_CAP, coalesce(as.numeric(game_date - lag(game_date)), 3))
      ) |>
      ungroup()
  } else {
    stop("build_model_benchmark_cache.R only uses method='reset' (the Rmd's real re-benchmark winner).")
  }

  features_selected <- features |>
    select(game_id, season, game_date, team_id, team_winner, team_home_away,
           roll_pts_scored, roll_oreb, roll_dreb, roll_ast, roll_stl, roll_blk,
           roll_tov, roll_efg, roll_tovp, roll_ftr, roll_ts, days_rest)

  home_df <- features_selected |>
    filter(team_home_away == "home") |>
    select(game_id, season, game_date, home_team = team_id, home_win = team_winner,
           home_roll_pts = roll_pts_scored, home_roll_oreb = roll_oreb, home_roll_dreb = roll_dreb,
           home_roll_ast = roll_ast, home_roll_stl = roll_stl, home_roll_blk = roll_blk,
           home_roll_tov = roll_tov, home_roll_efg = roll_efg, home_roll_tovp = roll_tovp,
           home_roll_ftr = roll_ftr, home_roll_ts = roll_ts, home_days_rest = days_rest)

  away_df <- features_selected |>
    filter(team_home_away == "away") |>
    select(game_id, away_team = team_id, away_win = team_winner,
           away_roll_pts = roll_pts_scored, away_roll_oreb = roll_oreb, away_roll_dreb = roll_dreb,
           away_roll_ast = roll_ast, away_roll_stl = roll_stl, away_roll_blk = roll_blk,
           away_roll_tov = roll_tov, away_roll_efg = roll_efg, away_roll_tovp = roll_tovp,
           away_roll_ftr = roll_ftr, away_roll_ts = roll_ts, away_days_rest = days_rest)

  joined_df <- dplyr::inner_join(home_df, away_df, by = "game_id", relationship = "one-to-one")

  model_df <- joined_df |>
    mutate(
      target_home_win = factor(if_else(home_win == TRUE, "Win", "Loss"), levels = c("Win", "Loss")),
      diff_roll_pts   = home_roll_pts - away_roll_pts,
      diff_roll_oreb  = home_roll_oreb - away_roll_oreb,
      diff_roll_dreb  = home_roll_dreb - away_roll_dreb,
      diff_roll_treb  = (home_roll_oreb + home_roll_dreb) - (away_roll_oreb + away_roll_dreb),
      diff_roll_ast   = home_roll_ast - away_roll_ast,
      diff_roll_stl   = home_roll_stl - away_roll_stl,
      diff_roll_blk   = home_roll_blk - away_roll_blk,
      diff_roll_tov   = home_roll_tov - away_roll_tov,
      diff_roll_efg   = home_roll_efg - away_roll_efg,
      diff_roll_tovp  = home_roll_tovp - away_roll_tovp,
      diff_roll_ftr   = home_roll_ftr - away_roll_ftr,
      diff_roll_ts    = home_roll_ts - away_roll_ts,
      diff_days_rest  = home_days_rest - away_days_rest
    ) |>
    drop_na()

  n_after_dropna <- nrow(model_df)
  message(sprintf(
    "build_feature_df(window_size=%s, method=%s): %d rows retained after drop_na() - expected early-season rolling-window NA gap.",
    window_size, method, n_after_dropna
  ))

  return(model_df)
}

build_wnba_recipe <- function(train_data) {
  recipe(target_home_win ~ ., data = train_data) |>
    step_rm(
      game_id, game_date, season, home_team, away_team, home_win, away_win,
      home_roll_ts, home_roll_ftr, home_roll_efg, home_roll_pts, home_roll_tovp,
      home_roll_oreb, home_roll_dreb, home_roll_ast, home_roll_stl, home_roll_blk, home_roll_tov,
      away_roll_ts, away_roll_ftr, away_roll_efg, away_roll_pts, away_roll_tovp,
      away_roll_oreb, away_roll_dreb, away_roll_ast, away_roll_stl, away_roll_blk, away_roll_tov,
      home_days_rest, away_days_rest
    ) |>
    step_normalize(all_numeric_predictors())
}

model_df <- build_feature_df(box_scores, window_size = ROLLING_WINDOW_SIZE, method = "reset")

# CURRENT_SEASON read from config.R (not hardcoded) - train on seasons strictly before it,
# evaluate out-of-sample on seasons >= it. Matches WNBA_Analysis_Project.Rmd's
# model-benchmarks chunk (lines 588-589).
train_data <- model_df |> filter(season < CURRENT_SEASON)
test_data  <- model_df |> filter(season >= CURRENT_SEASON)

stopifnot(nrow(train_data) > 0, nrow(test_data) > 0)

cat(sprintf(
  "[data] train: %d games (season < %d) | test: %d games (season >= %d)\n",
  nrow(train_data), CURRENT_SEASON, nrow(test_data), CURRENT_SEASON
))

wnba_recipe <- build_wnba_recipe(train_data)

# ------------------------------------------------------------------------------------------
# 3. Fit the three candidate architectures (identical specs to WNBA_Analysis_Project.Rmd's
#    model-benchmarks chunk, lines 593-603).
# ------------------------------------------------------------------------------------------
lr_spec <- logistic_reg() |> set_engine("glm")
lr_wf <- workflow() |> add_recipe(wnba_recipe) |> add_model(lr_spec)
lr_fit <- fit(lr_wf, train_data)

rf_spec <- rand_forest(trees = 250, mode = "classification") |>
  set_engine("ranger", importance = "impurity", num.threads = 4)
rf_wf <- workflow() |> add_recipe(wnba_recipe) |> add_model(rf_spec)
rf_fit <- fit(rf_wf, train_data)

xgb_spec <- boost_tree(trees = 150, tree_depth = 3, mode = "classification") |>
  set_engine("xgboost", nthread = 4)
xgb_wf <- workflow() |> add_recipe(wnba_recipe) |> add_model(xgb_spec)
xgb_fit <- fit(xgb_wf, train_data)

# ------------------------------------------------------------------------------------------
# 4. Evaluate out-of-sample - eval_model() copied verbatim from
#    WNBA_Analysis_Project.Rmd lines 605-622. Model names here match the brief's success
#    criteria exactly ("Logistic Regression", "Random Forest", "XGBoost") rather than the
#    Rmd's slightly more verbose labels ("Random Forest (ranger)", "XGBoost (boost_tree)").
# ------------------------------------------------------------------------------------------
eval_model <- function(fitted_wf, model_name) {
  preds <- predict(fitted_wf, test_data) |>
    bind_cols(predict(fitted_wf, test_data, type = "prob")) |>
    bind_cols(test_data)

  acc <- preds |> accuracy(truth = target_home_win, estimate = .pred_class) |> pull(.estimate)
  auc <- preds |> roc_auc(truth = target_home_win, .pred_Win, event_level = "first") |> pull(.estimate)
  brier <- mean((if_else(preds$target_home_win == "Win", 1, 0) - preds$.pred_Win)^2)
  logloss <- mn_log_loss(preds, truth = target_home_win, .pred_Win, event_level = "first") |> pull(.estimate)

  tibble(
    Model = model_name,
    Accuracy = round(acc, 4),
    `ROC-AUC` = round(auc, 4),
    `Brier Score` = round(brier, 4),
    `Log-Loss` = round(logloss, 4)
  )
}

benchmark_results <- bind_rows(
  eval_model(lr_fit, "Logistic Regression"),
  eval_model(rf_fit, "Random Forest"),
  eval_model(xgb_fit, "XGBoost")
)

print(benchmark_results)

out_path <- file.path(PROJECT_DIR, "data", "model_benchmark_results.csv")
write_csv(benchmark_results, out_path)
cat(sprintf("[done] wrote %s (%d rows)\n", out_path, nrow(benchmark_results)))
