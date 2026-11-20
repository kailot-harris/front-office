# ------------------------------------------------------------------------------
# Sidecar data manifest (front-office#102) + schedule-coverage lag gate,
# publish_web.R assertion H (front-office#191). Fully offline: every case runs
# against a temp data directory and an explicit schedule_through_date.
# ------------------------------------------------------------------------------
if (!file.exists("config.R")) {
  if (file.exists("../../config.R")) setwd(normalizePath("../..", winslash = "/"))
  else stop("Cannot locate the project root (no config.R).", call. = FALSE)
}
suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

source("tools/publish_web.R")
dm <- new.env()
sys.source("tools/write_data_manifest.R", envir = dm)

# g.json is game-dated (games[].game_date); u.json/v.json are not; n.json has
# no embedded stamp at all.
TEST_EXTRACTORS <- list(
  "g.json" = list(field = "games[].game_date", fn = function(j) {
    d <- vapply(j$games, function(x) x$game_date, character(1))
    if (length(d)) max(d) else NA_character_
  })
)

game_payload <- function(stamp, last_game) {
  sprintf('{"generated_at": "%s", "games": [{"game_date": "2026-09-01"}, {"game_date": "%s"}]}',
          stamp, last_game)
}

make_data_dir <- function(files = list(
  "g.json" = game_payload("2026-09-20T10:00:00Z", "2026-09-19"),
  "u.json" = '{"metadata": {"generated_at": "2026-09-21T10:00:00Z"}}',
  "v.json" = '{"lastPublished": "2026-09-22T10:00:00Z"}'
)) {
  d <- tempfile("dm-data-")
  dir.create(d)
  for (f in names(files)) writeLines(files[[f]], file.path(d, f))
  d
}

build <- function(d, ...) dm$build_data_manifest(data_dir = d, extractors = TEST_EXTRACTORS, ...)
write_m <- function(d, ...) {
  m <- build(d, previous = dm$.dm_read_previous(file.path(d, "data_manifest.json")), ...)
  write_manifest(d, m)
  m
}
write_manifest <- function(d, m) {
  writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", pretty = TRUE),
             file.path(d, "data_manifest.json"))
}
entry <- function(m, f) Filter(function(e) identical(e$file, f), m$datasets)[[1]]

test_that("builder covers every top-level json; stamps and coverage come from content", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  m <- build(d, schedule_through_date = NA_character_)
  expect_equal(m$schema_version, 1L)
  expect_equal(m$sport, "mlb")
  expect_null(m$schedule_through_date)
  expect_equal(vapply(m$datasets, `[[`, character(1), "file"), c("g.json", "u.json", "v.json"))
  expect_equal(vapply(m$datasets, `[[`, character(1), "stamp_source"),
               c("payload:generated_at", "payload:metadata.generated_at", "payload:lastPublished"))
  g <- entry(m, "g.json")
  expect_equal(g$through_date, "2026-09-19")
  expect_equal(g$through_date_source, "payload:games[].game_date")
  u <- entry(m, "u.json")
  expect_null(u$through_date)
  expect_equal(u$through_date_source, "not_game_dated")
  expect_true(nzchar(u$coverage_note))
  expect_match(g$content_sha256, "^[0-9a-f]{64}$")
})

test_that("through_date is never derived from generated_at", {
  d <- make_data_dir(list("g.json" = '{"generated_at": "2026-09-20T10:00:00Z", "games": []}'))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  g <- entry(build(d, schedule_through_date = NA_character_), "g.json")
  expect_null(g$through_date)
  expect_equal(g$through_date_source, "not_game_dated")
})

test_that("schedule date helper is NA offline and reads a fixture schedule", {
  expect_identical(dm$dm_latest_completed_schedule_date(schedule_path = tempfile()), NA_character_)
  p <- tempfile(fileext = ".rds")
  on.exit(unlink(p), add = TRUE)
  saveRDS(data.frame(game_type = c("R", "R", "S"),
                     official_date = c("2026-09-25", "2026-09-27", "2026-09-30"),
                     status = c("Final", "Scheduled", "Final")), p)
  expect_identical(dm$dm_latest_completed_schedule_date(schedule_path = p), "2026-09-25")
})

test_that("content-hash carry-forward: same bytes keep the stamp, new bytes get a new one", {
  d <- make_data_dir(list("n.json" = '[{"team": "NYY"}]'))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  t1 <- as.POSIXct("2026-09-01 12:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-09-05 12:00:00", tz = "UTC")
  m1 <- write_m(d, schedule_through_date = NA_character_, now = t1)
  e1 <- entry(m1, "n.json")
  expect_equal(e1$stamp_source, "manifest:content_hash")
  expect_equal(e1$generated_at, "2026-09-01T12:00:00Z")

  m2 <- write_m(d, schedule_through_date = NA_character_, now = t2)
  expect_equal(entry(m2, "n.json")$generated_at, "2026-09-01T12:00:00Z")
  # nothing moved -> manifest top-level stamp does not move either
  expect_equal(m2$generated_at, m1$generated_at)

  writeLines('[{"team": "BOS"}]', file.path(d, "n.json"))
  m3 <- write_m(d, schedule_through_date = NA_character_, now = t2)
  e3 <- entry(m3, "n.json")
  expect_equal(e3$generated_at, "2026-09-05T12:00:00Z")
  expect_false(identical(e3$content_sha256, e1$content_sha256))
  expect_equal(m3$generated_at, "2026-09-05T12:00:00Z")
})

test_that("manifest writer never reads file mtimes or git history", {
  src <- readLines("tools/write_data_manifest.R")
  code <- sub("#.*$", "", src)
  expect_false(any(grepl("file[.]info|file[.]mtime|file_mtime|git log|system2?\\(", code)))
})

test_that("committed builder output passes assertion H with schedule unknown", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  write_m(d, schedule_through_date = NA_character_)
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_true(r$pass)
  expect_equal(r$id, "H")
})

test_that("stale lag beyond max_lag_days fails assertion H", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  write_m(d, schedule_through_date = "2026-09-28")
  r <- .assert_manifest_and_coverage(data_dir = d, max_lag_days = 3L)
  expect_false(r$pass)
  expect_true(any(grepl("[LAGGING]", r$detail, fixed = TRUE)))
  expect_equal(r$coverage[["g.json"]]$lag_days, 9L)
  expect_equal(r$coverage[["g.json"]]$status, "LAGGING")
  r2 <- .assert_manifest_and_coverage(data_dir = d, max_lag_days = 10L)
  expect_true(r2$pass)
})

test_that("FO#191: brand-new stamp over out-of-date game content FAILS the gate", {
  # Rebuilt today from a stale cache: stamp is fresh, latest game is old.
  d <- make_data_dir(list("g.json" = game_payload("2026-09-28T09:00:00Z", "2026-09-10")))
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  m <- write_m(d, schedule_through_date = "2026-09-27")
  expect_equal(entry(m, "g.json")$through_date, "2026-09-10")
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_false(r$pass)
  expect_equal(r$coverage[["g.json"]]$status, "LAGGING")
  expect_equal(r$coverage[["g.json"]]$lag_days, 17L)
})

test_that("undated datasets are [UNDATED] and judged only on generated_at freshness", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  write_m(d, schedule_through_date = "2026-09-22")
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_true(r$pass)
  expect_equal(r$coverage[["u.json"]]$status, "UNDATED")
  expect_true(any(grepl("[UNDATED]", r$detail, fixed = TRUE)))
  r2 <- .assert_manifest_and_coverage(data_dir = d, schedule_through_date = "2026-10-15")
  expect_false(r2$pass)
  expect_equal(r2$coverage[["u.json"]]$status, "LAGGING")
})

test_that("off-season (schedule ended before the content) passes", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  write_m(d, schedule_through_date = "2026-09-19")
  r <- .assert_manifest_and_coverage(data_dir = d, mode = "offseason")
  expect_true(r$pass)
  expect_equal(r$coverage[["g.json"]]$status, "OK")
})

test_that("static: true passes with a reason and fails without one", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  m <- build(d, schedule_through_date = "2026-12-31")
  m$datasets <- lapply(m$datasets, function(e) {
    e$static <- TRUE; e$static_reason <- "frozen reference table"; e
  })
  write_manifest(d, m)
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_true(r$pass)
  expect_true(all(grepl("[STATIC]", r$detail, fixed = TRUE)))

  m$datasets[[1]]["static_reason"] <- list(NULL)
  write_manifest(d, m)
  r2 <- .assert_manifest_and_coverage(data_dir = d)
  expect_false(r2$pass)
  expect_equal(r2$coverage[["g.json"]]$status, "MISSING")
})

test_that("mtime / sibling stamp sources are rejected", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  m <- build(d, schedule_through_date = NA_character_)
  m$datasets[[2]]$stamp_source <- "file_mtime"
  m$datasets[[3]]$stamp_source <- "sibling:g.json"
  write_manifest(d, m)
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_false(r$pass)
  expect_equal(r$coverage[["u.json"]]$status, "MISSING")
  expect_equal(r$coverage[["v.json"]]$status, "MISSING")
})

test_that("unlisted, unstamped, or absent-manifest datasets fail", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  expect_false(.assert_manifest_and_coverage(data_dir = d)$pass)  # no manifest

  write_m(d, schedule_through_date = NA_character_)
  writeLines('{"generated_at": "2026-09-22T10:00:00Z"}', file.path(d, "new.json"))
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_false(r$pass)
  expect_equal(r$coverage[["new.json"]]$status, "MISSING")

  unlink(file.path(d, "new.json"))
  m <- jsonlite::fromJSON(file.path(d, "data_manifest.json"), simplifyVector = FALSE)
  m$datasets[[2]]$generated_at <- "2026-09-21 10:00:00"
  write_manifest(d, m)
  r2 <- .assert_manifest_and_coverage(data_dir = d)
  expect_false(r2$pass)
  expect_equal(r2$coverage[["u.json"]]$status, "MISSING")
})

test_that("dry run lists every dataset with its coverage and writes nothing", {
  d <- make_data_dir()
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  write_m(d, schedule_through_date = "2026-09-21")
  before <- tools::md5sum(list.files(d, full.names = TRUE))
  r <- .assert_manifest_and_coverage(data_dir = d)
  expect_true(r$pass)
  expect_equal(length(r$detail), 3L)
  for (f in c("g.json", "u.json", "v.json")) expect_true(any(grepl(f, r$detail, fixed = TRUE)))
  expect_equal(r$coverage[["g.json"]]$through_date, "2026-09-19")
  expect_identical(tools::md5sum(list.files(d, full.names = TRUE)), before)
})

test_that("the committed web/public/data manifest covers every top-level json", {
  r <- .assert_manifest_and_coverage(schedule_through_date = NA_character_)
  expect_true(r$pass, info = paste(r$detail, collapse = "\n"))
  on_disk <- setdiff(list.files(WEB_DATA_DIR, pattern = "[.]json$"), "data_manifest.json")
  expect_setequal(names(r$coverage), on_disk)
  m <- jsonlite::fromJSON(file.path(WEB_DATA_DIR, "data_manifest.json"), simplifyVector = FALSE)
  srcs <- vapply(m$datasets, function(e) e$stamp_source, character(1))
  expect_true(all(grepl("^(payload:.+|manifest:content_hash)$", srcs)))
})
