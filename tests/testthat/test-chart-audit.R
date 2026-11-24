# ==============================================================================
# tests/testthat/test-chart-audit.R
#
# Tests for front-office#139 MLB chart script audit fixes:
#   - tools/gif_payroll_efficiency_bubble.R (real CBT payroll JSON, no imputed WAR/payroll, no hardcoded ROI teams)
#   - tools/gif_trade_deadline_splits.R (season-derived deadline_date default)
#   - tools/gif_baserunning_diamond.R (no synthetic 75% SB% fallback)
# ==============================================================================

.chart_audit_root <- function() {
  if (file.exists("config.R")) return(".")
  if (file.exists("../../config.R")) return(normalizePath("../..", winslash = "/"))
  Sys.getenv("MLB_PROJECT_DIR", unset = ".")
}

testthat::test_that("gif_payroll_efficiency_bubble.R has no hardcoded payroll table or synthetic fallbacks", {
  path <- file.path(.chart_audit_root(), "tools/gif_payroll_efficiency_bubble.R")
  src <- paste(readLines(path, warn = FALSE), collapse = "\n")

  testthat::expect_false(grepl("TEAM_PAYROLL_2026", src, fixed = TRUE))
  testthat::expect_false(grepl("MIL, TB, CLE", src, fixed = TRUE))
  testthat::expect_false(grepl("coalesce\\(payroll,\\s*150", src, perl = TRUE))
  testthat::expect_false(grepl("coalesce\\(total_war,\\s*35", src, perl = TRUE))
  testthat::expect_false(grepl("total_war\\s*=\\s*35", src, perl = TRUE))
  testthat::expect_true(grepl("viz_stop_no_data", src, fixed = TRUE))
  testthat::expect_true(grepl("cbt_payroll_sheet\\.json", src, perl = TRUE))
})

testthat::test_that("load_cbt_payroll reads real 2026 payrolls and refuses missing data via viz_stop_no_data", {
  root <- .chart_audit_root()
  source(file.path(root, "config.R"))
  source(file.path(root, "tools/viz_common.R"))

  # Extract load_cbt_payroll without requiring mlbplotR at test time
  exprs <- parse(file.path(root, "tools/gif_payroll_efficiency_bubble.R"))
  env <- new.env(parent = globalenv())
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        identical(e[[2]], as.name("load_cbt_payroll"))) {
      eval(e, envir = env)
    }
  }
  testthat::expect_true(is.function(env$load_cbt_payroll))

  payroll_json <- file.path(root, "web/public/data/cbt_payroll_sheet.json")
  df <- env$load_cbt_payroll(2026, payroll_file = payroll_json)
  testthat::expect_equal(nrow(df), 30L)
  testthat::expect_true(all(c("payroll_abbr", "payroll") %in% names(df)))
  testthat::expect_true(all(is.finite(df$payroll) & df$payroll > 0))

  testthat::expect_error(
    env$load_cbt_payroll(2026, payroll_file = tempfile(fileext = ".json")),
    "\\[SKIP-NO-DATA\\]"
  )
  testthat::expect_error(
    env$load_cbt_payroll(1999, payroll_file = payroll_json),
    "\\[SKIP-NO-DATA\\]"
  )
})

testthat::test_that("gif_trade_deadline_splits.R derives deadline_date from season", {
  path <- file.path(.chart_audit_root(), "tools/gif_trade_deadline_splits.R")
  src <- paste(readLines(path, warn = FALSE), collapse = "\n")

  testthat::expect_false(grepl('deadline_date\\s*=\\s*"2026-08-01"', src, perl = TRUE))
  testthat::expect_true(grepl('deadline_date\\s*=\\s*sprintf\\("%d-08-01",\\s*season\\)', src, perl = TRUE))
})

testthat::test_that("gif_baserunning_diamond.R does not impute 75% SB rate on zero attempts", {
  path <- file.path(.chart_audit_root(), "tools/gif_baserunning_diamond.R")
  src <- paste(readLines(path, warn = FALSE), collapse = "\n")

  testthat::expect_false(grepl("ifelse\\(attempts > 0,\\s*\\(total_sb / attempts\\) \\* 100,\\s*75\\)", src, perl = TRUE))
  testthat::expect_true(grepl("NA_real_", src, fixed = TRUE))
})

testthat::test_that("gif_payroll_efficiency_bubble refuses missing batters/pitchers cache when mlbplotR is available", {
  testthat::skip_if_not_installed("mlbplotR")
  testthat::skip_if_not_installed("gifski")
  .is_sourced_test <- TRUE
  source(file.path(.chart_audit_root(), "tools/gif_payroll_efficiency_bubble.R"))

  testthat::expect_error(
    generate_gif_payroll_efficiency_bubble(
      season = 2026,
      schedule_file = tempfile(fileext = ".rds"),
      batters_file = tempfile(fileext = ".rds"),
      pitchers_file = tempfile(fileext = ".rds")
    ),
    "\\[SKIP-NO-DATA\\]"
  )
})
