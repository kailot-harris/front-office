# ==============================================================================
# Run every tests/test_*.R in its own R process and aggregate the results.
#
# Modeled on NBA Analytics/.github/scripts/run-tests.R and WNBA Analytics's
# assertion-counting runner. Each file in tests/test_*.R is a self-contained
# offline test script that prints [PASS] / [FAIL] lines and exits non-zero on
# any failure. Running each script in its own R process keeps one file's global
# state out of the next one's.
#
# All tests under tests/test_*.R are offline (zero network calls, zero paid API
# keys). They load the packages listed in .github/r-dependencies.txt, which the
# CI `r` job installs first. A test that needs a gitignored pipeline cache
# prints a [SKIP] line instead of failing; skips are counted and shown in the
# summary so a skipped test is never mistaken for a passed one.
# ==============================================================================

tests <- sort(Sys.glob(file.path("tests", "test_*.R")))

summarise <- function(lines) {
  path <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(path)) cat(paste(lines, collapse = "\n"), "\n", file = path, append = TRUE)
  cat(paste(lines, collapse = "\n"), "\n")
}

if (length(tests) == 0L) {
  summarise(c("### R tests: none found",
              "",
              "`tests/test_*.R` matched no files, so nothing ran."))
  quit(status = 1L)
}

rscript <- file.path(R.home("bin"), "Rscript")
results <- data.frame(
  file    = tests,
  status  = NA_integer_,
  passed  = 0L,
  failed  = 0L,
  skipped = 0L,
  elapsed = NA_real_,
  stringsAsFactors = FALSE
)

for (i in seq_along(tests)) {
  f <- tests[[i]]
  cat(sprintf("\n================ %s ================\n", f))
  t0 <- proc.time()[["elapsed"]]
  out <- suppressWarnings(system2(rscript, shQuote(f), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  results$status[[i]]  <- if (is.null(st)) 0L else as.integer(st)
  results$elapsed[[i]] <- round(proc.time()[["elapsed"]] - t0, 2)
  if (length(out)) cat(paste(out, collapse = "\n"), "\n")
  results$passed[[i]] <- sum(grepl("^\\s*\\[PASS\\]", out))
  results$failed[[i]] <- sum(grepl("^\\s*\\[FAIL\\]", out))
  results$skipped[[i]] <- sum(grepl("^\\s*\\[SKIP\\]", out))

  # If the test script exited non-zero without printing any [FAIL] line,
  # count at least one failure so a crashed file is reflected in the count
  # and "0 failed" cannot appear beside an exited non-zero test file.
  if (results$status[[i]] != 0L && results$failed[[i]] == 0L) {
    results$failed[[i]] <- 1L
  }
}

failed_files <- results[results$status != 0L | results$failed > 0L, , drop = FALSE]
total_pass   <- sum(results$passed)
total_fail   <- sum(results$failed)
total_skip   <- sum(results$skipped)

summarise(c(
  sprintf("### R unit tests: %d file(s), %d assertion(s) passed, %d failed, %d skip notice(s)",
          nrow(results), total_pass, total_fail, total_skip),
  "",
  "| Test script | Assertions (pass / fail) | Skip notices | Elapsed | Exit |",
  "| --- | --- | --- | --- | --- |",
  sprintf("| `%s` | %d / %d | %d | %.2fs | %s |",
          results$file,
          results$passed,
          results$failed,
          results$skipped,
          results$elapsed,
          ifelse(results$status == 0L & results$failed == 0L,
                 "0 (PASS)",
                 paste0(results$status, " (FAIL)")))
))

if (nrow(failed_files) > 0L) quit(status = 1L)
