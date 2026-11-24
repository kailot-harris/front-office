# tests/test_publish_push_rebase.R
# Offline tests for the push step of tools/publish_web.R (.pw_do_publish ->
# .pw_push_with_rebase): fetch, rebase onto origin/<branch>, push, retry once,
# and on a conflict abort + `reset --mixed` so no local commit is left behind.
# Uses a temp bare remote and two temp clones only; never touches a real remote.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
suppressPackageStartupMessages(library(jsonlite))
root <- normalizePath(getwd(), winslash = "/")
source("tools/publish_web.R")
setwd(root)

g <- function(dir, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(ok = is.null(st) || st == 0L, out = as.character(out))
}
g1 <- function(dir, ...) { r <- g(dir, ...); if (length(r$out)) r$out[1] else NA_character_ }
ident <- function(dir) {
  g(dir, "config", "user.email", "t@example.com"); g(dir, "config", "user.name", "t")
  g(dir, "config", "core.autocrlf", "false"); g(dir, "config", "commit.gpgsign", "false")
}
data_file <- file.path("web", "public", "data", "a.json")
write_at <- function(dir, rel, txt) {
  dir.create(dirname(file.path(dir, rel)), recursive = TRUE, showWarnings = FALSE)
  writeLines(txt, file.path(dir, rel))
}

# Bare remote on `main`, seeded with one commit; returns paths of the remote and
# two clones: `pub` (the scheduled checkout) and `other` (lands commits mid-run).
setup <- function() {
  base <- normalizePath(tempfile("pw_push_"), winslash = "/", mustWork = FALSE)
  dir.create(base)
  remote <- file.path(base, "remote.git"); seed <- file.path(base, "seed")
  system2("git", c("init", "-q", "--bare", shQuote(remote)), stdout = FALSE, stderr = FALSE)
  g(remote, "symbolic-ref", "HEAD", "refs/heads/main")
  system2("git", c("init", "-q", shQuote(seed)), stdout = FALSE, stderr = FALSE)
  ident(seed); g(seed, "checkout", "-q", "-b", "main")
  write_at(seed, data_file, '{"v":0}'); write_at(seed, "code.R", "x <- 1")
  write_at(seed, file.path("web", "public", "animations", "index.json"), "{}")
  g(seed, "add", "-A"); g(seed, "commit", "-q", "-m", "init")
  g(seed, "remote", "add", "origin", shQuote(remote)); g(seed, "push", "-q", "origin", "main")
  cl <- function(name) {
    d <- file.path(base, name)
    system2("git", c("clone", "-q", "-b", "main", shQuote(remote), shQuote(d)), stdout = FALSE, stderr = FALSE)
    ident(d); d
  }
  list(base = base, remote = remote, pub = cl("pub"), other = cl("other"))
}
land_other <- function(s, rel, txt, msg) {
  write_at(s$other, rel, txt); g(s$other, "add", "-A"); g(s$other, "commit", "-q", "-m", shQuote(msg))
  invisible(g(s$other, "push", "-q", "origin", "main"))
}
publish <- function(s) {
  tryCatch(list(err = NULL, steps = .pw_do_publish(s$pub, "Publish test run", "main")),
           error = function(e) list(err = conditionMessage(e), steps = NULL))
}
parents <- function(dir, ref) length(strsplit(g1(dir, "rev-list", "--parents", "-n", "1", ref), " ")[[1]]) - 1L
no_merges <- function(dir, ref) length(g(dir, "rev-list", "--merges", ref)$out) == 0L

# --- (c) normal case: nothing landed on the remote during the run -------------
s <- setup()
write_at(s$pub, data_file, '{"v":1}')
r <- publish(s)
if (!is.null(r$err)) cat(r$err, "
")
ok("(c) no remote change: publish succeeds", is.null(r$err))
ok("(c) remote tip equals the local publish commit",
   identical(g1(s$remote, "rev-parse", "main"), g1(s$pub, "rev-parse", "HEAD")))
ok("(c) remote tip is the publish commit",
   identical(g1(s$remote, "log", "-1", "--format=%s", "main"), "Publish test run"))
ok("(c) no rebase step was needed", !any(grepl("^git rebase origin", vapply(r$steps, `[[`, "", "label"))))
unlink(s$base, recursive = TRUE, force = TRUE)

# --- (a) remote moved, no conflict: rebase + push, no merge commit -------------
s <- setup()
land_other(s, "code.R", "x <- 2", "dependency bump")
other_sha <- g1(s$other, "rev-parse", "HEAD")
write_at(s$pub, data_file, '{"v":1}')
r <- publish(s)
labels <- vapply(r$steps, `[[`, "", "label")
ok("(a) remote moved: publish succeeds", is.null(r$err))
ok("(a) a fetch and a rebase step were recorded",
   any(grepl("^git fetch origin main", labels)) && any(grepl("^git rebase origin/main", labels)))
ok("(a) remote tip is the publish commit",
   identical(g1(s$remote, "log", "-1", "--format=%s", "main"), "Publish test run"))
ok("(a) remote tip contains the other commit",
   g(s$remote, "merge-base", "--is-ancestor", other_sha, "main")$ok)
ok("(a) publish commit has one parent: the other commit",
   parents(s$remote, "main") == 1L && identical(g1(s$remote, "rev-parse", "main^"), other_sha))
ok("(a) no merge commit on the remote", no_merges(s$remote, "main"))
ok("(a) local HEAD equals the remote tip",
   identical(g1(s$pub, "rev-parse", "HEAD"), g1(s$remote, "rev-parse", "main")))
unlink(s$base, recursive = TRUE, force = TRUE)

# --- (b) remote changed the same data file: abort, reset --mixed, fail ---------
s <- setup()
land_other(s, data_file, '{"v":"theirs"}', "remote edits the data file")
write_at(s$pub, data_file, '{"v":"ours"}')
r <- publish(s)
ok("(b) conflict: the step fails", !is.null(r$err))
ok("(b) failure message says the publish commit was not pushed",
   isTRUE(grepl("publish commit was NOT pushed", r$err, fixed = TRUE)))
ok("(b) failure message says the checkout is back in step with origin",
   isTRUE(grepl("back in step with origin/main", r$err, fixed = TRUE)))
ok("(b) failure message says the regenerated files are still in the working tree",
   isTRUE(grepl("regenerated files are still in the working tree", r$err, fixed = TRUE)))
ok("(b) no rebase left in progress",
   !dir.exists(file.path(s$pub, ".git", "rebase-merge")) && !dir.exists(file.path(s$pub, ".git", "rebase-apply")))
ok("(b) local branch equals origin/main",
   identical(g1(s$pub, "rev-parse", "HEAD"), g1(s$pub, "rev-parse", "origin/main")))
ok("(b) origin/main is the remote's tip (the other commit)",
   identical(g1(s$pub, "rev-parse", "origin/main"), g1(s$remote, "rev-parse", "main")))
ok("(b) remote still has no publish commit",
   identical(g1(s$remote, "log", "-1", "--format=%s", "main"), "remote edits the data file"))
ok("(b) generated file is still in the working tree with our content",
   identical(readLines(file.path(s$pub, data_file)), '{"v":"ours"}'))
ok("(b) generated file shows as an unstaged modification",
   any(grepl("^ M web/public/data/a.json$", g(s$pub, "status", "--porcelain")$out)))
ok("(b) no stash was created", length(g(s$pub, "stash", "list")$out) == 0L)
unlink(s$base, recursive = TRUE, force = TRUE)

# --- source guards: never merge, stash or hard-reset in the push step ----------
src <- paste(deparse(.pw_push_with_rebase), collapse = "\n")
ok("push step never merges, stashes or hard-resets",
   !grepl('"merge"|"pull"|"stash"|--hard', src))

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All publish push/rebase tests passed\n")
