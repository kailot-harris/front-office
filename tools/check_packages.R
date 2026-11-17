# Preflight for scheduled runs. The .bat launches R with --vanilla (which skips
# .Rprofile, so renv never activates), meaning R only sees the user/site library
# and not the project's renv library. Verify the packages the weekly run depends
# on are loadable under those same conditions and fail loudly BEFORE the
# pipeline runs, instead of degrading (e.g. a missing udpipe/sentimentr silently
# dropping the sentiment pulse).
#
# REQUIRED: abort (exit 1) if any is missing. Add a package here when a pipeline
#           step starts depending on it at runtime.
# Other renv.lock packages (dev/optional, e.g. tidytext) only produce a warning.
required <- c("jsonlite", "udpipe", "sentimentr")

has <- function(p) requireNamespace(p, quietly = TRUE)

fail <- function(missing) {
  cat(sprintf("[ERROR] check_packages: required package(s) not visible to --vanilla R: %s\n",
              paste(missing, collapse = ", ")), file = stderr())
  cat(sprintf("Fix: install.packages(c(%s)) into the user library at the renv.lock versions.\n",
              paste(sprintf("'%s'", missing), collapse = ", ")), file = stderr())
  quit(status = 1L)
}

# jsonlite is checked FIRST because the renv.lock scan below depends on it.
if (!has("jsonlite")) fail("jsonlite")

missing <- required[!vapply(required, has, logical(1))]
if (length(missing)) fail(missing)

lock_pkgs <- names(jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)$Packages)
lock_missing <- setdiff(lock_pkgs[!vapply(lock_pkgs, has, logical(1))], required)
if (length(lock_missing)) {
  cat(sprintf("[WARN] check_packages: renv.lock packages not visible to --vanilla R (not required): %s\n",
              paste(lock_missing, collapse = ", ")))
}
cat(sprintf("[OK] check_packages: required packages present (%s).\n", paste(required, collapse = ", ")))
