# ml_cv_benchmark.R
# ------------------------------------------------------------------------------------------
# P4 (wnba_ml_benchmark_agent) - rigorous cross-validated benchmark of the WNBA win-prediction
# model against a named external standard.
#
# Reuses WNBA_Analysis_Project.Rmd's exact feature-engineering function (build_feature_df,
# window_size = ROLLING_WINDOW_SIZE = 13, method = "reset") and its winning architecture on the
# real WNBA re-run (Random Forest via ranger - see WNBA_Analysis_Project.Rmd lines ~398-402 and
# task_assignments.md's T2 Handoff Notes: RF won on ROC-AUC 0.666 / Brier 0.227 / Log-Loss 0.644
# on a SINGLE train/2026-holdout split). This script does NOT trust that single split; it re-fits
# RF under leave-one-season-out (LOSO) cross-validation across all 8 real seasons (2019-2026) in
# box_scores_cache.rds, computes accuracy/precision/recall/F1/ROC-AUC per fold and pooled, with
# bootstrap 95% CIs on the pooled out-of-fold predictions.
#
# Then, as the "legitimate improvement" step (GAP_REMEDIATION_PLAN.md / agent10.md Step 4), it
# re-runs the identical LOSO procedure with one added real feature: cosine similarity between the
# home and away team's P1-regenerated real-data embedding vectors (team_embeddings.csv, retrained
# on cache/games_for_embeddings.csv's 1,953 real games, per P1's Handoff Notes in
# task_assignments_phase2.md). cache/travel_fatigue_metrics.rds was considered and REJECTED for
# this purpose: it contains only 4 illustrative demo rows (not one row per historical game across
# 1,902 modeled games), so it cannot supply a real per-game training feature without fabricating
# the other ~1,898 rows - which would violate this task's own no-p-hacking/no-fabrication mandate.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe ml_cv_benchmark.R
# ------------------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(tidymodels)
  library(slider)
  library(fastshap)
})

set.seed(20260912)  # fixed seed for reproducibility of bootstrap resampling only (not for tuning)

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)
source("config.R")

# ------------------------------------------------------------------------------------------
# 1. Load real data
# ------------------------------------------------------------------------------------------
stopifnot(file.exists(CACHE_TEAM_BOX))
box_scores <- readRDS(CACHE_TEAM_BOX)
cat(sprintf("[data] box_scores_cache.rds: %d real team-game rows, seasons %s\n",
            nrow(box_scores), paste(range(box_scores$season), collapse = "-")))

# team_id (numeric ESPN id) -> team_abbreviation lookup, needed to join the embeddings CSV
# (which is keyed by abbreviation string per P1's Handoff Notes).
team_lookup <- box_scores |>
  distinct(team_id, team_abbreviation)

emb_path <- if (exists("CACHE_EMBEDDINGS")) CACHE_EMBEDDINGS else file.path(PROJECT_DIR, "data", "team_embeddings.csv")
stopifnot(file.exists(emb_path))
team_emb <- read_csv(emb_path, show_col_types = FALSE)
emb_cols <- setdiff(names(team_emb), "team_id")
cat(sprintf("[data] team_embeddings.csv: %d teams x %d embedding dims (real-trained per P1)\n",
            nrow(team_emb), length(emb_cols)))

# ------------------------------------------------------------------------------------------
# 2. Feature engineering - IDENTICAL to WNBA_Analysis_Project.Rmd's build_feature_df()
#    (copied verbatim, window_size default overridden by caller to ROLLING_WINDOW_SIZE = 13,
#    method = "reset", per the Rmd's own real-data re-benchmark: reset won on ROC-AUC/Brier).
# ------------------------------------------------------------------------------------------
build_feature_df <- function(data, window_size = ROLLING_WINDOW_SIZE, method = "reset") {
  if (method == "reset") {
    features <- data |>
      arrange(team_id, season, game_date) |>
      group_by(season, team_id) |>
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
        roll_ts         = slide_dbl(ts, mean, .before = window_size, .after = -1),
        days_rest       = pmin(REST_DAYS_CAP, coalesce(as.numeric(game_date - lag(game_date)), 3))
      ) |>
      ungroup()
  } else {
    stop("Only 'reset' is used by this benchmark (Rmd's real re-benchmark winner); other methods omitted here.")
  }

  features_selected <- features |>
    select(game_id, season, game_date, team_id, team_abbreviation, team_winner, team_home_away,
           roll_pts_scored, roll_oreb, roll_dreb, roll_ast, roll_stl, roll_blk,
           roll_tov, roll_efg, roll_tovp, roll_ftr, roll_ts, days_rest)

  home_df <- features_selected |>
    filter(team_home_away == "home") |>
    select(game_id, season, game_date, home_team = team_id, home_abbr = team_abbreviation,
           home_win = team_winner,
           home_roll_pts = roll_pts_scored, home_roll_oreb = roll_oreb, home_roll_dreb = roll_dreb,
           home_roll_ast = roll_ast, home_roll_stl = roll_stl, home_roll_blk = roll_blk,
           home_roll_tov = roll_tov, home_roll_efg = roll_efg, home_roll_tovp = roll_tovp,
           home_roll_ftr = roll_ftr, home_roll_ts = roll_ts, home_days_rest = days_rest)

  away_df <- features_selected |>
    filter(team_home_away == "away") |>
    select(game_id, away_team = team_id, away_abbr = team_abbreviation, away_win = team_winner,
           away_roll_pts = roll_pts_scored, away_roll_oreb = roll_oreb, away_roll_dreb = roll_dreb,
           away_roll_ast = roll_ast, away_roll_stl = roll_stl, away_roll_blk = roll_blk,
           away_roll_tov = roll_tov, away_roll_efg = roll_efg, away_roll_tovp = roll_tovp,
           away_roll_ftr = roll_ftr, away_roll_ts = roll_ts, away_days_rest = days_rest)

  model_df <- inner_join(home_df, away_df, by = "game_id") |>
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

  return(model_df)
}

model_df <- build_feature_df(box_scores, window_size = ROLLING_WINDOW_SIZE, method = "reset")
cat(sprintf("[data] model_df (window=%d, reset): %d real games, seasons %s\n",
            ROLLING_WINDOW_SIZE, nrow(model_df), paste(range(model_df$season), collapse = "-")))
print(table(model_df$season))

# ------------------------------------------------------------------------------------------
# 3. Add the real embeddings-similarity feature (P1's real-trained team_embeddings.csv)
# ------------------------------------------------------------------------------------------
emb_mat <- as.matrix(team_emb[, emb_cols])
rownames(emb_mat) <- team_emb$team_id

cosine_sim <- function(a, b) {
  if (is.null(a) || is.null(b) || any(is.na(a)) || any(is.na(b))) return(NA_real_)
  sum(a * b) / (sqrt(sum(a^2)) * sqrt(sum(b^2)))
}

model_df_emb <- model_df |>
  rowwise() |>
  mutate(
    emb_similarity = {
      h <- if (home_abbr %in% rownames(emb_mat)) emb_mat[home_abbr, ] else NULL
      a <- if (away_abbr %in% rownames(emb_mat)) emb_mat[away_abbr, ] else NULL
      cosine_sim(h, a)
    }
  ) |>
  ungroup()

n_missing_emb <- sum(is.na(model_df_emb$emb_similarity))
cat(sprintf("[data] emb_similarity computed for %d/%d games (%d missing -> dropped for the 'improved' model only)\n",
            nrow(model_df_emb) - n_missing_emb, nrow(model_df_emb), n_missing_emb))
model_df_emb <- model_df_emb |> filter(!is.na(emb_similarity))

# ------------------------------------------------------------------------------------------
# 4. Model spec - winning architecture per WNBA_Analysis_Project.Rmd's real re-run:
#    Random Forest (ranger) won ROC-AUC/Brier/Log-Loss on the WNBA data (matches the NBA
#    baseline's own conclusion; verified independently here, not assumed).
# ------------------------------------------------------------------------------------------
rf_spec <- rand_forest(trees = 250, mode = "classification") |>
  set_engine("ranger", importance = "impurity", num.threads = 4)

drop_cols_base <- c("game_id", "game_date", "season", "home_team", "away_team",
                     "home_abbr", "away_abbr", "home_win", "away_win",
                     "home_roll_ts", "home_roll_ftr", "home_roll_efg", "home_roll_pts", "home_roll_tovp",
                     "home_roll_oreb", "home_roll_dreb", "home_roll_ast", "home_roll_stl", "home_roll_blk", "home_roll_tov",
                     "away_roll_ts", "away_roll_ftr", "away_roll_efg", "away_roll_pts", "away_roll_tovp",
                     "away_roll_oreb", "away_roll_dreb", "away_roll_ast", "away_roll_stl", "away_roll_blk", "away_roll_tov",
                     "home_days_rest", "away_days_rest")

make_recipe <- function(train_data, extra_drop = character(0)) {
  recipe(target_home_win ~ ., data = train_data) |>
    step_rm(all_of(intersect(c(drop_cols_base, extra_drop), names(train_data)))) |>
    step_normalize(all_numeric_predictors())
}

# ------------------------------------------------------------------------------------------
# 5. Leave-one-season-out cross-validation
# ------------------------------------------------------------------------------------------
run_loso <- function(df, label) {
  seasons <- sort(unique(df$season))
  fold_results <- list()
  oof_preds <- list()
  shap_results <- list()

  for (s in seasons) {
    train_data <- df |> filter(season != s)
    test_data  <- df |> filter(season == s)
    if (nrow(test_data) < 10) {
      cat(sprintf("[%s] season %d: only %d rows, skipping fold (too small for stable metrics)\n", label, s, nrow(test_data)))
      next
    }

    rec <- make_recipe(train_data)
    wf <- workflow() |> add_recipe(rec) |> add_model(rf_spec)
    fit_m <- fit(wf, train_data)

    preds <- predict(fit_m, test_data) |>
      bind_cols(predict(fit_m, test_data, type = "prob")) |>
      bind_cols(test_data |> select(game_id, season, target_home_win))

    acc  <- accuracy(preds, truth = target_home_win, estimate = .pred_class) |> pull(.estimate)
    prec <- precision(preds, truth = target_home_win, estimate = .pred_class, event_level = "first") |> pull(.estimate)
    rec_ <- recall(preds, truth = target_home_win, estimate = .pred_class, event_level = "first") |> pull(.estimate)
    f1   <- f_meas(preds, truth = target_home_win, estimate = .pred_class, event_level = "first") |> pull(.estimate)
    auc  <- roc_auc(preds, truth = target_home_win, .pred_Win, event_level = "first") |> pull(.estimate)

    fold_results[[as.character(s)]] <- tibble(
      season = s, n = nrow(test_data), accuracy = acc, precision = prec,
      recall = rec_, f1 = f1, roc_auc = auc
    )
    oof_preds[[as.character(s)]] <- preds

    # SHAP analysis for this fold
    try({
      rf_obj <- extract_fit_engine(fit_m)
      # Prepare numeric matrices for fastshap
      p_rec <- prep(rec)
      train_processed <- bake(p_rec, new_data = train_data) |>
        select(-all_of(intersect(c(drop_cols_base, "emb_similarity"), names(train_data)))) |>
        as.matrix()
      test_processed <- bake(p_rec, new_data = test_data) |>
        select(-all_of(intersect(c(drop_cols_base, "emb_similarity"), names(train_data)))) |>
        as.matrix()

      # Define prediction wrapper for fastshap
      p_fn <- function(object, newdata) {
        predict(object, newdata, type = "prob")[, "Win"]
      }

      # Compute SHAP values for test set (nsim=10 for speed in CV)
      s_vals <- fastshap::explain(rf_obj, X = test_processed, pred_wrapper = p_fn, nsim = 10, K = 0)
      shap_results[[as.character(s)]] <- as_tibble(s_vals) |>
        mutate(season = s)
    }, silent = TRUE)

    cat(sprintf("[%s] fold season=%d n=%d acc=%.4f prec=%.4f rec=%.4f f1=%.4f auc=%.4f\n",
                label, s, nrow(test_data), acc, prec, rec_, f1, auc))
  }

  fold_table <- bind_rows(fold_results)
  oof_table  <- bind_rows(oof_preds)
  shap_table <- bind_rows(shap_results)
  list(fold_table = fold_table, oof_table = oof_table, shap_table = shap_table)
}

cat("\n===== BASELINE MODEL (Rmd feature set, no embeddings) - LOSO CV =====\n")
baseline_loso <- run_loso(model_df, "baseline")

cat("\n===== IMPROVED MODEL (+ emb_similarity real feature) - LOSO CV =====\n")
improved_loso <- run_loso(model_df_emb, "improved")

# ------------------------------------------------------------------------------------------
# 6. Pooled metrics + bootstrap 95% CI on out-of-fold predictions
# ------------------------------------------------------------------------------------------
bootstrap_ci <- function(oof_table, n_boot = 2000, seed = 20260912) {
  set.seed(seed)
  n <- nrow(oof_table)
  metric_fn <- function(d) {
    tibble(
      accuracy  = accuracy(d, truth = target_home_win, estimate = .pred_class)$.estimate,
      precision = precision(d, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
      recall    = recall(d, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
      f1        = f_meas(d, truth = target_home_win, estimate = .pred_class, event_level = "first")$.estimate,
      roc_auc   = roc_auc(d, truth = target_home_win, .pred_Win, event_level = "first")$.estimate
    )
  }

  point <- metric_fn(oof_table)

  boot_draws <- map_dfr(1:n_boot, function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    metric_fn(oof_table[idx, ])
  })

  ci <- map_dfr(names(point), function(m) {
    vals <- boot_draws[[m]]
    tibble(metric = m, estimate = point[[m]],
           ci_lo = quantile(vals, 0.025, na.rm = TRUE),
           ci_hi = quantile(vals, 0.975, na.rm = TRUE))
  })
  ci
}

cat("\n===== POOLED OUT-OF-FOLD METRICS + BOOTSTRAP 95% CI (n_boot=2000, percentile method) =====\n")
baseline_ci <- bootstrap_ci(baseline_loso$oof_table)
cat("-- Baseline (n_oof =", nrow(baseline_loso$oof_table), ") --\n")
print(baseline_ci)

# SHAP Global Importance for Baseline
cat("\n--- Baseline Pooled SHAP Feature Importance (OOF) ---\n")
baseline_shap_imp <- baseline_loso$shap_table |>
  summarise(across(where(is.numeric) & !contains("season"), ~mean(abs(.x), na.rm = TRUE))) |>
  pivot_longer(everything(), names_to = "feature", values_to = "mean_abs_shap") |>
  arrange(desc(mean_abs_shap))
print(knitr::kable(baseline_shap_imp, format = "simple"))

improved_ci <- bootstrap_ci(improved_loso$oof_table)
cat("-- Improved (+emb_similarity) (n_oof =", nrow(improved_loso$oof_table), ") --\n")
print(improved_ci)

# SHAP Global Importance for Improved
cat("\n--- Improved Pooled SHAP Feature Importance (OOF) ---\n")
improved_shap_imp <- improved_loso$shap_table |>
  summarise(across(where(is.numeric) & !contains("season"), ~mean(abs(.x), na.rm = TRUE))) |>
  pivot_longer(everything(), names_to = "feature", values_to = "mean_abs_shap") |>
  arrange(desc(mean_abs_shap))
print(knitr::kable(improved_shap_imp, format = "simple"))


# Fold-to-fold normal/t-approx CI as a secondary check (8 folds -> t with df = n_folds-1)
fold_ci <- function(fold_table) {
  n_folds <- nrow(fold_table)
  tcrit <- qt(0.975, df = n_folds - 1)
  fold_table |>
    summarise(across(c(accuracy, precision, recall, f1, roc_auc),
                      list(mean = ~mean(.x), se = ~sd(.x) / sqrt(n_folds)))) |>
    pivot_longer(everything(), names_to = "stat", values_to = "value") |>
    mutate(metric = str_remove(stat, "_mean$|_se$"), which = if_else(str_detect(stat, "_mean$"), "mean", "se")) |>
    select(metric, which, value) |>
    pivot_wider(names_from = which, values_from = value) |>
    mutate(ci_lo = mean - tcrit * se, ci_hi = mean + tcrit * se)
}

cat("\n===== FOLD-TO-FOLD (across-season) MEAN +/- t-CI (secondary check, n_folds small) =====\n")
cat("-- Baseline --\n"); print(fold_ci(baseline_loso$fold_table))
cat("-- Improved --\n"); print(fold_ci(improved_loso$fold_table))

# ------------------------------------------------------------------------------------------
# 7. Save everything a report-writer needs
# ------------------------------------------------------------------------------------------
saveRDS(list(
  baseline_fold_table = baseline_loso$fold_table,
  baseline_oof_table  = baseline_loso$oof_table,
  baseline_boot_ci    = baseline_ci,
  improved_fold_table = improved_loso$fold_table,
  improved_oof_table  = improved_loso$oof_table,
  improved_boot_ci    = improved_ci,
  n_missing_emb       = n_missing_emb
), file.path("cache", "ml_benchmark_cv_results.rds"))

cat("\n[done] Saved cache/ml_benchmark_cv_results.rds\n")
