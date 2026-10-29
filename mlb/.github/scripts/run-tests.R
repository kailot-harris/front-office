# Run testthat unit test suite for MLB Analytics.
#
# Runs all test files in tests/testthat/ using testthat::test_dir().
# Summarises results to GITHUB_STEP_SUMMARY if running under GitHub Actions.

suppressPackageStartupMessages(library(testthat))

summarise <- function(lines) {
  path <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(path)) cat(paste(lines, collapse = "\n"), "\n", file = path, append = TRUE)
  cat(paste(lines, collapse = "\n"), "\n")
}

test_res <- testthat::test_dir("tests/testthat", stop_on_failure = FALSE)
df_res <- as.data.frame(test_res)

total_tests <- nrow(df_res)
total_failed <- sum(df_res$failed > 0)
total_warned <- sum(df_res$warning > 0)
total_skipped <- sum(df_res$skipped > 0)
total_passed <- sum(df_res$passed)

summarise(c(
  sprintf("### MLB R testthat suite: %d test file(s), %d failure(s)", total_tests, total_failed),
  "",
  sprintf("- **Passed assertions:** %d", total_passed),
  sprintf("- **Failed contexts:** %d", total_failed),
  sprintf("- **Warnings:** %d", total_warned),
  sprintf("- **Skipped:** %d", total_skipped),
  "",
  "| Context | Passed | Failed | Warnings | Skipped |",
  "| --- | --- | --- | --- | --- |",
  sprintf("| `%s` | %d | %d | %d | %d |",
          df_res$file, df_res$passed, df_res$failed, df_res$warning, df_res$skipped)
))

if (any(df_res$failed > 0)) {
  stop("Unit tests failed!")
}
