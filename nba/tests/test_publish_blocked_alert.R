# ==============================================================================
# tests/test_publish_blocked_alert.R
#
# NBA_analytics#145: a blocked live publish opens (or comments on) a GitHub
# issue labelled `publish-blocked`; the next successful live publish closes it.
# Dry runs never call gh, and a gh failure never changes the gate's outcome.
#
# Every gh call here goes to a recording fake runner - nothing touches GitHub.
# The results fed to the notifier are built the same way publish_web() builds
# them (list of checks with id/name/pass/fatal/summary/detail); their content
# describes the gate's own assertions, not any sports data.
#
# Usage: Rscript tests/test_publish_blocked_alert.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})

old_wd <- getwd()
setwd(REPO_ROOT)
source(file.path(REPO_ROOT, "tools", "publish_web.R"))

n_pass <- 0L
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) {
    n_pass <<- n_pass + 1L
    cat("  PASS:", label, "\n")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL:", label, "\n")
  }
}

# Recording fake gh runner. `open_issue` is what `gh issue list` reports;
# `labels` what `gh label list` reports; `fail_on` makes a matching call fail.
fake_gh <- function(open_issue = NA_integer_, labels = character(0), fail_on = NULL,
                    error_on = NULL) {
  env <- new.env()
  env$calls <- list()
  env$bodies <- list()
  env$runner <- function(args) {
    args <- as.character(args)
    key <- paste(args[1:2], collapse = " ")
    env$calls[[length(env$calls) + 1L]] <- args
    bf <- match("--body-file", args)
    if (!is.na(bf)) env$bodies[[length(env$bodies) + 1L]] <- paste(readLines(args[[bf + 1L]], warn = FALSE), collapse = "\n")
    if (!is.null(error_on) && key %in% error_on) stop("gh CLI not found (fake)")
    if (!is.null(fail_on) && key %in% fail_on) return(list(status = 1L, out = "HTTP 401: Bad credentials (fake)"))
    out <- switch(key,
      "issue list"   = if (is.na(open_issue)) character(0) else as.character(open_issue),
      "label list"   = labels,
      "issue create" = "https://github.com/kailot-harris/NBA_analytics/issues/999",
      character(0))
    list(status = 0L, out = out)
  }
  env$keys <- function() vapply(env$calls, function(a) paste(a[1:2], collapse = " "), character(1))
  env
}

user <- Sys.info()[["user"]]
host <- Sys.info()[["nodename"]]
home <- Sys.getenv("USERPROFILE", Sys.getenv("HOME"))
root <- .pw_repo_root()

make_result <- function(blocked = TRUE, dry_run = FALSE, published = FALSE) {
  checks <- list(
    list(id = "A", name = "mtime freshness", pass = TRUE, fatal = TRUE, summary = "all fresh", detail = character(0)),
    list(id = "G", name = "web dataset contracts (vitest node project)", pass = !blocked, fatal = TRUE,
         summary = "payload FAILS the contract suite; publishing it would ship the defect - 238 passed, 1 failed",
         detail = c("    TEST SUITE SUMMARY",
                    sprintf("    FAIL  %s/web/src/data/__tests__/contracts.test.ts > slate file", root),
                    sprintf("    at %s\\AppData\\Local\\Temp\\vitest-123\\chunk.js:10", gsub("/", "\\\\", home)),
                    sprintf("    on host %s as %s", host, user),
                    "    1 failed | 238 passed")),
    list(id = "D", name = "warning scan", pass = FALSE, fatal = FALSE, summary = "2 warning(s)", detail = character(0))
  )
  list(dry_run = dry_run, blocked = blocked, published = published,
       run_start = as.POSIXct("2026-11-16 09:00:02"), publish_branch = "main", repo_root = root,
       assertions_passed = "A", assertions_failed = c("G", "D"),
       stage_warnings = c(sprintf(">>> [WARN] build_x.R: declared output %s/cache/x.rds was NOT rewritten", root),
                          sprintf(">>> [WARN] build_y.R: read %s/Documents/y.csv", home),
                          "w3", "w4", "w5", "w6", "w7"),
       checks = checks)
}

cat("\n[1] blocked, no open issue -> issue list, label list, label create, issue create\n")
f <- fake_gh()
r <- make_result()
r_before <- r
out <- .pw_notify_github(r, runner = f$runner)
check(identical(f$keys(), c("issue list", "label list", "label create", "issue create")), "call order")
create <- f$calls[[4]]
check(identical(create[match("--label", create) + 1L], "publish-blocked"), "create carries the label")
title <- create[match("--title", create) + 1L]
check(grepl("2026-11-16", title, fixed = TRUE) && grepl("G", title, fixed = TRUE), sprintf("title has date and id: %s", title))
check(identical(f$calls[[1]][match("--repo", f$calls[[1]]) + 1L], "kailot-harris/NBA_analytics"), "targets the repo")
check(identical(r, r_before), "result object untouched")
cat("  gh calls:\n"); for (a in f$calls) cat("    gh", paste(a, collapse = " "), "\n")
example_body <- f$bodies[[1]]

cat("\n[1b] blocked, no open issue, label already exists -> no label create\n")
f <- fake_gh(labels = c("synthetic-data", "publish-blocked"))
.pw_notify_github(make_result(), runner = f$runner)
check(identical(f$keys(), c("issue list", "label list", "issue create")), "label not re-created")

cat("\n[2] blocked, open issue #77 -> comment, no create\n")
f <- fake_gh(open_issue = 77L)
.pw_notify_github(make_result(), runner = f$runner)
check(identical(f$keys(), c("issue list", "issue comment")), "list then comment only")
check(identical(f$calls[[2]][[3]], "77"), "comments on #77")
check(!any(f$keys() == "issue create"), "no second issue")
cat("  gh calls:\n"); for (a in f$calls) cat("    gh", paste(a, collapse = " "), "\n")

cat("\n[3] success, open issue #77 -> comment then close\n")
f <- fake_gh(open_issue = 77L)
.pw_notify_github(make_result(blocked = FALSE, published = TRUE), runner = f$runner)
check(identical(f$keys(), c("issue list", "issue comment", "issue close")), "list, comment, close")
check(identical(f$calls[[3]][[3]], "77"), "closes #77")
check(grepl("recovered", f$bodies[[1]], fixed = TRUE) && grepl("2026-11-16", f$bodies[[1]], fixed = TRUE),
      "recovery comment names the date")
cat("  gh calls:\n"); for (a in f$calls) cat("    gh", paste(a, collapse = " "), "\n")

cat("\n[4] success, no open issue -> only the read-only lookup, nothing written\n")
f <- fake_gh()
.pw_notify_github(make_result(blocked = FALSE, published = TRUE), runner = f$runner)
check(identical(f$keys(), "issue list"), "no comment/close/create")

cat("\n[5] dry run -> no gh calls at all\n")
f <- fake_gh(open_issue = 77L)
.pw_notify_github(make_result(blocked = TRUE, dry_run = TRUE), runner = f$runner)
.pw_notify_github(make_result(blocked = FALSE, dry_run = TRUE), runner = f$runner)
check(length(f$calls) == 0L, "zero calls for blocked and passing dry runs")

cat("\n[6] gh failing or missing -> logged, no error, result unchanged\n")
for (case in list(list(fail_on = "issue list"), list(fail_on = "issue create"),
                  list(fail_on = "label create"), list(error_on = "issue list"))) {
  f <- do.call(fake_gh, case)
  r <- make_result()
  msgs <- character(0)
  res <- withCallingHandlers(
    tryCatch(.pw_notify_github(r, runner = f$runner), error = function(e) "ERRORED"),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  lbl <- paste(names(case), unlist(case))
  check(identical(res, "failed"), sprintf("%s: returns quietly", lbl))
  check(any(grepl("^>>> \\[WARN\\] publish_web: GitHub publish-blocked notification skipped", msgs)),
        sprintf("%s: logged a >>> publish_web line", lbl))
  check(identical(r, make_result()), sprintf("%s: result unchanged", lbl))
}
# Real runner with no gh binary at all.
old_bin <- Sys.getenv("NBA_GH_BIN", NA)
Sys.setenv(NBA_GH_BIN = file.path(tempdir(), "no-such-gh.exe"))
check(identical(.pw_gh_bin(), ""), "NBA_GH_BIN pointing nowhere resolves to no binary")
res <- suppressMessages(.pw_notify_github(make_result(), runner = NULL))
check(identical(res, "failed"), "missing binary with the real runner: logged, no error")
if (is.na(old_bin)) Sys.unsetenv("NBA_GH_BIN") else Sys.setenv(NBA_GH_BIN = old_bin)
# Timeout is an exit status like any other.
f_to <- list(runner = function(args) list(status = 124L, out = character(0)))
res <- suppressMessages(.pw_notify_github(make_result(), runner = f_to$runner))
check(identical(res, "failed"), "timeout (exit 124): logged, no error")

cat("\n[7] sanitising strips paths, home, host and user\n")
s <- .pw_sanitize_public(c(
  sprintf("%s/tools/publish_web.R", root),
  sprintf("%s\\tools\\publish_web.R", gsub("/", "\\\\", root)),
  sprintf("%s\\AppData\\Local\\Temp\\x.js", gsub("/", "\\\\", home)),
  "D:\\other\\place\\file.txt and /home/someone/x",
  sprintf("host=%s user=%s", toupper(host), user),
  "see https://github.com/kailot-harris/NBA_analytics/issues/145"),
  repo_root = root, home = home, host = host, user = user)
cat(paste0("    ", s, collapse = "\n"), "\n")
check(identical(s[1:2], c("<repo>/tools/publish_web.R", "<repo>\\tools\\publish_web.R")), "repo root -> <repo>")
check(identical(s[3], "<home>\\AppData\\Local\\Temp\\x.js"), "home -> <home>")
check(identical(s[4], "<path> and <home>/x"), "other absolute paths stripped")
check(identical(s[5], "host=<host> user=<user>"), "host and user stripped (case-insensitive)")
check(identical(s[6], "see https://github.com/kailot-harris/NBA_analytics/issues/145"), "URLs and repo slug survive")

leaks <- c(root, home, gsub("/", "\\\\", root), gsub("/", "\\\\", home), host)
check(!any(vapply(leaks[nzchar(leaks)], function(l) grepl(l, example_body, fixed = TRUE, ignore.case = FALSE), logical(1))),
      "rendered issue body has no repo root, home or host")
check(!grepl(sprintf("(?<![A-Za-z0-9])%s(?![A-Za-z0-9])", user), example_body, perl = TRUE, ignore.case = TRUE),
      "rendered issue body has no user name")
check(!grepl("[A-Za-z]:[\\\\/]", gsub("https?://", "", example_body), perl = TRUE), "rendered issue body has no drive path")
check(grepl("238 passed, 1 failed", example_body, fixed = TRUE), "body carries the failing assertion summary")
check(grepl("contracts.test.ts", example_body, fixed = TRUE), "body carries failing test output")
check(grepl("\nw5\n", example_body, fixed = TRUE) && !grepl("w6", example_body, fixed = TRUE) &&
      grepl("first 5 shown", example_body, fixed = TRUE),
      "at most 5 stage warnings")
check(!grepl("\\bD\\b \\(warning scan\\)", example_body, perl = TRUE), "non-fatal checks not listed as failures")

cat("\n---- example rendered issue body ----\n")
cat(example_body, "\n")
cat("---- end example ----\n")

setwd(old_wd)
cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
if (n_fail > 0L) quit(status = 1L)
