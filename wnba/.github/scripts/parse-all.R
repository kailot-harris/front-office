# Syntax check for every tracked R file. parse() only - nothing is evaluated, so
# this needs no packages and cannot hit an API or touch the cache.
#
# Copied verbatim from NBA Analytics/.github/scripts/parse-all.R, which is a
# proven live model rather than a template. Only this header differs.
#
# Tracked files only (via git ls-files). In this repo that exclusion is doing
# real work: `find . -name 'test*.R'` turns up 204 files, of which 64 are
# vendored THIRD-PARTY package tests under renv/library/ (vip, RcppArmadillo,
# fastshap, shiny, testthat itself) and the rest are mostly agent worktree
# copies under .claude/. Neither is tracked, so git ls-files never sees them
# and this script parses the 102 files the repo actually owns.

# `git ls-files '*.R' '*.r'` looks like the obvious call and is WRONG here.
# It matches only the repository ROOT on a Linux runner while matching every
# directory on this Windows checkout, so the job silently graded a fraction of
# the tree and still printed a confident count. Measured 2026-10-26 on the
# first real run: WNBA 43 files in CI against 99 locally, NFL 19 against 79 --
# in both cases exactly the root-level files. NBA Analytics' CI has the same
# bug and its "50 files" figure is root-level only.
#
# So: list every tracked path and filter on the extension in R, where the
# semantics do not depend on the platform or on core.ignorecase.
files <- system2("git", "ls-files", stdout = TRUE)
files <- files[nzchar(files)]
files <- files[grepl("[.][Rr]$", files)]
# Rmd/qmd are not parsed here: they are prose documents with chunks, and
# knitr - not R's parser - decides what is code.
files <- files[!grepl("node_modules/", files, fixed = TRUE)]

if (length(files) == 0L) {
  stop("No tracked .R files found - is this running outside the repository?")
}

failed <- character()
for (f in files) {
  err <- tryCatch({ parse(f); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(err)) {
    failed <- c(failed, sprintf("%s: %s", f, err))
    cat(sprintf("  FAIL  %s\n    %s\n", f, err))
  }
}

cat(sprintf("\nParsed %d file(s), %d failure(s).\n", length(files), length(failed)))

summary_path <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_path)) {
  lines <- c(sprintf("### R syntax: %d file(s) parsed, %d failure(s)",
                     length(files), length(failed)),
             if (length(failed)) c("", paste0("- `", failed, "`")))
  cat(paste(lines, collapse = "\n"), "\n", file = summary_path, append = TRUE)
}

if (length(failed)) quit(status = 1L)
