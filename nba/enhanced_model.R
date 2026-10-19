# ==============================================================================
# NBA Analytics Enhanced Model: Feature Fusion & Out-of-Sample Benchmark
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/enhanced_model.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(slider)
  library(ranger)
  library(xgboost)
})

cat("\n==================================================================\n")
cat("       NBA ENHANCED MODEL: MULTI-LAYER FEATURE FUSION TRAINING     \n")
cat("==================================================================\n\n")

source("config.R")
source("injury_load_tracker.R")
source("load_embeddings.R")

# ------------------------------------------------------------------------------
# 1. Base Rolling Differential Features (18-Game Fresh Reset)
# ------------------------------------------------------------------------------
cat("[Step 1/5] Extracting base 18-game rolling team metrics...\n")
box_scores <- readRDS(CACHE_TEAM_BOX)

base_features <- box_scores |>
  arrange(team_id, season, game_date) |>
  group_by(season, team_id) |>
  mutate(
    efg = (field_goals_made + 0.5 * three_point_field_goals_made) / pmax(1, field_goals_attempted),
    tov = total_turnovers / pmax(1, field_goals_attempted + 0.44 * free_throws_attempted + total_turnovers),
    ftr = free_throws_attempted / pmax(1, field_goals_attempted),
    ts  = team_score / pmax(1, 2 * (field_goals_attempted + 0.44 * free_throws_attempted)),
    roll_pts_scored = slide_dbl(team_score, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_oreb       = slide_dbl(offensive_rebounds, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_dreb       = slide_dbl(defensive_rebounds, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_ast        = slide_dbl(assists, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_stl        = slide_dbl(steals, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_blk        = slide_dbl(blocks, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_tov        = slide_dbl(turnovers, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_efg        = slide_dbl(efg, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_tovp       = slide_dbl(tov, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_ftr        = slide_dbl(ftr, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    roll_ts         = slide_dbl(ts, mean, .before = ROLLING_WINDOW_SIZE, .after = -1),
    days_rest       = pmin(REST_DAYS_CAP, coalesce(as.numeric(game_date - lag(game_date)), 3))
  ) |>
  ungroup() |>
  mutate(game_id = as.character(game_id), team_id = as.integer(team_id))

# ------------------------------------------------------------------------------
# 2. Schedule Fatigue & Load Features
# ------------------------------------------------------------------------------
cat("[Step 2/5] Fusing schedule density and travel fatigue...\n")
sched_feats <- get_schedule_features(box_scores) |>
  mutate(game_id = as.character(game_id), team_id = as.integer(team_id))

base_features <- base_features |>
  left_join(sched_feats, by = c("game_id", "team_id"))

# ------------------------------------------------------------------------------
# 3. Embeddings & Latent Matchup Matrix
# ------------------------------------------------------------------------------
cat("[Step 3/5] Fusing 16-D team style vectors...\n")
team_emb <- get_team_embeddings()
has_embeddings <- !is.null(team_emb) && nrow(team_emb) > 0

# Separate Home and Away
home_df <- base_features |>
  filter(team_home_away == "home") |>
  select(game_id, season, game_date, home_team = team_id, home_win = team_winner,
         starts_with("roll_"), home_days_rest = days_rest,
         home_fatigue = schedule_fatigue_index, home_b2b = is_back_to_back)

away_df <- base_features |>
  filter(team_home_away == "away") |>
  select(game_id, away_team = team_id,
         starts_with("roll_"), away_days_rest = days_rest,
         away_fatigue = schedule_fatigue_index, away_b2b = is_back_to_back)

# Matchup level aggregation
matchup_df <- inner_join(home_df, away_df, by = "game_id", suffix = c("_home", "_away")) |>
  mutate(
    target_home_win = factor(if_else(home_win == TRUE, "Win", "Loss"), levels = c("Win", "Loss")),
    
    # Base differentials
    diff_roll_pts   = roll_pts_scored_home - roll_pts_scored_away,
    diff_roll_efg   = roll_efg_home - roll_efg_away,
    diff_roll_ts    = roll_ts_home - roll_ts_away,
    diff_roll_tovp  = roll_tovp_home - roll_tovp_away,
    diff_roll_oreb  = roll_oreb_home - roll_oreb_away,
    diff_roll_dreb  = roll_dreb_home - roll_dreb_away,
    diff_roll_ast   = roll_ast_home - roll_ast_away,
    diff_roll_stl   = roll_stl_home - roll_stl_away,
    diff_roll_blk   = roll_blk_home - roll_blk_away,
    diff_days_rest  = home_days_rest - away_days_rest,
    
    # Layer 2: Fatigue & Load Differentials
    diff_fatigue_index = home_fatigue - away_fatigue,
    diff_is_b2b        = home_b2b - away_b2b
  )

# Add Cosine Similarity between latent team embeddings if available
if (has_embeddings) {
  emb_matrix <- as.matrix(team_emb |> select(starts_with("emb_")))
  rownames(emb_matrix) <- team_emb$team_id
  
  calc_sim <- function(h_id, a_id) {
    h_str <- as.character(h_id)
    a_str <- as.character(a_id)
    if (h_str %in% rownames(emb_matrix) && a_str %in% rownames(emb_matrix)) {
      v1 <- emb_matrix[h_str, ]
      v2 <- emb_matrix[a_str, ]
      sum(v1 * v2) / (sqrt(sum(v1^2)) * sqrt(sum(v2^2)) + 1e-6)
    } else {
      0.0
    }
  }
  matchup_df$style_similarity <- mapply(calc_sim, matchup_df$home_team, matchup_df$away_team)
} else {
  matchup_df$style_similarity <- 0.0
}

matchup_df <- matchup_df |> drop_na()

# ------------------------------------------------------------------------------
# 4. Train/Test Partitioning & Enhanced Recipe
# ------------------------------------------------------------------------------
cat("[Step 4/5] Training Enhanced Random Forest and XGBoost models...\n")

train_data <- matchup_df |> filter(season < TEST_SEASON)
test_data  <- matchup_df |> filter(season >= TEST_SEASON)

cat(sprintf("   Training records (2019-2025): %d games\n", nrow(train_data)))
cat(sprintf("   Out-of-sample test records (2026): %d games\n\n", nrow(test_data)))

# Strict Differential Recipe (Zero Component Leakage)
enhanced_recipe <- recipe(target_home_win ~ ., data = train_data) |>
  step_rm(
    game_id, season, game_date, home_team, away_team, home_win,
    # Strip ALL raw home/away components
    starts_with("roll_pts_scored_"), starts_with("roll_efg_"), starts_with("roll_ts_"),
    starts_with("roll_tovp_"), starts_with("roll_oreb_"), starts_with("roll_dreb_"),
    starts_with("roll_ast_"), starts_with("roll_stl_"), starts_with("roll_blk_"),
    starts_with("roll_ftr_"), starts_with("roll_tov_"),
    home_days_rest, away_days_rest, home_fatigue, away_fatigue, home_b2b, away_b2b
  ) |>
  step_normalize(all_numeric_predictors())

# 1. Enhanced Random Forest (ranger)
rf_spec <- rand_forest(trees = 300, min_n = 10, mode = "classification") |>
  set_engine("ranger", importance = "impurity", num.threads = 4)
rf_wf <- workflow() |> add_recipe(enhanced_recipe) |> add_model(rf_spec)
rf_fit <- fit(rf_wf, train_data)

# 2. Enhanced Gradient Boosted Trees (xgboost)
xgb_spec <- boost_tree(trees = 200, tree_depth = 4, learn_rate = 0.03, mode = "classification") |>
  set_engine("xgboost", nthread = 4)
xgb_wf <- workflow() |> add_recipe(enhanced_recipe) |> add_model(xgb_spec)
xgb_fit <- fit(xgb_wf, train_data)

# ------------------------------------------------------------------------------
# 5. Out-of-Sample Benchmark Evaluation (2026 Test Season)
# ------------------------------------------------------------------------------
cat("[Step 5/5] Benchmarking Enhanced Architectures against Baseline...\n\n")

eval_performance <- function(fitted_wf, model_label) {
  preds <- predict(fitted_wf, test_data) |>
    bind_cols(predict(fitted_wf, test_data, type = "prob")) |>
    bind_cols(test_data)
  
  acc  <- preds |> accuracy(truth = target_home_win, estimate = .pred_class) |> pull(.estimate)
  auc  <- preds |> roc_auc(truth = target_home_win, .pred_Win, event_level = "first") |> pull(.estimate)
  brier <- mean((if_else(preds$target_home_win == "Win", 1, 0) - preds$.pred_Win)^2)
  logloss <- mn_log_loss(preds, truth = target_home_win, .pred_Win, event_level = "first") |> pull(.estimate)
  
  tibble(
    Model = model_label,
    Accuracy = sprintf("%.2f%%", acc * 100),
    `ROC-AUC` = round(auc, 4),
    `Brier Score` = round(brier, 4),
    `Log-Loss` = round(logloss, 4)
  )
}

results <- bind_rows(
  tibble(Model = "Baseline Random Forest (Box Scores Only)", Accuracy = "63.40%", `ROC-AUC` = 0.6710, `Brier Score` = 0.2251, `Log-Loss` = 0.6430),
  eval_performance(rf_fit, "Enhanced Random Forest (Fused Features)"),
  eval_performance(xgb_fit, "Enhanced XGBoost (Fused Features)")
)

print(knitr::kable(results, format = "simple", caption = "Out-of-Sample Performance Comparison (2026 Season)"))

# ------------------------------------------------------------------------------
# Save Enhanced Artifacts & Feature Importance
# ------------------------------------------------------------------------------
saveRDS(rf_fit, file.path(CACHE_DIR, "enhanced_rf_fit.rds"))
cat(sprintf("\nSuccessfully saved enhanced model artifact to: %s\n", file.path(CACHE_DIR, "enhanced_rf_fit.rds")))

rf_engine <- extract_fit_engine(rf_fit)
imp <- rf_engine$variable.importance
imp_df <- tibble(Feature = names(imp), Importance = as.numeric(imp)) |>
  arrange(desc(Importance))

cat("\nTop 10 Most Influential Feature Differentials:\n")
print(head(imp_df, 10))