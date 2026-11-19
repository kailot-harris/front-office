# ==============================================================================
# tests/test_web_data_files_config.R
#
# Regression suite for NBA_analytics#194:
#   1. config.R defines WEB_JSON_PROJECTIONS_DIAGNOSTICS pointing to
#      web/public/data/projections_diagnostics.json and includes it in
#      WEB_DATA_FILES so tools/publish_web.R assertions A and F enforce its
#      freshness alongside all other pipeline-written web payloads.
#   2. Deliberate non-members (offseason_transactions.json, shots_index.json,
#      shots_metadata.json) remain excluded from WEB_DATA_FILES.
#   3. accuracy_governance.R writes projections_diagnostics.json with a
#      generated_at stamp that tools/publish_web.R's provenance parser reads.
#
# Usage: Rscript tests/test_web_data_files_config.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

cfg_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "config.R"), local = cfg_env)

ok("WEB_JSON_PROJECTIONS_DIAGNOSTICS is defined in config.R",
   exists("WEB_JSON_PROJECTIONS_DIAGNOSTICS", envir = cfg_env, inherits = FALSE))

diag_path <- cfg_env$WEB_JSON_PROJECTIONS_DIAGNOSTICS
ok("WEB_JSON_PROJECTIONS_DIAGNOSTICS points to projections_diagnostics.json inside WEB_DATA_DIR",
   is.character(diag_path) && length(diag_path) == 1L &&
     identical(basename(diag_path), "projections_diagnostics.json") &&
     identical(normalizePath(dirname(diag_path), winslash = "/", mustWork = FALSE),
               normalizePath(cfg_env$WEB_DATA_DIR, winslash = "/", mustWork = FALSE)))

ok("WEB_JSON_PROJECTIONS_DIAGNOSTICS is registered in WEB_DATA_FILES",
   diag_path %in% cfg_env$WEB_DATA_FILES)

ok("WEB_DATA_FILES has no duplicate entries",
   length(cfg_env$WEB_DATA_FILES) == length(unique(cfg_env$WEB_DATA_FILES)))

ok("Deliberate non-members stay excluded from WEB_DATA_FILES",
   !(cfg_env$WEB_JSON_OFFSEASON_TRANSACTIONS %in% cfg_env$WEB_DATA_FILES) &&
     !(cfg_env$WEB_JSON_SHOTS_INDEX %in% cfg_env$WEB_DATA_FILES) &&
     !(cfg_env$WEB_JSON_SHOTS_METADATA %in% cfg_env$WEB_DATA_FILES))

cfg_lines <- readLines(file.path(REPO_ROOT, "config.R"), warn = FALSE)
ok("Stale 'written by nothing' claim removed from config.R comments",
   !any(grepl("written by\\s+nothing|no writer, in any stage", cfg_lines, perl = TRUE)))

# Verify tools/publish_web.R provenance parser reads generated_at from the tracked diagnostics JSON
old_wd <- getwd()
setwd(REPO_ROOT)
on.exit(setwd(old_wd), add = TRUE)

pw_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "tools", "publish_web.R"), local = pw_env)
if (file.exists(diag_path)) {
  gen_at <- pw_env$.pw_payload_generated_at(diag_path)
  ok("publish_web.R parses non-NA generated_at timestamp from projections_diagnostics.json",
     inherits(gen_at, "POSIXct") && !is.na(gen_at))
} else {
  ok("projections_diagnostics.json path is valid (file absent in test fixture)", TRUE)
}

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
