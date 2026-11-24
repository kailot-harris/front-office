# ==============================================================================
# tests/test_publish_push_rebase.R
#
# The live publish's push step must survive commits that land on the publish
# branch while the pipeline runs: it fetches, rebases the publish commit onto
# origin/<branch>, and pushes; on a real conflict it aborts the rebase, moves
# the branch back to origin/<branch> without touching the working tree, and
# fails with a clear message. It never merges, stashes or hard-resets.
#
# Every repo here is a throwaway under tempdir(): a bare "remote" plus two
# clones (the pipeline's checkout and a second clone standing in for PRs that
# merge mid-run). Nothing touches the real remote.
#
# Usage: Rscript tests/test_publish_push_rebase.R
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
real_media_dir <- WEB_MEDIA_DIR

# Explicit identity so the commits made by .pw_git() and by the helpers below
# never depend on the machine's global git config.
Sys.setenv(GIT_AUTHOR_NAME = "test", GIT_AUTHOR_EMAIL = "test@example.com",
           GIT_COMMITTER_NAME = "test", GIT_COMMITTER_EMAIL = "test@example.com")

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

git <- function(repo, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), "-c", "core.autocrlf=false",
                                           "-c", "commit.gpgsign=false", ...),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop(paste(c(paste(..., collapse = " "), out), collapse = "\n"))
  invisible(as.character(out))
}
write_file <- function(repo, rel, lines) {
  p <- file.path(repo, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, p)
}
read_file <- function(repo, rel) readLines(file.path(repo, rel), warn = FALSE)
sha <- function(repo, ref) git(repo, "rev-parse", ref)[[1]]

DATA_FILE <- "web/public/data/today.json"
MOMENTUM  <- "data/history/momentum_rank_history.csv"

# A bare remote whose main holds a seed commit, plus the pipeline's clone
# ("local") and a second clone ("other") that pushes while the pipeline runs.
new_fixture <- function() {
  root <- normalizePath(tempfile("pw_push_"), winslash = "/", mustWork = FALSE)
  dir.create(root)
  remote <- file.path(root, "remote.git")
  git(root, "init", "-q", "--bare", "--initial-branch=main", shQuote(remote))
  seed <- file.path(root, "seed")
  git(root, "clone", "-q", shQuote(remote), shQuote(seed))
  git(seed, "checkout", "-q", "-B", "main")
  write_file(seed, DATA_FILE, '{"games": 0}')
  write_file(seed, "web/public/data/other.json", '{"x": 0}')
  write_file(seed, "web/public/media/keep.txt", "media")
  write_file(seed, "data/history/ratings_history.csv", "date,team,rating")
  write_file(seed, MOMENTUM, "date,team,rank")
  write_file(seed, "README.md", "seed")
  git(seed, "add", "-A")
  git(seed, "commit", "-q", "-m", "seed")
  git(seed, "push", "-q", "origin", "main")
  local <- file.path(root, "local")
  other <- file.path(root, "other")
  git(root, "clone", "-q", shQuote(remote), shQuote(local))
  git(root, "clone", "-q", shQuote(remote), shQuote(other))
  list(root = root, remote = remote, local = local, other = other,
       seed_sha = sha(seed, "HEAD"))
}

# The pipeline's regenerated output in the local clone.
regenerate <- function(fx) {
  write_file(fx$local, DATA_FILE, '{"games": 7, "from": "pipeline"}')
  write_file(fx$local, MOMENTUM, c("date,team,rank", "2026-11-24,BOS,1"))
}

# Run the push step against the local clone; returns list(err, steps, msgs).
run_publish <- function(fx) {
  assign("WEB_MEDIA_DIR", file.path(fx$local, "web", "public", "media"), envir = globalenv())
  on.exit(assign("WEB_MEDIA_DIR", real_media_dir, envir = globalenv()), add = TRUE)
  err <- NULL
  steps <- NULL
  msgs <- character(0)
  withCallingHandlers(
    tryCatch(
      steps <- .pw_do_publish(fx$local, "web/public/data", "Publish NBA web artifacts (test)", "main"),
      error = function(e) err <<- conditionMessage(e)),
    message = function(m) {
      msgs <<- c(msgs, sub("\n$", "", conditionMessage(m)))
      invokeRestart("muffleMessage")
    })
  list(err = err, steps = steps, msgs = msgs)
}

no_merges <- function(repo, ref) length(git(repo, "rev-list", "--merges", ref)) == 0L
stash_empty <- function(repo) length(git(repo, "stash", "list")) == 0L
rebase_in_progress <- function(repo) {
  any(dir.exists(file.path(repo, ".git", c("rebase-merge", "rebase-apply"))))
}

# ------------------------------------------------------------------------------
cat("\n(c) no remote change: the publish commit is pushed as before\n")
fx <- new_fixture()
regenerate(fx)
r <- run_publish(fx)
check(is.null(r$err), paste("push step succeeded", if (!is.null(r$err)) r$err else ""))
check(identical(sha(fx$remote, "main"), sha(fx$local, "HEAD")), "remote main == local HEAD")
check(identical(sha(fx$local, "HEAD~1"), fx$seed_sha), "publish commit sits directly on the seed commit")
check(identical(git(fx$local, "log", "-1", "--format=%s")[[1]], "Publish NBA web artifacts (test)"),
      "commit message unchanged")
committed <- git(fx$local, "show", "--name-only", "--format=", "HEAD")
check(MOMENTUM %in% committed, "momentum rank history is committed with the publish")
check(DATA_FILE %in% committed, "regenerated data file is committed")
check(any(grepl("^>>> publish_web: fetched origin/main", r$msgs)), "log line: fetched")
check(any(grepl("^>>> publish_web: pushed [0-9a-f]+ to origin/main", r$msgs)), "log line: pushed with SHA")

# ------------------------------------------------------------------------------
cat("\n(a) remote moved, no conflict: rebased onto the remote tip and pushed\n")
fx <- new_fixture()
write_file(fx$other, "web/public/data/other.json", '{"x": 1}')
write_file(fx$other, "DEPENDENCIES.txt", "bumped")
git(fx$other, "add", "-A")
git(fx$other, "commit", "-q", "-m", shQuote("dependency bump merged mid-run"))
git(fx$other, "push", "-q", "origin", "main")
other_sha <- sha(fx$other, "HEAD")
regenerate(fx)
r <- run_publish(fx)
check(is.null(r$err), paste("push step succeeded", if (!is.null(r$err)) r$err else ""))
check(identical(sha(fx$remote, "main"), sha(fx$local, "HEAD")), "remote main == local HEAD")
check(identical(sha(fx$remote, "main~1"), other_sha), "publish commit was rebased onto the mid-run commit")
check(no_merges(fx$remote, "main"), "no merge commit on the remote")
remote_log <- git(fx$remote, "log", "--format=%s", "main")
check(all(c("Publish NBA web artifacts (test)", "dependency bump merged mid-run") %in% remote_log),
      "remote tip contains both commits")
check(any(grepl("^>>> publish_web: rebased the publish commit onto the remote tip origin/main", r$msgs)),
      "log line: rebased onto the remote tip")
check(any(grepl(substr(other_sha, 1, 12), r$msgs, fixed = TRUE)), "rebase log line names the remote tip SHA")
check(stash_empty(fx$local), "stash list untouched")

# ------------------------------------------------------------------------------
cat("\n(b) remote changed the same data file: rebase aborted, checkout back in step\n")
fx <- new_fixture()
write_file(fx$other, DATA_FILE, '{"games": 3, "from": "someone else"}')
git(fx$other, "add", "-A")
git(fx$other, "commit", "-q", "-m", shQuote("conflicting change to the data file"))
git(fx$other, "push", "-q", "origin", "main")
other_sha <- sha(fx$other, "HEAD")
regenerate(fx)
generated <- read_file(fx$local, DATA_FILE)
r <- run_publish(fx)
if (!is.null(r$err)) cat("  step error was:\n", r$err, "\n")
check(!is.null(r$err), "push step fails")
check(isTRUE(grepl("the publish commit was NOT pushed", r$err, fixed = TRUE)),
      "failure message says the publish commit was not pushed")
check(isTRUE(grepl("in step with origin", r$err, fixed = TRUE)),
      "failure message says the checkout is in step with origin")
check(isTRUE(grepl("regenerated files are still in the working tree", r$err, fixed = TRUE)),
      "failure message says the regenerated files are still in the working tree")
check(!rebase_in_progress(fx$local), "no rebase left in progress")
check(identical(sha(fx$local, "HEAD"), sha(fx$local, "origin/main")), "local main == origin/main")
check(identical(sha(fx$local, "HEAD"), other_sha), "local main is the remote's commit")
check(identical(sha(fx$remote, "main"), other_sha), "remote main unchanged by the failed publish")
check(identical(read_file(fx$local, DATA_FILE), generated), "generated data file still in the working tree")
check(DATA_FILE %in% sub("^.. ", "", git(fx$local, "status", "--porcelain")),
      "generated data file shows as an uncommitted change")
check(identical(read_file(fx$local, MOMENTUM), c("date,team,rank", "2026-11-24,BOS,1")),
      "momentum history still in the working tree")
check(no_merges(fx$local, "HEAD"), "no merge commit")
check(stash_empty(fx$local), "stash list untouched")

setwd(old_wd)
cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
if (n_fail > 0L) quit(status = 1L)
