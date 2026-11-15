# ==============================================================================
# tests/test_prediction_log_provenance_v3.R
#
# Unit, migration, governance-isolation, formula-parity, and live-cache checks
# for Issue #123 (Tier 1a P2-a provenance standardization, P2-a2 schedule drag
# adjustment, and P2-b component/sigma snapshot).
#
# Standalone checks run completely on in-memory / tempdir() fixtures so CI runs
# without cache/ succeed cleanly. Live cache assertions run conditionally when
# cache/prediction_accuracy_log.rds is present.
#
# Usage: Rscript --vanilla tests/test_prediction_log_provenance_v3.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(tibble)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

near_eq <- function(a, b, tol = 1e-6) {
  !is.null(a) && !is.null(b) && is.numeric(a) && is.numeric(b) &&
    length(a) == 1L && length(b) == 1L && is.finite(a) && is.finite(b) &&
    abs(a - b) <= tol
}

section <- function(title) cat(sprintf("\n== %s ==\n", title))

SNAPSHOT_COLS <- c(
  "comp_bottom_up", "comp_rapm", "comp_shot_fatigue", "comp_embeddings",
  "comp_home_court", "comp_schedule", "sigma_game"
)

# ------------------------------------------------------------------------------
section("1. Isolated sourcing of logger, governance, and weekly projector")
# ------------------------------------------------------------------------------

old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA_character_)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
on.exit({
  if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
  else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
}, add = TRUE)

orig_wd <- getwd()
scratch_cwd <- tempfile("p3_cwd_")
dir.create(scratch_cwd, recursive = TRUE)
setwd(scratch_cwd)

logger_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "prediction_accuracy_logger.R"), local = logger_env)
ok("logger loads from scratch cwd without changing working directory",
   identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE),
             normalizePath(scratch_cwd, winslash = "/", mustWork = FALSE)))

gov_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "accuracy_governance.R"), local = gov_env)
ok("accuracy_governance.R loads with NBA_SKIP_STAGE_AUTORUN=1",
   is.function(gov_env$run_nba_accuracy_governance))

pwp_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "tools", "project_week_predictions.R"), local = pwp_env)
setwd(orig_wd)
unlink(scratch_cwd, recursive = TRUE)

ok("project_week_predictions.R loads fatigue engine as library",
   is.function(pwp_env$.pwp_compute_schedule_adjustments) &&
     is.function(pwp_env$.pwp_build_week_projections) &&
     is.function(pwp_env$calculate_travel_fatigue) &&
     isTRUE(pwp_env$FATIGUE_ENGINE_LIBRARY_ONLY))

# ------------------------------------------------------------------------------
section("2. P2-b snapshot schema & standardized provenance emitters")
# ------------------------------------------------------------------------------

empty_log <- logger_env$.empty_prediction_log()
ok(".empty_prediction_log() contains all 7 snapshot columns",
   all(SNAPSHOT_COLS %in% names(empty_log)))
ok(".empty_prediction_log() 7 snapshot columns all have typeof == 'double'",
   all(vapply(SNAPSHOT_COLS, function(k) typeof(empty_log[[k]]) == "double", logical(1))))

mock_slate <- tibble(
  game_id = "TEST_G1",
  game_date = as.Date("2026-11-20"),
  Matchup = "New York Knicks vs. Boston Celtics",
  Team = "Boston Celtics",
  Model_Win_Prob = 0.62
)
built <- logger_env$.build_slate_rows(mock_slate)
ok(".build_slate_rows() attaches LOGGED_PREGAME and all 7 double() snapshot columns",
   identical(built$log_source, "LOGGED_PREGAME") &&
     identical(built$home_team, "Celtics") &&
     identical(built$away_team, "Knicks") &&
     all(SNAPSHOT_COLS %in% names(built)) &&
     all(vapply(SNAPSHOT_COLS, function(k) typeof(built[[k]]) == "double", logical(1))))

seed_src <- paste(deparse(body(logger_env$seed_prediction_log)), collapse = "\n")
ok("seed_prediction_log() emits BACKTEST_SEEDED and never SEEDED_HINDSIGHT",
   grepl("BACKTEST_SEEDED", seed_src, fixed = TRUE) &&
     !grepl("SEEDED_HINDSIGHT", seed_src, fixed = TRUE))

bf_txt <- paste(readLines(file.path(REPO_ROOT, "tools", "backfill_week1_predictions.R"), warn = FALSE),
                collapse = "\n")
ok("backfill_week1_predictions.R explicitly emits log_source = 'BACKTEST_PREWEEK'",
   grepl('log_source\\s*=\\s*"BACKTEST_PREWEEK"', bf_txt, perl = TRUE))

# ------------------------------------------------------------------------------
section("3. P2-a classification and migrate_prediction_log_provenance_v3()")
# ------------------------------------------------------------------------------

ok(".classify_log_source() uses scheduled tip_time when present (same-day pre-tip -> LOGGED_PREGAME)",
   identical(logger_env$.classify_log_source(
     as.POSIXct("2026-10-24 09:00:00"),
     as.Date("2026-10-24"),
     tip_time = as.POSIXct("2026-10-24 19:30:00")
   ), "LOGGED_PREGAME"))

ok(".classify_log_source() classifies post-tip timestamp -> BACKTEST_SEEDED",
   identical(logger_env$.classify_log_source(
     as.POSIXct("2026-10-24 22:00:00"),
     as.Date("2026-10-24"),
     tip_time = as.POSIXct("2026-10-24 19:30:00")
   ), "BACKTEST_SEEDED"))

ok(".classify_log_source() fallback without tip_time fails closed on NA -> BACKTEST_SEEDED",
   identical(logger_env$.classify_log_source(as.POSIXct(NA), as.Date("2026-10-24")),
             "BACKTEST_SEEDED"))

# Synthetic migration covering every historical + 2026-27 cohort
synth_pre_mig <- tibble(
  game_id = c("BW1", "M1", "M2", "M3", "M4", "PR1", "LG1", "NA1"),
  game_date = as.Date(c(
    "2026-10-26", "2026-10-24", "2026-10-25", "2026-10-27", "2026-11-10",
    "2025-11-05", "2026-11-12", "2026-04-01"
  )),
  season = c(2026L, 2026L, 2026L, 2026L, 2026L, 2025L, 2026L, 2026L),
  home_team = c("Celtics", "Nuggets", "Heat", "Knicks", "Warriors", "Bucks", "Thunder", "Spurs"),
  away_team = c("Pistons", "Suns", "Magic", "Cavaliers", "Lakers", "Pacers", "Mavericks", "Rockets"),
  prediction_timestamp = as.POSIXct(c(
    "2026-10-18 00:44:01",
    "2026-10-24 08:15:00",
    "2026-10-25 08:30:00",
    "2026-10-27 09:00:00",
    "2026-11-10 08:00:00",
    "2026-04-20 12:00:00",
    "2026-11-11 08:00:00",
    NA
  )),
  predicted_home_win_prob = c(0.65, 0.70, 0.55, 0.60, 0.58, 0.61, 0.72, 0.52),
  .pred_Win = c(0.65, 0.70, 0.55, 0.60, 0.58, 0.61, 0.72, 0.52),
  predicted_winner = c("Celtics", "Nuggets", "Heat", "Knicks", "Warriors", "Bucks", "Thunder", "Spurs"),
  predicted_margin = c(4.1, 6.2, 1.5, 3.0, 2.4, 3.1, 7.0, 0.6),
  target_home_win = c("Win", "Win", "Loss", "Win", "Win", "Win", NA, "Loss"),
  actual_winner = c("Celtics", "Nuggets", "Magic", "Knicks", "Warriors", "Bucks", NA, "Rockets"),
  correct = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, NA, FALSE),
  brier_component = c(0.12, 0.09, 0.30, 0.16, 0.17, 0.15, NA, 0.27),
  log_loss_component = c(0.43, 0.36, 0.80, 0.51, 0.54, 0.49, NA, 0.73),
  status = c("RESOLVED", "RESOLVED", "RESOLVED", "RESOLVED", "RESOLVED", "RESOLVED", "PENDING", "RESOLVED"),
  resolved_timestamp = as.POSIXct(rep(NA, 8)),
  log_source = c(
    "LOGGED_PREGAME", "SEEDED_HINDSIGHT", "SEEDED_HINDSIGHT",
    "SEEDED_HINDSIGHT", "SEEDED_HINDSIGHT", "SEEDED_HINDSIGHT",
    "LOGGED_PREGAME", "SEEDED_HINDSIGHT"
  )
)

synth_mig <- logger_env$migrate_prediction_log_provenance_v3(synth_pre_mig, persist = FALSE)
ok("synthetic migration assigns exact v3 log_source values across all cohorts",
   identical(synth_mig$log_source, c(
     "BACKTEST_PREWEEK", "LOGGED_PREGAME", "LOGGED_PREGAME",
     "LOGGED_PREGAME", "LOGGED_PREGAME", "BACKTEST_SEEDED",
     "LOGGED_PREGAME", "BACKTEST_SEEDED"
   )))
ok("synthetic migration eliminates SEEDED_HINDSIGHT completely",
   !any(synth_mig$log_source == "SEEDED_HINDSIGHT", na.rm = TRUE))
ok("synthetic migration initializes all 7 double() snapshot columns to NA_real_",
   all(vapply(SNAPSHOT_COLS, function(k) {
     k %in% names(synth_mig) && typeof(synth_mig[[k]]) == "double" && all(is.na(synth_mig[[k]]))
   }, logical(1))))
shared_cols <- setdiff(names(synth_pre_mig), "log_source")
ok("synthetic migration preserves all existing predictions and outcomes untouched",
   identical(synth_pre_mig[, shared_cols, drop = FALSE], synth_mig[, shared_cols, drop = FALSE]))
ok("migrate_prediction_log_provenance_v3() is idempotent on second run",
   identical(logger_env$migrate_prediction_log_provenance_v3(synth_mig, persist = FALSE), synth_mig))

# ------------------------------------------------------------------------------
section("4. accuracy_governance.R BACKTEST_PREWEEK isolation & strict JSON keys")
# ------------------------------------------------------------------------------

mk_rows <- function(n, src, prob, home_wins, season = 2026L, status = "RESOLVED") {
  actual <- ifelse(seq_len(n) <= home_wins, "Celtics", "Heat")
  tibble(
    game_id = paste0(src, "_", seq_len(n)),
    game_date = as.Date("2026-10-25") + seq_len(n),
    season = season,
    home_team = rep("Celtics", n),
    away_team = rep("Heat", n),
    prediction_timestamp = as.POSIXct("2026-10-24 08:00:00"),
    predicted_home_win_prob = rep(prob, n),
    actual_winner = actual,
    status = rep(status, n),
    log_source = rep(src, n)
  )
}

gov_fixture <- bind_rows(
  mk_rows(10L, "LOGGED_PREGAME", 0.80, 8L, season = 2026L, status = "RESOLVED"),
  mk_rows(2L,  "LOGGED_PREGAME", 0.70, 1L, season = 2026L, status = "PENDING"),
  # Adversarial 0-of-5 wrong BACKTEST_PREWEEK at p=0.95: any leakage visibly shifts SU & Brier
  mk_rows(5L,  "BACKTEST_PREWEEK", 0.95, 0L, season = 2026L, status = "RESOLVED"),
  mk_rows(12L, "BACKTEST_SEEDED", 0.75, 9L, season = 2025L, status = "RESOLVED"),
  mk_rows(4L,  "SEEDED_HINDSIGHT", 0.75, 3L, season = 2025L, status = "RESOLVED")
)

gov_tmp_dir <- tempfile("gov_test_")
dir.create(gov_tmp_dir, recursive = TRUE)
gov_tmp_rds <- file.path(gov_tmp_dir, "accuracy_governance.rds")
gov_res <- gov_env$run_nba_accuracy_governance(
  log_df = gov_fixture,
  out_rds = gov_tmp_rds,
  web_data_dir = gov_tmp_dir,
  persist = TRUE
)
diag_json <- jsonlite::fromJSON(file.path(gov_tmp_dir, "projections_diagnostics.json"), simplifyVector = TRUE)

ok("governance headline counts LOGGED_PREGAME resolved only (10, excludes 5 BACKTEST_PREWEEK)",
   identical(as.integer(gov_res$total_games), 10L) &&
     near_eq(gov_res$su_accuracy, 0.80) &&
     identical(as.integer(diag_json$totalResolvedGames), 10L) &&
     identical(as.integer(diag_json$genuineForecast$totalGames), 10L))

ok("governance historical_backtest counts BACKTEST_SEEDED (+legacy) only (16, never merges BACKTEST_PREWEEK)",
   !is.null(gov_res$historical_backtest) &&
     identical(as.integer(gov_res$historical_backtest$total_games), 16L) &&
     near_eq(gov_res$historical_backtest$su_accuracy, 0.75) &&
     identical(as.integer(diag_json$historicalBacktest$totalGames), 16L))

expected_diag_keys <- c(
  "generated_at", "totalResolvedGames", "overallAccuracy", "brierScore",
  "brierSkillScore", "logLoss", "homeWinRate", "weightedCalibError",
  "calibrationStatus", "calibration", "accuracyDrift", "residualDistribution",
  "genuineForecast", "historicalBacktest", "rowCounts"
)
ok("diagnostics JSON preserves exact strict top-level and rowCounts keys",
   setequal(names(diag_json), expected_diag_keys) &&
     setequal(names(diag_json$rowCounts), c("resolvedTotal", "genuinePregame", "seededHindsight")) &&
     identical(as.integer(diag_json$rowCounts$resolvedTotal), 31L) &&
     identical(as.integer(diag_json$rowCounts$genuinePregame), 10L) &&
     identical(as.integer(diag_json$rowCounts$seededHindsight), 16L))

# Degenerate test: zero genuine rows must still never pull BACKTEST_PREWEEK into headline
no_gen_fixture <- filter(gov_fixture, log_source != "LOGGED_PREGAME")
gov_no_gen <- gov_env$run_nba_accuracy_governance(log_df = no_gen_fixture, persist = FALSE)
ok("governance falls back to BACKTEST_SEEDED and still isolates BACKTEST_PREWEEK when LOGGED_PREGAME == 0",
   identical(as.integer(gov_no_gen$total_games), 16L) &&
     near_eq(gov_no_gen$su_accuracy, 0.75))

unlink(gov_tmp_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
section("5. tools/project_week_predictions.R P2-a2 schedule drag & P2-b components")
# ------------------------------------------------------------------------------

synth_ratings <- list(
  rating = c(Warriors = 3.20, Nuggets = 4.60, Lakers = 1.40,
             GSW = 3.20, DEN = 4.60, LAL = 1.40),
  sd = c(Warriors = 1.10, Nuggets = 0.80, Lakers = 1.50,
         GSW = 1.10, DEN = 0.80, LAL = 1.50),
  bottom_up = c(Warriors = 3.00, Nuggets = 5.00, Lakers = 1.00,
                GSW = 3.00, DEN = 5.00, LAL = 1.00),
  rapm = c(Warriors = 4.00, Nuggets = 4.50, Lakers = 2.00,
           GSW = 4.00, DEN = 4.50, LAL = 2.00),
  shot_fatigue = c(Warriors = 2.50, Nuggets = 4.00, Lakers = 1.50,
                   GSW = 2.50, DEN = 4.00, LAL = 1.50),
  embeddings = c(Warriors = 3.25, Nuggets = 4.63, Lakers = 1.25,
                 GSW = 3.25, DEN = 4.63, LAL = 1.25),
  abbr = c(Warriors = "GSW", Nuggets = "DEN", Lakers = "LAL",
           GSW = "GSW", DEN = "DEN", LAL = "LAL"),
  n = 3L
)

# Full season spine: Day 0 Lakers @ Warriors; Day 1 Lakers @ Nuggets (eastward B2B at Denver altitude)
synth_spine <- tibble(
  game_id = c("S1", "S2"),
  game_date = as.Date(c("2026-10-20", "2026-10-21")),
  home_short_display_name = c("Warriors", "Nuggets"),
  away_short_display_name = c("Lakers", "Lakers")
)
wk_target <- synth_spine[2, , drop = FALSE]

sched_out <- pwp_env$.pwp_compute_schedule_adjustments(synth_spine, abbr_lookup = synth_ratings$abbr)
expected_away_drag <- as.numeric(
  pwp_env$calculate_travel_fatigue("DEN", "GSW", days_rest = 0L, is_back_to_back = TRUE)$fatigue_drag_pts
)
ok("schedule drag for opener game S1 is 0",
   near_eq(sched_out$schedule_adjustment[sched_out$game_id == "S1"], 0, tol = 1e-8))
ok("schedule drag for S2 uses full-spine prior appearance (B2B + DEN altitude + GSW->DEN flight)",
   expected_away_drag > 4.0 &&
     near_eq(sched_out$away_fatigue_drag[sched_out$game_id == "S2"], expected_away_drag, tol = 1e-8) &&
     near_eq(sched_out$home_fatigue_drag[sched_out$game_id == "S2"], 0, tol = 1e-8) &&
     near_eq(sched_out$schedule_adjustment[sched_out$game_id == "S2"], round(expected_away_drag, 2), tol = 1e-8))

ts_fixed <- as.POSIXct("2026-10-20 08:00:00")
proj <- pwp_env$.pwp_build_week_projections(wk_target, synth_spine, synth_ratings,
                                            prediction_timestamp = ts_fixed)

exp_bu    <- round(0.35 * (5.00 - 1.00), 4)
exp_rapm  <- round(0.25 * (4.50 - 2.00), 4)
exp_sf    <- round(0.20 * (4.00 - 1.50), 4)
exp_emb   <- round(0.20 * (4.63 - 1.25), 4)
exp_hca   <- 2.40
exp_sched <- round(expected_away_drag, 2)
exp_sigma <- round(sqrt(11.8^2 + 0.80^2 + 1.50^2), 4)
exp_margin_raw <- (4.60 - 1.40) + exp_hca + exp_sched
exp_sigma_raw  <- sqrt(11.8^2 + 0.80^2 + 1.50^2)
exp_prob <- round(pnorm(exp_margin_raw / exp_sigma_raw), 4)

ok("projector emits LOGGED_PREGAME and exact P2-a2/P2-b component & sigma values",
   identical(proj$log_source, "LOGGED_PREGAME") &&
     near_eq(proj$comp_bottom_up, exp_bu, tol = 1e-8) &&
     near_eq(proj$comp_rapm, exp_rapm, tol = 1e-8) &&
     near_eq(proj$comp_shot_fatigue, exp_sf, tol = 1e-8) &&
     near_eq(proj$comp_embeddings, exp_emb, tol = 1e-8) &&
     near_eq(proj$comp_home_court, exp_hca, tol = 1e-8) &&
     near_eq(proj$comp_schedule, exp_sched, tol = 1e-8) &&
     near_eq(proj$sigma_game, exp_sigma, tol = 1e-8) &&
     near_eq(proj$predicted_margin, round(exp_margin_raw, 2), tol = 1e-8) &&
     near_eq(proj$predicted_home_win_prob, exp_prob, tol = 1e-8))

comp_sum <- proj$comp_bottom_up + proj$comp_rapm + proj$comp_shot_fatigue +
  proj$comp_embeddings + proj$comp_home_court + proj$comp_schedule
ok("component snapshot decomposes predicted_margin within rounding tolerance (<= 0.02)",
   abs(comp_sum - proj$predicted_margin) <= 0.02)

# ------------------------------------------------------------------------------
section("6. Live cache verification (conditional on cache/ presence)")
# ------------------------------------------------------------------------------

live_log_path <- file.path(REPO_ROOT, "cache", "prediction_accuracy_log.rds")
if (file.exists(live_log_path)) {
  live_log <- readRDS(live_log_path)
  s27 <- as.Date(live_log$game_date) >= as.Date("2026-10-20")
  src_27 <- live_log$log_source[s27]
  src_prior <- live_log$log_source[!s27]

  ok("live cache/prediction_accuracy_log.rds has 2850 total rows",
     nrow(live_log) == 2850L)
  ok("live log has 0 SEEDED_HINDSIGHT rows anywhere",
     sum(live_log$log_source == "SEEDED_HINDSIGHT", na.rm = TRUE) == 0L)
  ok("live 2026-27 log has 210 LOGGED_PREGAME, 9 BACKTEST_PREWEEK, 0 BACKTEST_SEEDED",
     sum(src_27 == "LOGGED_PREGAME", na.rm = TRUE) == 210L &&
       sum(src_27 == "BACKTEST_PREWEEK", na.rm = TRUE) == 9L &&
       sum(src_27 == "BACKTEST_SEEDED", na.rm = TRUE) == 0L)
  ok("live prior-season log has 2631 BACKTEST_SEEDED rows",
     sum(src_prior == "BACKTEST_SEEDED", na.rm = TRUE) == 2631L &&
       length(src_prior) == 2631L)
  ok("live log includes all 7 snapshot columns as typeof == 'double'",
     all(vapply(SNAPSHOT_COLS, function(k) {
       k %in% names(live_log) && typeof(live_log[[k]]) == "double"
     }, logical(1))))

  live_gov <- readRDS(file.path(REPO_ROOT, "cache", "accuracy_governance.rds"))
  live_diag <- jsonlite::fromJSON(file.path(REPO_ROOT, "web", "public", "data", "projections_diagnostics.json"),
                                  simplifyVector = TRUE)
  ok("live accuracy_governance.rds & projections_diagnostics.json isolate BACKTEST_PREWEEK (179 genuine, 2631 backtest, 2819 resolvedTotal)",
     identical(as.integer(live_gov$total_games), 179L) &&
       identical(as.integer(live_gov$historical_backtest$total_games), 2631L) &&
       identical(as.integer(live_diag$totalResolvedGames), 179L) &&
       identical(as.integer(live_diag$historicalBacktest$totalGames), 2631L) &&
       identical(as.integer(live_diag$rowCounts$resolvedTotal), 2819L) &&
       identical(as.integer(live_diag$rowCounts$genuinePregame), 179L) &&
       identical(as.integer(live_diag$rowCounts$seededHindsight), 2631L))
  ok("live diagnostics buckets reconcile identically to headline and historical totals",
     identical(sum(live_diag$calibration$count), 179L) &&
       identical(sum(live_diag$accuracyDrift$games), 179L) &&
       identical(sum(live_diag$residualDistribution$count), 179L) &&
       identical(sum(live_diag$historicalBacktest$calibration$count), 2631L) &&
       identical(sum(live_diag$historicalBacktest$accuracyDrift$games), 2631L) &&
       identical(sum(live_diag$historicalBacktest$residualDistribution$count), 2631L))
} else {
  cat("  SKIP  cache/prediction_accuracy_log.rds absent (e.g. CI fresh checkout); standalone checks cover contracts.\n")
}

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
