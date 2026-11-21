# tests/test_visual_media_index.R
# Offline tests for web_media_index.R: build_media_index() gives each file its own
# mtime as generated_at, a GIF loop duration, and drops files with no metadata.
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
source("config.R")
source("R/gif_duration.R")
source("R/media_generated_at.R")
source("web_media_index.R")

dir <- tempfile("media_"); dir.create(dir)
# Two-frame 1x1 GIF, delays 50 and 70 hundredths = 1200 ms.
gif_bytes <- c(charToRaw("GIF89a"), as.raw(c(1, 0, 1, 0, 0x00, 0, 0)),
  rep(c(as.raw(c(0x21, 0xF9, 0x04, 0x00, 50, 0, 0x00, 0x00)),
        as.raw(c(0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00))), 1),
  as.raw(c(0x21, 0xF9, 0x04, 0x00, 70, 0, 0x00, 0x00)),
  as.raw(c(0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00)),
  as.raw(0x3B))
gif <- file.path(dir, "a.gif"); writeBin(gif_bytes, gif)
png <- file.path(dir, "b.png"); writeBin(as.raw(c(0x89, 0x50, 0x4E, 0x47)), png)
mystery <- file.path(dir, "mystery.png"); writeBin(as.raw(1:4), mystery)
Sys.setFileTime(gif, as.POSIXct("2026-11-10 08:00:00", tz = "UTC"))
Sys.setFileTime(png, as.POSIXct("2026-11-15 20:30:15", tz = "UTC"))

metadata <- list(
  "a.gif" = list(title = "A", category = "elo", desc = "Chart A."),
  "b.png" = list(title = "B", category = "elo", desc = "Chart B.")
)
stamp <- function(f) format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

warned <- character(0)
idx <- withCallingHandlers(
  build_media_index(c(gif, png, mystery), metadata),
  warning = function(w) { warned <<- c(warned, conditionMessage(w)); invokeRestart("muffleWarning") })
by_name <- setNames(idx, vapply(idx, function(m) m$filename, character(1)))

ok("unknown file omitted, known files kept", identical(sort(names(by_name)), c("a.gif", "b.png")))
ok("unknown file triggers a warning naming it", any(grepl("mystery.png", warned, fixed = TRUE)))
ok("generated_at is each file's own mtime",
   identical(by_name$a.gif$generated_at, stamp(gif)) && identical(by_name$b.png$generated_at, stamp(png)))
ok("different mtimes give different stamps", by_name$a.gif$generated_at != by_name$b.png$generated_at)
ok("generated_at is UTC ISO-8601", grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", by_name$a.gif$generated_at))
ok("GIF has duration_ms 1200", identical(by_name$a.gif$duration_ms, 1200L))
ok("PNG has no duration_ms", is.null(by_name$b.png$duration_ms))
ok("types and sizes", identical(by_name$a.gif$type, "gif") && identical(by_name$b.png$type, "image") &&
   by_name$a.gif$size_bytes == file.size(gif))
ok("title/category/description come from metadata",
   identical(by_name$a.gif$title, "A") && identical(by_name$a.gif$category, "elo") &&
   identical(by_name$a.gif$description, "Chart A."))

# An unreadable GIF keeps its slot with duration_ms NULL-able (NA -> JSON null).
bad <- file.path(dir, "bad.gif"); writeBin(charToRaw("not a gif at all"), bad)
idx2 <- build_media_index(bad, list("bad.gif" = list(title = "Bad", category = "x", desc = "d.")))
ok("unreadable GIF -> item kept, duration_ms NA (serialises to null)",
   length(idx2) == 1L && is.na(idx2[[1]]$duration_ms))
ok("NA duration serialises to JSON null",
   grepl('"duration_ms":null', jsonlite::toJSON(idx2, auto_unbox = TRUE, null = "null", na = "null")))
gone <- file.path(dir, "gone.png")
warned_gone <- character(0)
idx3 <- withCallingHandlers(
  build_media_index(gone, list("gone.png" = list(title = "G", category = "x", desc = "d."))),
  warning = function(w) { warned_gone <<- c(warned_gone, conditionMessage(w)); invokeRestart("muffleWarning") })
ok("nonexistent file is omitted with a warning (no NA generated_at)",
   length(idx3) == 0L && any(grepl("gone.png", warned_gone, fixed = TRUE)))
ok("empty input -> empty list", length(build_media_index(character(0), metadata)) == 0L)

# published_dir: identical tracked copy -> its commit time; re-rendered (different bytes) -> mtime.
if (nzchar(Sys.which("git"))) {
  repo <- tempfile("vmi_repo_"); dir.create(repo); pub <- file.path(repo, "anim"); dir.create(pub)
  g <- function(...) suppressWarnings(system2("git", c("-C", shQuote(repo), "-c", "user.name=t",
                                                       "-c", "user.email=t@example.com", ...), stdout = TRUE, stderr = TRUE))
  g("init", "-q"); file.copy(gif, file.path(pub, "a.gif"))
  g("add", "--", "anim/a.gif")
  Sys.setenv(GIT_COMMITTER_DATE = "2026-11-17T20:11:09Z", GIT_AUTHOR_DATE = "2026-11-17T20:11:09Z")
  g("commit", "-q", "-m", "x"); Sys.unsetenv(c("GIT_COMMITTER_DATE", "GIT_AUTHOR_DATE"))
  src <- file.path(dir, "src"); dir.create(src); s1 <- file.path(src, "a.gif"); file.copy(gif, s1)
  Sys.setFileTime(s1, Sys.time())
  same <- build_media_index(s1, metadata, published_dir = pub, repo = repo)
  ok("unchanged published copy -> commit time", identical(same[[1]]$generated_at, "2026-11-17T20:11:09Z"))
  con <- file(s1, "ab"); writeBin(as.raw(0), con); close(con)
  Sys.setFileTime(s1, as.POSIXct("2026-11-21 10:00:00", tz = "UTC"))
  rer <- build_media_index(s1, metadata, published_dir = pub, repo = repo)
  ok("re-rendered file (differs from published) -> its mtime", identical(rer[[1]]$generated_at, "2026-11-21T10:00:00Z"))
}

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All visual_media_index tests passed\n")
