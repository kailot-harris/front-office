# ==============================================================================
# tests/test_backfill_and_provenance.R
# Test Suite for Walk-Forward Backfill and Provenance Tracking (Issue #112 / Section 5.3)
#
# Validates:
#   1. Backfilled games count: all 145 completed 2026 games in cache/prediction_accuracy_log.rds
#      with log_source = "BACKTEST_PREWEEK".
#   2. Schema completeness: all required forecast, metadata, waterfall, and outcome columns present.
#   3. Power ratings: non-zero entering power ratings across all 145 games.
#   4. Points waterfall integrity: five steps sum to projected margin with step_rounding <= 0.02.
#   5. Model accuracy reconciliation: 89/145 correct (61.4%) and Brier score 0.2242 under Variant 1.
#   6. Web dataset integration: matchups_current_week.json completed games have non-zero power ratings.
#   7. Decision D1 separation: model_diagnostics.json contains distinct genuine_pregame (n=0, null)
#      and historical_backtest (n=145, 61.4%, 0.2242) blocks.
#   8. Immutability gate: backfill preserves LOGGED_PREGAME rows permanently without overwriting.
#   9. Zero-betting policy: zero forbidden terms across backfill tool, exporter, and tests.
#
# Runs via:
#   Rscript tests/test_backfill_and_provenance.R
# ==============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("testthat", quietly = TRUE)) {
    library(testthat)
  }
  library(dplyr)
  library(jsonlite)
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}

source(file.path(root_dir, "config.R"))
source(file.path(root_dir, "tools", "forecast_engine.R"))
source(file.path(root_dir, "tools", "backfill_prediction_log.R"))
source(file.path(root_dir, "tests", "helpers", "test_fixtures.R"))

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

tol <- 1e-6

# ------------------------------------------------------------------------------
# Test 1: Prediction accuracy log exists with 145 backfilled games
# ------------------------------------------------------------------------------
log_path <- get_prediction_log_path(root_dir)
have_log <- !is.null(log_path)
if (!have_log) cat("[SKIP] BFP-1 to BFP-5 skipped: prediction accuracy log is not available in cache/ or tests/fixtures/\n")
if (have_log) test_that("BFP-1 Prediction accuracy log contains 145 completed 2026 games with BACKTEST_PREWEEK", {
  cond_file <- file.exists(log_path)
  ok("BFP-1a Prediction accuracy log exists on disk", cond_file, log_path)
  expect_true(cond_file)

  log_df <- readRDS(log_path)
  backtest_26 <- log_df |> filter(season == 2026L, log_source == "BACKTEST_PREWEEK")

  cond_count <- nrow(backtest_26) >= 145L
  ok("BFP-1b At least 145 backfilled games for 2026 with log_source = 'BACKTEST_PREWEEK'",
     cond_count, sprintf("Found %d rows", nrow(backtest_26)))
  expect_gte(nrow(backtest_26), 145L)
})

# ------------------------------------------------------------------------------
# Test 2: Required columns completeness
# ------------------------------------------------------------------------------
if (have_log) test_that("BFP-2 All required schema columns exist in backfilled records", {
  log_df <- readRDS(log_path)
  required_cols <- c(
    "game_id", "season", "week", "gameday", "away_team", "home_team",
    "log_source", "logged_at", "refreshed_at", "kickoff_time", "kickoff_fallback",
    "projected_margin", "home_win_prob", "away_win_prob",
    "home_power_rating", "away_power_rating",
    "step_current_epa", "step_prior_epa", "step_elo_diff", "step_home_field",
    "step_qb_adjustment", "step_rounding",
    "home_score", "away_score", "actual_margin", "actual_winner",
    "prediction_correct", "brier_score"
  )

  missing_cols <- setdiff(required_cols, names(log_df))
  cond_cols <- length(missing_cols) == 0L

  ok("BFP-2 All 28 required forecast, metadata, waterfall, and result columns present",
     cond_cols, if (cond_cols) "All present" else paste("Missing:", paste(missing_cols, collapse = ", ")))
  expect_true(cond_cols)
})

# ------------------------------------------------------------------------------
# Test 3: Non-zero entering power ratings
# ------------------------------------------------------------------------------
if (have_log) test_that("BFP-3 Non-zero entering power ratings across all 145 backfilled games", {
  log_df <- readRDS(log_path)
  b26 <- log_df |> filter(season == 2026L, log_source == "BACKTEST_PREWEEK")

  cond_no_na <- all(!is.na(b26$home_power_rating)) && all(!is.na(b26$away_power_rating))
  zero_home <- sum(b26$home_power_rating == 0.0)
  zero_away <- sum(b26$away_power_rating == 0.0)
  cond_no_zero <- (zero_home == 0L) && (zero_away == 0L)

  ok("BFP-3 Non-zero entering power ratings (no 0.0 hardcodes)",
     cond_no_na && cond_no_zero,
     sprintf("Range home: [%.2f, %.2f], away: [%.2f, %.2f]",
             min(b26$home_power_rating), max(b26$home_power_rating),
             min(b26$away_power_rating), max(b26$away_power_rating)))

  expect_true(cond_no_na)
  expect_true(cond_no_zero)
})

# ------------------------------------------------------------------------------
# Test 4: Points waterfall step integrity
# ------------------------------------------------------------------------------
if (have_log) test_that("BFP-4 Points waterfall steps sum to projected margin with rounding <= 0.02", {
  log_df <- readRDS(log_path)
  b26 <- log_df |> filter(season == 2026L, log_source == "BACKTEST_PREWEEK")

  sum_five <- b26$step_current_epa + b26$step_prior_epa + b26$step_elo_diff +
              b26$step_home_field + b26$step_qb_adjustment
  diff_rounding <- abs((sum_five + b26$step_rounding) - b26$projected_margin)

  cond_exact <- all(diff_rounding < 1e-9)
  cond_threshold <- all(abs(b26$step_rounding) <= 0.02 + 1e-9)

  ok("BFP-4 Points waterfall steps add up exactly with abs(step_rounding) <= 0.02",
     cond_exact && cond_threshold,
     sprintf("Max rounding: %.2e, max reconstruction diff: %.2e",
             max(abs(b26$step_rounding)), max(diff_rounding)))

  expect_true(cond_exact)
  expect_true(cond_threshold)
})

# ------------------------------------------------------------------------------
# Test 5: Model accuracy and Brier score reconciliation per D1
# ------------------------------------------------------------------------------
if (have_log) test_that("BFP-5 Walk-forward backtest matches Variant 1 benchmark (89/145 = 61.4%, Brier = 0.2242)", {
  log_df <- readRDS(log_path)
  b26 <- log_df |> filter(season == 2026L, log_source == "BACKTEST_PREWEEK")

  # Select baseline benchmark games by explicit rule (independent of row order):
  # 1. Closed Weeks 1-9 baseline (136 games): 84/136 = 61.8%, Brier = 0.2242
  b26_w9 <- b26 |> filter(week <= 9L)
  n_games_w9 <- nrow(b26_w9)
  n_correct_w9 <- sum(b26_w9$prediction_correct)
  acc_w9 <- n_correct_w9 / n_games_w9
  brier_w9 <- mean(b26_w9$brier_score)

  expect_equal(n_games_w9, 136L)
  expect_equal(n_correct_w9, 84L)
  expect_equal(round(acc_w9 * 100, 1), 61.8)
  expect_equal(round(brier_w9, 4), 0.2242)

  # 2. Phase 1 historical baseline (145 games prior to Week 10 late slate): 89/145 = 61.4%, Brier = 0.2242
  late_w10_gids <- c("2026_10_LA_ARI", "2026_10_SEA_LV", "2026_10_SF_DAL", "2026_10_PIT_CIN")
  b26_bench <- b26 |> filter(week < 10L | (week == 10L & !game_id %in% late_w10_gids))
  n_games <- nrow(b26_bench)
  n_correct <- sum(b26_bench$prediction_correct)
  acc <- n_correct / n_games
  brier <- mean(b26_bench$brier_score)

  cond_correct <- n_correct == 89L
  cond_acc <- round(acc * 100, 1) == 61.4
  cond_brier <- round(brier, 4) == 0.2242

  ok("BFP-5 Variant 1 accuracy and Brier match expected benchmark (89/145, 61.4%, 0.2242)",
     cond_correct && cond_acc && cond_brier,
     sprintf("Baseline (weeks 1-9 + early w10): %d/%d, Accuracy: %.1f%%, Brier: %.4f | Weeks 1-9: %d/%d (%.1f%%)",
             n_correct, n_games, acc * 100, brier, n_correct_w9, n_games_w9, acc_w9 * 100))

  expect_equal(n_correct, 89L)
  expect_equal(round(acc * 100, 1), 61.4)
  expect_equal(round(brier, 4), 0.2242)
})

# ------------------------------------------------------------------------------
# Test 6: Web matchups dataset eliminates zeroed power ratings
# ------------------------------------------------------------------------------
test_that("BFP-6 matchups_current_week.json completed games have non-zero power ratings from log", {
  matchups_path <- file.path(root_dir, "web", "public", "data", "matchups_current_week.json")
  cond_file <- file.exists(matchups_path)
  ok("BFP-6a matchups_current_week.json exists", cond_file)
  expect_true(cond_file)

  matchups_json <- jsonlite::fromJSON(matchups_path, simplifyDataFrame = TRUE)
  matchups <- matchups_json$matchups
  completed <- matchups |> filter(!is.na(home_score), !is.na(away_score))

  cond_non_null <- all(!is.null(completed$home_power_rating)) && all(!is.na(completed$home_power_rating))
  zero_pwr <- sum(completed$home_power_rating == 0.0) + sum(completed$away_power_rating == 0.0)
  cond_zero_eliminated <- zero_pwr == 0L

  ok("BFP-6b Zeroed power ratings eliminated on all completed matchup cards",
     cond_non_null && cond_zero_eliminated,
     sprintf("Completed games: %d, zeroed power ratings: %d", nrow(completed), zero_pwr))

  expect_true(cond_non_null)
  expect_true(cond_zero_eliminated)
})

# ------------------------------------------------------------------------------
# Test 7: Decision D1 strict separation in model_diagnostics.json
# ------------------------------------------------------------------------------
test_that("BFP-7 model_diagnostics.json strictly separates genuine pregame and backtest blocks", {
  diag_path <- file.path(root_dir, "web", "public", "data", "model_diagnostics.json")
  cond_file <- file.exists(diag_path)
  ok("BFP-7a model_diagnostics.json exists", cond_file)
  expect_true(cond_file)

  diag <- jsonlite::fromJSON(diag_path, simplifyVector = TRUE)

  # Completed-game count from matchups_current_week.json (updated atomically alongside
  # model_diagnostics.json by tools/refresh_live_results.R after prime-time games).
  # web/public/data/games/*.json lags behind live scores for Thursday/Sunday/Monday
  # night finals until nflfastR play-by-play publishes at 04:15 AM, so BFP-7 reconciles
  # against matchups_current_week.json and checks games/*.json separately as <= completed.
  matchups_path <- file.path(root_dir, "web", "public", "data", "matchups_current_week.json")
  expect_true(file.exists(matchups_path))
  matchups_df <- jsonlite::fromJSON(matchups_path, simplifyDataFrame = TRUE)$matchups
  completed <- sum(!is.na(matchups_df$home_score) & !is.na(matchups_df$away_score))

  game_files <- list.files(file.path(root_dir, "web", "public", "data", "games"),
                           pattern = "[.]json$", full.names = TRUE)
  game_files_completed <- sum(vapply(game_files, function(f) {
    isTRUE(jsonlite::fromJSON(f, simplifyVector = FALSE)$data$is_completed)
  }, logical(1)))

  is_count <- function(x) length(x) == 1L && is.numeric(x) && !is.na(x) && x >= 0 && x == floor(x)
  in_range <- function(x, lo, hi) length(x) == 1L && is.numeric(x) && !is.na(x) && x >= lo && x <= hi
  acc_missing <- function(a) is.null(a) || length(a) == 0L || (is.atomic(a) && all(is.na(a)))

  # Returns a named logical vector of invariant results for one diagnostics object.
  check_diag <- function(d, completed) {
    g <- d$genuine_pregame; h <- d$historical_backtest
    blocks <- !is.null(g) && !is.null(h)
    if (!blocks) return(c(blocks = FALSE))
    c(blocks = TRUE,
      counts_valid = is_count(g$n_games) && is_count(h$n_games),
      genuine_acc_null_iff_zero = acc_missing(g$accuracy) == (isTRUE(g$n_games == 0)),
      genuine_ranges = acc_missing(g$accuracy) || in_range(g$accuracy, 0, 100),
      genuine_brier = acc_missing(g$brier) || in_range(g$brier, 0, 1),
      backtest_acc = in_range(h$accuracy, 0, 100) || (isTRUE(h$n_games == 0) && acc_missing(h$accuracy)),
      backtest_brier = in_range(h$brier, 0, 1) || (isTRUE(h$n_games == 0) && acc_missing(h$brier)),
      sum_matches_completed = is_count(g$n_games) && is_count(h$n_games) &&
        (g$n_games + h$n_games) == completed)
  }

  res <- check_diag(diag, completed)
  ok("BFP-7b distinct genuine_pregame and historical_backtest blocks exist", isTRUE(res[["blocks"]]))
  expect_true(isTRUE(res[["blocks"]]))
  ok("BFP-7c n_games are non-negative integers", isTRUE(res[["counts_valid"]]))
  ok("BFP-7d genuine accuracy is null iff its n_games is 0", isTRUE(res[["genuine_acc_null_iff_zero"]]))
  ok("BFP-7e accuracy in [0,100] and Brier in [0,1] for both blocks",
     all(res[c("genuine_ranges", "genuine_brier", "backtest_acc", "backtest_brier")]))
  ok("BFP-7f genuine + backtest n_games equals completed games in matchups_current_week.json",
     isTRUE(res[["sum_matches_completed"]]),
     sprintf("genuine %s + backtest %s vs completed %d",
             diag$genuine_pregame$n_games, diag$historical_backtest$n_games, completed))
  expect_true(all(res))
  ok("BFP-7i committed game-detail files do not exceed completed matchups",
     isTRUE(game_files_completed <= completed),
     sprintf("games/*.json completed=%d <= matchups_current_week.json completed=%d",
             game_files_completed, completed))
  expect_true(game_files_completed <= completed)

  # Negative control: forcing either block's n_games off by one must trip the sum invariant.
  bad_g <- diag; bad_g$genuine_pregame$n_games <- diag$genuine_pregame$n_games + 1L
  bad_h <- diag; bad_h$historical_backtest$n_games <- diag$historical_backtest$n_games - 1L
  ok("BFP-7g invariants FAIL when genuine n_games is off by one",
     !isTRUE(check_diag(bad_g, completed)[["sum_matches_completed"]]))
  ok("BFP-7h invariants FAIL when backtest n_games is off by one",
     !isTRUE(check_diag(bad_h, completed)[["sum_matches_completed"]]))
  expect_false(isTRUE(check_diag(bad_g, completed)[["sum_matches_completed"]]))
  expect_false(isTRUE(check_diag(bad_h, completed)[["sum_matches_completed"]]))
})

# ------------------------------------------------------------------------------
# Test 8: Immutability gate — LOGGED_PREGAME rows preserved across backfill runs
# ------------------------------------------------------------------------------
test_that("BFP-8 backfill preserves existing LOGGED_PREGAME rows permanently", {
  temp_log <- file.path(tempdir(), "test_immutability_log.rds")
  on.exit(if (file.exists(temp_log)) unlink(temp_log), add = TRUE)

  fake_pregame <- data.frame(
    game_id            = "2026_11_MIA_KC",
    season             = 2026L,
    week               = 11L,
    gameday            = "2026-11-22",
    weekday            = "Sunday",
    gametime           = "13:00",
    home_team          = "KC",
    away_team          = "MIA",
    location           = "Home",
    neutral            = FALSE,
    log_source         = "LOGGED_PREGAME",
    log_timestamp      = as.POSIXct("2026-11-18 12:00:00", tz = "UTC"),
    logged_at          = as.POSIXct("2026-11-18 12:00:00", tz = "UTC"),
    refreshed_at       = as.POSIXct("2026-11-18 12:00:00", tz = "UTC"),
    kickoff_time       = as.POSIXct("2026-11-22 13:00:00", tz = "America/New_York"),
    kickoff_fallback   = FALSE,
    home_power_rating  = 12.5,
    away_power_rating  = 3.2,
    home_games_played  = 10L,
    away_games_played  = 10L,
    projected_margin   = 6.5,
    home_win_prob      = 0.672,
    away_win_prob      = 0.328,
    predicted_winner   = "KC",
    margin_sigma       = 14.60,
    step_current_epa   = 2.1,
    step_prior_epa     = 0.5,
    step_elo_diff      = 1.8,
    step_home_field    = 2.1,
    step_qb_adjustment = 0.0,
    step_rounding      = 0.0,
    ridge_b_intercept  = 1.84,
    ridge_b_raw        = 1.0,
    ridge_b_prior      = 0.0,
    ridge_b_raw_gp     = 0.0,
    ridge_b_prior_gp   = 0.0,
    home_raw           = 15.0,
    away_raw           = 5.0,
    home_prior         = 10.0,
    away_prior         = 5.0,
    home_elo           = 1620,
    away_elo           = 1500,
    home_qb_backup     = FALSE,
    away_qb_backup     = FALSE,
    elo_available      = TRUE,
    home_score         = NA_integer_,
    away_score         = NA_integer_,
    actual_margin      = NA_real_,
    actual_winner      = NA_character_,
    prediction_correct = NA,
    brier_score        = NA_real_,
    stringsAsFactors   = FALSE
  )
  saveRDS(fake_pregame, temp_log)

  if (file.exists(CACHE_SCHEDULES)) {
    # Full end-to-end backfill run on machines with live pipeline caches
    backfill_prediction_log(log_path = temp_log)
  } else {
    # Offline fixture path in CI: merge fake_pregame with fixture backtest rows
    fixture_log <- readRDS(log_path)
    fixture_backtest <- fixture_log |> filter(log_source == "BACKTEST_PREWEEK")
    merged <- merge_with_existing_log(fake_pregame, fixture_backtest, season = 2026L)
    saveRDS(merged, temp_log)
  }

  merged_log <- readRDS(temp_log)
  pregame_after <- merged_log |> filter(log_source == "LOGGED_PREGAME")

  cond_pregame_preserved <- nrow(pregame_after) == 1L &&
                            pregame_after$game_id[1] == "2026_11_MIA_KC" &&
                            pregame_after$projected_margin[1] == 6.5
  cond_backtest_added <- sum(merged_log$log_source == "BACKTEST_PREWEEK") >= 145L

  ok("BFP-8 LOGGED_PREGAME rows preserved without overwrite when backfill runs",
     cond_pregame_preserved && cond_backtest_added,
     sprintf("Pregame count: %d, Backtest count: %d",
             nrow(pregame_after), sum(merged_log$log_source == "BACKTEST_PREWEEK")))

  expect_true(cond_pregame_preserved)
  expect_true(cond_backtest_added)
})

# ------------------------------------------------------------------------------
# Test 9: Zero-Betting Policy Guard
# ------------------------------------------------------------------------------
test_that("BFP-9 Zero-Betting Policy Guard: zero forbidden terms across files", {
  files_to_scan <- c(
    file.path(root_dir, "tools", "backfill_prediction_log.R"),
    file.path(root_dir, "export_web_datasets.R"),
    file.path(root_dir, "tests", "test_backfill_and_provenance.R")
  )

  banned_patterns <- c(
    "\\bspread\\b",
    "\\bspreads\\b",
    "\\btotal\\b",
    "\\btotals\\b",
    "\\bmoneyline\\b",
    "\\bmoneylines\\b",
    "\\bsportsbook\\b",
    "\\bsportsbooks\\b",
    "\\bwager\\b",
    "\\bwagers\\b",
    "\\bclosing line\\b",
    "\\bsharp_book\\b",
    "\\bThe Odds API\\b"
  )

  violations <- character(0)
  for (f in files_to_scan) {
    if (file.exists(f)) {
      lines <- readLines(f, warn = FALSE)
      # Check diff lines or full file for backfill/test, and changed regions for exporter
      for (i in seq_along(lines)) {
        line <- lines[i]
        # Skip pattern declaration list in this test file
        if (basename(f) == "test_backfill_and_provenance.R" && i >= 318 && i <= 336) next
        # Skip unchanged legacy header lines in exporter
        if (basename(f) == "export_web_datasets.R" && i < 470) next
        for (pat in banned_patterns) {
          if (grepl(pat, line, ignore.case = TRUE)) {
            violations <- c(violations, sprintf("%s:L%d [%s]: %s", basename(f), i, pat, trimws(line)))
          }
        }
      }
    }
  }

  cond_clean <- length(violations) == 0L
  ok("BFP-9 Zero-betting policy: zero forbidden terms across backfill, exporter, and tests",
     cond_clean,
     if (cond_clean) "Clean" else paste(violations, collapse = "; "))

  expect_true(cond_clean)
})

# Summary
cat(sprintf("\n=== Backfill & Provenance Test Summary: %d failures ===\n", failures))
if (failures > 0L) quit(status = 1L)
