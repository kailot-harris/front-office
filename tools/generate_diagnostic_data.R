# tools/generate_diagnostic_data.R
# Generates synthetic resolved data to test the Error Analysis framework.
#
# FINDING C-3 (docs/SECURITY_TECHNICAL_REVIEW.md): the 100 rows this script writes
# were, until Phase 4, indistinguishable from real predictions once in
# cache/prediction_accuracy_log.rds. app.R's Tab 8 filtered only on
# `status == "RESOLVED"`, so these fixtures were the ONLY thing the model-accuracy
# scoreboard ever displayed — a fabricated "83% accuracy / 0.131 Brier" presented as
# measured performance. Every row written here is now stamped
# `is_synthetic = TRUE` and `market_data_source = "DIAGNOSTIC"` at
# `schema_version = 2`, which agent_dashboard's Tab 8 reactive and
# prediction_accuracy_logger.R::summarize_prediction_accuracy() both filter on.
# If you add columns here, keep those two stamps — they are an interface contract
# (docs/task_assignments_phase4.md, "Interface contracts"), not decoration.

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
      stop(sprintf("generate_diagnostic_data.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
library(tidyverse)
source("config.R")

log_path <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
existing_log <- if (file.exists(log_path)) readRDS(log_path) else tibble()

set.seed(42)
n_games <- 100
teams <- names(WNBA_TEAMS)

# Create synthetic resolved games
synthetic_resolved <- tibble(
  # C-3: schema_version 2 — carries is_synthetic + market_data_source (see below).
  schema_version = 2L,
  game_id = paste0("DIAG_", 1:n_games),
  game_date = as.Date("2026-01-01") + sample(0:200, n_games, replace = TRUE),
  season = 2026L,
  home_team = sample(teams, n_games, replace = TRUE),
  away_team = sample(teams, n_games, replace = TRUE),
  prediction_timestamp = Sys.time() - 86400,
  predicted_home_win_prob = runif(n_games, 0.2, 0.8),
  predicted_winner = "TBD", # Will fix below
  predicted_margin = rnorm(n_games, 0, 10),
  contrib_net_diff = rnorm(n_games, 0, 8),
  contrib_hca = 2.4,
  contrib_fatigue = rnorm(n_games, 0, 2),
  model_rolling_window_size = 12L,
  model_margin_sigma = 14.0,
  model_rotation_size = 8L,
  model_offseason_method = "reset",
  injury_data_source = "DIAGNOSTIC",
  shot_quality_data_source = "DIAGNOSTIC",
  # C-3 interface contract — exact name `is_synthetic`, logical type. This is the
  # single flag that keeps these fixtures out of every reported accuracy metric.
  market_data_source = "DIAGNOSTIC",
  is_synthetic = TRUE,
  status = "RESOLVED",
  actual_winner = "TBD",
  correct = NA,
  brier_component = NA_real_,
  log_loss_component = NA_real_,
  resolved_timestamp = Sys.time()
)

# Inject specific bias patterns for the diagnostic tool to find:
# 1. "The LV Aces Bias": Model consistently under-predicts LV Aces (Home)
#     lavez_idx <- which(synthetic_resolved$home_team == "LV")
#    synthetic_resolved$predicted_margin[lavez_idx] <- synthetic_resolved$predicted_margin[lavez_idx] - 5

# 2. "Fatigue Blindness": High fatigue_drag correlates with larger residuals
#    synthetic_resolved <- synthetic_resolved |>
#      mutate(actual_margin = predicted_margin + (contrib_fatigue * 1.5) + rnorm(n_games, 0, 5))

# Simplified synthetic outcome generation
synthetic_resolved <- synthetic_resolved |>
  mutate(
    # Base actual margin = predicted + noise
    actual_margin = predicted_margin + rnorm(n_games, 0, 7),
    # Inject LV Aces under-prediction bias
    actual_margin = if_else(home_team == "LV", actual_margin + 6, actual_margin),
    # Inject Fatigue Correlation (Residuals grow with fatigue_drag)
    actual_margin = actual_margin + (contrib_fatigue * 2.0),

    actual_winner = if_else(actual_margin >= 0, home_team, away_team),
    predicted_winner = if_else(predicted_margin >= 0, home_team, away_team),
    correct = (actual_winner == predicted_winner),
    # Dummy Brier/LogLoss for schema compliance
    brier_component = runif(n_games, 0, 0.25),
    log_loss_component = runif(n_games, 0.1, 1.0)
  )

updated_log <- bind_rows(existing_log, synthetic_resolved)

# C-3 guard: never let a fixture row reach the log unstamped. If bind_rows() had to
# NA-fill is_synthetic for pre-existing rows, backfill them with the same rule
# prediction_accuracy_logger.R::migrate_prediction_log() uses, so this script can
# never itself be the source of an unmarked synthetic row.
if (!"is_synthetic" %in% names(updated_log)) updated_log$is_synthetic <- FALSE
updated_log <- updated_log |>
  mutate(
    is_synthetic = coalesce(
      as.logical(is_synthetic),
      grepl("^DIAG_", as.character(game_id)) |
        (!is.na(injury_data_source) & injury_data_source == "DIAGNOSTIC")
    ),
    market_data_source = coalesce(
      as.character(market_data_source),
      if_else(is_synthetic, "DIAGNOSTIC", "UNKNOWN")
    )
  )

stopifnot(is.logical(updated_log$is_synthetic), !any(is.na(updated_log$is_synthetic)))

saveRDS(updated_log, log_path)
cat(sprintf("Successfully injected %d synthetic RESOLVED games into log for diagnostics (all stamped is_synthetic = TRUE, schema_version 2).\n", n_games))
cat(sprintf("Log now holds %d rows, %d flagged synthetic.\n", nrow(updated_log), sum(updated_log$is_synthetic)))
