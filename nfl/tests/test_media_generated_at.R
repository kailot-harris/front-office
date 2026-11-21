# tests/test_media_generated_at.R
# Offline tests for R/media_generated_at.R: media_generated_at() reports the last commit
# time for a tracked file that is unchanged against HEAD, and the file's mtime otherwise.
# Each case builds its own throwaway git repo under tempdir().
# Shared file: identical in every sport repo.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("R/media_generated_at.R")

if (!nzchar(Sys.which("git"))) {
  cat("[SKIP] git not on PATH\n")
  quit(status = 0L)
}

stamp <- function(f) format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
git <- function(repo, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), "-c", "user.name=test",
                                           "-c", "user.email=test@example.com",
                                           "-c", "core.autocrlf=false", ...),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop(paste(out, collapse = "\n"))
  invisible(out)
}
new_repo <- function() {
  repo <- tempfile("mga_repo_"); dir.create(repo)
  git(repo, "init", "-q")
  repo
}
commit_file <- function(repo, name, bytes, date = "2026-11-17T20:11:09Z") {
  f <- file.path(repo, name); writeBin(bytes, f)
  git(repo, "add", "--", name)
  old <- Sys.getenv(c("GIT_COMMITTER_DATE", "GIT_AUTHOR_DATE"), unset = NA)
  Sys.setenv(GIT_COMMITTER_DATE = date, GIT_AUTHOR_DATE = date)
  on.exit({
    for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k]))
  })
  git(repo, "commit", "-q", "-m", "add")
  f
}

# 1. unchanged tracked file reports commit time, even after its mtime moves to now
repo <- new_repo()
f <- commit_file(repo, "a.gif", as.raw(1:8))
Sys.setFileTime(f, Sys.time())
ok("unchanged tracked file reports commit time",
   identical(media_generated_at(f, repo = repo), "2026-11-17T20:11:09Z"))
ok("relative path from repo works too",
   identical(media_generated_at("a.gif", repo = repo), "2026-11-17T20:11:09Z"))

# 2. modified tracked file reports mtime
writeBin(as.raw(8:1), f)
Sys.setFileTime(f, as.POSIXct("2026-11-21 09:30:00", tz = "UTC"))
ok("modified tracked file reports mtime",
   identical(media_generated_at(f, repo = repo), "2026-11-21T09:30:00Z"))

# 3. untracked file reports mtime
u <- file.path(repo, "new.gif"); writeBin(as.raw(1:3), u)
Sys.setFileTime(u, as.POSIXct("2026-11-20 01:02:03", tz = "UTC"))
ok("untracked file reports mtime", identical(media_generated_at(u, repo = repo), "2026-11-20T01:02:03Z"))

# 4. not a git repo falls back to mtime
plain <- tempfile("mga_plain_"); dir.create(plain)
p <- file.path(plain, "c.gif"); writeBin(as.raw(1:3), p)
Sys.setFileTime(p, as.POSIXct("2026-11-19 12:00:00", tz = "UTC"))
ok("not a git repo falls back to mtime", identical(media_generated_at(p, repo = plain), "2026-11-19T12:00:00Z"))

# 5. commit offset other than UTC is converted to UTC
repo2 <- new_repo()
g <- commit_file(repo2, "b.gif", as.raw(1:4), date = "2026-11-17T15:11:09-05:00")
ok("non-UTC commit offset converted to UTC",
   identical(media_generated_at(g, repo = repo2), "2026-11-17T20:11:09Z"))
ok("format is UTC ISO-8601", grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", media_generated_at(g, repo = repo2)))

# 6. git_state (one ls-files + status per directory) gives the same answers.
repo3 <- new_repo()
h1 <- commit_file(repo3, "same.gif", as.raw(1:5))
h2 <- commit_file(repo3, "changed.gif", as.raw(1:6))
writeBin(as.raw(6:1), h2); Sys.setFileTime(h2, as.POSIXct("2026-11-21 09:30:00", tz = "UTC"))
h3 <- file.path(repo3, "new.gif"); writeBin(as.raw(1:2), h3)
Sys.setFileTime(h3, as.POSIXct("2026-11-20 01:02:03", tz = "UTC"))
gs <- media_git_state(repo3, repo = repo3)
ok("git_state: same answers as per-file calls",
   all(vapply(c(h1, h2, h3), function(x) identical(media_generated_at(x, repo3, gs), media_generated_at(x, repo3)), logical(1))) &&
   identical(media_generated_at(h1, repo3, gs), "2026-11-17T20:11:09Z") &&
   identical(media_generated_at(h2, repo3, gs), "2026-11-21T09:30:00Z") &&
   identical(media_generated_at(h3, repo3, gs), "2026-11-20T01:02:03Z"))
ok("git_state outside a repo is NULL and falls back to mtime",
   is.null(media_git_state(plain, repo = plain)) && identical(media_generated_at(p, plain, NULL), "2026-11-19T12:00:00Z"))

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All media_generated_at tests passed\n")
