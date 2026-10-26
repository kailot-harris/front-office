# ==============================================================================
# tools/ml_feature_experiments_paired_ci.R
# ------------------------------------------------------------------------------
# Follow-up rigor check for docs/ML_IMPROVEMENT_IDEAS.md Part 2. The main
# ml_feature_experiments.R run compares baseline vs. each candidate feature via
# two SEPARATE bootstrap 95% CIs (identical to ml_cv_benchmark.R's own
# methodology) -- that's the headline, directly-comparable-to-the-published-
# report number. This script adds one additional, more sensitive check: since
# baseline and each candidate model are evaluated on the EXACT SAME games
# (same LOSO folds, same held-out games), a PAIRED bootstrap on the per-game
# delta is a tighter, less noisy way to ask "is this specific candidate
# actually better than baseline, or is the gap consistent with sampling
# noise?" -- paired resampling cancels out game-level difficulty variation
# that inflates the width of two independent marginal CIs.
#
# This does not change or re-run any model -- it only re-analyzes the
# oof_table predictions already saved by ml_feature_experiments.R.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe tools/ml_feature_experiments_paired_ci.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(yardstick)
})

# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("ml_feature_experiments_paired_ci.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

res <- readRDS(file.path("cache", "ml_feature_experiments_results.rds"))

paired_bootstrap <- function(base_oof, cand_oof, label, n_boot = 2000, seed = 20260912) {
  set.seed(seed)
  base_j <- base_oof |> arrange(game_id) |> mutate(correct_base = (.pred_class == target_home_win))
  cand_j <- cand_oof  |> arrange(game_id) |> mutate(correct_cand = (.pred_class == target_home_win))
  stopifnot(identical(base_j$game_id, cand_j$game_id))

  n <- nrow(base_j)
  point_acc_base <- mean(base_j$correct_base)
  point_acc_cand <- mean(cand_j$correct_cand)
  point_delta_acc <- point_acc_cand - point_acc_base

  auc_of <- function(d, probcol) {
    roc_auc_vec(truth = d$target_home_win, estimate = d[[probcol]], event_level = "first")
  }
  point_auc_base <- auc_of(base_j, ".pred_Win")
  point_auc_cand <- auc_of(cand_j, ".pred_Win")
  point_delta_auc <- point_auc_cand - point_auc_base

  deltas_acc <- numeric(n_boot)
  deltas_auc <- numeric(n_boot)
  for (i in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    deltas_acc[i] <- mean(cand_j$correct_cand[idx]) - mean(base_j$correct_base[idx])
    deltas_auc[i] <- auc_of(cand_j[idx, ], ".pred_Win") - auc_of(base_j[idx, ], ".pred_Win")
  }

  tibble(
    candidate = label,
    metric = c("accuracy", "roc_auc"),
    point_delta = c(point_delta_acc, point_delta_auc),
    ci_lo = c(quantile(deltas_acc, 0.025, na.rm = TRUE), quantile(deltas_auc, 0.025, na.rm = TRUE)),
    ci_hi = c(quantile(deltas_acc, 0.975, na.rm = TRUE), quantile(deltas_auc, 0.975, na.rm = TRUE)),
    pct_boot_gt_0 = c(mean(deltas_acc > 0), mean(deltas_auc > 0))
  )
}

out <- bind_rows(
  paired_bootstrap(res$baseline_oof_table, res$elo_oof_table, "elo"),
  paired_bootstrap(res$baseline_oof_table, res$rapm_oof_table, "rapm"),
  paired_bootstrap(res$baseline_oof_table, res$ewma_oof_table, "ewma")
)

cat("\n===== PAIRED bootstrap 95% CI on (candidate - baseline) delta, same games, n_boot=2000 =====\n")
print(out, n = Inf)

saveRDS(out, file.path("cache", "ml_feature_experiments_paired_ci.rds"))
cat("\n[done] Saved cache/ml_feature_experiments_paired_ci.rds\n")
