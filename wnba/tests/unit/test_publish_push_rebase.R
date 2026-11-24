# ==============================================================================
# test_publish_push_rebase.R
# tools/publish_web.R push step: fetch + rebase onto origin/<branch> before the
# push, one retry, and a clean unwind on a conflict.
#
# Every repo here is a throwaway under tempdir(): one bare "remote" and two
# clones (the publisher and a second writer standing in for a PR merged during
# the pipeline run). The real origin is never touched. Base R + jsonlite only,
# printing [PASS]/[FAIL] lines like the other tests/unit lifecycle scripts.
#   Rscript tests/unit/test_publish_push_rebase.R
# ==============================================================================

args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
source(file.path("tests", "helpers", "lifecycle_fixtures.R"))
lc_bootstrap()

# --- throwaway git fixtures ----------------------------------------------------
g <- function(repo, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), ...), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop(sprintf("git %s failed in %s:\n%s",
                                             paste(c(...), collapse = " "), repo, paste(out, collapse = "\n")))
  invisible(out)
}
g_ok <- function(repo, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(repo), ...), stdout = TRUE, stderr = TRUE))
  is.null(attr(out, "status")) || attr(out, "status") == 0L
}
write_file <- function(repo, rel, text) {
  p <- file.path(repo, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(text, p)
}
read_file <- function(repo, rel) readLines(file.path(repo, rel), warn = FALSE)

DATA <- "web/public/data/standings.json"

new_fixture <- function(tag) {
  root <- normalizePath(tempfile(paste0("pw_push_", tag, "_")), winslash = "/", mustWork = FALSE)
  dir.create(root)
  remote <- file.path(root, "remote.git")
  pub    <- file.path(root, "publisher")
  other  <- file.path(root, "other")
  system2("git", c("init", "--bare", "-q", "-b", "main", shQuote(remote)), stdout = TRUE, stderr = TRUE)
  for (cl in c(pub, other)) {
    system2("git", c("clone", "-q", shQuote(remote), shQuote(cl)), stdout = TRUE, stderr = TRUE)
    g(cl, "config", "user.name", "Test Writer")
    g(cl, "config", "user.email", "test@example.invalid")
    g(cl, "config", "core.autocrlf", "false")
    g(cl, "checkout", "-q", "-B", "main")
  }
  write_file(pub, DATA, '{"through_date": "2026-01-01"}')
  write_file(pub, "README.md", "fixture")
  g(pub, "add", "-A"); g(pub, "commit", "-q", "-m", "seed")
  g(pub, "push", "-q", "origin", "main")
  g(pub, "branch", "-q", "--set-upstream-to=origin/main", "main")
  g(other, "pull", "-q", "origin", "main")
  g(other, "branch", "-q", "--set-upstream-to=origin/main", "main")
  list(root = root, remote = remote, pub = pub, other = other)
}
remote_tip <- function(fx) g(fx$remote, "rev-parse", "main")[1]
head_of    <- function(repo, ref = "HEAD") g(repo, "rev-parse", ref)[1]
subjects   <- function(fx) g(fx$remote, "log", "--format=%s", "main")
merges     <- function(fx) length(g(fx$remote, "rev-list", "--merges", "main"))
in_rebase  <- function(repo) {
  gd <- file.path(repo, ".git")
  dir.exists(file.path(gd, "rebase-merge")) || dir.exists(file.path(gd, "rebase-apply"))
}
run_publish <- function(fx) {
  tryCatch(
    { utils::capture.output(steps <- .pw_do_publish(fx$pub, "web/public/data", "Publish test artifacts", "main"))
      list(ok = TRUE, steps = steps, msg = NA_character_) },
    error = function(e) list(ok = FALSE, steps = NULL, msg = conditionMessage(e)))
}

# --- (c) no remote change: still pushes ----------------------------------------
cat("\n-- (c) no remote change --\n")
fx <- new_fixture("c")
write_file(fx$pub, DATA, '{"through_date": "2026-01-02"}')
r <- run_publish(fx)
check("(c) publish succeeds", r$ok, r$msg)
check("(c) remote tip equals the publisher's HEAD", identical(remote_tip(fx), head_of(fx$pub)))
check("(c) remote tip is the publish commit", identical(subjects(fx)[1], "Publish test artifacts"))
check("(c) no rebase step was needed",
      !any(grepl("^git rebase", vapply(r$steps, `[[`, "", "label"))))

# --- (a) remote moved, no conflict: rebased and pushed ---------------------------
cat("\n-- (a) remote moved, different file --\n")
fx <- new_fixture("a")
write_file(fx$other, "README.md", "dependency bump merged during the run")
g(fx$other, "commit", "-q", "-am", shQuote("Merged PR during run")); g(fx$other, "push", "-q", "origin", "main")
other_sha <- head_of(fx$other)
write_file(fx$pub, DATA, '{"through_date": "2026-01-02"}')
r <- run_publish(fx)
check("(a) publish succeeds after rebase", r$ok, r$msg)
check("(a) a rebase step ran", any(grepl("^git rebase origin/main", vapply(r$steps, `[[`, "", "label"))))
check("(a) remote tip equals the publisher's HEAD", identical(remote_tip(fx), head_of(fx$pub)))
check("(a) remote history holds both commits, publish on top",
      identical(subjects(fx)[1:2], c("Publish test artifacts", "Merged PR during run")), subjects(fx))
check("(a) the other writer's commit is the publish commit's parent",
      identical(head_of(fx$remote, "main~1"), other_sha))
check("(a) no merge commit", merges(fx) == 0L)
check("(a) publisher in step with origin/main", identical(head_of(fx$pub), head_of(fx$pub, "origin/main")))

# --- (b) remote changed the same data file: rebase aborted, clean unwind ---------
cat("\n-- (b) remote changed the same data file --\n")
fx <- new_fixture("b")
write_file(fx$other, DATA, '{"through_date": "2026-01-05", "hand_edit": true}')
g(fx$other, "commit", "-q", "-am", shQuote("Conflicting data edit")); g(fx$other, "push", "-q", "origin", "main")
other_sha <- head_of(fx$other)
pub_before <- head_of(fx$pub)
generated <- '{"through_date": "2026-01-02", "regenerated": true}'
write_file(fx$pub, DATA, generated)
r <- run_publish(fx)
check("(b) publish step fails", !r$ok)
check("(b) failure says the publish commit was NOT pushed",
      isTRUE(grepl("the publish commit was NOT pushed", r$msg, fixed = TRUE)), r$msg)
check("(b) failure says the checkout is back in step with origin/main",
      isTRUE(grepl("back in step with origin/main", r$msg, fixed = TRUE)), r$msg)
check("(b) failure says the regenerated files are still in the working tree",
      isTRUE(grepl("regenerated files are still in the working tree", r$msg, fixed = TRUE)), r$msg)
check("(b) no rebase left in progress", !in_rebase(fx$pub))
check("(b) local main equals origin/main", identical(head_of(fx$pub), head_of(fx$pub, "origin/main")))
check("(b) origin/main is the other writer's commit", identical(head_of(fx$pub, "origin/main"), other_sha))
check("(b) remote untouched by the publisher", identical(remote_tip(fx), other_sha))
check("(b) no local commit left behind (origin/main..HEAD is empty)",
        length(g(fx$pub, "rev-list", "origin/main..HEAD")) == 0L)
check("(b) the generated file is still in the working tree", identical(read_file(fx$pub, DATA), generated),
      read_file(fx$pub, DATA))
check("(b) the generated file shows as an unstaged modification",
      any(grepl(paste0("^ M ", DATA), g(fx$pub, "status", "--porcelain"))), g(fx$pub, "status", "--porcelain"))
check("(b) no merge commit anywhere", merges(fx) == 0L)

# --- static: the push step never merges, stashes or hard-resets ------------------
cat("\n-- static guards --\n")
src <- readLines(file.path("tools", "publish_web.R"), warn = FALSE)
code <- src[!grepl("^\\s*#", src)]
push_block <- code[seq(grep("^\\.pw_rev <- function", code), grep("^\\.pw_do_publish <- function", code) + 20L)]
check("push step has no `git stash`", !any(grepl('"stash"', push_block, fixed = TRUE)))
check("push step has no hard reset", !any(grepl('"--hard"', push_block, fixed = TRUE)))
check("push step has no `git merge` (other than merge-base)",
      !any(grepl('"merge"', push_block, fixed = TRUE)))

lc_finish()
