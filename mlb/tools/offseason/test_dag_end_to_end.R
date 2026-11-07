# ==============================================================================
# tools/offseason/test_dag_end_to_end.R
# MLB 2026-2027 Off-Season Dynamics Monitor: End-to-End DAG Regression Suite
# Path: tools/offseason/test_dag_end_to_end.R
#
# Work unit: GitHub issue #62 (refs #64, #55, #56, #57, #58, #59)
#
# RATIONALE & WHY THIS SUITE EXISTS
# ---------------------------------
# Prior to Tier 1 and 2, every unit test in the repository passed:
#   - test_ingestion_health.R: called ingest_all() in isolation
#   - test_regex_extraction.R: fed curated strings to extract_regex_from_text()
#   - test_reconciler.R: asserted dedup logic on pre-extracted deltas
#   - test_pipeline_gate.R: asserted gate on mock empty diffs
# All units were green, yet the pipeline published a FALSE QUIET WEEK for six
# consecutive days ("Quiet week: 0 confirmed state transitions recorded.")
# while 1,970 live transactions (including 543 free agency declarations) went
# unreconciled.
#
# The composition was broken: the DAG's ingest edge did not exist in
# build_offseason_monitor.R, which instead re-read the 6-record benchmark fixture
# (official_wire_raw_samples.json) frozen on 2026-10-29. Since those 6 deltas had
# already been promoted into the baseline on 2026-10-31, the reconciler
# correctly collapsed them to 0 confirmed events, publishing a false quiet week.
#
# REGRESSION PROOF AGAINST 97c7d7b (PRE-TIER-1 BASELINE):
# --------------------------------------------------------
# On commit 97c7d7b (and current main before Tier 1 merges):
#   - build_offseason_monitor.R never called ingest_all() and unconditionally read
#     data/fixtures/official_wire_raw_samples.json.
#   - Even when fresh wire items (data/fixtures/wire_items_sample.json) were present,
#     build_offseason_monitor.R ignored them completely.
#   - Against baseline S0 where those 6 deltas were applied, length(confirmed_events)
#     collapsed to 0 and stateOfPlay emitted:
#       "Quiet week: 0 confirmed state transitions recorded."
#   - The Cardinal Assertion (Test 1) strictly fails on 97c7d7b with:
#       "Assertion failure: expected > 0 confirmed_events, got 0"
#       "Assertion failure: stateOfPlay contains forbidden quiet week message"
#
# PURITY CONTRACT:
# ----------------
# 1. Pure and offline: executes in bare `Rscript --vanilla` with ZERO network calls.
# 2. Uses committed offline fixtures (data/fixtures/wire_items_sample.json,
#    data/fixtures/league_state_s0.json).
# 3. Executes in an isolated filesystem sandbox so production cache/ and web/
#    directories are NEVER clobbered or mutated.
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
      stop(sprintf("test_dag_end_to_end.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

# Ensure renv / user library path includes installed packages
if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

# Prevent CLI wrapper execution when sourcing DAG orchestrator
interactive <- function() TRUE

# Load DAG components
source("config.R")
source("tools/offseason/wire_items_schema.R")
source("tools/offseason/extract_regex.R")
source("tools/offseason/reconcile_state.R")
source("tools/offseason/render_memo.R")
source("tools/offseason/ingest_freshness.R")
source("build_offseason_monitor.R")

# Save global config paths for restoration
ORIGINAL_CACHE_ROOT <- MLB_CACHE_ROOT
ORIGINAL_WEB_DATA_DIR <- WEB_DATA_DIR

# Clean up sandbox and restore paths on exit
on.exit({
  MLB_CACHE_ROOT <<- ORIGINAL_CACHE_ROOT
  WEB_DATA_DIR <<- ORIGINAL_WEB_DATA_DIR
}, add = TRUE)

# Test counter state
test_count <- 0L
pass_count <- 0L
fail_count <- 0L
test_results_log <- list()
start_suite_time <- Sys.time()

assert_test <- function(name, condition, detail = "") {
  test_count <<- test_count + 1L
  passed <- isTRUE(condition)
  test_results_log[[length(test_results_log) + 1L]] <<- list(
    id = test_count,
    name = name,
    passed = passed,
    detail = detail
  )
  if (passed) {
    pass_count <<- pass_count + 1L
    cat(sprintf("  [PASS] Test %02d: %s\n", test_count, name))
    return(TRUE)
  } else {
    fail_count <<- fail_count + 1L
    cat(sprintf("  [FAIL] Test %02d: %s\n", test_count, name))
    if (nzchar(detail)) cat(sprintf("         Detail: %s\n", detail))
    return(FALSE)
  }
}

cat("==============================================================================\n")
cat(">>> Starting Off-Season Monitor End-to-End DAG Regression Suite (Issue #62)\n")
cat("==============================================================================\n\n")

# Verify committed offline fixtures exist
fixtures_s0_path <- file.path(PROJECT_DIR, "data", "fixtures", "league_state_s0.json")
fixtures_sample_path <- file.path(PROJECT_DIR, "data", "fixtures", "wire_items_sample.json")
stopifnot(file.exists(fixtures_s0_path))
stopifnot(file.exists(fixtures_sample_path))

# Helper to construct a fresh sandbox for each test case
create_test_sandbox <- function(test_id_str) {
  sandbox <- tempfile(pattern = sprintf("mlb_dag_%s_", test_id_str))
  s_cache <- file.path(sandbox, "cache")
  s_web <- file.path(sandbox, "web", "public", "data")
  dir.create(s_cache, recursive = TRUE, showWarnings = FALSE)
  dir.create(s_web, recursive = TRUE, showWarnings = FALSE)
  list(root = sandbox, cache = s_cache, web = s_web)
}

# ------------------------------------------------------------------------------
# Test 1: Cardinal Assertion — Non-Quiet Week Reportable
# ------------------------------------------------------------------------------
# Given a baseline at S0 (asOf: 2026-10-29T03:13:00Z) and wire items postdating it
# (data/fixtures/wire_items_sample.json), the full DAG must emit non-zero
# confirmed_events and must NOT emit quiet-week text.
# ------------------------------------------------------------------------------
cat("--- Test 1: Cardinal Assertion — Non-Quiet Week Reportable ---\n")
sb1 <- create_test_sandbox("cardinal")
file.copy(fixtures_s0_path, file.path(sb1$cache, "league_state_baseline.json"), overwrite = TRUE)
file.copy(fixtures_sample_path, file.path(sb1$cache, "offseason_wire_items.json"), overwrite = TRUE)

manifest1 <- list(
  ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 15L)
  )
)
jsonlite::write_json(manifest1, file.path(sb1$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
wire_sample1 <- jsonlite::fromJSON(file.path(sb1$cache, "offseason_wire_items.json"), simplifyVector = FALSE)

# Mock offline ingest_all to supply pre-validated fixtures without network
ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = wire_sample1,
    manifest = manifest1,
    can_assert_quiet_week = TRUE
  )
}

MLB_CACHE_ROOT <<- sb1$cache
WEB_DATA_DIR <<- sb1$web

res1 <- tryCatch({
  build_offseason_monitor(mock_date = "2026-10-31")
}, error = function(e) {
  cat(sprintf("ERROR in Test 1 build: %s\n", conditionMessage(e)))
  NULL
})

assert_test(
  "Cardinal: DAG execution succeeds and produces output dataset",
  !is.null(res1) && is.list(res1)
)

confirmed_count1 <- if (!is.null(res1)) length(res1$editions[[1]]$confirmedChanges) else 0L
assert_test(
  "Cardinal: Confirmed events count is non-zero (greater than 0)",
  confirmed_count1 > 0L,
  sprintf("Found %d confirmed events, expected > 0", confirmed_count1)
)

is_quiet1 <- if (!is.null(res1)) isTRUE(res1$editions[[1]]$isQuietWeek) else TRUE
assert_test(
  "Cardinal: isQuietWeek is FALSE",
  !is_quiet1,
  sprintf("isQuietWeek was %s, expected FALSE", is_quiet1)
)

sop1 <- if (!is.null(res1)) res1$editions[[1]]$stateOfPlay else ""
assert_test(
  "Cardinal: stateOfPlay does NOT emit 'Quiet week: 0 confirmed state transitions recorded.'",
  !grepl("Quiet week: 0 confirmed state transitions recorded", sop1, fixed = TRUE),
  sprintf("stateOfPlay: %s", sop1)
)

output_file1 <- file.path(sb1$web, "offseason_monitor.json")
staged_file1 <- file.path(sb1$cache, "league_state_staged.json")
assert_test(
  "Cardinal: Exported artifacts exist on disk (offseason_monitor.json and league_state_staged.json)",
  file.exists(output_file1) && file.exists(staged_file1)
)

# ------------------------------------------------------------------------------
# Test 2: Reachable Quiet-Week Assertion
# ------------------------------------------------------------------------------
# Given fresh, healthy, non-empty wire items whose events have already been
# reconciled into the baseline, the DAG must successfully report a genuine quiet week.
# ------------------------------------------------------------------------------
cat("\n--- Test 2: Reachable Quiet-Week Assertion ---\n")
sb2 <- create_test_sandbox("quiet")
# Promote staged state from Test 1 (where the wire items were already applied) to baseline
file.copy(staged_file1, file.path(sb2$cache, "league_state_baseline.json"), overwrite = TRUE)
file.copy(fixtures_sample_path, file.path(sb2$cache, "offseason_wire_items.json"), overwrite = TRUE)

manifest2 <- list(
  ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 15L)
  )
)
jsonlite::write_json(manifest2, file.path(sb2$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
wire_sample2 <- jsonlite::fromJSON(file.path(sb2$cache, "offseason_wire_items.json"), simplifyVector = FALSE)

ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = wire_sample2,
    manifest = manifest2,
    can_assert_quiet_week = TRUE
  )
}

MLB_CACHE_ROOT <<- sb2$cache
WEB_DATA_DIR <<- sb2$web

res2 <- tryCatch({
  build_offseason_monitor(mock_date = "2026-11-01", force_quiet = FALSE, fixture_mode = FALSE)
}, error = function(e) {
  cat(sprintf("ERROR in Test 2 build: %s\n", conditionMessage(e)))
  NULL
})

assert_test(
  "Reachable Quiet: DAG succeeds and does not block on genuine quiet week",
  !is.null(res2) && is.list(res2)
)

confirmed_count2 <- if (!is.null(res2)) length(res2$editions[[1]]$confirmedChanges) else -1L
assert_test(
  "Reachable Quiet: Confirmed events count is exactly 0",
  confirmed_count2 == 0L,
  sprintf("Found %d confirmed events, expected 0", confirmed_count2)
)

is_quiet2 <- if (!is.null(res2)) isTRUE(res2$editions[[1]]$isQuietWeek) else FALSE
assert_test(
  "Reachable Quiet: isQuietWeek is certified as TRUE",
  is_quiet2,
  sprintf("isQuietWeek was %s, expected TRUE", is_quiet2)
)

sop2 <- if (!is.null(res2)) res2$editions[[1]]$stateOfPlay else ""
assert_test(
  "Reachable Quiet: stateOfPlay contains 'Quiet week: 0 confirmed state transitions recorded.'",
  grepl("Quiet week: 0 confirmed state transitions recorded", sop2, fixed = TRUE),
  sprintf("stateOfPlay: %s", sop2)
)

# ------------------------------------------------------------------------------
# Test 3: Blind-Versus-Quiet Discrimination Assertion
# ------------------------------------------------------------------------------
# Zero fetched items is a fault / outage, never a quiet week. The build must block
# with a distinguishable error and never certify quiet week.
# ------------------------------------------------------------------------------
cat("\n--- Test 3: Blind-Versus-Quiet Discrimination Assertion ---\n")
sb3 <- create_test_sandbox("blind")
file.copy(fixtures_s0_path, file.path(sb3$cache, "league_state_baseline.json"), overwrite = TRUE)

manifest3 <- list(
  ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 0L)  # Zero fetched items!
  )
)
jsonlite::write_json(manifest3, file.path(sb3$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
jsonlite::write_json(list(), file.path(sb3$cache, "offseason_wire_items.json"), auto_unbox = TRUE)

ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = list(),
    manifest = manifest3,
    can_assert_quiet_week = FALSE
  )
}

MLB_CACHE_ROOT <<- sb3$cache
WEB_DATA_DIR <<- sb3$web

blocked3 <- FALSE
err_msg3 <- ""
tryCatch({
  build_offseason_monitor(mock_date = "2026-10-31")
}, error = function(e) {
  blocked3 <<- TRUE
  err_msg3 <<- conditionMessage(e)
})

assert_test(
  "Blind Discrimination: 0 fetched items blocks execution",
  blocked3,
  "Expected build_offseason_monitor to throw error on 0 items found"
)

assert_test(
  "Blind Discrimination: Error message identifies fault as zero items / BLIND RUN (distinguished from quiet week)",
  grepl("zero items found|BLIND RUN", err_msg3, ignore.case = TRUE),
  sprintf("Error message: %s", err_msg3)
)

# ------------------------------------------------------------------------------
# Test 4: Frozen-Incident Regression (2026-11-02 Incident)
# ------------------------------------------------------------------------------
# Stale manifest timestamp (2026-11-01T01:49:37Z) evaluated against 2026-11-06
# (age ~130h >> 26h threshold) must fail the gate, even with composite_health="HEALTHY".
# ------------------------------------------------------------------------------
cat("\n--- Test 4: Frozen-Incident Regression (2026-11-02 Incident) ---\n")
sb4 <- create_test_sandbox("frozen_incident")
file.copy(fixtures_s0_path, file.path(sb4$cache, "league_state_baseline.json"), overwrite = TRUE)
file.copy(fixtures_sample_path, file.path(sb4$cache, "offseason_wire_items.json"), overwrite = TRUE)

# The frozen manifest from the incident: certified HEALTHY but dated Nov 1
frozen_manifest <- list(
  ingest_timestamp = "2026-11-01T01:49:37Z",
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 276L)
  )
)
jsonlite::write_json(frozen_manifest, file.path(sb4$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
wire_sample4 <- jsonlite::fromJSON(file.path(sb4$cache, "offseason_wire_items.json"), simplifyVector = FALSE)

ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = wire_sample4,
    manifest = frozen_manifest,
    can_assert_quiet_week = TRUE
  )
}

MLB_CACHE_ROOT <<- sb4$cache
WEB_DATA_DIR <<- sb4$web

blocked4 <- FALSE
err_msg4 <- ""
tryCatch({
  # Evaluated at now = 2026-11-06 (the incident date)
  build_offseason_monitor(mock_date = "2026-11-06", allow_degraded = FALSE)
}, error = function(e) {
  blocked4 <<- TRUE
  err_msg4 <<- conditionMessage(e)
})

assert_test(
  "Frozen Incident: Stale manifest evaluated at 2026-11-06 halts the pipeline",
  blocked4,
  "Expected build_offseason_monitor to abort on stale manifest"
)

assert_test(
  "Frozen Incident: Abort reason identifies STALE manifest age violation",
  grepl("STALE", err_msg4, fixed = TRUE),
  sprintf("Error message: %s", err_msg4)
)

# ------------------------------------------------------------------------------
# Test 5: Fixture-as-Production-Feed Tripwire
# ------------------------------------------------------------------------------
# Asserts that a default build does NOT read data/fixtures/official_wire_raw_samples.json.
# If cache/offseason_wire_items.json is missing, a default build must fail closed
# rather than falling back to the benchmark fixture.
# ------------------------------------------------------------------------------
cat("\n--- Test 5: Fixture-as-Production-Feed Tripwire ---\n")
sb5 <- create_test_sandbox("fixture_tripwire")
file.copy(fixtures_s0_path, file.path(sb5$cache, "league_state_baseline.json"), overwrite = TRUE)

manifest5 <- list(
  ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 15L)
  )
)
jsonlite::write_json(manifest5, file.path(sb5$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
# Deliberately do NOT write offseason_wire_items.json to sb5$cache

ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = list(),
    manifest = manifest5,
    can_assert_quiet_week = TRUE
  )
}

MLB_CACHE_ROOT <<- sb5$cache
WEB_DATA_DIR <<- sb5$web

blocked5 <- FALSE
err_msg5 <- ""
tryCatch({
  # Default build without fixture_mode
  build_offseason_monitor(mock_date = "2026-10-31", fixture_mode = FALSE)
}, error = function(e) {
  blocked5 <<- TRUE
  err_msg5 <<- conditionMessage(e)
})

assert_test(
  "Fixture Tripwire: Default build does NOT fallback to official_wire_raw_samples.json",
  blocked5 && grepl("wire-items artifact missing", err_msg5, fixed = TRUE),
  sprintf("Error message: %s", err_msg5)
)

# ------------------------------------------------------------------------------
# Test 6: Staleness Tripwire Independent of Gate (Unvouched Ingest)
# ------------------------------------------------------------------------------
# A build where can_assert_quiet_week is FALSE and confirmed events collapse to 0
# cannot publish a quiet week (Rule: "A zero is a claim").
# ------------------------------------------------------------------------------
cat("\n--- Test 6: Staleness Tripwire Independent of Gate ---\n")
sb6 <- create_test_sandbox("unvouched")
file.copy(staged_file1, file.path(sb6$cache, "league_state_baseline.json"), overwrite = TRUE)
file.copy(fixtures_sample_path, file.path(sb6$cache, "offseason_wire_items.json"), overwrite = TRUE)

# Manifest is FRESH, but can_assert_quiet_week is FALSE
manifest6 <- list(
  ingest_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(status = "HEALTHY", items_found = 15L)
  )
)
jsonlite::write_json(manifest6, file.path(sb6$cache, "ingestion_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
wire_sample6 <- jsonlite::fromJSON(file.path(sb6$cache, "offseason_wire_items.json"), simplifyVector = FALSE)

ingest_all <<- function(allow_degraded = FALSE) {
  list(
    raw_items = list(),
    normalized_items = wire_sample6,
    manifest = manifest6,
    can_assert_quiet_week = FALSE  # Ingestion cannot vouch for zero transitions
  )
}

MLB_CACHE_ROOT <<- sb6$cache
WEB_DATA_DIR <<- sb6$web

blocked6 <- FALSE
err_msg6 <- ""
tryCatch({
  build_offseason_monitor(mock_date = "2026-11-01", force_quiet = FALSE, fixture_mode = FALSE)
}, error = function(e) {
  blocked6 <<- TRUE
  err_msg6 <<- conditionMessage(e)
})

assert_test(
  "Staleness Tripwire: Unvouched ingest collapsing to 0 events blocks publication",
  blocked6 && grepl("BLIND RUN -- 0 confirmed state transitions", err_msg6, fixed = TRUE),
  sprintf("Error message: %s", err_msg6)
)

# ------------------------------------------------------------------------------
# Write Markdown Summary to test-results/SUMMARY.md
# ------------------------------------------------------------------------------
suite_duration_sec <- as.numeric(difftime(Sys.time(), start_suite_time, units = "secs"))
results_dir <- file.path(PROJECT_DIR, "test-results")
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
summary_file <- file.path(results_dir, "SUMMARY.md")

md_lines <- c(
  "# Test suite summary",
  "",
  sprintf("Run at %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
  "Mode: offline end-to-end regression suite (GitHub issue #62)",
  "",
  "| Stage | Result | Passed | Known | New | Time |",
  "| --- | --- | --- | --- | --- | --- |",
  sprintf("| Offseason DAG End-to-End | %s | %d/%d | — | — | %.1fs |",
          if (fail_count == 0L) "pass" else "fail", pass_count, test_count, suite_duration_sec),
  "",
  "## Assertion Breakdown",
  ""
)

for (r in test_results_log) {
  md_lines <- c(md_lines, sprintf("- [%s] Test %02d: %s",
                                   if (r$passed) "x" else " ", r$id, r$name))
}

writeLines(md_lines, summary_file, useBytes = TRUE)
cat(sprintf("\nMarkdown summary written to %s\n", summary_file))

# ------------------------------------------------------------------------------
# Final Verdict
# ------------------------------------------------------------------------------
cat("==============================================================================\n")
cat(sprintf("Test Suite Finished: %d / %d assertions passed (%d failed) in %.2fs\n",
            pass_count, test_count, fail_count, suite_duration_sec))
cat("==============================================================================\n")

if (fail_count > 0L) {
  stop(sprintf("test_dag_end_to_end.R FAILED: %d assertion(s) failed.", fail_count))
} else {
  cat("All end-to-end DAG regression assertions PASSED successfully.\n")
}
