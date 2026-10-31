# ==============================================================================
# tools/offseason/test_spring_handoff.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Spring Handoff & Reactivation Test Suite
# Path: tools/offseason/test_spring_handoff.R
#
# Validates the dual-trigger spring training detection and reactivation system:
#   1. Condition 1 Franchise Code Guard:
#      - Verifies rejection of college exhibition teams (e.g. Northeastern Huskies,
#        Minnesota Golden Gophers) and non-MLB squads.
#      - Confirms hand-off only fires when BOTH teams are verified MLB franchise codes.
#   2. Condition 2 Calendar Ceiling & Lockout Guard:
#      - Verifies hand-off fires when calendar cutoff (2027-02-22) is reached under NORMAL status.
#      - STRICT LOCKOUT GUARD: Verifies hand-off does NOT fire when calendar cutoff is reached
#        if leagueOperatingStatus == 'TRANSACTION_FREEZE'.
#   3. Clean Archive Generation & Reactivation:
#      - Verifies clean archive dataset generation in web/public/data/archive/2026_2027_offseason.json.
#      - Verifies seasonStatus transitions to '2027_SPRING_TRAINING'.
#      - Verifies retrospective memo generation.
#
# Conforms to blueprint §§ 1, 7, 10, Issue #49, and Zero-Betting Policy.
# ==============================================================================

# GitHub issue #90: Project root resolution prelude.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("test_spring_handoff.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

source("tools/offseason/check_spring_training_trigger.R")
source("tools/offseason/reactivate_spring_training.R")

test_pass_count <- 0L
total_tests <- 0L

assert_true <- function(condition, test_name, detail = "") {
  total_tests <<- total_tests + 1L
  if (isTRUE(condition)) {
    test_pass_count <<- test_pass_count + 1L
    cat(sprintf("  [PASS] %s%s\n", test_name, if (nzchar(detail)) sprintf(" - %s", detail) else ""))
  } else {
    cat(sprintf("  [FAIL] %s - Condition FALSE. %s\n", test_name, detail))
    stop(sprintf("Assertion failed: %s", test_name))
  }
}

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Running MLB Spring Handoff & Reactivation Test Suite (Issue #49)\n")
  cat("=====================================================================\n\n")
  
  # ---------------------------------------------------------------------------
  # TEST GROUP 1: Franchise Code Guard on Spring Schedule Feed
  # ---------------------------------------------------------------------------
  cat("Test Group 1: Franchise Code Guard (Rejection of Non-MLB Exhibitions)...\n")
  
  # Synthetic game dataset containing:
  # Game A: College team (Northeastern Huskies, ID 343) vs Boston Red Sox (ID 111)
  # Game B: College team (Minnesota Golden Gophers, ID 4864) vs Minnesota Twins (ID 142)
  # Game C: Minor league team (Sacramento River Cats, ID 105) vs San Francisco Giants (ID 137)
  # Game D: Unconfirmed/WBC team vs New York Mets (ID 121)
  # Game E: Confirmed MLB vs MLB (NYY @ TOR, IDs 147 @ 141)
  college_and_exhibition_games <- list(
    list(
      game_date = "2027-02-20T18:05:00Z",
      teams_away_team_id = 343,
      teams_away_team_name = "Northeastern Huskies",
      away_team_code = "NEU",
      teams_home_team_id = 111,
      teams_home_team_name = "Boston Red Sox",
      home_team_code = "BOS",
      series_description = "Exhibition Game",
      game_type = "E"
    ),
    list(
      game_date = "2027-02-21T18:05:00Z",
      teams_away_team_id = 4864,
      teams_away_team_name = "Minnesota Golden Gophers",
      away_team_code = "MINN",
      teams_home_team_id = 142,
      teams_home_team_name = "Minnesota Twins",
      home_team_code = "MIN",
      series_description = "Exhibition Game",
      game_type = "E"
    ),
    list(
      game_date = "2027-02-21T19:05:00Z",
      teams_away_team_id = 105,
      teams_away_team_name = "Sacramento River Cats",
      away_team_code = "SAC",
      teams_home_team_id = 137,
      teams_home_team_name = "San Francisco Giants",
      home_team_code = "SF",
      series_description = "Exhibition Game",
      game_type = "E"
    )
  )
  
  # Sub-test 1.1: Only non-MLB games in schedule, before calendar cutoff date
  eval_non_mlb <- evaluate_spring_training_trigger(
    as_of_date = "2027-02-15",
    operating_status = "NORMAL",
    schedule_data = college_and_exhibition_games,
    calendar_cutoff = "2027-02-22"
  )
  
  assert_true(
    !eval_non_mlb$handoffTriggered,
    "Non-MLB college exhibition games do NOT trigger spring handoff",
    sprintf("Rejected %d games, 0 confirmed", eval_non_mlb$condition1$rejectedExhibitionGamesCount)
  )
  assert_true(
    eval_non_mlb$condition1$rejectedExhibitionGamesCount == 3L,
    "All 3 non-MLB exhibition games correctly filtered and categorized as rejected"
  )
  assert_true(
    eval_non_mlb$condition1$confirmedMlbSpringGamesCount == 0L,
    "0 non-MLB exhibition games confirmed as MLB franchise games"
  )
  assert_true(
    eval_non_mlb$verdict == "MAINTAIN_OFFSEASON_MONITOR",
    "Verdict correctly remains MAINTAIN_OFFSEASON_MONITOR"
  )
  
  # Sub-test 1.2: Adding a confirmed MLB vs MLB game satisfies Condition 1
  confirmed_mlb_games <- c(
    college_and_exhibition_games,
    list(
      list(
        game_date = "2027-02-22T18:05:00Z",
        teams_away_team_id = 147,
        teams_away_team_name = "New York Yankees",
        away_team_code = "NYY",
        teams_home_team_id = 141,
        teams_home_team_name = "Toronto Blue Jays",
        home_team_code = "TOR",
        series_description = "Spring Training",
        game_type = "S"
      )
    )
  )
  
  eval_with_mlb <- evaluate_spring_training_trigger(
    as_of_date = "2027-02-15",
    operating_status = "NORMAL",
    schedule_data = confirmed_mlb_games,
    calendar_cutoff = "2027-02-22"
  )
  
  assert_true(
    eval_with_mlb$handoffTriggered,
    "Confirmed MLB vs MLB game successfully satisfies Condition 1 trigger",
    sprintf("Confirmed: %d, Rejected: %d",
            eval_with_mlb$condition1$confirmedMlbSpringGamesCount,
            eval_with_mlb$condition1$rejectedExhibitionGamesCount)
  )
  assert_true(
    eval_with_mlb$condition1$confirmedMlbSpringGamesCount == 1L,
    "Exactly 1 MLB vs MLB game confirmed"
  )
  assert_true(
    eval_with_mlb$condition1$rejectedExhibitionGamesCount == 3L,
    "3 college/minor-league exhibition games kept in rejected queue"
  )
  
  # ---------------------------------------------------------------------------
  # TEST GROUP 2: Calendar Ceiling & Lockout Freeze Guard (Condition 2)
  # ---------------------------------------------------------------------------
  cat("\nTest Group 2: Calendar Ceiling & Lockout Guard (Condition 2)...\n")
  
  # Sub-test 2.1: Calendar cutoff reached with NORMAL operating status -> FIRES
  eval_cal_normal <- evaluate_spring_training_trigger(
    as_of_date = "2027-02-23",
    operating_status = "NORMAL",
    schedule_data = list(), # Empty schedule
    calendar_cutoff = "2027-02-22"
  )
  
  assert_true(
    eval_cal_normal$handoffTriggered,
    "Calendar cutoff date reached under NORMAL operating status triggers hand-off"
  )
  assert_true(
    eval_cal_normal$condition2$triggered,
    "Condition 2 marked as triggered under NORMAL status"
  )
  assert_true(
    eval_cal_normal$condition2$lockoutBlockActive == FALSE,
    "Lockout block inactive when status is NORMAL"
  )
  
  # Sub-test 2.2: Calendar cutoff reached with TRANSACTION_FREEZE (Lockout) -> BLOCKED
  eval_cal_lockout <- evaluate_spring_training_trigger(
    as_of_date = "2027-02-23",
    operating_status = "TRANSACTION_FREEZE",
    schedule_data = list(), # Empty schedule
    calendar_cutoff = "2027-02-22"
  )
  
  assert_true(
    !eval_cal_lockout$handoffTriggered,
    "STRICT LOCKOUT GUARD: Calendar cutoff does NOT trigger hand-off during TRANSACTION_FREEZE"
  )
  assert_true(
    !eval_cal_lockout$condition2$triggered,
    "Condition 2 correctly evaluates to FALSE during TRANSACTION_FREEZE"
  )
  assert_true(
    eval_cal_lockout$condition2$calendarCutoffReached == TRUE,
    "Calendar cutoff date recognized as reached"
  )
  assert_true(
    eval_cal_lockout$condition2$lockoutBlockActive == TRUE,
    "Lockout block explicitly flagged as active"
  )
  assert_true(
    grepl("Lockout calendar freeze in effect", eval_cal_lockout$reason),
    "Trigger reason explicitly states lockout freeze prevented hand-off"
  )
  
  # Sub-test 2.3: Lockout calendar freeze remains in effect even well past cutoff (e.g. March 10)
  eval_march_lockout <- evaluate_spring_training_trigger(
    as_of_date = "2027-03-10",
    operating_status = "TRANSACTION_FREEZE",
    schedule_data = list(),
    calendar_cutoff = "2027-02-22"
  )
  
  assert_true(
    !eval_march_lockout$handoffTriggered,
    "Lockout calendar freeze indefinitely suppresses calendar cutoff until labor resolution"
  )
  
  # ---------------------------------------------------------------------------
  # TEST GROUP 3: Clean Archive Generation & Reactivation Orchestrator
  # ---------------------------------------------------------------------------
  cat("\nTest Group 3: Archive Generation & Reactivation Orchestrator...\n")
  
  temp_archive_path <- file.path(PROJECT_DIR, "web", "public", "data", "archive", "test_2026_2027_offseason.json")
  temp_memo_path <- file.path(PROJECT_DIR, "cache", "test_retrospective_memo.md")
  on.exit({
    if (file.exists(temp_archive_path)) unlink(temp_archive_path)
    if (file.exists(temp_memo_path)) unlink(temp_memo_path)
  }, add = TRUE)
  
  # Sub-test 3.1: Dry run execution does not create files
  dry_run_res <- reactivate_spring_training(
    dry_run = TRUE,
    force = TRUE,
    archive_dest = temp_archive_path,
    memo_dest = temp_memo_path
  )
  
  assert_true(
    dry_run_res$status == "SUCCESS",
    "Reactivation orchestrator completes successfully in dry-run mode"
  )
  assert_true(
    !file.exists(temp_archive_path),
    "Dry run does NOT write archive file to disk"
  )
  
  # Sub-test 3.2: Real execution writes valid archive and retrospective memo
  real_res <- reactivate_spring_training(
    dry_run = FALSE,
    force = TRUE,
    archive_dest = temp_archive_path,
    memo_dest = temp_memo_path
  )
  
  assert_true(
    real_res$status == "SUCCESS",
    "Reactivation orchestrator executes cleanly in live mode"
  )
  assert_true(
    file.exists(temp_archive_path),
    "Archive file successfully created at target destination"
  )
  assert_true(
    file.exists(temp_memo_path),
    "Final retrospective memo successfully generated"
  )
  
  # Sub-test 3.3: Validate archive contents and schema compliance
  archive_data <- jsonlite::fromJSON(temp_archive_path, simplifyDataFrame = FALSE)
  assert_true(
    !is.null(archive_data$archiveMetadata),
    "Archive contains top-level archiveMetadata block"
  )
  assert_true(
    archive_data$archiveMetadata$seasonStatus == "2027_SPRING_TRAINING",
    "Archive metadata records target seasonStatus '2027_SPRING_TRAINING'"
  )
  assert_true(
    !is.null(archive_data$offseasonMonitor$editions),
    "Archive preserves all published offseason editions intact"
  )
  
  # Sub-test 3.4: Validate retrospective memo content
  memo_lines <- readLines(temp_memo_path)
  memo_full <- paste(memo_lines, collapse = "\n")
  assert_true(
    grepl("2026-2027 MLB Off-Season Retrospective", memo_full),
    "Retrospective memo contains proper executive title"
  )
  assert_true(
    grepl("2027_SPRING_TRAINING", memo_full),
    "Retrospective memo documents hand-off to 2027_SPRING_TRAINING"
  )
  assert_true(
    grepl("Condition 1", memo_full) && grepl("Condition 2", memo_full),
    "Retrospective memo documents dual-trigger compliance"
  )
  
  # Restore baseline file if altered by real run test
  baseline_path <- "cache/league_state_baseline.json"
  if (file.exists(baseline_path)) {
    b_data <- jsonlite::fromJSON(baseline_path, simplifyDataFrame = FALSE)
    b_data$seasonStatus <- "2026_WORLD_SERIES_CONCLUDED"
    b_data$asOf <- "2026-10-31T18:29:51Z"
    b_data$generatedBy <- "tools/offseason/capture_baseline_s0.R@d704af2"
    writeLines(jsonlite::toJSON(b_data, pretty = TRUE, auto_unbox = TRUE, null = "null"), baseline_path)
  }
  
  cat("\n=====================================================================\n")
  cat(sprintf(">>> SPRING HANDOFF TEST SUITE COMPLETE: %d/%d TESTS PASSED (100%%)\n",
              test_pass_count, total_tests))
  cat("=====================================================================\n")
}

if (sys.nframe() == 0L) {
  main()
}
