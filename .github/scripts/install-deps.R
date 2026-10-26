# Install the packages listed in .github/r-dependencies.txt, skipping any the
# restored cache already provides. Installs from the Posit Public Package
# Manager binaries that setup-r configures (use-public-rspm), so a tidyverse
# install is a download rather than a source build.

lib <- Sys.getenv("R_LIBS_USER")
if (!nzchar(lib)) stop("R_LIBS_USER is not set.")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

spec <- readLines(".github/r-dependencies.txt", warn = FALSE)
spec <- trimws(sub("#.*$", "", spec))
wanted <- spec[nzchar(spec)]
if (length(wanted) == 0L) stop("No packages listed in .github/r-dependencies.txt.")

have    <- rownames(installed.packages(lib.loc = lib))
missing <- setdiff(wanted, have)

cat(sprintf("Requested: %s\n", paste(wanted, collapse = ", ")))
cat(sprintf("Cached:    %s\n", if (length(intersect(wanted, have)))
  paste(intersect(wanted, have), collapse = ", ") else "(none)"))

if (length(missing) == 0L) {
  cat("Nothing to install.\n")
} else {
  cat(sprintf("Installing: %s\n", paste(missing, collapse = ", ")))
  install.packages(missing, lib = lib, Ncpus = max(1L, parallel::detectCores()))
}

# Fail here rather than inside a test with a confusing "there is no package
# called ..." three steps later.
still <- setdiff(wanted, rownames(installed.packages(lib.loc = lib)))
if (length(still)) {
  stop(sprintf("Failed to install: %s", paste(still, collapse = ", ")))
}
cat("All requested packages are available.\n")
