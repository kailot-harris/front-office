# ==============================================================================
# R/media_generated_at.R
#
# media_generated_at(path, repo, git_state) -> "YYYY-MM-DDTHH:MM:SSZ" (UTC)
#
# When was this media file built, as honestly as the checkout can say? If the file is
# tracked by git and unchanged against HEAD, the answer is the commit time of the last
# commit that changed it: the publish time, which may be later than the render, but a copy,
# checkout or fresh clone (which moves the mtime, not the content) can never make an old
# file look new. Otherwise (untracked, modified, re-rendered this run, git missing, not a
# repo) it is the file's own mtime.
#
# media_git_state(dir, repo) runs `git ls-files` and `git status --porcelain` ONCE for a
# directory; pass the result as `git_state` when dating many files in that directory so
# only the per-file `git log` remains. Same answers as without it.
# Shared file: identical in every sport repo.
# ==============================================================================

.mga_git <- function(repo, args) {
  out <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(repo), args), stdout = TRUE, stderr = FALSE),
    error = function(e) structure(character(0), status = 1L)))
  st <- attr(out, "status")
  list(ok = is.null(st) || st == 0L, out = out)
}

.mga_norm <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type == "windows") tolower(p) else p
}

media_git_state <- function(dir, repo = ".") {
  if (!nzchar(Sys.which("git"))) return(NULL)
  top <- .mga_git(repo, c("rev-parse", "--show-toplevel"))
  if (!top$ok || !length(top$out)) return(NULL)
  root <- top$out[1]
  dir_abs <- normalizePath(dir, winslash = "/", mustWork = FALSE)
  ls <- .mga_git(repo, c("ls-files", "--full-name", "--", shQuote(dir_abs)))
  st <- .mga_git(repo, c("status", "--porcelain", "--untracked-files=all", "--", shQuote(dir_abs)))
  if (!ls$ok || !st$ok) return(NULL)
  st_paths <- sub("^.. ", "", st$out)
  st_paths <- sub("^.* -> ", "", st_paths)          # renames: keep the new path
  st_paths <- gsub('^"|"$', "", st_paths)
  list(dir = .mga_norm(dir_abs),
       tracked = .mga_norm(file.path(root, ls$out)),
       dirty = .mga_norm(file.path(root, st_paths)))
}

media_generated_at <- function(path, repo = ".", git_state = NULL) {
  fmt <- "%Y-%m-%dT%H:%M:%SZ"
  path_abs <- if (file.exists(path)) path else file.path(repo, path)
  path_abs <- normalizePath(path_abs, winslash = "/", mustWork = FALSE)
  mtime_stamp <- function() format(file.mtime(path_abs), fmt, tz = "UTC")
  if (!nzchar(Sys.which("git"))) return(mtime_stamp())

  key <- .mga_norm(path_abs)
  if (!is.null(git_state) && identical(.mga_norm(dirname(path_abs)), git_state$dir)) {
    if (!key %in% git_state$tracked || key %in% git_state$dirty) return(mtime_stamp())
  } else {
    tracked <- .mga_git(repo, c("ls-files", "--error-unmatch", "--", shQuote(path_abs)))
    if (!tracked$ok || !length(tracked$out)) return(mtime_stamp())
    status <- .mga_git(repo, c("status", "--porcelain", "--", shQuote(path_abs)))
    if (!status$ok || length(status$out) > 0L) return(mtime_stamp())
  }

  logged <- .mga_git(repo, c("log", "-1", "--format=%cI", "--", shQuote(path_abs)))
  iso <- if (logged$ok && length(logged$out)) trimws(logged$out[1]) else ""
  if (!nzchar(iso)) return(mtime_stamp())
  # %cI gives +hh:mm or Z; strptime's %z wants +hhmm.
  iso <- sub("Z$", "+0000", iso)
  iso <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", iso)
  t <- as.POSIXct(iso, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  if (is.na(t)) return(mtime_stamp())
  format(t, fmt, tz = "UTC")
}
