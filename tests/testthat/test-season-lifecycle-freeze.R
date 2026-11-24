# ==============================================================================
# test-season-lifecycle-freeze.R (MLB-Analytics#147)
# tools/freeze_season.R: season-end detection, refusal of incomplete files,
# frozen_sha256 recording, --thaw lifecycle moves, and a freeze -> manifest ->
# off-season gate round trip. Offline: temp-dir fixtures only.
# ==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

lc_bootstrap()

TODAY <- as.Date("2026-11-23")
NOW   <- as.POSIXct("2026-11-24 03:00:00", tz = "UTC")

test_that("fs_season_last_game finds latest completed slate game and refuses unfinished/absent seasons", {
  expect_identical(fs_season_last_game(lc_schedule(), 2026L, today = TODAY), as.Date("2026-10-28"))

  # Spring training / exhibition games after last_done are ignored when game_type is present.
  sched_ex <- rbind(
    lc_schedule(),
    data.frame(season = 2026L, game_type = "E", official_date = "2026-11-05",
               status_detailed_state = "Final", if_necessary = "N", stringsAsFactors = FALSE)
  )
  expect_identical(fs_season_last_game(sched_ex, 2026L, today = TODAY), as.Date("2026-10-28"))

  # Uncompleted game on or after today means the season is not over.
  expect_error(fs_season_last_game(lc_schedule(), 2026L, today = as.Date("2026-10-30")), "not over")
  expect_error(fs_season_last_game(lc_schedule(), 2025L, today = TODAY), "no games")
})

test_that("freeze_season refuses incomplete or absent files all-or-nothing without writing", {
  d <- lc_data_dir(digest_through = "2026-10-24")
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)

  r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                     season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_false(r$ok)
  expect_true("landing_digest.json" %in% r$refused$file)
  expect_true(grepl("2026-10-24 is before the season's last game 2026-10-28",
                    r$refused$reason[r$refused$file == "landing_digest.json"], fixed = TRUE))
  expect_identical(r$refused$file, "landing_digest.json")
  expect_false(file.exists(reg))
  expect_length(r$frozen, 0L)

  d_u <- lc_data_dir(digest_through = "2026-10-28", undated_stamp = "2026-10-27T10:00:00Z")
  on.exit(unlink(d_u, recursive = TRUE), add = TRUE)
  r_u <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                       season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_false(r_u$ok)
  expect_identical(r_u$refused$file, "projections_season_teams.json")

  r_abs <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                         season_files = c(LC_SEASON_FILES, "missing_season_file.json"),
                         today = TODAY, now = NOW)
  expect_false(r_abs$ok)
  expect_true("missing_season_file.json" %in% r_abs$refused$file)
  expect_false(file.exists(reg))

  expect_error(
    freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                  season_files = LC_SEASON_FILES, today = as.Date("2026-10-30"), now = NOW),
    "not over"
  )
  expect_false(file.exists(reg))
})

test_that("freeze_season records frozen_sha256 for complete set and dry-run writes nothing", {
  d2 <- lc_data_dir(digest_through = "2026-10-28", ws_through = "2026-10-28", undated_stamp = "2026-11-06T19:49:32Z")
  reg_dry <- tempfile("fs_reg_dry_", fileext = ".json")
  reg2 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d2, reg_dry, reg2), recursive = TRUE), add = TRUE)

  r_dry <- freeze_season(2026L, data_dir = d2, registry_path = reg_dry, schedule = lc_schedule(),
                         season_files = LC_SEASON_FILES, today = TODAY, now = NOW, write = FALSE)
  expect_true(r_dry$ok)
  expect_false(file.exists(reg_dry))
  expect_setequal(names(r_dry$frozen), LC_SEASON_FILES)

  r2 <- freeze_season(2026L, data_dir = d2, registry_path = reg2, schedule = lc_schedule(),
                      season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_true(r2$ok)
  rg <- mlb_read_lifecycle_registry(reg2)
  expect_identical(sort(names(rg$files)), sort(LC_SEASON_FILES))

  b <- rg$files[["landing_digest.json"]]
  expect_identical(b$lifecycle, "season_final")
  expect_identical(as.integer(b$season), 2026L)
  expect_identical(b$final_through_date, "2026-10-28")
  expect_identical(b$frozen_at, "2026-11-24T03:00:00Z")
  expect_identical(b$frozen_sha256, mlb_lifecycle_sha256(file.path(d2, "landing_digest.json")))
  expect_match(b$frozen_sha256, "^[0-9a-f]{64}$")

  expect_null(rg$files[["offseason_monitor.json"]])
  expect_null(rg$files[["legacy_2025_archive.json"]])
  expect_identical(lc_assign(reg2)("landing_digest.json")[[1]]$lifecycle, "season_final")
  expect_identical(lc_assign(reg2)("offseason_monitor.json")[[1]]$lifecycle, "live")

  # Round trip: freeze -> manifest -> off-season gate (F, H, M).
  m2 <- lc_manifest(d2, reg2)
  RUN_START <- as.POSIXct("2026-11-30 09:00:00", tz = "UTC")
  F2 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m2, data_dir = d2)
  H2 <- lc_quiet(.assert_manifest_and_coverage(d2, mode = "offseason", manifest = m2))
  M2 <- .assert_lifecycle(d2, manifest = m2, expected = lc_assign(reg2))
  expect_true(F2$pass)
  expect_true(H2$pass)
  expect_true(M2$pass)
})

test_that("thaw_season moves reused names to live and unique prior-season files to archived", {
  d2 <- lc_data_dir(digest_through = "2026-10-28", ws_through = "2026-10-28")
  reg2 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d2, reg2), recursive = TRUE), add = TRUE)
  # Freeze a set including a 2026-only filename alongside reused filenames.
  lc_write(d2, "postseason_bracket_2026.json", list(generated_at = "2026-11-01T12:00:00Z"))
  season_2026 <- c("postseason_bracket_2026.json", "landing_digest.json", "projections_season_teams.json")
  r2 <- freeze_season(2026L, data_dir = d2, registry_path = reg2, schedule = lc_schedule(),
                      season_files = season_2026, today = TODAY, now = NOW)
  expect_true(r2$ok)
  b_hash <- mlb_read_lifecycle_registry(reg2)$files[["postseason_bracket_2026.json"]]$frozen_sha256

  new_files <- c("postseason_bracket_2027.json", "landing_digest.json", "projections_season_teams.json")
  t <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
  expect_identical(sort(t$to_live), c("landing_digest.json", "projections_season_teams.json"))
  expect_identical(t$to_archived, "postseason_bracket_2026.json")

  rg2 <- mlb_read_lifecycle_registry(reg2)
  lc_after <- mlb_data_lifecycle(
    c("postseason_bracket_2026.json", "landing_digest.json", "postseason_bracket_2027.json"),
    registry = rg2,
    offseason_live = LC_LIVE,
    season_files = new_files,
    archived_files = LC_ARCHIVED
  )
  expect_identical(vapply(lc_after, `[[`, "", "lifecycle"),
                   c(postseason_bracket_2026.json = "archived",
                     landing_digest.json = "live",
                     postseason_bracket_2027.json = "live"))
  expect_identical(as.integer(rg2$files[["postseason_bracket_2026.json"]]$season), 2026L)
  expect_identical(rg2$files[["postseason_bracket_2026.json"]]$frozen_sha256, b_hash)

  t2 <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
  expect_length(t2$to_live, 0L)
  expect_length(t2$to_archived, 0L)

  reg3 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(reg3), add = TRUE)
  invisible(freeze_season(2026L, data_dir = d2, registry_path = reg3, schedule = lc_schedule(),
                          season_files = season_2026, today = TODAY, now = NOW))
  t3 <- thaw_season(2026L, registry_path = reg3, season_files = season_2026)
  expect_length(t3$to_live, 0L)
  expect_length(t3$to_archived, 0L)
})

test_that("freeze_season CLI exits non-zero when --season is omitted", {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  out <- suppressWarnings(system2(rscript, c("--vanilla", shQuote(file.path("tools", "freeze_season.R"))),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  expect_true(!is.null(st) && st != 0L)
})
