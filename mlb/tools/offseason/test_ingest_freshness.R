# ==============================================================================
# test_ingest_freshness.R — Test Suite for Ingest Freshness & Volume Gate
# ==============================================================================
# Normative contract reference: docs/contracts/offseason_wire_items_contract.md §6
# Work unit: GitHub issue #59 (closes #59, refs #64)
#
# Table-driven test suite over the fault matrix for assert_ingest_freshness().
# PURITY: Runs in bare Rscript --vanilla with no external dependencies and no network.
# ==============================================================================

# Source the unit under test
source("tools/offseason/ingest_freshness.R")

test_count <- 0L
pass_count <- 0L
fail_count <- 0L

assert_test <- function(name, condition, detail = "") {
  test_count <<- test_count + 1L
  if (isTRUE(condition)) {
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
cat(">>> Starting Ingest Freshness & Volume Assertion Test Suite (Issue #59)\n")
cat("==============================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. Signature & Return Shape Contract (§6)
# ------------------------------------------------------------------------------
cat("--- Group 1: Contract §6 Signature & Return Shape ---\n")

valid_manifest <- list(
  ingest_timestamp = "2026-11-06T10:00:00Z",
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(
      status = "HEALTHY",
      items_found = 1401L
    )
  )
)

res1 <- assert_ingest_freshness(valid_manifest, now = "2026-11-06T12:00:00Z", max_age_hours = 26, allow_stale = FALSE)

assert_test(
  "Return object is a list with exactly the 4 declared fields",
  identical(sort(names(res1)), sort(c("status", "age_hours", "max_age_hours", "reason"))),
  sprintf("Names found: %s", paste(names(res1), collapse = ", "))
)

assert_test(
  "Fresh verdict returns status == 'FRESH'",
  identical(res1$status, "FRESH")
)

assert_test(
  "Fresh verdict echoes max_age_hours == 26",
  identical(res1$max_age_hours, 26)
)

assert_test(
  "Fresh verdict computes correct age (2.0 hours)",
  abs(res1$age_hours - 2.0) < 1e-6,
  sprintf("age_hours was %f, expected 2.0", res1$age_hours)
)

assert_test(
  "Fresh verdict reason contains status, age, and threshold",
  grepl("FRESH", res1$reason) && grepl("2\\.0h", res1$reason) && grepl("26\\.0h", res1$reason),
  sprintf("reason: %s", res1$reason)
)

# ------------------------------------------------------------------------------
# 2. Real Stale Manifest from Incident (2026-11-01T01:49:37Z)
# ------------------------------------------------------------------------------
cat("\n--- Group 2: Real Stale Manifest Frozen Incident Regression ---\n")

real_incident_manifest <- list(
  ingest_timestamp = "2026-11-01T01:49:37Z",
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(
      status = "HEALTHY",
      items_found = 276L
    )
  )
)

# Case A: Asserted against now = 2026-11-06 (must stop with allow_stale = FALSE)
stopped_on_nov6 <- FALSE
err_msg_nov6 <- ""
tryCatch(
  assert_ingest_freshness(real_incident_manifest, now = "2026-11-06", max_age_hours = 26, allow_stale = FALSE),
  error = function(e) {
    stopped_on_nov6 <<- TRUE
    err_msg_nov6 <<- conditionMessage(e)
  }
)

assert_test(
  "Real stale manifest stops on now = 2026-11-06 (allow_stale = FALSE)",
  stopped_on_nov6,
  sprintf("Error message: %s", err_msg_nov6)
)

# Case B: Asserted against now = 2026-11-07T04:49:37Z (exact 147h age) with allow_stale = TRUE
res_stale_147 <- assert_ingest_freshness(
  real_incident_manifest,
  now = "2026-11-07T04:49:37Z",
  max_age_hours = 26,
  allow_stale = TRUE
)

assert_test(
  "Real stale manifest returns status 'STALE' at 147h",
  identical(res_stale_147$status, "STALE")
)

assert_test(
  "Real stale manifest age is exactly 147.0h",
  abs(res_stale_147$age_hours - 147.0) < 1e-6,
  sprintf("age_hours was %f, expected 147.0", res_stale_147$age_hours)
)

assert_test(
  "Real stale manifest reason string names status, ~147h age, and 26h threshold",
  grepl("STALE", res_stale_147$reason) && grepl("147\\.0h", res_stale_147$reason) && grepl("26\\.0h", res_stale_147$reason),
  sprintf("reason: %s", res_stale_147$reason)
)

# Case C: Same manifest within 26h window (now = 2026-11-01T02:00:00Z -> ~10m after ingest)
res_fresh_same <- assert_ingest_freshness(
  real_incident_manifest,
  now = "2026-11-01T02:00:00Z",
  max_age_hours = 26,
  allow_stale = FALSE
)

assert_test(
  "Same manifest at now = 2026-11-01T02:00:00Z passes as FRESH",
  identical(res_fresh_same$status, "FRESH")
)

expected_age_10m <- (10 * 60 + 23) / 3600
assert_test(
  "Same manifest age at 02:00:00Z is ~0.17h",
  abs(res_fresh_same$age_hours - expected_age_10m) < 1e-4,
  sprintf("age_hours was %f, expected %f", res_fresh_same$age_hours, expected_age_10m)
)

# ------------------------------------------------------------------------------
# 3. Four Distinct Missing / Unparseable Blocks
# ------------------------------------------------------------------------------
cat("\n--- Group 3: Fail-Closed Ambiguity Blocks & Distinct Reasons ---\n")

# 1. NULL manifest
res_null <- assert_ingest_freshness(NULL, allow_stale = TRUE)
assert_test("NULL manifest returns status == 'MISSING'", identical(res_null$status, "MISSING"))
assert_test("NULL manifest age_hours is NA_real_", is.na(res_null$age_hours))

# 2. Missing ingest_timestamp
manifest_no_ts <- list(
  composite_health = "HEALTHY",
  adapters = list(league_wire = list(status = "HEALTHY", items_found = 10L))
)
res_no_ts <- assert_ingest_freshness(manifest_no_ts, allow_stale = TRUE)
assert_test("Missing ingest_timestamp returns status == 'MISSING'", identical(res_no_ts$status, "MISSING"))
assert_test("Missing ingest_timestamp age_hours is NA_real_", is.na(res_no_ts$age_hours))

# 3. Malformed / unparseable ingest_timestamp
manifest_bad_ts <- list(
  ingest_timestamp = "2026-11-01 01:49:37", # Missing 'T' and 'Z'
  composite_health = "HEALTHY",
  adapters = list(league_wire = list(status = "HEALTHY", items_found = 10L))
)
res_bad_ts <- assert_ingest_freshness(manifest_bad_ts, allow_stale = TRUE)
assert_test("Malformed ingest_timestamp returns status == 'MISSING'", identical(res_bad_ts$status, "MISSING"))
assert_test("Malformed ingest_timestamp age_hours is NA_real_", is.na(res_bad_ts$age_hours))

# 4. Missing composite_health
manifest_no_health <- list(
  ingest_timestamp = "2026-11-06T10:00:00Z",
  adapters = list(league_wire = list(status = "HEALTHY", items_found = 10L))
)
res_no_health <- assert_ingest_freshness(manifest_no_health, allow_stale = TRUE)
assert_test("Missing composite_health returns status == 'MISSING'", identical(res_no_health$status, "MISSING"))
assert_test("Missing composite_health age_hours is NA_real_", is.na(res_no_health$age_hours))

# Verify all four reasons are distinct
reasons_group3 <- c(res_null$reason, res_no_ts$reason, res_bad_ts$reason, res_no_health$reason)
assert_test(
  "All four missing/malformed reason strings are distinct",
  length(unique(reasons_group3)) == 4L,
  sprintf("Reasons:\n  1: %s\n  2: %s\n  3: %s\n  4: %s",
          res_null$reason, res_no_ts$reason, res_bad_ts$reason, res_no_health$reason)
)

# ------------------------------------------------------------------------------
# 4. Health State Governance (HEALTHY, DEGRADED, FAILED, Unknown)
# ------------------------------------------------------------------------------
cat("\n--- Group 4: Health States (HEALTHY, DEGRADED, FAILED, Unknown) ---\n")

base_manifest_fn <- function(health) {
  list(
    ingest_timestamp = "2026-11-06T10:00:00Z",
    composite_health = health,
    adapters = list(league_wire = list(status = "HEALTHY", items_found = 100L))
  )
}
test_now <- "2026-11-06T11:00:00Z"

# 1. HEALTHY
res_healthy <- assert_ingest_freshness(base_manifest_fn("HEALTHY"), now = test_now, allow_stale = FALSE)
assert_test("HEALTHY manifest passes and returns status == 'FRESH'", identical(res_healthy$status, "FRESH"))

# 2. DEGRADED
res_degraded <- assert_ingest_freshness(base_manifest_fn("DEGRADED"), now = test_now, allow_stale = TRUE)
assert_test("DEGRADED manifest returns status == 'DEGRADED'", identical(res_degraded$status, "DEGRADED"))
stopped_degraded <- FALSE
tryCatch(
  assert_ingest_freshness(base_manifest_fn("DEGRADED"), now = test_now, allow_stale = FALSE),
  error = function(e) stopped_degraded <<- TRUE
)
assert_test("DEGRADED manifest blocks when allow_stale = FALSE", stopped_degraded)

# 3. FAILED (closes the hole where FAILED passed)
res_failed <- assert_ingest_freshness(base_manifest_fn("FAILED"), now = test_now, allow_stale = TRUE)
assert_test("FAILED manifest returns status == 'FAILED'", identical(res_failed$status, "FAILED"))
stopped_failed <- FALSE
tryCatch(
  assert_ingest_freshness(base_manifest_fn("FAILED"), now = test_now, allow_stale = FALSE),
  error = function(e) stopped_failed <<- TRUE
)
assert_test("FAILED manifest blocks when allow_stale = FALSE", stopped_failed)

# 4. Unrecognised string
res_unknown <- assert_ingest_freshness(base_manifest_fn("CORRUPTED_FEED"), now = test_now, allow_stale = TRUE)
assert_test("Unknown health string returns status == 'FAILED'", identical(res_unknown$status, "FAILED"))
stopped_unknown <- FALSE
tryCatch(
  assert_ingest_freshness(base_manifest_fn("CORRUPTED_FEED"), now = test_now, allow_stale = FALSE),
  error = function(e) stopped_unknown <<- TRUE
)
assert_test("Unknown health string blocks when allow_stale = FALSE", stopped_unknown)

# ------------------------------------------------------------------------------
# 5. Volume Assertions (Zero Items vs Absent items_found)
# ------------------------------------------------------------------------------
cat("\n--- Group 5: Volume Assertions (Zero Volume vs Absent items_found) ---\n")

# Case A: Live manifest shape on disk (has adapters.league_wire, but NO items_found)
manifest_live_shape <- list(
  ingest_timestamp = "2026-11-07T01:40:33Z",
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(
      status = "HEALTHY"
    )
  )
)

res_absent_items <- assert_ingest_freshness(manifest_live_shape, now = "2026-11-07T02:40:33Z", allow_stale = TRUE)
assert_test("Absent items_found returns status == 'MISSING'", identical(res_absent_items$status, "MISSING"))
stopped_absent_items <- FALSE
tryCatch(
  assert_ingest_freshness(manifest_live_shape, now = "2026-11-07T02:40:33Z", allow_stale = FALSE),
  error = function(e) stopped_absent_items <<- TRUE
)
assert_test("Absent items_found blocks when allow_stale = FALSE", stopped_absent_items)

# Case B: items_found = 0 (silent wire outage masquerading as quiet week)
manifest_zero_items <- list(
  ingest_timestamp = "2026-11-07T01:40:33Z",
  composite_health = "HEALTHY",
  adapters = list(
    league_wire = list(
      status = "HEALTHY",
      items_found = 0L
    )
  )
)

res_zero_items <- assert_ingest_freshness(manifest_zero_items, now = "2026-11-07T02:40:33Z", allow_stale = TRUE)
assert_test("items_found = 0 returns status == 'FAILED'", identical(res_zero_items$status, "FAILED"))
stopped_zero_items <- FALSE
tryCatch(
  assert_ingest_freshness(manifest_zero_items, now = "2026-11-07T02:40:33Z", allow_stale = FALSE),
  error = function(e) stopped_zero_items <<- TRUE
)
assert_test("items_found = 0 blocks when allow_stale = FALSE", stopped_zero_items)

# Verify both reasons are distinct
assert_test(
  "Absent items_found and items_found = 0 have distinct reasons",
  !identical(res_absent_items$reason, res_zero_items$reason) &&
    grepl("missing required field 'items_found'", res_absent_items$reason) &&
    grepl("zero items found", res_zero_items$reason),
  sprintf("Absent: %s\nZero:   %s", res_absent_items$reason, res_zero_items$reason)
)

# ------------------------------------------------------------------------------
# 6. allow_stale = TRUE Operator Advisory Pass
# ------------------------------------------------------------------------------
cat("\n--- Group 6: allow_stale = TRUE Conversion to Loud Advisory Pass ---\n")

test_stale_manifest <- list(
  ingest_timestamp = "2026-11-01T00:00:00Z",
  composite_health = "HEALTHY",
  adapters = list(league_wire = list(status = "HEALTHY", items_found = 50L))
)
now_stale_eval <- "2026-11-05T00:00:00Z"

# 1. allow_stale = FALSE stops
stopped_eval <- FALSE
tryCatch(
  assert_ingest_freshness(test_stale_manifest, now = now_stale_eval, allow_stale = FALSE),
  error = function(e) stopped_eval <<- TRUE
)
assert_test("Stale manifest stops when allow_stale = FALSE", stopped_eval)

# 2. allow_stale = TRUE returns status with warning and no error
warned_eval <- FALSE
res_advisory <- withCallingHandlers(
  assert_ingest_freshness(test_stale_manifest, now = now_stale_eval, allow_stale = TRUE),
  warning = function(w) {
    warned_eval <<- TRUE
    invokeRestart("muffleWarning")
  }
)
assert_test("Stale manifest does NOT stop when allow_stale = TRUE", !is.null(res_advisory))
assert_test("allow_stale = TRUE issues an advisory warning", warned_eval)
assert_test("allow_stale = TRUE preserves status == 'STALE'", identical(res_advisory$status, "STALE"))
assert_test("allow_stale = TRUE preserves accurate reason", grepl("STALE", res_advisory$reason))

# ------------------------------------------------------------------------------
# 7. Strict UTC Parsing (No Local Timezone Pollution)
# ------------------------------------------------------------------------------
cat("\n--- Group 7: Strict UTC Timestamp Parsing ---\n")

utc_manifest <- list(
  ingest_timestamp = "2026-11-01T01:49:37Z",
  composite_health = "HEALTHY",
  adapters = list(league_wire = list(status = "HEALTHY", items_found = 10L))
)
# Fixed UTC time exactly 2.0 hours later
fixed_utc_now <- as.POSIXct(strptime("2026-11-01T03:49:37Z", format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), tz = "UTC")

res_utc <- assert_ingest_freshness(utc_manifest, now = fixed_utc_now, allow_stale = FALSE)

assert_test(
  "Age computation is exactly 2.0 hours in UTC",
  abs(res_utc$age_hours - 2.0) < 1e-6,
  sprintf("Expected 2.0, got %f (if off by local offset, machine timezone leaked)", res_utc$age_hours)
)

# ------------------------------------------------------------------------------
# 8. Matrix Fault Table
# ------------------------------------------------------------------------------
cat("\n--- Group 8: Comprehensive Fault Matrix ---\n")

fault_matrix <- list(
  list(
    label = "Non-list root (string)",
    manifest = "not a list",
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Non-list root (numeric integer)",
    manifest = 12345L,
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Empty character timestamp",
    manifest = list(ingest_timestamp = "", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = 5L))),
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Timestamp without trailing Z",
    manifest = list(ingest_timestamp = "2026-11-01T01:49:37", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = 5L))),
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Missing adapters list object",
    manifest = list(ingest_timestamp = "2026-11-06T10:00:00Z", composite_health = "HEALTHY"),
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Missing league_wire adapter object",
    manifest = list(ingest_timestamp = "2026-11-06T10:00:00Z", composite_health = "HEALTHY", adapters = list(beat_feeds = list(items_found = 5L))),
    expected_status = "MISSING",
    expected_stop = TRUE
  ),
  list(
    label = "Negative items_found",
    manifest = list(ingest_timestamp = "2026-11-06T10:00:00Z", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = -1L))),
    expected_status = "FAILED",
    expected_stop = TRUE
  ),
  list(
    label = "Non-numeric items_found",
    manifest = list(ingest_timestamp = "2026-11-06T10:00:00Z", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = "many"))),
    expected_status = "FAILED",
    expected_stop = TRUE
  ),
  list(
    label = "Age exactly at threshold (26.0h boundary passes)",
    manifest = list(ingest_timestamp = "2026-11-05T00:00:00Z", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = 10L))),
    now = "2026-11-06T02:00:00Z",
    max_age_hours = 26,
    expected_status = "FRESH",
    expected_stop = FALSE
  ),
  list(
    label = "Age 1 second past threshold (26.0003h fails as STALE)",
    manifest = list(ingest_timestamp = "2026-11-05T00:00:00Z", composite_health = "HEALTHY", adapters = list(league_wire = list(items_found = 10L))),
    now = "2026-11-06T02:00:01Z",
    max_age_hours = 26,
    expected_status = "STALE",
    expected_stop = TRUE
  )
)

for (row in fault_matrix) {
  test_now_row <- if (!is.null(row$now)) row$now else "2026-11-06T11:00:00Z"
  test_threshold <- if (!is.null(row$max_age_hours)) row$max_age_hours else 26

  # Test allow_stale = TRUE
  res_row <- suppressWarnings(assert_ingest_freshness(
    row$manifest,
    now = test_now_row,
    max_age_hours = test_threshold,
    allow_stale = TRUE
  ))

  assert_test(
    sprintf("Fault matrix '%s' returns status '%s'", row$label, row$expected_status),
    identical(res_row$status, row$expected_status),
    sprintf("Got %s, expected %s", res_row$status, row$expected_status)
  )

  # Test allow_stale = FALSE stops if expected_stop == TRUE
  stopped_row <- FALSE
  tryCatch(
    assert_ingest_freshness(
      row$manifest,
      now = test_now_row,
      max_age_hours = test_threshold,
      allow_stale = FALSE
    ),
    error = function(e) stopped_row <<- TRUE
  )

  assert_test(
    sprintf("Fault matrix '%s' stop behaviour matches expected (%s)", row$label, row$expected_stop),
    identical(stopped_row, row$expected_stop)
  )
}

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
cat("\n==============================================================================\n")
cat(sprintf("Test Suite Finished: %d / %d assertions passed (%d failed)\n",
            pass_count, test_count, fail_count))
cat("==============================================================================\n")

if (fail_count > 0L) {
  stop(sprintf("test_ingest_freshness.R FAILED: %d failures.", fail_count))
} else {
  cat("All tests PASSED successfully.\n")
}
