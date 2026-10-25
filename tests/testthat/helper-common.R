# helper-common.R
# Executed automatically by testthat prior to running test files.

proj_dir <- if (file.exists("../../config.R")) {
  normalizePath("../..", winslash = "/")
} else if (file.exists("config.R")) {
  getwd()
} else {
  "c:/Users/kailo/kayceeslices/MLB Analytics"
}

# Set working directory to project root so all source() and relative paths resolve
setwd(proj_dir)
Sys.setenv(MLB_PROJECT_DIR = proj_dir)

# ------------------------------------------------------------------------------
# skip_if_no_cache() — for tests that evaluate the REAL season's pipeline output
#
# A handful of tests here are quality gates on actual cached engine output
# (is this season's Elo calibration still OPTIMAL? is the Bayes shrinkage
# monotonic on the real player pool?). They cannot be made fixture-driven
# without changing what they assert — a synthetic fixture says nothing about
# the real season — so they skip wherever `cache/` does not exist: CI, a fresh
# clone, a new git worktree. They still run, and still fail loudly, locally.
#
# Skipping on cache ABSENCE rather than on CI specifically is deliberate: a
# worktree without caches should behave the same way as CI, not blow up.
#
# @param stage Cache stage name, as passed to cache_path()
# @param ... One or more file names within that stage
skip_if_no_cache <- function(stage, ...) {
  files <- vapply(c(...), function(f) cache_path(stage, f, create = FALSE),
                  character(1))
  missing <- files[!file.exists(files)]
  if (length(missing) > 0) {
    testthat::skip(sprintf(
      "Requires pipeline cache not present in this environment: %s",
      paste(basename(missing), collapse = ", ")
    ))
  }
  invisible(TRUE)
}
