# tests/test_publish_guard.R  (NFL_analytics#154)
# Offline tests for tools/publish_guard.R: pipeline output is kept, other dirty
# files are classified for stashing. Uses a throwaway git repo; no network.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
root <- normalizePath(getwd(), winslash = "/")
source("config.R")
source("tools/publish_guard.R")

ok("PIPELINE_OUTPUT_DIRS covers WEB_DATA_DIR and WEB_ANIM_DIR",
   setequal(PIPELINE_OUTPUT_DIRS, c(WEB_DATA_DIR, WEB_ANIM_DIR)))
ok("PIPELINE_OUTPUT_FILES includes data/history/ratings_history.csv",
   "data/history/ratings_history.csv" %in% gsub("\\\\", "/", PIPELINE_OUTPUT_FILES))

# --- pure classifier ---------------------------------------------------------
r <- classify_dirty_paths(c(" M web/public/data/a.json", "?? web/public/animations/x.json"),
                          PIPELINE_OUTPUT_DIRS)
ok("output-only tree: nothing classified as other", length(r$other) == 0L && length(r$output) == 2L)
r <- classify_dirty_paths(c(" M web/public/data/a.json", " M data/history/ratings_history.csv"),
                          PIPELINE_OUTPUT_DIRS, PIPELINE_OUTPUT_FILES)
ok("ratings_history.csv is classified as output (kept), not other",
   length(r$other) == 0L && "data/history/ratings_history.csv" %in% r$output)
r <- classify_dirty_paths(c(" M web/public/data/a.json", " M config.R", "?? docs/n.md"),
                          PIPELINE_OUTPUT_DIRS)
ok("code/config/docs classified as other", setequal(r$other, c("config.R", "docs/n.md")))
r <- classify_dirty_paths(c("R  web/public/data/new.json", "web/other/old.json"), PIPELINE_OUTPUT_DIRS)
ok("rename source outside output dirs is flagged other", identical(r$other, "web/other/old.json"))
r <- classify_dirty_paths(c(" M web/public/data_extra/a.json"), PIPELINE_OUTPUT_DIRS)
ok("prefix lookalike dir is NOT treated as output", length(r$output) == 0L)

# --- CLI against a real temp repo --------------------------------------------
tmp <- tempfile("pg_repo_"); dir.create(tmp)
git <- function(...) system2("git", c("-C", shQuote(tmp), ...), stdout = FALSE, stderr = FALSE)
git("init", "-q"); git("config", "user.email", "t@example.com"); git("config", "user.name", "t")
dir.create(file.path(tmp, "web/public/data"), recursive = TRUE)
dir.create(file.path(tmp, "tools"))
invisible(file.copy(file.path(root, "config.R"), file.path(tmp, "config.R")))
invisible(file.copy(file.path(root, "tools/publish_guard.R"), file.path(tmp, "tools/publish_guard.R")))
writeLines("{}", file.path(tmp, "web/public/data/a.json"))
writeLines("x <- 1", file.path(tmp, "code.R"))
git("add", "-A"); git("commit", "-q", "-m", "init")

run_cli <- function() {
  o <- tempfile(); p <- tempfile()
  old <- setwd(tmp); on.exit(setwd(old))
  rc <- system2(file.path(R.home("bin"), "Rscript"), c("tools/publish_guard.R", shQuote(o), shQuote(p)),
                stdout = FALSE, stderr = FALSE)
  nul <- function(f) { b <- readBin(f, "raw", file.size(f)); if (!length(b)) return(character(0))
    cuts <- c(0L, which(b == as.raw(0L))); vapply(seq_len(length(cuts) - 1L), function(k)
      rawToChar(b[(cuts[k] + 1L):cuts[k + 1L]][-(cuts[k + 1L] - cuts[k])]), "") }
  list(rc = rc, other = nul(o), output = nul(p))
}
writeLines('{"w":11}', file.path(tmp, "web/public/data/a.json"))
writeLines("{}", file.path(tmp, "web/public/data/b.json"))
dir.create(file.path(tmp, "data/history"), recursive = TRUE)
writeLines("date,team,metric,value", file.path(tmp, "data/history/ratings_history.csv"))
res <- run_cli()
ok("CLI, output-only dirty tree (incl. ratings_history.csv): exit 0, nothing to stash, output kept",
   res$rc == 0L && length(res$other) == 0L && length(res$output) == 3L &&
     "data/history/ratings_history.csv" %in% res$output)
writeLines("x <- 2", file.path(tmp, "code.R"))
res <- run_cli()
ok("CLI, tracked code file modified: it is listed for stashing", res$rc == 0L && identical(res$other, "code.R"))
ok("CLI, output files still listed as kept", length(res$output) == 3L)
unlink(tmp, recursive = TRUE)

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All publish_guard tests passed\n")
