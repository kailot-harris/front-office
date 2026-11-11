# ==============================================================================
# tests/test_luxury_tax_schedule.R
# Path: tests/test_luxury_tax_schedule.R
#
# Regression coverage for #117 (NBA luxury tax brackets looked like the
# pre-2025-26 schedule):
#   1. compute_luxury_tax() no longer errors on an NA payroll -- it returns
#      NA_real_ instead.
#   2. compute_luxury_tax() rates/brackets are pinned against hand-computed
#      values from the verified 2023 CBA 2025-26-and-later schedule (standard
#      $1.00/$1.25/$3.50/$4.75 per dollar in brackets 1-4, repeater
#      $3.00/$3.25/$5.50/$6.75), at the tax threshold, +$3M, +$12M and +$25M,
#      for both standard and repeater teams.
#
# This test does NOT source build_cba_cap_dataset.R directly: that script is
# a run-everything top-level pipeline that writes the real published
# cba_cap_sheet.json / cache/cba_cap_sheet.rds as a side effect of being
# sourced, which would mutate published data as a side effect of running
# tests (explicitly out of scope for this fix). Instead this test parses the
# script's top-level expressions and evaluates only the ones that define the
# CBA threshold constants and compute_luxury_tax() itself, stopping before
# any data-loading or file-writing code runs.
#
# Usage: Rscript tests/test_luxury_tax_schedule.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "build_cba_cap_dataset.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "build_cba_cap_dataset.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

cat("=== Luxury Tax Schedule Test Suite (#117) ===\n")
cat(sprintf("Working root: %s\n", REPO_ROOT))

script_path <- file.path(REPO_ROOT, "build_cba_cap_dataset.R")
stopifnot(file.exists(script_path))

# Evaluate only the leading expressions of build_cba_cap_dataset.R (library
# loads, config.R, the CBA constant assignments, and the compute_luxury_tax
# function definition) in an isolated environment -- stop as soon as
# compute_luxury_tax has been defined, before any team/payroll data loading
# or JSON/RDS writing runs.
old_wd <- setwd(REPO_ROOT)
exprs <- parse(script_path)
sandbox <- new.env(parent = globalenv())
fn_defined <- FALSE
for (e in exprs) {
  eval(e, envir = sandbox)
  call_text <- paste(deparse(e), collapse = " ")
  if (grepl("^compute_luxury_tax\\s*<-\\s*function", call_text)) {
    fn_defined <- TRUE
    break
  }
}
setwd(old_wd)

stopifnot("compute_luxury_tax must be defined by the leading part of the script" = fn_defined)
stopifnot(exists("compute_luxury_tax", envir = sandbox, mode = "function"))
stopifnot(exists("LUXURY_TAX", envir = sandbox))

compute_luxury_tax <- get("compute_luxury_tax", envir = sandbox)
LUXURY_TAX <- get("LUXURY_TAX", envir = sandbox)

cat(sprintf("Luxury tax threshold loaded from script: $%.1fM\n", LUXURY_TAX))

# ------------------------------------------------------------------------------
# Test 1: NA payroll no longer errors
# ------------------------------------------------------------------------------
cat("\n[Test 1] NA payroll does not error...\n")
na_result <- tryCatch(compute_luxury_tax(NA_real_, is_repeater = FALSE), error = function(e) e)
stopifnot("compute_luxury_tax(NA) must not raise an error" = !inherits(na_result, "error"))
stopifnot("compute_luxury_tax(NA) must return NA_real_" = is.na(na_result))
na_result_rep <- tryCatch(compute_luxury_tax(NA_real_, is_repeater = TRUE), error = function(e) e)
stopifnot(!inherits(na_result_rep, "error"))
stopifnot(is.na(na_result_rep))
cat("  PASS: NA payroll returns NA_real_ for both standard and repeater teams.\n")

# ------------------------------------------------------------------------------
# Test 2: pinned values against hand-computed 2023 CBA 2025-26-and-later rates
#
# Standard rates (verified via Hoops Rumors CBA glossary, citing the CBA
# directly): $1.00 / $1.25 / $3.50 / $4.75 per dollar in brackets 1-4 (each
# bracket is $5M wide in this dataset's fixed-bracket implementation).
# Repeater rates: $3.00 / $3.25 / $5.50 / $6.75.
# Source: https://www.hoopsrumors.com/2024/11/hoops-rumors-glossary-luxury-tax-penalties-4.html
# ------------------------------------------------------------------------------
cat("\n[Test 2] Pinned tax bills at threshold, +$3M, +$12M, +$25M...\n")

std_rates <- c(1.00, 1.25, 3.50, 4.75, 5.25)
rep_rates <- c(3.00, 3.25, 5.50, 6.75, 7.25)

hand_computed_tax <- function(overage, rates) {
  if (overage <= 0) return(0)
  bill <- 0
  remaining <- overage
  bracket_width <- 5.0
  for (r in rates) {
    chunk <- min(remaining, bracket_width)
    if (chunk <= 0) break
    bill <- bill + chunk * r
    remaining <- remaining - chunk
  }
  round(bill, 1)
}

check_case <- function(label, overage, is_repeater) {
  rates <- if (is_repeater) rep_rates else std_rates
  expected <- hand_computed_tax(overage, rates)
  payroll <- LUXURY_TAX + overage
  actual <- compute_luxury_tax(payroll, is_repeater = is_repeater)
  cat(sprintf(
    "  %-28s payroll=$%.1fM repeater=%s expected=$%.1fM actual=$%.1fM\n",
    label, payroll, is_repeater, expected, actual
  ))
  stopifnot(isTRUE(all.equal(actual, expected)))
}

# At threshold: zero tax regardless of repeater status.
check_case("At threshold",      0,  FALSE)
check_case("At threshold (rep)", 0,  TRUE)
check_case("+$3M",              3,  FALSE)
check_case("+$3M (rep)",        3,  TRUE)
check_case("+$12M",             12, FALSE)
check_case("+$12M (rep)",       12, TRUE)
check_case("+$25M",             25, FALSE)
check_case("+$25M (rep)",       25, TRUE)

cat("  PASS: All pinned tax bills match hand-computed values.\n")


# ------------------------------------------------------------------------------
# Test 3 (#125): edge-case inputs must not crash -- NULL, NA, NaN, Inf
# payroll, an NA repeater flag, and vector payroll input.
# ------------------------------------------------------------------------------
cat("\n[Test 3] #125 edge cases do not crash (NULL/NA/NaN/Inf payroll, NA repeater, vectors)...\n")

run_safe <- function(label, expr) {
  result <- tryCatch(expr, error = function(e) e)
  cat(sprintf("  %-45s -> %s\n", label, paste(utils::capture.output(print(result)), collapse = " ")))
  if (inherits(result, "error")) {
    stop(sprintf("%s must not raise an error (got: %s)", label, conditionMessage(result)))
  }
  result
}

# NULL payroll: nothing to compute.
r_null <- run_safe("compute_luxury_tax(NULL)", compute_luxury_tax(NULL))
stopifnot("NULL payroll must return NA_real_" = length(r_null) == 1L && is.na(r_null))

# NA / NaN payroll (is.na() is TRUE for both in R).
r_na <- run_safe("compute_luxury_tax(NA_real_)", compute_luxury_tax(NA_real_))
stopifnot("NA payroll must return NA_real_" = is.na(r_na))
r_nan <- run_safe("compute_luxury_tax(NaN)", compute_luxury_tax(NaN))
stopifnot("NaN payroll must return NA_real_" = is.na(r_nan))

# Inf payroll: sensible (non-error, non-NaN) result -- infinite overage
# produces an infinite tax bill.
r_inf <- run_safe("compute_luxury_tax(Inf)", compute_luxury_tax(Inf))
stopifnot("Inf payroll must not be NA" = !is.na(r_inf))
stopifnot("Inf payroll must return Inf, not throw/NaN" = is.infinite(r_inf) && r_inf > 0)

# NA repeater flag: treated as FALSE (standard rate) with a warning, not an error.
na_rep_warnings <- character(0)
r_na_rep <- withCallingHandlers(
  run_safe("compute_luxury_tax(210, NA)", compute_luxury_tax(210, NA)),
  warning = function(w) {
    na_rep_warnings <<- c(na_rep_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
stopifnot("NA repeater flag must log a warning" = length(na_rep_warnings) >= 1L)
stopifnot(
  "NA repeater flag must be treated as FALSE (standard-rate bill)" =
    isTRUE(all.equal(r_na_rep, compute_luxury_tax(210, FALSE)))
)

# Vector payroll input (mix of valid, NA, NaN, Inf) -- must not error, and
# must match the scalar result element-by-element.
payroll_vec <- c(195, 205, NA_real_, NaN, Inf, 230)
r_vec <- run_safe("compute_luxury_tax(<vector>)", compute_luxury_tax(payroll_vec, is_repeater = FALSE))
stopifnot("vector payroll must return a value per element" = length(r_vec) == length(payroll_vec))
for (i in seq_along(payroll_vec)) {
  scalar_i <- compute_luxury_tax(payroll_vec[i], is_repeater = FALSE)
  if (is.na(payroll_vec[i])) {
    if (!is.na(r_vec[i])) stop(sprintf("vector element %d (NA/NaN) must be NA_real_", i))
  } else {
    if (!isTRUE(all.equal(r_vec[i], scalar_i))) {
      stop(sprintf("vector element %d must match the scalar result", i))
    }
  }
}

# Vector payroll with a vector (recycled) repeater flag.
r_vec_rep <- run_safe(
  "compute_luxury_tax(<vector>, <vector is_repeater>)",
  compute_luxury_tax(c(210, 215), is_repeater = c(FALSE, TRUE))
)
stopifnot("vector repeater flags must produce 2 results" = length(r_vec_rep) == 2L)
stopifnot(isTRUE(all.equal(r_vec_rep[1], compute_luxury_tax(210, FALSE))))
stopifnot(isTRUE(all.equal(r_vec_rep[2], compute_luxury_tax(215, TRUE))))

cat("  PASS: NULL/NA/NaN/Inf payroll, NA repeater flag, and vector input all handled without error.\n")

cat("\n=== ALL TESTS PASSED ===\n")
