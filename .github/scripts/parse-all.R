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
# and this script parses the 99 files the repo actually owns.

files <- system2("git", c("ls-files", "*.R", "*.r"), stdout = TRUE)
files <- files[nzchar(files)]
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
