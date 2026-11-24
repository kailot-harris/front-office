# ==============================================================================
# test-offseason-lifecycle-gate.R (MLB-Analytics#147)
# tools/publish_web.R off-season scoping of assertions F and H by data-file
# lifecycle, and assertion M (lifecycle present + frozen-file integrity).
# Offline: temp-dir fixtures only (tests/testthat/helper-lifecycle.R).
# ==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

lc_bootstrap()

RUN_START <- as.POSIXct("2026-11-30 09:00:00", tz = "UTC")

test_that("config.R classifies 100% of top-level web/public/data json files", {
  on_disk <- setdiff(sort(list.files(WEB_DATA_DIR, pattern = "[.]json$")), "data_manifest.json")
  expect_gt(length(on_disk), 0L)
  reg_empty <- list(schema_version = 1L, sport = "mlb", files = list())
  assigned <- mlb_data_lifecycle(on_disk, registry = reg_empty)
  missing_lc <- names(assigned)[vapply(assigned, is.null, logical(1))]
  expect_length(missing_lc, 0L)
  lcs <- vapply(assigned, function(x) x$lifecycle, character(1))
  expect_true(all(lcs %in% WEB_DATA_LIFECYCLES))
  expect_identical(unname(lcs["offseason_monitor.json"]), "live")
  expect_true(all(WEB_DATA_SEASON_FILES %in% on_disk))
})

test_that("unchanged season_final file with old stamp + lagging through_date passes offseason F, H, M", {
  d <- lc_data_dir(digest_through = "2026-10-24")
  reg <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg, d, f)

  m <- lc_manifest(d, reg)
  e <- setNames(m$datasets, vapply(m$datasets, `[[`, "", "file"))
  expect_identical(e[["landing_digest.json"]]$lifecycle, "season_final")
  expect_identical(e[["offseason_monitor.json"]]$lifecycle, "live")
  expect_identical(e[["legacy_2025_archive.json"]]$lifecycle, "archived")
  expect_false(is.null(e[["landing_digest.json"]]$frozen_sha256))
  expect_identical(as.integer(e[["landing_digest.json"]]$season), 2026L)

  # Fixture really is lagging: landing_digest through 2026-10-24, schedule through 2026-10-28.
  expect_identical(e[["landing_digest.json"]]$through_date, "2026-10-24")
  expect_identical(m$schedule_through_date, "2026-10-28")

  F_off <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m, data_dir = d)
  expect_true(F_off$pass)
  expect_true(any(grepl("[[]FRESH[]] +offseason_monitor[.]json", F_off$detail)))
  expect_true(any(grepl("[[]FROZEN[]] +landing_digest[.]json", F_off$detail)))

  H_off <- lc_quiet(.assert_manifest_and_coverage(d, mode = "offseason", manifest = m))
  expect_true(H_off$pass)
  expect_identical(H_off$id, "H")
  expect_true(any(grepl("[[]FROZEN[]] +landing_digest[.]json", H_off$detail)))
  expect_true(any(grepl("[[]ARCHIVED[]] +legacy_2025_archive[.]json", H_off$detail)))

  M_res <- .assert_lifecycle(d, manifest = m, expected = lc_assign(reg))
  expect_true(M_res$pass)
  expect_identical(M_res$id, "M")

  # Control: the same manifest in-season still fails H on the lagging file.
  H_in <- lc_quiet(.assert_manifest_and_coverage(d, manifest = m))
  expect_false(H_in$pass)
  expect_true(any(grepl("landing_digest.json lagging", H_in$problems, fixed = TRUE)))
})

test_that("assertion M catches changed frozen bytes, ignores CRLF-only diffs, and requires frozen metadata", {
  d2 <- lc_data_dir(digest_through = "2026-10-24")
  reg2 <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d2, reg2), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg2, d2, f)
  lc_write(d2, "landing_digest.json", list(
    generated_at = "2026-11-01T12:00:00Z",
    yesterday = list(list(final = TRUE, start_time_utc = "2026-10-28T18:00:00Z"))
  ))
  m2 <- lc_manifest(d2, reg2)
  M2 <- .assert_lifecycle(d2, manifest = m2, expected = lc_assign(reg2))
  expect_false(M2$pass)
  expect_true(any(grepl("landing_digest.json changed since frozen", M2$problems, fixed = TRUE)))
  expect_true(any(grepl("[CHANGED] landing_digest.json", M2$detail, fixed = TRUE)))

  # CRLF-only rewrite is not a content change (core.autocrlf checkouts).
  d2b <- lc_data_dir()
  reg2b <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d2b, reg2b), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg2b, d2b, f)
  p <- file.path(d2b, "landing_digest.json")
  txt <- readLines(p)
  con <- file(p, "wb")
  writeBin(charToRaw(paste0(paste(txt, collapse = "\r\n"), "\r\n")), con)
  close(con)
  M2b <- .assert_lifecycle(d2b, manifest = lc_manifest(d2b, reg2b), expected = lc_assign(reg2b))
  expect_true(M2b$pass)

  # season_final without its frozen fields fails.
  m2c <- lc_manifest(d2b, reg2b)
  for (i in seq_along(m2c$datasets)) {
    if (m2c$datasets[[i]]$file == "world_series.json") m2c$datasets[[i]]$frozen_sha256 <- NULL
  }
  M2c <- .assert_lifecycle(d2b, manifest = m2c, expected = NULL)
  expect_false(M2c$pass)
  expect_true(any(grepl("world_series.json season_final missing frozen_sha256", M2c$problems, fixed = TRUE)))
})

test_that("live files are still checked in full off-season (stale, unstamped, or unfrozen lagging)", {
  reg3 <- tempfile("lc_reg_", fileext = ".json")
  d3 <- lc_data_dir(live_stamp = "2026-11-17T20:04:32Z", digest_through = "2026-10-28")
  on.exit(unlink(c(d3, reg3), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg3, d3, f)
  F3 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = lc_manifest(d3, reg3), data_dir = d3)
  expect_false(F3$pass)
  expect_identical(F3$stale, "offseason_monitor.json")

  d3b <- lc_data_dir(live_stamp = NULL, digest_through = "2026-10-28")
  reg3b <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d3b, reg3b), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg3b, d3b, f)
  F3b <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = lc_manifest(d3b, reg3b), data_dir = d3b)
  expect_false(F3b$pass)
  expect_identical(F3b$unstamped, "offseason_monitor.json")

  # An unfrozen season file defaults to live and is checked in full by H and F.
  d3c <- lc_data_dir(digest_through = "2026-10-20")
  reg3c <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d3c, reg3c), recursive = TRUE), add = TRUE)
  lc_freeze_entry(reg3c, d3c, "world_series.json")
  lc_freeze_entry(reg3c, d3c, "projections_season_teams.json")
  m3c <- lc_manifest(d3c, reg3c)
  expect_identical(Filter(function(x) x$file == "landing_digest.json", m3c$datasets)[[1]]$lifecycle, "live")
  H3c <- lc_quiet(.assert_manifest_and_coverage(d3c, mode = "offseason", manifest = m3c))
  expect_false(H3c$pass)
  expect_true(any(grepl("landing_digest.json lagging 8", H3c$problems, fixed = TRUE)))
  F3c <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m3c, data_dir = d3c)
  expect_false(F3c$pass)
  expect_true("landing_digest.json" %in% F3c$stale)
})

test_that("an unclassified file fails M in both modes and stale manifest lifecycles fail M", {
  d4 <- lc_data_dir(extra = list("mystery_payload.json" = list(generated_at = "2026-11-30T09:05:00Z", x = 1L)))
  reg4 <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d4, reg4), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) lc_freeze_entry(reg4, d4, f)
  m4 <- lc_manifest(d4, reg4)
  expect_null(Filter(function(x) x$file == "mystery_payload.json", m4$datasets)[[1]]$lifecycle)

  M4 <- .assert_lifecycle(d4, manifest = m4, expected = lc_assign(reg4))
  expect_false(M4$pass)
  expect_true(any(grepl("mystery_payload.json has no lifecycle", M4$problems, fixed = TRUE)))

  pw_src <- paste(readLines(file.path("tools", "publish_web.R")), collapse = "\n")
  expect_true(grepl(".assert_lifecycle(WEB_DATA_DIR, manifest = manifest_obj)", pw_src, fixed = TRUE))

  F4 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m4, data_dir = d4)
  expect_true(any(grepl("mystery_payload.json", F4$detail, fixed = TRUE) & grepl("NO LIFECYCLE", F4$detail, fixed = TRUE)))

  m4b <- m4
  for (i in seq_along(m4b$datasets)) {
    if (m4b$datasets[[i]]$file == "mystery_payload.json") m4b$datasets[[i]]$lifecycle <- "live"
  }
  M4b <- .assert_lifecycle(d4, manifest = m4b, expected = lc_assign(reg4))
  expect_false(M4b$pass)
  expect_true(any(grepl("mystery_payload.json lifecycle live != config <none>", M4b$problems, fixed = TRUE)))
})

test_that("in-season verdicts are unchanged by lifecycle fields", {
  d <- lc_data_dir(digest_through = "2026-10-24")
  reg <- tempfile("lc_reg_", fileext = ".json")
  d3 <- lc_data_dir(digest_through = "2026-10-28")
  reg3 <- tempfile("lc_reg_", fileext = ".json")
  d3c <- lc_data_dir(digest_through = "2026-10-20")
  reg3c <- tempfile("lc_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg, d3, reg3, d3c, reg3c), recursive = TRUE), add = TRUE)
  for (f in LC_SEASON_FILES) {
    lc_freeze_entry(reg, d, f)
    lc_freeze_entry(reg3, d3, f)
  }
  lc_freeze_entry(reg3c, d3c, "world_series.json")
  lc_freeze_entry(reg3c, d3c, "projections_season_teams.json")

  strip <- function(m) {
    m$datasets <- lapply(m$datasets, function(x) {
      x[c("lifecycle", DM_LIFECYCLE_FIELDS)] <- NULL
      x
    })
    m
  }

  cases <- list(
    list(name = "lagging season_final (fails)", d = d, m = lc_manifest(d, reg)),
    list(name = "complete set (passes)", d = d3, m = lc_manifest(d3, reg3)),
    list(name = "lagging live file (fails)", d = d3c, m = lc_manifest(d3c, reg3c))
  )
  for (case in cases) {
    with_lc <- lc_quiet(.assert_manifest_and_coverage(case$d, manifest = case$m))
    without <- lc_quiet(.assert_manifest_and_coverage(case$d, manifest = strip(case$m)))
    expect_identical(with_lc$pass, without$pass, info = case$name)
    expect_identical(with_lc$problems, without$problems, info = case$name)
    expect_identical(with_lc$detail, without$detail, info = case$name)
  }

  expect_identical(formals(.assert_manifest_and_coverage)$mode, "inseason")
  expect_identical(formals(.assert_payload_provenance)$mode, "inseason")

  F_in <- .assert_payload_provenance(as.POSIXct("2000-01-01", tz = "UTC"))
  expect_identical(isTRUE(F_in$pass), length(F_in$stale) == 0L)
  expect_true(grepl("carry no stamp", F_in$summary))
})
