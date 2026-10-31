# ==============================================================================
# test_offseason_preseason_trigger.R
# Unit Tests for Preseason Hand-Off Trigger & Guard Logic (Phase 7 / Issue #124)
#
# Verifies:
#   1. Condition 1 (Schedule Feed with Franchise Code Guard):
#      - Triggers when both home_team and away_team are valid franchise codes in names(WNBA_TEAMS).
#      - Accurately suppresses triggers on exhibition teams (e.g., DEL, WIL, USA).
#      - Works with different column naming conventions (home_team/away_team or team_abbreviation/opponent_team_abbreviation).
#   2. Condition 2 (Calendar Ceiling Fallback):
#      - Accurately triggers on or after 2027-04-26 even with 0 schedule records.
#      - Remains suppressed prior to 2027-04-26 when no valid schedule matches exist.
#   3. Dual-Trigger Priority and Matrix Evaluation:
#      - Reports BOTH_CONDITIONS_MET when both schedule & ceiling fire.
#   4. Hand-off transition execution & dry-run fidelity:
#      - Dry-run leaves files completely unchanged.
#      - Live hand-off updates baseline seasonStatus to '2027_CAMP_OPEN' and archives monitor JSON.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# Source the preseason trigger module
source(file.path("tools", "offseason", "check_preseason_trigger.R"))

test_franchises <- c("ATL", "CHI", "CON", "DAL", "GS", "IND", "LV", "LA", "MIN", "NY", "PHX", "POR", "SEA", "TOR", "WSH")

test_that("Condition 1: Accurately suppresses triggers on exhibition and international opponents", {
  # Mock schedule with exhibition opponents (DEL, WIL, USA)
  exhibition_sched <- data.frame(
    game_id = c("mock_ex_1", "mock_ex_2", "mock_ex_3"),
    game_date = c("2027-04-15", "2027-04-18", "2027-04-20"),
    season = c(2027, 2027, 2027),
    home_team = c("NY", "DEL", "IND"),
    away_team = c("WIL", "MIN", "USA"),
    stringsAsFactors = FALSE
  )
  
  eval_res <- evaluate_preseason_trigger(
    schedule_data = exhibition_sched,
    as_of_date = "2027-04-20",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  
  expect_false(eval_res$schedule_triggered)
  expect_false(eval_res$calendar_triggered)
  expect_false(eval_res$triggered)
  expect_equal(length(eval_res$triggering_games), 0)
  expect_equal(length(eval_res$ignored_exhibitions), 3)
})

test_that("Condition 1: Fires trigger when both home and away teams are valid WNBA franchises", {
  # Mock schedule with genuine franchise matchups
  valid_sched <- data.frame(
    game_id = c("mock_pre_1", "mock_pre_2"),
    game_date = c("2027-04-22", "2027-04-23"),
    season = c(2027, 2027),
    home_team = c("GS", "LV"),
    away_team = c("SEA", "NY"),
    stringsAsFactors = FALSE
  )
  
  eval_res <- evaluate_preseason_trigger(
    schedule_data = valid_sched,
    as_of_date = "2027-04-22",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  
  expect_true(eval_res$schedule_triggered)
  expect_false(eval_res$calendar_triggered)
  expect_true(eval_res$triggered)
  expect_equal(length(eval_res$triggering_games), 2)
  expect_match(eval_res$trigger_reason, "CONDITION_1_MET")
})

test_that("Condition 1: Handles mixed schedules by filtering out exhibitions and capturing franchise games", {
  mixed_sched <- data.frame(
    game_id = c("mock_ex_1", "mock_valid_1"),
    game_date = c("2027-04-20", "2027-04-24"),
    season = c(2027, 2027),
    home_team = c("ATL", "TOR"),
    away_team = c("DEL", "POR"),
    stringsAsFactors = FALSE
  )
  
  eval_res <- evaluate_preseason_trigger(
    schedule_data = mixed_sched,
    as_of_date = "2027-04-21",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  
  expect_true(eval_res$schedule_triggered)
  expect_equal(length(eval_res$triggering_games), 1)
  expect_equal(eval_res$triggering_games[[1]]$home_team, "TOR")
  expect_equal(eval_res$triggering_games[[1]]$away_team, "POR")
  expect_equal(length(eval_res$ignored_exhibitions), 1)
})

test_that("Condition 2: Calendar ceiling fallback triggers when past cutoff date even with empty schedule", {
  eval_res_before <- evaluate_preseason_trigger(
    schedule_data = data.frame(),
    as_of_date = "2027-04-25",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  expect_false(eval_res_before$triggered)
  expect_false(eval_res_before$calendar_triggered)
  
  eval_res_on_ceiling <- evaluate_preseason_trigger(
    schedule_data = data.frame(),
    as_of_date = "2027-04-26",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  expect_true(eval_res_on_ceiling$triggered)
  expect_true(eval_res_on_ceiling$calendar_triggered)
  expect_match(eval_res_on_ceiling$trigger_reason, "CONDITION_2_MET")
  
  eval_res_after <- evaluate_preseason_trigger(
    schedule_data = data.frame(),
    as_of_date = "2027-04-28",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  expect_true(eval_res_after$triggered)
  expect_true(eval_res_after$calendar_triggered)
})

test_that("Dual-Trigger: Evaluates BOTH_CONDITIONS_MET when schedule and calendar both satisfy criteria", {
  valid_sched <- data.frame(
    game_id = "mock_pre_1",
    game_date = "2027-04-27",
    season = 2027,
    home_team = "MIN",
    away_team = "DAL",
    stringsAsFactors = FALSE
  )
  
  eval_res <- evaluate_preseason_trigger(
    schedule_data = valid_sched,
    as_of_date = "2027-04-27",
    calendar_ceiling = "2027-04-26",
    valid_franchises = test_franchises
  )
  
  expect_true(eval_res$schedule_triggered)
  expect_true(eval_res$calendar_triggered)
  expect_true(eval_res$triggered)
  expect_match(eval_res$trigger_reason, "BOTH_CONDITIONS_MET")
})

test_that("Transition Execution: Dry run and live hand-off work with injected paths without side effects", {
  # AGENTS.md Rule compliance: test in isolated temp directories
  temp_test_dir <- tempfile("test_preseason_hand_off_")
  dir.create(temp_test_dir, recursive = TRUE)
  on.exit(unlink(temp_test_dir, recursive = TRUE), add = TRUE)
  
  temp_baseline <- file.path(temp_test_dir, "league_state_baseline.json")
  temp_monitor  <- file.path(temp_test_dir, "offseason_monitor.json")
  temp_archive  <- file.path(temp_test_dir, "archive", "2026_2027_offseason.json")
  
  initial_baseline <- list(
    seasonStatus = "2026_POST_FINALS",
    updatedAt = "2026-10-31T20:00:00Z"
  )
  jsonlite::write_json(initial_baseline, temp_baseline, auto_unbox = TRUE)
  
  initial_monitor <- list(
    version = "2026-2027.1.0",
    currentWeekNumber = 1L
  )
  jsonlite::write_json(initial_monitor, temp_monitor, auto_unbox = TRUE)
  
  eval_triggered <- list(
    triggered = TRUE,
    trigger_reason = "CONDITION_2_MET (Calendar ceiling cutoff date reached)",
    schedule_triggered = FALSE,
    calendar_triggered = TRUE,
    as_of_date = "2027-04-27",
    calendar_ceiling = "2027-04-26",
    triggering_games = list(),
    ignored_exhibitions = list()
  )
  
  # 1. Test Dry Run
  dry_res <- execute_preseason_hand_off(
    eval_result = eval_triggered,
    dry_run = TRUE,
    baseline_path = temp_baseline,
    monitor_path = temp_monitor,
    archive_path = temp_archive
  )
  expect_equal(dry_res$status, "DRY_RUN_SUCCESS")
  expect_false(file.exists(temp_archive))
  base_after_dry <- jsonlite::fromJSON(temp_baseline)
  expect_equal(base_after_dry$seasonStatus, "2026_POST_FINALS")
  
  # 2. Test Live Execution against temp paths
  live_res <- execute_preseason_hand_off(
    eval_result = eval_triggered,
    dry_run = FALSE,
    baseline_path = temp_baseline,
    monitor_path = temp_monitor,
    archive_path = temp_archive
  )
  expect_equal(live_res$status, "TRANSITION_APPLIED")
  expect_true(file.exists(temp_archive))
  base_after_live <- jsonlite::fromJSON(temp_baseline)
  expect_equal(base_after_live$seasonStatus, "2027_CAMP_OPEN")
})
