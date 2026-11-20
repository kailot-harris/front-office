# ==============================================================================
# test_data_manifest_and_lag_gate.R
# Offline tests for tools/write_data_manifest.R and tools/publish_web.R
# Assertion I (Refs kailot-harris/front-office#102, #191). Uses temp dirs only;
# never reads cache/.
# ==============================================================================

args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) cur <- dirname(cur)
if (file.exists(file.path(cur, "config.R"))) setwd(cur)
dir.create("logs", showWarnings = FALSE)

user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")), "R", "win-library", "4.5")
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) .libPaths(c(.libPaths(), default_user_lib))
}

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

Sys.setenv(WNBA_SKIP_MANIFEST_AUTORUN = "1")
source(file.path("tools", "write_data_manifest.R"))
source(file.path("tools", "publish_web.R"))

make_data_dir <- function(files = c("a.json", "b.json", "cba_cap_sheet.json"), stamp = "2026-10-30T12:00:00Z") {
  d <- tempfile("dm_"); dir.create(d)
  for (f in files) writeLines(sprintf('{"generated_at": "%s", "x": 1}', stamp), file.path(d, f))
  d
}
write_manifest <- function(d, datasets, sched = NULL) {
  m <- list(schema_version = 1L, sport = "wnba", generated_at = "2026-11-01T00:00:00Z",
            schedule_through_date = sched, datasets = datasets)
  writeLines(toJSON(m, auto_unbox = TRUE, null = "null"), file.path(d, "data_manifest.json"))
}
entry <- function(file, through = "2026-10-30", static = FALSE, reason = NULL, gen = "2026-10-30T12:00:00Z") {
  e <- list(file = file, generated_at = gen, stamp_source = "payload:generated_at", content_sha256 = NULL,
            through_date = through, through_date_source = "payload:games[].gameDate", coverage_note = NULL,
            builder = "x", static = static)
  if (!is.null(reason)) e$static_reason <- reason
  e
}
quiet <- function(expr) { out <- capture.output(r <- expr); attr(r, "out") <- out; r }

test_that("build_data_manifest covers every top-level JSON with UTC stamps", {
  d <- make_data_dir()
  m <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"))
  expect_equal(sort(vapply(m$datasets, `[[`, "", "file")), c("a.json", "b.json", "cba_cap_sheet.json"))
  expect_true(all(vapply(m$datasets, function(e) .pw_is_utc_iso(e$generated_at), logical(1))))
  expect_null(m$schedule_through_date)
  cba <- Filter(function(e) e$file == "cba_cap_sheet.json", m$datasets)[[1]]
  expect_true(cba$static); expect_true(nzchar(cba$static_reason))
  write_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"))
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_true(r$pass)
})

test_that("dm_latest_completed_schedule_date reads completed games only", {
  d <- tempfile("sched_"); dir.create(d)
  p <- file.path(d, "s.rds")
  saveRDS(data.frame(game_date = c("2026-10-20", "2026-10-25", "2026-11-02"),
                     is_completed = c(TRUE, TRUE, FALSE)), p)
  expect_equal(dm_latest_completed_schedule_date(p), as.Date("2026-10-25"))
  expect_true(is.na(dm_latest_completed_schedule_date(file.path(d, "missing.rds"))))
})

test_that("stale lag fails Assertion I", {
  d <- make_data_dir(c("a.json"))
  write_manifest(d, list(entry("a.json", through = "2026-09-01")), sched = "2026-10-30")
  r <- quiet(.assert_manifest_and_coverage(d, max_lag_days = 3L, dry_run = TRUE))
  expect_false(r$pass)
  expect_true(any(grepl("\\[LAGGING\\] a.json", r$coverage)))
})

test_that("off-season (schedule_through_date <= through_date) passes", {
  d <- make_data_dir(c("a.json"))
  write_manifest(d, list(entry("a.json", through = "2026-11-06")), sched = "2026-10-30")
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_true(r$pass)
})

test_that("absent schedule date skips lag comparison but keeps completeness", {
  d <- make_data_dir(c("a.json"))
  write_manifest(d, list(entry("a.json", through = "2020-01-01")), sched = NULL)
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_true(r$pass)
  expect_true(any(grepl("lag comparison skipped", r$detail)))
})

test_that("static: true passes with a reason and fails without one", {
  d <- make_data_dir(c("a.json"))
  write_manifest(d, list(entry("a.json", through = "2020-01-01", static = TRUE, reason = "Archived")), sched = "2026-10-30")
  expect_true(quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))$pass)
  write_manifest(d, list(entry("a.json", through = "2020-01-01", static = TRUE)), sched = "2026-10-30")
  expect_false(quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))$pass)
})

test_that("unlisted or unstamped dataset fails; missing manifest fails", {
  d <- make_data_dir(c("a.json", "b.json"))
  write_manifest(d, list(entry("a.json")), sched = NULL)
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_false(r$pass); expect_true(any(grepl("\\[MISSING\\] b.json", r$coverage)))
  write_manifest(d, list(entry("a.json"), entry("b.json", gen = "2026-10-30 12:00")), sched = NULL)
  expect_false(quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))$pass)
  unlink(file.path(d, "data_manifest.json"))
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_false(r$pass); expect_match(r$summary, "absent")
})

test_that("dry run prints every dataset with its coverage date and does not mutate", {
  d <- make_data_dir(c("a.json", "b.json", "c.json"))
  write_manifest(d, list(entry("a.json"), entry("b.json", through = "2026-10-29"),
                         entry("c.json", static = TRUE, reason = "Archived")), sched = "2026-10-30")
  before <- tools::md5sum(file.path(d, "data_manifest.json"))
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  out <- attr(r, "out")
  expect_true(any(grepl("\\[OK\\] a.json - through 2026-10-30", out)))
  expect_true(any(grepl("\\[OK\\] b.json - through 2026-10-29", out)))
  expect_true(any(grepl("\\[STATIC\\] c.json", out)))
  expect_equal(unname(tools::md5sum(file.path(d, "data_manifest.json"))), unname(before))
})

undated <- function(file, gen = "2026-10-30T12:00:00Z") {
  list(file = file, generated_at = gen, stamp_source = "manifest:content_hash", content_sha256 = "x",
       through_date = NULL, through_date_source = "not_game_dated", coverage_note = "Profiles",
       builder = "x", static = FALSE)
}

test_that("through_date comes from payload game dates, never from the stamp (FO#191)", {
  d <- tempfile("cov_"); dir.create(d)
  writeLines('{"generated_at": "2026-11-19T10:00:00Z", "games": [{"gameDate": "2026-08-01"}, {"gameDate": "2026-08-15"}]}',
             file.path(d, "finals_series_backtest_2026.json"))
  writeLines('[{"player": "x"}]', file.path(d, "player_dna_profiles.json"))
  m <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), previous = NULL)
  e <- setNames(m$datasets, vapply(m$datasets, `[[`, "", "file"))
  expect_equal(e[["finals_series_backtest_2026.json"]]$through_date, "2026-08-15")
  expect_equal(e[["finals_series_backtest_2026.json"]]$through_date_source, "payload:games[].gameDate")
  expect_null(e[["player_dna_profiles.json"]]$through_date)
  expect_equal(e[["player_dna_profiles.json"]]$through_date_source, "not_game_dated")
  expect_true(nzchar(e[["player_dna_profiles.json"]]$coverage_note))
})

test_that("stale content with a brand-new stamp FAILS the gate (FO#191 acceptance)", {
  d <- tempfile("stale_"); dir.create(d)
  writeLines('{"generated_at": "2026-11-19T10:00:00Z", "games": [{"gameDate": "2026-08-15"}]}',
             file.path(d, "finals_series_backtest_2026.json"))
  sched <- file.path(d, "sched.rds")
  saveRDS(data.frame(game_date = "2026-10-31", is_completed = TRUE), sched)
  write_data_manifest(data_dir = d, schedule_path = sched, previous = NULL)
  r <- quiet(.assert_manifest_and_coverage(d, max_lag_days = 3L, dry_run = TRUE))
  expect_false(r$pass)
  expect_true(any(grepl("[LAGGING] finals_series_backtest_2026.json", r$coverage, fixed = TRUE)))
})

test_that("undated datasets are checked on generated_at freshness and labeled [UNDATED]", {
  d <- make_data_dir(c("a.json"))
  write_manifest(d, list(undated("a.json", gen = "2026-10-30T12:00:00Z")), sched = "2026-10-31")
  r <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))
  expect_true(r$pass); expect_true(any(grepl("[UNDATED] a.json", attr(r, "out"), fixed = TRUE)))
  write_manifest(d, list(undated("a.json", gen = "2026-09-01T12:00:00Z")), sched = "2026-10-31")
  expect_false(quiet(.assert_manifest_and_coverage(d, dry_run = TRUE))$pass)
})

test_that("content-hash carry-forward: same bytes keep stamp, changed bytes get a new one (FO#102)", {
  d <- tempfile("hash_"); dir.create(d)
  writeLines('[{"player": "x"}]', file.path(d, "player_dna_profiles.json"))
  t1 <- as.POSIXct("2026-11-01 00:00:00", tz = "UTC"); t2 <- as.POSIXct("2026-11-05 00:00:00", tz = "UTC")
  m1 <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), now = t1, previous = NULL)
  m2 <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), now = t2, previous = m1)
  expect_equal(m2$datasets[[1]]$generated_at, "2026-11-01T00:00:00Z")
  expect_equal(m2$datasets[[1]]$stamp_source, "manifest:content_hash")
  expect_equal(m2$generated_at, m1$generated_at)  # nothing moved -> top-level unchanged
  writeLines('[{"player": "y"}]', file.path(d, "player_dna_profiles.json"))
  m3 <- build_data_manifest(data_dir = d, schedule_path = file.path(d, "none.rds"), now = t2, previous = m2)
  expect_equal(m3$datasets[[1]]$generated_at, "2026-11-05T00:00:00Z")
  expect_equal(m3$generated_at, "2026-11-05T00:00:00Z")
})

test_that("manifest writer never reads file mtimes or git history", {
  code <- readLines(file.path("tools", "write_data_manifest.R"))
  code <- code[!grepl("^[[:space:]]*#", code)]
  expect_false(any(grepl("file[.]info|file[.]mtime|system2|git log", code)))
})

test_that("committed web/public/data/data_manifest.json covers the live payload set", {
  r <- quiet(.assert_manifest_and_coverage(file.path("web", "public", "data"), dry_run = TRUE))
  expect_true(r$pass, info = paste(r$problems, collapse = "; "))
})
