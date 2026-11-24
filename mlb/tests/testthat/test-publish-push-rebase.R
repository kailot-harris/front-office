# ------------------------------------------------------------------------------
# Publish push with fetch-rebase-retry (.pw_push_with_rebase in
# tools/publish_web.R). Regression test for the 2026-11-24 scheduled run: PRs
# merged into main while the pipeline ran, `git push origin HEAD` was rejected
# ("fetch first"), and the local publish commit was left behind on a diverged
# checkout. Fully offline: a bare remote and two clones under tempdir(); never
# touches this checkout's git state or any real remote.
# ------------------------------------------------------------------------------
if (!file.exists("config.R")) {
  if (file.exists("../../config.R")) setwd(normalizePath("../..", winslash = "/"))
  else stop("Cannot locate the project root (no config.R).", call. = FALSE)
}
suppressPackageStartupMessages(library(testthat))

source("tools/publish_web.R")

run_git <- function(dir, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop("git ", paste(c(...), collapse = " "), " failed:\n", paste(out, collapse = "\n"))
  }
  out
}

configure_clone <- function(dir, who) {
  run_git(dir, "config", "user.name", shQuote(who))
  run_git(dir, "config", "user.email", shQuote(paste0(gsub(" ", "-", tolower(who)), "@example.invalid")))
  run_git(dir, "config", "commit.gpgsign", "false")
}

# Bare remote on `main`, a seed commit, and two clones: `publisher` (the
# scheduled run's checkout) and `other` (a PR merging into main mid-run).
make_sandbox <- function(tag) {
  sandbox <- file.path(tempdir(), sprintf("push-rebase-%s-%d", tag, as.integer(Sys.getpid())))
  unlink(sandbox, recursive = TRUE, force = TRUE)
  dir.create(sandbox, recursive = TRUE)
  remote <- file.path(sandbox, "remote.git")
  seed <- file.path(sandbox, "seed")
  run_git(sandbox, "init", "--bare", "-q", "-b", "main", shQuote(remote))
  run_git(sandbox, "init", "-q", "-b", "main", shQuote(seed))
  configure_clone(seed, "Seed User")
  dir.create(file.path(seed, "web", "public", "data"), recursive = TRUE)
  writeLines('{"tick": 0}', file.path(seed, "web", "public", "data", "monitor.json"))
  writeLines("v0", file.path(seed, "README.txt"))
  run_git(seed, "add", "-A")
  run_git(seed, "commit", "-q", "-m", shQuote("seed"))
  run_git(seed, "remote", "add", "origin", shQuote(remote))
  run_git(seed, "push", "-q", "origin", "main")
  publisher <- file.path(sandbox, "publisher")
  other <- file.path(sandbox, "other")
  run_git(sandbox, "clone", "-q", shQuote(remote), shQuote(publisher))
  run_git(sandbox, "clone", "-q", shQuote(remote), shQuote(other))
  configure_clone(publisher, "Publish Bot")
  configure_clone(other, "Other Dev")
  list(root = sandbox, remote = remote, publisher = publisher, other = other)
}

# The scheduled run regenerates the data file and commits it locally.
publisher_commit <- function(sb, content = '{"tick": 1}') {
  writeLines(content, file.path(sb$publisher, "web", "public", "data", "monitor.json"))
  run_git(sb$publisher, "add", "-A", "--", "web/public/data")
  run_git(sb$publisher, "commit", "-q", "-m", shQuote("Publish web data"))
}

# Someone else pushes to main while the run is in flight.
other_pushes <- function(sb, path, content, msg) {
  full <- file.path(sb$other, path)
  dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
  writeLines(content, full)
  run_git(sb$other, "add", "-A")
  run_git(sb$other, "commit", "-q", "-m", shQuote(msg))
  run_git(sb$other, "push", "-q", "origin", "main")
}

merge_commit_count <- function(dir, ref) {
  length(run_git(dir, "rev-list", "--merges", ref))
}

test_that("(a) remote moved without conflict: publish commit is rebased and pushed, no merge commit", {
  skip_if(!nzchar(Sys.which("git")), "git not available")
  sb <- make_sandbox("moved")
  on.exit(unlink(sb$root, recursive = TRUE, force = TRUE), add = TRUE)

  publisher_commit(sb)
  other_pushes(sb, "DESCRIPTION.txt", "dependency bump", "Bump dependency")
  other_tip <- run_git(sb$remote, "rev-parse", "main")

  steps <- NULL
  expect_no_error(steps <- .pw_push_with_rebase(.pw_repo_root(sb$publisher), "main"))
  labels <- vapply(steps, `[[`, character(1), "label")
  expect_true("git fetch origin main" %in% labels)
  expect_true("git rebase origin/main" %in% labels)

  # The remote tip is the publisher's HEAD, and contains both commits.
  remote_tip <- run_git(sb$remote, "rev-parse", "main")
  expect_identical(remote_tip, run_git(sb$publisher, "rev-parse", "HEAD"))
  subjects <- run_git(sb$remote, "log", "--format=%s", "main")
  expect_identical(subjects[1:2], c("Publish web data", "Bump dependency"))
  # Linear: the publish commit's parent is the other clone's tip; no merges.
  expect_identical(run_git(sb$remote, "rev-parse", "main~1"), other_tip)
  expect_identical(merge_commit_count(sb$remote, "main"), 0L)
  expect_identical(run_git(sb$remote, "show", "main:web/public/data/monitor.json"), '{"tick": 1}')
  expect_identical(run_git(sb$remote, "show", "main:DESCRIPTION.txt"), "dependency bump")
  # Checkout is clean and in step with origin.
  expect_length(run_git(sb$publisher, "status", "--porcelain"), 0L)
  expect_identical(run_git(sb$publisher, "rev-parse", "origin/main"), remote_tip)
})

test_that("(b) remote changed the same data file: rebase aborted, branch reset to origin, file kept, clear failure", {
  skip_if(!nzchar(Sys.which("git")), "git not available")
  sb <- make_sandbox("conflict")
  on.exit(unlink(sb$root, recursive = TRUE, force = TRUE), add = TRUE)

  publisher_commit(sb, '{"tick": "publisher"}')
  other_pushes(sb, "web/public/data/monitor.json", '{"tick": "other"}', "Hand edit of monitor")
  other_tip <- run_git(sb$remote, "rev-parse", "main")

  err <- tryCatch({ .pw_push_with_rebase(.pw_repo_root(sb$publisher), "main"); NULL },
                  error = function(e) conditionMessage(e))
  cat("\n[conflict test] failure message:\n", err, "\n", sep = "")
  expect_false(is.null(err))
  expect_match(err, "the publish commit was NOT pushed", fixed = TRUE)
  expect_match(err, "back in step with origin/main", fixed = TRUE)
  expect_match(err, "regenerated files are still in the working tree", fixed = TRUE)

  # No rebase left in progress.
  git_dir <- run_git(sb$publisher, "rev-parse", "--absolute-git-dir")
  expect_false(dir.exists(file.path(git_dir, "rebase-merge")))
  expect_false(dir.exists(file.path(git_dir, "rebase-apply")))
  # Local branch equals origin/main, which equals the real remote tip.
  expect_identical(run_git(sb$publisher, "rev-parse", "main"), other_tip)
  expect_identical(run_git(sb$publisher, "rev-parse", "origin/main"), other_tip)
  expect_identical(run_git(sb$remote, "rev-parse", "main"), other_tip)
  # The regenerated file is still in the working tree (as a modification).
  expect_identical(readLines(file.path(sb$publisher, "web", "public", "data", "monitor.json")),
                   '{"tick": "publisher"}')
  porcelain <- run_git(sb$publisher, "status", "--porcelain")
  expect_true(any(grepl("web/public/data/monitor.json", porcelain, fixed = TRUE)))
  # Nothing went to the stash stack.
  expect_length(run_git(sb$publisher, "stash", "list"), 0L)
})

test_that("(c) no remote change: the publish commit is pushed as before", {
  skip_if(!nzchar(Sys.which("git")), "git not available")
  sb <- make_sandbox("nochange")
  on.exit(unlink(sb$root, recursive = TRUE, force = TRUE), add = TRUE)

  publisher_commit(sb)
  local_head <- run_git(sb$publisher, "rev-parse", "HEAD")

  steps <- NULL
  expect_no_error(steps <- .pw_push_with_rebase(.pw_repo_root(sb$publisher), "main"))
  labels <- vapply(steps, `[[`, character(1), "label")
  expect_false("git rebase origin/main" %in% labels)
  expect_identical(run_git(sb$remote, "rev-parse", "main"), local_head)
  expect_identical(run_git(sb$publisher, "rev-parse", "HEAD"), local_head)
  expect_identical(merge_commit_count(sb$remote, "main"), 0L)
})
