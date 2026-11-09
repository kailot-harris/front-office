# ==============================================================================
# check_renv_library_sync.R
# Path: tools/check_renv_library_sync.R
#
# Reports packages that renv.lock records but the CURRENT checkout's renv
# library does not have installed, and exits non-zero if any are missing.
#
# Why this exists (issue #171, 2026-11-09). `renv/.gitignore` ignores
# `library/`, so every git worktree gets its own EMPTY renv library while
# `renv/settings.json`'s `use.cache: true` means the package *cache* is global
# and shared. The consequence is a silent, merge-shaped trap:
#
#   1. An agent works in a worktree and installs new packages there. They land
#      in the worktree's library and in the global cache. `renv.lock` is
#      updated and committed, so the lockfile change travels with the branch.
#   2. Every test the agent runs passes, because it runs in that worktree.
#   3. The branch merges. `main` now has a lockfile naming packages its own
#      library has never had a symlink to. NOTHING in git tracks the library,
#      so the merge looks complete and clean.
#   4. The next run on `main` fails -- or worse, degrades gracefully. #171
#      merged with `sentimentr` and `udpipe` present only in the worktree;
#      `sentiment_pulse.R` correctly fell back to `available = FALSE`, so the
#      pipeline did not crash and would simply have published no sentiment
#      number that week.
#
# Step 4 is the dangerous one: a fail-safe design converts a missing-package
# error into a missing *feature*, which no exit code reports. This script makes
# that state loud and cheap to check.
#
# The remedy is nearly free because the cache is global -- restoring the 7
# packages #171 added took 44ms, all "linked from cache", with no downloads.
#
# Run after merging any branch that touched renv.lock, and in a fresh worktree
# before trusting a green test run:
#
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/check_renv_library_sync.R
#
# Exit 0 = every recorded package resolves. Exit 1 = at least one is missing
# (the remedy command is printed). Exit 2 = the lockfile could not be read.
# ==============================================================================

# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing. The
# walk-up is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too
# -- which matters here, since a worktree is exactly the case this script is about.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("check_renv_library_sync.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

lock_path <- file.path(PROJECT_DIR, "renv.lock")
if (!file.exists(lock_path)) {
  cat("check_renv_library_sync.R: no renv.lock at", lock_path, "\n")
  quit(status = 2)
}

# Parsed with base R regex, NOT jsonlite, deliberately. The sparse-library case
# this script exists to detect is exactly the case where jsonlite may not be
# installed either -- the first version of this script segfaulted in a fresh
# worktree for that reason. Base R only means it always runs where it is needed.
# renv writes one `"Package": "<name>"` line immediately followed by
# `"Version": "<ver>"` per record, which is stable enough to match directly.
lines <- readLines(lock_path, warn = FALSE)
pkg_idx <- grep('^\\s*"Package":\\s*"', lines)
if (length(pkg_idx) == 0) {
  cat("check_renv_library_sync.R: renv.lock records no packages (no \"Package\" entries found)\n")
  quit(status = 2)
}
pkg_names <- sub('^\\s*"Package":\\s*"([^"]+)".*$', "\\1", lines[pkg_idx])
pkg_vers <- vapply(pkg_idx, function(i) {
  nxt <- lines[seq(i, min(i + 3L, length(lines)))]
  vline <- grep('^\\s*"Version":\\s*"', nxt, value = TRUE)
  if (length(vline) == 0) "(no version recorded)" else sub('^\\s*"Version":\\s*"([^"]+)".*$', "\\1", vline[1])
}, character(1))
recorded <- setNames(as.list(pkg_vers), pkg_names)

# requireNamespace() would attach and run .onLoad for every package in the
# lockfile, which is slow and can error for reasons unrelated to presence.
# A library-path lookup answers the only question being asked: is it installed?
installed <- rownames(installed.packages())
missing <- setdiff(names(recorded), installed)

cat(sprintf("renv.lock records %d packages; %d resolve in this checkout's library.\n",
            length(recorded), length(recorded) - length(missing)))
cat("library:", .libPaths()[1], "\n")

if (length(missing) == 0) {
  cat("OK - every recorded package is installed.\n")
  quit(status = 0)
}

cat(sprintf("\nMISSING (%d):\n", length(missing)))
for (p in sort(missing)) {
  cat(sprintf("  - %-24s %s\n", p, recorded[[p]]))
}
cat("\nRemedy (cheap - the renv cache is global, so these usually link rather than download):\n")
cat(sprintf("  renv::restore(packages = c(%s), prompt = FALSE)\n",
            paste(sprintf('"%s"', sort(missing)), collapse = ", ")))
cat("\nDo NOT run renv::snapshot() to 'fix' this, especially in a worktree: a sparse\n")
cat("library makes snapshot() DELETE the lockfile records for everything not installed.\n")
cat("In #171 that was 7,763 lines. snapshot() writes the library into the lockfile;\n")
cat("restore() writes the lockfile into the library. Here you want restore().\n")
quit(status = 1)
