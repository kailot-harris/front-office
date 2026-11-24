# tests/test_manifest_lifecycle_gate.R  (NFL_analytics#214)
# Offline tests for lifecycle assignment in config.R / tools/write_data_manifest.R
# and assertion L (.assert_lifecycle) in tools/publish_web.R.
# Uses temp directories only; no network, no git, no schedules cache required.
failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s\n", label))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (is.null(detail)) "" else paste0(" -- ", paste(detail, collapse = "; "))))
    failures <<- failures + 1L
  }
}

suppressPackageStartupMessages(library(jsonlite))
root <- normalizePath(getwd(), winslash = "/")
source("tools/publish_web.R")
setwd(root)

ok("config.R defines WEB_DATA_LIFECYCLES, nfl_data_lifecycle, and nfl_lifecycle_sha256",
   identical(WEB_DATA_LIFECYCLES, c("live", "season_final", "archived")) &&
     exists("nfl_data_lifecycle", mode = "function") &&
     exists("nfl_lifecycle_sha256", mode = "function") &&
     exists(".assert_lifecycle", mode = "function"))

mk_payloads <- function(stamp = "2026-11-24T05:00:00Z") {
  d <- tempfile("lc_"); dir.create(d)
  w <- function(f, x) writeLines(toJSON(x, auto_unbox = TRUE, null = "null"), file.path(d, f))
  w("matchups_current_week.json", list(generated_at = stamp, matchups = list(
    list(week = 1, gameday = "2026-11-16", is_completed = TRUE),
    list(week = 2, gameday = "2026-11-23", is_completed = TRUE)
  )))
  w("standings_projections.json", list(generated_at = stamp, teams = list()))
  w("salary_cap_profiles.json", list(generated_at = stamp))
  w("unregistered_extra.json", list(generated_at = stamp, ok = TRUE))
  d
}

now <- as.POSIXct("2026-11-24 06:00:00", tz = "UTC")
rd <- function(d) fromJSON(file.path(d, "data_manifest.json"), simplifyVector = FALSE)
wm <- function(d, m) writeLines(toJSON(m, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(d, "data_manifest.json"))

# --- 1. Manifest builder emits lifecycle = "live" on every dataset ------------
d <- mk_payloads()
write_data_manifest(d, schedule_through_date = "2026-11-23", now = now)
m <- rd(d)

ok("builder assigns lifecycle = 'live' on every dataset (including static and unregistered)",
   length(m$datasets) == 4L &&
     all(vapply(m$datasets, function(e) identical(e$lifecycle, "live"), logical(1))) &&
     isTRUE(m$datasets$salary_cap_profiles.json$static))

# Standalone write_data_manifest.R without config.R loaded still assigns live
iso_env <- new.env(parent = baseenv())
local({
  old <- Sys.getenv("NFL_SKIP_MANIFEST_AUTORUN", NA)
  Sys.setenv(NFL_SKIP_MANIFEST_AUTORUN = "1")
  on.exit(if (is.na(old)) Sys.unsetenv("NFL_SKIP_MANIFEST_AUTORUN") else Sys.setenv(NFL_SKIP_MANIFEST_AUTORUN = old))
  sys.source(file.path(root, "tools", "write_data_manifest.R"), envir = iso_env)
})
m_iso <- iso_env$build_data_manifest(d, schedule_through_date = "2026-11-23", now = now, previous = NULL)
ok("standalone write_data_manifest.R (no config.R) still emits lifecycle = 'live' on every dataset",
   all(vapply(m_iso$datasets, function(e) identical(e$lifecycle, "live"), logical(1))))

# Explicit lifecycle_fn = NULL omits lifecycle (test/negative-control support)
m_nolc <- build_data_manifest(d, schedule_through_date = "2026-11-23", now = now, previous = NULL, lifecycle_fn = NULL)
ok("build_data_manifest(lifecycle_fn = NULL) omits lifecycle",
   all(vapply(m_nolc$datasets, function(e) is.null(e$lifecycle), logical(1))))

# --- 2. Assertion L passes on valid manifest ----------------------------------
L_live <- .assert_lifecycle(d)
ok("assertion L passes on live manifest (id = 'L', fatal = TRUE)",
   isTRUE(L_live$pass) && identical(L_live$id, "L") && isTRUE(L_live$fatal) &&
     identical(unname(L_live$counts[["live"]]), 4L),
   L_live$problems)

# Existing assertion H stays compatible with lifecycle field
h <- .assert_manifest_and_coverage(d, schedule_through_date = "2026-11-23")
ok("assertion H still passes with lifecycle present on all entries", isTRUE(h$pass), h$detail)

# publish_web() wires .assert_lifecycle into its checks
pw_src <- paste(readLines(file.path(root, "tools", "publish_web.R")), collapse = "\n")
ok("publish_web() invokes .assert_lifecycle(WEB_DATA_DIR)",
   grepl(".assert_lifecycle(WEB_DATA_DIR)", pw_src, fixed = TRUE))

# Mixed valid lifecycles: live, archived, and season_final with valid frozen_sha256
d_mix <- mk_payloads()
write_data_manifest(d_mix, schedule_through_date = "2026-11-23", now = now)
m_mix <- rd(d_mix)
m_mix$datasets$salary_cap_profiles.json$lifecycle <- "archived"
mcw_path <- file.path(d_mix, "matchups_current_week.json")
m_mix$datasets$matchups_current_week.json$lifecycle <- "season_final"
m_mix$datasets$matchups_current_week.json$season <- 2026L
m_mix$datasets$matchups_current_week.json$final_through_date <- "2026-11-23"
m_mix$datasets$matchups_current_week.json$frozen_sha256 <- nfl_lifecycle_sha256(mcw_path)
m_mix$datasets$matchups_current_week.json$frozen_at <- "2026-11-24T06:00:00Z"
wm(d_mix, m_mix)
L_mix <- .assert_lifecycle(d_mix)
ok("assertion L passes for valid live + archived + season_final entries",
   isTRUE(L_mix$pass) && identical(as.integer(L_mix$counts), c(2L, 1L, 1L)),
   L_mix$problems)

# CRLF-only rewrite of a season_final file is tolerated
txt <- readLines(mcw_path, warn = FALSE)
con <- file(mcw_path, "wb")
writeBin(charToRaw(paste0(paste(txt, collapse = "\r\n"), "\r\n")), con)
close(con)
L_crlf <- .assert_lifecycle(d_mix)
ok("assertion L treats CRLF-only rewrite of season_final file as unchanged", isTRUE(L_crlf$pass), L_crlf$problems)

# --- 3. Assertion L failures --------------------------------------------------
# (a) File entry missing lifecycle field
m_null <- m; m_null$datasets$standings_projections.json$lifecycle <- NULL; wm(d, m_null)
L_null <- .assert_lifecycle(d)
ok("assertion L FAILS when an entry has no lifecycle field",
   !isTRUE(L_null$pass) && any(grepl("standings_projections.json has no lifecycle", L_null$problems, fixed = TRUE)),
   L_null$problems)

# (b) File entry has empty string lifecycle
m_empty <- m; m_empty$datasets$standings_projections.json$lifecycle <- ""; wm(d, m_empty)
L_empty <- .assert_lifecycle(d)
ok("assertion L FAILS when an entry has empty lifecycle",
   !isTRUE(L_empty$pass) && any(grepl("standings_projections.json has no lifecycle", L_empty$problems, fixed = TRUE)),
   L_empty$problems)

# (c) File on disk unlisted in manifest$datasets
wm(d, m)
writeLines('{"generated_at":"2026-11-24T05:00:00Z"}', file.path(d, "mystery_payload.json"))
L_unlisted <- .assert_lifecycle(d)
ok("assertion L FAILS when a top-level JSON file on disk is unlisted in manifest",
   !isTRUE(L_unlisted$pass) && any(grepl("mystery_payload.json has no lifecycle", L_unlisted$problems, fixed = TRUE)),
   L_unlisted$problems)
invisible(file.remove(file.path(d, "mystery_payload.json")))

# (d) Unknown lifecycle value
m_bad <- m; m_bad$datasets$standings_projections.json$lifecycle <- "bogus"; wm(d, m_bad)
L_bad <- .assert_lifecycle(d)
ok("assertion L FAILS on unknown lifecycle value",
   !isTRUE(L_bad$pass) && any(grepl("standings_projections.json unknown lifecycle bogus", L_bad$problems, fixed = TRUE)),
   L_bad$problems)

# (e) Non-string lifecycle value
m_num <- m; m_num$datasets$standings_projections.json$lifecycle <- 123L; wm(d, m_num)
L_num <- .assert_lifecycle(d)
ok("assertion L FAILS on non-string lifecycle value",
   !isTRUE(L_num$pass) && any(grepl("standings_projections.json unknown lifecycle", L_num$problems, fixed = TRUE)),
   L_num$problems)

# (f) season_final missing metadata
m_miss <- m_mix; m_miss$datasets$matchups_current_week.json$frozen_sha256 <- NULL; wm(d_mix, m_miss)
L_miss <- .assert_lifecycle(d_mix)
ok("assertion L FAILS when season_final lacks frozen_sha256",
   !isTRUE(L_miss$pass) && any(grepl("matchups_current_week.json season_final missing frozen_sha256", L_miss$problems, fixed = TRUE)),
   L_miss$problems)

# (g) season_final bytes changed after freeze
wm(d_mix, m_mix)
writeLines('{"generated_at":"2026-11-24T05:00:00Z","mutated":true}', mcw_path)
L_changed <- .assert_lifecycle(d_mix)
ok("assertion L FAILS when season_final file bytes change after freeze",
   !isTRUE(L_changed$pass) && any(grepl("matchups_current_week.json changed since frozen", L_changed$problems, fixed = TRUE)) &&
     any(grepl("[CHANGED] matchups_current_week.json", L_changed$detail, fixed = TRUE)),
   L_changed$problems)

# (h) expected callback mismatch
wm(d, m)
L_exp <- .assert_lifecycle(d, expected = function(files) {
  out <- nfl_data_lifecycle(files)
  out[["standings_projections.json"]] <- list(lifecycle = "archived")
  out
})
ok("assertion L FAILS when expected lifecycle disagrees with manifest",
   !isTRUE(L_exp$pass) && any(grepl("standings_projections.json lifecycle live != expected archived", L_exp$problems, fixed = TRUE)),
   L_exp$problems)

# (i) Absent or malformed manifest
invisible(file.remove(file.path(d, "data_manifest.json")))
L_absent <- .assert_lifecycle(d)
ok("assertion L FAILS when data_manifest.json is absent", !isTRUE(L_absent$pass))

unlink(c(d, d_mix), recursive = TRUE)
cat(sprintf("\n%d failure(s)\n", failures))
quit(status = if (failures > 0L) 1L else 0L)
