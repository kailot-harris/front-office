# Run every tests/test_*.R in its own R process and aggregate the results.
#
# Each file is a self-contained script that prints PASS/FAIL lines and exits
# non-zero on failure (there is no testthat harness here). A separate process
# per file keeps one file's global state out of the next one's.
#
# A repository state with no test files is reported, not treated as a pass with
# a green tick and nothing behind it. It is also not a failure: tests/ arrives
# with the stage-bootstrap work, and main is expected to be without it until
# that merges.

tests <- sort(Sys.glob(file.path("tests", "test_*.R")))

summarise <- function(lines) {
  path <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(path)) cat(paste(lines, collapse = "\n"), "\n", file = path, append = TRUE)
  cat(paste(lines, collapse = "\n"), "\n")
}

if (length(tests) == 0L) {
  summarise(c("### R tests: none found",
              "",
              "`tests/test_*.R` matched no files, so nothing ran.",
              "This is expected only until the stage-bootstrap tests land on this branch."))
  quit(status = 0L)
}

rscript <- file.path(R.home("bin"), "Rscript")
results <- data.frame(file = tests, status = NA_integer_, stringsAsFactors = FALSE)

for (i in seq_along(tests)) {
  f <- tests[[i]]
  cat(sprintf("\n================ %s ================\n", f))
  results$status[[i]] <- system2(rscript, f)
}

failed <- results[results$status != 0L, , drop = FALSE]

summarise(c(
  sprintf("### R tests: %d file(s), %d failure(s)", nrow(results), nrow(failed)),
  "",
  "| test file | exit code |",
  "| --- | --- |",
  sprintf("| `%s` | %s |", results$file,
          ifelse(results$status == 0L, "0 (pass)", paste0(results$status, " (fail)")))
))

if (nrow(failed)) quit(status = 1L)
