# ==============================================================================
# tests/test_pipeline_failure_alert.R
#
# NBA_analytics#161: a run_full_pipeline.R crash (publish gate never reached)
# opens, or comments on, a `pipeline-failed` GitHub issue carrying a sanitized
# log tail. A gh failure never throws. Every gh call goes to a recording fake;
# nothing touches GitHub.
#
# Usage: Rscript tests/test_pipeline_failure_alert.R
# ==============================================================================
REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
setwd(REPO_ROOT)
source(file.path(REPO_ROOT, "tools", "publish_web.R"))

n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) cat("  PASS:", label, "\n") else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n") }
}
fake_gh <- function(open_issue = NA_integer_, labels = character(0), fail_on = NULL, error_on = NULL) {
  env <- new.env(); env$calls <- list(); env$bodies <- list()
  env$runner <- function(args) {
    args <- as.character(args); key <- paste(args[1:2], collapse = " ")
    env$calls[[length(env$calls) + 1L]] <- args
    bf <- match("--body-file", args)
    if (!is.na(bf)) env$bodies[[length(env$bodies) + 1L]] <- paste(readLines(args[[bf + 1L]], warn = FALSE), collapse = "\n")
    if (!is.null(error_on) && key %in% error_on) stop("gh CLI not found (fake)")
    if (!is.null(fail_on) && key %in% fail_on) return(list(status = 1L, out = "HTTP 401 (fake)"))
    out <- switch(key,
      "issue list" = if (is.na(open_issue)) character(0) else as.character(open_issue),
      "label list" = labels,
      "issue create" = "https://github.com/kailot-harris/NBA_analytics/issues/999",
      character(0))
    list(status = 0L, out = out)
  }
  env$keys <- function() vapply(env$calls, function(a) paste(a[1:2], collapse = " "), character(1))
  env
}

root <- .pw_repo_root()
user <- Sys.info()[["user"]]
home_dir <- if (nzchar(Sys.getenv("USERPROFILE"))) Sys.getenv("USERPROFILE") else Sys.getenv("HOME")
log_file <- tempfile(fileext = ".log")
writeLines(c(rep("filler line", 100),
             sprintf("Error in stage at %s/run_full_pipeline.R: boom", root),
             sprintf("profile %s", home_dir),
             "```fenced``` text", "PIPELINE RUN FAILED WITH EXIT CODE 1"), log_file)

cat("fresh crash opens an issue\n")
g <- fake_gh(labels = "pipeline-failed")
r <- .pw_notify_pipeline_failure(1, log_file, runner = g$runner)
check(identical(as.character(r), "created"), "returns created")
check(identical(g$keys(), c("issue list", "label list", "issue create")), "list -> label check -> create")
body <- g$bodies[[1]]
check(grepl("exited with code `1`", body, fixed = TRUE), "body names the exit code")
check(grepl("PIPELINE RUN FAILED WITH EXIT CODE 1", body, fixed = TRUE), "body carries the log tail")
check(!grepl("filler line", body) || sum(grepl("filler line", strsplit(body, "\n")[[1]])) <= 37, "tail is bounded (40 lines)")
check(!grepl(root, body, fixed = TRUE), "repo root stripped")
check(nzchar(home_dir) && !grepl(home_dir, body, fixed = TRUE), "home stripped")
check(!grepl("```fenced```", body, fixed = TRUE), "fence breakers neutralised")
check("pipeline-failed" %in% g$calls[[3]], "issue carries the label")

cat("missing label is created first\n")
g <- fake_gh(labels = character(0))
.pw_notify_pipeline_failure(2, log_file, runner = g$runner)
check(identical(g$keys(), c("issue list", "label list", "label create", "issue create")), "label created before the issue")

cat("recurring crash comments, never opens a second issue\n")
g <- fake_gh(open_issue = 77L)
r <- .pw_notify_pipeline_failure(1, log_file, runner = g$runner)
check(identical(as.character(r), "commented #77"), "returns commented #77")
check(identical(g$keys(), c("issue list", "issue comment")), "list -> comment only")
check(grepl("Failed again", g$bodies[[1]], fixed = TRUE), "comment heading")

cat("gh problems never throw\n")
for (case in list(list(fail_on = "issue list"), list(error_on = "issue list"), list(fail_on = "issue create", labels = "pipeline-failed"))) {
  g <- do.call(fake_gh, case)
  r <- tryCatch(.pw_notify_pipeline_failure(1, log_file, runner = g$runner), error = function(e) "THREW")
  check(identical(as.character(r), "failed"), paste("swallowed:", paste(names(case)[1], unlist(case[[1]])[1])))
}
r <- tryCatch(.pw_notify_pipeline_failure(1, file.path(tempdir(), "no_such.log"), runner = fake_gh(labels = "pipeline-failed")$runner),
              error = function(e) "THREW")
check(identical(as.character(r), "created"), "missing log file still notifies")

cat(sprintf("\n%s\n", if (n_fail == 0L) "ALL PASSED" else sprintf("%d FAILED", n_fail)))
quit(status = if (n_fail == 0L) 0L else 1L)
