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
