# tests/test_visual_media_index.R
# Offline tests for export_visual_media_index.R: build_media_index(dir, metadata) gives
# each file its honest generated_at (media_generated_at), a GIF loop duration, indexes only files
# present in dir, and drops files with no metadata. Usage: Rscript tests/test_visual_media_index.R
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(f)), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
source("R/gif_duration.R")
source("R/media_generated_at.R")
source("export_visual_media_index.R")

dir <- tempfile("media_"); dir.create(dir)
frame <- as.raw(c(0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00))
gce <- function(d) as.raw(c(0x21, 0xF9, 0x04, 0x00, d, 0, 0x00, 0x00))
gif_bytes <- c(charToRaw("GIF89a"), as.raw(c(1, 0, 1, 0, 0x00, 0, 0)),
               gce(50), frame, gce(70), frame, as.raw(0x3B))   # 1200 ms
gif <- file.path(dir, "a.gif"); writeBin(gif_bytes, gif)
png <- file.path(dir, "b.png"); writeBin(as.raw(c(0x89, 0x50, 0x4E, 0x47)), png)
mystery <- file.path(dir, "mystery.png"); writeBin(as.raw(1:4), mystery)
Sys.setFileTime(gif, as.POSIXct("2026-11-10 08:00:00", tz = "UTC"))
Sys.setFileTime(png, as.POSIXct("2026-11-15 20:30:15", tz = "UTC"))

mk <- function(title, desc, still) list(title = title, category = "standings", categoryLabel = "Standings & Parity",
                                         phase = 1L, previewPng = still, desc = desc)
metadata <- list(
  "a.gif"      = mk("A", "Chart A.", "b.png"),
  "b.png"      = mk("B", "Chart B.", "b.png"),
  "nostill.gif" = mk("N", "Still missing.", "nostill.png"),
  "absent.gif" = mk("Z", "Not on disk.", "b.png")
)
nostill <- file.path(dir, "nostill.gif"); writeBin(gif_bytes, nostill)
stamp <- function(f) format(file.mtime(f), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

warned <- character(0)
idx <- withCallingHandlers(
  build_media_index(dir, metadata),
  warning = function(w) { warned <<- c(warned, conditionMessage(w)); invokeRestart("muffleWarning") })
by_name <- setNames(idx, vapply(idx, function(m) m$filename, character(1)))

ok("only files present in dir are indexed (absent metadata entry -> no item)",
   identical(sort(names(by_name)), c("a.gif", "b.png")))
ok("an item whose still frame is absent is omitted with a warning",
   !("nostill.gif" %in% names(by_name)) && any(grepl("nostill.gif", warned, fixed = TRUE)))
ok("unknown file omitted with a warning naming it", any(grepl("mystery.png", warned, fixed = TRUE)))
ok("generated_at is each file's own mtime",
   identical(by_name$a.gif$generated_at, stamp(gif)) && identical(by_name$b.png$generated_at, stamp(png)))
ok("different mtimes give different stamps", by_name$a.gif$generated_at != by_name$b.png$generated_at)
ok("generated_at is UTC ISO-8601", grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", by_name$a.gif$generated_at))
ok("GIF has duration_ms 1200", identical(by_name$a.gif$duration_ms, 1200L))
ok("PNG has no duration_ms", is.null(by_name$b.png$duration_ms))
ok("types and sizes", identical(by_name$a.gif$type, "gif") && identical(by_name$b.png$type, "image") &&
   by_name$a.gif$size_bytes == file.size(gif))
ok("title/category/description come from metadata",
   identical(by_name$a.gif$title, "A") && identical(by_name$a.gif$category, "standings") &&
   identical(by_name$a.gif$description, "Chart A."))
ok("MLB extras (previewPng, phase, categoryLabel) come from metadata",
   identical(by_name$a.gif$previewPng, "b.png") && identical(by_name$a.gif$phase, 1L) &&
   identical(by_name$a.gif$categoryLabel, "Standings & Parity"))
ok("a still frame listed as previewPng is not reported as unknown", !any(grepl("b.png", warned[grepl("no metadata", warned)], fixed = TRUE)))
ok("id is the filename without extension", identical(by_name$a.gif$id, "a") && identical(by_name$b.png$id, "b"))

bad_dir <- tempfile("media_"); dir.create(bad_dir)
writeBin(charToRaw("not a gif at all"), file.path(bad_dir, "bad.gif"))
writeBin(as.raw(1:4), file.path(bad_dir, "bad.png"))
idx2 <- build_media_index(bad_dir, list("bad.gif" = mk("Bad", "d.", "bad.png")))
ok("unreadable GIF -> item kept, duration_ms NA", length(idx2) == 1L && is.na(idx2[[1]]$duration_ms))
txt <- visual_media_index_json(idx2)
ok("NA duration serialises to JSON null, never \"NA\"",
   grepl('"duration_ms": null', txt, fixed = TRUE) && !grepl('"NA"', txt, fixed = TRUE))
ok("empty/missing dir -> empty list",
   length(build_media_index(file.path(dir, "nope"), metadata)) == 0L)

# Tracked + unchanged -> last commit time (a copy/clone's fresh mtime must not make it look new);
# re-rendered (modified) -> its mtime.
if (nzchar(Sys.which("git"))) {
  repo <- tempfile("vmi_repo_"); dir.create(repo); pub <- file.path(repo, "media"); dir.create(pub)
  g <- function(...) suppressWarnings(system2("git", c("-C", shQuote(repo), "-c", "user.name=t",
                                                       "-c", "user.email=t@example.com", ...), stdout = TRUE, stderr = TRUE))
  g("init", "-q"); file.copy(gif, file.path(pub, "a.gif")); file.copy(png, file.path(pub, "b.png"))
  g("add", "--", "media/a.gif")
  Sys.setenv(GIT_COMMITTER_DATE = "2026-11-17T20:11:09Z", GIT_AUTHOR_DATE = "2026-11-17T20:11:09Z")
  g("commit", "-q", "-m", "x"); Sys.unsetenv(c("GIT_COMMITTER_DATE", "GIT_AUTHOR_DATE"))
  Sys.setFileTime(file.path(pub, "a.gif"), Sys.time())
  same <- build_media_index(pub, metadata, repo = repo)
  ok("unchanged tracked GIF -> commit time, not its fresh mtime",
     identical(same[[1]]$generated_at, "2026-11-17T20:11:09Z"))
  con <- file(file.path(pub, "a.gif"), "ab"); writeBin(as.raw(0), con); close(con)
  Sys.setFileTime(file.path(pub, "a.gif"), as.POSIXct("2026-11-21 10:00:00", tz = "UTC"))
  rer <- build_media_index(pub, metadata, repo = repo)
  ok("re-rendered tracked GIF -> its mtime", identical(rer[[1]]$generated_at, "2026-11-21T10:00:00Z"))
}

out_dir <- file.path(tempfile("out_"), "nested")
out_file <- file.path(out_dir, "idx.json")
run_export_visual_media_index(media_dir = dir, out_file = out_file, metadata = metadata)
ok("export creates a missing output dir and writes parseable JSON", file.exists(out_file) &&
   is.list(jsonlite::fromJSON(out_file, simplifyVector = FALSE)))
ok("no temp files left beside the output", identical(list.files(out_dir), "idx.json"))

if (failures > 0L) { cat(sprintf("%d failure(s)\n", failures)); quit(status = 1L) }
cat("All visual_media_index tests passed\n")
