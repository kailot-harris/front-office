# ==============================================================================
# check_renv_library_sync.R
# Path: tools/check_renv_library_sync.R
#
# Reports packages that renv.lock records but the CURRENT checkout's renv
# library does not have installed, and exits non-zero if any are missing.
#
# Mechanism: `renv/.gitignore` ignores `library/`, so every git worktree gets
# its own EMPTY renv library, while `renv/settings.json`'s `use.cache: true`
# keeps the package *cache* global and shared. Nothing under `renv/library/` is
# tracked, so a library difference is invisible to git status, git diff and any
# merge.
#
# So a branch can install packages, commit the renv.lock change, and pass every
# test in its own worktree, while the checkout it merges into never links those
# packages. Because scripts here are written to degrade gracefully rather than
# crash, the result is not necessarily a visible error: a missing package can
# surface as a missing *feature* that no exit code reports. This script makes
# that state explicit.
#
# Restoring is usually cheap -- the cache is global, so packages normally link
# rather than download.
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

# Parsed with base R regex, NOT jsonlite, deliberately: jsonlite is itself one
# of the packages absent from a fresh worktree's library, so depending on it
# would make this script fail in precisely the case it exists to detect.
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
# Naming 170 packages explicitly is unusable advice. Past a handful missing the
# library is wholesale unpopulated (a fresh worktree), and a bare restore is
# both shorter and what you actually want.
if (length(missing) > 12) {
  cat("  renv::restore(prompt = FALSE)\n")
  cat(sprintf("  # %d of %d recorded packages are missing - this library is unpopulated,\n",
              length(missing), length(recorded)))
  cat("  # so restore everything rather than naming packages individually.\n")
} else {
  cat(sprintf("  renv::restore(packages = c(%s), prompt = FALSE)\n",
              paste(sprintf('"%s"', sort(missing)), collapse = ", ")))
}
cat("\nDo NOT run renv::snapshot() to 'fix' this, especially in a worktree: a sparse\n")
cat("library makes snapshot() DELETE the lockfile records for everything not installed,\n")
cat("which can silently drop thousands of lines. Remember the direction - snapshot()\n")
cat("writes the library into the lockfile, restore() writes the lockfile into the\n")
cat("library. Here you want restore().\n")
quit(status = 1)
