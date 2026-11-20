# ------------------------------------------------------------------------------
# Off-season baseline promotion (.pw_promote_offseason_baseline in
# tools/publish_web.R). Regression test for the 2026-11-20 scheduled run: the
# root .gitignore ignores cache/, so a plain `git add` of the tracked
# cache/league_state_baseline.json exited 1 and the promotion stopped before
# its commit and push. Fully offline: runs against a throwaway repo and a local
# bare remote under tempdir(); never touches this checkout's git state.
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

test_that("promotion commits and pushes the tracked baseline even though cache/ is gitignored", {
  skip_if(!nzchar(Sys.which("git")), "git not available")

  sandbox <- file.path(tempdir(), sprintf("baseline-promotion-%d", as.integer(Sys.getpid())))
  unlink(sandbox, recursive = TRUE, force = TRUE)
  dir.create(sandbox, recursive = TRUE)
  on.exit(unlink(sandbox, recursive = TRUE, force = TRUE), add = TRUE)

  remote <- file.path(sandbox, "remote.git")
  repo <- file.path(sandbox, "repo")
  run_git(sandbox, "init", "--bare", "-q", shQuote(remote))
  run_git(sandbox, "init", "-q", shQuote(repo))
  run_git(repo, "config", "user.name", shQuote("Baseline Test"))
  run_git(repo, "config", "user.email", shQuote("baseline-test@example.invalid"))
  run_git(repo, "config", "commit.gpgsign", "false")
  run_git(repo, "remote", "add", "origin", shQuote(remote))

  # Root .gitignore ignores cache/ wholesale, as origin/main's did on 2026-11-20;
  # the baseline is tracked anyway (force-added once).
  writeLines("/cache/", file.path(repo, ".gitignore"))
  dir.create(file.path(repo, "cache"))
  writeLines('{"state": "before"}', file.path(repo, "cache", "league_state_baseline.json"))
  run_git(repo, "add", ".gitignore")
  run_git(repo, "add", "-f", "--", "cache/league_state_baseline.json")
  run_git(repo, "commit", "-q", "-m", shQuote("seed"))
  run_git(repo, "push", "-q", "origin", "HEAD")

  # The run's staged league state differs from the committed baseline.
  writeLines('{"state": "after"}', file.path(repo, "cache", "league_state_staged.json"))

  repo_root <- .pw_repo_root(repo)
  expect_false(is.na(repo_root))
  expect_no_error(.pw_promote_offseason_baseline(repo_root, file.path(repo_root, "cache")))

  # A follow-up commit with the expected subject exists locally ...
  subject <- run_git(repo, "log", "-1", "--format=%s")
  expect_identical(subject, "Promote MLB offseason baseline after publish")
  # ... it touched only the baseline ...
  changed <- run_git(repo, "show", "--name-only", "--format=", "HEAD")
  expect_identical(changed[nzchar(changed)], "cache/league_state_baseline.json")
  # ... and it was pushed to the bare remote.
  branch <- run_git(repo, "rev-parse", "--abbrev-ref", "HEAD")
  expect_identical(run_git(remote, "rev-parse", branch), run_git(repo, "rev-parse", "HEAD"))
  expect_identical(run_git(remote, "show", paste0(branch, ":cache/league_state_baseline.json")),
                   '{"state": "after"}')

  # Worktree clean: nothing modified, nothing staged, nothing untracked.
  expect_length(run_git(repo, "status", "--porcelain"), 0L)
})
