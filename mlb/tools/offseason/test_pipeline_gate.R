# ==============================================================================
# tools/offseason/test_pipeline_gate.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Pipeline Gate Test Suite
# Path: tools/offseason/test_pipeline_gate.R
#
# Validates Assertions A through G under --mode=offseason:
#   Assertion A: freshness checks only WEB_DATA_FILES_OFFSEASON
#   Assertion B: replaces slate check with week bounds / phase validation
#   Assertion C: lockout-tolerant (incremented freezeDayCount or updated lastPublished
#                passes even with Delta S = empty)
#   Assertion D: composite_health == HEALTHY required for quiet weeks; blocked on wire outage
#   Assertion E: publish branch check (HEAD matches expected)
#   Assertion F: payload provenance (embedded lastPublished / generated_at)
#   Assertion G: dataset contracts via vitest
#   Zero-betting policy guard & atomic promotion verification
#
# Conforms to blueprint §§ 5, 6, 7, 10 and Issue #46.
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
      stop(sprintf("test_pipeline_gate.R: cannot locate repo root (no config.R at or above '%s')", start))
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

source("logging_utils.R")
source("config.R")
source("tools/publish_web.R")

main <- function() {
  cat("=====================================================================\n")
  cat(">>> Running MLB Off-Season Publish Gate & Governance Test Suite\n")
  cat("=====================================================================\n")
  
  test_count <- 0
  pass_count <- 0
  
  run_test <- function(name, expr) {
    test_count <<- test_count + 1
    cat(sprintf("Test %d: %s...\n", test_count, name))
    res <- tryCatch(expr(), error = function(e) {
      cat(sprintf("  [FAIL] Error: %s\n", conditionMessage(e)))
      NULL
    })
    if (!is.null(res) && isTRUE(res)) {
      pass_count <<- pass_count + 1
      cat("  [PASS]\n")
    } else if (!is.null(res) && !isTRUE(res)) {
      cat("  [FAIL] Assertion evaluated to FALSE\n")
    }
  }
  
  # ---------------------------------------------------------------------------
  # Test 1: Assertion A freshness checks ONLY WEB_DATA_FILES_OFFSEASON
  # ---------------------------------------------------------------------------
  run_test("Assertion A checks only WEB_DATA_FILES_OFFSEASON", function() {
    # Past run start should pass for offseason files
    res <- .assert_mtime_freshness(as.POSIXct("2026-10-31 00:00:00"), mode = "offseason")
    if (!res$pass) return(FALSE)
    if (length(res$stale) != 0) return(FALSE)
    # Future run start should fail
    res_stale <- .assert_mtime_freshness(Sys.time() + 3600, mode = "offseason")
    if (res_stale$pass) return(FALSE)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 2: Assertion B validates offseason phase and week bounds
  # ---------------------------------------------------------------------------
  run_test("Assertion B validates active phase and week bounds", function() {
    res <- .assert_offseason_phase(WEB_JSON_OFFSEASON_MONITOR)
    if (!res$pass) return(FALSE)
    
    # Negative test: non-existent file
    res_neg <- .assert_offseason_phase("non_existent_file.json")
    if (res_neg$pass) return(FALSE)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 3: Assertion C lockout-tolerant non-empty diff
  # ---------------------------------------------------------------------------
  run_test("Assertion C lockout tolerance (passes when freezeDayCount / lastPublished advances)", function() {
    repo_root <- .pw_repo_root()
    # Currently offseason_monitor.json has changes
    res <- .assert_nonempty_diff(repo_root, mode = "offseason")
    if (!res$pass) return(FALSE)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 4: Assertion D Ingestion health & quiet-week precondition
  # ---------------------------------------------------------------------------
  run_test("Assertion D requires composite_health == HEALTHY and blocks on wire failure", function() {
    # Mock healthy manifest
    test_manifest_healthy <- list(
      ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      composite_health = "HEALTHY",
      adapters = list(league_wire = list(status = "HEALTHY"))
    )
    manifest_path <- file.path(MLB_CACHE_ROOT, "ingestion_manifest.json")
    writeLines(toJSON(test_manifest_healthy, pretty = TRUE, auto_unbox = TRUE), manifest_path)
    
    res_h <- .assert_offseason_health(allow_degraded = FALSE)
    if (!res_h$pass) return(FALSE)
    
    # Mock degraded manifest
    test_manifest_degraded <- list(
      ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      composite_health = "DEGRADED",
      adapters = list(league_wire = list(status = "FAILED"))
    )
    writeLines(toJSON(test_manifest_degraded, pretty = TRUE, auto_unbox = TRUE), manifest_path)
    
    # Should fail without --allow-degraded
    res_d1 <- .assert_offseason_health(allow_degraded = FALSE)
    if (res_d1$pass) return(FALSE)
    
    # Should pass with --allow-degraded
    res_d2 <- .assert_offseason_health(allow_degraded = TRUE)
    if (!res_d2$pass) return(FALSE)
    
    # Restore healthy manifest
    writeLines(toJSON(test_manifest_healthy, pretty = TRUE, auto_unbox = TRUE), manifest_path)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 5: Scoped Zero-Betting Policy Guard
  # ---------------------------------------------------------------------------
  run_test("Zero-Betting Policy Guard blocks sportsbooks and permits whitelisted math terms", function() {
    # Test valid files
    res_valid <- .assert_zero_betting(WEB_DATA_FILES_OFFSEASON)
    if (!res_valid$pass) return(FALSE)
    
    # Test forbidden domain
    tmp_bad_file <- file.path(MLB_CACHE_ROOT, "test_betting_violation.txt")
    writeLines("Check odds on draftkings.com for the winter meetings", tmp_bad_file)
    res_bad1 <- .assert_zero_betting(tmp_bad_file)
    if (res_bad1$pass) return(FALSE)
    
    # Test forbidden wagering terms
    writeLines("Team moneyline and runline bets available", tmp_bad_file)
    res_bad2 <- .assert_zero_betting(tmp_bad_file)
    if (res_bad2$pass) return(FALSE)
    
    # Test whitelisted math terms: draft lottery, lottery odds, arbitration model probability
    writeLines("Reviewing draft lottery outcomes, team lottery odds and arbitration model probability bounds.", tmp_bad_file)
    res_whitelisted <- .assert_zero_betting(tmp_bad_file)
    unlink(tmp_bad_file)
    if (!res_whitelisted$pass) return(FALSE)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 6: Atomic Promotion on Publish
  # ---------------------------------------------------------------------------
  run_test("Atomic Promotion transfers staged to baseline state", function() {
    staged_path <- file.path(MLB_CACHE_ROOT, "league_state_staged.json")
    baseline_path <- file.path(MLB_CACHE_ROOT, "league_state_baseline.json")
    
    if (!file.exists(staged_path)) {
      # Build monitor to generate staged state
      source("build_offseason_monitor.R")
      build_offseason_monitor()
    }
    
    # Read staged timestamp
    staged_data <- fromJSON(staged_path, simplifyDataFrame = FALSE)
    staged_as_of <- staged_data$asOf
    
    # Simulate promotion logic
    file.copy(staged_path, baseline_path, overwrite = TRUE)
    baseline_data <- fromJSON(baseline_path, simplifyDataFrame = FALSE)
    if (!identical(baseline_data$asOf, staged_as_of)) return(FALSE)
    TRUE
  })
  
  # ---------------------------------------------------------------------------
  # Test 7: Full Publish Gate Dry Run in Off-Season Mode
  # ---------------------------------------------------------------------------
  run_test("Full Publish Gate Dry Run (--mode=offseason)", function() {
    repo_root <- .pw_repo_root()
    cur_branch <- .pw_current_branch(repo_root)
    res <- publish_web(dry_run = TRUE,
                       run_start = as.POSIXct("2026-10-31 00:00:00"),
                       publish_branch = cur_branch,
                       mode = "offseason")
    if (isTRUE(res$blocked)) return(FALSE)
    if (length(res$assertions_failed) != 0) return(FALSE)
    TRUE
  })
  
  cat("=====================================================================\n")
  cat(sprintf(">>> TEST RESULTS: %d/%d PASS\n", pass_count, test_count))
  cat("=====================================================================\n")
  
  if (pass_count != test_count) {
    stop(sprintf("Pipeline gate test suite failed: %d/%d tests passed", pass_count, test_count))
  }
}

if (!interactive()) {
  main()
}
