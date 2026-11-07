# ==============================================================================
# build_cba_cap_dataset.R
# WNBA CBA Salary Cap Sheet (ARCHIVED — GitHub #128, #140, #141)
# ==============================================================================
# This script has been archived. Cap sheet generation has been retired pending
# integration with verified official WNBA player contract data.
# ==============================================================================

if (file.exists("logging_utils.R")) source("logging_utils.R")
message(">>> [CBA CAP BUILDER] Stage archived pending live contract feed integration (GitHub #128, #140, #141). Skipping execution.")
if (exists("log_info")) {
  log_info("build_cba_cap_dataset: Stage archived pending live contract feeds. Skipping write.", script = "build_cba_cap_dataset.R")
}
